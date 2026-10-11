--[[
    team_overview.lua — Team setup screen reading
    Handles the 5 team slots (HitButton_0 through _4), Remove/Switch buttons.
    Reads character names from the speech bubble (Text_CharaName in
    WBP_OBJ_Common_TexWin_Black).

    Strategy: Hook TextBlock:SetText to capture character names as the game
    sets them, since LoopAsync polling can't read TextBlock text reliably
    (different UObject access context than keybind callbacks).
]]

local H = require("helpers")
local FindAllOf = H.FindAllOf
local FindFirstOf = H.FindFirstOf
local TryCall = H.TryCall
local GetWidgetName = H.GetWidgetName
local Roster = require("chara_roster")

local TeamOV = {}

-- === SETTEXT HOOK: CAPTURE BUBBLE NAME ===
-- The game calls SetText on Text_CharaName when updating the speech bubble.
-- We hook that call to capture the name without needing to read from LoopAsync.

local _capturedBubbleName = nil  -- latest character name captured by hook
local _hookRegistered = false

--- Initialize the SetText hook. Call once at startup.
function TeamOV.InitHook()
    if _hookRegistered then return end

    -- Try hooking TextBlock:SetText — this fires when ANY TextBlock text changes
    local hookPath = "/Script/UMG.TextBlock:SetText"
    local ok, err = pcall(function()
        RegisterHook(hookPath, function(context, newText)
            -- context = the TextBlock being modified
            -- newText = the FText value being set
            local nameOk, wName = pcall(function() return context:get():GetFullName() end)
            if not nameOk then return end

            -- Only care about Text_CharaName inside the speech bubble
            if wName:find("Text_CharaName", 1, true)
               and wName:find("WBP_OBJ_Common_TexWin_Black", 1, true)
               and wName:find("Transient", 1, true) then
                -- Extract the text value
                local textOk, textStr = pcall(function()
                    return newText:get():ToString()
                end)
                if textOk and textStr and textStr:match("%S") then
                    _capturedBubbleName = textStr
                    print("[AE] SetText hook captured bubble name: " .. textStr)
                else
                    -- Game cleared the text (empty or whitespace)
                    print("[AE] SetText hook: Text_CharaName cleared")
                end
            end
        end)
        _hookRegistered = true
        print("[AE] TextBlock:SetText hook registered for bubble name capture")
    end)

    if not ok then
        print("[AE] WARNING: Could not register SetText hook: " .. tostring(err))
        print("[AE] Will fall back to direct read (may not work from LoopAsync)")
    end
end

--- Consume the captured bubble name (returns it once, then clears).
function TeamOV.ConsumeCapturedName()
    local result = _capturedBubbleName
    _capturedBubbleName = nil
    return result
end

--- Get the captured name without consuming it (for checking).
function TeamOV.GetCapturedName()
    return _capturedBubbleName
end

--- Clear captured name (e.g. on screen transition).
function TeamOV.ClearCapturedName()
    _capturedBubbleName = nil
end

-- === HOLD BUTTON CAPTION CACHE ===
-- Called by the focus reader, already on the game thread. Do not enqueue a
-- nested ExecuteInGameThread action: UE4SS 3.0.1 is iterating that action list.

local _holdButtonCaptions = {}  -- btnId -> caption string
--- Refresh hold button captions from the current team screen.
function TeamOV.RequestHoldButtonCaptions()
    _holdButtonCaptions = {}
    -- Duplicate hold buttons can belong to the roster grid; match BtnSet.
    local textBlocks = FindAllOf("TextBlock")
    if textBlocks then
        for _, tb in ipairs(textBlocks) do
            local ok, tbPath = pcall(function() return tb:GetFullName() end)
            if ok and tbPath:find("Transient", 1, true)
               and tbPath:find("BtnSet", 1, true)
               and GetWidgetName(tb) == "caption" then
                local btnId = tbPath:match("(WBP_OBJ_Common_HoldButton_%d+)")
                if btnId then
                    local ok2, text = pcall(function() return tb:GetText():ToString() end)
                    if ok2 and text and text:match("%S") then
                        _holdButtonCaptions[btnId] = text
                        print("[AE] GameThread hold caption: " .. btnId .. " = " .. text)
                    end
                end
            end
        end
    end
