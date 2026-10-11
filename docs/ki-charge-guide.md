# Ki-charge guide reading

The battle skill/button guide reads once during a hold of ki charge. Releasing
and holding charge again allows it to read again. Blinking or rebuilt copies of
the same guide text stay quiet during that hold. A new visible choice still
reads once, so newly displayed information remains available.

F6 reads the current visible guide immediately, including choices already read
during the hold. Tutorial instructions keep their twenty-second reminders.

The reader uses the game's Charge action and the actual player's native guide
widget, so keyboard/controller remapping does not require a fixed key binding.
It reads only text present in the captured, attached UI. A failure to establish
the native input or guide association leaves ordinary screen reading enabled.

Native research for game version 3022.021.003.012.015 identified
SSCharacter.IsBattleKeyPressed and GetBattleKeyHoldTime with Charge action 11,
and the battle HUD's P1SkillGuideWidget/P2SkillGuideWidget or indexed
GetSkillGuideSetOfPlayer getter. Native queries run in the existing screen poll,
only after battle HUD gauges establish a player baseline. The existing battle
HUD poll refreshes the player reference; screen reading adds no player-object
search. HUD references are revalidated and guide/input values are read fresh;
no new poll, file IO or Out-parameter table is added to ordinary reading. An
unavailable native binding logs one diagnostic per reason per battle.

F5 screen diagnostics include the charge state and associated guide when the
screen or held state changes. The timer does not cause extra diagnostic writes
on every poll. F5 is off by default.

Automated replays cover guide reconstruction, release/re-press, a new visible
choice, character changes, both player sides, the alternative native HUD root,
unavailable input, F6 and tutorial reminders. In an October 10, 2026 offline
training listening test, the player confirmed that the guide reads once per hold
and F6 still repeats it. No F5 native-state capture was recorded in that session;
the exact live input-to-guide association and player-two/controller coverage
remain separate from this listening result. Which listed moves can be used while
actively charging still needs a gameplay check; this change preserves the visible
guide.
