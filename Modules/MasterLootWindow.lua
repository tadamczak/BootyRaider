local Raider = BootyRaider
local Window = {}
Raider.Modules.MasterLootWindow = Window
local initialized = false
function Window.Initialize()
    if initialized then return end
    initialized = true
local Raider = BootyRaider
local Match = Raider.Core and Raider.Core.Compatibility and Raider.Core.Compatibility.Match or string.match
local RaidService = Raider.Services.Raid

Raider.Modules.MasterLootWindow = Raider.Modules.MasterLootWindow or {}
local MasterLootWindow = Raider.Modules.MasterLootWindow
local Stack = Raider.UI.Components.WindowStack
local function RaidWindowOwner()
    local host = Raider.Runtime and Raider.Runtime.host
    return host and (host.windows and host.windows.raid or host.window)
end

local MAX_ROWS = 8
local MAX_RESULT_ROWS = 6
local MAX_LIVE_ROWS = 6
local ROW_HEIGHT = 24
local DEFAULT_ROLL_SECONDS = 15
local ROLL_ICON_PATH = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"

local panel = Raider.UI.Components.CreateContainer("BootyRaiderMasterLootWindow", UIParent)
panel:SetWidth(390); panel:SetHeight(94 + MAX_ROWS * ROW_HEIGHT)
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
panel:EnableMouse(true); panel:Hide()
if Stack then Stack.Register(panel, {owner = RaidWindowOwner}) end
panel:SetMovable(true); panel:SetResizable(true)
panel:SetMinResize(360, 180); panel:SetMaxResize(600, 600)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function() this:StartMoving() end)
panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
panel:SetBackdropColor(0.02, 0.02, 0.02, 0.96); panel:SetBackdropBorderColor(0.68, 0.54, 0.27, 1)
Raider.UI.Components.RegisterSkinnedSurface(panel, "panel", { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } }, { 0.02, 0.02, 0.02, 0.96 }, { 0.68, 0.54, 0.27, 1 })
local panelBorder = Raider.UI.Components.CreateContainer(nil, panel)
panelBorder:SetAllPoints(panel); panelBorder:EnableMouse(false)
panelBorder:SetFrameLevel(panel:GetFrameLevel() + 80)
panelBorder:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
panelBorder:SetBackdropBorderColor(0.68, 0.54, 0.27, 1)

local title = Raider.UI.Components.CreateLabel(panel, nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12); title:SetText("Master Loot")
title:SetTextColor(unpack(Raider.UI.Components.Theme.colors.goldText))
Raider.UI.Components.SetHeadingIcon(title, "lootmaster")
local close = Raider.UI.Components.CreateWindowButton(panel, nil, "close")
close:SetPoint("RIGHT", panel, "TOPRIGHT", -8, -17)
close:SetScript("OnClick", function()
    if panel.manualSession then panel:Hide()
    else CloseLoot() end
end)


local scaleGrip = Raider.UI.Components.CreateControl(nil, panel)
scaleGrip:SetWidth(12); scaleGrip:SetHeight(12)
scaleGrip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
scaleGrip:SetFrameLevel(panel:GetFrameLevel() + 100)
scaleGrip.texture = Raider.UI.Components.CreateTexture(scaleGrip, nil, "OVERLAY")
scaleGrip.texture:SetAllPoints(scaleGrip)
scaleGrip.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
Raider.UI.Components.RegisterSkinCallback(function(skin)
    if skin == "classic" then
        scaleGrip.texture:SetTexture(Raider.UI.Components.ClassicAsset("Icons\\resize.tga"))
        scaleGrip.texture:SetVertexColor(1, 0.78, 0.24)
        scaleGrip.texture:ClearAllPoints()
        scaleGrip.texture:SetPoint("CENTER", scaleGrip, "CENTER", 0, 0)
        scaleGrip.texture:SetWidth(9); scaleGrip.texture:SetHeight(9)
    else
        scaleGrip.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        scaleGrip.texture:SetVertexColor(1, 1, 1)
        scaleGrip.texture:ClearAllPoints(); scaleGrip.texture:SetAllPoints(scaleGrip)
    end
end)
scaleGrip:SetScript("OnMouseDown", function()
    local left, top = panel:GetLeft(), panel:GetTop()
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    panel:StartSizing("BOTTOMRIGHT")
end)
scaleGrip:SetScript("OnMouseUp", function()
    panel:StopMovingOrSizing()
    Raider.Database.SetSetting("masterLootWindowWidth", math.floor(panel:GetWidth() + 0.5))
end)
scaleGrip:SetScript("OnHide", function() panel:StopMovingOrSizing() end)
local status = Raider.UI.Components.CreateLabel(panel, nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 12)
status:SetWidth(350); status:SetJustifyH("LEFT"); status:SetText("")
status:Hide()

local rollTime = Raider.UI.Components.CreateFramedEditBox(panel, nil, 32)
rollTime:SetPoint("RIGHT", close, "LEFT", -6, 0)
rollTime:SetHeight(18)
rollTime:SetNumeric(true); rollTime:SetMaxLetters(2)
rollTime:SetScript("OnTextChanged", function()
    local value = tonumber(this:GetText())
    if value and value > 60 then this:SetText("60") end
end)
rollTime:SetText(tostring(DEFAULT_ROLL_SECONDS))
local rollTimeLabel = Raider.UI.Components.CreateLabel(panel, nil, "OVERLAY", "GameFontHighlightSmall")
rollTimeLabel:SetPoint("RIGHT", rollTime, "LEFT", -4, 0)
rollTimeLabel:SetText("Roll time")

local scrollFrame = Raider.UI.Components.CreateScrollFrame(nil, panel)
scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -32)
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)
local scrollContent = Raider.UI.Components.CreateContainer(nil, scrollFrame)
scrollContent:SetWidth(349); scrollContent:SetHeight(200)
scrollContent:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
scrollFrame:SetScrollChild(scrollContent)
local scrollBar = Raider.UI.Components.CreateSliderFrame(nil, panel)
scrollBar:SetOrientation("VERTICAL")
scrollBar:SetWidth(12)
scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -9, -36)
scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -9, 9)
scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
scrollBar:SetMinMaxValues(0, 0)
scrollBar:SetValue(0)
scrollBar:SetScript("OnValueChanged", function() scrollFrame:SetVerticalScroll(this:GetValue()) end)
scrollBar:Hide()
local contentHeight = 0
local scrollExpanded = false
local footerReserve = 8
local appliedFooterReserve = 45
local function UpdateScrollRange()
    local viewportHeight = panel:GetHeight() - 32 - footerReserve
    local maximum = math.max(0, contentHeight - viewportHeight)
    local expanded = maximum <= 0
    if expanded ~= scrollExpanded or footerReserve ~= appliedFooterReserve then
        scrollExpanded = expanded
        appliedFooterReserve = footerReserve
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -32)
        scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", expanded and -13 or -28, footerReserve)
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -9, -36)
        scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -9, footerReserve + 1)
    end
    scrollContent:SetWidth(panel:GetWidth() - (expanded and 19 or 34))
    scrollContent:SetHeight(math.max(contentHeight, viewportHeight))
    scrollBar:SetMinMaxValues(0, maximum)
    if scrollBar:GetValue() > maximum then scrollBar:SetValue(maximum) end
    if maximum > 0 then scrollBar:Show() else scrollBar:Hide() end
end
scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function()
    if scrollBar:IsShown() then scrollBar:SetValue(scrollBar:GetValue() - arg1 * 23) end
end)

local rows = {}
local resultRows = {}
local liveRows = {}
local itemSlots = {}
local displayItems = {}
local displayCount = 0
local function GetGlobalRollDuration()
    local value = tonumber(rollTime:GetText())
    return math.max(1, math.min(60, math.floor(value or DEFAULT_ROLL_SECONDS)))
end
local firstSlot = 1
local firstResult = 1
local firstLiveResult = 1
local activeRoll
local raidRollPending
local lastRoll
local completedRolls = {}
local historyOrderBySource = {}
local lastRollBySource = {}
local expandedHistoryKey
local collapsedRounds = {}
local visibleHistoryLines = {}
local visibleHistoryRounds = {}
local lootSessionNumber = 0
local currentLootSession
local manualRollLink
local currentSessionHasGuid
local sessionOrder = {}
local sessionKnown = {}
local sessionSavedAt = {}
local restoreCandidates = {}
local eligible = {}
local rollTypeNames = { [98] = "Transmog", [99] = "OS", [100] = "MS", [101] = "Reycoin", [102] = "SR" }
local pendingAward
local events
local reyCoinEvents
local tracker
local retention = { sourceLimit = 64, historyLimit = 256, roundLimit = 8,
    historyOrder = {}, pendingKeys = {}, protectedSources = {} }

function retention.ClearMap(values)
    local key
    for key in pairs(values) do values[key] = nil end
end

function retention.ClearSequence(values)
    local index
    for index = table.getn(values), 1, -1 do table.remove(values, index) end
end

function retention.RememberSource(source)
    if not source or sessionKnown[source] then return end
    sessionKnown[source] = true
    sessionSavedAt[source] = date("%H:%M:%S")
    table.insert(sessionOrder, source)
end

function retention.EnsureSource()
    if currentLootSession then return end
    lootSessionNumber = lootSessionNumber + 1
    currentLootSession = "session:" .. lootSessionNumber
    currentSessionHasGuid = false
    retention.RememberSource(currentLootSession)
end

function retention.ResolveHistoryKey(key, link)
    local history = completedRolls[key]
    if not history or history.link == link then return key end
    return key .. ":item:" .. link
end

function retention.IsHistoryProtected(key, history)
    if retention.pendingKeys[key] then return true end
    if activeRoll and activeRoll.historyKey == key then return true end
    if raidRollPending and raidRollPending.historyKey == key then return true end
    if pendingAward and pendingAward.historyKey == key then return true end
    local current = lastRollBySource[currentLootSession]
    return current and current.historyKey == key and not current.manual and not current.awarded
end

function retention.ForgetHistory(key)
    local history = completedRolls[key]
    if not history then return end
    completedRolls[key] = nil; collapsedRounds[key] = nil
    local order = historyOrderBySource[history.source]
    local index
    for index = order and table.getn(order) or 0, 1, -1 do
        if order[index] == key then table.remove(order, index) end
    end
    if order and table.getn(order) == 0 then historyOrderBySource[history.source] = nil end
    for index = table.getn(retention.historyOrder), 1, -1 do
        if retention.historyOrder[index] == key then table.remove(retention.historyOrder, index) end
    end
    local previous = lastRollBySource[history.source]
    if previous and previous.historyKey == key then lastRollBySource[history.source] = nil end
    if lastRoll and lastRoll.historyKey == key then lastRoll = nil end
    if expandedHistoryKey == key then
        expandedHistoryKey = nil
        retention.ClearSequence(visibleHistoryLines); retention.ClearMap(visibleHistoryRounds)
    end
    for index = 1, table.getn(liveRows) do
        local row = liveRows[index]
        if row.roll and row.roll.historyKey == key then
            row.roll = nil; row.result = nil; row.playerName = nil; row:Hide()
        end
    end
    if retention.releaseHistoryView then retention.releaseHistoryView(history.lines) end
end

function retention.ForgetSource(source)
    local order = historyOrderBySource[source]
    while order and table.getn(order) > 0 do retention.ForgetHistory(order[table.getn(order)]) end
    historyOrderBySource[source] = nil; lastRollBySource[source] = nil
    sessionKnown[source] = nil; sessionSavedAt[source] = nil
    local index
    for index = table.getn(sessionOrder), 1, -1 do
        if sessionOrder[index] == source then table.remove(sessionOrder, index) end
    end
    for index = table.getn(restoreCandidates), 1, -1 do
        if restoreCandidates[index].source == source then
            -- Keep the reused sequence's Lua 5.0 stored length in sync.
            table.remove(restoreCandidates, index)
        end
    end
end

function retention.GetHistory(source, key, link, icon, manual)
    retention.RememberSource(source)
    key = retention.ResolveHistoryKey(key, link)
    local history = completedRolls[key]
    if not history then
        history = { source = source, link = link, icon = icon, lines = {}, rounds = 0, manual = manual }
        completedRolls[key] = history
        local order = historyOrderBySource[source]
        if not order then order = {}; historyOrderBySource[source] = order end
        table.insert(order, key); table.insert(retention.historyOrder, key)
    end
    return history, key
end

function retention.TrimRounds(key, history)
    -- Full lines must reach durable award/SR/RC copies before the transient
    -- restore cache can discard old rounds. Manual rolls have no award route.
    if not history.awarded and not history.manual then return end
    if history.rounds <= retention.roundLimit or history.trimmedAtRound == history.rounds then return end
    local lines, rounds, first = history.lines, 0, nil
    local index
    for index = table.getn(lines), 1, -1 do
        if string.find(lines[index], "^Round %d+:") or string.find(lines[index], "^Raid roll %d+/") then
            rounds = rounds + 1
            if rounds == retention.roundLimit then first = index; break end
        end
    end
    if not first or first <= 1 then return end
    local oldCount, kept = table.getn(lines), table.getn(lines) - first + 1
    for index = 1, kept do lines[index] = lines[first + index - 1] end
    for index = oldCount, kept + 1, -1 do table.remove(lines, index) end
    history.trimmedAtRound = history.rounds
    local firstRound = tonumber(Match(lines[1], "^Round (%d+):"))
    local collapsed = collapsedRounds[key]
    if collapsed and firstRound then
        local round
        for round in pairs(collapsed) do if round < firstRound then collapsed[round] = nil end end
        if not next(collapsed) then collapsedRounds[key] = nil end
    end
    local previous = lastRollBySource[history.source]
    if previous and previous.historyKey == key and previous.summaryIndex then previous.summaryIndex = previous.summaryIndex - first + 1 end
    if expandedHistoryKey == key then
        retention.ClearSequence(visibleHistoryLines); retention.ClearMap(visibleHistoryRounds)
    end
    if retention.refreshHistoryView then retention.refreshHistoryView(lines) end
end

function retention.Prune()
    retention.ClearMap(retention.pendingKeys); retention.ClearMap(retention.protectedSources)
    if RaidService.FillPendingLootHistoryKeys then RaidService.FillPendingLootHistoryKeys(retention.pendingKeys) end
    if currentLootSession then retention.protectedSources[currentLootSession] = true end
    if activeRoll then retention.protectedSources[activeRoll.source] = true end
    if raidRollPending then retention.protectedSources[raidRollPending.source] = true end
    if pendingAward then retention.protectedSources[pendingAward.source] = true end
    local index, key, history
    for index = 1, table.getn(retention.historyOrder) do
        key = retention.historyOrder[index]; history = completedRolls[key]
        if retention.IsHistoryProtected(key, history) then retention.protectedSources[history.source] = true
        else retention.TrimRounds(key, history) end
    end
    index = 1
    while table.getn(sessionOrder) > retention.sourceLimit and index <= table.getn(sessionOrder) do
        local source = sessionOrder[index]
        if retention.protectedSources[source] then index = index + 1 else retention.ForgetSource(source) end
    end
    index = 1
    while table.getn(retention.historyOrder) > retention.historyLimit and index <= table.getn(retention.historyOrder) do
        key = retention.historyOrder[index]; history = completedRolls[key]
        if retention.IsHistoryProtected(key, history) then index = index + 1 else retention.ForgetHistory(key) end
    end
