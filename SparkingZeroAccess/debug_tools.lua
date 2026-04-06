--[[
    debug_tools.lua — Debug dump utilities for SparkingZeroAccess
    Remove or comment out the require("debug_tools") line in main.lua to disable.

    Keybinds:
        F5 = Toggle continuous debug dump (250ms, change-only)
        F3 = Battle state dump
        F4 = Character select dump

    All dumps go to AE_debug/ folder in the Win64 directory.
]]

local DebugTools = {}

-- === HELPERS ===

local H = require("helpers")
local TryCall = H.TryCall
local TryGetProperty = H.TryGetProperty
local GetWidgetName = H.GetWidgetName
local GetClassName = H.GetClassName

local DUMP_DIR = "AE_debug"

local function WriteDump(filename, content)
    local f = io.open(DUMP_DIR .. "/" .. filename, "w")
    if not f then
        print("[AE-DBG] Error: could not write " .. filename)
        return
    end
    f:write(content)
    f:close()
    print("[AE-DBG] Wrote " .. DUMP_DIR .. "/" .. filename)
end

local function AppendDump(filename, content)
    local f = io.open(DUMP_DIR .. "/" .. filename, "a")
    if not f then
        print("[AE-DBG] Error: could not append " .. filename)
        return
    end
    f:write(content)
    f:close()
end

-- === CONTINUOUS DEBUG DUMP (F5 toggle) ===
-- Combines F5-F8 into a single rolling dump that fires on change.

local _dumpActive = false
local _lastDumpFocus = nil     -- last focused widget name
local _lastDumpClassKey = nil  -- hash of visible class set
local _dumpEntryCount = 0

