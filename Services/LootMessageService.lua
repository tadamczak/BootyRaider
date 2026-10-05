local Raider = BootyRaider
Raider.Services = Raider.Services or {}
local Messages = {}
Raider.Services.LootMessages = Messages

-- Durable text/preferences only. Formatting never starts a scan or creates UI.
Messages.Definitions = {
    {"Prefix", "Loot Master prefix", "[Loot Master]", ""},
    {"ItemRoll", "Item roll", "ROLL FOR %item. Available rolls: %rolls.", "%item, %rolls, %seconds"},
    {"PlayerRoll", "Specific player roll", "ROLL FOR %item. Available rolls: %rolls. Players: %players.", "%item, %rolls, %players, %seconds"},
    {"SRPlayers", "Soft Reserve players", "SR for %item: %players", "%item, %players"},
    {"Reroll", "Tied players reroll", "%players reroll for %item", "%players, %item"},
    {"Extended", "Roll extended", "Rolling for %item has been extended by %seconds seconds.", "%item, %seconds"},
    {"Tie", "Tie detected", "Tie for %item. Use Reroll to resolve the tied roll type.", "%item"},
    {"TradeWinner", "Winner must trade", "%player receives %item with %value Transmog and must trade it to %recipient.", "%player, %item, %value, %recipient"},
    {"SRWinner", "Only eligible SR", "%player wins %item as the only eligible SR.", "%player, %item"},
    {"Winner", "Roll winner", "%player wins %item with %value %roll.", "%player, %item, %value, %roll"},
    {"NoValidRolls", "No valid rolls", "No valid rolls for %item.", "%item"},
    {"NoRolls", "No rolls", "No rolls for %item.", "%item"},
    {"Stopped", "Roll stopped", "Rolling stopped for %item. All rolls are invalidated.", "%item"},
    {"Countdown", "Roll countdown", "%seconds", "%seconds"},
    {"RaidWinner", "Random raid winner", "Raid roll %value/%count: %player wins %item.", "%value, %count, %player, %item"},
    {"RaidUnavailable", "Random raid unavailable", "Raid roll %value/%count: %player cannot receive %item.", "%value, %count, %player, %item"},
    {"WrongRoll", "Wrong roll type", "%player wrong roll for %item: %reason.", "%player, %item, %reason"},
    {"CannotRoll", "Roll not eligible", "%player cannot roll for %item: %reason.", "%player, %item, %reason"},
    {"TradeConfirmed", "Trade confirmed", "%player traded %item to %recipient.", "%player, %item, %recipient"},
    {"RulesHeader", "Loot rules heading", "=== LOOT RULES ===", ""},
    {"RankRules", "Loot rules for rank", "%rank: %rights", "%rank, %rights"},
    {"SRLink", "Share SR link", "Please put your SR: %link", "%link"},
    {"MissingSR", "Missing Soft Reserves", "Members missing SR: %players", "%players"},
    {"InvalidSR", "Invalid SR rights", "Members with invalid SR loot rights: %players", "%players"},
    {"InvalidSRNotice", "Invalid SR removal notice", "Their invalid Soft Reserves will not be considered for loot and will be removed.", ""},
}
Messages.SettingKeys = {}
local definitions = {}
for index = 1, table.getn(Messages.Definitions) do
    local definition = Messages.Definitions[index]
    definition.textKey = "lmMessage" .. definition[1] .. "Text"
    definition.enabledKey = "lmMessage" .. definition[1] .. "Enabled"
    definitions[definition[1]] = definition
    table.insert(Messages.SettingKeys, definition.textKey); table.insert(Messages.SettingKeys, definition.enabledKey)
end

function Messages.EnsureDefaults(settings)
    for index = 1, table.getn(Messages.Definitions) do
        local definition = Messages.Definitions[index]
        if type(settings[definition.textKey]) ~= "string" then settings[definition.textKey] = definition[3] end
        if settings[definition.enabledKey] == nil then settings[definition.enabledKey] = true end
    end
end

local function Text(definition)
    local settings = BootyRaiderDB or {}
    if settings[definition.enabledKey] == false then return nil end
    local value = settings[definition.textKey]
    return type(value) == "string" and value or definition[3]
end

function Messages.Prefix(message)
    local prefix = Text(definitions.Prefix)
    if not prefix or prefix == "" then return message end
    prefix = string.gsub(prefix, "[%c]", " ")
    return prefix .. " " .. message
end

function Messages.Format(key, values, withoutPrefix)
    local definition = definitions[key]
    if not definition then return nil, "Unknown Loot Master message." end
    local template = Text(definition)
    if not template then return nil end
    local message = string.gsub(template, "%%([%a]+)", function(variable)
        local value = values and values[variable]
        return value ~= nil and tostring(value) or "%" .. variable
    end)
    message = string.gsub(message, "[%c]", " ")
    if not string.find(message, "%S") then return nil end
    return withoutPrefix and message or Messages.Prefix(message)
end

-- Split long captions into native chat messages without cutting item links.
function Messages.Build(key, values)
    local text, failure = Messages.Format(key, values, true)
    if failure then return nil, failure end
    if not text then return {} end -- Suppressed text must never cancel a roll.
    local result, current, offset = {}, "", 1
    while offset <= string.len(text) do
        local first, last, token = string.find(text, "(%S+)", offset)
        if not first then break end
        local linkEnd
        if string.find(token, "|Hitem:", 1, true) then
            local _, finish = string.find(text, "|h|r", first, true)
            if not finish then _, finish = string.find(text, "|h", (string.find(text, "|h", first, true) or first) + 2, true) end
            linkEnd = finish
        end
        if linkEnd then
            last = (string.find(text, "%s", linkEnd + 1) or (string.len(text) + 1)) - 1
            token = string.sub(text, first, last)
        end
        local beginning = Messages.Prefix(token)
        if string.len(beginning) > 255 then return nil, "A message contains a word or item link longer than 255 bytes." end
        local joined = current == "" and beginning or current .. " " .. token
        if string.len(joined) > 255 then table.insert(result, current); current = beginning else current = joined end
        offset = last + 1
    end
    if current ~= "" then table.insert(result, current) end
    return result
end

function Messages.BuildPlayerMessages(key, names, values)
    local definition = definitions[key]
    local template = definition and Text(definition)
    if not template then return {} end
    if not string.find(template, "%%players") then return Messages.Build(key, values) end
    local variables, result, caption = {}, {}, ""
    for variable, value in pairs(values or {}) do variables[variable] = value end
    for index = 1, table.getn(names) do
        local joined = caption == "" and names[index] or caption .. ", " .. names[index]
        variables.players = joined
        local text = Messages.Format(key, variables)
        if text and string.len(text) > 255 then
            if caption == "" then return nil, "The message and item link are too long for a raid warning." end
            variables.players = caption; table.insert(result, Messages.Format(key, variables))
            caption = names[index]; variables.players = caption
            text = Messages.Format(key, variables)
            if text and string.len(text) > 255 then return nil, "The message and item link are too long for a raid warning." end
        else caption = joined end
    end
    if caption ~= "" then variables.players = caption; table.insert(result, Messages.Format(key, variables)) end
    return result
end

function Messages.Send(key, values, send)
    local parts, failure
    if values and values.playerNames then parts, failure = Messages.BuildPlayerMessages(key, values.playerNames, values)
    else parts, failure = Messages.Build(key, values) end
    if not parts then return false, failure end
    for index = 1, table.getn(parts) do
        local ok, reason = send(parts[index], false)
        if not ok then return false, reason end
    end
    return true
end
