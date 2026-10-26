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

-- Numeric keys retain their existing contract. A name-only key is the full
-- normalized name; it never reaches native item APIs as an invented item ID.
function CSR.NormalizeItemReference(value)
    local id = tonumber(value)
    if id then
        if id >= 1 and id <= 2147483647 and id == math.floor(id) then return id end
        return nil
    end
    local name = Raider.Services.ItemReference.NormalizeName(value)
    return name and string.lower(name) or nil
end

local function ItemIdentity(item, scalar)
    local reference, name
    if not scalar and type(item) == "table" then
        reference = tonumber(item.itemId or item.id) or Raider.Services.ItemReference.Id(item.link or item.itemLink)
        name = Raider.Services.ItemReference.Name(item.name or item.itemName or item.link or item.itemLink)
    else reference = item end
    local key = CSR.NormalizeItemReference(reference) or CSR.NormalizeItemReference(name)
    if not name and type(key) == "string" then name = Raider.Services.ItemReference.NormalizeName(reference) end
    return key, name
end

local function GetClass(member)
    if type(member.classFile) == "string" and member.classFile ~= "" then return member.classFile end
    return member.class
end

local function ConsumeSources(state, key)
    if not key or state.receivedThisRaid[key] then return end
    state.receivedThisRaid[key] = true
    local sources = state.sources[key]
    local count = state.sourceCounts[key] or 0
    for index = (state.awardedThrough[key] or 0) + 1, count do sources[index].status = "AWARDED" end
    state.awardedThrough[key] = count
end

