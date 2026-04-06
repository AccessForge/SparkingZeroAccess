--[[
    speech.lua — Speech initialization and wrapper functions
    Loads speech_bridge module and provides Speak/SpeakQueued.
]]

local IconParser = require("icon_parser")

local Speech = {}

local speech = nil
local speech_loaded = false

function Speech.Init()
    local success, result = pcall(function()
        return require("speech_bridge")
    end)
    if success and result then
        speech = result
        speech_loaded = true
        print("[AE] Speech bridge loaded!")
    else
        print("[AE] Speech bridge failed: " .. tostring(result))
    end
end

function Speech.IsLoaded()
    return speech_loaded
end

function Speech.Speak(text, interrupt)
    if not speech_loaded or not speech then return end
    if not text or text == "" then return end
    text = IconParser.Parse(text)
    if not text or text == "" then return end
    speech.say(text, interrupt ~= false)
end

function Speech.SpeakQueued(text)
    if not speech_loaded or not speech then return end
    if not text or text == "" then return end
    text = IconParser.Parse(text)
    if not text or text == "" then return end
    speech.say(text, false)
end

return Speech
