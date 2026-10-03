--[[
    PsC Secure Comms — Mission Engine
    Reads active missions from ClaudeComms/missions.txt
    Checks completion conditions each tick
    Writes events to ClaudeComms/mission_status.txt (read by ORACLE via Monitor)

    Mission file format (one per line):
      STATUS|TYPE|ID|TITLE|TARGET_TOWN|CHECK|CHECK_VALUE|DESC
      STATUS:      ACTIVE, COMPLETE, FAILED
      TYPE:        TRAVEL, COLLECT, DROP, CLEAR
      CHECK:       TOWN, HASITEM, NOITEM, KILLS
      CHECK_VALUE: town name / item type / item type / kill count target
]]

local MISSIONS_FILE = "ClaudeComms/missions.txt"
local STATUS_FILE   = "ClaudeComms/mission_status.txt"

local TICK_RATE  = 200   -- check every ~3.3s
local tickCount  = 0
local killsAtStart = {}  -- [missionId] = kill count when mission was issued

-- ─── File I/O ─────────────────────────────────────────────────────────────────

local function loadMissions()
    local missions = {}
    pcall(function()
        local rdr = getFileReader(MISSIONS_FILE, false)
        if not rdr then return end
        local ln = rdr:readLine()
        while ln ~= nil do
            local status, mtype, id, title, town, check, checkVal, desc =
                ln:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
            if status and id then
                table.insert(missions, {
                    status   = status,
                    mtype    = mtype,
                    id       = id,
                    title    = title,
                    town     = town,
                    check    = check,
                    checkVal = checkVal,
                    desc     = desc or "",
                })
            end
            ln = rdr:readLine()
        end
        rdr:close()
    end)
    return missions
end

local function saveMissions(missions)
    pcall(function()
        local w = getFileWriter(MISSIONS_FILE, true, false)
        if not w then return end
        for i = 1, #missions do
            local m = missions[i]
            w:write(m.status .. "|" .. m.mtype .. "|" .. m.id .. "|" ..
                    m.title .. "|" .. m.town .. "|" .. m.check .. "|" ..
                    m.checkVal .. "|" .. (m.desc or "") .. "\n")
        end
        w:close()
    end)
end

local function writeStatus(event, missionId, extra)
    pcall(function()
        local w = getFileWriter(STATUS_FILE, true, false)
        if w then
            w:write(event .. "|" .. (missionId or "") .. "|" .. (extra or "") .. "\n")
            w:close()
        end
    end)
end

-- ─── Reward / Penalty system ──────────────────────────────────────────────────

local function applyReward(player, rewardCode)
    if not player or not rewardCode then return end
    -- rewardCode format: "FOOD", "AMMO", "MED", "MORALE", "PENALTY_STRESS", "PENALTY_DEPRESSED"
    if rewardCode == "FOOD" then
        player:getInventory():AddItems("Base.CannedBeans", 3)
        player:getInventory():AddItems("Base.CannedTuna", 2)
        player:getInventory():AddItems("Base.Crackers", 2)
        pcall(function() HaloTextHelper.addText(player, "SUPPLY DROP RECEIVED") end)
    elseif rewardCode == "AMMO" then
        player:getInventory():AddItems("Base.ShotgunShells", 20)
        player:getInventory():AddItems("Base.Bullets9mm", 30)
        pcall(function() HaloTextHelper.addText(player, "AMMUNITION RECEIVED") end)
    elseif rewardCode == "MED" then
        player:getInventory():AddItems("Base.Bandage", 4)
        player:getInventory():AddItems("Base.Painkillers", 2)
        player:getInventory():AddItems("Base.Antibiotics", 2)
        pcall(function() HaloTextHelper.addText(player, "MEDICAL SUPPLIES RECEIVED") end)
    elseif rewardCode == "MORALE" then
        pcall(function()
            local stats = player:getStats()
            if stats then
                stats:set(CharacterStat.UNHAPPINESS, math.max(0, stats:get(CharacterStat.UNHAPPINESS) - 0.4))
                stats:set(CharacterStat.BOREDOM,     math.max(0, stats:get(CharacterStat.BOREDOM)     - 0.4))
            end
        end)
        pcall(function() HaloTextHelper.addText(player, "MORALE STABILISED") end)
    elseif rewardCode == "PENALTY_STRESS" then
        pcall(function()
            local stats = player:getStats()
            if stats then
                stats:set(CharacterStat.STRESS, math.min(1, stats:get(CharacterStat.STRESS) + 0.5))
            end
        end)
        pcall(function() HaloTextHelper.addText(player, "MISSION FAILURE RECORDED") end)
    elseif rewardCode == "PENALTY_DEPRESSED" then
        pcall(function()
            local stats = player:getStats()
            if stats then
                stats:set(CharacterStat.UNHAPPINESS, math.min(1, stats:get(CharacterStat.UNHAPPINESS) + 0.6))
                stats:set(CharacterStat.FATIGUE,     math.min(1, stats:get(CharacterStat.FATIGUE)     + 0.3))
            end
        end)
        pcall(function() HaloTextHelper.addText(player, "ORACLE DISAPPOINTED") end)
    end
