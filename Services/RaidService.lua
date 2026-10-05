local Raider = BootyRaider
local Match = Raider.Core and Raider.Core.Compatibility and Raider.Core.Compatibility.Match or string.match

Raider.Services.Raid = Raider.Services.Raid or {}
local RaidService = Raider.Services.Raid
RaidService.debugReyCoin = false
RaidService.allowReyCoinSayTests = false

-- Guild data changes only when a roster snapshot is replaced. Reusing this
-- index keeps RAID_ROSTER_UPDATE work proportional to the raid (40 players),
-- rather than to the whole guild on every event.
local indexedGuildData
local indexedGuildMembers = {}
local pendingRollAwards = {}
local pendingLootEchoes = {}
local pendingReyCoinAwards = {}
local pendingSoftReserveTrades = {}
local nextReyCoinTransactionId = 0
local lootSessionAttendance
local lootSessionToken = 0
local pendingLootExpiry
-- Weak keys release replaced loot lists. Values contain records only, never
-- their list/member/attendance (Lua 5.0 weak tables are not ephemerons).
local ordinaryLootIndexes = setmetatable({}, { __mode = "k" })

local function ItemPayload(link)
    local _, _, payload = string.find(tostring(link or ""), "|H(item:[^|]+)|h")
    return payload
end

local function LootQuantity(value)
    return math.max(1, math.floor(tonumber(value) or 1))
end

local function IsOrdinaryReceipt(loot)
    return loot.ordinaryReceipt == true and not loot.awardHistoryKey
        and not loot.tradedFrom and not loot.tradedTo
        and (not loot.rollHistory or table.getn(loot.rollHistory) == 0)
end

local function OrdinaryLootIndex(lootList)
    local index = ordinaryLootIndexes[lootList]
    if index then return index end
    index = {}
    local position
    for position = 1, table.getn(lootList) do
        local loot = lootList[position]
        local payload = IsOrdinaryReceipt(loot) and ItemPayload(loot.link)
        if payload and not index[payload] then index[payload] = loot end
    end
    ordinaryLootIndexes[lootList] = index
    return index
end

local function NotifyPendingReyCoinChanged()
    if RaidService.onReyCoinChanged then RaidService.onReyCoinChanged() end
    if RaidService.onReyCoinPendingChanged then RaidService.onReyCoinPendingChanged() end
end

local function ActiveLootAttendance()
    local testing = Raider.Services.TestRaid
    if testing and testing.IsActive and testing.IsActive() then return testing.GetAttendance() end
    return Raider.Database.GetRaidAttendance()
end

local function FindLootMember(attendance, name)
    if not attendance or not name then return nil end
    local wanted, collectionIndex, memberIndex = string.lower(name), nil, nil
    for collectionIndex = 1, 2 do
        local collection = collectionIndex == 1 and attendance.members or attendance.departedMembers
        for memberIndex = 1, table.getn(collection or {}) do
            local member = collection[memberIndex]
            if member.name and string.lower(member.name) == wanted then return member end
        end
    end
    return nil
end

local function ArchiveLootMember(member)
    if not member then return nil end
    return { name=member.name, class=member.class, classFile=member.classFile,
        level=member.level, guildRank=member.guildRank, guildMember=member.guildMember,
        sr=member.sr, srItemIds=member.srItemIds, srSourceName=member.srSourceName,
        loot=member.loot, srConsumedAt=member.srConsumedAt,
        reyCoinUsedAt=member.reyCoinUsedAt, reyCoinItemLink=member.reyCoinItemLink }
end

local function EnsureConfirmedLootMember(attendance, name, source)
    local member = FindLootMember(attendance, name)
    if member then return member end
    if not source or string.lower(source.name or "") ~= string.lower(name or "") then return nil end
    -- Pending context is transient. A matching confirmed receipt/trade is the
    -- only path that turns an otherwise empty departed recipient into history.
    member = ArchiveLootMember(source)
    member.loot = {}
    if source.srItemIds then
        member.srItemIds = {}
        local index
        for index = 1, table.getn(source.srItemIds) do table.insert(member.srItemIds, source.srItemIds[index]) end
    end
    if source.srConsumedAt then
        member.srConsumedAt = {}
        local itemId, usedAt
        for itemId, usedAt in pairs(source.srConsumedAt) do member.srConsumedAt[itemId] = usedAt end
    end
    attendance.departedMembers = attendance.departedMembers or {}
    table.insert(attendance.departedMembers, member)
    return member
end

local function NotifyLootExpiryChanged()
    if RaidService.onPendingLootExpiryChanged then RaidService.onPendingLootExpiryChanged() end
end

local function ClearPendingLoot()
    local hadTransfers = table.getn(pendingSoftReserveTrades) > 0 or table.getn(pendingReyCoinAwards) > 0
    local key, index
    for key in pairs(pendingRollAwards) do pendingRollAwards[key] = nil end
    for key in pairs(pendingLootEchoes) do pendingLootEchoes[key] = nil end
    for index = table.getn(pendingSoftReserveTrades), 1, -1 do table.remove(pendingSoftReserveTrades, index) end
    for index = table.getn(pendingReyCoinAwards), 1, -1 do
        pendingReyCoinAwards[index].state = "cancelled"
        table.remove(pendingReyCoinAwards, index)
    end
    pendingLootExpiry = nil
    NotifyLootExpiryChanged()
    if hadTransfers then NotifyPendingReyCoinChanged() end
end

local function BindLootSession(attendance, force)
    if not force and lootSessionAttendance == attendance then return end
    lootSessionAttendance = attendance
    lootSessionToken = lootSessionToken + 1
    ordinaryLootIndexes = setmetatable({}, { __mode = "k" })
    ClearPendingLoot()
    if RaidService.onLootSessionChanged then RaidService.onLootSessionChanged() end
end

function RaidService.GetLootSessionToken()
    BindLootSession(ActiveLootAttendance())
    return lootSessionToken
end

function RaidService.IsLootSessionCurrent(token)
    return token ~= nil and token == RaidService.GetLootSessionToken()
end

-- Database notifies replacements; normal roster refresh explicitly transfers
-- the runtime owner before StoreRaidAttendance. No token is durable data.
function RaidService.OnRaidAttendanceChanged(previous, attendance)
    local testing = Raider.Services.TestRaid
    if testing and testing.IsActive and testing.IsActive() then return end
    BindLootSession(attendance)
end

function RaidService.PreserveLootSession(previous, attendance)
    if previous and lootSessionAttendance == previous then lootSessionAttendance = attendance end
end

function RaidService.ResetLootSession()
    BindLootSession(ActiveLootAttendance(), true)
end

local function ScheduleLootExpiry(expiresAt)
    if not pendingLootExpiry or expiresAt < pendingLootExpiry then pendingLootExpiry = expiresAt end
    NotifyLootExpiryChanged()
end

local function StopLootExpiryIfEmpty()
    if pendingLootExpiry and not next(pendingRollAwards) and not next(pendingLootEchoes) then
        pendingLootExpiry = nil
        NotifyLootExpiryChanged()
    end
end

function RaidService.GetNextPendingLootExpiry() return pendingLootExpiry end

-- Cache retention queries are read-only: they must not bind a provider,
-- prune transactions, or invoke callbacks while a window is evicting data.
local function PendingLootHistoryKeys(historyKey, target)
    if ActiveLootAttendance() ~= lootSessionAttendance then return false end
    local index, pending
    if next(pendingRollAwards) then
        local now = GetTime()
        for index, pending in pairs(pendingRollAwards) do
            if pending.lootSessionToken == lootSessionToken and pending.historyKey and pending.at + 30 > now then
                if target then target[pending.historyKey] = true end
                if pending.historyKey == historyKey then return true end
            end
        end
    end
    for index = 1, table.getn(pendingSoftReserveTrades) do
        pending = pendingSoftReserveTrades[index]
        if pending.lootSessionToken == lootSessionToken and pending.historyKey
            and (pending.state == "awaiting_receipt" or pending.state == "awaiting_trade") then
            if target then target[pending.historyKey] = true end
            if pending.historyKey == historyKey then return true end
        end
    end
    for index = 1, table.getn(pendingReyCoinAwards) do
        pending = pendingReyCoinAwards[index]
        if pending.lootSessionToken == lootSessionToken and pending.historyKey
            and (pending.state == "awaiting_item" or pending.state == "awaiting_trade") then
            if target then target[pending.historyKey] = true end
            if pending.historyKey == historyKey then return true end
        end
    end
    return false