end

function retention.Reset()
    if retention.releaseHistoryView then
        local key, history
        for key, history in pairs(completedRolls) do retention.releaseHistoryView(history.lines) end
    end
    retention.ClearMap(completedRolls); retention.ClearMap(historyOrderBySource)
    retention.ClearMap(lastRollBySource); retention.ClearMap(collapsedRounds)
    retention.ClearSequence(sessionOrder); retention.ClearMap(sessionKnown); retention.ClearMap(sessionSavedAt)
    retention.ClearSequence(retention.historyOrder)
    retention.ClearMap(retention.pendingKeys); retention.ClearMap(retention.protectedSources)
    retention.ClearSequence(restoreCandidates); retention.ClearSequence(visibleHistoryLines); retention.ClearMap(visibleHistoryRounds)
    retention.ClearMap(displayItems); expandedHistoryKey = nil; displayCount = 0
    currentLootSession = nil; currentSessionHasGuid = nil; manualRollLink = nil; panel.manualSession = nil
    local index
    for index = 1, table.getn(liveRows) do liveRows[index].roll = nil; liveRows[index].result = nil; liveRows[index].playerName = nil; liveRows[index]:Hide() end
end

-- Explicit read-only diagnostics; no tables are allocated by idle handlers.
function MasterLootWindow.GetHistoryRetentionState(source, historyKey)
    local state = { sourceLimit = retention.sourceLimit, historyLimit = retention.historyLimit,
        roundLimit = retention.roundLimit, sourceOrderCount = table.getn(sessionOrder),
        historyOrderCount = table.getn(retention.historyOrder), historyCount = 0,
        historySourceCount = 0, lastRollCount = 0, collapsedCount = 0,
        knownCount = 0, savedAtCount = 0, totalLines = 0,
        sourceRetained = source and sessionKnown[source] and true or false,
        historyRetained = historyKey and completedRolls[historyKey] and true or false,
        currentSource = currentLootSession, activeSource = activeRoll and activeRoll.source,
        pendingSource = pendingAward and pendingAward.source }
    local key, history
    for key, history in pairs(completedRolls) do state.historyCount = state.historyCount + 1; state.totalLines = state.totalLines + table.getn(history.lines) end
    for key in pairs(historyOrderBySource) do state.historySourceCount = state.historySourceCount + 1 end
    for key in pairs(lastRollBySource) do state.lastRollCount = state.lastRollCount + 1 end
    for key in pairs(collapsedRounds) do state.collapsedCount = state.collapsedCount + 1 end
    for key in pairs(sessionKnown) do state.knownCount = state.knownCount + 1 end
    for key in pairs(sessionSavedAt) do state.savedAtCount = state.savedAtCount + 1 end
    history = historyKey and completedRolls[historyKey]
    state.historyLineCount = history and table.getn(history.lines) or 0
    state.historyRounds = history and history.rounds or 0
    return state
end
local playerColors = {}
local playerColorCodes = {}
local function UpdateClassColors()
    local attendance = Raider.Database.GetRaidAttendance()
    if attendance and attendance.members then
        local memberIndex
        for memberIndex = 1, table.getn(attendance.members) do
            local member = attendance.members[memberIndex]
            local classFile = string.upper(member.classFile or member.class or "")
            local color = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]) or Raider.UI.Components.Theme.classColors[classFile]
            if member.name and color then
                playerColors[member.name] = color
                playerColorCodes[member.name] = string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
            end
        end
    end
    local index
    for index = 1, math.min(40, math.max(0, tonumber(GetNumRaidMembers()) or 0)) do
        local name, _, _, _, _, classFile = GetRaidRosterInfo(index)
        local color = name and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if color then
            playerColors[name] = color
            if not playerColorCodes[name] then
                playerColorCodes[name] = string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
            end
        end
    end
end

function MasterLootWindow.NeedsLootSlotRebind(roll, source, currentLink)
    return roll and roll.source == source and (not roll.slot or currentLink ~= roll.link)
end
local function ColoredName(name)
    local code = playerColorCodes[name]
    return code and (code .. name .. "|r") or name
end
local function ColoredHistoryLine(line)
    if string.find(line, "No rolls", 1, true) then
        return string.gsub(line, "No rolls", "|cff777777No rolls|r")
    end
    local prefix, name, suffix = Match(line, "^(%s*[>v]?%s*Round %d+: )([^%s]+)(.*)$")
    if not prefix then prefix, name, suffix = Match(line, "^(%s+)([^%s]+)(.*)$") end
    if not prefix then prefix, name, suffix = Match(line, "^(Raid roll %d+/%d+: )([^%s]+)(.*)$") end
    if name and playerColorCodes[name] then return prefix .. ColoredName(name) .. suffix end
    return line
end
local function ShowItemTooltip(owner, slot, link)
    if not link then return end
    Raider.UI.Components.AnchorTooltip(owner)
    local shown = false
    if slot and GameTooltip.SetLootItem then
        shown = pcall(GameTooltip.SetLootItem, GameTooltip, slot)
    end
    if not shown and GameTooltip.SetHyperlink then
        local payload = Match(link, "|H([^|]+)|h") or link
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, payload)
    end
    if shown then GameTooltip:Show() else GameTooltip:Hide() end
end
local RefreshResults
local FinishRoll
local CancelRoll
local OpenRestoreMenu
local Announce
local AnnounceMessage
local RefreshTracker
local function ExtendRoll()
    if not activeRoll then return end
    local seconds = activeRoll.duration or DEFAULT_ROLL_SECONDS
    activeRoll.endsAt = activeRoll.endsAt + seconds
    activeRoll.lastRemaining = math.max(0, math.ceil(activeRoll.endsAt - GetTime()))
    AnnounceMessage("Extended", {item=activeRoll.link, seconds=seconds})
    if panel:IsShown() and RefreshResults then RefreshResults() end
    if RefreshTracker then RefreshTracker() end
end
local finishButton = Raider.UI.Components.CreateButton(panel, nil, "Finish", 80, 20)
finishButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -13, 8)
finishButton:SetScript("OnClick", function() if activeRoll then FinishRoll() end end)
finishButton:Hide()
local extendButton = Raider.UI.Components.CreateButton(panel, nil, "Extend", 80, 20)
extendButton:SetPoint("RIGHT", finishButton, "LEFT", -6, 0)
extendButton:SetScript("OnClick", ExtendRoll)
extendButton:Hide()
local restoreButton = Raider.UI.Components.CreateControl(nil, panel)
restoreButton:SetWidth(96); restoreButton:SetHeight(18)
restoreButton.label = Raider.UI.Components.CreateLabel(restoreButton, nil, "OVERLAY", "GameFontNormalSmall")
restoreButton.label:SetAllPoints(restoreButton)
restoreButton.label:SetJustifyH("CENTER"); restoreButton.label:SetJustifyV("MIDDLE")
restoreButton.label:SetText("Restore rolls")
restoreButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
restoreButton:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
restoreButton:SetBackdropBorderColor(0.38, 0.38, 0.38, 0.95)
local restoreHighlight = Raider.UI.Components.CreateTexture(restoreButton, nil, "HIGHLIGHT")
restoreHighlight:SetAllPoints(restoreButton)
restoreHighlight:SetTexture(1, 0.72, 0.12, 0.12)
Raider.UI.Components.AttachGoldHoverBorder(restoreButton, 0.38, 0.38, 0.38, 0.95)
restoreButton:SetPoint("RIGHT", rollTimeLabel, "LEFT", -8, 0)
restoreButton:SetScript("OnClick", function() if OpenRestoreMenu then OpenRestoreMenu() end end)
restoreButton:Hide()
local liveHeader = Raider.UI.Components.CreateLabel(scrollContent, nil, "OVERLAY", "GameFontNormalSmall")
liveHeader:SetText("Current rolls")

local function FindCandidate(name)
    local index
    for index = 1, 40 do
        if GetMasterLootCandidate(index) == name then return index end
    end
end

local shiftAtLootOpen = false
local function AutoLootEnabled()
    return not panel.manualSession and Raider.Services.AutoLoot.IsEnabled(Raider.Database.GetSetting("lmAutoLootMode"), shiftAtLootOpen)
end

local autoLootPendingSlot
local autoLootFailedSlots = {}
local autoLootTimeout = Raider.UI.Components.CreateContainer(nil, panel)
autoLootTimeout:Hide()
local function IsAutoLootQuality(slot)
    local _, name, _, quality = GetLootSlotInfo(slot)
    return Raider.Services.AutoLoot.Allows(name, quality, Raider.Database.GetSetting("lmAutoLootRarities"), Raider.Database.GetSetting("lmAutoLootExceptions"), Raider.Database.GetSetting("lmAutoLootInclusions"))
end

local function AutoLootRoute(slot, candidate)
    if not IsAutoLootQuality(slot) then return nil end
    if candidate then return "master" end
    local _, _, _, quality = GetLootSlotInfo(slot)
    local threshold = type(GetLootThreshold) == "function" and GetLootThreshold() or 2
    if quality < threshold then return "direct" end
    return nil
end

local function AutoLootNext()
    if autoLootPendingSlot or not panel:IsShown() or not RaidService.IsPlayerLootMaster() or not AutoLootEnabled() then return end
    local candidate = FindCandidate(UnitName("player"))
    local slot
    for slot = 1, GetNumLootItems() or 0 do
        if LootSlotIsItem(slot) and not autoLootFailedSlots[slot] then
            local route = AutoLootRoute(slot, candidate)
            if route then
                autoLootPendingSlot = slot
                autoLootTimeout.remaining = 3
                autoLootTimeout:Show()
                if route == "direct" then LootSlot(slot) else GiveMasterLoot(slot, candidate) end
                return
            end
        end
    end
end

local function CanGive(roll, name)
    if not roll or not panel:IsShown() or not RaidService.IsPlayerLootMaster() then return nil, nil, "Master Loot is not open." end
    if not RaidService.IsLootSessionCurrent(roll.lootSessionToken) then return nil, nil, "This roll belongs to a previous raid session." end
    if roll.awarded or pendingAward then return nil,nil,"This item was already given or an award is pending." end
    if roll.results then
        if activeRoll or raidRollPending or lastRollBySource[currentLootSession]~=roll then return nil,nil,"This roll was replaced by a newer round." end
    elseif activeRoll or raidRollPending then return nil,nil,"Wait for the current roll to finish." end
    if roll.manual then return nil, nil, "A linked item roll cannot be awarded through Master Loot." end
    if roll.tieGroups and Raider.Services.LootRollRequest.HasBlockingTie(roll,roll.tieGroups) then return nil,nil,"Resolve the tied roll before giving loot." end
    if roll.source and roll.source ~= currentLootSession then return nil, nil, "Return to the original loot source to give this item." end
    local slot
    if roll.slot and LootSlotIsItem(roll.slot) and GetLootSlotLink(roll.slot) == roll.link then slot = roll.slot end
    if not slot then
        local index
        local lootCount = GetNumLootItems() or 0
        for index = 1, lootCount do
            if LootSlotIsItem(index) and GetLootSlotLink(index) == roll.link then slot = index; break end
        end
    end
    if not slot then return nil, nil, "The item is no longer in this loot window." end
    local candidate = FindCandidate(name)
    if not candidate then return nil, nil, "The player is not eligible or is out of range." end
    return candidate, slot
end

function MasterLootWindow.ResolveTies(roll)
    roll.tieGroups=Raider.Services.LootRollRequest.GetTieGroups(roll)
    if Raider.Services.LootRollRequest.HasBlockingTie(roll,roll.tieGroups) then
        roll.winner,roll.winnerResult,roll.tradeWinner,roll.tradeWinnerResult=nil,nil,nil,nil
    end
end

local function AwardToPlayer(roll, name)
    local candidate, slot, reason = CanGive(roll, name)
    if not candidate then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Raider: " .. reason) end
        return
    end
    local history = roll.historyKey and completedRolls[roll.historyKey]
    local lootIcon, lootName, quantity = GetLootSlotInfo(slot)
    local historyKey = retention.ResolveHistoryKey(roll.historyKey or (roll.source .. ":" .. slot .. ":award:" .. roll.link), roll.link)
    roll.historyKey = historyKey
    RaidService.QueueLootAwardForReceipt(name, roll.link, historyKey,
        history and history.link == roll.link and history.lines or nil, quantity)
    pendingAward = { source = roll.source, slot = slot, link = roll.link,
        lootSessionToken = roll.lootSessionToken,
        historyKey = historyKey,
        icon = lootIcon, winner = name,
        softReserve = roll.winnerResult and roll.winnerResult.range == 102 and roll.winner == name }
    if RaidService.debugReyCoin and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("Raider Reycoin trace: Give loot recipient=" .. tostring(name)
            .. " winner=" .. tostring(roll.winner) .. " tradeWinner=" .. tostring(roll.tradeWinner)
            .. " reyCoin=" .. tostring(roll.winnerUsesReyCoin) .. " slot=" .. tostring(slot)
            .. " slotName=" .. tostring(lootName) .. " rollItem=" .. tostring(Match(tostring(roll.link or ""), "item:(%d+)")))
    end
    local reyCoinWinner = roll.tradeWinnerResult and roll.tradeWinnerResult.range == 101 and roll.tradeWinner
        or (roll.winnerResult and roll.winnerResult.range == 101 and roll.winner)
    if reyCoinWinner and roll.winner and name and string.lower(name) == string.lower(roll.winner) then
        local reyCoinRollers = {}
        if roll.results then
            local index
            for index = 1, table.getn(roll.results) do
                local result = roll.results[index]
                if result and result.valid ~= false and result.range == 101 and result.name then
                    reyCoinRollers[string.lower(result.name)] = true
                end
            end
        end
        if RaidService.QueueReyCoinAward(reyCoinWinner, roll.link, name,
            reyCoinRollers, roll.historyKey, history and history.link == roll.link and history.lines or nil, quantity) then
            if string.lower(name) == string.lower(UnitName("player") or "") then
                reyCoinEvents.TrackLocalBag(roll.link)
            end
        end
    end
    if roll.tradeWinnerResult and roll.tradeWinnerResult.range == 102 and roll.tradeWinner
        and roll.winner and string.lower(name) == string.lower(roll.winner) then
        RaidService.QueueSoftReserveTrade(roll.tradeWinner, roll.link, name,
            roll.historyKey, history and history.link == roll.link and history.lines or nil, quantity)
    end
    GiveMasterLoot(slot, candidate)
