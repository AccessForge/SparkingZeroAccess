# Automatic subtitle speech

Press **F9** to turn automatic subtitle reading off or on. The reader announces
the new state and saves it for the next launch. A fresh installation starts with
subtitle reading on. An invalid preference also leaves reading on.

The setting controls dialogue text and speaker names in the game's confirmed
subtitle windows, including main-menu character banter, battle dialogue, and
Episode Battle text. With it off, text-only story narration in those windows
also needs a manual read. The subtitles remain visible on screen.

Menu choices, character selection, help and control text, battle HUD speech,
20-second tutorial reminders, and movie audio description continue to work.
Continue and skip button prompts remain automatic. **F6** reads all currently
visible screen text, including subtitles; **F7/F8** review individual items.
Turning subtitle reading back on resumes with new lines rather than replaying
dialogue that appeared while it was off.

The preference is a small `SparkingZeroAccess-subtitles.ini` file beside the
shipping executable, in `SparkingZERO/Binaries/Win64`. It contains only
`AutomaticSubtitles=true` or `AutomaticSubtitles=false`. The installer preserves
it, and the test ZIP does not contain the developer's preference. A save failure
is announced; the toggle still works for that session.

The filter uses exact native dialogue ownership and text fields, rather than
matching the spoken words. Confirmed classes are `WBP_OBJ_Common_TextWindow_C`,
`WBP_OBJ_Common_TexWin_Black_C`, `WBP_GRP_Common_EventText_C`, and
`WBP_MainMenu_Base_TextSub_C`. It filters dialogue/name leaves only, preserving
other text in the same window. Unknown text stays readable. Manual review and
diagnostic capture remain complete.

The generic screen reader and the separate Episode Battle subtitle reader share
the preference. Loading and saving happen only at startup and on F9, respectively.
There is no extra widget query or polling loop. The game's subtitle-background
sliders adjust the backdrop; they do not suppress these dialogue lines. CRI's
`ManaComponent.EnableSubtitles` controls embedded movie subtitle tracks, which
are separate from the game's native text windows.

Regression checks cover persistence, spoken toggle feedback, mixed subtitle and
instruction screens, class boundaries, manual review, unchanged/changed dialogue,
tutorial reminders, and the separate episode reader's continue prompt. Live
listening verification is recorded separately in the test package.
