local Raider = BootyRaider

Raider.Services = Raider.Services or {}
local CSR = {}
Raider.Services.CSR = CSR

local WINDOW_SECONDS = 60 * 24 * 60 * 60
local POINTS_PER_UNSUCCESSFUL_SR = 10
local KNOWN_RAIDS = { ["Blackwing Lair"] = true, ["Molten Core"] = true, ["Onyxia's Lair"] = true, ["Karazhan10"] = true, ["Zul'Gurub"] = true, ["Other"] = true }

local function Normalize(value)
    return string.lower(tostring(value or ""))
end

local function HasCsrRights(member, rules)
    if type(rules) ~= "table" then return false end
    local policy = Raider.Services.RankPolicy
    local key = policy.GetLootAlias(member.guildRank) or policy.FindLootRank(member.lootRank)
    key = key or policy.FindLootRank(member.guildRank)
    if not key then return false end
    local rule = rules and rules[key]
    if rule then return rule.csr and true or false end
    -- This mirrors the defaults shown by Set Loot Rules before the user saves.
    return key == "silverback"
end

local function ClearTable(target)
    local key
    for key in pairs(target) do target[key] = nil end
end

local function GetSavedAt(raid)
    if not raid then return 0 end
    -- Created At owns the sixty-day window. Start/save dates are only legacy
    -- fallbacks; later metadata edits must never renew eligibility.
    return tonumber(raid.createdAt) or tonumber(raid.startedAt) or tonumber(raid.savedAt) or tonumber(raid.completedAt) or 0
end

local function GetReserveCount(member)
    if type(member.srItems) == "table" then return table.getn(member.srItems), member.srItems, false end
    if type(member.srItemIds) == "table" then return table.getn(member.srItemIds), member.srItemIds, true end
    return 0, nil, false
end

local function GetLootCount(member)
    if type(member.lootItems) == "table" then return table.getn(member.lootItems), member.lootItems end
    if type(member.loot) == "table" then return table.getn(member.loot), member.loot end
    return 0, nil
end

local function GetItemId(item, scalar)
    if scalar then return tonumber(item) end
    if type(item) == "table" then return tonumber(item.itemId or item.id) end
    return tonumber(item)
end

local function GetClass(member)
    if type(member.classFile) == "string" and member.classFile ~= "" then return member.classFile end
    return member.class
end

