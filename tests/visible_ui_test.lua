-- Removing ancestor, switcher, viewport, or live-value checks must fail these cases.
package.path = './SparkingZeroAccess/?.lua;' .. package.path
local H = require('helpers')
local UI = require('visible_ui')
local widgets = {}
local function node(class, name, children, text)
    local n = {class = class, name = name, children = children or {}, text = text,
        valid = true, visible = true, RenderOpacity = 1}
    function n:IsValid() return self.valid end
    function n:GetFullName() return self.class .. ' /Engine/Transient.' .. self.name end
    function n:IsVisible() return self.visible end
    function n:GetChildrenCount() return #self.children end
    function n:GetChildAt(i) return self.children[i + 1] end
    function n:GetText() return {ToString = function() return self.text end} end
    function n:IsInViewport() return self.viewport == true end
    function n:GetActiveWidgetIndex() return self.active end
    return n
end
local function user(name, content, viewport)
    local n = node('WBP_' .. name .. '_C', name)
    n.WidgetTree = {RootWidget = content}
    n.viewport = viewport
    widgets[#widgets + 1] = n
    return n
end
local function capture()
    H.FindAllOf = function(class) assert(class == 'UserWidget'); return widgets end
    return UI.Capture()
end
local function texts(snapshot)
    local out = {}
    for _, entry in ipairs(snapshot.entries) do if entry.text then out[#out + 1] = entry.text end end
    return table.concat(out, '|')
end
local cases = {
    {'reads nested user widgets in display-tree order without keyboard focus', function()
        widgets = {}
        local inner = user('Controls', node('VerticalBox', 'rows', {
            node('TextBlock', 'action', nil, 'Guard'),
            node('RichTextBlock', 'key', nil, '<icon id="Key_16" table="Windows"/>'),
        }), false)
        user('Screen', node('CanvasPanel', 'canvas', {node('TextBlock', 'heading', nil, 'Controls'), inner}), true)
        assert(texts(capture()) == 'Controls|Guard|<icon id="Key_16" table="Windows"/>')
    end},
    {'never reads a hidden or transparent ancestor or inactive switcher page', function()
        widgets = {}
        local hidden = node('CanvasPanel', 'hidden', {node('TextBlock', 'secret', nil, 'hidden')})
        hidden.visible = false
        local transparent = node('CanvasPanel', 'transparent', {node('TextBlock', 'fade', nil, 'invisible')})
        transparent.RenderOpacity = 0
        local switch = node('WidgetSwitcher', 'pages', {
            node('TextBlock', 'old', nil, 'old page'), node('TextBlock', 'new', nil, 'current page')})
        switch.active = 1
        user('Screen', node('CanvasPanel', 'canvas', {hidden, transparent, switch}), true)
        assert(texts(capture()) == 'current page')
    end},
    {'excludes detached screens and destroyed widgets', function()
        widgets = {}
        user('Detached', node('TextBlock', 'stale', nil, 'stale'), false)
        local dead = node('TextBlock', 'destroyed', nil, 'destroyed'); dead.valid = false
        user('Screen', node('CanvasPanel', 'canvas', {dead, node('TextBlock', 'live', nil, 'live')}), true)
        assert(texts(capture()) == 'live')
    end},
    {'rereads changing tutorial text and newly visible pages', function()
        widgets = {}
        local label = node('TextBlock', 'instruction', nil, 'Move forward')
        local page = node('CanvasPanel', 'page', {label})
        user('Tutorial', page, true)
        assert(texts(capture()) == 'Move forward')
        label.text = 'Guard against an attack'
        assert(texts(capture()) == 'Guard against an attack')
        page.visible = false; assert(texts(capture()) == '')
        page.visible = true; assert(texts(capture()) == 'Guard against an attack')
    end},
    {'image evidence is collected without inventing a spoken texture label', function()
        widgets = {}
        local image = node('Image', 'control_image')
        image.Brush = {ResourceObject = node('Texture2D', 'Key_Unknown')}
        user('Controls', image, true)
        local snapshot = capture()
        assert(texts(snapshot) == '')
        assert(snapshot.entries[1].image:find('Key_Unknown', 1, true))
    end},
    {'widget cycles terminate and report incomplete traversal', function()
        widgets = {}
        local loop = node('CanvasPanel', 'loop'); loop.children = {loop}
        user('Screen', loop, true)
        local snapshot = capture()
        assert(#snapshot.warnings > 0)
    end},
    {'text outside a scroll viewport is not exposed until scrolled into view', function()
        widgets = {}
        local library = {IsValid = function() return true end,
            GetAbsoluteSize = function(_, geometry) return {X = geometry.w, Y = geometry.h} end,
            LocalToAbsolute = function(_, geometry) return {X = geometry.x, Y = geometry.y} end}
        StaticFindObject = function(path) if path == '/Script/UMG.Default__SlateBlueprintLibrary' then return library end end
        local function rect(widget, x, y, width, height)
            widget.geometry = {x = x, y = y, w = width, h = height}
            function widget:GetCachedGeometry() return self.geometry end
        end
        local first = node('TextBlock', 'first', nil, 'First row'); rect(first, 0, 0, 100, 20)
        local second = node('TextBlock', 'second', nil, 'Second row'); rect(second, 0, 120, 100, 20)
        local scroll = node('ScrollBox', 'scroll', {first, second}); rect(scroll, 0, 0, 100, 100)
        local root = user('Screen', scroll, true); rect(root, 0, 0, 800, 600)
        assert(texts(capture()) == 'First row')
        first.geometry.y = -120; second.geometry.y = 0
        assert(texts(capture()) == 'Second row')
        root.geometry.w, root.geometry.h = 0, 0
        assert(texts(capture()) == 'Second row', 'unavailable root geometry must not suppress a readable tree')
        StaticFindObject = nil
    end},
}
for _, case in ipairs(cases) do case[2](); print('PASS: ' .. case[1]) end
