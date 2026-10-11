--[[
    SparkingZeroAccess - UE4SS Lua Mod
    Phase 2: Live menu reader

    Uses targeted polling on known interactive widget classes.
    Object reads run on the game thread. Map hooks pause the reader
    throughout map loading and invalidate references before it resumes.

    Reader starts automatically on game launch.
]]

-- === MODULE LOADING ===

local H = require("helpers")
local FindAllOf = H.FindAllOf
local FindFirstOf = H.FindFirstOf
local GameThread = require("game_thread")
local FocusReader = require("focus_reader")
local TryCall = H.TryCall
local TryGetProperty = H.TryGetProperty
local IsValidRef = H.IsValidRef
local GetWidgetName = H.GetWidgetName
local GetClassName = H.GetClassName

local Speech = require("speech")
local Speak = Speech.Speak
local SpeakQueued = Speech.SpeakQueued

local WR = require("widget_reader")
local Trackers = require("poll_trackers")
local TeamOV = require("team_overview")
local Roster = require("chara_roster")
local SkillList = require("skill_list")
local Battle = require("battle")
local EpisodeBattle = require("episode_battle")
local Shop = require("shop")
local ScreenReader = require("screen_reader")
local Subtitles = require("subtitle_speech")

-- === FOCUS TRACKING ===

local readerEnabled = true
local lastFocusedName = nil
local lastSpokenLabel = nil
local lastFocusedWidget = nil
local lastGuideMessage = nil
local lastListTitle = nil
local lastMatchedLabelWidget = nil
local lastCaptionValue = nil
local lastAnnouncedDialogId = nil
local lastOptionsTip = nil
local slowPathCooldown = 0
local lastScreenContext = nil -- "team", "roster", "skilllist", "roomid", or nil
local teamSlotPollFrames = 0 -- counts frames waiting for bubble to appear
local roomIdDigitRefs = {}   -- cached TXT_Num TextBlock refs per IDPanel
local lastCaptionRef = nil   -- cached TextBlock/RichTextBlock ref for caption polling
local lastValueReader = nil  -- live reader for image-backed option values
local focusEmptyScanStreak = 0 -- consecutive ticks the slow-path scan returned nil
local pendingLabel = nil     -- focused hit area whose displayed button was not ready yet
local LABEL_RETRY_SECONDS, LABEL_RETRY_LIMIT = 0.25, 12 -- about 3 s of retries
local characterSlot = nil    -- focused character slot whose portrait is watched

-- Read TXT_GuideMessage from the main menu base widget
local function ReadGuideMessage()
    local base = FindFirstOf("WBP_MainMenu_Base_C")
    if not IsValidRef(base) then return nil end
    if not TryCall(base, "IsVisible") then return nil end

    local txtWidget = TryGetProperty(base, "TXT_GuideMessage")
    if not txtWidget then return nil end
    local getText = TryCall(txtWidget, "GetText")
    if not getText then return nil end
    local str = TryCall(getText, "ToString")
    if str and str ~= "" then
        return str:gsub("\n", " "):gsub("%s+", " ")
    end
    return nil
end

-- Read TEXT_TipsMain from the options tips widget
local function ReadOptionsTip()
    local richBlocks = FindAllOf("RichTextBlock")
    if not richBlocks then return nil end

    for _, rb in ipairs(richBlocks) do
        if GetWidgetName(rb) == "TEXT_TipsMain" then
            local ok, rbPath = pcall(function() return rb:GetFullName() end)
            if ok and rbPath:find("Transient", 1, true) then
                local ok2, text = pcall(function() return rb:GetText():ToString() end)
                if ok2 and text and text ~= "" then
                    return text:gsub("\n", " "):gsub("%s+", " ")
                end
            end
        end
    end
    return nil
end

-- Read visible Text_Title TextBlocks (list headers like "Stage", "BGM", etc.)
local function ReadListTitle()
    local textBlocks = FindAllOf("TextBlock")
    if not textBlocks then return nil end

    for _, tb in ipairs(textBlocks) do
        local tbName = GetWidgetName(tb)
        if tbName == "Text_Title" then
            local visible = TryCall(tb, "IsVisible")
            if visible then
                local ok, text = pcall(function() return tb:GetText():ToString() end)
                if ok and text and text ~= "" then
                    return text:match("^%s*(.-)%s*$")
                end
            end
        end
    end
    return nil
end

-- Queue the matched widget's value when the spoken label is its own title.
local function QueueMatchedValue(label)
    if lastMatchedLabelWidget and lastCaptionValue then
        local title, _ = WR.ReadWidgetTexts(lastMatchedLabelWidget)
        if title and title == label then
            SpeakQueued(lastCaptionValue)
        end
    end
end

-- === CHARACTER SLOTS ===
-- Roster, team list and team slots are identified by their portraits. A
-- portrait can still be loading when focus arrives, and it can change under
-- unchanged focus (roster paging, team edits). The focused slot's own image is
-- re-read on each focus tick; the object query is repeated only, bounded, when
-- the portrait widget itself was not found.

local CHARACTER_WAIT_SECONDS = LABEL_RETRY_SECONDS * LABEL_RETRY_LIMIT -- about 3 s
-- Final pictures a portrait can show instead of a character (Roster.DescribePortrait).
local PORTRAIT_STATES = {empty = "Empty", question = "Question mark", free = "Free",
    unrecognized = "Unrecognized portrait"}

