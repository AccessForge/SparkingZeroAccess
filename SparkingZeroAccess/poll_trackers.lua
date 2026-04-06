--[[
    poll_trackers.lua — Dialog, help window, and screen change tracking
    Polled at 100ms intervals from the main loop.
    IsValidRef() on FindFirstOf singletons only; FindAllOf iterations trust fresh results.
]]

local H = require("helpers")
local TryCall = H.TryCall
local IsValidRef = H.IsValidRef
local GetWidgetName = H.GetWidgetName

local Trackers = {}

local Speak = nil
local SpeakQueued = nil

-- Shared transition cooldown: checked by main loop and poll functions.
-- Set when a dialog dismisses or a map loads.
Trackers.transitionCooldownUntil = 0

function Trackers.Init(speakFn, speakQueuedFn)
    Speak = speakFn
    SpeakQueued = speakQueuedFn
end

-- === DIALOG TRACKING ===

local lastDialogState = {}

local function GetDialogText(dialog)
    local richBlocks = FindAllOf("RichTextBlock")
    if not richBlocks then return nil end

    local dialogFullName = dialog:GetFullName()
    local dialogId = dialogFullName:match("(WBP_Dialog_%d+_C_%d+)")
    if not dialogId then return nil end

    for _, rb in ipairs(richBlocks) do
        local rbPath = rb:GetFullName()
        if rbPath:find(dialogId, 1, true) then
            local rbName = GetWidgetName(rb)
            if rbName:find("Text_Main") then
                local getText = TryCall(rb, "GetText")
                if getText then
                    local str = TryCall(getText, "ToString")
                    if str and str ~= "" then return str end
                end
            end
        end
    end

    return nil
end

function Trackers.MarkDialogSeen(dialogId)
    local dialogTypes = {"WBP_Dialog_000_C", "WBP_Dialog_002_C"}
    for _, dtype in ipairs(dialogTypes) do
        local dialogs = FindAllOf(dtype)
        if dialogs then
            for i, d in ipairs(dialogs) do
                if d:GetFullName():find(dialogId, 1, true) then
                    local text = GetDialogText(d)
                    lastDialogState[dtype .. "_" .. i] = {visible = true, text = text}
                end
            end
        end
    end
end

function Trackers.PollDialogs()
    local dialogTypes = {"WBP_Dialog_000_C", "WBP_Dialog_002_C"}

    for _, dtype in ipairs(dialogTypes) do
        local dialogs = FindAllOf(dtype)
        if dialogs then
            for i, d in ipairs(dialogs) do
                local visible = TryCall(d, "IsVisible")
                if not visible then
                    local key = dtype .. "_" .. i
                    if lastDialogState[key] and lastDialogState[key].visible then
                        -- Dialog dismissed — trigger transition cooldown (400ms)
                        Trackers.transitionCooldownUntil = os.clock() + 0.4
                        print("[AE] Dialog dismissed, transition cooldown 400ms")
                    end
                    if lastDialogState[key] then
                        lastDialogState[key].visible = false
                    end
                else
                    local text = GetDialogText(d)
                    local key = dtype .. "_" .. i

                    local prev = lastDialogState[key]
                    local isNew = not prev or not prev.visible
                    local textChanged = prev and prev.text ~= text

                    if (isNew or textChanged) and text then
                        local cleaned = text:gsub("\n", " "):gsub("%s+", " ")
                        Speak(cleaned, true)
                        print("[AE] Dialog: " .. cleaned)
                    elseif isNew and not text then
                        Speak("Dialog opened", true)
                    end

                    lastDialogState[key] = {visible = true, text = text}
                end
            end
        end
    end
end

-- === HELP WINDOW TRACKING ===

local lastHelpWindowState = {}

function Trackers.PollHelpWindows()
    if os.clock() < Trackers.transitionCooldownUntil then return end
    local helpWindows = FindAllOf("WBP_GRP_DB_HelpWindow_C")
    if not helpWindows then return end

    for i, hw in ipairs(helpWindows) do
        local visible = TryCall(hw, "IsVisible")
        local key = "help_" .. i

        if not visible then
            if lastHelpWindowState[key] then
                lastHelpWindowState[key].visible = false
            end
        else
            local bodyText = nil
            local richBlocks = FindAllOf("RichTextBlock")
            if richBlocks then
                local hwId = hw:GetFullName():match("(WBP_GRP_DB_HelpWindow_C_%d+)")
                if hwId then
                    for _, rb in ipairs(richBlocks) do
                        if GetWidgetName(rb) == "TXT_main" then
                            local rbPath = rb:GetFullName()
                            if rbPath:find(hwId, 1, true) then
                                local ok, text = pcall(function() return rb:GetText():ToString() end)
                                if ok and text and text ~= "" then
                                    bodyText = text
                                    break
                                end
                            end
                        end
                    end
                end
            end

            local pageInfo = nil
            local textBlocks = FindAllOf("TextBlock")
            if textBlocks then
                local hwId = hw:GetFullName():match("(WBP_GRP_DB_HelpWindow_C_%d+)")
                if hwId then
                    local page0, page1 = nil, nil
                    for _, tb in ipairs(textBlocks) do
                        local tbPath = tb:GetFullName()
                        if tbPath:find(hwId, 1, true) then
                            local tbName = GetWidgetName(tb)
                            if tbName == "TXT_Page_0" then
                                local ok, t = pcall(function() return tb:GetText():ToString() end)
                                if ok then page0 = t end
                            elseif tbName == "TXT_Page_1" then
                                local ok, t = pcall(function() return tb:GetText():ToString() end)
                                if ok then page1 = t end
                            end
                        end
                    end
                    if page0 and page1 then
                        pageInfo = "Page " .. page0 .. " of " .. page1
                    end
                end
            end

            local prev = lastHelpWindowState[key]
            local isNew = not prev or not prev.visible
            local textChanged = prev and prev.text ~= bodyText

            if (isNew or textChanged) and bodyText then
                local cleaned = bodyText:gsub("\n", " "):gsub("%s+", " ")
                if pageInfo then
                    SpeakQueued(pageInfo)
                    SpeakQueued(cleaned)
                else
                    SpeakQueued(cleaned)
                end
                SpeakQueued("Press Back to close")
                print("[AE] Help: " .. (pageInfo or "") .. " " .. cleaned)
            end

            lastHelpWindowState[key] = {visible = true, text = bodyText}
        end
    end
