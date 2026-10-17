local Raider = BootyRaider
Raider.Services.LootRollRequest = {}
local Request = Raider.Services.LootRollRequest
local aliases = { tmog=98, mog=98, transmog=98, os=99, ms=100, rc=101, reycoin=101, sr=102 }
Request.CategoryNames = { [98]="Tmog", [99]="OS", [100]="MS", [101]="RC", [102]="SR" }
local transmogSlots = {
    INVTYPE_HEAD=true, INVTYPE_SHOULDER=true, INVTYPE_CHEST=true, INVTYPE_ROBE=true, INVTYPE_BODY=true,
    INVTYPE_WRIST=true, INVTYPE_HAND=true, INVTYPE_WAIST=true, INVTYPE_LEGS=true, INVTYPE_FEET=true,
    INVTYPE_WEAPON=true, INVTYPE_2HWEAPON=true, INVTYPE_WEAPONMAINHAND=true, INVTYPE_WEAPONOFFHAND=true,
    INVTYPE_RANGED=true, INVTYPE_RANGEDRIGHT=true, INVTYPE_THROWN=true,
}

function Request.IsTransmogEligible(reference)
    if type(GetItemInfo) ~= "function" then return false, "Item information is unavailable for Tmog." end
    if type(reference) == "string" then
        local _, _, itemId = string.find(reference, "item:(%d+)")
        reference = tonumber(itemId) or tonumber(reference)
    end
    if type(reference) ~= "string" and type(reference) ~= "number" then
        return false, "Link an item before choosing Tmog."
    end
    local name, _, _, _, _, _, _, legacySlot, extendedSlot = GetItemInfo(reference)
    if not name then return false, "Item information is not cached yet; try again before choosing Tmog." end
    -- Accept explicit equip-location tokens in either tuple position; icon
    -- paths must never grant eligibility when a client exposes another tuple.
    local slot
    if type(extendedSlot) == "string" and string.find(extendedSlot, "^INVTYPE_") then slot = extendedSlot
    elseif type(legacySlot) == "string" and string.find(legacySlot, "^INVTYPE_") then slot = legacySlot
    elseif extendedSlot == "" or legacySlot == "" then slot = "" end
    if slot == nil then return false, "Item equipment information is unavailable for Tmog; try again." end
    if not transmogSlots[slot] then return false, "Tmog is available only for eligible armor slots and weapons." end
    return true
end

local function Defaults(link)
    local types = { [99]=true, [100]=true, [101]=true }
    if Request.IsTransmogEligible(link) then types[98]=true; return types,4 end
    return types,3
end

local function HasPermission(value) return value ~= nil and value ~= false and value ~= 0 end

-- Organizing a linked-item roll is separate from awarding corpse loot.
function Request.CanOrganize()
    local raid = Raider.Services.Raid
    if not raid.IsInRaid() then return false end
    return raid.IsPlayerLootMaster()
        or (type(IsRaidLeader) == "function" and HasPermission(IsRaidLeader()))
        or (type(IsRaidOfficer) == "function" and HasPermission(IsRaidOfficer())) or false
end

function Request.Normalize(request)
    if type(request) ~= "table" or type(request.link) ~= "string" then return nil, "Link an item first." end
    local link = request.link
    if not string.find(link, "^|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r$")
        and not string.find(link, "^|Hitem:[^|]+|h%[[^%]]+%]|h$") then return nil, "Use a complete item link." end
    local types, count = {}, 0
    if request.types == nil then types, count = Defaults(link)
    elseif type(request.types) ~= "table" then return nil, "Choose at least one roll type."
    else
        local range, selected
        for range, selected in pairs(request.types) do
            if selected then
                if not Request.CategoryNames[range] or selected ~= true then return nil, "Unknown roll type." end
                if range == 98 then
                    local eligible, failure = Request.IsTransmogEligible(link)
                    if not eligible then return nil, failure end
                end
                types[range], count = true, count + 1
            end
        end
    end
    if count == 0 then return nil, "Choose at least one roll type." end
    if request.open ~= nil and type(request.open) ~= "boolean" then return nil, "Choose an open or restricted roll." end
    local names
    if request.open ~= true and request.names ~= nil then
        if type(request.names) ~= "table" then return nil, "Choose raid members from the list." end
        if table.getn(request.names) > 40 then return nil, "A roll can include at most 40 raid members." end
        if table.getn(request.names) > 0 then
            local physical, seen = {}, {}
            local raidCount = type(GetNumRaidMembers)=="function" and tonumber(GetNumRaidMembers()) or 0
            local index
            for index=1,math.min(40,math.max(0,raidCount or 0)) do
                local name = type(GetRaidRosterInfo)=="function" and GetRaidRosterInfo(index)
                if name then physical[string.lower(name)] = name end
            end
            names = {}
            for index=1,table.getn(request.names) do
                local raw = request.names[index]
                if type(raw)~="string" then return nil, "Invalid raid member name." end
                local normalized = string.lower(raw)
                local name = physical[normalized]
                if not name then return nil, raw .. " is not in the current raid." end
                if seen[normalized] then return nil, "Choose each raid member only once." end
                seen[normalized] = true; table.insert(names,name)
            end
        end
    end
    if request.open == false and not names then return nil, "Add at least one roller, or enable Open roll." end
    return { link=link, types=types, names=names, open=names == nil }
