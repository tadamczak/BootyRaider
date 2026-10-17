local Raider = BootyRaider

Raider.Database = Raider.Database or {}
local Database = Raider.Database

-- Read the previous durable spellings only at the owner initialization boundary.
-- A canonical value, including false, always wins over an older preference.
local legacyPreferenceKeys = {useBootyRaidTab = "useMOSRaidTab", useBootyRaidLogo = "useMOSRaidLogo"}
local legacyOwnedKeys = {}
for _, previous in pairs(legacyPreferenceKeys) do legacyOwnedKeys[previous] = true end
function Database.GetLegacyPreferenceKey(key) return legacyPreferenceKeys[key] end
function Database.NormalizeNativeRaidButtonStyle(value)
    if value == "mos" then return "booty" end
    return value
end
local function MigratePreferenceNames(store)
    for key, previous in pairs(legacyPreferenceKeys) do
        if store[key] == nil then store[key] = store[previous] end
        store[previous] = nil
    end
    store.nativeRaidButtonStyle = Database.NormalizeNativeRaidButtonStyle(store.nativeRaidButtonStyle)
end

-- Native Raid settings use their own durable keys; they never inherit the main
-- addon layout. Compact defaults fit all eight groups in the stock raid panel.
local nativeRaidGroupFields = {
    { "Columns", 2, 1, 4, true },
    { "ShowClass", true }, { "ShowLevel", true }, { "ShowHeader", true }, { "ShowBorder", true },
    { "BorderSize", 1, 1, 6, true }, { "ShowHoverBorder", true }, { "HoverBorderSize", 1, 1, 6, true }, { "HoverBorderColor", { 1, 1, 1 } },
    { "HeaderTextColor", { 1, 0.82, 0 } }, { "HeaderBackgroundColor", { 0.025, 0.025, 0.025 } },
    { "HeaderHoverTextColor", { 1, 1, 1 } }, { "HeaderTransparency", 100, 0, 100 },
    { "MemberTexture", "game" }, { "BorderTexture", "game" }, { "ViewBackgroundTexture", "game" },
    { "ViewBackgroundColor", { 0.025, 0.025, 0.025 } }, { "BorderColor", { 1, 1, 1 } },
    { "ShowLootMaster", true }, { "ShowRoleIcon", true }, { "ClassColors", true }, { "AutoTileWidth", true },
    { "TileWidth", 160, 160, 340 }, { "TileHeight", 16, 13, 28 }, { "HeaderHeight", 14, 12, 40 },
    { "Margin", 0, 0, 32 }, { "TileTextSize", 10, 8, 16 }, { "HeaderTextSize", 9, 8, 16 },
    { "HideEmptyGroups", false }, { "AutoAdjustVertically", false }, { "AutoAdjustHorizontally", false },
    { "BackgroundColor", { 0.025, 0.025, 0.025 } }, { "TextColor", { 1, 1, 1 } },
    { "HoverColor", { 0.12, 0.09, 0.025 } }, { "PressedColor", { 0.20, 0.14, 0.03 } },
    { "OddLightness", 5, 0, 100 },
}
Database.NativeRaidGroupKeys, Database.NativeRaidGroupSuffixes = {}, {}
Database.NativeRaidGroupFields = nativeRaidGroupFields
local nativeIndex
for nativeIndex = 1, table.getn(nativeRaidGroupFields) do
    local suffix = nativeRaidGroupFields[nativeIndex][1]
    Database.NativeRaidGroupKeys[nativeIndex] = "nativeRaidGroup" .. suffix
    Database.NativeRaidGroupSuffixes[nativeIndex] = suffix
end

local function EnsureNativeRaidGroupSettings()
    local index
    for index = 1, table.getn(nativeRaidGroupFields) do
        local field = nativeRaidGroupFields[index]
        local key = Database.NativeRaidGroupKeys[index]
        local value, default = BootyRaiderDB[key], field[2]
        if field[3] then
            value = tonumber(value)
            if not value or value ~= value then value = default end
            if field[5] then value = math.floor(value) end
            BootyRaiderDB[key] = math.max(field[3], math.min(field[4], value))
        elseif type(default) == "table" then
            if type(value) ~= "table" then
                BootyRaiderDB[key] = { default[1], default[2], default[3] }
            end
        elseif type(default) == "string" then
            local alternative = field[1] == "BorderTexture" and "project" or "color"
            if value ~= "game" and value ~= alternative then BootyRaiderDB[key] = default end
        elseif value == nil then BootyRaiderDB[key] = default end
    end
end

local borderPrefixes = {"raidGroup", "raidList"}
local function BorderSize(value)
    value = tonumber(value)
    if not value or value ~= value then return 1 end
    return math.max(1, math.min(6, math.floor(value)))
end

function Database.CopyLootRules(rules)
    local saved = {}
    local rank, rule
    for rank, rule in pairs(rules or {}) do
        if type(rule) == "table" then
            saved[rank] = { sr = rule.sr and true or false, reyCoin = rule.reyCoin and true or false,
                csr = rule.csr and true or false, highlyContested = rule.highlyContested and true or false }
        end
    end
    return saved