end

-- Global so terminal CMD can call it
function PSC_ApplyReward(playerNum, rewardCode)
    pcall(function()
        local player = getSpecificPlayer(playerNum or 0)
        if player then applyReward(player, rewardCode) end
    end)
end

-- ─── Completion checks ────────────────────────────────────────────────────────

local function checkMission(m, player)
    if m.status ~= "ACTIVE" then return false end

    local check = m.check
    local val   = m.checkVal

    if check == "TOWN" then
        -- Player must be in the target town
        local sq = player:getSquare()
        if not sq then return false end
        local town = PSC_GetCurrentTown and PSC_GetCurrentTown() or ""
        return town:lower() == (m.town or ""):lower()

    elseif check == "HASITEM" then
        -- Player must have the item in inventory
        local inv = player:getInventory()
        if not inv then return false end
        return inv:contains(val)

    elseif check == "NOITEM" then
        -- Player HAD the item and no longer has it (dropped/placed it)
        -- We track by: ACTIVE state implies they picked it up; NOITEM means they delivered it
        local inv = player:getInventory()
        if not inv then return false end
        -- Complete when they DON'T have the item AND they're in the target town
        local inTown = PSC_GetCurrentTown and PSC_GetCurrentTown():lower() == (m.town or ""):lower()
        return inTown and not inv:contains(val)

    elseif check == "KILLS" then
        -- Player has reached a kill count delta since mission start
        local target = tonumber(val) or 10
        local base   = killsAtStart[m.id] or 0
        local kills = 0
        pcall(function()
            local stats = player:getStats()
            if stats then kills = stats:getNumZombieKills() or 0 end
        end)
        return (kills - base) >= target
    end

    return false
end

-- ─── Tick handler ─────────────────────────────────────────────────────────────

local function onTick()
    tickCount = tickCount + 1
    if tickCount < TICK_RATE then return end
    tickCount = 0

    local player = getSpecificPlayer(0)
    if not player then return end

    local missions = loadMissions()
    local changed  = false

    for i = 1, #missions do
        local m = missions[i]
        if m.status == "ACTIVE" then
            -- Record kill baseline when we first see an active KILLS mission
            if m.check == "KILLS" and not killsAtStart[m.id] then
                pcall(function()
                    local stats = player:getStats()
                    killsAtStart[m.id] = stats and stats:getNumZombieKills() or 0
                end)
            end

            local ok = false
            pcall(function() ok = checkMission(m, player) end)
            if ok then
                missions[i].status = "COMPLETE"
                changed = true
                writeStatus("COMPLETE", m.id, m.title)
                killsAtStart[m.id] = nil
            end
        end
    end

    if changed then saveMissions(missions) end
end

Events.OnTick.Add(onTick)

-- ─── Global API (called from execCommand in Terminal) ─────────────────────────

function PSC_IssueMission(mtype, id, title, town, check, checkVal, desc)
    pcall(function()
        local missions = loadMissions()
        -- Remove any existing mission with same id
        local kept = {}
        for i = 1, #missions do
            if missions[i].id ~= id then table.insert(kept, missions[i]) end
        end
        table.insert(kept, {
            status   = "ACTIVE",
            mtype    = mtype or "TRAVEL",
            id       = id,
            title    = title or id,
            town     = town or "Unknown",
            check    = check or "TOWN",
            checkVal = checkVal or town or "",
            desc     = desc or "",
        })
        saveMissions(kept)
        writeStatus("ISSUED", id, title)
    end)
end

function PSC_FailMission(id, penaltyCode, playerNum)
    pcall(function()
        local missions = loadMissions()
        for i = 1, #missions do
            if missions[i].id == id then
                missions[i].status = "FAILED"
            end
        end
        saveMissions(missions)
        writeStatus("FAILED", id, penaltyCode or "")
        if penaltyCode then
            PSC_ApplyReward(playerNum or 0, penaltyCode)
        end
    end)
end

print("[PSC_SC] Mission engine active.")
