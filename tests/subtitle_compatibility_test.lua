-- Independent boundary checks for the F9 automatic-subtitle preference.
-- Real subtitle_speech, screen_reader, visible_ui, training_reader and
-- episode_battle run over a UMG mock shaped like captured screens. Only the
-- game_thread queue, key binding API, speech and game objects are stubbed.
-- Captured dialogue leaves (research\lag-menu-20261005\incoming\
-- screen-coverage-*.log): Text_CharaName and RichText_MainTalk occur only under
--   /WBP_OBJ_Common_TextWindow_C                                    (battle/training lines)
--   /WBP_MainMenu_Base_TextSub_C/WBP_OBJ_Common_TexWin_Black_C      (main-menu banter)
--   /WBP_GRP_BS_Top_00_TextSub_C/WBP_OBJ_Common_TexWin_Black_C      (character-select quotes)
-- The preference file is written only to the system temporary folder.
-- Run from the repository root with Lua 5.4 or LuaJIT.
package.path = './SparkingZeroAccess/?.lua;' .. package.path

local realClock, realPrint, realOpen = os.clock, print, io.open
local now, logs, spoken, jobs, keys = 1, {}, {}, {}, {}
os.clock = function() return now end
print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    logs[#logs + 1] = table.concat(parts, ' ')
end

-- File access is counted so polling paths can be shown to stay free of IO.
local opened = {}
io.open = function(path, mode, ...)
    opened[#opened + 1] = {path = tostring(path), mode = mode or 'r'}
    return realOpen(path, mode, ...)
end

-- Boundary stubs: one game-thread queue, the key binding API and speech.
package.loaded.game_thread = {
    After = function(_, _, callback) jobs[#jobs + 1] = callback end,
    Every = function() return function() end end,
    PauseForMapLoad = function() end, ResumeAfterMapLoad = function() end,
}
local function Flush()
    local pending = jobs
    jobs = {}
    for _, callback in ipairs(pending) do callback() end
end
Key = {F6 = 117, F7 = 118, F8 = 119, F9 = 120}
RegisterKeyBind = function(key, callback) keys[key] = callback end
local function Press(key) keys[key](); Flush() end
local function Speak(text, interrupt)
    spoken[#spoken + 1] = {text = text, interrupt = interrupt ~= false, queued = false}
end
local function SpeakQueued(text)
    spoken[#spoken + 1] = {text = text, interrupt = false, queued = true}
end

-- === UMG mock: user widgets own WidgetTrees; panels slot children ===
local GAME = '/Engine/Transient.GameEngine_2147482611:BP_SSGameInstance_C_2147482468'
local super = {Widget = 'Object', UserWidget = 'Widget', PanelWidget = 'Widget', TextBlock = 'Widget',
    RichTextBlock = 'Widget', CanvasPanel = 'PanelWidget', WidgetTree = 'Object',
    GameInstance = 'Object', BP_SSGameInstance_C = 'GameInstance'}
local function IsA(class, target)
    while class do
        if class == target then return true end
        class = super[class]
    end
    return false
end
local world, serial, focused = {}, 2147400000, nil
local methods = {}
function methods:IsValid() return self._valid end
function methods:type() return 'UObject' end
function methods:GetFullName() return self._class .. ' ' .. self._path end
function methods:GetOuter() return self._outer end
function methods:IsVisible() return self._visible end
function methods:IsInViewport() return self._viewport == true end
function methods:HasKeyboardFocus() return focused == self end
function methods:IsA(class) return IsA(self._class, class._className) end
function methods:GetText()
    assert(IsA(self._class, 'TextBlock') or IsA(self._class, 'RichTextBlock'), 'GetText on ' .. self._class)
    local text = self._text
    return {ToString = function() return text end}
end
function methods:GetChildrenCount()
    assert(IsA(self._class, 'PanelWidget'), 'GetChildrenCount on ' .. self._class)
    return #self._children
end
function methods:GetChildAt(i) return self._children[i + 1] end
local mt = {__index = function(self, key)
    if methods[key] then return methods[key] end
    return rawget(self, '_props')[key]
end}
local function Spawn(class, path, outer)
    local object = setmetatable({_class = class, _path = path, _outer = outer, _valid = true,
        _visible = true, _props = {}, _children = {}}, mt)
    world[#world + 1] = object
    return object
end
local gameInstance = Spawn('BP_SSGameInstance_C', GAME, nil)
local function OwnTree(widget)
    serial = serial + 1
    local tree = Spawn('WidgetTree', widget._path .. '.WidgetTree_' .. serial, widget)
    widget._tree, widget._props.WidgetTree = tree, tree
    return widget
end
local function Child(class, name, parent)
    if parent._tree then
        local widget = Spawn(class, parent._tree._path .. '.' .. name, parent._tree)
        parent._tree._props.RootWidget = widget
        return widget
    end
    local widget = Spawn(class, parent._outer._path .. '.' .. name, parent._outer)
    parent._children[#parent._children + 1] = widget
    return widget
end
local function Declare(class) if not super[class] then super[class] = 'UserWidget' end end
-- A displayed screen: top-level user widget in the viewport with a canvas.
local function Root(class, name)
    Declare(class)
    serial = serial + 1
    local widget = OwnTree(Spawn(class, GAME .. '.' .. (name or (class .. '_' .. serial)), gameInstance))
    widget._viewport = true
    return widget, Child('CanvasPanel', 'Canvas', widget)
end
-- A nested user widget slotted into a panel; returns its own canvas.
local function User(class, name, panel)
    Declare(class)
    local widget = OwnTree(Child(class, name, panel))
    return widget, Child('CanvasPanel', 'Canvas', widget)
end
local function Text(name, panel, text, rich)
    local widget = Child(rich and 'RichTextBlock' or 'TextBlock', name, panel)
    widget._text = text
    return widget
end
local function Clear()
    for _, object in ipairs(world) do
        if object ~= gameInstance then object._valid, object._viewport = false, false end
    end
end

local library = {IsValid = function() return true end, type = function() return 'UObject' end}
function library:GetAllWidgetsOfClass(context, out, class, topOnly)
    assert(context == gameInstance)
    for _, object in ipairs(world) do
        if object._valid and IsA(object._class, class._className) and (not topOnly or object._viewport) then
            out[#out + 1] = object
        end
    end
end
local userWidgetClass = {_className = 'UserWidget', IsValid = function() return true end,
    type = function() return 'UObject' end}
LoopInGameThreadWithDelay = function() end
StaticFindObject = function(path)
    if path == '/Script/UMG.Default__WidgetBlueprintLibrary' then return library end
    if path == '/Script/UMG.UserWidget' then return userWidgetClass end
end
FindFirstOf = function(name) if name == 'GameInstance' then return gameInstance end end
FindAllOf = function(name)
    local found = {}
    for _, object in ipairs(world) do
        if object._valid and IsA(object._class, name) then found[#found + 1] = object end
    end
    return #found > 0 and found or nil
end
FindObjects = function() return {} end

-- === Screens shaped like the captures ===
local Screens = {}
function Screens.MainMenu()
    local _, menu = Root('WBP_MainMenu_ModeMenu_C')
    local _, button = User('WBP_OBJ_MainMenu_BTN_Sub1_C', 'WBP_OBJ_MainMenu_BTN_Sub1_01', menu)
    Text('caption', button, 'Battle & Training')
    local _, sub = Root('WBP_MainMenu_Base_TextSub_C')
    local _, bubble = User('WBP_OBJ_Common_TexWin_Black_C', 'WBP_OBJ_Common_TexWin_Black', sub)
    return {
        name = Text('Text_CharaName', bubble, 'Goku'),
        line = Text('RichText_MainTalk', bubble, "Hey! Why're we playin' tag?!", true),
        description = Text('Text_Description', sub, 'Explore the world of Dragon Ball.'),
    }
end
function Screens.Training()
    local _, hud = Root('WBP_GRP_HUD_CSG_HUD_Main_C')
    local _, category = User('WBP_OBJ_HUD_CSG_CategolyText_C', 'WBP_OBJ_HUD_CSG_CategolyText', hud)
    Text('Text_Title', category, 'Guard')
    Text('Text_Comment', category, 'Hold Guard to block.')
    local _, command = User('WBP_OBJ_HUD_CSG_Command_BTN_C', 'WBP_OBJ_HUD_CSG_Command_BTN_0', hud)
    Text('RichText_PadButton_0', command, 'LB', true)
    local _, window = Root('WBP_OBJ_Common_TextWindow_C')
    return {
        name = Text('Text_CharaName', window, 'Vegeta'),
        line = Text('RichText_MainTalk', window, "Don't start getting cocky now!", true),
    }
end
function Screens.CharacterSelect()
    local _, sub = Root('WBP_GRP_BS_Top_00_TextSub_C')
    local _, bubble = User('WBP_OBJ_Common_TexWin_Black_C', 'WBP_OBJ_Common_TexWin_Black', sub)
    return {
        name = Text('Text_CharaName', bubble, 'Chi-Chi'),
        line = Text('RichText_MainTalk', bubble, 'You ready?!', true),
    }
end
function Screens.EventText(name, line)
    local event, canvas = Root('WBP_GRP_Common_EventText_C', 'WBP_GRP_Common_EventText_C_2147400777')
    local _, button = User('WBP_OBJ_Common_NextButton_C', 'WBP_OBJ_Common_NextButton', canvas)
    return {
        event = event,
        name = Text('Text_CharaName', canvas, name or ''),
        line = Text('RichText_MainTalk', canvas, line, true),
        prompt = Text('RichText_PadButton', button, 'Continue', true),
    }
end

-- === Real modules ===
local H = require('helpers')
local Subtitles = require('subtitle_speech')
local Reader = require('screen_reader')
local UI = require('visible_ui')
local EpisodeBattle = require('episode_battle')
local temp = os.getenv('TEMP') or os.getenv('TMP') or '.'
local settings = temp .. '/sza-subtitle-compat-' .. tostring(os.time()) .. '-' .. tostring(math.random(1e6)) .. '.ini'
os.remove(settings)
Subtitles.Init(Speak, settings)
Reader.Init(Speak, SpeakQueued, function() return true end)
EpisodeBattle.Init(Speak, SpeakQueued)
assert(keys[Key.F9] and keys[Key.F6] and keys[Key.F7] and keys[Key.F8], 'F6-F9 were not all registered')

local function Poll(t)
    now = t
    H.BeginReadCycle()
    local mark = #spoken
    Reader.Poll()
    local heard = {}
    for i = mark + 1, #spoken do heard[#heard + 1] = spoken[i].text end
    return table.concat(heard, ' | ')
end
-- Both polls are returned so speech in the first one (for example a replay
-- right after unmuting) cannot be missed.
local function Settle(t) return Poll(t) .. ' | ' .. Poll(t + 0.3) end
local function Has(text, fragment) return text:find(fragment, 1, true) ~= nil end
local function SetEnabled(value)
    if Subtitles.IsEnabled() ~= value then Press(Key.F9) end
    assert(Subtitles.IsEnabled() == value, 'F9 did not reach the requested state')
end
local function Fresh()
    Clear(); Reader.Reset(); focused = nil
end
local function Captured()
    H.BeginReadCycle()
    return UI.Capture()
end
local function EntryFor(snapshot, widget)
    for _, entry in ipairs(snapshot.entries) do
        if entry.path == widget:GetFullName() then return entry end
    end
    error('captured snapshot omitted ' .. widget:GetFullName())
end

local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then realPrint('PASS: ' .. name)
    else failures = failures + 1; realPrint('FAIL: ' .. name .. ': ' .. tostring(err)) end
end
local function info(text) realPrint('INFO: ' .. text) end

test('captured dialogue leaves classify by exact owner class, not by words or class prefixes', function()
    Fresh()
    local menu, training = Screens.MainMenu(), Screens.Training()
    local select, event = Screens.CharacterSelect(), Screens.EventText('Goku', 'Kamehameha!')
    local snapshot = Captured()
    for label, widget in pairs({menuName = menu.name, menuLine = menu.line, trainingName = training.name,
        trainingLine = training.line, eventName = event.name, eventLine = event.line}) do
        local entry = EntryFor(snapshot, widget)
        assert(Subtitles.IsSubtitle(entry), label .. ' was not classified as dialogue: ' .. tostring(entry.ancestry))
    end
    assert(not Subtitles.IsSubtitle(EntryFor(snapshot, menu.description)), 'a main-menu description was muted')
    assert(not Subtitles.IsSubtitle(EntryFor(snapshot, event.prompt)), 'the continue prompt was classified as dialogue')
    -- Same inner widget class as main-menu banter; captured 21 names and 20 lines.
    local quote = Subtitles.IsSubtitle(EntryFor(snapshot, select.line))
    assert(quote == Subtitles.IsSubtitle(EntryFor(snapshot, menu.line)),
        'the same TexWin_Black dialogue widget is classified differently on two screens')
    info('character-select quote bubble (/WBP_GRP_BS_Top_00_TextSub_C/WBP_OBJ_Common_TexWin_Black_C) muted by F9: '
        .. tostring(quote))
    Fresh()
    -- Near-miss containers and fields built by the real capture.
    local cases = {
        {'WBP_OBJ_Common_TextWindow_C2', 'RichText_MainTalk'},
        {'WBP_OBJ_Common_TextWindowEx_C', 'Text_CharaName'},
        {'XWBP_OBJ_Common_TextWindow_C', 'RichText_MainTalk'},
        {'WBP_MainMenu_Base_TextSub_Copy_C', 'Text_CharaName'},
        {'WBP_GRP_Common_EventText_Choice_C', 'RichText_MainTalk'},
    }
    local near = {}
    for _, case in ipairs(cases) do
        local _, canvas = Root(case[1])
        near[#near + 1] = {case[1], Text(case[2], canvas, 'Unrelated words')}
    end
    local _, window = Root('WBP_OBJ_Common_TextWindow_C')
    local fields = {}
    for _, leaf in ipairs({'Text_CharaName2', 'Text_CharaName_Shadow', 'RichText_MainTalk_01',
        'RichText_MainTalkBG', 'xRichText_MainTalk', 'caption'}) do
        fields[#fields + 1] = {leaf, Text(leaf, window, 'Field near miss')}
    end
    -- An instance merely named like a container is not that class.
    local _, notice = Root('WBP_GRP_Notice_C')
    local _, impostor = User('WBP_GRP_NoticeText_C', 'WBP_OBJ_Common_TextWindow_C_7', notice)
    local named = Text('RichText_MainTalk', impostor, 'Named, not owned')
    local snapshot2 = Captured()
    for _, case in ipairs(near) do
        assert(not Subtitles.IsSubtitle(EntryFor(snapshot2, case[2])), 'class prefix/suffix matched: ' .. case[1])
    end
    for _, case in ipairs(fields) do
        assert(not Subtitles.IsSubtitle(EntryFor(snapshot2, case[2])), 'field near miss matched: ' .. case[1])
    end
    assert(not Subtitles.IsSubtitle(EntryFor(snapshot2, named)), 'an instance name was treated as owner class')
end)

test('muting dialogue preserves menus, descriptions, training instructions and their 20-second reminder', function()
    Fresh(); SetEnabled(false)
    local menu, training = Screens.MainMenu(), Screens.Training()
    local heard = Settle(1)
    for _, text in ipairs({'Battle & Training', 'Explore the world of Dragon Ball.', 'Hold Guard to block',
        'Displayed inputs: LB'}) do
        assert(Has(heard, text), 'muting removed visible information: ' .. text .. ' in [' .. heard .. ']')
    end
    for _, widget in ipairs({menu.name, menu.line, training.name, training.line}) do
        assert(not Has(heard, widget._text), 'muted dialogue was spoken: ' .. widget._text)
    end
    local reminder = Poll(21.4)
    assert(Has(reminder, 'Hold Guard to block') and not Has(reminder, training.line._text),
        'the training reminder stopped or carried dialogue while muted: [' .. reminder .. ']')
end)

test('identical words outside dialogue stay audible while the dialogue copy is muted', function()
    Fresh(); SetEnabled(false)
    local menu = Screens.MainMenu()
    local _, notice = Root('WBP_GRP_Notice_C')
    Text('Text_Message', notice, menu.line._text)
    local _, hint = Root('WBP_GRP_Hint_C')
    Text('RichText_MainTalk', hint, 'Same field name, unrelated owner', true)
    local _, plate = Root('WBP_GRP_BS_CharaNameSet_DP_C')
    Text('Text_CharaName', plate, 'Goku')
    local heard = Settle(1)
    assert(Has(heard, menu.line._text), 'an unrelated widget with the dialogue words was muted')
    assert(Has(heard, 'Same field name, unrelated owner'), 'a dialogue field name outside dialogue was muted')
    assert(Has(heard, 'Goku'), 'a character name outside dialogue was muted')
    SetEnabled(true)
    Fresh()
    local again = Screens.MainMenu()
    local enabled = Settle(5)
    assert(Has(enabled, again.line._text) and Has(enabled, 'Goku'), 'dialogue stayed silent with F9 on')
end)

test('manual F6/F7/F8 review reads muted dialogue without changing the preference or causing replay', function()
    Fresh(); SetEnabled(false)
    local menu, training = Screens.MainMenu(), Screens.Training()
    Settle(1)
    now = 2
    Press(Key.F6)
    local review = spoken[#spoken]
    assert(review.interrupt and Has(review.text, menu.line._text) and Has(review.text, training.line._text)
        and Has(review.text, 'Battle & Training') and Has(review.text, 'Hold Guard to block'),
        'F6 omitted visible text: ' .. review.text)
    local rows = {}
    for _ = 1, 12 do
        Press(Key.F8)
        rows[#rows + 1] = spoken[#spoken].text
    end
    local stepped = table.concat(rows, ' | ')
    assert(Has(stepped, 'Vegeta') and Has(stepped, training.line._text), 'F8 skipped dialogue rows: ' .. stepped)
    Press(Key.F7)
    assert(spoken[#spoken].text:find(' of ', 1, true), 'F7 did not step back through review rows')
    assert(not Subtitles.IsEnabled(), 'manual review changed the F9 preference')
    local after = Poll(2.5)
    assert(not Has(after, menu.line._text) and not Has(after, training.line._text),
        'reviewed dialogue was replayed by passive speech while muted')
end)

test('map resets keep the muted state; unmuting never replays old lines; new lines resume', function()
    Fresh(); SetEnabled(false)
    local training = Screens.Training()
    assert(not Has(Settle(1), training.line._text))
    training.line._text = 'Heh! Die!'              -- a line changing while muted stays muted
    assert(not Has(Settle(2), 'Heh! Die!'))
    Reader.Reset()                                 -- map load or result-screen reset
    assert(not Subtitles.IsEnabled(), 'reset lost the preference')
    assert(not Has(Settle(3), 'Heh! Die!'), 'a reset replayed muted dialogue')
    SetEnabled(true)
    assert(spoken[#spoken].interrupt and Has(spoken[#spoken].text:lower(), 'on'), 'unmute feedback missing')
    assert(not Has(Settle(4), 'Heh! Die!'), 'unmuting replayed dialogue from the muted period')
    training.line._text = 'Galick Guuun!'
    assert(Has(Settle(5), 'Galick Guuun!'), 'new dialogue did not resume after unmuting')
end)

test('EventText narration follows F9 while the continue prompt remains', function()
    Fresh(); SetEnabled(false)
    local event = Screens.EventText(nil, 'Long ago, the Saiyans arrived.')
    local dummy = Spawn('WBP_GRP_AI_CharacterSelect_C', GAME .. '.WBP_GRP_AI_CharacterSelect_C_2147400999', gameInstance)
    pcall(EpisodeBattle.OnCharaSelectFocused, dummy)  -- enters the Episode Battle context
    local mark = #spoken
    H.BeginReadCycle(); EpisodeBattle.PollCutsceneText()
    local heard = {}
    for i = mark + 1, #spoken do heard[#heard + 1] = spoken[i].text end
    heard = table.concat(heard, ' | ')
    assert(not Has(heard, 'Long ago'), 'muted narration was spoken: ' .. heard)
    assert(Has(heard, 'Continue'), 'the continue prompt was dropped with narration: [' .. heard .. ']')
    local passive = Settle(1)
    assert(not Has(passive, 'Long ago') and Has(passive, 'Continue'),
        'passive EventText reading disagrees with narration muting: [' .. passive .. ']')
    SetEnabled(true)
    event.line._text = 'The battle began.'
    mark = #spoken
    H.BeginReadCycle(); EpisodeBattle.PollCutsceneText()
    assert(Has(spoken[mark + 1] and spoken[mark + 1].text or '', 'The battle began.'),
        'new narration did not resume after unmuting')
end)

test('polling and classification perform no file access; only F9 writes the preference', function()
    Fresh(); SetEnabled(false)
    Screens.MainMenu(); Screens.Training(); Screens.EventText('Goku', 'Kamehameha!')
    local before = #opened
    for i = 1, 60 do Poll(10 + i * 0.25) end
    assert(#opened == before, 'passive polling opened ' .. (#opened - before) .. ' file(s)')
    Press(Key.F9)
    local writes = 0
    for i = before + 1, #opened do
        assert(opened[i].path == settings, 'the preference was written outside the test folder: ' .. opened[i].path)
        if opened[i].mode:find('w', 1, true) then writes = writes + 1 end
    end
    assert(writes == 1, 'F9 performed ' .. writes .. ' preference writes')
    for _, entry in ipairs(opened) do
        assert(not entry.path:find('SparkingZeroAccess-subtitles.ini', 1, true) or entry.path == settings,
            'a test touched the default preference file')
    end
end)

test('a preference saved with Windows line endings is honoured', function()
    local file = assert(realOpen(settings, 'wb'))
    file:write('AutomaticSubtitles=false\r\n'); file:close()
    Subtitles.Init(Speak, settings)
    assert(not Subtitles.IsEnabled(), 'CRLF preference was not read')
    file = assert(realOpen(settings, 'wb'))
    file:write('\239\187\191AutomaticSubtitles=false\n'); file:close()
    Subtitles.Init(Speak, settings)
    info('UTF-8 BOM before AutomaticSubtitles=false leaves subtitles ' .. (Subtitles.IsEnabled() and 'ON' or 'OFF')
        .. ' (only affects hand-edited files)')
end)

os.remove(settings)
os.clock, print, io.open = realClock, realPrint, realOpen
assert(failures == 0, tostring(failures) .. ' subtitle compatibility failures')
