// Steam Rich Presence helper for counter-strike-extended.
//
// Wraps xash3d.exe: loads steam_api.dll dynamically (no proprietary headers
// or .lib needed), calls SteamAPI_Init + ISteamFriends::SetRichPresence,
// then launches xash3d.exe as a child and pumps Steam callbacks until it
// exits. All argv are forwarded to xash3d.exe verbatim.
//
// Presence reflects game state by tailing runtime/engine.log:
//   - default:                  "#CS_RP_MainMenu" (or "#HL_RP_MainMenu" if appid=70)
//   - "Spawn Server: <map>"     -> "#CS_RP_PlayingKnown" / "#HL_RP_SingleplayerKnown"
//                                  with the "map_name" token set.
//
// Build:  cmake -B build -A Win32  &&  cmake --build build --config Release
// Run:    runtime\cse_steamrp.exe -game cstrike

#define NOMINMAX
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <string>

namespace fs = std::filesystem;

// Flat-API typedefs, matched against the exports of steam_api.dll
// (Steamworks SDK ~1.5x, file version 06.91.21.57 as shipped with HL/CS).
typedef bool   (__cdecl *Fn_SteamAPI_Init)();
typedef void   (__cdecl *Fn_SteamAPI_Shutdown)();
typedef void   (__cdecl *Fn_SteamAPI_RunCallbacks)();
typedef void * (__cdecl *Fn_SteamAPI_SteamFriends_v017)();
typedef bool   (__cdecl *Fn_ISteamFriends_SetRichPresence)(void *self, const char *key, const char *value);
typedef void   (__cdecl *Fn_ISteamFriends_ClearRichPresence)(void *self);

static void log_err(const char *msg) { fprintf(stderr, "[steamrp] %s\n", msg); }

// Token set per Steam AppID. Resolved by the Steam client through
// <appid>_loc_<lang>.vdf (see src/cse/localization).
struct RpTokens {
    const char *appid;
    const char *main_menu;
    const char *playing;
};

// Find the most recently written *.log under runtime dir. xash3d's log file
// name is configurable via -log <file>, so we cannot assume "engine.log".
static std::string find_latest_log(const std::string &dir) {
    std::string latest;
    auto newest = fs::file_time_type::min();
    std::error_code ec;
    for (const auto &e : fs::directory_iterator(dir, ec)) {
        if (ec) break;
        if (!e.is_regular_file()) continue;
        if (e.path().extension() != ".log") continue;
        auto t = fs::last_write_time(e, ec);
        if (ec) continue;
        if (t > newest) {
            newest = t;
            latest = e.path().string();
        }
    }
    return latest;
}

// Tail engine.log from last offset; when "Spawn Server: <map>" is seen,
// update Rich Presence. Returns the current map (or empty).
static void update_from_log(const std::string &path, long long &offset, std::string &current_map,
                            void *friends, Fn_ISteamFriends_SetRichPresence set_rp,
                            const RpTokens &tok) {
    FILE *f = fopen(path.c_str(), "r");
    if (!f) return;
    // Detect log truncation/rotation.
    fseek(f, 0, SEEK_END);
    long long size = _ftelli64(f);
    if (size < offset) {
        offset = 0;
        current_map.clear();
    }
    fseek(f, (long)offset, SEEK_SET);
    static const char prefix[] = "Spawn Server: ";
    char line[1024];
    while (fgets(line, sizeof(line), f)) {
        if (char *p = strstr(line, prefix)) {
            p += sizeof(prefix) - 1;
            std::string map;
            while (*p && *p != '\r' && *p != '\n') map += *p++;
            if (!map.empty() && map != current_map) {
                current_map = map;
                if (friends && set_rp) {
                    set_rp(friends, "map_name", map.c_str());
                    set_rp(friends, "steam_display", tok.playing);
                    fprintf(stderr, "[steamrp] map loaded: %s -> %s\n", map.c_str(), tok.playing);
                }
            }
        }
    }
    offset = _ftelli64(f);
    fclose(f);
}

