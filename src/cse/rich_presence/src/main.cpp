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
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <set>
#include <string>
#include <vector>

namespace fs = std::filesystem;

// Flat-API typedefs, matched against the exports of steam_api.dll
// (Steamworks SDK ~1.5x, file version 06.91.21.57 as shipped with HL/CS).
typedef bool   (__cdecl *Fn_SteamAPI_Init)();
typedef void   (__cdecl *Fn_SteamAPI_Shutdown)();
typedef void   (__cdecl *Fn_SteamAPI_RunCallbacks)();
typedef void * (__cdecl *Fn_SteamAPI_SteamFriends_v017)();
typedef bool   (__cdecl *Fn_ISteamFriends_SetRichPresence)(void *self, const char *key, const char *value);
typedef void   (__cdecl *Fn_ISteamFriends_ClearRichPresence)(void *self);

// Avatar service, see the "Steam avatars" section below.
typedef void *   (__cdecl *Fn_SteamAPI_Accessor)();
typedef uint64_t (__cdecl *Fn_ISteamUser_GetSteamID)(void *self);
typedef bool     (__cdecl *Fn_ISteamFriends_RequestUserInformation)(void *self, uint64_t steamID, bool nameOnly);
typedef int      (__cdecl *Fn_ISteamFriends_GetMediumFriendAvatar)(void *self, uint64_t steamID);
typedef bool     (__cdecl *Fn_ISteamUtils_GetImageSize)(void *self, int image, uint32_t *w, uint32_t *h);
typedef bool     (__cdecl *Fn_ISteamUtils_GetImageRGBA)(void *self, int image, uint8_t *dest, int destSize);

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

// ---------------------------------------------------------------------------
// Steam avatars
//
// The game client cannot link steam_api itself, so this helper acts as its
// Steam side. Files exchanged under <exe_dir>/<gamedir>/cache/:
//   cse_steam_self.txt      written here: the local player's SteamID64, which
//                           the client republishes as the "cse_sid" userinfo key
//   avatars/wanted.txt      written by the client: one SteamID64 per line
//   avatars/<id64>.tga      written here: 32-bit uncompressed TGA
//
// Steam only knows accounts, so bots and non-Steam players never produce a
// file and the client keeps its placeholder slot for them.
// ---------------------------------------------------------------------------

struct SteamAvatars {
    void *user = nullptr;
    void *utils = nullptr;
    void *friends = nullptr;
    Fn_ISteamFriends_RequestUserInformation request = nullptr;
    Fn_ISteamFriends_GetMediumFriendAvatar  get_avatar = nullptr;
    Fn_ISteamUtils_GetImageSize             image_size = nullptr;
    Fn_ISteamUtils_GetImageRGBA             image_rgba = nullptr;
    std::string dir;                 // <exe_dir>/<gamedir>/cache/avatars
    std::set<uint64_t> requested;    // RequestUserInformation already sent
    std::set<uint64_t> done;         // TGA already on disk

    bool ready() const { return utils && friends && request && get_avatar && image_size && image_rgba; }
};

// Interface accessors are version-suffixed (SteamAPI_SteamUtils_v010, ...) and
// the suffix moves with the SDK, so probe a range instead of pinning one.
static void *resolve_interface(HMODULE dll, const char *base) {
    for (int v = 5; v <= 40; ++v) {
        char name[128];
        snprintf(name, sizeof(name), "%s_v%03d", base, v);
        if (auto fn = (Fn_SteamAPI_Accessor)GetProcAddress(dll, name)) {
            if (void *iface = fn()) return iface;
        }
    }
    return nullptr;
}

// 32-bit uncompressed TGA, top-down (attribute bit 0x20), BGRA byte order —
// the exact shape xash3d's img_tga.c reads back without a flip.
static bool write_tga32(const std::string &path, uint32_t w, uint32_t h, const uint8_t *rgba) {
    FILE *f = fopen(path.c_str(), "wb");
    if (!f) return false;

    uint8_t header[18] = {0};
    header[2] = 2; // uncompressed true-color
    header[12] = (uint8_t)(w & 0xFF);
    header[13] = (uint8_t)((w >> 8) & 0xFF);
    header[14] = (uint8_t)(h & 0xFF);
    header[15] = (uint8_t)((h >> 8) & 0xFF);
    header[16] = 32;
    header[17] = 0x28; // top-down + 8 alpha bits
    fwrite(header, 1, sizeof(header), f);

    std::vector<uint8_t> row(w * 4);
    for (uint32_t y = 0; y < h; ++y) {
        const uint8_t *src = rgba + (size_t)y * w * 4;
        for (uint32_t x = 0; x < w; ++x) {
            row[x * 4 + 0] = src[x * 4 + 2];
            row[x * 4 + 1] = src[x * 4 + 1];
            row[x * 4 + 2] = src[x * 4 + 0];
            row[x * 4 + 3] = src[x * 4 + 3];
        }
        fwrite(row.data(), 1, row.size(), f);
    }

    fclose(f);
    return true;
}

