local Raider = BootyRaider

Raider.Modules.RaidManagement = Raider.Modules.RaidManagement or {}
local RaidManagement = Raider.Modules.RaidManagement

function RaidManagement.HideRaidHistoryControls(controls)
    controls.historyScroll:Hide()
    controls.loadRaid:Hide(); controls.testRaid:Hide(); controls.historyTitle:Hide(); controls.historyEmpty:Hide()
    for _, group in ipairs({controls.historyButtons, controls.historyDeleteButtons, controls.historyLoadButtons, controls.historyHeaders}) do
        for index = 1, table.getn(group) do group[index]:Hide() end
    end
end

local function Cell(label, parent, x, width, text)
    label:ClearAllPoints(); label:SetPoint("LEFT", parent, "LEFT", x, 0); label:SetJustifyV("MIDDLE")
    label:SetWidth(width); label:SetHeight(0); label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(true) end
    if label.SetNonSpaceWrap then label:SetNonSpaceWrap(true) end
    label:SetText(text); label:Show()
    return Raider.UI.Components.MeasureTextHeight(label, width, true) + 10
end

local function MeasureHistory(width, controls)
    local page, snapshots, actionY = controls.historyPage, controls.historyPage.raidHistorySnapshots, controls.historyActionY
    local dataWidth = math.max(60, width - 48)
    local numberWidth = 28
    local remainingWidth = math.max(32, dataWidth - numberWidth)
    local nameWidth, raidWidth = math.floor(remainingWidth * 0.34), math.floor(remainingWidth * 0.30)
    local timeWidth = remainingWidth - nameWidth - raidWidth
    local widths = {numberWidth, nameWidth, raidWidth, timeWidth}
    local x = 8
    for index = 1, 4 do
        local heading = controls.historyHeaders[index]
        heading:ClearAllPoints(); heading:SetPoint("TOPLEFT", page, "TOPLEFT", x, actionY - 62); heading:SetWidth(widths[index] - 6); heading:SetJustifyH("LEFT"); heading:Show()
        x = x + widths[index]
    end
    controls.historyCanvas:SetWidth(width)
    local y = 0
    for index = 1, 10 do
        local snapshot, button = snapshots[index], controls.historyButtons[index]
        local deleteButton, load = controls.historyDeleteButtons[index], controls.historyLoadButtons[index]
        button:ClearAllPoints(); button:SetPoint("TOPLEFT", controls.historyCanvas, "TOPLEFT", 0, y); button:SetWidth(dataWidth)
        if snapshot then
            local savedAt = snapshot.savedAt or snapshot.updatedAt
            local height = math.max(26,
                Cell(button.number, button, 4, numberWidth - 6, tostring(index)),
                Cell(button.label, button, numberWidth, nameWidth, tostring(snapshot.id or "Unknown")),
                Cell(button.raidName, button, numberWidth + nameWidth, raidWidth, snapshot.raidName or "Unknown zone"),
                Cell(button.savedAt, button, numberWidth + nameWidth + raidWidth, timeWidth, savedAt and date("%Y-%m-%d %H:%M", savedAt) or ""))
            button:SetHeight(height); button:Show()
            Raider.UI.Components.StyleWarmListRow(button, page.selectedRaidHistoryId == snapshot.id)
            load:SetWidth(24); load:SetHeight(24); deleteButton:SetWidth(16); deleteButton:SetHeight(16)
            load:ClearAllPoints(); load:SetPoint("LEFT", button, "RIGHT", 4, 0); load:Show()
            deleteButton:ClearAllPoints(); deleteButton:SetPoint("LEFT", load, "RIGHT", 4, 0); deleteButton:Show()
            y = y - height - 2
        else button.number:Hide(); button:Hide(); load:Hide(); deleteButton:Hide() end
    end
    return math.max(1, -y - 2)
end

