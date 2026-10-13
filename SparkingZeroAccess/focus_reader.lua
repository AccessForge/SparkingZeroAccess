-- Find live keyboard focus through attached native UMG trees. No values cached.
local H = require('helpers')
local Focus = {}
local Call, Property = H.TryCall, H.TryGetProperty

function Focus.Find()
    if type(LoopInGameThreadWithDelay) ~= 'function' then return nil, false end
    local roots, native = H.GetViewportRoots()
    if native ~= true then return nil, false end
    local seen, count, supported = {}, 0, true
    local function Walk(widget, depth)
        if not H.IsValidRef(widget) then return nil end
        local visible = Call(widget, 'IsVisible')
        if type(visible) ~= 'boolean' then supported = false; return nil end
        local opacity = Property(widget, 'RenderOpacity')
        local focused = Call(widget, 'HasKeyboardFocus')
        if type(focused) ~= 'boolean' then supported = false; return nil end
        local hidden = not visible or (type(opacity) == 'number' and opacity <= 0.001)
        if hidden and focused then return nil, true end
        if hidden then
            local within = Call(widget, 'HasFocusedDescendants')
            if type(within) ~= 'boolean' then supported = false; return nil end
            return nil, within -- focus deliberately excluded by a hidden ancestor.
        end
        if focused then
            if H.IsUserWidget(widget) then return widget, true end
            return nil, true -- the original reader also ignores native-button focus.
        end
        local within = Call(widget, 'HasFocusedDescendants')
        if type(within) ~= 'boolean' then supported = false; return nil end
        if not within then return nil end
        local path = Call(widget, 'GetFullName')
        if not path or seen[path] or depth > 128 or count >= 8192 then supported = false; return nil end
        seen[path], count = true, count + 1
        if H.IsUserWidget(widget) then
            local tree = Property(widget, 'WidgetTree')
            local root = tree and Property(tree, 'RootWidget')
            if not H.IsValidRef(root) then supported = false; return nil end
            local found, accounted = Walk(root, depth + 1)
            if not found and not accounted then supported = false end
            return found, accounted
        end
        local children = Call(widget, 'GetChildrenCount')
        if type(children) ~= 'number' or children > 4096 then supported = false; return nil end
        local active
        local class = path:match('^(%S+)') or ''
        if class:find('WidgetSwitcher', 1, true) then
            active = Call(widget, 'GetActiveWidgetIndex')
            if type(active) ~= 'number' then supported = false; return nil end
        end
        local accounted = false
        for index = 0, children - 1 do
            local child = Call(widget, 'GetChildAt', index)
            if active == nil or active == index then
                local found, excluded = Walk(child, depth + 1)
                if found then return found, true end
                accounted = accounted or excluded == true
            elseif H.IsValidRef(child) then
                -- An inactive page may retain old Slate focus during a switch.
                accounted = accounted or Call(child, 'HasKeyboardFocus') == true
                    or Call(child, 'HasFocusedDescendants') == true
            end
        end
        if not accounted then supported = false end
        return nil, accounted
    end
    for _, root in ipairs(roots) do
        if H.IsValidRef(root) then
            local attached = Call(root, 'IsInViewport')
            if type(attached) ~= 'boolean' then supported = false end
            if attached then
                local focused = Walk(root, 0)
                if focused then return focused, true end
            end
        end
    end
    return nil, supported
end

return Focus
