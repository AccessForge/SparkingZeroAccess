--[[
    helpers.lua — Shared utility functions for SparkingZeroAccess
    Safe wrappers for UE4SS object access.

    IsValidRef() is for UObject references ONLY (widgets, actors, etc.).
    TryCall/TryGetProperty work on any object type (UObject, FText, FString, etc.)
    and use pcall as their safety net — no IsValid pre-check.
]]

local Helpers = {}
local cycleResults, widgetClasses, widgetClassMissUntil = {}, {}, {}
local widgetLibrary, userWidgetClass = nil, nil
local queryWarnings, slowQueries = {}, {}
local queryOutputs = {}
local engineQueryAnnounced = false
local firstWidgetReported = false

-- These references are shared only within a single game-thread dispatch.
-- Text, visibility, focus, and numeric values are never cached here.
function Helpers.BeginReadCycle()
    cycleResults = {}
end

local function IsUserWidgetClass(name)
    return name == "UserWidget" or name:match("^WBP_") ~= nil
end

local function QueryWidgets(name, topOnly)
    local world = Helpers.GetCachedFirstOf("GameInstance")
    if not world then return {} end
    if not Helpers.IsValidRef(widgetLibrary) then widgetLibrary = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end
    if not Helpers.IsValidRef(userWidgetClass) then userWidgetClass = StaticFindObject("/Script/UMG.UserWidget") end
    assert(Helpers.IsValidRef(widgetLibrary) and Helpers.IsValidRef(userWidgetClass), "WidgetBlueprintLibrary is unavailable")

    local class = name == "UserWidget" and userWidgetClass or widgetClasses[name]
    if class and not Helpers.IsValidRef(class) then
        class = nil
        widgetClasses[name] = nil
        widgetClassMissUntil[name] = nil
    end
    if not class then
        if os.clock() < (widgetClassMissUntil[name] or 0) then return {} end
        -- Search class objects, including derived BlueprintGeneratedClass types.
        -- A name-only lookup also searches unrelated objects for absent screens.
        local found = FindObjects(1, "Class", name, 0, 0, false)
        class = found and found[1]
        if not Helpers.IsValidRef(class) then
            widgetClassMissUntil[name] = os.clock() + 0.5
            return {}
        end
        widgetClasses[name] = class
    end
    -- Build 1152 retains an Out-table registry reference for every UFunction
    -- call without releasing it. Reuse bounded scratch storage, then empty it
    -- so the loader cannot retain entire historical widget lists. Returned
    -- lists stay independent; callers never receive the mutable scratch table.
    local outputKey = name .. (topOnly == true and ':roots' or ':all')
    local out = queryOutputs[outputKey]
    if not out then out = {}; queryOutputs[outputKey] = out end
    local function ClearOutput()
        for key in pairs(out) do out[key] = nil end
    end
    ClearOutput()
    local nestedOutput = false
    local ok, result = pcall(function()
        widgetLibrary:GetAllWidgetsOfClass(world, out, class, topOnly == true)
        -- Older bindings nest arrays under their parameter name.
        local found = out.FoundWidgets or out
        nestedOutput = out.FoundWidgets ~= nil
        assert(type(found) == "table", "unexpected FoundWidgets output type: " .. type(found))
        local copy = {}
        for i, item in ipairs(found) do
            local kind = item:type()
            if kind == "RemoteUnrealParam" or kind == "LocalUnrealParam" then item = item:get() end
            copy[i] = item
        end
        return copy
    end)
    ClearOutput() -- also release partial output when the native call fails.
    if not ok then error(result, 0) end
    if not engineQueryAnnounced then
        engineQueryAnnounced = true
        print("[AE] Engine widget query active; output=" .. (nestedOutput and "FoundWidgets" or "array") .. ", count=" .. #result)
    end
    if not firstWidgetReported and result[1] then
        firstWidgetReported = true
        print("[AE] Engine query first widget: " .. tostring(Helpers.TryCall(result[1], "GetFullName")))
    end
    return result
end

function Helpers.FindAllOf(name)
    if cycleResults[name] then return cycleResults[name] end
    local started = os.clock()
    local result
    if type(LoopInGameThreadWithDelay) ~= "function" then
        -- Stock 3.0.1 cannot marshal an out-array followed by input parameters.
        -- Its FName-based lookup finds the same derived instances without the
        -- repeated string conversions in FindAllOf. Exclude class defaults.
        result = FindObjects(0, name, nil, 0, 0x10, false)
    elseif IsUserWidgetClass(name) then
        local ok, found = pcall(QueryWidgets, name)
        if ok then result = found
        else
            if not queryWarnings[name] then
                queryWarnings[name] = true
                print("[AE] Engine query failed for " .. name .. ": " .. tostring(found) .. "; using UE4SS lookup")
            end
            result = FindObjects(0, name, nil, 0, 0x10, false)
        end
    else
        result = FindAllOf(name)
    end
    local elapsed = os.clock() - started
    if elapsed > 0.02 and not slowQueries[name] then
        slowQueries[name] = true
        print(string.format("[AE] Slow object query: %s %.1f ms", name, elapsed * 1000))
    end
    cycleResults[name] = result or {}
    return cycleResults[name]
end

function Helpers.FindFirstOf(name)
    if IsUserWidgetClass(name) then return Helpers.FindAllOf(name)[1] end
    return FindFirstOf(name)
end

-- Discover attached roots in the engine rather than marshal every allocated
-- nested widget into Lua. Nested user widgets are followed through their trees.
function Helpers.GetViewportRoots()
    local roots
    if type(LoopInGameThreadWithDelay) == 'function' then
        local ok, result = pcall(QueryWidgets, 'UserWidget', true)
        if ok then return result, true end
    end
    if not roots then
        roots = {}
        for _, widget in ipairs(Helpers.FindAllOf('UserWidget')) do
            if Helpers.IsValidRef(widget) and Helpers.TryCall(widget, 'IsInViewport') == true then
                roots[#roots + 1] = widget
            end
        end
    end
    return roots, false
end

function Helpers.IsUserWidget(widget)
    if not Helpers.IsValidRef(userWidgetClass) and type(StaticFindObject) == 'function' then
        userWidgetClass = StaticFindObject('/Script/UMG.UserWidget')
    end
    if Helpers.IsValidRef(userWidgetClass) then
        local result = Helpers.TryCall(widget, 'IsA', userWidgetClass)
        if type(result) == 'boolean' then return result end
    end
    -- Older loaders and fixtures can lack IsA. WidgetTree is a native property
    -- belonging to UUserWidget; it is not a guessed class-name convention.
    return Helpers.TryGetProperty(widget, 'WidgetTree') ~= nil
end

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

    local ok, fresh = pcall(Helpers.FindFirstOf, typeName)
    if ok and fresh and Helpers.IsValidRef(fresh) then
        _firstOfCache[typeName] = fresh
        _firstOfMissUntil[typeName] = nil
        return fresh
    end
    _firstOfMissUntil[typeName] = os.clock() + 0.5
    return nil
end

function Helpers.InvalidateCachedFirstOf(typeName)
    cycleResults = {}
    if typeName then
        _firstOfCache[typeName] = nil
        _firstOfMissUntil[typeName] = nil
        widgetClasses[typeName] = nil
        widgetClassMissUntil[typeName] = nil
    else
        _firstOfCache = {}
        _firstOfMissUntil = {}
        widgetClasses = {}
        widgetClassMissUntil = {}
        widgetLibrary, userWidgetClass = nil, nil
    end
end

return Helpers
