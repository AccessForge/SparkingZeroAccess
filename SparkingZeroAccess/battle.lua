--[[
    battle.lua — Battle screen accessibility
    Handles intro cutscene and in-battle HUD reading.

    Game values (from SSCharacter C++ class):
      HPGaugeValue     — HP (each bar = 10,000 units)
      SPGaugeValue     — KI energy (each bar = 10,000, max varies)
      SparkingGaugeValue — Sparking/burst gauge (full = 50,000)
      BlastStockCount  — blast stock count
      ComboNum         — current combo hit count
]]

local H = require("helpers")
local TryCall = H.TryCall
local IsValidRef = H.IsValidRef
local GetWidgetName = H.GetWidgetName

local Battle = {}

-- === CONSTANTS ===

local KI_PER_BAR = 10000
local SPARKING_FULL = 50000
local SPARKING_PER_BAR = 10000
local HP_THRESHOLDS = {75, 50, 25, 10}  -- percentage thresholds to announce


-- === INTERNAL STATE ===

local _introAnnounced = false
local _lastPlayerHP = nil       -- last raw HP value
local _maxPlayerHP = nil        -- max HP (captured at battle start)
local _lastHPThreshold = nil    -- last announced HP threshold index
local _lastKIBars = nil         -- last announced KI in bars (rounded)
local _lastSparkingBars = nil   -- last announced Sparking in bars (countdown)
local _lastSkillPoints = nil    -- last announced skill point count (BlastStockCount)
local _lastPawnPath = nil       -- track pawn identity for character switch detection
local _inBattle = false         -- are we in an active battle
local _battleWasActive = false  -- set when HUD first reads; survives Reset() for post-battle polls

-- Timer state
local _timerWidget = nil        -- cached WBP_Rep_TimeCount_C (SSBattleTimer)
local _timerDigitImgs = nil     -- cached {[2]=IMG hundreds, [1]=IMG tens, [0]=IMG ones}
local _timerDigitParents = nil  -- cached {[2]=WBP_Rep_TimerNum_02, ...} for visibility checks
local _lastTimerSeconds = nil   -- last read timer value in seconds
local _infiniteImg = nil        -- cached IMG_Infinite widget for no-time-limit detection
local _timerStartAnnounced = false -- have we announced the initial time limit

-- Result screen state
local _resultAnnounced = false  -- have we announced the result screen
local _resultResetCallback = nil -- callback to trigger full reset when result screen closes
local _cachedResultWidget = nil -- live ref to the visible+Transient result widget once found
local _resultMissUntil = 0      -- throttle for negative FindAllOf results during battle


-- Opponent tracking (keyed by pawn path)
local _enemyState = {}  -- path -> {lastHP, maxHP, lastThreshold, lastKIBars}

-- === HELPER: GET PLAYER AND OPPONENT PAWNS ===

local _pawnDetectionLogged = false
local _playerSide = nil  -- "1P" or "2P", set from character select

--- Set player side from character select screen.
--- Called by main.lua when team overview detects which side we're on.
--- Only accepts the first value per match — browsing the opponent's team
--- must not overwrite your actual side.
function Battle.SetPlayerSide(side)
    if not _playerSide then
        _playerSide = side
        _pawnDetectionLogged = false
        print("[AE] Player side set: " .. tostring(side))
    end
end

--- Clear player side. Called when entering character select for a new match.
function Battle.ResetPlayerSide()
    _playerSide = nil
end