end

local function FreezeLootRules(record, defaults)
    if type(record) == "table" and type(record.lootRules) ~= "table" then record.lootRules = Database.CopyLootRules(defaults) end
end

local function FreezeLegacyLootRules(store)
    if (tonumber(store.raidLootRulesVersion) or 0) >= 1 then return end
    -- Old records did not retain their rules. Freeze the existing calculation
    -- baseline once; later edits cannot rewrite an unknown historical choice.
    local defaults = type(store.lootRulesByRank) == "table" and store.lootRulesByRank or {}
    FreezeLootRules(store.raidAttendance, defaults)
    local _, key
    for _, key in ipairs({"softReserveHistory", "raidStatistics"}) do
        local history = store[key]
        if type(history) == "table" then
            local _, record
            if type(history.raids) == "table" then
                for _, record in pairs(history.raids) do FreezeLootRules(record, defaults) end
            else
                for _, record in ipairs(history) do FreezeLootRules(record, defaults) end
            end
        end
    end
    store.raidLootRulesVersion = 1
end

local function InitializeDefaults(store)
    BootyRaiderDB = store
    MigratePreferenceNames(store)
    FreezeLegacyLootRules(store)
    if Raider.Services and Raider.Services.LootMessages then Raider.Services.LootMessages.EnsureDefaults(BootyRaiderDB) end
    if (tonumber(BootyRaiderDB.groupLayoutVersion) or 0) < 2 then
        BootyRaiderDB.raidGroupMargin = 0; BootyRaiderDB.nativeRaidGroupMargin = 0
        if BootyRaiderDB.raidGroupTileHeight == 20 then BootyRaiderDB.raidGroupTileHeight = 22 end
        if BootyRaiderDB.raidGroupHeaderHeight == 22 then BootyRaiderDB.raidGroupHeaderHeight = 18 end
        if BootyRaiderDB.raidGroupHeaderTextSize == 10 then BootyRaiderDB.raidGroupHeaderTextSize = 9 end
        if BootyRaiderDB.nativeRaidGroupTileHeight == 13 then BootyRaiderDB.nativeRaidGroupTileHeight = 15 end
        if BootyRaiderDB.nativeRaidGroupHeaderHeight == 14 then BootyRaiderDB.nativeRaidGroupHeaderHeight = 12 end
        if BootyRaiderDB.nativeRaidGroupHeaderTextSize == 10 then BootyRaiderDB.nativeRaidGroupHeaderTextSize = 9 end
        BootyRaiderDB.groupLayoutVersion = 2
    end
    if (tonumber(BootyRaiderDB.groupLayoutVersion) or 0) < 3 then
        BootyRaiderDB.raidGroupShowBorder = false; BootyRaiderDB.nativeRaidGroupShowBorder = false
        BootyRaiderDB.groupLayoutVersion = 3
    end
    if (tonumber(BootyRaiderDB.groupLayoutVersion) or 0) < 4 then
        -- Adopt the requested stock appearance once; later user selections,
        -- including disabled outlines, remain durable.
        BootyRaiderDB.nativeRaidGroupShowBorder = true
        BootyRaiderDB.nativeRaidGroupShowHoverBorder = true
        if BootyRaiderDB.nativeRaidGroupTileHeight == 15 then BootyRaiderDB.nativeRaidGroupTileHeight = 16 end
        if BootyRaiderDB.nativeRaidGroupHeaderHeight == 12 then BootyRaiderDB.nativeRaidGroupHeaderHeight = 14 end
        local color = BootyRaiderDB.nativeRaidGroupBorderColor
        if type(color) ~= "table" or color[1] == 0.48 and color[2] == 0.38 and color[3] == 0.20 then BootyRaiderDB.nativeRaidGroupBorderColor = {1,1,1} end
        BootyRaiderDB.groupLayoutVersion = 4
    end
    for _, prefix in ipairs(borderPrefixes) do
        if BootyRaiderDB[prefix .. "ShowHoverBorder"] == nil then BootyRaiderDB[prefix .. "ShowHoverBorder"] = false end
        BootyRaiderDB[prefix .. "HoverBorderSize"] = BorderSize(BootyRaiderDB[prefix .. "HoverBorderSize"])
        if type(BootyRaiderDB[prefix .. "HoverBorderColor"]) ~= "table" then BootyRaiderDB[prefix .. "HoverBorderColor"] = {1, 0.78, 0.2} end
    end
    BootyRaiderDB.raidGroupBorderSize = BorderSize(BootyRaiderDB.raidGroupBorderSize)
    if tonumber(BootyRaiderDB.lootMasterOpacity) == nil then BootyRaiderDB.lootMasterOpacity = 100 end
    if BootyRaiderDB.lmAutoLootMode ~= "auto" and BootyRaiderDB.lmAutoLootMode ~= "shift" and BootyRaiderDB.lmAutoLootMode ~= "off" then
        BootyRaiderDB.lmAutoLootMode = BootyRaiderDB.lmAutoLoot and "auto" or "off"
    end
    if BootyRaiderDB.lmAutoLoot == nil then BootyRaiderDB.lmAutoLoot = false end
    if type(BootyRaiderDB.lmAutoLootRarities) ~= "number" or BootyRaiderDB.lmAutoLootRarities < 0 or BootyRaiderDB.lmAutoLootRarities > 31 then BootyRaiderDB.lmAutoLootRarities = 7 end
    if type(BootyRaiderDB.lmAutoLootPresets) ~= "number" then BootyRaiderDB.lmAutoLootPresets = 0 end
    if type(BootyRaiderDB.lmAutoLootExceptions) ~= "string" then BootyRaiderDB.lmAutoLootExceptions = "" end
    if type(BootyRaiderDB.lmAutoLootInclusions) ~= "string" then BootyRaiderDB.lmAutoLootInclusions = "" end
    if tonumber(BootyRaiderDB.outOfFocusOpacity) == nil then BootyRaiderDB.outOfFocusOpacity = 100 end
    if BootyRaiderDB.raidClassColors == nil then BootyRaiderDB.raidClassColors = true end
    BootyRaiderDB.raidGroupOddLightness = math.max(0,math.min(100,tonumber(BootyRaiderDB.raidGroupOddLightness) or 5))
    BootyRaiderDB.raidListOddLightness = math.max(0,math.min(100,tonumber(BootyRaiderDB.raidListOddLightness) or 5))
    if BootyRaiderDB.raidHideSectionHeader == nil then BootyRaiderDB.raidHideSectionHeader = false end
    if BootyRaiderDB.useBootyRaidTab == nil then BootyRaiderDB.useBootyRaidTab = false end
    if BootyRaiderDB.useBootyRaidLogo == nil then BootyRaiderDB.useBootyRaidLogo = true end
    if BootyRaiderDB.nativeRaidButtonStyle ~= "booty" then BootyRaiderDB.nativeRaidButtonStyle = "game" end
    EnsureNativeRaidGroupSettings()
    if BootyRaiderDB.raidLiveTrackingEnabled == nil then BootyRaiderDB.raidLiveTrackingEnabled = false end
    local raidGroupColumns = tonumber(BootyRaiderDB.raidGroupColumns) or 2
    BootyRaiderDB.raidGroupColumns = math.max(1, math.min(4, math.floor(raidGroupColumns)))
    if BootyRaiderDB.raidGroupShowClass == nil then BootyRaiderDB.raidGroupShowClass = true end
    if BootyRaiderDB.raidGroupShowLevel == nil then BootyRaiderDB.raidGroupShowLevel = true end
    if BootyRaiderDB.raidGroupShowHeader == nil then BootyRaiderDB.raidGroupShowHeader = true end
    if BootyRaiderDB.raidGroupHideEmptyGroups == nil then BootyRaiderDB.raidGroupHideEmptyGroups = false end
    if BootyRaiderDB.raidGroupAutoAdjustVertically == nil then BootyRaiderDB.raidGroupAutoAdjustVertically = false end
    if BootyRaiderDB.raidGroupAutoAdjustHorizontally == nil then BootyRaiderDB.raidGroupAutoAdjustHorizontally = false end
    if BootyRaiderDB.raidGroupShowBorder == nil then BootyRaiderDB.raidGroupShowBorder = false end
    if type(BootyRaiderDB.raidGroupHeaderTextColor) ~= "table" then BootyRaiderDB.raidGroupHeaderTextColor = { 1, 0.82, 0 } end
    if type(BootyRaiderDB.raidGroupHeaderBackgroundColor) ~= "table" then BootyRaiderDB.raidGroupHeaderBackgroundColor = { 0.025, 0.025, 0.025 } end
    if type(BootyRaiderDB.raidGroupHeaderHoverTextColor) ~= "table" then BootyRaiderDB.raidGroupHeaderHoverTextColor = {1,1,1} end
    BootyRaiderDB.raidGroupHeaderTransparency = math.max(0, math.min(100, tonumber(BootyRaiderDB.raidGroupHeaderTransparency) or 0))
    if BootyRaiderDB.raidGroupMemberTexture ~= "game" then BootyRaiderDB.raidGroupMemberTexture = "color" end
    if BootyRaiderDB.raidGroupBorderTexture ~= "game" then BootyRaiderDB.raidGroupBorderTexture = "project" end
    if BootyRaiderDB.raidGroupViewBackgroundTexture ~= "game" then BootyRaiderDB.raidGroupViewBackgroundTexture = "color" end
    if type(BootyRaiderDB.raidGroupViewBackgroundColor) ~= "table" then BootyRaiderDB.raidGroupViewBackgroundColor = {0.025,0.025,0.025} end
    if type(BootyRaiderDB.raidGroupBorderColor) ~= "table" then BootyRaiderDB.raidGroupBorderColor = { 0.48, 0.38, 0.20 } end
    if BootyRaiderDB.raidGroupShowLootMaster == nil then BootyRaiderDB.raidGroupShowLootMaster = true end
    if BootyRaiderDB.raidGroupShowRoleIcon == nil then BootyRaiderDB.raidGroupShowRoleIcon = true end
    if BootyRaiderDB.raidGroupClassColors == nil then BootyRaiderDB.raidGroupClassColors = true end
    if BootyRaiderDB.raidGroupAutoTileWidth == nil then BootyRaiderDB.raidGroupAutoTileWidth = true end
    BootyRaiderDB.raidGroupTileWidth = math.max(160, math.min(340, tonumber(BootyRaiderDB.raidGroupTileWidth) or 280))
    BootyRaiderDB.raidGroupTileHeight = math.max(14, math.min(28, tonumber(BootyRaiderDB.raidGroupTileHeight) or 22))
    BootyRaiderDB.raidGroupHeaderHeight = math.max(12, math.min(40, tonumber(BootyRaiderDB.raidGroupHeaderHeight) or 18))
    BootyRaiderDB.raidGroupMargin = math.max(0, math.min(32, tonumber(BootyRaiderDB.raidGroupMargin) or 0))
    BootyRaiderDB.raidGroupTileTextSize = math.max(8, math.min(16, tonumber(BootyRaiderDB.raidGroupTileTextSize) or 10))
    BootyRaiderDB.raidGroupHeaderTextSize = math.max(8, math.min(16, tonumber(BootyRaiderDB.raidGroupHeaderTextSize) or 9))
    if type(BootyRaiderDB.raidGroupBackgroundColor) ~= "table" then BootyRaiderDB.raidGroupBackgroundColor = { 0.025, 0.025, 0.025 } end
    if type(BootyRaiderDB.raidGroupTextColor) ~= "table" then BootyRaiderDB.raidGroupTextColor = { 1, 1, 1 } end
    if type(BootyRaiderDB.raidGroupHoverColor) ~= "table" then BootyRaiderDB.raidGroupHoverColor = { 0.12, 0.09, 0.025 } end
    if type(BootyRaiderDB.raidGroupPressedColor) ~= "table" then BootyRaiderDB.raidGroupPressedColor = { 0.20, 0.14, 0.03 } end
    if BootyRaiderDB.raidListShowName == nil then BootyRaiderDB.raidListShowName = true end
    if BootyRaiderDB.raidListShowLevel == nil then BootyRaiderDB.raidListShowLevel = true end
    if BootyRaiderDB.raidListShowStatus == nil then BootyRaiderDB.raidListShowStatus = true end
    if BootyRaiderDB.raidListShowGroup == nil then BootyRaiderDB.raidListShowGroup = true end
    if BootyRaiderDB.raidListShowClass == nil then BootyRaiderDB.raidListShowClass = true end
    if BootyRaiderDB.raidListShowGuildRank == nil then BootyRaiderDB.raidListShowGuildRank = true end
    if BootyRaiderDB.raidListShowSR == nil then BootyRaiderDB.raidListShowSR = true end
    if BootyRaiderDB.raidListShowLootMaster == nil then BootyRaiderDB.raidListShowLootMaster = true end
    if BootyRaiderDB.raidListShowRoleIcon == nil then BootyRaiderDB.raidListShowRoleIcon = true end
    if BootyRaiderDB.raidListShowFilters == nil then BootyRaiderDB.raidListShowFilters = true end
    if BootyRaiderDB.raidListShowSearch == nil then BootyRaiderDB.raidListShowSearch = true end
    BootyRaiderDB.raidListRowWidth = math.max(400, math.min(1200, tonumber(BootyRaiderDB.raidListRowWidth) or 1000))
    BootyRaiderDB.raidListRowHeight = math.max(16, math.min(30, tonumber(BootyRaiderDB.raidListRowHeight) or 20))
    if type(BootyRaiderDB.raidListBackgroundColor) ~= "table" then BootyRaiderDB.raidListBackgroundColor = { 0.025, 0.025, 0.025 } end
    if type(BootyRaiderDB.raidListTextColor) ~= "table" then BootyRaiderDB.raidListTextColor = { 1, 1, 1 } end
    if type(BootyRaiderDB.raidListHoverColor) ~= "table" then BootyRaiderDB.raidListHoverColor = { 0.12, 0.09, 0.025 } end
    if type(BootyRaiderDB.raidListPressedColor) ~= "table" then BootyRaiderDB.raidListPressedColor = { 0.20, 0.14, 0.03 } end
    if type(BootyRaiderDB.presentation) ~= "table" then BootyRaiderDB.presentation = {} end
    if type(BootyRaiderDB.presentation.windows) ~= "table" then BootyRaiderDB.presentation.windows = {} end
    if type(BootyRaiderDB.presentation.minimap) ~= "table" then BootyRaiderDB.presentation.minimap = {angle=240} end
    BootyRaiderDB.addonVersion = Raider.version