end

function RaidService.IsLootHistoryPending(historyKey)
    if not historyKey then return false end
    return PendingLootHistoryKeys(historyKey)
end

function RaidService.FillPendingLootHistoryKeys(target)
    if not target then return nil end
    PendingLootHistoryKeys(nil, target)
    return target
end

function RaidService.PrunePendingLoot(now)
    now = tonumber(now) or GetTime()
    local key, pending
    pendingLootExpiry = nil
    for key, pending in pairs(pendingRollAwards) do
        local expiresAt = pending.at + 30
        if expiresAt <= now then pendingRollAwards[key] = nil
        elseif not pendingLootExpiry or expiresAt < pendingLootExpiry then pendingLootExpiry = expiresAt end
    end
    for key, pending in pairs(pendingLootEchoes) do
        if pending.expiresAt <= now then pendingLootEchoes[key] = nil
        elseif not pendingLootExpiry or pending.expiresAt < pendingLootExpiry then pendingLootExpiry = pending.expiresAt end
    end
    NotifyLootExpiryChanged()
end

local function FindPendingReyCoinIndex(transfer)
    local index
    for index = 1, table.getn(pendingReyCoinAwards) do
        if pendingReyCoinAwards[index] == transfer then return index end
    end
end

local function CompletePendingReyCoin(transfer, recipient, traded)
    if not RaidService.IsLootSessionCurrent(transfer.lootSessionToken) then return false end
    local index = FindPendingReyCoinIndex(transfer)
    if index and transfer.recipientStates then
        EnsureConfirmedLootMember(ActiveLootAttendance(), recipient, transfer.recipientStates[string.lower(recipient or "")])
    end
    if not index or not RaidService.SetReyCoinUsage(recipient, transfer.link, true, transfer.lootSessionToken) then return false end
    if not RaidService.IsLootSessionCurrent(transfer.lootSessionToken) then return false end
    index = FindPendingReyCoinIndex(transfer)
    if not index then return false end
    if traded then RaidService.RecordReyCoinTrade(transfer, recipient) end
    transfer.state = "completed"
    table.remove(pendingReyCoinAwards, index)
    NotifyPendingReyCoinChanged()
    if traded and RaidService.onReyCoinTradeConfirmed then
        RaidService.onReyCoinTradeConfirmed(transfer.carrier, recipient, transfer.link, transfer.historyKey)
    end
    return true
end

local raidNameScratch = {}

local defaultSoftReserveRanks = { silverback = true, chimp = true, baboon = true }
local defaultHighlyContestedRanks = { silverback = true, chimp = true }
local defaultReyCoinRanks = { silverback = true, chimp = true, baboon = true }
local function GetSoftReserveRank(member)
    local rank = string.lower(member.guildRank or "")
    return Raider.Services.RankPolicy.GetLootAlias(rank) or (rank ~= "" and rank) or "guest"
end

local contestedSource, contestedNames = nil, {}
local function CurrentHighlyContestedItems()
    local items = Raider.Database.GetHighlyContestedItems and Raider.Database.GetHighlyContestedItems() or {}
    local testRaid = Raider.Services.TestRaid
    if testRaid and testRaid.IsActive and testRaid.IsActive() then items = testRaid.GetHighlyContestedItems(items) end
    return items
end

function RaidService.IsHighlyContestedItem(itemReference, items)
    items = items or CurrentHighlyContestedItems()
    if contestedSource ~= items then
        contestedSource = items
        contestedNames = {}
        local index
        for index = 1, table.getn(items) do
            contestedNames[string.lower(items[index])] = true
        end
    end
    local reference = tostring(itemReference or "")
    local name = Match(reference, "|h%[([^%]]+)%]|h")
    if not name and tonumber(reference) and type(GetItemInfo) == "function" then name = GetItemInfo(tonumber(reference)) end
    if not name and not tonumber(reference) then name = reference end
    return name and contestedNames[string.lower(name)] and true or false
end

function RaidService.GetInvalidSoftReserveItemIds(member, rules, contestedItems)
    local invalid = {}
    local itemIds = member and member.srItemIds
    if not itemIds then return invalid end
    rules = rules or Raider.Database.GetLootRules()
    local rank = GetSoftReserveRank(member)
    local rule = rules and rules[rank]
    local canReserve = (rule and rule.sr) or (not rule and defaultSoftReserveRanks[rank])
    local canContested = canReserve and ((rule and rule.highlyContested) or (not rule and defaultHighlyContestedRanks[rank]))
    local index
    for index = 1, table.getn(itemIds) do
        local itemId = itemIds[index]
        if not canReserve or (not canContested and RaidService.IsHighlyContestedItem(itemId, contestedItems)) then
            invalid[table.getn(invalid) + 1] = itemId
        end
    end
    return invalid
end

function RaidService.GetSoftReserveIssues(attendance, rules)
    local issues = { missingNames = {}, invalidNames = {}, unmatchedNames = {} }
    if not attendance or not attendance.members then return issues end
    local importInfo = attendance.softReserveImport
    issues.unmatchedNames = importInfo and importInfo.unmatchedNames or issues.unmatchedNames
    rules = rules or Raider.Database.GetLootRules()
    local index
    for index = 1, table.getn(attendance.members) do
        local member = attendance.members[index]
        if member.name then
            local rank = GetSoftReserveRank(member)
            local rule = rules and rules[rank]
            local canReserve = (rule and rule.sr) or (not rule and defaultSoftReserveRanks[rank])
            local hasReserve = member.srItemIds and table.getn(member.srItemIds) > 0
            if canReserve and not hasReserve and importInfo then
                table.insert(issues.missingNames, member.name)
            elseif hasReserve and table.getn(RaidService.GetInvalidSoftReserveItemIds(member, rules)) > 0 then
                table.insert(issues.invalidNames, member.name)
            end
        end
    end
    table.sort(issues.missingNames)
    table.sort(issues.invalidNames)
    return issues
end

