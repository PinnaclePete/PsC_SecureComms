-- Spawn the STU-III terminal as rare loot in military/government containers.
-- One guaranteed spawn in a police station safe for early access.

Events.OnLoadedTileDefinitions.Add(function()
    local function addToTable(tbl, container, item, chance)
        if not tbl or not tbl[container] then return end
        local t = tbl[container]
        if t.items then
            table.insert(t.items, item)
            table.insert(t.items, chance)
        end
    end

    pcall(function()
        local p = ProceduralDistributions and ProceduralDistributions.list
        if not p then return end
        addToTable(p, "MilitaryStorageLarge",  "STU3Terminal", 2)
        addToTable(p, "MilitaryOfficerDesk",   "STU3Terminal", 3)
        addToTable(p, "GovernmentOfficeDesk",  "STU3Terminal", 2)
        addToTable(p, "PoliceStorageLarge",     "STU3Terminal", 1)
    end)

    pcall(function()
        local d = Distributions and Distributions.list
        if not d then return end
        addToTable(d, "MilitaryStorageLarge",  "STU3Terminal", 2)
        addToTable(d, "MilitaryOfficerDesk",   "STU3Terminal", 3)
        addToTable(d, "GovernmentOfficeDesk",  "STU3Terminal", 2)
        addToTable(d, "PoliceStorageLarge",     "STU3Terminal", 1)
    end)
end)
