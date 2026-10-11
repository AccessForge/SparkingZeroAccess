-- Read the image actually displayed by the focused language selector.
-- See docs/language-options.md for the native-data evidence behind these names.
local H = require("helpers")
local Languages = {}

local names = {
    jp = "Japanese", en = "English", es = "Spanish (Spain)",
    la = "Spanish (Latin America)", de = "German", fr = "French",
    it = "Italian", ko = "Korean", bp = "Portuguese (Brazil)",
    ru = "Russian", zhcn = "Simplified Chinese", zhtw = "Traditional Chinese",
    pl = "Polish", ar = "Arabic", th = "Thai", id = "Indonesian",
}
local textureNames = {}
for code, name in pairs(names) do
    local asset = "T_UI_Title_LanguageSelect_" .. code
    textureNames["Texture2D /Game/SS/UI/Title/OBJ/Texture/" .. asset .. "." .. asset] = name
end

function Languages.CreateReader(widget)
    if H.GetClassName(widget) ~= "WBP_OBJ_Option_List_013_Lang_C" then return nil end
    local reported = {}
    return function()
        if not H.IsValidRef(widget) or H.TryCall(widget, "IsVisible") == false then return nil end
        -- Resolve from the live row each time: the child may be replaced while
        -- the row retains focus. No global scan, saved setting, or key counting.
        local image = H.TryGetProperty(widget, "IMG_Lang")
        if not H.IsValidRef(image) or H.TryCall(image, "IsVisible") == false then return nil end
        local ok, texture = pcall(function() return image.Brush.ResourceObject end)
        if not ok or not H.IsValidRef(texture) then return nil end
        local path = H.TryCall(texture, "GetFullName")
        if textureNames[path] then return textureNames[path] end
        local diagnostic = tostring(path)
        if not reported[diagnostic] then
            reported[diagnostic] = true
            print("[AE] Unsupported language image: " .. diagnostic)
        end
        return "Language selection unavailable"
    end
end

return Languages