end
local giveConfirmation
local function ConfirmGive(roll, name)
    local candidate, slot, reason = CanGive(roll, name)
    if not candidate then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Raider: " .. reason) end
        return
    end
    if not giveConfirmation then
        giveConfirmation = Raider.UI.Components.Window.CreateProjectConfirmation("BootyRaiderGiveLoot", "Give Master Loot", "Give loot", "lootmaster", {modal = false})
        Raider.UI.Components.RegisterEscapeDialog(giveConfirmation)
        if Stack then Stack.SetOwner(giveConfirmation, panel) end
    end
    giveConfirmation.data = {roll = roll, name = name}
    giveConfirmation:Open("Give " .. tostring(roll.link or "item") .. " to " .. tostring(name) .. "?", function()
        local data = giveConfirmation.data
        AwardToPlayer(data and data.roll, data and data.name)
    end)
    giveConfirmation:ClearAllPoints(); giveConfirmation:SetPoint("BOTTOM", panel, "TOP", 0, 8)
end

local candidateMenu = Raider.UI.Components.CreateContainer("BootyRaiderLootCandidates", UIParent)
candidateMenu:SetWidth(220); candidateMenu:SetHeight(360)
candidateMenu:EnableMouse(true); candidateMenu:Hide()
local candidateDismiss = Raider.UI.Components.CreateControl(nil, UIParent)
candidateDismiss:SetAllPoints(UIParent)
candidateDismiss:RegisterForClicks("LeftButtonUp", "RightButtonUp")
candidateDismiss:SetScript("OnClick", function() candidateMenu:Hide() end)
candidateDismiss:Hide()
candidateMenu:SetScript("OnHide", function() candidateDismiss:Hide() end)
candidateMenu:SetMovable(true); candidateMenu:RegisterForDrag("LeftButton")
candidateMenu:SetScript("OnDragStart", function() this:StartMoving() end)
candidateMenu:SetScript("OnDragStop", function() this:StopMovingOrSizing(); this.userMoved = true end)
candidateMenu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
candidateMenu:SetBackdropColor(0.02, 0.02, 0.02, 0.98); candidateMenu:SetBackdropBorderColor(0.68, 0.54, 0.27, 1)
if Stack then Stack.Register(candidateMenu, {owner = panel, kind = "popup", dismiss = candidateDismiss}) end
local candidateButtons = {}
local eligibleCandidates = {}
local groupCounts = {}
local RestoreSession
local restorePicker = Raider.UI.Components.CreateContainer("BootyRaiderRestoreRolls", UIParent)
restorePicker:SetWidth(340); restorePicker:SetHeight(60)
restorePicker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
restorePicker:EnableMouse(true); restorePicker:Hide()
if Stack then Stack.Register(restorePicker, {owner = panel}) end
restorePicker:SetMovable(true); restorePicker:RegisterForDrag("LeftButton")
restorePicker:SetScript("OnDragStart", function() this:StartMoving() end)
restorePicker:SetScript("OnDragStop", function() this:StopMovingOrSizing(); this.userMoved = true end)
restorePicker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
restorePicker:SetBackdropColor(0.02, 0.02, 0.02, 0.98); restorePicker:SetBackdropBorderColor(0.68, 0.54, 0.27, 1)
local restoreTitle = Raider.UI.Components.CreateLabel(restorePicker, nil, "OVERLAY", "GameFontNormalSmall")
restoreTitle:SetPoint("TOPLEFT", restorePicker, "TOPLEFT", 12, -12)
restoreTitle:SetText("Choose a prior roll only if this is the same corpse")
local restoreClose = Raider.UI.Components.CreateWindowButton(restorePicker, nil, "close")
restoreClose:SetPoint("RIGHT", restorePicker, "TOPRIGHT", -8, -17)
restoreClose:SetScript("OnClick", function() restorePicker:Hide() end)


local restoreRows = {}
local restoreIndex
for restoreIndex = 1, 8 do
    local button = Raider.UI.Components.CreateButton(restorePicker, nil, "", 314, 21)
    button:SetPoint("TOPLEFT", restorePicker, "TOPLEFT", 12, -36 - (restoreIndex - 1) * 24)
    button:SetScript("OnClick", function()
        local source = this.source
        restorePicker:Hide()
        if source and RestoreSession then RestoreSession(source) end
    end)
    button:Hide()
    restoreRows[restoreIndex] = button
end

local function FindMatchingLootSlot(link)
    local slot
    local lootCount = GetNumLootItems() or 0
    for slot = 1, lootCount do
        if LootSlotIsItem(slot) and GetLootSlotLink(slot) == link then return slot end
    end
end

local function FindHistoryForItem(source, slot, link)
    if not source then return end
    local directKey = slot and (source .. ":" .. slot) or nil
    local direct = directKey and completedRolls[directKey]
    if direct and direct.link == link then return direct, directKey end
    local order = historyOrderBySource[source]
    local found, foundKey
    local index
    for index = 1, order and table.getn(order) or 0 do
        local history = completedRolls[order[index]]
        if history and history.link == link then
            if found then return nil end
            found = history; foundKey = order[index]
        end
    end
    return found, foundKey
end

local function UpdateRestoreCandidates()
    local index
    retention.ClearSequence(restoreCandidates)
    if currentSessionHasGuid then restoreButton:Hide(); return end
    for index = table.getn(sessionOrder), 1, -1 do
        local source = sessionOrder[index]
        if source ~= currentLootSession then
            local roll = activeRoll and activeRoll.source == source and activeRoll or lastRollBySource[source]
            local match = roll and FindMatchingLootSlot(roll.link)
            if not match then
                local order = historyOrderBySource[source]
                local historyIndex
                for historyIndex = 1, order and table.getn(order) or 0 do
                    local history = completedRolls[order[historyIndex]]
                    if history and FindMatchingLootSlot(history.link) then
                        match = true; roll = { link = history.link, winner = history.latestWinner }; break
                    end
                end
            end
            if match and roll then
                local entry = restoreCandidates[table.getn(restoreCandidates) + 1] or {}
                entry.source = source
                entry.label = "|cffffd700Loot:|r " .. roll.link .. " - " .. (sessionSavedAt[source] or "--:--:--")
                table.insert(restoreCandidates, entry)
                if table.getn(restoreCandidates) >= 8 then break end
            end
        end
    end
    if table.getn(restoreCandidates) > 0 then restoreButton:Show() else restoreButton:Hide() end
end

local function CreateRowActionButton(parent, text, width, height)
    local button = Raider.UI.Components.CreateControl(nil, parent)
    button:SetWidth(width); button:SetHeight(height)
    button.label = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetAllPoints(button)
    button.label:SetJustifyH("CENTER"); button.label:SetJustifyV("MIDDLE")
    button.label:SetText(text)
    local highlight = Raider.UI.Components.CreateTexture(button, nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetTexture(1, 0.72, 0.12, 0.12)
    button.highlight = highlight
    return button
end

OpenRestoreMenu = function()
    if restorePicker:IsShown() then restorePicker:Hide(); return end
    UpdateRestoreCandidates()
    local index
    for index = 1, 8 do
        local row = restoreRows[index]
        local candidate = restoreCandidates[index]
        if candidate then row.source = candidate.source; row:SetText(candidate.label); row:Show()
        else row.source = nil; row:Hide() end
    end
    if table.getn(restoreCandidates) > 0 then
        restorePicker:SetHeight(44 + table.getn(restoreCandidates) * 24)
        if not restorePicker.userMoved then
            restorePicker:ClearAllPoints()
            restorePicker:SetPoint("BOTTOM", panel, "TOP", 0, 8)
        end
        restorePicker:Show()
    end
end
local candidateGroupPanels = {}
local groupIndex, memberPosition
for groupIndex = 1, 8 do
    local groupPanel = Raider.UI.Components.CreateContainer(nil, candidateMenu)
    groupPanel:SetWidth(100); groupPanel:SetHeight(80)
    groupPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    groupPanel:SetBackdropColor(0.07, 0.07, 0.07, 0.92); groupPanel:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.85)
    local heading = Raider.UI.Components.CreateLabel(candidateMenu, nil, "OVERLAY", "GameFontNormalSmall")
    heading:SetPoint("BOTTOMLEFT", groupPanel, "TOPLEFT", 7, 2); heading:SetText("Group " .. groupIndex)
    groupPanel.heading = heading
    heading:Hide()
    for memberPosition = 1, 5 do
        local button = Raider.UI.Components.CreateControl(nil, groupPanel)
        button:SetWidth(88); button:SetHeight(13)
        button:SetPoint("TOPLEFT", groupPanel, "TOPLEFT", 7, -4 - (memberPosition - 1) * 14)
        button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        button:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
        button.hover = Raider.UI.Components.CreateTexture(button, nil, "HIGHLIGHT")
        button.hover:SetAllPoints(button)
        button.hover:SetTexture(1, 0.78, 0.28, 0.16)
        button.label = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontHighlightSmall")
        button.label:SetPoint("LEFT", button, "LEFT", 3, 0)
        button.label:SetWidth(82); button.label:SetJustifyH("LEFT")
        button:SetScript("OnEnter", function()
            this:SetBackdropColor(0.25, 0.20, 0.09, 0.9)
            if this.unavailableReason then
                Raider.UI.Components.AnchorTooltip(this)
                GameTooltip:SetText(this.unavailableReason)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            this:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
            GameTooltip:Hide()
        end)
        button:SetScript("OnClick", function()
            local name = this.memberName
            local item = candidateMenu.lootRef
            if name and item then ConfirmGive(item, name) end
            candidateMenu:Hide()
        end)
        button:RegisterForClicks("LeftButtonUp")
        button:Hide()
        candidateButtons[(groupIndex - 1) * 5 + memberPosition] = button
    end
    candidateGroupPanels[groupIndex] = groupPanel
end

local function OpenCandidateMenu(slot, link)
    if activeRoll or raidRollPending then return end
    retention.EnsureSource()
    if not slot or not link or not RaidService.IsPlayerLootMaster() then return end
    if not LootSlotIsItem(slot) or GetLootSlotLink(slot) ~= link then return end
    local _, historyKey = FindHistoryForItem(currentLootSession, slot, link)
    candidateMenu.lootRef = { slot = slot, link = link, source = currentLootSession, historyKey = historyKey,
        lootSessionToken = RaidService.GetLootSessionToken() }
    local index
    for index in pairs(eligibleCandidates) do eligibleCandidates[index] = nil end
    for index = 1, 40 do
        local name = GetMasterLootCandidate(index)
        if name then eligibleCandidates[name] = true end
    end
    for index = 1, 8 do groupCounts[index] = 0 end
    for index = 1, 40 do
        local button = candidateButtons[index]
        button.memberName = nil; button:Hide()
    end
    local raidCount = GetNumRaidMembers() or 0
    for index = 1, raidCount do
        local name, _, subgroup, _, class, classFile, _, online = GetRaidRosterInfo(index)
        subgroup = tonumber(subgroup) or 1
        if name and subgroup >= 1 and subgroup <= 8 and groupCounts[subgroup] < 5 then
            groupCounts[subgroup] = groupCounts[subgroup] + 1
            local button = candidateButtons[(subgroup - 1) * 5 + groupCounts[subgroup]]
            button.memberName = name
            local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile or string.upper(class or "")]
            if classColor then button.label:SetTextColor(classColor.r, classColor.g, classColor.b)
            else button.label:SetTextColor(1, 1, 1) end
            if eligibleCandidates[name] then
                button.unavailableReason = nil
                button.label:SetText(groupCounts[subgroup] .. ". " .. name)
                button:Enable(); button:SetAlpha(1)
            else
                button.unavailableReason = online and "Not on the eligible list: out of range or otherwise ineligible." or "Player is offline."
                button.label:SetText(groupCounts[subgroup] .. ". " .. name)
                button.label:SetTextColor(0.48, 0.48, 0.48)
                button:Disable(); button:SetAlpha(1)
            end
            button:Show()
        end
    end
    local leftHeight, rightHeight, visibleGroups = 0, 0, 0
    for index = 1, 8 do
        local groupPanel = candidateGroupPanels[index]
        local count = groupCounts[index]
        if count > 0 then
            visibleGroups = visibleGroups + 1
            local height = 6 + count * 14
            groupPanel:SetHeight(height)
            groupPanel:ClearAllPoints()
            if visibleGroups <= 4 then
                groupPanel:SetPoint("TOPLEFT", candidateMenu, "TOPLEFT", 8, -22 - leftHeight)
                leftHeight = leftHeight + height + 24
            else
                groupPanel:SetPoint("TOPLEFT", candidateMenu, "TOPLEFT", 112, -22 - rightHeight)
                rightHeight = rightHeight + height + 24
            end
            groupPanel.heading:Show()
            groupPanel:Show()
        else groupPanel.heading:Hide(); groupPanel:Hide() end
    end
    candidateMenu:SetWidth(visibleGroups > 4 and 220 or 116)
    candidateMenu:SetHeight(6 + math.max(leftHeight, rightHeight))
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x = x / scale + 12; y = y / scale
    x = math.max(8, math.min(x, UIParent:GetWidth() - candidateMenu:GetWidth() - 8))
    y = math.max(candidateMenu:GetHeight() + 8, math.min(y, UIParent:GetHeight() - 8))
    if not candidateMenu.userMoved then
        candidateMenu:ClearAllPoints()
        candidateMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
    candidateDismiss:Show()
    candidateMenu:Show()
end

