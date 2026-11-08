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
-- Preserve existing saved preset bit positions.
AutoLoot.PresetNames = { "ZG", "Kara10", "MC", "Onyxia's Lair", "BWL" }
AutoLoot.ModeChoices = {{text="Auto Loot",value="auto"},{text="Shift Loot",value="shift"},{text="Off",value="off"}}
AutoLoot.RarityNames = {"Poor","Common","Uncommon","Rare","Epic"}
AutoLoot.MaximumPresets = 30
local raidPresetMasks = { ["Zul'Gurub"]=1, ["Karazhan10"]=2, ["Lower Karazhan Halls"]=2,
    ["Molten Core"]=4, ["Onyxia's Lair"]=8, ["Blackwing Lair"]=16 }
local presets = {
    { "* Bijou *", "* Coin", "Razzashi Hatchling", "Blood Scythe" },
    { "Formula *", "Plans *", "* Sack of *", "Araxxna's Hatchling", "Skitterweb Hatchling" },
    { "Tome of Tranquilizing Shot", "Recipe *", "Formula *", "Plans *", "* Sack of *" },
    { "Recipe *", "* Sack of *", "Onyxia Hide Backpack" },
    { "Recipe *", "Head of the Broodlord Lashlayer", "Formula *", "Plans *", "* Sack of *" },
}
local inclusionPresets = { {}, {}, { "Lava Core", "Fiery Core" }, {}, { "Elementium Ore" } }
local checkedDefinitions=setmetatable({},{__mode="k"})
local registryKeys={exclusions="lmAutoLootExclusionPresetDefinitions",inclusions="lmAutoLootInclusionPresetDefinitions"}
local maskKeys={exclusions="lmAutoLootPresets",inclusions="lmAutoLootInclusionPresets"}
local textKeys={exclusions="lmAutoLootExceptions",inclusions="lmAutoLootInclusions"}
local function RegistryKey(kind) return assert(registryKeys[kind],"Select exclusions or inclusions presets.") end
local function DefaultDefinitions(kind)
    local result={}
    for index,name in ipairs(AutoLoot.PresetNames) do
        result[index]={name=name,items=table.concat((kind=="exclusions" and presets or inclusionPresets)[index],", ")}
    end
    checkedDefinitions[result]=true
    return result
end
function AutoLoot.ValidateDefinitions(value)
    if type(value)~="table" then return nil,"Invalid preset list." end
    local result,names,count={},{},table.getn(value)
    if count<5 or count>AutoLoot.MaximumPresets then return nil,"Use between 5 and 30 presets." end
    for key in pairs(value) do if type(key)~="number" or key~=math.floor(key) or key<1 or key>count then return nil,"Invalid preset list." end end
    for index=1,count do
        local entry=value[index]
        if type(entry)~="table" or type(entry.name)~="string" or type(entry.items)~="string" then return nil,"Each preset needs a name and an item list." end
        local name=string.gsub(entry.name,"^%s*(.-)%s*$","%1")
        if index<=5 and name~=AutoLoot.PresetNames[index] then return nil,"Built-in raid preset names cannot be changed." end
        if name=="" or string.len(name)>64 or string.find(name,"[%c|]") then return nil,"Enter a preset name of 1-64 characters without control characters or |." end
        if names[Normalize(name)] then return nil,"A preset with this name already exists. Select it to edit it." end
        if string.len(entry.items)>2048 or string.find(entry.items,"[%z\1-\8\11\12\14-\31]") then return nil,"Preset lists must contain at most 2048 characters." end
        names[Normalize(name)]=true
        result[index]={name=name,items=entry.items}
    end
    checkedDefinitions[result]=true
    return result
end
function AutoLoot.ReadCombinedDefinitions(value,kind)
    RegistryKey(kind)
    if type(value)~="table" then return nil,"Invalid combined preset list." end
    local count=table.getn(value)
    if count<5 or count>AutoLoot.MaximumPresets then return nil,"Use between 5 and 30 presets." end
    for key in pairs(value) do if type(key)~="number" or key~=math.floor(key) or key<1 or key>count then return nil,"Invalid combined preset list." end end
    local converted,reserved,occupied={},{},{}
    for _,name in ipairs(AutoLoot.PresetNames) do reserved[Normalize(name)]=true;occupied[Normalize(name)]=true end
    for _,entry in pairs(value) do if type(entry)=="table" and type(entry.name)=="string" then occupied[Normalize(entry.name)]=true end end
    for key,entry in pairs(value) do
        if type(entry)~="table" then return nil,"Invalid combined preset entry." end
        converted[key]={name=AutoLoot.PresetNames[key] or entry.name,items=entry[kind]}
    end
    -- Older builds allowed renaming built-ins. Restoring their fixed names must
    -- not discard a custom preset which subsequently took one of those names.
    for index=6,table.getn(converted) do
        local entry=converted[index]
        if entry and type(entry.name)=="string" and reserved[Normalize(entry.name)] then
            local base=entry.name;local name=base.." (custom)";local suffix=2
            while occupied[Normalize(name)] do name=base.." (custom "..suffix..")";suffix=suffix+1 end
            entry.name=name;occupied[Normalize(name)]=true
        end
    end
    return AutoLoot.ValidateDefinitions(converted)
