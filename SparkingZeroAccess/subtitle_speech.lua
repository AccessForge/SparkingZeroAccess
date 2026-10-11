-- Optional automatic dialogue speech. Manual screen review remains unfiltered.
-- The preference is read once at startup and written only when F9 is pressed.
local GameThread = require('game_thread')
local Subtitles = {}
local enabled = true
local settingsPath = 'SparkingZeroAccess-subtitles.ini'
local Speak

-- These native dialogue containers and leaf names were confirmed in visible
-- captures. Never classify by the spoken words or a partial class-name match.
local containers = {
    WBP_OBJ_Common_TextWindow_C = true,
    WBP_OBJ_Common_TexWin_Black_C = true,
    WBP_GRP_Common_EventText_C = true,
    WBP_MainMenu_Base_TextSub_C = true,
}
local fields = {RichText_MainTalk = true, Text_CharaName = true,
    ContextText = true, CharaNameText = true}

function Subtitles.IsEnabled()
    return enabled
end

function Subtitles.IsSubtitle(entry)
    if not entry or not entry.text or not fields[(entry.path or ''):match('([^%.]+)$')] then
        return false
    end
    if containers[entry.ownerClass] or containers[entry.rootClass] then return true end
    for class in (entry.ancestry or ''):gmatch('[^/]+') do
        if containers[class] then return true end
    end
    return false
end

function Subtitles.ShouldAnnounce(entry)
    return enabled or not Subtitles.IsSubtitle(entry)
end

local function Load()
    enabled = true
    local file, err, code = io.open(settingsPath, 'r')
    if not file then
        if code ~= 2 then return 'Could not read the subtitle preference: ' .. tostring(err) end
        return
    end
    local ok, text, readError = pcall(file.read, file, 4097)
    file:close()
    if not ok or not text then return 'Could not read the subtitle preference: ' .. tostring(readError or text) end
    local value = #text <= 4096 and text:match('^%s*AutomaticSubtitles%s*=%s*(%a+)%s*$')
    if value == 'true' then enabled = true
    elseif value == 'false' then enabled = false
    else return 'Invalid subtitle preference; automatic subtitle reading remains on.' end
end

local function Save()
    local file, err = io.open(settingsPath, 'w')
    if not file then return tostring(err) end
    local ok, written, writeError = pcall(file.write, file,
        'AutomaticSubtitles=' .. tostring(enabled) .. '\n')
    local closedOk, closed, closeError = pcall(file.close, file)
    if not ok or not written then return tostring(writeError or written) end
    if not closedOk or not closed then return tostring(closeError or closed) end
end

function Subtitles.Toggle()
    enabled = not enabled
    local err = Save()
    print('[AE] Automatic subtitle reading ' .. (enabled and 'on' or 'off'))
    if err then print('[AE] Subtitle preference was not saved: ' .. err) end
    return enabled, err
end

function Subtitles.Init(speak, path)
    Speak = speak
    settingsPath = path or 'SparkingZeroAccess-subtitles.ini'
    local err = Load()
    if err then
        print('[AE] ' .. err)
        Speak('Could not load the subtitle preference. Automatic subtitle reading on.', true)
    elseif not enabled then
        Speak('Automatic subtitle reading off. Press F9 to turn it on.', true)
    end
    if type(RegisterKeyBind) == 'function' and Key and Key.F9 then
        local registered, registrationError = pcall(RegisterKeyBind, Key.F9, function()
            GameThread.After(0, 'Subtitle speech toggle', function()
                local active, saveError = Subtitles.Toggle()
                local text = 'Automatic subtitle reading ' .. (active and 'on' or 'off')
                if saveError then text = text .. '. The preference could not be saved for the next launch.' end
                Speak(text, true)
            end)
        end)
        if registered then
            print('[AE] F9 toggles automatic subtitle speech; currently ' .. (enabled and 'on' or 'off'))
        else
            print('[AE] F9 subtitle hotkey could not be registered: ' .. tostring(registrationError))
            Speak('The subtitle toggle key could not be registered.', true)
        end
    else
        print('[AE] F9 subtitle hotkey is unavailable in this keybinding API')
    end
end

return Subtitles
