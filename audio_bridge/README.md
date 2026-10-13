# Movie description audio player

`audio_bridge.c` provides nonblocking WAV playback, pause, resume, stop and
status for the Lua description scheduler. It links Lua 5.4.7 statically and uses
Windows multimedia APIs. The Lua license is included. Clip paths are relative
to the DLL and reject traversal, absolute paths and command delimiters.

The x64 build requires Visual Studio 2022 Build Tools with C++ and Windows SDK
support. This differs from the existing MinGW speech-bridge build. Obtain
[Lua 5.4.7 source](https://www.lua.org/ftp/lua-5.4.7.tar.gz), then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File audio_bridge\Build.ps1 -LuaSource YOUR_LUA_SOURCE\src
```

The default source location is `speech_bridge/lua-5.4.7/src`. Build output is
ignored under `audio_bridge/bin`; the generated project and intermediate files
are also local. Copy `bin/audio_bridge.dll` into `SparkingZeroAccess/` for the
runtime package, keeping the `AudioDescription` folder next to it.

`tests/native_audio_bridge_test.py` exercises the real built backend using a
silent temporary WAV. It needs a Windows audio device and the test requirements;
the ordinary CI job instead tests the scheduler and failure handling with mocks.

The 37 distributed narration clips are synthetic and authorized for distribution.
Their cue sheet contains narration text, movie timings and file hashes. It
contains no private voice/profile/project identifiers. The voice reference
recording and raw/extracted game footage are not distributed.
