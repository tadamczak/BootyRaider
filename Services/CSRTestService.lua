local Raider = BootyRaider

Raider.Services = Raider.Services or {}
local TestLab = {}
Raider.Services.CSRTest = TestLab

local DAY = 24 * 60 * 60
local ITEMS = { 18404, 17078, 16929 }

local function AddEntry(state, srItemId, lootItemId)
    if not state.currentPlayer then return false, "Select a test player first." end
    state.sequence = state.sequence + 1
    local member = { name = state.currentPlayer, guildRank = state.ranks[state.currentPlayer], srItems = {}, lootItems = {} }
    if srItemId then member.srItems[1] = { itemId = srItemId, count = 1 } end
    if lootItemId then member.lootItems[1] = { itemId = lootItemId, count = 1 } end
    table.insert(state.entries, {
        id = "csr-test-" .. state.sequence, raidName = "CSR Test Raid", createdAt = state.now, savedAt = state.now,
        csrEnabled = true, lootRules = { silverback = { csr = true }, macaque = { csr = false } },
        members = { member },
    })
    state.now = state.now + 60
    return true
end

function TestLab.Create()
    local state = { entries = {}, log = {}, ranks = {}, players = {}, itemSelections = {},
        now = time(), sequence = 0, playerSequence = 0, itemIndex = 1 }
    TestLab.Reset(state)
    return state
end

function TestLab.Reset(state)
    local index
    for index = table.getn(state.entries), 1, -1 do table.remove(state.entries, index) end
    for index = table.getn(state.log), 1, -1 do table.remove(state.log, index) end
    for index = table.getn(state.players), 1, -1 do table.remove(state.players, index) end
    local key
    for key in pairs(state.ranks) do state.ranks[key] = nil end
    for key in pairs(state.itemSelections) do state.itemSelections[key] = nil end
    state.archiveSummary = nil
    state.now = time(); state.sequence = 0; state.playerSequence = 0; state.itemIndex = 1; state.currentPlayer = nil
    table.insert(state.log, "Test reset. Add a player to begin.")
end

function TestLab.AddPlayer(state)
    state.playerSequence = state.playerSequence + 1
    state.currentPlayer = "CSRTestPlayer" .. state.playerSequence
    state.ranks[state.currentPlayer] = "Silverback"
    state.itemSelections[state.currentPlayer] = state.itemIndex
    table.insert(state.players, state.currentPlayer)
    AddEntry(state, TestLab.GetItemId(state), nil)
    table.insert(state.log, 1, "Added and selected " .. state.currentPlayer .. ".")
    return true
end

function TestLab.GetPlayers(state)
    return state.players
end

function TestLab.SelectPlayer(state, name)
    local wanted = string.lower(tostring(name or ""))
    for _, player in ipairs(state.players) do
        if string.lower(player) == wanted then
            state.currentPlayer = player
            state.itemIndex = state.itemSelections[player]
            return true
        end
    end
    return false, "Select an existing test player."
end

function TestLab.GetItemId(state)
    return ITEMS[state.itemIndex]
end

function TestLab.NextItem(state)
    state.itemIndex = math.mod(state.itemIndex, table.getn(ITEMS)) + 1
    if state.currentPlayer then state.itemSelections[state.currentPlayer] = state.itemIndex end
    table.insert(state.log, 1, "Selected another item.")
end

function TestLab.ToggleRank(state)
    if not state.currentPlayer then return false, "Select a test player first." end
    local rank = state.ranks[state.currentPlayer]
    if rank == "Silverback" then rank = "Macaque" else rank = "Silverback" end
    state.ranks[state.currentPlayer] = rank
    table.insert(state.log, 1, state.currentPlayer .. " rank changed to " .. rank .. ".")
    return true
end

function TestLab.AddMissedReserve(state)
    local ok, reason = AddEntry(state, TestLab.GetItemId(state), nil)
    if ok then table.insert(state.log, 1, "Added an unsuccessful SR for the selected player and item.") end
    return ok, reason
end

function TestLab.AwardItem(state)
    local ok, reason = AddEntry(state, nil, TestLab.GetItemId(state))
    if ok then table.insert(state.log, 1, "Awarded the selected item; its previous reserves are archived as AWARDED.") end
    return ok, reason
end

function TestLab.AdvanceDays(state, days)
    days = tonumber(days)
    if not days or days < 1 or days - days ~= 0 or days ~= math.floor(days) then
        return false, "Advance by a positive whole number of days."
    end
    local nextTime = state.now + (days * DAY)
    if nextTime - nextTime ~= 0 then return false, "The simulated date is out of range." end
    state.now = nextTime
    table.insert(state.log, 1, "Advanced simulated time by " .. tostring(days) .. " days.")
    return true
end

function TestLab.SetSourceArchived(state, raidId, playerName, itemId, archived, selectedRaids)
    if type(archived) ~= "boolean" then return false, "Choose Archive or Activate." end
    if selectedRaids ~= nil and type(selectedRaids) ~= "table" then return false, "Invalid raid filter." end
    itemId = tonumber(itemId)
    if not itemId or itemId < 1 or itemId > 2147483647 or itemId ~= math.floor(itemId) then
        return false, "A valid item ID is required."
    end
    local wantedId, entry = string.lower(tostring(raidId or "")), nil
    for _, candidate in ipairs(state.entries) do
        if string.lower(tostring(candidate.id)) == wantedId then entry = candidate end
    end
    if not entry then return false, "This test raid no longer exists." end
    -- Only the isolated simulation's filtered ledger can authorize an action.
    -- No live database, guild permissions or durable raid records are involved.
    state.archiveSummary = TestLab.BuildSummary(state, state.archiveSummary, selectedRaids, nil, true)
    local wanted, source = string.lower(tostring(playerName or "")), nil
    for _, player in ipairs(state.archiveSummary.players) do
        if string.lower(tostring(player.name or "")) == wanted and player.itemId == itemId then
            for _, candidate in ipairs(player.raids) do if candidate.id == entry.id then source = candidate end end
        end
    end
    if not source then return false, "This test CSR source is no longer available." end
    if archived and source.status ~= "ACTIVE" then return false, "This test CSR source is already archived." end
    if not archived and (source.status ~= "ARCHIVED" or source.expired or not source.manuallyArchived) then
        return false, "Only unexpired manually archived CSR can be activated."
    end
    local records = entry.csrArchived
    if archived then
        if type(records) ~= "table" then records = {}; entry.csrArchived = records end
        if type(records[wanted]) ~= "table" then records[wanted] = {} end
        records[wanted][itemId] = true
    elseif type(records) == "table" and type(records[wanted]) == "table" then
        records[wanted][itemId] = nil
        if not next(records[wanted]) then records[wanted] = nil end
        if not next(records) then entry.csrArchived = nil end
    end
    return true
end

function TestLab.BuildSummary(state, target, selectedRaids, searchText, showArchived)
    return Raider.Services.CSR.BuildSummary(state.entries, nil, state.now, target, nil, selectedRaids, searchText, showArchived)
end
