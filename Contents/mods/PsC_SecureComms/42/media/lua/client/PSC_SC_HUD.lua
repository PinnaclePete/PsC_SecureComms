--[[
    PsC Secure Comms — Floating HUD notifier
    Shows a blinking indicator in the top-right corner when a response is
    waiting in ClaudeComms/response.txt (i.e. ORACLE has a message for the player).
    Clicking the indicator opens the terminal UI.
]]

local RESPONSE_FILE = "ClaudeComms/response.txt"
local POLL_RATE     = 60   -- ticks between file checks
local BLINK_RATE    = 20   -- ticks per blink toggle

local HUD = ISPanel:derive("PSC_SC_HUD")

function HUD:new(playerNum)
    local W, H   = 28, 28
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    -- anchor top-right, leave room for vanilla moodles
    local o = ISPanel.new(self, sw - W - 8, 60, W, H)
    o.playerNum  = playerNum or 0
    o.hasMail    = false
    o.blinkTick  = 0
    o.blinkOn    = true
    o.pollTick   = 0
    o.backgroundColor = {r=0, g=0, b=0, a=0}
    o.borderColor     = {r=0, g=0, b=0, a=0}
    return o
end

function HUD:initialise()
    ISPanel.initialise(self)
end

function HUD:prerender()
    if not self.hasMail then return end
    local W, H = self.width, self.height
    -- outer casing
    self:drawRectStatic(0, 0, W, H, 0.85, 0, 0.05, 0.02)
    self:drawRectBorderStatic(0, 0, W, H, 1, 0.08, 0.5, 0.18)
end

function HUD:render()
    if not self.hasMail then return end
    local W, H = self.width, self.height

    if self.blinkOn then
        -- bright green fill
        self:drawRect(2, 2, W-4, H-4, 0.9, 0.04, 0.8, 0.28)
    else
        -- dim
        self:drawRect(2, 2, W-4, H-4, 0.9, 0.02, 0.25, 0.10)
    end

    -- Signal bars (3 vertical bars to suggest comms)
    local barW = 4
    local gaps = {6, 11, 16}
    local heights = {4, 8, 12}
    for i = 1, #gaps do
        local gx = gaps[i]
        local bh = heights[i]
        local by = H - 4 - bh
        local alpha = self.blinkOn and 1.0 or 0.4
        self:drawRect(gx, by, barW, bh, alpha, 0.05, 1.0, 0.35)
    end

    -- "MSG" label
    local fh = getTextManager():getFontHeight(UIFont.Tiny)
    self:drawText("MSG", 3, 2, 0.05, 1.0, 0.35, 1.0, UIFont.Tiny)
end

function HUD:update()
    ISPanel.update(self)

    self.blinkTick = self.blinkTick + 1
    if self.blinkTick >= BLINK_RATE then
        self.blinkTick = 0
        self.blinkOn   = not self.blinkOn
    end

    self.pollTick = self.pollTick + 1
    if self.pollTick >= POLL_RATE then
        self.pollTick = 0
        self:checkMail()
    end
end

function HUD:checkMail()
    local found = false
    pcall(function()
        local rdr = getFileReader(RESPONSE_FILE, false)
        if not rdr then return end
        local first = rdr:readLine()
        rdr:close()
        if first and first:match("%S") then
            found = true
        end
    end)
    self.hasMail = found
end

function HUD:onMouseDown(x, y)
    -- Open (or bring to front) the terminal when clicked
    if not self.hasMail then return end
    pcall(function()
        if PSC_SC_ActiveTerminal then
            PSC_SC_ActiveTerminal:setVisible(true)
            PSC_SC_ActiveTerminal:bringToTop()
        else
            local ui = PSC_TerminalUI_Open and PSC_TerminalUI_Open(self.playerNum)
            if ui then
                PSC_SC_ActiveTerminal = ui
            end
        end
    end)
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

local hudInstances = {}

local function getSaveWorld()
    local name = "unknown"
    pcall(function() name = getWorld():getWorld() end)
    return name
end

local function onGameStart()
    pcall(function()
        local w = getFileWriter("ClaudeComms/save_info.txt", true, false)
        if w then
            w:write("save_world: " .. tostring(getSaveWorld()) .. "\n")
            w:close()
        end
    end)
    local n = getNumActivePlayers and getNumActivePlayers() or 1
    for i = 0, n - 1 do
        if not hudInstances[i] then
            local h = HUD:new(i)
            h:initialise()
            h:addToUIManager()
            hudInstances[i] = h
        end
    end
end

local function onGameEnd()
    for i, h in pairs(hudInstances) do
        pcall(function() h:removeFromUIManager() end)
        hudInstances[i] = nil
    end
end

local function onPlayerDeath(player)
    pcall(function()
        if not player or player:getPlayerNum() ~= 0 then return end
        local name = player:getDisplayName() or "Unknown"
        local day  = 0
        local x, y = 0, 0
        pcall(function()
            local gt = GameTime.getInstance()
            if gt then day = math.floor(gt:getWorldAgeHours() / 24) end
        end)
        pcall(function()
            local sq = player:getSquare()
            if sq then x = sq:getX(); y = sq:getY() end
        end)

        local kills, hours, infected, weapon = 0, 0, false, "none"
        pcall(function() kills = player:getZombieKills() end)
        pcall(function() hours = math.floor(player:getHoursSurvived()) end)
        pcall(function() infected = player:getBodyDamage():IsInfected() end)
        pcall(function()
            local item = player:getPrimaryHandItem()
            if item then weapon = item:getDisplayName() end
        end)

        local w = getFileWriter("ClaudeComms/story_state_kia.txt", true, false)
        if w then
            w:write("save_world: " .. tostring(getSaveWorld()) .. "\n")
            w:write("operator_status: KIA\n")
            w:write("kia_name: " .. name .. "\n")
            w:write("kia_day: " .. tostring(day) .. "\n")
            w:write("kia_position: " .. tostring(x) .. "|" .. tostring(y) .. "\n")
            w:write("kia_kills: " .. tostring(kills) .. "\n")
            w:write("kia_hours_survived: " .. tostring(hours) .. "\n")
            w:write("kia_infected: " .. tostring(infected) .. "\n")
            w:write("kia_weapon: " .. weapon .. "\n")
            w:close()
        end

        -- Also notify the live mission-event monitor so ORACLE reacts at once
        local ev = getFileWriter("ClaudeComms/mission_status.txt", true, true)
        if ev then
            ev:write("OPERATOR_KIA|" .. name .. "|" .. tostring(day) .. "|" .. tostring(x) .. "|" .. tostring(y) .. "\n")
            ev:close()
        end
    end)
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onGameEnd)
Events.OnPlayerDeath.Add(onPlayerDeath)

print("[PSC_SC] HUD notifier loaded.")