// Reads the client's request list and writes out whatever Steam already has.
// Avatars arrive asynchronously: GetMediumFriendAvatar returns 0 until the
// image is cached locally, so unfinished ids are simply retried next tick.
static void process_avatar_requests(SteamAvatars &av) {
    if (!av.ready()) return;

    FILE *f = fopen((av.dir + "\\wanted.txt").c_str(), "r");
    if (!f) return;

    char line[64];
    while (fgets(line, sizeof(line), f)) {
        uint64_t id = strtoull(line, nullptr, 10);
        if (id == 0 || av.done.count(id)) continue;

        std::string out = av.dir + "\\" + std::to_string(id) + ".tga";
        if (fs::exists(out)) {
            av.done.insert(id);
            continue;
        }

        if (av.requested.insert(id).second)
            av.request(av.friends, id, false);

        int image = av.get_avatar(av.friends, id);
        if (image <= 0) continue;

        uint32_t w = 0, h = 0;
        if (!av.image_size(av.utils, image, &w, &h) || w == 0 || h == 0) continue;

        std::vector<uint8_t> rgba((size_t)w * h * 4);
        if (!av.image_rgba(av.utils, image, rgba.data(), (int)rgba.size())) continue;

        if (write_tga32(out, w, h, rgba.data())) {
            av.done.insert(id);
            fprintf(stderr, "[steamrp] avatar %llu -> %ux%u\n", (unsigned long long)id, w, h);
        }
    }

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

    // 3. Build the xash3d.exe command line: forward every arg verbatim. The
    //    gamedir is picked out of it too, since the avatar cache lives there.
    std::string xash_cmdline = "xash3d.exe";
    std::string gamedir = "cstrike";
    for (int i = 1; i < argc; ++i) {
        xash_cmdline += " ";
        xash_cmdline += argv[i];
        if (!strcmp(argv[i], "-game") && i + 1 < argc) gamedir = argv[i + 1];
    }

    // 4. Optional Rich Presence setup. Failure here is non-fatal: the game
    //    must launch regardless.
    HMODULE hs = LoadLibraryA("steam_api.dll");
    bool rp_active = false;
    void *friends = nullptr;
    SteamAvatars avatars;
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

                // Avatar service. Every piece is optional: a missing export
                // just leaves the client on placeholder slots.
                std::string cache = exe_dir + "\\" + gamedir + "\\cache";
                std::error_code ec;
                fs::create_directories(cache + "\\avatars", ec);

                avatars.friends    = friends;
                avatars.user       = resolve_interface(hs, "SteamAPI_SteamUser");
                avatars.utils      = resolve_interface(hs, "SteamAPI_SteamUtils");
                avatars.dir        = cache + "\\avatars";
                avatars.request    = (Fn_ISteamFriends_RequestUserInformation)GetProcAddress(hs, "SteamAPI_ISteamFriends_RequestUserInformation");
                avatars.get_avatar = (Fn_ISteamFriends_GetMediumFriendAvatar)GetProcAddress(hs, "SteamAPI_ISteamFriends_GetMediumFriendAvatar");
                avatars.image_size = (Fn_ISteamUtils_GetImageSize)GetProcAddress(hs, "SteamAPI_ISteamUtils_GetImageSize");
                avatars.image_rgba = (Fn_ISteamUtils_GetImageRGBA)GetProcAddress(hs, "SteamAPI_ISteamUtils_GetImageRGBA");

                auto fn_steam_id = (Fn_ISteamUser_GetSteamID)GetProcAddress(hs, "SteamAPI_ISteamUser_GetSteamID");
                if (avatars.user && fn_steam_id) {
                    uint64_t self_id = fn_steam_id(avatars.user);
                    if (self_id) {
                        if (FILE *sf = fopen((cache + "\\cse_steam_self.txt").c_str(), "w")) {
                            fprintf(sf, "%llu\n", (unsigned long long)self_id);
                            fclose(sf);
                        }
                        fprintf(stderr, "[steamrp] local SteamID64: %llu\n", (unsigned long long)self_id);
                    }
                }

                if (!avatars.ready())
                    log_err("steam_api.dll lacks the avatar exports; slots stay on placeholders.");
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
        if (now - last_log_check >= 1000)
            process_avatar_requests(avatars);
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