RefreshResults = function()
    if activeRoll and activeRoll.source == currentLootSession then
        finishButton:Show(); extendButton:Show(); footerReserve = 32
    else finishButton:Hide(); extendButton:Hide(); footerReserve = 8 end
    local index
    local lootRows = math.max(1, math.min(MAX_ROWS, displayCount))
    local expandedHistory
    local expandedRow
    for index = 1, MAX_ROWS do
        local row = rows[index]
        if row.link then
            local history, key
            if row.historyKey then history = completedRolls[row.historyKey]; key = row.historyKey
            else history, key = FindHistoryForItem(currentLootSession, row.slot, row.link) end
            if history and table.getn(history.lines) > 0 and key == expandedHistoryKey then expandedHistory = history; expandedRow = index; break end
        end
    end
    local historyCount = 0
    local previousHistoryCount = table.getn(visibleHistoryLines)
    if expandedHistory then
        local hidden = false
        local collapsed = collapsedRounds[expandedHistoryKey]
        for index = 1, table.getn(expandedHistory.lines) do
            local line = expandedHistory.lines[index]
            local round = tonumber(Match(line, "^Round (%d+):"))
            if round then
                hidden = collapsed and collapsed[round]
                historyCount = historyCount + 1
                local nextLine = expandedHistory.lines[index + 1]
                local hasDetails = nextLine and not Match(nextLine, "^Round %d+:")
                local visibleLine = (hasDetails and (hidden and "> " or "v ") or "") .. ColoredHistoryLine(line)
                if visibleHistoryLines[historyCount] then visibleHistoryLines[historyCount] = visibleLine else table.insert(visibleHistoryLines, visibleLine) end
                visibleHistoryRounds[historyCount] = hasDetails and round or nil
            elseif not hidden then
                historyCount = historyCount + 1
                local visibleLine = ColoredHistoryLine(line)
                if visibleHistoryLines[historyCount] then visibleHistoryLines[historyCount] = visibleLine else table.insert(visibleHistoryLines, visibleLine) end
                visibleHistoryRounds[historyCount] = nil
            end
        end
    end
    for index = previousHistoryCount, historyCount + 1, -1 do
        table.remove(visibleHistoryLines, index); visibleHistoryRounds[index] = nil
    end
    firstResult = math.min(firstResult, math.max(1, historyCount - MAX_RESULT_ROWS + 1))
    local historyVisible = math.min(MAX_RESULT_ROWS, historyCount)
    local extraHeight = expandedHistory and (historyVisible * 23 + 4) or 0
    for index = 1, MAX_ROWS do
        local row = rows[index]
        local top = -2 - (index - 1) * ROW_HEIGHT - (expandedRow and index > expandedRow and extraHeight or 0)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, top)
        row:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, top)
        if row.link then
            local history = row.historyKey and completedRolls[row.historyKey] or FindHistoryForItem(currentLootSession, row.slot, row.link)
            local hasHistory = history and table.getn(history.lines) > 0
            row.historyIndicator:SetText(hasHistory and (expandedRow == index and "v" or ">") or "")
            local historySpacing = hasHistory and true or false
            if row.historySpacing ~= historySpacing then
                row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row.icon, "RIGHT", historySpacing and 17 or 7, 1)
                row.name:SetPoint("RIGHT", row, "RIGHT", -125, 0)
                row.historySpacing = historySpacing
            end
        else row.historyIndicator:SetText("") end
    end
    for index = 1, MAX_RESULT_ROWS do
        local row = resultRows[index]
        local line = expandedHistory and firstResult + index - 1 <= historyCount
            and visibleHistoryLines[firstResult + index - 1]
        if line then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", rows[expandedRow], "BOTTOMLEFT", 3, -4 - (index - 1) * 23)
            row.text:SetText(line)
            row.roundNumber = visibleHistoryRounds[firstResult + index - 1]
            row:Show()
        else row.roundNumber = nil; row:Hide() end
    end

    local liveRoll = activeRoll and activeRoll.source == currentLootSession and activeRoll or lastRollBySource[currentLootSession]
    if raidRollPending and raidRollPending.source == currentLootSession then liveRoll = raidRollPending end
    local liveResults = liveRoll and liveRoll.results
    if liveRoll and activeRoll ~= liveRoll and not liveRoll.raidRoll then MasterLootWindow.ResolveTies(liveRoll) end
    local liveCount = liveResults and table.getn(liveResults) or 0
    firstLiveResult = math.min(firstLiveResult, math.max(1, liveCount - MAX_LIVE_ROWS + 1))
    local liveHeight = liveRoll and (22 + math.max(1, math.min(MAX_LIVE_ROWS, liveCount)) * 23) or 0
    liveHeader:ClearAllPoints()
    liveHeader:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 3, -9 - lootRows * ROW_HEIGHT - extraHeight)
    if liveRoll then
        if activeRoll == liveRoll then
            liveHeader:SetText("Current roll - Remaining time: " .. math.max(0, liveRoll.lastRemaining or DEFAULT_ROLL_SECONDS) .. "s.")
        elseif raidRollPending == liveRoll or liveRoll.raidRollResult then liveHeader:SetText("Current roll - Raid roll")
        else liveHeader:SetText("Current roll") end
        liveHeader:Show()
    else liveHeader:Hide() end
    for index = 1, MAX_LIVE_ROWS do
        local row = liveRows[index]
        row.rerollRange = nil; if row.rerollButton then row.rerollButton:Hide() end
        local result = liveResults and liveResults[firstLiveResult + index - 1]
        if result then
            row.playerName = result.name; row.roll = liveRoll; row.result = result
            local winningResult = liveRoll.winnerResult and liveRoll.winnerResult == result or (not liveRoll.winnerResult and liveRoll.winner == result.name and result.valid ~= false)
            local showItemLink = liveRoll.raidRoll or (activeRoll ~= liveRoll and winningResult)
            if showItemLink and liveRoll.link then
                row.text:ClearAllPoints(); row.text:SetPoint("LEFT", row, "LEFT", 5, 0)
                row.text:SetText(ColoredName(result.name) .. " - ")
                row.text:SetWidth(row.text:GetStringWidth() + 2)
                row.itemHit.itemId = tonumber(Match(liveRoll.link, "item:(%d+)"))
                row.itemHit.itemName = Match(liveRoll.link, "%[([^%]]+)%]")
                row.itemHit.text:SetText(liveRoll.link)
                row.itemHit:SetWidth(row.itemHit.text:GetStringWidth() + 2)
                row.itemHit:ClearAllPoints(); row.itemHit:SetPoint("LEFT", row.text, "RIGHT", 0, 0)
                row.valueText:ClearAllPoints(); row.valueText:SetPoint("LEFT", row.itemHit, "RIGHT", 0, 0)
                if liveRoll.raidRoll then row.valueText:SetText(" - " .. result.value .. "/" .. liveRoll.raidCount)
                else row.valueText:SetText(" (" .. result.value .. ")" .. (result.valid == false and " - Invalid" or "")
                    .. (liveRoll.tradedTo and winningResult and " - traded to " .. liveRoll.tradedTo or "")) end
                row.itemHit:Show(); row.valueText:Show()
            else
                row.itemHit:Hide(); row.valueText:Hide()
                row.text:ClearAllPoints(); row.text:SetPoint("LEFT", row, "LEFT", 5, 0); row.text:SetPoint("RIGHT", row, "RIGHT", -85, 0)
                if result.valid == false then
                    row.text:SetText(result.name .. " - (" .. result.value .. ") - Invalid roll (" .. result.shortInvalidReason .. ")")
                else row.text:SetText(ColoredName(result.name) .. " - (" .. result.value .. ")") end
            end
            if result.valid == false then row.text:SetTextColor(1, 0.28, 0.28)
            else row.text:SetTextColor(1, 1, 1) end
            if activeRoll ~= liveRoll and winningResult then row:SetBackdropBorderColor(1, 0.78, 0.2, 1)
            else row:SetBackdropBorderColor(0, 0, 0, 0) end
            if activeRoll or liveRoll.source ~= currentLootSession or liveRoll.manual then
                row.giveButton:Hide()
            else
                row.giveButton:Show()
                if result.valid == false or (liveRoll.raidRoll and not liveRoll.awardable) then
                    row.giveButton:Disable(); row.giveButton:SetAlpha(0.35)
                    row.giveButton:SetBackdropBorderColor(0.38, 0.38, 0.38, 0.9)
                    row.giveButton.highlight:SetAlpha(0)
                else row.giveButton:Enable(); row.giveButton:SetAlpha(1); row.giveButton.highlight:SetAlpha(1) end
            end
            if not activeRoll and not liveRoll.awarded and liveRoll.source == currentLootSession then
                for _, group in ipairs(liveRoll.tieGroups or {}) do
                    if result.valid ~= false and result.range == group.range and result.value == group.value then
                        row.rerollRange = group.range; row.rerollButton:Show(); row.giveButton:Hide()
                    end
                end
            end
            row:Show()
        elseif liveRoll and liveCount == 0 and index == 1 then
            row.playerName = nil; row.roll = nil; row.result = nil
            row.itemHit:Hide(); row.valueText:Hide()
            row.text:ClearAllPoints(); row.text:SetPoint("LEFT", row, "LEFT", 5, 0); row.text:SetPoint("RIGHT", row, "RIGHT", -85, 0)
            row.text:SetText(liveRoll.raidRollResult or (raidRollPending == liveRoll and "Raid roll in progress..." or (activeRoll == liveRoll and "Waiting for rolls..." or "No rolls")))
            row.text:SetTextColor(activeRoll == liveRoll and 1 or 0.48, activeRoll == liveRoll and 1 or 0.48, activeRoll == liveRoll and 1 or 0.48)
            row.giveButton:Hide(); row:Show()
        else row.playerName = nil; row.roll = nil; row.result = nil; row.itemHit:Hide(); row.valueText:Hide(); row:Hide() end
    end
    contentHeight = lootRows * ROW_HEIGHT + extraHeight + liveHeight + 2
    UpdateScrollRange()
    local contentWidth = scrollContent:GetWidth()
    for index = 1, MAX_RESULT_ROWS do resultRows[index]:SetWidth(contentWidth - 6) end
    for index = 1, MAX_LIVE_ROWS do liveRows[index]:SetWidth(contentWidth - 3) end
end

