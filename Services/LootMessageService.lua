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
    {"RaidUnavailable", "Random raid unavailable", "Raid roll %value/%count: %player cannot receive %item.", "%value, %count, %player, %item", whisperRecipient = "player"},
    {"WrongRoll", "Wrong roll type", "%player wrong roll for %item: %reason.", "%player, %item, %reason", whisperRecipient = "player"},
    {"CannotRoll", "Roll not eligible", "%player cannot roll for %item: %reason.", "%player, %item, %reason", whisperRecipient = "player"},
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
local messageGroups = {
    Prefix = "General",
    ItemRoll = "Rolling", PlayerRoll = "Rolling", Reroll = "Rolling", Extended = "Rolling", Tie = "Rolling",
    NoValidRolls = "Rolling", NoRolls = "Rolling", Stopped = "Rolling", Countdown = "Rolling",
    WrongRoll = "Rolling", CannotRoll = "Rolling",
    SRPlayers = "Soft Reserves", SRLink = "Soft Reserves", MissingSR = "Soft Reserves",
    InvalidSR = "Soft Reserves", InvalidSRNotice = "Soft Reserves",
    TradeWinner = "Loot", SRWinner = "Loot", Winner = "Loot", RaidWinner = "Loot",
    RaidUnavailable = "Loot", TradeConfirmed = "Loot",
    RulesHeader = "Loot rules", RankRules = "Loot rules",
}
for index = 1, table.getn(Messages.Definitions) do
    local definition = Messages.Definitions[index]
    definition.group = assert(messageGroups[definition[1]], "Loot message has no settings group.")
    definition.textKey = "lmMessage" .. definition[1] .. "Text"
    definition.enabledKey = "lmMessage" .. definition[1] .. "Enabled"
    definitions[definition[1]] = definition
    table.insert(Messages.SettingKeys, definition.textKey); table.insert(Messages.SettingKeys, definition.enabledKey)
    if definition.whisperRecipient then
        definition.whisperKey = "lmMessage" .. definition[1] .. "Whisper"
        table.insert(Messages.SettingKeys, definition.whisperKey)
    end
end

function Messages.EnsureDefaults(settings)
    for index = 1, table.getn(Messages.Definitions) do
        local definition = Messages.Definitions[index]
        if type(settings[definition.textKey]) ~= "string" then settings[definition.textKey] = definition[3] end
        if settings[definition.enabledKey] == nil then settings[definition.enabledKey] = true end
        if definition.whisperKey and settings[definition.whisperKey] == nil then settings[definition.whisperKey] = false end
    end
end

local function Text(definition, settings, drafts, includeDisabled)
    settings = settings or BootyRaiderDB or {}
    if not includeDisabled and settings[definition.enabledKey] == false then return nil end
    local value = drafts and drafts[definition.textKey]
    if value == nil then value = settings[definition.textKey] end
    return type(value) == "string" and value or definition[3]
end

local function Prefixed(message, settings, drafts)
    local prefix = Text(definitions.Prefix, settings, drafts)
    if not prefix or prefix == "" then return message end
    prefix = string.gsub(prefix, "[%c]", " ")
    return prefix .. " " .. message
end

function Messages.Prefix(message) return Prefixed(message) end

local function Expand(template, values)
    local message = string.gsub(template, "%%([%a]+)", function(variable)
        local value = values and values[variable]
        return value ~= nil and tostring(value) or "%" .. variable
    end)
    return string.gsub(message, "[%c]", " ")
end

function Messages.Format(key, values, withoutPrefix)
    local definition = definitions[key]
    if not definition then return nil, "Unknown Loot Master message." end
    local template = Text(definition)
    if not template then return nil end
    local message = Expand(template, values)
    if not string.find(message, "%S") then return nil end
    return withoutPrefix and message or Messages.Prefix(message)
end

local previewValues = {
    item = "[Azuresong Mageblade]", rolls = "MS (100), OS (99), RC (101), SR (102), Tmog (98)",
    seconds = 15, players = "Playerone, Playertwo", player = "Playerone", recipient = "Playertwo",
    value = 97, roll = "SR", count = 40, rank = "Chimp", rights = "SR, Reycoin, CSR",
    reason = "use a selected roll type", link = "https://softres.it/raid/example",
}

-- Preview uses the same expansion and prefix rules without sending chat or
-- changing durable settings. Disabled templates remain visible for editing.
function Messages.Preview(key, settings, drafts)
    local definition = definitions[key]
    if not definition then return nil, "Unknown Loot Master message." end
    settings = settings or BootyRaiderDB or {}
    local sample = definition == definitions.Prefix and definitions.ItemRoll or definition
    local template = Text(sample, settings, drafts, true)
    local text = Expand(template, previewValues)
    if string.find(text, "%S") then text = Prefixed(text, settings, drafts) else text = "" end
    local caption = "Example"
    if settings[definition.enabledKey] == false then caption = caption .. " (disabled)"
    elseif definition.whisperKey and settings[definition.whisperKey] == true then
        caption = caption .. " (whisper to " .. previewValues[definition.whisperRecipient] .. ")"
    end
    return caption .. ": " .. (text ~= "" and text or "(empty message; nothing will be sent)")
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
    if table.getn(parts) == 0 then return true end
    local definition, recipient = definitions[key], nil
    if definition.whisperKey and BootyRaiderDB and BootyRaiderDB[definition.whisperKey] == true then
        recipient = values and values[definition.whisperRecipient]
        if type(recipient) ~= "string" or recipient == "" then return false, "The Loot Master whisper has no recipient." end
    end
    for index = 1, table.getn(parts) do
        local ok, reason = send(parts[index], false, recipient)
        if not ok then return false, reason end
    end
    return true
end