end

--- Check if hold button captions have been cached.
function TeamOV.HaveHoldCaptions()
    return next(_holdButtonCaptions) ~= nil
end

-- === GUIDE BAR READING ===

--- Read the bottom guide bar shortcuts from WBP_OBJ_GuideButtonSet.
--- Returns a list of shortcut strings like {"Space Confirm", "2 Stage Select", ...}
--- Also includes hold buttons (Start Battle, Return to Main Menu).
function TeamOV.ReadGuideBar()
    local shortcuts = {}

    -- Hold buttons — read key icon from RichTextBlock (works from LoopAsync),
    -- caption from game-thread cache (TextBlock needs game thread to resolve).
    -- Filter by BtnSet parent to avoid duplicate instances in roster grid.
    local holdBtnIds = {"WBP_OBJ_Common_HoldButton_00", "WBP_OBJ_Common_HoldButton_01"}
    local richBlocks2 = FindAllOf("RichTextBlock")
    for _, btnId in ipairs(holdBtnIds) do
        local caption = _holdButtonCaptions[btnId]
        if caption then
            -- Read key icon from RichTextBlock inside BtnSet
            local key = nil
            if richBlocks2 then
                for _, rb in ipairs(richBlocks2) do
                    local ok, rbPath = pcall(function() return rb:GetFullName() end)
                    if ok and rbPath:find(btnId, 1, true)
                       and rbPath:find("BtnSet", 1, true)
                       and rbPath:find("Transient", 1, true)
                       and GetWidgetName(rb) == "RichText_PadButton_1" then
                        local ok2, text = pcall(function() return rb:GetText():ToString() end)
                        if ok2 and text and text:match("%S") then key = text end
                        break
                    end
                end
            end
            table.insert(shortcuts, "Hold " .. (key and (key .. " ") or "") .. caption)
        end
    end

    -- Read guide button set (bottom bar)
    local guideWidgets = {
        "WBP_OBJ_Guide_Btn_Present",
        "WBP_OBJ_Guide_Btn_0",
        "WBP_OBJ_Guide_Btn_1",
        "WBP_OBJ_Guide_Btn_2",
        "WBP_OBJ_Guide_Btn_3",
    }
    local richBlocks = FindAllOf("RichTextBlock")
    if richBlocks then
        for _, gw in ipairs(guideWidgets) do
            for _, rb in ipairs(richBlocks) do
                local ok, rbPath = pcall(function() return rb:GetFullName() end)
                if ok and rbPath:find(gw, 1, true)
                   and rbPath:find("Transient", 1, true)
                   and GetWidgetName(rb) == "RTEXT_Help_0" then
                    local ok2, text = pcall(function() return rb:GetText():ToString() end)
                    if ok2 and text and text:match("%S")
                       and not text:find("ヘルプテキスト") then
                        table.insert(shortcuts, text)
                    end
                    break
                end
            end
        end
    end

    return shortcuts
end

-- === CONTEXT DETECTION ===

function TeamOV.IsTeamSlot(widget)
    local name = GetWidgetName(widget)
    if not name:match("^WBP_OBJ_Common_HitButton_%d+$") then return false end
    local path = widget:GetFullName()
    return path:find("WBP_GRP_BS_Top_00_1P_C", 1, true) ~= nil
        or path:find("WBP_GRP_BS_Top_00_2P_C", 1, true) ~= nil
end

-- === READING ===

function TeamOV.GetSlotInfo(widget)
    local name = GetWidgetName(widget)
    local slot = name:match("HitButton_(%d+)$")
    if not slot then return nil, nil end

    local path = widget:GetFullName()
    local side = nil
    if path:find("Top_00_1P", 1, true) then
        side = "Player 1"
    elseif path:find("Top_00_2P", 1, true) then
        side = "Player 2"
    end

    return tonumber(slot), side
end

--- Read character name from speech bubble, or nil if slot is empty.
--- Direct scan every time — no cache needed for 5 slots.
local _bubbleLogCounter = 0

