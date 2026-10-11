-- Covers text on attached UMG screens that do not receive keyboard focus.
-- All entry points that touch UObjects run through game_thread.
local UI = require('visible_ui')
local Icons = require('icon_parser')
local GameThread = require('game_thread')
local Movie = require('movie_reader')
local AD = require('audio_description')
local Training = require('training_reader')
local Subtitles = require('subtitle_speech')
local Battle = require('battle')
local Reader = {}
local state, reviewPath = {}, nil
local chargeHold
local Speak, SpeakQueued, CanRead
local logPath, lastLogKey, logBytes, logFailed = nil, nil, 0, false
local movieError, descriptions, currentMovie
local TUTORIAL_REPEAT_SECONDS = 20
local logSession = 0

function Reader.SetLogging(enabled)
    logPath, lastLogKey, logBytes, logFailed = nil, nil, 0, false
    if enabled then
        logSession = logSession + 1
        logPath = 'AE_debug/screen-coverage-' .. os.date('%Y%m%d-%H%M%S')
            .. '-' .. logSession .. '.log'
        print('[AE] Screen diagnostic logging enabled: ' .. logPath)
    end
end

local function MovieNotice(snapshot)
    for _, entry in ipairs(snapshot.entries) do
        if entry.image and entry.image:find('.SSCriMediaPlayer_', 1, true) then
            if descriptions then return descriptions:Notice(currentMovie) end
            return 'Video screen. Audio description is not installed for this video yet.'
        end
    end
end

local function Clean(text)
    text = Icons.Parse(text or '')
    -- Formatting tags carry no words. IconParser resolves input glyphs first.
    return text:gsub('</>', ''):gsub('<[^>]+>', ''):gsub('%s+', ' ')
        :gsub(' +([,.;:])', '%1'):match('^%s*(.-)%s*$')
end

local function Numeric(text)
    return text:match('^[%d%s%p]+$') ~= nil
end

local function ExistingReader(entry)
    local ancestry = entry.ancestry or ''
    return ancestry:find('/WBP_Dialog_000_C', 1, true)
        or ancestry:find('/WBP_Dialog_002_C', 1, true)
        or ancestry:find('/WBP_GRP_DB_HelpWindow_C', 1, true)
end

function Reader.Reset(keepMovie)
    state, reviewPath, lastLogKey = {}, nil, nil
    movieError = nil
    if not keepMovie then
        chargeHold = nil
        Movie.Reset()
        currentMovie = nil
        if descriptions then descriptions:Reset() end
    end
end

local function ChargeContext(context)
    -- Only the actual player's native Charge key and guide pointer qualify.
    -- Unknown native state must leave the visible information readable.
    if type(context) ~= 'table' or type(context.held) ~= 'boolean'
        or type(context.pawn) ~= 'string' or type(context.guide) ~= 'string' then return end
    if not context.held then chargeHold = nil; return end
    local holdTime = context.holdTime
    local restarted = chargeHold and type(holdTime) == 'number'
        and type(chargeHold.holdTime) == 'number' and holdTime + 0.001 < chargeHold.holdTime
    local newHold = not chargeHold or chargeHold.pawn ~= context.pawn or restarted
    if newHold then chargeHold = {pawn = context.pawn, seen = {}} end
    chargeHold.guide, chargeHold.holdTime = context.guide, holdTime
    return chargeHold, newHold
end

