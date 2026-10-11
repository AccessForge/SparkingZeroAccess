-- Focus moves must be read live without enumerating unrelated allocated widgets.
package.path = './SparkingZeroAccess/?.lua;' .. package.path
LoopInGameThreadWithDelay = function() end
local H = require('helpers')
local roots, childReads, globalQueries = {}, 0, 0
H.GetViewportRoots = function() return roots, true end
H.FindAllOf = function() globalQueries = globalQueries + 1; error('global focus enumeration') end
H.IsUserWidget = function(widget) return widget.WidgetTree ~= nil end
local function node(name, children, user)
    local widget = {name = name, children = children or {}, valid = true, visible = true, RenderOpacity = 1}
    function widget:IsValid() return self.valid end
    function widget:GetFullName() return 'Widget /Engine/Transient.' .. self.name end
    function widget:IsVisible() return self.visible end
    function widget:IsInViewport() return self.viewport == true end
    function widget:HasKeyboardFocus() return self.focus == true end
    function widget:HasFocusedDescendants()
        if self.missingAPI then return nil end
        local list = self.WidgetTree and {self.WidgetTree.RootWidget} or self.children
        for _, child in ipairs(list) do
            if child.focus or child:HasFocusedDescendants() then return true end
        end
        return false
    end
    function widget:GetChildrenCount() return #self.children end
    function widget:GetChildAt(index) childReads = childReads + 1; return self.children[index + 1] end
    function widget:GetActiveWidgetIndex() return self.active end
    if user then widget.WidgetTree = {RootWidget = node(name .. '_canvas', children)} end
    return widget
end
local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then print('PASS: ' .. name) else failures = failures + 1; print('FAIL: ' .. name .. ': ' .. tostring(err)) end
end
-- The reader does not yet have a tree focus path. Treat absence as a red result.
local ok, Focus = pcall(require, 'focus_reader')
if not ok then Focus = {Find = function() return nil, false end} end
test('an unfocused battle screen touches only its roots', function()
    local children = {}
    for i = 1, 2000 do children[i] = node('unrelated_' .. i) end
    local screen = node('battle', children, true); screen.viewport = true
    roots, childReads = {screen}, 0
    local focused, supported = Focus.Find()
    assert(supported and focused == nil, 'native no-focus result was not supported')
    assert(childReads == 0 and globalQueries == 0, 'no-focus battle still enumerated allocated widgets')
end)
test('rapid focus movement reaches the final nested user widget', function()
    local left, right = node('left', nil, true), node('right', nil, true)
    local owner = node('menu', {node('padding'), left, right}, true); owner.viewport = true
    roots = {owner}
    for i = 1, 41 do
        left.focus, right.focus = i % 2 == 1, i % 2 == 0
        local expected = left.focus and left or right
        local focused, supported = Focus.Find()
        assert(supported and focused == expected, 'focus traversal returned a stale or missing item')
    end
end)
test('hidden or destroyed owners and inactive switcher pages cannot supply focus', function()
    local stale, current = node('inactive', nil, true), node('current', nil, true)
    stale.focus, current.focus = true, true
    local switcher = node('switcher', {stale, current}); switcher.active = 1
    function switcher:GetFullName() return 'WidgetSwitcher /Engine/Transient.switcher' end
    local owner = node('menu', {switcher}, true); owner.viewport = true
    roots = {owner}
    assert(Focus.Find() == current, 'an inactive page supplied the focus')
    owner.visible = false; assert(Focus.Find() == nil); owner.visible = true
    owner.valid = false; assert(Focus.Find() == nil)
end)
test('unsupported native focus APIs explicitly request the existing compatibility scan', function()
    local owner = node('old_loader', nil, true); owner.viewport = true; owner.missingAPI = true
    roots = {owner}
    local focused, supported = Focus.Find()
    assert(focused == nil and supported == false, 'unavailable API was mistaken for a reliable no-focus result')
end)
test('a replaced viewport is searched afresh instead of retaining its old focus', function()
    local old, new = node('old', nil, true), node('new', nil, true)
    old.viewport, new.viewport, old.focus, new.focus = true, true, true, true
    roots = {old}; assert(Focus.Find() == old)
    roots = {new}; old.valid = false; assert(Focus.Find() == new)
end)
test('a native focused branch outside the UMG children requests the compatibility scan', function()
    local host = node('native_slate_host'); host.viewport = true
    function host:HasFocusedDescendants() return true end
    roots = {host}
    local focused, supported = Focus.Find()
    assert(focused == nil and supported == false, 'an unreachable focused branch was reported as definite no-focus')
end)
test('focus excluded by a transparent ancestor is distinguished from an unreachable branch', function()
    local selected = node('fading_selected', nil, true); selected.focus = true
    local owner = node('fading_menu', {selected}, true); owner.viewport = true; owner.RenderOpacity = 0
    roots = {owner}
    local focused, supported = Focus.Find()
    assert(focused == nil and supported == true, 'intentionally hidden focus requested an unrelated global scan')
    owner.RenderOpacity = 1
    assert(Focus.Find() == selected, 'focus did not return when the same live screen became visible')
end)
test('truncated child enumeration cannot silently report that no focus exists', function()
    local children = {}
    for i = 1, 4097 do children[i] = node('many_' .. i, nil, true) end
    children[4097].focus = true
    local owner = node('wide_menu', children); owner.viewport = true
    roots = {owner}
    local focused, supported = Focus.Find()
    assert(focused == nil and supported == false, 'a safety limit silently hid native focus')
end)
assert(failures == 0, tostring(failures) .. ' focus tree failures')
