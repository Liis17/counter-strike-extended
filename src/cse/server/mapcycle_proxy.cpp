// CSE server-side map rotation proxy.
//
// Xash3D loads this DLL as the game DLL. It forwards the normal YaPB entry
// points and replaces only the engine ChangeLevel callback. ReGameDLL still
// decides when a level ends; this proxy changes the destination map.

#include <crlib/crlib.h>
#include <linkage/goldsrc.h>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <fstream>
#include <random>
#include <string>
#include <vector>

using ChangeLevelFn = void (*)(char *, char *);
using GiveFnptrsToDllFn = void (CR_STDCALL *)(enginefuncs_t *, globalvars_t *);
using GetEntityAPIFn = int (*)(gamefuncs_t *, int);
using GetNewDLLFunctionsFn = int (*)(newgamefuncs_t *, int *);
using GetBlendingInterfaceFn = int (*)(int, void **, void *, float *, float *);
using GetPhysicsInterfaceFn = int (*)(int, void *, void *);

static enginefuncs_t g_engine {};
static globalvars_t *g_globals = nullptr;
static ChangeLevelFn g_engineChangeLevel = nullptr;
static HMODULE g_yapb = nullptr;
static GiveFnptrsToDllFn g_yapbGiveFnptrsToDll = nullptr;
static GetEntityAPIFn g_yapbGetEntityAPI = nullptr;
static GetNewDLLFunctionsFn g_yapbGetNewDLLFunctions = nullptr;
static GetBlendingInterfaceFn g_yapbGetBlendingInterface = nullptr;
static GetPhysicsInterfaceFn g_yapbGetPhysicsInterface = nullptr;

static std::vector <std::string> g_mapPool {};
static std::vector <std::string> g_remainingMaps {};
static std::mt19937 g_random {
    static_cast <std::mt19937::result_type> (
        std::chrono::steady_clock::now ().time_since_epoch ().count ())
};

static std::string ToLower (std::string value) {
    std::transform (value.begin (), value.end (), value.begin (), [] (unsigned char ch) {
        return static_cast <char> (std::tolower (ch));
    });
    return value;
}

static bool IsMapName (const std::string &value) {
    return !value.empty () && std::all_of (value.begin (), value.end (), [] (unsigned char ch) {
        return std::isalnum (ch) || ch == '_';
    });
}

static std::string ModuleDirectory () {
    MEMORY_BASIC_INFORMATION memoryInfo {};
    if (!VirtualQuery (reinterpret_cast <const void *> (&ModuleDirectory), &memoryInfo, sizeof (memoryInfo))) {
        return {};
    }

    char modulePath[MAX_PATH] {};
    const auto length = GetModuleFileNameA (
        static_cast <HMODULE> (memoryInfo.AllocationBase), modulePath, sizeof (modulePath));
    if (length == 0) {
        return {};
    }

    const std::string path (modulePath, length);
    const auto separator = path.find_last_of ("\\/");
    return separator == std::string::npos ? std::string {} : path.substr (0, separator);
}

static std::string RuntimeFilePath (const char *fileName) {
    const auto dllDirectory = ModuleDirectory ();
    if (!dllDirectory.empty ()) {
        return dllDirectory + "\\..\\" + fileName;
    }
    return std::string ("cstrike\\") + fileName;
}

static std::string MapPoolPath () {
    return RuntimeFilePath ("cse_map_pool.txt");
}

static std::string MapCyclePath () {
    return RuntimeFilePath ("mapcycle.txt");
}

static void Log (const std::string &message) {
    if (g_engine.pfnServerPrint) {
        g_engine.pfnServerPrint (("[CSE] " + message + "\n").c_str ());
    }
}

static bool ReadMapFile (const std::string &path, std::vector <std::string> &maps) {
    std::ifstream file (path, std::ios::binary);
    if (!file) {
        return false;
    }

    maps.clear ();
    std::string line;
    while (std::getline (file, line)) {
        if (!line.empty () && line.back () == '\r') {
            line.pop_back ();
        }

        const auto comment = line.find_first_of ("#/");
        if (comment != std::string::npos) {
            line.resize (comment);
        }

        const auto first = line.find_first_not_of (" \t");
        if (first == std::string::npos) {
            continue;
        }

        const auto last = line.find_first_of (" \t", first);
        auto map = ToLower (line.substr (first, last == std::string::npos ? last : last - first));
        if (IsMapName (map) && std::find (maps.begin (), maps.end (), map) == maps.end ()) {
            maps.push_back (std::move (map));
        }
    }

    return true;
}

static void LoadMapPool () {
    g_mapPool.clear ();
    g_remainingMaps.clear ();

    ReadMapFile (MapPoolPath (), g_mapPool);
    if (g_mapPool.size () < 2) {
        std::vector <std::string> mapcyclePool {};
        if (ReadMapFile (MapCyclePath (), mapcyclePool) && mapcyclePool.size () >= 2) {
            g_mapPool = std::move (mapcyclePool);
            Log ("using mapcycle.txt as the random map pool");
        }
    }

    g_remainingMaps = g_mapPool;
    if (g_mapPool.size () < 2) {
        g_mapPool.clear ();
        g_remainingMaps.clear ();
        Log ("map pool must contain at least two maps; keeping the ReGameDLL destination");
    }
}

static std::string CurrentMap () {
    if (!g_globals || !g_engine.pfnSzFromIndex) {
        return {};
    }

    const auto map = g_engine.pfnSzFromIndex (static_cast <int> (g_globals->mapname));
    return map ? ToLower (map) : std::string {};
}

