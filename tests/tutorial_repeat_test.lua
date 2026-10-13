package.path = './SparkingZeroAccess/?.lua;' .. package.path
local Training = require('training_reader')
local Reader = require('screen_reader')
local MAIN = 'WBP_GRP_TTR_HUD_TutorialAll_C'
local TIP = 'WBP_OBJ_TRR_HUD_TipText_C'
local CHECK = 'WBP_OBJ_TTR_Icon_Check_C'
local function snapshot(entries) return {entries = entries, nodes = {}, roots = {}, warnings = {}} end
local function tip(root, index, caption, input, checked)
    local rootPath = '/Engine/Transient.' .. root
    local ownerPath = rootPath .. '.WidgetTree_1.WBP_TTR_Tip_' .. index
    local owner = TIP .. ' ' .. ownerPath
    local result = {}
    for _, field in ipairs({{'RichText_PadButton_0', input}, {'caption', caption}}) do
        result[#result + 1] = {path = 'TextBlock ' .. ownerPath .. '.WidgetTree_2.' .. field[1],
            root = MAIN .. ' ' .. rootPath, rootClass = MAIN, owner = owner, ownerClass = TIP,
            ancestry = '/' .. MAIN .. '/' .. TIP, text = field[2]}
    end
    if checked then
        result[#result + 1] = {path = 'Image ' .. ownerPath .. '.WidgetTree_2.Check.WidgetTree_3.IMG_Check_0',
            root = MAIN .. ' ' .. rootPath, rootClass = MAIN,
            owner = CHECK .. ' ' .. ownerPath .. '.WidgetTree_2.Check', ownerClass = CHECK,
            ancestry = '/' .. MAIN .. '/' .. TIP .. '/' .. CHECK,
            image = 'Texture2D /Game/SS/UI/DramaticBattle/OBJ/Texture/T_UI_DB_Common_CheckMark.T_UI_DB_Common_CheckMark'}
    end
    return result
