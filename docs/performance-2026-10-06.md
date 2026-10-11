# Candidate 18: widget-query memory lifetime

The new tester log runs for about 105 minutes. Speech and the retained native
reader callback continue, but some reader cycles last several seconds. The
largest recorded cycle is 57,240 ms. Detailed F5 logging was not enabled and
the previous invalid-callback-reference error did not recur. That log has no
per-job timings or heap samples, so it cannot alone identify the operation
responsible for every pause.

The UE4SS 3.0.1-1152 UFunction binding creates a registry reference for each
output table and does not release it. Its `DynamicUnrealFunctionOutParameters`
container has no cleanup destructor. Repeated `GetAllWidgetsOfClass` queries
therefore kept historical lists of Lua UObject wrappers alive. This is separate
from the candidate 17 callback-registration repair.

The reader now uses one temporary output table for each queried widget class
and query mode. It copies fresh, unwrapped UObject references into an independent
result list and empties the temporary table after success or failure. The input
table is also empty before each native call. Later queries cannot mutate an
earlier result list. No native registry entries are deleted, no displayed values
are cached, and no game executable or object offsets are changed.

The focus reader also starts at attached viewport roots and follows only native
`HasFocusedDescendants` branches until it finds the focused UserWidget. A battle
screen with no keyboard focus requires only root checks. Cached focus references
are still revalidated, and the existing global compatibility scan remains when
the native query or focus/tree APIs are unavailable. Hidden ancestors and inactive
switcher pages are excluded. This also reduces native output-array allocations.
Ghidra confirms these API registrations in the current executable. The native
comparison covered 180 samples while the player used the title, menus, Options
and character selection. All eight differences were old focus underneath a
hidden ancestor. The diagnostic checked native parents and opacity in the same
pass and shortly afterwards: fading parents returned to visible, with the focus
path intact. There were no missed visible choices or uncertain tree captures.
If native code reports focused descendants that the UMG walk cannot reach, the
reader explicitly falls back to the compatibility scan.

Regression tests first reproduced retained obsolete widgets, growing query
storage and partial output surviving a native error. They pass with the repair.
The normal loader log now names jobs taking at least 50 ms, limited to one line
per job per ten seconds, and includes the Lua heap size in its regular timing
report. Jobs lasting at least one second are always named, even after an earlier
minor stall in that reporting window. This gives testers useful evidence without
enabling F5 diagnostics.

The local pre-repair run reproduced approximately 950 MB of Lua heap after about
eleven minutes of menus and training. Dense character-selection captures still
cost approximately 27 ms each, with larger occasional spikes. A small private
probe separates query, capture, speech and polling costs. It is excluded from
the distributed package.

In the repaired local run, the sampled Lua heap stayed below 6 MB for about eleven
minutes and ended at 1.97 MB. Training reader cycles averaged about 1.2 ms; the
largest measured visible capture was 35 ms. The actual shipped native binding
retained 12/12 obsolete result lists with the old helper and 0/12 with the repaired
helper, returning the same 34 widgets. The player confirmed responsive rapid
navigation, F6 and training speech, then confirmed choices and character names
in the final build. These runs did not reproduce the earlier large Lua growth.

All 286 Lua checks and syntax checks for 23 modules pass, including native-path
integration, hidden ancestors, unreachable Slate branches and truncation safety.
All 17 installer checks pass in Windows PowerShell 5.1. The installer computes
streaming SHA-256 through built-in .NET APIs instead of depending on a shell
function that failed to resolve during the local install.

The final build is deployed. The long heap probe was archived; the short native
comparison removed its own callback after 180 samples. Its startup require and
module were then removed from disk, so subsequent launches are clean. The
running session uses the final production reader with no active diagnostic job.
The shared package excludes those private probes and their logs.
The repair does not establish zero overhead, eliminate every possible game
stall, or prove the cause of all multi-second events on another PC.
The loader still retains a small registry slot and native output-array storage
per query. The repair clears the much larger historical Lua widget payload and
avoids whole-widget focus queries on unfocused battle screens. The earlier dense
character-grid cost remains a relevant limit; the friend should retest a longer
session and send the normal loader log if pauses recur, leaving F5 off.

Relevant loader source:
https://github.com/UE4SS-RE/RE-UE4SS/blob/e3ba1016/UE4SS/src/LuaType/LuaUObject.cpp
and https://github.com/UE4SS-RE/RE-UE4SS/blob/e3ba1016/UE4SS/include/LuaType/LuaUFunction.hpp.
