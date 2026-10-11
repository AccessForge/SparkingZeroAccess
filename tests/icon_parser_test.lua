package.path = './SparkingZeroAccess/?.lua;' .. package.path
local Icons = require('icon_parser')
assert(Icons.Parse('<icon id="Key_19" table="Windows"/> Options') == 'Tab Options')
print('PASS: the live Options glyph is Tab, matching the working game key')
assert(Icons.Parse('<icon table="Windows" id="Pad_Win" text="R" /> Skip') == 'R Skip')
assert(Icons.Parse('<icon text="Q" id="Pad_Win" table="Windows"/><icon id="Pad_Win" text="E" table="Windows"/> Change Screen') == 'Q E Change Screen')
print('PASS: input glyphs survive attribute order, whitespace, and adjacent icons')
assert(Icons.Parse('<icon id="Pad_03" table="XSX"/> Confirm') == 'A Confirm')
assert(Icons.Parse('<icon id="Pad_03" table="PS5"/> Confirm') == 'Cross Confirm')
assert(Icons.Parse('<icon id="Key_20" table="Windows"/> Back') == 'Backspace Back')
print('PASS: supported controller and keyboard glyphs preserve their existing labels')
assert(Icons.Parse('<icon id="Pad_22" table="XSX"/>') == 'D-Pad Up')
assert(Icons.Parse('<icon id="pad_22" table="XSX"/>') == 'D-Pad Up')
assert(Icons.Parse('<icon id="Pad_22" table="PS5"/>') == 'D-Pad Up')
print('PASS: the captured Transform prompt names the D-pad Up input confirmed by the player')
local directions = {'Up', 'Right', 'Down', 'Left'}
for _, platform in ipairs({'XSX', 'PS5'}) do
    for i, direction in ipairs(directions) do
        for _, button in ipairs({{13 + i, 'Left Stick'}, {17 + i, 'Right Stick'}, {21 + i, 'D-Pad'}}) do
            local tag = string.format('<icon id="Pad_%02d" table="%s"/>', button[1], platform)
            assert(Icons.Parse(tag) == button[2] .. ' ' .. direction, tag)
        end
    end
end
print('PASS: all twelve stick and D-pad directions match the live native key table on both controllers')
assert(Icons.Parse('<icon id="Pad_00" table="XSX"/> Pause') == 'Menu Pause')
assert(Icons.Parse('<icon id="Pad_01" table="XSX"/>') == 'View')
assert(Icons.Parse('<icon id="Pad_00" table="PS5"/> Pause') == 'Options Pause')
assert(Icons.Parse('<icon id="Pad_01" table="PS5"/>') == 'Touchpad')
assert(Icons.Parse('<icon id="Pad_26" table="XSX"/>') == 'Left Stick Horizontal')
assert(Icons.Parse('<icon id="Pad_29" table="PS5"/>') == 'Right Stick Vertical')
assert(Icons.Parse('<icon id="Pad_30" table="PS5"/>') == 'Touchpad Horizontal')
print('PASS: menu, view, touchpad and axis glyphs use their native input identities')
assert(Icons.Parse('<icon id="Key_999" table="Windows"/> Action'):find('Key_999',1,true))
print('PASS: an unmapped glyph remains visible for diagnosis instead of disappearing')
