-- Pure cue scheduling. Receives only the current visible movie's scalar data.
local AD = {}
local Player = {}; Player.__index = Player
local function Finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

function AD.New(backend, manifest, report)
    report = report or print
    local films = {}
    for name, film in pairs(type(manifest) == 'table' and manifest or {}) do
        local valid = type(name) == 'string' and type(film) == 'table'
            and Finite(film.fps) and film.fps > 0 and Finite(film.totalFrames) and film.totalFrames > 0
            and type(film.cues) == 'table'
        local previousEnd = 0
        if valid then
            for _, cue in ipairs(film.cues) do
                valid = type(cue) == 'table' and Finite(cue.at) and Finite(cue.untilTime)
                    and cue.at >= previousEnd and cue.untilTime > cue.at and type(cue.file) == 'string'
                    and (cue.duration == nil or (Finite(cue.duration) and cue.duration > 0))
                if not valid then break end
                previousEnd = cue.untilTime
            end
        end
        if valid then films[name:lower()] = film
        else report('[AE] Audio description manifest rejected: ' .. tostring(name)) end
    end
    return setmetatable({backend = type(backend) == 'table' and backend or nil, manifest = films,
        report = report, nextCue = 1}, Player)
end

function Player:Call(method, ...)
    local fn = self.backend and self.backend[method]
    if type(fn) ~= 'function' then return false end
    local ok, value, message = pcall(fn, ...)
    if not ok or value == false then
        local errorText = tostring(not ok and value or message or method .. ' failed')
        if self.lastError ~= errorText then
            self.lastError = errorText
            self.report('[AE] Audio description: ' .. errorText)
        end
        return false
    end
    return value
end

function Player:StopCue()
    if self.active then self:Call('stop') end
    self.active, self.audioPaused = nil, false
end

function Player:Reset()
    self:StopCue()
    self.identity, self.lastTime, self.lastAdvance = nil, nil, nil
    self.nextCue = 1
end

function Player:Film(movie)
    if not movie or type(movie.url) ~= 'string' then return nil end
    local name = movie.url:gsub('\\', '/'):match('([^/]+)$')
    local film = name and self.manifest[name:lower()]
    if not film or movie.fps ~= film.fps or movie.totalFrames ~= film.totalFrames
        or type(film.cues) ~= 'table' or #film.cues == 0 then return nil end
    return film, name:lower()
end

function Player:Notice(movie)
    local film = self:Film(movie)
    if not film then return 'Video screen. Audio description is not installed for this video yet.' end
    if not self.backend then
        return 'Video screen. Audio description is unavailable because its audio player could not start.'
    end
    if self.lastError then return 'Video screen. Audio description encountered a playback error.' end
    return (film.title or 'Video screen') .. '. Audio description is enabled.'
end

function Player:Update(movie, now)
    local time = movie and movie.seconds
    if not movie or type(time) ~= 'number' or time ~= time or time < 0
        or time == math.huge or (movie.playing ~= true and movie.paused ~= true) then
        self:Reset(); return
    end
    local film, name = self:Film(movie)
    if not film or not self.backend then self:Reset(); return end
    local identity = tostring(movie.player) .. '|' .. name
    if identity ~= self.identity or (self.lastTime and time < self.lastTime - 0.25) then
        self:Reset()
        self.identity, self.lastAdvance = identity, now
    end
    if self.lastTime ~= time then self.lastAdvance = now end
    self.lastTime = time
    if self.active and (time >= self.active.untilTime or self:Call('mode') == 'stopped') then
        self:StopCue()
    end
    local paused = movie.paused == true or now - self.lastAdvance >= 0.5
    if self.active and paused ~= self.audioPaused then
        if not self:Call(paused and 'pause' or 'resume') then self:StopCue(); return end
        self.audioPaused = paused
    end
    if paused then return end
    -- Never build an audio backlog or describe a scene the player has passed.
    while self.nextCue <= #film.cues do
        local cue = film.cues[self.nextCue]
        if type(cue.at) ~= 'number' or type(cue.untilTime) ~= 'number'
            or cue.untilTime <= cue.at or type(cue.file) ~= 'string' then
            self.nextCue = self.nextCue + 1
        elseif time < cue.at then return
        else
            self.nextCue = self.nextCue + 1
            local fits = cue.duration and time + cue.duration + 0.02 <= cue.untilTime
                or (not cue.duration and time - cue.at <= 0.5)
            if time < cue.untilTime and fits then
                self:StopCue()
                if self:Call('play', cue.file) then
                    self.active, self.audioPaused = cue, false
                    self.lastError = nil
                    self.report('[AE] Audio description cue: ' .. cue.file .. ' at ' .. tostring(time))
                end
                return
            else
                self.report('[AE] Audio description skipped after its scene window: ' .. cue.file
                    .. ' at ' .. tostring(time))
            end
        end
    end
end

return AD
