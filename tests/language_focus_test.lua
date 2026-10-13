-- Integration test: the real main.lua, widget_reader.lua and language_options.lua
-- read a simulated language settings screen through the game-thread scheduler.
-- The engine mock follows UE4SS semantics (class hierarchy, invalid objects,
-- engine widget queries, legacy FindObjects lookups); no source text is inspected.
-- Run from the repository root with Lua 5.4 or LuaJIT.
package.path = "./SparkingZeroAccess/?.lua;" .. package.path

local realClock, realPrint = os.clock, print
local REAL_MODULES = {"helpers", "game_thread", "poll_trackers", "widget_reader", "language_options"}
local STUBBED_MODULES = {"team_overview", "chara_roster", "skill_list", "battle", "episode_battle", "shop"}
local TEXTURE_DIR = "/Game/SS/UI/Title/OBJ/Texture/"
local SCREEN = "/Engine/Transient.GameEngine_2147482611:BP_SSGameInstance_C_2147482468"

local SUPER = {
    Widget = "Object", UserWidget = "Widget", TextBlock = "Widget", RichTextBlock = "Widget",
    Image = "Widget", GameInstance = "Object", Texture2D = "Object",
}
local function IsA(className, target)
    local current = className
    while current do
        if current == target then return true end
        current = SUPER[current]
    end
    return false
end

