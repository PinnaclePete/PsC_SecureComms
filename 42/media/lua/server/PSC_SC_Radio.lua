--[[
    PsC Secure Comms - ORACLE radio channel (one way: ORACLE -> player).
    Registers a dynamic channel at 147.3 MHz. Whenever the terminal receives a
    reply, the client calls PSC_SC_Radio.air(lines) and the lines are
    broadcast, so a tuned radio shows them as overhead text without opening the unit.
]]

PSC_SC_Radio = PSC_SC_Radio or {}
local Radio = PSC_SC_Radio

local CHANNEL_UUID = "7d3b9a40-5c1e-4f6a-8e21-0a1c5f9b2d77"
local FREQ_KHZ     = 147300
local CHANNEL_NAME = "ORACLE"

Radio.channel = nil
Radio.freqKhz = FREQ_KHZ

function Radio.onLoadRadioScripts(scriptManager)
    local existing = scriptManager:getRadioChannel(CHANNEL_UUID)
    if existing then
        Radio.channel = existing
        return
    end
    Radio.channel = DynamicRadioChannel.new(CHANNEL_NAME, FREQ_KHZ, ChannelCategory.Emergency, CHANNEL_UUID)
    scriptManager:AddChannel(Radio.channel, false)
    print("[PSC_SC] Registered ORACLE radio channel at 147.3 MHz")
end

function Radio.air(lines)
    if not Radio.channel or not lines or #lines == 0 then return false end
    local bc = RadioBroadCast.new("ORACLE-" .. tostring(ZombRand(100000, 999999)), -1, -1)
    for i = 1, #lines do
        bc:AddRadioLine(RadioLine.new(lines[i], 0.12, 1.0, 0.38))
    end
    Radio.channel:setAiringBroadcast(bc)
    return true
end

Events.OnLoadRadioScripts.Add(Radio.onLoadRadioScripts)
