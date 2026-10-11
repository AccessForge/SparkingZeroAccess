--[[
    widget_reader.lua — Text reading, widget matching, and label resolution
    Handles reading text from widgets, matching numbered hit buttons to labels,
    and resolving what to speak for a given focused widget.

    Scope rules: a widget's text comes only from its own attached subtree, and
    only while displayed. Hidden or collapsed ancestors, transparent ancestors
    and inactive switcher pages exclude their text. A hit area's label widget
    must share the nearest owning user widget with it. Nothing is matched by
    instance-name substring, and text is never cached.
]]

local H = require("helpers")
local FindAllOf = H.FindAllOf
local TryCall = H.TryCall
local TryGetProperty = H.TryGetProperty
local IsValidRef = H.IsValidRef
local GetWidgetName = H.GetWidgetName
local GetClassName = H.GetClassName
local Languages = require("language_options")

local WidgetReader = {}

-- === WIDGET LABELS & SUPPRESSION ===

WidgetReader.WidgetLabels = {
    StartButton = "Start",
    OptionButton = "Options",
    QuitButton = "Quit",
    StoreButton = "Store",
    GameStart_Button = "Start",
    GameQuit_Button = "Quit",
    WBP_OBJ_Common_HitBTN_Replace = "Switch",
    WBP_OBJ_Common_HitBTN_Remove = "Remove",
    WBP_OBJ_Toggle_HitButton = "Switch View",
    -- Shop top
    WBP_OBJ_SH_BTN_Shop = "Shop",
    WBP_OBJ_SH_BTN_Customize = "Customize",
    -- Pause menu
    ResumeButton = "Close Menu",
    RetryButton = "Retry",
    CommandListButton = "Explain Controls",
    StageSelectButton = "Stage Select",
}

WidgetReader.SuppressedClasses = {
    ["WBP_MainMenu_Base_C"] = true,
    ["WBP_MainMenu_ModeMenu_C"] = true,
    ["WBP_GRP_BS_StageList_DP2_C"] = true,
    ["WBP_GRP_BS_StageTop_DP_C"] = true,
    ["WBP_GRP_BS_CharaList_DP_C"] = true,
    ["WBP_GRP_BS_Top_00_1P_C"] = true,
    ["WBP_GRP_BS_Top_00_2P_C"] = true,
    ["WBP_GRP_BS_ChList_TeamList_DB_C"] = true,
    ["WBP_GRP_BS_Top_00_BtnSet_C"] = true,
    ["WBP_GRP_AI_CharacterSelect_C"] = true,
    ["WBP_GRP_SH_Top_C"] = true,
    ["WBP_GRP_SH_Main_00_C"] = true,
    ["WBP_GRP_SH_Main_S00_C"] = true,
    ["WBP_GRP_SH_Main_L00_C"] = true,
}

-- === WIDGET TREE SCOPE ===

local TITLE_NAMES = {Text_Title = true, Title = true, TitleText = true, TXT_Label = true}
local LABEL_CLASS_PARTS = {"BTN_Menu", "SetBGMBTN", "SetRuleBTN"}
local LEAF_CLASSES = {Image = true, Spacer = true, ProgressBar = true, Throbber = true,
    CircularThrobber = true, Slider = true}
local PLACEHOLDER = "設定項目" -- template caption of unused setting rows
local MAX_NODES, MAX_LEVELS, MAX_HOPS, MAX_EXTRAS = 256, 32, 64, 3
local reportedTrees = {}
-- Reference only: GetListPosition receives just the name from main.lua.
local lastLabeled, lastLabeledName = nil, nil

-- "Class /Path" -> class, path. Object names cannot contain spaces.
local function Identify(object)
    local full = TryCall(object, "GetFullName")
    if type(full) ~= "string" then return nil, nil end
    return full:match("^(%S+) (.+)$")
end

local function LeafName(path)
    return path:match("[%.:]([^%.:]+)$") or path
end

