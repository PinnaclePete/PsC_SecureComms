--[[
    PsC Secure Comms — STU-III Terminal
    File bridge: Zomboid/Lua/ClaudeComms/query.txt   (game → Claude)
                 Zomboid/Lua/ClaudeComms/response.txt (Claude → game)
]]

local QUERY_FILE    = "ClaudeComms/query.txt"
local RESPONSE_FILE = "ClaudeComms/response.txt"
local HISTORY_FILE  = "ClaudeComms/history.txt"
local TASKS_FILE    = "ClaudeComms/tasks.txt"

local C_GREEN  = {0.12, 1.00, 0.38, 1.00}
local C_PLAYER = {0.90, 1.00, 0.32, 1.00}
local C_DIM    = {0.05, 0.50, 0.18, 1.00}
local FONT     = UIFont.Small

-- ─── Map markers ──────────────────────────────────────────────────────────────
-- B42 API: ISWorldMap_instance.mapAPI:getMarkersAPI():addGridSquareMarker(x,y,r,r,g,b,a)

local PSC_MapMarkers = {}   -- {x, y, label, handle}

local function pscSyncMapMarkers()
    pcall(function()
        if not ISWorldMap_instance or not ISWorldMap_instance.mapAPI then return end
        local api = ISWorldMap_instance.mapAPI:getMarkersAPI()
        if not api then return end
        for i = 1, #PSC_MapMarkers do
            local m = PSC_MapMarkers[i]
            if not m.handle then
                local h = api:addGridSquareMarker(m.x, m.y, 8, 0.08, 1.0, 0.35, 0.85)
                if h then
                    h:setBlink(true)
                    h:setMinScreenRadius(10)
                    m.handle = h
                end
            end
        end
    end)
end

local function pscAddMapMarker(mx, my, label)
    table.insert(PSC_MapMarkers, {x=mx, y=my, label=label, handle=nil})
    pscSyncMapMarkers()
end

-- Hook world map open to sync markers each time it's shown
if not ISWorldMap.PSC_ShowWorldMapWrapped then
    ISWorldMap.PSC_ShowWorldMapWrapped = true
    local _orig = ISWorldMap.ShowWorldMap
    ISWorldMap.ShowWorldMap = function(...)
        local r = _orig(...)
        pscSyncMapMarkers()
        return r
    end
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local TEXT_W = 536   -- panel width 560 minus 10px left and 14px right margins

