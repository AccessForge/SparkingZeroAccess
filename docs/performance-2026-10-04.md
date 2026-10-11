# October 4, 2026 performance repair

The candidate 12 reader stalled on Steam build 24953175, displayed version
3022.021.003.012.015. This also reproduced the tester's report of immediate
slowdown. Its executable SHA256 is
`6DB7002A8FA66A1309B01037D8A9A8C678A8ECD35B72D4C6AFAC550A74371657`.
The version matches the publisher's September 4 update notice:
https://dbsz.bn-ent.net/information/?p=299.

## Cause and change

The reader resolves widget classes by name before asking Unreal for their
instances. Some classes do not exist on the current screen, so the reader
retries them. The old name-only lookup searched unrelated objects as well.
Several misses could coincide and stall a single reader dispatch.

Class resolution now limits the search to `Class` objects and derived types,
including `WidgetBlueprintGeneratedClass`. It still uses the engine's widget
query, includes derived widget instances, retries missing classes, invalidates
references across map changes, and reads displayed values live. Polling rates
and screen coverage are unchanged. An unrelated object sharing the requested
class name can no longer displace the class and force the slower fallback.

## Evidence and limits

A diagnostic launch compared both lookup methods in the same process for five
class names: two present classes and three absent classes. Both methods returned
the same object identities or absence. Name-only calls took 11-26 ms; class
filtered calls took 0-1 ms at the timer's one-millisecond resolution. Zero means
below that resolution, not zero cost.

The earlier profiled title-screen reader job typically took about 14-15 ms per
call. With class filtering, early title-screen samples were about 5-6 ms per
call. Other reader work remains measurable. These are reader timings, not
rendered FPS, and performance on another PC still needs testing.

There are 176 passing Lua checks, including a regression for a name collision
between a widget class and an unrelated object, array-output compatibility,
late class availability, cache invalidation and existing accessibility behavior.
The temporary profiling script is excluded from the release.

The current Steam executable was also imported into Ghidra and identified as
UE5.1. Older executable addresses must not be reused as current hook evidence.
The working loader configuration remains UE4SS 3.0.1-1152-ge3ba1016 with
`HookInitGameState=0`; the executable itself is not patched.