end

local ownedExact = {
    groupLayoutVersion=true, useBootyRaidTab=true, useBootyRaidLogo=true,
    outOfFocusOpacity=true, reyCoinPanelWidth=true, reyCoinPanelHeight=true,
    masterLootWindowWidth=true, masterLootWindowHeight=true,
    lootRulesByRank=true, highlyContestedItems=true, highlyContestedItemsCustomized=true,
    softReserveHistory=true, presentation=true, raidLootRulesVersion=true,
}
function Database.OwnsField(key)
    return type(key)=="string" and (ownedExact[key] or legacyOwnedKeys[key] or string.find(key,"^raid")
        or string.find(key,"^nativeRaid") or string.find(key,"^lm") or string.find(key,"^lootMaster") or string.find(key,"^csr")) and true or false
end
function Database.Ensure()
    local store,failure=BootyLib.Data.Ensure("raider")
    if not store then error(failure or "BootyRaider data is unavailable.") end
    return store
end
function Database.GetSetting(key)
    if key=="chatActionLogs" then
        local shared,failure=BootyLib.Data.Ensure("lib")
        if not shared then error(failure or "BootyLib data is unavailable.") end
        return shared[key]
    end
    local store=Database.Ensure()
    return store and store[key]
end
function Database.SetSetting(key,value)
    if key=="chatActionLogs" then
        local shared,failure=BootyLib.Data.Ensure("lib")
        if not shared then error(failure or "BootyLib data is unavailable.") end
        shared[key]=value
        return value
    end
    if not Database.OwnsField(key) then return nil,"This field belongs to another product." end
    local store=Database.Ensure();if not store then return nil end
    store[key]=value
    if Raider.OnSettingChanged then Raider.OnSettingChanged(key) end
    return value