local function Refresh()
    local count = GetNumLootItems() or 0
    local autoEnabled = AutoLootEnabled() and RaidService.IsPlayerLootMaster()
    local autoCandidate = autoEnabled and FindCandidate(UnitName("player"))
    local index, slot
    retention.ClearSequence(itemSlots)
    for slot = 1, count do
        if LootSlotIsItem(slot) and not (autoEnabled and not autoLootFailedSlots[slot] and AutoLootRoute(slot, autoCandidate)) then
            table.insert(itemSlots, slot)
        end
    end
    local itemCount = table.getn(itemSlots)
    displayCount = 0
    for index = 1, itemCount do
        displayCount = displayCount + 1
        local entry = displayItems[displayCount] or {}
        displayItems[displayCount] = entry
        entry.slot = itemSlots[index]; entry.historyKey = nil; entry.manual = nil; entry.link = nil
    end
    if manualRollLink and currentLootSession and string.find(currentLootSession, "^manual:") then
        displayCount = displayCount + 1
        local entry = displayItems[displayCount] or {}
        displayItems[displayCount] = entry
        entry.slot = nil; entry.historyKey = nil; entry.link = manualRollLink; entry.manual = true
    end
    local order = historyOrderBySource[currentLootSession]
    for index = 1, order and table.getn(order) or 0 do
        local key = order[index]
        local history = completedRolls[key]
        if history and history.awarded then
            displayCount = displayCount + 1
            local entry = displayItems[displayCount] or {}
            displayItems[displayCount] = entry
            entry.slot = nil; entry.historyKey = key; entry.link = history.link; entry.manual = nil
        end
    end
    firstSlot = math.min(firstSlot, math.max(1, displayCount - MAX_ROWS + 1))
    if activeRoll and not activeRoll.manual and activeRoll.slot
        and activeRoll.source == currentLootSession and GetLootSlotLink(activeRoll.slot) ~= activeRoll.link then
        for index = 1, itemCount do
            slot = itemSlots[index]
            if GetLootSlotLink(slot) == activeRoll.link then activeRoll.slot = slot; break end
        end
    end
    for index = 1, MAX_ROWS do
        local row = rows[index]
        local entry = displayItems[firstSlot + index - 1]
        slot = entry and entry.slot
        if entry and firstSlot + index - 1 <= displayCount then
            local texture, name, quantity, quality
            if slot then texture, name, quantity, quality = GetLootSlotInfo(slot) end
            row.slot = slot; row.historyKey = entry.historyKey
            row.link = slot and GetLootSlotLink(slot) or entry.link
            local awarded = row.historyKey and completedRolls[row.historyKey]
            if awarded and awarded.awarded then
                row:SetBackdropBorderColor(1, 0.78, 0.2, 1)
            else row:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.8) end
            row.winner:ClearAllPoints()
            if awarded then row.winner:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            else row.winner:SetPoint("RIGHT", row.rollButton, "LEFT", -7, 1) end
            local manualName, manualTexture
            if entry.manual then
                local itemId = tonumber(Match(tostring(entry.link), "item:(%d+)"))
                local equipLocation
                manualName, _, _, _, _, _, _, _, equipLocation, manualTexture = GetItemInfo(itemId or entry.link)
                if type(GetItemIcon) == "function" then
                    local icon = GetItemIcon(itemId or entry.link)
                    if icon then manualTexture = icon end
                end
                if not manualTexture and type(equipLocation) == "string"
                    and string.find(equipLocation, "Interface\\", 1, true) then manualTexture = equipLocation end
                if type(manualTexture) ~= "string" then manualTexture = nil end
            end
            row.icon:SetVertexColor(1, 1, 1, 1)
            row.icon:SetTexture(texture or manualTexture or (awarded and awarded.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(entry.manual and entry.link
                or (slot and ("[" .. (name or "Loot") .. "]" .. ((quantity or 1) > 1 and " x" .. quantity or "")) or ("Awarded: " .. tostring(entry.link))))
            row.nameHit:SetWidth(math.max(1, math.min(row.name:GetWidth(), row.name:GetStringWidth() + 2)))
            local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
            if awarded then row.name:SetTextColor(title:GetTextColor())
            elseif color then row.name:SetTextColor(color.r, color.g, color.b)
            else row.name:SetTextColor(1, 1, 1) end
            local completed = row.historyKey and completedRolls[row.historyKey] or FindHistoryForItem(currentLootSession, slot, row.link)
            if completed and completed.latestWinner then
                row.winner:SetText(completed.tradedTo and (completed.latestWinner .. " traded to " .. completed.tradedTo) or completed.latestWinner)
                local winnerColor = playerColors[completed.tradedTo or completed.latestWinner]
                if winnerColor then row.winner:SetTextColor(winnerColor.r, winnerColor.g, winnerColor.b)
                else row.winner:SetTextColor(1, 1, 1) end
                row.rewardIcon:ClearAllPoints()
                row.rewardIcon:SetPoint("RIGHT", row.winner, "RIGHT", -row.winner:GetStringWidth() - 3, 0)
                row.rewardIcon:Show()
            else row.winner:SetText(""); row.rewardIcon:Hide() end
            if entry.manual then row.rollButton:Hide(); row.raidButton:Hide()
            elseif not slot then row.rollButton:Hide(); row.raidButton:Hide()
            elseif activeRoll and activeRoll.source == currentLootSession and activeRoll.slot == slot then
                row.rollButton:Show(); row.raidButton:Show(); row.raidButton:Disable()
                if row.rollButton.icon then row.rollButton.icon:Hide() end
                if row.rollButton.stopIcon then row.rollButton.stopIcon:Show() end
                if row.rollButton.stopSlash then row.rollButton.stopSlash:Show() end
                row.rollButton.label:SetText(""); row.rollButton:Enable()
                row.rollButton:SetAlpha(1); row.raidButton:SetAlpha(0.35)
            else
                row.rollButton:Show(); row.raidButton:Show()
                if row.rollButton.icon then row.rollButton.icon:Show() end
                if row.rollButton.stopIcon then row.rollButton.stopIcon:Hide() end
                if row.rollButton.stopSlash then row.rollButton.stopSlash:Hide() end
                row.rollButton.label:SetText("")
                if row.link and LootSlotIsItem(slot) and not activeRoll and not raidRollPending then
                    row.rollButton:Enable(); row.raidButton:Enable()
                    row.rollButton:SetAlpha(1); row.raidButton:SetAlpha(1)
                else
                    row.rollButton:Disable(); row.raidButton:Disable()
                    row.rollButton:SetAlpha(0.35); row.raidButton:SetAlpha(0.35)
                end
            end
            row:Show()
        else
            row.slot = nil; row.link = nil; row.historyKey = nil; row.rewardIcon:Hide(); row:Hide()
        end
    end
    RefreshResults()
end

RestoreSession = function(source)
    if not sessionKnown[source] then return end
    if activeRoll and activeRoll.source ~= source then
        status:SetText("Finish the current roll before restoring another session")
        return
    end
    if activeRoll and activeRoll.source == source and BootyRaiderRollTracker then BootyRaiderRollTracker:Hide() end
    if activeRoll and activeRoll.source == source then
        local slot = FindMatchingLootSlot(activeRoll.link)
        if slot then activeRoll.slot = slot end
    end
    local previous = lastRollBySource[source]
    if previous then
        local slot = FindMatchingLootSlot(previous.link)
        if slot then previous.slot = slot end
    end
    currentLootSession = source
    retention.Prune()
    expandedHistoryKey = nil; firstResult = 1; firstLiveResult = 1
    restoreButton:Hide(); tracker:Hide()
    if activeRoll and activeRoll.source == source then
        status:SetText("Rolling for " .. activeRoll.link .. " - " .. (activeRoll.lastRemaining or DEFAULT_ROLL_SECONDS) .. "s")
    else status:SetText("") end
    local savedWidth = tonumber(Raider.Database.GetSetting("masterLootWindowWidth"))
    if savedWidth then panel:SetWidth(math.max(360, math.min(600, savedWidth))) end
    Refresh()
end

Announce = function(message, prefix)
    local ok = RaidService.SendRaidWarning(message, prefix)
    if not ok and RaidService.IsInRaid() and type(SendChatMessage)=="function" then
        -- A master looter is not necessarily a leader or assistant.
        ok=pcall(SendChatMessage,prefix == false and message or RaidService.PrefixLootMasterMessage(message),"RAID")
    end
    return ok and true or false
end
AnnounceMessage = function(key, values) return Raider.Services.LootMessages.Send(key, values, Announce) end

local timer = Raider.UI.Components.CreateContainer(nil, UIParent)
timer:Hide()
events = Raider.UI.Components.CreateContainer(nil, UIParent)
reyCoinEvents = Raider.Modules.MasterLootEvents.Create(RaidService, function(key, values) AnnounceMessage(key, values) end)
local previousPendingChanged = RaidService.onReyCoinPendingChanged
RaidService.onReyCoinPendingChanged = function()
    if previousPendingChanged then previousPendingChanged() end
    retention.Prune()
end
local previousExpiryChanged = RaidService.onPendingLootExpiryChanged
RaidService.onPendingLootExpiryChanged = function()
    if previousExpiryChanged then previousExpiryChanged() end
    retention.Prune()
end
RaidService.onReyCoinTradeConfirmed = function(sender, recipient, link, historyKey)
    local history = historyKey and completedRolls[historyKey]
    if history and history.link == link then
        history.tradedTo = recipient
        table.insert(history.lines, sender .. " traded " .. link .. " to " .. recipient .. ".")
    end
    if lastRoll and lastRoll.historyKey == historyKey and lastRoll.link == link then lastRoll.tradedTo = recipient end
    retention.Prune()
    if panel:IsShown() then Refresh() end
end

tracker = Raider.UI.Components.CreateContainer("BootyRaiderRollTracker", UIParent)
tracker:SetWidth(300); tracker:SetHeight(168)
tracker:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 130)
tracker:EnableMouse(true); tracker:Hide()
if Stack then Stack.Register(tracker, {owner = RaidWindowOwner}) end
tracker:SetMovable(true); tracker:SetResizable(true)
tracker:SetMinResize(280, 168); tracker:SetMaxResize(500, 340)
tracker:RegisterForDrag("LeftButton")
tracker:SetScript("OnDragStart", function() this:StartMoving() end)
tracker:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
tracker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
tracker:SetBackdropColor(0.02, 0.02, 0.02, 0.96); tracker:SetBackdropBorderColor(0.68, 0.54, 0.27, 1)
local trackerTitle = Raider.UI.Components.CreateLabel(tracker, nil, "OVERLAY", "GameFontNormalSmall")
trackerTitle:SetPoint("TOPLEFT", tracker, "TOPLEFT", 12, -12); trackerTitle:SetWidth(240); trackerTitle:SetJustifyH("LEFT")
trackerTitle:SetText("Ongoing rolls"); trackerTitle:SetTextColor(1, 0.82, 0.28)
local trackerItemIcon = Raider.UI.Components.CreateTexture(tracker, nil, "ARTWORK")
trackerItemIcon:SetWidth(17); trackerItemIcon:SetHeight(17)
trackerItemIcon:SetPoint("TOPLEFT", tracker, "TOPLEFT", 12, -34)
local trackerItem = Raider.UI.Components.CreateControl(nil, tracker)
trackerItem:SetHeight(18); trackerItem:SetWidth(1)
trackerItem:SetPoint("LEFT", trackerItemIcon, "RIGHT", 6, 0)
trackerItem:RegisterForClicks("LeftButtonUp", "RightButtonUp")
trackerItem.text = Raider.UI.Components.CreateLabel(trackerItem, nil, "OVERLAY", "GameFontHighlightSmall")
trackerItem.text:SetAllPoints(trackerItem); trackerItem.text:SetJustifyH("LEFT")
trackerItem:SetScript("OnEnter", function()
    local roll = activeRoll or lastRoll
    if roll then ShowItemTooltip(this, nil, roll.link) end
end)
trackerItem:SetScript("OnLeave", function() GameTooltip:Hide() end)
trackerItem:SetScript("OnClick", function()
    local roll = activeRoll or lastRoll
    if not roll then return end
    if arg1 == "LeftButton" and IsShiftKeyDown() then
        if ChatFrame_OpenChat and ChatFrameEditBox and not ChatFrameEditBox:IsShown() then ChatFrame_OpenChat("") end
        if ChatFrameEditBox then ChatFrameEditBox:SetFocus(); ChatFrameEditBox:Insert(roll.link) end
    elseif arg1 == "LeftButton" and IsControlKeyDown() then
        if DressUpItemLink then DressUpItemLink(roll.link) end
    else ShowItemTooltip(this, nil, roll.link) end
end)
local trackerStatus = Raider.UI.Components.CreateLabel(tracker, nil, "OVERLAY", "GameFontHighlightSmall")
trackerStatus:SetPoint("TOPLEFT", tracker, "TOPLEFT", 12, -59); trackerStatus:SetWidth(276); trackerStatus:SetJustifyH("LEFT")
local trackerClose = Raider.UI.Components.CreateWindowButton(tracker, nil, "close")
trackerClose:SetPoint("RIGHT", tracker, "TOPRIGHT", -8, -17)
trackerClose:SetScript("OnClick", function() tracker:Hide() end)


local trackerGrip = Raider.UI.Components.CreateControl(nil, tracker)
trackerGrip:SetWidth(12); trackerGrip:SetHeight(12)
trackerGrip:SetPoint("BOTTOMRIGHT", tracker, "BOTTOMRIGHT", 0, 0)
trackerGrip.texture = Raider.UI.Components.CreateTexture(trackerGrip, nil, "OVERLAY")
trackerGrip.texture:SetAllPoints(trackerGrip)
trackerGrip.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
Raider.UI.Components.RegisterSkinCallback(function(skin)
    if skin == "classic" then
        trackerGrip.texture:SetTexture(Raider.UI.Components.ClassicAsset("Icons\\resize.tga"))
        trackerGrip.texture:SetVertexColor(1, 0.78, 0.24)
        trackerGrip.texture:ClearAllPoints()
        trackerGrip.texture:SetPoint("CENTER", trackerGrip, "CENTER", 0, 0)
        trackerGrip.texture:SetWidth(9); trackerGrip.texture:SetHeight(9)
    else
        trackerGrip.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        trackerGrip.texture:SetVertexColor(1, 1, 1)
        trackerGrip.texture:ClearAllPoints(); trackerGrip.texture:SetAllPoints(trackerGrip)
    end
end)
trackerGrip:SetScript("OnMouseDown", function()
    local left, top = tracker:GetLeft(), tracker:GetTop()
    tracker:ClearAllPoints()
    tracker:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    tracker:StartSizing("BOTTOMRIGHT")
end)
trackerGrip:SetScript("OnMouseUp", function() tracker:StopMovingOrSizing(); tracker.userSized = true end)
trackerGrip:SetScript("OnHide", function() tracker:StopMovingOrSizing() end)
local trackerFinish = Raider.UI.Components.CreateButton(tracker, nil, "Finish", 80, 20)
trackerFinish:SetPoint("BOTTOMRIGHT", tracker, "BOTTOMRIGHT", -13, 15)
trackerFinish:SetScript("OnClick", function() if activeRoll then FinishRoll() end end)
local trackerExtend = Raider.UI.Components.CreateButton(tracker, nil, "Extend", 80, 20)
trackerExtend:SetPoint("RIGHT", trackerFinish, "LEFT", -6, 0)
trackerExtend:SetScript("OnClick", ExtendRoll)
local trackerRows = {}
local trackerFirst = 1
local trackerIndex
for trackerIndex = 1, MAX_LIVE_ROWS do
    local row = Raider.UI.Components.CreateContainer(nil, tracker)
    row:SetPoint("TOPLEFT", tracker, "TOPLEFT", 12, -78 - (trackerIndex - 1) * 23)
    row:SetWidth(276); row:SetHeight(21)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
    row:SetBackdropBorderColor(1, 0.78, 0.2, 1)
    row.text = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 5, 0); row.text:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    row.text:SetJustifyH("LEFT")
    trackerRows[trackerIndex] = row