end

-- === SCREEN TRACKING ===

local lastScreenState = {}

function Trackers.PollScreenChanges()
    if os.clock() < Trackers.transitionCooldownUntil then return end

    local screens = {
        {"WBP_Option_C", "Options Menu"},
        {"WBP_GRP_Title_CI_Logo_C", "Loading"},
        {"WBP_Title_C", "Press confirm to start", 1000},
    }

    for _, screen in ipairs(screens) do
        local typeName, label = screen[1], screen[2]
        local w = FindFirstOf(typeName)
        local isVisible = false

        if IsValidRef(w) and TryCall(w, "IsVisible") then
            isVisible = true
        end

        if isVisible and not lastScreenState[typeName] then
            if screen[3] then
                ExecuteWithDelay(screen[3], function()
                    Speak(label, true)
                    print("[AE] Screen: " .. label .. " (delayed " .. screen[3] .. "ms)")
                end)
            else
                Speak(label, true)
                print("[AE] Screen: " .. label)
            end
        end

        lastScreenState[typeName] = isVisible
    end
end

-- === PLAYER MATCH ROOM POLLING ===

local lastRoomIdText = nil
local lastPlayerStatus = {}  -- panel suffix -> {status, username}

function Trackers.PollRoom()
    -- Guard: skip expensive TextBlock scan if not on room screen
    local ok, roomWindow = pcall(FindFirstOf, "WBP_MenuOLB_PLMatch_Room_LWindow_C")
    if not ok or not roomWindow or not TryCall(roomWindow, "IsVisible") then
        if lastRoomIdText then
            lastRoomIdText = nil
            lastPlayerStatus = {}
        end
        return
    end

    local textBlocks = FindAllOf("TextBlock")
    if not textBlocks then
        lastRoomIdText = nil
        lastPlayerStatus = {}
        return
    end

    -- Collect all room-related TextBlocks in one pass
    local roomId = nil
    local panels = {}  -- suffix -> {field -> value}
    local onRoomScreen = false

    for _, tb in ipairs(textBlocks) do
        local ok, tbPath = pcall(function() return tb:GetFullName() end)
        if not ok then goto continue end

        -- Room ID
        if tbPath:find("PLMatch_Room_LWindow", 1, true)
           and tbPath:find("Transient", 1, true)
           and GetWidgetName(tb) == "TXT_ID" then
            onRoomScreen = true
            local ok2, text = pcall(function() return tb:GetText():ToString() end)
            if ok2 and text then roomId = text end
        end

        -- Player panel fields
        local panelSuffix = tbPath:match("PLMatch_PlayerPanel_(%d+)")
        if panelSuffix and tbPath:find("Transient", 1, true) then
            onRoomScreen = true
            if not panels[panelSuffix] then panels[panelSuffix] = {} end
            local tbName = GetWidgetName(tb)
            local ok2, text = pcall(function() return tb:GetText():ToString() end)
            if ok2 and text and text ~= "" then
                panels[panelSuffix][tbName] = text
            end
        end

        ::continue::
    end

    if not onRoomScreen then
        lastRoomIdText = nil
        lastPlayerStatus = {}
        return
    end

    -- Room ID toggle
    if roomId and roomId ~= lastRoomIdText then
        lastRoomIdText = roomId
        if not roomId:find("XXX", 1, true) and not roomId:find("000-000-000", 1, true) then
            Speak("Room ID, " .. roomId, true)
        end
    end

    -- Player status changes
    for suffix, fields in pairs(panels) do
        local status = fields.TXT_Status_00
        if status == "Text Block" then status = nil end
        local username = fields.TXT_Username_Own
        if not username or username == "Username" then
            username = fields.TXT_UserName
        end
        if username == "Username" then username = nil end
        local enter = fields.TXT_Enter

        -- Build a key for tracking: "username|status" or "Available"
        local current
        if username and status then
            current = username .. "|" .. status
        elseif enter == "Available" then
            current = "Available"
        else
            current = nil
        end

        local prev = lastPlayerStatus[suffix]
        if current and current ~= prev then
            lastPlayerStatus[suffix] = current
            -- Don't announce on first detection (initial load)
            if prev ~= nil then
                local slotNum = tonumber(suffix) + 1
                if current == "Available" then
                    SpeakQueued("Slot " .. slotNum .. ", Available")
                elseif username and status then
                    SpeakQueued("Slot " .. slotNum .. ", " .. username .. ", " .. status)
                end
            end
        elseif current == nil and prev ~= nil then
            lastPlayerStatus[suffix] = nil
        end
    end
end

return Trackers