function Reader.Update(snapshot, now)
    local nextState, spoken, unique, nodes = {}, {}, {}, {}
    for _, node in ipairs(snapshot.nodes) do nodes[node.path] = node end
    local charge, newHold = ChargeContext(snapshot.kiCharge)
    local function InChargeGuide(entry)
        if not charge then return false end
        local current, visited = entry, {}
        while current and not visited[current.path] do
            if current.path == charge.guide then return true end
            visited[current.path] = true
            current = nodes[current.parent]
        end
        return false
    end
    local function Focused(entry)
        local current, visited = entry, {}
        while current and not visited[current.path] do
            visited[current.path] = true
            if current.focused then return true end
            current = nodes[current.parent]
        end
        return false
    end
    for _, entry in ipairs(Training.Entries(snapshot)) do
        if entry.text then
            local text = Clean(entry.text)
            local guideText = InChargeGuide(entry)
            local previous = not (guideText and newHold) and state[entry.path]
            local value
            if previous and previous.text == text then value = previous
            else value = {text = text, since = now, announced = false} end
            nextState[entry.path] = value
            if not Subtitles.ShouldAnnounce(entry) or ExistingReader(entry)
                or Focused(entry) or Numeric(text) or text == ''
                or (guideText and charge.seen[text]) then
                value.announced = true
            elseif (not value.announced and now - value.since >= 0.15)
                or (entry.tutorial and value.lastAnnounced
                    and now - value.lastAnnounced >= TUTORIAL_REPEAT_SECONDS) then
                value.announced = true
                value.lastAnnounced = now
                if guideText then charge.seen[text] = true end
                if not unique[text] then
                    unique[text], spoken[#spoken + 1] = true, text
                end
            end
        end
    end
    state = nextState
    return spoken
end

local function Record(snapshot)
    if not logPath or logFailed or logBytes >= 10 * 1024 * 1024 then return end
    local key = {}
    for _, root in ipairs(snapshot.roots) do
        key[#key + 1] = root.path
    end
    for _, node in ipairs(snapshot.nodes) do
        if node.focused then
            key[#key + 1] = 'FOCUS ' .. node.path
        end
    end
    for _, entry in ipairs(snapshot.entries) do
        if entry.text and not Numeric(entry.text) then key[#key + 1] = entry.path .. '=' .. entry.text end
    end
    local charge = snapshot.kiCharge
    if charge then
        key[#key + 1] = 'KI CHARGE ' .. tostring(charge.held) .. ' ' .. charge.pawn .. ' ' .. charge.guide
    end
    local signature = table.concat(key, '\n')
    if signature == lastLogKey then return end
    lastLogKey = signature
    local lines = {'\n=== ' .. os.date('%Y-%m-%d %H:%M:%S') .. ' ==='}
    if charge then
        lines[#lines + 1] = 'KI CHARGE held=' .. tostring(charge.held)
            .. ' holdTime=' .. tostring(charge.holdTime) .. ' side=' .. tostring(charge.side)
            .. ' pawn=' .. charge.pawn .. ' guide=' .. charge.guide
    end
    for _, root in ipairs(snapshot.roots) do lines[#lines + 1] = 'ROOT ' .. root.path end
    for _, node in ipairs(snapshot.nodes) do
        if node.focused then lines[#lines + 1] = 'FOCUS ' .. node.path end
    end
    for _, entry in ipairs(snapshot.entries) do
        lines[#lines + 1] = (entry.text and 'TEXT ' or 'IMAGE ') .. entry.path .. '\n  '
            .. (entry.text or entry.image) .. '\n  owners=' .. entry.ancestry
    end
    for _, warning in ipairs(snapshot.warnings) do lines[#lines + 1] = 'WARNING ' .. warning end
    local content = table.concat(lines, '\n') .. '\n'
    local file = io.open(logPath, 'a')
    if not file then
        logFailed = true
        print('[AE] Cannot write screen coverage log: ' .. logPath)
        return
    end
    file:write(content); file:close()
    logBytes = logBytes + #content
end

local function CaptureMovie(snapshot)
    local ok, result = pcall(Movie.Capture, snapshot)
    if not ok then
        if movieError ~= tostring(result) then
            movieError = tostring(result)
            print('[AE] Movie clock unavailable: ' .. movieError)
        end
        currentMovie = nil
    else movieError, currentMovie = nil, result end
    if descriptions then
        local audioOk, audioError = pcall(descriptions.Update, descriptions, currentMovie, os.clock())
        if not audioOk then
            descriptions:Reset()
            print('[AE] Audio description update failed: ' .. tostring(audioError))
        end
    end
end

function Reader.Poll()
    local snapshot = UI.Capture()
    if type(Battle.ReadKiChargeGuide) == 'function' then
        snapshot.kiCharge = Battle.ReadKiChargeGuide()
    end
    CaptureMovie(snapshot)
    Record(snapshot)
    local text = Reader.Update(snapshot, os.clock())
    if #text > 0 then
        local announcement = table.concat(text, '. ')
        SpeakQueued(announcement)
        print('[AE] Screen text: ' .. announcement)
    end
end

local function Review(direction)
    local snapshot = UI.Capture()
    CaptureMovie(snapshot)
    Record(snapshot)
    local rows = {}
    local movieNotice = MovieNotice(snapshot)
    if movieNotice then rows[#rows + 1] = {path = 'current-movie', text = movieNotice} end
    for _, entry in ipairs(Training.Entries(snapshot)) do
        local text = entry.text and Clean(entry.text)
        if text and text ~= '' then rows[#rows + 1] = {path = entry.path, text = text} end
    end
    if #rows == 0 then
        print('[AE] Screen review: no text; roots=' .. tostring(#snapshot.roots))
        Speak('No readable text on the current screen', true)
        return
    end
    if direction == 0 then
        local all = {}
        for _, row in ipairs(rows) do all[#all + 1] = row.text end
        Speak(table.concat(all, '. '), true)
        print('[AE] Screen review: ' .. table.concat(all, '. '))
        reviewPath = rows[1].path
    else
        local index = direction > 0 and 0 or #rows + 1
        for i, row in ipairs(rows) do if row.path == reviewPath then index = i; break end end
        index = math.max(1, math.min(#rows, index + direction))
        reviewPath = rows[index].path
        Speak(rows[index].text .. ', ' .. index .. ' of ' .. #rows, true)
        print('[AE] Screen review item: ' .. rows[index].text)
    end
    -- Mark what the player just requested as read so passive polling does not
    -- immediately repeat it. Restart tutorial reminders from this manual read.
    -- New values remain eligible on the next poll.
    local now = os.clock()
    Reader.Update(snapshot, now)
    for _, value in pairs(state) do
        value.announced, value.lastAnnounced = true, now
    end
end

function Reader.Init(speak, queued, canRead)
    Speak, SpeakQueued, CanRead = speak, queued, canRead
    if descriptions then descriptions:Reset() end
    local manifestOk, manifest = pcall(require, 'description_manifest')
    local backendOk, backend = pcall(require, 'audio_bridge')
    descriptions = AD.New(backendOk and backend or nil, manifestOk and manifest or {})
    if backendOk and manifestOk then
        print('[AE] Movie audio description player loaded')
    elseif manifestOk then
        print('[AE] Movie audio description player unavailable: ' .. tostring(backend))
    end
    Reader.SetLogging(false)
    print('[AE] Screen hotkey API: ' .. type(RegisterKeyBind) .. ', Key=' .. type(Key)
        .. ', F6=' .. tostring(Key and Key.F6))
    if type(RegisterKeyBind) == 'function' and Key then
        local function Bind(key, direction)
            if not key then return end
            RegisterKeyBind(key, function()
                print('[AE] Screen review key received: ' .. tostring(key))
                GameThread.After(0, 'Read screen', function()
                    if CanRead and not CanRead() then
                        print('[AE] Screen review deferred: reader disabled or world changing')
                        Speak('Screen reader is unavailable while the game is loading or the reader is disabled', true)
                        return
                    end
                    Review(direction)
                end)
            end)
            if type(IsKeyBindRegistered) == 'function' then
                local ok, registered = pcall(IsKeyBindRegistered, key)
                print('[AE] Screen hotkey registration: ' .. tostring(key) .. '=' .. tostring(ok and registered))
            end
        end
        Bind(Key.F6, 0); Bind(Key.F7, -1); Bind(Key.F8, 1)
    end
    print('[AE] Screen coverage reader: F6 read screen, F7 previous text, F8 next text')
    print('[AE] Visible tutorial instructions repeat every 20 seconds')
end

return Reader