end

function Request.ParseManualRollRequest(text)
    text = tostring(text or "")
    local first,last,link = string.find(text,"(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)")
    if not first then first,last,link=string.find(text,"(|Hitem:[^|]+|h%[[^%]]+%]|h)") end
    if not first or string.find(string.sub(text,1,first-1),"%S") then return nil, "Link an item first." end
    local tail=string.sub(text,last+1)
    local types,names,hasTypes={}, {}, false
    local offset=1
    while true do
        local tokenFirst,tokenLast,token=string.find(tail,"(%S+)",offset)
        if not tokenFirst then break end
        local range=aliases[string.lower(token)]
        if range then types[range],hasTypes=true,true else table.insert(names,token) end
        offset=tokenLast+1
    end
    return Request.Normalize({link=link,types=hasTypes and types or nil,names=names})
end

-- A category's highest tied value can be rerolled independently. Only the
-- winning main category and Tmog carrier ties prevent a final award.
function Request.GetTieGroups(roll)
    if not roll or roll.manualWinnerResult then return {} end
    local groups, mainRange, values = {}, -1, {}
    local index,result
    for index=1,table.getn(roll.results or {}) do
        result=roll.results[index]
        if result.valid~=false and not result.automatic then
            values[result.range]=math.max(values[result.range] or -1,result.value)
            if result.range~=98 then mainRange=math.max(mainRange,result.priority or result.range) end
        end
    end
    for _,range in ipairs({102,101,100,99,98}) do
        local value=values[range]
        local group={range=range,value=value,names={},results={},affectsWinner=range==98 or range==mainRange}
        local seen={}
        for index=1,table.getn(roll.results or {}) do
            result=roll.results[index]
            if result.valid~=false and not result.automatic and result.range==range and result.value==value and not seen[string.lower(result.name)] then
                seen[string.lower(result.name)]=true;table.insert(group.names,result.name);table.insert(group.results,result)
            end
        end
        if table.getn(group.names)>1 then table.insert(groups,group) end
    end
    return groups
end

function Request.HasBlockingTie(roll,groups)
    if roll and roll.manualWinnerResult then return false end
    for _,group in ipairs(groups or Request.GetTieGroups(roll)) do if group.affectsWinner then return true end end
    return false
end

function Request.BuildRerollWarnings(names,link)
    return Raider.Services.LootMessages.BuildPlayerMessages("Reroll", names, {item=link})
end

function Request.CreateRerollRequest(roll,range)
    if not roll or roll.awarded or roll.manualWinnerResult then return nil,"This roll cannot be rerolled." end
    local groups=Request.GetTieGroups(roll)
    for _,group in ipairs(groups) do
        if group.range==range then
            local request,failure=Request.Normalize({link=roll.link,types={[range]=true},names=group.names})
            if not request then return nil,failure end
            request.carryResults={}
            for _,result in ipairs(roll.results or {}) do
                if result.valid~=false and result.range~=range then
                    local copy={}
                    for key,value in pairs(result) do copy[key]=value end
                    copy.carried=true;table.insert(request.carryResults,copy)
                end
            end
            request.reroll=true
            return request
        end
    end
    return nil,"Only players tied at the top of the same roll type can reroll."
end