function CSR.BuildSummary(entries, rules, currentTime, target, rosterData, selectedRaids, searchText, showArchived)
    local summary = target or { players = {} }
    summary.players = summary.players or {}
    local players, states = summary.players, summary.states or {}
    summary.states = states
    local index
    for index = table.getn(players), 1, -1 do table.remove(players, index) end
    for index in pairs(states) do states[index] = nil end

    local now = tonumber(currentTime) or time()
    local cutoff = now - WINDOW_SECONDS
    local archives = showArchived == true
    local query = Normalize(searchText)
    -- Keep the public rules/rosterData arguments for callers. Eligibility belongs
    -- to each saved raid's rules/member records, never current defaults/roster.
    summary.rosterLootRanks = nil
    local ordered = summary.orderedScratch or {}
    summary.orderedScratch = ordered
    for index = table.getn(ordered), 1, -1 do table.remove(ordered, index) end
    for index = 1, table.getn(entries or {}) do
        local savedAt = GetSavedAt(entries[index])
        local raidName = tostring(entries[index].raidName or "Other")
        local filterName = KNOWN_RAIDS[raidName] and raidName or "Other"
        if entries[index].csrEnabled == true and (archives or savedAt >= cutoff) and savedAt <= now
            and (not selectedRaids or selectedRaids[filterName]) then table.insert(ordered, entries[index]) end
    end
    table.sort(ordered, function(a, b)
        local left, right = GetSavedAt(a), GetSavedAt(b)
        if left == right then return tostring(a.id or "") < tostring(b.id or "") end
        return left < right
    end)

    local raidIndex, memberIndex, itemIndex
    for raidIndex = 1, table.getn(ordered) do
        local raid = ordered[raidIndex]
        local savedAt = GetSavedAt(raid)
        for memberIndex = 1, table.getn(raid.members or {}) do
            local member = raid.members[memberIndex]
            local key = Normalize(member.name)
            local lootCount, lootItems = GetLootCount(member)
            local reserveCount, reserveItems, scalarReserves = GetReserveCount(member)
            local hasLoot = lootCount > 0
            local hasRights = HasCsrRights(member, raid.lootRules)
            if key ~= "" and (hasLoot or hasRights) then
                local state = states[key]
                if not state then state = { name = member.name or "Unknown", class = GetClass(member),
                    pending = {}, sources = {}, receivedThisRaid = {} }; states[key] = state end
                if not state.class or state.class == "" then state.class = GetClass(member) end
                state.sources = state.sources or {}
                ClearTable(state.receivedThisRaid)
                -- Receiving an item clears all CSR previously accumulated for
                -- it, irrespective of whether it was reserved in this raid.
                for itemIndex = 1, lootCount do
                    local itemId = GetItemId(lootItems[itemIndex], false)
                    if itemId then state.pending[itemId] = nil; state.sources[itemId] = nil; state.receivedThisRaid[itemId] = true end
                end
                if hasRights then
                    for itemIndex = 1, reserveCount do
                        local reserve = reserveItems[itemIndex]
                        local itemId = GetItemId(reserve, scalarReserves)
                        if itemId and not state.receivedThisRaid[itemId] then
                            local count = type(reserve) == "table" and tonumber(reserve.count) or 1
                            count = count or 1
                            state.pending[itemId] = (state.pending[itemId] or 0) + count
                            state.sources[itemId] = state.sources[itemId] or {}
                            local sources = state.sources[itemId]
                            local previous = sources[table.getn(sources)]
                            if previous and previous.id == raid.id and previous.savedAt == savedAt then
                                previous.count = previous.count + count
                            else
                                local archivedItems = type(raid.csrArchived) == "table" and raid.csrArchived[key]
                                local manuallyArchived = type(archivedItems) == "table" and archivedItems[itemId] == true
                                local expired = savedAt < cutoff
                                sources[table.getn(sources) + 1] = { id = raid.id, raidName = raid.raidName or "Other", savedAt = savedAt,
                                    playerName = state.name, itemId = itemId, manuallyArchived = manuallyArchived,
                                    expired = expired, expiresAt = savedAt + WINDOW_SECONDS,
                                    status = (expired or manuallyArchived) and "ARCHIVED" or "ACTIVE", count = count }
                            end
                        end
                    end
                end
            end
        end
    end

    local _, state
    for _, state in pairs(states) do
        local itemId, missed
        for itemId, missed in pairs(state.pending) do
            if missed > 0 and (query == "" or string.find(Normalize(state.name), query, 1, true)) then
                local activeCount, archivedCount = 0, 0
                local sources = state.sources and state.sources[itemId] or {}
                for index = table.getn(sources), 1, -1 do
                    if sources[index].status == "ACTIVE" then activeCount = activeCount + sources[index].count
                    elseif archives then archivedCount = archivedCount + sources[index].count
                    else table.remove(sources, index) end
                end
                if activeCount + archivedCount > 0 then
                    table.insert(players, { name = state.name, class = state.class, itemId = itemId, items = activeCount, archivedItems = archivedCount,
                        csr = activeCount * POINTS_PER_UNSUCCESSFUL_SR, raids = sources })
                end
            end
        end
    end
    table.sort(players, function(a, b)
        local left, right = string.lower(a.name), string.lower(b.name)
        if left == right then return (tonumber(a.itemId) or 0) < (tonumber(b.itemId) or 0) end
        return left < right
    end)
    summary.cutoff = cutoff
    summary.now = now
    summary.showArchived = archives
    summary.pointsPerItem = POINTS_PER_UNSUCCESSFUL_SR
    return summary
end