int main(int argc, char **argv) {
    // 1. Resolve runtime dir = directory of this exe, and chdir there so
    //    SteamAPI_Init finds steam_appid.txt, xash3d.exe is on CWD, and
    //    engine.log is in the working directory.
    char exe_path[MAX_PATH] = {0};
    GetModuleFileNameA(nullptr, exe_path, MAX_PATH);
    std::string exe_dir(exe_path);
    size_t slash = exe_dir.find_last_of("\\/");
    if (slash != std::string::npos) exe_dir = exe_dir.substr(0, slash);
    SetCurrentDirectoryA(exe_dir.c_str());

    // 2. Pick token set from steam_appid.txt (default: CS 1.6, appid 10).
    RpTokens tok = {"10", "#CS_RP_MainMenu", "#CS_RP_PlayingKnown"};
    if (FILE *af = fopen("steam_appid.txt", "r")) {
        int appid = 0;
        if (fscanf(af, "%d", &appid) == 1 && appid == 70) {
            tok = {"70", "#HL_RP_MainMenu", "#HL_RP_SingleplayerKnown"};
        }
        fclose(af);
    }

    // 3. Build the xash3d.exe command line: forward every arg verbatim.
    std::string xash_cmdline = "xash3d.exe";
    for (int i = 1; i < argc; ++i) {
        xash_cmdline += " ";
        xash_cmdline += argv[i];
    }

    // 4. Optional Rich Presence setup. Failure here is non-fatal: the game
    //    must launch regardless.
    HMODULE hs = LoadLibraryA("steam_api.dll");
    bool rp_active = false;
    void *friends = nullptr;
    Fn_ISteamFriends_ClearRichPresence fn_clear = nullptr;
    Fn_SteamAPI_Shutdown fn_shutdown = nullptr;
    Fn_ISteamFriends_SetRichPresence fn_set_rp = nullptr;

    if (!hs) {
        log_err("steam_api.dll not found next to xash3d.exe; skipping Rich Presence.");
        log_err("       Copy it from an installed Steam HL/CS install to runtime/.");
    } else {
        auto fn_init    = (Fn_SteamAPI_Init)GetProcAddress(hs, "SteamAPI_Init");
        fn_shutdown     = (Fn_SteamAPI_Shutdown)GetProcAddress(hs, "SteamAPI_Shutdown");
        auto fn_run_cb  = (Fn_SteamAPI_RunCallbacks)GetProcAddress(hs, "SteamAPI_RunCallbacks");
        auto fn_friends = (Fn_SteamAPI_SteamFriends_v017)GetProcAddress(hs, "SteamAPI_SteamFriends_v017");
        fn_set_rp       = (Fn_ISteamFriends_SetRichPresence)GetProcAddress(hs, "SteamAPI_ISteamFriends_SetRichPresence");
        fn_clear        = (Fn_ISteamFriends_ClearRichPresence)GetProcAddress(hs, "SteamAPI_ISteamFriends_ClearRichPresence");

        if (fn_init && fn_shutdown && fn_run_cb && fn_friends && fn_set_rp && fn_clear) {
            if (fn_init()) {
                friends = fn_friends();
                if (friends) {
                    fn_set_rp(friends, "steam_display", tok.main_menu);
                    rp_active = true;
                    fprintf(stderr, "[steamrp] Rich Presence active (appid=%s, %s).\n", tok.appid, tok.main_menu);
                }
            } else {
                log_err("SteamAPI_Init failed (Steam client not running, or app not owned). Skipping RP.");
            }
        } else {
            log_err("steam_api.dll is missing expected flat-API exports; skipping RP.");
        }
    }

    // 5. Launch xash3d.exe as a child process.
    STARTUPINFOA si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    if (!CreateProcessA(nullptr, (LPSTR)xash_cmdline.c_str(), nullptr, nullptr, FALSE,
                        0, nullptr, nullptr, &si, &pi)) {
        fprintf(stderr, "[steamrp] CreateProcess failed (%lu): %s\n", GetLastError(), xash_cmdline.c_str());
        if (rp_active && fn_clear && friends) fn_clear(friends);
        if (fn_shutdown) fn_shutdown();
        return 1;
    }

    // 6. Pump Steam callbacks + tail the latest .log while xash3d runs.
    auto fn_run_cb = hs ? (Fn_SteamAPI_RunCallbacks)GetProcAddress(hs, "SteamAPI_RunCallbacks") : nullptr;
    std::string log_path;
    long long log_offset = 0;
    std::string current_map;
    DWORD last_log_check = 0;
    for (;;) {
        if (fn_run_cb) fn_run_cb();
        DWORD now = GetTickCount();
        if (rp_active && now - last_log_check >= 1000) {
            std::string latest = find_latest_log(exe_dir);
            if (!latest.empty()) {
                if (latest != log_path) {
                    log_path = latest;
                    log_offset = 0;
                    current_map.clear();
                }
                update_from_log(log_path, log_offset, current_map, friends, fn_set_rp, tok);
            }
            last_log_check = now;
        }
        DWORD r = WaitForSingleObject(pi.hProcess, 200);
        if (r == WAIT_FAILED || r == WAIT_OBJECT_0) break;
    }

    // 7. Cleanup.
    DWORD exit_code = 0;
    GetExitCodeProcess(pi.hProcess, &exit_code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    if (rp_active && fn_clear && friends) fn_clear(friends);
    if (fn_shutdown) fn_shutdown();
    return (int)exit_code;
}
