--[[
    episode_battle.lua — Episode Battle (Story Mode) accessibility
    Handles two screens:
    1. Character Select — pick a character, continue/new game/story map
    2. Story Map — navigate chapter nodes within a character's saga

    Character select uses focus-based reading (HitButtons inside
    WBP_GRP_AI_CharacterSelect_C). Story map uses poll-based reading
    (no keyboard focus on nodes — text changes on WBP_GRP_AI_ChartTitle_C).

    Key discovery: both character panels AND action buttons (Continue,
    Story Map, New Game) receive focus as WBP_OBJ_Common_HitButton_C.
    The BTN_Menu widgets are visual labels only. We map HitButton suffix
    to BTN_Menu suffix to read button captions.
]]

local H = require("helpers")
local TryCall = H.TryCall
local TryGetProperty = H.TryGetProperty
local IsValidRef = H.IsValidRef
local GetWidgetName = H.GetWidgetName
local GetClassName = H.GetClassName

local IconParser = require("icon_parser")

local EpisodeBattle = {}

-- === STATE ===

local Speak = nil
local SpeakQueued = nil

-- Character select state
local _lastCharaName = nil        -- last announced character name (CaracterText_0)
local _lastHitButtonWidget = nil  -- last focused HitButton widget ref (identity check)
local _lastChapterTitle = nil     -- last TXT_ChapterTitle value
local _announcedEntry = false     -- whether we announced entry to this screen

-- Story map state
local _storyMapActive = false
local _lastEventTitle = nil       -- last Text_EventTitle value
local _lastChapter = nil          -- last Text_Chapter value
local _lastScenario0 = nil        -- last Text_ScenarioTitle_0 (character saga)
local _lastScenario1 = nil        -- last Text_ScenarioTitle_1 (arc name)
local _announcedMapEntry = false  -- whether we announced entry to story map
local _mapEntryDelay = 0          -- countdown before entry announcement (lets transition finish)

-- Branch conditions state
local _lastBranchConditions = ""  -- serialized string of last announced conditions
local _lastGuideButtonCount = 0   -- visible guide button count (story node vs path node detection)
local _onPathNode = false         -- true when on a path/connector node

-- Cutscene state
local _announcedSkip = false      -- whether we announced "hold to skip" for this cutscene
local _lastCutsceneText = nil     -- last RichText_MainTalk content (narration/dialog)

function EpisodeBattle.Init(speakFn, speakQueuedFn)
    Speak = speakFn
    SpeakQueued = speakQueuedFn
end

function EpisodeBattle.Reset()
    _lastCharaName = nil
    _lastHitButtonWidget = nil
    _lastChapterTitle = nil
    _announcedEntry = false
    -- Do NOT reset story map state here — story map survives screen resets
    -- because it's poll-based and the chart widget persists independently
end

function EpisodeBattle.FullReset()
    _lastCharaName = nil
    _lastHitButtonWidget = nil
    _lastChapterTitle = nil
    _announcedEntry = false
    _storyMapActive = false
    _lastEventTitle = nil
    _lastChapter = nil
    _lastScenario0 = nil
    _lastScenario1 = nil
    _announcedMapEntry = false
    _mapEntryDelay = 0
    _lastBranchConditions = ""
    _lastGuideButtonCount = 0
    _onPathNode = false
    _announcedSkip = false
    _lastCutsceneText = nil
end

-- === PARENT CONTAINER DETECTION ===

local CONTAINER_CLASS = "WBP_GRP_AI_CharacterSelect_C"

--- Check if a widget is inside the Episode Battle character select screen.
function EpisodeBattle.IsCharaSelect(widget)
    local ok, path = pcall(function() return widget:GetFullName() end)
    if not ok then return false end
    return path:find(CONTAINER_CLASS, 1, true) ~= nil
end

-- === TEXT READING HELPERS ===

--- Find a TextBlock by name inside a container class and read its text.
local function ReadTextInContainer(fieldName, containerClass)
    local textBlocks = FindAllOf("TextBlock")
    if not textBlocks then return nil end

    for _, tb in ipairs(textBlocks) do
        if GetWidgetName(tb) == fieldName then
            local ok, tbPath = pcall(function() return tb:GetFullName() end)
            if ok and tbPath:find(containerClass, 1, true)
               and tbPath:find("Transient", 1, true) then
                local ok2, text = pcall(function() return tb:GetText():ToString() end)
                if ok2 and text and text ~= "" then
                    return text
                end
            end
        end
    end
    return nil
