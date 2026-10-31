local Raider = BootyRaider

Raider.Services = Raider.Services or {}
local RankPolicy = {}
Raider.Services.RankPolicy = RankPolicy

local lootAliases = { ["officer wukong"] = "chimp", ["chimp banker"] = "chimp" }
local lootRanks = { macaque = true, guest = true, alt = true, baboon = true, chimp = true, silverback = true }

-- Exact names only: callers retain their own empty/default and raw-rank policy.
function RankPolicy.GetLootAlias(value)
    return lootAliases[string.lower(tostring(value or ""))]
end

function RankPolicy.GetDisplayName(value)
    if string.lower(tostring(value or "")) == "officer wukong" then return "Officer (Chimp)" end
    return value
end

-- CSR historically accepts the first known alphabetic token in a saved rank.
function RankPolicy.FindLootRank(value)
    local word
    for word in string.gfind(string.lower(tostring(value or "")), "%a+") do
        if lootRanks[word] then return word end
    end
    return nil
end

-- History controls use current guild authority, never a raid role or the rank
-- frozen in a historical member record. An invalidated directory fails closed.
function RankPolicy.HasOfficerAuthority(name)
    local directory = BootyLib and BootyLib.GuildDirectory
    local member = directory and directory.Find and name and directory.Find(name)
    local rank = member and string.lower(tostring(member.rank or ""))
    return member and member.rankIndex == 0 or rank == "officer wukong" or rank == "mukla"
end
function RankPolicy.CanManageHistory()
    local name = type(UnitName) == "function" and UnitName("player")
    if RankPolicy.HasOfficerAuthority(name) then return true end
    return false, "Only guild officers and the guild master can change Raid Stats and CSR."
end
