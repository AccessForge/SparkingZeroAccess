-- UObject reads belong on the game thread. Modern loaders retain one native
-- pump; the legacy worker only requests service and never inspects objects.
local GameThread = {}
local H = require("helpers")
local jobs, delayed = {}, {}
local pending, started, paused = false, false, false
local pendingSince = 0
local legacyRetryUsed = false
local LEGACY_CALLBACK_TIMEOUT = 2
local generation, resumeAt = 0, 0
local firstPollCompleted = false
local timing = {count = 0, total = 0, maximum = 0, lastReport = os.clock()}
local slowJobReports = {}

local function Run(label, callback)
    local startedAt = os.clock()
    local ok, result = pcall(callback)
    local finishedAt = os.clock()
    local elapsed = finishedAt - startedAt
    if label ~= 'Reader dispatch' and elapsed >= 0.05
        and (elapsed >= 1 or not slowJobReports[label] or finishedAt - slowJobReports[label] >= 10) then
        slowJobReports[label] = finishedAt
        print(string.format('[AE] Slow reader job: %s %.1f ms; Lua heap %.1f MB',
            label, elapsed * 1000, collectgarbage('count') / 1024))
    end
    if not ok then print("[AE] " .. label .. " error: " .. tostring(result)) end
    return ok and result == true
end

local function Service()
    local now = os.clock()
    if paused or now < resumeAt then return end
    H.BeginReadCycle()

    local ready = delayed
    delayed = {}
    for _, job in ipairs(ready) do
        if job.generation == generation then
            if now >= job.due then Run(job.label, job.callback)
            else delayed[#delayed + 1] = job end
        end
    end
    for _, job in ipairs(jobs) do
        if job.active and now >= job.due then
            -- Skip missed frames instead of replaying old UI announcements.
            job.due = now + job.interval
            if Run(job.label, job.callback) then job.active = false end
        end
    end
    for i = #jobs, 1, -1 do
        if not jobs[i].active then table.remove(jobs, i) end
    end
    if not firstPollCompleted then
        firstPollCompleted = true
        print("[AE] First game-thread polling cycle completed")
    end
end

local function Dispatch()
    local startedAt = os.clock()
    Run("Reader dispatch", Service)
    pending = false
    legacyRetryUsed = false
    local finishedAt = os.clock()
    local elapsed = finishedAt - startedAt
    timing.count = timing.count + 1
    timing.total = timing.total + elapsed
    timing.maximum = math.max(timing.maximum, elapsed)
    if finishedAt - timing.lastReport >= 10 then
        print(string.format("[AE] Reader timing: %.2f ms average, %.2f ms maximum, %d cycles; Lua heap %.1f MB",
            timing.total * 1000 / timing.count, timing.maximum * 1000, timing.count,
            collectgarbage('count') / 1024))
        timing = {count = 0, total = 0, maximum = 0, lastReport = finishedAt}
    end
end

local function Start()
    if started then return end
    started = true
    -- Current UE4SS keeps this callback in one native loop. A discarded
    -- one-shot previously left pending=true forever, disabling every reader.
    -- It also created a fresh Lua registry reference from the worker each tick.
    if type(LoopInGameThreadWithDelay) == 'function'
        and (EngineTickAvailable == true or ProcessEventAvailable == true) then
        LoopInGameThreadWithDelay(16, Dispatch)
        print('[AE] Persistent game-thread reader loop active')
        return
    end
    LoopAsync(16, function()
        local now = os.clock()
        if paused or now < resumeAt then return false end
        if pending then
            if legacyRetryUsed or now - pendingSince < LEGACY_CALLBACK_TIMEOUT then return false end
            -- A native registry failure can consume a one-shot without calling
            -- Dispatch. Retry it; if the original was merely delayed, each job's
            -- due time still prevents duplicate reads in that frame.
            print('[AE] Retrying a missing legacy reader callback')
            legacyRetryUsed = true
        end
        pending = true
        pendingSince = now
        local ok, err = pcall(ExecuteInGameThread, Dispatch)
        if not ok then
            pending = false
            legacyRetryUsed = false
            print("[AE] Unable to schedule reader: " .. tostring(err))
        end
        return false
    end)
end

function GameThread.Every(milliseconds, label, callback)
    local job = {interval = milliseconds / 1000, due = 0, label = label, callback = callback, active = true}
    jobs[#jobs + 1] = job
    Start()
    return function() job.active = false end
end

function GameThread.After(milliseconds, label, callback)
    delayed[#delayed + 1] = {due = os.clock() + milliseconds / 1000,
        generation = generation, label = label, callback = callback}
    Start()
end

function GameThread.PauseForMapLoad()
    paused = true
    generation = generation + 1
    delayed = {} -- callbacks may hold references to the map being destroyed
end

function GameThread.ResumeAfterMapLoad(seconds)
    resumeAt = os.clock() + seconds
    paused = false
end

return GameThread
