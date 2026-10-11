package.path = './SparkingZeroAccess/?.lua;' .. package.path
local H = require('helpers')
local queries, chart, texts, spoken = {}, nil, {}, {}
local function widget(class,name,text)
    local o={class=class,name=name,text=text}
    function o:IsValid() return not self.dead end
    function o:GetFullName() return self.class..' /Engine/Transient.Chart.'..self.name end
    function o:IsVisible() return not self.hidden end
    function o:IsInViewport() return self.viewport == true end
    function o:GetOuter() return self.outer end
    function o:GetText() return {ToString=function() return self.text end} end
    return o
end
H.FindAllOf=function(class)
    queries[class]=(queries[class] or 0)+1
    if class=='WBP_GRP_AI_ChartTitle_C' then return chart and {chart} or {} end
    if class=='TextBlock' then return texts end
    return {}
end
local E=require('episode_battle')
E.Init(function(text) spoken[#spoken+1]=text end,function(text) spoken[#spoken+1]=text end)
local failures=0
local function test(name,fn)
    E.FullReset(); queries={}; spoken={}
    local ok,err=pcall(fn)
    if ok then print('PASS: '..name) else failures=failures+1; print('FAIL: '..name..': '..tostring(err)) end
end
test('an absent story map never scans global text widgets',function()
    chart=nil
    for i=1,100 do E.PollStoryMap() end
    assert(not queries.TextBlock,'idle screen scanned text widgets')
    assert(#spoken==0)
end)
test('detached and hidden chart owners never activate the story reader',function()
    chart=widget('WBP_GRP_AI_ChartTitle_C','chart')
    texts={widget('TextBlock','Text_ScenarioTitle_0','Goku saga')}
    E.PollStoryMap(); assert(#spoken==0 and not queries.TextBlock)
    chart.outer=widget('WBP_Story_C','screen'); chart.outer.viewport=true
    chart.outer.hidden=true
    E.PollStoryMap(); assert(#spoken==0 and not queries.TextBlock)
    chart.outer.hidden=false; chart.hidden=true
    E.PollStoryMap(); assert(#spoken==0 and not queries.TextBlock)
end)
test('visible story fields and changed nodes remain readable with one text scan per poll',function()
    chart=widget('WBP_GRP_AI_ChartTitle_C','chart'); chart.viewport=true
    function chart:GetFullName() return 'WBP_GRP_AI_ChartTitle_C /Engine/Transient.WBP_GRP_AI_ChartTitle_C_1' end
    texts={widget('TextBlock','Text_ScenarioTitle_0','Goku saga'),
        widget('TextBlock','Text_ScenarioTitle_1','Saiyan arc'),
        widget('TextBlock','Text_Chapter','Chapter 1'),
        widget('TextBlock','Text_EventTitle','Arrival'),
        widget('TextBlock','TXT_Orb','Dragon Orb available')}
    for _,tb in ipairs(texts) do
        tb.outer=chart
        function tb:GetFullName() return 'TextBlock /Engine/Transient.WBP_GRP_AI_ChartTitle_C_1.WidgetTree.'..self.name end
    end
    for i=1,8 do E.PollStoryMap() end
    assert(table.concat(spoken,'|'):find('Goku saga, Saiyan arc, Chapter 1',1,true))
    assert(table.concat(spoken,'|'):find('Dragon Orb available',1,true))
    local before=queries.TextBlock
    texts[4].text='Raditz battle'; E.PollStoryMap()
    assert(spoken[#spoken]=='Raditz battle')
    assert(queries.TextBlock==before+1,'story fields caused repeated global walks')
    chart.hidden=true; E.PollStoryMap(); assert(not E.IsStoryMapActive())
end)
test('numbered widget trees are read without mixing retained chart instances',function()
    chart=widget('WBP_GRP_AI_ChartTitle_C','chart'); chart.viewport=true
    function chart:GetFullName() return 'WBP_GRP_AI_ChartTitle_C /Engine/Transient.WBP_GRP_AI_ChartTitle_C_1' end
    local stale=widget('TextBlock','Text_ScenarioTitle_0','Hidden old saga')
    function stale:GetFullName() return 'TextBlock /Engine/Transient.WBP_GRP_AI_ChartTitle_C_11.WidgetTree.Text_ScenarioTitle_0' end
    stale.outer=chart
    local live=widget('TextBlock','Text_ScenarioTitle_0','Vegeta saga')
    function live:GetFullName() return 'TextBlock /Engine/Transient.WBP_GRP_AI_ChartTitle_C_1.WidgetTree_2147482000.Text_ScenarioTitle_0' end
    live.outer=chart; texts={stale,live}
    for i=1,8 do E.PollStoryMap() end
    assert(table.concat(spoken,'|'):find('Vegeta saga',1,true))
    assert(not table.concat(spoken,'|'):find('Hidden old saga',1,true))
end)
assert(failures==0,tostring(failures)..' story poll failures')
