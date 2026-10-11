-- Exercise the real reader startup against UE4SS scheduling boundaries.
-- Run from the repository root with Lua 5.4 or LuaJIT.
package.path = "./SparkingZeroAccess/?.lua;" .. package.path

local realClock = os.clock
local function harness(legacyLoader)
    local h = {now = 1, phase = "startup", loops = {}, queue = {}, reads = 0, unsafe = 0}
    os.clock = function() return h.now end
    local function noop() end
    EngineTickAvailable = not legacyLoader and true or nil
    LoopInGameThreadWithDelay = not legacyLoader and function(_, callback)
        h.pump = callback
        h.pumpCount = (h.pumpCount or 0) + 1
        return 1
    end or nil
    for _, name in ipairs({"helpers", "poll_trackers", "game_thread", "main"}) do
        package.loaded[name] = nil
    end
    for _, name in ipairs({"widget_reader", "team_overview", "chara_roster", "skill_list", "battle", "episode_battle", "shop"}) do
        package.loaded[name] = setmetatable({}, {__index = function() return noop end})
    end
    package.loaded.speech = {Init = noop, IsLoaded = function() return true end, Speak = noop, SpeakQueued = noop}
    package.loaded.debug_tools = {Init = noop}
    LoopAsync = function(ms, callback)
        h.loops[#h.loops + 1] = {callback = callback, ms = ms}
    end
    ExecuteInGameThread = function(callback) h.queue[#h.queue + 1] = callback end
    ExecuteWithDelay = function(ms, callback)
        h.loops[#h.loops + 1] = {callback = callback, ms = ms}
    end
    RegisterLoadMapPreHook = function(callback) h.pre = callback end
    RegisterLoadMapPostHook = function(callback) h.post = callback end
    local function read()
        h.reads = h.reads + 1
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
    end
    local gi = {IsValid = function() read(); return true end}
    local widgetClass = {IsValid = function() read(); return true end}
    local widgetLibrary = {IsValid = function() read(); return true end,
        GetAllWidgetsOfClass = function() read() end}
    StaticFindObject = function(path)
        read()
        return path == "/Script/UMG.Default__WidgetBlueprintLibrary" and widgetLibrary or widgetClass
    end
    FindObjects = function() read(); return {widgetClass} end
    FindFirstOf = function(name) read(); if name == "GameInstance" then return gi end end
    FindAllOf = function() read(); return {} end
    function h:async()
        self.phase = "worker"
        local count = #self.loops
        for i = 1, count do self.loops[i].callback() end
    end
    function h:game()
        self.phase = "game"
        if self.pump then self.pump() end
        local queue = self.queue
        self.queue = {}
        for _, callback in ipairs(queue) do callback() end
    end
    assert(loadfile("SparkingZeroAccess/main.lua"))()
    return h
end

local cases = {
    {"stock 3.0.1 never registers its broken pre-load callback", function()
        local h = harness(true)
        assert(h.pre == nil, "registered a pre-load callback on an incompatible loader")
        assert(type(h.post) == "function", "post-load reset was lost")
    end},
    {"object scans execute on the game thread", function()
        local h = harness()
        h:async()
        assert(h.unsafe == 0, "reader touched Unreal objects from an async callback")
        h:game()
        assert(h.reads > 0, "reader never inspected game objects")
    end},
    {"a long map load stays paused until the post hook", function()
        local h = harness()
        h.phase = "game"
        h.pre()
        local before = h.reads
        h.now = 20 -- substantially longer than the old five-second cooldown
        h:async(); h:game()
        assert(h.reads == before, "reader accessed objects while the map was still loading")
        h.post()
        h.now = 21
        h:async(); h:game()
        assert(h.reads > before, "reader did not resume after map load")
    end},
    {"a busy game cannot accumulate reader callbacks", function()
        local h = harness()
        for i = 1, 100 do h.now = i; h:async() end
        assert(#h.queue == 0, "modern reader accumulated one-shot callbacks")
        h:game()
        assert(h.reads > 0, "pending reader callback did not run")
    end},
    {"slow frames do not create duplicate polling loops", function()
        local h = harness()
        local count = #h.loops
        local pumps = h.pumpCount
        h.now = 20
        h:game()
        assert(#h.loops == count, "a watchdog created extra reader loops")
        assert(h.pumpCount == pumps, "a slow frame created extra native pumps")
    end},
}

local failures = 0
for _, case in ipairs(cases) do
    local ok, err = pcall(case[2])
    if ok then print("PASS: " .. case[1])
    else failures = failures + 1; print("FAIL: " .. case[1] .. ": " .. tostring(err)) end
end
os.clock = realClock
assert(failures == 0, tostring(failures) .. " reader lifecycle regressions")
