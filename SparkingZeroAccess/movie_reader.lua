-- Read-only CRI movie context. Call only from the game-thread screen capture.
-- A player qualifies only when its material is present in the visible UMG tree.
local H = require('helpers')
local Movie = {}
local Call, Property = H.TryCall, H.TryGetProperty
local cachedPlayer, cachedImage, lastLog, nextSearch = nil, nil, nil, 0
local arrayWarnings = {}

local function Name(value) return Call(value, 'GetFullName') end
local function String(value)
    if type(value) == 'string' then return value end
    return Call(value, 'ToString')
end
local function Each(array, callback)
    if not array then return nil, 'array unavailable' end
    -- Indexed reads avoid ForEach's parameter wrappers. Never index outside the
    -- reported length: this UE4SS version expands a TArray on an out-of-range read.
    local count = Call(array, 'GetArrayNum')
    if type(count) == 'number' then
        for i = 1, math.min(count, 16) do
            local value = Property(array, i)
            callback(i - 1, Call(value, 'get') or value)
        end
        return count
    end
    if type(array) == 'table' and not array.ForEach then
        for i, value in ipairs(array) do callback(i - 1, value) end
        return #array
    else
        local seen = 0
        local ok, err = pcall(function()
            array:ForEach(function(i, value)
                seen = seen + 1
                callback(i - 1, Call(value, 'get') or value)
                return seen >= 16
            end)
        end)
        if ok then return seen end
        return nil, tostring(err)
    end
end

function Movie.Reset()
    cachedPlayer, cachedImage, lastLog, nextSearch = nil, nil, nil, 0
    arrayWarnings = {}
end

function Movie.Capture(snapshot)
    local surface
    for _, entry in ipairs(snapshot.entries) do
        if entry.image and entry.image:find('.SSCriMediaPlayer_', 1, true) then
            surface = entry
            break
        end
    end
    if not surface then Movie.Reset(); return nil end
    if cachedImage ~= surface.image or not H.IsValidRef(cachedPlayer) then
        cachedPlayer = nil
        if cachedImage ~= surface.image then nextSearch = 0 end
        cachedImage = surface.image
        if os.clock() < nextSearch then return nil end
        nextSearch = os.clock() + 1
        for _, player in ipairs(H.FindAllOf('SSCriMediaPlayer') or {}) do
            if H.IsValidRef(player) and Name(Property(player, 'DynamicManaMaterial')) == surface.image then
                cachedPlayer = player
                break
            end
        end
        if not cachedPlayer then
            print('[AE] Movie surface has no matched player: ' .. surface.image)
            return nil
        end
    end
    local result = {surface = surface.path, player = Name(cachedPlayer),
        slot = Property(cachedPlayer, 'ManaPlayerNo'), components = {}}
    local count, arrayError = Each(Property(cachedPlayer, 'ManaComponents'), function(index, component)
        if not H.IsValidRef(component) then return end
        local source = Call(component, 'GetSource')
        if not H.IsValidRef(source) then source = Property(Property(component, 'Movie'), 'MovieSource') end
        local row = {index = index, component = Name(component), source = Name(source),
            url = String(Call(source, 'GetUrl')) or String(Property(source, 'FilePath')),
            frame = Call(component, 'GetFrameNumber'), status = Call(component, 'GetStatus'),
            playing = Call(component, 'IsPlaying'), paused = Call(component, 'IsPaused'),
            subtitles = Property(source, 'NumSubtitleChannels')}
        Each(Property(source, 'VideoTracks'), function(trackIndex, track)
            if trackIndex ~= 0 then return end
            row.fps, row.totalFrames = Property(track, 'FrameRate'), Property(track, 'TotalFrames')
        end)
        if type(row.fps) == 'number' and row.fps > 0 and type(row.frame) == 'number' and row.frame >= 0 then
            row.seconds = row.frame / row.fps
        end
        result.components[#result.components + 1] = row
        if index == result.slot then
            for key, value in pairs(row) do result[key] = value end
        end
    end)
    result.componentCount = count
    if arrayError and not arrayWarnings[arrayError] then
        arrayWarnings[arrayError] = true
        print('[AE] Movie component read failed: ' .. arrayError)
    end
    local subtitlePlayer = Property(cachedPlayer, 'MovieSubtitlePlayer')
    result.subtitleUi = Name(Property(subtitlePlayer, 'TextAreaUi'))
    result.subtitleAsset = Name(Property(subtitlePlayer, 'MovieSubtitleDataAsset'))
    -- Change-only telemetry retains source identities and a coarse clock without
    -- retaining component/text wrappers or dumping future subtitle records.
    local key = table.concat({result.player or '?', result.url or '?',
        tostring(result.slot), tostring(count), tostring(result.paused), tostring(result.playing),
        tostring(math.floor((result.frame or -1) / 150))}, '|')
    if key ~= lastLog then
        lastLog = key
        print('[AE] Movie: ' .. key .. ' frame=' .. tostring(result.frame)
            .. ' source=' .. tostring(result.source) .. ' subtitleUi=' .. tostring(result.subtitleUi)
            .. ' subtitleAsset=' .. tostring(result.subtitleAsset))
        for _, row in ipairs(result.components) do
            print('[AE] Movie component: index=' .. tostring(row.index) .. ' frame=' .. tostring(row.frame)
                .. ' playing=' .. tostring(row.playing) .. ' paused=' .. tostring(row.paused)
                .. ' status=' .. tostring(row.status) .. ' subtitles=' .. tostring(row.subtitles)
                .. ' fps=' .. tostring(row.fps) .. ' totalFrames=' .. tostring(row.totalFrames)
                .. ' url=' .. tostring(row.url) .. ' source=' .. tostring(row.source))
        end
    end
    return result
end

return Movie