function RaidService.GetSoftReserveRollRights(itemLink)
    local reserved, allowed, names, rankRights, rankNames, reyCoinRights, reyCoinUsed = {}, {}, {}, {}, {}, {}, {}
    local itemId = tonumber(Match(tostring(itemLink or ""), "item:(%d+)"))
    if not itemId then return false, reserved, allowed, names, rankRights, rankNames, reyCoinRights, reyCoinUsed end
    local testRaid = Raider.Services.TestRaid
    local testing = testRaid and testRaid.IsActive and testRaid.IsActive()
    local attendance = testing and testRaid.GetAttendance() or Raider.Database.GetRaidAttendance()
    if not testing and not Raider.raidSessionTransitionPending then
        local raidCount = GetNumRaidMembers() or 0
        if raidCount > 0 then
            local needsSync = not attendance or not attendance.members or table.getn(attendance.members) ~= raidCount
            if not needsSync then
                local name
                for name in pairs(raidNameScratch) do raidNameScratch[name] = nil end
                local memberIndex
                for memberIndex = 1, table.getn(attendance.members) do
                    local member = attendance.members[memberIndex]
                    if member.name then raidNameScratch[string.lower(member.name)] = true end
                end
                local raidIndex
                for raidIndex = 1, raidCount do
                    local raidName = GetRaidRosterInfo(raidIndex)
                    if raidName and not raidNameScratch[string.lower(raidName)] then needsSync = true; break end
                end
            end
            if needsSync then RaidService.SaveRoster(); attendance = Raider.Database.GetRaidAttendance() end
        end
    end
    local rules = Raider.Database.GetLootRules()
    if testing then rules = testRaid.GetLootRules(rules) end
    local contested = RaidService.IsHighlyContestedItem(itemLink)
    local hasReserve = false
    if attendance and attendance.members then
        local memberIndex
        for memberIndex = 1, table.getn(attendance.members) do
            local member = attendance.members[memberIndex]
            local itemIds = member.srItemIds
            if member.name then
                local rank = GetSoftReserveRank(member)
                local rule = rules and rules[rank]
                local name = string.lower(member.name)
                local displayRank = Raider.Services.RankPolicy.GetDisplayName(member.guildRank)
                rankNames[name] = (displayRank ~= member.guildRank and displayRank) or (rank and rank ~= "" and rank) or (member.guildRank and member.guildRank ~= "" and member.guildRank) or "Guest"
                if (rule and rule.sr) or (not rule and defaultSoftReserveRanks[rank]) then
                    rankRights[name] = true
                end
                if (rule and rule.reyCoin) or (not rule and defaultReyCoinRanks[rank]) then reyCoinRights[name] = true end
                local usedAt = tonumber(member.reyCoinUsedAt) or 0
                if usedAt > 0 and usedAt >= (tonumber(attendance.sessionStartedAt) or 0) then reyCoinUsed[name] = true end
            end
            if member.name and itemIds then
                local reserveIndex
                for reserveIndex = 1, table.getn(itemIds) do
                    local consumedAt = member.srConsumedAt and tonumber(member.srConsumedAt[itemId]) or 0
                    if tonumber(itemIds[reserveIndex]) == itemId
                        and (not consumedAt or consumedAt < (tonumber(attendance.sessionStartedAt) or 0)) then
                        local name = string.lower(member.name)
                        reserved[name] = true
                        local rank = GetSoftReserveRank(member)
                        local rule = rules and rules[rank]
                        local canContested = (rule and rule.highlyContested) or (not rule and defaultHighlyContestedRanks[rank])
                        if rankRights[name] and (not contested or canContested) then
                            hasReserve = true
                            allowed[name] = true
                            names[table.getn(names) + 1] = member.name
                        end
                        break
                    end
                end
            end
        end
    end
    return hasReserve, reserved, allowed, names, rankRights, rankNames, reyCoinRights, reyCoinUsed
end

-- Roll strategies are stateless and shared by all rounds. Transmog remains a
-- separate carrier pool; SR takes precedence over ordinary main-pool rules.
local transmogPolicy = {
    pool = "transmog",
    valid = function() return true end,
}
local srPolicy = {
    pool = "main",
    valid = function(roll, name, range)
        return range == 102 and roll.srReserved[name] and roll.srAllowed[name]
    end,
    reason = function(roll, name)
        if not roll.srRankRights[name] then
            return "no SR for rank " .. (roll.srRankNames[name] or "Unknown")
        end
        if not roll.srReserved[name] then return "no SR for this item" end
        if not roll.srAllowed[name] then return "no loot rights for Highly Contested item" end
        return "wrong roll, use /roll 102"
    end,
}
local reyCoinPolicy = {
    pool = "main", usesReyCoin = true,
    valid = function(roll, name, range, used)
        return roll.reyCoinRights[name] and not used
    end,
    reason = function(roll, name, range, used, usedItem)
        if not roll.reyCoinRights[name] then
            return "no loot rights to Reycoin for rank " .. (roll.srRankNames[name] or "Unknown")
        end
        return "Reycoin already used for: " .. tostring(usedItem or "unknown item")
    end,
}
local regularPolicy = { pool = "main", valid = function() return true end }
local wrongRangePolicy = {
    pool = "main", valid = function() return false end,
    reason = function() return "wrong roll, use /roll 98, 99, 100 or 101" end,
}
local openItemPolicies = {
    [99] = regularPolicy, [100] = regularPolicy, [101] = reyCoinPolicy,
}

function RaidService.GetLootRollPolicy(roll, range)
    if range == 98 then return transmogPolicy end
    if roll.allowedTypes then
        if range == 102 then return srPolicy end
        return openItemPolicies[range] or wrongRangePolicy
    end
    if roll.srRestricted then return srPolicy end
    return openItemPolicies[range] or wrongRangePolicy
end

function RaidService.ProcessLootRoll(roll, name, value, range, reyCoinUsed, reyCoinItem)
    local normalizedName = string.lower(name)
    if roll.allowedNames and not roll.allowedNames[normalizedName] then return nil, "not selected for this roll" end
    local policy = RaidService.GetLootRollPolicy(roll, range)
    local selected = not roll.allowedTypes or roll.allowedTypes[range]
    local valid = selected and policy.valid(roll, normalizedName, range, reyCoinUsed) and true or false
    local invalidReason = not selected and "wrong roll, use a selected roll type"
        or (not valid and policy.reason(roll, normalizedName, range, reyCoinUsed, reyCoinItem) or nil)

    local rollKey = name .. ":" .. range
    local previousResult = roll.seen[rollKey]
    if previousResult and not (valid and previousResult.valid == false) then return nil, invalidReason end

    local priority = valid and range or -1
    local results = roll.results
    local position = table.getn(results) + 1
    while position > 1 and (results[position - 1].priority < priority
        or (results[position - 1].priority == priority and results[position - 1].value < value)) do
        position = position - 1
    end
    local result = { name = name, value = value, range = range, priority = priority,
        valid = valid, invalidReason = invalidReason, shortInvalidReason = invalidReason }
    table.insert(results, position, result)
    roll.seen[rollKey] = result
    if valid and policy.pool == "transmog" then
        if value > roll.transmogHighest then
            roll.transmogHighest = value; roll.transmogWinner = name; roll.transmogResult = result
        end
    elseif valid and (priority > roll.highestPriority
        or (priority == roll.highestPriority and value > roll.highest)) then
        roll.highestPriority = priority; roll.highest = value; roll.winner = name
        roll.winnerResult = result; roll.winnerUsesReyCoin = policy.usesReyCoin and true or false
    end
    return result, invalidReason
end

function RaidService.FinalizeLootRoll(roll)
    if roll.srRestricted and not roll.allowedTypes and not roll.winner then
        local onlyName
        local allowedCount = 0
        local normalizedName
        for normalizedName in pairs(roll.srAllowed or {}) do
            allowedCount = allowedCount + 1
            onlyName = normalizedName
            if allowedCount > 1 then break end
        end
        if allowedCount == 1 then
            local nameIndex
            for nameIndex = 1, table.getn(roll.srNames or {}) do
                if string.lower(roll.srNames[nameIndex]) == onlyName then onlyName = roll.srNames[nameIndex]; break end
            end
            local automatic = { name = onlyName, value = 0, range = 102, priority = 102,
                valid = true, automatic = true }
            table.insert(roll.results, 1, automatic)
        end
    end
    local main, transmog
    local index
    for index = 1, table.getn(roll.results or {}) do
        local result = roll.results[index]
        if result.valid ~= false then
            if result.range == 98 then
                if not transmog or result.value > transmog.value then transmog = result end
            elseif not main or result.priority > main.priority
                or (result.priority == main.priority and result.value > main.value) then main = result end
        end
    end
    roll.highestPriority = main and main.priority or -1
    roll.transmogHighest = transmog and transmog.value or -1
    roll.transmogWinner = transmog and transmog.name or nil
    roll.transmogResult = transmog
    local chosen = roll.manualWinnerResult
    if chosen and chosen.valid == false then chosen = nil; roll.manualWinnerResult = nil end
    if not chosen then chosen = transmog or main end
    roll.winnerResult = chosen
    roll.winner = chosen and chosen.name or nil
    roll.highest = chosen and chosen.value or -1
    roll.winnerUsesReyCoin = chosen and chosen.range == 101 or false
    roll.tradeWinner = chosen and chosen.range == 98 and main and main.name ~= chosen.name and main.name or nil
    roll.tradeWinnerResult = roll.tradeWinner and main or nil
    return roll.winner, roll.tradeWinner
end

function RaidService.ConfirmSoftReserveReceipt(recipient, itemLink, expectedSessionToken)
    if expectedSessionToken ~= nil and not RaidService.IsLootSessionCurrent(expectedSessionToken) then return false end
    local itemId = tonumber(Match(tostring(itemLink or ""), "item:(%d+)"))
    local attendance = ActiveLootAttendance()
    if not recipient or not itemId or not attendance or not attendance.members then return false end
    local member = FindLootMember(attendance, recipient)
    if member then
        member.srConsumedAt = member.srConsumedAt or {}
        member.srConsumedAt[itemId] = time()
        return true
    end
    return false