end
-- Optional enrichment is a read-only shared client cache, never a dependency
-- on BootyGuild persistence and never a prerequisite to starting a raid.
function Database.GetRosterData()
    return BootyLib.GuildDirectory.GetSnapshot()
end
function Database.GetGuildIdentity()
    local snapshot=Database.GetRosterData()
    if not snapshot then return nil end
    return tostring(snapshot.realmName or "UnknownRealm").." - "..snapshot.guildName,snapshot.guildName,snapshot.realmName
end
BootyLib.Data.RegisterOwner("raider","BootyRaiderDB",Database.OwnsField,InitializeDefaults)
function Database.GetRaidAttendance()
    Database.Ensure()
    return BootyRaiderDB.raidAttendance
end

function Database.StoreRaidAttendance(attendance)
    Database.Ensure()
    if attendance then Database.EnsureRaidLootRules(attendance) end
    local previous = BootyRaiderDB.raidAttendance
    BootyRaiderDB.raidAttendance = attendance
    if Database.onRaidAttendanceChanged then Database.onRaidAttendanceChanged(previous, attendance) end
    return attendance
end

function Database.GetDefaultLootRules()
    Database.Ensure()
    if type(BootyRaiderDB.lootRulesByRank) ~= "table" then BootyRaiderDB.lootRulesByRank = {} end
    return BootyRaiderDB.lootRulesByRank