function RaidManagement.ShowRaidHistoryControls(page, controls, canStartRaid)
    local fullWidth = math.max(1, Raider.UI.Components.GetFrameSpan(page) - 16)
    local width = math.min(500, fullWidth)
    local rightInset = 8 + fullWidth - width
    local buttonWidth = math.min(110, (width - 8) / 2)
    if controls.title then
        controls.title:SetText("Raid")
        if BootyRaiderDB.raidHideSectionHeader then controls.title:Hide() else controls.title:Show() end
    end
    local textY = BootyRaiderDB.raidHideSectionHeader and -8 or -48
    if controls.raidInfo then
        controls.raidInfo:ClearAllPoints(); controls.raidInfo:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, textY + 2); controls.raidInfo:Show()
    end
    local actionY = textY - 38
    if controls.unavailable then
        local label = controls.unavailable
        label:ClearAllPoints(); label:SetPoint("TOPLEFT", page, "TOPLEFT", 8, textY)
        local helpWidth = controls.raidInfo and math.min(width, math.max(1, fullWidth - 34)) or width
        label:SetWidth(helpWidth); label:SetJustifyH("LEFT")
        if label.SetWordWrap then label:SetWordWrap(true) end
        label:SetText(canStartRaid and "Start a new raid snapshot, or load a saved raid." or "Join a raid to start a new snapshot, or load a saved raid.")
        label:SetHeight(0)
        local textHeight = math.max(16, Raider.UI.Components.MeasureTextHeight(label, helpWidth))
        label:SetHeight(textHeight); label:Show()
        actionY = textY - textHeight - 16
    end
    controls.scan:ClearAllPoints(); controls.scan:SetPoint("TOPLEFT", page, "TOPLEFT", 8, actionY)
    controls.scan:SetWidth(buttonWidth); controls.scan:SetHeight(22); controls.scan:SetText("New Raid"); controls.scan:Show()
    if canStartRaid then controls.scan:Enable() else controls.scan:Disable() end
    controls.loadRaid:Hide()
    controls.testRaid:ClearAllPoints(); controls.testRaid:SetPoint("LEFT", controls.scan, "RIGHT", 8, 0)
    controls.testRaid:SetWidth(buttonWidth); controls.testRaid:SetHeight(22); controls.testRaid:Show()
    controls.historyTitle:ClearAllPoints(); controls.historyTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 8, actionY - 38); controls.historyTitle:Show()
    local snapshots = page.getRaidHistory and page.getRaidHistory() or {}; page.raidHistorySnapshots = snapshots
    if not Raider.UI.Components.ApplySelectionListStyle(controls.historyButtons, snapshots, page.selectedRaidHistoryId, controls.loadRaid) then page.selectedRaidHistoryId = nil end
    controls.historyPage = page; controls.historyActionY = actionY
    page.raidHistoryHeaderY = actionY - 62
    page.raidHistoryRowsY = actionY - 82
    local _, pageHeight = Raider.UI.Components.GetFrameSpan(page)
    local viewportHeight = math.max(1, pageHeight + actionY - 82 - 8)
    local contentWidth, contentHeight, overflow, maximum = Raider.UI.Components.ResolveScrollLayout(width, viewportHeight, 20, MeasureHistory, controls)
    controls.historyScroll:ClearAllPoints()
    controls.historyScroll:SetPoint("TOPLEFT", page, "TOPLEFT", 8, actionY - 82)
    controls.historyScroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -rightInset - (overflow and 20 or 0), 8)
    controls.historyCanvas:SetWidth(contentWidth); controls.historyCanvas:SetHeight(contentHeight)
    controls.historyScroll:Show()
    local bar = getglobal("BootyRaiderRaidHistoryScrollScrollBar")
    if bar then
        bar:ClearAllPoints(); bar:SetWidth(16)
        bar:SetPoint("TOPRIGHT", page, "TOPRIGHT", -rightInset, actionY - 98)
        bar:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -rightInset, 24)
    end
    if controls.historyScroll.UpdateScrollChildRect then controls.historyScroll:UpdateScrollChildRect() end
    Raider.UI.Components.ApplyScrollRange(controls.historyScroll, bar, maximum)
    controls.historyScroll.bootyScrollGutter = overflow and 20 or 0
    if table.getn(snapshots) == 0 then
        controls.historyEmpty:ClearAllPoints(); controls.historyEmpty:SetPoint("TOPLEFT", page, "TOPLEFT", 8, actionY - 86); controls.historyEmpty:Show()
    else controls.historyEmpty:Hide() end
end
