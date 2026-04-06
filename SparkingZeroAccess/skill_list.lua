--[[
    skill_list.lua — Explanation of Controls overlay reading
    Appears in multiple contexts: character select (R2), pause menu, etc.

    Focusable items are WBP_OBJ_SL_Content_Skill_C (skills) and
    WBP_OBJ_SL_Content_Other_C (Ki Charge, etc.) inside WBP_GRP_SL_Main_0_C.

    Each item has a "caption" TextBlock with the skill name.
    Text_BtnGuide (RichTextBlock) shows the button combo to activate.
    Detail cells (SL_Cell_*) show resource cost and description.
]]

local H = require("helpers")
local TryCall = H.TryCall
local GetWidgetName = H.GetWidgetName
local GetClassName = H.GetClassName

local SkillList = {}

-- === INTERNAL STATE ===

local _lastAnnounced = nil   -- last announced widget name string
local _lastCategory = nil    -- last announced category string

-- === CONTEXT DETECTION ===

--- Check if a widget is a skill list item.
function SkillList.IsSkillListItem(widget)
    local className = GetClassName(widget)
    return className == "WBP_OBJ_SL_Content_Skill_C"
        or className == "WBP_OBJ_SL_Content_Other_C"
end

--- Check if we should announce. Pass the name string, not the widget.
--- Returns: shouldAnnounce, categoryChanged
function SkillList.ShouldAnnounce(widgetName, category)
    local catChanged = (category ~= nil and category ~= _lastCategory)
    if widgetName == _lastAnnounced and not catChanged then
        return false, false
    end
    _lastAnnounced = widgetName
    if category then _lastCategory = category end
    return true, catChanged
end

--- Reset internal state (call on screen transitions).
function SkillList.Reset()
    _lastAnnounced = nil
    _lastCategory = nil
end

-- === READING ===

--- Read the skill name from the focused item's caption TextBlock.
function SkillList.ReadSkillName(widget)
    local widgetName = GetWidgetName(widget)
    if not widgetName then return nil end

    local textBlocks = FindAllOf("TextBlock")
    if not textBlocks then return nil end

    for _, tb in ipairs(textBlocks) do
        local ok, tbPath = pcall(function() return tb:GetFullName() end)
        if ok and tbPath:find(widgetName, 1, true)
           and tbPath:find("Transient", 1, true)
           and GetWidgetName(tb) == "caption" then
            local ok2, text = pcall(function() return tb:GetText():ToString() end)
            if ok2 and text and text ~= "" then return text end
        end
    end
    return nil
end

--- Read the button combo from Text_BtnGuide RichTextBlock.
--- Returns raw icon markup (speech module auto-parses it).
function SkillList.ReadButtonCombo()
    local richBlocks = FindAllOf("RichTextBlock")
    if not richBlocks then return nil end

    for _, rb in ipairs(richBlocks) do
        local ok, rbPath = pcall(function() return rb:GetFullName() end)
        if ok and rbPath:find("WBP_GRP_SL_Main_0_C", 1, true)
           and rbPath:find("Transient", 1, true)
           and GetWidgetName(rb) == "Text_BtnGuide" then
            local ok2, text = pcall(function() return rb:GetText():ToString() end)
            if ok2 and text and text:match("%S") then return text end
        end
    end
    return nil
end

--- Read detail cells: resource cost and skill description.
--- Returns two values: costText (from small cells), descText (from XL cell).
--- Filters out Japanese placeholder text.
function SkillList.ReadDetails()
    local textBlocks = FindAllOf("TextBlock")
    if not textBlocks then return nil, nil end

    local costParts = {}
    local descText = nil

    for _, tb in ipairs(textBlocks) do
        local ok, tbPath = pcall(function() return tb:GetFullName() end)
        if ok and tbPath:find("WBP_GRP_SL_Main_0_C", 1, true)
           and tbPath:find("Transient", 1, true)
           and GetWidgetName(tb) == "caption" then
            -- Check which cell type this belongs to
            local cellType = tbPath:match("WBP_OBJ_SL_Cell_(%w+)")
            if cellType then
                local ok2, text = pcall(function() return tb:GetText():ToString() end)
                if ok2 and text and text:match("%S")
                   and not text:find("\227\131\134\227\130\173\227\130\185\227\131\136", 1, true) then
                    -- Filter out placeholder "テキストブロック" (UTF-8 bytes)
                    if cellType == "XL" then
                        descText = text:gsub("\n", " "):gsub("%s+", " ")
                    else
                        table.insert(costParts, text:gsub("\n", " "):gsub("%s+", " "))
                    end
                end
            end
        end
    end

    local costText = #costParts > 0 and table.concat(costParts, ", ") or nil
    return costText, descText
end

--- Read the category title (Text_ListTitle).
function SkillList.ReadCategory()
    local textBlocks = FindAllOf("TextBlock")
    if not textBlocks then return nil end

    for _, tb in ipairs(textBlocks) do
        local ok, tbPath = pcall(function() return tb:GetFullName() end)
        if ok and tbPath:find("WBP_GRP_SL_Main_0_C", 1, true)
           and tbPath:find("Transient", 1, true)
           and GetWidgetName(tb) == "Text_ListTitle" then
            local ok2, text = pcall(function() return tb:GetText():ToString() end)
            if ok2 and text and text ~= "" then return text end
        end
    end
    return nil
end

--- Read the overlay title (Text_Title).
function SkillList.ReadTitle()
    local textBlocks = FindAllOf("TextBlock")
    if not textBlocks then return nil end

    for _, tb in ipairs(textBlocks) do
        local ok, tbPath = pcall(function() return tb:GetFullName() end)
        if ok and tbPath:find("WBP_GRP_SL_Main_0_C", 1, true)
           and tbPath:find("Transient", 1, true)
           and GetWidgetName(tb) == "Text_Title" then
            local ok2, text = pcall(function() return tb:GetText():ToString() end)
            if ok2 and text and text ~= "" then return text end
        end
    end
    return nil
end

return SkillList