end

function Database.EnsureRaidLootRules(attendance)
    if type(attendance) ~= "table" then return nil end
    if type(attendance.lootRules) ~= "table" then FreezeLootRules(attendance, Database.GetDefaultLootRules()) end
    return attendance.lootRules
end

function Database.GetLootRules()
    Database.Ensure()
    local attendance = BootyRaiderDB.raidAttendance
    if attendance then return Database.EnsureRaidLootRules(attendance) end
    return Database.GetDefaultLootRules()
end

function Database.SaveLootRules(rules)
    Database.Ensure()
    local saved = Database.CopyLootRules(rules)
    local attendance = BootyRaiderDB.raidAttendance
    if attendance then attendance.lootRules = saved else BootyRaiderDB.lootRulesByRank = saved end
end

local defaultHighlyContestedItems = {
    "Heavy Dark Iron Ring", "Lost Dark Iron Chain", "Fireguard Shoulders", "Runed Wardstone",
    "Talisman of Ephemeral Power", "Wild Growth Spaulders", "Molten Emberstone",
    "Sigil of Ancient Accord", "Onslaught Girdle", "Band of Accuria",
    "Yoxtez, Black Breath of the Dragonflight", "Broodwarden's Bulwarkblade",
}

function Database.GetHighlyContestedItems()
    Database.Ensure()
    if type(BootyRaiderDB.highlyContestedItems) ~= "table"
        or (table.getn(BootyRaiderDB.highlyContestedItems) == 0 and not BootyRaiderDB.highlyContestedItemsCustomized) then
        local items = {}
        local index
        for index = 1, table.getn(defaultHighlyContestedItems) do items[index] = defaultHighlyContestedItems[index] end
        BootyRaiderDB.highlyContestedItems = items
    end
    return BootyRaiderDB.highlyContestedItems
end

function Database.SaveHighlyContestedItems(items)
    Database.Ensure()
    local saved, seen, count = {}, {}, 0
    local index
    for index = 1, table.getn(items or {}) do
        local name = string.gsub(tostring(items[index] or ""), "^%s+", "")
        name = string.gsub(name, "%s+$", "")
        local key = string.lower(name)
        if name ~= "" and not seen[key] then count = count + 1; saved[count] = name; seen[key] = true end
    end
    BootyRaiderDB.highlyContestedItems = saved
    BootyRaiderDB.highlyContestedItemsCustomized = true
    return count
end

