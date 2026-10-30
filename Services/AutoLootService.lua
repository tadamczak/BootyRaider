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
AutoLoot.ModeChoices = {{text="Auto Loot",value="auto"},{text="Shift Loot",value="shift"},{text="Off",value="off"}}
AutoLoot.RarityNames = {"Poor","Common","Uncommon","Rare","Epic"}
AutoLoot.MaximumPresets = 30
local raidPresetMasks = { ["Zul'Gurub"]=1, ["Karazhan10"]=2, ["Lower Karazhan Halls"]=2,
    ["Molten Core"]=4, ["Onyxia's Lair"]=8, ["Blackwing Lair"]=16 }
local presets = {
    { "* Bijou *", "* Coin", "Razzashi Hatchling", "Blood Scythe" }, {},
    { "Tome of Tranquilizing Shot", "Recipe *" },
    { "Recipe *", "* Sack of *", "Onyxia Hide Backpack" },
    { "Recipe *", "Head of the Broodlord Lashlayer" },
}
local inclusionPresets = { {}, {}, { "Lava Core", "Fiery Core" }, {}, {} }
local checkedDefinitions=setmetatable({},{__mode="k"})
local function DefaultDefinitions()
    local result={}
    for index,name in ipairs(AutoLoot.PresetNames) do
        result[index]={name=name,exclusions=table.concat(presets[index],", "),inclusions=table.concat(inclusionPresets[index],", ")}
    end
    checkedDefinitions[result]=true
    return result
end
function AutoLoot.GetDefinitions(store)
    store=store or BootyRaiderDB
    if not store then return DefaultDefinitions() end
    if type(store.lmAutoLootPresetDefinitions)~="table" then store.lmAutoLootPresetDefinitions=DefaultDefinitions() end
    if not checkedDefinitions[store.lmAutoLootPresetDefinitions] then
        local validated,reason=AutoLoot.ValidateDefinitions(store.lmAutoLootPresetDefinitions)
        assert(validated,"Invalid auto loot presets: "..tostring(reason))
        store.lmAutoLootPresetDefinitions=validated
    end
    return store.lmAutoLootPresetDefinitions
end
function AutoLoot.ValidateDefinitions(value)
    if type(value)~="table" then return nil,"Invalid preset list." end
    local result,names,count={},{},table.getn(value)
    if count<5 or count>AutoLoot.MaximumPresets then return nil,"Use between 5 and 30 presets." end
    for key in pairs(value) do if type(key)~="number" or key~=math.floor(key) or key<1 or key>count then return nil,"Invalid preset list." end end
    for index=1,count do
        local entry=value[index]
        if type(entry)~="table" or type(entry.name)~="string" or type(entry.exclusions)~="string" or type(entry.inclusions)~="string" then return nil,"Each preset needs a name, exclusions and inclusions." end
        local name=string.gsub(entry.name,"^%s*(.-)%s*$","%1")
        if name=="" or string.len(name)>64 or string.find(name,"[%c|]") then return nil,"Enter a preset name of 1-64 characters without control characters or |." end
        if names[Normalize(name)] then return nil,"A preset with this name already exists. Select it to edit it." end
        if string.len(entry.exclusions)>2048 or string.len(entry.inclusions)>2048 or string.find(entry.exclusions,"[%z\1-\8\11\12\14-\31]") or string.find(entry.inclusions,"[%z\1-\8\11\12\14-\31]") then return nil,"Preset lists must contain at most 2048 characters." end
        names[Normalize(name)]=true
        result[index]={name=name,exclusions=entry.exclusions,inclusions=entry.inclusions}
    end
    checkedDefinitions[result]=true
    return result
end
function AutoLoot.GetPresetNames(store)
    local names={}
    for index,entry in ipairs(AutoLoot.GetDefinitions(store)) do names[index]=entry.name end
    return names
end
function AutoLoot.GetPresetChoices(store,allowNew)
    local choices={}
    if allowNew then choices[1]={text="New preset",value=0} end
    for index,entry in ipairs(AutoLoot.GetDefinitions(store)) do table.insert(choices,{text=entry.name,value=index}) end
    return choices
end
function AutoLoot.MaskSelection(mask,names,selected)
    selected=selected or {}
    for key in pairs(selected) do selected[key]=nil end
    for index,name in ipairs(names) do if math.mod(math.floor((tonumber(mask) or 0)/2^(index-1)),2)==1 then selected[name]=true end end
    return selected