end

function RaidService.GetReyCoinAttendance()
    local testRaid = Raider.Services.TestRaid
    local testing = testRaid and testRaid.IsActive and testRaid.IsActive()
    return testing and testRaid.GetAttendance() or Raider.Database.GetRaidAttendance()
end

function RaidService.HasUsedReyCoin(playerName)
    local attendance = RaidService.GetReyCoinAttendance()
    if not playerName or not attendance or not attendance.members then return false end
    local member = FindLootMember(attendance, playerName)
    if member then
        local usedAt = tonumber(member.reyCoinUsedAt) or 0
        local used = usedAt > 0 and usedAt >= (tonumber(attendance.sessionStartedAt) or 0)
        return used, used and member.reyCoinItemLink or nil
    end
    return false
end

function RaidService.SetReyCoinUsage(playerName, itemLink, used, expectedSessionToken)
    if expectedSessionToken ~= nil and not RaidService.IsLootSessionCurrent(expectedSessionToken) then return false end
    local attendance = RaidService.GetReyCoinAttendance()
    if not playerName then return false end
    local member = FindLootMember(attendance, playerName)
    local testRaid = Raider.Services.TestRaid
    if not member and not Raider.raidSessionTransitionPending and not (testRaid and testRaid.IsActive and testRaid.IsActive()) and (GetNumRaidMembers() or 0) > 0 then
        RaidService.SaveRoster()
        attendance = Raider.Database.GetRaidAttendance()
        member = FindLootMember(attendance, playerName)
    end
    if expectedSessionToken ~= nil and not RaidService.IsLootSessionCurrent(expectedSessionToken) then return false end
    if not member then
        return false
    end
    member.reyCoinUsedAt = used and time() or nil
    member.reyCoinItemLink = used and itemLink or nil
    if RaidService.onReyCoinChanged then RaidService.onReyCoinChanged() end
    return true
end

function RaidService.ResetReyCoinUsage(attendance)
    if attendance and attendance.members then
        local index, collectionIndex
        for collectionIndex = 1, 2 do
            local collection = collectionIndex == 1 and attendance.members or attendance.departedMembers
            for index = 1, table.getn(collection or {}) do
                collection[index].reyCoinUsedAt = nil
                collection[index].reyCoinItemLink = nil
            end
        end
    end
    pendingReyCoinAwards = {}
    NotifyPendingReyCoinChanged()
end

function RaidService.ConsumeReyCoin(playerName, itemLink)
    return RaidService.SetReyCoinUsage(playerName, itemLink, true)
end

function RaidService.GetBagItemCount(itemLink)
    local itemId = Match(tostring(itemLink or ""), "item:(%d+)")
    if not itemId then return 0 end
    local total = 0
    local bag, slot
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and Match(link, "item:(%d+)") == itemId then
                local texture, count = GetContainerItemInfo(bag, slot)
                total = total + (count or 1)
            end
        end
    end
    return total
end

function RaidService.QueueReyCoinAward(winner, itemLink, carrier, reyCoinRollers, historyKey, rollHistory, quantity)
    local token = RaidService.GetLootSessionToken()
    if not lootSessionAttendance then return false end
    local itemId = Match(tostring(itemLink or ""), "item:(%d+)")
    if not winner or not itemId then return false end
    reyCoinRollers = reyCoinRollers or {}
    reyCoinRollers[string.lower(winner)] = true
    local recipientStates, name = {}, nil
    for name in pairs(reyCoinRollers) do recipientStates[string.lower(name)] = ArchiveLootMember(FindLootMember(lootSessionAttendance, name)) end
    nextReyCoinTransactionId = nextReyCoinTransactionId + 1
    if RaidService.debugReyCoin and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("Raider Reycoin trace: queued winner=" .. tostring(winner)
            .. " carrier=" .. tostring(carrier or winner) .. " item=" .. tostring(itemId))
    end
    table.insert(pendingReyCoinAwards, {
        transactionId = nextReyCoinTransactionId, state = "awaiting_item",
        lootSessionToken = token,
        winner = winner, carrier = carrier or winner, link = itemLink, itemId = itemId,
        reyCoinRollers = reyCoinRollers, historyKey = historyKey, rollHistory = rollHistory,
        recipientStates = recipientStates,
        quantity = quantity and LootQuantity(quantity) or nil,
    })
    NotifyPendingReyCoinChanged()
    return true
end

function RaidService.HasPendingReyCoinAward()
    RaidService.GetLootSessionToken()
    return table.getn(pendingReyCoinAwards) > 0
end

function RaidService.GetPendingReyCoinTransfers()
    RaidService.GetLootSessionToken()
    return pendingReyCoinAwards
end

function RaidService.CancelPendingReyCoinTransfer(transfer)
    local index
    for index = 1, table.getn(pendingReyCoinAwards) do
        if pendingReyCoinAwards[index] == transfer then
            transfer.state = "cancelled"
            table.remove(pendingReyCoinAwards, index)
            NotifyPendingReyCoinChanged()
            return true
        end
    end
    return false
end

function RaidService.ConfirmPendingReyCoinTransfer(transfer)
    if not transfer or not transfer.carrierReceived or string.lower(transfer.carrier or "") == string.lower(transfer.winner or "") then return false end
    return CompletePendingReyCoin(transfer, transfer.winner, true)
end

function RaidService.ConfirmReyCoinReceipt(recipient, itemLink)
    RaidService.GetLootSessionToken()
    local itemId = Match(tostring(itemLink or ""), "item:(%d+)")
    if not itemId or not recipient then return false end
    if RaidService.debugReyCoin and DEFAULT_CHAT_FRAME and table.getn(pendingReyCoinAwards) > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Raider Reycoin trace: receipt recipient=" .. tostring(recipient)
            .. " item=" .. tostring(itemId) .. " pending=" .. tostring(table.getn(pendingReyCoinAwards)))
    end
    local index
    for index = table.getn(pendingReyCoinAwards), 1, -1 do
        local pending = pendingReyCoinAwards[index]
        if pending.itemId == itemId then
            if string.lower(recipient) == string.lower(pending.winner) then
                return CompletePendingReyCoin(pending, pending.winner, false)
            end
            if string.lower(recipient) == string.lower(pending.carrier) then
                if pending.state ~= "awaiting_trade" then
                    pending.carrierReceived = true
                    pending.state = "awaiting_trade"
                    NotifyPendingReyCoinChanged()
                end
                return true
            end
        end
    end
    if RaidService.debugReyCoin and DEFAULT_CHAT_FRAME and table.getn(pendingReyCoinAwards) > 0 then
        local first = pendingReyCoinAwards[1]
        DEFAULT_CHAT_FRAME:AddMessage("Raider Reycoin trace: receipt unmatched; first pending winner="
            .. tostring(first.winner) .. " carrier=" .. tostring(first.carrier) .. " item=" .. tostring(first.itemId))
    end
    return false
end

function RaidService.ConfirmReyCoinLoot(message)
    local itemId = Match(tostring(message or ""), "item:(%d+)")
    if not itemId then return false end
    local _, _, itemLink = string.find(message, "(|c%x+|Hitem:.-|h%[.-%]|h|r)")
    if not itemLink then _, _, itemLink = string.find(message, "(|Hitem:.-|h%[.-%]|h)") end
    local _, _, parsedQuantity = string.find(message, "x(%d+)")
    local quantity = tonumber(parsedQuantity) or 1
    local selfMessage = itemLink and ((LOOT_ITEM_SELF and string.format(LOOT_ITEM_SELF, itemLink) == message)
        or (LOOT_ITEM_SELF_MULTIPLE and string.format(LOOT_ITEM_SELF_MULTIPLE, itemLink, quantity) == message))
    local recipient
    if selfMessage or string.find(message, "You receive loot", 1, true) or string.find(message, "You receive item", 1, true) then
        recipient = UnitName("player")
    else
        recipient = Match(message, "^%s*([^%s:]+)")
        if recipient == "You" then recipient = UnitName("player") end
    end
    return RaidService.ConfirmReyCoinReceipt(recipient, message)
