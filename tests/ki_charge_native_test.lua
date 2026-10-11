-- Real Battle and screen_reader over controlled native getter boundaries.
-- This verifies player/guide ownership and audible filtering, not the game
-- engine's implementation of its reflected methods.
package.path = './SparkingZeroAccess/?.lua;' .. package.path
local H = require('helpers')
local Battle = require('battle')
local UI = require('visible_ui')
local Reader = require('screen_reader')
local now, spoken, keys, queuedJobs = 1, {}, {}, {}
local realPrint, warnings = print, 0
print = function(...)
    local message = tostring(select(1, ...))
    if message:find('Ki-charge guide unavailable', 1, true) then warnings = warnings + 1 end
    realPrint(...)
end
os.clock = function() return now end
package.loaded.audio_bridge = {play = function() return true end,
    stop = function() return true end, mode = function() return 'stopped' end}
package.loaded.game_thread.After = function(_, _, callback) queuedJobs[#queuedJobs + 1] = callback end
RegisterKeyBind = function(key, callback) keys[key] = callback end
Key = {F6 = 117, F7 = 118, F8 = 119}

local function object(name)
    return {GetFullName = function() return name end, IsValid = function(self) return not self.dead end}
end
local p1 = object('BPCHR_Player1_C /Engine/Transient.Player1')
local p2 = object('BPCHR_Player2_C /Engine/Transient.Player2')
for _, pawn in ipairs({p1, p2}) do
    pawn.HPGaugeValue, pawn.SPGaugeValue, pawn.SparkingGaugeValue = 100000, 30000, 0
    pawn.BlastStockCount, pawn.ComboNum = 2, 0
    pawn.held, pawn.holdTime = true, 0.3
    function pawn:IsBattleKeyPressed(key)
        assert(key == 11, 'a battle key other than native Charge was queried')
        if self.unreadable then error('input unavailable') end
        return self.held
    end
    function pawn:GetBattleKeyHoldTime(key)
        assert(key == 11, 'the hold timer queried a different action')
        return self.holdTime
    end
end
p1.TargetPawn, p2.TargetPawn = p2, p1
local camera = object('BP_DirectorMainCamera_C /Engine/Transient.Camera')
local controller = object('BP_BattlePlayerController_C /Engine/Transient.Controller')
controller.Pawn = p1
function controller:GetViewTarget() return camera end
local g1 = object('NativeSkillGuide /Engine/Transient.Hud.P1Guide')
local g2 = object('NativeSkillGuide /Engine/Transient.Hud.P2Guide')
local hud = object('NativeBattleHud /Engine/Transient.Hud')
hud.P1SkillGuideWidget, hud.P2SkillGuideWidget = g1, g2
local root = object('NativeBattleHudRoot /Engine/Transient.HudRoot')
function root:GetSkillGuideSetOfPlayer(index)
    if index == 0 then return g1 elseif index == 1 then return g2 end
end
local hudQueries, controllerQueries = 0, 0
FindAllOf = function(class)
    if class == 'BP_BattlePlayerController_C' then return {controller} end
    return {}
end
FindObjects = function(_, class)
    if class == 'BP_BattlePlayerController_C' then
        controllerQueries = controllerQueries + 1
        return {controller}
    end
    return {}
end
FindFirstOf = function(class)
    if class == 'BP_BattlePlayerController_C' then return controller end
    if class == 'SSMainGameHUDWidget' then hudQueries = hudQueries + 1; return hud end
    if class == 'SSMainGameHUDWidgetRoot' then hudQueries = hudQueries + 1; return root end
end

local suffix, chosen = 'a', g1
UI.Capture = function()
    local path = chosen:GetFullName()
    local row = {path = path .. '.row' .. suffix, parent = path}
    local label = {path = row.path .. '.name', parent = row.path, text = 'Holy Wrath'}
    local button = {path = row.path .. '.button', parent = row.path, text = 'X'}
    return {roots = {{path = 'hud'}}, nodes = {{path = path}, row, label, button},
        entries = {label, button}, warnings = {}}
end
Reader.Init(function(text) spoken[#spoken + 1] = text end,
    function(text) spoken[#spoken + 1] = text end, function() return true end)
local function poll(at)
    now = at
    H.BeginReadCycle()
    Reader.Poll()
end
local function enter(side)
    Battle.Reset(); Battle.ResetPlayerSide(); Battle.SetPlayerSide(side)
    H.InvalidateCachedFirstOf(); H.BeginReadCycle()
    Reader.Reset(); spoken = {}
    Battle.PollHUD(function() end, function() end)
end

enter('1P')
local establishedControllerQueries = controllerQueries
poll(1); p1.holdTime = 0.6; poll(1.3)
assert(spoken[1] == 'Holy Wrath. X')
suffix = 'b'; p1.holdTime = 0.9; poll(1.6)
p1.holdTime = 1.2; poll(1.9)
assert(#spoken == 1, 'the native charge/guide association did not stop a rebuilt guide from repeating')
assert(hudQueries == 1, 'a steady guide caused repeated HUD object lookups')
assert(controllerQueries == establishedControllerQueries,
    'the charging correction added global player-controller searches to the existing battle HUD poll')
print('PASS: native player-one charge state filters only its guide without repeated HUD lookups')

p1.held, p1.holdTime = false, 0; poll(2)
p1.held, p1.holdTime = true, 0.1; poll(2.1)
p1.holdTime = 0.4; poll(2.4)
assert(#spoken == 2 and spoken[2] == 'Holy Wrath. X', 'the native release did not enable the next hold')
keys[Key.F6]()
for _, callback in ipairs(queuedJobs) do callback() end
queuedJobs = {}
assert(spoken[3] == 'Holy Wrath. X', 'F6 could not repeat an already announced charging guide')
print('PASS: native release resets the guide and F6 still reads it immediately during a hold')

chosen, suffix = g2, 'a'
p1.held, p1.holdTime = false, 0
p2.held, p2.holdTime = true, 0.2
enter('2P')
poll(3); p2.holdTime = 0.5; poll(3.3)
suffix = 'b'; p2.holdTime = 0.8; poll(3.6)
p2.holdTime = 1.1; poll(3.9)
assert(#spoken == 1 and spoken[1] == 'Holy Wrath. X', 'player-two guide used the opponent charge state')
print('PASS: the actual player-two pawn and its own native guide are paired')

hud.dead = true
Reader.Reset(); spoken = {}; suffix = 'c'
poll(4); p2.holdTime = 1.4; poll(4.3)
local rootQueries = hudQueries
suffix = 'd'; p2.holdTime = 1.7; poll(4.6)
p2.holdTime = 2; poll(4.9)
assert(#spoken == 1, 'the alternative native HUD root lost guide suppression')
assert(hudQueries == rootQueries, 'a valid alternative HUD caused repeated global searches for an absent primary HUD')
print('PASS: the alternative native HUD root supplies the same player-owned guide')

p2.unreadable = true
suffix = 'e'; poll(5); poll(5.3)
assert(spoken[2] == 'Holy Wrath. X', 'unreadable native input silently hid guide text')
assert(warnings == 1, 'a failed native input binding did not report one diagnostic for the battle')
poll(5.4); poll(5.5)
assert(warnings == 1, 'a failing native input binding flooded diagnostics')
print('PASS: a failed native input getter leaves the visible guide readable')

local changed = object('BPCHR_Player2Changed_C /Engine/Transient.Player2Changed')
changed.HPGaugeValue, changed.SPGaugeValue, changed.SparkingGaugeValue = 100000, 30000, 0
changed.BlastStockCount, changed.ComboNum = 2, 0
changed.IsBattleKeyPressed, changed.GetBattleKeyHoldTime = p2.IsBattleKeyPressed, p2.GetBattleKeyHoldTime
changed.held, changed.holdTime, changed.TargetPawn = true, 0.2, p1
p1.TargetPawn = changed
H.BeginReadCycle()
Battle.PollHUD(function() end, function() end)
poll(5.6); changed.holdTime = 0.5; poll(5.9)
assert(spoken[3] == 'Holy Wrath. X', 'the reused native reference did not follow a player character change')
suffix = 'f'; changed.holdTime = 0.8; poll(6.2)
changed.holdTime = 1.1; poll(6.5)
assert(#spoken == 3, 'the refreshed player reference lost charging-guide deduplication')
print('PASS: the existing HUD poll refreshes the player reference after a character change')

Battle.Reset(); Reader.Reset(); spoken = {}
local before = hudQueries
poll(7); poll(7.3)
assert(spoken[1] == 'Holy Wrath. X')
assert(hudQueries == before, 'ordinary menu polling searched for battle HUD objects')
print('PASS: leaving battle stops native charge queries and preserves ordinary screen reading')
