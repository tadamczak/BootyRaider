local Raider = BootyRaider

Raider.Services.TestRaid = Raider.Services.TestRaid or {}
local TestRaid = Raider.Services.TestRaid

local classSpecs = {
    { "Warrior", "WARRIOR" }, { "Paladin", "PALADIN" }, { "Hunter", "HUNTER" },
    { "Rogue", "ROGUE" }, { "Priest", "PRIEST" }, { "Shaman", "SHAMAN" },
    { "Mage", "MAGE" }, { "Warlock", "WARLOCK" }, { "Druid", "DRUID" },
}
local rankNames = { "Silverback", "Chimp", "Baboon", "Guest", "Alt", "Macaque" }
local sampleItems = {
    17078, 16921, 16929, 16939, 16955, 33149, 18816, 18832,
    17076, 19364, 17075, 16908, 18423, 18814, 18815, 19137,
}
local sampleLootItems = {
    { 19019, "Thunderfury, Blessed Blade of the Windseeker", "ffff8000" },
    { 17182, "Sulfuras, Hand of Ragnaros", "ffff8000" },
    { 18832, "Brutality Blade", "ffa335ee" }, { 17076, "Bonereaver's Edge", "ffa335ee" },
    { 18816, "Perdition's Blade", "ffa335ee" }, { 19364, "Ashkandi, Greatsword of the Brotherhood", "ffa335ee" },
    { 17075, "Vis'kag the Bloodletter", "ffa335ee" }, { 18814, "Choker of the Fire Lord", "ffa335ee" },
    { 18815, "Essence of the Pure Flame", "ffa335ee" }, { 19137, "Onslaught Girdle", "ffa335ee" },
    { 16908, "Bloodfang Hood", "ffa335ee" }, { 18423, "Head of Onyxia", "ffa335ee" },
}

local state = { active = false, attendance = nil, lootMasterIndex = nil, lootRules = nil, highlyContestedItems = nil }

local function CopyRules(source)
    local result = {}
    local rank, rule
    for rank, rule in pairs(source or {}) do
        result[rank] = { sr = rule.sr and true or false, reyCoin = rule.reyCoin and true or false, csr = rule.csr and true or false, highlyContested = rule.highlyContested and true or false }
    end
    return result
end

local function CopyItems(source)
    local result, seen = {}, {}
    local index
    for index = 1, table.getn(source or {}) do
        local name = string.gsub(tostring(source[index] or ""), "^%s+", ""); name = string.gsub(name, "%s+$", "")
        local key = string.lower(name)
        if name ~= "" and not seen[key] then result[table.getn(result) + 1] = name; seen[key] = true end
    end
    return result
end

local function FindMember(name)
    if not state.attendance then return nil end
    local index
    for index = 1, table.getn(state.attendance.members) do
        local member = state.attendance.members[index]
        if member.name == name then return member end
    end
    return nil
end

local function Reindex()
    if not state.attendance then return end
    local index
    for index = 1, table.getn(state.attendance.members) do state.attendance.members[index].raidIndex = index end
end

function TestRaid.Start()
    state.lootRules = nil; state.highlyContestedItems = nil
    local members = {}
    local index
    for index = 1, 40 do
        local classSpec = classSpecs[math.mod(index - 1, table.getn(classSpecs)) + 1]
        local testName
        if index <= 5 then testName = "NoSR" .. index
        elseif index <= 10 then testName = "NoLoot" .. (index - 5)
        else testName = "Testplayer" .. index end
        members[index] = {
            raidIndex = index, name = testName, raidRank = index == 1 and 2 or (index == 2 and 1 or 0),
            subgroup = math.floor((index - 1) / 5) + 1, level = 60, class = classSpec[1], classFile = classSpec[2],
            zone = index > 34 and "Orgrimmar" or "Test Raid", online = index <= 36, dead = false,
            guildRank = rankNames[math.mod(index - 1, table.getn(rankNames)) + 1], guildMember = index <= 34,
            publicNote = "Test data", officerNote = "", sr = "", srItemIds = nil, loot = {},
        }
        if index <= 5 or index > 10 then
            local lootCount, lootIndex = math.mod(index, 3) + 1, nil
            for lootIndex = 1, lootCount do
                local sampleIndex = math.mod(index + lootIndex - 2, table.getn(sampleLootItems)) + 1
                local sampleItem = sampleLootItems[sampleIndex]
                members[index].loot[lootIndex] = { itemId = sampleItem[1], name = sampleItem[2], link = "|c" .. sampleItem[3] .. "|Hitem:" .. sampleItem[1] .. ":0:0:0|h[" .. sampleItem[2] .. "]|h|r", count = math.mod(lootIndex, 3) == 0 and 2 or 1 }
            end
        end
        if index > 5 then
            local itemId = sampleItems[math.mod(index - 1, table.getn(sampleItems)) + 1]
            members[index].sr = tostring(itemId); members[index].srItemIds = { itemId }
        end
    end
    local missingNames = {}
    for index = 1, table.getn(members) do
        if not members[index].srItemIds then missingNames[table.getn(missingNames) + 1] = members[index].name end
    end
    local unmatchedReservations = {
        { name = "ReserveAltOne", itemIds = { 17075 } },
        { name = "ReserveAltTwo", itemIds = { 16908 } },
        { name = "ReserveAltThree", itemIds = { 18423 } },
    }
    state.attendance = {
        _transient = true, raidName = "Test Raid", sessionStartedAt = time(), updatedBy = UnitName("player") or "Tester", members = members,
        softReserveImport = {
            id = "test-raid", origin = "test", importedAt = time(), missingNames = missingNames,
            unmatchedNames = { "ReserveAltOne", "ReserveAltThree", "ReserveAltTwo" }, unmatchedReservations = unmatchedReservations,
        },
    }
    state.lootMasterIndex = 1; state.active = true
    if Raider.Services.Raid and Raider.Services.Raid.ResetLootSession then Raider.Services.Raid.ResetLootSession() end
    return state.attendance
