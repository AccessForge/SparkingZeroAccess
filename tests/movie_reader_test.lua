package.path = './SparkingZeroAccess/?.lua;' .. package.path
local H = require('helpers')
local Movie = require('movie_reader')
local queries = 0
local function object(path, fields)
    local o = fields or {}
    function o:IsValid() return not self.dead end
    function o:GetFullName() return path end
    return o
end
local source = object('FileManaMovie /Game/Opening.OP1', {
    GetUrl = function() return {ToString = function() return 'Movies/MV_Opening/Korat_OP1_1K_CP.usm' end} end,
    NumSubtitleChannels = 0,
    VideoTracks = {{FrameRate = 30, TotalFrames = 651}},
})
local frame, paused = 45, false
local component = object('ManaComponent /Game/Map.Player.Component', {
    GetSource = function() return source end,
    GetFrameNumber = function() return frame end,
    IsPlaying = function() return true end,
    IsPaused = function() return paused end,
    GetStatus = function() return 5 end,
})
local material = object('MaterialInstanceDynamic /Game/Map.SSCriMediaPlayer_1.Material_1')
local player = object('SSCriMediaPlayer /Game/Map.SSCriMediaPlayer_1', {
    DynamicManaMaterial = material, ManaPlayerNo = 0,
    ManaComponents = {ForEach = function(_, fn)
        -- UE4SS build 1152 passes one-based Lua indices, including ForEach.
        fn(1, {get = function() return component end})
    end},
})
H.FindAllOf = function(class)
    assert(class == 'SSCriMediaPlayer')
    queries = queries + 1
    return {object('SSCriMediaPlayer /Game/Map.Unrelated', {DynamicManaMaterial = object('different')}), player}
end
local screen = {entries = {{image = material:GetFullName(), path = 'Image /Engine/Transient.Movie.IMG_Movie_Area'}}}
assert(Movie.Capture({entries = {}}) == nil and queries == 0)
print('PASS: ordinary UI never searches allocated movie players')
local got = Movie.Capture(screen)
assert(got and got.url == 'Movies/MV_Opening/Korat_OP1_1K_CP.usm' and got.frame == 45)
assert(got.player == player:GetFullName(), 'must match the material that is actually displayed')
assert(type(got.source) == 'string' and got.playing and not got.paused)
print('PASS: only the player feeding the visible movie surface is reported')
frame, paused = 150, true
got = Movie.Capture(screen)
assert(got.frame == 150 and got.paused and queries == 1)
print('PASS: cached player references still read the current clock and pause state')
local reads = 0
player.ManaComponents = setmetatable({GetArrayNum = function() return 1 end}, {
    __index = function(_, index)
        if type(index) == 'number' then
            assert(index == 1, 'never read outside the native array: UE4SS expands it')
            reads = reads + 1
            return component
        end
    end,
})
got = Movie.Capture(screen)
assert(got.frame == frame and got.index == 0 and reads == 1)
assert(got.fps == 30 and got.totalFrames == 651 and got.seconds == 5)
print('PASS: native bounded array reads expose the active movie clock in seconds')
player.ManaComponents.GetArrayNum = function() return 0 end
got = Movie.Capture(screen)
assert(got.frame == nil and got.componentCount == 0 and reads == 1)
print('PASS: empty component arrays are never indexed or expanded')
player.ManaComponents = {ForEach = function() error('unsupported array conversion') end}
got = Movie.Capture(screen)
assert(got and got.frame == nil)
print('PASS: unavailable movie arrays are diagnosed without breaking other screen reading')
assert(Movie.Capture({entries = {}}) == nil)
player.dead = true
assert(Movie.Capture(screen) == nil)
print('PASS: leaving the screen or destroying the player cancels movie context')