function TeamOV.ReadBubbleName()
    _bubbleLogCounter = _bubbleLogCounter + 1
    local logThis = (_bubbleLogCounter % 10 == 1)

    -- === METHOD A: Parent widget property traversal ===
    -- FindFirstOf the bubble widget, then access Text_CharaName as a child property.
    -- Different UE4SS code path from FindAllOf — may work from LoopAsync.
    local ok_a, result_a = pcall(function()
        local bubble = FindFirstOf("WBP_OBJ_Common_TexWin_Black_C")
        if not bubble then return nil, "no bubble widget" end
        -- Check it's a live instance
        local bPath = bubble:GetFullName()
        if not bPath:find("Transient", 1, true) then return nil, "not transient" end

        -- Try accessing Text_CharaName as a property of the bubble widget
        local textWidget = bubble.Text_CharaName
        if not textWidget then return nil, "no Text_CharaName property" end

        -- Try .Text property on the TextBlock
        local ftxt = textWidget.Text
        if ftxt then
            local str = ftxt:ToString()
            if str and str:match("%S") then return str, "A.Text" end
        end

        -- Try :GetText():ToString()
        local gt = textWidget:GetText()
        if gt then
            local str = gt:ToString()
            if str and str:match("%S") then return str, "A.GetText" end
        end

        return nil, "Text_CharaName found but empty"
    end)

    if ok_a and result_a then
        if logThis then print("[AE] Bubble #" .. _bubbleLogCounter .. ": " .. tostring(result_a) .. " via parent traversal") end
        return result_a
    end

    -- === METHOD B: FindFirstOf("WBP_GRP_BS_Top_00_TextSub_C") ===
    -- The TextSub is the parent container of the bubble
    local ok_b, result_b = pcall(function()
        local textSub = FindFirstOf("WBP_GRP_BS_Top_00_TextSub_C")
        if not textSub then return nil, "no TextSub" end
        local subPath = textSub:GetFullName()
        if not subPath:find("Transient", 1, true) then return nil, "TextSub not transient" end

        -- Try navigating: TextSub -> WBP_OBJ_Common_TexWin_Black -> Text_CharaName
        local bubble = textSub.WBP_OBJ_Common_TexWin_Black
        if not bubble then return nil, "no TexWin_Black in TextSub" end
        local textWidget = bubble.Text_CharaName
        if not textWidget then return nil, "no Text_CharaName in TexWin_Black" end

        local ftxt = textWidget.Text
        if ftxt then
            local str = ftxt:ToString()
            if str and str:match("%S") then return str, "B.Text" end
        end
        local gt = textWidget:GetText()
        if gt then
            local str = gt:ToString()
            if str and str:match("%S") then return str, "B.GetText" end
        end
        return nil, "TextSub path found but empty"
    end)

    if ok_b and result_b then
        if logThis then print("[AE] Bubble #" .. _bubbleLogCounter .. ": " .. tostring(result_b) .. " via TextSub") end
        return result_b
    end

    -- === METHOD C: FindAllOf("TextBlock") scan (original, rarely works from LoopAsync) ===
    local ok_c, result_c = pcall(function()
        local textBlocks = FindAllOf("TextBlock")
        if not textBlocks then return nil, "no TextBlocks" end
        for _, tb in ipairs(textBlocks) do
            if GetWidgetName(tb) == "Text_CharaName" then
                local tbPath = tb:GetFullName()
                if tbPath:find("Transient", 1, true)
                   and tbPath:find("WBP_OBJ_Common_TexWin_Black", 1, true) then
                    -- .Text property
                    local ftxt = tb.Text
                    if ftxt then
                        local str = ftxt:ToString()
                        if str and str:match("%S") then return str, "C.Text" end
                    end
                    -- :GetText()
                    local gt = tb:GetText()
                    if gt then
                        local str = gt:ToString()
                        if str and str:match("%S") then return str, "C.GetText" end
                    end
                    return nil, "C found TB but empty"
                end
            end
        end
        return nil, "C no matching TB"
    end)

    if ok_c and result_c then
        if logThis then print("[AE] Bubble #" .. _bubbleLogCounter .. ": " .. tostring(result_c) .. " via FindAllOf") end
        return result_c
    end

    -- Log failures periodically
    if logThis then
        local detail_a = ok_a and tostring(select(2, ok_a, result_a)) or tostring(result_a)
        local detail_b = ok_b and tostring(select(2, ok_b, result_b)) or tostring(result_b)
        local detail_c = ok_c and tostring(select(2, ok_c, result_c)) or tostring(result_c)
        print("[AE] Bubble #" .. _bubbleLogCounter .. " FAILED: A=" .. detail_a .. " B=" .. detail_b .. " C=" .. detail_c)
    end

    return nil
