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
