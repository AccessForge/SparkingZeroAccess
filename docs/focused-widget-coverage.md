# Focused widget reading

`widget_reader.lua` decides what to say for the widget that has keyboard
focus. Since 2026-10-03 it reads only text that belongs to that widget and is
actually displayed. Previously it matched instance-name substrings across the
whole game. For example, `ControlButton` could announce another row's
"Battle Assist" title, and a stale hidden caption could be spoken.

## Scope rules

- **Own subtree only.** The reader walks the focused user widget's
  `WidgetTree.RootWidget`. It descends through panel children (`GetChildrenCount`
  and `GetChildAt`) and nested user widgets' own trees.
- **Displayed only.** Any of these excludes text:
  - `IsVisible()` false on the text or an ancestor (Collapsed or Hidden)
  - `RenderOpacity` of 0
  - an inactive `WidgetSwitcher` page
- **Fallback.** If a widget's `WidgetTree` cannot be read, it uses the per-cycle
  `TextBlock` and `RichTextBlock` queries instead. It keeps only text whose path
  starts with the widget's exact path plus `.`, then walks up with `GetParent`.
  At a tree root it continues to the owning user widget through
  `GetOuter():GetOuter()`. The same visibility rules apply, and widgets removed
  from their tree are rejected.
- **Hit areas** (`HitBtn_Text_05`, `HitButton_3`) first use their native
  `USSMenuButton.RemoteButton` reference. That display widget must be live,
  attached, displayed, and share the same nearest owning user widget. The
  link can identify a caption with a different numeric suffix, as in Battle
  Training. No captions are cached.
- If a hit area's label is not ready on initial focus, `main.lua` retries at
  250 ms intervals for at most twelve attempts. A newly available label is
  queued once; focus loss, map changes and reader shutdown cancel the retry.
  Resolved labels retain their normal live caption polling.
- When no usable native link exists, the numbered menu item (`BTN_Menu`,
  `SetBGMBTN`, `SetRuleBTN`) with the same number provides the label:
  - The item must be in the hit area's list: the nearest owning user widget
    that holds numbered menu items.
  - The item must be displayed.
  - A number missing from that list is never borrowed from another list or
    screen. The cleaned widget name is spoken instead, and
    `[AE] No match found for:` is logged.
- **List position** ("3 of 12") counts only displayed hit areas in the focused
  widget's nearest owner that holds more than one of them. `main.lua` passes
  the focused widget explicitly to `GetListPosition(name, widget)`.

## What is spoken

- **Label.** In order of preference:
  - the widget's own `Title`, `Text_Title`, `TitleText` or `TXT_Label`
  - its native FText `Title` property
  - a nested title text
  - otherwise the caption or first displayed text

  The setting-template placeholder `設定項目` is never used.
- **Value.** In order of preference:
  - the native `SSMenuButton.caption` widget, when displayed
  - the shallowest displayed text named `caption`
  - for a titled row without a caption, the first other displayed text

  `main.lua` polls the returned text widget for changes.
- **Extra text.** Up to three other displayed texts follow the label,
  for example a disabled row's "Cannot be changed from this screen." notice.
  Button-prompt icon markup is passed through for the speech icon parser.
- **Rows of any class.** A setting row needs no class allow-list. The live
  subtitle-background rows are `WBP_OBJ_Option_List_012_TextAlpha_C`, which the
  old allow-list missed, so only their value ("0") was spoken.

## Return contract

`GetSpokenLabel(widget)` still returns:
`label, matchedWidget, initialValue, valueTextWidget, valueReader`.

- A titled widget returns its value and that value's text widget.
  `ReadWidgetTexts(matchedWidget)` returns the same label, so `main.lua` queues
  the value after it.
- Without a title, the label is the caption or first text. Its text widget is
  returned for change polling, and `ReadWidgetTexts` returns no title, so the
  label is not repeated.
- Language rows are unchanged. They use the native `Title` and the live image
  reader from `language_options.lua` (see [language options](language-options.md)).

## Evidence

- Live paths follow `Owner.WidgetTree_<id>.Child` (language screen captures,
  candidate 6 coverage log).
- `GetParent`, `GetVisibility` and `GetOuter` work live
  (`language-values-20261003.txt`, `language-names-20261003.txt`).
  `IsVisible`, which the reader calls, has been used live throughout the mod.
  The language row's `Disable` overlay is Collapsed (visibility 1).
- The candidate 6 tree walk read nested `WidgetTree` text live on the title,
  dialog and tutorial screens.
- On the same screens, IsVisible-only dumps listed hidden debug and placeholder
  texts, while the effective-visibility walk did not.
- Candidate 11 verified `RemoteButton` live on the Battle Training top screen:
  `WBP_OBJ_Common_HitButton_0` points to `WBP_OBJ_CSG_BTN_01` (Close-Range
  Maneuvers), and `_1` points to `WBP_OBJ_CSG_BTN_00` (Select Training Type).
  Both initial focus and Up/Down changes read the correct live captions.
- The later 21:30 user session exposed a delayed initialization: the initial
  hit area had no readable caption, but its native link worked after the user
  moved focus. `tests/focus_caption_ready_test.lua` reproduces delayed link
  and caption creation, bounded retries and cancellation on both loader APIs.

## Tests

`tests/widget_reader_test.lua` runs the real helpers, reader and language
modules against a simulated UMG hierarchy. It covers both loader query paths,
with readable and unreadable widget trees. The previous reader fails all of its
cases. Each of these targeted mutations makes at least one case fail:

- ignoring switcher pages
- ignoring opacity
- checking only the widget's own visibility
- borrowing from farther lists
- dropping extra text
- dropping the name fallback for list position
- ignoring the native caption
- preferring nested titles
- keeping the placeholder
- accepting detached widgets
- substring scoping

## Still to validate live

- Options rows with a disabled notice:
  - an enabled row must not announce "Cannot be changed from this screen."
  - a disabled row should announce it
- Stage, BGM and rule lists: the label and "X of Y" on every row.
- Controls and key-binding rows: the label plus the displayed binding.
- Native remote-caption links on other menus and deeper training lists.
- Text inside ListView or DynamicEntryBox containers below a focused widget
  is not walked. These containers are not panels.
