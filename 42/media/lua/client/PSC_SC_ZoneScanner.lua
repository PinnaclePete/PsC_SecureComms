--[[
    PsC Secure Comms — Zone & Town Scanner
    Writes player location context every 2s to:
      Zomboid/Lua/PZ_Scan/context.txt   format: x|y|zoneName|townName
    Fires town-change events to:
      Zomboid/Lua/PZ_Scan/town_event.txt  format: ENTERED|townName|x|y
    Both files read by ORACLE and the mission engine.
]]

local CONTEXT_FILE    = "PZ_Scan/context.txt"
local TOWN_EVENT_FILE = "PZ_Scan/town_event.txt"
local TICK_RATE       = 120   -- ~2 seconds
local tickCount       = 0
local lastTown        = ""

-- Approximate world-tile bounding boxes for each town/area.
-- Miguel at 12488x3245 confirmed = Louisville.
local TOWNS = {
    {name="Louisville",  x1=9000,  y1=200,   x2=15500, y2=6000},
    {name="Muldraugh",   x1=9900,  y1=9200,  x2=11400, y2=11000},
    {name="Rosewood",    x1=7400,  y1=9700,  x2=9400,  y2=11400},
    {name="West Point",  x1=11200, y1=6800,  x2=13300, y2=8800},
    {name="Riverside",   x1=6000,  y1=6600,  x2=8200,  y2=8600},
    {name="March Ridge", x1=9400,  y1=10900, x2=11100, y2=12600},
    {name="Brandenburg", x1=5000,  y1=3000,  x2=8000,  y2=6500},
    {name="Valley Station", x1=8000, y1=5000, x2=10500, y2=8000},
}

local function getTownName(x, y)
    for i = 1, #TOWNS do
        local t = TOWNS[i]
        if x >= t.x1 and x <= t.x2 and y >= t.y1 and y <= t.y2 then
            return t.name
        end
    end
    return "Wilderness"
end

local function getZoneName(square)
    if not square then return "Unknown" end
    local result = "Open"
    pcall(function()
        local room = square:getRoom()
        if room then
            local rd = room:getDef()
            if rd then
                local n = rd:getName()
                if n and n ~= "" then result = n end
            end
        end
    end)
    if result ~= "Open" then return result end
    pcall(function()
        local building = square:getBuilding()
        if building then
            local bd = building:getDef()
            if bd then
                local n = bd:getName()
                if n and n ~= "" then result = n end
            end
        end
    end)
    return result
end

local function scan(playerNum)
    pcall(function()
        local player = getSpecificPlayer(playerNum)
        if not player then return end
        local sq = player:getSquare()
        if not sq then return end

        local wx   = sq:getX()
        local wy   = sq:getY()
        local zone = getZoneName(sq)
        local town = getTownName(wx, wy)

        -- Write context
        local w = getFileWriter(CONTEXT_FILE, true, false)
        if w then
            w:write(wx .. "|" .. wy .. "|" .. zone .. "|" .. town .. "\n")
            w:close()
        end

        -- Fire town-change event
        if town ~= lastTown then
            lastTown = town
            local ev = getFileWriter(TOWN_EVENT_FILE, true, false)
            if ev then
                ev:write("ENTERED|" .. town .. "|" .. wx .. "|" .. wy .. "\n")
                ev:close()
            end
        end
    end)
end

Events.OnTick.Add(function()
    tickCount = tickCount + 1
    if tickCount >= TICK_RATE then
        tickCount = 0
        scan(0)
    end
end)

-- Expose for mission engine to call directly
function PSC_GetCurrentTown()
    local player = getSpecificPlayer(0)
    if not player then return "Unknown" end
    local sq = player:getSquare()
    if not sq then return "Unknown" end
    return getTownName(sq:getX(), sq:getY())
end

print("[PSC_SC] Zone scanner active.")
