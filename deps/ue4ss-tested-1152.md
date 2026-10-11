# Tested UE4SS loader bundle

`ue4ss-tested-1152.zip` contains the loader files used in the local repair:

- `dwmapi.dll` next to the shipping executable;
- `ue4ss/UE4SS.dll` (UE4SS 3.0.1-1152-ge3ba1016);
- `ue4ss/UE4SS-settings.ini` with the tested configuration;
- the stock SDK backend JSON and MIT license;
- `FILE-HASHES.json` with SHA-256 hashes for those five files.

Archive SHA-256:
`78EC4F345F3990365CE77B76934B73974EA0AEA99E2BB4BC6A67D4F10881CBEE`.
UE4SS DLL SHA-256:
`680A026890ABB4D0DF2211251F8DEFC1681A584275F1521DCC0FE30AF480006F`.

This is the official UE4SS binary, with game-specific settings. It contains no
game executable, player settings, saves, logs, narration or local machine paths.
The official source project is [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS).

`HookInitGameState=0` is required on the tested game builds: Ghidra showed that
the detected hook target returns a class pointer, while the hook expects an
initializer. The unmodified hook crashed even with this mod disabled.
EngineTick execution/scanning and the normal map/script hooks stay enabled.
The other settings disable the UObject listener cache, hot reload and GUI
consoles. The runtime retains fresh UI values.

The standalone package builder consumes this ZIP and preserves the tested
`ue4ss/Mods` layout. Its installer backs up and disables an active legacy root
`UE4SS.dll`, preserves other mod entries, and refuses a running game.

**AccessForge integration still needs attention before its automatic update
path can claim compatibility.** Its current installer chooses a generic UE4SS
release and installs mod scripts under `Win64/Mods`. The tested loader layout
uses `Win64/ue4ss/Mods`. This ZIP is deliberately not added as an automatic patch
dependency: copying it alone would leave the layout mismatch and an active
legacy DLL unresolved. Use the standalone repair ZIP for the tested path, or
adapt AccessForge's loader installation and migration before enabling that path.