end

function RaidService.IsPendingReyCoinTrade(sender, itemLink)
    RaidService.GetLootSessionToken()
    local itemId = Match(tostring(itemLink or ""), "item:(%d+)")
    if not sender or not itemId then return false end
    local index
    for index = 1, table.getn(pendingReyCoinAwards) do
        local pending = pendingReyCoinAwards[index]
        if pending.itemId == itemId and string.lower(pending.carrier) == string.lower(sender) and pending.carrierReceived then return true end
    end
    return false
end

function RaidService.ConfirmReyCoinTrade(sender, recipient, itemLink)
    RaidService.GetLootSessionToken()
    local itemId = Match(tostring(itemLink or ""), "item:(%d+)")
    if not sender or not recipient or not itemLink then return false end
    local itemName = string.gsub(string.gsub(tostring(itemLink), "^%[", ""), "%]$", "")
    local failure = "no matching item"
    local index
    for index = table.getn(pendingReyCoinAwards), 1, -1 do
        local pending = pendingReyCoinAwards[index]
        local pendingName = Match(tostring(pending.link or ""), "|h%[([^%]]+)%]|h")
        local itemMatches = (itemId and pending.itemId == itemId)
            or (not itemId and pendingName and string.lower(pendingName) == string.lower(itemName))
        if itemMatches then
            if string.lower(pending.carrier) ~= string.lower(sender) then failure = "sender mismatch"
            elseif not pending.reyCoinRollers or not pending.reyCoinRollers[string.lower(recipient)] then failure = "recipient not in valid Reycoin rolls"
            else failure = "usage save failed" end
        end
        if itemMatches and pending.state == "awaiting_trade"
            and string.lower(pending.carrier) == string.lower(sender)
            and pending.reyCoinRollers and pending.reyCoinRollers[string.lower(recipient)] then
            if CompletePendingReyCoin(pending, recipient, true) then
                return true, pending.link
            end
        end
    end
    return false, failure
end

function RaidService.PrefixLootMasterMessage(message)
    return Raider.Services.LootMessages.Prefix(tostring(message or ""))
end

function RaidService.QueueLootAwardForReceipt(recipient, itemLink, historyKey, lines, quantity)
    local token = RaidService.GetLootSessionToken()
    if not lootSessionAttendance then return false end
    local itemId = Match(tostring(itemLink or ""), "item:(%d+)")
    if not recipient or not itemId then return false end
    local copy = lines and {} or nil
    local index
    for index = 1, table.getn(lines or {}) do copy[index] = lines[index] end
    local now = GetTime()
    pendingRollAwards[string.lower(recipient) .. ":" .. itemId] = {
        lines = copy, at = now, lootSessionToken = token, historyKey = historyKey,
        recipientState = ArchiveLootMember(FindLootMember(lootSessionAttendance, recipient)),
        quantity = quantity and LootQuantity(quantity) or nil }
    ScheduleLootExpiry(now + 30)
    return true
end

function RaidService.QueueRollHistoryForAward(recipient, itemLink, lines)
    if not lines or table.getn(lines) == 0 then return end
    RaidService.QueueLootAwardForReceipt(recipient, itemLink, nil, lines)
end

local function TakeRollHistory(recipient, itemId)
    local key = string.lower(recipient or "") .. ":" .. tostring(itemId or "")
    local pending = pendingRollAwards[key]
    pendingRollAwards[key] = nil
    StopLootExpiryIfEmpty()
    if pending and pending.lootSessionToken == lootSessionToken and GetTime() - pending.at < 30 then return pending.lines, pending end
end

local function AppendRollHistory(loot, history)
    if not history then return end
    loot.rollHistory = loot.rollHistory or {}
    local index
    for index = 1, table.getn(history) do
        table.insert(loot.rollHistory, history[index])
    end
end

function RaidService.RecordReyCoinTrade(pending, recipient)
    if not pending then return false end
    if pending.lootSessionToken ~= nil and not RaidService.IsLootSessionCurrent(pending.lootSessionToken) then return false end
    local attendance = ActiveLootAttendance()
    if not attendance or not attendance.members or not pending or not recipient then return false end
    local sender = pending.carrier
    local senderMember, recipientMember = FindLootMember(attendance, sender), FindLootMember(attendance, recipient)
    local index
    if not recipientMember then return false end
    local loot, candidateIndex, fallbackIndex
    if senderMember and senderMember.loot then
        for index = table.getn(senderMember.loot), 1, -1 do
            local candidate = senderMember.loot[index]
            local candidatePayload, pendingPayload = ItemPayload(candidate.link), ItemPayload(pending.link)
            if tostring(candidate.itemId or "") == tostring(pending.itemId or "") and not candidate.tradedTo
                and (not candidatePayload or not pendingPayload or candidatePayload == pendingPayload) then
                if pending.historyKey and candidate.awardHistoryKey == pending.historyKey then
                    candidateIndex = index; break
                elseif not candidate.awardHistoryKey and not fallbackIndex then
                    fallbackIndex = index
                elseif not pending.historyKey and not candidateIndex then
                    candidateIndex = index
                end
            end
        end
        candidateIndex = candidateIndex or fallbackIndex
        if candidateIndex then
            local candidate = senderMember.loot[candidateIndex]
            local available = LootQuantity(candidate.count)
            local quantity = pending.quantity and LootQuantity(pending.quantity)
                or (IsOrdinaryReceipt(candidate) and 1 or available)
            quantity = math.min(available, quantity)
            if quantity < available then
                loot = {}
                local key, value
                for key, value in pairs(candidate) do
                    if key ~= "rollHistory" then loot[key] = value end
                end
                AppendRollHistory(loot, candidate.rollHistory)
                candidate.count = available - quantity
                attendance.nextLootRecordId = (tonumber(attendance.nextLootRecordId) or 0) + 1
                loot.sourceRecordId = candidate.recordId
                loot.recordId = attendance.nextLootRecordId
                loot.count = quantity
            else
                loot = table.remove(senderMember.loot, candidateIndex)
                ordinaryLootIndexes[senderMember.loot] = nil
            end
        end
    end
    if not loot then
        local itemName = Match(tostring(pending.link or ""), "%[([^%]]+)%]") or "Unknown item"
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(pending.link)
        attendance.nextLootRecordId = (tonumber(attendance.nextLootRecordId) or 0) + 1
        loot = { recordId = attendance.nextLootRecordId, itemId = pending.itemId,
            name = itemName, link = pending.link, icon = itemTexture,
            count = pending.quantity and LootQuantity(pending.quantity) or 1 }
    end
    if not loot.rollHistory or table.getn(loot.rollHistory) == 0 then
        AppendRollHistory(loot, pending.rollHistory)
    end
    loot.rollHistory = loot.rollHistory or {}
    table.insert(loot.rollHistory, sender .. " traded " .. pending.link .. " to " .. recipient .. ".")
    loot.tradedFrom = sender
    loot.tradedTo = recipient
    loot.ordinaryReceipt = nil
    loot.awardHistoryKey = loot.awardHistoryKey or pending.historyKey
    recipientMember.loot = recipientMember.loot or {}
    table.insert(recipientMember.loot, loot)
    return true
end

local function NotifySoftReserveTradeChanged()
    if RaidService.onReyCoinPendingChanged then RaidService.onReyCoinPendingChanged() end
end

function RaidService.HasPendingSoftReserveAward()
    RaidService.GetLootSessionToken()
    return table.getn(pendingSoftReserveTrades) > 0
end

function RaidService.HasPendingSoftReserveTrade()
    RaidService.GetLootSessionToken()
    local index
    for index = 1, table.getn(pendingSoftReserveTrades) do
        if pendingSoftReserveTrades[index].state == "awaiting_trade" then return true end
    end
    return false
end

