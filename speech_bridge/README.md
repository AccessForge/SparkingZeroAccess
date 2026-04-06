# Speech Bridge — Build Instructions

`speech_bridge.dll` is a Lua 5.4 C module that bridges UE4SS Lua to screen readers via UniversalSpeech.

## Prerequisites

- **GCC (MinGW-w64 64-bit):** Install via `winget install -e --id MingW-w64.MingW-w64` or download from [WinLibs](https://winlibs.com/)
- **Lua 5.4.7 source:** Download from https://www.lua.org/ftp/lua-5.4.7.tar.gz and extract to `lua-5.4.7/` in this folder
- **UniversalSpeech:** Download from https://github.com/qtnc/UniversalSpeech/releases — extract to `UniversalSpeech/` in this folder (only needed for reference; the header is included inline in speech_bridge.c)

## Build

From this directory:

```bash
# Build Lua static library first (only needed once)
cd lua-5.4.7/src
make mingw
cd ../..

# Build speech_bridge.dll
gcc -shared -o speech_bridge.dll speech_bridge.c lua-5.4.7/src/liblua54.a -luser32
```

## Output

Copy these files to `SparkingZeroAccess/`:
- `speech_bridge.dll` (the built module)

These DLLs must also be in `SparkingZeroAccess/` (pre-built, included in the mod):
- `UniversalSpeech.dll` (64-bit, from UniversalSpeech release)
- `nvdaControllerClient.dll` (from UniversalSpeech release)
- `ZDSRAPI.dll` (from UniversalSpeech release)

## How it works

- Statically links Lua 5.4 so UE4SS can `require("speech_bridge")`
- Dynamically loads `UniversalSpeech.dll` at runtime (no link-time dependency)
- Exposes `say()`, `stop()`, `detect()`, `braille()`, and rate/volume controls to Lua
- Supports NVDA, JAWS, and SAPI fallback via UniversalSpeech's engine detection
