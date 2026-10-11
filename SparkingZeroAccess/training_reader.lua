-- Compose only the current, displayed Battle Training instruction widgets.
-- This consumes a visible_ui snapshot; it never reads future lesson data.
local Training = {}
local MAIN = 'WBP_GRP_HUD_CSG_HUD_Main_C'
local CATEGORY = 'WBP_OBJ_HUD_CSG_CategolyText_C'
local COMMAND = 'WBP_OBJ_HUD_CSG_Command_BTN_C'
local TIPS = 'WBP_OBJ_HUD_CSG_Com_Tips_C'
local INTRO = 'WBP_GRP_TTR_HUD_TutorialAll_C'
local INTRO_TIP = 'WBP_OBJ_TRR_HUD_TipText_C'
local CHECK = 'WBP_OBJ_TTR_Icon_Check_C'
local CHECK_IMAGE = 'Texture2D /Game/SS/UI/DramaticBattle/OBJ/Texture/T_UI_DB_Common_CheckMark.T_UI_DB_Common_CheckMark'

local function Role(entry)
    if entry.rootClass ~= MAIN or not entry.text or not entry.root then return nil end
    local name = entry.path:match('%.([^%.]+)$')
    if entry.ownerClass == CATEGORY then
        if name == 'Text_Title' then return 'title' end
        if name == 'Text_Comment' or name == 'Text_Comment_Large' then return 'instruction' end
    elseif entry.ownerClass == COMMAND and name and name:match('^RichText_PadButton_') then
        return 'inputs'
    elseif entry.ownerClass == TIPS and name == 'caption' then
        return 'tips'
    end
end

local function AppendUnique(items, seen, text, key)
    if not text:match('%S') or seen[key] then return end
    seen[key] = true
    items[#items + 1] = text
end

local function Sentence(text)
    return text:gsub('[%.%s]+$', '')
end

-- The opening tutorial has separate action rows. Pair each caption with its
-- own displayed input; identical buttons in different rows are significant.
local function IntroEntries(snapshot)
    local groups, order, members = {}, {}, {}
    for _, entry in ipairs(snapshot.entries) do
        if entry.rootClass == INTRO and entry.ownerClass == INTRO_TIP
            and entry.text and entry.owner and entry.root then
            local name = entry.path:match('%.([^%.]+)$')
            local role = name == 'caption' and 'caption'
                or (name and name:match('^RichText_PadButton_') and 'inputs')
            if role then
                local group = groups[entry.owner]
                if not group then
                    group = {root = entry.root, ownerPath = entry.owner:match('^%S+%s+(.+)$') or entry.owner,
                        caption = {}, inputs = {}, seen = {}}
                    groups[entry.owner], order[#order + 1] = group, group
                end
                AppendUnique(group[role], group.seen, entry.text, entry.path)
                members[entry] = true
            end
        end
    end
    for _, entry in ipairs(snapshot.entries) do
        if entry.rootClass == INTRO and entry.ownerClass == CHECK
            and entry.image == CHECK_IMAGE and entry.path:match('%.IMG_Check_0$') then
            local path = entry.path:match('^%S+%s+(.+)$') or entry.path
            for _, group in ipairs(order) do
                -- Include the path separator so Tip_1 cannot match Tip_10.
                if group.root == entry.root and path:sub(1, #group.ownerPath + 1) == group.ownerPath .. '.' then
                    group.checked = true
                end
            end
        end
    end
    local roots = {}
    for _, group in ipairs(order) do
        local caption, inputs = table.concat(group.caption, '. '), table.concat(group.inputs, ', ')
        local text = caption ~= '' and caption or 'Displayed inputs'
        if inputs ~= '' then text = Sentence(text) .. ': ' .. inputs end
        text = Sentence(text) .. '.'
        if group.checked then text = text .. ' Check mark.' end
        roots[group.root] = roots[group.root] or {}
        roots[group.root][#roots[group.root] + 1] = text
    end
    local result, emitted = {}, {}
    for _, entry in ipairs(snapshot.entries) do
        if not members[entry] then result[#result + 1] = entry
        elseif not emitted[entry.root] then
            emitted[entry.root] = true
            result[#result + 1] = {path = entry.root .. '#tutorial-instructions',
                root = entry.root, rootClass = INTRO, ancestry = '/' .. INTRO,
                text = table.concat(roots[entry.root], ' '), tutorial = true}
        end
    end
    return result
end

function Training.Entries(snapshot)
    local groups, roles = {}, {}
    local entries = IntroEntries(snapshot)
    for _, entry in ipairs(entries) do
        local role = Role(entry)
        if role then
            local group = groups[entry.root]
            if not group then
                group = {title = {}, instruction = {}, inputs = {}, tips = {}, seen = {}}
                groups[entry.root] = group
            end
            -- Repeated presses are separate command widgets. Only duplicate
            -- paths are removed for inputs; duplicate instruction text is one line.
            local key = role .. ':' .. (role == 'inputs' and entry.path or entry.text)
            AppendUnique(group[role], group.seen, entry.text, key)
            roles[entry] = role
        end
    end
    local result, emitted = {}, {}
    for _, entry in ipairs(entries) do
        if not roles[entry] then
            result[#result + 1] = entry
        elseif not emitted[entry.root] then
            emitted[entry.root] = true
            local group, parts = groups[entry.root], {}
            for _, role in ipairs({'title', 'instruction', 'inputs', 'tips'}) do
                local values = group[role]
                if #values > 0 then
                    local text = table.concat(values, role == 'inputs' and ', ' or '. ')
                    if role == 'inputs' then text = 'Displayed inputs: ' .. text end
                    parts[#parts + 1] = text:match('^%s*(.-)%s*$')
                end
            end
            -- Add separators between parts while retaining the final sentence's
            -- punctuation, including explanation-only pages.
            for i = 1, #parts - 1 do parts[i] = Sentence(parts[i]) end
            local text = table.concat(parts, '. ')
            result[#result + 1] = {path = entry.root .. '#training-instructions',
                root = entry.root, rootClass = MAIN, ancestry = '/' .. MAIN,
                text = text, tutorial = true}
        end
    end
    return result
end

return Training
