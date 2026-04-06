# Sparking Zero Access

A screen reader accessibility mod for **DRAGON BALL: Sparking! ZERO** on PC (Steam).

This mod reads game UI elements aloud through your screen reader (NVDA, JAWS, or SAPI fallback), making the game navigable for blind and visually impaired players. It tracks keyboard focus, reads menu labels, announces battle HUD changes, and more — all without altering gameplay or overriding game controls.

## Features

### Menus
- Title screen, main menu, options, and pause menu
- Settings read with label, current value, and description
- Dialogs and help windows announced automatically
- List position ("3 of 12") and tab changes
- Button prompts read as text (e.g. "Triangle" instead of an icon)

### Character Select
- Character names and DP costs in the roster grid (208 characters supported)
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

### Using AccessForge (Recommended)

[AccessForge](https://github.com/AccessForge/AccessForge) is the easiest way to install and keep the mod up to date. It takes care of everything for you — the mod loader, dependencies, and the mod itself. It works fully with screen readers like NVDA.

1. Download `AccessForge.exe` from [AccessForge Releases](https://github.com/AccessForge/AccessForge/releases)
2. Place it anywhere you like and run it
3. Find Sparking Zero Access in the mod list, select it, and click Install

That's it. When updates are released, they show up in the Updates tab — select and click Update, no manual file management needed.

### Manual Installation

1. **Install UE4SS v3.0.1** into `SparkingZERO\Binaries\Win64\`:
   - Download from [UE4SS releases](https://github.com/UE4SS-RE/RE-UE4SS/releases)
   - Extract all files into the `Win64` directory

2. **Install UTOC Signature Bypass**:
   - Required for UE4SS to work with this game
   - Place `dsound.dll` and `plugins\DBSparkingZeroUTOCBypass.asi` in the `Win64` directory

3. **Install the mod**:
   - Copy the contents of `SparkingZeroAccess\` into `SparkingZERO\Binaries\Win64\Mods\SparkingZeroAccess\Scripts\`
   - Add `SparkingZeroAccess : 1` to `Mods\mods.txt`

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

The mod polls for keyboard focus changes every 16ms using UE4SS's `LoopAsync`. When focus moves to a new widget:

1. **Fast path**: Check `WidgetLabels` table for known widget names (instant lookup)
2. **Screen-specific handlers**: Character select, team overview, skill list, room ID input, etc. each have dedicated handlers
3. **Generic path**: Read widget text via `caption` property or child TextBlock iteration
4. **Slow fallback**: `FindAllOf("TextBlock")` scan filtered by widget path

Speech output uses UniversalSpeech via a custom Lua C module (`speech_bridge.dll`) that statically links Lua 5.4 and dynamically loads UniversalSpeech.

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

When DLC characters are added to the game, update `chara_names.lua` with the new texture IDs and display names. The texture ID format is `T_UI_ChThumbP1_XXXX_YY_ZZ`. Run `uv run scripts/Update-CharaNames.py` to pull the latest data from the community spreadsheet.

## Known Issues

- Team slot character names use texture ID lookup — new DLC characters need to be added to `chara_names.lua`
- Some options screens have values displayed as images instead of text (e.g. language selection)
- Control style selector uses a full-screen overlay without keyboard focus
- Victory and match result screens have code written but need a safe polling approach

## License

This project is an accessibility mod created to make DRAGON BALL: Sparking! ZERO playable for blind and visually impaired users. It does not modify game files or alter gameplay.

DRAGON BALL: Sparking! ZERO is developed by Spike Chunsoft and published by Bandai Namco Entertainment.
