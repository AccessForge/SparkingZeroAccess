package.path='./SparkingZeroAccess/?.lua;'..package.path
local realClock=os.clock
local failures=0
local function harness(native)
    package.loaded.game_thread=nil
    local h={now=1,queue={},worker=nil,pump=nil,reads=0,requests=0}
    os.clock=function() return h.now end
    LoopAsync=function(_,fn) h.worker=fn end
    ExecuteInGameThread=function(fn) h.requests=h.requests+1; h.queue[#h.queue+1]=fn end
    if native then EngineTickAvailable=false else EngineTickAvailable=nil end
    ProcessEventAvailable=native and true or nil
    LoopInGameThreadWithDelay=native and function(_,fn) h.pump=fn end or nil
    h.GT=require('game_thread')
    h.GT.Every(16,'Recovered focus',function() h.reads=h.reads+1 end)
    function h:dispatch()
        local ready=self.queue; self.queue={}
        for _,fn in ipairs(ready) do fn() end
    end
    return h
end
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then print('PASS: '..name) else failures=failures+1; print('FAIL: '..name..': '..tostring(err)) end
end
test('a discarded legacy one-shot recovers without restarting the game',function()
    local h=harness(false)
    h.worker(); h.queue={} -- the loader consumed a bad callback reference
    h.now=3.1; h.worker(); h:dispatch()
    assert(h.reads==1,'legacy reader stayed waiting for a lost callback')
    h.now=3.2; h.worker(); h:dispatch()
    assert(h.reads==2)
end)
test('a delayed legacy callback cannot duplicate due reader work or build a backlog',function()
    local h=harness(false)
    h.worker()
    for i=1,50 do h.now=1+i*.01; h.worker() end
    assert(h.requests==1,'short delay queued a backlog')
    h.now=3.1; h.worker()
    assert(h.requests==2,'long delay was never rearmed')
    h:dispatch(); assert(h.reads==1,'late and replacement callbacks replayed the same job')
    h.now=3.2; h.worker(); h:dispatch(); assert(h.reads==2)
end)
test('legacy recovery respects a map pause and discards old delayed references',function()
    local h=harness(false)
    h.worker(); h.queue={}
    local stale=false
    h.GT.After(100,'Old widget',function() stale=true end)
    h.GT.PauseForMapLoad(); h.now=20; h.worker()
    assert(h.requests==1,'map pause rearmed unsafe polling')
    h.GT.ResumeAfterMapLoad(.8); h.now=21; h.worker(); h:dispatch()
    assert(h.reads==1 and not stale,'map pause lost recovery or retained old references')
end)
test('a blocked legacy game has at most one recovery request outstanding',function()
    local h=harness(false)
    h.worker()
    for i=1,200 do h.now=1+i; h.worker() end
    assert(h.requests<=2,'recovery accumulated callbacks while the game was blocked')
    h:dispatch(); assert(h.reads==1,'a blocked game replayed reader work')
    h.now=h.now+.02; h.worker(); h:dispatch(); assert(h.reads==2)
end)
test('the modern ProcessEvent fallback also uses a persistent pump',function()
    local h=harness(true)
    assert(type(h.pump)=='function' and not h.worker,'ProcessEvent used cross-thread one-shots')
    for i=1,20 do h.now=h.now+.02; h.pump() end
    assert(h.reads==20 and h.requests==0)
end)
os.clock=realClock
assert(failures==0,tostring(failures)..' dispatcher recovery failures')
