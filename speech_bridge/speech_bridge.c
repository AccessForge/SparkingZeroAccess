/*
 * speech_bridge.c - Lua 5.4 C module for UniversalSpeech
 *
 * Dynamically loads UniversalSpeech.dll and exposes speech functions to Lua.
 * Place this compiled DLL (speech_bridge.dll) in the UE4SS mod's Scripts/ folder
 * alongside UniversalSpeech.dll and nvdaControllerClient.dll.
 *
 * Lua usage:
 *   local speech = require("speech_bridge")
 *   speech.say("Hello world")          -- speak text (interrupt previous)
 *   speech.say("queued text", false)   -- speak without interrupting
 *   speech.stop()                      -- stop speaking
 *   speech.is_speaking()               -- returns true/false
 *   speech.detect()                    -- returns engine name or nil
 *   speech.set_rate(value)             -- set speech rate
 *   speech.get_rate()                  -- get speech rate
 *   speech.enable_native(true/false)   -- enable/disable SAPI fallback
 *   speech.braille("text")             -- output to braille display
 */

#include <windows.h>
#include <string.h>
#include "lua-5.4.7/src/lua.h"
#include "lua-5.4.7/src/lauxlib.h"

/* UniversalSpeech parameter constants */
#define SP_VOLUME       0
#define SP_RATE         4
#define SP_PITCH        8
#define SP_PAUSED       16
#define SP_BUSY         18
#define SP_WAIT         20
#define SP_ENABLE_NATIVE_SPEECH 0xFFFF
#define SP_ENGINE       0x40000

/* Function pointer types matching UniversalSpeech exports */
typedef int (__cdecl *fn_speechSay)(const wchar_t* str, int interrupt);
typedef int (__cdecl *fn_speechSayA)(const char* str, int interrupt);
typedef int (__cdecl *fn_speechStop)(void);
typedef int (__cdecl *fn_speechGetValue)(int what);
typedef int (__cdecl *fn_speechSetValue)(int what, int value);
typedef const wchar_t* (__cdecl *fn_speechGetString)(int what);
typedef int (__cdecl *fn_brailleDisplay)(const wchar_t* str);

/* Our own module handle, set in DllMain */
static HMODULE g_hSelf = NULL;

/* Loaded function pointers */
static HMODULE g_hDLL = NULL;
static fn_speechSay g_speechSay = NULL;
static fn_speechSayA g_speechSayA = NULL;
static fn_speechStop g_speechStop = NULL;
static fn_speechGetValue g_speechGetValue = NULL;
static fn_speechSetValue g_speechSetValue = NULL;
static fn_speechGetString g_speechGetString = NULL;
static fn_brailleDisplay g_brailleDisplay = NULL;

/* Convert UTF-8 string to wide string. Caller must free result. */
static wchar_t* utf8_to_wide(const char* utf8) {
    if (!utf8) return NULL;
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (len <= 0) return NULL;
    wchar_t* wide = (wchar_t*)malloc(len * sizeof(wchar_t));
    if (!wide) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, len);
    return wide;
}

/* Convert wide string to UTF-8. Caller must free result. */
static char* wide_to_utf8(const wchar_t* wide) {
    if (!wide) return NULL;
    int len = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
    if (len <= 0) return NULL;
    char* utf8 = (char*)malloc(len);
    if (!utf8) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8, len, NULL, NULL);
    return utf8;
}

/* Lua: speech.say(text [, interrupt]) */
static int l_say(lua_State *L) {
    const char* text = luaL_checkstring(L, 1);
    int interrupt = 1; /* default: interrupt */
    if (lua_gettop(L) >= 2) {
        interrupt = lua_toboolean(L, 2);
    }

    if (!g_speechSay) {
        lua_pushboolean(L, 0);
        return 1;
    }

    wchar_t* wide = utf8_to_wide(text);
    if (!wide) {
        lua_pushboolean(L, 0);
        return 1;
    }

    int result = g_speechSay(wide, interrupt);
    free(wide);
    lua_pushboolean(L, result >= 0);
    return 1;
}

/* Lua: speech.stop() */
static int l_stop(lua_State *L) {
    if (g_speechStop) {
        g_speechStop();
    }
    return 0;
}

