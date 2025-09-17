--[[
EcoTracker Widget - Beyond All Reason Resource Tracking

SUMMARY:
This widget tracks economic units (metal extractors, energy generators, converters, builders) 
in real-time during gameplay. It monitors resource production/consumption rates, unit counts, 
and total accumulated resources for all economy-related buildings.

USAGE:
1. Enable the widget in the game's widget menu
2. The widget automatically tracks all economy units as they're built/destroyed
3. Real-time data is displayed on screen showing:
   - Total energy/metal produced
   - Per-unit-type production rates and totals
   - Unit counts over time
4. Click the button (bottom-left corner) to:
   - Export current data to CSV file (LuaUI/Widgets/data.csv)
   - Reset all tracking data to start fresh
5. CSV export includes columns for game time, metal production, energy production, and unit counts

The widget tracks: metal extractors, energy generators, converters, and construction units.
]]

function widget:GetInfo()
    return {
        name = "EcoTracker",
        desc = "Tracks resources with start/stop controls.",
        author = "David Skinner, feat. CMDRZod(adapted from spectator HUD)",
        date = "2025-01-05",
        license = "GPLv2",
        layer = 0,
        enabled = false
    }
end

local unitCache = {}
local unitDefsToTrack = {}

local unitModelCache = {} -- to swapped out
unitModelCache.unitdefs = {}
unitModelCache.seconds = {}
unitModelCache.energyProduced = 0
unitModelCache.metalProduced = 0
unitModelCache.energySpent = 0
unitModelCache.metalSpent = 0
local gaiaID = Spring.GetGaiaTeamID()
local gaiaAllyID = select(6, Spring.GetTeamInfo(gaiaID, false))

local options = {
    useMetalEquivalent70 = false,
    subtractReclaimFromIncome = false,
    staticWindValue = 14.2
}

-- column configuration
-- run test from ?? -> 20:00
gamesecondscoldef = { name = "Game Seconds", unit = nil, valueFunc = nil }
armfusEcoldef = { name = "Arm Fusion", unit = "armfus", valueProperty = "energyProducedOverTimeArray" }
armafusEcoldef = { name = "Arm AFUS", unit = "armafus", valueProperty = "energyProducedOverTimeArray" }
armwinEcoldef = { name = "Arm Wind", unit = "armwin", valueProperty = "energyProducedOverTimeArray" }
armmmkrMcoldef = { name = "Arm T2 Conv", unit = "armmmkr", valueProperty = "metalProducedOverTimeArray" }
armmakrMcoldef = { name = "Arm T1 Conv", unit = "armmakr", valueProperty = "metalProducedOverTimeArray" }
armmohoMcoldef = { name = "T2 Mex", unit = "armmoho", valueProperty = "metalProducedOverTimeArray" }
armnanotcMScoldef = { name = "Arm Con Turret", unit = "armnanotc", valueProperty = "metalSpentOverTimeArray" }
armnanotcCcoldef = { name = "Arm Con Turret Count", unit = "armnanotc", valueProperty = "countOverTimeArray" }
local csvColumns = { gamesecondscoldef, armmohoMcoldef, armmakrMcoldef, armmmkrMcoldef,
    armafusEcoldef, armfusEcoldef, armwinEcoldef,
    armnanotcMScoldef, armnanotcCcoldef }

function widget:Initialize()
    -- viewScreenWidth, viewScreenHeight = Spring.GetViewGeometry()
    buildUnitDefs()
    buildUnitCache()
end

local lastGameUpdate = 0
function widget:Update()
    local gs = math.floor(Spring.GetGameSeconds())
    if gs == lastGameUpdate then
        return
    end
    lastGameUpdate = gs
    calculateUnitData(unitCache, 0, "economyUnits", gs)
end

