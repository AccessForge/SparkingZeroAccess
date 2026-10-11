package.path = './SparkingZeroAccess/?.lua;' .. package.path
local AD = require('audio_description')
local events, mode = {}, 'closed'
local backend = {}
for _, name in ipairs({'play', 'pause', 'resume', 'stop'}) do
    backend[name] = function(file)
        events[#events + 1] = name .. (file and ':' .. file or '')
        mode = name == 'play' and 'playing' or name == 'resume' and 'playing' or name == 'pause' and 'paused' or 'closed'
        return true
    end
end
backend.mode = function() return mode end
local manifest = {['op3.usm'] = {fps = 30, totalFrames = 300, cues = {
    {at = 1, untilTime = 3, file = 'one.wav'},
    {at = 5, untilTime = 7, file = 'two.wav'},
}}}
local reader = AD.New(backend, manifest, function() end)
local function movie(t, paused)
    return {url = 'file://Movies/OP3.usm', player = 'visible-player', fps = 30,
        totalFrames = 300, seconds = t, playing = true, paused = paused or false}
end
local function reset() reader:Reset(); events = {} end
reader:Update(movie(0), 0)
assert(#events == 0)
reader:Update(movie(1.1), 1.1)
reader:Update(movie(1.2), 1.2)
assert(table.concat(events, '|') == 'play:one.wav')
print('PASS: a current cue starts once from the matching visible movie clock')
reader:Update(movie(1.3, true), 1.3)
reader:Update(movie(1.3, true), 2)
reader:Update(movie(1.4), 2.1)
assert(table.concat(events, '|') == 'play:one.wav|pause|resume')
print('PASS: pause and resume preserve a cue without restarting its words')
reader:Update(movie(3), 3.7)
assert(events[#events] == 'stop')
print('PASS: a cue cannot run beyond its approved scene window')
reset(); reader:Update(movie(2), 2)
assert(#events == 0)
reader:Update(movie(5.1), 5.1)
assert(events[#events] == 'play:two.wav')
print('PASS: late attachment skips missed narration and reaches the next cue')
reader:Update(nil, 5.2)
assert(events[#events] == 'stop')
print('PASS: leaving or skipping the movie cancels narration immediately')
reset(); reader:Update(movie(1.1), 1.1)
reader:Update(movie(0), 1.3)
reader:Update(movie(1.1), 2.4)
assert(table.concat(events, '|') == 'play:one.wav|stop|play:one.wav')
print('PASS: replaying the movie resets narration timing')
reset(); local wrong = movie(1.1); wrong.totalFrames = 301
reader:Update(wrong, 1.1)
wrong = movie(1.1); wrong.url = 'another.usm'; reader:Update(wrong, 1.1)
assert(#events == 0)
print('PASS: a different movie or revision cannot play these descriptions')
reset(); reader:Update(movie(1.1), 1.1)
reader:Update(movie(1.1), 1.7)
reader:Update(movie(1.2), 1.8)
assert(table.concat(events, '|') == 'play:one.wav|pause|resume')
print('PASS: a stalled native clock pauses audio until frames advance again')
reset(); backend.play = function() error('device lost') end
assert(pcall(function() reader:Update(movie(1.1), 1.1) end))
print('PASS: audio device failures do not escape into screen reading')

local lateEvents, messages = {}, {}
local late = AD.New({play = function(file) lateEvents[#lateEvents + 1] = file; return true end},
    {['op3.usm'] = {fps = 30, totalFrames = 300, cues = {
        {at = 1, untilTime = 3, duration = 1, file = 'short.wav'},
    }}}, function(message) messages[#messages + 1] = message end)
late:Update(movie(1.7), 1.7)
assert(lateEvents[1] == 'short.wav', 'a delayed poll lost a cue that still fits its visible scene')
late:Reset(); lateEvents, messages = {}, {}
late:Update(movie(2.8), 2.8)
assert(#lateEvents == 0 and #messages == 1 and messages[1]:find('skipped', 1, true))
print('PASS: late cues play only if the whole clip fits, and missed scenes are logged')

messages = {}
local malformed = AD.New(backend, {['op3.usm'] = {fps = 30, totalFrames = 300,
    cues = {false, {at = 2, untilTime = 1, file = 'bad.wav'}}}},
    function(message) messages[#messages + 1] = message end)
assert(pcall(function() malformed:Update(movie(1), 1) end))
assert(#messages == 1, 'bad manifest must be rejected once, without per-poll errors')
assert(malformed:Film(movie(1)) == nil)
print('PASS: malformed cue data is rejected without crashing or flooding the reader')

local installed = AD.New(backend, require('description_manifest'), function() end)
for _, resolution in ipairs({'1K', '2K', '4K'}) do
    local current = {url = 'file://Movies/Korat_OP3_' .. resolution .. '_CP.usm',
        fps = 30, totalFrames = 2717}
    local film = installed:Film(current)
    assert(film and #film.cues == 19, 'missing OP3 narration for ' .. resolution)
    assert(film.cues[1].file == 'AudioDescription/op3-01.wav')
    current.totalFrames = 2557
    assert(installed:Film(current) == nil, 'resolution alias accepted another film timing')
    current.totalFrames, current.fps = 2717, 60
    assert(installed:Film(current) == nil, 'resolution alias accepted another frame rate')
end
print('PASS: reviewed opening narration matches every resolution while rejecting different timing')

for _, resolution in ipairs({'1K', '2K', '4K'}) do
    local current = {url = 'file://Movies/Korat_OP2_' .. resolution .. '_CP.usm',
        fps = 30, totalFrames = 2557}
    local film = installed:Film(current)
    assert(film and #film.cues == 18, 'missing post-tutorial narration for ' .. resolution)
    assert(film.cues[1].file == 'AudioDescription/op2-01.wav')
    current.totalFrames = 2717
    assert(installed:Film(current) == nil, 'post-tutorial narration accepted main opening timing')
end
print('PASS: post-tutorial movie uses its own narration at every resolution')

local released = require('description_manifest')
for name, film in pairs(released) do
    local played, skipped, currentTime = {}, {}, 0
    local clocked = AD.New({
        play = function(file)
            played[#played + 1] = {file = file, at = currentTime}; return true
        end,
        stop = function() return true end,
        mode = function() return 'playing' end,
    }, released, function(message)
        if message:find('skipped', 1, true) then skipped[#skipped + 1] = message end
    end)
    local current = {url = 'file://Movies/' .. name, fps = film.fps,
        totalFrames = film.totalFrames, player = 'current', playing = true}
    for tick = 0, math.floor(film.totalFrames / film.fps * 4) do
        currentTime = tick * 0.25 + 0.249
        current.seconds = currentTime
        clocked:Update(current, currentTime)
    end
    assert(#skipped == 0 and #played == #film.cues, name .. ': polling dropped a released cue')
    for i, event in ipairs(played) do
        local cue = film.cues[i]
        assert(event.file == cue.file and event.at >= cue.at)
        assert(event.at + cue.duration <= cue.untilTime, name .. ': narration outlasts its scene')
    end
end
print('PASS: every released movie cue fits the regular 250 ms poll at all resolutions')
