local Raider = BootyRaider
local UI = Raider.UI.Components

local function ItemLabel(reference, name)
    if type(reference) == "number" then return UI.GetItemLabel(reference) end
    return name or reference or "Unknown item"
end

local function ItemTooltip()
    if this.itemId then UI.ShowItemTooltip(this)
    elseif this.itemName then UI.AnchorTooltip(this); GameTooltip:SetText(this.itemName); GameTooltip:Show() end
end

Raider.Modules = Raider.Modules or {}
local CSR = {}
Raider.Modules.CSR = CSR

local function CreateTestLab(owner, onChanged, onExit)
    local service = Raider.Services.CSRTest
    local dialog = UI.CreateContainer("BootyRaiderCSRTestLab", UIParent)
    dialog:SetWidth(560); dialog:SetHeight(620); dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dialog:SetResizable(true); dialog:SetMinResize(320, 280); dialog:SetMaxResize(850, 700)
    if dialog.SetClampedToScreen then dialog:SetClampedToScreen(true) end
    dialog.title = UI.CreateHeading(dialog, "CSR Test Lab", 1, "gold", "csr")
    dialog.close = UI.CreateWindowButton(dialog, nil, "close")
    dialog.minimize = UI.CreateWindowButton(dialog, nil, "minimize")
    dialog.minimizeButton = dialog.minimize
    UI.Window.StyleProjectDialog(dialog)
    dialog.minimize:SetPoint("RIGHT", dialog.close, "LEFT", -4, 0)
    dialog.title:SetPoint("RIGHT", dialog.minimize, "LEFT", -8, 0)
    dialog.host = UI.CreateContainer(nil, dialog)
    dialog.body = UI.CreateResponsiveCanvas(dialog.host, "BootyRaiderCSRTestLabBody")
    local body = dialog.body
    dialog.state = service.Create(); dialog.summary = { players = {} }
    dialog.help = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.help:SetText("Temporary simulation. Saved raids are unchanged.")
    dialog.error = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall"); dialog.error:SetTextColor(1, 0.3, 0.3)
    local function Section(title)
        local section = UI.CreateContainer(nil, body)
        section.title = UI.CreateHeading(section, title, 3, "gold")
        return section
    end
    dialog.setupSection = Section("Player setup"); dialog.csrSection = Section("CSR Setup")
    dialog.timelineSection = Section("Timeline"); dialog.logSection = Section("Simulation Log")
    dialog.sections = {dialog.setupSection, dialog.csrSection, dialog.timelineSection, dialog.logSection}
    dialog.playerTitle, dialog.reserveTitle = dialog.setupSection.title, dialog.csrSection.title
    dialog.timeTitle, dialog.logTitle = dialog.timelineSection.title, dialog.logSection.title
    local function Action(parent, text, width, callback)
        local button = UI.CreateButton(parent, nil, text, width, 26)
        UI.StyleActionButton(button); button.bootyFlowWidth = width
        button:SetScript("OnClick", function()
            if dialog.minimized or not dialog:IsVisible() or not button:IsEnabled() then return end
            local accepted, reason = callback(dialog.state)
            dialog.actionError = accepted == false and reason or nil; dialog:Refresh()
        end)
        return button
    end
    dialog.setupPlayerGroup = UI.CreateContainer(nil, dialog.setupSection); dialog.setupPlayerGroup:SetHeight(26)
    dialog.setupPlayerLabel = UI.CreateLabel(dialog.setupPlayerGroup, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.setupPlayerLabel:SetText("Player:")
    dialog.setupPlayerSelect = UI.CreateDropdownButton(dialog.setupPlayerGroup, nil, "New player", 220)
    dialog.setupPlayerSelect:SetHeight(26)
    dialog.setupPlayerPanel = UI.CreateDropdownPanel(dialog.setupSection, dialog.setupPlayerSelect, 220, 80, 20)
    dialog.setupPlayerCanvas = UI.CreateResponsiveCanvas(dialog.setupPlayerPanel, "BootyRaiderCSRSetupPlayers")
    dialog.setupPlayerChoices = {}
    dialog.rankGroup = UI.CreateContainer(nil, dialog.setupSection)
    dialog.rankGroup:SetHeight(26)
    local rankChoices = {}
    for _, rank in ipairs(service.GetRanks()) do table.insert(rankChoices, {value = rank, text = rank}) end
    dialog.rankLabel, dialog.rankSelect, dialog.rankPanel = UI.CreateChoiceField({
        parent = dialog.rankGroup, label = "Rank:", x = 0, y = 0, width = 176, height = 202, firstY = -4, step = 24,
        initialText = dialog.state.setupRank, choices = rankChoices, getValue = function() return dialog.state.setupRank end,
        onSelect = function(rank)
            local accepted, reason = service.SetSetupRank(dialog.state, rank)
            dialog.actionError = accepted == false and reason or nil
        end, onChanged = function() dialog:Refresh() end,
    })
    dialog.rankSelect:SetHeight(26); dialog.rankChoices = dialog.rankPanel.options
    dialog.addPlayer = Action(dialog.setupSection, "Add player", 112, function(state)
        if state.setupPlayer then return service.UpdatePlayer(state) end
        return service.AddPlayer(state)
    end)
    dialog.itemHit = UI.CreateControl(nil, dialog.setupSection)
    dialog.item = UI.CreateLabel(dialog.itemHit, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.setupItem = dialog.item; dialog.itemHit.label = dialog.item; dialog.itemHit.labelPrefix = "Item: "
    local smallFont, smallSize, smallFlags = dialog.item:GetFont()
    dialog.rankLabel:SetFont(smallFont, smallSize, smallFlags)
    dialog.itemHit:SetScript("OnEnter", function() UI.ShowItemTooltip(this) end)
    dialog.itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    dialog.itemHit:SetScript("OnClick", function() UI.HandleItemClick(this) end)
    dialog.nextItem = Action(dialog.setupSection, "Next Item", 96, service.NextSetupItem)
    dialog.setupItemControls = {dialog.rankGroup, dialog.itemHit}
    dialog.playerControls = {dialog.addPlayer, dialog.nextItem}
    dialog.playerSelect = UI.CreateDropdownButton(dialog.csrSection, nil, "Select player and item", 260)
    dialog.playerSelect:SetHeight(26)
    dialog.playerPanel = UI.CreateDropdownPanel(dialog.csrSection, dialog.playerSelect, 260, 80, 20)
    dialog.playerCanvas = UI.CreateResponsiveCanvas(dialog.playerPanel, "BootyRaiderCSRTestPlayers")
    dialog.playerChoices = {}
    dialog.setupPlayerSelect:SetScript("OnClick", function()
        dialog.rankPanel:Hide(); dialog.playerPanel:Hide()
        if dialog.setupPlayerPanel:IsVisible() then dialog.setupPlayerPanel:Hide() else dialog.setupPlayerPanel:Show() end
    end)
    local toggleRank = dialog.rankSelect:GetScript("OnClick")
    dialog.rankSelect:SetScript("OnClick", function()
        dialog.setupPlayerPanel:Hide(); dialog.playerPanel:Hide(); toggleRank()
    end)
    dialog.playerSelect:SetScript("OnClick", function()
        if not dialog.playerSelect:IsEnabled() then return end
        dialog.rankPanel:Hide(); dialog.setupPlayerPanel:Hide()
        if dialog.playerPanel:IsVisible() then dialog.playerPanel:Hide() else dialog.playerPanel:Show() end
    end)
    dialog.contextStatus = UI.CreateContainer(nil, dialog.csrSection); dialog.contextStatus:SetHeight(26)
    dialog.statusRankLabel = UI.CreateLabel(dialog.contextStatus, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.statusRankLabel:SetText("Rank:"); dialog.statusRankLabel:SetTextColor(unpack(UI.Theme.colors.goldText))
    dialog.status = UI.CreateLabel(dialog.contextStatus, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.statusCsrLabel = UI.CreateLabel(dialog.contextStatus, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.statusCsrLabel:SetText("CSR:"); dialog.statusCsrLabel:SetTextColor(unpack(UI.Theme.colors.goldText))
    dialog.result = UI.CreateLabel(dialog.contextStatus, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.contextControls = {dialog.playerSelect, dialog.contextStatus}
    dialog.reserveActions = {
        Action(dialog.csrSection, "Add unsuccessful SR", 150, service.AddMissedReserve),
        Action(dialog.csrSection, "Award Item", 104, service.AwardItem),
    }
    dialog.dateStatus = UI.CreateLabel(dialog.timelineSection, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.dateGroup = UI.CreateContainer(nil, dialog.timelineSection)
    dialog.dateLabel = UI.CreateLabel(dialog.dateGroup, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.dateLabel:SetText("Date:"); dialog.dateLabel:SetTextColor(unpack(UI.Theme.colors.goldText))
    dialog.dateGroup:SetHeight(26)
    dialog.timeActions = {
        Action(dialog.timelineSection, "+1 Day", 80, function(state) return service.AdvanceDays(state, 1) end),
        Action(dialog.timelineSection, "+7 Days", 80, function(state) return service.AdvanceDays(state, 7) end),
    }
    dialog.timelineControls = {dialog.dateGroup, dialog.timeActions[1], dialog.timeActions[2]}
    dialog.actions = {dialog.addPlayer, dialog.nextItem, dialog.reserveActions[1], dialog.reserveActions[2],
        dialog.timeActions[1], dialog.timeActions[2]}
    dialog.logBody = UI.CreateContainer(nil, dialog.logSection); dialog.logBody:EnableMouse(false)
    UI.SetProjectButtonOutline(dialog.logBody, true, nil, nil, nil, nil, nil, nil, true)
    dialog.logRows, dialog.logLines = {}, {}
    for index = 1, 5 do
        local row = UI.CreateContainer(nil, dialog.logBody); row:EnableMouse(false)
        UI.SetAlternatingRowColor(row, nil, index)
        row.date = UI.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
        row.date:SetTextColor(unpack(UI.Theme.colors.goldText))
        row.label = UI.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
        dialog.logRows[index], dialog.logLines[index] = row, row.label
    end
    dialog.reset = UI.CreateButton(dialog, nil, "Reset Test", 90, 26)
    dialog.exit = UI.CreateButton(dialog, nil, "Exit Test", 80, 26)
    UI.StyleActionButton(dialog.reset); UI.StyleActionButton(dialog.exit)
    dialog.exit:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 8)
    dialog.reset:SetPoint("RIGHT", dialog.exit, "LEFT", -8, 0)
    local function ClosePanels() dialog.playerPanel:Hide(); dialog.rankPanel:Hide(); dialog.setupPlayerPanel:Hide() end
    local function Exit() ClosePanels(); dialog:Hide(); if onExit then onExit() end end
    dialog.close:SetScript("OnClick", Exit); dialog.exit:SetScript("OnClick", Exit)
    dialog.reset:SetScript("OnClick", function() service.Reset(dialog.state); dialog.actionError = nil; dialog:Refresh() end)
    dialog.grip = UI.CreateResizeGrip(dialog)
    dialog.resizeGrip = dialog.grip
    UI.AttachTooltip(dialog.grip, "Resize CSR Test Lab", "Drag to change the window size.")
    dialog.grip:SetScript("OnMouseDown", function() if not dialog.minimized then dialog:StartSizing("BOTTOMRIGHT") end end)
    dialog.grip:SetScript("OnMouseUp", function() dialog:StopMovingOrSizing(); dialog:Layout() end)
    dialog.grip:SetScript("OnHide", function() dialog:StopMovingOrSizing() end)
    local function LabelHeight(label, width)
        label:SetWidth(math.max(1, width)); label:SetHeight(0); label:SetJustifyH("LEFT")
        if label.SetWordWrap then label:SetWordWrap(true) end
        local height = math.max(16, UI.MeasureTextHeight(label, width))
        label:SetHeight(height); return height
    end
    local function Line(label, parent, width, top)
        label:ClearAllPoints(); label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -top)
        return top + LabelHeight(label, width) + 6
    end
    local function TextWidth(label)
        local previous = label:GetWidth()
        label:SetWidth(0)
        local width = math.ceil(label:GetStringWidth()) + 2
        label:SetWidth(previous)
        return width
    end
    local function Inline(label, parent, x)
        label:ClearAllPoints(); label:SetPoint("LEFT", parent, "LEFT", x, 0)
        label:SetWidth(TextWidth(label)); label:SetHeight(16); label:SetJustifyH("LEFT")
    end
    local function LayoutContent(width)
        local y = Line(dialog.help, body, width, 0)
        if dialog.actionError then y = Line(dialog.error, body, width, y); dialog.error:Show() else dialog.error:Hide() end
        local function Begin(section)
            section:ClearAllPoints(); section:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y); section:SetWidth(width)
            return Line(section.title, section, width, 0)
        end
        local function Finish(section, height) section:SetHeight(height); y = y + height + 12 end
        local top = Begin(dialog.setupSection)
        dialog.setupPlayerGroup:ClearAllPoints(); dialog.setupPlayerGroup:SetPoint("TOPLEFT", dialog.setupSection, "TOPLEFT", 0, -top)
        dialog.setupPlayerGroup:SetWidth(width)
        Inline(dialog.setupPlayerLabel, dialog.setupPlayerGroup, 0)
        dialog.setupPlayerSelect:ClearAllPoints(); dialog.setupPlayerSelect:SetPoint("LEFT", dialog.setupPlayerLabel, "RIGHT", 4, 0)
        dialog.setupPlayerSelect:SetWidth(math.max(1, width - TextWidth(dialog.setupPlayerLabel) - 4)); UI.ReflowControlText(dialog.setupPlayerSelect)
        top = top + 34
        local rankWidth = math.min(width, TextWidth(dialog.rankLabel) + 154)
        dialog.rankGroup.bootyFlowWidth = rankWidth
        Inline(dialog.rankLabel, dialog.rankGroup, 0)
        dialog.rankSelect:ClearAllPoints(); dialog.rankSelect:SetPoint("LEFT", dialog.rankLabel, "RIGHT", 4, 0)
        dialog.rankSelect:SetWidth(math.max(1, rankWidth - TextWidth(dialog.rankLabel) - 4)); UI.ReflowControlText(dialog.rankSelect)
        local itemWidth = width - rankWidth - 8
        if itemWidth < 120 then itemWidth = width end
        dialog.itemHit.bootyFlowWidth = itemWidth
        dialog.item:ClearAllPoints(); dialog.item:SetPoint("LEFT", dialog.itemHit, "LEFT", 0, 0)
        dialog.itemHit:SetHeight(math.max(26, LabelHeight(dialog.item, itemWidth)))
        top = UI.LayoutFlow(dialog.setupSection, dialog.setupItemControls, 0, top, width, 8) + 8
        Finish(dialog.setupSection, UI.LayoutFlow(dialog.setupSection, dialog.playerControls, 0, top, width, 8))
        top = Begin(dialog.csrSection)
        Inline(dialog.statusRankLabel, dialog.contextStatus, 0)
        local rankValueX = TextWidth(dialog.statusRankLabel) + 4
        Inline(dialog.status, dialog.contextStatus, rankValueX)
        local csrLabelX = rankValueX + TextWidth(dialog.status) + 12
        Inline(dialog.statusCsrLabel, dialog.contextStatus, csrLabelX)
        local csrValueX = csrLabelX + TextWidth(dialog.statusCsrLabel) + 4
        Inline(dialog.result, dialog.contextStatus, csrValueX)
        dialog.contextStatus.bootyFlowWidth = csrValueX + TextWidth(dialog.result)
        local playerWidth = math.min(260, math.max(math.min(160, width), width - dialog.contextStatus.bootyFlowWidth - 8))
        dialog.playerSelect.bootyFlowWidth = playerWidth
        dialog.playerSelect:SetWidth(playerWidth); UI.ReflowControlText(dialog.playerSelect)
        if dialog.playerSelect.label.SetWordWrap then dialog.playerSelect.label:SetWordWrap(false) end
        dialog.playerSelect:SetHeight(26); dialog.contextStatus:SetHeight(26)
        top = UI.LayoutFlow(dialog.csrSection, dialog.contextControls, 0, top, width, 8) + 8
        Finish(dialog.csrSection, UI.LayoutFlow(dialog.csrSection, dialog.reserveActions, 0, top, width, 8))
        top = Begin(dialog.timelineSection)
        Inline(dialog.dateLabel, dialog.dateGroup, 0)
        Inline(dialog.dateStatus, dialog.dateGroup, TextWidth(dialog.dateLabel) + 4)
        dialog.dateGroup.bootyFlowWidth = TextWidth(dialog.dateLabel) + 4 + TextWidth(dialog.dateStatus)
        Finish(dialog.timelineSection, UI.LayoutFlow(dialog.timelineSection, dialog.timelineControls, 0, top, width, 4))
        top = Begin(dialog.logSection)
        dialog.logBody:ClearAllPoints(); dialog.logBody:SetPoint("TOPLEFT", dialog.logSection, "TOPLEFT", 0, -top)
        dialog.logBody:SetWidth(width)
        local logTop = 4
        for index, row in ipairs(dialog.logRows) do
            if dialog.logLines[index]:GetText() ~= "" then
                row:ClearAllPoints(); row:SetPoint("TOPLEFT", dialog.logBody, "TOPLEFT", 4, -logTop); row:SetWidth(math.max(1, width - 8))
                local dateWidth = math.max(72, TextWidth(row.date))
                row.date:ClearAllPoints(); row.date:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4); row.date:SetWidth(dateWidth); row.date:SetHeight(16)
                row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 14 + dateWidth, -4)
                row:SetHeight(math.max(24, LabelHeight(row.label, width - 28 - dateWidth) + 8))
                row:Show(); logTop = logTop + row:GetHeight()
            else row:Hide() end
        end
        dialog.logBody:SetHeight(logTop + 4)
        Finish(dialog.logSection, top + dialog.logBody:GetHeight())
        return y - 12
    end
    local function LayoutChoices(width, height, context)
        local y = 4
        for _, choice in ipairs(context.choices) do
            if choice:IsShown() then
                choice:ClearAllPoints(); choice:SetPoint("TOPLEFT", context.canvas, "TOPLEFT", 4, -y)
                choice:SetWidth(math.max(1, width - 8))
                choice.label:ClearAllPoints(); choice.label:SetPoint("TOPLEFT", choice, "TOPLEFT", 6, -4)
                choice:SetHeight(math.max(22, LabelHeight(choice.label, width - 20) + 8))
                y = y + choice:GetHeight() + 2
            end
        end
        return y + 2
    end
    local playerLayout = {canvas = dialog.playerCanvas, choices = dialog.playerChoices}
    local setupPlayerLayout = {canvas = dialog.setupPlayerCanvas, choices = dialog.setupPlayerChoices}
    local function LayoutPopup(panel, toggle, context)
        panel:SetWidth(toggle:GetWidth())
        panel:SetHeight(math.min(202, math.max(34, LayoutChoices(panel:GetWidth(), nil, context))))
        UI.LayoutResponsiveCanvas(context.canvas, LayoutChoices, context)
    end
    function dialog:Layout()
        if self.minimized or self.changingWindowState or not self:IsVisible() then return end
        ClosePanels()
        self.host:ClearAllPoints(); self.host:SetPoint("TOPLEFT", self, "TOPLEFT", 16, -40)
        self.host:SetWidth(self:GetWidth()-32); self.host:SetHeight(self:GetHeight()-90)
        UI.LayoutResponsiveCanvas(body, LayoutContent)
        LayoutPopup(self.playerPanel, self.playerSelect, playerLayout)
        LayoutPopup(self.setupPlayerPanel, self.setupPlayerSelect, setupPlayerLayout)
    end
    dialog:SetScript("OnSizeChanged", function() dialog:Layout() end)
    function dialog:Refresh()
        if self.minimized or not self:IsVisible() then self.refreshPending = true; return end
        self.refreshPending = nil
        self.error:SetText(self.actionError or "")
        service.BuildSummary(self.state, self.summary)
        local selected, selectedItem, selectedCsr = self.state.currentPlayer, service.GetItemId(self.state), 0
        for _, player in ipairs(self.summary.players) do
            if player.name == selected and player.itemId == selectedItem then selectedCsr = player.csr end
        end
        self.rankSelect:RefreshChoiceValues()
        self.itemHit.itemId = service.GetSetupItemId(self.state)
        self.item:SetText("Item: " .. UI.GetItemLabel(self.itemHit.itemId))
        self.setupPlayerSelect:SetText(self.state.setupPlayer or "New player")
        self.addPlayer:SetText(self.state.setupPlayer and "Update player" or "Add player")
        local setupPlayers = service.GetPlayers(self.state)
        for index = 1, table.getn(setupPlayers) + 1 do
            local choice = self.setupPlayerChoices[index]
            if not choice then
                choice = UI.CreateButton(self.setupPlayerCanvas, nil, "", 220, 22); UI.StyleDropdownChoice(choice)
                choice:SetScript("OnClick", function()
                    local accepted, reason = service.SelectSetupPlayer(dialog.state, this.playerName)
                    dialog.actionError = accepted == false and reason or nil; dialog.setupPlayerPanel:Hide(); dialog:Refresh()
                end)
                self.setupPlayerChoices[index] = choice
            end
            choice.playerName = setupPlayers[index - 1]
            choice:SetText(choice.playerName or "New player"); choice:Show()
        end
        for index = table.getn(setupPlayers) + 2, table.getn(self.setupPlayerChoices) do self.setupPlayerChoices[index]:Hide() end
        self.playerSelect:SetText(selected and (selected .. " - " .. UI.GetItemLabel(selectedItem)) or "Select player and item")
        local players = service.GetPlayerItems(self.state)
        for index, context in ipairs(players) do
            local choice = self.playerChoices[index]
            if not choice then
                choice = UI.CreateButton(self.playerCanvas, nil, "", 240, 22); UI.StyleDropdownChoice(choice)
                choice:SetScript("OnClick", function()
                    local accepted, reason = service.SelectPlayer(dialog.state, this.playerName, this.itemId)
                    dialog.actionError = accepted == false and reason or nil; dialog.playerPanel:Hide(); dialog:Refresh()
                end)
                self.playerChoices[index] = choice
            end
            choice.playerName, choice.itemId = context.name, context.itemId
            choice:SetText(context.name .. " - " .. UI.GetItemLabel(context.itemId)); choice:Show()
        end
        for index = table.getn(players) + 1, table.getn(self.playerChoices) do self.playerChoices[index]:Hide() end
        if selected then self.playerSelect:Enable() else self.playerSelect:Disable() end
        for _, button in ipairs(self.reserveActions) do if selected then button:Enable() else button:Disable() end end
        self.status:SetText(selected and self.state.ranks[selected] or "-"); self.result:SetText(tostring(selectedCsr))
        self.dateStatus:SetText(date("%d.%m.%Y", self.state.now))
        for index, line in ipairs(self.logLines) do
            line:SetText(self.state.log[index] or "")
            local stamp = self.state.logTimes[index]
            self.logRows[index].date:SetText(stamp and date("%d.%m.%Y", stamp) or "")
        end
        self:Layout()
        if onChanged then onChanged() end
    end
    function dialog:SetMinimized(minimized)
        minimized = minimized and true or false
        if self.minimized == minimized then return end
        ClosePanels(); self:StopMovingOrSizing(); self.changingWindowState = true
        local left, top = self.GetLeft and self:GetLeft(), self.GetTop and self:GetTop()
        if left and top then
            self:ClearAllPoints(); self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        self.minimized = minimized
        if minimized then
            self.expandedWidth, self.expandedHeight = self:GetWidth(), self:GetHeight()
            self.host:Hide(); body.layoutViewport:Hide(); self.reset:Hide(); self.exit:Hide(); self.grip:Hide()
            self:SetResizable(false); self:SetMinResize(320, UI.Window.MinimizedHeight)
            self:SetHeight(UI.Window.MinimizedHeight); UI.SetWindowButtonAction(self.minimize, "maximize")
        else
            self:SetMinResize(320, 280); self:SetMaxResize(850, 700); self:SetResizable(true)
            self:SetWidth(self.expandedWidth or 560); self:SetHeight(self.expandedHeight or 620)
            self.host:Show(); body.layoutViewport:Show(); self.reset:Show(); self.exit:Show(); self.grip:Show()
            UI.SetWindowButtonAction(self.minimize, "minimize")
        end
        self.changingWindowState = nil
        if not minimized then self:Refresh() end
    end
    dialog.minimize:SetScript("OnClick", function() dialog:SetMinimized(not dialog.minimized) end)
    function dialog:Open()
        self:Show()
        if self.minimized then self:SetMinimized(false) else self:Refresh() end
    end
    function dialog:Toggle()
        if self:IsShown() then Exit() else self:Open() end
    end
    dialog:SetScript("OnHide", function() ClosePanels(); dialog:StopMovingOrSizing(); GameTooltip:Hide() end)
    dialog:Hide()
    if UI.WindowStack then UI.WindowStack.Register(dialog, {owner = owner}) end
    return dialog
end

local function PairKey(player)
    return string.lower(player.name or "") .. ":" .. tostring(player.itemId or "")
end

local function ClearArray(values)
    for index = table.getn(values), 1, -1 do values[index] = nil end
end

local reportHeaderColor, reportSectionColor = {1, 1, 1}, {0.015, 0.015, 0.015}
local function ReportFont(label)
    local font, _, flags = label:GetFont()
    label:SetFont(font, 10 + (UI.GetTextSizeDelta(label:GetParent()) or 0), flags)
end

local function StyleReportRow(row, index, accordion, header)
    if accordion then UI.SetRowColor(row, reportSectionColor, 1)
    elseif header then UI.SetRowColor(row, reportHeaderColor, 0)
    else UI.SetAlternatingRowColor(row, nil, index) end
    UI.SetProjectButtonOutline(row, accordion, nil, nil, nil, nil, nil, nil, true)
    row.bootyTableRowHover:Hide(); row.bootyTableRowSelection:Hide()
    row.bootyTableRowSelected = false; row.bootyTableRowHovered = nil
    row:EnableMouse(not header)
end

function CSR.Create(host, getEntries, getRules, getRosterData, openRaidStatistics, options)
    options = options or {}
    local page = UI.CreateResponsiveCanvas(host, "BootyRaiderCSRPage")
    local controller = { page = page, rows = {}, detailRows = {}, detailLines = {}, viewButtons = {},
        summary = { players = {} }, selectedRaids = {}, expanded = {}, sortStates = {},
        nodes = {}, pairs = {}, groups = {}, layoutRows = {}, groupMode = "default", showArchived = false,
        showAwarded = false, visibility = {} }
    page.csrController = controller; host.csrController = controller
    local raidNames = Raider.Services.RaidStatistics.GetRaidNames()
    for _, name in ipairs(raidNames) do controller.selectedRaids[name] = true end
    controller.testLab = CreateTestLab(page, function() controller.testMode = true; controller:Refresh() end,
        function() controller.testMode = false; controller:Refresh() end)
    controller.title = UI.CreateHeading(page, "CSR", 1, "gold", "csr")
    controller.description = UI.CreateLabel(page, nil, "OVERLAY", "GameFontHighlightSmall")
    controller.description:SetJustifyH("LEFT")
    controller.descriptionText = "Unsuccessful Soft Reserves. Each miss grants 10 CSR for 60 days. Archived reserves remain available for reference and grant no CSR."
    controller.description:SetText(controller.descriptionText)
    controller.testButton = UI.CreateButton(page, nil, "CSR Test Lab", 96, 22)
    UI.StyleActionButton(controller.testButton)
    controller.testButton:SetScript("OnClick", function() controller.testLab:Toggle() end)
    controller.raidFilter = UI.CreateDropdownButton(page, nil, "Raid", 87)
    controller.raidFilter.bootyFlowWidth = 87; controller.raidFilter:SetHeight(26)
    controller.raidPanel = UI.CreateDropdownPanel(page, controller.raidFilter, 190, 178, 20)
    controller.raidDismiss = controller.raidPanel.dismiss
    controller.raidFilter:SetScript("OnClick", function()
        if controller.raidPanel:IsVisible() then controller.raidPanel:Hide() else controller.raidPanel:Show() end
    end)
    UI.FilterPanel.Refresh(controller.raidPanel, raidNames, controller.selectedRaids, function() controller:Refresh() end, true, true)
    controller.raidChecks = controller.raidPanel.options
    controller.searchGroup = UI.CreateContainer(nil, page)
    controller.searchGroup:SetWidth(108); controller.searchGroup:SetHeight(26); controller.searchGroup.bootyFlowWidth = 108
    controller.search = UI.CreateFramedEditBox(controller.searchGroup, nil, 108)
    controller.search:SetPoint("LEFT", controller.searchGroup, "LEFT", 0, 0); controller.search:SetHeight(26)
    controller.search:SetAutoFocus(false)
    controller.search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    controller.search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    controller.search:SetScript("OnTextChanged", function() controller:Refresh() end)
    UI.AttachPlaceholder(controller.search, "Search...")
    controller.groupBox = UI.CreateContainer(nil, page)
    controller.groupBox:SetWidth(128); controller.groupBox:SetHeight(26)
    local groupLabel
    groupLabel, controller.groupBy = UI.CreateChoiceField({ parent = controller.groupBox, label = "Group By", x = 0, y = 0,
        buttonOffset = 48, width = 80, height = 76, firstY = -5, step = 22, initialText = "Default", font = "GameFontHighlightSmall",
        choices = {{ value = "default", text = "Default" }, { value = "player", text = "Player" }, { value = "item", text = "Item" }},
        getValue = function() return controller.groupMode end,
        onSelect = function(value) controller:SetGroupBy(value) end })
    groupLabel:ClearAllPoints(); groupLabel:SetPoint("LEFT", controller.groupBox, "LEFT", 0, 0)
    groupLabel:SetJustifyV("MIDDLE"); groupLabel:SetHeight(26); controller.groupLabel = groupLabel
    controller.groupBy:SetHeight(26)
    local function HistoryFilter(text, field)
        local group = UI.CreateContainer(nil, page)
        group:SetWidth(156); group:SetHeight(26); group.bootyFlowWidth = 156
        local check = UI.CreateCheckButton(nil, group, "UICheckButtonTemplate")
        check:SetPoint("LEFT", group, "LEFT", 0, 0)
        check:SetWidth(18); check:SetHeight(18); check:SetChecked(false)
        check.label = UI.CreateLabel(group, nil, "OVERLAY", "GameFontHighlightSmall")
        check.label:SetPoint("LEFT", check, "RIGHT", 0, 0); check.label:SetText(text)
        check.label:SetJustifyH("LEFT"); check.label:SetJustifyV("MIDDLE")
        if check.label.SetWordWrap then check.label:SetWordWrap(false) end
        check:SetScript("OnClick", function()
            controller[field] = this:GetChecked() and true or false; controller:Refresh()
        end)
        check.labelHit = UI.CreateControl(nil, group)
        check.labelHit:SetPoint("LEFT", check, "RIGHT", 0, 0); check.labelHit:SetHeight(26)
        check.labelHit:SetScript("OnClick", function()
            check:SetChecked(not check:GetChecked())
            controller[field] = check:GetChecked() and true or false; controller:Refresh()
        end)
        return group, check
    end
    controller.archivedGroup, controller.archivedCheck = HistoryFilter("Show archived CSR", "showArchived")
    controller.awardedGroup, controller.awardedCheck = HistoryFilter("Show awarded CSR", "showAwarded")
    controller.filterControls = { controller.raidFilter, controller.searchGroup, controller.groupBox, controller.archivedGroup, controller.awardedGroup }
    local filterSettings = { "csrShowRaidFilter", "csrShowSearchFilter", "csrShowGroupFilter", "csrShowArchivedFilter", "csrShowAwardedFilter" }
    controller.flow = {}
    controller.filterDividers = {}
    for index = 1, 2 do
        local divider = UI.CreateContainer(nil, host)
        UI.RegisterSkinnedSurface(divider, "content", nil, {0, 0, 0, 0}, {0.68, 0.54, 0.27, 1})
        UI.JoinSurfaceEdges(divider, true, false); divider:SetHeight(4)
        controller.filterDividers[index] = divider
    end
    controller.headers = {}
    local function OnSort() controller:Sort(this.tableKey, this.sortKey) end
    for index, text in ipairs({ "Player name", "Item", "CSR" }) do
        local header = UI.Table.CreateHeader(page, nil, text, 0, 0, 100, nil, false)
        header.tableKey = "root"; header:SetScript("OnClick", OnSort); controller.headers[index] = header
    end
    controller.playerHeader, controller.itemsHeader, controller.csrHeader = unpack(controller.headers)
    controller.scroll = UI.CreateScrollFrame("BootyRaiderCSRScroll", page, "UIPanelScrollFrameTemplate")
    UI.RegisterSkinnedScrollBar(getglobal("BootyRaiderCSRScrollScrollBar"))
    controller.canvas = UI.CreateContainer(nil, controller.scroll); controller.scroll:SetScrollChild(controller.canvas)
    controller.measure = UI.CreateLabel(page, nil, "ARTWORK", "GameFontHighlightSmall"); controller.measure:SetAlpha(0)
    if controller.measure.SetWordWrap then controller.measure:SetWordWrap(true) end
    controller.empty = UI.CreateLabel(page, nil, "OVERLAY", "GameFontDisableSmall")
    controller.empty:SetText("No matching Soft Reserves.")
    controller.sourceColumns = {
        { field = "no", text = "#", desiredWidth = 30, minimumWidth = 22, fraction = 0.04 },
        { field = "raid", text = "Raid", desiredWidth = 284, minimumWidth = 45, fraction = 0.55 },
        { field = "date", text = "Date", desiredWidth = 100, minimumWidth = 65, fraction = 0.15 },
        { field = "expires", text = "Expires in", desiredWidth = 88, minimumWidth = 54, fraction = 0.12 },
        { field = "status", text = "Status", desiredWidth = 94, minimumWidth = 60, fraction = 0.14 },
    }
    local function SourceLabel(source)
        return tostring(source.id or "-") .. " | " .. tostring(source.raidName or "Other")
    end
    local function ItemText(player)
        local count = (tonumber(player.items) or 0) + (tonumber(player.archivedItems) or 0)
        return ItemLabel(player.itemId, player.itemName) .. (count > 1 and (" x " .. count) or "")
    end
    local function KeyValue(node, field)
        local player = node.player
        if field == "csr" then return player and player.csr or node.csr end
        if field == "count" then return table.getn(node.children or {}) end
        if field == "item" then
            local itemId = player and player.itemId or node.itemId
            local itemName = type(itemId) == "number" and GetItemInfo(itemId) or itemId
            return string.lower(itemName or ("Item " .. tostring(itemId)))
        end
        return string.lower(player and player.name or node.name or "")
    end
    local function SortNodes(values, state, defaultField)
        local field, descending = state and state.field or defaultField or "name", state and state.descending
        table.sort(values, function(a, b)
            local left, right = KeyValue(a, field), KeyValue(b, field)
            if left == right then return a.key < b.key end
            if descending then return left > right end
            return left < right
        end)
    end
    local function SourceValue(source, field)
        if field == "raid" then return source.sortRaid end
        if field == "date" then return tonumber(source.raid.savedAt) or 0 end
        if field == "expires" then return tonumber(source.raid.expiresAt) or 0 end
        if field == "status" then return source.raid.status or "ACTIVE" end
        return source.no
    end
    function controller:Sort(tableKey, field)
        local state = self.sortStates[tableKey]
        if state and state.field == field then state.descending = not state.descending
        else self.sortStates[tableKey] = { field = field, descending = false } end
        self:SortNodes(); self:RefreshLayout()
    end
    function controller:SortNodes()
        SortNodes(self.nodes, self.sortStates["root:" .. self.groupMode], self.groupMode == "item" and "item" or "name")
        for _, group in pairs(self.groups) do SortNodes(group.children, self.sortStates[group.key], self.groupMode == "player" and "item" or "name") end
        for _, node in ipairs(self.pairs) do
            local state = self.sortStates[node.key]
            table.sort(node.sources, function(a, b)
                local field = state and state.field or "no"
                local left, right = SourceValue(a, field), SourceValue(b, field)
                if left == right then return a.no < b.no end
                if state and state.descending then return left > right end
                return left < right
            end)
        end
    end
    function controller:BuildNodes()
        ClearArray(self.nodes); ClearArray(self.pairs)
        for key in pairs(self.groups) do self.groups[key] = nil end
        for _, player in ipairs(self.summary.players) do
            local node = { kind = "pair", key = PairKey(player), player = player, sources = {} }
            for index, raid in ipairs(player.raids or {}) do
                local raidText = SourceLabel(raid)
                local days = math.max(0, math.ceil(((tonumber(raid.expiresAt) or 0) - (self.summary.now or time())) / 86400))
                node.sources[index] = { no = index, raid = raid, sortRaid = string.lower(raidText),
                    texts = { tostring(index), raidText, date("%Y-%m-%d", tonumber(raid.savedAt) or 0), tostring(days) .. "d", (raid.status or "ACTIVE") .. (raid.provisional and " *" or "") } }
            end
            table.insert(self.pairs, node)
            if self.groupMode == "default" then table.insert(self.nodes, node)
            else
                local key = self.groupMode .. ":" .. (self.groupMode == "player" and string.lower(player.name or "") or tostring(player.itemId))
                local group = self.groups[key]
                if not group then
                    group = { kind = "group", key = key, name = player.name, class = player.class, itemId = player.itemId, itemName = player.itemName, children = {}, csr = 0 }
                    self.groups[key] = group; table.insert(self.nodes, group)
                end
                group.csr = group.csr + player.csr; group.provisional = group.provisional or player.provisional; table.insert(group.children, node)
            end
        end
        self:SortNodes()
    end
    function controller:SetGroupBy(value)
        if value ~= "default" and value ~= "player" and value ~= "item" then return end
        self.groupMode = value; self.expandedKey = nil
        self:BuildNodes(); self:RefreshLayout()
    end
    function controller:IsExpanded(node)
        if self.groupMode == "default" then return self.expandedKey == node.key end
        return self.expanded[node.key] and true or false
    end
    function controller:Toggle(node)
        if self.groupMode == "default" then self.expandedKey = self.expandedKey ~= node.key and node.key or nil
        else self.expanded[node.key] = not self.expanded[node.key] end
        self:RefreshLayout()
    end
    local function OnRowClick() if this.node then controller:Toggle(this.node) end end
    function controller:AcquireRow(index)
        if self.rows[index] then return self.rows[index] end
        local row = UI.CreateControl(nil, self.canvas)
        -- Only the fixed-height family heading owns its fill/outline. The
        -- transparent wrapper can grow around independently styled children.
        row.heading = UI.CreateControl(nil, row)
        row.heading:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0); row.heading:SetHeight(24)
        UI.StyleSelectableTableRow(row.heading, false, false)
        row.heading.ownerRow = row
        row.heading:SetScript("OnClick", function() if this.ownerRow.node then controller:Toggle(this.ownerRow.node) end end)
        row.name = UI.CreateLabel(row.heading, nil, "OVERLAY", "GameFontHighlightSmall")
        row.label = UI.CreateLabel(row.heading, nil, "OVERLAY", "GameFontHighlightSmall")
        row.csr = UI.CreateLabel(row.heading, nil, "OVERLAY", "GameFontHighlightSmall")
        row.toggle = UI.CreateLabel(row.heading, nil, "OVERLAY", "GameFontHighlightSmall")
        for _, label in ipairs({row.name, row.label, row.csr, row.toggle}) do ReportFont(label) end
        row.classIcon = UI.CreateClassIcon(row.heading, 16)
        row.iconRegion = UI.CreateTexture(row.heading, nil, "ARTWORK"); row.iconRegion:SetWidth(19); row.iconRegion:SetHeight(19)
        row.itemHit = UI.CreateControl(nil, row.heading); row.itemHit.ownerRow = row
        row.itemHit:SetScript("OnEnter", ItemTooltip)
        row.itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.itemHit:SetScript("OnClick", function() if this.ownerRow.node then controller:Toggle(this.ownerRow.node) end end)
        row:SetScript("OnClick", OnRowClick); self.rows[index] = row
        return row
    end
    function controller:AcquireDetail(index, owner)
        local row = self.detailRows[index]
        if row then row:SetParent(owner); return row end
        row = UI.CreateControl(nil, owner); row.labels = {}; row.headers = {}; row.visibleHeaders = {}
        UI.StyleSelectableTableRow(row, false, false)
        for cell = 1, 5 do
            row.labels[cell] = UI.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
            ReportFont(row.labels[cell])
            local header = UI.Table.CreateHeader(row, nil, "", 0, 0, 20, nil, false)
            header:SetScript("OnClick", OnSort); row.headers[cell] = header
        end
        row.toggle = UI.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall"); ReportFont(row.toggle)
        row.classIcon = UI.CreateClassIcon(row, 16)
        row.iconRegion = UI.CreateTexture(row, nil, "ARTWORK"); row.iconRegion:SetWidth(19); row.iconRegion:SetHeight(19)
        row.itemHit = UI.CreateControl(nil, row); row.itemHit.ownerRow = row
        row.itemHit:SetScript("OnEnter", ItemTooltip)
        row.itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.itemHit:SetScript("OnClick", function() if this.ownerRow.node then controller:Toggle(this.ownerRow.node) end end)
        row.view = UI.CreateIconButton(row, nil, "Interface\\AddOns\\BootyLib\\Assets\\Skins\\Classic\\Icons\\view.tga", 16, 2, UI.Theme.colors.goldIcon)
        UI.AttachTooltip(row.view, "View raid", function()
            return controller.testMode and "Simulated contributions have no saved raid to open." or "Open this saved raid in Raid Statistics."
        end)
        row.archive = UI.CreateIconButton(row, nil, "Interface\\AddOns\\BootyLib\\Assets\\Skins\\Classic\\Icons\\archive.tga", 16, 2, UI.Theme.colors.goldIcon)
        row.archive.ownerRow = row
        UI.AttachTooltip(row.archive, "Archive CSR", "Archive this raid contribution without deleting its history.")
        row.activate = UI.CreateIconButton(row, nil, "Interface\\AddOns\\BootyLib\\Assets\\Skins\\Classic\\Icons\\enable.tga", 16, 2, UI.Theme.colors.goldIcon)
        row.activate.ownerRow = row
        UI.AttachTooltip(row.activate, "Activate CSR", "Restore this contribution while its original 60-day validity remains.")
        local function ChangeArchive()
            local source = this.ownerRow.source
            if not source then return end
            local accepted, reason
            if controller.testMode then
                accepted, reason = Raider.Services.CSRTest.SetSourceArchived(controller.testLab.state, source.id,
                    source.playerName, source.itemId, this == this.ownerRow.archive)
            else
                if not options.canManageHistory or not options.canManageHistory() or not options.setSourceArchived then return end
                accepted, reason = options.setSourceArchived(source.id, source.playerName, source.itemId, this == this.ownerRow.archive, controller.selectedRaids)
            end
            if not accepted and reason then controller.actionError = reason else controller.actionError = nil end
            controller:Refresh()
        end
        row.archive:SetScript("OnClick", ChangeArchive); row.activate:SetScript("OnClick", ChangeArchive)
        row.view:SetScript("OnClick", function() if not controller.testMode and openRaidStatistics and this.raidId then openRaidStatistics(this.raidId) end end)
        row.raidHit = UI.CreateControl(nil, row)
        UI.AttachTooltip(row.raidHit, "Raid contribution", function() return row.source and SourceLabel(row.source) or "" end)
        row:SetScript("OnClick", OnRowClick)
        self.detailRows[index] = row; self.detailLines[index] = row.labels[1]; self.viewButtons[index] = row.view
        return row
    end
    local function SetSourceWidths(width)
        local actionsWidth = (controller.canManageHistory or controller.testMode) and 52 or 32
        local available = math.max(5, math.min(596, width - actionsWidth))
        UI.Table.AllocateColumnWidths(controller.sourceColumns, available)
        return available
    end
    local function AppendDetail(entry, kind, node, source, indent, height)
        entry.count = entry.count + 1
        local detail = entry.details[entry.count]
        if not detail then detail = {}; entry.details[entry.count] = detail end
        detail.kind, detail.node, detail.source, detail.indent = kind, node, source, indent
        detail.y, detail.height = entry.height, height
        entry.height = entry.height + height
    end
    local function AppendSources(entry, node, width, indent)
        AppendDetail(entry, "sourceHeader", node, nil, indent, 26)
        SetSourceWidths(math.max(1, width - indent))
        for index, source in ipairs(node.sources) do
            AppendDetail(entry, "source", node, source, indent, 22)
            entry.details[entry.count].stripe = index
        end
    end
    local function MeasureRows(width, self)
        local total = 0
        ReportFont(self.measure)
        for index, node in ipairs(self.nodes) do
            local entry = self.layoutRows[index]
            if not entry then entry = { details = {} }; self.layoutRows[index] = entry end
            entry.y, entry.node, entry.count, entry.height = total, node, 0, 26
            if self:IsExpanded(node) then
                if node.kind == "pair" then AppendSources(entry, node, width, 16)
                else
                    for _, child in ipairs(node.children) do
                        AppendDetail(entry, "pair", child, nil, 16, 26)
                        if self:IsExpanded(child) then AppendSources(entry, child, width, 32) end
                    end
                end
                if entry.count > 0 and index < table.getn(self.nodes) then entry.height = entry.height + 8 end
            end
            total = total + entry.height
        end
        for index = table.getn(self.layoutRows), table.getn(self.nodes) + 1, -1 do self.layoutRows[index] = nil end
        return total
    end
    local function PanelWidth(frame)
        if frame.bootyWidthOwner and frame.bootyWidthInset then return UI.GetFrameSpan(frame.bootyWidthOwner) - frame.bootyWidthInset end
        return UI.GetFrameSpan(frame)
    end
    local function LayoutDivider(divider, top)
        local panel = host.bootyContentPanel or host
        local width, hostWidth = PanelWidth(panel), PanelWidth(host)
        local pageLeft, panelLeft = page.GetLeft and page:GetLeft(), panel.GetLeft and panel:GetLeft()
        local inset = pageLeft and panelLeft and (pageLeft - panelLeft) or (width - hostWidth) / 2
        divider:ClearAllPoints(); divider:SetPoint("TOPLEFT", page, "TOPLEFT", -inset, -top)
        divider:SetWidth(width)
        UI.JoinSurfaceEdges(divider, true, false, panel.bootyBorderOutsetLeft, panel.bootyBorderOutsetRight)
    end
    function controller:SyncFilterDividers()
        local viewport = page.layoutViewport
        local offset = viewport:GetVerticalScroll()
        local bottom = offset + viewport:GetHeight()
        for index, divider in ipairs(self.filterDividers) do
            local top = index == 1 and self.filterTop or self.filterBottom
            if host:IsShown() and page:IsShown() and top and top >= offset and top + 4 <= bottom then divider:Show() else divider:Hide() end
        end
    end
    local function LayoutContent(width, height, self)
        local available = math.max(80, width - 16)
        self.title:ClearAllPoints(); self.title:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -8)
        UI.FitButtonLabel(self.title, math.max(1, available - 104))
        local settings=BootyRaiderDB or {}
        local hideTitle=settings.csrHideSectionHeader
        if hideTitle then self.title:Hide() else self.title:Show() end
        local descriptionTop=hideTitle and 8 or 42
        local descriptionWidth=hideTitle and math.max(1,available-104) or available
        self.description:SetWidth(descriptionWidth); self.description:SetHeight(0)
        local descriptionHeight=UI.MeasureTextHeight(self.description,descriptionWidth)
        local buttonTop,top=8,descriptionTop+math.max(24,descriptionHeight)+8
        if hideTitle then
            local blockHeight=math.max(descriptionHeight,self.testButton:GetHeight())
            descriptionTop=8+(blockHeight-descriptionHeight)/2
            buttonTop=8+(blockHeight-self.testButton:GetHeight())/2
            top=blockHeight+16
        end
        self.description:ClearAllPoints();self.description:SetPoint("TOPLEFT",page,"TOPLEFT",8,-descriptionTop)
        self.description:SetHeight(descriptionHeight)
        self.testButton:ClearAllPoints();self.testButton:SetPoint("TOPRIGHT",page,"TOPRIGHT",-8,-buttonTop)
        local font, size, flags = self.archivedCheck.label:GetFont()
        self.groupLabel:SetFont(font, size, flags); self.groupLabel:SetWidth(0)
        self.groupLabelWidth = math.ceil(self.groupLabel:GetStringWidth())
        self.groupBox.bootyFlowWidth = self.groupLabelWidth + 4 + 80
        self.groupBy:ClearAllPoints(); self.groupBy:SetPoint("LEFT", self.groupBox, "LEFT", self.groupLabelWidth + 4, 0)
        self.groupBy:SetWidth(80)
        self.archivedCheck.label:SetWidth(0); self.awardedCheck.label:SetWidth(0)
        self.archivedGroup.bootyFlowWidth = 18 + math.ceil(self.archivedCheck.label:GetStringWidth()) + 2
        self.awardedGroup.bootyFlowWidth = 18 + math.ceil(self.awardedCheck.label:GetStringWidth()) + 2
        for index=table.getn(self.flow),1,-1 do table.remove(self.flow,index) end
        for index,control in ipairs(self.filterControls) do
            if settings[filterSettings[index]]~=false then control:Show();table.insert(self.flow,control) else control:Hide() end
        end
        if not self.raidFilter:IsShown() then self.raidPanel:Hide() end
        if not self.groupBox:IsShown() then self.groupBy.panel:Hide() end
        if not self.searchGroup:IsShown() then self.search:ClearFocus() end
        self.filterTop,self.filterBottom=nil,nil
        if table.getn(self.flow)>0 then
            self.filterTop = top
            LayoutDivider(self.filterDividers[1], top)
            self.filterBottom = UI.LayoutFlow(page, self.flow, 8, top + 8, available, 8) + 4
            LayoutDivider(self.filterDividers[2], self.filterBottom)
            top = self.filterBottom + 12
        end
        self.search:SetWidth(math.max(24, self.searchGroup:GetWidth()))
        self.archivedCheck.label:SetWidth(math.max(1, self.archivedGroup:GetWidth() - 18))
        self.archivedCheck.labelHit:SetWidth(math.max(1, self.archivedGroup:GetWidth() - 18))
        self.awardedCheck.label:SetWidth(math.max(1, self.awardedGroup:GetWidth() - 18))
        self.awardedCheck.labelHit:SetWidth(math.max(1, self.awardedGroup:GetWidth() - 18))
        self.headerTop, self.bodyTop = top, top + 24
        self.bodyHeight, self.bodyWidth = math.max(48, height - self.bodyTop - 8), available
        return self.bodyTop + self.bodyHeight + 8
    end
    function controller:Layout() UI.LayoutResponsiveCanvas(page, LayoutContent, self); self:SyncFilterDividers() end
    local previousPageScroll = page.layoutViewport:GetScript("OnVerticalScroll")
    page.layoutViewport:SetScript("OnVerticalScroll", function()
        if previousPageScroll then previousPageScroll() end
        controller:SyncFilterDividers()
    end)
    page:SetScript("OnHide", function() for _, divider in ipairs(controller.filterDividers) do divider:Hide() end end)
    local function HeaderCells(row, fields, widths, tableKey)
        local x = 8
        for index, field in ipairs(fields) do
            local header = row.headers[index]
            header:ClearAllPoints(); header:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            header:SetWidth(widths[index]); header:SetHeight(22)
            header.tableKey, header.sortKey = tableKey, field.field
            header.label:SetText(field.text); header:Show(); x = x + widths[index]
            header.label:SetTextColor(unpack(UI.Theme.colors.goldText))
            row.visibleHeaders[index] = header
        end
        for index = table.getn(row.visibleHeaders), table.getn(fields) + 1, -1 do row.visibleHeaders[index] = nil end
        UI.Table.FitHeaders(row.visibleHeaders, 10 + (UI.GetTextSizeDelta(row) or 0))
    end
    local function ItemIcon(row, itemId, x)
        local owner = row.heading or row
        row.itemId = itemId; row.iconRegion:ClearAllPoints(); row.iconRegion:SetPoint("TOPLEFT", owner, "TOPLEFT", x, -2)
        row.itemHit.itemId, row.itemHit.iconRegion = tonumber(itemId), row.iconRegion
        row.itemHit.itemName = type(itemId) == "string" and itemId or nil
        row.iconRegion:SetTexture(tonumber(itemId) and type(GetItemIcon) == "function" and GetItemIcon(itemId) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.iconRegion:Show(); row.itemHit:Show()
    end
    local function PlayerColor(label, class)
        local settings = BootyRaiderDB or {}
        local key = string.upper(tostring(class or ""))
        local color = settings.csrUseClassColors ~= false and ((RAID_CLASS_COLORS and RAID_CLASS_COLORS[key]) or UI.Theme.classColors[key])
        if color then label:SetTextColor(color.r, color.g, color.b)
        else label:SetTextColor(unpack(UI.Theme.colors.goldText)) end
    end
    local function AccordionLead(row, node, itemMode, x)
        local owner = row.heading or row
        UI.Table.Cell(row.toggle, owner, x, 10, 24, controller:IsExpanded(node) and "-" or "+")
        row.toggle:SetTextColor(unpack(UI.Theme.colors.goldText)); row.toggle:Show()
        local nextX = x + 14
        if itemMode then ItemIcon(row, node.player and node.player.itemId or node.itemId, nextX); nextX = nextX + 24
        else
            local settings = BootyRaiderDB or {}
            local class = node.player and node.player.class or node.class
            local coordinates = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[string.upper(tostring(class or ""))]
            if settings.csrShowClassIcon ~= false and coordinates then
                row.classIcon:ClearAllPoints(); row.classIcon:SetPoint("LEFT", owner, "LEFT", nextX, 0)
                row.classIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
                row.classIcon:SetTexCoord(unpack(coordinates)); row.classIcon:Show(); nextX = nextX + 20
            end
        end
        return nextX
    end
    local function RenderDetail(row, detail, width)
        row.node, row.source, row.kind, row.itemId = nil, detail.source and detail.source.raid, detail.kind, nil
        for index = 1, 5 do ReportFont(row.labels[index]); row.labels[index]:Hide(); row.headers[index]:Hide() end
        row.view:Hide(); row.archive:Hide(); row.activate:Hide(); row.raidHit:Hide(); row.iconRegion:Hide(); row.classIcon:Hide(); row.itemHit:Hide(); row.toggle:Hide()
        if detail.kind == "source" or detail.kind == "sourceHeader" then
            local columnsWidth = SetSourceWidths(width)
            local x = 8
            if detail.kind == "sourceHeader" then
                local widths = {}
                for index, column in ipairs(controller.sourceColumns) do widths[index] = column.width end
                HeaderCells(row, controller.sourceColumns, widths, detail.node.key)
            else
                local raid = detail.source.raid
                for index, column in ipairs(controller.sourceColumns) do
                    local label = row.labels[index]
                    UI.Table.Cell(label, row, x, column.width - 8, row:GetHeight(), detail.source.texts[index])
                    if raid.status == "ARCHIVED" then label:SetTextColor(0.5, 0.5, 0.5)
                    elseif column.field == "status" and raid.status == "AWARDED" then label:SetTextColor(0.2, 1, 0.2)
                    elseif column.field == "status" then label:SetTextColor(1, 1, 0)
                    else label:SetTextColor(1, 1, 1) end
                    label:Show(); x = x + column.width
                end
                row.raidHit:ClearAllPoints(); row.raidHit:SetPoint("LEFT", row, "LEFT", 8 + controller.sourceColumns[1].width, 0)
                row.raidHit:SetWidth(math.max(1, controller.sourceColumns[2].width - 8)); row.raidHit:SetHeight(row:GetHeight()); row.raidHit:Show()
                row.view:ClearAllPoints(); row.view:SetPoint("LEFT", row, "LEFT", columnsWidth + ((controller.canManageHistory or controller.testMode) and 28 or 8), 0)
                row.view.raidId = raid.id; row.view:Show()
                if controller.testMode then row.view:Disable(); row.view:SetAlpha(0.35)
                else row.view:Enable(); row.view:SetAlpha(1) end
                if controller.canManageHistory or controller.testMode then
                    local action = raid.status == "ACTIVE" and row.archive or raid.status == "ARCHIVED" and raid.manuallyArchived and not raid.expired and row.activate or nil
                    if action then action:ClearAllPoints(); action:SetPoint("RIGHT", row.view, "LEFT", -4, 0); action:Show() end
                end
            end
        else
            local player = detail.node.player
            row.node = detail.node
            local itemMode = controller.groupMode == "player"
            local textX = AccordionLead(row, detail.node, itemMode, 8)
            local csrX = math.max(8, math.min(720, controller.renderWidth) - 40 - detail.indent)
            UI.Table.Cell(row.labels[1], row, textX, math.max(1, csrX - textX - 8), 24, itemMode and ItemText(player) or player.name); row.labels[1]:Show()
            PlayerColor(row.labels[1], itemMode and "" or player.class)
            UI.Table.Cell(row.labels[2], row, csrX, 40, 24, tostring(player.csr) .. (player.provisional and " *" or "")); row.labels[2]:Show()
            row.labels[2]:SetTextColor(1, 1, 1)
            if itemMode then
                row.itemHit:ClearAllPoints(); row.itemHit:SetPoint("TOPLEFT", row, "TOPLEFT", 20, 0)
                row.itemHit:SetWidth(math.max(1, csrX - 28)); row.itemHit:SetHeight(24)
            end
        end
    end
    function controller:Render(changed)
        if self.rendering then return end
        self.rendering = true
        self.canManageHistory = options.canManageHistory and options.canManageHistory() and true or false
        if changed or not self.renderWidth then
            local width, total, _, maximum = UI.ResolveScrollLayout(self.bodyWidth, self.bodyHeight, 20, MeasureRows, self)
            self.renderWidth, self.renderHeight, self.renderMaximum = width, total, maximum
        end
        local width = self.renderWidth
        self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -self.bodyTop)
        self.scroll:SetWidth(width); self.scroll:SetHeight(self.bodyHeight)
        self.canvas:SetWidth(width); self.canvas:SetHeight(self.renderHeight)
        local bar = getglobal(self.scroll:GetName() .. "ScrollBar")
        if bar then
            bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", page, "TOPLEFT", 12 + width, -self.bodyTop - 16)
            bar:SetHeight(math.max(1, self.bodyHeight - 32)); bar:SetWidth(16)
        end
        UI.ApplyScrollRange(self.scroll, bar, self.renderMaximum)
        local csrWidth = 40
        local columnsWidth = math.min(720, width)
        local nameWidth = self.groupMode == "default" and math.floor(columnsWidth * 0.30) or math.max(1, columnsWidth - csrWidth - 90)
        local itemWidth = columnsWidth - nameWidth - csrWidth
        local starts, widths = {0, nameWidth, columnsWidth - csrWidth}, {nameWidth, itemWidth, csrWidth}
        local texts, fields
        if self.groupMode == "player" then texts, fields = {"Player", "Items", "CSR"}, {"name", "count", "csr"}
        elseif self.groupMode == "item" then texts, fields = {"Item", "Players", "CSR"}, {"item", "count", "csr"}
        else texts, fields = {width < 420 and "Player" or "Player name", "Item", "CSR"}, {"name", "item", "csr"} end
        for index, header in ipairs(self.headers) do
            header:ClearAllPoints(); header:SetPoint("TOPLEFT", page, "TOPLEFT", 8 + starts[index], -self.headerTop)
            header:SetWidth(widths[index]); header:SetHeight(20); header.label:SetText(texts[index])
            header.label:SetTextColor(unpack(UI.Theme.colors.goldText))
            header.tableKey, header.sortKey = "root:" .. self.groupMode, fields[index]
        end
        UI.Table.FitHeaders(self.headers, 10 + (UI.GetTextSizeDelta(page) or 0))
        local top, bottom = self.scroll:GetVerticalScroll(), self.scroll:GetVerticalScroll() + self.bodyHeight
        for _, detail in ipairs(self.detailRows) do detail:Hide() end
        local used, detailUsed = 0, 0
        for index, entry in ipairs(self.layoutRows) do
            if entry.y >= bottom then break end
            if entry.y + entry.height > top then
                used = used + 1
                local row, node = self:AcquireRow(used), entry.node
                row.node, row.player = node, node.player
                row:ClearAllPoints(); row:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -entry.y)
                row:SetWidth(width); row:SetHeight(entry.height - 2)
                row.heading:SetWidth(width)
                ReportFont(row.name); ReportFont(row.label); ReportFont(row.csr); ReportFont(row.toggle)
                row.iconRegion:Hide(); row.classIcon:Hide(); row.itemHit:Hide(); row.itemId = nil
                local textX = AccordionLead(row, node, not node.player and self.groupMode == "item", 8)
                if node.player then
                    UI.Table.Cell(row.name, row.heading, textX, nameWidth - textX - 8, 24, node.player.name)
                    UI.Table.Cell(row.label, row.heading, nameWidth + 32, itemWidth - 40, 24, ItemText(node.player))
                    UI.Table.Cell(row.csr, row.heading, columnsWidth - csrWidth, csrWidth - 8, 24, tostring(node.player.csr) .. (node.player.provisional and " *" or ""))
                    ItemIcon(row, node.player.itemId, nameWidth + 8)
                    row.itemHit:ClearAllPoints(); row.itemHit:SetPoint("TOPLEFT", row.heading, "TOPLEFT", nameWidth, 0)
                    row.itemHit:SetWidth(itemWidth); row.itemHit:SetHeight(24)
                else
                    local itemMode = self.groupMode == "item"
                    UI.Table.Cell(row.name, row.heading, textX, nameWidth - textX - 8, 24,
                        itemMode and ItemLabel(node.itemId, node.itemName) or node.name)
                    UI.Table.Cell(row.label, row.heading, nameWidth + 8, itemWidth - 16, 24, tostring(table.getn(node.children)))
                    UI.Table.Cell(row.csr, row.heading, columnsWidth - csrWidth, csrWidth - 8, 24, tostring(node.csr) .. (node.provisional and " *" or ""))
                    if itemMode then
                        row.itemHit:ClearAllPoints(); row.itemHit:SetPoint("TOPLEFT", row.heading, "TOPLEFT", 20, 0)
                        row.itemHit:SetWidth(math.max(1, nameWidth - 20)); row.itemHit:SetHeight(24)
                    end
                end
                PlayerColor(row.name, node.player and node.player.class or self.groupMode == "player" and node.class)
                row.label:SetTextColor(1, 1, 1); row.csr:SetTextColor(1, 1, 1)
                StyleReportRow(row.heading, index, true, false)
                for detailIndex = 1, entry.count do
                    local detail = entry.details[detailIndex]
                    if entry.y + detail.y + detail.height > top and entry.y + detail.y < bottom then
                        detailUsed = detailUsed + 1
                        local child = self:AcquireDetail(detailUsed, row)
                        child:ClearAllPoints(); child:SetPoint("TOPLEFT", row, "TOPLEFT", detail.indent, -detail.y)
                        child:SetWidth(math.max(1, width - detail.indent)); child:SetHeight(detail.height - 2)
                        RenderDetail(child, detail, child:GetWidth())
                        StyleReportRow(child, detail.kind == "source" and detail.stripe or detailIndex,
                            detail.kind == "pair", detail.kind == "sourceHeader")
                        child:Show()
                    end
                end
                row:Show()
            end
        end
        for index = used + 1, table.getn(self.rows) do self.rows[index].node = nil; self.rows[index].player = nil; self.rows[index]:Hide() end
        self.empty:ClearAllPoints(); self.empty:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -self.bodyTop - 4); self.empty:SetWidth(width)
        if table.getn(self.nodes) == 0 then self.empty:Show() else self.empty:Hide() end
        self.rendering = false
    end
    function controller:RefreshLayout()
        if not host:IsShown() then return end
        Raider.Diagnostics.Count("uiRefreshes"); self:Layout(); self:Render(true)
    end
    function controller:Refresh()
        if not host:IsShown() then return end
        self.visibility.showArchived, self.visibility.showAwarded = self.showArchived, self.showAwarded
        if self.testMode then
            local state = self.testLab.state
            Raider.Services.CSR.BuildSummary(state.entries, nil, state.now, self.summary, nil, nil, self.search:GetText(), self.visibility)
        else
            local service = Raider.Services.RaidCSR or Raider.Services.CSR
            service.BuildSummary(getEntries(), nil, time(), self.summary, getRosterData(), self.selectedRaids, self.search:GetText(), self.visibility)
        end
        self.description:SetText(self.descriptionText .. (self.summary.provisional and "\n* Provisional: unresolved raid changes may affect these points." or "")
            .. (self.actionError and ("\n|cffff5555" .. tostring(self.actionError) .. "|r") or ""))
        self:BuildNodes(); self:RefreshLayout()
    end
    controller.scroll:SetScript("OnVerticalScroll", function() this:SetVerticalScroll(arg1 or 0); controller:Render() end)
    return { frame = page, page = page, Show = function(self) host:Show(); page:Show(); controller:Refresh() end,
        Hide = function(self)
            controller.testMode = false
            controller.testLab:Hide(); controller.raidPanel:Hide(); controller.raidDismiss:Hide()
            controller.groupBy.panel:Hide(); controller.groupBy.panel.dismiss:Hide(); page:Hide(); host:Hide()
        end,
        Refresh = function(self) controller:Refresh() end,
        OnResize = function(self) controller.raidPanel:Hide(); controller.groupBy.panel:Hide(); controller:RefreshLayout() end }
end
