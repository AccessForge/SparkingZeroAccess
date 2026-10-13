--[[
    icon_parser.lua — Convert UMG RichText icon markup to readable text
    Handles keyboard keys, PlayStation buttons, and Xbox buttons.
]]

local IconParser = {}

-- Keyboard special key IDs (Key_XX)
local KeyNames = {
    Key_16 = "Space",
    Key_19 = "Tab", -- verified against the live Options glyph and keyboard input
    Key_20 = "Backspace",
    Key_26 = "Left Shift",
    Key_34 = "Left Arrow",
    Key_35 = "Up Arrow",
    Key_36 = "Right Arrow",
    Key_37 = "Down Arrow",
    Key_38 = "Left Mouse",
    Key_39 = "Right Mouse",
}

-- PS4 button IDs (different mapping from PS5 in some cutscene/legacy widgets)
-- Falls through to PS5 table for IDs not listed here
local PS4Names = {
    Pad_05 = "Cross",
    pad_05 = "Cross",
}

-- PlayStation button IDs (Pad_XX, PS5 tables — also used as fallback for PS4)
local PSNames = {
    Pad_00 = "Options",
    Pad_01 = "Touchpad",
    Pad_02 = "Circle",
    Pad_03 = "Cross",
    Pad_04 = "Square",
    Pad_05 = "Triangle",
    Pad_06 = "L1",
    Pad_07 = "L2",
    Pad_08 = "L3",
    Pad_09 = "Left Stick",
    Pad_10 = "R1",
    Pad_11 = "R2",
    Pad_12 = "R3",
    Pad_13 = "Right Stick",
    Pad_14 = "Left Stick Up",
    Pad_15 = "Left Stick Right",
    Pad_16 = "Left Stick Down",
    Pad_17 = "Left Stick Left",
    Pad_18 = "Right Stick Up",
    Pad_19 = "Right Stick Right",
    Pad_20 = "Right Stick Down",
    Pad_21 = "Right Stick Left",
    Pad_22 = "D-Pad Up", -- native tag builder shares key ids with XSX
    Pad_23 = "D-Pad Right",
    Pad_24 = "D-Pad Down",
    Pad_25 = "D-Pad Left",
    Pad_26 = "Left Stick Horizontal",
    Pad_27 = "Left Stick Vertical",
    Pad_28 = "Right Stick Horizontal",
    Pad_29 = "Right Stick Vertical",
    Pad_30 = "Touchpad Horizontal",
    Pad_31 = "Touchpad Vertical",
    -- lowercase variants (game uses both casings)
    pad_02 = "Circle",
    pad_04 = "Square",
    pad_05 = "Triangle",
}

-- Xbox button IDs (same Pad_XX indices, different labels)
local XboxNames = {
    Pad_00 = "Menu",
    Pad_01 = "View",
    Pad_02 = "B",
    Pad_03 = "A",
    Pad_04 = "X",
    Pad_05 = "Y",
    Pad_06 = "LB",
    Pad_07 = "LT",
    Pad_08 = "LS",
    Pad_09 = "Left Stick", -- observed L_Stick_0 glyph in the controls diagram
    Pad_10 = "RB",
    Pad_11 = "RT",
    Pad_12 = "RS",
    Pad_13 = "Right Stick", -- observed R_Stick_0 glyph in the controls diagram
    Pad_14 = "Left Stick Up",
    Pad_15 = "Left Stick Right",
    Pad_16 = "Left Stick Down",
    Pad_17 = "Left Stick Left",
    Pad_18 = "Right Stick Up",
    Pad_19 = "Right Stick Right",
    Pad_20 = "Right Stick Down",
    Pad_21 = "Right Stick Left",
    Pad_22 = "D-Pad Up", -- Transform prompt, confirmed with the player's input
    Pad_23 = "D-Pad Right",
    Pad_24 = "D-Pad Down",
    Pad_25 = "D-Pad Left",
    Pad_26 = "Left Stick Horizontal",
    Pad_27 = "Left Stick Vertical",
    Pad_28 = "Right Stick Horizontal",
    Pad_29 = "Right Stick Vertical",
    -- lowercase variants
    pad_02 = "B",
    pad_04 = "X",
    pad_05 = "Y",
}

--- Parse a single icon tag and return readable text
local function ParseIcon(fullMatch, id, table_name, text)
    if text and text ~= "" then
        return text:gsub("\\r\\n", " "):gsub("\\n", " ")
    end

    local upperTable = (table_name or ""):upper()
    
    if upperTable == "WINDOWS" or upperTable == "KEYBOARD" then
        return KeyNames[id] or id
    elseif upperTable == "PS4" then
        -- PS4 table has some different mappings; fall through to PS5 for unknown IDs
        local lookupId = id:sub(1,1):upper() .. id:sub(2)
        return PS4Names[lookupId] or PS4Names[id] or PSNames[lookupId] or PSNames[id] or id
    elseif upperTable == "PS5" or upperTable == "SONY" then
        local lookupId = id:sub(1,1):upper() .. id:sub(2)
        return PSNames[lookupId] or PSNames[id] or id
    elseif upperTable == "XBOXONE" or upperTable == "XSX" or upperTable == "XBOX" then
        local lookupId = id:sub(1,1):upper() .. id:sub(2)
        return XboxNames[lookupId] or XboxNames[id] or id
    end

    return id
end

--- Convert RichText icon markup to readable text
--- e.g. '<icon id="Pad_Win" table="Windows" text="W"/>' becomes "W"
--- e.g. '<icon id="Key_35" table="Windows"/>' becomes "Up Arrow"
function IconParser.Parse(richText)
    if not richText or richText == "" then return richText end

    -- Attribute order and spacing are not part of the icon's meaning. Separate
    -- adjacent glyphs so Q followed by E is not pronounced as one invented key.
    local result = richText:gsub('<icon%s+([^>]*)/>', function(attributes)
        local values = {}
        for key, value in attributes:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do values[key] = value end
        for key, value in attributes:gmatch("([%w_]+)%s*=%s*'([^']*)'") do values[key] = value end
        local label = ParseIcon(nil, values.id or 'Unknown button', values['table'], values.text)
        return ' ' .. label .. ' '
    end)

    -- Clean up whitespace
    result = result:gsub("%s+", " ")
    result = result:match("^%s*(.-)%s*$")

    return result
end

return IconParser