end
tracker:SetScript("OnSizeChanged", function()
    trackerTitle:SetWidth(this:GetWidth() - 60)
    trackerStatus:SetWidth(this:GetWidth() - 24)
    local i
    for i = 1, MAX_LIVE_ROWS do trackerRows[i]:SetWidth(this:GetWidth() - 24) end
end)
RefreshTracker = function()
    if not tracker:IsShown() then return end
    local roll = activeRoll or lastRoll
    if not roll then tracker:Hide(); return end
    trackerItemIcon:SetTexture(roll.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    trackerItem.text:SetText(roll.link)
    trackerItem:SetWidth(math.max(1, math.min(tracker:GetWidth() - 62, trackerItem.text:GetStringWidth() + 2)))
    trackerStatus:SetText(activeRoll and ("Current roll - Remaining time: " .. math.max(0, roll.lastRemaining or DEFAULT_ROLL_SECONDS) .. "s.") or "Current roll")
    if activeRoll then
        trackerStatus:SetTextColor(1, 0.82, 0.28)
        trackerFinish:Show(); trackerExtend:Show()
    else
        trackerStatus:SetTextColor(1, 0.82, 0.28)
        trackerFinish:Hide(); trackerExtend:Hide()
    end
    local count = roll.results and table.getn(roll.results) or 0
    local neededHeight = 145 + math.max(1, math.min(MAX_LIVE_ROWS, count)) * 23
    tracker:SetMinResize(280, neededHeight)
    if not tracker.userSized then tracker:SetHeight(neededHeight)
    elseif tracker:GetHeight() < neededHeight then tracker:SetHeight(neededHeight) end
    trackerFirst = math.min(trackerFirst, math.max(1, count - MAX_LIVE_ROWS + 1))
    local index
    for index = 1, MAX_LIVE_ROWS do
        local line
        local result = roll.results and roll.results[trackerFirst + index - 1]
        if result then line = ColoredName(result.name) .. " - " .. result.value .. (result.valid == false and " - Invalid" or "") end
        if index == 1 and not line then line = "Waiting for rolls..." end
        if line then trackerRows[index].text:SetText(line); trackerRows[index]:Show()
        else trackerRows[index]:Hide() end
    end
end
tracker:EnableMouseWheel(true)
tracker:SetScript("OnMouseWheel", function()
    local roll = activeRoll or lastRoll
    if not roll then return end
    local count = table.getn(roll.results)
    trackerFirst = math.max(1, math.min(math.max(1, count - MAX_LIVE_ROWS + 1), trackerFirst - arg1))
    RefreshTracker()
end)

FinishRoll = function()
    local roll = activeRoll
    if not roll then return end
    RaidService.FinalizeLootRoll(roll)
    MasterLootWindow.ResolveTies(roll)
    if roll.winnerResult then
        local winnerIndex
        local index
        for index = 1, table.getn(roll.results) do
            if roll.results[index] == roll.winnerResult then winnerIndex = index; break end
        end
        if winnerIndex and winnerIndex > 1 then
            local result = roll.results[winnerIndex]
            while winnerIndex > 1 do
                roll.results[winnerIndex] = roll.results[winnerIndex - 1]
                winnerIndex = winnerIndex - 1
            end
            roll.results[1] = result
        end
        firstLiveResult = 1
    end
    activeRoll = nil; lastRoll = roll
    lastRollBySource[roll.source] = roll
    local history, historyKey = retention.GetHistory(roll.source, roll.historyKey, roll.link, roll.icon, roll.manual)
    roll.historyKey = historyKey
    history.rounds = history.rounds + 1
    history.latestWinner = not Raider.Services.LootRollRequest.HasBlockingTie(roll,roll.tieGroups) and roll.winner or nil
    local lines = history.lines
    roll.summaryIndex = table.getn(lines) + 1
    table.insert(lines, "Round " .. history.rounds .. ": " ..
        (roll.winner and (roll.winner .. (roll.winnerResult and roll.winnerResult.automatic
            and " (automatic SR)" or (" (" .. roll.highest .. "/" .. (roll.winnerResult and roll.winnerResult.range or 100) .. ")")))
            or (table.getn(roll.results) > 0 and "No valid rolls" or "No rolls")))
    if Raider.Services.LootRollRequest.HasBlockingTie(roll,roll.tieGroups) then
        local parts={}
        for _,group in ipairs(roll.tieGroups) do if group.affectsWinner then table.insert(parts,"Tie "..Raider.Services.LootRollRequest.CategoryNames[group.range]..": "..table.concat(group.names,", ")) end end
        lines[roll.summaryIndex]="Round "..history.rounds..": "..table.concat(parts,"; ")
    end
    local index
    for index = 1, table.getn(roll.results) do
        local result = roll.results[index]
        table.insert(lines, "    " .. result.name .. (result.automatic and " - automatic SR"
            or (" - " .. result.value .. "/" .. (result.range or 100) .. (result.valid == false and " - Invalid (" .. result.invalidReason .. ")" or ""))))
    end
    timer:SetScript("OnUpdate", nil); timer:Hide()
    -- Loot-window rolls keep listening while the item is unawarded. A linked
    -- item has no Master Loot award event, so its listener ends with the timer.
    if roll.manual then events:UnregisterEvent("CHAT_MSG_SYSTEM") end
    if Raider.Services.LootRollRequest.HasBlockingTie(roll,roll.tieGroups) then
        AnnounceMessage("Tie", {item=roll.link})
    elseif roll.tradeWinner then
        AnnounceMessage("TradeWinner", {player=roll.winner, item=roll.link, value=roll.highest, recipient=roll.tradeWinner})
    elseif roll.winnerResult and roll.winnerResult.automatic then
        AnnounceMessage("SRWinner", {player=roll.winner, item=roll.link})
    elseif roll.winner then
        AnnounceMessage("Winner", {player=roll.winner, item=roll.link, value=roll.highest, roll=roll.winnerResult and rollTypeNames[roll.winnerResult.range] or "roll"})
    else
        AnnounceMessage(table.getn(roll.results) > 0 and "NoValidRolls" or "NoRolls", {item=roll.link})
    end
    if currentLootSession == roll.source then status:SetText("") end
    retention.Prune()
    if panel:IsShown() then Refresh() end
    tracker:Hide()
end

CancelRoll = function()
    local roll = activeRoll
    if not roll then return end
    activeRoll = nil
    lastRollBySource[roll.source] = nil
    timer:SetScript("OnUpdate", nil); timer:Hide()
    events:UnregisterEvent("CHAT_MSG_SYSTEM")
    AnnounceMessage("Stopped", {item=roll.link})
    if currentLootSession == roll.source then status:SetText("Roll stopped; all rolls are invalidated") end
    retention.Prune()
    if panel:IsShown() then Refresh() end
    tracker:Hide()
end

local function OnTimerUpdate()
    local roll = activeRoll
    if not roll then
        if raidRollPending and GetTime() >= raidRollPending.endsAt then
            raidRollPending = nil
            events:UnregisterEvent("CHAT_MSG_SYSTEM")
            timer:SetScript("OnUpdate", nil); timer:Hide()
            status:SetText("Raid roll result was not received; try again")
            retention.Prune()
            if panel:IsShown() then Refresh() end
        end
        return
    end
    local remaining = math.ceil(roll.endsAt - GetTime())
    if remaining <= 0 then FinishRoll(); return end
    if remaining ~= roll.lastRemaining then
        roll.lastRemaining = remaining
        if currentLootSession == roll.source then status:SetText("Rolling for " .. roll.link .. " - " .. remaining .. "s") end
        if panel:IsShown() and currentLootSession == roll.source then RefreshResults() end
        if remaining <= 3 then AnnounceMessage("Countdown", {seconds=remaining}) end
        RefreshTracker()
    end
end

local function StartRoll(slot, link, request)
    if activeRoll then status:SetText("A roll is already in progress"); return false end
    if raidRollPending then status:SetText("Wait for the raid roll result"); return false end
    local manual = not slot
    if not link or (manual and not Raider.Services.LootRollRequest.CanOrganize()) or (not manual and not RaidService.IsPlayerLootMaster()) then return false end
    if not manual and (not LootSlotIsItem(slot) or GetLootSlotLink(slot) ~= link) then return false end
    retention.EnsureSource()
    local seconds = GetGlobalRollDuration()
    local count = math.min(40, math.max(0, tonumber(GetNumRaidMembers()) or 0))
    local index
    for index in pairs(eligible) do eligible[index] = nil end
    for index = 1, count do
        local name = GetRaidRosterInfo(index)
        if name then eligible[name] = true end
    end
    local allowedNames
    if request and request.names then
        allowedNames={}
        for index=1,table.getn(request.names) do allowedNames[string.lower(request.names[index])]=true end
        for name in pairs(eligible) do if not allowedNames[string.lower(name)] then eligible[name]=nil end end
    end
    firstLiveResult = 1
    local _, historyKey = FindHistoryForItem(currentLootSession, slot, link)
    local icon
    if slot then icon = GetLootSlotInfo(slot)
    else
        local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(link)
        icon = itemTexture
    end
    local srRestricted, srReserved, srAllowed, srNames, srRankRights, srRankNames, reyCoinRights, reyCoinUsed = RaidService.GetSoftReserveRollRights(link)
    activeRoll = { slot = slot, link = link, icon = icon, source = currentLootSession,
        lootSessionToken = RaidService.GetLootSessionToken(),
        historyKey = historyKey or retention.ResolveHistoryKey(currentLootSession .. ":" .. tostring(slot or "manual"), link), manual = manual,
        duration = seconds, endsAt = GetTime() + seconds, lastRemaining = seconds, seen = {}, results = {}, highest = -1, highestPriority = -1, transmogHighest = -1, srRestricted = srRestricted, srReserved = srReserved, srAllowed = srAllowed, srNames = srNames, srRankRights = srRankRights, srRankNames = srRankNames, reyCoinRights = reyCoinRights, reyCoinUsed = reyCoinUsed }
    activeRoll.allowedTypes=request and request.types
    activeRoll.allowedNames=allowedNames
    if allowedNames then
        local filtered={}
        for name,value in pairs(srAllowed or {}) do if allowedNames[name] then filtered[name]=value end end
        activeRoll.srAllowed=filtered
    end
    for _,result in ipairs(request and request.carryResults or {}) do
        table.insert(activeRoll.results,result);activeRoll.seen[result.name..":"..result.range]=result
    end
    if request and request.reroll then
        -- The exact reroll announcement was sent after all validation.
    elseif request then
        local choices={}
        for _,range in ipairs({102,101,100,99,98}) do if request.types[range] then table.insert(choices,Raider.Services.LootRollRequest.CategoryNames[range].." ("..range..")") end end
        local sent=AnnounceMessage(request.names and "PlayerRoll" or "ItemRoll", {item=link, rolls=table.concat(choices,", "), seconds=seconds,
            players=request.names and table.concat(request.names,", ") or "", playerNames=request.names})
        if not sent then
            activeRoll=nil;timer:SetScript("OnUpdate",nil);timer:Hide();events:UnregisterEvent("CHAT_MSG_SYSTEM")
            status:SetText("The roll announcement could not be sent.")
            Refresh();return false,"The roll announcement could not be sent."
        end
    elseif srRestricted then
        AnnounceMessage("SRPlayers", {item=link, players=table.concat(srNames, ", "), playerNames=srNames})
        AnnounceMessage("ItemRoll", {item=link, rolls="SR (102)", seconds=seconds})
    else
        AnnounceMessage("ItemRoll", {item=link, rolls="RC (101), MS (100), OS (99), Tmog (98)", seconds=seconds})
    end
    events:RegisterEvent("CHAT_MSG_SYSTEM")
    timer:SetScript("OnUpdate", OnTimerUpdate)
    timer:Show()
    status:SetText("Rolling for " .. link .. " - " .. seconds .. "s")
    Refresh()
    return true
end

function MasterLootWindow.Reroll(roll,range)
    if activeRoll or raidRollPending or not roll or roll.source~=currentLootSession
        or (roll.manual and not Raider.Services.LootRollRequest.CanOrganize()) or (not roll.manual and not RaidService.IsPlayerLootMaster())
        or lastRollBySource[currentLootSession]~=roll or not RaidService.IsLootSessionCurrent(roll.lootSessionToken) then return false end
    local request,failure=Raider.Services.LootRollRequest.CreateRerollRequest(roll,range)
    if not request then status:SetText(failure);return false end
    if roll.slot and (not LootSlotIsItem(roll.slot) or GetLootSlotLink(roll.slot)~=roll.link) then return false end
    local messages,errorMessage=Raider.Services.LootRollRequest.BuildRerollWarnings(request.names,roll.link)
    if not messages then status:SetText(errorMessage);return false end
    for _,message in ipairs(messages) do
        local sent,failure=RaidService.SendRaidWarning(message,false)
        if not sent then status:SetText(failure or "Cannot send a raid warning.");return false end
    end
    return StartRoll(roll.slot,roll.link,request)
end

local function ResolveRaidRoll(value)
    local pending = raidRollPending
    if not pending then return end
    raidRollPending = nil
    events:UnregisterEvent("CHAT_MSG_SYSTEM")
    timer:SetScript("OnUpdate", nil); timer:Hide()
    local name = pending.players[value]
    if not name then status:SetText("Raid roll returned an invalid roster position"); Refresh(); return end
    local candidate, _, unavailableReason = CanGive(pending, name)
    AnnounceMessage(candidate and "RaidWinner" or "RaidUnavailable", {value=value, count=pending.count, player=name, item=pending.link})
    local history, historyKey = retention.GetHistory(pending.source, pending.historyKey, pending.link, pending.icon)
    pending.historyKey = historyKey
    history.rounds = history.rounds + 1
    history.latestWinner = name
    table.insert(history.lines, "Raid roll " .. value .. "/" .. pending.count .. ": " .. name)
    lastRoll = { source = pending.source, link = pending.link, icon = pending.icon, historyKey = pending.historyKey,
        lootSessionToken = pending.lootSessionToken,
        results = { { name = name, value = value } }, winner = name, highest = value,
        raidRoll = true, raidCount = pending.count, awardable = candidate and true or false }
    lastRollBySource[pending.source] = lastRoll
    retention.Prune()
    status:SetText(candidate and name or (name .. ": " .. (unavailableReason or "unavailable")))
    if panel:IsShown() then Refresh() end
end

local function StartRaidRoll(slot, link)
    if activeRoll or raidRollPending then status:SetText("Another roll is in progress"); return end
    if not slot or not link or not RaidService.IsPlayerLootMaster() then return end
    if not LootSlotIsItem(slot) or GetLootSlotLink(slot) ~= link then return end
    retention.EnsureSource()
    local count = GetNumRaidMembers() or 0
    if count < 1 then status:SetText("No raid members to roll for"); return end
    if type(RandomRoll) ~= "function" then status:SetText("Raid roll is unavailable in this client"); return end
    local players = {}
    local index
    for index = 1, count do players[index] = GetRaidRosterInfo(index) end
    local _, historyKey = FindHistoryForItem(currentLootSession, slot, link)
    raidRollPending = { slot = slot, link = link, source = currentLootSession,
        lootSessionToken = RaidService.GetLootSessionToken(),
        historyKey = historyKey or retention.ResolveHistoryKey(currentLootSession .. ":" .. slot, link), icon = GetLootSlotInfo(slot),
        count = count, players = players, endsAt = GetTime() + 8 }
    events:RegisterEvent("CHAT_MSG_SYSTEM")
    timer:SetScript("OnUpdate", OnTimerUpdate); timer:Show()
    local ok = pcall(RandomRoll, 1, count)
    if not ok then
        raidRollPending = nil; events:UnregisterEvent("CHAT_MSG_SYSTEM")
        timer:SetScript("OnUpdate", nil); timer:Hide()
        status:SetText("Raid roll could not be started")
    elseif raidRollPending then status:SetText("Raid roll 1-" .. count .. " in progress") end
    Refresh()
end

local function RowClick(clickedRow)
    local row = clickedRow or this
    if not row.link then return end
    if arg1 == "RightButton" then if row.slot and not activeRoll and not raidRollPending then OpenCandidateMenu(row.slot, row.link) end; return end
    local history, key
    if row.historyKey then history = completedRolls[row.historyKey]; key = row.historyKey
    else history, key = FindHistoryForItem(currentLootSession, row.slot, row.link) end
    if history and table.getn(history.lines) > 0 then
        if expandedHistoryKey == key then expandedHistoryKey = nil else expandedHistoryKey = key end
        firstResult = 1; RefreshResults()
    end
end

local index
for index = 1, MAX_ROWS do
    local row = Raider.UI.Components.CreateControl(nil, scrollContent)
    row:SetHeight(ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -2 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, -2 - (index - 1) * ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.85); row:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.8)
    row.icon = Raider.UI.Components.CreateTexture(row, nil, "ARTWORK")
    row.icon:SetWidth(17); row.icon:SetHeight(17); row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0); row.name:SetPoint("RIGHT", row, "RIGHT", -150, 0)
    row.name:SetHeight(18)
    row.name:SetJustifyH("LEFT"); row.name:SetJustifyV("MIDDLE")
    row.nameHit = Raider.UI.Components.CreateControl(nil, row)
    row.nameHit:SetWidth(1); row.nameHit:SetHeight(18)
    row.nameHit:SetPoint("LEFT", row.name, "LEFT", 0, 0)
    row.nameHit:SetFrameLevel(row:GetFrameLevel() + 1)
    row.nameHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.nameHit:SetScript("OnEnter", function()
        local item = this:GetParent()
        if item.link then ShowItemTooltip(this, item.slot, item.link) end
    end)
    row.nameHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.nameHit:SetScript("OnClick", function()
        local item = this:GetParent()
        if not item.link then return end
        if arg1 == "LeftButton" and (IsShiftKeyDown() or IsControlKeyDown()) then
            if IsShiftKeyDown() then
                if ChatFrame_OpenChat and ChatFrameEditBox and not ChatFrameEditBox:IsShown() then ChatFrame_OpenChat("") end
                if ChatFrameEditBox then ChatFrameEditBox:SetFocus(); ChatFrameEditBox:Insert(item.link) end
            elseif DressUpItemLink then DressUpItemLink(item.link) end
            return
        end
        RowClick(item)
    end)
    row.historyIndicator = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontNormalSmall")
    row.historyIndicator:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.historyIndicator:SetWidth(10); row.historyIndicator:SetJustifyH("CENTER")
    row.raidButton = CreateRowActionButton(row, "RR", 24, 18)
    row.raidButton:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 2)
    row.rollButton = CreateRowActionButton(row, "", 20, 18)
    row.rollButton:SetPoint("RIGHT", row.raidButton, "LEFT", -4, 0)
    row.rollButton.icon = Raider.UI.Components.CreateTexture(row.rollButton, nil, "ARTWORK")
    row.rollButton.icon:SetWidth(13)
    row.rollButton.icon:SetHeight(13)
    row.rollButton.icon:SetPoint("CENTER", row.rollButton, "CENTER", 0, 0)
    row.rollButton.icon:SetTexture(ROLL_ICON_PATH)
    row.rollButton.icon:SetTexCoord(0.11, 0.89, 0.11, 0.89)
    row.rollButton.stopIcon = Raider.UI.Components.CreateLabel(row.rollButton, nil, "OVERLAY", "GameFontNormal")
    row.rollButton.stopIcon:SetPoint("CENTER", row.rollButton, "CENTER", 0, 0)
    row.rollButton.stopIcon:SetText("O")
    row.rollButton.stopIcon:SetTextColor(1, 0.12, 0.12)
    row.rollButton.stopSlash = Raider.UI.Components.CreateLabel(row.rollButton, nil, "OVERLAY", "GameFontNormal")
    row.rollButton.stopSlash:SetPoint("CENTER", row.rollButton, "CENTER", 0, 0)
    row.rollButton.stopSlash:SetText("/")
    row.rollButton.stopSlash:SetTextColor(1, 0.12, 0.12)
    row.rollButton.stopIcon:Hide()
    row.rollButton.stopSlash:Hide()
    row.winner = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontNormalSmall")
    row.winner:SetPoint("RIGHT", row.rollButton, "LEFT", -7, 1)
    row.winner:SetHeight(16)
    row.winner:SetWidth(112)
    row.winner:SetJustifyH("RIGHT"); row.winner:SetJustifyV("MIDDLE")
    row.rewardIcon = Raider.UI.Components.CreateTexture(row, nil, "OVERLAY")
    row.rewardIcon:SetTexture("Interface\\Icons\\INV_Box_01")
    row.rewardIcon:SetWidth(15); row.rewardIcon:SetHeight(15)
    row.rewardIcon:SetPoint("RIGHT", row.winner, "LEFT", -3, 0)
    row.rewardIcon:Hide()
    row.rollButton:SetScript("OnClick", function()
        local item = this:GetParent()
        if activeRoll then
            if activeRoll.slot == item.slot then CancelRoll() end
        else StartRoll(item.slot, item.link) end
    end)
    row.raidButton:SetScript("OnClick", function()
        local item = this:GetParent()
        StartRaidRoll(item.slot, item.link)
    end)
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", function()
        this:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    end)
    row:SetScript("OnLeave", function()
        this:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
        GameTooltip:Hide()
    end)
    row:Hide()
    rows[index] = row