end

local function ReadCharaSelectText(fieldName)
    return ReadTextInContainer(fieldName, CONTAINER_CLASS)
end

local function ReadChartText(fieldName)
    return ReadTextInContainer(fieldName, "WBP_GRP_AI_ChartTitle_C")
end

--- Read the button caption from a BTN_Menu widget matching a suffix.
local function ReadBtnMenuCaption(suffix)
    local targetName = "WBP_OBJ_AI_BTN_Menu_" .. suffix
    local textBlocks = FindAllOf("TextBlock")
    if not textBlocks then return nil end

    for _, tb in ipairs(textBlocks) do
        if GetWidgetName(tb) == "caption" then
            local ok, tbPath = pcall(function() return tb:GetFullName() end)
            if ok and tbPath:find(targetName, 1, true)
               and tbPath:find("Transient", 1, true) then
                local ok2, text = pcall(function() return tb:GetText():ToString() end)
                if ok2 and text and text ~= "" then
                    return text
                end
            end
        end
    end
    return nil
end

--- Read guide bar from the visible WBP_GRP_GuideSet_C.
--- guideSetFilter: optional string to match a specific GuideSet instance.
--- Returns a list of readable guide button strings.
local function ReadGuideBar(guideSetFilter)
    local richBlocks = FindAllOf("RichTextBlock")
    if not richBlocks then return {} end

    local guideNames = {
        "WBP_OBJ_Guide_Btn_Present",
        "WBP_OBJ_Guide_Btn_0",
        "WBP_OBJ_Guide_Btn_1",
        "WBP_OBJ_Guide_Btn_2",
        "WBP_OBJ_Guide_Btn_3",
        "WBP_OBJ_Guide_Btn_4",
    }

    -- Japanese placeholder patterns to filter out
    local jpFilters = {
        "\227\131\152\227\131\171\227\131\151",  -- ヘルプ
        "\227\131\151\227\131\172\227\130\188",  -- プレゼ
        "\227\131\156\227\130\191\227\131\179",  -- ボタン
    }

    local results = {}
    for _, gw in ipairs(guideNames) do
        for _, rb in ipairs(richBlocks) do
            local ok, rbPath = pcall(function() return rb:GetFullName() end)
            if ok and rbPath:find(gw, 1, true)
               and rbPath:find("Transient", 1, true)
               and (not guideSetFilter or rbPath:find(guideSetFilter, 1, true)) then
                local rbName = GetWidgetName(rb)
                if rbName == "RTEXT_Help_0" or rbName == "RTEXT_Help_1" then
                    local ok2, text = pcall(function() return rb:GetText():ToString() end)
                    if ok2 and text and text:match("%S") then
                        -- Filter out Japanese placeholder text
                        local isJp = false
                        for _, jp in ipairs(jpFilters) do
                            if text:find(jp, 1, true) then
                                isJp = true
                                break
                            end
                        end
                        if not isJp then
                            table.insert(results, text)
                        end
                    end
                end
            end
        end
    end
    return results
end

-- === CHARACTER SELECT: FOCUS HANDLER ===

