-- Replays visible skill-guide changes through the real passive screen reader.
-- Native references are represented by the paths that visible_ui captures;
-- no test claims to validate the UE4SS binding or controller input itself.
package.path = './SparkingZeroAccess/?.lua;' .. package.path
local Reader = require('screen_reader')

local function snapshot(holdTime, suffix, text, options)
    options = options or {}
    local guide = options.guide or 'hud.skillGuide'
    local rows = options.hidden and {} or {
        {path = guide .. '.row' .. suffix .. '.name', text = text or 'Holy Wrath',
            parent = guide .. '.row' .. suffix, owner = guide .. '.row' .. suffix},
        {path = guide .. '.row' .. suffix .. '.button', text = 'X',
            parent = guide .. '.row' .. suffix, owner = guide .. '.row' .. suffix},
    }
    local nodes = {
        {path = 'hud', class = 'WBP_BattleHUD_C'},
        {path = guide, parent = 'hud'},
        {path = guide .. '.row' .. suffix, parent = guide},
    }
    for _, row in ipairs(rows) do nodes[#nodes + 1] = row end
    return {entries = rows, nodes = nodes, roots = {{path = 'hud'}}, warnings = {},
        kiCharge = holdTime and {pawn = options.pawn or 'player1', guide = guide,
            held = holdTime > 0, holdTime = holdTime} or nil}
end

local function heard(s, now) return table.concat(Reader.Update(s, now), '. ') end

Reader.Reset()
assert(heard(snapshot(0.2, 'a'), 1) == '')
assert(heard(snapshot(0.5, 'a'), 1.3) == 'Holy Wrath. X')
Reader.Update(snapshot(1.2, 'a', nil, {hidden = true}), 2)
Reader.Update(snapshot(1.5, 'b'), 2.3)
assert(heard(snapshot(1.8, 'b'), 2.6) == '',
    'a rebuilt skill guide repeated while the same charge button was held')
print('PASS: a blinking or rebuilt guide reads once during one charge hold')

Reader.Update(snapshot(0, 'b'), 3)
Reader.Update(snapshot(0.1, 'b'), 3.1)
assert(heard(snapshot(0.4, 'b'), 3.4) == 'Holy Wrath. X',
    'a new charge hold did not read the unchanged visible guide again')
print('PASS: release and a new hold read the unchanged guide again')

Reader.Update(snapshot(0.7, 'c', 'Super Explosive Wave'), 3.7)
assert(heard(snapshot(1, 'c', 'Super Explosive Wave'), 4) == 'Super Explosive Wave',
    'a newly displayed choice was lost or an unchanged button repeated')
Reader.Update(snapshot(1.3, 'd'), 4.3)
assert(heard(snapshot(1.6, 'd'), 4.6) == '',
    'an earlier guide choice repeated when it returned during the same hold')
print('PASS: new visible choices read once without replaying previously read guide text')

Reader.Update(snapshot(0.1, 'd'), 5)
assert(heard(snapshot(0.4, 'd'), 5.3) == 'Holy Wrath. X',
    'a release and re-press between snapshots were missed')
print('PASS: the native hold timer detects a new hold between captures')

Reader.Update(snapshot(0.6, 'e', nil, {pawn = 'player2'}), 5.6)
assert(heard(snapshot(0.9, 'e', nil, {pawn = 'player2'}), 5.9) == 'Holy Wrath. X',
    'changing the actual player character kept the previous guide muted')
print('PASS: a different player character receives its own guide reading')

Reader.Reset()
local s = snapshot(0.2, 'a')
s.entries[#s.entries + 1] = {path = 'lesson', text = 'Hold ki charge', tutorial = true}
s.entries[#s.entries + 1] = {path = 'outside', text = 'Holy Wrath'}
Reader.Update(s, 10)
heard(s, 10.3)
Reader.Update(snapshot(0.5, 'a', nil, {hidden = true}), 11)
s = snapshot(0.8, 'b')
s.entries[#s.entries + 1] = {path = 'outside2', text = 'Holy Wrath'}
Reader.Update(s, 11.3)
assert(heard(s, 11.6) == 'Holy Wrath', 'a label outside the native skill-guide subtree was muted')
s.entries[#s.entries + 1] = {path = 'lesson', text = 'Hold ki charge', tutorial = true}
Reader.Update(s, 12)
assert(heard(s, 12.3) == 'Hold ki charge')
assert(heard(s, 32.4) == 'Hold ki charge', 'tutorial reminders stopped repeating after twenty seconds')
print('PASS: guide filtering preserves other visible labels and twenty-second tutorial reminders')

Reader.Reset()
Reader.Update(snapshot(nil, 'a'), 40)
assert(heard(snapshot(nil, 'a'), 40.3) == 'Holy Wrath. X')
Reader.Update(snapshot(nil, 'a', nil, {hidden = true}), 41)
Reader.Update(snapshot(nil, 'b'), 41.3)
assert(heard(snapshot(nil, 'b'), 41.6) == 'Holy Wrath. X',
    'unknown native charge state silently suppressed visible guide information')
print('PASS: unavailable native charge state leaves the visible information readable')

Reader.Reset()
Reader.Update(snapshot(0.1, 'a'), 45)
heard(snapshot(0.4, 'a'), 45.3)
Reader.Reset(true)
Reader.Update(snapshot(0.7, 'b'), 46)
assert(heard(snapshot(1, 'b'), 46.3) == '',
    'recovering a focused widget replayed the guide during an unchanged native charge hold')
print('PASS: focus-reader recovery preserves the current charging hold')

for _, timer in ipairs({{value = 0}, {}}) do
    Reader.Reset()
    local first = snapshot(0, 'a')
    first.kiCharge.held, first.kiCharge.holdTime = true, timer.value
    Reader.Update(first, 47)
    assert(heard(first, 47.3) == 'Holy Wrath. X')
    local rebuilt = snapshot(0, 'b')
    rebuilt.kiCharge.held, rebuilt.kiCharge.holdTime = true, timer.value
    Reader.Update(rebuilt, 48)
    assert(heard(rebuilt, 48.3) == '', 'a zero or unavailable timer reset a confirmed held charge')
end
print('PASS: a confirmed held charge stays quiet with a zero or unavailable hold timer')

Reader.Reset()
Reader.Update(snapshot(0.1, 'a'), 50)
heard(snapshot(0.4, 'a'), 50.3)
Reader.Reset()
Reader.Update(snapshot(0.7, 'a'), 51)
assert(heard(snapshot(1, 'a'), 51.3) == 'Holy Wrath. X',
    'a screen/map reset kept the previous charging session muted')
print('PASS: screen/map reset clears guide repetition history')
