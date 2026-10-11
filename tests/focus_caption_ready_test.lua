-- Integration test: the real main.lua and widget_reader.lua read a training
-- menu whose first focused hit area has no native RemoteButton link or caption
-- yet (live session 2026-10-03 21:30:31). The engine mock follows UMG trees:
-- user widgets own WidgetTrees, panels own slotted children, paths follow the
-- outer chain, and unsupported calls fail as they do through UE4SS. The
-- passive screen_reader is stubbed so only focus speech is measured.
-- Run from the repository root with Lua 5.4 or LuaJIT.
package.path = "./SparkingZeroAccess/?.lua;" .. package.path

local realClock, realPrint = os.clock, print
local REAL_MODULES = {"helpers", "game_thread", "poll_trackers", "widget_reader", "language_options"}
local STUBBED_MODULES = {"team_overview", "chara_roster", "skill_list", "battle", "episode_battle", "shop",
    "screen_reader"}
local GAME = "/Engine/Transient.GameEngine_2147482611:BP_SSGameInstance_C_2147482468"
local PLACEHOLDER = "Common HitButton 0"

local function Harness(options)
    local h = {now = 1, phase = "game", loops = {}, queue = {}, spoken = {}, logs = {},
        world = {}, unsafe = 0, legacy = options.legacy, focused = nil, serial = 2147476000}
    local super = {Widget = "Object", UserWidget = "Widget", PanelWidget = "Widget", TextBlock = "Widget",
        WidgetTree = "Object", GameInstance = "Object", BP_SSGameInstance_C = "GameInstance",
        CanvasPanel = "PanelWidget", Overlay = "PanelWidget"}
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
    local mt = {__index = function(self, key)
        if methods[key] then return methods[key] end
        Touch(self)
        local props = rawget(self, "_props")
        props._reads[key] = (props._reads[key] or 0) + 1
        return props[key]
    end}
    local function Spawn(class, path, outer)
        local object = setmetatable({_class = class, _path = path, _outer = outer, _valid = true,
            _visible = true, _props = {_reads = {}}}, mt)
        h.world[#h.world + 1] = object
        return object
    end
    local function OwnTree(widget)
        h.serial = h.serial + 1
        local tree = Spawn("WidgetTree", widget._path .. ".WidgetTree_" .. h.serial, widget)
        widget._tree, widget._props.WidgetTree = tree, tree
        return widget
    end
    -- A user widget parent receives the widget as its tree root; a panel
    -- parent slots it as its next child in the same tree.
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
    function h:Reads(object, key) return object._props._reads[key] or 0 end
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
            assert(world == gameInstance and topLevelOnly == false)
            for _, object in ipairs(h:Instances(class._className)) do out[#out + 1] = object end
        end}
    StaticFindObject = function(path)
        if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then return library end
        if path == "/Script/UMG.UserWidget" then return ClassObject("UserWidget") end
        return nil
    end
    FindObjects = function(count, class, name, _, _, exact)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        if class == nil then return super[name] and {ClassObject(name)} or {} end
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
    LoopAsync = function(_, callback) h.loops[#h.loops + 1] = callback end
    ExecuteInGameThread = function(callback) h.queue[#h.queue + 1] = callback end
    ExecuteWithDelay = function(_, callback) h.loops[#h.loops + 1] = function() callback(); return true end end
    RegisterLoadMapPreHook = function(callback) h.pre = callback end
    RegisterLoadMapPostHook = function(callback) h.post = callback end
    RegisterHook = function() return 1, 2 end
    RegisterKeyBind = function() end
    LoopInGameThreadWithDelay = (not options.legacy) and function() return 1 end or nil

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

    -- The live training-type menu. Native links cross the numbers:
    -- HitButton_0 -> CSG_BTN_01 and HitButton_1 -> CSG_BTN_00.
    function h:TrainingMenu()
        super.WBP_GRP_CSG_Top_C = "UserWidget"
        super.WBP_OBJ_Common_HitButton_C = "UserWidget"
        super.WBP_OBJ_CSG_BTN_C = "UserWidget"
        self.serial = self.serial + 1
        local screen = OwnTree(Spawn("WBP_GRP_CSG_Top_C", GAME .. ".WBP_GRP_CSG_Top_C_" .. self.serial, gameInstance))
        local canvas = Place("CanvasPanel", "Canvas", screen)
        canvas._children = {}
        local function HitArea(name)
            local hit = OwnTree(Place("WBP_OBJ_Common_HitButton_C", name, canvas))
            Place("Overlay", "HitArea", hit)._children = {}
            return hit
        end
        local function Button(name, text)
            local button = OwnTree(Place("WBP_OBJ_CSG_BTN_C", name, canvas))
            local root = Place("Overlay", "Root", button)
            root._children = {}
            button.caption = Place("TextBlock", "caption", root)
            button.caption._text = text
            button._props.caption = button.caption
            return button
        end
        local m = {screen = screen}
        m.hit0 = HitArea("WBP_OBJ_Common_HitButton_0")
        m.hit1 = HitArea("WBP_OBJ_Common_HitButton_1")
        m.btn0 = Button("WBP_OBJ_CSG_BTN_00", "Select Training Type")
        m.btn1 = Button("WBP_OBJ_CSG_BTN_01", "") -- caption not initialized yet
        m.hit1._props.RemoteButton = m.btn0
        function m.LinkReady() m.hit0._props.RemoteButton = m.btn1 end
        function m.TextReady() m.btn1.caption._text = "Special Maneuvers" end
        return m
    end
    function h:Destroy(menu)
        local prefix = menu.screen._path
        for _, object in ipairs(self.world) do
            if object._path == prefix or object._path:sub(1, #prefix + 1) == prefix .. "." then
                object._valid = false
            end
        end
    end
    function h:Focus(widget) self.focused = widget end

    -- One frame: the async worker requests service, then the game thread runs it.
    function h:Frame(dt)
        self.now = self.now + (dt or 0.02)
        self.phase = "worker"
        local loops = self.loops
        for i = #loops, 1, -1 do
            if loops[i]() == true then table.remove(loops, i) end
        end
        self.phase = "game"
        local queue = self.queue
        self.queue = {}
        for _, callback in ipairs(queue) do callback() end
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
    function h:Logged(text)
        local n = 0
        for _, line in ipairs(self.logs) do
            if line:find(text, 1, true) then n = n + 1 end
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

local function ExpectHealthy(h)
    assert(h.unsafe == 0, "game objects were touched outside the game thread")
    for _, line in ipairs(h.logs) do
        assert(not line:lower():find("error", 1, true), "reader reported: " .. line)
    end
end

-- Focus lands on the first hit area before its button is ready, as live.
local function FocusUnready(options)
    local h = Harness(options)
    local menu = h:TrainingMenu()
    h:Focus(menu.hit0)
    h:Run(0.1)
    assert(h:Count(PLACEHOLDER) == 1, "unready hit area was not announced: " .. Heard(h))
    return h, menu
end

local cases = {
    {"a late native link and caption are announced once without moving focus", function(options)
        local h, menu = FocusUnready(options)
        local mark = h:Mark()
        h:Run(0.3)
        assert(#h:Since(mark) == 0, "spoke before the label was ready: " .. Heard(h, mark))
        menu.LinkReady() -- the native link exists, but its caption is still empty
        h:Run(0.6)
        assert(#h:Since(mark) == 0, "spoke an empty caption: " .. Heard(h, mark))
        menu.TextReady()
        h:Run(0.6)
        local heard = h:Since(mark)
        assert(#heard == 1 and heard[1].text == "Special Maneuvers", "expected one corrected label; heard " .. Heard(h, mark))
        assert(heard[1].queued, "the correction cut off speech already in progress")
        local reads = h:Reads(menu.hit0, "RemoteButton")
        mark = h:Mark()
        h:Run(3)
        assert(#h:Since(mark) == 0, "corrected label repeated: " .. Heard(h, mark))
        assert(h:Reads(menu.hit0, "RemoteButton") == reads, "kept retrying after the label resolved")
        -- The corrected label now has a caption reference like any matched button.
        menu.btn1.caption._text = "Special Moves"
        h:Run(0.2)
        heard = h:Since(mark)
        assert(#heard == 1 and heard[1].text == "Special Moves" and heard[1].interrupt,
            "caption change after correction not announced: " .. Heard(h, mark))
        assert(h:Logged("Focus label ready after") == 1)
        ExpectHealthy(h)
    end},
    {"a label resolved on focus is not retried or repeated", function(options)
        local h = Harness(options)
        local menu = h:TrainingMenu()
        h:Focus(menu.hit1)
        h:Run(4)
        assert(h:Count("Select Training Type") == 1, "resolved label missing or repeated: " .. Heard(h))
        assert(h:Reads(menu.hit1, "RemoteButton") == 1, "a resolved label was resolved again")
        assert(h:Logged("Focus label") == 0, "a resolved label entered the retry path")
        ExpectHealthy(h)
    end},
    {"a permanently unavailable label stops after bounded, throttled retries", function(options)
        local h, menu = FocusUnready(options)
        local mark = h:Mark()
        h:Run(0.9)
        local early = h:Reads(menu.hit0, "RemoteButton")
        assert(early >= 2 and early <= 6, "retries are not throttled: " .. early .. " reads in 1 s")
        h:Run(6)
        local settled = h:Reads(menu.hit0, "RemoteButton")
        h:Run(6)
        assert(h:Reads(menu.hit0, "RemoteButton") == settled, "retries never stopped")
        assert(settled <= 21, "too many retries: " .. settled)
        assert(h:Logged("Focus label unavailable after") == 1, "giving up was not reported once")
        assert(#h:Since(mark) == 0, "spoke while the label stayed unavailable: " .. Heard(h, mark))
        ExpectHealthy(h)
    end},
    {"moving focus cancels the pending retry", function(options)
        local h, menu = FocusUnready(options)
        h:Run(0.3)
        local mark = h:Mark()
        h:Focus(menu.hit1)
        h:Run(0.3)
        assert(h:Count("Select Training Type", mark) == 1, "new focus not announced: " .. Heard(h, mark))
        local reads = h:Reads(menu.hit0, "RemoteButton")
        menu.LinkReady(); menu.TextReady()
        h:Run(3)
        assert(h:Reads(menu.hit0, "RemoteButton") == reads, "the unfocused hit area was still retried")
        assert(h:Count("Special Maneuvers") == 0, "the old focus was announced: " .. Heard(h))
        ExpectHealthy(h)
    end},
    {"losing focus cancels the pending retry", function(options)
        local h, menu = FocusUnready(options)
        h:Run(0.3)
        h:Focus(nil)
        h:Run(0.3)
        local reads, mark = h:Reads(menu.hit0, "RemoteButton"), h:Mark()
        menu.LinkReady(); menu.TextReady()
        h:Run(3)
        assert(h:Reads(menu.hit0, "RemoteButton") == reads, "an unfocused hit area was still retried")
        assert(#h:Since(mark) == 0, "spoke without focus: " .. Heard(h, mark))
        ExpectHealthy(h)
    end},
    {"map loading cancels the pending retry for the old world", function(options)
        local h, menu = FocusUnready(options)
        h:Run(0.3)
        local reads, mark = h:Reads(menu.hit0, "RemoteButton"), h:Mark()
        if h.pre then
            h.pre()
            menu.LinkReady(); menu.TextReady()
            h:Run(5) -- far longer than the retry window
            assert(h:Reads(menu.hit0, "RemoteButton") == reads, "retried during map load")
            assert(#h:Since(mark) == 0, "spoke during map load: " .. Heard(h, mark))
        else
            assert(h.legacy, "map pre-hook missing on a fixed loader")
            menu.LinkReady(); menu.TextReady()
        end
        h:Destroy(menu)
        local nextMenu = h:TrainingMenu()
        h:Focus(nextMenu.hit1)
        h.post()
        h:Run(1.5)
        assert(h:Reads(menu.hit0, "RemoteButton") == reads, "the old world's hit area was read after loading")
        assert(h:Count("Special Maneuvers", mark) == 0, "a cancelled correction was spoken: " .. Heard(h, mark))
        assert(h:Count("Select Training Type", mark) == 1, "the next map's focus was not announced: " .. Heard(h, mark))
        ExpectHealthy(h)
    end},
}

local variants = {
    {"UE4SS 1152", {legacy = false}},
    {"stock UE4SS 3.0.1", {legacy = true}},
}

local failures = 0
for _, variant in ipairs(variants) do
    for _, case in ipairs(cases) do
        local ok, err = pcall(case[2], variant[2])
        os.clock, print = realClock, realPrint
        local label = variant[1] .. ": " .. case[1]
        if ok then print("PASS: " .. label)
        else failures = failures + 1; print("FAIL: " .. label .. ": " .. tostring(err)) end
    end
end
os.clock, print = realClock, realPrint
assert(failures == 0, tostring(failures) .. " focus caption readiness regressions")
