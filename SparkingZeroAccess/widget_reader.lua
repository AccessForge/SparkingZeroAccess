--[[
    widget_reader.lua — Text reading, widget matching, and label resolution
    Handles reading text from widgets, matching numbered hit buttons to labels,
    and resolving what to speak for a given focused widget.
]]

local H = require("helpers")
local TryCall = H.TryCall
local TryGetProperty = H.TryGetProperty
local GetWidgetName = H.GetWidgetName
local GetClassName = H.GetClassName

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

-- === TEXT READING ===

local function GetButtonText(widget)
    local caption = TryGetProperty(widget, "caption")
    if caption then
        local getText = TryCall(caption, "GetText")
        if getText then
            local str = TryCall(getText, "ToString")
            if str and str ~= "" then return str end
        end
    end

    local childCount = TryCall(widget, "GetChildrenCount")
    if childCount and childCount > 0 then
        for i = 0, math.min(childCount - 1, 20) do
            local child = TryCall(widget, "GetChildAt", i)
            if child then
                local cn = GetClassName(child)
                if cn == "TextBlock" or cn == "RichTextBlock" then
                    local getText = TryCall(child, "GetText")
                    if getText then
                        local str = TryCall(getText, "ToString")
                        if str and str ~= "" then return str end
                    end
                end
            end
        end
    end

    return nil
end

function WidgetReader.ReadWidgetTexts(widget)
    local captionText = nil
    local titleText = nil
    local captionRef = nil

    local caption = TryGetProperty(widget, "caption")
    if caption then
        local getText = TryCall(caption, "GetText")
        if getText then
            local str = TryCall(getText, "ToString")
            if str and str ~= "" then
                captionText = str
                captionRef = caption
            end
        end
    end

    if not captionText then
        local widgetPath = widget:GetFullName()
        local instanceName = widgetPath:match("%.([^%.]+)$")
        if instanceName then
            local richBlocks = FindAllOf("RichTextBlock")
            if richBlocks then
                for _, rb in ipairs(richBlocks) do
                    local rbName = GetWidgetName(rb)
                    if rbName == "caption" then
                        local rbPath = rb:GetFullName()
                        if rbPath:find(instanceName, 1, true) then
                            local ok, text = pcall(function() return rb:GetText():ToString() end)
                            if ok and text and text ~= "" then
                                captionText = text
                                captionRef = rb
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    local widgetFullName = widget:GetFullName()
    local widgetInstanceName = widgetFullName:match("%.([^%.]+)$")
    if widgetInstanceName then
        local titleNames = {Text_Title = true, Title = true, TitleText = true, TXT_Label = true}
        local textBlocks = FindAllOf("TextBlock")
        if textBlocks then
            for _, tb in ipairs(textBlocks) do
                local tbName = GetWidgetName(tb)
                if titleNames[tbName] then
                    local tbPath = tb:GetFullName()
                    if tbPath:find(widgetInstanceName, 1, true) then
                        local ok, text = pcall(function() return tb:GetText():ToString() end)
                        if ok and text and text ~= "" and not text:find("設定項目") then
                            titleText = text
                            break
                        end
                    end
                end
            end
        end
    end

    return titleText, captionText, captionRef
end

local function FindMatchingLabelWidget(widgetName)
    local suffix = widgetName:match("_(%d+)$")
    if not suffix then return nil end

    local allWidgets = FindAllOf("UserWidget")
    if not allWidgets then return nil end

    for _, item in ipairs(allWidgets) do
        local itemName = GetWidgetName(item)
        local itemSuffix = itemName:match("_(%d+)$")
        if itemSuffix == suffix then
            local className = GetClassName(item)
            if className:find("BTN_Menu") or className:find("SetBGMBTN") or className:find("SetRuleBTN") then
                local visible = TryCall(item, "IsVisible")
                if visible then
                    return item
                end
            end
        end
    end

    return nil
end

-- === LIST POSITION ===

function WidgetReader.GetListPosition(widgetName)
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

    local suffixes = {}
    for _, item in ipairs(items) do
        local path = item:GetFullName()
        if path:find("Transient") then
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

function WidgetReader.GetSpokenLabel(widget)
    local name = GetWidgetName(widget)
    if WidgetReader.WidgetLabels[name] then
        return WidgetReader.WidgetLabels[name], nil, nil
    end

    if name:find("HitBtn") or name:find("HitButton") then
        local labelWidget = FindMatchingLabelWidget(name)
        if labelWidget then
            local title, caption, capRef = WidgetReader.ReadWidgetTexts(labelWidget)
            print("[AE] Matched: " .. GetWidgetName(labelWidget) .. " title=" .. tostring(title) .. " caption=" .. tostring(caption))
            if title then return title, labelWidget, caption, capRef end
            if caption then return caption, labelWidget, caption, capRef end
        else
            print("[AE] No match found for: " .. name)
        end
        return CleanWidgetName(name), nil, nil
    end

    -- Fast path: try direct child text first (no FindAllOf)
    local text = GetButtonText(widget)
    if text then
        -- Settings widgets have a title/label alongside caption — read it via slow path
        local cn = GetClassName(widget)
        if cn == "WBP_OBJ_Option_List_011_Gauge_C"
        or cn == "WBP_OBJ_Option_List_010_Text_C"
        or cn == "WBP_OBJ_MainMenu_BTN_Sub4_C" then
            local title, caption, capRef = WidgetReader.ReadWidgetTexts(widget)
            if title then return title, widget, caption, capRef end
        end
        return text, nil, nil, nil
    end

    -- Slow path: search all TextBlocks/RichTextBlocks by path matching
    local title, caption, capRef = WidgetReader.ReadWidgetTexts(widget)
    if title then return title, widget, caption, capRef end
    if caption then return caption, widget, nil, nil end

    return CleanWidgetName(name), nil, nil, nil
end

return WidgetReader