function Database.StoreSoftReserveSnapshot(snapshot)
    Database.Ensure()
    if not snapshot or not snapshot.id then return false end
    if type(snapshot.lootRules) ~= "table" then FreezeLootRules(snapshot, Database.GetDefaultLootRules()) end
    if type(BootyRaiderDB.softReserveHistory) ~= "table" then BootyRaiderDB.softReserveHistory = { order = {}, raids = {} } end
    local history = BootyRaiderDB.softReserveHistory
    if type(history.order) ~= "table" then history.order = {} end
    if type(history.raids) ~= "table" then history.raids = {} end
    local index
    for index = table.getn(history.order), 1, -1 do if history.order[index] == snapshot.id then table.remove(history.order, index) end end
    table.insert(history.order, 1, snapshot.id); history.raids[snapshot.id] = snapshot
    while table.getn(history.order) > 10 do
        local expiredId = table.remove(history.order); history.raids[expiredId] = nil
    end
    return true
end

function Database.GetSoftReserveHistory()
    Database.Ensure()
    local history = BootyRaiderDB.softReserveHistory
    local snapshots = {}
    if not history or not history.order or not history.raids then return snapshots end
    local index, defaults = nil, BootyRaiderDB.lootRulesByRank
    for index = 1, math.min(10, table.getn(history.order)) do
        local snapshot = history.raids[history.order[index]]
        if snapshot then FreezeLootRules(snapshot, defaults); table.insert(snapshots, snapshot) end
    end
    return snapshots
end

function Database.HasSoftReserveSnapshot(snapshotId)
    Database.Ensure()
    local wanted = string.lower(tostring(snapshotId or ""))
    local history = BootyRaiderDB.softReserveHistory
    if wanted == "" or not history or type(history.raids) ~= "table" then return false end
    local id
    for id in pairs(history.raids) do if string.lower(tostring(id)) == wanted then return true end end
    return false
end

function Database.DeleteSoftReserveSnapshot(snapshotId)
    Database.Ensure()
    local history = BootyRaiderDB.softReserveHistory
    if not snapshotId or not history or type(history.order) ~= "table" or type(history.raids) ~= "table" or not history.raids[snapshotId] then return false end
    history.raids[snapshotId] = nil
    local index
    for index = table.getn(history.order), 1, -1 do if history.order[index] == snapshotId then table.remove(history.order, index) end end
    return true
end

function Database.StoreRaidStatistic(entry)
    Database.Ensure()
    if not entry or not entry.id then return false end
    if type(entry.lootRules) ~= "table" then FreezeLootRules(entry, Database.GetDefaultLootRules()) end
    if type(BootyRaiderDB.raidStatistics) ~= "table" then BootyRaiderDB.raidStatistics = { order = {}, raids = {} } end
    local history = BootyRaiderDB.raidStatistics
    if type(history.order) ~= "table" then history.order = {} end
    if type(history.raids) ~= "table" then history.raids = {} end
    local index
    for index = table.getn(history.order), 1, -1 do if history.order[index] == entry.id then table.remove(history.order, index) end end
    table.insert(history.order, 1, entry.id); history.raids[entry.id] = entry
    -- CSR archives share these saved records. Automatic count-based eviction
    -- would silently erase their history; explicit deletion remains available.
    return true
end

function Database.GetRaidStatistics()
    Database.Ensure()
    local result = {}
    local history = BootyRaiderDB.raidStatistics
    if not history or type(history.order) ~= "table" or type(history.raids) ~= "table" then return result end
    local index, defaults = nil, BootyRaiderDB.lootRulesByRank
    for index = 1, table.getn(history.order) do
        local entry = history.raids[history.order[index]]
        if entry then FreezeLootRules(entry, defaults); result[table.getn(result) + 1] = entry end
    end
    return result
end

local function FindSavedRaid(history, raidId)
    if type(history) ~= "table" or type(history.raids) ~= "table" then return nil end
    local wanted = string.lower(tostring(raidId or ""))
    if wanted == "" then return nil end
    local id, record
    for id, record in pairs(history.raids) do
        if string.lower(tostring(id)) == wanted then return id, record end
    end
end

function Database.DeleteRaidStatistic(raidId)
    Database.Ensure()
    local history = BootyRaiderDB.raidStatistics
    raidId = FindSavedRaid(history, raidId)
    if not raidId or type(history.order) ~= "table" then return false end
    history.raids[raidId] = nil
    local index
    for index = table.getn(history.order), 1, -1 do
        if history.order[index] == raidId then table.remove(history.order, index) end
    end
    return true
end

function Database.GetSavedRaidState(raidId)
    Database.Ensure()
    local snapshotId, snapshot = FindSavedRaid(BootyRaiderDB.softReserveHistory, raidId)
    local statisticId, statistic = FindSavedRaid(BootyRaiderDB.raidStatistics, raidId)
    if snapshot and type(snapshot.lootRules) ~= "table" then FreezeLootRules(snapshot, Database.GetDefaultLootRules()) end
    if statistic and type(statistic.lootRules) ~= "table" then FreezeLootRules(statistic, Database.GetDefaultLootRules()) end
    return snapshotId or statisticId, snapshot, statistic
