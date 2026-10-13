package.path = './SparkingZeroAccess/?.lua;' .. package.path
local H = require('helpers')
local UI = require('visible_ui')
LoopInGameThreadWithDelay = function() end
local fullQueries, rootQueries, hiddenReads = 0, 0, 0
local function object(class, name, children, text)
    local o = {class=class, name=name, children=children or {}, text=text, RenderOpacity=1}
    function o:IsValid() return self.dead ~= true end
    function o:type() return 'UObject' end
    function o:GetFullName() return self.class .. ' /Engine/Transient.' .. self.name end
    function o:IsVisible() return self.hidden ~= true end
    function o:IsInViewport() return self.viewport == true end
    function o:IsA() return self.WidgetTree ~= nil end
    function o:GetChildrenCount() return #self.children end
    function o:GetChildAt(index) return self.children[index+1] end
    function o:HasKeyboardFocus() return self.focus == true end
    function o:GetText() return {ToString=function() return self.text end} end
    return o
end
local world, coreClass = object('GameInstance','world'), object('Class','UserWidget')
local nested = object('ControlsPanel_C','nested')
nested.WidgetTree={RootWidget=object('TextBlock','action',nil,'Guard: Left Trigger')}
local root = object('WBP_Test_C','root')
root.WidgetTree={RootWidget=object('CanvasPanel','canvas',{nested})}
root.viewport=true
local detached = object('WBP_Hidden_C','unused')
function detached:GetFullName() hiddenReads=hiddenReads+1; return 'WBP_Hidden_C /Engine/Transient.unused' end
local roots, all = {root}, {root,nested,detached}
local library=object('WidgetBlueprintLibrary','library')
function library:GetAllWidgetsOfClass(context,out,class,topOnly)
    assert(context==world and class==coreClass)
    if topOnly then rootQueries=rootQueries+1 else fullQueries=fullQueries+1 end
    for i,w in ipairs(topOnly and roots or all) do out[i]=w end
end
FindFirstOf=function() return world end
StaticFindObject=function(path)
    if path=='/Script/UMG.Default__WidgetBlueprintLibrary' then return library end
    if path=='/Script/UMG.UserWidget' then return coreClass end
end
FindObjects=function(count,class) assert(count==0 and class=='UserWidget'); return all end
local function capture() H.BeginReadCycle(); return UI.Capture() end
local function text(snapshot)
    local result={}
    for _,row in ipairs(snapshot.entries) do if row.text then result[#result+1]=row.text end end
    return table.concat(result,'|')
end
local failures=0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then print('PASS: '..name) else failures=failures+1; print('FAIL: '..name..': '..tostring(err)) end
end
test('screen capture enumerates only viewport roots while reading nested native user widgets',function()
    assert(text(capture())=='Guard: Left Trigger')
    assert(rootQueries==1 and fullQueries==0 and hiddenReads==0,
        'screen capture still enumerated unneeded user widgets')
end)
test('a newly attached screen and changed text are read in the next cycle',function()
    root.WidgetTree.RootWidget.children[1].WidgetTree.RootWidget.text='Guard: Right Trigger'
    assert(text(capture())=='Guard: Right Trigger')
    roots={}
    assert(text(capture())=='')
    roots={root}
    assert(text(capture())=='Guard: Right Trigger')
end)
test('hidden roots, nested owners and destroyed roots never expose their text',function()
    nested.hidden=true; assert(text(capture())==''); nested.hidden=false
    root.hidden=true; assert(text(capture())==''); root.hidden=false
    root.dead=true; assert(text(capture())==''); root.dead=false
end)
test('the legacy loader preserves attached nested screen coverage',function()
    LoopInGameThreadWithDelay=nil
    H.InvalidateCachedFirstOf()
    assert(text(capture())=='Guard: Right Trigger')
end)
test('native text and image leaves avoid panel and unused geometry queries',function()
    local expensive=0
    local label=object('TextBlock','prompt',nil,'Hold Guard')
    local image=object('Image','checkmark')
    image.Brush={ResourceObject=object('Texture2D','visible_check')}
    for _,leaf in ipairs({label,image}) do
        function leaf:GetChildrenCount() expensive=expensive+1; error('not a panel') end
        function leaf:GetCachedGeometry() expensive=expensive+1; return {X=0,Y=0} end
    end
    local leafRoot=object('WBP_Lesson_C','lesson')
    leafRoot.WidgetTree={RootWidget=object('CanvasPanel','lesson_canvas',{label,image})}
    leafRoot.viewport=true
    all={leafRoot}; roots={leafRoot}
    StaticFindObject=function(path)
        if path=='/Script/UMG.Default__SlateBlueprintLibrary' then return object('SlateBlueprintLibrary','slate') end
        if path=='/Script/UMG.Default__WidgetBlueprintLibrary' then return library end
        if path=='/Script/UMG.UserWidget' then return coreClass end
    end
    local s=capture()
    assert(text(s)=='Hold Guard' and #s.entries==2,'leaf content was omitted')
    assert(expensive==0,'leaves performed panel or geometry calls without a clip rectangle')
end)
assert(failures==0,tostring(failures)..' viewport query failures')
