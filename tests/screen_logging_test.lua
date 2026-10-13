package.path = './SparkingZeroAccess/?.lua;' .. package.path
local UI=require('visible_ui')
local Movie=require('movie_reader')
local Reader=require('screen_reader')
local realOpen=io.open
local writes, current, keys, jobs, events = {}, 'Guard', {}, {}, {}
io.open=function(path)
    return {write=function(_,data) writes[#writes+1]={path=path,data=data} end,close=function() end}
end
Movie.Capture=function() end
UI.Capture=function()
    return {roots={{path='screen'}},nodes={},warnings={},
        entries={{path='instruction',text=current,ancestry='/WBP_Tutorial_C'}}}
end
Key={F3=3,F4=4,F5=5,F6=6,F7=7,F8=8}
RegisterKeyBind=function(key,fn) keys[key]=fn end
Reader.Init(function() end,function() end)
local failures=0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then print('PASS: '..name) else failures=failures+1; print('FAIL: '..name..': '..tostring(err)) end
end
test('normal screen polling performs no diagnostic file writes',function()
    for i=1,20 do Reader.Poll() end
    assert(#writes==0,'normal polling wrote detailed screen dumps')
end)
test('explicit screen logging captures changes only and stops immediately',function()
    writes={}; Reader.SetLogging(true); Reader.Poll()
    assert(#writes==1 and writes[1].data:find('Guard',1,true))
    for i=1,20 do Reader.Poll() end
    assert(#writes==1,'unchanged screens were repeatedly dumped')
    current='Charge'; Reader.Poll(); assert(#writes==2)
    Reader.SetLogging(false); current='Dash'; Reader.Poll(); assert(#writes==2)
end)
test('F5 controls both the debug dump and the visible screen log on the game thread',function()
    local GT=require('game_thread')
    GT.After=function(_,_,fn) jobs[#jobs+1]=fn end
    GT.Every=function() return function() end end
    local logging=Reader.SetLogging
    Reader.SetLogging=function(enabled) events[#events+1]=enabled end
    local Debug=require('debug_tools'); Debug.Init(function() end)
    keys[Key.F5](); assert(#events==0,'F5 changed logging on the input thread')
    jobs[1](); assert(events[1]==true)
    keys[Key.F5](); jobs[2](); assert(events[2]==false)
    Reader.SetLogging=logging
end)
io.open=realOpen
assert(failures==0,tostring(failures)..' screen logging failures')
