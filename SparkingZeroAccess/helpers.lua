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

return Helpers
