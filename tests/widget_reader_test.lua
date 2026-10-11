-- Scope regression tests for widget_reader.lua. The real helpers,
-- widget_reader and language_options modules read a simulated UMG hierarchy:
-- user widgets own WidgetTrees, panels own slotted children, object paths
-- follow Unreal's outer chain (".WidgetTree_<id>." after each owner, as in
-- the live captures), and visibility, render opacity and switcher pages
-- behave like UMG. Calls that a class does not support raise errors as they
-- do through UE4SS. Every case runs against the engine widget query (UE4SS
-- 1152) and the stock 3.0.1 FindObjects path, with and without readable
-- WidgetTree properties. Run from the repository root with LuaJIT or Lua 5.4.
package.path = "./SparkingZeroAccess/?.lua;" .. package.path

local realPrint = print
local GAME = "/Engine/Transient.GameEngine_2147482611:BP_SSGameInstance_C_2147482468"
local TEXTURE_DIR = "/Game/SS/UI/Title/OBJ/Texture/"
local DISABLED_NOTICE = "Cannot be changed from this screen."

local BASE_CLASSES = {
    Widget = "Object", UserWidget = "Widget", PanelWidget = "Widget",
    TextLayoutWidget = "Widget", TextBlock = "TextLayoutWidget", RichTextBlock = "TextLayoutWidget",
    Image = "Widget", WidgetTree = "Object", GameInstance = "Object",
    BP_SSGameInstance_C = "GameInstance", Texture2D = "Object",
    VerticalBox = "PanelWidget", Overlay = "PanelWidget", CanvasPanel = "PanelWidget",
    WidgetSwitcher = "PanelWidget",
}