-- A user widget's designed and created children are outered to its
-- WidgetTree, so ".WidgetTree_<id>." follows the owner's path in theirs.
-- Returns every owning user widget, nearest first.
local function Owners(path)
    local owners, from = {}, 1
    while true do
        local s, e = path:find("%.WidgetTree[_%d]*%.", from)
        if not s then return owners end
        table.insert(owners, 1, path:sub(1, s - 1))
        from = e
    end
end

local function IsUnder(path, ownerPath)
    return path:sub(1, #ownerPath + 1) == ownerPath .. "."
end

local function IsTextClass(class)
    return class:sub(-9) == "TextBlock" or class:find("EditableText", 1, true) ~= nil
end

local function ReadText(widget)
    local text = TryCall(TryCall(widget, "GetText"), "ToString")
    if type(text) == "string" and text:match("%S") then return text end
    return nil
end

local function Clean(text)
    return (text:gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

local function IsDisplayed(widget)
    if TryCall(widget, "IsVisible") == false then return false end
    local opacity = TryGetProperty(widget, "RenderOpacity")
    return type(opacity) ~= "number" or opacity > 0.001
end

-- Returns the tree's root widget, and whether the WidgetTree itself was
-- readable (an empty tree is readable but has no root).
local function TreeRoot(userWidget)
    local tree = TryGetProperty(userWidget, "WidgetTree")
    if not (tree and IsValidRef(tree)) then return nil, false end
    local root = TryGetProperty(tree, "RootWidget")
    if root and IsValidRef(root) then return root, true end
    return nil, true
end

-- Only a switcher's active page is displayed. An unknown page stays readable.
local function IsActivePage(switcher, child, childPath)
    local active = TryCall(switcher, "GetActiveWidget")
    if active and IsValidRef(active) then
        local _, activePath = Identify(active)
        if activePath then return activePath == childPath end
    end
    local index = TryCall(switcher, "GetActiveWidgetIndex")
    local childIndex = TryCall(switcher, "GetChildIndex", child)
    if type(index) == "number" and type(childIndex) == "number" and childIndex >= 0 then
        return index == childIndex
    end
    return true
end

-- True when the widget and each ancestor below stopPath are displayed.
-- Tree roots continue at the user widget that owns the tree. memo shares
-- verified ancestors between calls with the same stopPath.
local function IsShownWithin(widget, stopPath, memo)
    local node, walked = widget, {}
    local _, path = Identify(node)
    for _ = 1, MAX_HOPS do
        if not path then return false end
        local known = memo and memo[path]
        if path == stopPath or known then
            if memo then for _, p in ipairs(walked) do memo[p] = true end end
            return true
        end
        if known == false or not IsDisplayed(node) then
            if memo then memo[path] = false end
            return false
        end
        walked[#walked + 1] = path
        local parent = TryCall(node, "GetParent")
        if parent and IsValidRef(parent) then
            local parentClass, parentPath = Identify(parent)
            if parentClass and parentClass:find("Switcher", 1, true)
            and not IsActivePage(parent, node, path) then
                return false
            end
            node, path = parent, parentPath
        else
            local owner = path:match("^(.+)%.WidgetTree[_%d]*%.[^%.:]+$")
            if not owner then return true end
            local tree = TryCall(node, "GetOuter")
            local root = tree and TryGetProperty(tree, "RootWidget")
            if root and IsValidRef(root) then
                local _, rootPath = Identify(root)
                if rootPath and rootPath ~= path then return false end -- removed from its tree
            end
            if owner == stopPath then return true end
            node = tree and TryCall(tree, "GetOuter")
            if not (node and IsValidRef(node)) then return true end
            _, path = Identify(node)
        end
    end
    return true
end

-- Displayed text below a widget in display order. depth counts nested user
-- widgets (0 = the widget's own tree). nil when its tree cannot be read.
local function WalkTexts(widget)
    local entries, seen, visited = {}, {}, 0
    local function Visit(node, depth, level, isStart)
        if visited >= MAX_NODES or level > MAX_LEVELS then return end
        if not (node and IsValidRef(node)) then return end
        local class, path = Identify(node)
        if not path or seen[path] then return end
        seen[path], visited = true, visited + 1
        if not isStart and not IsDisplayed(node) then return end
        if IsTextClass(class) then
            local text = ReadText(node)
            if text then
                entries[#entries + 1] = {ref = node, path = path, name = LeafName(path), raw = text, depth = depth}
            end
            return
        end
        if LEAF_CLASSES[class] then return end
        local count = class:sub(-2) ~= "_C" and TryCall(node, "GetChildrenCount") or nil
        if type(count) ~= "number" then
            local root, readable = TreeRoot(node)
            if root then
                Visit(root, isStart and depth or depth + 1, level + 1)
            elseif isStart and not readable then
                return "unreadable"
            end
            return
        end
        local active = class:find("Switcher", 1, true) and TryCall(node, "GetActiveWidgetIndex") or nil
        for i = 0, math.min(count, MAX_NODES) - 1 do
            if type(active) ~= "number" or active == i then
                Visit(TryCall(node, "GetChildAt", i), depth, level + 1)
            end
        end
    end
    if Visit(widget, 0, 0, true) == "unreadable" then return nil end
    return entries
end

-- Fallback when a widget tree cannot be read: exact path scope over the
-- per-cycle text queries, filtered by the same displayed-ancestor rule.
local function ScanTexts(widgetPath)
    local entries, memo = {}, {}
    for _, className in ipairs({"TextBlock", "RichTextBlock"}) do
        for _, block in ipairs(FindAllOf(className) or {}) do
            local _, path = Identify(block)
            if path and IsUnder(path, widgetPath) then
                local text = ReadText(block)
                if text and IsShownWithin(block, widgetPath, memo) then
                    local _, trees = path:sub(#widgetPath + 1):gsub("%.WidgetTree[_%d]*%.", "")
                    entries[#entries + 1] = {ref = block, path = path, name = LeafName(path), raw = text,
                        depth = math.max(trees - 1, 0), order = #entries}
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.depth ~= b.depth then return a.depth < b.depth end
        return a.order < b.order
    end)
    return entries
end

local function First(entries, accept)
    for _, e in ipairs(entries) do
        if accept(e) then return e end
    end
    return nil
end

local function Shallowest(entries, accept)
    local best = nil
    for _, e in ipairs(entries) do
        if accept(e) and (not best or e.depth < best.depth) then best = e end
    end
    return best
end

-- Resolve what a widget displays:
--   label     spoken label, followed by any other displayed text
--   title     the label when the widget shows a title (nil otherwise)
--   value     raw text of the current value, valueRef its live text widget
local function Describe(widget)
    local _, path = Identify(widget)
    if not path then return {} end
    local found = WalkTexts(widget)
    if not found then
        local class = GetClassName(widget)
        if not reportedTrees[class] then
            reportedTrees[class] = true
            print("[AE] Widget tree unreadable for " .. class .. "; using exact path scope")
        end
        found = ScanTexts(path)
    end
    local entries = {}
    for _, e in ipairs(found) do
        if not e.raw:find(PLACEHOLDER, 1, true) then
            e.text = Clean(e.raw)
            entries[#entries + 1] = e
        end
    end

    -- Value: the native SSMenuButton caption when displayed, else a caption text.
    local value, captionPath = nil, nil
    local caption = TryGetProperty(widget, "caption")
    if caption and IsValidRef(caption) then
        local _, p = Identify(caption)
        captionPath = p
    end
    if captionPath then
        value = First(entries, function(e) return e.path == captionPath end)
    end
    value = value or Shallowest(entries, function(e) return e.name == "caption" end)

    -- Title: the widget's own title text, its native Title, then a nested one.
    local titleEntry = First(entries, function(e)
        return e.depth == 0 and TITLE_NAMES[e.name] and e ~= value
    end)
    local title = titleEntry and titleEntry.text
    if not title then
        local native = TryCall(TryGetProperty(widget, "Title"), "ToString")
        if type(native) == "string" and native:match("%S") and not native:find(PLACEHOLDER, 1, true) then
            title = Clean(native)
        end
    end
    if not title then
        titleEntry = Shallowest(entries, function(e) return TITLE_NAMES[e.name] and e ~= value end)
        title = titleEntry and titleEntry.text
    end
    if title and value and value.text == title then
        title, titleEntry = nil, nil -- the caption itself is the label
    end
    if title and not value then
        value = First(entries, function(e) return e ~= titleEntry and e.text ~= title end)
    end

    local label, labelEntry = title, titleEntry
    if not label then
        labelEntry = value or entries[1]
        value = labelEntry
        label = labelEntry and labelEntry.text
    end
    if not label then return {} end

    -- Other displayed text in the widget follows the label.
    local spoken, extras = {[label] = true}, {}
    if value then spoken[value.text] = true end
    for _, e in ipairs(entries) do
        if #extras >= MAX_EXTRAS then break end
        if e ~= titleEntry and e ~= labelEntry and e ~= value and not spoken[e.text] then
            spoken[e.text] = true
            extras[#extras + 1] = e.text
        end
    end
    if #extras > 0 then label = label .. ", " .. table.concat(extras, ", ") end

    return {
        label = label,
        title = title and label or nil,
        value = value and value.raw or nil,
        valueRef = value and value.ref or nil,
    }
end

-- === TEXT READING ===

-- Returns the widget's spoken title (nil without a displayed title), its
-- current value text and that value's live text widget. Every call reads
-- fresh text, so callers may compare titles from separate calls.
function WidgetReader.ReadWidgetTexts(widget)
    local d = Describe(widget)
    return d.title, d.value, d.valueRef
end

local function IsLabelClass(class)
    for _, part in ipairs(LABEL_CLASS_PARTS) do
        if class:find(part, 1, true) then return true end
    end
    return false
end

-- USSMenuButton.RemoteButton is the native link to the displayed button.
-- CSG hit-area numbers and caption-widget numbers do not necessarily agree.
-- Only use a live, attached display widget belonging to this same menu.
local function FindRemoteLabelWidget(widget)
    local remote = TryGetProperty(widget, "RemoteButton")
    if not (remote and IsValidRef(remote)) then return nil end
    local _, focusPath = Identify(widget)
    local _, remotePath = Identify(remote)
    if not focusPath or not remotePath or focusPath == remotePath then return nil end
    local owner = Owners(focusPath)[1]
    if not owner or Owners(remotePath)[1] ~= owner then return nil end
    if not IsShownWithin(remote, owner) then return nil end
    return remote
end

-- Hit areas carry no text; the displayed menu item with the same number in
-- their list does (HitBtn_Text_05 -> BS_BTN_Menu_DP_05). The list is the
-- nearest owner of the hit area that holds numbered menu items. A number
-- missing from that list is never borrowed from a farther list.
local function FindMatchingLabelWidget(widget, widgetName)
    local suffix = widgetName:match("_(%d+)$")
    local _, focusPath = Identify(widget)
    if not suffix or not focusPath then return nil end
    local owners = Owners(focusPath)
    if #owners == 0 then return nil end

    local listRank, matches = nil, {}
    for _, item in ipairs(FindAllOf("UserWidget") or {}) do
        local class, path = Identify(item)
        local itemSuffix = path and path ~= focusPath and IsLabelClass(class) and LeafName(path):match("_(%d+)$")
        if itemSuffix then
            for rank, owner in ipairs(owners) do
                if IsUnder(path, owner) then
                    if not listRank or rank < listRank then listRank = rank end
                    if itemSuffix == suffix and not matches[rank] and IsShownWithin(item, owner) then
                        matches[rank] = item
                    end
                    break
                end
            end
        end
    end
    return listRank and matches[listRank] or nil
end

-- === LIST POSITION ===

function WidgetReader.GetListPosition(widgetName, widget)
    local widgetClass = nil
    if widgetName:find("HitBtn_Text") then
        widgetClass = "WBP_OBJ_Common_HitBtn_Text_C"
    elseif widgetName:find("HitButton_%d") then
        widgetClass = "WBP_OBJ_Common_HitButton_C"
    else
        return nil, nil
    end

    local focusSuffix = widgetName:match("_(%d+)$")
    if not focusSuffix then return nil, nil end
    focusSuffix = tonumber(focusSuffix)

    local items = FindAllOf(widgetClass)
    if not items then return nil, nil end

    -- main.lua labels the focused widget, then asks for its position by name.
    if not widget and lastLabeledName == widgetName and IsValidRef(lastLabeled) then
        widget = lastLabeled
    end
    local focusPath = nil
    if widget then
        local _, p = Identify(widget)
        focusPath = p
    end

    local suffixes = nil
    if focusPath then
        -- Count displayed items of the nearest owner that holds the list.
        for _, owner in ipairs(Owners(focusPath)) do
            suffixes = {}
            local memo = {}
            for _, item in ipairs(items) do
                local _, path = Identify(item)
                local s = path and tonumber(LeafName(path):match("_(%d+)$"))
                if s and IsUnder(path, owner) and (path == focusPath or IsShownWithin(item, owner, memo)) then
                    table.insert(suffixes, s)
                end
            end
            if #suffixes > 1 then break end
        end
    end
    if not suffixes then
        suffixes = {}
        for _, item in ipairs(items) do
            local path = TryCall(item, "GetFullName")
            if path and path:find("Transient") then
                local vis = TryCall(item, "IsVisible")
                if vis then
                    local iName = GetWidgetName(item)
                    local s = iName:match("_(%d+)$")
                    if s then
                        table.insert(suffixes, tonumber(s))
                    end
                end
            end
        end
    end

    table.sort(suffixes)
    local position = nil
    for i, s in ipairs(suffixes) do
        if s == focusSuffix then
            position = i
            break
        end
    end

    if position then
        return position, #suffixes
    end
    return nil, nil
end

-- === LABEL RESOLUTION ===

local function CleanWidgetName(name)
    local cleaned = name
    cleaned = cleaned:gsub("^WBP_", "")
    cleaned = cleaned:gsub("^OBJ_", "")
    cleaned = cleaned:gsub("^BTN_", "")
    cleaned = cleaned:gsub("^GRP_", "")
    cleaned = cleaned:gsub("^CMN_", "")
    cleaned = cleaned:gsub("_C$", "")
    cleaned = cleaned:gsub("_Button$", "")
    cleaned = cleaned:gsub("Button$", "")
    cleaned = cleaned:gsub("_Btn$", "")
    cleaned = cleaned:gsub("_BTN$", "")
    cleaned = cleaned:gsub("_", " ")
    cleaned = cleaned:match("^%s*(.-)%s*$")
    if cleaned == "" then cleaned = name end
    return cleaned
end

-- Returns label, matched widget, current value, value text widget, and for
-- image-backed settings a live value reader.
function WidgetReader.GetSpokenLabel(widget)
    local name = GetWidgetName(widget)
    lastLabeled, lastLabeledName = widget, name
    if WidgetReader.WidgetLabels[name] then
        return WidgetReader.WidgetLabels[name], nil, nil
    end

    local valueReader = Languages.CreateReader(widget)
    if valueReader then
        -- SSMenuButtonImage.Title is FText; its value is a separate image.
        local title = TryCall(TryGetProperty(widget, "Title"), "ToString")
        if not title or title == "" then title = WidgetReader.ReadWidgetTexts(widget) end
        return title or CleanWidgetName(name), widget, valueReader(), nil, valueReader
    end

    if name:find("HitBtn") or name:find("HitButton") then
        local labelWidget = FindRemoteLabelWidget(widget)
        if labelWidget then
            print("[AE] Native label link: " .. name .. " -> " .. GetWidgetName(labelWidget))
        else
            labelWidget = FindMatchingLabelWidget(widget, name)
        end
        if labelWidget then
            local d = Describe(labelWidget)
            print("[AE] Matched: " .. GetWidgetName(labelWidget) .. " title=" .. tostring(d.title) .. " caption=" .. tostring(d.value))
            if d.label then return d.label, labelWidget, d.value, d.valueRef end
        else
            print("[AE] No match found for: " .. name)
        end
    end

    -- A displayed title is followed by the value; otherwise the label is the
    -- caption or first text, still polled for changes through its widget.
    local d = Describe(widget)
    if d.label then return d.label, widget, d.value, d.valueRef end
    return CleanWidgetName(name), nil, nil, nil
end

return WidgetReader