end

--- Find a team slot's CharaIcon IMG_Face_Main portrait image.
--- slotIndex: 0-4 (matches HitButton_0 through _4)
--- side: "1P" or "2P" (defaults to "1P")
--- owner: optional Top_00 instance name of the focused slot
function TeamOV.FindSlotPortrait(slotIndex, side, owner)
    return Roster.FindPortrait("WBP_OBJ_BS_CharaIcon_" .. slotIndex, "Top_00_" .. (side or "1P"), owner)
end

--- Read character ID from CharaIcon's IMG_Face_Main texture.
--- Returns the character ID string (e.g. "0000_00") or nil for empty/unreadable
--- slots, then the texture name and the portrait image.
function TeamOV.ReadSlotTextureId(slotIndex, side, owner)
    local image = TeamOV.FindSlotPortrait(slotIndex, side, owner)
    if not image then return nil end
    local texName = Roster.ReadPortrait(image)
    -- Pattern: T_UI_ChThumbP1_XXXX_YY_ZZ or T_UI_ChThumbP2_XXXX_YY_ZZ
    local charaId = texName and texName:match("T_UI_ChThumb[^_]+_(%d+_%d+)_%d+")
    return charaId, texName, image
end

--- Test texture reading from current context.
--- Logs results for all 5 slots. Used to verify LoopAsync compatibility.
function TeamOV.TestTextureRead()
    print("[AE] === Texture Read Test ===")
    for i = 0, 4 do
        local charaId, texName = TeamOV.ReadSlotTextureId(i)
        if charaId then
            print("[AE] Slot " .. (i+1) .. ": charaId=" .. charaId .. " tex=" .. tostring(texName))
        elseif texName then
            print("[AE] Slot " .. (i+1) .. ": no character (" .. texName .. ")")
        else
            print("[AE] Slot " .. (i+1) .. ": unreadable")
        end
    end
    print("[AE] === End Texture Test ===")
end

--- Read character name and DP for a team slot from its portrait.
--- side: "1P" or "2P" (defaults to "1P")
--- Returns Roster.DescribePortrait's name, charaId, dp (charaId may also be
--- "empty", "question", "free" or "unrecognized"; all nil while not readable),
--- followed by the portrait image and texture name.
function TeamOV.ReadSlotCharaName(slotIndex, side, owner)
    local image = TeamOV.FindSlotPortrait(slotIndex, side, owner)
    if not image then return nil, nil, nil, nil, nil end
    local texName = Roster.ReadPortrait(image)
    local name, charaId, dp = Roster.DescribePortrait(texName, image)
    return name, charaId, dp, image, texName
end

--- Count filled slots and total their DP.
--- side: "1P" or "2P" (defaults to "1P")
--- Returns total (nil when any filled slot's DP is unknown) and the count;
--- both nil while any slot shows neither a character nor Empty (loading,
--- "?", unrecognized), since its member is not known.
function TeamOV.GetTotalDP(side, owner)
    local total = 0
    local count = 0
    for i = 0, 4 do
        local _, charaId, dp = TeamOV.ReadSlotCharaName(i, side, owner)
        if charaId ~= "empty" then
            if not (charaId and charaId:match("^%d+_%d+$")) then return nil, nil end
            count = count + 1
            total = (total and dp) and (total + dp) or nil
        end
    end
    return total, count
end

--- No-op for compatibility (main.lua calls this on screen transitions)
function TeamOV.InvalidateCache()
    _holdButtonCaptions = {}
end

return TeamOV