end

for index = 1, MAX_RESULT_ROWS do
    local row = Raider.UI.Components.CreateControl(nil, scrollContent)
    row:SetHeight(21)
    row:SetWidth(scrollContent:GetWidth() - 6)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
    row.text = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 5, 0); row.text:SetPoint("RIGHT", row, "RIGHT", -5, 0); row.text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function()
        if not this.roundNumber or not expandedHistoryKey then return end
        local collapsed = collapsedRounds[expandedHistoryKey]
        if not collapsed then collapsed = {}; collapsedRounds[expandedHistoryKey] = collapsed end
        collapsed[this.roundNumber] = not collapsed[this.roundNumber]
        firstResult = 1; RefreshResults()
    end)
    row:SetScript("OnEnter", function()
        this:SetBackdropColor(0.16, 0.14, 0.08, 0.95)
    end)
    row:SetScript("OnLeave", function() this:SetBackdropColor(0.08, 0.08, 0.08, 0.8) end)
    row:Hide(); resultRows[index] = row
end

for index = 1, MAX_LIVE_ROWS do
    local row = Raider.UI.Components.CreateControl(nil, scrollContent)
    row:SetHeight(21); row:SetWidth(scrollContent:GetWidth() - 3)
    row:SetPoint("TOPLEFT", liveHeader, "BOTTOMLEFT", 0, -3 - (index - 1) * 23)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
    row:SetBackdropBorderColor(0, 0, 0, 0)
    row:SetScript("OnEnter", function()
        if this.roll and not activeRoll and not this.roll.awarded and this.result and this.result.valid ~= false then
            this:SetBackdropColor(0.16, 0.14, 0.08, 0.95)
        end
    end)
    row:SetScript("OnLeave", function() this:SetBackdropColor(0.08, 0.08, 0.08, 0.8) end)
    row:SetScript("OnClick", function()
        local roll, result = this.roll, this.result
        if not roll or activeRoll or roll.awarded or not result or result.valid == false then return end
        roll.manualWinnerResult = result
        RaidService.FinalizeLootRoll(roll)
        local history = completedRolls[roll.historyKey]
        if history and roll.summaryIndex then
            history.latestWinner = roll.winner
            history.lines[roll.summaryIndex] = "Round " .. history.rounds .. ": " .. roll.winner .. " (" .. roll.highest .. "/" .. result.range .. ")"
        end
        RefreshResults()
    end)
    row.text = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 5, 0); row.text:SetPoint("RIGHT", row, "RIGHT", -85, 0); row.text:SetJustifyH("LEFT")
    row.itemHit = Raider.UI.Components.CreateControl(nil, row)
    row.itemHit:SetHeight(19); row.itemHit:SetWidth(1)
    row.itemHit.text = Raider.UI.Components.CreateLabel(row.itemHit, nil, "OVERLAY", "GameFontHighlightSmall")
    row.itemHit.text:SetAllPoints(row.itemHit); row.itemHit.text:SetJustifyH("LEFT")
    row.itemHit:SetScript("OnEnter", function() Raider.UI.Components.ShowItemTooltip(this) end)
    row.itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.itemHit:SetScript("OnClick", function() Raider.UI.Components.HandleItemClick(this) end)
    row.itemHit:Hide()
    row.valueText = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
    row.valueText:Hide()
    row.giveButton = CreateRowActionButton(row, "Give loot", 78, 16)
    row.giveButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    row.giveButton:SetBackdropColor(0.14, 0.12, 0.08, 0.95)
    row.giveButton:SetBackdropBorderColor(0.38, 0.38, 0.38, 0.9)
    Raider.UI.Components.AttachGoldHoverBorder(row.giveButton, 0.38, 0.38, 0.38, 0.9)
    row.giveButton:SetPoint("RIGHT", row, "RIGHT", -5, -1)
    row.giveButton:SetScript("OnClick", function()
        local result = this:GetParent()
        if result.roll and result.playerName and not activeRoll then
            if result.result and result.result.valid ~= false then
                if result.roll.winnerResult~=result.result then result.roll.manualWinnerResult=result.result end
                RaidService.FinalizeLootRoll(result.roll)
            end
            ConfirmGive(result.roll, result.playerName)
        end
    end)
    row.rerollButton=Raider.UI.Components.CreateButton(row,nil,"Reroll",78,18)
    row.rerollButton:SetPoint("RIGHT",row,"RIGHT",-5,-1)
    row.rerollButton:SetScript("OnClick",function() local owner=this:GetParent();MasterLootWindow.Reroll(owner.roll,owner.rerollRange) end)
    row.rerollButton:Hide()
    row:Hide(); liveRows[index] = row
end

panel:SetScript("OnSizeChanged", function()
    UpdateScrollRange()
    local width = scrollContent:GetWidth()
    local i
    for i = 1, MAX_RESULT_ROWS do resultRows[i]:SetWidth(width - 6) end
    for i = 1, MAX_LIVE_ROWS do liveRows[i]:SetWidth(width - 3) end
end)

panel:EnableMouseWheel(true)
panel:SetScript("OnMouseWheel", function()
    if scrollBar:IsShown() and not IsShiftKeyDown() and not IsControlKeyDown() then
        scrollBar:SetValue(scrollBar:GetValue() - arg1 * 23)
        return
    end
    if IsShiftKeyDown() then
        local count = 0
        if expandedHistoryKey and completedRolls[expandedHistoryKey] then
            local history = completedRolls[expandedHistoryKey]
            local hidden = false
            local collapsed = collapsedRounds[expandedHistoryKey]
            local lineIndex
            for lineIndex = 1, table.getn(history.lines) do
                local round = tonumber(Match(history.lines[lineIndex], "^Round (%d+):"))
                if round then hidden = collapsed and collapsed[round]; count = count + 1
                elseif not hidden then count = count + 1 end
            end
        end
        firstResult = math.max(1, math.min(math.max(1, count - MAX_RESULT_ROWS + 1), firstResult - arg1))
        RefreshResults()
    elseif IsControlKeyDown() then
        local roll = activeRoll and activeRoll.source == currentLootSession and activeRoll or lastRollBySource[currentLootSession]
        local count = roll and table.getn(roll.results) or 0
        firstLiveResult = math.max(1, math.min(math.max(1, count - MAX_LIVE_ROWS + 1), firstLiveResult - arg1))
        RefreshResults()
    else
        local count = displayCount
        firstSlot = math.max(1, math.min(math.max(1, count - MAX_ROWS + 1), firstSlot - arg1))
        Refresh()
    end
end)

local historyDialog = Raider.UI.Components.CreateContainer("BootyRaiderRollHistory", UIParent)
historyDialog:SetWidth(340); historyDialog:SetHeight(90)
historyDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
historyDialog:EnableMouse(true); historyDialog:Hide()
if Stack then Stack.Register(historyDialog, {owner = RaidWindowOwner}) end
historyDialog:SetMovable(true); historyDialog:RegisterForDrag("LeftButton")
historyDialog:SetScript("OnDragStart", function() this:StartMoving() end)
historyDialog:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
historyDialog:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
historyDialog:SetBackdropColor(0.02, 0.02, 0.02, 0.98); historyDialog:SetBackdropBorderColor(0.68, 0.54, 0.27, 1)
local historyDialogTitle = Raider.UI.Components.CreateLabel(historyDialog, nil, "OVERLAY", "GameFontNormalSmall")
historyDialogTitle:SetPoint("TOPLEFT", historyDialog, "TOPLEFT", 14, -12)
historyDialogTitle:SetWidth(355); historyDialogTitle:SetJustifyH("LEFT")
local historyDialogItem = Raider.UI.Components.CreateControl(nil, historyDialog)
historyDialogItem:SetHeight(18); historyDialogItem:SetWidth(1)
historyDialogItem:SetFrameLevel(historyDialog:GetFrameLevel() + 1)
historyDialogItem:SetPoint("LEFT", historyDialogTitle, "RIGHT", 0, 0)
historyDialogItem.text = Raider.UI.Components.CreateLabel(historyDialogItem, nil, "OVERLAY", "GameFontNormalSmall")
historyDialogItem.text:SetAllPoints(historyDialogItem); historyDialogItem.text:SetJustifyH("LEFT")
historyDialogItem:SetScript("OnEnter", function() Raider.UI.Components.ShowItemTooltip(this) end)
historyDialogItem:SetScript("OnLeave", function() GameTooltip:Hide() end)
historyDialogItem:SetScript("OnClick", function() Raider.UI.Components.HandleItemClick(this) end)
local historyDialogClose = Raider.UI.Components.CreateWindowButton(historyDialog, nil, "close")
Raider.UI.Components.SetClassicButtonCompact(historyDialogClose, true)
Raider.UI.Components.AttachGoldHoverBorder(historyDialogClose, 0.35, 0.35, 0.35, 1)
historyDialogClose:SetPoint("TOPRIGHT", historyDialog, "TOPRIGHT", -8, -8)
historyDialogClose:SetScript("OnClick", function() historyDialog:Hide() end)
local historyDialogRows = {}
local RefreshHistoryDialog
local historyDialogIndex
for historyDialogIndex = 1, 10 do
    local row = Raider.UI.Components.CreateControl(nil, historyDialog)
    row:SetPoint("TOPLEFT", historyDialog, "TOPLEFT", 15, -34 - (historyDialogIndex - 1) * 22)
    row:SetWidth(400); row:SetHeight(21)
    row.label = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetAllPoints(row); row.label:SetJustifyH("LEFT")
    row:SetScript("OnClick", function()
        if not this.round then return end
        historyDialog.collapsed[this.round] = not historyDialog.collapsed[this.round]
        RefreshHistoryDialog()
    end)
    historyDialogRows[historyDialogIndex] = row
end
historyDialog.visibleLines = {}
historyDialog.visibleRounds = {}
historyDialog.collapsed = {}
retention.releaseHistoryView = function(lines)
    if lines and historyDialog.lines ~= lines then return end
    historyDialog.lines = nil; historyDialog:Hide()
    retention.ClearSequence(historyDialog.visibleLines); retention.ClearMap(historyDialog.visibleRounds)
    retention.ClearMap(historyDialog.collapsed); historyDialog.visibleCount = 0
end
RefreshHistoryDialog = function()
    local lines = historyDialog.lines
    local count = lines and table.getn(lines) or 0
    local visibleLines, visibleRounds = historyDialog.visibleLines, historyDialog.visibleRounds
    local visibleCount, hidden = 0, false
    local previousVisibleCount = historyDialog.visibleCount or 0
    local index
    for index = 1, count do
        local line = lines[index]
        local round = tonumber(Match(line, "^Round (%d+):"))
        if round then
            local nextLine = lines[index + 1]
            local hasDetails = nextLine and Match(nextLine, "^%s+")
            hidden = hasDetails and historyDialog.collapsed[round] or false
            visibleCount = visibleCount + 1
            local visibleLine = (hasDetails and (hidden and "> " or "v ") or "") .. line
            if visibleLines[visibleCount] then visibleLines[visibleCount] = visibleLine else table.insert(visibleLines, visibleLine) end
            visibleRounds[visibleCount] = hasDetails and round or nil
        elseif not hidden then
            visibleCount = visibleCount + 1
            if visibleLines[visibleCount] then visibleLines[visibleCount] = line else table.insert(visibleLines, line) end
            visibleRounds[visibleCount] = nil
        end
    end
    for index = previousVisibleCount, visibleCount + 1, -1 do table.remove(visibleLines, index); visibleRounds[index] = nil end
    historyDialog.visibleCount = visibleCount
    historyDialog.offset = math.max(1, math.min(historyDialog.offset or 1, math.max(1, visibleCount - 9)))
    local widestLine = historyDialogTitle:GetStringWidth() + historyDialogItem:GetWidth() + 60
    for index = 1, 10 do
        local visibleIndex = historyDialog.offset + index - 1
        local text = visibleIndex <= visibleCount and visibleLines[visibleIndex] or nil
        if count == 0 and index == 1 then text = "No rolls" end
        local row = historyDialogRows[index]
        row.round = visibleIndex <= visibleCount and visibleRounds[visibleIndex] or nil
        row.label:SetText(ColoredHistoryLine(text or ""))
        if text then widestLine = math.max(widestLine, row.label:GetStringWidth() + 38) end
        if row.round then row:EnableMouse(true) else row:EnableMouse(false) end
    end
    historyDialog:SetWidth(math.max(300, math.min(430, widestLine)))
    historyDialog:SetHeight(math.max(74, math.min(260, 46 + math.min(10, math.max(1, visibleCount)) * 22)))
    for index = 1, 10 do historyDialogRows[index]:SetWidth(historyDialog:GetWidth() - 30) end
end
retention.refreshHistoryView = function(lines)
    if historyDialog.lines == lines then RefreshHistoryDialog() end
