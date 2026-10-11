# Sparking Zero Access

A screen reader accessibility mod for **DRAGON BALL: Sparking! ZERO** on PC (Steam).

This mod reads game UI elements aloud through your screen reader (NVDA, JAWS, or SAPI fallback), making the game navigable for blind and visually impaired players. It tracks keyboard focus, reads menu labels, announces battle HUD changes, and more — all without altering gameplay or overriding game controls.

The current repair was exercised on Windows Steam game version
**3022.021.003.012.015**, build **24953175**. It adds game-thread reading and
recovery, faster widget queries, language/controls/tutorial coverage, native
character names, F6/F7/F8 review, twenty-second tutorial reminders, movie audio
description and once-per-charge skill-guide reading. See
[the repair and its validation limits](docs/current-build-repair.md).

## Features

### Menus
- Title screen, main menu, options, and pause menu
- Settings read with label, current value, and description
- Dialogs and help windows announced automatically
- List position ("3 of 12") and tab changes
- Button prompts read as text (e.g. "Triangle" instead of an icon)

### Character Select
- Character names from native game records and DP costs in the roster grid
- Team slots with character name, DP, and slot number
- Skills with type, name, button combo, cost, and description
- Team overview with total DP
- Both player sides readable

### Battle
- HP, KI, and Sparking gauge changes for you and your opponent
- Skill point changes
- Match timer with countdown
- Works in local and online matches

### Online
- Player Match room lobby with player names, status, and win counts
- Room ID input with digit-by-digit navigation
- Player join/leave announcements
- Rank Match lobby

## Installation

### Requirements
- DRAGON BALL: Sparking! ZERO (Steam, PC)
- A screen reader: NVDA (recommended), JAWS, or Windows SAPI
- Windows 10 or later (64-bit)

### Standalone repair for the tested current build

