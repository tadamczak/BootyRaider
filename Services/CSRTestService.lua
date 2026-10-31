local Raider = BootyRaider

Raider.Services = Raider.Services or {}
local TestLab = {}
Raider.Services.CSRTest = TestLab

local DAY = 24 * 60 * 60
local ITEMS = { 18404, 17078, 16929 }

local function PushLog(state, message, eventTime)
    table.insert(state.log, 1, message)
    table.insert(state.logTimes, 1, eventTime or state.now)
end

local function FindPlayer(state, name)
    local wanted = string.lower(tostring(name or ""))
    for _, player in ipairs(state.players) do
        if string.lower(player) == wanted then return player end
    end
end

local function RememberPlayerItem(state, itemId)
    for _, context in ipairs(state.playerItems) do
        if context.name == state.currentPlayer and context.itemId == itemId then return end
    end
    table.insert(state.playerItems, { name = state.currentPlayer, itemId = itemId, itemIndex = state.itemIndex })
end

local function AddEntry(state, srItemId, lootItemId)
    if not state.currentPlayer then return false, "Select a test player first." end
    RememberPlayerItem(state, srItemId or lootItemId)
    state.sequence = state.sequence + 1
    local member = { name = state.currentPlayer, guildRank = state.ranks[state.currentPlayer], srItems = {}, lootItems = {} }
    if srItemId then member.srItems[1] = { itemId = srItemId, count = 1 } end
    if lootItemId then member.lootItems[1] = { itemId = lootItemId, count = 1 } end
    table.insert(state.entries, {
        id = "csr-test-" .. state.sequence, raidName = "CSR Test Raid", createdAt = state.now, savedAt = state.now, endedAt = state.now,
        csrEnabled = true, lootRules = { silverback = { csr = true }, macaque = { csr = false } },
        members = { member },
    })
    state.now = state.now + 60
    return true
end

function TestLab.Create()
    local state = { entries = {}, log = {}, logTimes = {}, ranks = {}, players = {}, playerItems = {}, itemSelections = {},
        now = time(), sequence = 0, playerSequence = 0, itemIndex = 1 }
    TestLab.Reset(state)
    return state
end

function TestLab.Reset(state)
    local index
    for index = table.getn(state.entries), 1, -1 do table.remove(state.entries, index) end
    for index = table.getn(state.log), 1, -1 do table.remove(state.log, index) end
    for index = table.getn(state.logTimes), 1, -1 do table.remove(state.logTimes, index) end
    for index = table.getn(state.players), 1, -1 do table.remove(state.players, index) end
    for index = table.getn(state.playerItems), 1, -1 do table.remove(state.playerItems, index) end
    local key
    for key in pairs(state.ranks) do state.ranks[key] = nil end
    for key in pairs(state.itemSelections) do state.itemSelections[key] = nil end
    state.archiveSummary = nil
    state.now = time(); state.sequence = 0; state.playerSequence = 0; state.itemIndex = 1; state.currentPlayer = nil
    state.setupPlayer = nil; state.setupOriginalItemIndex = nil; state.setupRank = "Silverback"; state.setupItemIndex = 1
    PushLog(state, "Test reset. Add a player to begin.")
end

function TestLab.AddPlayer(state)
    local eventTime = state.now
    state.playerSequence = state.playerSequence + 1
    state.currentPlayer = "CSRTestPlayer" .. state.playerSequence
    state.ranks[state.currentPlayer] = state.setupRank or "Silverback"
    state.itemIndex = state.setupItemIndex or state.itemIndex
    state.itemSelections[state.currentPlayer] = state.itemIndex
    table.insert(state.players, state.currentPlayer)
    AddEntry(state, TestLab.GetItemId(state), nil)
    state.setupPlayer = nil; state.setupOriginalItemIndex = nil
    -- Raid-creating actions log the entry's time, before the minute step.
    PushLog(state, "Added and selected " .. state.currentPlayer .. ".", eventTime)
    return true
end

function TestLab.GetPlayers(state)
    return state.players
end

function TestLab.SelectSetupPlayer(state, name)
    if name == nil then state.setupPlayer = nil; state.setupOriginalItemIndex = nil; return true end
    local player = FindPlayer(state, name)
    if not player then return false, "Select an existing test player." end
    state.setupPlayer = player
    state.setupRank = state.ranks[player]
    state.setupItemIndex = state.itemSelections[player]
    state.setupOriginalItemIndex = state.setupItemIndex
    return true
end

