-- A friend log must identify the slow job without a separate profiling build.
package.path = './SparkingZeroAccess/?.lua;' .. package.path
local now, pump, lines = 20, nil, {}
local realClock, realPrint = os.clock, print
os.clock = function() return now end
print = function(line) lines[#lines + 1] = line end
EngineTickAvailable = true
LoopInGameThreadWithDelay = function(_, fn) pump = fn; return 1 end
local H = require('helpers')
H.BeginReadCycle = function() end
local GT = require('game_thread')
local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then realPrint('PASS: ' .. name) else failures = failures + 1; realPrint('FAIL: ' .. name .. ': ' .. tostring(err)) end
end
local function count(text)
    local total = 0
    for _, line in ipairs(lines) do if line:find(text, 1, true) then total = total + 1 end end
    return total
end
test('a long reader job is named once per reporting window while the pump keeps working', function()
    local calls = 0
    GT.Every(16, 'Visible screen text', function() calls = calls + 1; now = now + .075 end)
    for i = 1, 12 do now = now + .02; pump() end
    assert(calls == 12, 'stall reporting disabled the reader job')
    assert(count('Slow reader job: Visible screen text') == 1, 'slow job attribution is missing or floods the log')
    now = now + 11; pump()
    assert(count('Slow reader job: Visible screen text') == 2, 'subsequent stalls were not reported')
    assert(count('Lua heap') > 0, 'the normal performance report cannot distinguish memory growth')
end)
test('a slow failing job reports its error and later jobs remain serviced', function()
    local survived = 0
    GT.After(0, 'Faulting reader', function() now = now + .06; error('lost native read') end)
    GT.After(0, 'Next reader', function() survived = survived + 1 end)
    now = now + .02; pump()
    assert(survived == 1, 'stall reporting interrupted later jobs')
    assert(count('Faulting reader error:') == 1 and count('Slow reader job: Faulting reader') == 1,
        'failure and slow-job attribution were not both preserved')
end)
test('a major stall is attributed even after a smaller stall in the same reporting window', function()
    local elapsed = .06
    local cancel = GT.Every(16, 'Growing stall', function() now = now + elapsed end)
    now = now + .02; pump()
    elapsed = 5
    now = now + .1; pump()
    cancel()
    assert(count('Slow reader job: Growing stall') == 2, 'the five-second stall was hidden by the earlier minor report')
end)
os.clock, print = realClock, realPrint
assert(failures == 0, tostring(failures) .. ' reader stall diagnostic failures')
