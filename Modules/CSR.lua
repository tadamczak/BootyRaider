local Raider = BootyRaider
local UI = Raider.UI.Components

Raider.Modules = Raider.Modules or {}
local CSR = {}
Raider.Modules.CSR = CSR

local function CreateTestLab(owner, onChanged, onExit)
    local dialog = UI.CreateContainer("BootyRaiderCSRTestLab", UIParent)
    dialog:SetWidth(500); dialog:SetHeight(420); dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dialog:SetResizable(true); dialog:SetMinResize(280, 240); dialog:SetMaxResize(850, 700)
    if dialog.SetClampedToScreen then dialog:SetClampedToScreen(true) end
    dialog.title = UI.CreateHeading(dialog, "CSR Test Lab", 1, "gold", "csr")
    dialog.close = UI.CreateWindowButton(dialog, nil, "close")
    UI.Window.StyleProjectDialog(dialog)
    dialog.host = UI.CreateContainer(nil, dialog)
    dialog.body = UI.CreateResponsiveCanvas(dialog.host, "BootyRaiderCSRTestLabBody")
    local body = dialog.body
    dialog.help = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.help:SetText("Temporary simulation: add players and reserves, award items, change rank or advance time. Saved raids are unchanged.")
    dialog.state = Raider.Services.CSRTest.Create(); dialog.summary = { players = {} }
    dialog.status = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.item = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.result = UI.CreateLabel(body, nil, "OVERLAY", "GameFontNormal")
    dialog.logTitle = UI.CreateLabel(body, nil, "OVERLAY", "GameFontNormal")
    dialog.logTitle:SetText("Simulation log")
    dialog.logLines = {}
    for index = 1, 5 do dialog.logLines[index] = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall") end
    local function Action(text, width, callback)
        local button = UI.CreateButton(body, nil, text, width, 26)
        UI.StyleActionButton(button); button.bootyFlowWidth = width
        button:SetScript("OnClick", function() callback(dialog.state); dialog:Refresh() end)
        return button
    end
    dialog.actions = {
        Action("Add player", 90, Raider.Services.CSRTest.AddPlayer),
        Action("Add unsuccessful SR", 142, Raider.Services.CSRTest.AddMissedReserve),
        Action("Award item", 94, Raider.Services.CSRTest.AwardItem),
        Action("Next item", 84, Raider.Services.CSRTest.NextItem),
        Action("Toggle rank", 94, Raider.Services.CSRTest.ToggleRank),
        Action("+7 days", 76, function(state) Raider.Services.CSRTest.AdvanceDays(state, 7) end),
    }
    dialog.reset = UI.CreateButton(dialog, nil, "Reset Test", 90, 26)
    dialog.exit = UI.CreateButton(dialog, nil, "Exit Test", 80, 26)
    UI.StyleActionButton(dialog.reset); UI.StyleActionButton(dialog.exit)
    dialog.exit:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 8)
    dialog.reset:SetPoint("RIGHT", dialog.exit, "LEFT", -8, 0)
    local function Exit() dialog:Hide(); if onExit then onExit() end end
    dialog.close:SetScript("OnClick", Exit); dialog.exit:SetScript("OnClick", Exit)
    dialog.reset:SetScript("OnClick", function() Raider.Services.CSRTest.Reset(dialog.state); dialog:Refresh() end)
    dialog.grip = UI.CreateControl(nil, dialog)
    dialog.grip:SetWidth(12); dialog.grip:SetHeight(12); dialog.grip:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", 0, 0)
    dialog.grip:SetFrameLevel(dialog:GetFrameLevel()+100)
    dialog.grip:SetScript("OnMouseDown", function() dialog:StartSizing("BOTTOMRIGHT") end)
    dialog.grip:SetScript("OnMouseUp", function() dialog:StopMovingOrSizing() end)
    local function LayoutContent(width)
        local y = 0
        local function Line(line)
            line:ClearAllPoints(); line:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            line:SetWidth(width); line:SetHeight(0); line:SetJustifyH("LEFT")
            if line.SetWordWrap then line:SetWordWrap(true) end
            y = y + math.max(16, UI.MeasureTextHeight(line, width)) + 8
        end
        Line(dialog.help); Line(dialog.status); Line(dialog.item); Line(dialog.result)
        y = UI.LayoutFlow(body, dialog.actions, 0, y, width, 8) + 8
        Line(dialog.logTitle)
        for i = 1, table.getn(dialog.logLines) do
            if dialog.logLines[i]:GetText() ~= "" then Line(dialog.logLines[i]); dialog.logLines[i]:Show() else dialog.logLines[i]:Hide() end
        end
        return y
    end
    function dialog:Layout()
        self.host:ClearAllPoints(); self.host:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -36)
        self.host:SetWidth(self:GetWidth()-16); self.host:SetHeight(self:GetHeight()-78)
        UI.LayoutResponsiveCanvas(body, LayoutContent)
    end
    dialog:SetScript("OnSizeChanged", function() dialog:Layout() end)
    function dialog:Refresh()
        Raider.Services.CSRTest.BuildSummary(self.state, self.summary)
        local totalItems, totalCsr = 0, 0
        for _, player in ipairs(self.summary.players) do totalItems=totalItems+player.items; totalCsr=totalCsr+player.csr end
        local selected = self.state.currentPlayer
        self.status:SetText("Player: " .. (selected or "none") .. "   Rank: " .. (selected and self.state.ranks[selected] or "-") .. "   Date: " .. date("%Y-%m-%d", self.state.now))
        self.item:SetText("Item: " .. UI.GetItemLabel(Raider.Services.CSRTest.GetItemId(self.state)))
        self.result:SetText("Rows: " .. table.getn(self.summary.players) .. "   Reserves: " .. totalItems .. "   CSR: " .. totalCsr)
        for i=1,table.getn(self.logLines) do self.logLines[i]:SetText(self.state.log[i] or "") end
        self:Layout()
        if onChanged then onChanged() end
    end
    function dialog:Open() self:Refresh(); self:Show() end
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

