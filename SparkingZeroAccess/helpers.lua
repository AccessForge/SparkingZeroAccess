--[[
    helpers.lua — Shared utility functions for SparkingZeroAccess
    Safe wrappers for UE4SS object access.

    IsValidRef() is for UObject references ONLY (widgets, actors, etc.).
    TryCall/TryGetProperty work on any object type (UObject, FText, FString, etc.)
    and use pcall as their safety net — no IsValid pre-check.
]]

local Helpers = {}

--- Check if a UObject reference is still alive.
--- ONLY use on known UObject types (widgets, actors, components).
--- Do NOT use on FText, FString, or other non-UObject types.
function Helpers.IsValidRef(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    if ok then return valid end
    -- Fallback: try GetFullName as a proxy
    ok = pcall(function() return obj:GetFullName() end)
    return ok
end

function Helpers.TryCall(obj, methodName, ...)
    local success, value = pcall(function(...)
        return obj[methodName](obj, ...)
    end, ...)
    if success then return value end
    return nil
end

function Helpers.TryGetProperty(obj, propName)
    local success, value = pcall(function()
        return obj[propName]
    end)
    if success then return value end
    return nil
end

function Helpers.GetWidgetName(obj)
    local ok, fullName = pcall(function() return obj:GetFullName() end)
    if not ok then return "(invalid)" end
    return fullName:match("%.([^%.]+)$") or fullName
end

function Helpers.GetClassName(obj)
    local ok, fullName = pcall(function() return obj:GetFullName() end)
    if not ok then return "(invalid)" end
    return fullName:match("^(.-)%s") or fullName
end

-- Cached singleton lookup. With bUseUObjectArrayCache=false every FindFirstOf
-- is a full GUObjectArray walk, so callers that hit the same singleton every
-- tick (PollScreenChanges, PollRoom, etc.) should route through here.
-- Positive results are revalidated with IsValidRef; negative results are
-- throttled to a 500ms retry window.
local _firstOfCache = {}      -- typeName -> live UObject ref
local _firstOfMissUntil = {}  -- typeName -> os.clock() until next retry allowed

function Helpers.GetCachedFirstOf(typeName)
    local cached = _firstOfCache[typeName]
    if cached and Helpers.IsValidRef(cached) then
        return cached
    end
    _firstOfCache[typeName] = nil

    local missUntil = _firstOfMissUntil[typeName]
    if missUntil and os.clock() < missUntil then
        return nil
    end

    local ok, fresh = pcall(FindFirstOf, typeName)
    if ok and fresh and Helpers.IsValidRef(fresh) then
        _firstOfCache[typeName] = fresh
        _firstOfMissUntil[typeName] = nil
        return fresh
    end
    _firstOfMissUntil[typeName] = os.clock() + 0.5
    return nil
end

function Helpers.InvalidateCachedFirstOf(typeName)
    if typeName then
        _firstOfCache[typeName] = nil
        _firstOfMissUntil[typeName] = nil
    else
        _firstOfCache = {}
        _firstOfMissUntil = {}
    end
end

return Helpers