end
function AutoLoot.SelectionMask(selected,names)
    local mask=0
    for index,name in ipairs(names) do if selected[name] then mask=mask+2^(index-1) end end
    return mask
end
local function Entries(definitions,field)
    local result={}
    for index,preset in ipairs(definitions) do
        result[index]={}
        for entry in string.gfind(preset[field],"[^,]+") do
            local trimmed=string.gsub(entry,"^%s*(.-)%s*$","%1")
            if trimmed~="" then table.insert(result[index],trimmed) end
        end
    end
    return result
end
local function ApplyPresetEntries(text, mask, entriesByRaid, previous)
    local entries, owned, seen = {}, {}, {}
    local index, entry, item
    for index = 1, table.getn(entriesByRaid) do
        if AutoLoot.PresetNames[index] then owned[Normalize(AutoLoot.PresetNames[index] .. " exceptions preset test")] = true end
        for item = 1, table.getn(entriesByRaid[index]) do owned[Normalize(entriesByRaid[index][item])] = true end
    end
    for _,list in ipairs(previous or {}) do for _,value in ipairs(list) do owned[Normalize(value)]=true end end
    owned["onyxia exceptions preset test"] = true
    for entry in string.gfind(tostring(text or ""), "[^,]+") do
        local key = Normalize(entry)
        if key ~= "" and not owned[key] and not seen[key] then
            table.insert(entries, (string.gsub(entry, "^%s*(.-)%s*$", "%1"))); seen[key] = true
        end
    end
    for index = 1, table.getn(entriesByRaid) do
        if math.mod(math.floor((tonumber(mask) or 0) / 2 ^ (index - 1)), 2) == 1 then
            for item = 1, table.getn(entriesByRaid[index]) do
                entry = entriesByRaid[index][item]
                if not seen[Normalize(entry)] then table.insert(entries, entry); seen[Normalize(entry)] = true end
            end
        end
    end
    return table.concat(entries, ", ")
end
function AutoLoot.ApplyPresets(text, mask, store) return ApplyPresetEntries(text, mask, Entries(AutoLoot.GetDefinitions(store),"exclusions")) end
function AutoLoot.ApplyInclusionPresets(text, mask, store) return ApplyPresetEntries(text, mask, Entries(AutoLoot.GetDefinitions(store),"inclusions")) end

function AutoLoot.SavePreset(store,index,name,exclusions,inclusions)
    local current=AutoLoot.GetDefinitions(store)
    index=tonumber(index)
    if index==0 then index=table.getn(current)+1 end
    if not index or index~=math.floor(index) or index<1 or index>table.getn(current)+1 then return false,"Select a preset to edit or New preset." end
    if index>AutoLoot.MaximumPresets then return false,"You can save up to 30 auto loot presets." end
    local proposed={}
    for position,entry in ipairs(current) do proposed[position]=entry end
    proposed[index]={name=name,exclusions=exclusions,inclusions=inclusions}
    local validated,reason=AutoLoot.ValidateDefinitions(proposed)
    if not validated then return false,reason end
    local excluded=ApplyPresetEntries(store.lmAutoLootExceptions,store.lmAutoLootPresets,Entries(validated,"exclusions"),Entries(current,"exclusions"))
    local included=ApplyPresetEntries(store.lmAutoLootInclusions,store.lmAutoLootInclusionPresets,Entries(validated,"inclusions"),Entries(current,"inclusions"))
    store.lmAutoLootPresetDefinitions=validated
    store.lmAutoLootExceptions,store.lmAutoLootInclusions=excluded,included
    return true,index
end

function AutoLoot.GetRaidPreset(raidName, exclusions, inclusions, store)
    local mask = raidPresetMasks[raidName] or 0
    return mask, AutoLoot.ApplyPresets(exclusions, mask, store), AutoLoot.ApplyInclusionPresets(inclusions, mask, store), mask
end

function AutoLoot.ApplyRaidPreset(raidName)
    Raider.Database.Ensure()
    local mask = raidPresetMasks[raidName] or 0
    Raider.Database.SetSetting("lmAutoLootExceptions", AutoLoot.ApplyPresets(BootyRaiderDB.lmAutoLootExceptions, mask))
    Raider.Database.SetSetting("lmAutoLootPresets", mask)
    Raider.Database.SetSetting("lmAutoLootInclusionPresets", mask)
    Raider.Database.SetSetting("lmAutoLootInclusions", AutoLoot.ApplyInclusionPresets(BootyRaiderDB.lmAutoLootInclusions, mask))
    return mask
end
