# Current-build accessibility repair

The contributed runtime is the candidate20 repair tested on Steam game version
3022.021.003.012.015, build 24953175. The executable SHA-256 is
`6DB7002A8FA66A1309B01037D8A9A8C678A8ECD35B72D4C6AFAC550A74371657`.
Earlier compatibility work also exercised version 3020.019.003.012.013.

The repair fixes the startup initialization hook, runs Unreal reads on the game
thread, bounds callbacks during loading/recovery, and replaces slow repeated
object scans with live widget queries. A later correction releases native widget
query arrays instead of retaining them across polling cycles. Focus retry,
visible-tree reading and manual review retain information during rapid menu
navigation. Diagnostics report slow reader jobs and Lua memory without requiring
F5 logging.

Displayed language textures, controls, training lessons, native character names
and visible training indicators are read from the game's current UI/state.
Tutorial instructions repeat every twenty seconds. The skill/button guide reads
once per ki-charge hold; release/re-press permits another reading and F6 remains
immediate. No combat or confirmation input is automated.

The movie reader follows the native clock of a movie whose material is attached
to the displayed UI. The runtime contains 37 authorized narration clips: nineteen
for the main opening and eighteen for the post-tutorial movie, with 1K/2K/4K
aliases. It includes the native audio player and its source/Lua license. Raw game
footage, the voice reference recording and private generation identifiers are
excluded. Missing narration/backend data reports unavailable rather than stopping
ordinary menu speech.

F6 reads the current screen; F7/F8 review individual text items. F9 remembers
whether automatic subtitle speech is enabled. **F9 off currently also mutes
text-only story lines in recognized dialogue windows.** F6 can still review them.
The proposed correction to silence only positively confirmed voiced character
dialogue is not implemented in this contribution. See
[subtitle controls](subtitle-speech.md) and [charge guide controls](ki-charge-guide.md).

## Loader and release integration

The tested loader is UE4SS 3.0.1-1152-ge3ba1016 with `HookInitGameState=0`,
EngineTick execution/scanning, UObject listener cache disabled, hot reload off
and GUI consoles off. The tested files and MIT license are in
`deps/ue4ss-tested-1152.zip`; see [loader bundle and AccessForge limits](../deps/ue4ss-tested-1152.md).

The existing AccessForge mod asset still contains all runtime Lua, speech DLLs,
`audio_bridge.dll` and the entire `AudioDescription` folder. The release workflow
also builds a separate `-repair.zip` with the tested loader/configuration and
the backup-making installer. To reproduce that package without touching a game:

```powershell
python helpers/Build-RepairPackage.py --output standalone-repair
```

The current AccessForge 1.0.3 packager was exercised locally: its mod ZIP retains
all 68 runtime files, including the narration subfolder and native audio DLL.
The separately generated repair payload matches all 75 files in the installed
candidate20 build, apart from the intentionally managed mod registry.

Use the standalone repair ZIP for the currently tested installation path.
AccessForge's automatic loader choice and its older `Win64/Mods` layout have
not been migrated by this contribution. That integration remains a maintainer
decision before claiming compatibility through automatic AccessForge updates.

## Reproduce automated checks

Use Python 3.12 and stock Windows PowerShell 5.1 from the repository root:

```powershell
python -m pip install -r requirements-tests.txt
python tests/run_lua54.py
python -m unittest discover -s tests -p test_build_descriptions.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\install_discovery_test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\install_repair_test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\install_launcher_test.ps1
```

The Lua runner covers 323 checks in thirty suites and parses all twenty-four
runtime modules. Installer tests use isolated fixtures rather than a live game.
Description-builder checks use silent temporary PCM data rather than voice data.
The Tests workflow runs these checks on Windows. Native audio playback requires
a Windows audio device and is tested separately using
`tests/native_audio_bridge_test.py` after building `audio_bridge/bin/audio_bridge.dll`.

## Build the optional native audio player

Install Visual Studio 2022 Build Tools with the C++ workload and obtain the
official Lua 5.4.7 source. Place it at `speech_bridge/lua-5.4.7` or provide its
`src` directory explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File audio_bridge\Build.ps1 -LuaSource YOUR_LUA_SOURCE\src
```

Copy the built `audio_bridge/bin/audio_bridge.dll` beside the other runtime Lua
modules, keeping `AudioDescription` alongside it. The committed DLL is the tested
x64 build. Its PDB record contains only `audio_bridge.pdb`, not a local build path.

## Live evidence and limits

A player confirmed responsive menus/training with continued speech after the
lookup correction, rapid-menu movement with working speech, readable character
names/F6 text, and once-per-hold guide reading with F6 repeat. Opening-description
starts and scheduler behavior were recorded in game. These results establish
specific local behavior; they do not validate every screen, DLC, online mode,
controller/player side, narration volume or another player's frame times.

No F5 native-state trace was captured during the final charge listening check.
The exact live input-to-guide association and player-two coverage remain
separate from that listening result. Whether each listed move can activate while
charging also remains untested.
