--[[
    chara_roster.lua — Character selection grid reading
    Handles the roster grid (HitButton_00 through _33+), skill slots,
    and team list slots in the roster view.

    A slot's character is identified by the portrait texture on its CharaIcon
    IMG_Face_Main image (T_UI_ChThumbP1_<id>_<costume>). Its name is read from
    the game's own character record, the data the name plate displays.
    chara_names.lua is only the fallback when that record cannot be read.
]]

local H = require("helpers")
local FindAllOf = H.FindAllOf
local FindFirstOf = H.FindFirstOf
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

-- === NATIVE CHARACTER NAMES ===
-- The battle-setup name plate shows the character record's NameInfo.ShortName
-- in Text_Name and NameInfo.TitleName in Text_Name_Plus (Ghidra, exe 6DB7002A:
-- FUN_1429de240 reads record+0x570 and record+0x588; NameInfo is at +0x558).
-- Each record is SSCharacterDataAsset.CharacterDataAssetRecord, one asset per
-- portrait ID. Only asset references are cached; names are read live, in the
-- game's current language.

local DATA_FOLDER = "/Game/SS/MasterDataAsset/CharacterData/"
local _dataAssets = {}      -- charaId -> SSCharacterDataAsset reference
local _dataMissUntil = {}   -- charaId -> os.clock() before the next lookup
local _pathTried = {}       -- charaId -> path lookup already tried since the last reset
local _reported = {}        -- log each ID's name source and each odd texture once

local function NativeText(value)
    local ok, text = pcall(function() return value:ToString() end)
    if not ok or type(text) ~= "string" then return nil end
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end

local function FindCharacterData(charaId)
    local asset = _dataAssets[charaId]
    if asset and IsValidRef(asset) then return asset end
    _dataAssets[charaId] = nil
    if os.clock() < (_dataMissUntil[charaId] or 0) then return nil end

    -- A class-filtered lookup uses the class hash (0-1 ms, like helpers.lua);
    -- it also cannot return a same-named object of another class. The path
    -- lookup's cost is unmeasured in this loader, so it runs once per ID.
    local shortName = "CharacterData_" .. charaId
    local found
    if type(FindObjects) == "function" then
        local ok, objects = pcall(FindObjects, 1, "SSCharacterDataAsset", shortName, 0, 0, false)
        local object = ok and type(objects) == "table" and objects[1] or nil
        if IsValidRef(object) then found = object end
    end
    if not found and not _pathTried[charaId] and type(StaticFindObject) == "function" then
        _pathTried[charaId] = true
        local ok, object = pcall(StaticFindObject, DATA_FOLDER .. shortName .. "." .. shortName)
        if ok and IsValidRef(object) then found = object end
    end
    if not found then
        _dataMissUntil[charaId] = os.clock() + 0.5
        return nil
    end
    _dataAssets[charaId] = found
    _dataMissUntil[charaId] = nil
    return found
end

--- Name as the native name plate shows it: "ShortName" or "ShortName, TitleName".
--- Returns name, or nil and the reason it could not be read.
function Roster.ReadNativeName(charaId)
    local asset = FindCharacterData(charaId)
    if not asset then return nil, "character data not found" end
    local ok, shortName, titleName = pcall(function()
        local info = asset.CharacterDataAssetRecord.NameInfo
        return NativeText(info.ShortName), NativeText(info.TitleName)
    end)
    if not ok then return nil, tostring(shortName) end
    if not shortName then return nil, "empty ShortName" end
    return titleName and (shortName .. ", " .. titleName) or shortName
end

-- === PORTRAITS ===

--- Texture currently assigned to a portrait Image, or nil while none is set.
function Roster.ReadPortrait(image)
    local ok, texName = pcall(function()
        local brush = image.Brush
        local resource = brush and brush.ResourceObject
        if not resource or not resource:IsValid() then return nil end
        return resource:GetFullName()
    end)
    if ok and type(texName) == "string" and texName ~= "" then return texName end
    return nil
end

-- Placeholder textures a battle-setup icon declares for itself
-- (reflected USSBattleSetupNewCharaIcon: QuestionTexture, FreeTexture, EmptyTexture).
local PLACEHOLDERS = {{"QuestionTexture", "question"}, {"FreeTexture", "free"}, {"EmptyTexture", "empty"}}