local function GetPlayerPawn()
    -- Find the camera controller (GetViewTarget = BP_DirectorMainCamera_C).
    -- Its Pawn is always the P1-side character.
    -- When we're P1: that's our pawn.
    -- When we're P2: our pawn is its TargetPawn (the opponent from P1's view).
    local ok, allCtrls = pcall(FindAllOf, "BP_BattlePlayerController_C")
    if ok and allCtrls then
        for _, ctrl in ipairs(allCtrls) do
            local vtOk, vt = pcall(function() return ctrl:GetViewTarget() end)
            if vtOk and vt then
                local vtNameOk, vtName = pcall(function() return vt:GetFullName() end)
                if vtNameOk and vtName and vtName:find("BP_DirectorMainCamera_C") then
                    local pok, p1Pawn = pcall(function() return ctrl.Pawn end)
                    if not pok or not p1Pawn then break end
                    local nameOk, name = pcall(function() return p1Pawn:GetFullName() end)
                    if not nameOk or not name or not name:find("BPCHR_") then break end

                    if _playerSide == "2P" then
                        -- We're P2: our pawn is P1's TargetPawn
                        local tpOk, tp = pcall(function() return p1Pawn.TargetPawn end)
                        if tpOk and tp then
                            local tpNameOk, tpName = pcall(function() return tp:GetFullName() end)
                            if tpNameOk and tpName and tpName:find("BPCHR_") then
                                if not _pawnDetectionLogged then
                                    _pawnDetectionLogged = true
                                    print("[AE] Player pawn (2P via TargetPawn): " .. tpName:sub(1, 80))
                                end
                                return tp
                            end
                        end
                    else
                        -- We're P1 (or unknown/offline): camera controller's pawn is ours
                        if not _pawnDetectionLogged then
                            _pawnDetectionLogged = true
                            print("[AE] Player pawn (1P camera controller): " .. name:sub(1, 80))
                        end
                        return p1Pawn
                    end
                end
            end
        end
    end

    -- Fallback: controller approach (offline / single player)
    local cok, pc = pcall(FindFirstOf, "BP_BattlePlayerController_C")
    if not cok or not pc then return nil end
    local pok, pawn = pcall(function() return pc.Pawn end)
    if not pok or not pawn then return nil end
    local nameOk, name = pcall(function() return pawn:GetFullName() end)
    if nameOk and name and name:find("BPCHR_") then
        if not _pawnDetectionLogged then
            _pawnDetectionLogged = true
            print("[AE] Player pawn (FALLBACK controller): " .. name:sub(1, 80))
        end
        return pawn
    end
    return nil
end

local function ReadGauges(pawn)
    if not pawn then return nil end
    local values = {}
    local ok1, hp = pcall(function() return pawn.HPGaugeValue end)
    if ok1 and type(hp) == "number" then values.hp = hp end
    local ok2, sp = pcall(function() return pawn.SPGaugeValue end)
    if ok2 and type(sp) == "number" then values.sp = sp end
    local ok3, sparking = pcall(function() return pawn.SparkingGaugeValue end)
    if ok3 and type(sparking) == "number" then values.sparking = sparking end
    local ok4, blast = pcall(function() return pawn.BlastStockCount end)
    if ok4 and type(blast) == "number" then values.blast = blast end
    local ok5, combo = pcall(function() return pawn.ComboNum end)
    if ok5 and type(combo) == "number" then values.combo = combo end
    return values
end

local function GetEnemyPawns(playerPawn)
    local enemies = {}

    -- Primary: use TargetPawn property (reliable — set by the game itself)
    local tok, target = pcall(function() return playerPawn.TargetPawn end)
    if tok and target then
        local nameOk, name = pcall(function() return target:GetFullName() end)
        if nameOk and name and name:find("BPCHR_") then
            table.insert(enemies, {pawn = target, path = name})
            return enemies
        end
    end

    -- Fallback: scan all pawns (offline/single player)
    local ok, allPawns = pcall(FindAllOf, "Pawn")
    if not ok or not allPawns then return {} end

    local playerPath = nil
    pcall(function() playerPath = playerPawn:GetFullName() end)

    for _, p in ipairs(allPawns) do
        local pok, path = pcall(function() return p:GetFullName() end)
        if pok and path and path:find("BPCHR_") then
            if not playerPath or path ~= playerPath then
                table.insert(enemies, {pawn = p, path = path})
            end
        end
    end
    return enemies
