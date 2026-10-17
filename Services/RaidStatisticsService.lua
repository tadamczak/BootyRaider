local Raider = BootyRaider

Raider.Services = Raider.Services or {}
local RaidStatistics = {}
Raider.Services.RaidStatistics = RaidStatistics

local RAID_NAMES = { "Blackwing Lair", "Molten Core", "Onyxia's Lair", "Karazhan10", "Zul'Gurub", "Other" }

function RaidStatistics.GetRaidNames() return RAID_NAMES end

local function ResolveLootRank(member)
    return Raider.Services.RankPolicy.GetLootAlias(member and member.guildRank) or (member and member.guildRank) or "Guest"
end

function RaidStatistics.BuildEntry(attendance, saveOptions)
    if not attendance or type(attendance.members) ~= "table" then return nil end
    local importInfo = attendance.softReserveImport
    local raidId = attendance.snapshotId or (importInfo and importInfo.id)
    if not raidId then return nil end
    saveOptions = saveOptions or {}
    local now = time()
    local startedAt, endedAt = tonumber(attendance.sessionStartedAt), tonumber(attendance.endedAt)
    local entry = {
        id = raidId, displayName = attendance.displayName, raidName = attendance.raidName or "Unknown zone", savedAt = now, members = {},
        startedAt = attendance.sessionStartedAt,
        endedAt = endedAt,
        createdAt = attendance.createdAt or startedAt or attendance.lastSavedAt or now,
        modifiedAt = attendance.modifiedAt or attendance.lastSavedAt or now,
        duration = startedAt and endedAt and endedAt >= startedAt and endedAt - startedAt or nil,
        statisticsEnabled = saveOptions.saveRaidStatistics ~= false,
        attendanceEnabled = saveOptions.saveAttendance ~= false,
        csrEnabled = saveOptions.saveCSR == true,
        lootRules = Raider.Database.CopyLootRules(Raider.Database.EnsureRaidLootRules(attendance)),
    }
    local memberIndex, lootIndex, itemIndex, collectionIndex
    local includedNames = {}
    for collectionIndex = 1, 2 do
      local collection = collectionIndex == 1 and attendance.members or attendance.departedMembers
      for memberIndex = 1, table.getn(collection or {}) do
        local member = collection[memberIndex]
        local key = string.lower(member.name or "")
        if not includedNames[key] then
        local lootCount = 0
        for lootIndex = 1, table.getn(member.loot or {}) do lootCount = lootCount + (tonumber(member.loot[lootIndex].count) or 1) end
        local savedMember = {
            name = member.name, class = member.class or "", guildRank = member.guildRank ~= "" and member.guildRank or "Guest",
            lootRank = ResolveLootRank(member),
            attendance = 1, srCount = table.getn(member.srItemIds or {}), lootCount = lootCount, srItems = {}, lootItems = {},
        }
        for itemIndex = 1, table.getn(member.srItemIds or {}) do
            local itemId = tonumber(member.srItemIds[itemIndex])
            local itemName
            if itemId and type(GetItemInfo) == "function" then itemName = GetItemInfo(itemId) end
            savedMember.srItems[itemIndex] = { itemId = itemId, name = itemName, count = 1 }
        end
        for lootIndex = 1, table.getn(member.loot or {}) do
            local loot = member.loot[lootIndex]
            savedMember.lootItems[lootIndex] = { itemId = tonumber(loot.itemId), name = loot.name, count = tonumber(loot.count) or 1 }
        end
        table.insert(entry.members, savedMember)
        includedNames[key] = true
        end
      end
    end
    return entry
end

local function AppendItems(target, source, raid)
    local index
    for index = 1, table.getn(source or {}) do
        local item = source[index]
        local itemId = tonumber(item.itemId)
        if itemId then
            target[table.getn(target) + 1] = {
                itemId = itemId, name = item.name, count = tonumber(item.count) or 1,
                raidId = raid.id, savedAt = raid.savedAt,
                context = tostring(raid.id or "-") .. " | " .. date("%Y-%m-%d", tonumber(raid.savedAt) or 0),
            }
        end
    end
end

local function AppendMissingReserve(target, raid)
    target[table.getn(target) + 1] = {
        missing = true, raidId = raid.id, savedAt = raid.savedAt,
        context = tostring(raid.id or "-") .. " | " .. date("%Y-%m-%d", tonumber(raid.savedAt) or 0),
    }
end