local function BuildDumpEntry()
    local lines = {}
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")

    -- Find focused widget and all visible widgets in one pass
    local allWidgets = FindAllOf("UserWidget")
    local focused = nil
    local classes = {}
    local classOrder = {}
    local totalVisible = 0

    if allWidgets then
        for _, w in ipairs(allWidgets) do
            local visible = TryCall(w, "IsVisible")
            if visible then
                local ok, fullName = pcall(function() return w:GetFullName() end)
                if ok and fullName:find("Transient") then
                    local className = GetClassName(w)
                    local widgetName = GetWidgetName(w)
                    local hasFocus = TryCall(w, "HasKeyboardFocus")

                    if hasFocus then focused = w end

                    if not classes[className] then
                        classes[className] = {}
                        table.insert(classOrder, className)
                    end
                    table.insert(classes[className], {
                        name = widgetName,
                        focused = hasFocus,
                    })
                    totalVisible = totalVisible + 1
                end
            end
        end
    end

    -- Build change detection key
    local focusName = focused and GetWidgetName(focused) or "(none)"
    local classKey = table.concat(classOrder, "|") .. "#" .. totalVisible

    -- Skip if nothing changed
    if focusName == _lastDumpFocus and classKey == _lastDumpClassKey then
        return nil
    end
    _lastDumpFocus = focusName
    _lastDumpClassKey = classKey

    -- === Header ===
    _dumpEntryCount = _dumpEntryCount + 1
    table.insert(lines, "========== Entry " .. _dumpEntryCount .. " [" .. timestamp .. "] ==========")
    table.insert(lines, "")

    -- === Focused Widget (F8 equivalent) ===
    table.insert(lines, "--- Focused Widget ---")
    if focused then
        table.insert(lines, "Name: " .. GetWidgetName(focused))
        table.insert(lines, "Class: " .. GetClassName(focused))
        table.insert(lines, "Path: " .. focused:GetFullName())

        -- Subtree text
        local focusedInstance = GetWidgetName(focused)
        local foundAny = false
        local allTB = FindAllOf("TextBlock")
        if allTB then
            for _, tb in ipairs(allTB) do
                local ok2, tbPath = pcall(function() return tb:GetFullName() end)
                if ok2 and tbPath:find(focusedInstance, 1, true) then
                    local tbName = GetWidgetName(tb)
                    local ok3, text = pcall(function() return tb:GetText():ToString() end)
                    if ok3 and text and text ~= "" then
                        table.insert(lines, "  TB: " .. tbName .. " = \"" .. text .. "\"")
                        foundAny = true
                    end
                end
            end
        end
        local allRTB = FindAllOf("RichTextBlock")
        if allRTB then
            for _, rb in ipairs(allRTB) do
                local ok2, rbPath = pcall(function() return rb:GetFullName() end)
                if ok2 and rbPath:find(focusedInstance, 1, true) then
                    local rbName = GetWidgetName(rb)
                    local ok3, text = pcall(function() return rb:GetText():ToString() end)
                    if ok3 and text and text ~= "" then
                        table.insert(lines, "  RTB: " .. rbName .. " = \"" .. text .. "\"")
                        foundAny = true
                    end
                end
            end
        end
        if not foundAny then
            table.insert(lines, "  (no text in subtree)")
        end
    else
        table.insert(lines, "(no widget has keyboard focus)")
    end
    table.insert(lines, "")

    -- === Visible Widget Classes (F5 equivalent) ===
    table.insert(lines, "--- Visible Widgets (" .. totalVisible .. " total, " .. #classOrder .. " classes) ---")
    for _, className in ipairs(classOrder) do
        local instances = classes[className]
        table.insert(lines, className .. " (" .. #instances .. ")")
        for _, inst in ipairs(instances) do
            local focusTag = inst.focused and " [FOCUSED]" or ""
            table.insert(lines, "  " .. inst.name .. focusTag)
        end
    end
    table.insert(lines, "")

    -- === All Visible Text (F7 equivalent) ===
    table.insert(lines, "--- All Visible Text ---")
    local textCount = 0

    -- Reuse allTB/allRTB from above if we had a focused widget, otherwise fetch fresh
    local tbList = allTB or FindAllOf("TextBlock")
    if tbList then
        for _, tb in ipairs(tbList) do
            local visible = TryCall(tb, "IsVisible")
            if visible then
                local ok, text = pcall(function() return tb:GetText():ToString() end)
                if ok and text and text ~= "" and text ~= "Text Block" then
                    table.insert(lines, "TB \"" .. text .. "\"")
                    table.insert(lines, "   " .. tb:GetFullName())
                    textCount = textCount + 1
                end
            end
        end
    end

    local rtbList = allRTB or FindAllOf("RichTextBlock")
    if rtbList then
        for _, rb in ipairs(rtbList) do
            local visible = TryCall(rb, "IsVisible")
            if visible then
                local ok, text = pcall(function() return rb:GetText():ToString() end)
                if ok and text and text ~= "" then
                    table.insert(lines, "RTB \"" .. text .. "\"")
                    table.insert(lines, "   " .. rb:GetFullName())
                    textCount = textCount + 1
                end
            end
        end
    end
    table.insert(lines, "(" .. textCount .. " text elements)")
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

local function StartDumpLoop()
    _dumpActive = true
    _lastDumpFocus = nil
    _lastDumpClassKey = nil

    AppendDump("debug_dump.txt", "\n=== Dump Started " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n\n")

    LoopAsync(250, function()
        if not _dumpActive then return true end  -- stop loop
        local ok, entry = pcall(BuildDumpEntry)
        if ok and entry then
            AppendDump("debug_dump.txt", entry)
        end
        return false  -- continue loop
    end)
end

local function StopDumpLoop()
    _dumpActive = false
    AppendDump("debug_dump.txt", "=== Dump Stopped " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
end

-- === F4: CHARA SELECT — TEXTURE ID + DATATABLE SEARCH ===

local function DumpCharaSelectInfo()
    local lines = {}
    table.insert(lines, "=== Character Select: Texture IDs + DataTable Search ===")
    table.insert(lines, "Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(lines, "")

    -- === 1. Read IMG_Face_Main texture per team slot (compact) ===
    table.insert(lines, "--- Team Slot Textures (1P, IMG_Face_Main) ---")
    local images = FindAllOf("Image")
    if images then
        for slotIdx = 0, 4 do
            local iconName = "WBP_OBJ_BS_CharaIcon_" .. slotIdx
            local found = false
            for _, img in ipairs(images) do
                local ok, imgPath = pcall(function() return img:GetFullName() end)
                if ok and imgPath:find(iconName, 1, true)
                   and imgPath:find("Top_00_1P", 1, true)
                   and imgPath:find("Transient", 1, true) then
                    local imgWidgetName = GetWidgetName(img)
                    if imgWidgetName == "IMG_Face_Main" then
                        found = true
                        -- Try Brush.ResourceObject
                        local texInfo = "(no texture)"
                        local brushKeys = {"Brush", "brush"}
                        for _, bk in ipairs(brushKeys) do
                            local ok2, texName = pcall(function()
                                local brush = img[bk]
                                if not brush then return nil end
                                local res = brush.ResourceObject
                                if not res then return nil end
                                return res:GetFullName()
                            end)
                            if ok2 and texName then
                                texInfo = texName
                                break
                            end
                        end
                        table.insert(lines, "Slot " .. (slotIdx+1) .. ": " .. texInfo)
                        break
                    end
                end
            end
            if not found then
                table.insert(lines, "Slot " .. (slotIdx+1) .. ": (IMG_Face_Main not found)")
            end
        end
    else
        table.insert(lines, "(no Image widgets found)")
    end
    WriteDump("chara_select.txt", table.concat(lines, "\n"))

    -- === 2. DataTable search — find character data tables ===
    table.insert(lines, "")
    table.insert(lines, "--- DataTable Search ---")
    local dtClasses = {"DataTable", "UDataTable"}
    for _, dtClass in ipairs(dtClasses) do
        local dts = FindAllOf(dtClass)
        if dts then
            table.insert(lines, dtClass .. " instances: " .. #dts)
            for _, dt in ipairs(dts) do
                local ok, dtPath = pcall(function() return dt:GetFullName() end)
                if ok then
                    -- Log ALL data tables, filter for interesting ones
                    local isChara = dtPath:find("Chara", 1, true)
                        or dtPath:find("chara", 1, true)
                        or dtPath:find("Character", 1, true)
                        or dtPath:find("Battle", 1, true)
                        or dtPath:find("Param", 1, true)
                        or dtPath:find("Name", 1, true)
                        or dtPath:find("Icon", 1, true)
                        or dtPath:find("Thumb", 1, true)
                        or dtPath:find("ID", 1, true)
                    if isChara then
                        table.insert(lines, "  [MATCH] " .. dtPath)
                    end
                end
            end
            -- Also log first 20 paths regardless of filter
            table.insert(lines, "")
            table.insert(lines, "  First 50 DataTable paths:")
            local count = 0
            for _, dt in ipairs(dts) do
                if count >= 50 then break end
                local ok, dtPath = pcall(function() return dt:GetFullName() end)
                if ok then
                    table.insert(lines, "  " .. dtPath)
                    count = count + 1
                end
            end
            if #dts > 50 then
                table.insert(lines, "  ... and " .. (#dts - 50) .. " more")
            end
        else
            table.insert(lines, dtClass .. ": not found")
        end
    end
    WriteDump("chara_select.txt", table.concat(lines, "\n"))

    -- === 3. Inspect SSCharacterDataAsset properties ===
    table.insert(lines, "")
    table.insert(lines, "--- SSCharacterDataAsset Deep Inspect (first 3) ---")
    local charaAssets = FindAllOf("SSCharacterDataAsset")
    if charaAssets then
        table.insert(lines, "Total: " .. #charaAssets)
        -- Inspect first 3 assets to find readable properties
        for i = 1, math.min(3, #charaAssets) do
            local asset = charaAssets[i]
            local ok, assetPath = pcall(function() return asset:GetFullName() end)
            if ok then
                table.insert(lines, "")
                table.insert(lines, "[" .. i .. "] " .. assetPath)
                -- Try common name/ID properties
                local nameProps = {
                    "CharacterName", "CharaName", "DisplayName", "Name",
                    "CharacterID", "CharaID", "ID", "CharaId",
                    "NameText", "NameLabel", "Label",
                    "ShortName", "FullName_", "Title",
                    "ThumbnailID", "ThumbID", "IconID",
                    "BattleName", "SelectName",
                    "DP", "DPCost", "Cost",
                }
                for _, prop in ipairs(nameProps) do
                    local ok2, val = pcall(function() return asset[prop] end)
                    if ok2 and val ~= nil then
                        local info = "type=" .. type(val) .. " tostring=" .. tostring(val)
                        -- Try ToString
                        local ok3, s3 = pcall(function() return val:ToString() end)
                        if ok3 and s3 then info = info .. " ToString=\"" .. s3 .. "\"" end
                        -- Try GetText
                        local ok4, s4 = pcall(function() return val:GetText():ToString() end)
                        if ok4 and s4 then info = info .. " GetText=\"" .. s4 .. "\"" end
                        -- Try GetFullName
                        local ok5, s5 = pcall(function() return val:GetFullName() end)
                        if ok5 and s5 then info = info .. " FullName=" .. s5 end
                        -- Check if it's a number
                        if type(val) == "number" then info = "number=" .. val end
                        if type(val) == "string" then info = "string=\"" .. val .. "\"" end
                        if type(val) == "boolean" then info = "bool=" .. tostring(val) end
                        table.insert(lines, "  " .. prop .. " = " .. info)
                    end
                end
            end
        end

        -- === 4. List ALL SSCharacterDataAsset paths (for ID mapping) ===
        table.insert(lines, "")
        table.insert(lines, "--- ALL SSCharacterDataAsset paths ---")
        for _, asset in ipairs(charaAssets) do
            local ok, path = pcall(function() return asset:GetFullName() end)
            if ok then
                -- Extract just the asset name
                local assetName = path:match("([^%.]+)$") or path
                table.insert(lines, assetName)
            end
        end
    else
        table.insert(lines, "SSCharacterDataAsset: not found")
    end

    -- === 5. Look for assets matching our texture IDs ===
    table.insert(lines, "")
    table.insert(lines, "--- StaticFindObject: texture ID probes ---")
    local probeIds = {"0000_00", "0000_10", "0020_00", "0030_00", "0050_00"}
    for _, cid in ipairs(probeIds) do
        local probePaths = {
            "/Game/SS/MasterDataAsset/CharacterData/CharacterData_" .. cid,
            "/Game/SS/MasterDataAsset/CharacterData/CharacterData_" .. cid .. ".CharacterData_" .. cid,
        }
        for _, path in ipairs(probePaths) do
            local ok, obj = pcall(function() return StaticFindObject(path) end)
            if ok and obj then
                table.insert(lines, "FOUND: " .. path)
                -- Try reading name from it
                local nameProps2 = {"CharacterName", "CharaName", "DisplayName", "Name"}
                for _, np in ipairs(nameProps2) do
                    local ok2, val = pcall(function() return obj[np] end)
                    if ok2 and val then
                        local ok3, s = pcall(function() return val:ToString() end)
                        if ok3 and s then
                            table.insert(lines, "  " .. np .. " = \"" .. s .. "\"")
                        end
                    end
                end
            end
        end
    end

    WriteDump("chara_select.txt", table.concat(lines, "\n"))

    -- === 6. DP VALUE PROBE ===
    -- Search for any TextBlock/RichTextBlock with numeric content in the 1P panel
    -- Also check Img_DPNum material parameters for numeric values
    table.insert(lines, "")
    table.insert(lines, "--- DP Value Probe ---")

    -- 6a. ALL TextBlocks inside Top_00_1P (not just visible — hidden ones might have DP)
    table.insert(lines, "All TextBlocks in Top_00_1P:")
    local allTB = FindAllOf("TextBlock")
    if allTB then
        for _, tb in ipairs(allTB) do
            local ok, tbPath = pcall(function() return tb:GetFullName() end)
            if ok and tbPath:find("Top_00_1P", 1, true) and tbPath:find("Transient", 1, true) then
                local tbName = GetWidgetName(tb)
                local ok2, text = pcall(function() return tb:GetText():ToString() end)
                local vis = TryCall(tb, "IsVisible")
                local textStr = (ok2 and text) or "(error)"
                table.insert(lines, "  " .. tbName .. " = \"" .. textStr .. "\" visible=" .. tostring(vis))
            end
        end
    end

    -- 6b. Check Img_DPNum MaterialInstanceDynamic for scalar/vector parameters
    table.insert(lines, "")
    table.insert(lines, "Img_DPNum material parameter probe (CharaIcon_0 and _1):")
    local mats = FindAllOf("MaterialInstanceDynamic")
    if mats then
        for _, mat in ipairs(mats) do
            local ok, matPath = pcall(function() return mat:GetFullName() end)
            if ok and matPath:find("Img_DPNum", 1, true)
               and matPath:find("Top_00_1P", 1, true) then
                table.insert(lines, "  " .. matPath)
                -- Try reading scalar parameters
                local scalarNames = {"Value", "Number", "DP", "Num", "Digit",
                    "Param", "Amount", "Count", "DPValue", "NumValue",
                    "Hundreds", "Tens", "Ones", "Digit0", "Digit1", "Digit2"}
                for _, sn in ipairs(scalarNames) do
                    local ok2, val = pcall(function() return mat[sn] end)
                    if ok2 and val ~= nil then
                        local info = "type=" .. type(val)
                        if type(val) == "number" then info = info .. " value=" .. val end
                        if type(val) == "boolean" then info = info .. " value=" .. tostring(val) end
                        local ok3, s = pcall(function() return val:ToString() end)
                        if ok3 and s then info = info .. " ToString=\"" .. s .. "\"" end
                        table.insert(lines, "    " .. sn .. " = " .. info)
                    end
                end
            end
        end
    end

    -- 6c. Search for ANY widget class with "DP" in name
    table.insert(lines, "")
    table.insert(lines, "Widget classes containing 'DP' in Top_00_1P:")
    local allWidgets = FindAllOf("UserWidget")
    if allWidgets then
        for _, w in ipairs(allWidgets) do
            local ok, wPath = pcall(function() return w:GetFullName() end)
            if ok and wPath:find("Top_00_1P", 1, true) and wPath:find("Transient", 1, true) then
                local wName = GetWidgetName(w)
                if wName:find("DP", 1, true) or wName:find("dp", 1, true) then
                    table.insert(lines, "  " .. GetClassName(w) .. " : " .. wName)
                    table.insert(lines, "    " .. wPath)
                end
            end
        end
    end

    -- 6d. Check the BtnSet panel for DP-related text (Total DP values)
    table.insert(lines, "")
    table.insert(lines, "All TextBlocks in Top_00_BtnSet:")
    if allTB then
        for _, tb in ipairs(allTB) do
            local ok, tbPath = pcall(function() return tb:GetFullName() end)
            if ok and tbPath:find("BtnSet", 1, true) and tbPath:find("Transient", 1, true) then
                local tbName = GetWidgetName(tb)
                local ok2, text = pcall(function() return tb:GetText():ToString() end)
                local textStr = (ok2 and text) or "(error)"
                table.insert(lines, "  " .. tbName .. " = \"" .. textStr .. "\"")
            end
        end
    end

    -- 6e. Search ALL visible TextBlocks for anything that looks like a number (DP value)
    table.insert(lines, "")
    table.insert(lines, "All TextBlocks with numeric content (possible DP values):")
    if allTB then
        for _, tb in ipairs(allTB) do
            local ok, tbPath = pcall(function() return tb:GetFullName() end)
            if ok and tbPath:find("Transient", 1, true)
               and not tbPath:find("Debug", 1, true)
               and not tbPath:find("Notification", 1, true) then
                local ok2, text = pcall(function() return tb:GetText():ToString() end)
                if ok2 and text and text:match("^%d+$") then
                    local tbName = GetWidgetName(tb)
                    table.insert(lines, "  " .. tbName .. " = \"" .. text .. "\" path=" .. tbPath)
                end
            end
        end
    end

    -- === 7. SSCharacterDataAsset DP extraction attempts ===
    table.insert(lines, "")
    table.insert(lines, "--- SSCharacterDataAsset DP Extraction (3 known characters) ---")
    -- Try multiple UE4SS APIs to read properties from known character data assets
    local testIds = {"0000_00", "0920_01", "0030_00"} -- Goku Z-Early, Kefla SSJ, Gohan Kid
    for _, cid in ipairs(testIds) do
        local assetPath = "/Game/SS/MasterDataAsset/CharacterData/CharacterData_" .. cid .. ".CharacterData_" .. cid
        local ok, asset = pcall(function() return StaticFindObject(assetPath) end)
        if ok and asset then
            table.insert(lines, "")
            table.insert(lines, "CharacterData_" .. cid .. ":")

            -- Method 1: Iterate reflected properties using ForEachProperty (if available)
            local ok1, err1 = pcall(function()
                local propCount = 0
                asset:ForEachProperty(function(prop)
                    propCount = propCount + 1
                    local propName = prop:GetFName():ToString()
                    local propType = prop:GetClass():GetFName():ToString()
                    local entry = "  [prop] " .. propName .. " type=" .. propType

                    -- Try to read value based on type
                    if propType == "IntProperty" or propType == "Int32Property"
                       or propType == "FloatProperty" or propType == "DoubleProperty" then
                        local ok2, val = pcall(function()
                            return prop:ContainerPtrToValuePtr(asset):get()
                        end)
                        if ok2 then entry = entry .. " value=" .. tostring(val) end
                    elseif propType == "StrProperty" or propType == "NameProperty" then
                        local ok2, val = pcall(function()
                            return prop:ContainerPtrToValuePtr(asset):get():ToString()
                        end)
                        if ok2 and val then entry = entry .. " value=\"" .. val .. "\"" end
                    elseif propType == "TextProperty" then
                        local ok2, val = pcall(function()
                            return prop:ContainerPtrToValuePtr(asset):get():ToString()
                        end)
                        if ok2 and val then entry = entry .. " value=\"" .. val .. "\"" end
                    end

                    table.insert(lines, entry)
                end)
                table.insert(lines, "  Total properties: " .. propCount)
            end)
            if not ok1 then
                table.insert(lines, "  ForEachProperty failed: " .. tostring(err1))
            end

            -- Method 2: Try GetPropertyValue (UE4SS custom API)
            local dpProps = {"DP", "DPCost", "Cost", "BattlePoint", "Point",
                "CharacterName", "ID", "CharaID"}
            for _, dp in ipairs(dpProps) do
                -- Try :GetPropertyValue(name)
                local ok3, val3 = pcall(function()
                    return asset:GetPropertyValue(dp)
                end)
                if ok3 and val3 ~= nil then
                    local info = "type=" .. type(val3)
                    if type(val3) == "number" then info = info .. " value=" .. val3 end
                    if type(val3) == "string" then info = info .. " value=\"" .. val3 .. "\"" end
                    if type(val3) == "boolean" then info = info .. " value=" .. tostring(val3) end
                    local ok4, s = pcall(function() return val3:ToString() end)
                    if ok4 and s then info = info .. " ToString=\"" .. s .. "\"" end
                    table.insert(lines, "  GetPropertyValue(\"" .. dp .. "\") = " .. info)
                end

                -- Try :GetKismetPropertyValue(name)
                local ok5, val5 = pcall(function()
                    return asset:GetKismetPropertyValue(dp)
                end)
                if ok5 and val5 ~= nil then
                    local info = "type=" .. type(val5)
                    if type(val5) == "number" then info = info .. " value=" .. val5 end
                    if type(val5) == "string" then info = info .. " value=\"" .. val5 .. "\"" end
                    table.insert(lines, "  GetKismetPropertyValue(\"" .. dp .. "\") = " .. info)
                end
            end

            -- Method 3: Try member function approach
            local ok6, val6 = pcall(function()
                return asset:GetDP()
            end)
            if ok6 and val6 then
                table.insert(lines, "  GetDP() = " .. tostring(val6))
            end
            local ok7, val7 = pcall(function()
                return asset:GetDPCost()
            end)
            if ok7 and val7 then
                table.insert(lines, "  GetDPCost() = " .. tostring(val7))
            end
        else
            table.insert(lines, "CharacterData_" .. cid .. ": not found")
        end
    end

    WriteDump("chara_select.txt", table.concat(lines, "\n"))
end

-- === F3: BATTLE HUD — HP & KI GAUGE EXPLORATION (appends) ===

local function ProbeProperties(obj, propNames)
    local results = {}
    for _, prop in ipairs(propNames) do
        local ok, val = pcall(function() return obj[prop] end)
        if ok and val ~= nil then
            local display = tostring(val)
            -- Try to get numeric value
            if type(val) == "userdata" then
                -- Try common value accessors
                for _, method in ipairs({"GetValue", "GetCurrentValue", "GetPercent",
                    "GetFillPercent", "ToString", "GetFloat", "GetInt"}) do
                    local mok, mval = pcall(function()
                        local fn = val[method]
                        if fn then return fn(val) end
                        return nil
                    end)
                    if mok and mval ~= nil then
                        display = display .. " -> " .. method .. "()=" .. tostring(mval)
                    end
                end
                -- Try GetFullName for UObject identification
                local nok, fname = pcall(function() return val:GetFullName() end)
                if nok and fname then
                    display = display .. " [" .. fname:sub(1, 120) .. "]"
                end
            end
            table.insert(results, "  " .. prop .. " = " .. display)
        end
    end
    return results
end

local function DumpBattleGauges()
    local lines = {}
    table.insert(lines, "--- Battle Gauge Snapshot " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---")

    -- Common gauge property names to probe
    local gaugeProps = {
        "Percent", "percent", "FillPercent", "fillPercent",
        "CurrentValue", "currentValue", "Value", "value",
        "MaxValue", "maxValue", "MinValue",
        "CurrentHP", "currentHP", "HP", "hp", "Health", "health",
        "MaxHP", "maxHP",
        "Ratio", "ratio", "Rate", "rate",
        "GaugePercent", "gaugePercent",
        "BarPercent", "barPercent",
        "FillAmount", "fillAmount",
        "Progress", "progress",
        "CurrentKi", "Ki", "ki", "Energy", "energy",
        "SpGauge", "spGauge", "SpecialGauge",
        "StockNum", "stockNum", "StockCount",
        "CharaNum", "charaNum",
        "bIsActive", "bIsVisible",
        "Gauge", "gauge", "GaugeValue",
        "Material", "DynamicMaterial",
        "Img_Gauge", "IMG_Gauge", "img_gauge",
        "Img_GaugeColor", "IMG_GaugeColor",
        "GaugeImage", "gaugeImage",
        "ProgressBar", "progressBar",
    }

    -- === HP GAUGES ===
    for _, playerTag in ipairs({"P1", "P2"}) do
        local className = "WBP_OBJ_HpGauge_" .. playerTag .. "_C"
        table.insert(lines, "")
        table.insert(lines, "=== " .. className .. " ===")
        local widget = FindFirstOf(className)
        if widget then
            local ok, path = pcall(function() return widget:GetFullName() end)
            if ok then table.insert(lines, "Path: " .. path) end

            local props = ProbeProperties(widget, gaugeProps)
            if #props > 0 then
                for _, p in ipairs(props) do table.insert(lines, p) end
            else
                table.insert(lines, "  (no matching properties found)")
            end

            -- Try to get children
            local cok, childCount = pcall(function() return widget:GetChildrenCount() end)
            if cok and childCount and childCount > 0 then
                table.insert(lines, "  Children: " .. childCount)
                for i = 0, math.min(childCount - 1, 15) do
                    local child = TryCall(widget, "GetChildAt", i)
                    if child then
                        local cn = GetClassName(child)
                        local cname = GetWidgetName(child)
                        local entry = "    [" .. i .. "] " .. cn .. " : " .. cname
                        -- Probe child for gauge values too
                        local childProps = ProbeProperties(child, gaugeProps)
                        for _, cp in ipairs(childProps) do
                            entry = entry .. "\n      " .. cp:sub(3)
                        end
                        table.insert(lines, entry)
                    end
                end
            end
        else
            table.insert(lines, "  (not found)")
        end
    end

    -- === HP STOCK ===
    table.insert(lines, "")
    table.insert(lines, "=== HP Stock (WBP_Rep_HpStock_C) ===")
    local hpStocks = FindAllOf("WBP_Rep_HpStock_C")
    if hpStocks then
        local count = 0
        for _, stock in ipairs(hpStocks) do
            local ok, path = pcall(function() return stock:GetFullName() end)
            if ok and path:find("Transient", 1, true) then
                local visible = TryCall(stock, "IsVisible")
                local name = GetWidgetName(stock)
                local opacity = TryCall(stock, "GetRenderOpacity")
                table.insert(lines, "  " .. name .. " visible=" .. tostring(visible) .. " opacity=" .. tostring(opacity))
                count = count + 1
                if count >= 14 then break end
            end
        end
    else
        table.insert(lines, "  (not found)")
    end

    -- === KI / SPECIAL GAUGE ===
    for _, playerTag in ipairs({"P1", "P2"}) do
        local className = "WBP_GRP_SpGauge_" .. playerTag .. "_C"
        table.insert(lines, "")
        table.insert(lines, "=== " .. className .. " ===")
        local widget = FindFirstOf(className)
        if widget then
            local ok, path = pcall(function() return widget:GetFullName() end)
            if ok then table.insert(lines, "Path: " .. path) end

            local props = ProbeProperties(widget, gaugeProps)
            if #props > 0 then
                for _, p in ipairs(props) do table.insert(lines, p) end
            else
                table.insert(lines, "  (no matching properties found)")
            end

            -- Children
            local cok, childCount = pcall(function() return widget:GetChildrenCount() end)
            if cok and childCount and childCount > 0 then
                table.insert(lines, "  Children: " .. childCount)
                for i = 0, math.min(childCount - 1, 15) do
                    local child = TryCall(widget, "GetChildAt", i)
                    if child then
                        local cn = GetClassName(child)
                        local cname = GetWidgetName(child)
                        local entry = "    [" .. i .. "] " .. cn .. " : " .. cname
                        local childProps = ProbeProperties(child, gaugeProps)
                        for _, cp in ipairs(childProps) do
                            entry = entry .. "\n      " .. cp:sub(3)
                        end
                        table.insert(lines, entry)
                    end
                end
            end
        else
            table.insert(lines, "  (not found)")
        end
    end

    -- === KI GAUGE PARTS (individual segments) ===
    table.insert(lines, "")
    table.insert(lines, "=== SpGaugeParts (WBP_OBJ_SpGaugePartsSet_C) ===")
    local kiParts = FindAllOf("WBP_OBJ_SpGaugePartsSet_C")
    if kiParts then
        local count = 0
        for _, part in ipairs(kiParts) do
            local ok, path = pcall(function() return part:GetFullName() end)
            if ok and path:find("Transient", 1, true) then
                local name = GetWidgetName(part)
                local visible = TryCall(part, "IsVisible")
                local opacity = TryCall(part, "GetRenderOpacity")
                local entry = "  " .. name .. " visible=" .. tostring(visible) .. " opacity=" .. tostring(opacity)
                -- Probe each part
                local partProps = ProbeProperties(part, gaugeProps)
                for _, pp in ipairs(partProps) do
                    entry = entry .. "\n    " .. pp:sub(3)
                end
                table.insert(lines, entry)
                count = count + 1
                if count >= 10 then break end
            end
        end
    else
        table.insert(lines, "  (not found)")
    end

    -- === KING GAUGE (burst gauge) ===
    for _, playerTag in ipairs({"P1", "P2"}) do
        local className = "WBP_OBJ_KingGauge_" .. playerTag .. "_C"
        local widget = FindFirstOf(className)
        if widget then
            table.insert(lines, "")
            table.insert(lines, "=== " .. className .. " ===")
            local props = ProbeProperties(widget, gaugeProps)
            if #props > 0 then
                for _, p in ipairs(props) do table.insert(lines, p) end
            else
                table.insert(lines, "  (no matching properties found)")
            end
        end
    end

    -- === CHARACTER STOCK NUMBERS ===
    table.insert(lines, "")
    table.insert(lines, "=== Character Stock Numbers ===")
    local textBlocks = FindAllOf("TextBlock")
    if textBlocks then
        for _, tb in ipairs(textBlocks) do
            local ok, tbPath = pcall(function() return tb:GetFullName() end)
            if ok and tbPath:find("StyleIcon_Timer", 1, true) and tbPath:find("Transient", 1, true) then
                local name = GetWidgetName(tb)
                if name == "CharaNum" then
                    local ok2, text = pcall(function() return tb:GetText():ToString() end)
                    local player = tbPath:find("_P1_") and "P1" or "P2"
                    table.insert(lines, "  " .. player .. " CharaNum = " .. (ok2 and text or "?"))
                end
            end
        end
    end

    table.insert(lines, "")
    AppendDump("battle_gauges.txt", table.concat(lines, "\n") .. "\n")
end

-- === F2: BATTLE GAME STATE — HP/KI FROM GAME LOGIC (appends) ===

local function ProbeObject(obj, label, propNames)
    local lines = {}
    table.insert(lines, label)
    local ok, path = pcall(function() return obj:GetFullName() end)
    if ok then table.insert(lines, "  Path: " .. path) end
    local cls = GetClassName(obj)
    table.insert(lines, "  Class: " .. cls)

    for _, prop in ipairs(propNames) do
        local pok, val = pcall(function() return obj[prop] end)
        if pok and val ~= nil then
            local display = tostring(val)
            if type(val) == "number" then
                display = tostring(val)
            elseif type(val) == "boolean" then
                display = tostring(val)
            elseif type(val) == "userdata" then
                -- Try numeric conversions
                for _, method in ipairs({"GetFloat", "GetInt", "GetValue", "ToString"}) do
                    local mok, mval = pcall(function()
                        local fn = val[method]
                        if fn then return fn(val) end
                        return nil
                    end)
                    if mok and mval ~= nil then
                        display = display .. " -> " .. method .. "()=" .. tostring(mval)
                    end
                end
                -- Try GetFullName for identification
                local nok, fname = pcall(function() return val:GetFullName() end)
                if nok and fname then
                    display = display .. " [" .. fname:sub(1, 100) .. "]"
                end
            end
            table.insert(lines, "  " .. prop .. " = " .. display)
        end
    end
    return lines
end

-- === OBJECT DUMPER (from ConsoleCommandsMod/dump_object.lua) ===

local UClassStaticClass = StaticFindObject("/Script/CoreUObject.Class")
local UScriptStructStaticClass = StaticFindObject("/Script/CoreUObject.ScriptStruct")

local function SafeIsA(Property, TypeKey)
    if not TypeKey then return false end
    local ok, result = pcall(function() return Property:IsA(TypeKey) end)
    return ok and result
end

local function DumpPropertyWithinObject(Object, Property)
    local PropName = Property:GetFName():ToString()
    local ValueStr = ""

    -- Try type-specific reading
    if SafeIsA(Property, PropertyTypes.Int8Property) or SafeIsA(Property, PropertyTypes.Int16Property)
       or SafeIsA(Property, PropertyTypes.IntProperty) or SafeIsA(Property, PropertyTypes.Int64Property)
       or SafeIsA(Property, PropertyTypes.ByteProperty) then
        local ok, Value = pcall(function() return Object[PropName] end)
        ValueStr = ok and string.format("%s", Value) or "?"
    elseif SafeIsA(Property, PropertyTypes.FloatProperty) or SafeIsA(Property, PropertyTypes.DoubleProperty) then
        local ok, Value = pcall(function() return Object[PropName] end)
        ValueStr = ok and string.format("%s", Value) or "?"
    elseif SafeIsA(Property, PropertyTypes.BoolProperty) then
        local ok, Value = pcall(function() return Object[PropName] end)
        ValueStr = ok and (Value and "True" or "False") or "?"
    elseif SafeIsA(Property, PropertyTypes.NameProperty) or SafeIsA(Property, PropertyTypes.StrProperty)
        or SafeIsA(Property, PropertyTypes.TextProperty) then
        local ok, Value = pcall(function() return Object[PropName]:ToString() end)
        ValueStr = ok and Value or "?"
    elseif SafeIsA(Property, PropertyTypes.EnumProperty) then
        local ok, Value = pcall(function()
            local v = Object[PropName]
            return string.format("%s(%s)", Property:GetEnum():GetNameByValue(v):ToString(), v)
        end)
        ValueStr = ok and Value or "?"
    elseif SafeIsA(Property, PropertyTypes.ObjectProperty) then
        local ok, Value = pcall(function() return Object[PropName]:GetFullName() end)
        ValueStr = ok and Value:sub(1, 120) or "?"
    elseif SafeIsA(Property, PropertyTypes.StructProperty) then
        local ok, Value = pcall(function() return Object[PropName]:GetFullName() end)
        ValueStr = ok and Value:sub(1, 120) or "(struct)"
    elseif SafeIsA(Property, PropertyTypes.ArrayProperty) then
        local ok, Value = pcall(function()
            local arr = Object[PropName]
            return string.format("Array[%d]", arr:GetArrayNum())
        end)
        ValueStr = ok and Value or "Array[?]"
    else
        -- Fallback: try raw read for unhandled types (DoubleProperty, etc.)
        local ok, Value = pcall(function() return Object[PropName] end)
        if ok and Value ~= nil then
            if type(Value) == "number" or type(Value) == "boolean" then
                ValueStr = tostring(Value)
            elseif type(Value) == "string" then
                ValueStr = Value
            else
                local fnOk, fn = pcall(function() return Value:GetFullName() end)
                ValueStr = fnOk and fn:sub(1, 80) or tostring(Value)
            end
        else
            ValueStr = "?"
        end
    end

    local offset = 0
    pcall(function() offset = Property:GetOffset_Internal() end)
    local typeName = "?"
    pcall(function() typeName = Property:GetClass():GetFName():ToString() end)
    return string.format("0x%04X %s %s = %s", offset, typeName, PropName, ValueStr)
end

local function DumpObjectToLines(Object, lines)
    local clsOk, ObjectClass = pcall(function() return Object:GetClass() end)
    if not clsOk or not ObjectClass then
        table.insert(lines, "  (could not get class)")
        return
    end
    while ObjectClass and ObjectClass:IsValid() do
        local nameOk, clsName = pcall(function() return ObjectClass:GetFullName() end)
        table.insert(lines, string.format("=== %s ===", nameOk and clsName or "?"))
        pcall(function()
            ObjectClass:ForEachProperty(function(Property)
                local ok, line = pcall(DumpPropertyWithinObject, Object, Property)
                if ok and type(line) == "string" then
                    table.insert(lines, "  " .. line)
                else
                    -- Still show name, type, and offset for errored properties
                    local pname = "?"
                    local ptype = "?"
                    local poffset = "????"
                    pcall(function() pname = Property:GetFName():ToString() end)
                    pcall(function() ptype = Property:GetClass():GetFName():ToString() end)
                    pcall(function() poffset = string.format("0x%04X", Property:GetOffset_Internal()) end)
                    table.insert(lines, "  " .. poffset .. " " .. ptype .. " " .. pname .. " = (error)")
                end
            end)
        end)
        local superOk, super = pcall(function() return ObjectClass:GetSuperStruct() end)
        if superOk and super and super:IsValid() then
            ObjectClass = super
        else
            break
        end
    end
end

local function DumpBattleGameState()
    local lines = {}
    table.insert(lines, "--- Battle Game State " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---")

    -- Get player's active pawn
    local pc = FindFirstOf("BP_BattlePlayerController_C")
    if not pc then
        table.insert(lines, "(not in battle)")
        AppendDump("battle_state.txt", table.concat(lines, "\n") .. "\n")
        return
    end

    local pawn = pc.Pawn
    local pawnPath = "(none)"
    pcall(function() pawnPath = pawn:GetFullName() end)
    table.insert(lines, "Player Pawn: " .. pawnPath)
    table.insert(lines, "")

    -- Full dump of player pawn (entire class hierarchy)
    DumpObjectToLines(pawn, lines)

    -- Dump game state (for timer, round info, etc.)
    table.insert(lines, "")
    table.insert(lines, "=== Battle Game State Object ===")
    local gsOk, gs = pcall(FindFirstOf, "BP_BattleGameStateBase_C")
    if gsOk and gs then
        local gsPath = "?"
        pcall(function() gsPath = gs:GetFullName() end)
        table.insert(lines, "Path: " .. gsPath)
        pcall(DumpObjectToLines, gs, lines)
    else
        table.insert(lines, "  (not found)")
    end

    -- Pawn summary
    table.insert(lines, "")
    table.insert(lines, "=== All Battle Pawns (summary) ===")
    local allPawns = FindAllOf("Pawn")
    if allPawns then
        for _, p in ipairs(allPawns) do
            local pok, path = pcall(function() return p:GetFullName() end)
            if pok and path and not path:find("/Script/") then
                local sgOk, sg = pcall(function() return p.SpGaugeValue end)
                local bsOk, bs = pcall(function() return p.BattleState end)
                local sgStr = sgOk and type(sg) == "number" and (" SpGauge=" .. sg) or ""
                local bsStr = bsOk and type(bs) == "number" and (" BattleState=" .. bs) or ""
                table.insert(lines, "  " .. path:sub(1, 100) .. sgStr .. bsStr)
            end
        end
    end

    -- Write main dump before attempting identification debug
    AppendDump("battle_state.txt", table.concat(lines, "\n") .. "\n")
    lines = {}

    -- === PAWN IDENTIFICATION DEBUG ===
    table.insert(lines, "=== Pawn Identification Debug ===")

    -- Safe name getter that never returns nil
    local function SafeName(obj)
        if not obj then return "nil" end
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name then return name:sub(1, 120) end
        return "?"
    end

    if allPawns then
        for _, p in ipairs(allPawns) do
            local path = SafeName(p)
            if path:find("BPCHR_") and not path:find("DESTROYED") then
                table.insert(lines, "")
                table.insert(lines, "--- " .. path .. " ---")

                -- UE networking properties
                local roleOk, role = pcall(function() return p.Role end)
                table.insert(lines, "  Role = " .. (roleOk and tostring(role) or "err"))
                local remOk, rem = pcall(function() return p.RemoteRole end)
                table.insert(lines, "  RemoteRole = " .. (remOk and tostring(rem) or "err"))

                -- UE methods
                local methods = {"IsLocallyControlled", "IsPlayerControlled", "HasAuthority", "IsLocallyViewed"}
                for _, m in ipairs(methods) do
                    local mok, mval = pcall(function() return p[m](p) end)
                    table.insert(lines, "  " .. m .. "() = " .. (mok and tostring(mval) or "err"))
                end

                -- Controller identity
                local cok, ctrl = pcall(function() return p.Controller end)
                if cok and ctrl then
                    table.insert(lines, "  Controller = " .. SafeName(ctrl))
                    local lcOk, lc = pcall(function() return ctrl.IsLocalController(ctrl) end)
                    table.insert(lines, "  Controller:IsLocalController() = " .. (lcOk and tostring(lc) or "err"))
                    local lpcOk, lpc = pcall(function() return ctrl.IsLocalPlayerController(ctrl) end)
                    table.insert(lines, "  Controller:IsLocalPlayerController() = " .. (lpcOk and tostring(lpc) or "err"))
                    table.insert(lines, "  Controller.Pawn = " .. SafeName(pcall(function() return ctrl.Pawn end) and ctrl.Pawn or nil))
                else
                    table.insert(lines, "  Controller = (none)")
                end

                -- PlayerState
                local psOk, ps = pcall(function() return p.PlayerState end)
                if psOk and ps then
                    table.insert(lines, "  PlayerState = " .. SafeName(ps))
                    local pidOk, pid = pcall(function() return ps.PlayerId end)
                    table.insert(lines, "  PlayerState.PlayerId = " .. (pidOk and tostring(pid) or "err"))
                    local compOk, comp = pcall(function() return ps.CompressedPing end)
                    table.insert(lines, "  PlayerState.CompressedPing = " .. (compOk and tostring(comp) or "err"))
                else
                    table.insert(lines, "  PlayerState = (none)")
                end

                -- TargetPawn
                local tpOk, tp = pcall(function() return p.TargetPawn end)
                table.insert(lines, "  TargetPawn = " .. SafeName(tpOk and tp or nil))

                -- Game-specific identification properties
                local idProps = {
                    "StartPlayerControllerID", "bIsLocalViewTarget",
                    "PlayerSide", "BattleSide", "SideIndex", "TeamIndex",
                    "PlayerIndex", "CharacterIndex", "OwnerIndex",
                    "bIsPlayer1", "bIsPlayer2", "bIsLocalPlayer",
                    "bIsMyCharacter", "bIsRemoteCharacter",
                    "ViewingController",
                }
                for _, prop in ipairs(idProps) do
                    local propOk, propVal = pcall(function() return p[prop] end)
                    if propOk and propVal ~= nil then
                        local display = tostring(propVal)
                        if type(propVal) == "userdata" then
                            display = SafeName(propVal)
                        end
                        table.insert(lines, "  " .. prop .. " = " .. display)
                    end
                end

                -- HP/KI for correlation
                local hpOk, hp = pcall(function() return p.HPGaugeValue end)
                local spOk, sp = pcall(function() return p.SPGaugeValue end)
                table.insert(lines, "  HPGaugeValue = " .. (hpOk and tostring(hp) or "err"))
                table.insert(lines, "  SPGaugeValue = " .. (spOk and tostring(sp) or "err"))
            end
        end
    end

    -- Write pawn identification before attempting controller debug
    AppendDump("battle_state.txt", table.concat(lines, "\n") .. "\n")
    lines = {}

    -- === ALL CONTROLLERS ===
    table.insert(lines, "=== All BP_BattlePlayerControllers ===")
    local allCtrls = FindAllOf("BP_BattlePlayerController_C")
    if allCtrls then
        for i, ctrl in ipairs(allCtrls) do
            table.insert(lines, "")
            table.insert(lines, "--- Controller " .. i .. ": " .. SafeName(ctrl) .. " ---")
            local lcOk, lc = pcall(function() return ctrl.IsLocalController(ctrl) end)
            table.insert(lines, "  IsLocalController() = " .. (lcOk and tostring(lc) or "err"))
            local lpcOk, lpc = pcall(function() return ctrl.IsLocalPlayerController(ctrl) end)
            table.insert(lines, "  IsLocalPlayerController() = " .. (lpcOk and tostring(lpc) or "err"))
            local cpOk, cpawn = pcall(function() return ctrl.Pawn end)
            table.insert(lines, "  Pawn = " .. SafeName(cpOk and cpawn or nil))
            local apOk, apawn = pcall(function() return ctrl.AcknowledgedPawn end)
            table.insert(lines, "  AcknowledgedPawn = " .. SafeName(apOk and apawn or nil))
            local vtOk, vt = pcall(function() return ctrl:GetViewTarget() end)
            table.insert(lines, "  GetViewTarget() = " .. SafeName(vtOk and vt or nil))
            local psOk2, ps2 = pcall(function() return ctrl.PlayerState end)
            table.insert(lines, "  PlayerState = " .. SafeName(psOk2 and ps2 or nil))
            local netOk, netMode = pcall(function() return ctrl.GetNetMode(ctrl) end)
            table.insert(lines, "  GetNetMode() = " .. (netOk and tostring(netMode) or "err"))
            local plOk, pl = pcall(function() return ctrl.Player end)
            table.insert(lines, "  Player = " .. SafeName(plOk and pl or nil))
        end
    else
        table.insert(lines, "  (none found)")
    end

    table.insert(lines, "")
    AppendDump("battle_state.txt", table.concat(lines, "\n") .. "\n")
end

-- === INIT & KEYBINDS ===

function DebugTools.Init(SpeakFn)
    -- Create dump directory
    os.execute("mkdir " .. DUMP_DIR .. " 2>NUL")

    -- Clear dump files on startup
    local filesToClear = {"debug_dump.txt", "chara_select.txt", "battle_gauges.txt", "battle_state.txt"}
    for _, f in ipairs(filesToClear) do
        local fh = io.open(DUMP_DIR .. "/" .. f, "w")
        if fh then
            fh:write("(cleared on startup " .. os.date("%Y-%m-%d %H:%M:%S") .. ")\n\n")
            fh:close()
        end
    end

    -- F5: Toggle continuous debug dump
    RegisterKeyBind(Key.F5, function()
        if _dumpActive then
            StopDumpLoop()
            if SpeakFn then SpeakFn("Debug dump off", true) end
            print("[AE-DBG] Continuous dump stopped")
        else
            StartDumpLoop()
            if SpeakFn then SpeakFn("Debug dump on", true) end
            print("[AE-DBG] Continuous dump started (250ms, change-only)")
        end
    end)

    -- F4: Character select dump
    RegisterKeyBind(Key.F4, function()
        if SpeakFn then SpeakFn("Inspecting character select...", true) end
        pcall(DumpCharaSelectInfo)
        if SpeakFn then SpeakFn("Character select dump complete", true) end
    end)

    -- F3: Battle state dump
    RegisterKeyBind(Key.F3, function()
        if SpeakFn then SpeakFn("Battle dump", true) end
        local ok, err = pcall(DumpBattleGameState)
        if not ok then
            AppendDump("battle_state.txt", "--- ERROR: " .. tostring(err) .. " ---\n\n")
            print("[AE-DBG] Battle state error: " .. tostring(err))
        end
        pcall(DumpBattleGauges)
        if SpeakFn then SpeakFn("Battle dump complete", true) end
    end)

    print("[AE-DBG] Debug tools loaded. F3=battle dump, F4=chara select, F5=toggle debug dump")
end

return DebugTools
