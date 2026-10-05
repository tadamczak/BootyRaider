local Raider = BootyRaider
Raider.Services.RaidInfo = Raider.Services.RaidInfo or {}
local RaidInfo = Raider.Services.RaidInfo

function RaidInfo.Request()
    if type(RequestRaidInfo) ~= "function" then return false end
    return pcall(RequestRaidInfo)
end

function RaidInfo.Read(target)
    target = target or {}
    local retained = 0
    local available = type(GetNumSavedInstances) == "function" and type(GetSavedInstanceInfo) == "function"
    if available then
        local ok, count = pcall(GetNumSavedInstances)
        available = ok and tonumber(count) ~= nil
        if available then
            local index
            for index = 1, math.max(0, math.floor(tonumber(count))) do
                local success, name, id, reset = pcall(GetSavedInstanceInfo, index)
                if success and name then
                    retained = retained + 1
                    local entry = target[retained] or {}; target[retained] = entry
                    entry.name = tostring(name); entry.id = id
                    entry.resetSeconds = math.max(0, tonumber(reset) or 0)
                end
            end
        end
    end
    local index
    for index = table.getn(target), retained + 1, -1 do target[index] = nil end
    return target, available
end

function RaidInfo.FormatReset(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor(math.mod(seconds, 86400) / 3600)
    local minutes = math.floor(math.mod(seconds, 3600) / 60)
    if days > 0 then return days .. "d " .. hours .. "h" end
    if hours > 0 then return hours .. "h " .. minutes .. "m" end
    if minutes > 0 then return minutes .. "m" end
    return seconds .. "s"
end