local function Harness(options)
    options = options or {}
    local h = {now = 1, phase = "game", loops = {}, queue = {}, spoken = {}, logs = {},
        world = {}, unsafe = 0, legacy = options.legacy, focused = nil, serial = 0}
    os.clock = function() return h.now end
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        h.logs[#h.logs + 1] = table.concat(parts, " ")
    end

    local function touch(self)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        if not self._valid then error("Object is not valid", 2) end
    end
    local methods = {}
    function methods:IsValid() return self._valid end
    function methods:type() return "UObject" end
    function methods:GetFullName() touch(self); return self._class .. " " .. self._path end
    function methods:GetFName()
        touch(self)
        local name = self._path:match("[%.:]([^%.:]+)$") or self._path
        return {ToString = function() return name end}
    end
    function methods:IsVisible() touch(self); return self._visible end
    function methods:HasKeyboardFocus() touch(self); return h.focused == self end
    function methods:GetText()
        touch(self)
        local text = self._text
        if type(text) == "function" then text = text() end
        return {ToString = function() return text end}
    end
    local mt = {__index = function(self, key)
        if methods[key] then return methods[key] end
        touch(self)
        local props = rawget(self, "_props")
        props._reads[key] = (props._reads[key] or 0) + 1
        return props[key]
    end}

    local function new(className, path, props)
        local object = setmetatable({_class = className, _path = path, _valid = true,
            _visible = true, _props = props or {}}, mt)
        object._props._reads = {}
        return object
    end
    local function spawn(className, path, props)
        local object = new(className, path, props)
        h.world[#h.world + 1] = object
        return object
    end
    function h:Reads(object, key) return object._props._reads[key] or 0 end
    function h:Destroy(object) object._valid = false end
    function h:ClassExists(name)
        if SUPER[name] then return true end
        for _, object in ipairs(self.world) do
            if object._valid and object._class == name then return true end
        end
        return false
    end
    function h:Instances(className, exact)
        local found = {}
        for _, object in ipairs(self.world) do
            if object._valid and (exact and object._class == className or not exact and IsA(object._class, className)) then
                found[#found + 1] = object
            end
        end
        return found
    end

    -- Native UE4SS globals.
    local gameInstance = spawn("BP_SSGameInstance_C", "/Engine/Transient.GameEngine_2147482611:BP_SSGameInstance_C_2147482468")
    SUPER.BP_SSGameInstance_C = "GameInstance"
    h.gameInstance = gameInstance
    local function classObject(name)
        local object = new("WidgetBlueprintGeneratedClass", "/Script/Mock." .. name)
        object._className = name
        return object
    end
    local widgetLibrary = new("WidgetBlueprintLibrary", "/Script/UMG.Default__WidgetBlueprintLibrary", {
        GetAllWidgetsOfClass = function(_, world, out, class, topLevelOnly)
            touch(world)
            assert(world == gameInstance, "widget query used an unexpected world context")
            assert(topLevelOnly == false, "nested option rows require TopLevelOnly=false")
            for _, object in ipairs(h:Instances(class._className, false)) do
                if IsA(object._class, "UserWidget") then out[#out + 1] = object end
            end
        end})
    StaticFindObject = function(path)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then return widgetLibrary end
        if path == "/Script/UMG.UserWidget" then return classObject("UserWidget") end
        return nil
    end
    FindObjects = function(count, className, objectName, _, bannedFlags, exactClass)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        if className == nil then
            return h:ClassExists(objectName) and {classObject(objectName)} or {}
        end
        local found = {}
        for _, object in ipairs(h:Instances(className, exactClass)) do
            local name = object._path:match("[%.:]([^%.:]+)$")
            if objectName == nil or objectName == name then found[#found + 1] = object end
            if count > 0 and #found >= count then break end
        end
        return found
    end
    FindAllOf = function(className)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        local found = h:Instances(className, false)
        return #found > 0 and found or nil
    end
    FindFirstOf = function(className)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        return h:Instances(className, false)[1]
    end
    LoopAsync = function(_, callback) h.loops[#h.loops + 1] = callback end
    ExecuteInGameThread = function(callback) h.queue[#h.queue + 1] = callback end
    ExecuteWithDelay = function(_, callback) h.loops[#h.loops + 1] = function() callback(); return true end end
    RegisterLoadMapPreHook = function(callback) h.pre = callback end
    RegisterLoadMapPostHook = function(callback) h.post = callback end
    RegisterHook = function() return 1, 2 end
    RegisterKeyBind = function() end
    LoopInGameThreadWithDelay = (not options.legacy) and function() return 1 end or nil

    -- Real reader modules; unrelated specialist screens never claim these widgets.
    for _, name in ipairs(REAL_MODULES) do package.loaded[name] = nil end
    local function noop() end
    for _, name in ipairs(STUBBED_MODULES) do
        package.loaded[name] = setmetatable({}, {__index = function() return noop end})
    end
    -- A specialist screen handler that claims shop items and returns early.
    local shopSpeak = noop
    package.loaded.shop = setmetatable({
        Init = function(speak) shopSpeak = speak end,
        IsShopItem = function(widget) return widget._class == "WBP_OBJ_SH_ItemIcon_S00_C" end,
        OnItemFocused = function() shopSpeak("Senzu Bean, 100 Zeni", true) end,
    }, {__index = function() return noop end})
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

    -- Game objects for the first-run language screen.
    function h:Texture(code)
        local asset = "T_UI_Title_LanguageSelect_" .. code
        return new("Texture2D", TEXTURE_DIR .. asset .. "." .. asset)
    end
    function h:TextBlock(className, path, text, visible)
        local object = spawn(className, path)
        object._text = text
        object._visible = visible ~= false
        return object
    end
    function h:LanguageScreen(textCode, voiceCode)
        self.serial = self.serial + 1
        local id = tostring(2147475505 + self.serial)
        local list = SCREEN .. ".WBP_Option_List_Language_C_" .. id
        local tree = list .. ".WidgetTree_" .. id
        local s = {objects = {}}
        local function add(object) s.objects[#s.objects + 1] = object; return object end
        local function tipFor()
            local row = h.focused and h.focused._path:match("([^%.]+)$")
            if row == "LocalizationTextButton" then
                return "Change the display language.\n*Changing languages will return you to the title screen."
            elseif row == "LocalizationVoiceButton" then return "Change the spoken language."
            end
            return "Adjust the subtitle background during events."
        end
        SUPER.WBP_Option_List_Language_C = "UserWidget"
        SUPER.WBP_OBJ_Option_List_013_Lang_C = "UserWidget"
        SUPER.WBP_OBJ_Option_List_011_Gauge_C = "UserWidget"
        SUPER.WBP_GRP_TTR_Opt_Title_C = "UserWidget"
        SUPER.WBP_Option_Tips_C = "UserWidget"
        add(spawn("WBP_Option_List_Language_C", list))
        local title = add(spawn("WBP_GRP_TTR_Opt_Title_C", SCREEN .. ".WBP_GRP_TTR_Opt_Title_C_" .. id))
        add(self:TextBlock("TextBlock", title._path .. ".WidgetTree.Text_Title", "Language"))
        local tips = add(spawn("WBP_Option_Tips_C", SCREEN .. ".WBP_Option_Tips_C_" .. id))
        add(self:TextBlock("RichTextBlock", tips._path .. ".WidgetTree.TEXT_TipsMain", tipFor))

        local function languageRow(name, label, code)
            local row = add(spawn("WBP_OBJ_Option_List_013_Lang_C", tree .. "." .. name, {
                Title = {ToString = function() return label end}}))
            local image = add(spawn("Image", row._path .. ".WidgetTree.IMG_Lang", {
                Brush = {ResourceObject = self:Texture(code)}}))
            row._props.IMG_Lang = image
            add(self:TextBlock("TextBlock", row._path .. ".WidgetTree.Title", label))
            add(self:TextBlock("TextBlock", row._path .. ".WidgetTree.Text_Disable",
                "Cannot be changed from this screen.", false))
            return row, image
        end
        s.textRow, s.textImage = languageRow("LocalizationTextButton", "Displayed Language", textCode)
        s.voiceRow, s.voiceImage = languageRow("LocalizationVoiceButton", "Voice Language", voiceCode)

        s.gaugeRow = add(spawn("WBP_OBJ_Option_List_011_Gauge_C", tree .. ".BackgroundEventButton"))
        s.gaugeCaption = add(self:TextBlock("TextBlock", s.gaugeRow._path .. ".WidgetTree.caption", "0"))
        s.gaugeRow._props.caption = s.gaugeCaption
        add(self:TextBlock("TextBlock", s.gaugeRow._path .. ".WidgetTree.Title", "Subtitle Background (Event)"))
        return s
    end
    function h:SetLanguage(image, code) image._props.Brush = {ResourceObject = self:Texture(code)} end
    function h:DestroyScreen(s) for _, object in ipairs(s.objects) do self:Destroy(object) end end
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
        local frames = math.floor(seconds / 0.02 + 0.5)
        for _ = 1, frames do self:Frame(0.02) end
    end
    function h:Mark() return #self.spoken end
    function h:Since(mark)
        local entries = {}
        for i = mark + 1, #self.spoken do entries[#entries + 1] = self.spoken[i] end
        return entries
    end
    function h:Count(text, mark)
        local n = 0
        for i = (mark or 0) + 1, #self.spoken do
            if self.spoken[i].text == text then n = n + 1 end
        end
        return n
    end
    function h:IndexOf(text, mark)
        for i = (mark or 0) + 1, #self.spoken do
            if self.spoken[i].text == text then return i end
        end
        return nil
    end
    return h
end

local function Describe(h, mark)
    local parts = {}
    for _, entry in ipairs(h:Since(mark or 0)) do
        parts[#parts + 1] = string.format("%q%s", entry.text, entry.queued and "(queued)" or "")
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end

local function ExpectLabelThenValue(h, mark, label, value)
    local at = h:IndexOf(label, mark)
    assert(at, "label not spoken; heard " .. Describe(h, mark))
    local nextEntry = h.spoken[at + 1]
    assert(nextEntry and nextEntry.text == value,
        "expected " .. value .. " right after " .. label .. "; heard " .. Describe(h, mark))
    assert(nextEntry.queued, "initial value interrupted its own label")
    assert(h:Count(label, mark) == 1, label .. " repeated; heard " .. Describe(h, mark))
    assert(h:Count(value, mark) == 1, value .. " repeated; heard " .. Describe(h, mark))
end

local function ExpectSingleChange(h, mark, value)
    local heard = h:Since(mark)
    assert(#heard == 1, "expected only " .. value .. "; heard " .. Describe(h, mark))
    assert(heard[1].text == value, "expected " .. value .. "; heard " .. Describe(h, mark))
    assert(heard[1].interrupt and not heard[1].queued, "a changed value must interrupt stale speech")
end

local function ExpectHealthy(h)
    assert(h.unsafe == 0, "game objects were touched outside the game thread")
    for _, line in ipairs(h.logs) do
        assert(not line:lower():find("error", 1, true), "reader reported: " .. line)
    end
end

local function FocusedLanguageScreen(options, textCode)
    local h = Harness(options)
    local s = h:LanguageScreen(textCode or "en", "jp")
    h:Focus(s.textRow)
    h:Run(0.5)
    return h, s
end

local cases = {
    {"focus announces the setting, then its current language once", function(options)
        local h = FocusedLanguageScreen(options)
        ExpectLabelThenValue(h, 0, "Displayed Language", "English")
        local tip = "Change the display language. *Changing languages will return you to the title screen."
        assert(h:Count(tip) == 1, "language tip missing; heard " .. Describe(h))
        assert(h:IndexOf(tip) > h:IndexOf("English"), "tip delayed the current value")
        assert(h:Count("Cannot be changed from this screen.") == 0, "hidden disabled notice was spoken")
        ExpectHealthy(h)
    end},
    {"an unchanged selection is not repeated", function(options)
        local h = FocusedLanguageScreen(options)
        local mark = h:Mark()
        h:Run(2)
        assert(#h:Since(mark) == 0, "unchanged selection repeated: " .. Describe(h, mark))
        ExpectHealthy(h)
    end},
    {"Left/Right image changes announce each new language once", function(options)
        local h, s = FocusedLanguageScreen(options)
        local mark = h:Mark()
        h:SetLanguage(s.textImage, "la")
        h:Run(1)
        ExpectSingleChange(h, mark, "Spanish (Latin America)")
        mark = h:Mark()
        h:SetLanguage(s.textImage, "en")
        h:Run(1)
        ExpectSingleChange(h, mark, "English")
        ExpectHealthy(h)
    end},
    {"voice language row reads the same native textures", function(options)
        local h, s = FocusedLanguageScreen(options)
        local mark = h:Mark()
        h:Focus(s.voiceRow)
        h:Run(0.5)
        ExpectLabelThenValue(h, mark, "Voice Language", "Japanese")
        mark = h:Mark()
        h:SetLanguage(s.voiceImage, "en")
        h:Run(1)
        ExpectSingleChange(h, mark, "English")
        ExpectHealthy(h)
    end},
    {"an ordinary text setting keeps its caption polling", function(options)
        local h, s = FocusedLanguageScreen(options)
        local mark = h:Mark()
        h:Focus(s.gaugeRow)
        h:Run(0.5)
        ExpectLabelThenValue(h, mark, "Subtitle Background (Event)", "0")
        mark = h:Mark()
        h:SetLanguage(s.textImage, "fr") -- previous row changes off-focus
        s.gaugeCaption._text = "10"
        h:Run(1)
        ExpectSingleChange(h, mark, "10")
        ExpectHealthy(h)
    end},
    {"a known-label button drops the previous language reader", function(options)
        local h, s = FocusedLanguageScreen(options)
        SUPER.WBP_Title_Button_C = "UserWidget"
        local button = h:TextBlock("WBP_Title_Button_C", SCREEN .. ".WBP_Title_Button_C_1.WidgetTree.OptionButton", nil)
        local mark = h:Mark()
        h:Focus(button)
        h:Run(0.5)
        assert(h:Count("Options", mark) == 1, "known button label missing: " .. Describe(h, mark))
        local reads = h:Reads(s.textImage, "Brush")
        mark = h:Mark()
        h:SetLanguage(s.textImage, "de")
        h:Run(1)
        assert(#h:Since(mark) == 0, "stale language reader spoke: " .. Describe(h, mark))
        assert(h:Reads(s.textImage, "Brush") == reads, "unfocused language image was still polled")
        mark = h:Mark()
        h:Focus(s.textRow)
        h:Run(0.5)
        ExpectLabelThenValue(h, mark, "Displayed Language", "German")
        ExpectHealthy(h)
    end},
    {"a specialist control drops the previous language reader", function(options)
        local h, s = FocusedLanguageScreen(options)
        SUPER.WBP_OBJ_MainMenu_OLB_IDPanel_C = "UserWidget"
        local panelPath = SCREEN .. ".WBP_MenuOLB_IDInput_C_1.WidgetTree.WBP_OBJ_MainMenu_OLB_IDPanel_0"
        local panel = h:TextBlock("WBP_OBJ_MainMenu_OLB_IDPanel_C", panelPath, nil)
        local digit = h:TextBlock("TextBlock", panelPath .. ".WidgetTree.TXT_Num", "5")
        local mark = h:Mark()
        h:Focus(panel)
        h:Run(0.5)
        assert(h:Count("5, digit 1 of 9", mark) == 1, "room ID digit missing: " .. Describe(h, mark))
        local reads = h:Reads(s.textImage, "Brush")
        mark = h:Mark()
        h:SetLanguage(s.textImage, "it")
        digit._text = "6"
        h:Run(1)
        ExpectSingleChange(h, mark, "6")
        assert(h:Reads(s.textImage, "Brush") == reads, "unfocused language image was still polled")
        ExpectHealthy(h)
    end},
    {"a specialist screen handler drops the previous language reader", function(options)
        local h, s = FocusedLanguageScreen(options)
        SUPER.WBP_OBJ_SH_ItemIcon_S00_C = "UserWidget"
        local item = h:TextBlock("WBP_OBJ_SH_ItemIcon_S00_C",
            SCREEN .. ".WBP_GRP_SH_Main_S00_C_1.WidgetTree.WBP_OBJ_SH_ItemIcon_S00", nil)
        local mark = h:Mark()
        h:Focus(item)
        h:Run(0.5)
        assert(h:Count("Senzu Bean, 100 Zeni", mark) == 1, "shop item missing: " .. Describe(h, mark))
        local reads = h:Reads(s.textImage, "Brush")
        mark = h:Mark()
        h:SetLanguage(s.textImage, "ko")
        h:Run(1)
        assert(#h:Since(mark) == 0, "stale language reader spoke: " .. Describe(h, mark))
        assert(h:Reads(s.textImage, "Brush") == reads, "unfocused language image was still polled")
        ExpectHealthy(h)
    end},
    {"map loading never reads the old image; the next map's row is announced", function(options)
        local h, s = FocusedLanguageScreen(options)
        local reads = h:Reads(s.textImage, "Brush")
        local mark = h:Mark()
        if h.pre then
            h.pre()
            h:SetLanguage(s.textImage, "fr")
            h:Run(20) -- far longer than any fixed transition cooldown
            assert(h:Reads(s.textImage, "Brush") == reads, "old language image was read during map load")
            assert(#h:Since(mark) == 0, "spoke during map load: " .. Describe(h, mark))
        else
            assert(h.legacy, "map pre-hook missing on a fixed loader")
        end
        h:DestroyScreen(s)
        local nextScreen = h:LanguageScreen("jp", "en")
        h:Focus(nextScreen.textRow)
        h.post()
        h:Run(1.5)
        assert(h:Reads(s.textImage, "Brush") == reads, "old language image was read after the map changed")
        ExpectLabelThenValue(h, mark, "Displayed Language", "Japanese")
        mark = h:Mark()
        h:SetLanguage(nextScreen.textImage, "en")
        h:Run(1)
        ExpectSingleChange(h, mark, "English")
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
assert(failures == 0, tostring(failures) .. " language focus regressions")
