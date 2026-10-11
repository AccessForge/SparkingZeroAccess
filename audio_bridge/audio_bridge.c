/* Local asynchronous PCM16 narration. No screen-reader or game audio changes. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "lua.h"
#include "lauxlib.h"

static HMODULE self_module;
static HWAVEOUT device;
static WAVEHDR header;
static BYTE *file_buffer;
static int paused;

static int failure(lua_State *L, const char *message) {
    lua_pushboolean(L, 0); lua_pushstring(L, message); return 2;
}
static int audio_result(lua_State *L, MMRESULT error) {
    char message[256] = {0};
    if (!error) { lua_pushboolean(L, 1); return 1; }
    waveOutGetErrorTextA(error, message, sizeof(message));
    return failure(L, message);
}
static MMRESULT close_audio(void) {
    MMRESULT error;
    if (device) {
        error = waveOutReset(device);
        if (error) return error;
        if (header.dwFlags & WHDR_PREPARED) {
            error = waveOutUnprepareHeader(device, &header, sizeof(header));
            if (error) return error;
        }
        error = waveOutClose(device);
        if (error) return error;
        device = NULL;
    }
    free(file_buffer); file_buffer = NULL;
    memset(&header, 0, sizeof(header)); paused = 0;
    return MMSYSERR_NOERROR;
}
static DWORD read_u32(const BYTE *p) { DWORD n; memcpy(&n, p, 4); return n; }

static int play(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    wchar_t path[4096], relative[1024];
    DWORD path_length, size, count, offset, data_size = 0;
    HANDLE file;
    WAVEFORMATEX format = {0};
    BYTE *data = NULL;
    MMRESULT error;
    if (strstr(name, "..") || strchr(name, ':') || strchr(name, '"') ||
        strchr(name, '\n') || strchr(name, '\r') || name[0] == '/' || name[0] == '\\')
        return luaL_error(L, "description clip must be a relative local filename");
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, relative, 1024))
        return failure(L, "Invalid description filename");
    path_length = GetModuleFileNameW(self_module, path, 4096);
    if (!path_length || path_length >= 4096) return failure(L, "Module path unavailable");
    wchar_t *slash = wcsrchr(path, L'\\');
    if (!slash) return failure(L, "Module directory unavailable");
    slash[1] = 0;
    if (wcscat_s(path, 4096, relative)) return failure(L, "Description path too long");
    /* Do not overwrite or free a buffer the audio driver still owns. */
    error = close_audio();
    if (error) return audio_result(L, error);
    file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return failure(L, "Description audio file cannot be opened");
    size = GetFileSize(file, NULL);
    if (size < 44 || size > 32 * 1024 * 1024) {
        CloseHandle(file); return failure(L, "Invalid description WAV size");
    }
    file_buffer = (BYTE*)malloc(size);
    if (!file_buffer) { CloseHandle(file); return failure(L, "Audio allocation failed"); }
    if (!ReadFile(file, file_buffer, size, &count, NULL) || count != size) {
        CloseHandle(file); close_audio(); return failure(L, "Audio read failed");
    }
    CloseHandle(file);
    if (memcmp(file_buffer, "RIFF", 4) || memcmp(file_buffer + 8, "WAVE", 4)) {
        close_audio(); return failure(L, "Description audio is not WAV");
    }
    for (offset = 12; offset <= size - 8;) {
        DWORD chunk_size = read_u32(file_buffer + offset + 4);
        DWORD start = offset + 8;
        if (chunk_size > size - start) { close_audio(); return failure(L, "Truncated WAV chunk"); }
        if (!memcmp(file_buffer + offset, "fmt ", 4) && chunk_size >= 16)
            memcpy(&format, file_buffer + start, 16);
        if (!memcmp(file_buffer + offset, "data", 4)) { data = file_buffer + start; data_size = chunk_size; }
        offset = start + chunk_size + (chunk_size & 1);
    }
    if (format.wFormatTag != WAVE_FORMAT_PCM || format.wBitsPerSample != 16 ||
        format.nChannels < 1 || format.nChannels > 2 || format.nSamplesPerSec < 8000 ||
        format.nSamplesPerSec > 96000 || format.nBlockAlign != format.nChannels * 2 ||
        format.nAvgBytesPerSec != format.nSamplesPerSec * format.nBlockAlign ||
        !data || !data_size || data_size % format.nBlockAlign) {
        close_audio(); return failure(L, "Description WAV must be mono or stereo PCM16");
    }
    error = waveOutOpen(&device, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL);
    if (error) { close_audio(); return audio_result(L, error); }
    header.lpData = (LPSTR)data; header.dwBufferLength = data_size;
    error = waveOutPrepareHeader(device, &header, sizeof(header));
    if (!error) error = waveOutWrite(device, &header, sizeof(header));
    if (error) close_audio();
    return audio_result(L, error);
}
static int stop(lua_State *L) { return audio_result(L, close_audio()); }
static int pause_audio(lua_State *L) {
    MMRESULT error = device ? waveOutPause(device) : 0;
    if (!error && device) paused = 1;
    return audio_result(L, error);
}
static int resume_audio(lua_State *L) {
    MMRESULT error = device ? waveOutRestart(device) : 0;
    if (!error) paused = 0;
    return audio_result(L, error);
}
static int mode(lua_State *L) {
    lua_pushstring(L, !device ? "closed" : (header.dwFlags & WHDR_DONE) ? "stopped" : paused ? "paused" : "playing");
    return 1;
}
static const luaL_Reg functions[] = {
    {"play", play}, {"stop", stop}, {"pause", pause_audio},
    {"resume", resume_audio}, {"mode", mode}, {NULL, NULL}
};
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) { self_module = instance; DisableThreadLibraryCalls(instance); }
    return TRUE; /* Audio APIs must not run under the Windows loader lock. */
}
__declspec(dllexport) int luaopen_audio_bridge(lua_State *L) {
    luaL_newlib(L, functions);
    lua_newuserdatauv(L, 1, 0);
    if (luaL_newmetatable(L, "SparkingZeroAccess.AudioLifetime")) {
        lua_pushcfunction(L, stop); lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);
    lua_setfield(L, -2, "_lifetime");
    return 1;
}