local function wrapText(text, maxPx)
    local tm    = getTextManager()
    local lines = {}
    for para in (text .. "\n"):gmatch("([^\n]*)\n") do
        if para == "" then
            lines[#lines + 1] = ""
        else
            local cur = ""
            for word in para:gmatch("%S+") do
                local try = (cur == "") and word or (cur .. " " .. word)
                if tm:MeasureStringX(FONT, try) <= maxPx then
                    cur = try
                else
                    if cur ~= "" then lines[#lines + 1] = cur end
                    cur = word
                    while #cur > 1 and tm:MeasureStringX(FONT, cur) > maxPx do
                        local cut = #cur - 1
                        while cut > 1 and tm:MeasureStringX(FONT, cur:sub(1, cut)) > maxPx do
                            cut = cut - 1
                        end
                        lines[#lines + 1] = cur:sub(1, cut)
                        cur = cur:sub(cut + 1)
                    end
                end
            end
            if cur ~= "" then lines[#lines + 1] = cur end
        end
    end
    return lines
end

local function parseResponse(raw)
    local cmds    = {}
    local clean   = {}
    local logical = {}
    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("%[CMDEX:", "[CMD_EXAMPLE:")  -- escape: CMDEX shows as text, never executes
        local stripped = line:gsub("%[CMD:([^%]]+)%]", function(inner)
            local parts = {}
            for p in (inner .. ":"):gmatch("([^:]*):") do
                table.insert(parts, p)
            end
            table.insert(cmds, parts)
            return ""
        end)
        stripped = stripped:match("^%s*(.-)%s*$")
        if stripped ~= "" then
            logical[#logical + 1] = stripped
            local wrapped = wrapText(stripped, TEXT_W)
            for i = 1, #wrapped do
                table.insert(clean, wrapped[i])
            end
        end
    end
    return clean, cmds, logical
end

-- ─── Task persistence ─────────────────────────────────────────────────────────

local function loadTasks()
    local tasks = {}
    pcall(function()
        local rdr = getFileReader(TASKS_FILE, false)
        if not rdr then return end
        local ln = rdr:readLine()
        while ln ~= nil do
            local status, title, desc = ln:match("^([^|]+)|([^|]+)|(.*)$")
            if status and title then
                table.insert(tasks, {status=status, title=title, desc=desc or ""})
            end
            ln = rdr:readLine()
        end
        rdr:close()
    end)
    return tasks
end

local function saveTasks(tasks)
    pcall(function()
        local w = getFileWriter(TASKS_FILE, true, false)
        if not w then return end
        for i = 1, #tasks do
            local t = tasks[i]
            w:write(t.status .. "|" .. t.title .. "|" .. (t.desc or "") .. "\n")
        end
        w:close()
    end)
end

local function addTask(title, desc)
    local tasks = loadTasks()
    for i = 1, #tasks do
        if tasks[i].title == title then
            tasks[i].status = "ACTIVE"
            saveTasks(tasks)
            return
        end
    end
    table.insert(tasks, {status="ACTIVE", title=title, desc=desc or ""})
    saveTasks(tasks)
end

local function completeTask(title)
    local tasks = loadTasks()
    for i = 1, #tasks do
        if tasks[i].title:lower() == title:lower() then
            tasks[i].status = "DONE"
        end
    end
    saveTasks(tasks)
end

-- ─── History ──────────────────────────────────────────────────────────────────

local function histAppend(colChar, text)
    pcall(function()
        local w = getFileWriter(HISTORY_FILE, true, true)
        if w then w:write(colChar .. "|" .. text .. "\n"); w:close() end
    end)
end

-- ─── Command execution ────────────────────────────────────────────────────────

local function execCommand(cmd, playerNum)
    local kind = cmd[1]
    if kind == "inject" then
        local itemType = cmd[2]
        local amount   = tonumber(cmd[3]) or 1
        pcall(function()
            local player = getSpecificPlayer(playerNum)
            if player then
                player:getInventory():AddItems(itemType, amount)
                pcall(function() HaloTextHelper.addText(player, "PACKAGE RECEIVED") end)
            end
        end)
    elseif kind == "halo" then
        local msg = cmd[2] or ""
        pcall(function()
            local player = getSpecificPlayer(playerNum)
            if player then HaloTextHelper.addText(player, msg) end
        end)
    elseif kind == "task" then
        pcall(function() addTask(cmd[2] or "Task", cmd[3] or "") end)
    elseif kind == "taskdone" then
        pcall(function() completeTask(cmd[2] or "") end)
    elseif kind == "mission" then
        -- [CMD:mission:TYPE:id:title:town:check:checkVal:desc]
        pcall(function()
            if PSC_IssueMission then
                PSC_IssueMission(cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8] or "")
            end
            -- Also add to the visible task list
            addTask(cmd[4] or cmd[3] or "Mission", cmd[8] or "")
        end)
    elseif kind == "reward" then
        pcall(function()
            if PSC_ApplyReward then PSC_ApplyReward(playerNum, cmd[2]) end
        end)
    elseif kind == "fail" then
        pcall(function()
            if PSC_FailMission then PSC_FailMission(cmd[2], cmd[3], playerNum) end
            completeTask(cmd[2] or "")  -- mark done in task list too
        end)
    elseif kind == "complete" then
        -- cmd[2]=missionId, cmd[3]=reward, cmd[4]=optional title override
        pcall(function()
            local missionId = cmd[2] or ""
            -- try title override first, then look up by ID in missions file
            if cmd[4] and cmd[4] ~= "" then
                completeTask(cmd[4])
            else
                -- scan missions.txt to find the title for this ID
                local rdr = getFileReader("ClaudeComms/missions.txt", false)
                if rdr then
                    local ln = rdr:readLine()
                    while ln ~= nil do
                        local s, mt, id, title = ln:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)")
                        if id == missionId and title then completeTask(title) end
                        ln = rdr:readLine()
                    end
                    rdr:close()
                end
            end
            if PSC_ApplyReward and cmd[3] then PSC_ApplyReward(playerNum, cmd[3]) end
        end)
    elseif kind == "devstat" then
        -- [CMD:devstat:statName:value]  0.0=none 1.0=max (B42 CharacterStat API)
        local statName = cmd[2]
        local val      = tonumber(cmd[3]) or 0
        pcall(function()
            local player = getSpecificPlayer(playerNum)
            if not player then return end
            local stats = player:getStats()
            if not stats then return end
            if     statName == "hunger"  then stats:set(CharacterStat.HUNGER,      val)
            elseif statName == "thirst"  then stats:set(CharacterStat.THIRST,      val)
            elseif statName == "fatigue" then stats:set(CharacterStat.FATIGUE,     val)
            elseif statName == "boredom" then stats:set(CharacterStat.BOREDOM,     val)
            elseif statName == "stress"  then stats:set(CharacterStat.STRESS,      val)
            elseif statName == "unhappy" then stats:set(CharacterStat.UNHAPPINESS, val)
            elseif statName == "panic"   then stats:set(CharacterStat.PANIC,       val)
            elseif statName == "endurance" then stats:set(CharacterStat.ENDURANCE, val)
            end
        end)
    elseif kind == "helicopter" then
        pcall(function()
            local player = getSpecificPlayer(playerNum)
            if not player then return end
            HaloTextHelper.addText(player, "EXTRACTION ASSET INBOUND")
            -- Play helicopter sound if available
            pcall(function()
                local x, y, z = player:getX(), player:getY(), player:getZ()
                getSoundManager():PlayWorldSound("HelicopterFlyby", false, x, y, z, 200, 1.0, false)
            end)
        end)
    elseif kind == "marker" then
        local mx = tonumber(cmd[2])
        local my = tonumber(cmd[3])
        if mx and my then
            local label = cmd[4] or "WAYPOINT"
            pscAddMapMarker(mx, my, label)
            pcall(function()
                local player = getSpecificPlayer(playerNum)
                if player then HaloTextHelper.addText(player, "WAYPOINT: " .. label) end
            end)
        end
    end
end

-- ─── Terminal UI ──────────────────────────────────────────────────────────────

local TerminalUI = ISPanel:derive("PSC_TerminalUI")

function TerminalUI:new(playerNum)
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local W, H = 560, 470
    local o = ISPanel.new(self, (sw - W) / 2, (sh - H) / 2, W, H)
    o.playerNum    = playerNum or 0
    o.lines        = {}
    o.subtitle     = "SESSION ACTIVE"
    o.waiting      = false
    o.twTarget     = nil
    o.twLines      = {}
    o.twLineIdx    = 1
    o.twPos        = 0
    o.twTick       = 0
    o.twSpeed      = 1
    o.twCmds       = {}
    o.pollTick     = 0
    o.POLL_RATE    = 45
    o.blinkTick    = 0
    o.blinkOn      = true
    o.activeTab    = "COMMS"
    o.backgroundColor = {r=0,g=0,b=0,a=0}
    o.borderColor     = {r=0,g=0,b=0,a=0}
    return o
end

function TerminalUI:onTabComms()
    self.activeTab = "COMMS"
    self.inputBox:setVisible(true)
    self.sendBtn:setVisible(true)
end

function TerminalUI:onTabTasks()
    self.activeTab = "TASKS"
    self.tasksCache = loadTasks()
    self.inputBox:setVisible(false)
    self.sendBtn:setVisible(false)
end

function TerminalUI:initialise()
    local fh = getTextManager():getFontHeight(FONT)
    local W, H = self.width, self.height
    local inputY = H - 44

    self.inputBox = ISTextEntryBox:new("", 28, inputY + 7, W - 136, fh + 10)
    self.inputBox:initialise(); self.inputBox:instantiate()
    self.inputBox:setMaxLines(1)
    self:addChild(self.inputBox)

    self.sendBtn = ISButton:new(W - 102, inputY + 5, 94, fh + 14, "TRANSMIT", self, TerminalUI.onSend)
    self.sendBtn:initialise(); self.sendBtn:instantiate()
    self:addChild(self.sendBtn)

    self.closeBtn = ISButton:new(W - 26, 4, 22, 22, "X", self, TerminalUI.onClose)
    self.closeBtn:initialise(); self.closeBtn:instantiate()
    self:addChild(self.closeBtn)

    self.tabComms = ISButton:new(2, 36, 80, 20, "COMMS", self, TerminalUI.onTabComms)
    self.tabComms:initialise(); self.tabComms:instantiate()
    self:addChild(self.tabComms)

    self.tabTasks = ISButton:new(84, 36, 80, 20, "TASKS", self, TerminalUI.onTabTasks)
    self.tabTasks:initialise(); self.tabTasks:instantiate()
    self:addChild(self.tabTasks)

    ISPanel.initialise(self)

    self:sysLine("╔══════════════════════════════════════════════════╗")
    self:sysLine("║   KNOX COUNTY SECURE COMMUNICATIONS NETWORK     ║")
    self:sysLine("║   ENCRYPTION: ACTIVE  ·  AUTHENTICATION: PASS   ║")
    self:sysLine("╚══════════════════════════════════════════════════╝")
    self:sysLine("")
    self:loadHistory()
    self:sysLine("Secure channel established.")
    self:sysLine("Transmit your message below.")
    self:sysLine("")
end

function TerminalUI:sysLine(text)
    table.insert(self.lines, {col = C_GREEN, text = text})
end

function TerminalUI:playerLine(text)
    local wrapped = wrapText("> " .. text, TEXT_W)
    for i = 1, #wrapped do
        table.insert(self.lines, {col = C_PLAYER, text = wrapped[i]})
    end
    histAppend("P", "> " .. text)
end

function TerminalUI:loadHistory()
    local loaded = {}
    pcall(function()
        local rdr = getFileReader(HISTORY_FILE, false)
        if not rdr then return end
        local ln = rdr:readLine()
        while ln ~= nil do
            local colChar, text = ln:match("^([GPD])|(.*)$")
            local col = nil
            if     colChar == "G" then col = C_GREEN
            elseif colChar == "P" then col = C_PLAYER
            elseif colChar == "D" then col = C_DIM
            end
            if col then
                local frags = wrapText(text, TEXT_W)
                for f = 1, #frags do
                    table.insert(loaded, {col = col, text = frags[f]})
                end
            end
            ln = rdr:readLine()
        end
        rdr:close()
    end)
    if #loaded > 0 then
        table.insert(self.lines, {col = C_DIM, text = "─── PREVIOUS SESSION ───────────────────────────────"})
        for i = 1, #loaded do
            table.insert(self.lines, loaded[i])
        end
        table.insert(self.lines, {col = C_DIM, text = "─── SESSION RESUMED ────────────────────────────────"})
        table.insert(self.lines, {col = C_GREEN, text = ""})
    end
end

function TerminalUI:prerender()
    local W, H  = self.width, self.height
    local divY  = H - 46
    local bodyY = 58

    self:drawRectStatic(0, 0, W, H, 0.97, 0, 0, 0)
    self:drawRectBorderStatic(0, 0, W, H, 1, 0.1, 0.6, 0.22)
    self:drawRectBorderStatic(1, 1, W-2, H-2, 0.4, 0.04, 0.35, 0.12)

    self:drawRectStatic(0, 0, W, 34, 0.92, 0, 0.07, 0.03)
    self:drawRectBorderStatic(0, 34, W, 1, 1, 0.1, 0.6, 0.22)

    self:drawRectStatic(0, 34, W, 24, 0.9, 0, 0.04, 0.02)
    local tabX = self.activeTab == "COMMS" and 2 or 84
    self:drawRectStatic(tabX, 36, 80, 20, 0.9, 0, 0.1, 0.04)
    self:drawRectBorderStatic(0, 57, W, 1, 1, 0.1, 0.6, 0.22)

    if self.activeTab == "COMMS" then
        self:drawRectStatic(0, divY, W, H - divY, 0.92, 0, 0.07, 0.03)
        self:drawRectBorderStatic(0, divY, W, 1, 1, 0.1, 0.6, 0.22)
    end

    for y = bodyY, divY - 1, 4 do
        self:drawRectStatic(0, y, W, 1, 0.03, 0, 0.05, 0.01)
    end
end

function TerminalUI:render()
    local fh    = getTextManager():getFontHeight(FONT)
    local lh    = fh + 3
    local W, H  = self.width, self.height
    local divY  = H - 46
    local bodyY = 60
    local bodyH = divY - bodyY - 2

    self:drawText("STU-III SECURE TERMINAL", 10, 8,
        C_GREEN[1], C_GREEN[2], C_GREEN[3], C_GREEN[4], FONT)
    self:drawText(self.subtitle, 10, 8 + fh + 1,
        C_DIM[1], C_DIM[2], C_DIM[3], C_DIM[4], FONT)

    if self.activeTab == "COMMS" then
        local maxLines = math.floor(bodyH / lh)
        local display  = {}
        for i = 1, #self.lines do
            table.insert(display, self.lines[i])
        end

        if self.twTarget and self.twLines[self.twLineIdx] then
            for i = 1, self.twLineIdx - 1 do
                table.insert(display, {col = C_GREEN, text = self.twLines[i]})
            end
            local partial = string.sub(self.twLines[self.twLineIdx], 1, self.twPos)
            local cursor  = self.blinkOn and "█" or " "
            table.insert(display, {col = C_GREEN, text = partial .. cursor})
        elseif self.waiting then
            local ndots = math.floor(self.pollTick / 12) % 4
            table.insert(display, {col = C_DIM, text = "  awaiting response" .. string.rep(".", ndots)})
        end

        local startIdx = math.max(1, #display - maxLines + 1)
        for i = startIdx, #display do
            local l = display[i]
            local y = bodyY + (i - startIdx) * lh
            self:drawText(l.text, 10, y, l.col[1], l.col[2], l.col[3], l.col[4], FONT)
        end

        self:drawText(">", 10, divY + 9, C_GREEN[1], C_GREEN[2], C_GREEN[3], C_GREEN[4], FONT)

    else
        local tasks = self.tasksCache or {}
        local y = bodyY + 4
        if #tasks == 0 then
            self:drawText("No tasks assigned.", 10, y,
                C_DIM[1], C_DIM[2], C_DIM[3], C_DIM[4], FONT)
        else
            for i = 1, #tasks do
                if y + lh > divY then break end
                local t      = tasks[i]
                local bullet = t.status == "DONE" and "[x] " or "[+] "
                local col    = t.status == "DONE" and C_DIM or C_GREEN
                self:drawText(bullet .. t.title, 10, y,
                    col[1], col[2], col[3], col[4], FONT)
                y = y + lh
                if t.desc and t.desc ~= "" then
                    local dl = wrapText(t.desc, TEXT_W - 30)
                    for j = 1, #dl do
                        if y + lh > divY then break end
                        self:drawText("    " .. dl[j], 10, y,
                            C_DIM[1], C_DIM[2], C_DIM[3], C_DIM[4], FONT)
                        y = y + lh
                    end
                end
                y = y + 2
            end
        end
    end
end

function TerminalUI:update()
    ISPanel.update(self)

    if self.activeTab == "TASKS" then
        self.taskTick = (self.taskTick or 0) + 1
        if self.taskTick >= 60 or not self.tasksCache then
            self.taskTick   = 0
            self.tasksCache = loadTasks()
        end
    end

    self.blinkTick = self.blinkTick + 1
    if self.blinkTick >= 25 then
        self.blinkTick = 0
        self.blinkOn   = not self.blinkOn
    end

    if self.twTarget then
        self.twTick = self.twTick + 1
        if self.twTick >= self.twSpeed then
            self.twTick = 0
            local line = self.twLines[self.twLineIdx]
            if line and self.twPos < #line then
                self.twPos = self.twPos + 1
            elseif self.twLineIdx < #self.twLines then
                local done = self.twLines[self.twLineIdx]
                table.insert(self.lines, {col = C_GREEN, text = done})
                self.twLineIdx = self.twLineIdx + 1
                self.twPos     = 0
            else
                local last = self.twLines[self.twLineIdx]
                if last then
                    table.insert(self.lines, {col = C_GREEN, text = last})
                end
                self:sysLine("")
                for i = 1, #self.twCmds do
                    pcall(execCommand, self.twCmds[i], self.playerNum)
                end
                self.twCmds    = {}
                self.twTarget  = nil
                self.twLines   = {}
                self.twLineIdx = 1
                self.twPos     = 0
                self.waiting   = false
            end
        end
        return
    end

    -- Always poll — lets ORACLE push messages without waiting for player to transmit
    if not self.twTarget then
        self.pollTick = self.pollTick + 1
        if self.pollTick >= self.POLL_RATE then
            self.pollTick = 0
            self:checkResponse()
        end
    end
end

function TerminalUI:checkResponse()
    local raw = nil
    pcall(function()
        local rdr = getFileReader(RESPONSE_FILE, false)
        if not rdr then return end
        local parts = {}
        local ln = rdr:readLine()
        while ln ~= nil do
            table.insert(parts, ln)
            ln = rdr:readLine()
        end
        rdr:close()
        local joined = table.concat(parts, "\n"):match("^%s*(.-)%s*$")
        if joined and joined ~= "" then
            raw = joined
            local w = getFileWriter(RESPONSE_FILE, true, false)
            if w then w:write(""); w:close() end
        end
    end)

    if raw then
        local cleanLines, cmds, logical = parseResponse(raw)
        if #cleanLines > 0 then
            -- Save to history NOW so close-before-typewriter-finish doesn't lose lines
            for i = 1, #logical do
                histAppend("G", logical[i])
            end
            pcall(function()
                if PSC_SC_Radio and not logical[1]:match("^DEV:") then
                    PSC_SC_Radio.air(logical)
                end
            end)
            self.twTarget  = table.concat(cleanLines, "\n")
            self.twLines   = cleanLines
            self.twLineIdx = 1
            self.twPos     = 0
            self.twTick    = 0
            self.twCmds    = cmds
        else
            for i = 1, #cmds do
                pcall(execCommand, cmds[i], self.playerNum)
            end
            self.waiting = false
        end
        self.waiting = false
    end
end

function TerminalUI:onSend(btn)
    if self.waiting then return end
    local txt = self.inputBox:getText()
    if not txt or txt:match("^%s*$") then return end
    self.inputBox:setText("")
    self:playerLine(txt)
    self.waiting  = true
    self.pollTick = 0
    pcall(function()
        local player = getSpecificPlayer(self.playerNum)
        local name   = player and player:getUsername() or "Survivor"
        local w = getFileWriter(QUERY_FILE, true, false)
        if w then w:write(name .. "|" .. txt); w:close() end
    end)
end

function TerminalUI:onClose(btn)
    self:setVisible(false)
    self:removeFromUIManager()
    PSC_SC_ActiveTerminal = nil
end

function TerminalUI:onKeyPress(key)
    if key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER then
        self:onSend(nil)
        return true
    end
    return ISPanel.onKeyPress(self, key)
end

-- ─── Context menu ─────────────────────────────────────────────────────────────

local function onFillInventoryMenu(playerNum, context, items)
    if not items or #items == 0 then return end
    for i = 1, #items do
        local v    = items[i]
        local item = instanceof(v, "InventoryItem") and v
                     or (type(v) == "table" and v.items and v.items[1])
        if item and item:getType() == "STU3Terminal" then
            context:addOption("Open Secure Terminal", item, function()
                if PSC_SC_ActiveTerminal then
                    pcall(function()
                        PSC_SC_ActiveTerminal:setVisible(false)
                        PSC_SC_ActiveTerminal:removeFromUIManager()
                    end)
                end
                local ui = TerminalUI:new(playerNum)
                ui:initialise()
                ui:addToUIManager()
                PSC_SC_ActiveTerminal = ui
            end)
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryMenu)

function PSC_TerminalUI_Open(playerNum)
    if PSC_SC_ActiveTerminal then
        pcall(function()
            PSC_SC_ActiveTerminal:setVisible(false)
            PSC_SC_ActiveTerminal:removeFromUIManager()
        end)
    end
    local ui = TerminalUI:new(playerNum or 0)
    ui:initialise()
    ui:addToUIManager()
    PSC_SC_ActiveTerminal = ui
    return ui
end

print("[PSC_SC] Secure terminal ready.")