function calculateUnitData(unitCache, teamID, cacheName, gameSecond)
    unitModelCache.seconds[#unitModelCache.seconds + 1] = gameSecond

    for key, value in pairs(unitModelCache.unitdefs) do
        value.count = 0
        value.lastSecondEnergyProduced = 0
        value.lastSecondEnergySpent = 0
        value.lastSecondMetalProduced = 0
        value.lastSecondMetalSpent = 0
    end

    if unitCache[teamID] and unitCache[teamID][cacheName] then
        for udid, unitIds in pairs(unitCache[teamID][cacheName].defs) do
            if not unitModelCache.unitdefs[udid] then
                unitModelCache.unitdefs[udid] = {
                    name = UnitDefs[udid]["tooltip"],
                    count = 0,
                    countOverTimeArray = {},

                    lastSecondEnergyProduced = 0,
                    totalEnergyProduced = 0,
                    totalEnergySpent = 0,
                    lastSecondEnergySpent = 0,
                    energyProducedOverTimeArray = {},
                    energySpentOverTimeArray = {},

                    lastSecondMetalProduced = 0,
                    totalMetalProduced = 0,
                    totalMetalSpent = 0,
                    lastSecondMetalSpent = 0,
                    metalProducedOverTimeArray = {},
                    metalSpentOverTimeArray = {}
                }
            else
                unitModelCache.unitdefs[udid].count = #unitCache[teamID][cacheName].defs[udid]

                if isWind(udid) then
                    local windPower = (function()
                        if options.staticWindValue > 0 then
                            return options.staticWindValue
                        else
                            return
                                select(4, Spring.GetWind())
                        end
                    end)()
                    local windEnergyThisSecond = windPower * unitModelCache.unitdefs[udid].count
                    unitModelCache.unitdefs[udid].totalEnergyProduced = unitModelCache.unitdefs[udid].totalEnergyProduced + windEnergyThisSecond
                    unitModelCache.unitdefs[udid].lastSecondEnergyProduced = windEnergyThisSecond
                    unitModelCache.unitdefs[udid].energyProducedOverTimeArray[gameSecond] = windEnergyThisSecond
                    unitModelCache.unitdefs[udid].energySpentOverTimeArray[gameSecond] = unitModelCache.unitdefs[udid].lastSecondEnergySpent
                    unitModelCache.unitdefs[udid].metalProducedOverTimeArray[gameSecond] = unitModelCache.unitdefs[udid].lastSecondMetalProduced
                    unitModelCache.unitdefs[udid].metalSpentOverTimeArray[gameSecond] = unitModelCache.unitdefs[udid].lastSecondMetalSpent
                    unitModelCache.energyProduced = unitModelCache.energyProduced + windEnergyThisSecond
                else
                    for _, unitId in ipairs(unitIds) do
                        local metalMake, metalUse, energyMake, energyUse = Spring.GetUnitResources(unitId)

                        unitModelCache.unitdefs[udid].totalEnergyProduced = unitModelCache.unitdefs[udid]
                            .totalEnergyProduced +
                            energyMake
                        unitModelCache.unitdefs[udid].lastSecondEnergyProduced = unitModelCache.unitdefs[udid]
                            .lastSecondEnergyProduced + energyMake
                        unitModelCache.unitdefs[udid].lastSecondEnergySpent = unitModelCache.unitdefs[udid]
                            .lastSecondEnergySpent + energyUse
                        unitModelCache.unitdefs[udid].totalEnergySpent = unitModelCache.unitdefs[udid].totalEnergySpent +
                            energyUse
                        unitModelCache.unitdefs[udid].energyProducedOverTimeArray[gameSecond] = unitModelCache.unitdefs[udid].lastSecondEnergyProduced
                        unitModelCache.unitdefs[udid].energySpentOverTimeArray[gameSecond] = unitModelCache.unitdefs[udid].lastSecondEnergySpent

                        unitModelCache.unitdefs[udid].totalMetalProduced = unitModelCache.unitdefs[udid]
                            .totalMetalProduced +
                            metalMake
                        unitModelCache.unitdefs[udid].lastSecondMetalProduced = unitModelCache.unitdefs[udid]
                            .lastSecondMetalProduced + metalMake
                        unitModelCache.unitdefs[udid].lastSecondMetalSpent = unitModelCache.unitdefs[udid]
                            .lastSecondMetalSpent +
                            metalUse
                        unitModelCache.unitdefs[udid].totalMetalSpent = unitModelCache.unitdefs[udid].totalMetalSpent +
                            metalUse
                        unitModelCache.unitdefs[udid].metalProducedOverTimeArray[gameSecond] = unitModelCache.unitdefs[udid].lastSecondMetalProduced
                        unitModelCache.unitdefs[udid].metalSpentOverTimeArray[gameSecond] = unitModelCache.unitdefs[udid].lastSecondMetalSpent

                        unitModelCache.energyProduced = unitModelCache.energyProduced + energyMake
                        unitModelCache.metalProduced = unitModelCache.metalProduced + metalMake
                    end
                end
            end
            unitModelCache.unitdefs[udid].countOverTimeArray[gameSecond] = #unitCache[teamID][cacheName].defs[udid]
        end
    end
end

--#region DRAW
local lx = 0
local ly = 300
local rx = 50
local ry = 350
-- commente out for performance
function widget:DrawScreen()
    -- gl.Text("Hello There", 1700, 1350, 16, "s")
        local mouseX, mouseY = Spring.GetMouseState()

        gl.Text(mouseX .. " " .. mouseY, 400, 150, 16, "o")
        gl.Text("total E: " .. unitModelCache.energyProduced, 400, 200, 16, "o")
        gl.Text("total M: " .. unitModelCache.metalProduced, 400, 225, 16, "o")

        local startPosX = 1700
        local startPosY = 1350
        local textSpacing = 0
        local buffer = 5
        local function printecobuilding(prefix, value)
            gl.Text(prefix .. value, startPosX, startPosY - textSpacing, 16, "s")
            textSpacing = textSpacing + 25

            if textSpacing >= startPosY - 200 then
                textSpacing = 0
                startPosX = startPosX + 300
            end
        end

        -- draw e structure diagnostics
        if unitModelCache then
            for unitDef, unitInfo in pairs(unitModelCache.unitdefs) do
                printecobuilding("", unitInfo.name)
                -- printecobuilding("UnitDefId:", unitDef)
                printecobuilding("Count: ", unitInfo.count)
                printecobuilding("Total E Produced:", unitInfo.totalEnergyProduced)
                printecobuilding("Total E Spent:", unitInfo.totalEnergySpent)
                printecobuilding("E/s IN:", unitInfo.lastSecondEnergyProduced)
                -- printecobuilding("E/s OUT:", unitInfo.lastSecondEnergySpent)
                printecobuilding("Total M Produced:", unitInfo.totalMetalProduced)
                printecobuilding("Total M Spent:", unitInfo.totalMetalSpent)
                printecobuilding("M/s IN:", unitInfo.lastSecondMetalProduced)
                -- printecobuilding("M/s OUT:", unitInfo.lastSecondMetalSpent)
                printecobuilding("-----------", "")
            end
        end

    --     -- reset button
    WG.FlowUI.Draw.Element(
        lx, -- x of bottom left
        ly, -- y of bottom left
        rx, -- x of top right
        ry, -- y of top right
        1, 1, 1, 1,
        1, 1, 1, 1
    )
end
--#endregion
local windDefIds = {}
function buildUnitDefs()
    local function isEconomyUnit(unitDefId, unitDef)
        return ((unitDef.customParams.unitgroup == 'metal') or (unitDef.customParams.unitgroup == 'energy')) or
            (unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency) or
            (unitDef.buildSpeed and (unitDef.buildSpeed > 0))
    end

    unitDefsToTrack = {}
    unitDefsToTrack.economyUnitDefs = {}

    for unitDefID, unitDef in ipairs(UnitDefs) do
        if isEconomyUnit(unitDefID, unitDef) then
            unitDefsToTrack.economyUnitDefs[unitDefID] = {
                name = unitDef.tooltip,
                energyMake = unitDef.energyMake,
                metalMake = unitDef
                    .metalMake
            }
        end

        if unitDef.tooltip == 'armwin' or unitDef.tooltip == 'corwin' then
            table.insert(windDefIds, unitDefID)
        end
    end
end

function buildUnitCache()
    unitCache = {}

    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            local teamList = Spring.GetTeamList(allyID)
            if teamList then
                for _, teamID in ipairs(teamList) do
                    unitCache[teamID] = {}
                    unitCache[teamID].economyUnits = {}
                    unitCache[teamID].economyUnits.defs = {}
                    unitCache[teamID].economyUnits.units = {}
                    local unitIDs = Spring.GetTeamUnits(teamID)
                    for i = 1, #unitIDs do
                        local unitID = unitIDs[i]
                        if not Spring.GetUnitIsBeingBuilt(unitID) then
                            local unitDefID = Spring.GetUnitDefID(unitID)
                            addToUnitCache(teamID, unitID, unitDefID)
                        end
                    end
                end
            end
        end
    end
end

--#region ADD/REMOVE
function addToUnitCache(teamID, unitID, unitDefID)
    local function addToUnitCacheInternal(cache, teamID, unitID, value)
        if unitCache[teamID][cache] then
            if not unitCache[teamID][cache][unitID] then
                -- might want to push unit into array here
                unitCache[teamID][cache].units[unitID] = value
                if unitCache[teamID][cache].defs[unitDefID] == nil then
                    unitCache[teamID][cache].defs[unitDefID] = {}
                end
                table.insert(unitCache[teamID][cache].defs[unitDefID], unitID)
            else
                Spring.Echo(string.format("WARNING: addToUnitCache(), unitID %d already added", unitID))
            end
        end
    end

    if unitDefsToTrack.economyUnitDefs[unitDefID] then
        addToUnitCacheInternal("economyUnits", teamID, unitID,
            unitDefsToTrack.economyUnitDefs[unitDefID])
    end
end

function removeFromUnitCache(teamID, unitID, unitDefID)
    local function removeFromUnitCacheInternal(cache, teamID, unitID, value)
        if unitCache[teamID][cache] then
            if unitCache[teamID][cache].units[unitID] then
                unitCache[teamID][cache].units[unitID] = nil
                removeValue(unitCache[teamID][cache].defs[unitDefID], unitID)
            else
                Spring.Echo(string.format("WARNING: removeFromUnitCache(), unitID %d not in unit cache", unitID))
            end
        end
    end

    if unitDefsToTrack.economyUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("economyUnits", teamID, unitID,
            unitDefsToTrack.economyUnitDefs[unitDefID])
    end
end

function removeValue(array, value)
    for i, v in ipairs(array) do
        if v == value then
            table.remove(array, i)
            return true -- Return true if a value was removed
        end
    end
    return false -- Return false if the value was not found
end

--#endregion

--#region CREATE/DESTROY
function widget:UnitFinished(unitID, unitDefID, unitTeam)
    if unitCache[unitTeam] then
        addToUnitCache(unitTeam, unitID, unitDefID)
    end
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if Spring.GetUnitIsBeingBuilt(unitID) then
        return
    end

    if unitCache[oldTeam] then
        removeFromUnitCache(oldTeam, unitID, unitDefID)
    end

    if unitCache[newTeam] then
        addToUnitCache(newTeam, unitID, unitDefID)
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
    -- unit might've been a nanoframe
    if Spring.GetUnitIsBeingBuilt(unitID) then
        return
    end

    if unitCache[unitTeam] then
        removeFromUnitCache(unitTeam, unitID, unitDefID)
    end
end

--#endregion

--#region UTILITIES
function selectedUnitTableToString(tbl)
    local result = "{"
    for key, value in pairs(tbl) do
        local keyStr = tostring(key)
        local valueStr = type(value) == "table" and tableToString(value) or tostring(value)
        local unitDefID = Spring.GetUnitDefID(value)
        result = result .. keyStr .. " = " .. valueStr .. "," .. unitDefID .. ", "
    end
    result = result:sub(1, -3) -- Remove the trailing comma and space
    return result .. "}"
end

function tableToString(tbl)
    local result = "{"
    for key, value in pairs(tbl) do
        local keyStr = tostring(key)
        local valueStr = type(value) == "table" and tableToString(value) or tostring(value)
        result = result .. keyStr .. " = " .. valueStr .. ", "
    end
    result = result:sub(1, -3) -- Remove the trailing comma and space
    return result .. "}"
end

function is_point_in_box(x, y, x_min, y_min, x_max, y_max)
    return x >= x_min and x <= x_max and y >= y_min and y <= y_max
end

function containsValue(array, value)
    for _, v in ipairs(array) do
        if v == value then
            return true -- Value found
        end
    end
    return false -- Value not found
end

function isWind(unitDefId)
    return containsValue(windDefIds, unitDefId)
end

local printCount = 5
local printCountCurrent = 0
function PrintSome(msg)
    if printCountCurrent < printCount then
        if type(msg) == "table" then
            Spring.Echo("printsome: " .. tableToString(msg))
        else
            Spring.Echo("printsome: " .. msg)
        end
    end
    printCountCurrent = printCountCurrent + 1
end

function writeTableToCSV(filename, modelCacheDefs, coldefs)
    local file = io.open(filename, "w")
    if not file then
        return false, "Failed to open file"
    end

    local headerRow = {}
    for i, coldef in ipairs(coldefs) do
        table.insert(headerRow, coldef.name)
    end
    file:write(table.concat(headerRow, ","), "\n")

    local modelCacheDefsByName = {}
    for _, v in pairs(modelCacheDefs) do
        modelCacheDefsByName[v.name] = v
    end

    for _, sec in ipairs(unitModelCache.seconds) do
        local values = {}
        table.insert(values, sec) -- Add time as the first column

        -- Process each column definition
        for _, coldef in ipairs(coldefs) do
            if coldef.valueProperty ~= nil then
                local v = modelCacheDefsByName[coldef.unit] -- Fetch the correct unit directly
                if v then
                    local value = (v[coldef.valueProperty] and v[coldef.valueProperty][sec]) or 0
                    table.insert(values, tostring(value))
                else
                    table.insert(values, "0") -- Default value if unit not found
                end
            end
        end
        file:write(table.concat(values, ","), "\n")
    end

    file:close()
    return true
end


function widget:MousePress(x, y, button)
    if is_point_in_box(x, y, lx, ly, rx, ry) then
        writeTableToCSV("LuaUI/Widgets/data.csv", unitModelCache.unitdefs, csvColumns)
        clearAllData()
    end
end

function clearAllData()
    unitModelCache.energyProduced = 0
    unitModelCache.metalProduced = 0
    unitModelCache.seconds = {}
    
    for udid, value in pairs(unitModelCache.unitdefs) do
        value.totalEnergyProduced = 0
        value.totalEnergySpent = 0
        value.totalMetalProduced = 0
        value.totalMetalSpent = 0
        value.energyProducedOverTimeArray = {}
        value.energySpentOverTimeArray = {}
        value.metalProducedOverTimeArray = {}
        value.metalSpentOverTimeArray = {}
        value.countOverTimeArray = {}
    end
end

--#endregion
