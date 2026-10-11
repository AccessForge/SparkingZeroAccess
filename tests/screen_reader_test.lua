package.path = './SparkingZeroAccess/?.lua;' .. package.path
local Reader = require('screen_reader')
local function entry(path, text, ancestry)
    return {path = path, text = text, ancestry = ancestry or '/WBP_Tutorial_C',
        root = 'screen', rootClass = 'WBP_Screen_C', owner = 'instruction', ownerClass = 'WBP_Tutorial_C'}
end
local function snapshot(entries, nodes) return {entries = entries, nodes = nodes or {}, roots = {{path = 'screen'}}, warnings = {}} end
Reader.Reset()
local s = snapshot({entry('a', 'Move forward')})
assert(#Reader.Update(s, 1) == 0)
assert(table.concat(Reader.Update(s, 1.3), '|') == 'Move forward')
assert(#Reader.Update(s, 2) == 0)
s.entries[1].text = 'Guard'
assert(#Reader.Update(s, 3) == 0)
assert(table.concat(Reader.Update(s, 3.3), '|') == 'Guard')
print('PASS: instructions announce once and update without any focus change')
Reader.Update(snapshot({}), 4)
Reader.Update(s, 5)
assert(table.concat(Reader.Update(s, 5.3), '|') == 'Guard')
print('PASS: reopening an instruction announces it again')
Reader.Reset()
s = snapshot({entry('focus.label', 'Guard'), entry('detail', 'Hold to block')}, {{path = 'focus', focused = true}})
s.entries[1].parent = 'focus'
Reader.Update(s, 1)
assert(table.concat(Reader.Update(s, 1.3), '|') == 'Hold to block')
print('PASS: focus speech is not duplicated while unfocused instructions remain readable')
Reader.Reset()
s = snapshot({entry('dialog', 'Saving', '/WBP_Dialog_000_C'), entry('n', '40999'), entry('help', 'Press confirm')})
Reader.Update(s, 1)
assert(table.concat(Reader.Update(s, 1.3), '|') == 'Press confirm')
print('PASS: existing dialog reader and rapidly changing numeric HUD values are not duplicated')
Reader.Reset()
s = snapshot({entry('a', 'Old page')})
Reader.Update(s, 1)
s = snapshot({entry('b', 'New page')})
Reader.Update(s, 1.1)
assert(table.concat(Reader.Update(s, 1.4), '|') == 'New page')
print('PASS: a dismissed page cannot leave delayed announcements')

local UI = require('visible_ui')
local spoken, binds, worker, dispatch = {}, {}
Key = {F6 = 117, F7 = 118, F8 = 119}
RegisterKeyBind = function(key, callback) binds[key] = callback end
LoopAsync = function(_, callback) worker = callback end
ExecuteInGameThread = function(callback) dispatch = callback end
UI.Capture = function() return snapshot({entry('row1', 'Guard'), entry('row2', 'Charge')}) end
local canRead = true
Reader.Init(function(text) spoken[#spoken + 1] = text end, function() end, function() return canRead end)
binds[Key.F6]()
assert(#spoken == 0, 'hotkey accessed the screen before game-thread dispatch')
worker(); dispatch()
assert(spoken[1] == 'Guard. Charge')
binds[Key.F8](); worker(); dispatch()
assert(spoken[2] == 'Charge, 2 of 2')
binds[Key.F7](); worker(); dispatch()
assert(spoken[3] == 'Guard, 1 of 2')
print('PASS: F6/F7/F8 read and review the current screen on the game thread')
UI.Capture = function()
    return snapshot({{path = 'movie', image = 'MaterialInstanceDynamic /Game/Map.SSCriMediaPlayer_1.Material_1'}})
end
binds[Key.F6](); worker(); dispatch()
assert(spoken[4]:lower():find('video', 1, true), 'a movie surface must not be reported as an empty screen')
assert(spoken[4]:lower():find('audio description', 1, true))
print('PASS: F6 identifies a video that needs description when it has no UMG text')
local movie = require('movie_reader')
local capture, clock = movie.Capture, os.clock
movie.Capture = function() error('movie property disappeared') end
UI.Capture = function() return snapshot({entry('instruction', 'Hold Guard')}) end
local queued = {}
Reader.Init(function() end, function(text) queued[#queued + 1] = text end)
Reader.Reset()
os.clock = function() return 10 end
Reader.Poll()
os.clock = function() return 10.3 end
Reader.Poll()
assert(queued[1] == 'Hold Guard', 'a movie probe failure must not silence the visible screen')
movie.Capture, os.clock = capture, clock
print('PASS: movie clock failures do not silence visible instructions')

local audioEvents = {}
package.loaded.audio_bridge, package.loaded.description_manifest = nil, nil
package.preload.audio_bridge = function()
    return {
        play = function(file) audioEvents[#audioEvents + 1] = 'play:' .. file; return true end,
        stop = function() audioEvents[#audioEvents + 1] = 'stop'; return true end,
        mode = function() return 'playing' end,
    }
end
package.preload.description_manifest = function()
    return {['test.usm'] = {fps = 30, totalFrames = 300, title = 'Test opening',
        cues = {{at = 1, untilTime = 3, file = 'test.wav'}}}}
end
local currentMovie = {player = 'visible-player', url = 'file://test.usm',
    fps = 30, totalFrames = 300, seconds = 1.1, playing = true}
movie.Capture = function() return currentMovie end
UI.Capture = function()
    return snapshot({{path = 'movie', image = 'MaterialInstanceDynamic /Game/Map.SSCriMediaPlayer_1.Material_1'}})
end
spoken = {}
Reader.Init(function(text) spoken[#spoken + 1] = text end, function() end, function() return true end)
Reader.Poll()
assert(audioEvents[1] == 'play:test.wav', 'visible native movie did not start its description')
binds[Key.F6](); worker(); dispatch()
assert(spoken[1]:find('Audio description is enabled', 1, true), 'F6 incorrectly reports a described film as unavailable')
Reader.Reset(true)
assert(#audioEvents == 1, 'an unrelated focus reset interrupted movie narration')
print('PASS: recovering the focused widget does not interrupt current movie narration')
Reader.Reset()
assert(audioEvents[#audioEvents] == 'stop', 'map reset left narration playing')
print('PASS: screen polling plays matched descriptions, F6 reports them, and reset stops them')

Reader.Poll()
movie.Capture = function() error('movie disappeared during playback') end
Reader.Poll()
assert(audioEvents[#audioEvents] == 'stop', 'a lost movie clock left narration running')
movie.Capture = capture
print('PASS: losing the native movie stops narration without breaking the screen reader')