function RaidService.QueueSoftReserveTrade(recipient, itemLink, carrier, historyKey, rollHistory, quantity)
    local token = RaidService.GetLootSessionToken()
    if not lootSessionAttendance then return false end
    local itemId = tonumber(Match(tostring(itemLink or ""), "item:(%d+)"))
    if not recipient or not carrier or not itemId then return false end
    local copy = {}
    local index
    for index = 1, table.getn(rollHistory or {}) do copy[index] = rollHistory[index] end
    table.insert(pendingSoftReserveTrades, {
        recipient = recipient, carrier = carrier, link = itemLink, itemId = itemId,
        recipientState = ArchiveLootMember(FindLootMember(lootSessionAttendance, recipient)),
        historyKey = historyKey, rollHistory = copy, state = "awaiting_receipt", lootSessionToken = token,
        quantity = quantity and LootQuantity(quantity) or nil })
    NotifySoftReserveTradeChanged()
    return true
end

function RaidService.ConfirmSoftReserveCarrierReceipt(carrier, itemLink)
    RaidService.GetLootSessionToken()
    local itemId = tonumber(Match(tostring(itemLink or ""), "item:(%d+)"))
    if not carrier or not itemId then return false end
    local index
    for index = 1, table.getn(pendingSoftReserveTrades) do
        local pending = pendingSoftReserveTrades[index]
        if pending.state == "awaiting_receipt" and pending.itemId == itemId
            and string.lower(pending.carrier) == string.lower(carrier) then
            pending.state = "awaiting_trade"
            NotifySoftReserveTradeChanged()
            return true
        end
    end
    return false
end

function RaidService.IsPendingSoftReserveTrade(sender, itemLink)
    RaidService.GetLootSessionToken()
    local itemId = tonumber(Match(tostring(itemLink or ""), "item:(%d+)"))
    local index
    for index = 1, table.getn(pendingSoftReserveTrades) do
        local pending = pendingSoftReserveTrades[index]
        if pending.state == "awaiting_trade" and pending.itemId == itemId
            and string.lower(pending.carrier) == string.lower(sender or "") then return true end
    end
    return false
end

function RaidService.ConfirmSoftReserveTrade(sender, recipient, itemReference)
    RaidService.GetLootSessionToken()
    if not sender or not recipient or not itemReference then return false end
    local itemName = Match(tostring(itemReference), "%[([^%]]+)%]") or tostring(itemReference)
    local itemId = tonumber(Match(tostring(itemReference), "item:(%d+)"))
    local index
    for index = 1, table.getn(pendingSoftReserveTrades) do
        local pending = pendingSoftReserveTrades[index]
        local expectedName = Match(tostring(pending.link), "%[([^%]]+)%]")
        if pending.state == "awaiting_trade"
            and string.lower(pending.carrier) == string.lower(sender)
            and string.lower(pending.recipient) == string.lower(recipient)
            and ((itemId and pending.itemId == itemId)
                or (expectedName and string.lower(expectedName) == string.lower(itemName))) then
            EnsureConfirmedLootMember(ActiveLootAttendance(), recipient, pending.recipientState)
            if not RaidService.ConfirmSoftReserveReceipt(recipient, pending.link, pending.lootSessionToken) then return false end
            RaidService.RecordReyCoinTrade(pending, recipient)
            table.remove(pendingSoftReserveTrades, index)
            NotifySoftReserveTradeChanged()
            if RaidService.onReyCoinTradeConfirmed then
                RaidService.onReyCoinTradeConfirmed(sender, recipient, pending.link, pending.historyKey)
            end
            return true, pending.link
        end
    end
    return false
end

local function GetGuildMemberIndex(guildData)
    if guildData == indexedGuildData then return indexedGuildMembers end
    indexedGuildData = guildData
    indexedGuildMembers = {}
    if guildData and guildData.members then
        local guildIndex
        for guildIndex = 1, table.getn(guildData.members) do
            local member = guildData.members[guildIndex]
            indexedGuildMembers[string.lower(member.name or "")] = member
        end
    end
    return indexedGuildMembers
end

local function HasRecordedLootState(member)
    return member and ((member.loot and table.getn(member.loot) > 0)
        or (tonumber(member.reyCoinUsedAt) or 0) > 0
        or (member.srConsumedAt and next(member.srConsumedAt) ~= nil))
end

function RaidService.ResetRecordedLoot(attendance)
    if attendance then
        local collectionIndex, memberIndex
        for collectionIndex = 1, 2 do
            local collection = collectionIndex == 1 and attendance.members or attendance.departedMembers
            for memberIndex = 1, table.getn(collection or {}) do collection[memberIndex].loot = {} end
        end
        RaidService.ResetReyCoinUsage(attendance)
        for memberIndex = table.getn(attendance.departedMembers or {}), 1, -1 do
            if not HasRecordedLootState(attendance.departedMembers[memberIndex]) then table.remove(attendance.departedMembers, memberIndex) end
        end
        if attendance.departedMembers and table.getn(attendance.departedMembers) == 0 then attendance.departedMembers = nil end
    else RaidService.ResetReyCoinUsage(attendance) end
    RaidService.ResetLootSession()
end

function RaidService.SaveRoster()
    Raider.Diagnostics.Count("scans")
    Raider.Database.Ensure()
    local guildData = Raider.Database.GetRosterData()
    if type(IsInGuild) == "function" then
        local inGuild = IsInGuild()
        if not inGuild or inGuild == 0 then guildData = nil end
    end
    local guildMembers = GetGuildMemberIndex(guildData)

    local previousLoot, previousReserves, previousReyCoin, previousReyCoinItems, previousSrConsumed = {}, {}, {}, {}, {}
    local currentRaidName = GetRealZoneText() or ""
    local previousAttendance = Raider.Database.GetRaidAttendance()
    local activeSession = Raider.Services.RaidRes and Raider.Services.RaidRes.HasSession(previousAttendance)
    local total = GetNumRaidMembers() or 0
    -- Zone transitions can briefly expose an empty roster or a graveyard zone.
    -- Never replace an active session with that transient context.
    if activeSession and total == 0 then return table.getn(previousAttendance.members or {}) end
    local preservePrevious = previousAttendance and previousAttendance.members
        and (activeSession or previousAttendance.raidName == currentRaidName)
    if preservePrevious then
        local previousIndex, collectionIndex
        for collectionIndex = 1, 2 do
            local collection = collectionIndex == 1 and previousAttendance.departedMembers or previousAttendance.members
            for previousIndex = 1, table.getn(collection or {}) do
                local previousMember = collection[previousIndex]
                local key = string.lower(previousMember.name or "")
                previousLoot[key] = previousMember.loot or {}
                previousReserves[key] = { text = previousMember.sr or "", itemIds = previousMember.srItemIds, sourceName = previousMember.srSourceName }
                previousReyCoin[key] = previousMember.reyCoinUsedAt
                previousReyCoinItems[key] = previousMember.reyCoinItemLink
                previousSrConsumed[key] = previousMember.srConsumedAt
            end
        end
    end

    local members, presentNames = {}, {}
    local raidIndex
    for raidIndex = 1, total do
        local name, raidRank, subgroup, level, class, classFile, zone, online, dead = GetRaidRosterInfo(raidIndex)
        if name then
            presentNames[string.lower(name)] = true
            local guildMember = guildMembers[string.lower(name)]
            local previousReserve = previousReserves[string.lower(name)]
            table.insert(members, {
                raidIndex = raidIndex,
                name = name,
                raidRank = tonumber(raidRank) or 0,
                subgroup = subgroup or 0,
                level = level or 0,
                class = class or (guildMember and guildMember.class) or "",
                classFile = classFile or "",
                zone = zone or "",
                online = online and true or false,
                dead = dead and true or false,
                guildRank = guildMember and guildMember.rank or "",
                publicNote = guildMember and guildMember.publicNote or "",
                officerNote = guildMember and guildMember.officerNote or "",
                guildMember = guildMember and true or false,
                sr = previousReserve and previousReserve.text or "",
                srItemIds = previousReserve and previousReserve.itemIds or nil,
                srSourceName = previousReserve and previousReserve.sourceName or nil,
                srConsumedAt = previousSrConsumed[string.lower(name)],
                reyCoinUsedAt = previousReyCoin[string.lower(name)],
                reyCoinItemLink = previousReyCoinItems[string.lower(name)],
                loot = previousLoot[string.lower(name)] or {},
            })
        end
    end

    -- A departing player leaves the physical roster, but their confirmed loot
    -- remains part of this session. Rejoins move that same aggregate back above.
    local departedMembers
    if preservePrevious then
        local archivedNames, collectionIndex, previousIndex = {}, nil, nil
        for collectionIndex = 1, 2 do
            local collection = collectionIndex == 1 and previousAttendance.members or previousAttendance.departedMembers
            for previousIndex = 1, table.getn(collection or {}) do
                local member = collection[previousIndex]
                local key = string.lower(member.name or "")
                if key ~= "" and not presentNames[key] and not archivedNames[key] and HasRecordedLootState(member) then
                    departedMembers = departedMembers or {}
                    table.insert(departedMembers, collectionIndex == 1 and ArchiveLootMember(member) or member)
                    archivedNames[key] = true
                end
            end
        end
    end

    local scanTimestamp = time()
    local attendance = {
        addonVersion = Raider.version,
        scannedAt = scanTimestamp,
        scannedAtText = date("%Y-%m-%d %H:%M:%S", scanTimestamp),
        raidName = activeSession and previousAttendance.raidName or currentRaidName,
        updatedBy = UnitName("player"),
        members = members,
        departedMembers = departedMembers,
        snapshotId = previousAttendance and previousAttendance.snapshotId or nil,
        _loadedSnapshotId = previousAttendance and previousAttendance._loadedSnapshotId or nil,
        sessionStartedAt = previousAttendance and previousAttendance.sessionStartedAt or nil,
        lastSavedAt = previousAttendance and previousAttendance.lastSavedAt or nil,
        softReserveImport = preservePrevious and previousAttendance.softReserveImport or nil,
        nextLootRecordId = preservePrevious and previousAttendance.nextLootRecordId or 0,
    }
    if preservePrevious then RaidService.PreserveLootSession(previousAttendance, attendance) end
    Raider.Database.StoreRaidAttendance(attendance)
    return table.getn(members)
