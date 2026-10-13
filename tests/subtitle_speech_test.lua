package.path = './SparkingZeroAccess/?.lua;' .. package.path
local callbacks, jobs, announcements = {}, {}, {}
Key = {F6 = 117, F7 = 118, F8 = 119, F9 = 120}
RegisterKeyBind = function(key, callback) callbacks[key] = callback end
package.loaded.game_thread = {After = function(_, _, callback) jobs[#jobs + 1] = callback end}
local available, Subtitles = pcall(require, 'subtitle_speech')
assert(available, 'The F9 subtitle speech preference has not been implemented')
local function flush()
    local pending = jobs
    jobs = {}
    for _, callback in ipairs(pending) do callback() end
end
local function speak(text, interrupt)
    announcements[#announcements + 1] = {text = text, interrupt = interrupt}
end
local config = os.tmpname()
os.remove(config)
local function init() Subtitles.Init(speak, config) end
local function contents()
    local file = io.open(config, 'r')
    if not file then return nil end
    local text = file:read('*a'); file:close()
    return text
end
local function write(text)
    local file = assert(io.open(config, 'w'))
    file:write(text); file:close()
end
local function entry(name, text, ancestry)
    return {path = 'screen' .. ancestry:gsub('/', '.') .. '.' .. name, text = text, ancestry = ancestry,
        owner = ancestry, ownerClass = ancestry:match('([^/]+)$'), root = 'screen',
        rootClass = ancestry:match('^/([^/]+)')}
end
local function snapshot(entries)
    return {entries = entries, nodes = {}, roots = {{path = 'screen'}}, warnings = {}}
end

init()
assert(Subtitles.IsEnabled(), 'a new install unexpectedly disables subtitle access')
assert(contents() == nil, 'loading a missing preference wrote a file')
assert(callbacks[Key.F9], 'F9 was not registered')
callbacks[Key.F9]()
assert(Subtitles.IsEnabled(), 'F9 mutated reader state before game-thread dispatch')
flush()
assert(not Subtitles.IsEnabled(), 'F9 did not disable automatic subtitle speech')
assert(announcements[#announcements].text:lower():find('off', 1, true))
assert(announcements[#announcements].interrupt == true, 'toggle feedback did not clear current subtitle speech')
assert(contents():find('AutomaticSubtitles=false', 1, true), 'disabled state was not saved')
print('PASS: F9 toggles on the game thread with spoken feedback and saves the preference')
init()
assert(not Subtitles.IsEnabled(), 'restart lost the disabled setting')
callbacks[Key.F9](); flush()
assert(Subtitles.IsEnabled())
assert(announcements[#announcements].text:lower():find('on', 1, true))
init()
assert(Subtitles.IsEnabled(), 'restart lost the enabled setting')
print('PASS: both subtitle settings survive restart')

local line = entry('RichText_MainTalk', 'Are you ready to fight?', '/WBP_OBJ_Common_TextWindow_C')
local name = entry('Text_CharaName', 'Vegeta', '/WBP_OBJ_Common_TextWindow_C')
local banter = entry('RichText_MainTalk', 'Hey! Why are we playing tag?',
    '/WBP_MainMenu_Base_TextSub_C/WBP_OBJ_Common_TexWin_Black_C')
local instruction = entry('Text_Comment', 'Hold Guard to block.', '/WBP_GRP_HUD_CSG_HUD_Main_C')
local menu = entry('caption', 'Battle & Training', '/WBP_MainMenu_ModeMenu_C')
local prompt = entry('RichText_PadButton', 'Press confirm to continue.',
    '/WBP_GRP_Common_EventText_C/WBP_OBJ_Common_NextButton_C')
local option = entry('Title', 'Subtitle Background (Event)', '/WBP_OBJ_Option_List_012_TextAlpha_C')
Subtitles.Toggle()
assert(not Subtitles.ShouldAnnounce(line) and not Subtitles.ShouldAnnounce(name))
assert(not Subtitles.ShouldAnnounce(banter))
assert(Subtitles.ShouldAnnounce(instruction) and Subtitles.ShouldAnnounce(menu))
assert(Subtitles.ShouldAnnounce(prompt) and Subtitles.ShouldAnnounce(option))
print('PASS: muting dialogue preserves menu labels, tutorial instructions, continue prompts and setting labels')
assert(not Subtitles.IsSubtitle(entry('RichText_MainTalk', 'Same field, unrelated widget', '/WBP_Other_C')))
assert(not Subtitles.IsSubtitle(entry('Text_CharaName', 'Vegeta', '/WBP_CharacterSelect_C')))
assert(not Subtitles.IsSubtitle(entry('RichText_MainTalk', 'Unrelated class suffix', '/WBP_OBJ_Common_TextWindow_C_Extra')))
assert(not Subtitles.IsSubtitle(entry('caption', 'Are you ready to fight?', '/WBP_OBJ_Common_TextWindow_C')))
print('PASS: subtitle classification uses exact ownership and field roles instead of matching spoken words')

local Reader = require('screen_reader')
Reader.Reset()
local mixed = snapshot({line, name, banter, instruction, menu, prompt, option})
Reader.Update(mixed, 1)
local result = table.concat(Reader.Update(mixed, 1.3), '. ')
assert(not result:find(line.text, 1, true) and not result:find(name.text, 1, true)
    and not result:find(banter.text, 1, true), 'muted subtitles reached passive screen speech')
assert(result:find(instruction.text, 1, true) and result:find(menu.text, 1, true)
    and result:find(prompt.text, 1, true) and result:find(option.text, 1, true))
Subtitles.Toggle()
assert(#Reader.Update(mixed, 2) == 0, 'unmuting replayed subtitles from the muted period')
line.text = 'Now let us train.'
Reader.Update(mixed, 3)
assert(table.concat(Reader.Update(mixed, 3.3), '. '):find(line.text, 1, true),
    'new subtitle text did not resume after unmuting')
print('PASS: passive screen speech obeys F9, avoids stale catch-up, and resumes on new dialogue')

Subtitles.Toggle()
local UI, Movie = require('visible_ui'), require('movie_reader')
UI.Capture = function() return mixed end
Movie.Capture = function() return nil end
Reader.Init(speak, function() end, function() return true end)
callbacks[Key.F6](); flush()
assert(announcements[#announcements].text:find(line.text, 1, true), 'F6 cannot review muted subtitles')
callbacks[Key.F8](); flush()
assert(announcements[#announcements].text:find('Vegeta', 1, true), 'manual next-text review muted subtitle names')
callbacks[Key.F7](); flush()
assert(announcements[#announcements].text:find(line.text, 1, true))
Reader.Reset()
assert(not Subtitles.IsEnabled(), 'map or screen reset lost the subtitle preference')
print('PASS: F6/F7/F8 retain explicit subtitle review and reader reset preserves the choice')

local reminder = entry('training#instructions', 'Guard: hold Left Shoulder.', '/WBP_GRP_HUD_CSG_HUD_Main_C')
reminder.tutorial = true
Reader.Update(snapshot({reminder, line}), 10)
assert(table.concat(Reader.Update(snapshot({reminder, line}), 10.3), '. ') == reminder.text)
assert(table.concat(Reader.Update(snapshot({reminder, line}), 30.4), '. ') == reminder.text,
    'muting subtitles suppressed the 20-second tutorial reminder')
print('PASS: automatic tutorial reminders continue every 20 seconds while subtitles are muted')

write('AutomaticSubtitles=not-a-boolean\n')
init()
assert(Subtitles.IsEnabled(), 'an invalid preference silently removed subtitle access')
print('PASS: a malformed preference keeps subtitle access enabled')
os.remove(config)
local missingFolder = config .. '/missing/settings.ini'
Subtitles.Init(speak, missingFolder)
callbacks[Key.F9](); flush()
assert(not Subtitles.IsEnabled(), 'a save failure prevented the current-session toggle')
local feedback = announcements[#announcements].text:lower()
assert(feedback:find('off', 1, true) and feedback:find('not', 1, true)
    and feedback:find('sav', 1, true), 'a save failure was not announced')
print('PASS: persistence failure leaves the session choice working and is spoken to the user')
os.remove(config)