/* Lua: speech.is_speaking() -> boolean */
static int l_is_speaking(lua_State *L) {
    if (g_speechGetValue) {
        lua_pushboolean(L, g_speechGetValue(SP_BUSY) != 0);
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/* Lua: speech.detect() -> string or nil */
static int l_detect(lua_State *L) {
    if (!g_speechGetString) {
        lua_pushnil(L);
        return 1;
    }

    const wchar_t* name = g_speechGetString(SP_ENGINE);
    if (!name) {
        lua_pushnil(L);
        return 1;
    }

    char* utf8 = wide_to_utf8(name);
    if (!utf8) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushstring(L, utf8);
    free(utf8);
    return 1;
}

/* Lua: speech.set_rate(value) */
static int l_set_rate(lua_State *L) {
    int value = (int)luaL_checkinteger(L, 1);
    if (g_speechSetValue) {
        lua_pushboolean(L, g_speechSetValue(SP_RATE, value) >= 0);
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/* Lua: speech.get_rate() -> integer */
static int l_get_rate(lua_State *L) {
    if (g_speechGetValue) {
        lua_pushinteger(L, g_speechGetValue(SP_RATE));
    } else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/* Lua: speech.set_volume(value) */
static int l_set_volume(lua_State *L) {
    int value = (int)luaL_checkinteger(L, 1);
    if (g_speechSetValue) {
        lua_pushboolean(L, g_speechSetValue(SP_VOLUME, value) >= 0);
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/* Lua: speech.get_volume() -> integer */
static int l_get_volume(lua_State *L) {
    if (g_speechGetValue) {
        lua_pushinteger(L, g_speechGetValue(SP_VOLUME));
    } else {
        lua_pushinteger(L, 0);
    }
    return 1;
}

/* Lua: speech.enable_native(bool) -- enable/disable SAPI fallback */
static int l_enable_native(lua_State *L) {
    int enable = lua_toboolean(L, 1);
    if (g_speechSetValue) {
        g_speechSetValue(SP_ENABLE_NATIVE_SPEECH, enable);
    }
    return 0;
}

/* Lua: speech.braille(text) */
static int l_braille(lua_State *L) {
    const char* text = luaL_checkstring(L, 1);

    if (!g_brailleDisplay) {
        lua_pushboolean(L, 0);
        return 1;
    }

    wchar_t* wide = utf8_to_wide(text);
    if (!wide) {
        lua_pushboolean(L, 0);
        return 1;
    }

    int result = g_brailleDisplay(wide);
    free(wide);
    lua_pushboolean(L, result >= 0);
    return 1;
}

/* Module function table */
static const luaL_Reg speech_funcs[] = {
    {"say", l_say},
    {"stop", l_stop},
    {"is_speaking", l_is_speaking},
    {"detect", l_detect},
    {"set_rate", l_set_rate},
    {"get_rate", l_get_rate},
    {"set_volume", l_set_volume},
    {"get_volume", l_get_volume},
    {"enable_native", l_enable_native},
    {"braille", l_braille},
    {NULL, NULL}
};

/* DllMain — capture our own module handle so we can find our directory */
BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    if (fdwReason == DLL_PROCESS_ATTACH) {
        g_hSelf = hinstDLL;
    }
    return TRUE;
}

/* Build a full path to a DLL in the same directory as speech_bridge.dll */
static HMODULE load_library_from_own_dir(const char* dllName) {
    char path[MAX_PATH];
    DWORD len = GetModuleFileNameA(g_hSelf, path, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) return NULL;

    /* Strip filename to get directory */
    char* lastSlash = strrchr(path, '\\');
    if (!lastSlash) return NULL;
    lastSlash[1] = '\0';

    /* Append the target DLL name */
    if (strlen(path) + strlen(dllName) >= MAX_PATH) return NULL;
    strcat(path, dllName);

    return LoadLibraryA(path);
}

/* Module initialization - called by require("speech_bridge") */
__declspec(dllexport) int luaopen_speech_bridge(lua_State *L) {
    /* Get our own directory so dependent DLLs also load from there */
    char modDir[MAX_PATH];
    DWORD dirLen = GetModuleFileNameA(g_hSelf, modDir, MAX_PATH);
    if (dirLen > 0 && dirLen < MAX_PATH) {
        char* slash = strrchr(modDir, '\\');
        if (slash) *slash = '\0';
        SetDllDirectoryA(modDir);
    }

    /* Load UniversalSpeech.dll from the same directory as speech_bridge.dll */
    g_hDLL = load_library_from_own_dir("UniversalSpeech.dll");
    if (!g_hDLL) {
        luaL_error(L, "Failed to load UniversalSpeech.dll from mod directory (error %lu)", GetLastError());
        return 0;
    }

    /* Load function pointers */
    g_speechSay = (fn_speechSay)GetProcAddress(g_hDLL, "speechSay");
    g_speechSayA = (fn_speechSayA)GetProcAddress(g_hDLL, "speechSayA");
    g_speechStop = (fn_speechStop)GetProcAddress(g_hDLL, "speechStop");
    g_speechGetValue = (fn_speechGetValue)GetProcAddress(g_hDLL, "speechGetValue");
    g_speechSetValue = (fn_speechSetValue)GetProcAddress(g_hDLL, "speechSetValue");
    g_speechGetString = (fn_speechGetString)GetProcAddress(g_hDLL, "speechGetString");
    g_brailleDisplay = (fn_brailleDisplay)GetProcAddress(g_hDLL, "brailleDisplay");

    if (!g_speechSay) {
        FreeLibrary(g_hDLL);
        g_hDLL = NULL;
        luaL_error(L, "Failed to find speechSay in UniversalSpeech.dll");
        return 0;
    }

    /* Enable SAPI fallback by default */
    if (g_speechSetValue) {
        g_speechSetValue(SP_ENABLE_NATIVE_SPEECH, 1);
    }

    /* Create and return the module table */
    luaL_newlib(L, speech_funcs);
    return 1;
}
