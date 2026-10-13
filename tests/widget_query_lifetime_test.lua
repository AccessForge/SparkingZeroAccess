-- Build 1152 call_ufunction_from_lua retains each Out table in the registry.
-- Model that binding behavior while exercising the real helper query path.
package.path = './SparkingZeroAccess/?.lua;' .. package.path
LoopInGameThreadWithDelay = function() end
local H = require('helpers')
local retained, source, failQuery = {}, {}, false
local function object(class, name)
    local o = {class = class, name = name}
    function o:IsValid() return true end
    function o:type() return 'UObject' end
    function o:GetFullName() return self.class .. ' /Engine/Transient.' .. self.name end
    return o
end
local world, userClass = object('GameInstance', 'world'), object('Class', 'UserWidget')
local library = object('WidgetBlueprintLibrary', 'library')
function library:GetAllWidgetsOfClass(context, out, class, topOnly)
    assert(context == world and class == userClass)
    retained[#retained + 1] = out -- make_ref; no unref in this loader's binding.
    assert(next(out) == nil, 'stale output serialized back into the native input array')
    for i, widget in ipairs(source) do out[i] = widget end
    if failQuery then error('interrupted native query') end
end
FindFirstOf = function() return world end
FindObjects = function() return {} end
StaticFindObject = function(path)
    if path == '/Script/UMG.Default__WidgetBlueprintLibrary' then return library end
    if path == '/Script/UMG.UserWidget' then return userClass end
end
local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then print('PASS: ' .. name) else failures = failures + 1; print('FAIL: ' .. name .. ': ' .. tostring(err)) end
end
test('completed queries release widget references despite the loader retaining Out tables', function()
    local weak = setmetatable({}, {__mode = 'v'})
    for i = 1, 30 do
        source = {object('WBP_Transient_C', 'old_' .. i)}
        weak[i] = source[1]
        H.BeginReadCycle()
        local current = H.FindAllOf('UserWidget')
        assert(current[1] == source[1], 'current widget was omitted')
    end
    source = {}
    H.BeginReadCycle()
    collectgarbage('collect')
    local alive = 0
    for i = 1, 30 do if weak[i] then alive = alive + 1 end end
    assert(alive == 0, 'native output tables retained ' .. alive .. ' obsolete widgets')
end)
test('repeated queries retain bounded scratch storage and preserve independent fresh results', function()
    retained = {}
    source = {object('WBP_Menu_C', 'first')}
    H.BeginReadCycle()
    local first = H.FindAllOf('UserWidget')
    for i = 1, 100 do
        source = {object('WBP_Menu_C', 'next_' .. i)}
        H.BeginReadCycle()
        assert(H.FindAllOf('UserWidget')[1] == source[1])
        assert(H.GetViewportRoots()[1] == source[1])
    end
    assert(first[1].name == 'first', 'later native queries mutated an earlier returned list')
    local distinct, count = {}, 0
    for _, out in ipairs(retained) do
        if not distinct[out] then distinct[out] = true; count = count + 1 end
        assert(next(out) == nil, 'a completed query left widgets in retained native scratch storage')
    end
    assert(count <= 2, 'query storage grew with polling: ' .. count .. ' retained output tables')
end)
test('a partial native query failure also releases scratch widgets before fallback', function()
    source = {object('WBP_Menu_C', 'partial')}
    failQuery = true
    H.BeginReadCycle()
    assert(#H.FindAllOf('UserWidget') == 0, 'native failure did not use the ordinary fallback')
    assert(next(retained[#retained]) == nil, 'failed native query retained partial widget results')
    failQuery = false
    H.BeginReadCycle()
    assert(H.FindAllOf('UserWidget')[1] == source[1], 'native queries did not recover')
end)
assert(failures == 0, tostring(failures) .. ' widget query lifetime failures')