end
local function append(target, source) for _, item in ipairs(source) do target[#target + 1] = item end end
local entries = {}
append(entries, tip('tutorial', 0, 'Move', '<icon id="Pad_14" table="XSX"/>', true))
append(entries, tip('tutorial', 1, 'Jump (On ground)', '<icon id="Pad_06" table="XSX"/>', false))
append(entries, tip('tutorial', 2, 'Fly (While midair)', '<icon id="Pad_06" table="XSX"/>', true))
local s = snapshot(entries)
local composed = Training.Entries(s)
local text = {}
for _, row in ipairs(composed) do if row.text then text[#text + 1] = row.text end end
assert(#text == 1, 'intro tutorial action/input pairs must form one instruction item')
assert(text[1] == 'Move: <icon id="Pad_14" table="XSX"/>. Check mark. Jump (On ground): <icon id="Pad_06" table="XSX"/>. Fly (While midair): <icon id="Pad_06" table="XSX"/>. Check mark.')
assert(#s.entries == 8 and s.entries[1].text:find('<icon', 1, true), 'native snapshot was mutated')
print('PASS: introductory tutorial pairs every action with its own input and visible check mark')

local foreign = tip('other-tutorial', 1, 'Guard', 'RB', true)
local onlyJump = tip('tutorial', 1, 'Jump', 'LB', false)
append(onlyJump, {foreign[3]})
local rows = Training.Entries(snapshot(onlyJump))
assert(rows[1].text == 'Jump: LB.', 'foreign check mark was borrowed')
local wrongImage = tip('tutorial', 1, 'Jump', 'LB', true)
wrongImage[3].image = 'Texture2D /Game/Other.Decoration'
assert(Training.Entries(snapshot(wrongImage))[1].text == 'Jump: LB.')
print('PASS: only the visible check-mark asset in the same tutorial row supplies check status')

Reader.Reset()
assert(#Reader.Update(s, 1) == 0)
local first = table.concat(Reader.Update(s, 1.3), '. ')
assert(first:find('Jump (On ground): LB.', 1, true))
assert(first:find('Move: Left Stick Up. Check mark.', 1, true))
assert(#Reader.Update(s, 21.2) == 0, 'tutorial repeated before twenty seconds')
assert(table.concat(Reader.Update(s, 21.31), '. ') == first, 'unchanged tutorial did not repeat')
assert(#Reader.Update(s, 21.5) == 0, 'repeat queued every poll')
assert(table.concat(Reader.Update(s, 41.32), '. ') == first)
print('PASS: unchanged tutorial instructions repeat every twenty seconds without polling duplicates')

local changed = snapshot(tip('tutorial', 1, 'Guard', '<icon id="Pad_10" table="XSX"/>', false))
assert(#Reader.Update(changed, 42) == 0)
assert(table.concat(Reader.Update(changed, 42.3), '. ') == 'Guard: RB.')
assert(#Reader.Update(changed, 61.6) == 0, 'new step inherited the old repeat deadline')
assert(table.concat(Reader.Update(changed, 62.31), '. ') == 'Guard: RB.')
Reader.Update(snapshot({}), 63)
assert(#Reader.Update(snapshot({}), 1000) == 0)
assert(#Reader.Update(changed, 1001) == 0)
assert(table.concat(Reader.Update(changed, 1001.3), '. ') == 'Guard: RB.')
print('PASS: step changes restart the timer and leaving the tutorial discards its instructions')

Reader.Reset()
local ordinary = snapshot({{path = 'dialogue', text = 'Are you ready?', root = 'dialogue',
    rootClass = 'WBP_OBJ_Common_TextWindow_C', ancestry = '/WBP_OBJ_Common_TextWindow_C'}})
Reader.Update(ordinary, 1)
assert(#Reader.Update(ordinary, 1.3) == 1)
assert(#Reader.Update(ordinary, 25) == 0 and #Reader.Update(ordinary, 1000) == 0)
print('PASS: dialogue and ordinary screen text are not automatically repeated')

Reader.Reset()
local battleTraining = snapshot({{path = 'training.Text_Comment', text = 'Press to transform.',
    root = 'training', rootClass = 'WBP_GRP_HUD_CSG_HUD_Main_C',
    owner = 'training.category', ownerClass = 'WBP_OBJ_HUD_CSG_CategolyText_C'}})
Reader.Update(battleTraining, 1)
assert(table.concat(Reader.Update(battleTraining, 1.3)) == 'Press to transform.')
assert(table.concat(Reader.Update(battleTraining, 21.31)) == 'Press to transform.')
Reader.Reset()
assert(#Reader.Update(snapshot({}), 1000) == 0)
print('PASS: Battle Training lessons also repeat and map reset clears the reminder state')

Reader.Reset()
local unchecked = snapshot(tip('tutorial', 1, 'Jump (On ground)', 'LB', false))
local checked = snapshot(tip('tutorial', 1, 'Jump (On ground)', 'LB', true))
Reader.Update(unchecked, 1); Reader.Update(unchecked, 1.3)
assert(#Reader.Update(checked, 2) == 0)
assert(table.concat(Reader.Update(checked, 2.3)) == 'Jump (On ground): LB. Check mark.')
assert(#Reader.Update(checked, 21.5) == 0)
print('PASS: a newly visible check mark is announced even when the instruction text is unchanged')

local UI = require('visible_ui')
local binds, worker, dispatch, spoken = {}, nil, nil, {}
local clock, now = os.clock, 1
os.clock = function() return now end
Key = {F6 = 117, F7 = 118, F8 = 119}
RegisterKeyBind = function(key, callback) binds[key] = callback end
LoopAsync = function(_, callback) worker = callback end
ExecuteInGameThread = function(callback) dispatch = callback end
UI.Capture = function() return s end
Reader.Init(function(value) spoken[#spoken + 1] = value end, function() end, function() return true end)
Reader.Reset()
Reader.Update(s, 1); Reader.Update(s, 1.3)
now = 20
binds[Key.F6](); worker(); dispatch()
assert(spoken[1]:find('Jump (On ground): LB.', 1, true))
assert(#Reader.Update(s, 21.31) == 0, 'manual review was immediately repeated')
assert(#Reader.Update(s, 40.01) == 1)
os.clock = clock
print('PASS: F6 repeats immediately and postpones the next automatic tutorial reminder')
