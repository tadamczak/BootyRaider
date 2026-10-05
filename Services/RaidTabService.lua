local Raider = BootyRaider
Raider.Services.RaidTab = {}
local RaidTab = Raider.Services.RaidTab

-- Reuse one adapter per native view. Shared group controls read their usual
-- setting names while the values come exclusively from the native key family.
function RaidTab.GetGroupSettings(target)
    target = target or {}
    local suffixes = Raider.Database.NativeRaidGroupSuffixes
    local index
    for index = 1, table.getn(suffixes) do
        local suffix = suffixes[index]
        target["raidGroup" .. suffix] = BootyRaiderDB["nativeRaidGroup" .. suffix]
    end
    return target
end

local function Allowed(value) return value ~= nil and value ~= false and value ~= 0 end

function RaidTab.IsInRaid()
    return type(GetNumRaidMembers) == "function" and (tonumber(GetNumRaidMembers()) or 0) > 0
end

function RaidTab.CanManage()
    return (type(IsRaidLeader) == "function" and Allowed(IsRaidLeader()))
        or (type(IsRaidOfficer) == "function" and Allowed(IsRaidOfficer())) or false
end

-- This model reads the physical raid only. No Raider session, attendance, test
-- raid or SavedVariables are consulted or updated by the native Raid tab.
function RaidTab.ReadMembers(target)
    target = target or {}
    local count = type(GetNumRaidMembers) == "function" and tonumber(GetNumRaidMembers()) or 0
    count = math.max(0, math.min(40, math.floor(count or 0)))
    local index, used = 1, 0
    if type(GetRaidRosterInfo) == "function" then
        for index = 1, count do
            local name, rank, subgroup, level, class, classFile, zone, online = GetRaidRosterInfo(index)
            if name then
                used = used + 1
                local member = target[used] or {}
                target[used] = member
                member.name = name; member.raidRank = rank; member.subgroup = subgroup
                member.raidIndex = index
                member.level = level; member.class = class; member.classFile = classFile
                member.zone = zone; member.online = online
            end
        end
    end
    for index = table.getn(target), used + 1, -1 do target[index] = nil end
    return target
end

function RaidTab.CanInvite()
    if type(InviteByName) ~= "function" then return false end
    if type(GetNumRaidMembers) == "function" and (GetNumRaidMembers() or 0) > 0 then return RaidTab.CanManage() end
    return not (type(GetNumPartyMembers) == "function" and (GetNumPartyMembers() or 0) > 0)
        or (type(IsPartyLeader) == "function" and Allowed(IsPartyLeader())) or false
end

function RaidTab.Invite(name)
    name = string.gsub(string.gsub(tostring(name or ""), "^%s+", ""), "%s+$", "")
    if name == "" or string.find(name, "%c") or not RaidTab.CanInvite() then return false end
    InviteByName(name)
    return true
end

function RaidTab.CanConvert()
    return type(ConvertToRaid) == "function" and type(GetNumPartyMembers) == "function"
        and (GetNumPartyMembers() or 0) > 0 and type(GetNumRaidMembers) == "function"
        and (GetNumRaidMembers() or 0) == 0 and type(IsPartyLeader) == "function" and Allowed(IsPartyLeader()) or false
end

function RaidTab.Convert()
    if not RaidTab.CanConvert() then return false end
    ConvertToRaid()
    return true
end

function RaidTab.MoveMemberToSlot(member, targetMember, targetGroup)
    if not RaidTab.CanManage() then return false end
    return Raider.Services.Raid.MoveMemberToSlot(member, targetMember, targetGroup)
end

function RaidTab.RunMemberAction(member, action)
    if action ~= "ignore" and action ~= "report" then
        if not RaidTab.CanManage() then return false end
        if action ~= "remove" and not (type(IsRaidLeader) == "function" and Allowed(IsRaidLeader())) then return false end
    end
    return Raider.Services.Raid.RunMemberAction(member, action)
end
