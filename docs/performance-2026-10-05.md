# Candidate 17 performance and reader continuity repair

The supplied candidate 16 logs came from game version 3022.021.003.012.015
with UE4SS 3.0.1-1152-ge3ba1016. Dispatch timings commonly averaged 20-30 ms,
with recorded spikes up to 3.5 seconds. The last session ended with
`[Lua::Registry::get_function_ref] Ref was not function` and no subsequent
reader activity. The player reports that all speech, including F6, remains
silent until restart. The log does not prove which native callback lost its
reference.

The reader now asks Unreal for attached viewport roots, then follows their
native widget trees. It no longer enumerates all allocated UserWidget objects
and their full names before reading a screen. Text, focus, visibility, active
switcher pages and nested controls are still read live. A same-process comparison
returned the identical three attached roots: the old discovery took 6-7 ms and
the new query took 0-1 ms at the timer's one-millisecond resolution.

Story-map polling first checks for an attached, visible chart. An absent or
retained hidden chart triggers no global text scan. On an active chart its five
fields share one text walk, matched to that chart's native object path. Changing
nodes, saga, chapter and Dragon Orb information remain readable.

Detailed screen-coverage files are now opt-in with F5. The same key starts and
stops the ordinary debug dump and the visible screen log on the game thread.
Unchanged screens do not rebuild their full diagnostic text. UE4SS startup,
speech and error messages remain available in the normal loader log.

The packaged current loader runs the reader through one persistent engine-tick
callback. This removes per-frame registration from the asynchronous worker.
The former worker waited for each one-shot callback to clear its pending flag;
a discarded native callback could leave that flag set indefinitely. Persistent
jobs preserve map-load pauses and discard delayed references from old maps.
The ProcessEvent fallback also uses the persistent native API. Older loaders
without that API retry a discarded one-shot after two seconds, with at most one
recovery request outstanding. This avoids an unbounded backlog during a blocked
game. Two lost legacy requests in a row remain a limitation; the supplied package
includes the modern loader.

An unused native TextBlock:SetText hook was removed. It captured a name that had
no reader callers and entered Lua for every scripted text update. Character and
team names still come from native character records and portraits.

On a local title-screen comparison, visible-screen capture fell from about
9.7 ms to 2.4 ms per call, and story-map polling fell from about 4 ms to below
0.2 ms per call. These are reader timings, not rendered frame rates. Temporary
profiling adds measurement overhead. They do not establish performance on every
PC or prove the reported rapid-menu failure is resolved.

The player tested rapid menu movement and training and reported that the game
was responsive and speech kept working. In a second launch, character selection
names and F6 screen text still read. That launch's lighter job-only profiler
measured dense-grid screen captures at about 27-30 ms per call, including spikes
around 100-120 ms. Remaining capture cost is measurable; this release does not
claim zero overhead or guaranteed performance on the friend's PC. The game
closed normally and reader timings continued until closure.

An independent two-thread Lua 5.4 model reproduced the friend's final empty print
and invalid registry-reference error with the former cross-thread dispatcher.
Five two-minute persistent-loop runs completed without callback reference errors,
including heavy simulated text-hook traffic. The model uses the loader source;
it is not a test of the actual shipped DLL. An unused text hook and repeated
registration were removed from normal use, and lost-frame regression tests keep
the final focused menu item readable.

Native API names and the current executable fingerprint were checked in Ghidra.
No game executable bytes or object offsets were changed. The persistent callback
uses the documented loader API:
https://docs.ue4ss.com/dev/lua-api/global-functions/delayedactions.html.

The performance regressions cover nested native widget trees, visibility and
attachment changes, absent/hidden story charts, fresh story fields, diagnostic
logging, missed pump frames, and map teardown. Live listening and rapid-navigation
results above supplement 266 passing Lua checks and syntax checks for all 22
modules. The temporary profilers are excluded from the release.
