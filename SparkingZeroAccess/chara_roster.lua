--[[
    chara_roster.lua — Character selection grid reading
    Handles the roster grid (HitButton_00 through _33+), skill slots,
    and team list slots in the roster view.

    Character names come from texture IDs on the CharaIcon IMG_Face_Main
    images, looked up via chara_names.lua — same approach as team_overview.
]]

local H = require("helpers")
local TryCall = H.TryCall
local TryGetProperty = H.TryGetProperty
local IsValidRef = H.IsValidRef
local GetWidgetName = H.GetWidgetName

local CharaNames = require("chara_names")

local Roster = {}

-- === CONTEXT DETECTION ===

local _lastContextWidget = nil
local _lastContextType = nil

function Roster.GetContext(widget)
    if widget == _lastContextWidget then return _lastContextType end
    _lastContextWidget = widget

    local name = GetWidgetName(widget)

    if name:find("SkillHitBTN", 1, true) then
        _lastContextType = "skill"
        return "skill"
    end

    local path = widget:GetFullName()

    if path:find("WBP_GRP_BS_CharaList_DP_C", 1, true) then
        _lastContextType = "roster"
        return "roster"
    end

    if path:find("WBP_GRP_BS_ChList_TeamList_DB_C", 1, true) then
        _lastContextType = "teamlist"
        return "teamlist"
    end

    _lastContextType = nil
    return nil
end

-- === TEXTURE-BASED CHARACTER READING ===

--- Read character name + DP for a roster grid slot via texture ID.
--- gridSuffix: the two-digit suffix from the focused HitButton (e.g. "10")
--- Returns: name, charaId, dp  or  nil, nil, nil
function Roster.ReadGridCharaName(gridSuffix)
    local iconName = "WBP_OBJ_BS_CharaIcon_" .. gridSuffix
    local images = FindAllOf("Image")
    if not images then return nil, nil, nil end

    for _, img in ipairs(images) do
        local ok, imgPath = pcall(function() return img:GetFullName() end)
        if ok and imgPath:find(iconName, 1, true)
           and imgPath:find("WBP_GRP_BS_CharaList_DP_C", 1, true)
           and imgPath:find("Transient", 1, true) then
            local imgWidgetName = GetWidgetName(img)
            if imgWidgetName == "IMG_Face_Main" then
                -- Read Brush.ResourceObject texture name
                local ok2, texName = pcall(function()
                    local brush = img.Brush
                    if not brush then return nil end
                    local res = brush.ResourceObject
                    if not res then return nil end
                    return res:GetFullName()
                end)
                if ok2 and texName then
                    local charaId = texName:match("T_UI_ChThumb[^_]+_(%d+_%d+)_%d+")
                    if charaId then
                        local name = CharaNames.GetName(charaId)
                        local dp = CharaNames.GetDP(charaId)
                        return name, charaId, dp
                    end
                end
                return nil, nil, nil
            end
        end
    end
    return nil, nil, nil
end

-- === TEAM LIST TEXTURE READING ===

--- Read character name for a team list slot via texture ID.
--- Team list icons are inside WBP_GRP_BS_ChList_TeamList_DB_C.
--- slotSuffix: the suffix from the focused HitButton (e.g. "0" through "4")
function Roster.ReadTeamListCharaName(slotSuffix)
    -- Team list uses two-digit icon names: CharaIcon_00 through _04
    local iconName = "WBP_OBJ_BS_CharaIcon_0" .. slotSuffix
    local images = FindAllOf("Image")
    if not images then return nil, nil, nil end

    for _, img in ipairs(images) do
        local ok, imgPath = pcall(function() return img:GetFullName() end)
        if ok and imgPath:find(iconName, 1, true)
           and imgPath:find("WBP_GRP_BS_ChList_TeamList_DB_C", 1, true)
           and imgPath:find("Transient", 1, true) then
            local imgWidgetName = GetWidgetName(img)
            if imgWidgetName == "IMG_Face_Main" then
                local ok2, texName = pcall(function()
                    local brush = img.Brush
                    if not brush then return nil end
                    local res = brush.ResourceObject
                    if not res then return nil end
                    return res:GetFullName()
                end)
                if ok2 and texName then
                    local charaId = texName:match("T_UI_ChThumb[^_]+_(%d+_%d+)_%d+")
                    if charaId then
                        local name = CharaNames.GetName(charaId)
                        local dp = CharaNames.GetDP(charaId)
                        return name, charaId, dp
                    end
                    -- Empty slot
                    if texName:find("Empty", 1, true) then
                        return nil, "empty", nil
                    end
                end
                return nil, nil, nil
            end
        end
    end
    return nil, nil, nil
end

-- === SKILL READING ===

function Roster.ReadSkillName(widget)
    local name = GetWidgetName(widget)
    local suffix = name:match("SkillHitBTN_(%d+)$")
    if not suffix then return nil end

    local suffixNum = tonumber(suffix)
    local targetName
    if suffixNum == 0 then targetName = "SkillBTN_0"
    elseif suffixNum == 1 then targetName = "SkillBTN_1"
    elseif suffixNum == 2 then targetName = "SkillBTN_Brast_0"
    elseif suffixNum == 3 then targetName = "SkillBTN_Brast_1"
    elseif suffixNum == 4 then targetName = "SkillBTN_Ult_0"
    else return nil end

    local skillWidgets = FindAllOf("WBP_OBJ_BS_SetSkillBTN_C")
    if not skillWidgets then return nil end

    for _, sw in ipairs(skillWidgets) do
        if GetWidgetName(sw) == targetName then
            local caption = TryGetProperty(sw, "caption")
            if caption then
                local ok, text = pcall(function() return caption:GetText():ToString() end)
                if ok and text and text ~= "" then return text end
            end
        end
    end

    return nil
end

-- === CACHE INVALIDATION (compatibility with main.lua) ===

function Roster.InvalidateCache()
    _lastContextWidget = nil
    _lastContextType = nil
end

return Roster
