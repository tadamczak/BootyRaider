local Reference = {}
BootyRaider.Services.ItemReference = Reference

function Reference.NormalizeName(value)
    if type(value) ~= "string" or string.find(value, "[%c|]") then return nil end
    local name = string.gsub(value, "%s+", " ")
    name = string.gsub(string.gsub(name, "^ +", ""), " +$", "")
    if name == "" or string.len(name) > 120 or tonumber(name) or string.find(name, "^item:") then return nil end
    return name
end

function Reference.Id(value)
    local id = tonumber(value)
    if not id and type(value) == "string" then
        local _, _, matched = string.find(value, "^item:(%d+)")
        if not matched then _, _, matched = string.find(value, "|Hitem:(%d+)") end
        id = tonumber(matched)
    end
    if id and id > 0 and id == math.floor(id) then return id end
end

function Reference.Name(value)
    if type(value) == "string" then
        local _, _, name = string.find(value, "|h%[([^%]]+)%]|h")
        if name then return Reference.NormalizeName(name) end
        if not Reference.Id(value) then return Reference.NormalizeName(value) end
    end
    local id = Reference.Id(value)
    if id and type(GetItemInfo) == "function" then return Reference.NormalizeName(GetItemInfo(id)) end
end

function Reference.NameKey(value)
    local name = Reference.Name(value)
    return name and ("name:" .. string.lower(name)) or nil
end

function Reference.Key(value)
    return Reference.Id(value) or Reference.NameKey(value)
end

-- IDs take precedence when both sides have one. Names bridge an uncatalogued
-- manual reservation to the actual item link without fabricating an item ID.
function Reference.Matches(left, right)
    local leftId, rightId = Reference.Id(left), Reference.Id(right)
    if leftId and rightId then return leftId == rightId end
    local leftName, rightName = Reference.NameKey(left), Reference.NameKey(right)
    return leftName ~= nil and leftName == rightName
end