local function PlaceholderState(image, texName)
    -- Image -> WidgetTree -> the CharaIcon user widget that owns it.
    local icon = image and TryCall(TryCall(image, "GetOuter"), "GetOuter")
    if not icon or not IsValidRef(icon) then return nil end
    for _, entry in ipairs(PLACEHOLDERS) do
        local texture = TryGetProperty(icon, entry[1])
        if texture and IsValidRef(texture) and TryCall(texture, "GetFullName") == texName then
            return entry[2]
        end
    end
    return nil
end

--- Identify a portrait texture; image (optional) is the portrait's Image.
--- Returns: name, charaId, dp      — identified character (native name preferred)
---          nil, charaId, nil      — a character portrait whose name is unknown
---          nil, "empty", nil      — empty slot portrait
---          nil, "question"/"free", nil — the icon's own "?" or "Free" picture
---          nil, "unrecognized", nil — some other final picture, not a character
---          nil, nil, nil          — no portrait shown (not loaded yet)
function Roster.DescribePortrait(texName, image)
    if not texName then return nil, nil, nil end
    local charaId = CharaNames.ExtractIdFromTexture(texName)
    if not charaId then
        if texName:find("Empty", 1, true) then return nil, "empty", nil end
        local state = PlaceholderState(image, texName) or "unrecognized"
        if not _reported[texName] then
            _reported[texName] = true
            print("[AE] Portrait is not a character thumbnail (" .. state .. "): " .. texName)
        end
        return nil, state, nil
    end

    local dp = CharaNames.GetDP(charaId)
    local name, reason = Roster.ReadNativeName(charaId)
    if name then
        if _reported[charaId] ~= "native" then
            _reported[charaId] = "native"
            print("[AE] Character " .. charaId .. ": " .. name .. " (native record)")
        end
        return name, charaId, dp
    end

    name = CharaNames.GetName(charaId)
    if _reported[charaId] ~= "fallback" then
        _reported[charaId] = "fallback"
        print("[AE] Character " .. charaId .. ": native name unavailable (" .. tostring(reason)
            .. "); static table: " .. tostring(name))
    end
    return name, charaId, dp
end

--- Find a CharaIcon's IMG_Face_Main image whose path contains listFilter.
--- owner, when known, is the instance name of the focused list
--- ("WBP_GRP_..._C_123"); only that exact instance can supply the image.
function Roster.FindPortrait(iconName, listFilter, owner)
    local images = FindAllOf("Image")
    if not images then return nil end
    local iconSegment = iconName .. "."
    local ownerSegment = owner and (owner .. ".")
    for _, img in ipairs(images) do
        local ok, imgPath = pcall(function() return img:GetFullName() end)
        if ok and imgPath:find(iconSegment, 1, true)
           and imgPath:find(listFilter, 1, true)
           and imgPath:find("Transient", 1, true)
           and GetWidgetName(img) == "IMG_Face_Main" then
            if not ownerSegment or imgPath:find(ownerSegment, 1, true) then return img end
        end
    end
    return nil
end

local function ReadSlot(iconName, listFilter, owner)
    local image = Roster.FindPortrait(iconName, listFilter, owner)
    if not image then return nil, nil, nil, nil, nil end
    local texName = Roster.ReadPortrait(image)
    local name, charaId, dp = Roster.DescribePortrait(texName, image)
    return name, charaId, dp, image, texName
end

-- === ROSTER GRID ===

--- Read the character in a roster grid slot.
--- gridSuffix: the two-digit suffix from the focused HitButton (e.g. "10")
--- owner: optional CharaList instance name of the focused button
--- Returns DescribePortrait's name, charaId, dp, plus the portrait image and
--- texture name (image is nil when the portrait widget was not found).
function Roster.ReadGridCharaName(gridSuffix, owner)
    return ReadSlot("WBP_OBJ_BS_CharaIcon_" .. gridSuffix, "WBP_GRP_BS_CharaList_DP_C", owner)
end

-- === TEAM LIST ===

--- Read the character in a team list slot (inside WBP_GRP_BS_ChList_TeamList_DB_C).
--- slotSuffix: the suffix from the focused HitButton (e.g. "0" through "4")
--- Same returns as ReadGridCharaName; empty slots return nil, "empty".
function Roster.ReadTeamListCharaName(slotSuffix, owner)
    -- Team list uses two-digit icon names: CharaIcon_00 through _04
    return ReadSlot("WBP_OBJ_BS_CharaIcon_0" .. slotSuffix, "WBP_GRP_BS_ChList_TeamList_DB_C", owner)
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

--- Forget character data references (map changes). Names are never cached.
function Roster.InvalidateCharacterData()
    _dataAssets = {}
    _dataMissUntil = {}
    _pathTried = {}
end

return Roster
