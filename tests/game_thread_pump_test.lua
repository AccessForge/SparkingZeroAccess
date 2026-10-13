package.path='./SparkingZeroAccess/?.lua;'..package.path
local workerCalls, oneShots, pump, interval = 0, 0, nil, nil
EngineTickAvailable=true
LoopInGameThreadWithDelay=function(ms,fn) interval,pump=ms,fn; return 99 end
LoopAsync=function() workerCalls=workerCalls+1 end
ExecuteInGameThread=function() oneShots=oneShots+1 end
local now=10
local realClock=os.clock
os.clock=function() return now end
local H=require('helpers')
local cycles=0
H.BeginReadCycle=function() cycles=cycles+1 end
local GT=require('game_thread')
local failures=0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then print('PASS: '..name) else failures=failures+1; print('FAIL: '..name..': '..tostring(err)) end
end
test('the current loader retains one game-thread pump without per-frame callback registration',function()
    GT.Every(16,'Fast reader',function() end)
    GT.Every(100,'Slow reader',function() end)
    assert(type(pump)=='function' and interval==16,'no persistent native pump')
    for i=1,500 do now=now+0.017; pump() end
    assert(workerCalls==0 and oneShots==0 and cycles==500,'per-frame callbacks still cross worker threads')
end)
test('a delayed or missed pump frame does not strand future reader jobs',function()
    local read=0
    GT.Every(16,'Surviving reader',function() read=read+1 end)
    assert(type(pump)=='function','no persistent native pump')
    now=now+0.05; pump()
    now=now+10 -- no callback serviced during a blocked frame
    now=now+0.017; pump()
    now=now+0.017; pump()
    assert(read==3,'reader remained waiting for a discarded one-shot')
end)
test('map teardown discards delayed references and resumes the existing pump',function()
    local oldRead,newRead=0,0
    GT.After(100,'Old map',function() oldRead=oldRead+1 end)
    GT.PauseForMapLoad()
    assert(type(pump)=='function','no persistent native pump')
    now=now+3; pump()
    GT.ResumeAfterMapLoad(.8)
    GT.After(0,'New map',function() newRead=newRead+1 end)
    now=now+.9; pump()
    assert(oldRead==0 and newRead==1,'map pause lost the pump or retained old objects')
end)
os.clock=realClock
assert(failures==0,tostring(failures)..' game-thread pump failures')