function CSR.BuildSummary(entries, rules, currentTime, target, rosterData, selectedRaids, searchText, showArchived)
    local summary = target or { players = {} }
    summary.players = summary.players or {}
    local players, states = summary.players, summary.states or {}
    summary.states = states
    local index
    for index = table.getn(players), 1, -1 do players[index] = nil end
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
    for index = table.getn(ordered), 1, -1 do ordered[index] = nil end
    local orderedCount = 0
    for index = 1, table.getn(entries or {}) do
        local savedAt = GetSavedAt(entries[index])
        local raidName = tostring(entries[index].raidName or "Other")
        local filterName = KNOWN_RAIDS[raidName] and raidName or "Other"
        if entries[index].csrEnabled == true and (archives or savedAt >= cutoff) and savedAt <= now
            and (not selectedRaids or selectedRaids[filterName]) then
            orderedCount = orderedCount + 1; ordered[orderedCount] = entries[index]
        end
    end
    table.sort(ordered, function(a, b)
        local left, right = GetSavedAt(a), GetSavedAt(b)
        if left == right then return tostring(a.id or "") < tostring(b.id or "") end
        return left < right
    end)

    -- Saved labels bridge manual names to known IDs without depending on the
    -- client's changing cache. Ambiguous names never merge two distinct IDs.
    local nameIds, labels = {}, {}
    for _, raid in ipairs(ordered) do
        for _, member in ipairs(raid.members or {}) do
            local _, reserves, scalar = GetReserveCount(member)
            local _, loot = GetLootCount(member)
            for collectionIndex = 1, 2 do
                local values = collectionIndex == 1 and reserves or loot
                for _, item in ipairs(values or {}) do
                    local key, name = ItemIdentity(item, collectionIndex == 1 and scalar)
                    if key and name then
                        labels[key] = labels[key] or name
                        local nameKey = CSR.NormalizeItemReference(name)
                        if type(key) == "number" and nameKey then
                            if nameIds[nameKey] == nil then nameIds[nameKey] = key
                            elseif nameIds[nameKey] ~= key then nameIds[nameKey] = false end
                        end
                    end
                end
            end
        end
    end
    local function Resolve(key) return nameIds[key] or key end
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
                    pending = {}, sources = {}, sourceCounts = {}, awardedThrough = {}, receivedThisRaid = {} }; states[key] = state end
                if not state.class or state.class == "" then state.class = GetClass(member) end
                state.sources = state.sources or {}
                ClearTable(state.receivedThisRaid)
                if hasRights then
                    for itemIndex = 1, reserveCount do
                        local reserve = reserveItems[itemIndex]
                        local originalKey = ItemIdentity(reserve, scalarReserves)
                        local itemId = Resolve(originalKey)
                        if itemId then
                            local count = type(reserve) == "table" and tonumber(reserve.count) or 1
                            count = count or 1
                            state.pending[itemId] = (state.pending[itemId] or 0) + count
                            state.sources[itemId] = state.sources[itemId] or {}
                            local sources = state.sources[itemId]
                            local sourceCount = state.sourceCounts[itemId] or 0
                            local previous = sources[sourceCount]
                            if previous and previous.id == raid.id and previous.savedAt == savedAt and previous.itemId == originalKey then
                                previous.count = previous.count + count
                            else
                                local archivedItems = type(raid.csrArchived) == "table" and raid.csrArchived[key]
                                local manuallyArchived = type(archivedItems) == "table" and archivedItems[originalKey] == true
                                local expired = savedAt < cutoff
                                sourceCount = sourceCount + 1; state.sourceCounts[itemId] = sourceCount
                                sources[sourceCount] = { id = raid.id, raidName = raid.raidName or "Other", savedAt = savedAt,
                                    playerName = state.name, itemId = originalKey, manuallyArchived = manuallyArchived,
                                    expired = expired, expiresAt = savedAt + WINDOW_SECONDS,
                                    status = (expired or manuallyArchived) and "ARCHIVED" or "ACTIVE", count = count }
                            end
                        end
                    end
                end
                -- A receipt consumes the balance through this raid, but its
                -- provenance remains available in the archived ledger. Process
                -- reserves first so a reserved-and-received item is retained too.
                for itemIndex = 1, lootCount do
                    local key, name = ItemIdentity(lootItems[itemIndex], false)
                    ConsumeSources(state, Resolve(key))
                    -- Even an ambiguous label can consume its name-only bucket;
                    -- it must never consume a different known numeric ID.
                    ConsumeSources(state, name and CSR.NormalizeItemReference(name))
                end
            end
        end
    end

    local _, state
    local playerCount = 0
    for _, state in pairs(states) do
        local itemId, missed
        for itemId, missed in pairs(state.pending) do
            if missed > 0 and (query == "" or string.find(Normalize(state.name), query, 1, true)) then
                local activeCount, archivedCount, kept = 0, 0, 0
                local sources = state.sources and state.sources[itemId] or {}
                local sourceCount = table.getn(sources)
                for index = 1, sourceCount do
                    local source = sources[index]
                    if source.status == "ACTIVE" then activeCount = activeCount + source.count
                    elseif archives then archivedCount = archivedCount + source.count end
                    if source.status == "ACTIVE" or archives then
                        kept = kept + 1; sources[kept] = source
                    end
                end
                for index = sourceCount, kept + 1, -1 do sources[index] = nil end
                if activeCount + archivedCount > 0 then
                    playerCount = playerCount + 1
                    players[playerCount] = { name = state.name, class = state.class, itemId = itemId, itemName = labels[itemId], items = activeCount, archivedItems = archivedCount,
                        csr = activeCount * POINTS_PER_UNSUCCESSFUL_SR, raids = sources }
                end
            end
        end
    end
    table.sort(players, function(a, b)
        local left, right = string.lower(a.name), string.lower(b.name)
        if left == right then
            if type(a.itemId) ~= type(b.itemId) then return type(a.itemId) == "number" end
            if type(a.itemId) == "number" and type(b.itemId) == "number" then return a.itemId < b.itemId end
            return tostring(a.itemId) < tostring(b.itemId)
        end
        return left < right
    end)
    summary.cutoff = cutoff
    summary.now = now
    summary.showArchived = archives
    summary.pointsPerItem = POINTS_PER_UNSUCCESSFUL_SR
    return summary
end
