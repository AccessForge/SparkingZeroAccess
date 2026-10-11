package.path = "./SparkingZeroAccess/?.lua;" .. package.path

local phase, reads, unsafe, now = "worker", 0, 0, 1
local loops, queue, keys = {}, {}, {}
local realClock, realExecute, realOpen = os.clock, os.execute, io.open
os.clock = function() return now end
os.execute = function() end
io.open = function() return {write = function() end, close = function() end} end
LoopAsync = function(ms, fn) loops[#loops + 1] = fn end
ExecuteInGameThread = function(fn) queue[#queue + 1] = fn end
RegisterKeyBind = function(key, fn) keys[key] = fn end
Key = {F3 = 3, F4 = 4, F5 = 5}
local function recordRead()
    reads = reads + 1
    if phase ~= "game" then unsafe = unsafe + 1 end
end
FindAllOf = function() recordRead(); return {} end
FindObjects = function() recordRead(); return {} end
FindFirstOf = function() recordRead() end
StaticFindObject = function() recordRead() end
local function tick()
    phase = "worker"
    for _, fn in ipairs(loops) do fn() end
    phase = "game"
    local ready = queue
    queue = {}
    for _, fn in ipairs(ready) do fn() end
end

local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then print("PASS: " .. name)
    else failures = failures + 1; print("FAIL: " .. name .. ": " .. tostring(err)) end
end

local Debug = require("debug_tools")
Debug.Init(function() end)
test("debug hotkeys defer object reads to the game thread", function()
    phase = "worker"
    keys[Key.F3](); keys[Key.F4]()
    assert(unsafe == 0, "debug hotkey accessed game objects on the input thread")
    tick()
    assert(reads > 0, "debug request never inspected objects")
end)
test("the continuous debug dump also uses the game thread", function()
    unsafe = 0
    phase = "worker"
    keys[Key.F5]()
    now = 2
    tick()
    assert(unsafe == 0, "continuous dump accessed game objects on the worker")
    keys[Key.F5]()
end)
test("team captions do not nest ExecuteInGameThread calls", function()
    require("helpers").BeginReadCycle()
    local Team = require("team_overview")
    phase = "game"
    local beforeReads, beforeQueue = reads, #queue
    Team.RequestHoldButtonCaptions()
    assert(#queue == beforeQueue, "caption read enqueued a nested game-thread action")
    assert(reads > beforeReads, "caption read did not run")
end)

local GameThread = require("game_thread")
test("old-map delayed widget reads are discarded", function()
    local oldRead = false
    GameThread.After(1500, "Old dialog", function() oldRead = true end)
    GameThread.PauseForMapLoad()
    now = 20
    tick()
    GameThread.ResumeAfterMapLoad(0.8)
    now = 21
    tick()
    assert(not oldRead, "delayed callback retained an old-map widget")
end)
test("one failing reader does not disable the other readers", function()
    local goodCalls = 0
    GameThread.Every(100, "Expected test error", function() error("test stale widget") end)
    GameThread.Every(100, "Healthy reader", function() goodCalls = goodCalls + 1 end)
    now = 22; tick()
    now = 23; tick()
    assert(goodCalls == 2, "a Lua error stopped healthy readers")
end)

os.clock, os.execute, io.open = realClock, realExecute, realOpen
assert(failures == 0, tostring(failures) .. " deferred read regressions")