end

local function PendingReceiptTransfer(recipient, itemId)
    local normalizedName = string.lower(recipient)
    local index, pending
    for index = 1, table.getn(pendingSoftReserveTrades) do
        pending = pendingSoftReserveTrades[index]
        if pending.lootSessionToken == lootSessionToken and pending.state == "awaiting_receipt"
            and tostring(pending.itemId) == tostring(itemId)
            and string.lower(pending.carrier) == normalizedName then return pending end
    end
    for index = 1, table.getn(pendingReyCoinAwards) do
        pending = pendingReyCoinAwards[index]
        if pending.lootSessionToken == lootSessionToken and pending.state == "awaiting_item"
            and tostring(pending.itemId) == tostring(itemId)
            and string.lower(pending.carrier) == normalizedName then return pending end
    end
end

function RaidService.RecordLoot(message, confirmedAward)
    RaidService.GetLootSessionToken()
    local attendance = ActiveLootAttendance()
    if not attendance or not attendance.members or not message then return false end

    local itemStart, itemEnd, itemLink = string.find(message, "(|c%x+|Hitem:.-|h%[.-%]|h|r)")
    if not itemLink then itemStart, itemEnd, itemLink = string.find(message, "(|Hitem:.-|h%[.-%]|h)") end
    if not itemLink then return false end
    local _, _, parsedItemId = string.find(itemLink, "item:(%d+)")
    local _, _, parsedQuantity = string.find(string.sub(message, itemEnd + 1), "x(%d+)")
    local quantity = LootQuantity(parsedQuantity)
    local recipient
    local selfMessage = (LOOT_ITEM_SELF and string.format(LOOT_ITEM_SELF, itemLink) == message)
        or (LOOT_ITEM_SELF_MULTIPLE and string.format(LOOT_ITEM_SELF_MULTIPLE, itemLink, quantity) == message)
    if selfMessage or string.find(message, "You receive loot", 1, true) or string.find(message, "You receive item", 1, true) then
        recipient = UnitName("player")
    else
        local prefix = string.sub(message, 1, math.max(0, (itemStart or 1) - 1))
        local prefixName = Match(prefix, "^%s*([^%s:]+)")
        local found = FindLootMember(attendance, prefixName)
        recipient = found and found.name or prefixName
    end
    if not recipient then return false end

    local member = FindLootMember(attendance, recipient)
    if not member and parsedItemId then
        local pending = pendingRollAwards[string.lower(recipient) .. ":" .. parsedItemId]
        if pending and pending.lootSessionToken == lootSessionToken and GetTime() - pending.at < 30 then
            member = EnsureConfirmedLootMember(attendance, recipient, pending.recipientState)
        end
    end
    if not member then return false end

    local _, _, parsedItemName = string.find(itemLink, "%[([^%]]+)%]")
    local itemName = parsedItemName or "Unknown item"
    local itemId = parsedItemId or itemName
    local receiptKey = string.lower(recipient) .. ":" .. tostring(itemId)
    local echo = pendingLootEchoes[receiptKey]
    if echo and not confirmedAward then
        if GetTime() <= echo.expiresAt then
            echo.count = echo.count - 1
            if echo.count <= 0 then pendingLootEchoes[receiptKey] = nil end
            StopLootExpiryIfEmpty()
            return false
        end
        pendingLootEchoes[receiptKey] = nil
        StopLootExpiryIfEmpty()
    end
    local rollHistory, award = TakeRollHistory(recipient, itemId)
    local transfer = not award and PendingReceiptTransfer(recipient, itemId)
    local ordinary = not confirmedAward and not award and not transfer
    member.loot = member.loot or {}
    local payload = ordinary and ItemPayload(itemLink)
    local ordinaryIndex = payload and OrdinaryLootIndex(member.loot)
    local previous = ordinaryIndex and ordinaryIndex[payload]
    if previous then
        previous.count = LootQuantity(previous.count) + quantity
        return true
    end
    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
    attendance.nextLootRecordId = (tonumber(attendance.nextLootRecordId) or 0) + 1
    local loot = { recordId = attendance.nextLootRecordId, itemId = itemId, name = itemName,
        link = itemLink, icon = itemTexture, count = quantity,
        ordinaryReceipt = ordinary and true or nil,
        awardHistoryKey = award and award.historyKey or (transfer and transfer.historyKey) }
    AppendRollHistory(loot, rollHistory)
    table.insert(member.loot, loot)
    if ordinaryIndex then ordinaryIndex[payload] = loot end
    return true
end

function RaidService.RecordPendingAwardReceipt(recipient, itemLink)
    RaidService.GetLootSessionToken()
    local itemId = Match(tostring(itemLink or ""), "item:(%d+)")
    if not recipient or not itemId then return false end
    local key = string.lower(recipient) .. ":" .. itemId
    local pending = pendingRollAwards[key]
    if not pending then return false end
    if pending.at + 30 <= GetTime() then
        pendingRollAwards[key] = nil
        StopLootExpiryIfEmpty()
        return false
    end
    local quantitySuffix = pending.quantity and (" x" .. pending.quantity) or ""
    local recorded = RaidService.RecordLoot(recipient .. " receives loot: " .. itemLink .. quantitySuffix, true)
    if recorded then
        local echo = pendingLootEchoes[key]
        if not echo or GetTime() > echo.expiresAt then
            echo = { count = 0, expiresAt = GetTime() + 5 }
            pendingLootEchoes[key] = echo
        end
        echo.count = echo.count + 1
        ScheduleLootExpiry(echo.expiresAt)
    end
    return recorded
end

function RaidService.IsPlayerIgnored(name)
    if type(GetNumIgnores) ~= "function" or type(GetIgnoreName) ~= "function" then return false end
    local index
    for index = 1, GetNumIgnores() do
        if string.lower(GetIgnoreName(index) or "") == string.lower(name or "") then return true end
    end
    return false
end

