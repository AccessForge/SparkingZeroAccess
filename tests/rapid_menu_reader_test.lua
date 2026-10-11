-- Integration test: rapid D-pad navigation through a menu while the loader
-- loses one game-thread callback. A tester's UE4SS.log (2026-10-05) ends with
-- "[Lua] " (an empty print) at 16:13:25.0522540 and, one frame later,
-- "Error: [Lua::Registry::get_function_ref] Ref was not function / No
-- traceback" at 16:13:25.0768308; the reader never logged again. UE4SS 1152
-- consumes such an action without running it. The real main.lua,
-- game_thread.lua, helpers.lua, widget_reader.lua, poll_trackers.lua and
-- team_overview.lua run against a UMG mock. Evidence and the two-thread
-- reproduction: research\lag-menu-20261005\menu\REPORT.md.
-- Run from the repository root with Lua 5.4 or LuaJIT.
package.path = "./SparkingZeroAccess/?.lua;" .. package.path

local realClock, realPrint = os.clock, print
local REAL_MODULES = {"helpers", "game_thread", "focus_reader", "poll_trackers", "widget_reader", "language_options", "team_overview"}
local STUBBED_MODULES = {"chara_roster", "skill_list", "battle", "episode_battle", "shop", "screen_reader"}
local GAME = "/Engine/Transient.GameEngine_2147482611:BP_SSGameInstance_C_2147482468"
local SET_TEXT = "/Script/UMG.TextBlock:SetText"