end

function TestRaid.Stop()
    local wasActive = state.active
    state.active = false; state.attendance = nil; state.lootMasterIndex = nil; state.lootRules = nil; state.highlyContestedItems = nil
    if wasActive and Raider.Services.Raid and Raider.Services.Raid.ResetLootSession then Raider.Services.Raid.ResetLootSession() end
end
function TestRaid.IsActive() return state.active end
function TestRaid.GetAttendance() return state.attendance end
function TestRaid.GetLootRules(defaultRules)
    if not state.lootRules then state.lootRules = CopyRules(defaultRules) end
    return state.lootRules
end
function TestRaid.SaveLootRules(rules) state.lootRules = CopyRules(rules) end
function TestRaid.GetHighlyContestedItems(defaultItems)
    if not state.highlyContestedItems then state.highlyContestedItems = CopyItems(defaultItems) end
    return state.highlyContestedItems
end
function TestRaid.SaveHighlyContestedItems(items)
    state.highlyContestedItems = CopyItems(items)
    return table.getn(state.highlyContestedItems)
end
function TestRaid.IsInRaid() return state.active end
function TestRaid.GetRaidMemberCount() return state.attendance and table.getn(state.attendance.members) or 0 end
function TestRaid.GetRaidMemberInfo(index)
    local member = state.attendance and state.attendance.members[index]
    if not member then return nil end
    return member.name, member.raidRank, member.subgroup, member.level, member.class, member.classFile, member.zone, member.online, member.dead
end
function TestRaid.GetLootMasterInfo() return "master", state.lootMasterIndex end
function TestRaid.IsPlayerIgnored(name)
    local index
    for index = 1, TestRaid.GetRaidMemberCount() do local member = state.attendance.members[index]; if member.name == name then return member.testIgnored and true or false end end
    return false
end
function TestRaid.GetGroupCounts()
    local counts = { 0, 0, 0, 0, 0, 0, 0, 0 }
    local index
    for index = 1, TestRaid.GetRaidMemberCount() do local group = state.attendance.members[index].subgroup; counts[group] = counts[group] + 1 end
    return counts
end
function TestRaid.MoveMemberToGroup(member, targetGroup)
    if not member then return false end
    member = FindMember(member.name)
    if not member then return false end
    local group = math.max(1, math.min(8, tonumber(targetGroup) or 1)); local counts = TestRaid.GetGroupCounts()
    if counts[group] >= 5 and member.subgroup ~= group then return false end
    member.subgroup = group; return true
end
function TestRaid.MoveMemberToSlot(member, targetMember, targetGroup)
    if not member then return false end
    local source = FindMember(member.name)
    local target = targetMember and FindMember(targetMember.name)
    if not source then return false end
    local sourceGroup = source.subgroup
    if target and target ~= source then target.subgroup = sourceGroup end
    source.subgroup = math.max(1, math.min(8, tonumber(targetGroup) or 1))
    return true
end
function TestRaid.RunMemberAction(member, action)
    if not member or not state.attendance then return false end
    local canonicalMember = FindMember(member.name)
    if not canonicalMember then return false end
    member = canonicalMember
    if action == "remove" then
        local lootMaster = state.attendance.members[state.lootMasterIndex or 0]
        local index
        for index = table.getn(state.attendance.members), 1, -1 do if state.attendance.members[index] == member then table.remove(state.attendance.members, index); break end end
        local missing = state.attendance.softReserveImport and state.attendance.softReserveImport.missingNames or {}
        for index = table.getn(missing), 1, -1 do if missing[index] == member.name then table.remove(missing, index) end end
        Reindex()
        state.lootMasterIndex = nil
        if lootMaster ~= member then
            for index = 1, table.getn(state.attendance.members) do if state.attendance.members[index] == lootMaster then state.lootMasterIndex = index; break end end
        end
        return true
    elseif action == "leader" then
        local index
        for index = 1, table.getn(state.attendance.members) do state.attendance.members[index].raidRank = state.attendance.members[index] == member and 2 or (state.attendance.members[index].raidRank == 2 and 0 or state.attendance.members[index].raidRank) end
        return true
    elseif action == "assistant" then member.raidRank = member.raidRank == 1 and 0 or 1; return true
    elseif action == "lootmaster" then state.lootMasterIndex = member.raidIndex; return true
    elseif action == "ignore" then member.testIgnored = not member.testIgnored; return true
    elseif action == "report" then return true end
    return false
end