end

local function ToBars(value, perBar)
    return math.floor(value / perBar)
end

-- === TIMER READING ===

--- Extract digit (0-9) from a timer Image widget's texture name.
--- Texture pattern: T_UI_TimeNum_XX where XX = 00..09
local function ReadTimerDigit(imgWidget)
    local ok, name = pcall(function()
        return imgWidget.Brush.ResourceObject:GetFName():ToString()
    end)
    if not ok or not name then return nil end
    local digit = name:match("_(%d%d)$")
    if digit then return tonumber(digit) end
    return nil
end

--- Find and cache the 3 timer digit Image widgets (IMG_Num_A inside WBP_Rep_TimerNum_00/01/02)
--- and their parent widgets (for visibility checks), plus IMG_Infinite.
local function CacheTimerDigits()
    if _timerDigitImgs then return true end

    local ok, timer = pcall(FindFirstOf, "WBP_Rep_TimeCount_C")
    if not ok or not timer then return false end
    local validOk, valid = pcall(function() return timer:IsValid() end)
    if not validOk or not valid then return false end
    _timerWidget = timer

    -- Cache IMG_Infinite ref directly from the widget property
    local infOk, infImg = pcall(function() return timer.IMG_Infinite end)
    if infOk and infImg then
        _infiniteImg = infImg
    end

    -- Cache parent digit widgets for visibility checks
    _timerDigitParents = {}
    for i = 0, 2 do
        local propName = "WBP_Rep_TimerNum_0" .. i
        local pok, parent = pcall(function() return timer[propName] end)
        if pok and parent then
            _timerDigitParents[i] = parent
        end
    end

    -- Find IMG_Num_A inside each of the 3 digit positions
    local iok2, images = pcall(FindAllOf, "Image")
    if not iok2 or not images then return false end

    local digits = {}
    for _, img in ipairs(images) do
        local iok, imgPath = pcall(function() return img:GetFullName() end)
        if iok and imgPath and imgPath:find("Transient", 1, true)
           and imgPath:find("WBP_Rep_TimeCount_C", 1, true) then
            local imgName = GetWidgetName(img)
            if imgName == "IMG_Num_A" then
                -- Determine position from parent: WBP_Rep_TimerNum_02 = hundreds, _01 = tens, _00 = ones
                -- Only use the primary set (no _01 suffix on TimerNum)
                if imgPath:find("WBP_Rep_TimerNum_02%.", 1, false) then
                    digits[2] = img
                elseif imgPath:find("WBP_Rep_TimerNum_01%.", 1, false) then
                    digits[1] = img
                elseif imgPath:find("WBP_Rep_TimerNum_00%.", 1, false) then
                    digits[0] = img
                end
            end
        end
    end

    if digits[2] and digits[1] and digits[0] then
        _timerDigitImgs = digits
        print("[AE] Timer digit images cached")
        return true
    end
    return false
end

local TIMER_INFINITE = -1  -- sentinel for no time limit

--- Read the current timer value in seconds from the HUD textures.
--- Returns TIMER_INFINITE if no time limit, nil if reading fails.
local function ReadTimerSeconds()
    if not _timerDigitImgs then
        if not CacheTimerDigits() then return nil end
    end

    -- Validate timer widget is still alive before accessing cached children
    if _timerWidget and not IsValidRef(_timerWidget) then
        print("[AE] Timer widget stale, invalidating cache")
        _timerWidget = nil
        _timerDigitImgs = nil
        _timerDigitParents = nil
        _infiniteImg = nil
        return nil
    end

    -- No time limit — IMG_Infinite is visible
    if _infiniteImg then
        local visOk, visible = pcall(TryCall, _infiniteImg, "IsVisible")
        if visOk and visible then return TIMER_INFINITE end
    end

    -- Check parent widget visibility — game hides digit widgets instead of
    -- changing texture to 0 (e.g. hundreds hidden when timer < 100)
    local hundreds = 0
    if _timerDigitParents[2] and TryCall(_timerDigitParents[2], "IsVisible") then
        hundreds = ReadTimerDigit(_timerDigitImgs[2]) or 0
    end
    local tens = 0
    if _timerDigitParents[1] and TryCall(_timerDigitParents[1], "IsVisible") then
        tens = ReadTimerDigit(_timerDigitImgs[1]) or 0
    end
    local ones = ReadTimerDigit(_timerDigitImgs[0])

    if ones then
        return hundreds * 100 + tens * 10 + ones
    end

    -- Read failed — refs likely stale, invalidate cache
    _timerDigitImgs = nil
    _timerDigitParents = nil
    return nil