--- Called from main.lua OnWidgetFocused when widget is inside the character select.
function EpisodeBattle.OnCharaSelectFocused(widget)
    if not Speak then return false end

    local name = GetWidgetName(widget)

    -- Announce screen entry
    if not _announcedEntry then
        _announcedEntry = true
        _storyMapActive = false
        _announcedMapEntry = false
        Speak("Episode Battle", true)
        print("[AE] Episode Battle character select entered")

        -- Queue guide bar on first entry
        local guideBar = ReadGuideBar()
        if #guideBar > 0 then
            for _, text in ipairs(guideBar) do
                SpeakQueued(text)
            end
            print("[AE] Episode guide bar: " .. table.concat(guideBar, ", "))
        end
    end

    -- Only handle HitButton — that's what gets focus here
    local className = GetClassName(widget)
    if className ~= "WBP_OBJ_Common_HitButton_C" then
        return true
    end

    -- Track by widget identity, not name — different characters can reuse
    -- the same HitButton name (e.g. HitButton_1 for both Goku and Frieza)
    if widget == _lastHitButtonWidget then
        return true
    end
    _lastHitButtonWidget = widget

    -- Read selected character name
    local charaName = ReadCharaSelectText("CaracterText_0")
    local charaChanged = charaName and charaName ~= _lastCharaName

    if charaChanged then
        -- Character changed (up/down navigation)
        _lastCharaName = charaName
        Speak(charaName, true)
        print("[AE] Episode char: " .. charaName)

        -- Queue chapter title + story text
        local chapterTitle = ReadCharaSelectText("TXT_ChapterTitle")
        if chapterTitle then
            SpeakQueued(chapterTitle)
            _lastChapterTitle = chapterTitle
        end

        local storyText = ReadCharaSelectText("TXT_main")
        if storyText then
            local collapsed = storyText:gsub("\n", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
            if collapsed and collapsed ~= "" then
                SpeakQueued(collapsed)
            end
        end
    end

    -- Always announce the current button caption (whether char changed or not)
    local suffix = name:match("_(%d+)$")
    if not suffix then
        -- No suffix (e.g. "WBP_OBJ_Common_HitButton") — map to BTN_Menu_0
        suffix = "0"
    end

    local caption = ReadBtnMenuCaption(suffix)
    if caption then
        if charaChanged then
            SpeakQueued(caption)
        else
            Speak(caption, true)
        end
        print("[AE] Episode button: " .. caption)
    end

    return true
end

-- === STORY MAP: POLL-BASED READING ===

--- Poll for story map visibility and node changes.
--- Uses safe FindAllOf("TextBlock") scan — no FindFirstOf crash risk.
function EpisodeBattle.PollStoryMap()
    if not Speak then return end

    -- Detect story map via Text_ScenarioTitle_0 (always present, never placeholder)
    local saga = ReadChartText("Text_ScenarioTitle_0")

    if not saga then
        if _storyMapActive then
            _storyMapActive = false
            _announcedMapEntry = false
            _lastEventTitle = nil
            _lastChapter = nil
            _lastScenario0 = nil
            _lastScenario1 = nil
            print("[AE] Story map closed")
        end
        return
    end

    -- Story map is visible
    if not _storyMapActive then
        _storyMapActive = true
        -- Start delay countdown (~100ms) to let transition finish
        _mapEntryDelay = 6  -- 6 × 16ms poll cycles
        Speak("Story Map", true)
        print("[AE] Story map detected, waiting for transition")
    end

    -- Read event title, filtering "???" placeholder
    local eventTitle = ReadChartText("Text_EventTitle")
    if eventTitle == "???" then eventTitle = nil end

    -- Delayed entry announcement (waits for char select to fade)
    if not _announcedMapEntry then
        if _mapEntryDelay > 0 then
            _mapEntryDelay = _mapEntryDelay - 1
            return
        end
        _announcedMapEntry = true

        -- Re-read saga fresh (char select text should be gone by now)
        saga = ReadChartText("Text_ScenarioTitle_0")
        local arc = ReadChartText("Text_ScenarioTitle_1")
        local chapter = ReadChartText("Text_Chapter")

        local parts = {}
        if saga then table.insert(parts, saga) end
        if arc then table.insert(parts, arc) end
        if chapter then table.insert(parts, chapter) end
        if #parts > 0 then
            Speak(table.concat(parts, ", "), true)
            print("[AE] Story map: " .. table.concat(parts, ", "))
        end

        _lastScenario0 = saga
        _lastScenario1 = arc
        _lastChapter = chapter
        _lastEventTitle = eventTitle
        if eventTitle then
            SpeakQueued(eventTitle)
        end

        -- Read Dragon Orb status
        local orb = ReadChartText("TXT_Orb")
        if orb then
            SpeakQueued(orb)
        end

        -- Read guide bar (now the story map's guide bar, not char select's)
        local guideBar = ReadGuideBar()
        if #guideBar > 0 then
            for _, text in ipairs(guideBar) do
                SpeakQueued(text)
            end
            print("[AE] Story map guide: " .. table.concat(guideBar, ", "))
        end

        return
    end

    -- Poll for node changes
    if eventTitle and eventTitle ~= _lastEventTitle then
        _lastEventTitle = eventTitle
        Speak(eventTitle, true)
        print("[AE] Story node: " .. eventTitle)

        -- Check if chapter changed too
        local chapter = ReadChartText("Text_Chapter")
        if chapter and chapter ~= _lastChapter then
            _lastChapter = chapter
            SpeakQueued(chapter)
        end

        -- Check if arc changed
        local arc = ReadChartText("Text_ScenarioTitle_1")
        if arc and arc ~= _lastScenario1 then
            _lastScenario1 = arc
            SpeakQueued(arc)
        end

        -- Check if saga changed
        local saga = ReadChartText("Text_ScenarioTitle_0")
        if saga and saga ~= _lastScenario0 then
            _lastScenario0 = saga
            SpeakQueued(saga)
        end
    end

    -- Detect path node vs story node via guide button count
    local guideOk, guideButtons = pcall(FindAllOf, "WBP_OBJ_Guide_Btn_0_C")
    if guideOk and guideButtons then
        local visCount = 0
        for _, btn in ipairs(guideButtons) do
            local vok, vis = pcall(function() return btn:IsVisible() end)
            if vok and vis then visCount = visCount + 1 end
        end

        if visCount ~= _lastGuideButtonCount then
            local wasPath = _onPathNode
            _lastGuideButtonCount = visCount
            -- Path nodes have <=3 guide buttons, story nodes have 4+
            _onPathNode = (visCount <= 3)

            if _onPathNode and not wasPath then
                -- Just moved to a path node — read branch conditions
                local ok2, branchWidgets = pcall(FindAllOf, "WBP_OBJ_AI_BranchConditons_Set_C")
                if ok2 and branchWidgets then
                    local visibleIds = {}
                    for _, bw in ipairs(branchWidgets) do
                        local visOk, visible = pcall(function() return bw:IsVisible() end)
                        if visOk and visible then
                            local nameOk, fullName = pcall(function() return bw:GetFullName() end)
                            if nameOk then
                                local instId = fullName:match("(WBP_OBJ_AI_BranchConditons_Set_C_%d+)")
                                if instId then visibleIds[instId] = true end
                            end
                        end
                    end

                    local textBlocks2 = FindAllOf("TextBlock")
                    if textBlocks2 then
                        local condByInst = {}
                        local instOrder = {}
                        for _, tb in ipairs(textBlocks2) do
                            if GetWidgetName(tb) == "Text_BranchCondition_0" then
                                local ok3, tbPath = pcall(function() return tb:GetFullName() end)
                                if ok3 and tbPath:find("Transient", 1, true) then
                                    local instId = tbPath:match("(WBP_OBJ_AI_BranchConditons_Set_C_%d+)")
                                    if instId and visibleIds[instId] and not condByInst[instId] then
                                        local ok4, text = pcall(function() return tb:GetText():ToString() end)
                                        if ok4 and text and text ~= "" then
                                            condByInst[instId] = text
                                            table.insert(instOrder, instId)
                                        end
                                    end
                                end
                            end
                        end

                        local parts = {}
                        for i, instId in ipairs(instOrder) do
                            local text = condByInst[instId]
                            if text == "???" then
                                table.insert(parts, i .. ": locked")
                            else
                                table.insert(parts, i .. ": " .. text)
                            end
                        end

                        if #parts > 0 then
                            Speak("Path", true)
                            for _, part in ipairs(parts) do
                                SpeakQueued(part)
                            end
                            print("[AE] Path node, conditions: " .. table.concat(parts, ", "))
                        else
                            Speak("Path", true)
                            print("[AE] Path node, no conditions")
                        end
                    end
                end
            end
        end
    end
end

--- Returns true if the story map is currently active.
function EpisodeBattle.IsStoryMapActive()
    return _storyMapActive
end

-- === CUTSCENE SKIP: POLL-BASED ===

--- Poll for WBP_GRP_AI_EventSkip_C visibility.
--- Announces "Hold confirm to skip" once when it first appears.
--- Only polls after episode battle has been entered (avoids FindFirstOf crash during transitions).
function EpisodeBattle.PollCutsceneSkip()
    if not Speak then return end
    -- Only poll when we've been in episode battle context
    -- FindFirstOf on this class crashes during main menu → char select transitions
    if not _announcedEntry and not _storyMapActive then return end

    local ok, skipWidget = pcall(FindFirstOf, "WBP_GRP_AI_EventSkip_C")
    if not ok or not skipWidget or not IsValidRef(skipWidget) then
        if _announcedSkip then _announcedSkip = false end
        return
    end

    local visible = TryCall(skipWidget, "IsVisible")
    if not visible then
        if _announcedSkip then _announcedSkip = false end
        return
    end

    if not _announcedSkip then
        _announcedSkip = true
        -- Read the skip button icon text and pass through icon parser via SpeakQueued
        local skipIcon = nil
        local ok2, skipPath = pcall(function() return skipWidget:GetFullName() end)
        local skipId = ok2 and skipPath:match("(WBP_GRP_AI_EventSkip_C_%d+)") or nil
        if skipId then
            local richBlocks = FindAllOf("RichTextBlock")
            if richBlocks then
                for _, rb in ipairs(richBlocks) do
                    if GetWidgetName(rb) == "RichText_PadButton_1" then
                        local ok3, rbPath = pcall(function() return rb:GetFullName() end)
                        if ok3 and rbPath:find(skipId, 1, true) then
                            local ok4, text = pcall(function() return rb:GetText():ToString() end)
                            if ok4 and text and text ~= "" then skipIcon = text end
                            break
                        end
                    end
                end
            end
        end
        if skipIcon then
            SpeakQueued("Hold " .. skipIcon .. " to skip")
        else
            SpeakQueued("Hold to skip")
        end
        print("[AE] Cutscene skip available")
    end
end

-- === CUTSCENE TEXT: POLL-BASED ===

--- Poll for narration/dialog text in cutscenes.
--- Reads RichText_MainTalk inside WBP_GRP_Common_EventText_C.
--- Announces character name (if present) + dialog text on change.
function EpisodeBattle.PollCutsceneText()
    if not Speak then return end

    local richBlocks = FindAllOf("RichTextBlock")
    if not richBlocks then
        if _lastCutsceneText then _lastCutsceneText = nil end
        return
    end

    -- Find RichText_MainTalk inside WBP_GRP_Common_EventText_C
    local mainTalkText = nil
    local eventTextPath = nil
    for _, rb in ipairs(richBlocks) do
        if GetWidgetName(rb) == "RichText_MainTalk" then
            local ok, rbPath = pcall(function() return rb:GetFullName() end)
            if ok and rbPath:find("WBP_GRP_Common_EventText_C", 1, true)
               and rbPath:find("Transient", 1, true) then
                local ok2, text = pcall(function() return rb:GetText():ToString() end)
                if ok2 and text and text ~= "" then
                    mainTalkText = text
                    -- Extract the EventText instance path for character name lookup
                    eventTextPath = rbPath:match("(WBP_GRP_Common_EventText_C_%d+)")
                    break
                end
            end
        end
    end

    if not mainTalkText then
        if _lastCutsceneText then _lastCutsceneText = nil end
        return
    end

    if mainTalkText == _lastCutsceneText then return end
    _lastCutsceneText = mainTalkText

    -- Look for Text_CharaName in the same EventText container
    local charaName = nil
    if eventTextPath then
        local textBlocks = FindAllOf("TextBlock")
        if textBlocks then
            for _, tb in ipairs(textBlocks) do
                if GetWidgetName(tb) == "Text_CharaName" then
                    local ok, tbPath = pcall(function() return tb:GetFullName() end)
                    if ok and tbPath:find(eventTextPath, 1, true) then
                        local ok2, name = pcall(function() return tb:GetText():ToString() end)
                        if ok2 and name and name ~= "" then
                            charaName = name
                        end
                        break
                    end
                end
            end
        end
    end

    -- Only announce narration (no character name). Voiced dialog has a character name
    -- and is already spoken by the game's voice acting.
    if not charaName then
        local collapsed = mainTalkText:gsub("\n", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
        if collapsed and collapsed ~= "" then
            SpeakQueued(collapsed)
            print("[AE] Cutscene narration: " .. collapsed)

            -- Read the next button icon and pass through icon parser
            if eventTextPath then
                for _, rb in ipairs(richBlocks) do
                    if GetWidgetName(rb) == "RichText_PadButton" then
                        local ok3, rbPath = pcall(function() return rb:GetFullName() end)
                        if ok3 and rbPath:find(eventTextPath, 1, true)
                           and rbPath:find("WBP_OBJ_Common_NextButton", 1, true) then
                            local ok4, btnText = pcall(function() return rb:GetText():ToString() end)
                            if ok4 and btnText and btnText ~= "" then
                                SpeakQueued(btnText)
                            end
                            break
                        end
                    end
                end
            end
        end
    end
end

return EpisodeBattle