local function IsCharacterId(charaId)
    return charaId ~= nil and PORTRAIT_STATES[charaId] == nil
end

local function CharacterText(name, charaId, dp)
    if name then return dp and (name .. ", " .. dp .. " DP") or name end
    if charaId == nil then return "Loading character" end
    return PORTRAIT_STATES[charaId] or "Unknown character"
end

-- A placeholder ("Loading character", "Unknown character", "Character
-- unavailable") is corrected without cutting off speech queued after it.
local function SpeakCharacterSlot(slot, name, charaId, dp, interrupt)
    local text = CharacterText(name, charaId, dp)
    slot.spokenText = text
    slot.placeholder = name == nil and (charaId == nil or IsCharacterId(charaId))
    print("[AE] " .. slot.label .. ": " .. text .. " (" .. tostring(charaId) .. ")")
    slot.speak(text, interrupt)
end

local function ResetCharacterNameRetry(slot, name, charaId)
    slot.namePending = name == nil and IsCharacterId(charaId)
    slot.nameAttempts = 0
    slot.nameDue = os.clock() + LABEL_RETRY_SECONDS
end

-- read() returns name, charaId, dp, portrait image, texture name.
-- speak(text, interrupt) announces the slot in its screen's format.
local function StartCharacterSlot(widget, label, read, speak)
    local now = os.clock()
    local slot = {widget = widget, label = label, read = read, speak = speak, attempts = 0,
        due = now + LABEL_RETRY_SECONDS}
    characterSlot = slot
    local ok, name, charaId, dp, image, texture = pcall(read)
    if not ok then
        print("[AE] " .. label .. " portrait read error: " .. tostring(name))
        name, charaId, dp, image, texture = nil, nil, nil, nil, nil
    end
    slot.image, slot.texture, slot.key = image, texture, charaId
    slot.waitSince = charaId == nil and now or nil
    ResetCharacterNameRetry(slot, name, charaId)
    SpeakCharacterSlot(slot, name, charaId, dp, true)
end

local function CheckCharacterSlot()
    local slot = characterSlot
    if slot.widget ~= lastFocusedWidget then
        characterSlot = nil
        return
    end
    local read, name, charaId, dp = false, nil, nil, nil
    if slot.image and not IsValidRef(slot.image) then slot.image = nil end
    if slot.image then
        local texture = Roster.ReadPortrait(slot.image)
        if texture ~= slot.texture then
            slot.texture, read = texture, true
            name, charaId, dp = Roster.DescribePortrait(texture, slot.image)
            ResetCharacterNameRetry(slot, name, charaId)
        elseif slot.namePending and slot.nameAttempts < LABEL_RETRY_LIMIT
            and os.clock() >= slot.nameDue then
            -- The portrait can load before its character record. Reuse the
            -- image; the native lookup itself is cached and miss-throttled.
            slot.nameAttempts = slot.nameAttempts + 1
            slot.nameDue = os.clock() + LABEL_RETRY_SECONDS
            name, charaId, dp = Roster.DescribePortrait(texture, slot.image)
            if name then slot.namePending, read = false, true end
        end
    elseif slot.attempts < LABEL_RETRY_LIMIT and os.clock() >= slot.due then
        slot.attempts = slot.attempts + 1
        slot.due = os.clock() + LABEL_RETRY_SECONDS
        local ok, image, texture
        ok, name, charaId, dp, image, texture = pcall(slot.read)
        if not ok then name, charaId, dp, image, texture = nil, nil, nil, nil, nil end
        slot.image, slot.texture, read = image, texture, true
        ResetCharacterNameRetry(slot, name, charaId)
        if not image and slot.attempts >= LABEL_RETRY_LIMIT then
            print("[AE] " .. slot.label .. ": portrait widget not found after " .. slot.attempts .. " searches")
        end
    end
    if read and charaId == nil then
        -- Nothing shown now. A brief gap (page refill) is not announced.
        slot.waitSince = slot.waitSince or os.clock()
    elseif read then
        slot.waitSince, slot.unavailable = nil, false
        if charaId ~= slot.key or CharacterText(name, charaId, dp) ~= slot.spokenText then
            slot.key = charaId
            SpeakCharacterSlot(slot, name, charaId, dp, not slot.placeholder)
        end
    end
    if slot.waitSince and not slot.unavailable
        and os.clock() - slot.waitSince >= CHARACTER_WAIT_SECONDS then
        -- Still nothing to identify: say so once instead of leaving "Loading"
        -- or a cleared portrait's previous name.
        slot.unavailable, slot.key = true, nil
        slot.spokenText, slot.placeholder = "Character unavailable", true
        print("[AE] " .. slot.label .. ": no character portrait after " .. CHARACTER_WAIT_SECONDS .. " s")
        slot.speak("Character unavailable", false)
    end
end

local function OnWidgetFocused(widget)
    if not readerEnabled then return end

    local name = GetWidgetName(widget)
    if name == lastFocusedName and widget == lastFocusedWidget then return end

    lastFocusedName = name
    lastFocusedWidget = widget
    pendingLabel = nil
    characterSlot = nil
    -- Specialist handlers below may return early. Never carry the preceding
    -- setting's value reader into another control or screen.
    lastValueReader = nil
    lastCaptionRef = nil

    -- Check if this widget's class is suppressed
    local className = GetClassName(widget)
    if WR.SuppressedClasses[className] then
        return
    end

    -- === ROOM ID INPUT ===
    if className == "WBP_OBJ_MainMenu_OLB_IDPanel_C" then
        local firstEntry = (lastScreenContext ~= "roomid")
        lastScreenContext = "roomid"

        -- Build digit ref cache on first entry (one FindAllOf for all 9 panels)
        if firstEntry then
            roomIdDigitRefs = {}
            local textBlocks = FindAllOf("TextBlock")
            if textBlocks then
                for _, tb in ipairs(textBlocks) do
                    if GetWidgetName(tb) == "TXT_Num" then
                        local ok, tbPath = pcall(function() return tb:GetFullName() end)
                        if ok then
                            local panelName = tbPath:match("(WBP_OBJ_MainMenu_OLB_IDPanel_%d+)")
                            if panelName then
                                roomIdDigitRefs[panelName] = tb
                            end
                        end
                    end
                end
            end
        end

        local suffix = name:match("_(%d+)$")
        local position = suffix and (tonumber(suffix) + 1) or nil

        -- Read digit from cached ref
        local digit = nil
        local digitRef = roomIdDigitRefs and roomIdDigitRefs[name]
        if digitRef and IsValidRef(digitRef) then
            local ok, text = pcall(function() return digitRef:GetText():ToString() end)
            if ok and text then digit = text end
            lastMatchedLabelWidget = digitRef
        end

        local announcement = ""
        if position and digit then
            announcement = digit .. ", digit " .. position .. " of 9"
        elseif position then
            announcement = "Digit " .. position .. " of 9"
        end

        if announcement ~= "" then
            lastSpokenLabel = announcement
            lastCaptionValue = digit
            Speak(announcement, true)
        end

        if firstEntry then
            SpeakQueued("Up Down to change, Left Right to move")
        end

        return
    end

    -- === FAST PATH: WidgetLabels direct lookup (pause menu, etc.) ===
    -- Skip all expensive FindAllOf scans when we have a direct mapping
    if WR.WidgetLabels[name] then
        lastScreenContext = nil
        local label = WR.WidgetLabels[name]
        if label ~= lastSpokenLabel then
            lastSpokenLabel = label
            Speak(label, true)
        end
        return
    end

    -- === PLAYER MATCH PANEL ===
    if className == "WBP_OBJ_PLMatch_PlayerPanel_C" then
        local firstEntry = (lastScreenContext ~= "plmatch_room")
        lastScreenContext = "plmatch_room"

        -- Derive slot number from widget name suffix (e.g. _00 -> 1, _01 -> 2)
        local slotSuffix = name:match("_(%d+)$")
        local slotNum = slotSuffix and (tonumber(slotSuffix) + 1) or nil

        local widgetInstance = name
        local textBlocks = FindAllOf("TextBlock")
        if textBlocks then
            local fields = {}
            for _, tb in ipairs(textBlocks) do
                local ok, tbPath = pcall(function() return tb:GetFullName() end)
                if ok and tbPath:find(widgetInstance, 1, true) and tbPath:find("Transient", 1, true) then
                    local tbName = GetWidgetName(tb)
                    local ok2, text = pcall(function() return tb:GetText():ToString() end)
                    if ok2 and text and text ~= "" then
                        fields[tbName] = text
                    end
                end
            end

            local parts = {}
            if slotNum then
                table.insert(parts, tostring(slotNum))
            end
            local username = fields.TXT_Username_Own
            if not username or username == "Username" then
                username = fields.TXT_UserName
            end
            if username and username ~= "Username" then
                table.insert(parts, username)
            end
            local status = fields.TXT_Status_00
            if status and status ~= "Text Block" then
                table.insert(parts, status)
            elseif fields.TXT_Enter == "Available" then
                table.insert(parts, "Available")
            end
            if username and username ~= "Username" and fields.TXT_WinCountNum and fields.TXT_GameCountNum then
                table.insert(parts, fields.TXT_WinCountNum .. "/" .. fields.TXT_GameCountNum .. " wins")
            end

            local announcement = table.concat(parts, ", ")
            if announcement ~= "" and announcement ~= lastSpokenLabel then
                lastSpokenLabel = announcement
                Speak(announcement, true)
            end
        end

        -- Announce guide bar on first entry
        if firstEntry then
            SpeakQueued("Player Match Room")
            local richBlocks = FindAllOf("RichTextBlock")
            if richBlocks then
                local guideNames = {
                    "WBP_OBJ_Guide_Btn_Present",
                    "WBP_OBJ_Guide_Btn_0",
                    "WBP_OBJ_Guide_Btn_1",
                    "WBP_OBJ_Guide_Btn_2",
                    "WBP_OBJ_Guide_Btn_3",
                }
                for _, gw in ipairs(guideNames) do
                    for _, rb in ipairs(richBlocks) do
                        local ok, rbPath = pcall(function() return rb:GetFullName() end)
                        if ok and rbPath:find(gw, 1, true)
                           and rbPath:find("Transient", 1, true) then
                            local rbName = GetWidgetName(rb)
                            if rbName == "RTEXT_Help_0" or rbName == "RTEXT_Help_1" then
                                local ok2, text = pcall(function() return rb:GetText():ToString() end)
                                if ok2 and text and text:match("%S")
                                   and not text:find("\227\131\152\227\131\171\227\131\151", 1, true)
                                   and not text:find("\227\131\151\227\131\172\227\130\188", 1, true) then
                                    SpeakQueued(text)
                                end
                            end
                        end
                    end
                end
            end
        end

        return
    end

    -- === SHOP DIALOG (purchase confirmation / purchase complete) ===
    if Shop.IsShopDialog(widget) then
        Shop.OnShopDialogFocused(widget)
        lastSpokenLabel = "shop_dialog"
        return
    end

    -- === SHOP ITEM GRID ===
    if Shop.IsShopItem(widget) then
        local firstEntry = (lastScreenContext ~= "shop")
        lastScreenContext = "shop"
        Shop.OnItemFocused(widget)
        lastSpokenLabel = "shop_item"
        return
    end

    -- === EPISODE BATTLE (character select) ===
    if EpisodeBattle.IsCharaSelect(widget) then
        local firstEntry = (lastScreenContext ~= "episode_battle")
        lastScreenContext = "episode_battle"
        EpisodeBattle.OnCharaSelectFocused(widget)
        lastSpokenLabel = "episode_battle"
        return
    end

    -- === TEAM OVERVIEW (check first — cheap name + path match) ===
    if TeamOV.IsTeamSlot(widget) then
        local slot, side = TeamOV.GetSlotInfo(widget)
        local sideCode = side == "Player 2" and "2P" or "1P"
        local teamContext = "team_" .. sideCode
        -- Reset player side when first entering team overview (not when switching 1P/2P panels)
        local isTeamScreen = lastScreenContext == "team_1P" or lastScreenContext == "team_2P"
        if not isTeamScreen then
            Battle.ResetPlayerSide()
        end
        Battle.SetPlayerSide(sideCode)
        local firstEntry = (lastScreenContext ~= teamContext)
        lastScreenContext = teamContext
        local slotNum = slot and (slot + 1) or 0
        print("[AE] Team slot: " .. slotNum .. " (" .. sideCode .. ")")

        -- Read the character from the slot's portrait
        local owner = widget:GetFullName():match("(WBP_GRP_BS_Top_00_[12]P_C_%d+)")
        StartCharacterSlot(widget, "Team slot " .. slotNum .. " (" .. sideCode .. ")",
            function() return TeamOV.ReadSlotCharaName(slot, sideCode, owner) end,
            function(text, interrupt)
                Speak(text, interrupt)
                SpeakQueued("Slot " .. slotNum)
            end)

        -- Announce context + guide bar shortcuts on first entry or side switch
        if firstEntry then
            -- Refresh hold button captions in this game-thread polling cycle.
            pcall(TeamOV.RequestHoldButtonCaptions)

            local playerLabel = side or "Player 1"
            -- Count the side's characters; a total missing an unknown DP would be wrong.
            local dpOk, totalDP, charCount = pcall(TeamOV.GetTotalDP, sideCode, owner)
            local dpInfo = ""
            if dpOk and charCount and charCount > 0 then
                dpInfo = (totalDP and (", Total " .. totalDP .. " DP") or "") .. ", " .. charCount
                    .. (charCount == 1 and " character" or " characters")
            end
            SpeakQueued(playerLabel .. ", Team Overview" .. dpInfo)

            -- Let the guide bar finish updating before announcing its captions.
            GameThread.After(100, "Team guide", function()
                if lastScreenContext ~= teamContext then return end
                local ok, shortcuts = pcall(TeamOV.ReadGuideBar)
                if ok and shortcuts and #shortcuts > 0 then
                    for _, sc in ipairs(shortcuts) do
                        SpeakQueued(sc)
                    end
                    print("[AE] Guide bar: " .. table.concat(shortcuts, ", "))
                end
            end)
        end

        teamSlotPollFrames = 0
        lastSpokenLabel = "team_slot"
        return
    end

    -- === SKILL LIST / EXPLANATION OF CONTROLS ===
    if SkillList.IsSkillListItem(widget) then
        local firstEntry = (lastScreenContext ~= "skilllist")
        lastScreenContext = "skilllist"

        local category = SkillList.ReadCategory()
        local shouldAnnounce, catChanged = SkillList.ShouldAnnounce(name, category)

        if not shouldAnnounce then return end

        local skillName = SkillList.ReadSkillName(widget)

        -- Category change: announce category first
        if catChanged and not firstEntry then
            Speak(category, true)
        end

        -- Announce skill name + button combo
        if skillName then
            local btnCombo = SkillList.ReadButtonCombo()
            local announcement = skillName
            if btnCombo then announcement = announcement .. ", " .. btnCombo end

            if catChanged and not firstEntry then
                SpeakQueued(announcement)
            else
                Speak(announcement, true)
            end
            lastSpokenLabel = skillName

            -- Queue resource cost, then description
            local costText, descText = SkillList.ReadDetails()
            if costText then SpeakQueued(costText) end
            if descText then SpeakQueued(descText) end

            print("[AE] Skill list: " .. skillName .. " [" .. tostring(btnCombo) .. "]")
        end

        -- Announce title on first entry
        if firstEntry then
            local title = SkillList.ReadTitle()
            if title then
                SpeakQueued(title)
                print("[AE] Skill list opened: " .. title)
            end
        end

        return
    end

    -- === CHARACTER ROSTER ===
    local rosterCtx = Roster.GetContext(widget)
    if rosterCtx == "roster" then
        lastScreenContext = "roster"
        teamSlotPollFrames = 0 -- stop team polling when entering roster
        -- Extract grid suffix from widget name (e.g. "WBP_OBJ_Common_HitButton_10" -> "10")
        local gridSuffix = name:match("HitButton_(%d+)$")
        if gridSuffix then
            local owner = widget:GetFullName():match("(WBP_GRP_BS_CharaList_DP_C_%d+)")
            StartCharacterSlot(widget, "Roster grid " .. gridSuffix,
                function() return Roster.ReadGridCharaName(gridSuffix, owner) end,
                function(text, interrupt)
                    lastSpokenLabel = text
                    Speak(text, interrupt)
                end)
        end
        return
    end

    if rosterCtx == "skill" then
        local skillName = Roster.ReadSkillName(widget)
        if skillName then
            local widgetName = GetWidgetName(widget)
            local suffix = tonumber(widgetName:match("SkillHitBTN_(%d+)$"))
            local prefix = ""
            if suffix == 4 then prefix = "Ultimate: "
            elseif suffix == 2 or suffix == 3 then prefix = "Blast: "
            end
            Speak(prefix .. skillName, true)
            lastSpokenLabel = skillName
        else
            Speak("Skill " .. (tonumber(name:match("(%d+)$")) or 0) + 1, true)
        end
        return
    end

    if rosterCtx == "teamlist" then
        local slot = GetWidgetName(widget):match("HitButton_(%d+)$")
        if slot then
            local slotNum = tonumber(slot) + 1
            local owner = widget:GetFullName():match("(WBP_GRP_BS_ChList_TeamList_DB_C_%d+)")
            StartCharacterSlot(widget, "Team list slot " .. slotNum,
                function() return Roster.ReadTeamListCharaName(slot, owner) end,
                function(text, interrupt)
                    -- Every new focus speaks, also after passing through the list.
                    local announcement = "Slot " .. slotNum .. ", " .. text
                    lastSpokenLabel = announcement
                    Speak(announcement, interrupt)
                end)
        end
        return
    end

    -- If widget is inside a dialog, announce dialog text first, then button label
    -- Pattern matches both regular dialogs (WBP_Dialog_000_C_123) and shop dialogs (WBP_Dialog_SH_000_C_123)
    local widgetPath = widget:GetFullName()
    local dialogId = widgetPath:match("(WBP_Dialog_%d+_C_%d+)")
    if dialogId then
        if dialogId ~= lastAnnouncedDialogId then
            lastAnnouncedDialogId = dialogId
            local textBlocks = FindAllOf("TextBlock")
            if textBlocks then
                for _, tb in ipairs(textBlocks) do
                    if tb:GetFullName():find(dialogId, 1, true) then
                        if GetWidgetName(tb) == "TEXT_Header" then
                            local ok, headerText = pcall(function() return tb:GetText():ToString() end)
                            if ok and headerText and headerText ~= "" then
                                Speak(headerText, true)
                            end
                            break
                        end
                    end
                end
            end
            local richBlocks = FindAllOf("RichTextBlock")
            if richBlocks then
                for _, rb in ipairs(richBlocks) do
                    if rb:GetFullName():find(dialogId, 1, true) then
                        if GetWidgetName(rb):find("Text_Main") then
                            local ok, bodyText = pcall(function() return rb:GetText():ToString() end)
                            if ok and bodyText and bodyText ~= "" then
                                SpeakQueued(bodyText:gsub("\n", " "):gsub("%s+", " "))
                            end
                            break
                        end
                    end
                end
            end
            -- Queue button label after a delay so the body text has time to be read
            local dialogWidget = widget
            GameThread.After(1500, "Dialog button", function()
                if lastFocusedWidget ~= dialogWidget or not IsValidRef(dialogWidget) then return end
                local label = WR.GetSpokenLabel(dialogWidget)
                lastSpokenLabel = label
                SpeakQueued(label)
            end)
            Trackers.MarkDialogSeen(dialogId)
        else
            local label = WR.GetSpokenLabel(widget)
            lastSpokenLabel = label
            Speak(label, true)
        end
        return
    end

    -- Clear dialog and screen context tracking when in generic handler
    lastAnnouncedDialogId = nil
    lastScreenContext = nil

    -- Check if the list header changed (tab switch via L1/R1)
    local listTitle = ReadListTitle()
    local headerChanged = listTitle and listTitle ~= lastListTitle
    if headerChanged then
        lastListTitle = listTitle
        Speak(listTitle, true)
    end

    -- Image-backed settings also return a live value reader.
    lastMatchedLabelWidget = nil
    lastCaptionValue = nil
    lastCaptionRef = nil
    lastValueReader = nil
    local label, matchedWidget, captionValue, captionRef, valueReader = WR.GetSpokenLabel(widget)
    lastMatchedLabelWidget = matchedWidget
    lastCaptionValue = captionValue
    lastCaptionRef = captionRef
    lastValueReader = valueReader

    -- No matched widget means the reader fell back to the widget name: the hit
    -- area's displayed button was not initialized yet. PollFocus retries it.
    if not matchedWidget and not valueReader and (name:find("HitBtn") or name:find("HitButton")) then
        pendingLabel = {widget = widget, name = name, attempts = 0, due = os.clock() + LABEL_RETRY_SECONDS}
    end

    if label == lastSpokenLabel and not headerChanged and not lastValueReader then return end

    lastSpokenLabel = label

    if headerChanged then
        SpeakQueued(label)
    else
        Speak(label, true)
    end

    if lastValueReader and lastCaptionValue then
        print("[AE] Language value: " .. lastCaptionValue)
        SpeakQueued(lastCaptionValue)
    else
        QueueMatchedValue(label)
    end

    local pos, total = WR.GetListPosition(name, widget)
    if pos and total then
        SpeakQueued(pos .. " of " .. total)
    end

    local guide = ReadGuideMessage()
    if guide and guide ~= lastGuideMessage then
        lastGuideMessage = guide
        SpeakQueued(guide)
    end

    if className:match("^WBP_OBJ_Option_List_") then
        local tip = ReadOptionsTip()
        if tip and tip ~= lastOptionsTip then
            lastOptionsTip = tip
            SpeakQueued(tip)
        end
    end
end

-- === FOCUS SCAN ===
-- Prefer attached native focus branches; retain the global compatibility scan.
-- The transition cooldown protects against stale refs during screen changes.
-- pcall on HasKeyboardFocus catches any Lua-level errors on individual widgets.

local focusTreeAnnounced, focusTreeWarning = false, false
local function ScanForFocus()
    local ok, focused, supported = pcall(FocusReader.Find)
    if ok and supported then
        if not focusTreeAnnounced then
            focusTreeAnnounced = true
            print('[AE] Native viewport focus reader active')
        end
        return focused
    end
    if not focusTreeWarning then
        focusTreeWarning = true
        print('[AE] Native viewport focus query unavailable; using compatibility widget scan')
    end
    local ok, allWidgets = pcall(FindAllOf, "UserWidget")
    if not ok or not allWidgets then return nil end
    for i = 1, #allWidgets do
        local w = allWidgets[i]
        local fok, focused = pcall(function()
            return w.HasKeyboardFocus and w:HasKeyboardFocus()
        end)
        if fok and focused then
            return w
        end
    end
    return nil
end

-- Re-resolve a focused hit area's label while its button initializes, at most
-- LABEL_RETRY_LIMIT times. The correction is queued so that screen text
-- announced meanwhile is not cut off.
local function RetryPendingLabel()
    local pending = pendingLabel
    if pending.widget ~= lastFocusedWidget then
        pendingLabel = nil
        return
    end
    if os.clock() < pending.due then return end
    pending.attempts = pending.attempts + 1
    local label, matchedWidget, captionValue, captionRef = WR.GetSpokenLabel(pending.widget)
    if matchedWidget then
        pendingLabel = nil
        lastMatchedLabelWidget = matchedWidget
        lastCaptionValue = captionValue
        lastCaptionRef = captionRef
        print("[AE] Focus label ready after " .. pending.attempts .. " retries: " .. label)
        if label ~= lastSpokenLabel then
            lastSpokenLabel = label
            SpeakQueued(label)
            QueueMatchedValue(label)
        end
    elseif pending.attempts >= LABEL_RETRY_LIMIT then
        pendingLabel = nil
        print("[AE] Focus label unavailable after " .. pending.attempts .. " retries: " .. pending.name)
    else
        pending.due = os.clock() + LABEL_RETRY_SECONDS
    end
end

local function PollFocus()
    -- Cooldown: skip UObject access to let game finish destroying widgets
    if slowPathCooldown > 0 then
        slowPathCooldown = slowPathCooldown - 1
        return
    end

    -- Transition cooldown: dialog just dismissed or map loading
    if os.clock() < Trackers.transitionCooldownUntil then
        if lastFocusedWidget then
            lastFocusedWidget = nil
            lastValueReader = nil
            lastFocusedName = nil
            lastSpokenLabel = nil
            lastMatchedLabelWidget = nil
        end
        pendingLabel = nil
        characterSlot = nil
        focusEmptyScanStreak = 0
        return
    end

    -- Fast path: check if cached focused widget still has focus
    if lastFocusedWidget then
        if not IsValidRef(lastFocusedWidget) then
            -- Widget destroyed — clear refs, fall through to slow path
            -- No cooldown needed: IsValid() caught it safely
            lastFocusedWidget = nil
            lastValueReader = nil
            lastFocusedName = nil
            lastSpokenLabel = nil
            lastMatchedLabelWidget = nil
            pendingLabel = nil
            characterSlot = nil
        else
            local ok, stillFocused = pcall(function()
                return lastFocusedWidget:HasKeyboardFocus()
            end)

            if not ok then
                -- pcall caught error after IsValid passed — enter brief cooldown
                print("[AE] Stale widget after IsValid, brief cooldown")
                lastFocusedWidget = nil
                lastValueReader = nil
                lastFocusedName = nil
                lastSpokenLabel = nil
                lastMatchedLabelWidget = nil
                pendingLabel = nil
                characterSlot = nil
                    TeamOV.InvalidateCache()
                Roster.InvalidateCache()
                slowPathCooldown = 6 -- 6 x 16ms = ~100ms
                return
            end

            if stillFocused then
                if pendingLabel then RetryPendingLabel() end
                -- Character slots: re-read the focused portrait, never rescan
                if characterSlot then CheckCharacterSlot() end
                -- Room ID digit change polling (cached TXT_Num TextBlock ref)
                if lastScreenContext == "roomid" and IsValidRef(lastMatchedLabelWidget) then
                    local ok, gt = pcall(function() return lastMatchedLabelWidget:GetText() end)
                    if ok and gt then
                        local newDigit = TryCall(gt, "ToString")
                        if newDigit and newDigit ~= lastCaptionValue then
                            lastCaptionValue = newDigit
                            Speak(newDigit, true)
                        end
                    end
                elseif lastValueReader then
                    local newValue = lastValueReader()
                    if newValue and newValue ~= lastCaptionValue then
                        lastCaptionValue = newValue
                        print("[AE] Language value: " .. newValue)
                        Speak(newValue, true)
                    end
                -- Focus unchanged — check caption value changes (D-pad left/right)
                elseif lastCaptionRef and IsValidRef(lastCaptionRef) then
                    local ok, gt = pcall(function() return lastCaptionRef:GetText() end)
                    if ok and gt then
                        local newCaption = TryCall(gt, "ToString")
                        if newCaption and newCaption ~= lastCaptionValue then
                            lastCaptionValue = newCaption
                            Speak(newCaption, true)
                        end
                    end
                end
                return
            end

            -- Focus moved — clear cached widget, fall through to slow path
            lastFocusedWidget = nil
            lastValueReader = nil
            pendingLabel = nil
            characterSlot = nil
        end
    end

    -- Slow path: discover focus from attached native roots or compatibility scan.
    -- Throttle: after 6 consecutive empty scans (~100ms) drop to 1-in-6 cadence
    -- so we don't burn 60Hz GUObjectArray walks on screens that genuinely have
    -- no focusable widget (cutscene fades, animations, brief dialog gaps).
    -- Reset to full cadence the moment focus reappears.
    if focusEmptyScanStreak >= 6 and (focusEmptyScanStreak % 6) ~= 0 then
        focusEmptyScanStreak = focusEmptyScanStreak + 1
        return
    end

    local focused = ScanForFocus()
    if focused then
        focusEmptyScanStreak = 0
        OnWidgetFocused(focused)
        return
    end

    focusEmptyScanStreak = focusEmptyScanStreak + 1
    -- Nothing focused
    if lastFocusedName ~= nil then
        lastFocusedName = nil
        lastFocusedWidget = nil
        lastValueReader = nil
        lastSpokenLabel = nil
    end
    pendingLabel = nil
    characterSlot = nil
end

-- === MAIN LOOP ===

local function ResetStaleState(keepMovie)
    ScreenReader.Reset(keepMovie)
    lastFocusedName = nil
    lastFocusedWidget = nil
    lastSpokenLabel = nil
    lastGuideMessage = nil
    lastListTitle = nil
    lastMatchedLabelWidget = nil
    lastCaptionValue = nil
    lastAnnouncedDialogId = nil
    lastOptionsTip = nil
    lastCaptionRef = nil
    lastValueReader = nil
    pendingLabel = nil
    characterSlot = nil
    focusEmptyScanStreak = 0
    teamSlotPollFrames = 0
    roomIdDigitRefs = {}
    TeamOV.InvalidateCache()
    Roster.InvalidateCache()
    Roster.InvalidateCharacterData()
    EpisodeBattle.Reset()
    Shop.Reset()
end

-- Quick world liveness check — if this fails, we're in a transition.
-- GameInstance is a process-lifetime singleton, so we cache it and only
-- re-fetch when IsValidRef reports the cached ref is dead. This avoids a
-- full GUObjectArray scan every loop tick (previously 120/sec across both
-- loops).
local _cachedGameInstance = nil

local function IsWorldAlive()
    if _cachedGameInstance and IsValidRef(_cachedGameInstance) then
        return true
    end
    _cachedGameInstance = nil
    local ok, gi = pcall(FindFirstOf, "GameInstance")
    if ok and gi then
        _cachedGameInstance = gi
        return true
    end
    return false
end

local function StartFocusLoop()
    GameThread.Every(16, "Focus reader", function()
        if not readerEnabled or Trackers.IsInTransition() or not IsWorldAlive() then
            if not readerEnabled then pendingLabel, characterSlot = nil, nil end
            return false
        end
        local ok, err = pcall(PollFocus)
        if not ok then
            print("[AE] Focus loop error: " .. tostring(err))
            ResetStaleState(true)
        end
        return false
    end)
end

local function StartPollLoop()
    -- Slow loop: dialogs, screen changes, battle HUD, cutscene text, shop categories, etc.
    -- These detect state changes on the game's timeline, not on user input, so 100ms
    -- is more than tight enough for announcements (HP thresholds, integer-second timer,
    -- dialog appearance) without burning 60Hz of FindAllOf/FindFirstOf scans.
    -- Focus tracking is on a separate 16ms loop for screen-reader responsiveness.
    GameThread.Every(100, "Screen reader", function()
        if not readerEnabled or Trackers.IsInTransition() or not IsWorldAlive() then
            return false
        end
        local ok, err = pcall(Trackers.PollDialogs)
        if not ok then print("[AE] PollDialogs error: " .. tostring(err)) end
        local ok2, err2 = pcall(Trackers.PollHelpWindows)
        if not ok2 then print("[AE] PollHelpWindows error: " .. tostring(err2)) end
        local ok3, err3 = pcall(Trackers.PollScreenChanges)
        if not ok3 then print("[AE] PollScreenChanges error: " .. tostring(err3)) end
        -- PollIntro removed (investigating retry crash)
        local ok6, err6 = pcall(Trackers.PollRoom)
        if not ok6 then print("[AE] PollRoom error: " .. tostring(err6)) end
        local ok7, err7 = pcall(EpisodeBattle.PollStoryMap)
        if not ok7 then print("[AE] PollStoryMap error: " .. tostring(err7)) end
        local ok8, err8 = pcall(EpisodeBattle.PollCutsceneSkip)
        if not ok8 then print("[AE] PollCutsceneSkip error: " .. tostring(err8)) end
        local ok9, err9 = pcall(EpisodeBattle.PollCutsceneText)
        if not ok9 then print("[AE] PollCutsceneText error: " .. tostring(err9)) end
        local ok5, err5 = pcall(Battle.PollHUD, Speak, SpeakQueued)
        if not ok5 then print("[AE] PollHUD error: " .. tostring(err5)) end
        local ok5r, err5r = pcall(Battle.PollResult, Speak, SpeakQueued)
        if not ok5r then print("[AE] PollResult error: " .. tostring(err5r)) end
        local ok10, err10 = pcall(Shop.PollCategory)
        if not ok10 then print("[AE] PollShopCategory error: " .. tostring(err10)) end
        return false
    end)
end

local function StartReader()
    StartFocusLoop()
    StartPollLoop()
    GameThread.Every(250, "Visible screen text", function()
        if readerEnabled and not Trackers.IsInTransition() and IsWorldAlive() then
            ScreenReader.Poll()
        end
    end)

    print("[AE] Reader scheduled on the game thread (one pending dispatch)")
end

-- === DEBUG TOOLS (remove this block to disable) ===
local debugOk, debugTools = pcall(require, "debug_tools")
if debugOk and debugTools then
    debugTools.Init(Speak)
else
    print("[AE] Debug tools not loaded: " .. tostring(debugTools))
end
-- === END DEBUG TOOLS ===

-- === INIT ===
print("[AE] Initializing SparkingZeroAccess Phase 2...")
Speech.Init()
Subtitles.Init(Speak)
Trackers.Init(Speak, SpeakQueued)
EpisodeBattle.Init(Speak, SpeakQueued)
Shop.Init(Speak, SpeakQueued)
ScreenReader.Init(Speak, SpeakQueued, function()
    return readerEnabled and not Trackers.IsInTransition() and IsWorldAlive()
end)
-- No TextBlock:SetText hook (TeamOV.InitHook): its captured bubble name is never
-- read, and UE4SS runs that Lua for every scripted SetText on the hook thread it
-- shares with reader callbacks. Team names come from portraits and native records.
Battle.Init()
Battle.SetResetCallback(function()
    print("[AE] Result screen reset triggered")
    ResetStaleState()
    SkillList.Reset()
    TeamOV.ClearCapturedName()
    Trackers.ArmTransitionCooldown(0.8)
end)

-- Map transition hooks: pause polling before tear-down, reset state after load.
-- A load has no fixed time limit. Only the matching post hook resumes reads.
-- Stock 3.0.1 pushes five arguments but calls this hook with an argument count
-- of four (UE4SS #776). This later API is present only after that fix.
if type(LoopInGameThreadWithDelay) == "function" then
    RegisterLoadMapPreHook(function(engine, world, url)
        print("[AE] Map load starting, pausing poll loops")
        pendingLabel = nil -- never re-resolve a widget from the old world
        characterSlot = nil
        ScreenReader.Reset() -- Stop movie narration before the old world is torn down.
        GameThread.PauseForMapLoad()
        Trackers.BeginMapLoad()
        _cachedGameInstance = nil
        H.InvalidateCachedFirstOf()
    end)
else
    print("[AE] Legacy UE4SS detected: skipping its broken map pre-hook; update UE4SS for full transition protection")
end

RegisterLoadMapPostHook(function(engine, world)
    print("[AE] Map loaded, resetting state")
    GameThread.PauseForMapLoad() -- also discards old callbacks on legacy loaders
    H.InvalidateCachedFirstOf()
    _cachedGameInstance = nil
    ResetStaleState()
    SkillList.Reset()
    Battle.Reset()
    TeamOV.ClearCapturedName()
    EpisodeBattle.FullReset()  -- full reset on map change (story map too)
    Trackers.EndMapLoad()
    GameThread.ResumeAfterMapLoad(0.8)
end)

if Speech.IsLoaded() then
    StartReader()
    print("[AE] Waiting for first game-thread read.")
else
    print("[AE] Speech not available.")
end
