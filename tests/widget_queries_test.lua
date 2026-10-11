package.path = "./SparkingZeroAccess/?.lua;" .. package.path
local H = require("helpers")
LoopInGameThreadWithDelay = function() end -- current loader API
local now, nativeQueries, broadQueries, classQueries = 1, 0, 0, 0
local realClock = os.clock
os.clock = function() return now end
local function valid(object)
    object.IsValid = function() return object.alive ~= false end
    object.type = function() return "UObject" end
    return object
end
local world, widgetClass = valid({}), valid({})
local coreClass = valid({})
local liveWidget = valid({text = "First"})
local widgets, blocks = {liveWidget}, {liveWidget}
local classExists = true
local classNameCollision = false
local nonClassObject = valid({})
local keyedOutput = false
local wrappedOutput = true
local library = valid({GetAllWidgetsOfClass = function(self, context, out, class, topOnly)
    assert(context == world and (class == widgetClass or class == coreClass) and topOnly == false)
    nativeQueries = nativeQueries + 1
    local target = out
    if keyedOutput then target = {}; out.FoundWidgets = target end
    for i, widget in ipairs(widgets) do
        target[i] = wrappedOutput and {
            type = function() return "RemoteUnrealParam" end,
            get = function() return widget end,
        } or widget
    end
end})
StaticFindObject = function(path)
    if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then return library end
    if path == "/Script/UMG.UserWidget" then return coreClass end
    error("Unexpected static lookup: " .. path)
end
FindObjects = function(count, class, name, required, banned, exact)
    if count == 0 then
        assert(name == nil and required == 0 and banned == 0x10 and exact == false)
        return class == "TextBlock" and blocks or widgets
    end
    assert(count == 1 and (class == nil or class == "Class") and name:match("^WBP_"))
    if class == "Class" then assert(exact == false, "derived BlueprintGeneratedClass was excluded") end
    classQueries = classQueries + 1
    if classNameCollision and class == nil then return {nonClassObject} end
    return classExists and {widgetClass} or {}
end
FindFirstOf = function(name) assert(name == "GameInstance"); return world end
FindAllOf = function(name)
    broadQueries = broadQueries + 1
    assert(name == "TextBlock", "UI class triggered an expensive global hierarchy scan")
    return blocks
end

local cases = {
    {"UI queries use the engine and include nested widgets", function()
        assert(type(H.FindAllOf) == "function", "native widget query helper is missing")
        H.BeginReadCycle()
        assert(H.FindAllOf("WBP_Test_C")[1] == liveWidget)
        assert(H.FindAllOf("UserWidget")[1] == liveWidget)
        assert(nativeQueries == 2 and broadQueries == 0)
    end},
    {"one cycle shares references and still reads live text", function()
        H.BeginReadCycle()
        local first = H.FindAllOf("TextBlock")
        liveWidget.text = "Changed"
        local second = H.FindAllOf("TextBlock")
        assert(first == second and second[1].text == "Changed")
        assert(broadQueries == 1, "duplicated global scan within one polling cycle")
        blocks = {liveWidget, valid({text = "New"})}
        H.BeginReadCycle()
        assert(#H.FindAllOf("TextBlock") == 2, "next cycle did not see newly created text")
    end},
    {"missing widget classes are retried after loading", function()
        classExists = false
        H.InvalidateCachedFirstOf()
        H.BeginReadCycle()
        local before = classQueries
        assert(#(H.FindAllOf("WBP_New_C") or {}) == 0)
        H.BeginReadCycle()
        H.FindAllOf("WBP_New_C")
        assert(classQueries == before + 1, "missing class was scanned every frame")
        now = now + 0.6
        classExists = true
        H.BeginReadCycle()
        assert(H.FindAllOf("WBP_New_C")[1] == liveWidget, "newly loaded class remained unavailable")
    end},
    {"map invalidation discards query results", function()
        widgets = {valid({text = "New map"})}
        H.InvalidateCachedFirstOf()
        H.BeginReadCycle()
        assert(H.FindAllOf("WBP_Test_C")[1].text == "New map")
    end},
    {"legacy named array output is read as well as the current flat output", function()
        keyedOutput = true
        H.BeginReadCycle()
        assert(H.FindAllOf("WBP_Test_C")[1] == widgets[1], "legacy FoundWidgets array was lost")
        keyedOutput = false
    end},
    {"direct UObject output remains readable", function()
        wrappedOutput = false
        H.BeginReadCycle()
        assert(H.FindAllOf("WBP_Test_C")[1] == widgets[1])
        wrappedOutput = true
    end},
    {"a deleted cached class is resolved again", function()
        widgetClass.alive = false
        widgetClass = valid({})
        H.BeginReadCycle()
        local before = classQueries
        assert(H.FindAllOf("WBP_Test_C")[1] == widgets[1])
        assert(classQueries == before + 1, "dead cached class was reused")
    end},
    {"class-name collisions never fall back to scanning all widget instances", function()
        classNameCollision = true
        H.InvalidateCachedFirstOf()
        H.BeginReadCycle()
        local before = nativeQueries
        assert(H.FindAllOf("WBP_Collision_C")[1] == widgets[1])
        assert(nativeQueries == before + 1, "an unrelated named object displaced the widget class and forced a fallback scan")
        classNameCollision = false
    end},
    {"stock loader uses the equivalent FName lookup without broken output arrays", function()
        LoopInGameThreadWithDelay = nil
        H.BeginReadCycle()
        local before = nativeQueries
        assert(H.FindAllOf("UserWidget")[1] == widgets[1])
        assert(H.FindAllOf("TextBlock")[1] == blocks[1])
        assert(nativeQueries == before, "stock loader called its broken array-output API")
    end},
}
local failed = 0
for _, case in ipairs(cases) do
    local ok, err = pcall(case[2])
    if ok then print("PASS: " .. case[1])
    else failed = failed + 1; print("FAIL: " .. case[1] .. ": " .. tostring(err)) end
end
os.clock = realClock
assert(failed == 0, tostring(failed) .. " widget query regressions")