end
function AutoLoot.GetDefinitions(store,kind)
    local key=RegistryKey(kind)
    store=store or BootyRaiderDB
    if not store then return DefaultDefinitions(kind) end
    local existing=store[key]
    if existing and checkedDefinitions[existing] then return existing end
    -- Stage both halves before publishing the one-time split. A rejected legacy
    -- list cannot leave only half of the custom presets migrated.
    local staged={}
    for _,category in ipairs({"exclusions","inclusions"}) do
        local registry=store[registryKeys[category]]
        local reason
        if registry then
            if not checkedDefinitions[registry] then registry,reason=AutoLoot.ValidateDefinitions(registry) end
        elseif store.lmAutoLootPresetDefinitions~=nil then
            registry,reason=AutoLoot.ReadCombinedDefinitions(store.lmAutoLootPresetDefinitions,category)
        else registry=DefaultDefinitions(category) end
        assert(registry,"Invalid auto loot presets: "..tostring(reason))
        staged[category]=registry
    end
    for category,registry in pairs(staged) do store[registryKeys[category]]=registry end
    store.lmAutoLootPresetDefinitions=nil
    return store[key]
end
function AutoLoot.GetPresetNames(store,kind)
    local names={}
    for index,entry in ipairs(AutoLoot.GetDefinitions(store,kind)) do names[index]=entry.name end
    return names
end
function AutoLoot.GetPresetChoices(store,kind,allowNew)
    local choices={}
    if allowNew then choices[1]={text="New preset",value=0} end
    for index,entry in ipairs(AutoLoot.GetDefinitions(store,kind)) do table.insert(choices,{text=entry.name,value=index}) end
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
local function Entries(definitions)
    local result={}
    for index,preset in ipairs(definitions) do
        result[index]={}
        for entry in string.gfind(preset.items,"[^,]+") do
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
function AutoLoot.ApplyPresets(text, mask, store) return ApplyPresetEntries(text, mask, Entries(AutoLoot.GetDefinitions(store,"exclusions"))) end
function AutoLoot.ApplyInclusionPresets(text, mask, store) return ApplyPresetEntries(text, mask, Entries(AutoLoot.GetDefinitions(store,"inclusions"))) end

function AutoLoot.SavePreset(store,kind,index,name,items)
    local key=RegistryKey(kind)
    local current=AutoLoot.GetDefinitions(store,kind)
    index=tonumber(index)
    if index==0 then index=table.getn(current)+1 end
    if not index or index~=math.floor(index) or index<1 or index>table.getn(current)+1 then return false,"Select a preset to edit or New preset." end
    if index>AutoLoot.MaximumPresets then return false,"You can save up to 30 auto loot presets." end
    local proposed={}
    for position,entry in ipairs(current) do proposed[position]=entry end
    proposed[index]={name=name,items=items}
    local validated,reason=AutoLoot.ValidateDefinitions(proposed)
    if not validated then return false,reason end
    local applied=ApplyPresetEntries(store[textKeys[kind]],store[maskKeys[kind]],Entries(validated),Entries(current))
    store[key]=validated;store[textKeys[kind]]=applied
    return true,index
end
function AutoLoot.DeletePreset(store,kind,index)
    local key=RegistryKey(kind)
    local current=AutoLoot.GetDefinitions(store,kind)
    if type(index)~="number" or index~=math.floor(index) or index<1 or index>table.getn(current) then return false,"Select a preset to delete." end
    if index<=table.getn(AutoLoot.PresetNames) then return false,"Built-in raid presets cannot be deleted." end
    local proposed={}
    for position,entry in ipairs(current) do if position~=index then table.insert(proposed,entry) end end
    local validated,reason=AutoLoot.ValidateDefinitions(proposed)
    if not validated then return false,reason end
    local oldMask=tonumber(store[maskKeys[kind]]) or 0
    local bit=2^(index-1)
    local mask=math.mod(oldMask,bit)+math.floor(oldMask/(bit*2))*bit
    local applied=ApplyPresetEntries(store[textKeys[kind]],mask,Entries(validated),Entries(current))
    store[key],store[maskKeys[kind]],store[textKeys[kind]]=validated,mask,applied
    return true
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