end


-- === INTRO CUTSCENE (removed — was not working reliably) ===

-- === BATTLE HUD POLLING ===

--- Poll battle HUD values and announce significant changes.
--- Called from the 100ms poll loop.
function Battle.PollHUD(Speak, SpeakQueued)
    local pawn = GetPlayerPawn()
    if not pawn then
        -- Pawn briefly nil during animations/events — don't reset tracking state.
        -- All state resets only on map transition (Battle.Reset).
        return
    end

    local gauges = ReadGauges(pawn)
    if not gauges or not gauges.hp then return end

    local currentKIBars = gauges.sp and ToBars(gauges.sp, KI_PER_BAR) or 0
    local currentSparkBars = gauges.sparking and ToBars(gauges.sparking, SPARKING_PER_BAR) or 0

    -- First reading — capture baselines silently
    if not _maxPlayerHP then
        _maxPlayerHP = gauges.hp
        _lastPlayerHP = gauges.hp
        _lastHPThreshold = 0
        _lastKIBars = currentKIBars
        _lastSparkingBars = currentSparkBars
        _lastSkillPoints = gauges.blast or 0
        _battleWasActive = true
        print("[AE] Battle started: HP=" .. gauges.hp .. " (max)")
        return
    end

    -- === TIMER ===
    local timerSecs = ReadTimerSeconds()
    if timerSecs then
        -- Store initial value silently
        if not _timerStartAnnounced then
            _timerStartAnnounced = true
            if timerSecs ~= TIMER_INFINITE then
                _lastTimerSeconds = timerSecs
            end
        end

        if timerSecs ~= TIMER_INFINITE and _lastTimerSeconds and timerSecs ~= _lastTimerSeconds then
                if timerSecs % 30 == 0 then
                Speak(timerSecs .. " seconds", true)
            end
            if timerSecs <= 10 and timerSecs > 0 then
                -- Final countdown on 10, 5, 4, 3, 2, 1 seconds
                if timerSecs <= 5 or timerSecs == 10 then
                    Speak(timerSecs .. "", true)
                end
            end
            _lastTimerSeconds = timerSecs
        end
    end

    -- Detect character switch by pawn identity change
    local pawnPath = nil
    pcall(function() pawnPath = pawn:GetFullName() end)
    if pawnPath and _lastPawnPath and pawnPath ~= _lastPawnPath then
        _maxPlayerHP = gauges.hp
        _lastHPThreshold = 0
        print("[AE] Character switch: " .. pawnPath)
    end
    _lastPawnPath = pawnPath

    -- Track highest HP seen
    if gauges.hp > _maxPlayerHP then
        _maxPlayerHP = gauges.hp
    end

    -- HP percentage thresholds — one-shot per match, never re-trigger
    if _maxPlayerHP > 0 then
        local hpPercent = (gauges.hp / _maxPlayerHP) * 100

        if gauges.hp <= 0 and (_lastPlayerHP or 0) > 0 then
            Speak("HP empty", true)
        else
            for i, threshold in ipairs(HP_THRESHOLDS) do
                if hpPercent <= threshold and (_lastHPThreshold or 0) < i then
                    _lastHPThreshold = i
                    Speak("HP " .. threshold .. " percent", true)
                    break
                end
            end
        end
    end

    -- KI bar change
    if _lastKIBars and currentKIBars ~= _lastKIBars then
        if currentKIBars <= 0 then
            Speak("KI empty", true)
        else
            Speak("KI " .. currentKIBars, true)
        end
        _lastKIBars = currentKIBars
    end

    -- Sparking gauge — announce activation, countdown every bar, and ended
    if _lastSparkingBars ~= nil and currentSparkBars ~= _lastSparkingBars then
        if currentSparkBars >= 5 and _lastSparkingBars < 5 then
            -- Just activated (jumped from 0 to 50k)
            Speak("Sparking", true)
        elseif currentSparkBars <= 0 and _lastSparkingBars > 0 then
            -- Drained completely
            Speak("Sparking ended", true)
        elseif currentSparkBars < _lastSparkingBars and currentSparkBars > 0 then
            -- Draining — announce countdown
            SpeakQueued("Sparking " .. currentSparkBars)
        end
        _lastSparkingBars = currentSparkBars
    end

    -- Skill points (BlastStockCount)
    local currentSkill = gauges.blast or 0
    if _lastSkillPoints and currentSkill ~= _lastSkillPoints then
        SpeakQueued(currentSkill .. " skill points")
    end
    _lastSkillPoints = currentSkill

    _lastPlayerHP = gauges.hp

    -- === OPPONENTS (all non-player BPCHR pawns) ===
    local enemies = GetEnemyPawns(pawn)
    for _, enemy in ipairs(enemies) do
        local eg = ReadGauges(enemy.pawn)
        if eg and eg.hp then
            -- Get or create state for this pawn
            local es = _enemyState[enemy.path]
            if not es then
                es = {lastHP = eg.hp, maxHP = eg.hp, lastThreshold = 0, lastKIBars = eg.sp and ToBars(eg.sp, KI_PER_BAR) or 0, lastSparkingBars = eg.sparking and ToBars(eg.sparking, SPARKING_PER_BAR) or 0}
                _enemyState[enemy.path] = es
            end

            local enemyKIBars = eg.sp and ToBars(eg.sp, KI_PER_BAR) or 0
            local enemySparkBars = eg.sparking and ToBars(eg.sparking, SPARKING_PER_BAR) or 0

            -- Track highest enemy HP seen
            if eg.hp > es.maxHP then
                es.maxHP = eg.hp
            end

            -- Enemy HP thresholds
            if es.maxHP > 0 then
                local enemyPercent = (eg.hp / es.maxHP) * 100

                if eg.hp <= 0 and es.lastHP > 0 then
                    Speak("Enemy HP empty", true)
                else
                    for i, threshold in ipairs(HP_THRESHOLDS) do
                        if enemyPercent <= threshold and es.lastThreshold < i then
                            es.lastThreshold = i
                            Speak("Enemy HP " .. threshold .. " percent", true)
                            break
                        end
                    end
                end
            end

            -- Enemy KI bar change
            if enemyKIBars ~= es.lastKIBars then
                if enemyKIBars <= 0 then
                    SpeakQueued("Enemy KI empty")
                else
                    SpeakQueued("Enemy KI " .. enemyKIBars)
                end
                es.lastKIBars = enemyKIBars
            end

            -- Enemy Sparking gauge
            if enemySparkBars ~= es.lastSparkingBars then
                if enemySparkBars >= 5 and es.lastSparkingBars < 5 then
                    SpeakQueued("Enemy Sparking")
                elseif enemySparkBars <= 0 and es.lastSparkingBars > 0 then
                    SpeakQueued("Enemy Sparking ended")
                elseif enemySparkBars < es.lastSparkingBars and enemySparkBars > 0 then
                    SpeakQueued("Enemy Sparking " .. enemySparkBars)
                end
                es.lastSparkingBars = enemySparkBars
            end

            es.lastHP = eg.hp
        end
    end
