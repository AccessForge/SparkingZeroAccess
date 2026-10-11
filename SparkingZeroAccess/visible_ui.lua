-- Read the attached UMG tree, not every allocated widget. Run on the game thread.
-- Text and visibility are read afresh on every capture. No UObject survives it.
local H = require('helpers')
local UI = {}
local Call, Property = H.TryCall, H.TryGetProperty
local geometryReported = false

local function Name(widget)
    return Call(widget, 'GetFullName')
end

local function Visible(widget)
    if not H.IsValidRef(widget) or Call(widget, 'IsVisible') ~= true then return false end
    local opacity = Property(widget, 'RenderOpacity')
    return type(opacity) ~= 'number' or opacity > 0.001
end

function UI.Capture()
    local snapshot = {roots = {}, entries = {}, nodes = {}, warnings = {}}
    local slate
    if type(StaticFindObject) == 'function' then
        local ok, library = pcall(StaticFindObject, '/Script/UMG.Default__SlateBlueprintLibrary')
        if ok and H.IsValidRef(library) then slate = library end
    end
    local function Bounds(widget)
        if not slate then return nil end
        local geometry = Call(widget, 'GetCachedGeometry')
        if not geometry then return nil end
        local size = Call(slate, 'GetAbsoluteSize', geometry)
        local point = Call(slate, 'LocalToAbsolute', geometry, {X = 0, Y = 0})
        local width, height = Property(size, 'X'), Property(size, 'Y')
        local x, y = Property(point, 'X'), Property(point, 'Y')
        if not geometryReported then
            geometryReported = true
            print('[AE] Geometry probe: ' .. tostring(Name(widget)) .. ' size='
                .. tostring(width) .. ',' .. tostring(height) .. ' origin=' .. tostring(x) .. ',' .. tostring(y)
                .. ' type=' .. tostring(Call(geometry, 'type')))
        end
        -- Cached geometry can be empty before layout, or when this loader cannot
        -- marshal FGeometry. It is not evidence that the attached tree is hidden.
        if type(width) == 'number' and width > 0 and type(height) == 'number' and height > 0
            and type(x) == 'number' and type(y) == 'number' then
            return {left = x, top = y, right = x + width, bottom = y + height}
        end
    end
    local function Intersect(a, b)
        if not a then return b end
        if not b then return a end
        return {left = math.max(a.left, b.left), top = math.max(a.top, b.top),
            right = math.min(a.right, b.right), bottom = math.min(a.bottom, b.bottom)}
    end
    local function Empty(rect)
        return rect and (rect.right <= rect.left or rect.bottom <= rect.top)
    end
    local seen, count = {}, 0
    local widgets = H.GetViewportRoots()

    local function Walk(widget, root, owner, ancestry, parentPath, depth, clip)
        if not Visible(widget) then return end
        local path = Name(widget)
        if not path then return end
        if seen[path] then
            snapshot.warnings[#snapshot.warnings + 1] = 'Repeated widget: ' .. path
            return
        end
        if depth > 128 or count >= 8192 then
            snapshot.warnings[#snapshot.warnings + 1] = 'Widget traversal limit: ' .. path
            return
        end
        seen[path], count = true, count + 1
        local class = path:match('^(%S+)') or ''
        local isText = class:find('Text', 1, true)
        local isLeaf = class == 'TextBlock' or class == 'RichTextBlock' or class == 'Image'
        local clipping = not isLeaf and Property(widget, 'Clipping') or nil
        local clips = class:find('ScrollBox', 1, true) or clipping == 1 or clipping == 2 or clipping == 3
        -- Native text/image widgets have no UMG children. Geometry only changes
        -- their inclusion when an ancestor supplies a clipping rectangle.
        local bounds = (depth == 0 or clips or ((isText or class == 'Image') and clip))
            and Bounds(widget) or nil
        if (isText or class == 'Image') and bounds and Empty(Intersect(clip, bounds)) then return end
        if depth == 0 or clips then clip = Intersect(clip, bounds) end
        if Empty(clip) then return end
        local treeRoot
        if not isLeaf and H.IsUserWidget(widget) then
            owner = {path = path, class = class}
            ancestry = ancestry .. '/' .. class
            local tree = Property(widget, 'WidgetTree')
            treeRoot = tree and Property(tree, 'RootWidget')
            if not H.IsValidRef(treeRoot) then
                snapshot.warnings[#snapshot.warnings + 1] = 'Widget tree unavailable: ' .. path
                treeRoot = nil
            end
        end
        local node = {path = path, class = class, root = root.path, rootClass = root.class,
            owner = owner.path, ownerClass = owner.class, ancestry = ancestry, parent = parentPath,
            focused = Call(widget, 'HasKeyboardFocus') == true, bounds = bounds}
        snapshot.nodes[#snapshot.nodes + 1] = node
        if class:find('Text', 1, true) then
            local value = Call(Call(widget, 'GetText'), 'ToString')
            if type(value) == 'string' then
                value = value:gsub('%s+', ' '):match('^%s*(.-)%s*$')
                if value ~= '' then node.text = value end
            end
        elseif class == 'Image' then
            local brush = Property(widget, 'Brush')
            local image = brush and Property(brush, 'ResourceObject')
            if H.IsValidRef(image) then node.image = Name(image) end
        end
        if node.text or node.image then snapshot.entries[#snapshot.entries + 1] = node end

        if isLeaf then return end

        if treeRoot then
            Walk(treeRoot, root, owner, ancestry, path, depth + 1, clip)
            return
        end
        local childCount = Call(widget, 'GetChildrenCount')
        if type(childCount) ~= 'number' or childCount < 1 then return end
        local active
        if class:find('WidgetSwitcher', 1, true) then
            active = Call(widget, 'GetActiveWidgetIndex')
            if type(active) ~= 'number' then
                snapshot.warnings[#snapshot.warnings + 1] = 'Active page unavailable: ' .. path
                return
            end
        end
        for index = 0, math.min(childCount, 4096) - 1 do
            if active == nil or active == index then
                Walk(Call(widget, 'GetChildAt', index), root, owner, ancestry, path, depth + 1, clip)
            end
        end
    end

    -- Only attached roots qualify. Nested widgets are visited through their
    -- owner so a visible child can never override a hidden ancestor.
    for _, widget in ipairs(widgets) do
        if H.IsValidRef(widget) and Call(widget, 'IsInViewport') == true and Visible(widget) then
            local root = {path = Name(widget), class = H.GetClassName(widget)}
            if root.path and not seen[root.path] then
                snapshot.roots[#snapshot.roots + 1] = root
                Walk(widget, root, root, '', nil, 0)
            end
        end
    end
    return snapshot
end

return UI