Download the complete `dragon-ball-sparking-zero-access-VERSION-repair.zip`
asset from [Releases](https://github.com/AccessForge/SparkingZeroAccess/releases),
extract it, close the game and run **Install.cmd**. It finds Steam libraries
automatically, uses a numbered choice or Windows file picker when necessary,
backs up replaced files and preserves other mod entries.

This asset includes the tested loader and its required game-specific settings.
AccessForge's generic loader selection and older mod-folder layout still need
integration before its automatic install/update path can claim the same
compatibility. See [loader requirements](deps/ue4ss-tested-1152.md).

### Using AccessForge

[AccessForge](https://github.com/AccessForge/AccessForge) is the easiest way to install and keep the mod up to date. It takes care of everything for you — the mod loader, dependencies, and the mod itself. It works fully with screen readers like NVDA.

1. Download `AccessForge.exe` from [AccessForge Releases](https://github.com/AccessForge/AccessForge/releases)
2. Place it anywhere you like and run it
3. Find Sparking Zero Access in the mod list, select it, and click Install

That's it. When updates are released, they show up in the Updates tab — select and click Update, no manual file management needed.

### Manual Installation

1. **Install the tested UE4SS loader and configuration** into `SparkingZERO\Binaries\Win64\`:
   - Use `deps/ue4ss-tested-1152.zip` and follow its [layout and migration notes](deps/ue4ss-tested-1152.md).
   - Back up and disable an active legacy root `UE4SS.dll` before using the new `ue4ss` subfolder layout.
   - The required `HookInitGameState=0` setting is included. Stock UE4SS v3.0.1 is not the validated loader for this repair.

2. **Install UTOC Signature Bypass**:
   - Required for UE4SS to work with this game
   - Place `dsound.dll` and `plugins\DBSparkingZeroUTOCBypass.asi` in the `Win64` directory

3. **Install the mod**:
   - Copy the entire contents of `SparkingZeroAccess\`, including DLLs and `AudioDescription\`, into `SparkingZERO\Binaries\Win64\ue4ss\Mods\SparkingZeroAccess\Scripts\`.
   - Add `SparkingZeroAccess : 1` to `ue4ss\Mods\mods.txt`.

4. **Launch the game**. You should hear "Press confirm to start" on the title screen.

## Development

### Project Structure

```
SparkingZeroAccess/         # The Lua mod (deployed to game)
  main.lua                  # Orchestrator: focus tracking, keybinds, init
  helpers.lua               # TryCall, TryGetProperty, GetWidgetName, IsValidRef
  speech.lua                # Speech init, Speak/SpeakQueued
  widget_reader.lua         # Text reading, widget matching, label resolution
  poll_trackers.lua         # Dialog, help window, screen change, room polling
  icon_parser.lua           # RichText icon markup to readable text
  battle.lua                # Battle HUD: HP/KI/Sparking, opponent tracking
  team_overview.lua         # Team setup: slot navigation, character names
  chara_roster.lua          # Character roster: grid names, skills
  chara_names.lua           # Texture ID to character name lookup table
  skill_list.lua            # Skill list overlay reading
  debug_tools.lua           # Debug dump utilities (F3-F5)
  speech_bridge.dll         # Lua C module bridging to UniversalSpeech
  UniversalSpeech.dll       # Screen reader abstraction library
  nvdaControllerClient.dll  # NVDA support
  ZDSRAPI.dll               # Additional speech support

speech_bridge/              # Speech bridge source code
  speech_bridge.c           # Lua C module source
  speech_bridge.dll         # Compiled bridge
```

### How It Works

The mod reads engine objects on the game thread through one persistent job pump.
Map-load hooks suspend reads during transitions and discard delayed work from
the old world. Focus recovery retries unresolved current captions without
creating another polling loop. When focus moves to a new widget:

1. **Fast path**: Check `WidgetLabels` table for known widget names (instant lookup)
2. **Screen-specific handlers**: Character select, team overview, skill list, room ID input, etc. each have dedicated handlers
3. **Generic path**: Read widget text via `caption` property or child TextBlock iteration
4. **Visible-tree fallback**: attached UI text scoped to the current widget and visible ancestors

Speech output uses UniversalSpeech via a custom Lua C module (`speech_bridge.dll`) that statically links Lua 5.4 and dynamically loads UniversalSpeech.

The movie description backend has separate source in `audio_bridge/`. Its build
and reproducible reader/installer checks are documented in
[current-build repair](docs/current-build-repair.md). The release workflow also
packages the standalone repair through `helpers/Build-RepairPackage.py`.

### Building the Speech Bridge

From the `speech_bridge/` directory:

```
gcc -shared -o speech_bridge.dll speech_bridge.c lua-5.4.7/src/liblua54.a -luser32
```

Requires WinLibs MinGW-w64 (installable via `winget install winlibs.mingw-w64`).

### Deploying Changes

After modifying files in `SparkingZeroAccess/`:

```
accessforge install --from SparkingZeroAccess
```

### Debug Tools

Press **F5** in-game to toggle continuous debug dumping. Dumps are written to `SparkingZERO\Binaries\Win64\AE_debug\debug_dump.txt` every 250ms when changes are detected. Each entry includes the focused widget with subtree text, visible widget classes, and all visible text on screen.

Additional dumps:
- **F3** — Battle state and gauge values
- **F4** — Character select texture IDs

### Adding New Characters

Character names now prefer the game's native character records, including late
portrait loading and changed roster entries. `chara_names.lua` remains the
fallback for older or unavailable records. See [character-name coverage](docs/character-names.md).

## Known Issues

- F9 off mutes text-only story lines as well as dialogue in recognized subtitle windows; F6 still reviews them. Voiced-only filtering remains unimplemented.
- Some controller glyphs remain unresolved; this repair does not claim to resolve issue #3 or replace the separate D-pad PR #6.
- Movie narration covers the main opening and post-tutorial movie only; other movies report unavailable.
- Broader screens, online play, player-two/controller coverage and performance on other PCs still need live testing.
- Victory and match result screens have code written but need a safe polling approach

## License

This project is an accessibility mod created to make DRAGON BALL: Sparking! ZERO playable for blind and visually impaired users. It does not modify game files or alter gameplay.

DRAGON BALL: Sparking! ZERO is developed by Spike Chunsoft and published by Bandai Namco Entertainment.