end

--- Read current battle status on demand. Returns a formatted string.
function Battle.ReadStatus()
    local pawn = GetPlayerPawn()
    if not pawn then return nil end

    local g = ReadGauges(pawn)
    if not g or not g.hp then return nil end

    local hpPercent = _maxPlayerHP and _maxPlayerHP > 0 and math.floor((g.hp / _maxPlayerHP) * 100) or 0
    local spBars = g.sp and ToBars(g.sp, KI_PER_BAR) or 0
    local parts = {}
    table.insert(parts, "HP " .. hpPercent .. " percent")
    table.insert(parts, "KI " .. spBars .. " bars")
    if g.sparking and g.sparking >= SPARKING_FULL then
        table.insert(parts, "Sparking ready")
    end
    if g.blast and g.blast > 0 then
        table.insert(parts, "Blast stock " .. g.blast)
    end
    return table.concat(parts, ", ")
end

-- === RESULT SCREEN ===
-- Polled from the 100ms loop. Uses FindAllOf + IsVisible to detect
-- post-battle screens (no keyboard focus lands on them).

--- Helper: read a TextBlock's text by name from a pre-fetched list,
--- scoped to a specific parent widget path.
local function ReadTextBlock(textBlocks, parentPath, targetName)
    for _, tb in ipairs(textBlocks) do
        local tok, tbPath = pcall(function() return tb:GetFullName() end)
        if tok and tbPath and tbPath:find(parentPath, 1, true) then
            if GetWidgetName(tb) == targetName then
                local ok, text = pcall(function() return tb:GetText():ToString() end)
                if ok and text and text:match("%S") then return text end
            end
        end
    end
    return nil