function TestLab.UpdatePlayer(state)
    local player = FindPlayer(state, state.setupPlayer)
    if not player then return false, "Select an existing setup player first." end
    local oldItemId, newItemId = ITEMS[state.setupOriginalItemIndex], ITEMS[state.setupItemIndex]
    if not oldItemId or not newItemId then return false, "Select a valid setup item." end
    local original
    for _, context in ipairs(state.playerItems) do
        if context.name == player then
            if context.itemId == oldItemId then original = context end
            if oldItemId ~= newItemId and context.itemId == newItemId then
                return false, "This test player already has the selected item. Select that CSR context instead."
            end
        end
    end
    if not original then return false, "The selected test player and item no longer exist." end
    -- The Lab edits its fixture ledger. Moving both reserves and receipts keeps
    -- AWARDED history intact; separate existing item histories must not merge.
    local playerKey = string.lower(player)
    for _, entry in ipairs(state.entries) do
        for _, member in ipairs(entry.members) do
            if string.lower(member.name) == playerKey then
                member.guildRank = state.setupRank
                for _, item in ipairs(member.srItems) do if item.itemId == oldItemId then item.itemId = newItemId end end
                for _, item in ipairs(member.lootItems) do if item.itemId == oldItemId then item.itemId = newItemId end end
            end
        end
        local archived = entry.csrArchived and entry.csrArchived[playerKey]
        if oldItemId ~= newItemId and archived and archived[oldItemId] then
            archived[newItemId] = archived[oldItemId]; archived[oldItemId] = nil
        end
    end
    original.itemId = newItemId; original.itemIndex = state.setupItemIndex
    state.currentPlayer = player
    state.ranks[player] = state.setupRank
    state.itemIndex = state.setupItemIndex
    state.itemSelections[player] = state.itemIndex
    state.setupOriginalItemIndex = state.setupItemIndex
    PushLog(state, "Updated and selected " .. player .. ".")
    return true
end

function TestLab.GetRanks()
    return Raider.Services.RankPolicy.GetGuildRanks()
end

function TestLab.SetSetupRank(state, rank)
    local wanted = string.lower(tostring(rank or ""))
    for _, candidate in ipairs(TestLab.GetRanks()) do
        if string.lower(candidate) == wanted then state.setupRank = candidate; return true end
    end
    return false, "Select a valid test rank."
end

function TestLab.GetSetupItemId(state)
    return ITEMS[state.setupItemIndex or state.itemIndex]
end

function TestLab.NextSetupItem(state)
    state.setupItemIndex = math.mod(state.setupItemIndex or state.itemIndex, table.getn(ITEMS)) + 1
end

function TestLab.GetPlayerItems(state)
    return state.playerItems
end

function TestLab.SelectPlayer(state, name, itemId)
    local wanted = string.lower(tostring(name or ""))
    for _, player in ipairs(state.players) do
        if string.lower(player) == wanted then
            local itemIndex = state.itemSelections[player]
            if itemId ~= nil then
                itemIndex = nil
                for _, context in ipairs(state.playerItems) do
                    if context.name == player and context.itemId == tonumber(itemId) then itemIndex = context.itemIndex; break end
                end
                if not itemIndex then return false, "Select an existing test player and item." end
            end
            state.currentPlayer = player
            state.itemIndex = itemIndex
            state.itemSelections[player] = itemIndex
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
    -- Preserve the old one-item selector's add-player flow; the setup-only API
    -- never changes the currently selected player's CSR action context.
    state.setupItemIndex = state.itemIndex
    if state.currentPlayer then state.itemSelections[state.currentPlayer] = state.itemIndex end
    PushLog(state, "Selected another item.")
end

function TestLab.ToggleRank(state)
    if not state.currentPlayer then return false, "Select a test player first." end
    local rank = state.ranks[state.currentPlayer]
    if rank == "Silverback" then rank = "Macaque" else rank = "Silverback" end
    state.ranks[state.currentPlayer] = rank
    PushLog(state, state.currentPlayer .. " rank changed to " .. rank .. ".")
    return true
end

function TestLab.AddMissedReserve(state)
    local eventTime = state.now
    local ok, reason = AddEntry(state, TestLab.GetItemId(state), nil)
    if ok then PushLog(state, "Added an unsuccessful SR for the selected player and item.", eventTime) end
    return ok, reason
end

function TestLab.AwardItem(state)
    local eventTime = state.now
    local ok, reason = AddEntry(state, nil, TestLab.GetItemId(state))
    if ok then PushLog(state, "Awarded the selected item; its previous reserves are archived as AWARDED.", eventTime) end
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
    PushLog(state, "Advanced simulated time by " .. tostring(days) .. " days.")
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
