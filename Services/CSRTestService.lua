local Raider = BootyRaider

Raider.Services = Raider.Services or {}
local TestLab = {}
Raider.Services.CSRTest = TestLab

local DAY = 24 * 60 * 60
local ITEMS = { 18404, 17078, 16929 }

local function AddEntry(state, srItemId, lootItemId)
    if not state.currentPlayer then return false end
    state.sequence = state.sequence + 1
    local member = { name = state.currentPlayer, guildRank = state.ranks[state.currentPlayer], srItems = {}, lootItems = {} }
    if srItemId then member.srItems[1] = { itemId = srItemId, count = 1 } end
    if lootItemId then member.lootItems[1] = { itemId = lootItemId, count = 1 } end
    table.insert(state.entries, {
        id = "csr-test-" .. state.sequence, raidName = "CSR Test Raid", savedAt = state.now,
        members = { member },
    })
    state.now = state.now + 60
    return true
end

function TestLab.Create()
    local state = { entries = {}, log = {}, ranks = {}, now = time(), sequence = 0, playerSequence = 0, itemIndex = 1 }
    TestLab.Reset(state)
    return state
end

function TestLab.Reset(state)
    local index
    for index = table.getn(state.entries), 1, -1 do table.remove(state.entries, index) end
    for index = table.getn(state.log), 1, -1 do table.remove(state.log, index) end
    local key
    for key in pairs(state.ranks) do state.ranks[key] = nil end
    state.now = time(); state.sequence = 0; state.playerSequence = 0; state.itemIndex = 1; state.currentPlayer = nil
    table.insert(state.log, "Test reset. Add a player to begin.")
end

function TestLab.AddPlayer(state)
    state.playerSequence = state.playerSequence + 1
    state.currentPlayer = "CSRTestPlayer" .. state.playerSequence
    state.ranks[state.currentPlayer] = "Silverback"
    AddEntry(state, TestLab.GetItemId(state), nil)
    table.insert(state.log, 1, "Added and selected " .. state.currentPlayer .. ".")
end

function TestLab.GetItemId(state)
    return ITEMS[state.itemIndex]
end

function TestLab.NextItem(state)
    state.itemIndex = math.mod(state.itemIndex, table.getn(ITEMS)) + 1
    table.insert(state.log, 1, "Selected another item.")
end

function TestLab.ToggleRank(state)
    if not state.currentPlayer then return end
    local rank = state.ranks[state.currentPlayer]
    if rank == "Silverback" then rank = "Macaque" else rank = "Silverback" end
    state.ranks[state.currentPlayer] = rank
    table.insert(state.log, 1, state.currentPlayer .. " rank changed to " .. rank .. ".")
end

function TestLab.AddMissedReserve(state)
    if AddEntry(state, TestLab.GetItemId(state), nil) then table.insert(state.log, 1, "Added an unsuccessful SR for the selected player and item.") end
end

function TestLab.AwardItem(state)
    if AddEntry(state, nil, TestLab.GetItemId(state)) then table.insert(state.log, 1, "Awarded the selected item; only that item's CSR was cleared.") end
end

function TestLab.AdvanceDays(state, days)
    state.now = state.now + ((tonumber(days) or 0) * DAY)
    table.insert(state.log, 1, "Advanced simulated time by " .. tostring(days) .. " days.")
end

function TestLab.BuildSummary(state, target)
    return Raider.Services.CSR.BuildSummary(state.entries, { silverback = { csr = true }, macaque = { csr = false } }, state.now, target)
end