local function Engine(options)
    local e = {objects = {}, serial = 2147475000, logs = {}}
    local super = {}
    for class, base in pairs(BASE_CLASSES) do super[class] = base end
    local function IsA(class, target)
        while class do
            if class == target then return true end
            class = super[class]
        end
        return false
    end

    local methods = {}
    local function Live(self)
        if not self._valid then error("Object is not valid", 3) end
    end
    local function Need(self, base, name)
        if not IsA(self._class, base) then error(name .. " is not a member of " .. self._class, 3) end
    end
    function methods:IsValid() return self._valid end
    function methods:type() return "UObject" end
    function methods:GetFullName() Live(self); return self._class .. " " .. self._path end
    function methods:GetOuter() Live(self); return self._outer end
    function methods:IsVisible() Live(self); Need(self, "Widget", "IsVisible"); return self._visible end
    function methods:GetParent() Live(self); Need(self, "Widget", "GetParent"); return self._parent end
    function methods:GetText()
        Live(self); Need(self, "TextLayoutWidget", "GetText")
        local text = self._text
        return {ToString = function() return text end}
    end
    function methods:GetChildrenCount()
        Live(self); Need(self, "PanelWidget", "GetChildrenCount")
        return #self._children
    end
    function methods:GetChildAt(index)
        Live(self); Need(self, "PanelWidget", "GetChildAt")
        return self._children[index + 1]
    end
    function methods:GetChildIndex(child)
        Live(self); Need(self, "PanelWidget", "GetChildIndex")
        for i, c in ipairs(self._children) do
            if c == child then return i - 1 end
        end
        return -1
    end
    function methods:GetActiveWidgetIndex()
        Live(self); Need(self, "WidgetSwitcher", "GetActiveWidgetIndex")
        return self._active
    end
    function methods:GetActiveWidget()
        Live(self); Need(self, "WidgetSwitcher", "GetActiveWidget")
        return self._children[self._active + 1]
    end
    local mt = {__index = function(self, key)
        if methods[key] then return methods[key] end
        Live(self)
        if key == "WidgetTree" and options.unreadableTrees then return nil end
        return rawget(self, "_props")[key]
    end}

    local function Spawn(class, path, outer)
        local object = setmetatable({_class = class, _path = path, _outer = outer, _valid = true,
            _visible = true, _props = {RenderOpacity = 1}}, mt)
        e.objects[#e.objects + 1] = object
        return object
    end
    local function NextId()
        e.serial = e.serial + 1
        return tostring(e.serial)
    end
    local function OwnTree(widget)
        local tree = Spawn("WidgetTree", widget._path .. ".WidgetTree_" .. NextId(), widget)
        widget._tree, widget._props.WidgetTree = tree, tree
        return widget
    end
    -- A user widget parent receives the widget as its tree root; a panel
    -- parent slots it as its next child, in the panel's own tree.
    local function Place(class, name, parent)
        if parent._tree then
            local tree = parent._tree
            assert(not tree._props.RootWidget, "widget tree already has a root")
            local widget = Spawn(class, tree._path .. "." .. name, tree)
            tree._props.RootWidget = widget
            return widget
        end
        assert(parent._children, parent._path .. " is not a panel")
        local widget = Spawn(class, parent._outer._path .. "." .. name, parent._outer)
        widget._parent = parent
        parent._children[#parent._children + 1] = widget
        return widget
    end

    e.game = Spawn("BP_SSGameInstance_C", GAME, nil)
    function e:Screen(class)
        super[class] = super[class] or "UserWidget"
        return OwnTree(Spawn(class, GAME .. "." .. class .. "_" .. NextId(), self.game))
    end
    function e:User(class, name, parent)
        super[class] = super[class] or "UserWidget"
        return OwnTree(Place(class, name, parent))
    end
    function e:Panel(class, name, parent)
        local panel = Place(class, name, parent)
        panel._children = {}
        if IsA(class, "WidgetSwitcher") then panel._active = 0 end
        return panel
    end
    function e:Text(name, parent, text, class)
        local block = Place(class or "TextBlock", name, parent)
        block._text = text
        return block
    end
    function e:Image(name, parent) return Place("Image", name, parent) end
    -- Removed from its panel (or never added): still outered to the tree.
    function e:Detached(name, owner, text)
        local block = Spawn("TextBlock", owner._tree._path .. "." .. name, owner._tree)
        block._text = text
        return block
    end
    function e:Texture(code)
        local asset = "T_UI_Title_LanguageSelect_" .. code
        return Spawn("Texture2D", TEXTURE_DIR .. asset .. "." .. asset, nil)
    end
    -- Destroyed widgets leave their panel; everything they own becomes invalid.
    function e:Destroy(widget)
        for _, object in ipairs(self.objects) do
            if object == widget or object._path:sub(1, #widget._path + 1) == widget._path .. "." then
                object._valid = false
            end
        end
        local parent = widget._parent
        if parent then
            for i, child in ipairs(parent._children) do
                if child == widget then table.remove(parent._children, i) break end
            end
        end
    end
    function e:Instances(class)
        local found = {}
        for _, object in ipairs(self.objects) do
            if object._valid and IsA(object._class, class) then found[#found + 1] = object end
        end
        return found
    end

    -- UE4SS globals used by helpers.lua.
    local function ClassObject(name)
        return {_className = name, IsValid = function() return true end, type = function() return "UObject" end}
    end
    local library = {IsValid = function() return true end, type = function() return "UObject" end,
        GetAllWidgetsOfClass = function(_, world, out, class, topLevelOnly)
            assert(world == e.game, "widget query used an unexpected world context")
            assert(topLevelOnly == false, "nested widgets require TopLevelOnly=false")
            for _, object in ipairs(e:Instances(class._className)) do out[#out + 1] = object end
        end}
    StaticFindObject = function(path)
        if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then return library end
        if path == "/Script/UMG.UserWidget" then return ClassObject("UserWidget") end
        return nil
    end
    FindObjects = function(count, class, name, required, banned, exact)
        if class == nil or (class == "Class" and name ~= nil and exact == false) then
            return super[name] and {ClassObject(name)} or {}
        end
        local found = {}
        for _, object in ipairs(e:Instances(class)) do
            if name == nil or object._path:match("[%.:]([^%.:]+)$") == name then found[#found + 1] = object end
            if count > 0 and #found >= count then break end
        end
        return found
    end
    FindAllOf = function(class)
        local found = e:Instances(class)
        return #found > 0 and found or nil
    end
    FindFirstOf = function(class) return e:Instances(class)[1] end
    LoopInGameThreadWithDelay = (not options.stock) and function() return 1 end or nil
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        e.logs[#e.logs + 1] = table.concat(parts, " ")
    end

    for _, name in ipairs({"helpers", "language_options", "widget_reader"}) do package.loaded[name] = nil end
    e.H = require("helpers")
    e.WR = require("widget_reader")
    return e
end

-- Each read starts a new polling cycle, as the game-thread scheduler does.
local function Label(e, widget)
    e.H.BeginReadCycle()
    return e.WR.GetSpokenLabel(widget)
end

local function Title(e, widget)
    e.H.BeginReadCycle()
    return (e.WR.ReadWidgetTexts(widget))
end

local function Expect(actual, expected, what)
    if actual ~= expected then
        error(what .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function Logged(e, text)
    for _, line in ipairs(e.logs) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

-- An SSMenuButton option row: Title and caption texts, plus the disabled
-- notice that stays collapsed until the row is disabled.
local function OptionRow(e, parent, name, title, caption, class)
    local row = e:User(class or "WBP_OBJ_Option_List_010_Text_C", name, parent)
    local root = e:Panel("Overlay", "Root", row)
    row.title = e:Text("Title", root, title)
    if caption then
        row.caption = e:Text("caption", root, caption)
        row._props.caption = row.caption
    end
    row.disable = e:Panel("Overlay", "Disable", root)
    row.disable._visible = false
    row.notice = e:Text("Text_Disable", row.disable, DISABLED_NOTICE)
    return row
end

local function MenuItem(e, parent, class, name, caption, title)
    local item = e:User(class, name, parent)
    local root = e:Panel("Overlay", "Root", item)
    if title then e:Text("Text_Title", root, title) end
    item.caption = e:Text("caption", root, caption)
    item._props.caption = item.caption
    return item
end

local function StageList(e, captionPrefix, count)
    local screen = e:Screen("WBP_GRP_BS_StageList_DP2_C")
    local canvas = e:Panel("CanvasPanel", "Canvas", screen)
    local hits, items = {}, {}
    for i = 0, count - 1 do
        hits[i] = e:User("WBP_OBJ_Common_HitBtn_Text_C", string.format("WBP_OBJ_Common_HitBtn_Text_%02d", i), canvas)
    end
    for i = 0, count - 1 do
        items[i] = MenuItem(e, canvas, "WBP_OBJ_BS_BTN_Menu_DP_C",
            string.format("WBP_OBJ_BS_BTN_Menu_DP_%02d", i), captionPrefix .. " " .. i)
    end
    return screen, hits, items, canvas
end

local function LanguageScreen(e, voiceTitle, textTitle, textCode)
    local screen = e:Screen("WBP_Option_List_Language_C")
    local list = e:Panel("VerticalBox", "VBOX_List", screen)
    local function Row(name, title, code)
        local row = OptionRow(e, list, name, title, nil, "WBP_OBJ_Option_List_013_Lang_C")
        row._props.Title = {ToString = function() return title end}
        local image = e:Image("IMG_Lang", row._tree._props.RootWidget)
        image._props.Brush = {ResourceObject = e:Texture(code)}
        row._props.IMG_Lang = image
        return row, image
    end
    local voice = Row("LocalizationVoiceButton", voiceTitle, "jp")
    local text, image = Row("LocalizationTextButton", textTitle, textCode)
    return screen, text, image, voice
end

local cases = {
    {"native remote captions follow the focused hit area despite different row numbers", function(e)
        local screen = e:Screen("WBP_GRP_CSG_Top_00_C")
        local canvas = e:Panel("CanvasPanel", "Canvas", screen)
        local hit = e:User("WBP_OBJ_Common_HitButton_C", "WBP_OBJ_Common_HitButton_1", canvas)
        local row = MenuItem(e, canvas, "WBP_OBJ_CSG_BTN_00_C", "WBP_OBJ_CSG_BTN_00", "Select Training Type")
        MenuItem(e, canvas, "WBP_OBJ_BS_BTN_Menu_C", "WBP_OBJ_BS_BTN_Menu_1", "Unrelated numbered caption")
        hit._props.RemoteButton = row
        local label, matched, value, ref = Label(e, hit)
        Expect(label, "Select Training Type", "native linked caption")
        assert(matched == row and ref == row.caption, "linked caption is not polled")
        Expect(value, "Select Training Type", "caption value")
        row.caption._text = "Close-Range Maneuvers"
        Expect(Label(e, hit), "Close-Range Maneuvers", "fresh linked caption")
    end},
    {"remote labels are ignored when hidden, detached or destroyed", function(e)
        local screen = e:Screen("WBP_GRP_CSG_Top_00_C")
        local canvas = e:Panel("CanvasPanel", "Canvas", screen)
        local hit = e:User("WBP_OBJ_Common_HitButton_C", "WBP_OBJ_Common_HitButton_1", canvas)
        local row = MenuItem(e, canvas, "WBP_OBJ_CSG_BTN_00_C", "WBP_OBJ_CSG_BTN_00", "Secret stale label")
        hit._props.RemoteButton = row
        row._visible = false
        Expect(Label(e, hit), "Common HitButton 1", "hidden remote caption")
        row._visible = true
        row._props.RenderOpacity = 0
        Expect(Label(e, hit), "Common HitButton 1", "transparent remote caption")
        row._props.RenderOpacity = 1
        row._parent = nil
        Expect(Label(e, hit), "Common HitButton 1", "detached remote caption")
        row._valid = false
        Expect(Label(e, hit), "Common HitButton 1", "destroyed remote caption")
    end},
    {"remote links cannot borrow a caption from another screen", function(e)
        local screen = e:Screen("WBP_GRP_CSG_Top_00_C")
        local canvas = e:Panel("CanvasPanel", "Canvas", screen)
        local hit = e:User("WBP_OBJ_Common_HitButton_C", "WBP_OBJ_Common_HitButton_1", canvas)
        local other = e:Screen("WBP_GRP_CSG_Top_00_C")
        local box = e:Panel("CanvasPanel", "Canvas", other)
        local row = MenuItem(e, box, "WBP_OBJ_CSG_BTN_00_C", "WBP_OBJ_CSG_BTN_00", "Other screen")
        hit._props.RemoteButton = row
        Expect(Label(e, hit), "Common HitButton 1", "foreign remote caption")
    end},
    {"a setting row reads only its own title, never a row whose name contains it", function(e)
        -- An older options screen and "BattleAssistControlButton" are queried
        -- first, so a substring search on "ControlButton" would reach them first.
        local old = e:Screen("WBP_Option_List_Control_C")
        OptionRow(e, e:Panel("VerticalBox", "VBOX_List", old), "ControlButton", "Old Control Type", "Classic")
        old._visible = false
        local screen = e:Screen("WBP_Option_List_Control_C")
        local list = e:Panel("VerticalBox", "VBOX_List", screen)
        OptionRow(e, list, "BattleAssistControlButton", "Battle Assist", "On")
        local control = OptionRow(e, list, "ControlButton", "Control Type", "Standard")
        local label, matched, value, ref, reader = Label(e, control)
        Expect(label, "Control Type", "label")
        assert(matched == control, "value owner is not the focused row")
        Expect(value, "Standard", "initial value")
        assert(ref == control.caption, "polled value is not the row's own caption")
        assert(reader == nil, "a text row needs no value reader")
        Expect(Title(e, control), label, "re-read title (main speaks the value only when they match)")
    end},
    {"a setting row whose class was not listed still reads its title and value", function(e)
        -- Live capture: the subtitle background rows are 012_TextAlpha rows.
        local screen = e:Screen("WBP_Option_List_Language_C")
        local list = e:Panel("VerticalBox", "VBOX_List", screen)
        local row = OptionRow(e, list, "BackgroundEventButton", "Subtitle Background (Event)", "0",
            "WBP_OBJ_Option_List_012_TextAlpha_C")
        local label, matched, value, ref = Label(e, row)
        Expect(label, "Subtitle Background (Event)", "label")
        Expect(value, "0", "initial value")
        assert(matched == row and ref == row.caption, "value is not polled from the row's caption")
        Expect(Title(e, row), label, "re-read title")
    end},
    {"hidden, transparent and inactive-page captions are never read", function(e)
        local screen = e:Screen("WBP_Option_List_KeyConfig_C")
        local list = e:Panel("VerticalBox", "VBOX_List", screen)
        local row = e:User("WBP_OBJ_Option_KeyConfig_C", "GuardKeyButton", list)
        local root = e:Panel("Overlay", "Root", row)
        -- Stale captions precede the displayed one in every query order.
        e:Detached("caption", row, "Removed binding")
        local hidden = e:Panel("Overlay", "Overlay_Keyboard", root)
        hidden._visible = false
        MenuItem(e, hidden, "WBP_OBJ_Option_ChangeKey_C", "ChangeKey_Keyboard", "Q")
        e:Text("Title", hidden, "Old Guard Title")
        local faded = e:Panel("Overlay", "Overlay_Fade", root)
        faded._props.RenderOpacity = 0
        MenuItem(e, faded, "WBP_OBJ_Option_ChangeKey_C", "ChangeKey_Faded", "E")
        e:Text("Title", root, "Guard")
        local pages = e:Panel("WidgetSwitcher", "Switcher_Device", root)
        MenuItem(e, pages, "WBP_OBJ_Option_ChangeKey_C", "ChangeKey_Old", "Old binding")
        local pad = MenuItem(e, pages, "WBP_OBJ_Option_ChangeKey_C", "ChangeKey_Pad", '<icon id="Pad_04" table="XSX"/>')
        pages._active = 1
        local disable = e:Panel("Overlay", "Disable", root)
        disable._visible = false
        e:Text("Text_Disable", disable, DISABLED_NOTICE)

        local label, matched, value, ref = Label(e, row)
        Expect(label, "Guard", "label")
        assert(matched == row, "value owner is not the focused row")
        Expect(value, '<icon id="Pad_04" table="XSX"/>', "displayed binding")
        assert(ref == pad.caption, "polled value is not the displayed binding")
        -- The hidden title must not replace the displayed one either.
        Expect(Title(e, row), "Guard", "re-read title")
    end},
    {"a row's own title and native caption outrank nested texts", function(e)
        local screen = e:Screen("WBP_Option_List_Graphics_C")
        local list = e:Panel("VerticalBox", "VBOX_List", screen)
        local row = e:User("WBP_OBJ_Option_List_011_Gauge_C", "BrightnessButton", list)
        local root = e:Panel("Overlay", "Root", row)
        -- A nested gauge widget with its own title and caption comes first.
        local gauge = MenuItem(e, root, "WBP_OBJ_Option_Gauge_C", "Gauge", "Press A to adjust", "Level")
        e:Text("Title", root, "Brightness")
        local number = e:Text("Text_Num", root, "5")
        row._props.caption = number
        local label, matched, value, ref = Label(e, row)
        Expect(label, "Brightness, Level, Press A to adjust", "label")
        Expect(value, "5", "native caption value")
        assert(matched == row and ref == number and ref ~= gauge.caption, "value is not the native caption")
        Expect(Title(e, row), label, "re-read title")
    end},
    {"a disabled row reads its displayed notice with the label", function(e)
        local screen = e:Screen("WBP_Option_List_Control_C")
        local list = e:Panel("VerticalBox", "VBOX_List", screen)
        local row = OptionRow(e, list, "BattleAssistButton", "Battle Assist", "On")
        local label = Label(e, row)
        Expect(label, "Battle Assist", "label while enabled")
        row.disable._visible = true
        local disabledLabel, _, value = Label(e, row)
        Expect(disabledLabel, "Battle Assist, " .. DISABLED_NOTICE, "label while disabled")
        Expect(value, "On", "value while disabled")
        Expect(Title(e, row), disabledLabel, "re-read title")
    end},
    {"value changes are read through the returned value widget", function(e)
        local screen = e:Screen("WBP_Option_List_Sound_C")
        local list = e:Panel("VerticalBox", "VBOX_List", screen)
        local row = OptionRow(e, list, "BGMVolumeButton", "BGM Volume", "5", "WBP_OBJ_Option_List_011_Gauge_C")
        local _, _, value, ref = Label(e, row)
        Expect(value, "5", "initial value")
        row.caption._text = "6"
        Expect(ref:GetText():ToString(), "6", "polled caption after Right")
        -- A row without a native caption polls the text displayed beside its title.
        local plain = e:User("WBP_OBJ_Option_List_Plain_C", "VibrationButton", list)
        local root = e:Panel("Overlay", "Root", plain)
        e:Text("Title", root, "Vibration")
        local valueText = e:Text("TXT_Value", root, "On")
        local label, matched, plainValue, plainRef = Label(e, plain)
        Expect(label, "Vibration", "label without native caption")
        Expect(plainValue, "On", "value without native caption")
        assert(matched == plain and plainRef == valueText, "value widget is not the displayed value")
        valueText._text = "Off"
        Expect(plainRef:GetText():ToString(), "Off", "polled value after Left")
        Expect(Title(e, plain), label, "re-read title")
    end},
    {"duplicate hit areas use the numbered item under their own screen", function(e)
        local oldScreen = StageList(e, "Old Stage", 6)
        oldScreen._visible = false
        local _, hits, items = StageList(e, "Stage", 6)
        local label, matched, value, ref = Label(e, hits[5])
        Expect(label, "Stage 5", "label")
        assert(matched == items[5], "matched another screen's menu item")
        Expect(value, "Stage 5", "polled caption")
        assert(ref == items[5].caption, "caption widget belongs to another screen")
        Expect(Title(e, items[5]), nil, "caption-only item title (would repeat the label)")
        -- If this screen lacks item 05, the old screen's item is not borrowed.
        e:Destroy(items[5])
        local fallback = Label(e, hits[5])
        Expect(fallback, "Common HitBtn Text 05", "label without a matching item")
        assert(Logged(e, "No match found for: WBP_OBJ_Common_HitBtn_Text_05"), "missing match was not logged")
    end},
    {"a hit area's own list wins and a missing number is not borrowed from another list", function(e)
        local screen = e:Screen("WBP_GRP_BS_Setting_C")
        local canvas = e:Panel("CanvasPanel", "Canvas", screen)
        -- A screen-level menu precedes the rule list in query order.
        MenuItem(e, canvas, "WBP_OBJ_BS_BTN_Menu_DP_C", "WBP_OBJ_BS_BTN_Menu_DP_03", "Stage Select")
        MenuItem(e, canvas, "WBP_OBJ_BS_BTN_Menu_DP_C", "WBP_OBJ_BS_BTN_Menu_DP_05", "BGM Select")
        local rules = e:User("WBP_GRP_BS_RuleList_C", "RuleList", canvas)
        local ruleCanvas = e:Panel("CanvasPanel", "Canvas", rules)
        local hit3 = e:User("WBP_OBJ_Common_HitBtn_Text_C", "WBP_OBJ_Common_HitBtn_Text_03", ruleCanvas)
        local hit5 = e:User("WBP_OBJ_Common_HitBtn_Text_C", "WBP_OBJ_Common_HitBtn_Text_05", ruleCanvas)
        local rule3 = MenuItem(e, ruleCanvas, "WBP_OBJ_BS_SetRuleBTN_C", "WBP_OBJ_BS_SetRuleBTN_03",
            "180 Seconds", "Time Limit")
        local label, matched, value = Label(e, hit3)
        Expect(label, "Time Limit", "label from the rule list")
        assert(matched == rule3, "matched the screen-level menu item")
        Expect(value, "180 Seconds", "rule value")
        Expect(Title(e, rule3), "Time Limit", "re-read title")
        local missing = Label(e, hit5)
        Expect(missing, "Common HitBtn Text 05", "label for the rule list's missing item")
    end},
    {"a numbered item on a collapsed page does not label the hit area", function(e)
        local _, _, _, canvas = StageList(e, "Stage", 2)
        local hit = e:User("WBP_OBJ_Common_HitBtn_Text_C", "WBP_OBJ_Common_HitBtn_Text_02", canvas)
        -- The item itself is visible; only its page is collapsed.
        local page = e:Panel("Overlay", "Overlay_Page2", canvas)
        page._visible = false
        MenuItem(e, page, "WBP_OBJ_BS_BTN_Menu_DP_C", "WBP_OBJ_BS_BTN_Menu_DP_02", "Stage 2")
        Expect(Label(e, hit), "Common HitBtn Text 02", "label from a collapsed page")
        page._visible = true
        Expect(Label(e, hit), "Stage 2", "label after the page is shown")
    end},
    {"list position counts only displayed items of the focused list", function(e)
        local oldScreen = StageList(e, "Old Stage", 10)
        oldScreen._visible = false
        local _, hits = StageList(e, "Stage", 4)
        hits[2]._visible = false
        Label(e, hits[3])
        local position, total = e.WR.GetListPosition("WBP_OBJ_Common_HitBtn_Text_03")
        Expect(position, 3, "position after the labeled widget")
        Expect(total, 3, "total after the labeled widget")
        position, total = e.WR.GetListPosition("WBP_OBJ_Common_HitBtn_Text_01", hits[1])
        Expect(position, 2, "position of an explicit widget")
        Expect(total, 3, "total of an explicit widget")
    end},
    {"text inside nested widgets labels a wrapper and values change live", function(e)
        local screen = e:Screen("WBP_MainMenu_Mode_C")
        local box = e:Panel("VerticalBox", "VBOX_Buttons", screen)
        local wrapper = e:User("WBP_OBJ_MainMenu_BTN_Wrap_C", "BTN_Training", box)
        local inner = MenuItem(e, wrapper, "WBP_OBJ_Common_ButtonBase_C", "ButtonBase", "Training")
        local label, matched, value, ref = Label(e, wrapper)
        Expect(label, "Training", "label from nested caption")
        assert(matched == wrapper and ref == inner.caption, "nested caption is not polled")
        Expect(value, "Training", "polled caption")
        Expect(Title(e, wrapper), nil, "caption-only title (would repeat the label)")
    end},
    {"language rows keep their image reader and their own title", function(e)
        -- An older screen with the same row names is queried first.
        local oldScreen, _, _, oldVoice = LanguageScreen(e, "Old Voice Title", "Old Display Title", "jp")
        oldScreen._visible = false
        oldVoice._props.Title = {ToString = function() return "" end}
        local _, row, image, voice = LanguageScreen(e, "Voice Language", "Displayed Language", "en")
        local label, matched, value, ref, reader = Label(e, row)
        Expect(label, "Displayed Language", "label")
        assert(matched == row and ref == nil and type(reader) == "function", "language value reader missing")
        Expect(value, "English", "initial language")
        image._props.Brush = {ResourceObject = e:Texture("la")}
        Expect(reader(), "Spanish (Latin America)", "changed language")
        -- Without a native Title, the row's own displayed title is used.
        voice._props.Title = {ToString = function() return "" end}
        local voiceLabel, _, voiceValue = Label(e, voice)
        Expect(voiceLabel, "Voice Language", "title from the row's own text")
        Expect(voiceValue, "Japanese", "voice language")
    end},
    {"an unused row's template title is not spoken", function(e)
        local screen = e:Screen("WBP_Option_List_Game_C")
        local list = e:Panel("VerticalBox", "VBOX_List", screen)
        local row = OptionRow(e, list, "SettingButton_07", "設定項目", "On")
        local label, matched, value = Label(e, row)
        Expect(label, "On", "label without the template title")
        assert(matched == row and value == "On", "caption is no longer polled")
        Expect(Title(e, row), nil, "template title")
    end},
    {"widgets without any displayed text keep the cleaned name", function(e)
        local screen = e:Screen("WBP_GRP_Test_C")
        local canvas = e:Panel("CanvasPanel", "Canvas", screen)
        local button = e:User("WBP_OBJ_Common_Empty_C", "WBP_OBJ_Confirm_Button", canvas)
        local root = e:Panel("Overlay", "Root", button)
        local hidden = e:Text("caption", root, "Stale")
        hidden._visible = false
        button._props.caption = hidden
        local label, matched, value, ref = Label(e, button)
        Expect(label, "Confirm", "cleaned name")
        assert(matched == nil and value == nil and ref == nil, "hidden caption was returned")
    end},
}

local variants = {
    {"UE4SS 1152", {}},
    {"stock UE4SS 3.0.1", {stock = true}},
    {"UE4SS 1152, unreadable WidgetTree", {unreadableTrees = true}},
    {"stock UE4SS 3.0.1, unreadable WidgetTree", {stock = true, unreadableTrees = true}},
}

local failures = 0
for _, variant in ipairs(variants) do
    for _, case in ipairs(cases) do
        local e
        local ok, err = pcall(function()
            e = Engine(variant[2])
            case[2](e)
            for _, line in ipairs(e.logs) do
                assert(not line:lower():find("error", 1, true), "reader reported: " .. line)
            end
            if variant[2].unreadableTrees then
                assert(Logged(e, "Widget tree unreadable for"), "path-scope fallback was not reported")
            end
        end)
        print = realPrint
        local label = variant[1] .. ": " .. case[1]
        if ok then print("PASS: " .. label)
        else failures = failures + 1; print("FAIL: " .. label .. ": " .. tostring(err)) end
    end
end
print = realPrint
assert(failures == 0, tostring(failures) .. " widget reader regressions")
