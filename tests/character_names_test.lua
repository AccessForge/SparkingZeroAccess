-- Integration test: the real main.lua, chara_roster.lua, team_overview.lua and
-- chara_names.lua name characters on simulated battle-setup screens (live
-- session 2026-10-04: owned characters missing from the static table were
-- announced as "Unknown character", and a roster page change left the previous
-- page's character announced). Portraits are Image widgets whose
-- Brush.ResourceObject is a T_UI_ChThumb texture; names come from simulated
-- SSCharacterDataAsset records, as the game's name plate does. The engine mock
-- follows UE4SS semantics: missing objects are invalid wrappers, invalid
-- objects throw, and every object touch is checked against the game thread.
-- Record names and titles are simulated test data, not the game's records.
-- Run from the repository root with Lua 5.4 or LuaJIT.
package.path = "./SparkingZeroAccess/?.lua;" .. package.path

local realClock, realPrint = os.clock, print
local REAL_MODULES = {"helpers", "game_thread", "poll_trackers", "widget_reader", "language_options",
    "chara_names", "chara_roster", "team_overview"}
local STUBBED_MODULES = {"skill_list", "battle", "episode_battle", "shop", "screen_reader"}
local GAME = "/Engine/Transient.GameEngine_2147482611:BP_SSGameInstance_C_2147482468"
local THUMBS = "/Game/SS/UI/Common/CommonResource/CharacterThumb/"
local DATA = "/Game/SS/MasterDataAsset/CharacterData/"

local function Thumb(id, costume)
    local name = "T_UI_ChThumbP1_" .. id .. "_" .. (costume or "00")
    return THUMBS .. "P1/" .. name .. "." .. name
end
local EMPTY = THUMBS .. "T_UI_Common_Icon_Empty_Plus.T_UI_Common_Icon_Empty_Plus"

local function Harness(options)
    local h = {now = 1, phase = "game", loops = {}, queue = {}, spoken = {}, logs = {},
        world = {}, unsafe = 0, legacy = options.legacy, focused = nil, serial = 2147373000,
        imageScans = 0, dataLookups = 0, classLookups = 0, shortNameLookups = 0, records = {}, folderless = false}
    local super = {Widget = "Object", UserWidget = "Widget", PanelWidget = "Widget", Image = "Widget",
        TextBlock = "Widget", WidgetTree = "Object", GameInstance = "Object", BP_SSGameInstance_C = "GameInstance",
        CanvasPanel = "PanelWidget", Texture2D = "Object", SSCharacterDataAsset = "Object",
        WBP_OBJ_Common_HitButton_C = "UserWidget", WBP_OBJ_BS_CharaIcon_00_C = "UserWidget",
        WBP_GRP_BS_CharaList_DP_C = "UserWidget", WBP_GRP_BS_ChList_TeamList_DB_C = "UserWidget",
        WBP_GRP_BS_Top_00_1P_C = "UserWidget"}
    local function IsA(class, target)
        while class do
            if class == target then return true end
            class = super[class]
        end
        return false
    end
    os.clock = function() return h.now end
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        h.logs[#h.logs + 1] = table.concat(parts, " ")
    end

    local function Touch(self)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        if not self._valid then error("Object is not valid", 3) end
    end
    local methods = {}
    function methods:IsValid() return self._valid end
    function methods:type() return "UObject" end
    function methods:GetFullName() Touch(self); return self._class .. " " .. self._path end
    function methods:GetOuter() Touch(self); return self._outer end
    function methods:IsVisible() Touch(self); return true end
    function methods:HasKeyboardFocus() Touch(self); return h.focused == self end
    local mt = {__index = function(self, key)
        if methods[key] then return methods[key] end
        Touch(self)
        local props = rawget(self, "_props")
        props._reads[key] = (props._reads[key] or 0) + 1
        return props[key]
    end}
    local function Object(class, path, outer, live)
        local object = setmetatable({_class = class, _path = path, _outer = outer, _valid = true,
            _props = {_reads = {}}}, mt)
        if live then h.world[#h.world + 1] = object end
        return object
    end
    -- UE4SS returns an invalid wrapper, not nil, for a null object.
    local function Null() local null = Object("Object", "", nil, false); null._valid = false; return null end
    local function Spawn(class, path, outer) return Object(class, path, outer, true) end
    local function OwnTree(widget)
        h.serial = h.serial + 1
        local tree = Spawn("WidgetTree", widget._path .. ".WidgetTree_" .. h.serial, widget)
        widget._tree, widget._props.WidgetTree = tree, tree
        return widget
    end
    local function Place(class, name, parent)
        if parent._tree then
            local widget = Spawn(class, parent._tree._path .. "." .. name, parent._tree)
            parent._tree._props.RootWidget = widget
            return widget
        end
        local widget = Spawn(class, parent._outer._path .. "." .. name, parent._outer)
        parent._children[#parent._children + 1] = widget
        return widget
    end
    function h:Reads(object, key) return object._props._reads[key] or 0 end
    function h:Instances(class, exact)
        local found = {}
        for _, object in ipairs(self.world) do
            if object._valid and (exact and object._class == class or not exact and IsA(object._class, class)) then
                found[#found + 1] = object
            end
        end
        return found
    end

    -- Portraits. A texture of false is a null brush resource (still loading).
    function h:Texture(path)
        if not path then return Null() end
        return Object("Texture2D", path, nil, false)
    end
    function h:SetPortrait(face, path) face._props.Brush = {ResourceObject = self:Texture(path)} end

    -- Character records: name = {short, title}. Text is read live. A record is
    -- a live SSCharacterDataAsset unless classless (only its path finds it).
    local function FText(value) return {ToString = function(self) return value end} end
    h.FText = FText
    function h:Record(id, short, title, classless)
        local name = "CharacterData_" .. id
        local asset = Object("SSCharacterDataAsset", DATA .. name .. "." .. name, nil, not classless)
        asset._props.CharacterDataAssetRecord = {NameInfo = {ShortName = FText(short), TitleName = FText(title or ""),
            FullName = FText("unused full name " .. id)}}
        self.records[id] = asset
        return asset
    end
    function h:Decoy(class, id, short) -- same object name, different class
        local name = "CharacterData_" .. id
        local decoy = Object(class, "/Game/Other/" .. name .. "." .. name, nil, true)
        decoy._props.CharacterDataAssetRecord = {NameInfo = {ShortName = FText(short), TitleName = FText("")}}
        return decoy
    end
    function h:Rename(id, short, title)
        self.records[id]._props.CharacterDataAssetRecord.NameInfo.ShortName = FText(short)
        self.records[id]._props.CharacterDataAssetRecord.NameInfo.TitleName = FText(title or "")
    end

    -- Native UE4SS globals.
    local gameInstance = Spawn("BP_SSGameInstance_C", GAME, nil)
    local function ClassObject(name)
        return {_className = name, IsValid = function() return true end, type = function() return "UObject" end}
    end
    local library = {IsValid = function() return true end, type = function() return "UObject" end,
        GetAllWidgetsOfClass = function(_, world, out, class, topLevelOnly)
            if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
            assert(world == gameInstance and topLevelOnly == false)
            for _, object in ipairs(h:Instances(class._className)) do out[#out + 1] = object end
        end}
    StaticFindObject = function(path)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then return library end
        if path == "/Script/UMG.UserWidget" then return ClassObject("UserWidget") end
        local id = path:match("^" .. DATA:gsub("%p", "%%%0") .. "CharacterData_(%d+_%d+)%.CharacterData_%d+_%d+$")
        if id then
            h.dataLookups = h.dataLookups + 1
            if not h.folderless and h.records[id] then return h.records[id] end
        end
        return Null()
    end
    FindObject = function(class, outer, name, exact)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        assert(class == nil and outer == -1 and exact == false, "unexpected FindObject overload")
        h.shortNameLookups = h.shortNameLookups + 1
        local id = name:match("^CharacterData_(%d+_%d+)$")
        return id and h.records[id] or Null()
    end
    local function CountImageScan(class) if class == "Image" then h.imageScans = h.imageScans + 1 end end
    FindObjects = function(count, class, name, _, _, exact)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        if class == nil then return super[name] and {ClassObject(name)} or {} end
        CountImageScan(class)
        if class == "SSCharacterDataAsset" then h.classLookups = h.classLookups + 1 end
        local found = {}
        for _, object in ipairs(h:Instances(class, exact)) do
            if name == nil or object._path:match("[%.:]([^%.:]+)$") == name then found[#found + 1] = object end
            if count > 0 and #found >= count then break end
        end
        return found
    end
    FindAllOf = function(class)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        CountImageScan(class)
        local found = h:Instances(class)
        return #found > 0 and found or nil
    end
    FindFirstOf = function(class)
        if h.phase ~= "game" then h.unsafe = h.unsafe + 1 end
        return h:Instances(class)[1]
    end
    LoopAsync = function(_, callback) h.loops[#h.loops + 1] = callback end
    ExecuteInGameThread = function(callback) h.queue[#h.queue + 1] = callback end
    ExecuteWithDelay = function(_, callback) h.loops[#h.loops + 1] = function() callback(); return true end end
    RegisterLoadMapPreHook = function(callback) h.pre = callback end
    RegisterLoadMapPostHook = function(callback) h.post = callback end
    RegisterHook = function() return 1, 2 end
    RegisterKeyBind = function() end
    LoopInGameThreadWithDelay = (not options.legacy) and function() return 1 end or nil

    for _, name in ipairs(REAL_MODULES) do package.loaded[name] = nil end
    local function noop() end
    for _, name in ipairs(STUBBED_MODULES) do
        package.loaded[name] = setmetatable({}, {__index = function() return noop end})
    end
    package.loaded.debug_tools = {Init = noop}
    package.loaded.speech = {
        Init = noop,
        IsLoaded = function() return true end,
        Speak = function(text, interrupt)
            h.spoken[#h.spoken + 1] = {text = text, interrupt = interrupt ~= false, queued = false}
        end,
        SpeakQueued = function(text)
            h.spoken[#h.spoken + 1] = {text = text, interrupt = false, queued = true}
        end,
    }
    assert(loadfile("SparkingZeroAccess/main.lua"))()

    -- A screen with hit buttons and same-numbered CharaIcon portraits.
    -- portraits: list of {hitName, iconName, texturePath or false}
    local function Screen(class, portraits)
        h.serial = h.serial + 1
        local screen = OwnTree(Spawn(class, GAME .. "." .. class .. "_" .. h.serial, gameInstance))
        local canvas = Place("CanvasPanel", "Canvas", screen)
        canvas._children = {}
        local m = {screen = screen, hits = {}, faces = {}, icons = {}}
        for _, p in ipairs(portraits) do
            local hit = OwnTree(Place("WBP_OBJ_Common_HitButton_C", "WBP_OBJ_Common_HitButton_" .. p[1], canvas))
            m.hits[p[1]] = hit
            if p[2] then
                local icon = OwnTree(Place("WBP_OBJ_BS_CharaIcon_00_C", "WBP_OBJ_BS_CharaIcon_" .. p[2], canvas))
                local face = Place("Image", "IMG_Face_Main", icon)
                h:SetPortrait(face, p[3])
                m.faces[p[1]], m.icons[p[1]] = face, icon
            end
        end
        return m
    end
    function h:Roster(grid) -- grid: {suffix = texture}
        local portraits = {}
        for suffix, texture in pairs(grid) do portraits[#portraits + 1] = {suffix, suffix, texture} end
        return Screen("WBP_GRP_BS_CharaList_DP_C", portraits)
    end
    function h:TeamList(slots) -- slots[1..5] = texture; hit "0" uses icon "00"
        local portraits = {}
        for i, texture in ipairs(slots) do portraits[#portraits + 1] = {tostring(i - 1), "0" .. (i - 1), texture} end
        return Screen("WBP_GRP_BS_ChList_TeamList_DB_C", portraits)
    end
    function h:Team(slots) -- slots[1..5] = texture; hit "0" uses icon "0"
        local portraits = {}
        for i, texture in ipairs(slots) do portraits[#portraits + 1] = {tostring(i - 1), tostring(i - 1), texture} end
        return Screen("WBP_GRP_BS_Top_00_1P_C", portraits)
    end
    function h:Destroy(menu)
        local prefix = menu.screen._path
        for _, object in ipairs(self.world) do
            if object._path == prefix or object._path:sub(1, #prefix + 1) == prefix .. "." then
                object._valid = false
            end
        end
    end
    function h:Focus(widget) self.focused = widget end

    -- One frame: the async worker requests service, then the game thread runs it.
    function h:Frame(dt)
        self.now = self.now + (dt or 0.02)
        self.phase = "worker"
        local loops = self.loops
        for i = #loops, 1, -1 do
            if loops[i]() == true then table.remove(loops, i) end
        end
        self.phase = "game"
        local queue = self.queue
        self.queue = {}
        for _, callback in ipairs(queue) do callback() end
    end
    function h:Run(seconds)
        for _ = 1, math.floor(seconds / 0.02 + 0.5) do self:Frame(0.02) end
    end
    function h:Mark() return #self.spoken end
    function h:Since(mark)
        local entries = {}
        for i = (mark or 0) + 1, #self.spoken do entries[#entries + 1] = self.spoken[i] end
        return entries
    end
    function h:Count(text, mark)
        local n = 0
        for _, entry in ipairs(self:Since(mark)) do
            if entry.text == text then n = n + 1 end
        end
        return n
    end
    function h:Logged(text)
        local n = 0
        for _, line in ipairs(self.logs) do
            if line:find(text, 1, true) then n = n + 1 end
        end
        return n
    end
    return h
end

local function Heard(h, mark)
    local parts = {}
    for _, entry in ipairs(h:Since(mark)) do
        parts[#parts + 1] = string.format("%q%s", entry.text, entry.queued and "(queued)" or "")
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end

local function ExpectHealthy(h)
    assert(h.unsafe == 0, "game objects were touched outside the game thread")
    for _, line in ipairs(h.logs) do
        assert(not line:lower():find("error", 1, true), "reader reported: " .. line)
    end
end

local function ExpectOnly(h, mark, expected)
    local heard = h:Since(mark)
    assert(#heard == 1 and heard[1].text == expected and heard[1].interrupt,
        "expected only " .. string.format("%q", expected) .. "; heard " .. Heard(h, mark))
end

-- A correction of a placeholder must not cut off speech queued before it.
local function ExpectQueued(h, mark, expected)
    local heard = h:Since(mark)
    assert(#heard == 1 and heard[1].text == expected and not heard[1].interrupt,
        "expected only queued " .. string.format("%q", expected) .. "; heard " .. Heard(h, mark)
        .. (heard[1] and heard[1].interrupt and " (interrupting)" or ""))
end

local cases = {
    {"a character missing from the static table is announced by its native name", function(options)
        local h = Harness(options)
        h:Record("3270_01", "Vegeta (GT)", "Super Saiyan")
        local roster = h:Roster({["24"] = Thumb("3270_01")})
        h:Focus(roster.hits["24"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Vegeta (GT), Super Saiyan")
        assert(h:Logged("Character 3270_01: Vegeta (GT), Super Saiyan (native record)") == 1)
        ExpectHealthy(h)
    end},
    {"the native name is preferred and the static table still supplies DP", function(options)
        local h = Harness(options)
        h:Record("0000_41", "Goku (Super)", "Super Saiyan")
        local roster = h:Roster({["14"] = Thumb("0000_41")})
        h:Focus(roster.hits["14"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Goku (Super), Super Saiyan, 6 DP")
        ExpectHealthy(h)
    end},
    {"the static table names a character whose record cannot be read", function(options)
        local h = Harness(options)
        local roster = h:Roster({["12"] = Thumb("0000_23")})
        h:Focus(roster.hits["12"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Goku (Z - End) Super Saiyan 3, 7 DP")
        assert(h:Logged("Character 0000_23: native name unavailable") == 1, "fallback was not logged")
        ExpectHealthy(h)
    end},
    {"a record is found by class and name, whatever its folder", function(options)
        local h = Harness(options)
        h.folderless = true
        h:Record("3280_01", "Trunks (GT)", "Super Saiyan")
        local roster = h:Roster({["27"] = Thumb("3280_01")})
        h:Focus(roster.hits["27"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Trunks (GT), Super Saiyan")
        assert(h.classLookups == 1 and h.dataLookups == 0, "class/path lookups "
            .. h.classLookups .. "/" .. h.dataLookups)
        assert(h.shortNameLookups == 0, "an unfiltered any-package lookup was used")
        ExpectHealthy(h)
    end},
    {"the path lookup is a one-time fallback when the class lookup finds nothing", function(options)
        local h = Harness(options)
        h:Record("3280_00", "Test Fighter C", nil, true) -- only its path finds it
        local roster = h:Roster({["26"] = Thumb("3280_00"), ["27"] = Thumb("3190_00")})
        h:Focus(roster.hits["26"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Test Fighter C")
        local mark = h:Mark()
        h:Focus(roster.hits["27"]) -- no record anywhere
        h:Run(5)
        ExpectOnly(h, mark, "Unknown character")
        assert(h.dataLookups == 2, "path lookups were repeated: " .. h.dataLookups)
        ExpectHealthy(h)
    end},
    {"a same-named object of another class is never used as a record", function(options)
        local h = Harness(options)
        h:Decoy("Texture2D", "3280_01", "Decoy")
        local roster = h:Roster({["27"] = Thumb("3280_01")})
        h:Focus(roster.hits["27"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Unknown character")
        ExpectHealthy(h)
    end},
    {"an unidentifiable character is reported as unknown, never as another name", function(options)
        local h = Harness(options)
        local roster = h:Roster({["05"] = Thumb("9999_99")})
        h:Focus(roster.hits["05"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Unknown character")
        ExpectHealthy(h)
    end},
    {"a portrait that is still loading is not called unknown and is named once it loads", function(options)
        local h = Harness(options)
        h:Record("3270_00", "Vegeta (GT)")
        local roster = h:Roster({["24"] = false})
        h:Focus(roster.hits["24"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Loading character")
        local mark = h:Mark()
        h:Run(0.5)
        assert(#h:Since(mark) == 0, "repeated while loading: " .. Heard(h, mark))
        h:SetPortrait(roster.faces["24"], Thumb("3270_00"))
        h:Run(0.1)
        ExpectQueued(h, mark, "Vegeta (GT)")
        mark = h:Mark()
        h:Run(2)
        assert(#h:Since(mark) == 0, "loaded name repeated: " .. Heard(h, mark))
        assert(h:Count("Unknown character") == 0, "a loading portrait was called unknown: " .. Heard(h))
        ExpectHealthy(h)
    end},
    {"a roster page change under unchanged focus names the new character once", function(options)
        local h = Harness(options)
        h:Record("0941_00", "Toppo", "God of Destruction")
        h:Record("0690_00", "Nuova Shenron (GT)")
        local roster = h:Roster({["30"] = Thumb("0941_00")})
        h:Focus(roster.hits["30"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Toppo, God of Destruction, 8 DP")
        local mark = h:Mark()
        h:SetPortrait(roster.faces["30"], false) -- cleared while the page refills
        h:Run(0.1)
        assert(#h:Since(mark) == 0, "a cleared portrait was announced: " .. Heard(h, mark))
        h:SetPortrait(roster.faces["30"], Thumb("0690_00"))
        h:Run(0.1)
        ExpectOnly(h, mark, "Nuova Shenron (GT)")
        mark = h:Mark()
        h:SetPortrait(roster.faces["30"], Thumb("0690_00", "01")) -- another costume, same character
        h:Run(2)
        assert(#h:Since(mark) == 0, "unchanged character repeated: " .. Heard(h, mark))
        ExpectHealthy(h)
    end},
    {"another instance of the roster list is never read for the focused list", function(options)
        local h = Harness(options)
        h:Record("0941_00", "Toppo", "God of Destruction")
        h:Record("3360_00", "Chilled")
        local outgoing = h:Roster({["20"] = Thumb("0941_00")}) -- found first by the object query
        local current = h:Roster({["20"] = Thumb("3360_00")})
        h:Focus(current.hits["20"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Chilled")
        assert(h:Reads(outgoing.faces["20"], "Brush") == 0, "the other list's portrait was read")
        ExpectHealthy(h)
    end},
    {"returning to a roster slot from the team list announces it again", function(options)
        local h = Harness(options)
        h:Record("0000_40", "Goku (Super)")
        local roster = h:Roster({["13"] = Thumb("0000_40")})
        local list = h:TeamList({Thumb("0000_40"), EMPTY, EMPTY, EMPTY, EMPTY})
        h:Focus(roster.hits["13"])
        h:Run(0.2)
        h:Focus(list.hits["0"])
        h:Run(0.2)
        h:Focus(roster.hits["13"])
        h:Run(0.2)
        assert(h:Count("Goku (Super), 5 DP") == 2, "the roster slot was not announced again: " .. Heard(h))
        assert(h:Count("Slot 1, Goku (Super), 5 DP") == 1, "team list slot not announced: " .. Heard(h))
        ExpectHealthy(h)
    end},
    {"team list slots are named natively and empty slots are announced", function(options)
        local h = Harness(options)
        h:Record("3270_01", "Vegeta (GT)", "Super Saiyan")
        local list = h:TeamList({Thumb("3270_01"), EMPTY, EMPTY, EMPTY, EMPTY})
        h:Focus(list.hits["0"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Slot 1, Vegeta (GT), Super Saiyan")
        local mark = h:Mark()
        h:Focus(list.hits["1"])
        h:Run(0.2)
        ExpectOnly(h, mark, "Slot 2, Empty")
        mark = h:Mark()
        h:SetPortrait(list.faces["1"], Thumb("3270_01")) -- a member is added under focus
        h:Run(0.1)
        ExpectOnly(h, mark, "Slot 2, Vegeta (GT), Super Saiyan")
        ExpectHealthy(h)
    end},
    {"team overview names slots natively and never announces a wrong DP total", function(options)
        local h = Harness(options)
        h:Record("0000_40", "Goku (Super)")
        h:Record("3270_01", "Vegeta (GT)", "Super Saiyan")
        local team = h:Team({Thumb("0000_40"), Thumb("3270_01"), EMPTY, EMPTY, EMPTY})
        h:Focus(team.hits["0"])
        h:Run(0.2)
        local heard = h:Since(0)
        assert(heard[1] and heard[1].text == "Goku (Super), 5 DP" and heard[2] and heard[2].text == "Slot 1",
            "first slot misread: " .. Heard(h))
        assert(h:Count("Player 1, Team Overview, 2 characters") == 1,
            "team summary missing, or totals a DP that is not known: " .. Heard(h))
        local mark = h:Mark()
        h:Focus(team.hits["1"])
        h:Run(0.2)
        heard = h:Since(mark)
        assert(#heard == 2 and heard[1].text == "Vegeta (GT), Super Saiyan" and heard[2].text == "Slot 2"
            and heard[2].queued, "second slot misread: " .. Heard(h, mark))
        assert(h:Count("Unknown character") == 0)
        ExpectHealthy(h)
    end},
    {"names are read live in the current language; only record references are cached", function(options)
        local h = Harness(options)
        h:Record("3360_00", "Chilled")
        local roster = h:Roster({["20"] = Thumb("3360_00"), ["21"] = Thumb("0000_40")})
        h:Record("0000_40", "Goku (Super)")
        h:Focus(roster.hits["20"])
        h:Run(0.2)
        h:Focus(roster.hits["21"])
        h:Run(0.2)
        h:Rename("3360_00", "Kiruzu") -- display language changed
        local mark = h:Mark()
        h:Focus(roster.hits["20"])
        h:Run(0.2)
        ExpectOnly(h, mark, "Kiruzu")
        assert(h.classLookups == 2 and h.dataLookups == 0, "record references were not reused: "
            .. h.classLookups .. " class and " .. h.dataLookups .. " path lookups")
        ExpectHealthy(h)
    end},
    {"a steady focus re-reads only its own portrait, without object queries", function(options)
        local h = Harness(options)
        h:Record("3270_00", "Vegeta (GT)")
        h:Record("3270_01", "Vegeta (GT)", "Super Saiyan")
        local roster = h:Roster({["24"] = Thumb("3270_00"), ["25"] = Thumb("3270_01")})
        h:Focus(roster.hits["24"])
        h:Run(0.2)
        local scans, lookups = h.imageScans, h.classLookups + h.dataLookups
        local own, other = h:Reads(roster.faces["24"], "Brush"), h:Reads(roster.faces["25"], "Brush")
        h:Run(2)
        assert(h.imageScans == scans, "steady focus repeated the Image query " .. (h.imageScans - scans) .. " times")
        assert(h.classLookups + h.dataLookups == lookups, "steady focus repeated record lookups")
        assert(h:Reads(roster.faces["24"], "Brush") > own, "the focused portrait was not watched")
        assert(h:Reads(roster.faces["25"], "Brush") == other, "an unfocused portrait was read")
        -- Moving focus stops watching the previous slot.
        h:Focus(roster.hits["25"])
        h:Run(0.2)
        own = h:Reads(roster.faces["24"], "Brush")
        h:Run(1)
        assert(h:Reads(roster.faces["24"], "Brush") == own, "the previous slot was still watched")
        assert(h:Count("Vegeta (GT), Super Saiyan") == 1)
        ExpectHealthy(h)
    end},
    {"a missing portrait widget is searched for a bounded number of times", function(options)
        local h = Harness(options)
        h:Record("3290_00", "Test Fighter A")
        local roster = h:Roster({["28"] = Thumb("3290_00")})
        local orphan = h:Roster({["29"] = Thumb("3290_00")})
        orphan.faces["29"]._valid = false -- the hit button exists, its portrait does not
        h:Focus(orphan.hits["29"])
        h:Run(0.2)
        ExpectOnly(h, 0, "Loading character")
        local scans = h.imageScans
        h:Run(6)
        local used = h.imageScans - scans
        assert(used >= 6 and used <= 12, "portrait search was not bounded and throttled: " .. used .. " queries")
        assert(h:Logged("portrait widget not found after 12 searches") == 1, "giving up was not logged once")
        local settled = h.imageScans
        h:Run(3)
        assert(h.imageScans == settled, "portrait search never stopped")
        ExpectQueued(h, 1, "Character unavailable")
        assert(h:Reads(roster.faces["28"], "Brush") == 0, "another list's portrait was read")
        ExpectHealthy(h)
    end},
    {"a portrait that never loads is reported unavailable once, then named if it loads", function(options)
        local h = Harness(options)
        h:Record("3330_00", "Test Fighter B")
        local roster = h:Roster({["15"] = false})
        h:Focus(roster.hits["15"])
        h:Run(2.5)
        ExpectOnly(h, 0, "Loading character")
        h:Run(1)
        ExpectQueued(h, 1, "Character unavailable")
        local mark = h:Mark()
        h:Run(3)
        assert(#h:Since(mark) == 0, "unavailable was repeated: " .. Heard(h, mark))
        h:SetPortrait(roster.faces["15"], Thumb("3330_00"))
        h:Run(0.1)
        ExpectQueued(h, mark, "Test Fighter B")
        assert(h:Logged("no character portrait after") == 1)
        ExpectHealthy(h)
    end},
    {"map loading discards the watched portrait of the old world", function(options)
        local h = Harness(options)
        h:Record("3270_00", "Vegeta (GT)")
        local roster = h:Roster({["24"] = Thumb("3270_00")})
        h:Focus(roster.hits["24"])
        h:Run(0.2)
        local mark, reads = h:Mark(), h:Reads(roster.faces["24"], "Brush")
        if h.pre then
            h.pre()
            h:Run(1) -- loading: the reader is paused
        else
            assert(h.legacy, "map pre-hook missing on a fixed loader")
        end
        h:Destroy(roster)
        h:Focus(nil)
        h.post()
        h:Run(3)
        assert(h:Reads(roster.faces["24"], "Brush") == reads, "an old-world portrait was read during or after loading")
        assert(#h:Since(mark) == 0, "spoke for the old world: " .. Heard(h, mark))
        ExpectHealthy(h)
    end},
}

cases[#cases + 1] = {"a late native name replaces unknown without changing the portrait", function(options)
    local h = Harness(options)
    local roster = h:Roster({["24"] = Thumb("3270_01")})
    h:Focus(roster.hits["24"])
    h:Run(0.2)
    ExpectOnly(h, 0, "Unknown character")
    local mark, scans = h:Mark(), h.imageScans
    h:Record("3270_01", "Vegeta (GT)", "Super Saiyan")
    h:Run(0.8)
    ExpectQueued(h, mark, "Vegeta (GT), Super Saiyan")
    h:Run(3)
    assert(h:Count("Vegeta (GT), Super Saiyan") == 1, "late name repeated")
    assert(h.imageScans == scans, "late record retried the global portrait query")
    ExpectHealthy(h)
end}

cases[#cases + 1] = {"missing native names stop retrying after a bounded interval", function(options)
    local h = Harness(options)
    local roster = h:Roster({["24"] = Thumb("3190_00")})
    h:Focus(roster.hits["24"])
    h:Run(5)
    local lookups, scans = h.classLookups, h.imageScans
    assert(lookups > 1 and lookups <= 8, "native retries were absent or unbounded: " .. lookups)
    assert(h.dataLookups <= 1, "the unfiltered path lookup was retried: " .. h.dataLookups)
    h:Run(4)
    assert(h.classLookups == lookups and h.imageScans == scans, "missing native name kept scanning")
    assert(h:Count("Unknown character") == 1)
    ExpectHealthy(h)
end}

cases[#cases + 1] = {"a missing owned portrait cannot borrow another list's same-numbered slot", function(options)
    local h = Harness(options)
    h:Record("3270_01", "Vegeta (GT)", "Super Saiyan")
    local other = h:Roster({["24"] = Thumb("3270_01")})
    local current = h:Roster({["24"] = false})
    current.faces["24"]._valid = false
    h:Focus(current.hits["24"])
    h:Run(0.2)
    ExpectOnly(h, 0, "Loading character")
    assert(h:Reads(other.faces["24"], "Brush") == 0, "read a foreign portrait")
    ExpectHealthy(h)
end}

cases[#cases + 1] = {"the current team screen announces its delayed guide", function(options)
    local h = Harness(options)
    h:Record("0000_40", "Goku (Super)")
    local team = h:Team({Thumb("0000_40")})
    require("team_overview").ReadGuideBar = function() return {"Hold R Start Battle"} end
    h:Focus(team.hits["0"])
    h:Run(0.3)
    assert(h:Count("Hold R Start Battle") == 1, "team guide did not speak")
    ExpectHealthy(h)
end}

cases[#cases + 1] = {"a late name after a placeholder keeps the team summary queued before it", function(options)
    local h = Harness(options)
    h:Record("0000_40", "Goku (Super)")
    h:Record("3270_00", "Vegeta (GT)")
    local team = h:Team({Thumb("0000_40"), false, EMPTY, EMPTY, EMPTY})
    h:Focus(team.hits["1"])
    h:Run(0.05)
    local heard = h:Since(0)
    assert(#heard == 3 and heard[1].text == "Loading character" and heard[2].text == "Slot 2"
        and heard[3].text == "Player 1, Team Overview",
        "a still-loading member must leave the count and total out: " .. Heard(h))
    local mark = h:Mark()
    h:SetPortrait(team.faces["1"], Thumb("3270_00"))
    h:Run(0.04)
    heard = h:Since(mark)
    assert(#heard == 2 and heard[1].text == "Vegeta (GT)" and not heard[1].interrupt
        and heard[2].text == "Slot 2", "the late name cut off queued speech: " .. Heard(h, mark))
    ExpectHealthy(h)
end}

cases[#cases + 1] = {"an icon's own question-mark picture is announced at once, never as loading", function(options)
    local h = Harness(options)
    local question = "/Game/SS/UI/BattleSetting/OBJ/Texture/T_Test_Question.T_Test_Question"
    local team = h:Team({question, EMPTY, EMPTY, EMPTY, EMPTY})
    team.icons["0"]._props.QuestionTexture = h:Texture(question)
    h:Focus(team.hits["0"])
    h:Run(4)
    local heard = h:Since(0)
    assert(heard[1].text == "Question mark" and heard[2].text == "Slot 1",
        "the question-mark picture was misread: " .. Heard(h))
    assert(h:Count("Loading character") == 0 and h:Count("Character unavailable") == 0,
        "a final picture was treated as loading: " .. Heard(h))
    assert(h:Count("Player 1, Team Overview") == 1, "a hidden member was counted: " .. Heard(h))
    ExpectHealthy(h)
end}

cases[#cases + 1] = {"a picture that is not a character is final, not loading", function(options)
    local h = Harness(options)
    local other = "/Game/SS/UI/Common/Common_Texture/T_Test_Other.T_Test_Other"
    local roster = h:Roster({["03"] = other})
    h:Focus(roster.hits["03"])
    h:Run(4)
    ExpectOnly(h, 0, "Unrecognized portrait")
    assert(h:Logged("Portrait is not a character thumbnail (unrecognized): Texture2D " .. other) == 1)
    ExpectHealthy(h)
end}

cases[#cases + 1] = {"a portrait that stays cleared is reported unavailable, then named on return", function(options)
    local h = Harness(options)
    h:Record("0000_40", "Goku (Super)")
    local roster = h:Roster({["13"] = Thumb("0000_40")})
    h:Focus(roster.hits["13"])
    h:Run(0.2)
    ExpectOnly(h, 0, "Goku (Super), 5 DP")
    local mark = h:Mark()
    h:SetPortrait(roster.faces["13"], false)
    h:Run(2)
    assert(#h:Since(mark) == 0, "a brief gap was announced: " .. Heard(h, mark))
    h:Run(1.5)
    ExpectQueued(h, mark, "Character unavailable")
    mark = h:Mark()
    h:SetPortrait(roster.faces["13"], Thumb("0000_40"))
    h:Run(0.1)
    ExpectQueued(h, mark, "Goku (Super), 5 DP")
    ExpectHealthy(h)
end}

cases[#cases + 1] = {"a team list slot speaks again after focus passes through the list itself", function(options)
    local h = Harness(options)
    h:Record("3270_01", "Vegeta (GT)", "Super Saiyan")
    local list = h:TeamList({Thumb("3270_01"), EMPTY, EMPTY, EMPTY, EMPTY})
    h:Focus(list.hits["0"])
    h:Run(0.2)
    h:Focus(list.screen) -- the suppressed list container
    h:Run(0.2)
    h:Focus(list.hits["0"])
    h:Run(0.2)
    assert(h:Count("Slot 1, Vegeta (GT), Super Saiyan") == 2, "returning focus was silent: " .. Heard(h))
    ExpectHealthy(h)
end}

local variants = {
    {"UE4SS 1152", {legacy = false}},
    {"stock UE4SS 3.0.1", {legacy = true}},
}

local failures = 0
for _, variant in ipairs(variants) do
    for _, case in ipairs(cases) do
        local ok, err = pcall(case[2], variant[2])
        os.clock, print = realClock, realPrint
        local label = variant[1] .. ": " .. case[1]
        if ok then print("PASS: " .. label)
        else failures = failures + 1; print("FAIL: " .. label .. ": " .. tostring(err)) end
    end
end
os.clock, print = realClock, realPrint
FindObject = nil
assert(failures == 0, tostring(failures) .. " character name regressions")
