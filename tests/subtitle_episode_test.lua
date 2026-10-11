package.path = './SparkingZeroAccess/?.lua;' .. package.path
local config = os.tmpname()
os.remove(config)
Key = {}
local Subtitles = require('subtitle_speech')
Subtitles.Init(function() end, config)

local function widget(name, text, path)
    return {GetFullName = function() return path end, _name = name,
        GetText = function() return {ToString = function() return text.value end} end}
end
local line = {value = 'Goku sets out to find his friends.'}
local parent = '/Engine/Transient.WBP_GRP_Common_EventText_C_101.WidgetTree.Window.'
local rich = {
    widget('RichText_MainTalk', line, 'RichTextBlock ' .. parent .. 'RichText_MainTalk'),
    widget('RichText_PadButton', {value = 'Press confirm to continue'},
        'RichTextBlock ' .. parent .. 'WBP_OBJ_Common_NextButton.RichText_PadButton'),
}
package.loaded.helpers = {
    FindAllOf = function(class) return class == 'RichTextBlock' and rich or {} end,
    GetWidgetName = function(value) return value._name end,
}
local Episode = require('episode_battle')
local spoken = {}
Episode.Init(function(text) spoken[#spoken + 1] = text end,
    function(text) spoken[#spoken + 1] = text end)
-- Select the actual Episode Battle branch without simulating unrelated menus.
local activated = false
for index = 1, 30 do
    local name = debug.getupvalue(Episode.PollCutsceneText, index)
    if not name then break end
    if name == '_announcedEntry' then
        debug.setupvalue(Episode.PollCutsceneText, index, true)
        activated = true
        break
    end
end
assert(activated, 'test did not reach the episode reader context')
Episode.PollCutsceneText()
assert(spoken[1] == line.value and spoken[2] == 'Press confirm to continue')
print('PASS: enabled episode reading includes the displayed narration and continue prompt')

Subtitles.Toggle()
spoken = {}
line.value = 'An unvoiced story line displayed while muted.'
Episode.PollCutsceneText()
assert(#spoken == 1 and spoken[1] == 'Press confirm to continue',
    'muted episode subtitles spoke or removed the continue prompt')
Episode.PollCutsceneText()
assert(#spoken == 1, 'unchanged episode dialogue repeated its prompt')
print('PASS: F9 suppresses the separate episode subtitle path and preserves its continue prompt')

Subtitles.Toggle()
spoken = {}
Episode.PollCutsceneText()
assert(#spoken == 0, 'unmuting replayed old episode dialogue')
line.value = 'New episode text after unmuting.'
Episode.PollCutsceneText()
assert(spoken[1] == line.value and spoken[2] == 'Press confirm to continue')
print('PASS: episode dialogue resumes on new text without replaying muted lines')
os.remove(config)