end

--- Find the visible+Transient result widget. Caches the ref once found and
--- only re-runs FindAllOf when the cached ref dies, becomes hidden, or after
--- a 500ms negative-cache window. Saves a full GUObjectArray walk per tick
--- during the multi-minute period a battle is active.
local function GetVisibleResultWidget()
    if _cachedResultWidget and IsValidRef(_cachedResultWidget) then
        local visOk, vis = pcall(TryCall, _cachedResultWidget, "IsVisible")
        if visOk and vis then
            return _cachedResultWidget
        end
    end
    _cachedResultWidget = nil

    if os.clock() < _resultMissUntil then return nil end

    local ok, results = pcall(FindAllOf, "WBP_GRP_BS_Result_03_DP_C")
    if ok and results then
        for _, r in ipairs(results) do
            local pok, path = pcall(function() return r:GetFullName() end)
            if pok and path and path:find("Transient", 1, true) then
                local visOk, vis = pcall(TryCall, r, "IsVisible")
                if visOk and vis then
                    _cachedResultWidget = r
                    return r
                end
            end
        end
    end
    _resultMissUntil = os.clock() + 0.5
    return nil
end

--- Poll for result screen (WBP_GRP_BS_Result_03_DP_C becomes visible).
--- Announces player level, rank up, rewards, win streak.
function Battle.PollResult(Speak, SpeakQueued)
    if _resultAnnounced then return end
    if not _maxPlayerHP then return end

    local resultWidget = GetVisibleResultWidget()
    if not resultWidget then return end

    local resultPath
    do
        local pok, path = pcall(function() return resultWidget:GetFullName() end)
        resultPath = pok and path and path:match("(WBP_GRP_BS_Result_03_DP_C_%d+)") or nil
    end

    -- Result widget is visible — scan TextBlocks for data.
    -- Rewards populate AFTER the result panel appears, so keep retrying
    -- until we find at least one real reward item before announcing.
    local tbok, textBlocks = pcall(FindAllOf, "TextBlock")
    if not tbok or not textBlocks then return end

    local parts = {}

    -- Rank up (only if WBP_GRP_BS_PlayerRankUP_C is visible — hidden = placeholder text)
    local rankUpVisible = false
    local rokup, rankUps = pcall(FindAllOf, "WBP_GRP_BS_PlayerRankUP_C")
    if rokup and rankUps then
        for _, ru in ipairs(rankUps) do
            local rpok, rpath = pcall(function() return ru:GetFullName() end)
            if rpok and rpath and rpath:find("Transient", 1, true) then
                local rvisOk, rvis = pcall(TryCall, ru, "IsVisible")
                if rvisOk and rvis then
                    rankUpVisible = true
                    break
                end
            end
        end
    end
    if rankUpVisible then
        local rankUp = ReadTextBlock(textBlocks, "PlayerRankUP", "Text_RewardInfo")
        if rankUp then table.insert(parts, rankUp) end
    end

    -- Player level (scoped strictly to result panel instance path, not PlayerRankUP)
    local level = ReadTextBlock(textBlocks, resultPath, "Text_RankNum")
    if level then table.insert(parts, "Player Level " .. level) end

    -- Rewards (from Notification_gift items — filter placeholders)
    local rewards = {}
    for _, tb in ipairs(textBlocks) do
        local tok, tbPath = pcall(function() return tb:GetFullName() end)
        if tok and tbPath and tbPath:find("Notification_gift", 1, true)
           and tbPath:find("Transient", 1, true) then
            local tbName = GetWidgetName(tb)
            if tbName == "Txt_ItemName" then
                local ok2, text = pcall(function() return tb:GetText():ToString() end)
                if ok2 and text and text:match("%S")
                   and not text:find("\227\130\162\227\130\164\227\131\134\227\131\160", 1, true) then
                    -- Find sibling TXT_Num for amount
                    local parentPath = tbPath:match("(.+)%.Txt_ItemName$")
                    if parentPath then
                        local num = ReadTextBlock(textBlocks, parentPath, "TXT_Num")
                        if num and not num:match("^9+$") then
                            text = num .. " " .. text
                        end
                    end
                    table.insert(rewards, text)
                end
            end
        end
    end

    -- Don't announce yet if rewards haven't populated (still all placeholder).
    -- Keep retrying until we find at least one real reward.
    if #rewards == 0 then return end

    for _, r in ipairs(rewards) do
        table.insert(parts, r)
    end

    -- Win streak (unsuffixed = yours, _P2 = opponent's)
    local winStreak = ReadTextBlock(textBlocks, "WBP_PlayerInfo", "Txt_WinningStreak_Value")
    if winStreak and not winStreak:match("^9+$") then
        table.insert(parts, "Win Streak " .. winStreak)
    end

    -- Now we have real data — announce and mark done
    _resultAnnounced = true
    if #parts > 0 then
        Speak(table.concat(parts, ", "), true)
        print("[AE] Result: " .. table.concat(parts, ", "))
    end
end

-- === INIT / RESET ===

function Battle.Init()
    -- No custom property registration needed — HPGaugeValue etc. are native C++ properties
end

function Battle.SetResetCallback(callback)
    _resultResetCallback = callback
end

function Battle.Reset()
    _introAnnounced = false
    _resultAnnounced = false
    _inBattle = false
    _lastPlayerHP = nil
    _maxPlayerHP = nil
    _lastHPThreshold = nil
    _lastKIBars = nil
    _lastSparkingBars = nil
    _lastSkillPoints = nil
    _lastPawnPath = nil
    _lastEnemyHP = nil
    _maxEnemyHP = nil
    _lastEnemyHPThreshold = nil
    _lastEnemyKIBars = nil
    _pawnDetectionLogged = false
    -- Note: do NOT reset _playerSide here — persists for rematches.
    -- It's cleared by ResetPlayerSide() when entering character select.
    -- and needs to persist through the map transition into battle
    _timerWidget = nil
    _timerDigitImgs = nil
    _timerDigitParents = nil
    _infiniteImg = nil
    _cachedResultWidget = nil
    _resultMissUntil = 0
    _lastTimerSeconds = nil
    _announcedTimerMarks = {}
    _timerStartAnnounced = false
end

return Battle