end

function Database.ResolveRaidId(raidId)
    local canonical = Database.GetSavedRaidState(raidId)
    return canonical
end

function Database.HasRaidStatistic(raidId)
    Database.Ensure()
    local history=BootyRaiderDB.raidStatistics
    local wanted=string.lower(tostring(raidId or ""))
    if wanted=="" or not history or type(history.raids)~="table" then return false end
    local id
    for id in pairs(history.raids) do if string.lower(tostring(id))==wanted then return true end end
    return false
end

function Database.UpdateRaidStatisticFlags(raidId, attendanceEnabled, csrEnabled)
    Database.Ensure()
    local history = BootyRaiderDB.raidStatistics
    local entry = history and history.raids and history.raids[raidId]
    if not entry then return false end
    entry.attendanceEnabled = attendanceEnabled and true or false
    entry.csrEnabled = csrEnabled and true or false
    return true
end

local function CleanRaidText(value)
    return string.gsub(string.gsub(tostring(value or ""), "^%s+", ""), "%s+$", "")
end

local function CopySavedRecord(source)
    if type(source) ~= "table" then return source end
    local result = {}
    for key, value in pairs(source) do result[key] = CopySavedRecord(value) end
    return result
end

local function IsRaidType(value)
    local service = Raider.Services and Raider.Services.RaidStatistics
    if not service or not service.GetRaidNames then return false end
    for _, name in ipairs(service.GetRaidNames()) do if value == name then return true end end
    return false
end

-- Metadata edits rename one saved identity. They never load a session, copy a
-- raid, or rewrite its source timestamps, rules and contribution choices.
function Database.UpdateRaidMetadata(raidId, metadata)
    Database.Ensure()
    if type(metadata) ~= "table" then return false, "Raid details are required." end
    local id = CleanRaidText(metadata.id)
    local editDisplayName = metadata.displayName ~= nil
    local displayName = CleanRaidText(metadata.displayName)
    if id == "" then return false, "Raid ID is required." end
    if string.len(id) > 80 or string.find(id, "%c") then return false, "Raid ID must contain at most 80 printable characters." end
    if string.len(displayName) > 120 or string.find(displayName, "%c") then return false, "Name must contain at most 120 printable characters." end
    if not IsRaidType(metadata.raidName) then return false, "Choose a valid raid type." end
    local snapshotId, snapshot = FindSavedRaid(BootyRaiderDB.softReserveHistory, raidId)
    local statisticId, statistic = FindSavedRaid(BootyRaiderDB.raidStatistics, raidId)
    if not snapshot and not statistic then return false, "This saved raid no longer exists." end
    local active = BootyRaiderDB.raidAttendance
    local wanted = string.lower(tostring(raidId or ""))
    local matchesActive = active and (string.lower(tostring(active.snapshotId or "")) == wanted
        or string.lower(tostring(active._loadedSnapshotId or "")) == wanted)
    if matchesActive and id ~= (snapshotId or statisticId) then
        return false, "Finish or end the current raid before renaming its ID."
    end
    for _, history in ipairs({BootyRaiderDB.softReserveHistory or {}, BootyRaiderDB.raidStatistics or {}}) do
        local targetId = FindSavedRaid(history, id)
        if targetId and string.lower(tostring(targetId)) ~= string.lower(tostring(raidId)) then
            return false, "This raid ID already exists. Choose a different ID."
        end
    end
    local now = time()
    local sources = {{BootyRaiderDB.softReserveHistory, snapshotId, snapshot}, {BootyRaiderDB.raidStatistics, statisticId, statistic}}
    local replacements = {}
    for index = 1, 2 do
        local source = sources[index]
        if source[3] then
            local copy = CopySavedRecord(source[3])
            copy.id = id
            if editDisplayName then copy.displayName = displayName ~= "" and displayName or nil end
            copy.raidName = metadata.raidName; copy.modifiedAt = now
            replacements[index] = copy
        end
    end
    local activeReplacement
    if matchesActive then
        -- Replace only the workspace owner; live member/loot references remain
        -- valid, while a prepared Save bound to the former owner becomes stale.
        activeReplacement = {}
        for key, value in pairs(active) do activeReplacement[key] = value end
        activeReplacement.raidName = metadata.raidName
        if editDisplayName then activeReplacement.displayName = displayName ~= "" and displayName or nil end
        if Database.onRaidAttendanceMetadataChanged then Database.onRaidAttendanceMetadataChanged(active, activeReplacement) end
    end
    for index = 1, 2 do
        local source, replacement = sources[index], replacements[index]
        if replacement then
            local history, previousId = source[1], source[2]
            history.raids[previousId] = nil; history.raids[id] = replacement
            for orderIndex = 1, table.getn(history.order or {}) do
                if history.order[orderIndex] == previousId then history.order[orderIndex] = id end
            end
        end
    end
    if activeReplacement then Database.StoreRaidAttendance(activeReplacement) end
    return true, id
end