local reportRowColor, reportSectionColor = {1, 1, 1}, {0.015, 0.015, 0.015}
local function ReportFont(label)
    local font, _, flags = label:GetFont()
    label:SetFont(font, 10 + (UI.GetTextSizeDelta(label:GetParent()) or 0), flags)
end

local function StyleReportRow(row, index, accordion, header)
    UI.SetRowColor(row, accordion and reportSectionColor or reportRowColor,
        accordion and 1 or header and 0 or math.mod(index, 2) == 0 and 0.14 or 0.025)
    UI.SetProjectButtonOutline(row, accordion)
    row.bootyTableRowHover:Hide(); row.bootyTableRowSelection:Hide()
    row.bootyTableRowSelected = false; row.bootyTableRowHovered = nil
    row:EnableMouse(not header)
end

function CSR.Create(host, getEntries, getRules, getRosterData, openRaidStatistics)
    local page = UI.CreateResponsiveCanvas(host, "BootyRaiderCSRPage")
    local controller = { page = page, rows = {}, detailRows = {}, detailLines = {}, viewButtons = {},
        summary = { players = {} }, selectedRaids = {}, expanded = {}, sortStates = {},
        nodes = {}, pairs = {}, groups = {}, layoutRows = {}, groupMode = "default", showArchived = false }
    page.csrController = controller; host.csrController = controller
    local raidNames = Raider.Services.RaidStatistics.GetRaidNames()
    for _, name in ipairs(raidNames) do controller.selectedRaids[name] = true end
    controller.testLab = CreateTestLab(page, function() controller.testMode = true; controller:Refresh() end,
        function() controller.testMode = false; controller:Refresh() end)
    controller.title = UI.CreateHeading(page, "CSR", 1, "gold", "csr")
    controller.description = UI.CreateLabel(page, nil, "OVERLAY", "GameFontHighlightSmall")
    controller.description:SetJustifyH("LEFT")
    controller.description:SetText("Unsuccessful Soft Reserves. Each miss grants 10 CSR for 60 days. Archived reserves remain available for reference and grant no CSR.")
    controller.testButton = UI.CreateButton(page, nil, "CSR Test Lab", 96, 22)
    UI.StyleActionButton(controller.testButton)
    controller.testButton:SetScript("OnClick", function() controller.testLab:Open() end)
    controller.raidFilter = UI.CreateDropdownButton(page, nil, "Raid", 130)
    controller.raidFilter.bootyFlowWidth = 130; controller.raidFilter:SetHeight(26)
    controller.raidPanel = UI.CreateDropdownPanel(page, controller.raidFilter, 190, 178, 20)
    controller.raidDismiss = controller.raidPanel.dismiss
    controller.raidFilter:SetScript("OnClick", function()
        if controller.raidPanel:IsVisible() then controller.raidPanel:Hide() else controller.raidPanel:Show() end
    end)
    UI.FilterPanel.Refresh(controller.raidPanel, raidNames, controller.selectedRaids, function() controller:Refresh() end, true, true)
    controller.raidChecks = controller.raidPanel.options
    controller.searchGroup = UI.CreateContainer(nil, page)
    controller.searchGroup:SetWidth(162); controller.searchGroup:SetHeight(26); controller.searchGroup.bootyFlowWidth = 162
    controller.search = UI.CreateFramedEditBox(controller.searchGroup, nil, 162)
    controller.search:SetPoint("LEFT", controller.searchGroup, "LEFT", 0, 0); controller.search:SetHeight(22)
    controller.search:SetAutoFocus(false)
    controller.search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    controller.search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    controller.search:SetScript("OnTextChanged", function() controller:Refresh() end)
    UI.AttachPlaceholder(controller.search, "Search...")
    controller.groupBox = UI.CreateContainer(nil, page)
    controller.groupBox:SetWidth(182); controller.groupBox:SetHeight(26); controller.groupBox.bootyFlowWidth = 182
    local groupLabel
    groupLabel, controller.groupBy = UI.CreateChoiceField({ parent = controller.groupBox, label = "Group By", x = 0, y = 0,
        buttonOffset = 62, width = 120, height = 76, firstY = -5, step = 22, initialText = "Default",
        choices = {{ value = "default", text = "Default" }, { value = "player", text = "Player" }, { value = "item", text = "Item" }},
        getValue = function() return controller.groupMode end,
        onSelect = function(value) controller:SetGroupBy(value) end })
    groupLabel:ClearAllPoints(); groupLabel:SetPoint("LEFT", controller.groupBox, "LEFT", 0, 0)
    controller.groupBy:SetHeight(26)
    controller.archivedGroup = UI.CreateContainer(nil, page)
    controller.archivedGroup:SetWidth(180); controller.archivedGroup:SetHeight(26); controller.archivedGroup.bootyFlowWidth = 180
    controller.archivedCheck = UI.CreateCheckButton(nil, controller.archivedGroup, "UICheckButtonTemplate")
    controller.archivedCheck:SetPoint("LEFT", controller.archivedGroup, "LEFT", 0, 0)
    controller.archivedCheck:SetWidth(22); controller.archivedCheck:SetHeight(22); controller.archivedCheck:SetChecked(false)
    controller.archivedCheck.label = UI.CreateLabel(controller.archivedGroup, nil, "OVERLAY", "GameFontHighlightSmall")
    controller.archivedCheck.label:SetPoint("LEFT", controller.archivedCheck, "RIGHT", 2, 0)
    controller.archivedCheck.label:SetText("Show archived CSR")
    controller.archivedCheck:SetScript("OnClick", function()
        controller.showArchived = this:GetChecked() and true or false; controller:Refresh()
    end)
    controller.archivedCheck.labelHit = UI.CreateControl(nil, controller.archivedGroup)
    controller.archivedCheck.labelHit:SetPoint("LEFT", controller.archivedCheck, "RIGHT", 0, 0)
    controller.archivedCheck.labelHit:SetWidth(156); controller.archivedCheck.labelHit:SetHeight(26)
    controller.archivedCheck.labelHit:SetScript("OnClick", function()
        local check = controller.archivedCheck; check:SetChecked(not check:GetChecked())
        controller.showArchived = check:GetChecked() and true or false; controller:Refresh()
    end)
    controller.flow = { controller.raidFilter, controller.searchGroup, controller.groupBox, controller.archivedGroup }
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
        { field = "raid", text = "Raid", desiredWidth = 300, minimumWidth = 45, fraction = 0.55 },
        { field = "date", text = "Date", desiredWidth = 92, minimumWidth = 65, fraction = 0.15 },
        { field = "expires", text = "Expires in", desiredWidth = 74, minimumWidth = 54, fraction = 0.12 },
        { field = "status", text = "Status", desiredWidth = 82, minimumWidth = 60, fraction = 0.14 },
    }
    local function SourceLabel(source)
        return tostring(source.id or "-") .. " | " .. tostring(source.raidName or "Other")
    end
    local function ItemText(player)
        local count = (tonumber(player.items) or 0) + (tonumber(player.archivedItems) or 0)
        return UI.GetItemLabel(player.itemId) .. (count > 1 and (" x " .. count) or "")
    end
    local function KeyValue(node, field)
        local player = node.player
        if field == "csr" then return player and player.csr or node.csr end
        if field == "count" then return table.getn(node.children or {}) end
        if field == "item" then
            local itemId = player and player.itemId or node.itemId
            local itemName = GetItemInfo(itemId)
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
                    texts = { tostring(index), raidText, date("%Y-%m-%d", tonumber(raid.savedAt) or 0), tostring(days) .. "d", raid.status or "ACTIVE" } }
            end
            table.insert(self.pairs, node)
            if self.groupMode == "default" then table.insert(self.nodes, node)
            else
                local key = self.groupMode .. ":" .. (self.groupMode == "player" and string.lower(player.name or "") or tostring(player.itemId))
                local group = self.groups[key]
                if not group then
                    group = { kind = "group", key = key, name = player.name, itemId = player.itemId, children = {}, csr = 0 }
                    self.groups[key] = group; table.insert(self.nodes, group)
                end
                group.csr = group.csr + player.csr; table.insert(group.children, node)
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
        for _, label in ipairs({row.name, row.label, row.csr}) do ReportFont(label) end
        row.iconRegion = UI.CreateTexture(row.heading, nil, "ARTWORK"); row.iconRegion:SetWidth(19); row.iconRegion:SetHeight(19)
        row.itemHit = UI.CreateControl(nil, row.heading); row.itemHit.ownerRow = row
        row.itemHit:SetScript("OnEnter", function() UI.ShowItemTooltip(this) end)
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
        row.iconRegion = UI.CreateTexture(row, nil, "ARTWORK"); row.iconRegion:SetWidth(19); row.iconRegion:SetHeight(19)
        row.itemHit = UI.CreateControl(nil, row); row.itemHit.ownerRow = row
        row.itemHit:SetScript("OnEnter", function() UI.ShowItemTooltip(this) end)
        row.itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.itemHit:SetScript("OnClick", function() if this.ownerRow.node then controller:Toggle(this.ownerRow.node) end end)
        row.view = UI.CreateButton(row, nil, "View", 48, 20); UI.StyleActionButton(row.view); row.view:SetHeight(20)
        row.view:SetScript("OnClick", function() if openRaidStatistics and this.raidId then openRaidStatistics(this.raidId) end end)
        row:SetScript("OnClick", OnRowClick)
        self.detailRows[index] = row; self.detailLines[index] = row.labels[1]; self.viewButtons[index] = row.view
        return row
    end
    local function SetSourceWidths(width)
        UI.Table.AllocateColumnWidths(controller.sourceColumns, math.max(5, width - 72))
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
            local raidWidth = math.max(1, controller.sourceColumns[2].width - 8)
            controller.measure:SetWidth(raidWidth); controller.measure:SetText(source.texts[2])
            local height = math.max(24, UI.MeasureTextHeight(controller.measure, raidWidth) + 8)
            AppendDetail(entry, "source", node, source, indent, height + 2)
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
                    AppendDetail(entry, "pairHeader", node, nil, 16, 26)
                    for _, child in ipairs(node.children) do
                        AppendDetail(entry, "pair", child, nil, 16, 26)
                        if self:IsExpanded(child) then AppendSources(entry, child, width, 32) end
                    end
                end
            end
            total = total + entry.height
        end
        for index = table.getn(self.layoutRows), table.getn(self.nodes) + 1, -1 do self.layoutRows[index] = nil end
        return total
    end
    local function LayoutContent(width, height, self)
        local available = math.max(80, width - 16)
        self.title:ClearAllPoints(); self.title:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -8)
        UI.FitButtonLabel(self.title, math.max(1, available - 104))
        self.testButton:ClearAllPoints(); self.testButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -8)
        self.description:ClearAllPoints(); self.description:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -42)
        self.description:SetWidth(available); self.description:SetHeight(0)
        local top = 42 + math.max(24, UI.MeasureTextHeight(self.description, available)) + 8
        top = UI.LayoutFlow(page, self.flow, 8, top, available, 8) + 8
        self.search:SetWidth(math.max(24, self.searchGroup:GetWidth()))
        self.groupBy:SetWidth(math.max(24, self.groupBox:GetWidth() - 62))
        self.archivedCheck.label:SetWidth(math.max(1, self.archivedGroup:GetWidth() - 24))
        self.archivedCheck.labelHit:SetWidth(math.max(1, self.archivedGroup:GetWidth() - 22))
        self.headerTop, self.bodyTop = top, top + 24
        self.bodyHeight, self.bodyWidth = math.max(48, height - self.bodyTop - 8), available
        return self.bodyTop + self.bodyHeight + 8
    end
    function controller:Layout() UI.LayoutResponsiveCanvas(page, LayoutContent, self) end
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
        row.itemHit.itemId, row.itemHit.iconRegion = itemId, row.iconRegion
        row.iconRegion:SetTexture(type(GetItemIcon) == "function" and GetItemIcon(itemId) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.iconRegion:Show(); row.itemHit:Show()
    end
    local function RenderDetail(row, detail, width)
        row.node, row.source, row.kind, row.itemId = nil, detail.source and detail.source.raid, detail.kind, nil
        for index = 1, 5 do ReportFont(row.labels[index]); row.labels[index]:Hide(); row.headers[index]:Hide() end
        row.view:Hide(); row.iconRegion:Hide(); row.itemHit:Hide()
        if detail.kind == "source" or detail.kind == "sourceHeader" then
            SetSourceWidths(width)
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
                    label:SetTextColor(1, 1, 1)
                    if index == 2 and label.SetWordWrap then label:SetWordWrap(true) end
                    label:Show(); x = x + column.width
                end
                row.view:ClearAllPoints(); row.view:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.view.raidId = raid.id; row.view:Show()
            end
        elseif detail.kind == "pairHeader" then
            HeaderCells(row, {{field = controller.groupMode == "player" and "item" or "name", text = controller.groupMode == "player" and "Item" or "Player"},
                {field = "csr", text = "CSR"}}, {width - 64, 48}, detail.node.key)
        else
            local player = detail.node.player
            row.node = detail.node
            local prefix = controller:IsExpanded(detail.node) and "- " or "+ "
            local label = controller.groupMode == "player" and ItemText(player) or player.name
            UI.Table.Cell(row.labels[1], row, 8, width - 64, 24, prefix .. label); row.labels[1]:Show()
            row.labels[1]:SetTextColor(unpack(UI.Theme.colors.goldText))
            UI.Table.Cell(row.labels[2], row, width - 48, 40, 24, tostring(player.csr)); row.labels[2]:Show()
            row.labels[2]:SetTextColor(1, 1, 1)
            if controller.groupMode == "player" then
                ItemIcon(row, player.itemId, 8)
                UI.Table.Cell(row.labels[1], row, 32, width - 88, 24, prefix .. label)
                row.itemHit:ClearAllPoints(); row.itemHit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                row.itemHit:SetWidth(width - 56); row.itemHit:SetHeight(24)
            end
        end
    end
    function controller:Render(changed)
        if self.rendering then return end
        self.rendering = true
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
        local nameWidth = self.groupMode == "default" and math.floor(width * 0.32) or math.max(1, width - csrWidth - 90)
        local itemWidth = width - nameWidth - csrWidth
        local starts, widths = {0, nameWidth, width - csrWidth}, {nameWidth, itemWidth, csrWidth}
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
                ReportFont(row.name); ReportFont(row.label); ReportFont(row.csr)
                row.iconRegion:Hide(); row.itemHit:Hide(); row.itemId = nil
                local prefix = self:IsExpanded(node) and "- " or "+ "
                if node.player then
                    UI.Table.Cell(row.name, row.heading, 8, nameWidth - 16, 24, prefix .. node.player.name)
                    UI.Table.Cell(row.label, row.heading, nameWidth + 32, itemWidth - 40, 24, ItemText(node.player))
                    UI.Table.Cell(row.csr, row.heading, width - csrWidth, csrWidth - 8, 24, tostring(node.player.csr))
                    ItemIcon(row, node.player.itemId, nameWidth + 8)
                    row.itemHit:ClearAllPoints(); row.itemHit:SetPoint("TOPLEFT", row.heading, "TOPLEFT", nameWidth, 0)
                    row.itemHit:SetWidth(itemWidth); row.itemHit:SetHeight(24)
                else
                    local itemMode = self.groupMode == "item"
                    UI.Table.Cell(row.name, row.heading, itemMode and 32 or 8, nameWidth - (itemMode and 40 or 16), 24,
                        prefix .. (itemMode and UI.GetItemLabel(node.itemId) or node.name))
                    UI.Table.Cell(row.label, row.heading, nameWidth + 8, itemWidth - 16, 24, tostring(table.getn(node.children)))
                    UI.Table.Cell(row.csr, row.heading, width - csrWidth, csrWidth - 8, 24, tostring(node.csr))
                    if itemMode then
                        ItemIcon(row, node.itemId, 8)
                        row.itemHit:ClearAllPoints(); row.itemHit:SetPoint("TOPLEFT", row.heading, "TOPLEFT", 0, 0)
                        row.itemHit:SetWidth(nameWidth); row.itemHit:SetHeight(24)
                    end
                end
                row.name:SetTextColor(unpack(UI.Theme.colors.goldText))
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
                            detail.kind == "pair", detail.kind == "sourceHeader" or detail.kind == "pairHeader")
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
        if self.testMode then
            local state = self.testLab.state
            Raider.Services.CSR.BuildSummary(state.entries, nil, state.now, self.summary, nil, nil, self.search:GetText(), self.showArchived)
        else
            Raider.Services.CSR.BuildSummary(getEntries(), nil, time(), self.summary, getRosterData(), self.selectedRaids, self.search:GetText(), self.showArchived)
        end
        self:BuildNodes(); self:RefreshLayout()
    end
    controller.scroll:SetScript("OnVerticalScroll", function() this:SetVerticalScroll(arg1 or 0); controller:Render() end)
    return { frame = page, page = page, Show = function(self) host:Show(); page:Show(); controller:Refresh() end,
        Hide = function(self)
            controller.testLab:Hide(); controller.raidPanel:Hide(); controller.raidDismiss:Hide()
            controller.groupBy.panel:Hide(); controller.groupBy.panel.dismiss:Hide(); page:Hide(); host:Hide()
        end,
        Refresh = function(self) controller:Refresh() end,
        OnResize = function(self) controller.raidPanel:Hide(); controller.groupBy.panel:Hide(); controller:RefreshLayout() end }
end
