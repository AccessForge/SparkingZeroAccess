# Character names

The original reader identified a roster portrait correctly but looked its name
up in a fixed community list. On the tested current build, 31 of the 67 character
IDs observed in one session were absent from that list. Owning the character did
not change that lookup. The team-list branch could also stay silent for an
unrecognized portrait.

The repaired reader identifies the selected slot from its portrait and reads
the matching loaded SSCharacterDataAsset. The game's native name plate uses the
record's NameInfo.ShortName and NameInfo.TitleName; these fields were verified
against the current executable in Ghidra. The asset directory was also verified
in the installed game's asset registry. Names use the game's current language.
The old table remains a fallback when the record is unavailable.

The asset lookup uses the class and short name together through
[UE4SS FindObjects](https://docs.ue4ss.com/dev/lua-api/global-functions/findobjects.html).
The full-path lookup is a fallback, attempted once per character until reset.
Only live asset references are cached; localized names are read again from the
record. Missing assets are retried with a half-second minimum interval.

The visible name plate itself can lag behind focus and temporarily show the
previous character. It therefore cannot safely identify a newly focused slot.
The selected portrait is also watched for changes, so paging the roster or
editing a team updates speech even if the hit button keeps keyboard focus.
These reads run on the existing game-thread dispatch and reuse the selected
Image reference. They do not add an all-object polling loop. A missing name
is retried briefly even if its portrait is already loaded. Retries stop after
12 attempts and reuse the portrait reference. If the focused list's own image
is missing, another list instance cannot supply its character or team total.

The icon's own question-mark and Free textures are announced as those visible
states. Other final pictures are reported as unrecognized instead of staying
on "Loading character". A portrait left blank for three seconds is reported
unavailable once. If its name arrives later, the correction is queued so it
does not interrupt the team context. Returning focus to a team-list slot
announces it again.

Unknown DP values are not guessed. A team summary counts members once every
slot is identified as a character or empty. It omits both count and total while
any slot is unresolved, and announces total DP only when every member's value
is known. New badges, proficiency stars, and DP values absent from the old
table need further work.

The character integration checks run the real reader modules against both
supported loader APIs. Live listening verification is still needed for the
new names, roster paging, team edits, and the second player's team screen.