function RaidService.RunMemberAction(member, action)
    if not member then return false end
    local name = member.name
    if action == "leader" and type(PromoteToLeader) == "function" then
        PromoteToLeader(name)
    elseif action == "assistant" then
        if (tonumber(member.raidRank) or 0) == 1 and type(DemoteAssistant) == "function" then DemoteAssistant(name)
        elseif type(PromoteToAssistant) == "function" then PromoteToAssistant(name) end
    elseif action == "remove" and type(UninviteByName) == "function" then
        UninviteByName(name)
    elseif action == "lootmaster" and type(SetLootMethod) == "function" then
        SetLootMethod("master", name)
    elseif action == "ignore" then
        if RaidService.IsPlayerIgnored(name) and type(DelIgnore) == "function" then DelIgnore(name)
        elseif type(AddIgnore) == "function" then AddIgnore(name) end
    elseif action == "report" then
        if type(ReportPlayer) == "function" then ReportPlayer(name)
        elseif type(ToggleHelpFrame) == "function" then ToggleHelpFrame() end
    else
        return false
    end
    return true
end

function RaidService.GetGroupCounts()
    local counts = { 0, 0, 0, 0, 0, 0, 0, 0 }
    local raidIndex
    for raidIndex = 1, (GetNumRaidMembers() or 0) do
        local _, _, subgroup = GetRaidRosterInfo(raidIndex)
        subgroup = math.max(1, math.min(8, tonumber(subgroup) or 1))
        counts[subgroup] = counts[subgroup] + 1
    end
    return counts
end

function RaidService.GetLootMasterInfo()
    local lootMethod, partyLootMasterIndex, raidLootMasterIndex = GetLootMethod()
    return lootMethod, raidLootMasterIndex
end

function RaidService.IsPlayerLootMaster()
    if (GetNumRaidMembers() or 0) == 0 then return false end
    local method, _, index = GetLootMethod()
    if method ~= "master" or not index then return false end
    local unit = "raid" .. index
    if type(UnitIsUnit) == "function" and UnitIsUnit(unit, "player") then return true end
    return UnitName(unit) == UnitName("player")
end

function RaidService.GetRaidMemberCount()
    return GetNumRaidMembers() or 0
end

function RaidService.IsInRaid()
    return RaidService.GetRaidMemberCount() > 0
end

local function HasRaidPermission(value)
    return value ~= nil and value ~= false and value ~= 0
end

function RaidService.CanReadyCheck()
    if type(DoReadyCheck) ~= "function" or not RaidService.IsInRaid() then return false end
    return (type(IsRaidLeader) == "function" and HasRaidPermission(IsRaidLeader()))
        or (type(IsRaidOfficer) == "function" and HasRaidPermission(IsRaidOfficer())) or false
end

function RaidService.ReadyCheck()
    if not RaidService.CanReadyCheck() then return false end
    DoReadyCheck()
    return true
end

function RaidService.SendRaidWarning(message, prefix)
    if not RaidService.IsInRaid() or type(SendChatMessage) ~= "function" then return false, "You must be in a raid." end
    local playerName = UnitName("player")
    local index, canWarn
    for index = 1, RaidService.GetRaidMemberCount() do
        local name, rank = GetRaidRosterInfo(index)
        local isPlayer = type(UnitIsUnit) == "function" and UnitIsUnit("raid" .. index, "player") or name == playerName
        if isPlayer then canWarn = (tonumber(rank) or 0) > 0; break end
    end
    if not canWarn then return false, "Only the raid leader or an assistant can send a Raid Warning." end
    local ok=pcall(SendChatMessage,prefix == false and message or RaidService.PrefixLootMasterMessage(message),"RAID_WARNING")
    if not ok then return false,"The raid warning could not be sent." end
    return true
end

function RaidService.SendLootRules(rules)
    rules = rules or Raider.Database.GetLootRules()
    local sent, errorMessage = RaidService.SendLootMessage("RulesHeader")
    if not sent then return false, errorMessage end
    local ranks = {
        { "Silverback", "silverback" }, { "Chimp", "chimp" }, { "Baboon", "baboon" },
        { "Guest", "guest" }, { "Alt", "alt" }, { "Macaque", "macaque" },
    }
    local index
    for index = 1, table.getn(ranks) do
        local rankName, rankKey = ranks[index][1], ranks[index][2]
        local rule = rules[rankKey]
        local hasSR = rule and rule.sr or (not rule and defaultSoftReserveRanks[rankKey])
        local hasContested = hasSR and (rule and rule.highlyContested or (not rule and defaultHighlyContestedRanks[rankKey]))
        local hasReyCoin = rule and rule.reyCoin or (not rule and defaultReyCoinRanks[rankKey])
        local hasCSR = rule and rule.csr or (not rule and rankKey == "silverback")
        local parts = {}
        if hasSR then parts[table.getn(parts) + 1] = hasContested and "SR + HCI" or "SR" end
        if hasReyCoin then parts[table.getn(parts) + 1] = "RC" end
        if hasCSR then parts[table.getn(parts) + 1] = "CSR" end
        local rights = table.getn(parts) > 0 and table.concat(parts, ", ") or "None"
        sent, errorMessage = RaidService.SendLootMessage("RankRules", {rank=rankName, rights=rights})
        if not sent then return false, errorMessage end
    end
    return true
end

function RaidService.SendRaidWarningList(names)
    if not names or table.getn(names) == 0 then return false, "There are no raid members missing a Soft Reserve." end
    return RaidService.SendLootMessage("MissingSR", {players=table.concat(names, ", "), playerNames=names})
end

function RaidService.SendLootMessage(key, values)
    return Raider.Services.LootMessages.Send(key, values, RaidService.SendRaidWarning)
end

function RaidService.GetRaidMemberInfo(index)
    return GetRaidRosterInfo(index)
end

local function FindCurrentRaidMember(name)
    if not name then return nil, nil end
    local wanted = string.lower(tostring(name))
    local index
    for index = 1, RaidService.GetRaidMemberCount() do
        local currentName, _, subgroup = GetRaidRosterInfo(index)
        if currentName and string.lower(currentName) == wanted then return index, tonumber(subgroup) or 0 end
    end
    return nil, nil
end

function RaidService.MoveMemberToGroup(member, targetGroup)
    if not member or type(SetRaidSubgroup) ~= "function" then return false end
    local memberIndex, currentGroup = FindCurrentRaidMember(member.name)
    if not memberIndex then return false end
    local group = math.max(1, math.min(8, tonumber(targetGroup) or 1))
    local counts = RaidService.GetGroupCounts()
    if counts[group] >= 5 and currentGroup ~= group then return false end
    if currentGroup == group then return true end
    SetRaidSubgroup(memberIndex, group)
    member.raidIndex = memberIndex
    member.subgroup = group
    return true
end

function RaidService.MoveMemberToSlot(member, targetMember, targetGroup)
    if not member then return false end
    local memberIndex, memberGroup = FindCurrentRaidMember(member.name)
    if not memberIndex then return false end
    local targetIndex, targetMemberGroup = nil, nil
    if targetMember then targetIndex, targetMemberGroup = FindCurrentRaidMember(targetMember.name) end
    if targetIndex and targetIndex ~= memberIndex and memberGroup ~= targetMemberGroup and type(SwapRaidSubgroup) == "function" then
        SwapRaidSubgroup(memberIndex, targetIndex)
        return true
    end
    if targetIndex and memberGroup == targetMemberGroup then return true end
    return RaidService.MoveMemberToGroup(member, targetGroup)
end

function RaidService.GetFilterValues(members)
    local classes, ranks, seenClasses, seenRanks = {}, {}, {}, {}
    local memberIndex
    for memberIndex = 1, table.getn(members) do
        local className = members[memberIndex].class ~= "" and members[memberIndex].class or "Unknown"
        local rankName = members[memberIndex].guildRank ~= "" and members[memberIndex].guildRank or "Guest"
        if not seenClasses[className] then seenClasses[className] = true; classes[table.getn(classes) + 1] = className end
        if not seenRanks[rankName] then seenRanks[rankName] = true; ranks[table.getn(ranks) + 1] = rankName end
    end
    return classes, ranks
end