local function Harness(options)
    local h = {now = 1, phase = "game", loops = {}, queue = {}, pumps = {}, spoken = {}, logs = {},
        world = {}, unsafe = 0, hooks = {}, dropped = 0, focused = nil, serial = 2147476000}
    local super = {Widget = "Object", UserWidget = "Widget", PanelWidget = "Widget", TextBlock = "Widget",
        WidgetTree = "Object", GameInstance = "Object", BP_SSGameInstance_C = "GameInstance",
        VerticalBox = "PanelWidget", Overlay = "PanelWidget",
        WBP_GRP_Test_Menu_C = "UserWidget", WBP_OBJ_Test_BTN_C = "UserWidget"}
    local function IsA(class, target)
        while class do
            if class == target then return true end
            class = super[class]
        end
        return false
    end
    os.clock = function() return h.now end
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        h.logs[#h.logs + 1] = table.concat(parts, " ")
    end

    local function Touch(self)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        if not self._valid then error("Object is not valid", 3) end
    end
    local function Need(self, base, name)
        if not IsA(self._class, base) then error(name .. " is not a member of " .. self._class, 3) end
    end
    local methods = {}
    function methods:IsValid() return self._valid end
    function methods:type() return "UObject" end
    function methods:GetFullName() Touch(self); return self._class .. " " .. self._path end
    function methods:GetOuter() Touch(self); return self._outer end
    function methods:IsVisible() Touch(self); Need(self, "Widget", "IsVisible"); return self._visible end
    function methods:GetParent() Touch(self); Need(self, "Widget", "GetParent"); return self._parent end
    function methods:HasKeyboardFocus() Touch(self); Need(self, "Widget", "HasKeyboardFocus"); return h.focused == self end
    function methods:GetText()
        Touch(self); Need(self, "TextBlock", "GetText")
        local text = self._text
        return {ToString = function() return text end}
    end
    function methods:GetChildrenCount() Touch(self); Need(self, "PanelWidget", "GetChildrenCount"); return #self._children end
    function methods:GetChildAt(i) Touch(self); Need(self, "PanelWidget", "GetChildAt"); return self._children[i + 1] end
    if options.nativeTree then
        function methods:IsInViewport()
            Touch(self); Need(self, "UserWidget", "IsInViewport")
            return self._outer and IsA(self._outer._class, "GameInstance") or false
        end
        -- Model an independent Slate focus path through owners and parents.
        -- It deliberately stays focused when a native host's UMG list is empty.
        function methods:HasFocusedDescendants()
            Touch(self); Need(self, "Widget", "HasFocusedDescendants")
            local node = h.focused
            while node do
                if node._parent then node = node._parent
                elseif node._outer and node._outer._class == "WidgetTree" then node = node._outer._outer
                else node = nil end
                if node == self then return true end
            end
            return false
        end
        function methods:GetChildrenCount()
            Touch(self); Need(self, "PanelWidget", "GetChildrenCount")
            return self._nativeOnly and 0 or #self._children
        end
    end
    local mt = {__index = function(self, key)
        if methods[key] then return methods[key] end
        Touch(self)
        return rawget(self, "_props")[key]
    end}
    local function Spawn(class, path, outer)
        local object = setmetatable({_class = class, _path = path, _outer = outer, _valid = true,
            _visible = true, _props = {}}, mt)
        h.world[#h.world + 1] = object
        return object
    end
    local function OwnTree(widget)
        h.serial = h.serial + 1
        local tree = Spawn("WidgetTree", widget._path .. ".WidgetTree_" .. h.serial, widget)
        widget._tree, widget._props.WidgetTree = tree, tree
        return widget
    end
    local function Place(class, name, parent)
        if parent._tree then
            local widget = Spawn(class, parent._tree._path .. "." .. name, parent._tree)
            parent._tree._props.RootWidget = widget
            return widget
        end
        local widget = Spawn(class, parent._outer._path .. "." .. name, parent._outer)
        widget._parent = parent
        parent._children[#parent._children + 1] = widget
        return widget
    end
    function h:Instances(class, exact)
        local found = {}
        for _, object in ipairs(self.world) do
            if object._valid and (exact and object._class == class or not exact and IsA(object._class, class)) then
                found[#found + 1] = object
            end
        end
        return found
    end

    -- Native UE4SS globals.
    local gameInstance = Spawn("BP_SSGameInstance_C", GAME, nil)
    local function ClassObject(name)
        return {_className = name, IsValid = function() return true end, type = function() return "UObject" end}
    end
    local library = {IsValid = function() return true end, type = function() return "UObject" end,
        GetAllWidgetsOfClass = function(_, world, out, class, topLevelOnly)
            if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
            assert(world == gameInstance)
            for _, object in ipairs(h:Instances(class._className)) do
                if not topLevelOnly or object._outer == gameInstance then out[#out + 1] = object end
            end
        end}
    StaticFindObject = function(path)
        if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then return library end
        if path == "/Script/UMG.UserWidget" then return ClassObject("UserWidget") end
        return nil
    end
    FindObjects = function(count, class, name, _, _, exact)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        if class == nil then return super[name] and {ClassObject(name)} or {} end
        if class == "Class" then return super[name] and {ClassObject(name)} or {} end
        local found = {}
        for _, object in ipairs(h:Instances(class, exact)) do
            if name == nil or object._path:match("[%.:]([^%.:]+)$") == name then found[#found + 1] = object end
            if count > 0 and #found >= count then break end
        end
        return found
    end
    FindAllOf = function(class)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        local found = h:Instances(class)
        return #found > 0 and found or nil
    end
    FindFirstOf = function(class)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        return h:Instances(class)[1]
    end
    -- Loader scheduling. UE4SS 1152 offers persistent game-thread loops and,
    -- like stock 3.0.1, the async LoopAsync worker plus one-shot
    -- ExecuteInGameThread actions.
    LoopAsync = function(_, callback) h.loops[#h.loops + 1] = callback end
    ExecuteInGameThread = function(callback) h.queue[#h.queue + 1] = callback end
    ExecuteWithDelay = function(_, callback) h.loops[#h.loops + 1] = function() callback(); return true end end
    RegisterLoadMapPreHook = function(callback) h.pre = callback end
    RegisterLoadMapPostHook = function(callback) h.post = callback end
    RegisterHook = function(path) h.hooks[#h.hooks + 1] = path; return 1, 2 end
    RegisterKeyBind = function() end
    if options.legacy then
        LoopInGameThreadWithDelay, EngineTickAvailable = nil, nil
    else
        EngineTickAvailable = true
        LoopInGameThreadWithDelay = function(ms, callback)
            h.pumps[#h.pumps + 1] = {ms = ms, callback = callback}
            return #h.pumps
        end
    end

    for _, name in ipairs(REAL_MODULES) do package.loaded[name] = nil end
    local function noop() end
    for _, name in ipairs(STUBBED_MODULES) do
        package.loaded[name] = setmetatable({}, {__index = function() return noop end})
    end
    package.loaded.debug_tools = {Init = noop}
    package.loaded.speech = {
        Init = noop,
        IsLoaded = function() return true end,
        Speak = function(text, interrupt)
            h.spoken[#h.spoken + 1] = {text = text, interrupt = interrupt ~= false, queued = false}
        end,
        SpeakQueued = function(text)
            h.spoken[#h.spoken + 1] = {text = text, interrupt = false, queued = true}
        end,
    }
    assert(loadfile("SparkingZeroAccess/main.lua"))()

    -- A ten-item menu. Each item shows its label in a caption TextBlock.
    function h:Menu()
        self.serial = self.serial + 1
        local screen = OwnTree(Spawn("WBP_GRP_Test_Menu_C", GAME .. ".WBP_GRP_Test_Menu_C_" .. self.serial, gameInstance))
        local list = Place("VerticalBox", "List", screen)
        list._children = {}
        local items = {}
        for i = 1, 10 do
            local button = OwnTree(Place("WBP_OBJ_Test_BTN_C", string.format("WBP_OBJ_Test_BTN_%02d", i - 1), list))
            local root = Place("Overlay", "Root", button)
            root._children = {}
            local caption = Place("TextBlock", "caption", root)
            caption._text = "Item " .. i
            button._props.caption = caption
            items[i] = button
        end
        return items
    end
    function h:Focus(widget) self.focused = widget end

    -- One frame: the async worker may request service; then the game thread
    -- runs queued one-shot actions and persistent loops. drop loses the first
    -- game-thread callback of this frame, as UE4SS 1152 does after
    -- get_function_ref fails (the action is unreferenced without running).
    function h:Frame(dt, drop)
        self.now = self.now + (dt or 0.02)
        self.phase = "worker"
        local loops = self.loops
        for i = #loops, 1, -1 do
            if loops[i]() == true then table.remove(loops, i) end
        end
        self.phase = "game"
        local queue = self.queue
        self.queue = {}
        for _, callback in ipairs(queue) do
            if drop then drop = false; self.dropped = self.dropped + 1 else callback() end
        end
        for _, pump in ipairs(self.pumps) do
            if drop then drop = false; self.dropped = self.dropped + 1 else pump.callback() end
        end
        return drop
    end
    function h:Run(seconds)
        for _ = 1, math.floor(seconds / 0.02 + 0.5) do self:Frame(0.02) end
    end
    function h:Mark() return #self.spoken end
    function h:Since(mark)
        local entries = {}
        for i = mark + 1, #self.spoken do entries[#entries + 1] = self.spoken[i] end
        return entries
    end
    function h:Count(text, mark)
        local n = 0
        for _, entry in ipairs(self:Since(mark or 0)) do
            if entry.text == text then n = n + 1 end
        end
        return n
    end
    return h
end

local function Heard(h, mark)
    local parts = {}
    for _, entry in ipairs(h:Since(mark or 0)) do
        parts[#parts + 1] = string.format("%q%s", entry.text, entry.queued and "(queued)" or "")
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end

local function LastFocusSpeech(h, mark)
    local last = nil
    for _, entry in ipairs(h:Since(mark or 0)) do
        if entry.interrupt and entry.text:match("^Item %d+$") then last = entry.text end
    end
    return last
end

local cases = {
    {"rapid navigation announces the final focus", function(options)
        local h = Harness(options)
        local items = h:Menu()
        h:Focus(items[1])
        h:Run(0.2)
        assert(h:Count("Item 1") == 1, "first focus not announced: " .. Heard(h))
        local mark = h:Mark()
        -- One D-pad step per frame, faster than any announcement can finish.
        for i = 2, 10 do
            h:Focus(items[i])
            h:Frame(0.02)
        end
        h:Run(0.5)
        assert(LastFocusSpeech(h, mark) == "Item 10", "final focus not announced last: " .. Heard(h, mark))
        assert(h:Count("Item 10", mark) == 1, "final focus missing or repeated: " .. Heard(h, mark))
        assert(h.unsafe == 0, "game objects were touched outside the game thread")
    end},
    {"a lost game-thread callback does not silence later focus changes", function(options)
        local h = Harness(options)
        local items = h:Menu()
        h:Focus(items[1])
        h:Run(0.2)
        local mark = h:Mark()
        for i = 2, 10 do
            h:Focus(items[i])
            -- The loader loses one callback in the middle of the burst.
            assert(not h:Frame(0.02, i == 5), "no game-thread callback was available to lose")
        end
        h:Run(0.5)
        assert(h.dropped == 1, "the loader fault was not injected")
        assert(LastFocusSpeech(h, mark) == "Item 10",
            "reader stopped after the lost callback: " .. Heard(h, mark))
        mark = h:Mark()
        h:Focus(items[9])
        h:Run(0.2)
        assert(h:Count("Item 9", mark) == 1, "a later focus change was not announced: " .. Heard(h, mark))
        assert(h.unsafe == 0, "game objects were touched outside the game thread")
    end, currentLoaderOnly = true}, -- stock 3.0.1 has no persistent game-thread loop
    {"the reader registers no native TextBlock:SetText hook", function(options)
        -- That hook ran Lua with a GetFullName on the loader's shared hook
        -- thread for every scripted SetText, captured a bubble name nothing
        -- reads, and is the hook-thread user that the cross-thread race needs.
        local h = Harness(options)
        for _, path in ipairs(h.hooks) do
            assert(path ~= SET_TEXT, "registered " .. SET_TEXT)
        end
    end},
    {"the native viewport path preserves rapid final focus", function(options)
        local h = Harness(options)
        local items = h:Menu(); h:Focus(items[1]); h:Run(.2)
        for i = 2, 10 do h:Focus(items[i]); h:Frame(.02) end
        h:Run(.2)
        assert(LastFocusSpeech(h) == "Item 10", "native tree lost final focus: " .. Heard(h))
        assert(table.concat(h.logs, "\n"):find("Native viewport focus reader active", 1, true), "test only exercised compatibility scan")
        assert(not table.concat(h.logs, "\n"):find("using compatibility widget scan", 1, true), "supported native menu fell back")
        assert(h.unsafe == 0, "native focus ran outside the game thread")
    end, nativeTreeOnly = true},
    {"native discovery waits for a hidden owner to become visible", function(options)
        local h = Harness(options)
        local items = h:Menu(); local owner = items[1]._parent._outer._outer
        owner._visible = false; h:Focus(items[1]); h:Run(.5)
        assert(h:Count("Item 1") == 0, "hidden ancestor focus was spoken")
        owner._visible = true; h:Run(.5)
        assert(h:Count("Item 1") == 1, "focus did not speak when its live owner became visible: " .. Heard(h))
    end, nativeTreeOnly = true},
    {"an unreachable Slate branch keeps speaking through the compatibility reader", function(options)
        local h = Harness(options)
        local items = h:Menu(); items[1]._parent._nativeOnly = true
        h:Focus(items[1]); h:Run(.2)
        assert(h:Count("Item 1") == 1, "a native host silently lost visible focus: " .. Heard(h))
        assert(table.concat(h.logs, "\n"):find("using compatibility widget scan", 1, true), "unreachable focus did not fall back")
        h:Focus(items[10]); h:Run(.2)
        assert(LastFocusSpeech(h) == "Item 10", "fallback lost later focus: " .. Heard(h))
    end, nativeTreeOnly = true},
}

local variants = {
    {"UE4SS 1152", {legacy = false}},
    {"stock UE4SS 3.0.1", {legacy = true}},
    {"UE4SS 1152 native viewport tree", {legacy = false, nativeTree = true}},
}

local failures = 0
for _, variant in ipairs(variants) do
    for _, case in ipairs(cases) do
        if not (case.currentLoaderOnly and variant[2].legacy)
            and (not case.nativeTreeOnly or variant[2].nativeTree) then
            local ok, err = pcall(case[2], variant[2])
            os.clock, print = realClock, realPrint
            local label = variant[1] .. ": " .. case[1]
            if ok then print("PASS: " .. label)
            else failures = failures + 1; print("FAIL: " .. label .. ": " .. tostring(err)) end
        end
    end
end
LoopInGameThreadWithDelay, EngineTickAvailable = nil, nil
os.clock, print = realClock, realPrint
assert(failures == 0, tostring(failures) .. " rapid menu reader regressions")
