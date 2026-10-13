package.path = './SparkingZeroAccess/?.lua;' .. package.path
local Training = require('training_reader')
local function row(root, ownerClass, name, text)
    return {path = root .. '.WidgetTree_1.' .. ownerClass .. '.WidgetTree_2.' .. name,
        root = root, rootClass = 'WBP_GRP_HUD_CSG_HUD_Main_C',
        owner = root .. '.WidgetTree_1.' .. ownerClass, ownerClass = ownerClass,
        ancestry = '/WBP_GRP_HUD_CSG_HUD_Main_C/' .. ownerClass,
        text = text}
end
local function snapshot(entries) return {entries = entries, nodes = {}, roots = {}, warnings = {}} end
local title = row('lesson', 'WBP_OBJ_HUD_CSG_CategolyText_C', 'Text_Title', 'Transform')
local instruction = row('lesson', 'WBP_OBJ_HUD_CSG_CategolyText_C', 'Text_Comment', 'Press to transform.')
local first = row('lesson', 'WBP_OBJ_HUD_CSG_Command_BTN_C', 'RichText_PadButton_1', '<icon id="Pad_22" table="XSX"/>')
local second = row('lesson', 'WBP_OBJ_HUD_CSG_Command_BTN_C', 'RichText_PadButton_2', '<icon id="Pad_04" table="XSX"/>')
second.path = second.path:gsub('WidgetTree_2', 'WidgetTree_3')
local tip = row('lesson', 'WBP_OBJ_HUD_CSG_Com_Tips_C', 'caption', 'Press to transform or return to original form')
local s = snapshot({first, second, tip, instruction, title})
local rows = Training.Entries(s)
assert(#rows == 1 and rows[1].text == 'Transform. Press to transform. Displayed inputs: <icon id="Pad_22" table="XSX"/>, <icon id="Pad_04" table="XSX"/>. Press to transform or return to original form')
assert(#s.entries == 5 and s.entries[1] == first, 'must not modify native snapshot used for diagnostics')
print('PASS: current lesson instructions and visible button prompts form one review item')

local explanation = snapshot({instruction})
rows = Training.Entries(explanation)
assert(#rows == 1 and rows[1].text == 'Press to transform.')
rows = Training.Entries(snapshot({title, instruction, first}))
assert(rows[1].text:find('Displayed inputs:', 1, true) and not rows[1].text:find('Pad_04', 1, true))
print('PASS: explanation-only screens do not invent inputs or reuse a previous step')

local foreign = row('other', 'WBP_OBJ_HUD_CSG_Command_BTN_C', 'RichText_PadButton_1', 'Y')
rows = Training.Entries(snapshot({title, instruction, first, foreign}))
assert(#rows == 2 and not rows[1].text:find('Y', 1, true) and rows[2].text == 'Displayed inputs: Y')
local unrelated = row('lesson', 'WBP_OBJ_Guide_Btn_Present_C', 'RTEXT_Help_0', 'A Next')
local unknown = row('lesson', 'WBP_NewInstruction_C', 'caption', 'New displayed instruction')
rows = Training.Entries(snapshot({unrelated, title, unknown, instruction}))
assert(rows[1] == unrelated and rows[3] == unknown, 'unrecognized visible text was removed or reordered')
print('PASS: separate roots and unrelated instructions keep their own speech')

local duplicate = row('lesson', 'WBP_OBJ_HUD_CSG_CategolyText_C', 'Text_Comment_Large', instruction.text)
rows = Training.Entries(snapshot({title, instruction, duplicate}))
assert(rows[1].text == 'Transform. Press to transform.')
rows = Training.Entries(snapshot({title, first, first}))
assert(rows[1].text == 'Transform. Displayed inputs: <icon id="Pad_22" table="XSX"/>')
local repeatInput = row('lesson', 'WBP_OBJ_HUD_CSG_Command_BTN_C', 'RichText_PadButton_2', first.text)
rows = Training.Entries(snapshot({title, first, repeatInput}))
assert(rows[1].text:find('XSX"/>, <icon', 1, true), 'two displayed presses of the same button must be retained')
print('PASS: duplicate text nodes are combined but repeated command buttons are preserved')

local Reader = require('screen_reader')
Reader.Reset()
Reader.Update(snapshot({title, instruction}), 1)
assert(#Reader.Update(snapshot({title, instruction}), 1.3) == 1)
assert(#Reader.Update(s, 2) == 0)
local spoken = Reader.Update(s, 2.3)
assert(#spoken == 1 and spoken[1]:find('Displayed inputs:', 1, true))
assert(#Reader.Update(s, 3) == 0)
Reader.Update(snapshot({}), 4)
assert(#Reader.Update(s, 5) == 0)
assert(#Reader.Update(s, 5.3) == 1)
print('PASS: a changed or reopened lesson is announced together after settling without repeats')

local UI = require('visible_ui')
local binds, worker, dispatch, reviewed = {}, nil, nil, nil
Key = {F6 = 117, F7 = 118, F8 = 119}
RegisterKeyBind = function(key, callback) binds[key] = callback end
LoopAsync = function(_, callback) worker = callback end
ExecuteInGameThread = function(callback) dispatch = callback end
UI.Capture = function() return s end
Reader.Init(function(text) reviewed = text end, function() end, function() return true end)
binds[Key.F6](); worker(); dispatch()
assert(reviewed:find('Transform. Press to transform.', 1, true))
assert(reviewed:find('D-Pad Up', 1, true) and reviewed:find('X', 1, true))
assert(reviewed:find('Press to transform or return to original form', 1, true))
assert(not reviewed:find('Right Stick', 1, true) and not reviewed:find('<icon', 1, true))
print('PASS: F6 reviews the current lesson with instructions and corrected controller names')
