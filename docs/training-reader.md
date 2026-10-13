# Battle Training reader

## Tutorial reminders (candidate 14)

Visible tutorial and Battle Training instructions repeat automatically every
20 seconds. A changed step is announced after the usual short settling delay
and starts a fresh reminder interval. Instructions that disappear are discarded.
Dialogue, ordinary menus and movie notices do not receive automatic reminders.
F6 still reads immediately and postpones the next automatic reminder for
20 seconds; F7/F8 retain their existing review controls.

The opening tutorial uses `WBP_GRP_TTR_HUD_TutorialAll_C`, with separate
`WBP_OBJ_TRR_HUD_TipText_C` rows. Each displayed caption is paired with the input
glyph in that same row, so Jump and Fly both retain their own LB/Space prompt.
A visible `IMG_Check_0` using `T_UI_DB_Common_CheckMark` inside the row is read
as “Check mark.” No check status is inferred from the player's inputs, hidden
widgets or future tutorial data. Only the currently attached visible snapshot
is used. Unreal's visibility calls do not establish ancestor visibility by
themselves; the existing walker checks the full parent chain
([Epic issue UE-54224](https://issues.unrealengine.com/issue/UE-54224)).

The repeat timer reuses the existing screen capture, with no extra object
search or polling loop. Eight new checks cover row associations, mark ownership,
timing, changed/removed steps, ordinary dialogue, Battle Training, progress-only
changes and F6 timing. All 184 Lua checks pass. Replaying three captured opening
tutorial snapshots preserved the real input bindings and visible check marks.

## Battle Training composition

The reader uses the current visible UI captured by `visible_ui.lua`. For
`WBP_GRP_HUD_CSG_HUD_Main_C`, `training_reader.lua` combines the displayed
category title and comment, command button glyphs and tip caption into one
item. Automatic reading and F6/F7/F8 share that item. Other text remains in
the screen reader unchanged.

Grouping uses the exact root instance. It deduplicates repeated title/comment
text but retains separate command buttons with the same input. Dismissed
widgets disappear from the next capture, so the reader cannot carry a previous
instruction into an explanation-only page or a new lesson. The raw diagnostic
capture remains unchanged.

The input list says "Displayed inputs". It does not invent timing, hold
requirements, future steps or success results. Native Ghidra research identifies
`CommandData.Commentary` and `SettingData.Commands`/`ClassicCommands` as full
lesson records; the reader deliberately does not access them.

## Evidence and validation

- User session: October 3, 2026, 21:26-21:35 CDT, candidate 11. The Transform
  prompt used XSX `Pad_22`, and the player confirmed using D-pad Up. The old
  parser incorrectly called it Right Stick Up.
- A one-shot game-thread read at 21:55:52 returned all 32 entries from
  `KoratGameSingleton.OptionData.KeyIconTextTable`. It verifies right stick
  directions 18-21, D-pad directions 22-25, special-right 00 and special-left
  01. Ghidra's native tag builder uses those same ids for PS5 and XSX. The
  parser now reads these as right stick, D-pad, Menu/Options and View/Touchpad.
- `PadIconFKeyTable` is a separate reverse map of Japanese textual button
  symbols to input keys; despite its name, its keys are not `Pad_NN` ids.
- Local capture: `../evidence/user-training-20261003-213653` outside this repo.
  Offline replay preserves all 539 text rows across 84 captured snapshots,
  including 55 occurrences of the corrected Transform input.
- `tests/training_reader_test.lua` covers composition, current-only inputs,
  root separation, preservation of other text, repeated command buttons,
  change settling and F6 review with real icon parsing.
- `tests/focus_caption_ready_test.lua` covers the separate initial-caption
  readiness bug on both supported loader query APIs.

Other image-only success/practice states and exact input sequence ordering still need
native or visual confirmation before the reader can describe those details.
These checks establish displayed-text coverage, not complete gameplay access.