function Database.UpdateRaidStatistic(raidId,members,attendanceEnabled,csrEnabled,raidName)
    Database.Ensure()
    local history=BootyRaiderDB.raidStatistics
    local canonical,entry=FindSavedRaid(history,raidId)
    if not entry or type(members)~="table" then return false end
    if raidName then
        local updated, reason = Database.UpdateRaidMetadata(canonical, {id=canonical,raidName=raidName})
        if not updated then return false, reason end
        entry=history.raids[canonical]
    end
    entry.members=members;entry.attendanceEnabled=attendanceEnabled and true or false;entry.csrEnabled=csrEnabled and true or false
    entry.modifiedAt=time()
    return true
end

function Database.ResetRaidGroupView()
    Database.Ensure()
    BootyRaiderDB.raidGroupOddLightness = 5
    BootyRaiderDB.raidGroupColumns = 2
    BootyRaiderDB.raidGroupHideEmptyGroups = false
    BootyRaiderDB.raidGroupAutoAdjustVertically = false
    BootyRaiderDB.raidGroupAutoAdjustHorizontally = false
    BootyRaiderDB.raidGroupShowClass = true
    BootyRaiderDB.raidGroupShowLevel = true
    BootyRaiderDB.raidGroupShowHeader = true
    BootyRaiderDB.raidGroupShowBorder = false
    BootyRaiderDB.raidGroupBorderSize = 1
    BootyRaiderDB.raidGroupShowHoverBorder = false
    BootyRaiderDB.raidGroupHoverBorderSize = 1
    BootyRaiderDB.raidGroupHoverBorderColor = {1, 0.78, 0.2}
    BootyRaiderDB.raidGroupHeaderTextColor = { 1, 0.82, 0 }
    BootyRaiderDB.raidGroupHeaderBackgroundColor = { 0.025, 0.025, 0.025 }
    BootyRaiderDB.raidGroupHeaderHoverTextColor = {1,1,1}
    BootyRaiderDB.raidGroupHeaderTransparency = 0
    BootyRaiderDB.raidGroupMemberTexture = "color"
    BootyRaiderDB.raidGroupBorderTexture = "project"
    BootyRaiderDB.raidGroupViewBackgroundTexture = "color"
    BootyRaiderDB.raidGroupViewBackgroundColor = {0.025,0.025,0.025}
    BootyRaiderDB.raidGroupBorderColor = { 0.48, 0.38, 0.20 }
    BootyRaiderDB.raidGroupClassColors = true
    BootyRaiderDB.raidGroupShowLootMaster = true
    BootyRaiderDB.raidGroupShowRoleIcon = true
    BootyRaiderDB.raidGroupAutoTileWidth = true
    BootyRaiderDB.raidGroupTileWidth = 280
    BootyRaiderDB.raidGroupTileHeight = 22
    BootyRaiderDB.raidGroupHeaderHeight = 18
    BootyRaiderDB.raidGroupMargin = 0
    BootyRaiderDB.raidGroupTileTextSize = 10
    BootyRaiderDB.raidGroupHeaderTextSize = 9
    BootyRaiderDB.raidGroupBackgroundColor = { 0.025, 0.025, 0.025 }
    BootyRaiderDB.raidGroupTextColor = { 1, 1, 1 }
    BootyRaiderDB.raidGroupHoverColor = { 0.12, 0.09, 0.025 }
    BootyRaiderDB.raidGroupPressedColor = { 0.20, 0.14, 0.03 }
end

function Database.ResetNativeRaidGroupView()
    Database.Ensure()
    local index
    for index = 1, table.getn(Database.NativeRaidGroupKeys) do
        BootyRaiderDB[Database.NativeRaidGroupKeys[index]] = nil
    end
    EnsureNativeRaidGroupSettings()
end

function Database.ResetRaidListView()
    Database.Ensure()
    BootyRaiderDB.raidListShowHoverBorder = false
    BootyRaiderDB.raidListHoverBorderSize = 1
    BootyRaiderDB.raidListHoverBorderColor = {1, 0.78, 0.2}
    BootyRaiderDB.raidListOddLightness = 5
    BootyRaiderDB.raidListShowName = true
    BootyRaiderDB.raidListShowLevel = true
    BootyRaiderDB.raidListShowStatus = true
    BootyRaiderDB.raidListShowGroup = true
    BootyRaiderDB.raidListShowClass = true
    BootyRaiderDB.raidListShowGuildRank = true
    BootyRaiderDB.raidListShowSR = true
    BootyRaiderDB.raidListShowLootMaster = true
    BootyRaiderDB.raidListShowRoleIcon = true
    BootyRaiderDB.raidListShowFilters = true
    BootyRaiderDB.raidListShowSearch = true
    BootyRaiderDB.raidListRowWidth = 1000
    BootyRaiderDB.raidListRowHeight = 20
    BootyRaiderDB.raidListBackgroundColor = { 0.025, 0.025, 0.025 }
    BootyRaiderDB.raidListTextColor = { 1, 1, 1 }
    BootyRaiderDB.raidListHoverColor = { 0.12, 0.09, 0.025 }
    BootyRaiderDB.raidListPressedColor = { 0.20, 0.14, 0.03 }
end