function RaidStatistics.BuildSummary(entries, selectedRaids)
    local summary = { raids = 0, participations = 0, uniquePlayers = 0, sr = 0, loot = 0, players = {} }
    local byName = {}
    local raidIndex, memberIndex
    for raidIndex = 1, table.getn(entries or {}) do
        local raid = entries[raidIndex]
        local selected = type(selectedRaids) == "table" and selectedRaids[raid.id] or (not selectedRaids or raid.id == selectedRaids)
        if selected then
            summary.raids = summary.raids + 1
            for memberIndex = 1, table.getn(raid.members or {}) do
                local member = raid.members[memberIndex]
                local key = string.lower(member.name or "")
                local player = byName[key]
                if not player then
                    player = { name = member.name, class = member.class, guildRank = Raider.Services.RankPolicy.GetDisplayName(member.guildRank), raids = 0, sr = 0, loot = 0, srItems = {}, lootItems = {} }
                    byName[key] = player; summary.players[table.getn(summary.players) + 1] = player
                end
                local attendanceValue=tonumber(member.attendance);if attendanceValue==nil then attendanceValue=1 end
                if raid.attendanceEnabled ~= false then player.raids = player.raids + attendanceValue
                elseif selectedRaids then player.attendanceOff = true end
                player.sr = player.sr + (tonumber(member.srCount) or 0); player.loot = player.loot + (tonumber(member.lootCount) or 0)
                if table.getn(member.srItems or {}) > 0 then AppendItems(player.srItems, member.srItems, raid) else AppendMissingReserve(player.srItems, raid) end
                AppendItems(player.lootItems, member.lootItems, raid)
                if raid.attendanceEnabled ~= false then summary.participations = summary.participations + attendanceValue end
                summary.sr = summary.sr + (tonumber(member.srCount) or 0); summary.loot = summary.loot + (tonumber(member.lootCount) or 0)
            end
        end
    end
    summary.uniquePlayers = table.getn(summary.players)
    table.sort(summary.players, function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end)
    return summary
end

local function ParseDate(value, endOfDay)
    value = tostring(value or "")
    if value == "" then return nil end
    local _, _, year, month, day = string.find(value, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then return false end
    local stamp = time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = endOfDay and 23 or 0, min = endOfDay and 59 or 0, sec = endOfDay and 59 or 0 })
    if not stamp or date("%Y-%m-%d", stamp) ~= value then return false end
    return stamp
end

local function Contains(value, query)
    return string.find(string.lower(tostring(value or "")), query, 1, true) ~= nil
end

local function ItemName(value)
    local text = tostring(value or "")
    local _, _, label = string.find(text, "|h%[(.-)%]|h")
    return label or text
end

local function MatchesItems(items, query)
    local index
    for index = 1, table.getn(items or {}) do
        local item = items[index]
        local savedName = ItemName(item.name or item.itemName)
        local savedLink = ItemName(item.link or item.itemLink)
        if Contains(savedName, query) or Contains(savedLink, query) then return true end
        -- This reads the client's existing item cache only. There is no polling
        -- or item-query event retained by a hidden statistics page.
        if savedName == "" and savedLink == ""
            and type(GetItemInfo) == "function" and tonumber(item.itemId) then
            local name = GetItemInfo(tonumber(item.itemId))
            if Contains(name, query) then return true end
        end
    end
    return false
end

local function MatchesSearch(entry, query)
    if query == "" or Contains(entry.id, query) or Contains(entry.displayName, query) or Contains(entry.raidName or "Other", query) then return true end
    local index
    for index = 1, table.getn(entry.members or {}) do
        local member = entry.members[index]
        if Contains(member.name, query) or MatchesItems(member.srItems, query) or MatchesItems(member.lootItems, query) then return true end
    end
    return false
end

function RaidStatistics.FilterEntries(entries, fromText, toText, target, selectedRaids, searchText)
    local fromStamp, toStamp = ParseDate(fromText, false), ParseDate(toText, true)
    if fromStamp == false or toStamp == false then return nil, "Use date format YYYY-MM-DD." end
    if fromStamp and toStamp and fromStamp > toStamp then return nil, "The From date must be before the To date." end
    local query = string.lower(tostring(searchText or ""))
    local index
    for index = table.getn(target), 1, -1 do table.remove(target, index) end
    for index = 1, table.getn(entries or {}) do
        local savedAt = tonumber(entries[index].savedAt) or 0
        local raidName = tostring(entries[index].raidName or "Other")
        local known = false
        local raidIndex
        for raidIndex = 1, table.getn(RAID_NAMES) do if RAID_NAMES[raidIndex] == raidName then known = true; break end end
        local filterName = known and raidName or "Other"
        if entries[index].statisticsEnabled ~= false and (not selectedRaids or selectedRaids[filterName])
            and (not fromStamp or savedAt >= fromStamp) and (not toStamp or savedAt <= toStamp)
            and MatchesSearch(entries[index], query) then table.insert(target, entries[index]) end
    end
    return target
end