end
historyDialog:EnableMouseWheel(true)
historyDialog:SetScript("OnMouseWheel", function()
    local count = this.visibleCount or 0
    this.offset = math.max(1, math.min(math.max(1, count - 9), (this.offset or 1) - arg1))
    RefreshHistoryDialog()
end)
function MasterLootWindow.ShowHistory(itemLink, lines, itemId, itemName)
    historyDialog.lines = lines
    historyDialog.offset = 1
    local round
    for round in pairs(historyDialog.collapsed) do historyDialog.collapsed[round] = nil end
    UpdateClassColors()
    local link = itemLink
    if not link or not string.find(link, "|Hitem:", 1, true) then
        local _, resolvedLink = GetItemInfo(itemId or itemLink)
        link = resolvedLink
        if not link and itemName and itemName ~= "" then
            local rawItem = itemLink and Match(itemLink, "(item:[^|%s]+)") or nil
            if not rawItem and itemId then rawItem = "item:" .. tostring(itemId) end
            link = rawItem and ("|cffffffff|H" .. rawItem .. "|h[" .. itemName .. "]|h|r") or itemName
        end
        link = link or itemName or (itemId and ("Item " .. tostring(itemId))) or "Item"
        if type(link) == "string" and Match(link, "^item:%d+") then
            local readableName = itemName and not Match(itemName, "^item:") and itemName or (itemId and ("Item " .. tostring(itemId))) or "Item"
            link = "|cffffffff|H" .. link .. "|h[" .. readableName .. "]|h|r"
        end
    end
    historyDialogTitle:SetText("Roll history: ")
    historyDialogTitle:SetWidth(historyDialogTitle:GetStringWidth() + 2)
    historyDialogItem.itemId = tonumber(itemId) or tonumber(Match(tostring(link), "item:(%d+)"))
    historyDialogItem.itemName = itemName
    historyDialogItem.text:SetText(tostring(link or "Item"))
    historyDialogItem:SetWidth(historyDialogItem.text:GetStringWidth() + 2)
    RefreshHistoryDialog()
    historyDialog:Show()
end

function MasterLootWindow.Open()
    if Raider.active==false then return false,"BootyRaider is stopped." end
    RaidService.GetLootSessionToken()
    local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
    shiftAtLootOpen = shift == true or shift == 1
    panel.manualSession = nil; manualRollLink = nil
    autoLootPendingSlot = nil; autoLootTimeout:Hide()
    local failedSlot
    for failedSlot in pairs(autoLootFailedSlots) do autoLootFailedSlots[failedSlot] = nil end
    firstSlot = 1; firstResult = 1; firstLiveResult = 1; expandedHistoryKey = nil
    tracker:Hide(); candidateMenu:Hide(); restorePicker:Hide()
    local sourceGuid
    local lootCount = GetNumLootItems() or 0
    if type(GetLootSourceInfo) == "function" then
        local slot
        for slot = 1, lootCount do
            if LootSlotIsItem(slot) then
                local ok, guid = pcall(GetLootSourceInfo, slot)
                if ok and type(guid) == "string" and guid ~= "" then sourceGuid = guid end
                break
            end
        end
    end
    currentSessionHasGuid = sourceGuid and true or false
    if sourceGuid then currentLootSession = "corpse:" .. sourceGuid
    else
        lootSessionNumber = lootSessionNumber + 1
        currentLootSession = "session:" .. lootSessionNumber
    end
    retention.RememberSource(currentLootSession)
    retention.Prune()
    if activeRoll and activeRoll.source ~= currentLootSession then tracker:Show(); RefreshTracker() end
    if activeRoll and activeRoll.source == currentLootSession then
        status:SetText("Rolling for " .. activeRoll.link .. " - " .. (activeRoll.lastRemaining or DEFAULT_ROLL_SECONDS) .. "s")
    else status:SetText("") end
    local activeSlotLink = activeRoll and activeRoll.slot and GetLootSlotLink(activeRoll.slot) or nil
    if MasterLootWindow.NeedsLootSlotRebind(activeRoll, currentLootSession, activeSlotLink) then
        local slot
        for slot = 1, lootCount do
            if LootSlotIsItem(slot) and GetLootSlotLink(slot) == activeRoll.link then
                activeRoll.slot = slot; break
            end
        end
    end
    UpdateClassColors()
    Refresh()
    UpdateRestoreCandidates()
    events:RegisterEvent("LOOT_CLOSED"); events:RegisterEvent("LOOT_SLOT_CLEARED"); events:RegisterEvent("RAID_ROSTER_UPDATE"); events:RegisterEvent("UI_ERROR_MESSAGE")
    panel:Show()
    local slot
    for slot = lootCount, 1, -1 do
        if LootSlotIsCoin(slot) then LootSlot(slot) end
    end
    AutoLootNext()
end

function MasterLootWindow.StartManualRoll(request)
    if Raider.active==false then return false,"BootyRaider is stopped." end
    local normalized,failure=Raider.Services.LootRollRequest.Normalize(request)
    if not normalized then return false,failure end
    local link=normalized.link
    if not RaidService.IsInRaid() then
        return false,"You must be in a raid."
    end
    if not Raider.Services.LootRollRequest.CanOrganize() then
        return false,"Only the Loot Master, raid leader or an assistant can start a roll."
    end
    if activeRoll or raidRollPending then
        return false,"Another roll is already in progress."
    end
    RaidService.GetLootSessionToken()
    lootSessionNumber = lootSessionNumber + 1
    currentLootSession = "manual:" .. lootSessionNumber
    currentSessionHasGuid = false
    manualRollLink = link
    panel.manualSession = true
    firstSlot = 1; firstResult = 1; firstLiveResult = 1; expandedHistoryKey = nil
    retention.RememberSource(currentLootSession)
    retention.Prune()
    UpdateClassColors()
    panel:Show()
    Refresh()
    return StartRoll(nil, link,normalized)
end

function MasterLootWindow.OpenLinkedItemRoll(itemReference)
    local request,failure=Raider.Services.LootRollRequest.ParseManualRollRequest(itemReference)
    local ok=false
    if request then ok,failure=MasterLootWindow.StartManualRoll(request) end
    if not ok and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Raider: "..tostring(failure or "Could not start the roll.")) end
    return ok,failure
end

function MasterLootWindow.OpenNewRollDialog()
    if not MasterLootWindow.CanStartManualRoll() then
        local message = Raider.Services.LootRollRequest.CanOrganize() and "Another roll is already in progress."
            or "Only the Loot Master, raid leader or an assistant can start a roll."
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Raider: " .. message) end
        return false, message
    end
    if not MasterLootWindow.newRollDialog then MasterLootWindow.newRollDialog=Raider.Modules.LootRollDialog.Create({start=MasterLootWindow.StartManualRoll}) end
    MasterLootWindow.newRollDialog:Open()
    return true
end

function MasterLootWindow.CanStartManualRoll()
    return Raider.active~=false and Raider.Services.LootRollRequest.CanOrganize() and not activeRoll and not raidRollPending
end

function MasterLootWindow.ApplyAutoLootSetting()
    if not panel:IsShown() then return end
    Refresh()
    AutoLootNext()
end

autoLootTimeout:SetScript("OnUpdate", function()
    this.remaining = this.remaining - arg1
    if this.remaining > 0 then return end
    this:Hide()
    if not autoLootPendingSlot then return end
    autoLootFailedSlots[autoLootPendingSlot] = true
    autoLootPendingSlot = nil
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Raider: Automatic loot did not complete; item remains available for manual handling.") end
    Refresh()
    AutoLootNext()
end)

events:SetScript("OnEvent", function()
    if event == "LOOT_CLOSED" then
        shiftAtLootOpen = false
        autoLootPendingSlot = nil; autoLootTimeout:Hide()
        panel:Hide(); candidateMenu:Hide(); restorePicker:Hide()
        events:UnregisterEvent("LOOT_CLOSED"); events:UnregisterEvent("RAID_ROSTER_UPDATE"); events:UnregisterEvent("UI_ERROR_MESSAGE")
        if not pendingAward then events:UnregisterEvent("LOOT_SLOT_CLEARED") end
        if activeRoll then tracker:Show(); RefreshTracker() end
        retention.Prune()
    elseif event == "LOOT_SLOT_CLEARED" then
        if autoLootPendingSlot and tonumber(arg1) == autoLootPendingSlot then autoLootPendingSlot = nil; autoLootTimeout:Hide() end
        local failedSlot
        for failedSlot in pairs(autoLootFailedSlots) do autoLootFailedSlots[failedSlot] = nil end
        if pendingAward and tonumber(arg1) == pendingAward.slot and currentLootSession == pendingAward.source then
            local history, historyKey = retention.GetHistory(pendingAward.source, pendingAward.historyKey, pendingAward.link, pendingAward.icon)
            pendingAward.historyKey = historyKey
            history.awarded = true
            local awardedRoll = lastRollBySource[currentLootSession]
            if awardedRoll and awardedRoll.historyKey == pendingAward.historyKey then awardedRoll.awarded = true end
            history.latestWinner = pendingAward.winner
            local previous = lastRollBySource[currentLootSession]
            if previous and previous.historyKey == pendingAward.historyKey then
                lastRollBySource[currentLootSession] = nil
            end
            if completedRolls[pendingAward.historyKey] then completedRolls[pendingAward.historyKey].awarded = true end
            if RaidService.IsLootSessionCurrent(pendingAward.lootSessionToken) then
                RaidService.RecordPendingAwardReceipt(pendingAward.winner, pendingAward.link)
                if pendingAward.softReserve then RaidService.ConfirmSoftReserveReceipt(pendingAward.winner, pendingAward.link, pendingAward.lootSessionToken) end
                RaidService.ConfirmSoftReserveCarrierReceipt(pendingAward.winner, pendingAward.link)
                reyCoinEvents.ConfirmAwardReceipt(pendingAward.winner, pendingAward.link)
            end
            pendingAward = nil
            retention.Prune()
            if not activeRoll and not raidRollPending then events:UnregisterEvent("CHAT_MSG_SYSTEM") end
            if not panel:IsShown() then events:UnregisterEvent("LOOT_SLOT_CLEARED") end
        end
        if panel:IsShown() then
            Refresh()
            UpdateRestoreCandidates()
            AutoLootNext()
        end
    elseif event == "UI_ERROR_MESSAGE" and autoLootPendingSlot then
        autoLootTimeout:Hide()
        autoLootFailedSlots[autoLootPendingSlot] = true
        autoLootPendingSlot = nil
        Refresh()
        AutoLootNext()
    elseif event == "RAID_ROSTER_UPDATE" and panel:IsShown() then
        UpdateClassColors(); Refresh()
    elseif event == "CHAT_MSG_SYSTEM" and raidRollPending then
        local name, value, low, high = Match(arg1 or "", "^(.+) rolls? a? ?(%d+) %((%d+)%-(%d+)%)%.?$")
        if name == "You" then name = UnitName("player") end
        if name == UnitName("player") and tonumber(low) == 1 and tonumber(high) == raidRollPending.count then
            ResolveRaidRoll(tonumber(value))
        end
    elseif event == "CHAT_MSG_SYSTEM" and (activeRoll or (lastRollBySource[currentLootSession] and not lastRollBySource[currentLootSession].awarded)) then
        local name, value, low, high = Match(arg1 or "", "^(.+) rolls? a? ?(%d+) %((%d+)%-(%d+)%)%.?$")
        if name == "You" then name = UnitName("player") end
        value = tonumber(value)
        local range = tonumber(high)
        local roll = activeRoll or lastRollBySource[currentLootSession]
        if name and value and tonumber(low) == 1 and range and eligible[name] then
            local reyCoinUsed, reyCoinItem = false, nil
            if range == 101 then reyCoinUsed, reyCoinItem = RaidService.HasUsedReyCoin(name) end
            local result, invalidReason = RaidService.ProcessLootRoll(roll, name, value, range, reyCoinUsed, reyCoinItem)
            if invalidReason then
                if string.find(invalidReason, "^wrong roll") then
                    AnnounceMessage("WrongRoll", {player=name, item=roll.link, reason=string.gsub(invalidReason, "^wrong roll, ", "")})
                else AnnounceMessage("CannotRoll", {player=name, item=roll.link, reason=invalidReason}) end
            end
            if result then
                if not activeRoll then
                    RaidService.FinalizeLootRoll(roll)
                    MasterLootWindow.ResolveTies(roll)
                    local history = completedRolls[roll.historyKey]
                    if history and roll.summaryIndex then
                        history.latestWinner = roll.winner
                        history.lines[roll.summaryIndex] = "Round " .. history.rounds .. ": " ..
                            (roll.winner and (roll.winner .. " (" .. roll.highest .. "/" .. (roll.winnerResult and roll.winnerResult.range or 100) .. ")") or "No valid rolls")
                        if Raider.Services.LootRollRequest.HasBlockingTie(roll,roll.tieGroups) then history.lines[roll.summaryIndex]="Round "..history.rounds..": Tie - reroll required" end
                        table.insert(history.lines, "    " .. result.name .. " - " .. result.value .. "/" .. (result.range or 100) .. (result.valid == false and " - Invalid (" .. result.invalidReason .. ")" or ""))
                    end
                end
                if panel:IsShown() then RefreshResults() end
                RefreshTracker()
            end
        end
    end
end)

RaidService.onLootSessionChanged = function()
    activeRoll = nil; raidRollPending = nil; pendingAward = nil; lastRoll = nil
    retention.Reset()
    timer:SetScript("OnUpdate", nil); timer:Hide()
    events:UnregisterEvent("CHAT_MSG_SYSTEM")
    if not panel:IsShown() then events:UnregisterEvent("LOOT_SLOT_CLEARED") end
    candidateMenu:Hide(); restorePicker:Hide(); restoreButton:Hide(); tracker:Hide()
    status:SetText("")
    if panel:IsShown() then Refresh() end
end


    function MasterLootWindow.IsBusy()
        return activeRoll ~= nil or raidRollPending ~= nil or pendingAward ~= nil or autoLootPendingSlot ~= nil
    end
    function MasterLootWindow.Stop()
        if MasterLootWindow.IsBusy() then return false,"Finish the current loot operation before stopping BootyRaider." end
        events:UnregisterEvent("LOOT_CLOSED");events:UnregisterEvent("LOOT_SLOT_CLEARED")
        events:UnregisterEvent("RAID_ROSTER_UPDATE");events:UnregisterEvent("UI_ERROR_MESSAGE");events:UnregisterEvent("CHAT_MSG_SYSTEM")
        panel:Hide();tracker:Hide();candidateMenu:Hide();restorePicker:Hide();historyDialog:Hide()
        if giveConfirmation then giveConfirmation:Hide() end
        if MasterLootWindow.newRollDialog then MasterLootWindow.newRollDialog:Hide() end
        timer:SetScript("OnUpdate",nil);timer:Hide();autoLootTimeout:Hide()
        return true
    end
end
function Window.IsInitialized() return initialized end
function Window.IsBusy() return false end
function Window.Stop() return true end
function Window.CanStartManualRoll()
    return Raider.active ~= false and Raider.Services.LootRollRequest.CanOrganize()
end
local function OpenLazy(method,value)
    if Raider.active == false then return false,"BootyRaider is stopped." end
    Window.Initialize()
    return Window[method](value)
end
function Window.Open() return OpenLazy("Open") end
function Window.StartManualRoll(request) return OpenLazy("StartManualRoll",request) end
function Window.OpenLinkedItemRoll(text) return OpenLazy("OpenLinkedItemRoll",text) end
function Window.OpenNewRollDialog() return OpenLazy("OpenNewRollDialog") end
function Window.ShowHistory(link,lines,itemId,itemName)
    Window.Initialize();return Window.ShowHistory(link,lines,itemId,itemName)
end
function Window.ApplyAutoLootSetting() end
