-- Run from the repository root with Lua 5.4 or LuaJIT.
package.path = "./SparkingZeroAccess/?.lua;" .. package.path

local SkillList = require("skill_list")

-- UE4SS owns these objects in-game; substitute only its object lookup boundary.
local function textBlock(cellType, text)
    return {
        GetFullName = function()
            return "TextBlock /Engine/Transient.Test.WBP_GRP_SL_Main_0_C.WBP_OBJ_SL_Cell_"
                .. cellType .. ".caption"
        end,
        GetText = function()
            return {ToString = function() return text end}
        end,
    }
end

local cases = {
    {
        name = "one cost with line breaks is readable",
        blocks = {textBlock("S", "Ki\n3 bars")},
        cost = "Ki 3 bars",
    },
    {
        name = "multiple costs and description remain separate",
        blocks = {
            textBlock("S", "Ki  3 bars"),
            textBlock("M", "Skill Count\n2"),
            textBlock("XL", "Move behind\nthe opponent."),
        },
        cost = "Ki 3 bars, Skill Count 2",
        description = "Move behind the opponent.",
    },
    {
        name = "description without costs is readable",
        blocks = {textBlock("XL", "Charge your ki.")},
        description = "Charge your ki.",
    },
    {
        name = "empty detail list remains empty",
        blocks = {},
    },
}

for _, case in ipairs(cases) do
    require("helpers").BeginReadCycle()
    FindObjects = function(count, className)
        assert(count == 0)
        assert(className == "TextBlock", "Unexpected UE4SS lookup")
        return case.blocks
    end
    local ok, cost, description = pcall(SkillList.ReadDetails)
    assert(ok, case.name .. ": " .. tostring(cost))
    assert(cost == case.cost, case.name .. ": unexpected cost " .. tostring(cost))
    assert(description == case.description, case.name .. ": unexpected description")
    print("PASS: " .. case.name)
end
