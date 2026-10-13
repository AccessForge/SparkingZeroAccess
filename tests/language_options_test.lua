package.path = "./SparkingZeroAccess/?.lua;" .. package.path

-- Names are grounded in the captured native language entries, not key order.
local Languages = require("language_options")
local failures = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then print("PASS: " .. name)
    else failures = failures + 1; print("FAIL: " .. name .. ": " .. tostring(err)) end
end
local function object(path)
    return {valid = true, visible = true, path = path,
        IsValid = function(self) return self.valid end,
        IsVisible = function(self) return self.visible end,
        GetFullName = function(self) assert(self.valid); return self.path end}
end
local prefix = "Texture2D /Game/SS/UI/Title/OBJ/Texture/T_UI_Title_LanguageSelect_"
local function texture(code)
    return object(prefix .. code .. ".T_UI_Title_LanguageSelect_" .. code)
end
local function row(code)
    local r = object("WBP_OBJ_Option_List_013_Lang_C /Engine/Transient.Screen.WidgetTree.LocalizationTextButton")
    r.IMG_Lang = object("Image /Engine/Transient.Screen.WidgetTree.LocalizationTextButton.WidgetTree.IMG_Lang")
    r.IMG_Lang.Brush = {ResourceObject = texture(code)}
    return r
end

test("all sixteen captured textures have distinct accurate spoken names", function()
    local expected = {jp="Japanese", en="English", es="Spanish (Spain)", la="Spanish (Latin America)",
        de="German", fr="French", it="Italian", ko="Korean", bp="Portuguese (Brazil)", ru="Russian",
        zhcn="Simplified Chinese", zhtw="Traditional Chinese", pl="Polish", ar="Arabic", th="Thai", id="Indonesian"}
    for code, name in pairs(expected) do
        assert(Languages.CreateReader(row(code))() == name, "incorrect language for " .. code)
    end
end)
test("selection is read live without an object scan or key inference", function()
    FindAllOf = function() error("unexpected scan") end
    FindObjects = FindAllOf
    local r = row("en")
    local read = Languages.CreateReader(r)
    assert(read() == "English")
    r.IMG_Lang.Brush.ResourceObject = texture("la")
    assert(read() == "Spanish (Latin America)")
    r.IMG_Lang.Brush.ResourceObject = texture("en")
    assert(read() == "English")
end)
test("replaced image widget is resolved from the focused row", function()
    local r = row("en")
    local read = Languages.CreateReader(r)
    local old = r.IMG_Lang
    r.IMG_Lang = row("jp").IMG_Lang
    old.valid = false
    assert(read() == "Japanese")
end)
test("invalid or hidden widgets are not read", function()
    local r = row("en")
    local read = Languages.CreateReader(r)
    r.IMG_Lang.valid = false
    assert(read() == nil)
    r.IMG_Lang.valid = true; r.IMG_Lang.visible = false
    assert(read() == nil)
    r.IMG_Lang.visible = true; r.valid = false
    assert(read() == nil)
end)
test("unrecognized resources report an unavailable value instead of guessing", function()
    local r = row("unknown")
    local read = Languages.CreateReader(r)
    assert(read() == "Language selection unavailable")
    r.IMG_Lang.Brush.ResourceObject.path = "Texture2D /Game/Other/T_UI_Title_LanguageSelect_en.T_UI_Title_LanguageSelect_en"
    assert(read() == "Language selection unavailable", "unrelated texture falsely identified")
end)
test("other image buttons are not treated as language settings", function()
    local r = row("en")
    r.path = "WBP_Other_C /Engine/Transient.Other"
    assert(Languages.CreateReader(r) == nil)
end)
assert(failures == 0, tostring(failures) .. " language reader regressions")