static bool IsMapValid (const std::string &map) {
    return !g_engine.pfnIsMapValid || g_engine.pfnIsMapValid (map.c_str ()) != 0;
}

static std::string NextRandomMap (const std::string &currentMap) {
    if (g_mapPool.empty ()) {
        LoadMapPool ();
    }
    if (g_mapPool.empty ()) {
        return {};
    }

    for (int refill = 0; refill < 2; ++refill) {
        g_remainingMaps.erase (
            std::remove (g_remainingMaps.begin (), g_remainingMaps.end (), currentMap),
            g_remainingMaps.end ());

        std::vector <size_t> candidates {};
        for (size_t index = 0; index < g_remainingMaps.size (); ++index) {
            const auto &map = g_remainingMaps[index];
            if (map != currentMap && IsMapValid (map)) {
                candidates.push_back (index);
            }
        }

        if (!candidates.empty ()) {
            std::uniform_int_distribution <size_t> distribution (0, candidates.size () - 1);
            const auto selectedIndex = candidates[distribution (g_random)];
            const auto selectedMap = g_remainingMaps[selectedIndex];
            g_remainingMaps.erase (g_remainingMaps.begin () + selectedIndex);
            return selectedMap;
        }

        g_remainingMaps = g_mapPool;
    }

    return {};
}

static void CSE_ChangeLevel (char *map, char *landmark) {
    if (!g_engineChangeLevel) {
        return;
    }

    const auto requestedMap = map ? ToLower (map) : std::string {};
    auto currentMap = CurrentMap ();
    if (currentMap.empty ()) {
        currentMap = requestedMap;
    }

    const auto nextMap = NextRandomMap (currentMap);
    if (nextMap.empty ()) {
        g_engineChangeLevel (map, landmark);
        return;
    }

    Log ("random map rotation: " + (currentMap.empty () ? std::string ("<unknown>") : currentMap)
        + " -> " + nextMap);

    std::vector <char> nextMapBuffer (nextMap.begin (), nextMap.end ());
    nextMapBuffer.push_back ('\0');
    g_engineChangeLevel (nextMapBuffer.data (), landmark);
}

static bool LoadYaPB () {
    if (g_yapb) {
        return true;
    }

    const auto dllDirectory = ModuleDirectory ();
    const auto path = dllDirectory.empty () ? std::string ("yapb.dll") : dllDirectory + "\\yapb.dll";
    g_yapb = LoadLibraryA (path.c_str ());
    if (!g_yapb) {
        Log ("unable to load YaPB from " + path);
        return false;
    }

    g_yapbGiveFnptrsToDll = reinterpret_cast <GiveFnptrsToDllFn> (
        GetProcAddress (g_yapb, "GiveFnptrsToDll"));
    g_yapbGetEntityAPI = reinterpret_cast <GetEntityAPIFn> (
        GetProcAddress (g_yapb, "GetEntityAPI"));
    g_yapbGetNewDLLFunctions = reinterpret_cast <GetNewDLLFunctionsFn> (
        GetProcAddress (g_yapb, "GetNewDLLFunctions"));
    g_yapbGetBlendingInterface = reinterpret_cast <GetBlendingInterfaceFn> (
        GetProcAddress (g_yapb, "Server_GetBlendingInterface"));
    g_yapbGetPhysicsInterface = reinterpret_cast <GetPhysicsInterfaceFn> (
        GetProcAddress (g_yapb, "Server_GetPhysicsInterface"));

    if (!g_yapbGiveFnptrsToDll || !g_yapbGetEntityAPI) {
        Log ("YaPB does not expose the required game-DLL entry points");
        return false;
    }
    return true;
}

CR_EXPORT int GetEntityAPI (gamefuncs_t *table, int interfaceVersion) {
    return g_yapbGetEntityAPI ? g_yapbGetEntityAPI (table, interfaceVersion) : HLFalse;
}

CR_EXPORT int GetNewDLLFunctions (newgamefuncs_t *table, int *interfaceVersion) {
    return g_yapbGetNewDLLFunctions
        ? g_yapbGetNewDLLFunctions (table, interfaceVersion)
        : HLFalse;
}

CR_EXPORT int Server_GetBlendingInterface (
    int version, void **interfaceTable, void *studio, float *rotationMatrix, float *boneTransform) {
    return g_yapbGetBlendingInterface
        ? g_yapbGetBlendingInterface (version, interfaceTable, studio, rotationMatrix, boneTransform)
        : HLFalse;
}

CR_EXPORT int Server_GetPhysicsInterface (int version, void *physicsApi, void *interfaceTable) {
    return g_yapbGetPhysicsInterface
        ? g_yapbGetPhysicsInterface (version, physicsApi, interfaceTable)
        : HLFalse;
}

#if defined(CR_WINDOWS) && defined(CR_CXX_MSVC) && !defined(CR_ARCH_X64)
#pragma comment(linker, "/EXPORT:GiveFnptrsToDll=_GiveFnptrsToDll@8")
#endif

CR_EXPORT void CR_STDCALL GiveFnptrsToDll (enginefuncs_t *table, globalvars_t *globals) {
    if (!table) {
        return;
    }

    g_engine = *table;
    g_globals = globals;
    g_engineChangeLevel = table->pfnChangeLevel;
    g_mapPool.clear ();
    g_remainingMaps.clear ();

    if (!LoadYaPB ()) {
        return;
    }

    auto wrappedEngine = *table;
    wrappedEngine.pfnChangeLevel = CSE_ChangeLevel;
    g_yapbGiveFnptrsToDll (&wrappedEngine, globals);
}
