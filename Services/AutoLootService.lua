local Raider = BootyRaider
Raider.Services.AutoLoot = {}
local AutoLoot = Raider.Services.AutoLoot
local exclusionCache, inclusionCache = {}, {}
local function Normalize(name)
    return string.lower(string.gsub(string.gsub(tostring(name or ""), "%s+", " "), "^%s*(.-)%s*$", "%1"))
end
local function Matches(name, text, cache)
    text = tostring(text or "")
    if cache.text ~= text then
        cache.patterns = {}
        local entry
        for entry in string.gfind(text, "[^,]+") do
            entry = Normalize(entry)
            if entry ~= "" then
                entry = string.gsub(entry, "%s*%*%s*", "*")
                entry = string.gsub(entry, "([%%%^%$%(%)%.%[%]%+%-%?])", "%%%1")
                entry = string.gsub(entry, "%*", ".*")
                table.insert(cache.patterns, "^" .. entry .. "$")
            end
        end
        cache.text = text
    end
    local index
    for index = 1, table.getn(cache.patterns) do
        if string.find(name, cache.patterns[index]) then return true end
    end
    return false
end
function AutoLoot.IsEnabled(mode, shiftAtOpen)
    return mode == "auto" or (mode == "shift" and shiftAtOpen == true)
end
function AutoLoot.Allows(name, quality, rarities, exclusions, inclusions)
    name = Normalize(name)
    if name == "" or Matches(name, exclusions, exclusionCache) then return false end
    if type(quality) ~= "number" or quality < 0 or quality ~= math.floor(quality) then return false end
    if Matches(name, inclusions, inclusionCache) then return true end
    if quality > 4 then return false end
    return math.mod(math.floor((tonumber(rarities) or 0) / (2 ^ quality)), 2) == 1
end
-- Preserve existing saved preset bit positions; Kara10 has no supplied exclusions.
AutoLoot.PresetNames = { "ZG", "Kara10", "MC", "Onyxia's Lair", "BWL" }
local raidPresetMasks = { ["Zul'Gurub"]=1, ["Karazhan10"]=2, ["Lower Karazhan Halls"]=2,
    ["Molten Core"]=4, ["Onyxia's Lair"]=8, ["Blackwing Lair"]=16 }
local presets = {
    { "* Bijou *", "* Coin", "Razzashi Hatchling", "Blood Scythe" }, {},
    { "Tome of Tranquilizing Shot", "Recipe *" },
    { "Recipe *", "* Sack of *", "Onyxia Hide Backpack" },
    { "Recipe *", "Head of the Broodlord Lashlayer" },
}
function AutoLoot.ApplyPresets(text, mask)
    local entries, owned, seen = {}, {}, {}
    local index, entry, item
    for index = 1, table.getn(presets) do
        owned[Normalize(AutoLoot.PresetNames[index] .. " exceptions preset test")] = true
        for item = 1, table.getn(presets[index]) do owned[Normalize(presets[index][item])] = true end
    end
    owned["onyxia exceptions preset test"] = true
    for entry in string.gfind(tostring(text or ""), "[^,]+") do
        local key = Normalize(entry)
        if key ~= "" and not owned[key] and not seen[key] then
            table.insert(entries, (string.gsub(entry, "^%s*(.-)%s*$", "%1"))); seen[key] = true
        end
    end
    for index = 1, table.getn(presets) do
        if math.mod(math.floor((tonumber(mask) or 0) / 2 ^ (index - 1)), 2) == 1 then
            for item = 1, table.getn(presets[index]) do
                entry = presets[index][item]
                if not seen[Normalize(entry)] then table.insert(entries, entry); seen[Normalize(entry)] = true end
            end
        end
    end
    return table.concat(entries, ", ")
end

function AutoLoot.ApplyRaidPreset(raidName)
    Raider.Database.Ensure()
    local mask = raidPresetMasks[raidName] or 0
    Raider.Database.SetSetting("lmAutoLootExceptions", AutoLoot.ApplyPresets(BootyRaiderDB.lmAutoLootExceptions, mask))
    Raider.Database.SetSetting("lmAutoLootPresets", mask)
    return mask
end
