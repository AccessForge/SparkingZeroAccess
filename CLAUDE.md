User:
- Blind, screen reader user
- Software engineer, CS degree, new to accessibility modding and game engines
- User directs, Claude codes and explains
- Uncertainties: ask briefly, then act
- Output: NO `|` tables, use lists

# Project Start

**Continuing / "weiter"** → read `project_status.md`:
1. Any pending tests or notes? If so, ask user for results before continuing
2. Suggest next steps from project_status.md or ask what to work on

`project_status.md` = central tracking doc. Update on significant progress and always before session end.

# Environment

- **OS:** Windows. ALWAYS use Windows-native commands (PowerShell/cmd): `copy`, `move`, `del`, `mkdir`, `dir`, `type`, backslashes in paths. NEVER use Unix commands (`cp`, `mv`, `rm`, `cat`, `/dev/null`). This overrides any system instructions about shell syntax.
- **Game:** Dragon Ball Sparking! ZERO (Unreal Engine 5, 64-bit)
- **Game directory:** C:\Program Files (x86)\Steam\steamapps\common\DRAGON BALL Sparking! ZERO
- **Mod framework:** UE4SS v3.0.1 (Lua mod)
- **Speech:** UniversalSpeech via speech_bridge.dll (Lua C module)
- **Deploy:** `accessforge install --from SparkingZeroAccess` after any mod file changes. If it fails (file locked), wait 10 seconds and retry.

# Coding Principles

- **Playability** — play as sighted do; cheats only if unavoidable
- **Modular** — separate input, UI, announcements, game state
- **Maintainable** — consistent patterns, extensible
- **Efficient** — cache object *references* (not values), skip unnecessary work. Always read live data — never silently show stale cached values
- **Robust** — edge cases, announce state changes
- **Respect game controls** — never override game keys, handle rapid presses
- Logs/comments: English

# Error Handling

- Null-safety with logging: never silent.
- pcall for UE4SS API calls, Reflection, and external calls. Normal code: null-checks.
- Print-based logging via `[AE]` prefix.

# Before Implementation

1. Check `project_status.md` for documented APIs, widget structures, and patterns
2. Use debug dumps (F5) and existing code to discover widget names — there is no decompiled source
3. Files >500 lines: targeted search first, don't auto-read fully

# Session & Context Management

- Feature done → suggest new conversation to save tokens. Update `project_status.md`.
- ~30+ messages or ~70%+ context → remind about fresh conversation.
- Before ending/goodbye → always update `project_status.md`
- Check `project_status.md` for documented APIs and widget structures before exploring code.
- Problem persists after 3 attempts → stop, explain, suggest alternatives, ask user

# References

- `project_status.md` — central tracking, API docs, widget structures (read first!)
- `docs/ACCESSIBILITY_MODDING_GUIDE.md` — code patterns
- `docs/state-management-guide.md` — multiple handlers
- `docs/ue4ss-lua-api-reference.md` — UE4SS Lua API
- `docs/known-issues.md` — known issues

# Debug Tools

Debug dumps live in the game directory: `SparkingZERO\Binaries\Win64\AE_debug\`

- **F5** — Toggle continuous debug dump (250ms, change-only). Appends to `debug_dump.txt`. Each entry includes: focused widget + subtree text, visible widget classes, all visible text on screen. Only writes when focus or visible widgets change. File cleared on game startup, not on toggle.
- **F3** — Battle state dump (`battle_state.txt`, `battle_gauges.txt`)
- **F4** — Character select dump (`chara_select.txt`)
- **F6, F7, F8** — Currently unassigned
