local Raider = BootyRaider
local Match = Raider.Core and Raider.Core.Compatibility and Raider.Core.Compatibility.Match or string.match

Raider.Modules.RaidManagement = Raider.Modules.RaidManagement or {}
local RaidManagement = Raider.Modules.RaidManagement

local function GroupSettings(page)
    return page and page.groupSettings or BootyRaiderDB
end

function RaidManagement.ResetIssueAttention(page)
    local button = page.classicIssues
    if not button then return end
    button.mosIssueKeys = nil; button.mosIssueScratch = nil
    Raider.UI.Components.SetAttentionPulse(button, false)
end

function RaidManagement.UpdateIssueAttention(button, issues)
    local previous, current = button.mosIssueKeys or {}, button.mosIssueScratch or {}
    for key in pairs(current) do current[key] = nil end
    local newIssue, count = false, 0
    local groups = {issues.unmatchedNames, issues.missingNames, issues.invalidNames}
    for category = 1, 3 do
        for index = 1, table.getn(groups[category] or {}) do
            local key = category .. ":" .. groups[category][index]
            current[key] = true; count = count + 1
            if not previous[key] then newIssue = true end
        end
    end
    button.mosIssueKeys = current; button.mosIssueScratch = previous
    Raider.UI.Components.SetAttentionPulse(button, count > 0 and (newIssue or button.mosAttentionPending))
end

function RaidManagement.AttachReyCoinAdd(view, refresh)
    local function Submit()
        local name = string.gsub(view.reyCoinInput:GetText() or "", "^%s*(.-)%s*$", "%1")
        if name == "" then view.reyCoinFeedback:SetText("Enter a player name."); return end
        local item = view.reyCoinItem and string.gsub(view.reyCoinItem:GetText() or "", "^%s*(.-)%s*$", "%1") or ""
        if not Raider.Services.Raid.SetReyCoinUsage(name, item ~= "" and item or nil, true) then
            view.reyCoinFeedback:SetText("Player not found in this raid."); return
        end
        view.reyCoinFeedback:SetText(""); view.reyCoinInput:SetText(""); view.reyCoinInput:ClearFocus(); if view.reyCoinItem then view.reyCoinItem:SetText(""); view.reyCoinItem:ClearFocus() end; refresh()
    end
    view.reyCoinAdd:SetScript("OnClick", Submit)
    view.reyCoinInput:SetScript("OnEnterPressed", Submit)
    if view.reyCoinItem then view.reyCoinItem:SetScript("OnEnterPressed", Submit) end
end

local function RestoreHeaderFont(control)
    local label = control.label or control
    if not label.GetFont then return end
    local font, size, flags = label:GetFont()
    control.mosFitFontSize = control.mosFitFontSize or size
    label:SetFont(font, control.mosFitFontSize, flags)
    label:SetWidth(0)
end

function RaidManagement.CreateChrome(page, callbacks)
    local view = {}
    view.classicToolbar = Raider.UI.Components.CreateContainer(nil, page)
    page.classicToolbar = view.classicToolbar
    view.classicToolbar:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -48); view.classicToolbar:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -48); view.classicToolbar:SetHeight(42)
    view.classicToolbar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } }); view.classicToolbar:SetBackdropColor(0, 0, 0, 0); view.classicToolbar:SetBackdropBorderColor(0, 0, 0, 0)
    Raider.UI.Components.RegisterSkinnedSurface(view.classicToolbar, "title", { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }); view.classicToolbar:Hide()
    Raider.UI.Components.SetSurfaceHorizontalBorders(view.classicToolbar, true, true)
    view.classicToolbar:SetFrameLevel(page:GetFrameLevel())
    view.classicSummary = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontDisableSmall")
    view.classicSummary:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -31); view.classicSummary:SetWidth(245); view.classicSummary:SetHeight(14); view.classicSummary:SetJustifyH("LEFT"); view.classicSummary:Hide()
    page.classicSummary = view.classicSummary
    view.title = Raider.UI.Components.CreateHeading(page, "", 1, "gold", "raids")
    view.title:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -8); view.title:SetHeight(18); view.title:SetText("Raid")
    view.classicRaidName = Raider.UI.Components.CreateHeading(page, "", 1, "gold")
    view.classicRaidName:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -10); view.classicRaidName:SetWidth(120); view.classicRaidName:SetJustifyH("LEFT"); view.classicRaidName:Hide()
    view.classicMeta = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontHighlightSmall")
    view.classicMeta:SetPoint("LEFT", view.classicRaidName, "RIGHT", 10, 0); view.classicMeta:SetWidth(82); view.classicMeta:SetJustifyH("LEFT"); view.classicMeta:Hide()
    view.classicSaved = Raider.UI.Components.CreateButton(page, nil, "Not saved yet", 108, 24)
    view.classicSaved:SetPoint("LEFT", view.classicMeta, "RIGHT", 8, 0); Raider.UI.Components.SetClassicButtonGold(view.classicSaved, true); view.classicSaved:Hide()
    Raider.UI.Components.AttachTooltip(view.classicSaved, "Raid save status", function() return view.classicSaved.mosRaidSavedText or view.classicSaved:GetText() end)
    Raider.UI.Components.SetClassicButtonLabelOffset(view.classicSaved, 2)
    Raider.UI.Components.SetButtonLabelInsets(view.classicSaved, 8, 4)
    view.classicIssues = Raider.UI.Components.CreateButton(page, nil, "", 96, 24)
    view.classicIssues:SetPoint("LEFT", view.classicSaved, "RIGHT", 8, 0); Raider.UI.Components.SetClassicButtonIcon(view.classicIssues, "warning_triangle", 13, 7, 1); Raider.UI.Components.SetClassicButtonGold(view.classicIssues, true); view.classicIssues:Hide()
    Raider.UI.Components.SetClassicButtonLabelOffset(view.classicIssues, 2, 4)
    Raider.UI.Components.AttachTooltip(view.classicIssues, "Raid issues", "Review missing, invalid or unmatched Soft Reserves.")
    view.classicIssues:SetScript("OnClick", function()
        Raider.UI.Components.SetAttentionPulse(view.classicIssues, false)
        if page.softReserveWarning then page.softReserveWarning.userDismissed = false; page.softReserveWarning.userMinimized = false; page.softReserveWarning.forceExpanded = true end
        if page.missingSoftReserveWarning then page.missingSoftReserveWarning.userDismissed = false; page.missingSoftReserveWarning.userMinimized = false; page.missingSoftReserveWarning.forceExpanded = true end
        if page.invalidSoftReserveWarning then page.invalidSoftReserveWarning.userDismissed = false; page.invalidSoftReserveWarning.userMinimized = false; page.invalidSoftReserveWarning.forceExpanded = true end
        if page.resizeRefresh then page.resizeRefresh() end
    end)
    page.classicRaidName = view.classicRaidName; page.classicMeta = view.classicMeta; page.classicSaved = view.classicSaved; page.classicIssues = view.classicIssues
    view.modeButton = Raider.UI.Components.CreateButton(page, "BootyRaiderRaidModeButton", "LM Mode", 96, 22)
    view.modeButton.mosClassicReserveIconSpace = true
    Raider.UI.Components.SetClassicButtonIcon(view.modeButton, "loot_tools", 13, 7, 0)
    Raider.UI.Components.AttachGoldHoverBorder(view.modeButton, 0.35, 0.35, 0.35, 1)
    view.modeButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -8)
    view.modeButton:SetScript("OnClick", callbacks.toggleLootMaster); view.modeButton:Hide()
    view.minimizeButton = Raider.UI.Components.CreateWindowButton(page, "BootyRaiderRaidMinimizeButton", "minimize")
    view.minimizeButton:SetScript("OnClick", callbacks.toggleMinimize); view.minimizeButton:Hide()
    page.lmConfigOpen = false
    view.lmConfigPanel = Raider.UI.Components.CreateContainer(nil, page)
    view.lmConfigPanel:SetWidth(340)
    view.lmConfigPanel:SetPoint("TOPLEFT", page, "TOPRIGHT", 0, 0)
    view.lmConfigPanel:SetPoint("BOTTOMLEFT", page, "BOTTOMRIGHT", 0, 0)
    view.lmConfigPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    view.lmConfigPanel:SetBackdropColor(0.04, 0.04, 0.04, 0.96)
    view.lmConfigPanel:SetBackdropBorderColor(0.65, 0.5, 0.2, 0.7)
    view.lmConfigPanel:SetFrameLevel(page:GetFrameLevel() + 12)
    view.lmConfigPanel:Hide()
    view.lmConfigTitle = Raider.UI.Components.CreateLabel(view.lmConfigPanel, nil, "OVERLAY", "GameFontNormalSmall")
    view.lmConfigTitle:SetPoint("TOPLEFT", view.lmConfigPanel, "TOPLEFT", 8, -8)
    view.lmConfigTitle:SetText("Loot Master Config")
    view.lmConfigClose = Raider.UI.Components.CreateWindowButton(view.lmConfigPanel, nil, "close")
    view.lmConfigClose:SetPoint("TOPRIGHT", view.lmConfigPanel, "TOPRIGHT", -6, -6)
    view.lmConfigClose:SetScript("OnClick", function() page.lmConfigOpen = false; view.lmConfigPanel:Hide() end)
    page.lmConfigClose = view.lmConfigClose
    view.lmConfigTitle:SetTextColor(unpack(Raider.UI.Components.Theme.colors.goldText))
    Raider.UI.Components.SetHeadingIcon(view.lmConfigTitle,"settings")
    view.lmConfigTitle:SetPoint("TOPRIGHT",view.lmConfigPanel,"TOPRIGHT",-34,-8)
    RaidManagement.CreateAutoLootControls(page, view)
    view.lmConfigToggle = Raider.UI.Components.CreateButton(page, nil, "", 18, 18)
    Raider.UI.Components.SetClassicButtonCompact(view.lmConfigToggle, true)
    Raider.UI.Components.AttachGoldHoverBorder(view.lmConfigToggle, 0.35, 0.35, 0.35, 1)
    view.lmConfigToggle:SetPoint("RIGHT", view.minimizeButton, "LEFT", -4, 0)
    view.lmConfigToggle:SetFrameLevel(page:GetFrameLevel() + 13)
    view.lmConfigIcon = Raider.UI.Components.CreateTexture(view.lmConfigToggle, nil, "OVERLAY")
    view.lmConfigIcon:SetWidth(12); view.lmConfigIcon:SetHeight(12)
    view.lmConfigIcon:SetPoint("CENTER", view.lmConfigToggle, "CENTER", 0, 0)
    view.lmConfigIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    view.lmConfigToggle:SetScript("OnClick", function()
        page.lmConfigOpen = not page.lmConfigOpen
        if page.lmConfigOpen then
            view.lmConfigPanel:Show()
        else
            view.lmConfigPanel:Hide()
        end
    end)
    view.lmConfigToggle:Hide()
    page.lmConfigPanel = view.lmConfigPanel; page.lmConfigToggle = view.lmConfigToggle
    view.reyCoinPanel = Raider.UI.Components.CreateContainer(nil, page)
    view.reyCoinPanel:SetWidth(150); view.reyCoinPanel:SetHeight(210)
    view.reyCoinPanel:SetPoint("TOPLEFT", page, "TOPRIGHT", 0, 0)
    view.reyCoinPanel:SetFrameLevel(view.lmConfigPanel:GetFrameLevel() + 1)
    view.reyCoinPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    view.reyCoinPanel:SetBackdropColor(0.025, 0.025, 0.022, 0.98)
    view.reyCoinPanel:SetBackdropBorderColor(0.7, 0.55, 0.23, 0.9)
    view.reyCoinPanel:EnableMouse(true)
    view.reyCoinPanel:Hide()
    page.reyCoinPanel = view.reyCoinPanel
    view.reyCoinTitle = Raider.UI.Components.CreateLabel(view.reyCoinPanel, nil, "OVERLAY", "GameFontNormalSmall")
    view.reyCoinTitle:SetPoint("TOPLEFT", view.reyCoinPanel, "TOPLEFT", 8, -8)
    view.reyCoinTitle:SetText("Reycoin list")
    view.reyCoinTitle:SetTextColor(unpack(Raider.UI.Components.Theme.colors.goldText))
    Raider.UI.Components.SetHeadingIcon(view.reyCoinTitle,"list")
    view.reyCoinTitle:SetPoint("TOPRIGHT",view.reyCoinPanel,"TOPRIGHT",-34,-8)
    view.reyCoinScroll = Raider.UI.Components.CreateScrollFrame(nil, view.reyCoinPanel)
    view.reyCoinScroll:SetPoint("TOPLEFT", view.reyCoinPanel, "TOPLEFT", 6, -29)
    view.reyCoinScroll:SetPoint("BOTTOMRIGHT", view.reyCoinPanel, "BOTTOMRIGHT", -6, 61)
    view.reyCoinCanvas = Raider.UI.Components.CreateContainer(nil, view.reyCoinScroll)
    view.reyCoinCanvas:SetWidth(130); view.reyCoinCanvas:SetHeight(1)
    view.reyCoinScroll:SetScrollChild(view.reyCoinCanvas)
    view.reyCoinScroll:EnableMouseWheel(true)
    view.reyCoinScroll:SetScript("OnMouseWheel", function()
        local maximum = math.max(0, view.reyCoinCanvas:GetHeight() - view.reyCoinScroll:GetHeight())
        view.reyCoinScroll:SetVerticalScroll(math.max(0, math.min(maximum, view.reyCoinScroll:GetVerticalScroll() - arg1 * 24)))
    end)
    view.reyCoinRows = {}
    page.reyCoinScroll = view.reyCoinScroll
    page.reyCoinCanvas = view.reyCoinCanvas
    page.reyCoinRows = view.reyCoinRows
    local function RefreshReyCoinList()
        local attendance = Raider.Services.Raid.GetReyCoinAttendance()
        local members = attendance and attendance.members
        local count = 0
        local transfers = Raider.Services.Raid.GetPendingReyCoinTransfers()
        local transferIndex
        for transferIndex = 1, table.getn(transfers) do
            local transfer = transfers[transferIndex]
            if string.lower(transfer.carrier or "") ~= string.lower(transfer.winner or "") and count < table.getn(view.reyCoinRows) then
                count = count + 1
                local row = view.reyCoinRows[count]
                row.pendingTransfer = transfer; row.playerName = nil
                row.label:SetText((transfer.winner or "Unknown") .. (transfer.state == "awaiting_trade" and " - awaiting trade" or " - awaiting item"))
                row.remove.text:SetText("X")
                row:Show()
            end
        end
        local memberIndex
        for memberIndex = 1, table.getn(members or {}) do
            local member = members[memberIndex]
            local usedAt = tonumber(member.reyCoinUsedAt) or 0
            if usedAt > 0 and count < table.getn(view.reyCoinRows) then
                count = count + 1
                local row = view.reyCoinRows[count]
                row.pendingTransfer = nil; row.playerName = member.name
                row.label:SetText((member.name or "Unknown") .. " - " .. (member.reyCoinItemLink and (Match(member.reyCoinItemLink, "%[([^%]]+)%]") or member.reyCoinItemLink) or "Manual"))
                row.remove.text:SetText("X")
                row:Show()
            end
        end
        local index
        for index = count + 1, table.getn(view.reyCoinRows) do view.reyCoinRows[index]:Hide() end
        view.reyCoinCanvas:SetHeight(math.max(1, count * 25))
    end
    page.RefreshReyCoinList = RefreshReyCoinList
    Raider.Services.Raid.onReyCoinChanged = function()
        if view.reyCoinPanel:IsShown() then RefreshReyCoinList() end
    end
    for index = 1, 40 do
        local row = Raider.UI.Components.CreateContainer(nil, view.reyCoinCanvas)
        row.shade = Raider.UI.Components.CreateTexture(row, nil, "BACKGROUND"); row.shade:SetAllPoints(row)
        row.shade:SetTexture(1,1,1, math.mod(index,2)==0 and 0.09 or 0)
        row:SetHeight(24); row:SetPoint("TOPLEFT", view.reyCoinCanvas, "TOPLEFT", 0, -(index - 1) * 25)
        row:SetPoint("RIGHT", view.reyCoinCanvas, "RIGHT", 0, 0)
        row.label = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row, "LEFT", 2, 0); row.label:SetPoint("RIGHT", row, "RIGHT", -18, 0)
        row.label:SetJustifyH("LEFT")
        row.remove = Raider.UI.Components.CreateControl(nil, row)
        row.remove:SetWidth(16); row.remove:SetHeight(16); row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.remove.text = Raider.UI.Components.CreateLabel(row.remove, nil, "OVERLAY", "GameFontNormalSmall")
        row.remove.text:SetAllPoints(row.remove); row.remove.text:SetText("X")
        Raider.UI.Components.AttachGoldHoverBorder(row.remove, 0, 0, 0, 0)
        row.remove:SetScript("OnEnter", function() this.text:SetTextColor(1, 0.82, 0.28); Raider.UI.Components.SetProjectButtonOutline(this, true) end)
        row.remove:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1); Raider.UI.Components.SetProjectButtonOutline(this, false) end)
        row.remove:SetScript("OnClick", function()
            local selected = this:GetParent()
            if selected.pendingTransfer then
                Raider.Services.Raid.CancelPendingReyCoinTransfer(selected.pendingTransfer)
            else
                Raider.Services.Raid.SetReyCoinUsage(selected.playerName, nil, false)
            end
            RefreshReyCoinList()
        end)
        row:Hide(); view.reyCoinRows[index] = row
    end
    view.reyCoinInput = Raider.UI.Components.CreateFramedEditBox(view.reyCoinPanel, nil, 68)
    view.reyCoinInput:SetHeight(22); view.reyCoinInput:ClearAllPoints(); view.reyCoinInput:SetPoint("BOTTOMLEFT", view.reyCoinPanel, "BOTTOMLEFT", 8, 18); view.reyCoinInput:SetAutoFocus(false)
    view.reyCoinInput:SetScript("OnEscapePressed", function() this:ClearFocus() end); view.reyCoinInput:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    view.reyCoinItem = Raider.UI.Components.CreateFramedEditBox(view.reyCoinPanel, nil, 68)
    view.reyCoinItem:SetHeight(22); view.reyCoinItem:SetAutoFocus(false)
    view.reyCoinItem:SetPoint("LEFT", view.reyCoinInput, "RIGHT", 4, 0)
    view.reyCoinItem:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    Raider.UI.Components.AttachPlaceholder(view.reyCoinInput, "Player name")
    Raider.UI.Components.AttachPlaceholder(view.reyCoinItem, "Item")
    page.reyCoinItem = view.reyCoinItem
    view.reyCoinAdd = Raider.UI.Components.CreateButton(view.reyCoinPanel, nil, "Add", 40, 22)
    page.reyCoinInput = view.reyCoinInput; page.reyCoinAdd = view.reyCoinAdd
    view.reyCoinAdd:SetPoint("LEFT", view.reyCoinItem, "RIGHT", 4, 0)
    view.reyCoinInput:SetFrameLevel(view.reyCoinPanel:GetFrameLevel() + 3); view.reyCoinAdd:SetFrameLevel(view.reyCoinPanel:GetFrameLevel() + 3)
    view.reyCoinFeedback = Raider.UI.Components.CreateComponentLabel(view.reyCoinPanel, "", "gold")
    view.reyCoinFeedback:SetPoint("BOTTOMLEFT", view.reyCoinPanel, "BOTTOMLEFT", 8, 43)
    view.reyCoinFeedback:SetPoint("BOTTOMRIGHT", view.reyCoinPanel, "BOTTOMRIGHT", -8, 43)
    view.reyCoinFeedback:SetHeight(16); view.reyCoinFeedback:SetJustifyH("LEFT")
    view.reyCoinScroll:ClearAllPoints()
    view.reyCoinScroll:SetPoint("TOPLEFT", view.reyCoinPanel, "TOPLEFT", 6, -29)
    view.reyCoinScroll:SetPoint("BOTTOMRIGHT", view.reyCoinPanel, "BOTTOMRIGHT", -6, 61)
    RaidManagement.AttachReyCoinAdd(view, RefreshReyCoinList)
    view.reyCoinPanel:SetScript("OnSizeChanged", function()
        view.reyCoinCanvas:SetWidth(math.max(1, view.reyCoinPanel:GetWidth() - 12))
        local width = math.max(40, (view.reyCoinPanel:GetWidth() - 64) / 2)
        view.reyCoinInput:SetWidth(width); view.reyCoinItem:SetWidth(width)
    end)
    view.reyCoinToggle = Raider.UI.Components.CreateButton(page, nil, "", 18, 18)
    Raider.UI.Components.SetClassicButtonCompact(view.reyCoinToggle, true)
    page.reyCoinToggle = view.reyCoinToggle
    view.reyCoinToggle:SetWidth(18); view.reyCoinToggle:SetHeight(18)
    view.reyCoinToggle:SetPoint("RIGHT", view.lmConfigToggle, "LEFT", -4, 0)
    view.reyCoinToggle.icon = Raider.UI.Components.CreateTexture(view.reyCoinToggle, nil, "ARTWORK")
    view.reyCoinToggle.icon:SetPoint("CENTER", view.reyCoinToggle, "CENTER", 0, 0)
    view.reyCoinToggle.icon:SetWidth(12); view.reyCoinToggle.icon:SetHeight(12)
    view.reyCoinToggle.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    Raider.UI.Components.AttachGoldHoverBorder(view.reyCoinToggle, 0.38, 0.38, 0.38, 0.95)
    view.reyCoinToggle:SetScript("OnClick", function()
        if view.reyCoinPanel:IsShown() then view.reyCoinPanel:Hide(); return end
        if view.lmConfigPanel:IsShown() then view.lmConfigToggle:Click() end
        RefreshReyCoinList()
        view.reyCoinPanel:Show()
    end)
    view.reyCoinToggle:Hide()
    view.minimizedLabel = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontNormalSmall")
    view.minimizedLabel:SetTextColor(unpack(Raider.UI.Components.Theme.colors.goldText))
    view.minimizedLabel:SetText("LM Mode"); view.minimizedLabel:SetJustifyH("LEFT"); view.minimizedLabel:Hide()
    view.info = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontDisableSmall")
    view.info:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -15); view.info:SetText(""); view.info:Hide()

    view.searchLabel = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontNormalSmall")
    view.searchLabel:SetPoint("TOPRIGHT", page, "TOPRIGHT", -192, -82); view.searchLabel:SetText(""); view.searchLabel:Hide()
    view.searchBox = Raider.UI.Components.CreateFramedEditBox(page, "BootyRaiderRaidSearch", 178)
    view.searchBox:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -76); view.searchBox:Hide()
    Raider.UI.Components.AttachPlaceholder(view.searchBox,"Search...")
    view.refreshButton = Raider.UI.Components.CreateIconButton(page, nil, "Interface\\Buttons\\UI-RotationRight-Button-Up", 24)
    view.refreshButton:SetPoint("LEFT", view.searchBox, "RIGHT", 4, 0); view.refreshButton:Hide()
    Raider.UI.Components.AttachTooltip(view.refreshButton, "Refresh raid data", "Refresh the raid roster now. Disabled while Raid live tracking is active.")
    view.filterLabel = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontNormalSmall")
    view.filterLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -82); view.filterLabel:SetText(""); view.filterLabel:Hide()
    view.filterToolbar = Raider.UI.Components.CreateToolbarSurface(page, false, true); page.filterToolbar = view.filterToolbar; view.filterToolbar:Hide()

    local function CreateFilterButton(text, x)
        local button = Raider.UI.Components.CreateDropdownButton(page, nil, text, 84)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", x, -76)
        button:Hide()
        return button
    end
    view.classButton = CreateFilterButton("Class", 50)
    view.rankButton = CreateFilterButton("Rank", 142)
    view.classPanel = Raider.UI.Components.CreateDropdownPanel(page, view.classButton, 130, 80, 25)
    view.rankPanel = Raider.UI.Components.CreateDropdownPanel(page, view.rankButton, 130, 80, 25)
    view.dismiss = view.classPanel.dismiss
    view.classPanel:SetFrameLevel(page:GetFrameLevel() + 30); view.rankPanel:SetFrameLevel(page:GetFrameLevel() + 30)
    view.classButton:SetFrameLevel(page:GetFrameLevel() + 31); view.rankButton:SetFrameLevel(page:GetFrameLevel() + 31)

    view.unavailable = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontHighlight")
    view.unavailable:SetPoint("CENTER", page, "CENTER", 0, 12)
    view.unavailable:SetText("You must be in a raid to scan the raid roster.")
    view.status = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontHighlightSmall")
    view.status:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -48); view.status:SetWidth(245); view.status:SetJustifyH("LEFT")

    page.leaderModeButton = Raider.UI.Components.CreateButton(page, nil, "RL Mode", 118, 22)
    Raider.UI.Components.SetClassicButtonIcon(page.leaderModeButton, "raid_tools")
    page.leaderModeButton:SetPoint("TOPRIGHT", view.modeButton, "BOTTOMRIGHT", 0, -8)
    page.leaderModeButton:Disable(); page.leaderModeButton:Hide()
    Raider.UI.Components.AttachTooltip(page.leaderModeButton, "Raid Leader Mode", "Reserved for a future raid-leader workspace.")
    page.resetFiltersButton = Raider.UI.Components.CreateButton(page, nil, "Reset Filters", 104, 22)
    Raider.UI.Components.SetClassicButtonIcon(page.resetFiltersButton, "reset")
    Raider.UI.Components.SizeClassicButton(page.resetFiltersButton, 104, 22, 1)
    page.resetFiltersButton:SetPoint("TOPLEFT", page, "TOPLEFT", 242, -76); page.resetFiltersButton:Hide()
    Raider.UI.Components.RegisterSkinCallback(function(skin)
        if skin == "classic" then view.classicToolbar:Show()
        else view.classicToolbar:Hide(); view.classicSummary:Hide(); view.classicRaidName:Hide(); view.classicMeta:Hide(); view.classicSaved:Hide(); view.classicIssues:Hide(); view.title:Show() end
    end)
    return view
end

function RaidManagement.CreateActionControls(page)
    local controls = {}
    controls.readyCheck = Raider.UI.Components.CreateButton(page, nil, "Ready Check", 118, 22)
    Raider.UI.Components.SetClassicButtonIcon(controls.readyCheck, "check", 13, 7, 2)
    controls.readyCheck:SetScript("OnClick", function()
        if page.isTestRaid and page.isTestRaid() then return end
        if Raider.Services.Raid.ReadyCheck then Raider.Services.Raid.ReadyCheck() end
    end)
    controls.readyCheck:Hide()
    controls.raidInfo = Raider.UI.Components.CreateIconButton(page, nil, "Interface\\AddOns\\BootyLib\\Assets\\Skins\\Classic\\Icons\\info.tga", 26, 6, Raider.UI.Components.Theme.colors.goldIcon)
    Raider.UI.Components.ApplyDropdownChoiceSurface(controls.raidInfo)
    Raider.UI.Components.AttachGoldHoverBorder(controls.raidInfo, 0.35, 0.35, 0.35, 1)
    Raider.UI.Components.AttachTooltip(controls.raidInfo, "Raid Info", "Your saved instances, raid IDs and time until reset.")
    controls.raidInfo:SetScript("OnClick", function() if Raider.Modules.RaidInfo then Raider.Modules.RaidInfo.Toggle() end end)
    controls.raidInfo:Hide(); page.raidInfoButton = controls.raidInfo
    controls.scan = Raider.UI.Components.CreateButton(page, nil, "Scan Raid", 140, 24)
    controls.scan:SetPoint("CENTER", page, "CENTER", 0, 12); controls.scan:Hide()
    controls.loadRaid = Raider.UI.Components.CreateButton(page, nil, "Load", 78, 24); controls.loadRaid:Hide(); Raider.UI.Components.SetButtonEnabled(controls.loadRaid, false)
    Raider.UI.Components.AttachGoldHoverBorder(controls.scan, 0.35, 0.35, 0.35, 1)
    Raider.UI.Components.AttachTooltip(controls.scan, "New Raid", "Create a new raid session with a unique ID and scan the current raid roster.")
    Raider.UI.Components.AttachTooltip(controls.loadRaid, "Load Raid", "Load the selected saved raid snapshot.", true)
    controls.testRaid = Raider.UI.Components.CreateButton(page, nil, "Test Raid", 88, 24); controls.testRaid:Hide()
    Raider.UI.Components.AttachTooltip(controls.testRaid, "Test Raid", "Open a transient 40-player raid sandbox. Test data is never saved.")
    controls.historyTitle = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontNormal"); controls.historyTitle:SetText("Saved raids"); controls.historyTitle:Hide()
    Raider.UI.Components.SetHeadingIcon(controls.historyTitle,"archive")
    controls.historyScroll = Raider.UI.Components.CreateScrollFrame("BootyRaiderRaidHistoryScroll", page, "UIPanelScrollFrameTemplate")
    Raider.UI.Components.RegisterSkinnedScrollBar(getglobal("BootyRaiderRaidHistoryScrollScrollBar"))
    controls.historyCanvas = Raider.UI.Components.CreateContainer(nil, controls.historyScroll)
    controls.historyCanvas:SetWidth(300); controls.historyCanvas:SetHeight(1)
    controls.historyScroll:SetScrollChild(controls.historyCanvas); controls.historyScroll:Hide()
    controls.historyScroll:EnableMouseWheel(true)
    controls.historyScroll:SetScript("OnMouseWheel", function()
        local maximum = math.max(0, controls.historyCanvas:GetHeight() - this:GetHeight())
        local value = math.max(0, math.min(maximum, this:GetVerticalScroll() - arg1 * 32))
        local bar = getglobal("BootyRaiderRaidHistoryScrollScrollBar")
        if bar then bar:SetValue(value) else this:SetVerticalScroll(value) end
    end)
    controls.historyButtons = {}
    controls.historyDeleteButtons = {}
    controls.historyLoadButtons = {}
    controls.historyHeaders = {}
    for index, text in ipairs({"#", "Name", "Raid", "Time"}) do controls.historyHeaders[index] = Raider.UI.Components.CreateColumnLabel(page, text, "gold"); controls.historyHeaders[index]:Hide() end
    local historyIndex
    for historyIndex = 1, 10 do
        local button = Raider.UI.Components.CreateSelectionButton(controls.historyCanvas, nil, "", 380, 26); button.historyIndex = historyIndex; button:Hide()
        Raider.UI.Components.SetButtonLabelInsets(button, 8, 126)
        button.number = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontHighlightSmall")
        button.savedAt = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontHighlightSmall")
        button.raidName = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontHighlightSmall")
        button.savedAt:SetPoint("RIGHT", button, "RIGHT", -8, 0); button.savedAt:SetWidth(112); button.savedAt:SetJustifyH("RIGHT"); button.savedAt:SetTextColor(0.78, 0.78, 0.72)
        controls.historyButtons[historyIndex] = button
        local deleteButton = Raider.UI.Components.CreateDeleteButton(controls.historyCanvas, nil, 18, 2)
        deleteButton.historyIndex = historyIndex; deleteButton:Hide()
        Raider.UI.Components.AttachTooltip(deleteButton, "Delete saved raid", "Permanently remove this raid snapshot from saved history.")
        controls.historyDeleteButtons[historyIndex] = deleteButton
        local load = Raider.UI.Components.CreateIconButton(controls.historyCanvas, nil, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 18, 2)
        load.historyIndex = historyIndex; load:Hide()
        Raider.UI.Components.AttachTooltip(load, "Load raid", "Open this saved raid snapshot.")
        controls.historyLoadButtons[historyIndex] = load
    end
    controls.historyEmpty = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontDisable"); controls.historyEmpty:SetText("No raids to load"); controls.historyEmpty:Hide()
    controls.addStatistics = Raider.UI.Components.CreateButton(page, nil, "Add to Raid Statistics", 132, 22); controls.addStatistics:Hide()
    Raider.UI.Components.SetClassicButtonVariant(controls.addStatistics, "red")
    Raider.UI.Components.SetClassicButtonIcon(controls.addStatistics, "raid_stats")
    controls.addStatistics.mosClassicPersistentRed = true
    Raider.UI.Components.SetClassicButtonGold(controls.addStatistics, true)
    Raider.UI.Components.AttachTooltip(controls.addStatistics, "Add to Raid Statistics", "Save this session and add its compact result to Raid Statistics.")
    controls.export = Raider.UI.Components.CreateButton(page, nil, "Save Raid", 88, 22)
    Raider.UI.Components.SetClassicButtonVariant(controls.export, "red")
    Raider.UI.Components.SetClassicButtonIcon(controls.export, "save")
    controls.export.mosClassicPersistentRed = true
    Raider.UI.Components.SetClassicButtonGold(controls.export, true)
    controls.export:SetPoint("TOPRIGHT", page, "TOPRIGHT", -110, -42); controls.export:Hide()
    Raider.UI.Components.AttachTooltip(controls.export, "Save Raid", "Save this raid snapshot.")
    controls.quit = Raider.UI.Components.CreateButton(page, nil, "End Raid", 90, 22); controls.quit:Hide()
    Raider.UI.Components.SetClassicButtonVariant(controls.quit, "red")
    Raider.UI.Components.SetClassicButtonIcon(controls.quit, "quit")
    Raider.UI.Components.SetClassicButtonGold(controls.quit, true)
    Raider.UI.Components.AttachTooltip(controls.quit, "End Raid", "End the active raid session.")
    controls.raidLeaderTools = Raider.UI.Components.CreateButton(page, nil, "Raid Leader Tools", 118, 22); controls.raidLeaderTools:Hide()
    controls.raidLeaderTools.mosClassicKeepNormalSurface = true
    controls.raidLeaderTools.mosHoverTextColor = {1, 0.82, 0.28}
    Raider.UI.Components.SetClassicButtonIcon(controls.raidLeaderTools, "raid_tools", 13, 7, 2)
    Raider.UI.Components.SetClassicButtonLabelOffset(controls.raidLeaderTools, 2)
    controls.lootMasterTools = Raider.UI.Components.CreateButton(page, nil, "Loot Master Tools", 118, 22); controls.lootMasterTools:Hide()
    controls.lootMasterTools.mosClassicKeepNormalSurface = true
    controls.lootMasterTools.mosHoverTextColor = {1, 0.82, 0.28}
    Raider.UI.Components.SetClassicButtonIcon(controls.lootMasterTools, "loot_tools", 13, 7, 2)
    Raider.UI.Components.SetClassicButtonLabelOffset(controls.lootMasterTools, 2)
    Raider.UI.Components.AttachGoldHoverBorder(controls.raidLeaderTools, 0.35, 0.35, 0.35, 1)
    Raider.UI.Components.AttachGoldHoverBorder(controls.lootMasterTools, 0.35, 0.35, 0.35, 1)
    controls.reycoin = Raider.UI.Components.CreateButton(page, nil, "Reycoin list", 100, 22)
    controls.reycoin:Hide()
    controls.reycoin:SetScript("OnClick", function() page.lootMasterController.OpenSoloReyCoin() end)
    controls.newRoll = Raider.UI.Components.CreateButton(page, nil, "New Roll", 90, 22)
    Raider.UI.Components.SetClassicButtonIcon(controls.newRoll,"dice")
    controls.newRoll:Hide()
    controls.newRoll:SetScript("OnClick",function()
        if Raider.Modules.MasterLootWindow then Raider.Modules.MasterLootWindow.OpenNewRollDialog() end
    end)
    controls.lootRules = Raider.UI.Components.CreateButton(page, nil, "Set Loot Rules", 102, 22)
    controls.lootRules.mosClassicReserveIconSpace = true
    Raider.UI.Components.SetClassicButtonIcon(controls.lootRules, "rules")
    controls.lootRules:SetPoint("TOPRIGHT", page, "TOPRIGHT", -326, -42); controls.lootRules:Hide()
    controls.sendLootRules = Raider.UI.Components.CreateButton(page, nil, "Send Loot Rules", 112, 22)
    controls.sendLootRules.mosClassicReserveIconSpace = true
    Raider.UI.Components.SetClassicButtonIcon(controls.sendLootRules, "rules")
    controls.sendLootRules:Hide()
    controls.import = Raider.UI.Components.CreateButton(page, nil, "Import SR", 82, 22)
    controls.import.mosClassicReserveIconSpace = true
    Raider.UI.Components.SetClassicButtonIcon(controls.import, "import")
    controls.import:SetPoint("TOPRIGHT", page, "TOPRIGHT", -236, -42); controls.import:Hide()
    controls.shareSr = Raider.UI.Components.CreateButton(page, nil, "Share SR Link", 92, 22); controls.shareSr:Hide()
    controls.shareSr.mosClassicReserveIconSpace = true
    Raider.UI.Components.SetClassicButtonIcon(controls.shareSr, "link")
    Raider.UI.Components.AttachTooltip(controls.shareSr, "Share SR Link", "Send the saved Soft Reserve URL to the raid as a Raid Warning.")
    controls.resetLoot = Raider.UI.Components.CreateButton(page, "BootyRaiderRaidResetLootButton", "Reset loot", 82, 22)
    controls.resetLoot.mosClassicReserveIconSpace = true
    Raider.UI.Components.SetClassicButtonIcon(controls.resetLoot, "reset")
    controls.resetLoot:SetPoint("TOPRIGHT", page, "TOPRIGHT", -326, -42); controls.resetLoot:Hide()
    controls.resetLoot:SetScript("OnClick", function() RaidManagement.resetLootDialog:Open("Reset all recorded raid loot?", StaticPopupDialogs.BOOTY_RAIDER_RESET_LOOT.OnAccept) end)
    controls.live = Raider.UI.Components.CreateButton(page, nil, "Start Live Tracking", 118, 22)
    controls.live:SetPoint("TOPRIGHT", page, "TOPRIGHT", -416, -42); controls.live:Hide()
    return controls
end

function RaidManagement.RegisterResetLootDialog(options)
    RaidManagement.resetLootDialog = Raider.UI.Components.Window.CreateProjectConfirmation("BootyRaiderResetLootDialog", "Reset Loot", "Reset Loot", "reset")
    StaticPopupDialogs["BOOTY_RAIDER_RESET_LOOT"] = {
        text = "Reset all recorded raid loot?", button1 = "Reset loot", button2 = "Cancel",
        OnAccept = function()
            local attendance = options.getAttendance()
            Raider.Services.Raid.ResetRecordedLoot(attendance)
            options.clearSelection(); options.refresh(); options.printMessage("Raid loot history reset.")
        end,
        timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
end

local normalHeaderPositions = { 12, 172, 252, 347, 500 }
local normalHeaderWidths = { 155, 70, 85, 138, 55 }
local lootHeaderPositions = { 3, 0, 105, 170, 250 }
local lootHeaderWidths = { 90, 0, 55, 72, 35 }

local function SortLootByName(a, b)
    local aName, bName = string.lower(a.name or ""), string.lower(b.name or "")
    if aName == bName then return (tonumber(a.recordId) or 0) > (tonumber(b.recordId) or 0) end
    return aName < bName
end

local raidActionSpecs = { { "Leader", "leader" }, { "Assist", "assistant" }, { "Loot Master", "lootmaster" }, { "Remove", "remove" }, { "Report", "report" }, { "Ignore", "ignore" } }
local listHeaderSpecs = {
    { "Name", "name", 12, 155 },
    { "Group", "subgroup", 172, 70 },
    { "Class", "class", 252, 85 },
    { "Guild rank", "guildRank", 347, 138 },
    { "SR", "sr", 500, 55 },
    { "Lvl", "level", 555, 45 },
}

local function OnListHeaderClick()
    this.headerController.onSort(this.sortKey, this.defaultAscending)
end

local function OnGroupViewportMouseWheel()
    local page = this.groupPage
    local maximum = math.max(0, page.groupCanvas:GetHeight() - this:GetHeight())
    local value = math.max(0, math.min(maximum, this:GetVerticalScroll() - (arg1 * 42)))
    if page.groupScrollBar then page.groupScrollBar:SetValue(value) else this:SetVerticalScroll(value) end
end

local function OnListViewportScroll()
    FauxScrollFrame_OnVerticalScroll(this.rowStep or 21, this.refreshCallback)
end

local function PageSpan(page)
    if page.mosCompactGroupWidth then return page.mosCompactGroupWidth, page.mosCompactGroupHeight end
    if page.detachedLootMaster then return math.max(1, page:GetParent():GetWidth() - 8), math.max(1, page:GetParent():GetHeight() - 28) end
    local left, right = page:GetLeft(), page:GetRight()
    local bottom, top = page:GetBottom(), page:GetTop()
    return left and right and (right - left) or page:GetWidth(),
        bottom and top and (top - bottom) or page:GetHeight()
end

local function OnRaidPageSizeChanged()
    if not this:IsVisible() then return end
    local currentWidth, currentHeight = PageSpan(this)
    if math.abs(currentWidth - (this.layoutWidth or 0)) <= 0.5 and math.abs(currentHeight - (this.layoutHeight or 0)) <= 0.5 then return end
    this.layoutWidth, this.layoutHeight = currentWidth, currentHeight
    this.resizeRefresh()
end

local function OnLootMasterAlphaUpdate()
    this.elapsed = this.elapsed + arg1
    if this.elapsed < 0.08 then return end
    this.elapsed = 0
    local controller = this.lootMasterController
    local dashboard = controller.dashboard
    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    cursorX = cursorX / uiScale; cursorY = cursorY / uiScale
    local inside = dashboard:GetLeft() and cursorX >= dashboard:GetLeft() and cursorX <= dashboard:GetRight() and cursorY >= dashboard:GetBottom() and cursorY <= dashboard:GetTop()
    local settings = controller.getSettings()
    local opacity
    if inside then opacity = tonumber(settings.lootMasterOpacity) or 100
    else opacity = tonumber(settings.outOfFocusOpacity) or 100 end
    dashboard:SetAlpha(math.max(0, math.min(100, opacity)) / 100)
end

local function OnRaidActionClick()
    local row = this.ownerRow
    if row and row.controller and row.controller.onAction then row.controller.onAction(row, this.action) end
end

local function OnGroupClick()
    local row = this.ownerRow
    if row and row.controller and row.controller.onGroup then row.controller.onGroup(row) end
end

local function OnSoftReserveEnter() Raider.UI.Components.ShowItemTooltip(this) end
local function OnSoftReserveClick() Raider.UI.Components.HandleItemClick(this) end
local function OnSoftReserveLeave() GameTooltip:Hide() end
local function OnSoftReserveDeleteClick()
    local row = this.ownerRow
    if row and row.controller and row.controller.onRemoveSoftReserve then row.controller.onRemoveSoftReserve(row) end
end
local function OnLootItemEnter()
    if not this.itemId then return end
    Raider.UI.Components.ShowItemTooltip(this)
end
local function OnLootItemLeave() GameTooltip:Hide() end
local function OnLootItemClick()
    if not IsShiftKeyDown() and not IsControlKeyDown() and Raider.Modules.MasterLootWindow and Raider.Modules.MasterLootWindow.ShowHistory then
        Raider.Modules.MasterLootWindow.ShowHistory(this.itemLink or this.itemName, this.rollHistory, this.itemId, this.itemName)
    else
        Raider.UI.Components.HandleItemClick(this)
    end
end

local function OnRaidRowClick()
    if not this.displayedMember or not this.controller then return end
    if arg1 == "RightButton" then
        if this.controller.onContext then this.controller.onContext(this) end
    elseif this.controller.onSelect then
        this.controller.onSelect(this)
    end
end

local function OnRaidRowEnter()
    local settings = BootyRaiderDB
    this.mosRaidHovered = true
    if settings.raidListShowHoverBorder or this.mosProjectOutline then
        Raider.UI.Components.SetProjectButtonOutline(this, settings.raidListShowHoverBorder, settings.raidListHoverBorderSize, settings.raidListHoverBorderColor)
    end
    if this.displayedMember and this.controller and not this.controller.isSelected(this.displayedMember) then
        local color = BootyRaiderDB.raidListHoverColor
        Raider.UI.Components.SetRowColor(this, color, 0.98)
    end
end

local function OnRaidRowLeave()
    this.mosRaidHovered = nil
    if this.mosProjectOutline then this.mosProjectOutline:Hide() end
    if this.displayedMember and this.controller and not this.controller.isSelected(this.displayedMember) then
        local color = BootyRaiderDB.raidListBackgroundColor
        Raider.UI.Components.SetAlternatingRowColor(this, color, this.visibleIndex, BootyRaiderDB.raidListOddLightness)
    end
end

local function OnRaidMemberHide()
    this.mosRaidHovered=nil
    if this.mosProjectOutline then this.mosProjectOutline:Hide() end
    Raider.UI.Components.SetAtlasHighlight(this, false)
end

local function OnLootScroll()
    local row = this.ownerRow
    if row and row.controller and row.controller.refresh then FauxScrollFrame_OnVerticalScroll(24, row.controller.refresh) end
end

local function AddRaidCell(parent, row, key, x, width, hidden)
    row[key] = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
    row[key]:SetPoint("TOPLEFT", parent, "TOPLEFT", x, row.initialY)
    row[key]:SetWidth(width); row[key]:SetHeight(20); row[key]:SetJustifyH("LEFT")
    if hidden then row[key]:Hide() end
end

function RaidManagement.CreateListRow(parent, index, controller)
    local row = Raider.UI.Components.CreateControl(nil, parent)
    row.controller = controller
    row:SetScript("OnHide",OnRaidMemberHide)
    row.initialY = -132 - ((index - 1) * 21)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, row.initialY)
    row:SetWidth(543); row:SetHeight(20)
    row.name = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0); row.name:SetWidth(148); row.name:SetHeight(20); row.name:SetJustifyH("LEFT")
    row.crown = Raider.UI.Components.CreateTexture(row, nil, "OVERLAY")
    row.crown:SetWidth(14); row.crown:SetHeight(14); row.crown:SetPoint("LEFT", row, "LEFT", 1, 0); row.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); row.crown:Hide()
    row.lootMasterIcon = Raider.UI.Components.CreateTexture(row, nil, "OVERLAY")
    row.lootMasterIcon:SetWidth(13); row.lootMasterIcon:SetHeight(13); row.lootMasterIcon:SetPoint("RIGHT", row, "RIGHT", -3, 0); row.lootMasterIcon:SetTexture("Interface\\GroupFrame\\UI-Group-MasterLooter"); row.lootMasterIcon:Hide()
    AddRaidCell(parent, row, "level", 0, 45, true)
    AddRaidCell(parent, row, "status", 0, 62, true)
    AddRaidCell(parent, row, "group", 172, 70, false)
    row.groupHit = Raider.UI.Components.CreateControl(nil, parent); row.groupHit.ownerRow = row; row.groupHit:Hide()
    row.groupHit:SetScript("OnClick", OnGroupClick)
    AddRaidCell(parent, row, "class", 252, 85, false)
    AddRaidCell(parent, row, "rank", 347, 135, false)
    AddRaidCell(parent, row, "sr", 500, 55, false)
    row.srHit = Raider.UI.Components.CreateControl(nil, row)
    row.srHit.ownerRow = row; row.srHit.label = row.sr; row.srHit:Hide()
    row.srDelete = Raider.UI.Components.CreateDeleteButton(row.srHit, nil, 18, 3)
    row.srDelete:SetPoint("LEFT", row.srHit, "LEFT", 0, 0); row.srDelete.ownerRow = row; row.srDelete:SetScript("OnClick", OnSoftReserveDeleteClick); row.srDelete:Hide()
    Raider.UI.Components.AttachTooltip(row.srDelete, "Remove Soft Reserve", "Remove this player's assigned Soft Reserve.")
    row.srIcon = Raider.UI.Components.CreateTexture(row.srHit, nil, "ARTWORK")
    row.srIcon:SetWidth(16); row.srIcon:SetHeight(16); row.srIcon:SetPoint("LEFT", row.srHit, "LEFT", 20, 0); row.srIcon:Hide()
    row.srHit.iconRegion = row.srIcon
    row.srHit:SetScript("OnEnter", OnSoftReserveEnter); row.srHit:SetScript("OnLeave", OnSoftReserveLeave); row.srHit:SetScript("OnClick", OnSoftReserveClick)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    row:SetBackdropColor(0, 0, 0, 0); row:SetBackdropBorderColor(0, 0, 0, 0); row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Raider.UI.Components.RegisterSkinnedSurface(row, "row", { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    row.lootPanel = Raider.UI.Components.CreateContainer(nil, row)
    row.lootPanel:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -21); row.lootPanel:SetWidth(535); row.lootPanel:SetHeight(106)
    row.lootPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    row.lootPanel:SetBackdropColor(0.07, 0.08, 0.07, 0.94); row.lootPanel:SetBackdropBorderColor(0.30, 0.34, 0.30, 1)
    row.actions = Raider.UI.Components.CreateContainer(nil, row.lootPanel)
    row.actions:SetPoint("TOPLEFT", row.lootPanel, "TOPLEFT", 7, -7); row.actions:SetPoint("TOPRIGHT", row.lootPanel, "TOPRIGHT", -7, -7); row.actions:SetHeight(22)
    row.actionButtons = {}
    local actionIndex
    for actionIndex = 1, table.getn(raidActionSpecs) do
        local actionButton = Raider.UI.Components.CreateButton(row.actions, nil, raidActionSpecs[actionIndex][1], 58, 19)
        actionButton:SetPoint("LEFT", row.actions, "LEFT", (actionIndex - 1) * 62, 0)
        actionButton.action = raidActionSpecs[actionIndex][2]; actionButton.ownerRow = row; actionButton:SetScript("OnClick", OnRaidActionClick)
        row.actionButtons[actionIndex] = actionButton
    end
    row.lootTitle = Raider.UI.Components.CreateLabel(row.lootPanel, nil, "OVERLAY", "GameFontDisableSmall")
    row.lootTitle:SetPoint("TOPLEFT", row.lootPanel, "TOPLEFT", 10, -33); row.lootTitle:SetText("Loot received")
    row.lootEmpty = Raider.UI.Components.CreateLabel(row.lootPanel, nil, "OVERLAY", "GameFontDisableSmall")
    row.lootEmpty:SetPoint("TOPLEFT", row.lootPanel, "TOPLEFT", 10, -55); row.lootEmpty:SetText("No recorded items.")
    row.lootRows = {}
    local lootIndex
    for lootIndex = 1, 25 do
        local lootRow = {}
        lootRow.hit = Raider.UI.Components.CreateControl(nil, row.lootPanel); lootRow.hit:SetHeight(22)
        local highlight = Raider.UI.Components.CreateTexture(lootRow.hit, nil, "HIGHLIGHT"); highlight:SetAllPoints(lootRow.hit); highlight:SetTexture(1, 0.72, 0.12, 0.14)
        lootRow.icon = Raider.UI.Components.CreateTexture(lootRow.hit, nil, "ARTWORK")
        lootRow.icon:SetPoint("LEFT", lootRow.hit, "LEFT", 2, 0); lootRow.icon:SetWidth(20); lootRow.icon:SetHeight(20)
        lootRow.name = Raider.UI.Components.CreateLabel(lootRow.hit, nil, "OVERLAY", "GameFontHighlightSmall")
        lootRow.name:SetPoint("LEFT", lootRow.icon, "RIGHT", 7, 0); lootRow.name:SetWidth(455); lootRow.name:SetJustifyH("LEFT")
        lootRow.hit.label = lootRow.name; lootRow.hit.iconRegion = lootRow.icon
        lootRow.hit:SetScript("OnEnter", OnLootItemEnter); lootRow.hit:SetScript("OnLeave", OnLootItemLeave); lootRow.hit:SetScript("OnClick", OnLootItemClick); lootRow.hit:Hide()
        row.lootRows[lootIndex] = lootRow
    end
    row.lootScroll = Raider.UI.Components.CreateScrollFrame((parent.mosLootScrollPrefix or "BootyRaiderRaidLootScroll") .. index, row.lootPanel, "FauxScrollFrameTemplate")
    row.lootScroll:SetPoint("TOPLEFT", row.lootPanel, "TOPLEFT", 8, -24); row.lootScroll:SetPoint("BOTTOMRIGHT", row.lootPanel, "BOTTOMRIGHT", -30, 8)
    row.lootScrollBar = getglobal(row.lootScroll:GetName() .. "ScrollBar")
    if row.lootScrollBar then
        row.lootScrollBar:ClearAllPoints(); row.lootScrollBar:SetPoint("TOPRIGHT", row.lootPanel, "TOPRIGHT", -7, -26); row.lootScrollBar:SetPoint("BOTTOMRIGHT", row.lootPanel, "BOTTOMRIGHT", -7, 20)
    end
    row.lootScroll.ownerRow = row; row.lootScroll:SetScript("OnVerticalScroll", OnLootScroll)
    row.lootPanel:Hide(); row:SetScript("OnClick", OnRaidRowClick); row:SetScript("OnEnter", OnRaidRowEnter); row:SetScript("OnLeave", OnRaidRowLeave)
    row:Hide(); row.name:Hide(); row.group:Hide(); row.class:Hide(); row.rank:Hide(); row.sr:Hide(); row.level:Hide()
    row.initialY = nil
    return row
end

function RaidManagement.CreateListHeaders(page, onSort)
    local ui = { buttons = {}, controller = { onSort = onSort } }
    local index
    for index = 1, table.getn(listHeaderSpecs) do
        local spec = listHeaderSpecs[index]
        local label = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", page, "TOPLEFT", spec[3], -110)
        label:SetWidth(spec[4]); label:SetJustifyH("LEFT"); label:SetText(spec[1]); label:Hide()
        local button = Raider.UI.Components.CreateControl(nil, page)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", spec[3], -106); button:SetWidth(spec[4]); button:SetHeight(22)
        button.label = label; button.baseText = spec[1]; button.sortKey = spec[2]; button.defaultAscending = true; button.headerController = ui.controller
        Raider.UI.Components.Table.ApplyHeaderHover(button)
        button:SetScript("OnClick", OnListHeaderClick); button:Hide()
        ui.buttons[index] = button
    end
    ui.name = ui.buttons[1].label; ui.group = ui.buttons[2].label; ui.class = ui.buttons[3].label
    ui.rank = ui.buttons[4].label; ui.sr = ui.buttons[5].label; ui.level = ui.buttons[6].label; ui.levelButton = ui.buttons[6]

    ui.online = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontNormal")
    ui.online:SetWidth(62); ui.online:SetJustifyH("LEFT"); ui.online:SetText("Status"); ui.online:Hide()
    ui.onlineButton = Raider.UI.Components.CreateControl(nil, page)
    ui.onlineButton:SetWidth(62); ui.onlineButton:SetHeight(22); ui.onlineButton.label = ui.online; ui.onlineButton.baseText = "Status"
    ui.onlineButton.sortKey = "online"; ui.onlineButton.defaultAscending = false; ui.onlineButton.headerController = ui.controller
    Raider.UI.Components.Table.ApplyHeaderHover(ui.onlineButton)
    ui.onlineButton:SetScript("OnClick", OnListHeaderClick); ui.onlineButton:Hide()

    page.listColumns = {
        { key = "name", setting = "raidListShowName", fraction = 0.20, header = ui.name, button = ui.buttons[1] },
        { key = "level", setting = "raidListShowLevel", fraction = 0.07, header = ui.level, button = ui.levelButton },
        { key = "status", setting = "raidListShowStatus", fraction = 0.10, header = ui.online, button = ui.onlineButton },
        { key = "group", setting = "raidListShowGroup", fraction = 0.10, header = ui.group, button = ui.buttons[2] },
        { key = "class", setting = "raidListShowClass", fraction = 0.14, header = ui.class, button = ui.buttons[3] },
        { key = "rank", setting = "raidListShowGuildRank", fraction = 0.17, header = ui.rank, button = ui.buttons[4] },
        { key = "sr", setting = "raidListShowSR", fraction = 0.22, header = ui.sr, button = ui.buttons[5] },
    }
    page.listEnabled = {}; page.listPositions = {}; page.listWidths = {}
    page.headerLabels = { ui.name, ui.group, ui.class, ui.rank, ui.sr }
    local _, headerBaseSize = ui.name:GetFont()
    page.mosHeaderBaseSize = headerBaseSize
    page.listHeaderUI = ui
    return ui
end

local function CreateGroupCanvas(page, scrollName)
    page.groupFrame = Raider.UI.Components.CreateScrollFrame(scrollName, page, "UIPanelScrollFrameTemplate")
    page.groupFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -72)
    page.groupFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 5)
    page.groupCanvas = Raider.UI.Components.CreateContainer(nil, page.groupFrame)
    page.groupCanvas:SetWidth(1); page.groupCanvas:SetHeight(1)
    page.groupFrame:SetScrollChild(page.groupCanvas)
    page.groupScrollBar = getglobal(scrollName .. "ScrollBar")
    Raider.UI.Components.RegisterSkinnedScrollBar(page.groupScrollBar)
    page.groupFrame.groupPage = page
    page.groupFrame:EnableMouseWheel(true); page.groupFrame:SetScript("OnMouseWheel", OnGroupViewportMouseWheel)
    page.groupFrame:Hide()
    return page.groupFrame
end

function RaidManagement.CreateGroupViewport(page)
    page.raidView = "list"
    page.viewButton = Raider.UI.Components.CreateButton(page, nil, "Group View", 92, 22)
    page.viewButton:Hide()
    page.classicListButton = Raider.UI.Components.CreateButton(page, nil, "List", 90, 24); page.classicListButton:Hide()
    page.classicGroupButton = Raider.UI.Components.CreateButton(page, nil, "Groups", 100, 24); page.classicGroupButton:Hide()
    page.classicTwoButton = Raider.UI.Components.CreateButton(page, nil, "2 x 4", 78, 24); page.classicTwoButton:Hide()
    page.classicFourButton = Raider.UI.Components.CreateButton(page, nil, "4 x 2", 76, 24); page.classicFourButton:Hide()
    Raider.UI.Components.SetClassicButtonIcon(page.classicListButton, "list", 13, 7, 2); Raider.UI.Components.SetClassicButtonIcon(page.classicGroupButton, "groups", 13, 7, 2)
    Raider.UI.Components.SetClassicButtonIcon(page.classicTwoButton, "list", 12, 7, 2); Raider.UI.Components.SetClassicButtonIcon(page.classicFourButton, "groups", 12, 7, 2)
    Raider.UI.Components.SetClassicButtonLabelOffset(page.classicListButton, 2); Raider.UI.Components.SetClassicButtonLabelOffset(page.classicGroupButton, 2)
    Raider.UI.Components.SetClassicButtonLabelOffset(page.classicTwoButton, 2); Raider.UI.Components.SetClassicButtonLabelOffset(page.classicFourButton, 2)
    for _, button in ipairs({page.classicListButton, page.classicGroupButton, page.classicTwoButton, page.classicFourButton}) do button.mosSelectedTextColor = {1,0.82,0.28}; Raider.UI.Components.SetButtonTextColor(button, {1,1,1}) end
    return CreateGroupCanvas(page, "BootyRaiderRaidGroupScroll")
end

function RaidManagement.CreateListController(options)
    local controller = {}
    controller.refresh = options.refresh
    controller.isSelected = options.isSelected
    controller.onSelect = options.onSelect
    controller.onRemoveSoftReserve = function(row)
        local member = row and row.displayedMember
        if member and options.removeSoftReserve(member.name) then options.refresh() end
    end
    controller.onAction = function(row, action)
        local member = row and row.displayedMember
        if member and options.runMemberAction(member, action) then options.refresh() end
    end
    controller.onGroup = function(row)
        if options.page.openGroupSelector then options.page.openGroupSelector(row) end
    end
    controller.onContext = function(row)
        if options.page.showMemberMenu then options.page.showMemberMenu(row) end
    end
    options.page.rowController = controller
    return controller
end

function RaidManagement.CreateListViewport(page, rowCount, controller, scrollName)
    local rows = {}
    local index
    for index = 1, rowCount do rows[index] = RaidManagement.CreateListRow(page, index, controller) end
    scrollName = scrollName or "BootyRaiderRaidScrollFrame"
    local scrollFrame = Raider.UI.Components.CreateScrollFrame(scrollName, page, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", -4, -121)
    scrollFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 18)
    page.listRows = rows; page.listScrollFrame = scrollFrame
    page.listScrollBar = getglobal(scrollName .. "ScrollBar")
    Raider.UI.Components.RegisterSkinnedScrollBar(page.listScrollBar)
    return rows, scrollFrame
end

function RaidManagement.MountList(page, chrome, options)
    page.getSoftReserveData = options.getData
    page.getSoftReserveRules = options.getRules
    RaidManagement.CreateFilterController({
        page = page, classButton = chrome.classButton, rankButton = chrome.rankButton,
        classPanel = chrome.classPanel, rankPanel = chrome.rankPanel, dismiss = chrome.dismiss,
        resetButton = page.resetFiltersButton, searchBox = chrome.searchBox,
        selectedClasses = options.selectedClasses, selectedRanks = options.selectedRanks,
        getFilterValues = options.getFilterValues, refresh = options.refresh, onReset = options.onReset,
    })
    RaidManagement.CreateListHeaders(page, options.onSort)
    RaidManagement.CreateSoftReserveWarnings(page, options.clearUnmatchedSoftReserves, options.refresh, options.getData)
    RaidManagement.CreateSoftReserveFixDialog(page, options.applySoftReserveAssignments, options.refresh)
    local pendingSoftReserveRemoval = nil
    StaticPopupDialogs["BOOTY_RAIDER_REMOVE_MEMBER_SR"] = {
        text = "Remove the Soft Reserve assigned to %s?", button1 = "Remove SR", button2 = "Cancel",
        OnAccept = function() if pendingSoftReserveRemoval then options.removeSoftReserve(pendingSoftReserveRemoval); options.refresh() end; pendingSoftReserveRemoval = nil end,
        OnCancel = function() pendingSoftReserveRemoval = nil end,
        timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
    local removeSRDialog = Raider.UI.Components.Window.CreateProjectConfirmation("BootyRaiderRemoveMemberSR", "Remove Soft Reserve", "Remove SR", "fix")
    local controller = RaidManagement.CreateListController({
        page = page, runMemberAction = options.runMemberAction, isSelected = options.isSelected,
        refresh = options.refresh, onSelect = options.onSelect, removeSoftReserve = function(memberName)
            pendingSoftReserveRemoval = memberName
            removeSRDialog:Open("Remove the Soft Reserve assigned to " .. memberName .. "?", StaticPopupDialogs.BOOTY_RAIDER_REMOVE_MEMBER_SR.OnAccept, StaticPopupDialogs.BOOTY_RAIDER_REMOVE_MEMBER_SR.OnCancel)
            return false
        end,
    })
    local rows, scrollFrame = RaidManagement.CreateListViewport(page, options.rowCount or 25, controller)
    return { rows = rows, scrollFrame = scrollFrame }
end

function RaidManagement.AttachListScroll(page, refresh)
    page.listScrollFrame.refreshCallback = refresh
    page.listScrollFrame:SetScript("OnVerticalScroll", OnListViewportScroll)
end

function RaidManagement.AttachResizeHandler(page, refresh)
    page.layoutWidth, page.layoutHeight = PageSpan(page)
    page.resizeRefresh = refresh
    page:SetScript("OnUpdate", nil)
    page:SetScript("OnSizeChanged", OnRaidPageSizeChanged)
    Raider.UI.Components.RegisterSkinCallback(function() if page:IsVisible() then refresh() end end)
end

function RaidManagement.BeginRefresh(page, rows)
    page.groupFrame:Hide(); Raider.UI.Components.SetScrollBarVisible(page.groupScrollBar, false); page.viewButton:Hide()
    page.classicToolbar:Hide()
    if page.filterToolbar then page.filterToolbar:Hide() end
    page.classicSummary:Hide()
    page.lmConfigToggle:Hide()
    page.classicListButton:Hide(); page.classicGroupButton:Hide(); page.classicTwoButton:Hide(); page.classicFourButton:Hide()
    page.refreshControls.minimizedLabel:Hide()
    page.softReserveWarning:Hide(); page.missingSoftReserveWarning:Hide(); page.invalidSoftReserveWarning:Hide()
    page.listHeaderUI.online:Hide(); page.listHeaderUI.onlineButton:Hide()
    page.listHeaderUI.level:Hide(); page.listHeaderUI.levelButton:Hide()
    page.groupSelectMenu:Hide(); page.groupSelectDismiss:Hide()
    local index
    for index = 1, table.getn(rows) do
        rows[index].status:Hide(); rows[index].level:Hide(); rows[index].groupHit:Hide()
    end
end

function RaidManagement.HideListChrome(page)
    if page.filterToolbar then page.filterToolbar:Hide() end
    local headers = page.listHeaderUI
    headers.name:Hide(); headers.group:Hide(); headers.class:Hide(); headers.rank:Hide(); headers.sr:Hide()
    headers.level:Hide(); headers.online:Hide(); headers.onlineButton:Hide()
    local index
    for index = 1, table.getn(headers.buttons) do headers.buttons[index]:Hide() end
    page.listScrollFrame:Hide()
end

function RaidManagement.HideListTable(page, rows)
    RaidManagement.HideListChrome(page)
    local index
    for index = 1, table.getn(rows) do
        local row = rows[index]
        row:Hide(); row.name:Hide(); row.level:Hide(); row.status:Hide(); row.group:Hide(); row.groupHit:Hide()
        row.class:Hide(); row.rank:Hide(); row.sr:Hide(); row.lootPanel:Hide()
    end
end

function RaidManagement.SetListToolbar(page, controls)
    page.listToolbar = controls
end

function RaidManagement.LayoutListToolbar(page, lootMasterMode, settings)
    local controls = page.listToolbar
    if lootMasterMode then
        page.reyCoinToggle:Show()
        if not page.reyCoinConfigWrapped then
            local configClick = page.lmConfigToggle:GetScript("OnClick")
            if configClick then
                page.lmConfigToggle:SetScript("OnClick", function()
                    page.reyCoinPanel:Hide()
                    configClick()
                end)
                page.reyCoinConfigWrapped = true
            end
        end
        controls.filterLabel:Hide(); controls.resetButton:Hide(); controls.refreshButton:Hide(); controls.searchLabel:Hide(); if page.filterToolbar then page.filterToolbar:Hide() end
        controls.modeButton:SetScale(1); controls.minimizeButton:SetScale(1)
        controls.modeButton:ClearAllPoints(); controls.modeButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -8); controls.modeButton:SetWidth(18); controls.modeButton:SetHeight(18); Raider.UI.Components.SetWindowButtonAction(controls.modeButton, "close")
        controls.minimizeButton:ClearAllPoints(); controls.minimizeButton:SetPoint("RIGHT", controls.modeButton, "LEFT", -4, 0); controls.minimizeButton:SetWidth(18); controls.minimizeButton:SetHeight(18); Raider.UI.Components.SetWindowButtonAction(controls.minimizeButton, "minimize")
        Raider.UI.Components.SetClassicButtonCompact(controls.modeButton, true)
        if controls.modeButton.mosClassicIconKey then Raider.UI.Components.SetClassicButtonIcon(controls.modeButton, nil) end
        controls.searchLabel:ClearAllPoints(); controls.searchLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -10); controls.searchLabel:SetWidth(52); controls.searchLabel:SetJustifyH("LEFT"); controls.searchLabel:SetText("LM Mode")
        page.lmConfigToggle:ClearAllPoints(); page.lmConfigToggle:SetPoint("RIGHT", controls.minimizeButton, "LEFT", -4, 0)
        controls.searchLabel:Hide(); controls.searchBox:Hide(); controls.classButton:Hide(); controls.rankButton:Hide()
        return
    end

    local classic = Raider.UI.Components.IsClassicSkin()
    page.reyCoinToggle:Hide(); page.lmConfigToggle:Hide()
    if not page.lootMasterController or not page.lootMasterController.IsVisible() then if not page.reyCoinSolo then page.reyCoinPanel:Hide() end; page.lmConfigPanel:Hide() end
    local submenuOffset = classic and ((page.classicSectionOffset or 0) + (page.classicActionOffset or 0) + (page.classicToolbarOffset or 0)) or 0
    local pageWidth = PageSpan(page)
    local filterWidth = pageWidth < 650 and 60 or 84
    local toolbar = page.filterToolbar or page
    if page.filterToolbar then
        page.filterToolbar.mosBorderOutsetLeft=4;page.filterToolbar.mosBorderOutsetRight=4;Raider.UI.Components.SetSurfaceHorizontalBorders(page.filterToolbar,false,true)
        page.filterToolbar:ClearAllPoints(); page.filterToolbar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -92 - submenuOffset); page.filterToolbar:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -92 - submenuOffset)
        page.filterToolbar:SetHeight(38 + (page.classicSearchOffset or 0))
    end
    controls.filterLabel:Hide()
    controls.classButton:ClearAllPoints(); controls.classButton:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 6, -7); controls.classButton:SetWidth(filterWidth); controls.classButton:SetHeight(24)
    controls.rankButton:ClearAllPoints(); controls.rankButton:SetPoint("LEFT", controls.classButton, "RIGHT", 8, 0); controls.rankButton:SetWidth(filterWidth)
    controls.rankButton:SetHeight(24)
    controls.resetButton:ClearAllPoints(); controls.resetButton:SetPoint("LEFT", controls.rankButton, "RIGHT", 8, 0); controls.resetButton:SetHeight(24)
    Raider.UI.Components.SetClassicButtonCompact(controls.modeButton, false)
    controls.modeButton:SetWidth(96); controls.modeButton:SetHeight(22)
    if not controls.modeButton.mosClassicIconKey then Raider.UI.Components.SetClassicButtonIcon(controls.modeButton, "loot_tools", 13, 7, 0) end
    controls.searchLabel:Hide()
    controls.searchBox:ClearAllPoints()
    if (page.classicSearchOffset or 0) > 0 then controls.searchBox:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 6, -37)
    elseif settings.raidListShowFilters then controls.searchBox:SetPoint("LEFT", controls.resetButton, "RIGHT", 10, 0)
    else controls.searchBox:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 6, -7) end
    controls.searchBox:SetHeight(24)
    controls.searchBox:SetWidth(math.min(110, page.classicSearchWidth or 110))
    controls.refreshButton:ClearAllPoints(); controls.refreshButton:SetPoint("LEFT", controls.searchBox, "RIGHT", 4, 0)
    if settings.raidListShowFilters then
        controls.filterLabel:Hide(); controls.classButton:Show(); controls.rankButton:Show(); controls.resetButton:Show()
    else
        controls.filterLabel:Hide(); controls.classButton:Hide(); controls.rankButton:Hide(); controls.resetButton:Hide()
    end
    if settings.raidListShowSearch then controls.searchLabel:Hide(); controls.searchBox:Show(); controls.refreshButton:Show()
    else controls.searchLabel:Hide(); controls.searchBox:Hide(); controls.refreshButton:Hide() end
    if page.filterToolbar then
        if settings.raidListShowFilters or settings.raidListShowSearch then page.filterToolbar:Show() else page.filterToolbar:Hide() end
    end
end

function RaidManagement.SetRefreshControls(page, controls)
    page.refreshControls = controls
end

function RaidManagement.MountChrome(page, chrome, actions)
    RaidManagement.SetActions(page, page.viewButton, actions.raidLeaderTools, actions.lootMasterTools, actions.addStatistics, actions.export, actions.quit)
    RaidManagement.SetListToolbar(page, {
        filterLabel = chrome.filterLabel,
        classButton = chrome.classButton,
        rankButton = chrome.rankButton,
        resetButton = page.resetFiltersButton,
        searchLabel = chrome.searchLabel,
        searchBox = chrome.searchBox,
        refreshButton = chrome.refreshButton,
        modeButton = chrome.modeButton,
        minimizeButton = chrome.minimizeButton,
    })
    RaidManagement.SetRefreshControls(page, {
        leaderMode = page.leaderModeButton,
        readyCheck = actions.readyCheck, raidInfo = actions.raidInfo,
        title = chrome.title,
        resetFilters = page.resetFiltersButton,
        unavailable = chrome.unavailable,
        status = chrome.status,
        scan = actions.scan,
        loadRaid = actions.loadRaid,
        testRaid = actions.testRaid,
        raidLeaderTools = actions.raidLeaderTools,
        lootMasterTools = actions.lootMasterTools,
        historyTitle = actions.historyTitle,
        historyButtons = actions.historyButtons,
        historyDeleteButtons = actions.historyDeleteButtons,
        historyLoadButtons = actions.historyLoadButtons,
        historyHeaders = actions.historyHeaders,
        historyScroll = actions.historyScroll, historyCanvas = actions.historyCanvas,
        historyEmpty = actions.historyEmpty,
        export = actions.export,
        addStatistics = actions.addStatistics,
        quit = actions.quit,
        lootRules = actions.lootRules,
        sendLootRules = actions.sendLootRules,
        reycoin = actions.reycoin,
        newRoll = actions.newRoll,
        import = actions.import,
        shareSr = actions.shareSr,
        resetLoot = actions.resetLoot,
        live = actions.live,
        searchLabel = chrome.searchLabel,
        searchBox = chrome.searchBox,
        refreshButton = chrome.refreshButton,
        filterLabel = chrome.filterLabel,
        classButton = chrome.classButton,
        rankButton = chrome.rankButton,
        classPanel = chrome.classPanel,
        rankPanel = chrome.rankPanel,
        mode = chrome.modeButton,
        minimize = chrome.minimizeButton,
        minimizedLabel = chrome.minimizedLabel,
    })
end

function RaidManagement.MountGroupView(page, options)
    page.isTestRaid = options.isTestRaid
    page.moveMemberToSlot = options.moveMemberToSlot
    RaidManagement.CreateGroupSelector(page, options.getGroupCounts, options.moveMemberToGroup, options.refresh)
    RaidManagement.CreateGroupViewport(page)
    RaidManagement.CreateDragGhost(page)
    RaidManagement.CreateMemberMenu(page, function(member, action)
        if options.runMemberAction(member, action) then options.refresh() end
    end, options.isPlayerIgnored)
    RaidManagement.CreateGroupGrid(page)
    RaidManagement.SetGroupRenderer(page, {
        ensureDatabase = options.ensureDatabase,
        getLootMasterInfo = options.getLootMasterInfo,
        getRaidMemberCount = options.getRaidMemberCount,
        getRaidMemberInfo = options.getRaidMemberInfo,
    })
    page.refreshGroupView = function() RaidManagement.RefreshGroupView(page) end
    RaidManagement.AttachViewToggle(page, options.onViewChanged)
end

local compactGroupSerial = 0
function RaidManagement.CreateCompactGroupView(parent, dependencies)
    dependencies = dependencies or {}
    local page = Raider.UI.Components.CreateContainer(nil, parent)
    page:SetAllPoints(parent); page:Hide()
    page.mosGroupLayout = true; page.mosGroupLeft = 0; page.mosGroupTop = 0; page.mosGroupBottom = 0
    page.isTestRaid = function() return false end
    page.getGroupSettings = dependencies.getGroupSettings
    page.canManageGroups = dependencies.canManageGroups
    page.moveMemberToSlot = dependencies.moveMemberToSlot or function() return false end
    compactGroupSerial = compactGroupSerial + 1
    CreateGroupCanvas(page, "BootyRaiderCompactRaidGroupScroll" .. compactGroupSerial)
    RaidManagement.CreateDragGhost(page)
    local controller, members = {}, {}
    local function Changed() if dependencies.onChanged then dependencies.onChanged() end end
    RaidManagement.CreateMemberMenu(page, function(member, action)
        if dependencies.runMemberAction and dependencies.runMemberAction(member, action) then Changed() end
    end, dependencies.isPlayerIgnored or function() return false end)
    Raider.UI.Components.Window.ApplyProjectSurface(page.memberMenu)
    RaidManagement.CreateGroupGrid(page)
    if page.getGroupSettings then
        local group, index
        for group = 1, 8 do
            for index = 1, 5 do
                local slot = page.groupSlots[group][index]
                if slot.name.SetWordWrap then
                    slot.name:SetWordWrap(false); slot.class:SetWordWrap(false); slot.level:SetWordWrap(false); slot.offline:SetWordWrap(false); slot.empty:SetWordWrap(false)
                end
            end
        end
    end
    RaidManagement.SetGroupRenderer(page, {
        ensureDatabase = dependencies.ensureDatabase or function() end,
        getLootMasterInfo = dependencies.getLootMasterInfo or function() return nil end,
        getRaidMemberCount = function() return math.min(40, table.getn(members)) end,
        getRaidMemberIndex = function(index) return members[index] and members[index].raidIndex or index end,
        getRaidMemberInfo = function(index)
            local member = members[index]
            if member then return member.name, member.raidRank, member.subgroup, member.level, member.class, member.classFile, member.zone, member.online end
        end,
    })
    page.refreshGroupView = function()
        if dependencies.onChanged then Changed()
        elseif page:IsVisible() then RaidManagement.RefreshGroupView(page) end
    end
    function controller:Render(currentMembers, width, height)
        members = currentMembers or {}
        page.mosCompactGroupWidth = math.max(1, tonumber(width) or 1)
        page.mosCompactGroupHeight = math.max(1, tonumber(height) or 1)
        page:SetWidth(page.mosCompactGroupWidth); page:SetHeight(page.mosCompactGroupHeight)
        page:Show(); page.groupFrame:Show()
        RaidManagement.RefreshGroupView(page)
    end
    function controller:Hide()
        if page.dragGhost:IsShown() then Raider.dragRaidIndex = nil; Raider.raidDropSlot = nil; Raider.raidDragStarted = nil end
        page.dragGhost:SetScript("OnUpdate", nil); page.dragGhost:Hide()
        page.memberMenu:Hide(); page.memberMenuDismiss:Hide(); page.contextSlot = nil
        page:Hide(); members = {}
    end
    function controller:IsVisible() return page:IsVisible() end
    page:SetScript("OnHide", function() controller:Hide() end)
    return controller
end

function RaidManagement.CreateRenderer(options)
    return options
end

function RaidManagement.ClearSessionHeader(page)
    RaidManagement.ResetIssueAttention(page)
    page.classicRaidName:Hide(); page.classicRaidName.mosRaidName = nil; page.classicMeta:Hide(); page.classicMeta.mosRaidId = nil; page.classicSaved:Hide(); page.classicIssues:Hide(); page.classicSummary:Hide()
    page.refreshControls.title:SetText("Raid"); if BootyRaiderDB and BootyRaiderDB.raidHideSectionHeader then page.refreshControls.title:Hide() else page.refreshControls.title:Show() end
end

function RaidManagement.ApplySectionHeaderVisibility(page, raidId, lootMasterMode)
    if lootMasterMode then return end
    page.refreshControls.title:SetText("Raid")
    if BootyRaiderDB.raidHideSectionHeader then page.refreshControls.title:Hide() else page.refreshControls.title:Show() end
end

function RaidManagement.GetToolToolbarOffset(pageWidth, raidView)
    return tonumber(pageWidth) < (raidView == "groups" and 604 or 464) and 30 or 0
end

function RaidManagement.RefreshPage(renderer)
    local page, rows = renderer.page, renderer.rows
    renderer.countRefresh()
    RaidManagement.BeginRefresh(page, rows)
    local pageWidth = PageSpan(page)
    page.classicActionOffset = 0
    page.classicActionScale = 1
    -- The normal metadata row already has nine pixels of top padding. The
    -- added section consumes18px of text plus8px above and below it.
    page.classicSectionOffset = Raider.UI.Components.IsClassicSkin() and not BootyRaiderDB.raidHideSectionHeader and 25 or 0
    page.classicToolbarOffset = Raider.UI.Components.IsClassicSkin() and RaidManagement.GetToolToolbarOffset(pageWidth, page.raidView) or 0
    local lootMasterMode = renderer.isLootMasterMode()
    if page.raidInfoButton then
        if lootMasterMode then page.raidInfoButton:Hide() else
            page.raidInfoButton:ClearAllPoints(); page.raidInfoButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -9 - page.classicSectionOffset); page.raidInfoButton:Show()
        end
    end
    local attendance = renderer.getData()
    local issues
    local importInfo = attendance and attendance.softReserveImport
    local raidId = attendance and (attendance.snapshotId or (importInfo and importInfo.id))
    if attendance and raidId and renderer.isScanReady() then
        local savedText = attendance.lastSavedAt and date("%Y-%m-%d %H:%M", attendance.lastSavedAt) or "Not saved yet"
        if Raider.UI.Components.IsClassicSkin() and not lootMasterMode then
            local issueCount = 0
            issues = Raider.Services.Raid.GetSoftReserveIssues(attendance, page.getSoftReserveRules and page.getSoftReserveRules())
            if table.getn(issues.unmatchedNames) > 0 then issueCount = issueCount + 1 end
            if table.getn(issues.missingNames) > 0 then issueCount = issueCount + 1 end
            if table.getn(issues.invalidNames) > 0 then issueCount = issueCount + 1 end
            page.classicRaidName.mosRaidName = attendance.raidName or "Unknown zone"; page.classicRaidName:SetText(page.classicRaidName.mosRaidName); page.classicRaidName:Show()
            page.classicMeta.mosRaidId = tostring(raidId); page.classicMeta:SetText("|  " .. page.classicMeta.mosRaidId); page.classicMeta:Show()
            page.classicSaved.mosRaidSavedText = savedText; page.classicSaved:SetText(savedText); page.classicSaved:Show()
            RaidManagement.UpdateIssueAttention(page.classicIssues, issues)
            if issueCount > 0 then page.classicIssues.mosRaidIssuesText = issueCount .. " issues"; page.classicIssues:SetText(page.classicIssues.mosRaidIssuesText); page.classicIssues:Show() else page.classicIssues:Hide() end
            RestoreHeaderFont(page.classicRaidName); RestoreHeaderFont(page.classicMeta)
            local titleWidth = math.max(48, page.classicRaidName:GetStringWidth() + 4)
            local metaWidth = math.max(42, page.classicMeta:GetStringWidth() + 4)
            page.classicRaidName:SetWidth(titleWidth); page.classicMeta:SetWidth(metaWidth)
            page.classicActionOffset = 0
        else
            page.refreshControls.title:Show(); page.classicRaidName:Hide(); page.classicMeta:Hide(); page.classicSaved:Hide(); page.classicIssues:Hide()
            page.refreshControls.title:SetText("Raid")
        end
    else
        page.refreshControls.title:Show(); page.classicRaidName:Hide(); page.classicMeta:Hide(); page.classicSaved:Hide(); page.classicIssues:Hide()
        page.refreshControls.title:SetText("Raid")
    end
    if lootMasterMode then
        page.classicRaidName:Hide(); page.classicMeta:Hide()
        page.classicSaved:Hide(); page.classicIssues:Hide()
        page.refreshControls.title:SetText("Loot Master Mode")
        if renderer.isLootMasterMinimized() then page.refreshControls.title:Hide() else page.refreshControls.title:Show() end
    end
    RaidManagement.ApplySectionHeaderVisibility(page, raidId, lootMasterMode)
    page.classicSummary:Hide()
    if lootMasterMode and renderer.isLootMasterMinimized() then
        RaidManagement.ShowMinimizedLootMasterState(page, rows)
        return
    end
    if not renderer.isInRaid() and not renderer.isHistoricalLoaded() then
        RaidManagement.ClearSessionHeader(page)
        renderer.setScanReady(false)
        RaidManagement.ShowNoRaidState(page, rows)
        return
    end
    renderer.unavailable:Hide()
    if not renderer.isScanReady() then
        RaidManagement.ClearSessionHeader(page)
        RaidManagement.ShowScanRequiredState(page, rows)
        return
    end
    RaidManagement.ShowReadyState(page, lootMasterMode)
    local query = string.lower(renderer.searchBox:GetText() or "")
    RaidManagement.PrepareListMembers(page, renderer.visibleMembers, attendance, query, renderer.selectedClasses, renderer.selectedRanks, renderer.getSelectedName())
    RaidManagement.UpdateViewSelector(page, lootMasterMode)
    if not lootMasterMode and page.raidView == "groups" then
        RaidManagement.ShowGroupView(page, rows, issues)
        return
    end
    RaidManagement.RefreshListView(page, rows, renderer.visibleMembers, renderer.getSelectedName(), renderer.getSortKey(), lootMasterMode, renderer.getSettings(), issues)
end

function RaidManagement.ShowMinimizedLootMasterState(page, rows)
    if page.toolDropdowns then for _, panel in pairs(page.toolDropdowns) do panel:Hide() end end
    local controls = page.refreshControls
    controls.leaderMode:Hide(); controls.resetFilters:Hide()
    controls.unavailable:Hide(); controls.status:Hide(); controls.scan:Hide(); controls.testRaid:Hide(); controls.raidLeaderTools:Hide(); controls.lootMasterTools:Hide(); controls.addStatistics:Hide(); controls.export:Hide(); controls.quit:Hide(); controls.lootRules:Hide(); controls.sendLootRules:Hide(); controls.import:Hide(); controls.shareSr:Hide(); controls.resetLoot:Hide(); controls.live:Hide()
    controls.searchLabel:Hide(); controls.searchBox:Hide(); controls.refreshButton:Hide(); controls.filterLabel:Hide(); controls.classButton:Hide(); controls.rankButton:Hide(); controls.classPanel:Hide(); controls.rankPanel:Hide()
    RaidManagement.HideRaidHistoryControls(controls)
    RaidManagement.HideListTable(page, rows)
    controls.minimizedLabel:ClearAllPoints(); controls.minimizedLabel:SetPoint("LEFT", page, "LEFT", 5, 0); controls.minimizedLabel:SetWidth(68); controls.minimizedLabel:Show()
    controls.mode:ClearAllPoints(); controls.mode:SetPoint("RIGHT", page, "RIGHT", -5, 0); controls.mode:SetWidth(18); controls.mode:SetHeight(18); Raider.UI.Components.SetWindowButtonAction(controls.mode, "close"); controls.mode:Show()
    controls.minimize:ClearAllPoints(); controls.minimize:SetPoint("RIGHT", controls.mode, "LEFT", -4, 0); controls.minimize:SetWidth(18); controls.minimize:SetHeight(18); Raider.UI.Components.SetWindowButtonAction(controls.minimize, "maximize"); controls.minimize:Show()
    page.lmConfigToggle:ClearAllPoints(); page.lmConfigToggle:SetPoint("RIGHT", controls.minimize, "LEFT", -4, 0); page.lmConfigToggle:Show()
    page.reyCoinToggle:ClearAllPoints(); page.reyCoinToggle:SetPoint("RIGHT", page.lmConfigToggle, "LEFT", -4, 0); page.reyCoinToggle:Show()
end

function RaidManagement.ShowNoRaidState(page, rows)
    if page.toolDropdowns then for _, panel in pairs(page.toolDropdowns) do panel:Hide() end end
    local controls = page.refreshControls
    controls.leaderMode:Hide(); controls.resetFilters:Hide(); controls.mode:Hide(); controls.unavailable:Show()
    controls.unavailable:ClearAllPoints(); controls.unavailable:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -48); controls.unavailable:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -48); controls.unavailable:SetHeight(0); if controls.unavailable.SetWordWrap then controls.unavailable:SetWordWrap(true) end
    controls.raidLeaderTools:Hide(); controls.lootMasterTools:Hide(); controls.addStatistics:Hide(); controls.export:Hide(); controls.quit:Hide(); controls.lootRules:Hide(); controls.sendLootRules:Hide(); controls.import:Hide(); controls.shareSr:Hide(); controls.resetLoot:Hide(); controls.minimize:Hide(); controls.live:Hide()
    controls.searchLabel:Hide(); controls.searchBox:Hide(); controls.refreshButton:Hide(); controls.filterLabel:Hide(); controls.classButton:Hide(); controls.rankButton:Hide(); controls.classPanel:Hide(); controls.rankPanel:Hide()
    RaidManagement.HideListTable(page, rows); controls.status:SetText(""); controls.unavailable:SetText("Join a raid to start a new snapshot, or load a saved raid.")
    RaidManagement.ShowRaidHistoryControls(page, controls, false)
end

function RaidManagement.ShowScanRequiredState(page, rows)
    if page.toolDropdowns then for _, panel in pairs(page.toolDropdowns) do panel:Hide() end end
    local controls = page.refreshControls
    controls.leaderMode:Hide(); controls.resetFilters:Hide(); controls.mode:Hide()
    controls.raidLeaderTools:Hide(); controls.lootMasterTools:Hide(); controls.addStatistics:Hide(); controls.export:Hide(); controls.quit:Hide(); controls.lootRules:Hide(); controls.sendLootRules:Hide(); controls.import:Hide(); controls.shareSr:Hide(); controls.resetLoot:Hide(); controls.minimize:Hide(); controls.live:Hide()
    controls.searchLabel:Hide(); controls.searchBox:Hide(); controls.refreshButton:Hide(); controls.filterLabel:Hide(); controls.classButton:Hide(); controls.rankButton:Hide()
    RaidManagement.HideListTable(page, rows); controls.status:SetText("")
    RaidManagement.ShowRaidHistoryControls(page, controls, true)
end

function RaidManagement.ShowScanningState(page, rows)
    local controls = page.refreshControls
    page.groupFrame:Hide(); page.viewButton:Hide()
    controls.leaderMode:Hide(); controls.resetFilters:Hide(); controls.mode:Hide(); controls.raidLeaderTools:Hide(); controls.lootMasterTools:Hide(); controls.unavailable:Hide(); controls.status:Hide(); controls.scan:Hide()
    controls.addStatistics:Hide(); controls.export:Hide(); controls.quit:Hide(); controls.lootRules:Hide(); controls.sendLootRules:Hide(); controls.import:Hide(); controls.shareSr:Hide(); controls.resetLoot:Hide(); controls.minimize:Hide(); controls.live:Hide()
    controls.searchLabel:Hide(); controls.searchBox:Hide(); controls.refreshButton:Hide(); controls.filterLabel:Hide(); controls.classButton:Hide(); controls.rankButton:Hide(); controls.classPanel:Hide(); controls.rankPanel:Hide()
    RaidManagement.HideRaidHistoryControls(controls); RaidManagement.HideListTable(page, rows)
    page.softReserveWarning:Hide(); page.missingSoftReserveWarning:Hide(); page.invalidSoftReserveWarning:Hide()
end

function RaidManagement.UpdateActionAvailability(page, testRaid)
    local controls = page.refreshControls
    Raider.UI.Components.SetButtonEnabled(controls.export, not testRaid)
    Raider.UI.Components.SetClassicButtonDisabled(controls.export, testRaid and true or false)
    controls.shareSr:Enable(); controls.import:Enable()
    if controls.newRoll then
        local rolls=Raider.Modules.MasterLootWindow
        Raider.UI.Components.SetButtonEnabled(controls.newRoll,not testRaid and rolls and rolls.CanStartManualRoll and rolls.CanStartManualRoll() or false)
    end
    if controls.readyCheck then
        Raider.UI.Components.SetButtonEnabled(controls.readyCheck, not testRaid and Raider.Services.Raid.CanReadyCheck and Raider.Services.Raid.CanReadyCheck() or false)
    end
end

function RaidManagement.ShowReadyState(page, lootMasterMode)
    if lootMasterMode and page.toolDropdowns then for _, panel in pairs(page.toolDropdowns) do panel:Hide() end end
    local controls = page.refreshControls
    if Raider.UI.Components.IsClassicSkin() and not lootMasterMode then page.classicToolbar:Show() else page.classicToolbar:Hide() end
    page.classicSummary:Hide()
    controls.mode:Show(); controls.scan:Hide(); controls.live:Hide()
    controls.testRaid:Hide()
    RaidManagement.HideRaidHistoryControls(controls)
    controls.scan:ClearAllPoints(); controls.scan:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -42); controls.scan:SetWidth(98); controls.scan:SetHeight(22); controls.scan:SetText("Scan again")
    if lootMasterMode then
        page.lmConfigToggle:Show()
        if page.lmConfigOpen then page.lmConfigPanel:Show() end
        controls.leaderMode:Hide(); controls.resetFilters:Hide(); controls.raidLeaderTools:Hide(); controls.lootMasterTools:Hide(); controls.addStatistics:Hide(); controls.export:Hide(); controls.quit:Hide(); controls.lootRules:Hide(); controls.sendLootRules:Hide(); controls.import:Hide(); controls.shareSr:Hide(); controls.scan:Hide(); controls.resetLoot:Hide(); controls.live:Hide()
        controls.mode:ClearAllPoints(); controls.mode:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -8); controls.mode:SetWidth(18); controls.mode:SetHeight(18); Raider.UI.Components.SetWindowButtonAction(controls.mode, "close"); controls.mode:Show()
        controls.minimize:ClearAllPoints(); controls.minimize:SetPoint("RIGHT", controls.mode, "LEFT", -4, 0); controls.minimize:SetWidth(18); controls.minimize:SetHeight(18); controls.minimize:Show(); Raider.UI.Components.SetWindowButtonAction(controls.minimize, "minimize")
        controls.classButton:Hide(); controls.rankButton:Hide(); controls.classPanel:Hide(); controls.rankPanel:Hide()
    else
        controls.resetFilters:Show(); controls.raidLeaderTools:Show(); controls.lootMasterTools:Show(); controls.addStatistics:Hide(); controls.export:Show(); controls.quit:Show()
        controls.leaderMode:Hide(); controls.mode:Hide(); controls.lootRules:Hide(); controls.sendLootRules:Hide(); controls.import:Hide(); controls.shareSr:Hide(); controls.resetLoot:Hide()
        RaidManagement.UpdateActionAvailability(page, page.isTestRaid and page.isTestRaid())
        controls.live:Hide(); controls.scan:Hide(); controls.minimize:Hide()
        RaidManagement.UpdateToolSubmenu(page)
    end
end

function RaidManagement.UpdateViewSelector(page, lootMasterMode)
    if lootMasterMode then return end
    if Raider.UI.Components.IsClassicSkin() then
        page.viewButton:Hide()
        page.classicListButton:Show(); page.classicGroupButton:Show()
        if page.raidView == "groups" then page.classicTwoButton:Show(); page.classicFourButton:Show()
        else page.classicTwoButton:Hide(); page.classicFourButton:Hide() end
        Raider.UI.Components.SetClassicButtonSelected(page.classicListButton, page.raidView == "list")
        Raider.UI.Components.SetClassicButtonSelected(page.classicGroupButton, page.raidView == "groups")
        Raider.UI.Components.SetClassicButtonSelected(page.classicTwoButton, page.raidView == "groups" and tonumber(BootyRaiderDB.raidGroupColumns) == 2)
        Raider.UI.Components.SetClassicButtonSelected(page.classicFourButton, page.raidView == "groups" and tonumber(BootyRaiderDB.raidGroupColumns) == 4)
        RaidManagement.LayoutActions(page)
        return
    end
    page.classicListButton:Hide(); page.classicGroupButton:Hide(); page.classicTwoButton:Hide(); page.classicFourButton:Hide()
    page.viewButton:SetText(page.raidView == "groups" and "List View" or "Group View")
    page.viewButton:Show()
    RaidManagement.LayoutActions(page)
end

function RaidManagement.LayoutSoftReserveWarnings(page, lootMasterMode, side, issues)
    -- A full refresh shares its freshly computed issues with the header. Direct
    -- layout calls still resolve current data; no result is retained on the page.
    if not issues then
        local attendance = page.getSoftReserveData and page.getSoftReserveData() or nil
        issues = Raider.Services.Raid.GetSoftReserveIssues(attendance, page.getSoftReserveRules and page.getSoftReserveRules())
    end
    local unmatchedNames, missingNames, invalidNames = issues.unmatchedNames, issues.missingNames, issues.invalidNames
    local unmatchedCount = unmatchedNames and table.getn(unmatchedNames) or 0
    local missingCount = missingNames and table.getn(missingNames) or 0
    local invalidCount = table.getn(invalidNames)
    if page.softReserveWarning.lastDataCount == nil then page.softReserveWarning.lastDataCount = unmatchedCount
    elseif page.softReserveWarning.lastDataCount ~= unmatchedCount then page.softReserveWarning.lastDataCount = unmatchedCount; page.softReserveWarning.userDismissed = false end
    if page.missingSoftReserveWarning.lastDataCount == nil then page.missingSoftReserveWarning.lastDataCount = missingCount
    elseif page.missingSoftReserveWarning.lastDataCount ~= missingCount then page.missingSoftReserveWarning.lastDataCount = missingCount; page.missingSoftReserveWarning.userDismissed = false end
    if page.invalidSoftReserveWarning.lastDataCount == nil then page.invalidSoftReserveWarning.lastDataCount = invalidCount
    elseif page.invalidSoftReserveWarning.lastDataCount ~= invalidCount then page.invalidSoftReserveWarning.lastDataCount = invalidCount; page.invalidSoftReserveWarning.userDismissed = false end
    local showUnmatched = not lootMasterMode and unmatchedCount > 0 and not page.softReserveWarning.userDismissed
    local showMissing = not lootMasterMode and missingCount > 0 and not page.missingSoftReserveWarning.userDismissed
    local showInvalid = not lootMasterMode and invalidCount > 0 and not page.invalidSoftReserveWarning.userDismissed
    if not showUnmatched then page.softReserveWarning:Hide() end
    if not showMissing then page.missingSoftReserveWarning:Hide() end
    if not showInvalid then page.invalidSoftReserveWarning:Hide() end
    page.classicWarningBottom = 0
    local cards = {page.softReserveWarning, page.missingSoftReserveWarning, page.invalidSoftReserveWarning}
    for index = 1, 3 do
        local card = cards[index]
        card.text:Show(); card.info:Show(); card.fix:Show(); if card.ping then card.ping:Show() end
    end
    if not showUnmatched and not showMissing and not showInvalid then return 0, 0 end
    local visible = {showUnmatched, showMissing, showInvalid}
    local titles = {"Unassigned SR", "Missing SR", "Invalid SR"}
    local dockCount = 0
    for index = 1, 3 do
        local card = cards[index]
        card.docked = visible[index] and (card.userMinimized or (side and PageSpan(page) < 620 and not card.forceExpanded)) or false
        if card.docked then dockCount = dockCount + 1 end
        if card.classicHeader then
            if card.classicHeader.minimize then Raider.UI.Components.SetWindowButtonAction(card.classicHeader.minimize, card.docked and "maximize" or "minimize") end
            if card.classicHeader.divider then
                if card.docked then card.classicHeader.divider:Hide() else card.classicHeader.divider:Show() end
            end
        end
    end
    local dockIndex = 0
    for index = 1, 3 do
        local card = cards[index]
        if card.docked then
            local minimumContent = 339 -- minimum dashboard content without sidebar; dock width stays stable
            local width = math.max(1, math.min(minimumContent / 2, (PageSpan(page) - 4 - 2 * (dockCount - 1)) / dockCount))
            card:ClearAllPoints(); card:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 2 + dockIndex * (width + 2), 2)
            card:SetWidth(width); card:SetHeight(30)
            card.text:Hide(); card.info:Hide(); card.fix:Hide(); if card.ping then card.ping:Hide() end
            if card.classicHeader then card.classicHeader:Show(); card.classicHeader.title:SetText(titles[index]); card.classicHeader.title:SetTextColor(1, 1, 1) end
            card:Show(); dockIndex = dockIndex + 1; visible[index] = false
        end
    end
    page.classicWarningBottom = dockCount > 0 and 34 or 0
    showUnmatched, showMissing, showInvalid = visible[1], visible[2], visible[3]
    if not showUnmatched and not showMissing and not showInvalid then return 0, page.classicWarningBottom end
    for index = 1, 3 do
        if cards[index].classicHeader and not cards[index].docked then cards[index].classicHeader.title:SetText("Warning"); cards[index].classicHeader.title:SetTextColor(1, 0.82, 0.28) end
    end
    if side then
        local pageWidth, pageHeight = PageSpan(page)
        local width = math.min(250, math.max(210, math.floor(pageWidth * 0.30)))
        local top = -100 - (page.classicSectionOffset or 0) - (page.classicActionOffset or 0) - (page.classicToolbarOffset or 0)
        local available = math.max(0, pageHeight + top - 8 - (page.classicWarningBottom or 0))
        local shownCount = (showUnmatched and 1 or 0) + (showMissing and 1 or 0) + (showInvalid and 1 or 0)
        local gap = shownCount > 1 and 8 or 0
        local cardHeight = math.min(115, math.max(1, math.floor((available - gap * (shownCount - 1)) / shownCount)))
        local unmatchedHeight, missingHeight, invalidHeight = showUnmatched and cardHeight or 0, showMissing and cardHeight or 0, showInvalid and cardHeight or 0
        if showUnmatched then
            local warning = page.softReserveWarning
            warning:ClearAllPoints(); warning:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, top); warning:SetWidth(width); warning:SetHeight(unmatchedHeight)
            warning.text:SetText("Unassigned SR in imported SR"); warning.details = "The following players have Soft Reserves but are not currently in the raid:\n\n" .. table.concat(unmatchedNames, "\n"); warning:Show()
            local compact = unmatchedHeight < 90
            warning.text:ClearAllPoints(); warning.text:SetPoint("TOPLEFT", warning, "TOPLEFT", 15, -36); warning.text:SetPoint("TOPRIGHT", warning, "TOPRIGHT", -15, -36); warning.text:SetJustifyH("LEFT")
            warning.fix:ClearAllPoints(); warning.fix:SetPoint("BOTTOMLEFT", warning, "BOTTOMLEFT", 12, compact and 6 or 10); warning.fix:SetWidth(math.floor((width - 31) / 2)); warning.fix:SetHeight(22)
            warning.info:ClearAllPoints(); warning.info:SetPoint("LEFT", warning.fix, "RIGHT", 7, 0); warning.info:SetWidth(math.floor((width - 31) / 2)); warning.info:SetHeight(22)
            top = top - unmatchedHeight - gap
        end
        if showMissing then
            local warning = page.missingSoftReserveWarning
            warning:ClearAllPoints(); warning:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, top); warning:SetWidth(width); warning:SetHeight(missingHeight)
            warning.text:SetText("Raid members without SR"); warning.details = "The following raid members do not have a Soft Reserve:\n\n" .. table.concat(missingNames, "\n"); warning:Show()
            local compact = missingHeight < 90
            warning.text:ClearAllPoints(); warning.text:SetPoint("TOPLEFT", warning, "TOPLEFT", 15, -36); warning.text:SetPoint("TOPRIGHT", warning, "TOPRIGHT", -15, -36); warning.text:SetJustifyH("LEFT")
            local actionWidth = math.floor((width - 38) / 3)
            warning.fix:ClearAllPoints(); warning.fix:SetPoint("BOTTOMLEFT", warning, "BOTTOMLEFT", 12, compact and 6 or 10); warning.fix:SetWidth(actionWidth); warning.fix:SetHeight(22)
            warning.info:ClearAllPoints(); warning.info:SetPoint("LEFT", warning.fix, "RIGHT", 7, 0); warning.info:SetWidth(actionWidth); warning.info:SetHeight(22)
            warning.ping:ClearAllPoints(); warning.ping:SetPoint("LEFT", warning.info, "RIGHT", 7, 0); warning.ping:SetWidth(actionWidth); warning.ping:SetHeight(22)
            top = top - missingHeight - gap
        end
        if showInvalid then
            local warning = page.invalidSoftReserveWarning
            warning:ClearAllPoints(); warning:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, top); warning:SetWidth(width); warning:SetHeight(invalidHeight)
            warning.text:SetText("SR without loot rights")
            warning.details = "The following raid members have Soft Reserves without the required loot rights:\n\n" .. table.concat(invalidNames, "\n")
            warning:Show()
            warning.text:ClearAllPoints(); warning.text:SetPoint("TOPLEFT", warning, "TOPLEFT", 15, -36); warning.text:SetPoint("TOPRIGHT", warning, "TOPRIGHT", -15, -36); warning.text:SetJustifyH("LEFT")
            local actionWidth = math.floor((width - 38) / 3)
            warning.fix:ClearAllPoints(); warning.fix:SetPoint("BOTTOMLEFT", warning, "BOTTOMLEFT", 12, 6); warning.fix:SetWidth(actionWidth); warning.fix:SetHeight(22)
            warning.info:ClearAllPoints(); warning.info:SetPoint("LEFT", warning.fix, "RIGHT", 7, 0); warning.info:SetWidth(actionWidth); warning.info:SetHeight(22)
            warning.ping:ClearAllPoints(); warning.ping:SetPoint("LEFT", warning.info, "RIGHT", 7, 0); warning.ping:SetWidth(actionWidth); warning.ping:SetHeight(22)
        end
        for index = 1, 3 do
            local card = cards[index]
            for _, button in ipairs({card.fix, card.info, card.ping}) do
                Raider.UI.Components.FitButtonLabel(button, math.max(1, button:GetWidth() - 28))
                Raider.UI.Components.SetButtonLabelInsets(button, 23, 5)
            end
        end
        return width, page.classicWarningBottom
    end
    return 0, page.classicWarningBottom
end

function RaidManagement.RestoreDefaultWarningLayout(page)
    local outside, missing = page.softReserveWarning, page.missingSoftReserveWarning
    outside.text:ClearAllPoints(); outside.text:SetPoint("LEFT", outside, "LEFT", 9, -5); outside.text:SetPoint("RIGHT", outside, "RIGHT", -84, -5); outside.text:SetJustifyH("CENTER")
    outside.fix:ClearAllPoints(); outside.fix:SetPoint("TOPRIGHT", outside, "TOPRIGHT", -8, -6); outside.fix:SetWidth(66); outside.fix:SetHeight(20)
    outside.info:ClearAllPoints(); outside.info:SetPoint("BOTTOMRIGHT", outside, "BOTTOMRIGHT", -8, 6); outside.info:SetWidth(66); outside.info:SetHeight(20)
    missing.text:ClearAllPoints(); missing.text:SetPoint("LEFT", missing, "LEFT", 9, -5); missing.text:SetPoint("RIGHT", missing, "RIGHT", -84, -5); missing.text:SetJustifyH("CENTER")
    missing.fix:ClearAllPoints(); missing.fix:SetPoint("TOPRIGHT", missing, "TOPRIGHT", -8, -4); missing.fix:SetWidth(66); missing.fix:SetHeight(14)
    missing.info:ClearAllPoints(); missing.info:SetPoint("TOPRIGHT", missing, "TOPRIGHT", -8, -21); missing.info:SetWidth(66); missing.info:SetHeight(14)
    missing.ping:ClearAllPoints(); missing.ping:SetPoint("TOPRIGHT", missing, "TOPRIGHT", -8, -38); missing.ping:SetWidth(66); missing.ping:SetHeight(14)
    local invalid = page.invalidSoftReserveWarning
    invalid.text:ClearAllPoints(); invalid.text:SetPoint("LEFT", invalid, "LEFT", 9, -5); invalid.text:SetPoint("RIGHT", invalid, "RIGHT", -84, -5); invalid.text:SetJustifyH("CENTER")
    invalid.fix:ClearAllPoints(); invalid.fix:SetPoint("TOPRIGHT", invalid, "TOPRIGHT", -8, -4); invalid.fix:SetWidth(66); invalid.fix:SetHeight(14)
    invalid.info:ClearAllPoints(); invalid.info:SetPoint("TOPRIGHT", invalid, "TOPRIGHT", -8, -21); invalid.info:SetWidth(66); invalid.info:SetHeight(14)
    invalid.ping:ClearAllPoints(); invalid.ping:SetPoint("TOPRIGHT", invalid, "TOPRIGHT", -8, -38); invalid.ping:SetWidth(66); invalid.ping:SetHeight(14)
end

function RaidManagement.ShowGroupView(page, rows, issues)
    local controls = page.refreshControls
    controls.resetFilters:Hide(); controls.searchLabel:Hide(); controls.searchBox:Hide(); controls.refreshButton:Hide(); controls.filterLabel:Hide()
    controls.classButton:Hide(); controls.rankButton:Hide(); controls.classPanel:Hide(); controls.rankPanel:Hide()
    if page.filterToolbar then page.filterToolbar:Hide() end
    RaidManagement.HideListTable(page, rows)
    page.groupFrame:ClearAllPoints()
    if Raider.UI.Components.IsClassicSkin() then
        local warningWidth = RaidManagement.LayoutSoftReserveWarnings(page, false, true, issues)
        if not page.softReserveWarning:IsShown() and not page.missingSoftReserveWarning:IsShown() and not page.invalidSoftReserveWarning:IsShown() then warningWidth = 0 end
        -- 2px warning inset + 7.5px outer clearance (4px window + 1.5px page + 2px warning) + 20px scrollbar/gap.
        page.groupFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -100 - (page.classicSectionOffset or 0) - (page.classicActionOffset or 0) - (page.classicToolbarOffset or 0)); page.groupFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 4)
        if page.groupScrollBar then
            page.groupScrollBar:ClearAllPoints(); page.groupScrollBar:SetWidth(16)
            page.groupScrollBar:SetPoint("TOPLEFT", page.groupFrame, "TOPRIGHT", 4, -12)
            page.groupScrollBar:SetPoint("BOTTOMLEFT", page.groupFrame, "BOTTOMRIGHT", 4, 12)
        end
    else
        local warningWidth = RaidManagement.LayoutSoftReserveWarnings(page, false, true, issues)
        page.groupFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -72); page.groupFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 5)
    end
    page.mosGroupLayout = true
    page.mosGroupLeft = Raider.UI.Components.IsClassicSkin() and 10 or 6
    page.mosGroupTop = Raider.UI.Components.IsClassicSkin() and (-100 - (page.classicSectionOffset or 0) - (page.classicActionOffset or 0) - (page.classicToolbarOffset or 0)) or -72
    page.mosGroupBottom = Raider.UI.Components.IsClassicSkin() and 4 or 5
    page.groupFrame:Show(); if page.listScrollBar then page.listScrollBar:Hide() end
    page.refreshGroupView()
end

function RaidManagement.SetListRenderer(page, dependencies)
    page.listRenderer = dependencies
end

function RaidManagement.PrepareListMembers(page, target, data, query, selectedClasses, selectedRanks, selectedName)
    local members = data and data.members or {}
    if page.filterData ~= data then
        page.filterController:Build(members)
        page.filterData = data
    end
    RaidManagement.FilterMembers(target, members, query, selectedClasses, selectedRanks)
    table.sort(target, page.listRenderer.sortMembers)
    local selectedVisible = false
    local index
    for index = 1, table.getn(target) do
        if target[index].name == selectedName then selectedVisible = true; break end
    end
    if not selectedVisible then page.listRenderer.onSelectionMissing() end
    page.refreshControls.status:SetText(table.getn(target) .. " / " .. table.getn(members) .. " members")
    page.refreshControls.status:Hide()
    return members
end

function RaidManagement.LootMasterExpandedHeight(availableHeight, memberCount)
    local neighborHeight = math.min(2, math.max(0, memberCount - 1)) * 21
    return math.min(131, math.max(80, availableHeight - neighborHeight))
end

function RaidManagement.RefreshListView(page, rows, members, selectedName, sortKey, lootMasterMode, settings, issues)
    local renderer = page.listRenderer
    if not page.detachedLootMaster then RaidManagement.LayoutSoftReserveWarnings(page, lootMasterMode, true, issues) end
    page.classicWarningWidth = 0
    local pageWidth = PageSpan(page)
    local filterWidth = pageWidth < 650 and 60 or 84
    local searchSpace = pageWidth - (page.classicWarningWidth or 0) - ((page.classicWarningWidth or 0) > 0 and 8 or 12)
    local searchFixed = (filterWidth * 2) + 174
    local searchWidth = searchSpace - searchFixed
    page.classicSearchOffset = not lootMasterMode and Raider.UI.Components.IsClassicSkin() and settings.raidListShowFilters and settings.raidListShowSearch and searchWidth < 90 and 30 or 0
    page.classicSearchWidth = (page.classicSearchOffset or 0) > 0 and math.max(60, math.min(178, searchSpace - 93)) or math.max(90, math.min(178, searchWidth))
    if not settings.raidListShowFilters then page.classicSearchWidth = math.max(90, math.min(178, searchSpace - 40)) end
    if not page.detachedLootMaster then RaidManagement.LayoutListToolbar(page, lootMasterMode, settings) end
    local rowStartY, tableLeft, tableWidth = RaidManagement.LayoutListHeaders(page, page.listHeaderUI.buttons, sortKey, lootMasterMode, settings.raidListRowWidth, table.getn(members), selectedName)
    local warningHeight = 0
    local scrollFrame = page.listScrollFrame
    local listBottom = lootMasterMode and 1.5 or (Raider.UI.Components.IsClassicSkin() and 4 or 11)
    scrollFrame:ClearAllPoints(); scrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", tableLeft, rowStartY); scrollFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", tableLeft + tableWidth, listBottom + warningHeight)
    if page.listScrollBar then
        local scrollBarBottom = lootMasterMode and (listBottom + 12) or (Raider.UI.Components.IsClassicSkin() and 16 or listBottom)
        page.listScrollBar:ClearAllPoints(); page.listScrollBar:SetWidth(16); page.listScrollBar:SetPoint("TOPLEFT", page, "TOPLEFT", tableLeft + tableWidth + 4, rowStartY); page.listScrollBar:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", tableLeft + tableWidth + 4, scrollBarBottom + warningHeight)
    end
    local rowStep = lootMasterMode and 21 or ((tonumber(settings.raidListRowHeight) or 20) + 1)
    scrollFrame.rowStep = rowStep
    -- Anchor resolution can lag this refresh in the 1.12 client. Derive the
    -- viewport from the same page bounds used to place the rows and scrollbar.
    local _, pageHeight = PageSpan(page)
    local rowAreaHeight = math.max(0, pageHeight + rowStartY - listBottom - warningHeight)
    local availableRows = RaidManagement.CalculateVisibleRows(rowAreaHeight, 0, rowStep, table.getn(rows), 3)
    scrollFrame:Show()
    local expandedHeight, visibleRowCount = nil, availableRows
    if selectedName then
        if lootMasterMode then
            expandedHeight = RaidManagement.LootMasterExpandedHeight(rowAreaHeight, table.getn(members))
            visibleRowCount = math.max(1, math.min(table.getn(rows), 1 + math.floor((rowAreaHeight - expandedHeight) / rowStep)))
        else visibleRowCount = math.max(1, availableRows - 7) end
    end
    if not lootMasterMode or page.mosLastLootSelection ~= selectedName then
        RaidManagement.KeepSelectionVisible(scrollFrame, members, selectedName, visibleRowCount, rowStep)
    end
    page.mosLastLootSelection = selectedName
    local offset = renderer.updateScrollFrame(scrollFrame, table.getn(members), visibleRowCount, rowStep)
    local lootMethod, raidLootMasterIndex = renderer.getLootMasterInfo()
    RaidManagement.RenderListRows(page, rows, members, offset, visibleRowCount, rowStep, rowStartY, lootMasterMode, tableLeft, tableWidth, lootMethod, raidLootMasterIndex, selectedName, renderer.shorten, expandedHeight)
end

function RaidManagement.CompareMembers(a, b, sortKey, ascending)
    if not sortKey then
        if (tonumber(a.subgroup) or 0) == (tonumber(b.subgroup) or 0) then
            return string.lower(a.name or "") < string.lower(b.name or "")
        end
        return (tonumber(a.subgroup) or 0) < (tonumber(b.subgroup) or 0)
    end
    local av, bv = a[sortKey] or "", b[sortKey] or ""
    if sortKey == "subgroup" or sortKey == "level" then
        av, bv = tonumber(av) or 0, tonumber(bv) or 0
    else
        av, bv = string.lower(tostring(av)), string.lower(tostring(bv))
    end
    if av == bv then av, bv = string.lower(a.name or ""), string.lower(b.name or "") end
    if ascending then return av < bv end
    return av > bv
end

function RaidManagement.CalculateVisibleRows(pageHeight, reservedHeight, rowStep, poolSize, minimum)
    local height = math.max(0, (tonumber(pageHeight) or 0) - (tonumber(reservedHeight) or 0))
    local step = math.max(1, tonumber(rowStep) or 1)
    return math.max(tonumber(minimum) or 0, math.min(tonumber(poolSize) or 0, math.floor(height / step)))
end

function RaidManagement.PrintListLayoutDiagnostics(page, members, selectedName)
    local frame = page.listScrollFrame
    local rows = page.listRows
    local first = rows and rows[1]
    local last
    local shown = 0
    local index
    for index = 1, table.getn(rows or {}) do
        if rows[index]:IsShown() then last = rows[index]; shown = shown + 1 end
    end
    local function number(value) return tonumber(value) or 0 end
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Raider raid bounds: page %.0fx%.0f at %.0f..%.0f; viewport %.0fx%.0f", number(page:GetWidth()), number(page:GetHeight()), number(page:GetLeft()), number(page:GetRight()), number(frame:GetWidth()), number(frame:GetHeight())))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Raider raid rows: members=%d shown=%d selected=%s step=%d offset=%d warnings=%s/%s", table.getn(members or {}), shown, tostring(selectedName or "none"), number(frame.rowStep), number(frame.offset), tostring(page.softReserveWarning:IsShown()), tostring(page.missingSoftReserveWarning:IsShown())))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Raider raid edges: page right=%.0f bottom=%.0f; row right=%.0f last bottom=%.0f; scroll right=%.0f bottom=%.0f", number(page:GetRight()), number(page:GetBottom()), first and number(first:GetRight()) or 0, last and number(last:GetBottom()) or 0, page.listScrollBar and number(page.listScrollBar:GetRight()) or 0, page.listScrollBar and number(page.listScrollBar:GetBottom()) or 0))
end

local groupMemberArtwork = {path="Interface\\RaidFrame\\UI-RaidFrame-GroupButton", width=164, height=14, inset=3, coords={0,0.640625,0,0.4375}}
local groupHoverArtwork = {path="Interface\\RaidFrame\\UI-RaidFrame-GroupButton", width=164, height=14, inset=3, coords={0,0.640625,0.46875,0.90625}}
local groupOutlineArtwork = {path="Interface\\RaidFrame\\UI-RaidFrame-GroupOutline", width=170, height=80, inset=4, coords={0,0.6640625,0,0.625}}

function RaidManagement.ApplyGroupViewBackground(host, settings, nativeBackground)
    local UI = Raider.UI.Components
    local color = settings.raidGroupViewBackgroundColor or settings.raidGroupBackgroundColor
    if settings.raidGroupViewBackgroundTexture == "game" then
        -- The stock Friends artwork already owns the native stone background.
        -- Keep it visible; painting a stretched dialog image would replace it.
        if nativeBackground then UI.SetTextureBackground(host, nil)
        else UI.SetTextureBackground(host, "Interface\\DialogFrame\\UI-DialogBox-Background", nil, 1) end
    else UI.SetTextureBackground(host, "Interface\\Buttons\\WHITE8X8", color, 1) end
end

function RaidManagement.ApplyGroupTileAppearance(panel, header, height, settings)
    settings = settings or BootyRaiderDB
    local text, background, border = settings.raidGroupHeaderTextColor, settings.raidGroupHeaderBackgroundColor, settings.raidGroupBorderColor
    local hoverText = settings.raidGroupHeaderHoverTextColor or text
    header:SetTextColor(unpack(panel.headerHovered and hoverText or text))
    panel:SetBackdropBorderColor(0, 0, 0, 0)
    local UI = Raider.UI.Components
    if settings.raidGroupBorderTexture == "game" then
        if panel.mosProjectOutline then panel.mosProjectOutline:Hide() end
        UI.SetAtlasOutline(panel, settings.raidGroupShowBorder, groupOutlineArtwork, settings.raidGroupBorderSize, border, height, panel.outlineLevel)
    else
        if panel.mosAtlasOutline then panel.mosAtlasOutline:Hide() end
        if settings.raidGroupShowBorder or panel.mosProjectOutline then
            UI.SetProjectButtonOutline(panel, settings.raidGroupShowBorder, settings.raidGroupBorderSize, border, height, panel.outlineLevel)
        end
    end
    panel.headerBackground:SetTexture(background[1], background[2], background[3], 1)
    panel.headerBackground:SetAlpha(1 - (settings.raidGroupHeaderTransparency or 0) / 100)
    local inset = 0
    panel.headerBackground:ClearAllPoints()
    panel.headerBackground:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -inset)
    panel.headerBackground:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -inset, -inset)
    panel.headerBackground:SetHeight(math.max(1, height - inset))
    if settings.raidGroupShowHeader then panel.headerBackground:Show() else panel.headerBackground:Hide() end
end

local function SetGroupSlotHover(slot, settings, hovered)
    local UI = Raider.UI.Components
    if settings.raidGroupMemberTexture == "game" then
        if slot.mosProjectOutline then slot.mosProjectOutline:Hide() end
        UI.SetAtlasHighlight(slot, hovered and settings.raidGroupShowHoverBorder, groupHoverArtwork, settings.raidGroupHoverBorderSize, settings.raidGroupHoverBorderColor)
    else
        if slot.mosAtlasHighlight then UI.SetAtlasHighlight(slot, false, groupHoverArtwork, 1, settings.raidGroupHoverBorderColor) end
        if settings.raidGroupShowHoverBorder or slot.mosProjectOutline then
            UI.SetProjectButtonOutline(slot, hovered and settings.raidGroupShowHoverBorder, settings.raidGroupHoverBorderSize, settings.raidGroupHoverBorderColor)
        end
    end
end

local function OnGroupHeaderEnter()
    local settings = GroupSettings(this.groupPage)
    this.groupPanel.headerHovered = true
    this.groupLabel:SetTextColor(unpack(settings.raidGroupHeaderHoverTextColor or settings.raidGroupHeaderTextColor))
end

local function OnGroupHeaderLeave()
    this.groupPanel.headerHovered = nil
    local settings = GroupSettings(this.groupPage)
    this.groupLabel:SetTextColor(unpack(settings.raidGroupHeaderTextColor))
end

function RaidManagement.CalculateGroupGeometry(width, height, columns, preferredTileWidth, tileHeight, showHeader, autoTileWidth, configuredHeaderHeight, groupMargin, showBorder, fitWidth, visibleCount, autoVertical, autoHorizontal, fillHeight)
    local columnCount = math.floor(math.max(1, math.min(4, tonumber(columns) or 2)))
    local availableWidth = math.max(1, tonumber(width) or 1)
    local margin = math.max(0, tonumber(groupMargin) or 0)
    if fitWidth then
        columnCount = math.min(columnCount, math.max(1, math.floor(availableWidth)))
        if columnCount > 1 then margin = math.min(margin, math.max(0, math.floor((availableWidth - columnCount) / (columnCount - 1)))) end
    end
    visibleCount = math.floor(math.max(0, math.min(8, tonumber(visibleCount) or 8)))
    local groupRows = math.ceil(visibleCount / columnCount)
    local preferredWidth = (columnCount * (tonumber(preferredTileWidth) or 280)) + ((columnCount - 1) * margin)
    local layoutWidth = autoTileWidth and availableWidth or math.min(availableWidth, preferredWidth)
    local columnWidth = math.max(1, math.floor((layoutWidth - ((columnCount - 1) * margin)) / columnCount))
    local headerHeight = showHeader and math.max(12, tonumber(configuredHeaderHeight) or 18) or 0
    local rowHeight = tonumber(tileHeight) or 22
    local groupHeight = headerHeight + rowHeight * 5
    if (autoVertical and visibleCount < 8 or fillHeight and visibleCount == 8) and visibleCount > 0 and math.mod(visibleCount, columnCount) == 0 then
        groupHeight = math.max(groupHeight, ((tonumber(height) or 1) - (groupRows - 1) * margin) / groupRows)
        rowHeight = (groupHeight - headerHeight) / 5
    end
    local contentHeight = math.max(0, (groupRows * groupHeight) + ((groupRows - 1) * margin))
    return {
        columns = columnCount,
        rows = groupRows,
        layoutWidth = layoutWidth,
        xOffset = math.max(0, math.floor((availableWidth - layoutWidth) / 2)),
        columnWidth = columnWidth,
        headerHeight = headerHeight,
        groupHeight = groupHeight,
        tileHeight = rowHeight, visibleCount = visibleCount, autoHorizontal = autoHorizontal,
        contentHeight = contentHeight,
        canvasHeight = math.max(tonumber(height) or 1, contentHeight),
        maximumScroll = math.max(0, contentHeight - (tonumber(height) or 1)),
        margin = margin,
        tileInset = 0,
    }
end

function RaidManagement.CalculateGroupSlotColumns(slotWidth, reserveRoleIcon, reserveLootIcon, showLevel, showClass, offline, fitWidth)
    if fitWidth then
        local width = math.max(1, tonumber(slotWidth) or 1)
        local padding = math.min(3, (width - 1) / 10)
        local right = math.min(3, (width - 1) / 10)
        local available = math.max(1, width - padding - right)
        local nameMinimum = math.min(16, available)
        local role = reserveRoleIcon and available >= nameMinimum + 12
        if role then available = available - 12 end
        local loot = reserveLootIcon and available >= nameMinimum + 12
        if loot then available = available - 12 end
        local offlineWidth = offline and available >= nameMinimum + 46 and 42 or 0
        if offlineWidth > 0 then available = available - offlineWidth - 4 end
        local levelWidth = showLevel and available >= nameMinimum + 29 and 24 or 0
        if levelWidth > 0 then available = available - levelWidth - 5 end
        local preferredClass = math.max(36, math.min(64, math.floor(width * 0.25)))
        local classWidth = showClass and available >= nameMinimum + preferredClass + 5 and preferredClass or 0
        if classWidth > 0 then available = available - classWidth - 5 end
        return { nameInset = padding + (role and 12 or 0) + (loot and 12 or 0), nameWidth = available,
            classWidth = classWidth, levelWidth = levelWidth, offlineWidth = offlineWidth,
            showRoleIcon = role, showLootIcon = loot, rightInset = right, iconInset = padding }
    end
    local width = math.max(80, tonumber(slotWidth) or 80)
    local nameInset = 5 + (reserveRoleIcon and 18 or 0) + (reserveLootIcon and 18 or 0)
    local offlineWidth = offline and 42 or 0
    local classWidth = showClass and math.max(36, math.min(64, math.floor(width * 0.25))) or 0
    local levelWidth = showLevel and 24 or 0
    local rightSpace = 6 + offlineWidth + (offlineWidth > 0 and 4 or 0) + classWidth + (showClass and 5 or 0) + levelWidth + (showLevel and 5 or 0)
    return {
        nameInset = nameInset,
        nameWidth = math.max(16, width - nameInset - rightSpace),
        levelWidth = levelWidth,
        classWidth = classWidth,
        offlineWidth = offlineWidth,
    }
end

local function SetFontSize(fontString, size)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return end
    local path, currentSize, flags = fontString:GetFont()
    if path and currentSize ~= size then fontString:SetFont(path, size, flags) end
end

function RaidManagement.FilterMembers(target, members, query, selectedClasses, selectedRanks)
    local targetIndex
    for targetIndex = table.getn(target), 1, -1 do table.remove(target, targetIndex) end
    local memberIndex
    for memberIndex = 1, table.getn(members) do
        local member = members[memberIndex]
        local className = member.class ~= "" and member.class or "Unknown"
        local rankName = member.guildRank ~= "" and member.guildRank or "Guest"
        if selectedClasses[className] and selectedRanks[rankName] then
            if query == "" then
                table.insert(target, member)
            else
                local searchable = string.lower((member.name or "") .. " " .. tostring(member.subgroup or "") .. " " .. className .. " " .. rankName .. " " .. tostring(member.sr or ""))
                if string.find(searchable, query, 1, true) then table.insert(target, member) end
            end
        end
    end
    return target
end

function RaidManagement.MeasureListHeight(width, page)
    return page.mosListMeasuredHeight
end

function RaidManagement.FitListHeaders(page, headerButtons, lootMasterMode)
    local scale = 1
    local baseSize = lootMasterMode and 10 or (page.mosHeaderBaseSize or 12)
    local count = lootMasterMode and table.getn(headerButtons) or table.getn(page.listColumns)
    for index = 1, count do
        local button = lootMasterMode and headerButtons[index] or page.listColumns[index].button
        local enabled = lootMasterMode and button:IsVisible() or not lootMasterMode and page.listEnabled[index]
        if enabled then
            local label = button.label
            local font, _, flags = label:GetFont()
            label:SetFont(font, baseSize, flags); label:SetWidth(0)
            if label.SetWordWrap then label:SetWordWrap(false) end
            if label.SetNonSpaceWrap then label:SetNonSpaceWrap(false) end
            scale = math.min(scale, math.max(1, button:GetWidth() - 3) / math.max(1, label:GetStringWidth()))
        end
    end
    for index = 1, count do
        local button = lootMasterMode and headerButtons[index] or page.listColumns[index].button
        local label = button.label
        local font, _, flags = label:GetFont()
        label:SetFont(font, baseSize * scale, flags); label:SetWidth(math.max(1, button:GetWidth() - 3)); label:SetHeight(baseSize * scale + 3)
    end
end

function RaidManagement.LayoutListHeaders(page, headerButtons, sortKey, lootMasterMode, configuredRowWidth, memberCount, selectedName)
    local submenuOffset = not lootMasterMode and Raider.UI.Components.IsClassicSkin() and ((page.classicSectionOffset or 0) + (page.classicActionOffset or 0) + (page.classicToolbarOffset or 0) + (page.classicSearchOffset or 0)) or 0
    local filterOffset = not lootMasterMode and BootyRaiderDB.raidListShowFilters == false and BootyRaiderDB.raidListShowSearch == false and 34 or 0
    local headerY = lootMasterMode and -29 or -134 - submenuOffset + filterOffset
    local rowStartY = lootMasterMode and -46 or -156 - submenuOffset + filterOffset
    local positions = lootMasterMode and lootHeaderPositions or normalHeaderPositions
    local widths = lootMasterMode and lootHeaderWidths or normalHeaderWidths
    local headerIndex
    for headerIndex = 1, 5 do
        local label = page.headerLabels[headerIndex]
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", page, "TOPLEFT", positions[headerIndex], headerY)
        label:SetWidth(widths[headerIndex])
        label:SetFontObject(lootMasterMode and GameFontNormalSmall or GameFontNormal)
        local button = headerButtons[headerIndex]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", page, "TOPLEFT", positions[headerIndex], headerY + 4)
        button:SetWidth(widths[headerIndex])
        button:SetHeight(lootMasterMode and 15 or 22)
    end
    page.headerLabels[1]:Show()
    if lootMasterMode then page.headerLabels[2]:Hide() else page.headerLabels[2]:Show() end
    page.headerLabels[3]:Show(); page.headerLabels[4]:Show(); page.headerLabels[5]:Show()
    for headerIndex = 1, table.getn(headerButtons) do
        local header = headerButtons[headerIndex]
        if lootMasterMode and header.sortKey == "subgroup" then header:Hide() else header:Show() end
        header.label:SetText(header.baseText)
        header.label:SetTextColor(1, 0.82, 0)
    end

    local tableLeft = lootMasterMode and 1.5 or 6
    local pageWidth, pageHeight = PageSpan(page)
    local classic = Raider.UI.Components.IsClassicSkin()
    local rowStep = lootMasterMode and 21 or ((tonumber(BootyRaiderDB.raidListRowHeight) or 20) + 1)
    local bottom = lootMasterMode and 1.5 or (classic and 4 or 11)
    local bodyHeight = math.max(1, pageHeight + rowStartY - bottom)
    local count = memberCount or 0
    if not lootMasterMode and selectedName then count = count + 7 end
    page.mosListMeasuredHeight = count * rowStep
    if lootMasterMode and selectedName then
        page.mosListMeasuredHeight = page.mosListMeasuredHeight + RaidManagement.LootMasterExpandedHeight(bodyHeight, count) - rowStep
    end
    local fullWidth = math.max(1, pageWidth - tableLeft - (lootMasterMode and 3 or 4))
    local resolvedWidth, _, overflow = Raider.UI.Components.ResolveScrollLayout(fullWidth, bodyHeight, 20, RaidManagement.MeasureListHeight, page)
    page.mosListScrollGutter = overflow and 20 or 0
    local tableRight = tableLeft + resolvedWidth
    local availableWidth = math.max(1, tableRight - tableLeft)
    local tableWidth = availableWidth
    if lootMasterMode then
        local columns = page.mosLootColumns or {}; page.mosLootColumns = columns
        local scale = math.min(1, math.max(1, tableWidth - 35) / 250)
        local fontSize
        if page.listRows and page.listRows[1] then local _, size = page.listRows[1].name:GetFont(); fontSize = size end
        columns.nameInset = math.max(2, (20 - (fontSize or 12)) / 2)
        columns.nameWidth = math.max(1, 105 * scale - 5)
        columns.classX = tableLeft + 105 * scale
        columns.rankX = tableLeft + 170 * scale
        columns.srX = tableLeft + 250 * scale
        columns.classWidth = math.max(1, columns.rankX - columns.classX - 5)
        columns.rankWidth = math.max(1, columns.srX - columns.rankX - 5)
        columns.srWidth = math.max(1, tableWidth - 250 * scale)
        local labels, buttons = page.headerLabels, headerButtons
        labels[1]:ClearAllPoints(); labels[1]:SetPoint("TOPLEFT", page, "TOPLEFT", tableLeft + columns.nameInset, headerY); labels[1]:SetWidth(math.max(1, columns.nameWidth - columns.nameInset))
        buttons[1]:ClearAllPoints(); buttons[1]:SetPoint("TOPLEFT", page, "TOPLEFT", tableLeft + columns.nameInset, headerY + 4); buttons[1]:SetWidth(math.max(1, columns.nameWidth - columns.nameInset))
        for headerIndex = 3, 5 do
            local x = headerIndex == 3 and columns.classX or (headerIndex == 4 and columns.rankX or columns.srX)
            local width = headerIndex == 3 and columns.classWidth or (headerIndex == 4 and columns.rankWidth or columns.srWidth)
            labels[headerIndex]:ClearAllPoints(); labels[headerIndex]:SetPoint("TOPLEFT", page, "TOPLEFT", x, headerY); labels[headerIndex]:SetWidth(width)
            buttons[headerIndex]:ClearAllPoints(); buttons[headerIndex]:SetPoint("TOPLEFT", page, "TOPLEFT", x, headerY + 4); buttons[headerIndex]:SetWidth(width)
        end
    end
    local proportionalWidth = math.min(tableWidth, tonumber(configuredRowWidth) or tableWidth)
    if not lootMasterMode then
        local fractionTotal, lastEnabled = 0, nil
        for headerIndex = 1, table.getn(page.listColumns) do
            local column = page.listColumns[headerIndex]
            local enabled = BootyRaiderDB[column.setting] ~= false
            page.listEnabled[headerIndex] = enabled
            column.header:Hide(); column.button:Hide()
            if enabled then fractionTotal = fractionTotal + column.fraction; lastEnabled = headerIndex end
        end
        local columnX = tableLeft
        for headerIndex = 1, table.getn(page.listColumns) do
            local column = page.listColumns[headerIndex]
            local width = 0
            if page.listEnabled[headerIndex] then
                if headerIndex == lastEnabled then width = tableLeft + tableWidth - columnX
                else width = math.floor(proportionalWidth * column.fraction / fractionTotal) end
                page.listPositions[headerIndex] = columnX
                page.listWidths[headerIndex] = width
                column.header:ClearAllPoints(); column.header:SetPoint("TOPLEFT", page, "TOPLEFT", columnX, headerY); column.header:SetWidth(width); column.header:Show()
                column.button:ClearAllPoints(); column.button:SetPoint("TOPLEFT", page, "TOPLEFT", columnX, headerY + 4); column.button:SetWidth(width); column.button:Show()
                column.button.label:SetText(column.button.baseText)
                column.button.label:SetTextColor(1, 0.82, 0)
                columnX = columnX + width
            else
                page.listPositions[headerIndex] = columnX
                page.listWidths[headerIndex] = 0
            end
        end
    end
    RaidManagement.FitListHeaders(page, headerButtons, lootMasterMode)
    return rowStartY, tableLeft, tableWidth
end

function RaidManagement.PositionListRow(page, row, rowY, lootMasterMode, tableLeft, tableWidth)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", page, "TOPLEFT", tableLeft, rowY)
    if lootMasterMode then
        local columns = page.mosLootColumns
        local srWidth = columns and columns.srWidth or math.max(35, tableWidth - 250)
        local classX, rankX, srX = columns and columns.classX or 105, columns and columns.rankX or 170, columns and columns.srX or 250
        row.name:ClearAllPoints(); row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0); row.name:SetWidth(columns and columns.nameWidth or 90)
        row.group:ClearAllPoints(); row.group:SetPoint("TOPLEFT", page, "TOPLEFT", 0, rowY); row.group:SetWidth(0)
        row.level:ClearAllPoints(); row.level:SetPoint("TOPLEFT", page, "TOPLEFT", 0, rowY); row.level:SetWidth(0)
        row.status:ClearAllPoints(); row.status:SetPoint("TOPLEFT", page, "TOPLEFT", 0, rowY); row.status:SetWidth(0)
        row.class:ClearAllPoints(); row.class:SetPoint("TOPLEFT", page, "TOPLEFT", classX, rowY); row.class:SetWidth(columns and columns.classWidth or 55)
        row.rank:ClearAllPoints(); row.rank:SetPoint("TOPLEFT", page, "TOPLEFT", rankX, rowY); row.rank:SetWidth(columns and columns.rankWidth or 72)
        row.sr:ClearAllPoints(); row.sr:SetPoint("TOPLEFT", page, "TOPLEFT", srX + 20, rowY); row.sr:SetWidth(math.max(1, srWidth - 20))
        row.srHit:ClearAllPoints(); row.srHit:SetPoint("TOPLEFT", page, "TOPLEFT", srX, rowY); row.srHit:SetWidth(srWidth); row.srHit:SetHeight(20)
        row.srIcon:ClearAllPoints(); row.srIcon:SetPoint("LEFT", row.srHit, "LEFT", 2, 0)
        return
    end
    local columnIndex
    for columnIndex = 1, table.getn(page.listColumns) do
        local column = page.listColumns[columnIndex]
        local cell = row[column.key]
        cell:ClearAllPoints()
        if column.key == "name" then cell:SetPoint("TOPLEFT", row, "TOPLEFT", page.listPositions[columnIndex] - tableLeft, 0)
        else cell:SetPoint("TOPLEFT", page, "TOPLEFT", page.listPositions[columnIndex], rowY) end
        cell:SetWidth(page.listWidths[columnIndex]); cell:SetHeight(tonumber(BootyRaiderDB.raidListRowHeight) or 20); cell:SetJustifyV("MIDDLE")
        if column.key == "group" then
            row.groupHit:ClearAllPoints()
            row.groupHit:SetPoint("TOPLEFT", page, "TOPLEFT", page.listPositions[columnIndex], rowY)
            row.groupHit:SetWidth(page.listWidths[columnIndex])
            row.groupHit:SetHeight(tonumber(BootyRaiderDB.raidListRowHeight) or 20)
        elseif column.key == "sr" then
            row.sr:ClearAllPoints(); row.sr:SetPoint("TOPLEFT", page, "TOPLEFT", page.listPositions[columnIndex] + 36, rowY)
            row.sr:SetWidth(math.max(1, page.listWidths[columnIndex] - 36))
            row.srHit:ClearAllPoints(); row.srHit:SetPoint("TOPLEFT", page, "TOPLEFT", page.listPositions[columnIndex], rowY)
            row.srHit:SetWidth(page.listWidths[columnIndex]); row.srHit:SetHeight(tonumber(BootyRaiderDB.raidListRowHeight) or 20)
            row.srIcon:ClearAllPoints(); row.srIcon:SetPoint("LEFT", row.srHit, "LEFT", 20, 0)
        end
    end
end

function RaidManagement.LayoutLootPanel(row, lootMasterMode, tableWidth, expandedHeight)
    row:SetWidth(tableWidth)
    row:SetHeight(lootMasterMode and 20 or (tonumber(BootyRaiderDB.raidListRowHeight) or 20))
    row.lootPanel:SetWidth(tableWidth - 8)
    row.lootPanel:SetHeight(expandedHeight and math.max(55, expandedHeight - 25) or (lootMasterMode and 106 or 130))
    row.visibleLootRows = math.max(1, math.min(table.getn(row.lootRows), math.floor((row.lootPanel:GetHeight() - 27) / 24)))
    row.actions:Hide()
    row.lootTitle:ClearAllPoints()
    row.lootTitle:SetPoint("TOPLEFT", row.lootPanel, "TOPLEFT", 10, -8)
    row.lootEmpty:ClearAllPoints()
    row.lootEmpty:SetPoint("TOPLEFT", row.lootPanel, "TOPLEFT", 10, lootMasterMode and -34 or -30)
    local lootIndex
    for lootIndex = 1, table.getn(row.lootRows) do
        row.lootRows[lootIndex].name:SetWidth(lootMasterMode and math.max(1, tableWidth - 80) or 455)
        row.lootRows[lootIndex].hit:ClearAllPoints()
        row.lootRows[lootIndex].hit:SetPoint("TOPLEFT", row.lootPanel, "TOPLEFT", 8, -(lootMasterMode and 27 or 25) - ((lootIndex - 1) * 24))
        row.lootRows[lootIndex].hit:SetPoint("TOPRIGHT", row.lootPanel, "TOPRIGHT", -25, -(lootMasterMode and 27 or 25) - ((lootIndex - 1) * 24))
    end
end

local offlineTextColor = { 1, 1, 1 }
local function SetListTextColor(row, color, shade)
    local r, g, b = color[1] * shade, color[2] * shade, color[3] * shade
    row.name:SetTextColor(r, g, b); row.level:SetTextColor(r, g, b); row.status:SetTextColor(r, g, b)
    row.group:SetTextColor(r, g, b); row.class:SetTextColor(r, g, b); row.rank:SetTextColor(r, g, b); row.sr:SetTextColor(r, g, b)
end

function RaidManagement.BindListMember(page, row, member, lootMethod, raidLootMasterIndex, lootMasterMode, tableLeft, shorten)
    if row.mosProjectOutline then
        local settings = BootyRaiderDB
        Raider.UI.Components.SetProjectButtonOutline(row, row.mosRaidHovered and settings.raidListShowHoverBorder, settings.raidListHoverBorderSize, settings.raidListHoverBorderColor)
    end
    row.name:SetText(shorten(member.name, 22))
    local memberRank = tonumber(member.raidRank) or 0
    local showRole = not lootMasterMode and BootyRaiderDB.raidListShowRoleIcon and memberRank > 0
    if showRole then
        row.crown:SetTexture(memberRank == 2 and "Interface\\GroupFrame\\UI-Group-LeaderIcon" or "Interface\\GroupFrame\\UI-Group-AssistantIcon")
        row.crown:SetAlpha(1); row.crown:Show()
    else
        row.crown:Hide()
    end
    local showLootMaster = not lootMasterMode and BootyRaiderDB.raidListShowLootMaster and lootMethod == "master" and tonumber(raidLootMasterIndex) == tonumber(member.raidIndex)
    local _, fontSize = row.name:GetFont()
    local leftPadding = math.max(2, (row:GetHeight() - (fontSize or 12)) / 2)
    row.crown:ClearAllPoints(); row.crown:SetPoint("LEFT", row, "LEFT", leftPadding, 0)
    row.lootMasterIcon:ClearAllPoints(); row.lootMasterIcon:SetPoint("LEFT", row, "LEFT", leftPadding + (showRole and 15 or 0), 0)
    if showLootMaster then row.lootMasterIcon:Show() else row.lootMasterIcon:Hide() end
    local nameInset = leftPadding + (showRole and 17 or 0) + (showLootMaster and 14 or 0)
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", (lootMasterMode and 0 or page.listPositions[1] - tableLeft) + nameInset, 0)
    row.name:SetWidth(math.max(1, (lootMasterMode and (page.mosLootColumns and page.mosLootColumns.nameWidth or 90) or page.listWidths[1]) - nameInset))
    row.group:SetText(tostring(member.subgroup or ""))
    row.level:SetText(tostring(member.level or ""))
    row.status:SetText(member.online and "Online" or "Offline")
    row.class:SetText(shorten(member.class, 12))
    row.rank:SetText(shorten(Raider.Services.RankPolicy.GetDisplayName(member.guildRank ~= "" and member.guildRank or "Guest"), 18))
    local itemId = member.srItemIds and member.srItemIds[1]
    row.sr:SetText(itemId and Raider.UI.Components.GetItemLabel(itemId) or "")
    row.srHit.itemId = itemId
    local srTexture = itemId and type(GetItemIcon) == "function" and GetItemIcon(itemId) or nil
    if not srTexture and itemId then local _, _, _, _, _, _, _, _, _, cachedTexture = GetItemInfo(itemId); srTexture = cachedTexture end
    if srTexture then row.srIcon:SetTexture(srTexture); row.srIcon:Show() else row.srIcon:Hide() end
    if itemId and not lootMasterMode then row.srDelete:Show() else row.srDelete:Hide() end
    local shade = member.online and 1 or 0.55
    SetListTextColor(row, member.online and BootyRaiderDB.raidListTextColor or offlineTextColor, shade)
    row.crown:SetAlpha(member.online and 1 or 0.55); row.lootMasterIcon:SetAlpha(member.online and 1 or 0.55)
    if member.online and BootyRaiderDB.raidClassColors then
        local classKey = string.upper(member.classFile or "")
        local className = string.upper(member.class or "")
        local classColor = (RAID_CLASS_COLORS and (RAID_CLASS_COLORS[classKey] or RAID_CLASS_COLORS[className])) or Raider.UI.Components.Theme.classColors[classKey] or Raider.UI.Components.Theme.classColors[className]
        if classColor then
            row.name:SetTextColor(classColor.r * shade, classColor.g * shade, classColor.b * shade)
            row.class:SetTextColor(classColor.r * shade, classColor.g * shade, classColor.b * shade)
        end
    end
    row:Show()
    if lootMasterMode then
        row.groupHit:Hide(); row.name:Show(); row.level:Hide(); row.group:Hide(); row.status:Hide(); row.class:Show(); row.rank:Show(); row.sr:Show()
        if itemId then row.srHit:Show() else row.srHit:Hide() end
        return
    end
    local columnIndex
    for columnIndex = 1, table.getn(page.listColumns) do
        local column = page.listColumns[columnIndex]
        if page.listEnabled[columnIndex] then row[column.key]:Show() else row[column.key]:Hide() end
    end
    if page.listEnabled[4] then row.groupHit:Show() else row.groupHit:Hide() end
    if page.listEnabled[7] and itemId then row.srHit:Show() else row.srHit:Hide() end
    if not page.listEnabled[1] then row.crown:Hide() end
end

function RaidManagement.ExpandListRow(row, member, lootMasterMode, requestedHeight)
    local expandedHeight = requestedHeight or (lootMasterMode and 131 or 155)
    row:SetHeight(expandedHeight)
    local pressedColor = BootyRaiderDB.raidListPressedColor
    Raider.UI.Components.SetRowColor(row, pressedColor, 0.98)
    row:SetBackdropBorderColor(0.7, 0.55, 0.15, 0.9)
    Raider.UI.Components.SetClassicRowShade(row, false, false, true)
    row.lootPanel:Show()
    local loot = member.loot or {}
    table.sort(loot, SortLootByName)
    local visibleLootRows = row.visibleLootRows or table.getn(row.lootRows)
    FauxScrollFrame_Update(row.lootScroll, table.getn(loot), visibleLootRows, 24)
    if table.getn(loot) > visibleLootRows then
        row.lootScroll:Show(); if row.lootScrollBar then row.lootScrollBar:Show() end
    else
        row.lootScroll.offset = 0; row.lootScroll:SetVerticalScroll(0); row.lootScroll:Hide(); if row.lootScrollBar then row.lootScrollBar:Hide() end
    end
    local lootOffset = FauxScrollFrame_GetOffset(row.lootScroll)
    if table.getn(loot) == 0 then row.lootEmpty:Show() else row.lootEmpty:Hide() end
    local lootIndex
    for lootIndex = 1, table.getn(row.lootRows) do
        local item = lootIndex <= visibleLootRows and loot[lootOffset + lootIndex] or nil
        local lootRow = row.lootRows[lootIndex]
        if item then
            local itemId = tonumber(item.itemId) or tonumber(Match(tostring(item.link or ""), "item:(%d+)"))
            local realName, realLink, _, _, _, _, _, _, _, refreshedTexture = GetItemInfo(itemId or item.link)
            if itemId and type(GetItemIcon) == "function" then refreshedTexture = GetItemIcon(itemId) or refreshedTexture end
            if realName then item.name = realName end; if realLink then item.link = realLink end; if refreshedTexture then item.icon = refreshedTexture end
            lootRow.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            lootRow.name:SetText((itemId and Raider.UI.Components.GetItemLabel(itemId) or (item.name or "Unknown item")) .. ((tonumber(item.count) or 1) > 1 and (" x " .. item.count) or ""))
            lootRow.hit.itemId = itemId; lootRow.hit.itemName = item.name; lootRow.hit.itemLink = item.link; lootRow.hit.itemCount = item.count; lootRow.hit.rollHistory = item.rollHistory; lootRow.hit.labelSuffix = (tonumber(item.count) or 1) > 1 and (" x " .. item.count) or ""; lootRow.hit:Show(); lootRow.icon:Show(); lootRow.name:Show()
        else
            lootRow.hit.itemId = nil; lootRow.hit.itemName = nil; lootRow.hit.itemLink = nil; lootRow.hit.itemCount = nil; lootRow.hit.rollHistory = nil; lootRow.hit.labelSuffix = nil; lootRow.hit:Hide(); lootRow.icon:Hide(); lootRow.name:Hide()
        end
    end
    return expandedHeight
end

function RaidManagement.CollapseListRow(row, visibleIndex, lootMasterMode, rowStep)
    row:SetHeight(lootMasterMode and 20 or (tonumber(BootyRaiderDB.raidListRowHeight) or 20))
    local background = BootyRaiderDB.raidListBackgroundColor
    Raider.UI.Components.SetAlternatingRowColor(row, background, visibleIndex, BootyRaiderDB.raidListOddLightness)
    row:SetBackdropBorderColor(0, 0, 0, 0)
    Raider.UI.Components.SetClassicRowShade(row, math.mod(visibleIndex, 2) == 0, false)
    row.lootPanel:Hide()
    return rowStep
end

function RaidManagement.HideListRow(row)
    row.mosRaidHovered=nil
    if row.mosProjectOutline then row.mosProjectOutline:Hide() end
    row.displayedMember = nil
    row.crown:Hide(); row.lootMasterIcon:Hide(); row.groupHit:Hide(); row.srHit:Hide(); row.srDelete:Hide(); row.srIcon:Hide(); row.srHit.itemId = nil; row:Hide()
    row.name:Hide(); row.level:Hide(); row.status:Hide(); row.group:Hide()
    row.class:Hide(); row.rank:Hide(); row.sr:Hide(); row.lootPanel:Hide()
end

function RaidManagement.KeepSelectionVisible(scrollFrame, members, selectedName, visibleCount, rowStep)
    if not selectedName then return end
    local selectedIndex = nil
    local memberIndex
    for memberIndex = 1, table.getn(members) do
        if members[memberIndex].name == selectedName then selectedIndex = memberIndex; break end
    end
    if not selectedIndex then return end
    local currentOffset = scrollFrame.offset or 0
    if selectedIndex <= currentOffset then currentOffset = selectedIndex - 1
    elseif selectedIndex > currentOffset + visibleCount then currentOffset = selectedIndex - visibleCount end
    currentOffset = math.max(0, currentOffset)
    scrollFrame.offset = currentOffset
    scrollFrame:SetVerticalScroll(currentOffset * rowStep)
end

function RaidManagement.RenderListRows(page, rows, members, offset, visibleCount, rowStep, rowStartY, lootMasterMode, tableLeft, tableWidth, lootMethod, raidLootMasterIndex, selectedName, shorten, expandedHeight)
    local rowY = rowStartY
    local rowIndex
    for rowIndex = 1, table.getn(rows) do
        local member = members[offset + rowIndex]
        local row = rows[rowIndex]
        RaidManagement.PositionListRow(page, row, rowY, lootMasterMode, tableLeft, tableWidth)
        if member and rowIndex <= visibleCount then
            row.displayedMember = member
            row.visibleIndex = offset + rowIndex
            RaidManagement.LayoutLootPanel(row, lootMasterMode, tableWidth, member.name == selectedName and expandedHeight or nil)
            RaidManagement.BindListMember(page, row, member, lootMethod, raidLootMasterIndex, lootMasterMode, tableLeft, shorten)
            if member.name == selectedName then
                rowY = rowY - RaidManagement.ExpandListRow(row, member, lootMasterMode, expandedHeight)
            else
                rowY = rowY - RaidManagement.CollapseListRow(row, offset + rowIndex, lootMasterMode, rowStep)
            end
        else
            RaidManagement.HideListRow(row)
        end
    end
    return rowY
end

function RaidManagement.UpdateDragGhost(page)
    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale() or 1
    cursorX = cursorX / uiScale; cursorY = cursorY / uiScale
    page.dragGhost:ClearAllPoints()
    page.dragGhost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cursorX - (page.dragOffsetX or 0), cursorY - (page.dragOffsetY or 0))
end

local function PositionGroupGhostText(source, target, slot, ghost)
    local point, relative, relativePoint, x, y = source:GetPoint(1)
    if not point then return end
    if relative == slot then relative = ghost
    elseif relative == slot.class then relative = ghost.class
    elseif relative == slot.offline then relative = ghost.offline end
    target:ClearAllPoints(); target:SetPoint(point, relative, relativePoint, x, y); target:SetWidth(source:GetWidth())
end

local function OnGroupSlotMouseDown()
    if arg1 ~= "LeftButton" or not this.raidIndex then return end
    if type(IsRaidLeader) == "function" and type(IsRaidOfficer) == "function" and not IsRaidLeader() and not IsRaidOfficer() then return end
    local page = this.groupPage
    if page.canManageGroups and not page.canManageGroups() then return end
    local settings = GroupSettings(page)
    local pressed = settings.raidGroupPressedColor; Raider.UI.Components.SetRowColor(this, pressed, 0.98)
    Raider.dragRaidIndex = this.raidIndex; Raider.raidDropSlot = this; Raider.raidDragStarted = nil
    local cursorX, cursorY = GetCursorPosition(); local uiScale = UIParent:GetEffectiveScale() or 1
    cursorX = cursorX / uiScale; cursorY = cursorY / uiScale
    page.dragOffsetX = cursorX - (this:GetLeft() or cursorX); page.dragOffsetY = cursorY - (this:GetBottom() or cursorY)
    local ghost = page.dragGhost
    ghost:SetWidth(this:GetWidth()); ghost:SetHeight(this:GetHeight())
    local background = settings.raidGroupBackgroundColor; Raider.UI.Components.SetRowColor(ghost, background, 0.98)
    ghost.name:SetText(this.name:GetText()); ghost.level:SetText(this.level:GetText()); ghost.class:SetText(this.class:GetText())
    ghost.name:SetFont(this.name:GetFont()); ghost.level:SetFont(this.level:GetFont()); ghost.class:SetFont(this.class:GetFont()); ghost.offline:SetFont(this.offline:GetFont())
    local r, g, b = this.name:GetTextColor(); ghost.name:SetTextColor(r, g, b)
    r, g, b = this.level:GetTextColor(); ghost.level:SetTextColor(r, g, b)
    r, g, b = this.class:GetTextColor(); ghost.class:SetTextColor(r, g, b)
    local hasRole, hasLootMaster = this.crown:IsVisible(), this.lootMasterIcon:IsVisible()
    if hasRole then ghost.crown:SetTexture(this.crown:GetTexture()); ghost.crown:Show() else ghost.crown:Hide() end
    ghost.crown:ClearAllPoints(); ghost.crown:SetPoint("LEFT", ghost, "LEFT", 5, 0)
    ghost.lootMasterIcon:ClearAllPoints(); ghost.lootMasterIcon:SetPoint("LEFT", ghost, "LEFT", hasRole and 23 or 5, 0)
    if hasLootMaster then ghost.lootMasterIcon:Show() else ghost.lootMasterIcon:Hide() end
    ghost.name:ClearAllPoints(); ghost.name:SetPoint("LEFT", ghost, "LEFT", 5 + (hasRole and 18 or 0) + (hasLootMaster and 18 or 0), 0); ghost.name:SetWidth(this.name:GetWidth())
    ghost.level:SetWidth(this.level:GetWidth()); ghost.level:ClearAllPoints(); ghost.level:SetPoint("RIGHT", ghost, "RIGHT", -6, 0)
    ghost.level:SetJustifyH("RIGHT")
    ghost.class:ClearAllPoints(); ghost.class:SetPoint("RIGHT", ghost, "RIGHT", -6 - (this.offline:IsVisible() and this.offline:GetWidth() + 4 or 0), 0); ghost.class:SetWidth(this.class:GetWidth())
    if this.class:IsVisible() then ghost.level:SetPoint("RIGHT", ghost.class, "LEFT", -5, 0) end
    if this.level:IsVisible() then ghost.level:Show() else ghost.level:Hide() end
    if this.class:IsVisible() then ghost.class:Show() else ghost.class:Hide() end
    if this.offline:IsVisible() then ghost.offline:Show() else ghost.offline:Hide() end
    PositionGroupGhostText(this.name, ghost.name, this, ghost)
    if this.class:IsVisible() then PositionGroupGhostText(this.class, ghost.class, this, ghost) end
    if this.level:IsVisible() then PositionGroupGhostText(this.level, ghost.level, this, ghost) end
    if this.offline:IsVisible() then PositionGroupGhostText(this.offline, ghost.offline, this, ghost) end
    ghost:SetScript("OnUpdate", page.updateDragGhost); ghost:Show(); page.updateDragGhost()
end

local function OnGroupSlotMouseUp()
    local page = this.groupPage
    local hover = GroupSettings(page).raidGroupHoverColor; Raider.UI.Components.SetRowColor(this, hover, 0.98)
    if arg1 == "LeftButton" and Raider.dragRaidIndex and not Raider.raidDragStarted then
        Raider.dragRaidIndex = nil; Raider.raidDropSlot = nil; page.dragGhost:SetScript("OnUpdate", nil); page.dragGhost:Hide()
    end
end

local function OnGroupSlotClick()
    if arg1 == "RightButton" and this.hasMember then
        if this.groupPage.showMemberMenu then this.groupPage.showMemberMenu(this)
        elseif Raider.ShowRaidMemberMenu then Raider.ShowRaidMemberMenu(this) end
    end
end

local function OnGroupSlotDragStart()
    if not Raider.dragRaidIndex then return end
    if this.groupPage.canManageGroups and not this.groupPage.canManageGroups() then
        Raider.dragRaidIndex = nil; Raider.raidDropSlot = nil
        this.groupPage.dragGhost:SetScript("OnUpdate", nil); this.groupPage.dragGhost:Hide()
        return
    end
    Raider.raidDragStarted = true
    this.groupPage.groupMovePending = true
    if not this.groupPage.isTestRaid() and type(SetRaidRosterSelection) == "function" then SetRaidRosterSelection(this.raidIndex) end
end

local function OnGroupSlotDragStop()
    if not Raider.dragRaidIndex then return end
    local page = this.groupPage
    local target = Raider.raidDropSlot
    page.groupMovePending = true
    Raider.dragRaidIndex = nil; Raider.raidDropSlot = nil; Raider.raidDragStarted = nil
    page.dragGhost:SetScript("OnUpdate", nil); page.dragGhost:Hide()
    local settings = GroupSettings(page)
    Raider.UI.Components.SetAlternatingRowColor(this, settings.raidGroupBackgroundColor, this.slotIndex, settings.raidGroupOddLightness)
    if not target and type(MouseIsOver) == "function" then
        for group = 1, 8 do
            if MouseIsOver(page.groupPanels[group]) then
                for index = 1, 5 do
                    local candidate = page.groupSlots[group][index]
                    if not candidate.hasMember then target = candidate; break end
                end
                break
            end
        end
    end
    if not target then page.refreshGroupView(); return end
    local sourceName = this.displayedMember and this.displayedMember.name
    local targetName = target.displayedMember and target.displayedMember.name
    if not page.moveMemberToSlot(this.displayedMember, target.displayedMember, target.targetGroup) then page.refreshGroupView(); return end
    if sourceName then
        page.groupDisplaySlots[sourceName] = { group = target.targetGroup, slot = target.slotIndex }
        if targetName then
            page.groupDisplaySlots[targetName] = { group = this.targetGroup, slot = this.slotIndex }
            page.groupVacantSlots[this.targetGroup][this.slotIndex] = nil
        else
            page.groupVacantSlots[this.targetGroup][this.slotIndex] = true
        end
        page.groupVacantSlots[target.targetGroup][target.slotIndex] = nil
    end
    page.refreshGroupView()
end

local function OnGroupSlotEnter()
    if Raider.UI.Components.IsClassicSkin() then Raider.UI.Components.SetClassicRowShade(this, math.mod(this.slotIndex or 1, 2) == 0, true) end
    local settings = GroupSettings(this.groupPage)
    this.mosRaidHovered = true
    SetGroupSlotHover(this, settings, true)
    local color = settings.raidGroupHoverColor; Raider.UI.Components.SetRowColor(this, color, 0.98)
    if Raider.dragRaidIndex then Raider.raidDropSlot = this end
end

local function OnGroupSlotLeave()
    this.mosRaidHovered = nil
    SetGroupSlotHover(this, GroupSettings(this.groupPage), false)
    if Raider.UI.Components.IsClassicSkin() then Raider.UI.Components.SetClassicRowShade(this, math.mod(this.slotIndex or 1, 2) == 0, false) end
    local settings = GroupSettings(this.groupPage)
    Raider.UI.Components.SetAlternatingRowColor(this, settings.raidGroupBackgroundColor, this.slotIndex, settings.raidGroupOddLightness)
    if Raider.raidDropSlot == this then Raider.raidDropSlot = nil end
end

function RaidManagement.AttachGroupSlotHandlers(slot, page)
    slot:SetScript("OnHide",OnRaidMemberHide)
    slot.groupPage = page
    slot:SetScript("OnMouseDown", OnGroupSlotMouseDown); slot:SetScript("OnMouseUp", OnGroupSlotMouseUp)
    slot:SetScript("OnClick", OnGroupSlotClick); slot:SetScript("OnDragStart", OnGroupSlotDragStart); slot:SetScript("OnDragStop", OnGroupSlotDragStop)
    slot:SetScript("OnEnter", OnGroupSlotEnter); slot:SetScript("OnLeave", OnGroupSlotLeave)
end

function RaidManagement.SetGroupRenderer(page, dependencies)
    page.groupRenderer = dependencies
end

local function GroupGeometry(page, width, height)
    local db = GroupSettings(page)
    if page.mosCompactGroupWidth and not page.getGroupSettings then
        return RaidManagement.CalculateGroupGeometry(width, height, width < 260 and 1 or 2, width, 20, true, true, 22, 6, db.raidGroupShowBorder)
    end
    local hidden = db.raidGroupHideEmptyGroups
    return RaidManagement.CalculateGroupGeometry(width, height, db.raidGroupColumns, db.raidGroupTileWidth, db.raidGroupTileHeight, db.raidGroupShowHeader, db.raidGroupAutoTileWidth, db.raidGroupHeaderHeight, db.raidGroupMargin, db.raidGroupShowBorder, true,
        hidden and page.visibleGroupCount or 8, hidden and db.raidGroupAutoAdjustVertically, hidden and db.raidGroupAutoAdjustHorizontally, page.getGroupSettings ~= nil and not hidden)
end

function RaidManagement.MeasureGroupHeight(width, page)
    local geometry = GroupGeometry(page, width, page.mosGroupHeight)
    return geometry.contentHeight
end

function RaidManagement.ResolveGroupViewport(page)
    local width, height
    if page.mosGroupLayout then
        local pageWidth, pageHeight = PageSpan(page)
        width = pageWidth - page.mosGroupLeft - (page.mosCompactGroupWidth and 0 or 4)
        height = pageHeight + page.mosGroupTop - page.mosGroupBottom
    else width, height = PageSpan(page.groupFrame); width = width + (page.mosGroupScrollGutter or 0) end
    width, height = math.max(1, width), math.max(1, height)
    page.mosGroupHeight = height
    local overflow, maximum, measuredHeight
    width, measuredHeight, overflow, maximum = Raider.UI.Components.ResolveScrollLayout(width, height, 20, RaidManagement.MeasureGroupHeight, page)
    page.mosGroupScrollGutter = overflow and 20 or 0
    if page.mosGroupLayout then
        page.groupFrame:ClearAllPoints()
        page.groupFrame:SetPoint("TOPLEFT", page, "TOPLEFT", page.mosGroupLeft, page.mosGroupTop)
        page.groupFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -(page.mosCompactGroupWidth and 0 or 4) - page.mosGroupScrollGutter, page.mosGroupBottom)
    end
    if page.mosCompactGroupWidth then
        -- Wheel/clipping geometry uses the same supplied rectangle, even while
        -- native anchored descendants retain bounds from the preceding layout.
        page.groupFrame:SetWidth(width); page.groupFrame:SetHeight(height)
    end
    return width, height, maximum
end

function RaidManagement.RefreshGroupView(page)
    if not page.groupFrame:IsVisible() then return end
    local renderer = page.groupRenderer
    renderer.ensureDatabase()
    if page.getGroupSettings then page.groupSettings = page.getGroupSettings() end
    local settings = GroupSettings(page)
    RaidManagement.ApplyGroupViewBackground(page.groupCanvas, settings, page.getGroupSettings ~= nil)
    local roster = page.groupRoster or {}; page.groupRoster = roster
    local memberCount = math.floor(math.max(0, math.min(40, tonumber(renderer.getRaidMemberCount()) or 0)))
    local index
    for index = 1, 8 do page.groupCounts[index] = 0 end
    for index = 1, memberCount do
        local member = roster[index] or {}; roster[index] = member
        member[1], member[2], member[3], member[4], member[5], member[6], member[7], member[8] = renderer.getRaidMemberInfo(index)
        member[3] = math.floor(math.max(1, math.min(8, tonumber(member[3]) or 1)))
        if member[1] then page.groupCounts[member[3]] = page.groupCounts[member[3]] + 1 end
    end
    for index = memberCount + 1, table.getn(roster) do
        for field = 1, 8 do roster[index][field] = nil end
    end
    page.visibleGroupCount = 0
    for index = 1, 8 do if page.groupCounts[index] > 0 then page.visibleGroupCount = page.visibleGroupCount + 1 end end
    local width, height, maximum = RaidManagement.ResolveGroupViewport(page)
    local backgroundColor = settings.raidGroupBackgroundColor
    local textColor = settings.raidGroupTextColor
    local lootMethod, raidLootMasterIndex = renderer.getLootMasterInfo()
    local compact = page.mosCompactGroupWidth ~= nil
    local legacyCompact = compact and not page.getGroupSettings
    local slotHeight = legacyCompact and 20 or tonumber(settings.raidGroupTileHeight) or 22
    local tileTextSize = legacyCompact and 10 or tonumber(settings.raidGroupTileTextSize) or 10
    local headerTextSize = legacyCompact and 10 or tonumber(settings.raidGroupHeaderTextSize) or 10
    local geometry = GroupGeometry(page, width, height)
    slotHeight = geometry.tileHeight
    local columns, groupRows = geometry.columns, geometry.rows
    local layoutWidth, xOffset, columnWidth = geometry.layoutWidth, geometry.xOffset, geometry.columnWidth
    local headerHeight, groupHeight = geometry.headerHeight, geometry.groupHeight
    local groupInset = geometry.tileInset
    local contentHeight = geometry.contentHeight
    local yOffset = 0
    page.groupCanvas:SetWidth(width); page.groupCanvas:SetHeight(geometry.canvasHeight)
    if compact and page.groupFrame.UpdateScrollChildRect then page.groupFrame:UpdateScrollChildRect() end
    Raider.UI.Components.ApplyScrollRange(page.groupFrame, page.groupScrollBar, maximum)
    local groupIndex, slotIndex
    local visibleIndex = 0
    for groupIndex = 1, 8 do
        local visible = not settings.raidGroupHideEmptyGroups or page.groupCounts[groupIndex] > 0
        local column = math.mod(visibleIndex, columns)
        local row = math.floor(visibleIndex / columns)
        local rowCount = row == groupRows - 1 and geometry.visibleCount - row * columns or columns
        local panelWidth = geometry.autoHorizontal and rowCount > 0 and rowCount < columns
            and (layoutWidth - (rowCount - 1) * geometry.margin) / rowCount or columnWidth
        local x = math.floor(xOffset + column * (panelWidth + geometry.margin) + 0.5)
        local right = math.floor(xOffset + (column + 1) * (panelWidth + geometry.margin) - geometry.margin + 0.5)
        if column == (geometry.autoHorizontal and rowCount < columns and rowCount or columns) - 1 then right = math.floor(xOffset + layoutWidth) end
        panelWidth = math.max(1, right - x)
        local top = math.floor(yOffset + row * (groupHeight + geometry.margin) + 0.5)
        local bottom = math.floor(yOffset + row * (groupHeight + geometry.margin) + groupHeight + 0.5)
        local y = -top
        local panel = page.groupPanels[groupIndex]
        panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", page.groupCanvas, "TOPLEFT", x, y); panel:SetWidth(panelWidth); panel:SetHeight(bottom - top)
        if visible then panel:Show(); visibleIndex = visibleIndex + 1 else panel:Hide() end
        local header = page.groupHeaders[groupIndex]
        RaidManagement.ApplyGroupTileAppearance(panel, header, headerHeight, settings)
        SetFontSize(header, headerTextSize)
        local headerInset = 0
        header:ClearAllPoints(); header:SetPoint("TOPLEFT", panel, "TOPLEFT", headerInset, 0); header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -headerInset, 0)
        header.mosFitFontSize = headerTextSize
        Raider.UI.Components.FitButtonLabel(header, math.max(1, panelWidth - headerInset * 2)); header:SetJustifyH("CENTER")
        if header.SetWordWrap then header:SetWordWrap(false) end
        header:SetHeight(math.max(1, headerHeight)); header:SetJustifyV("MIDDLE")
        panel.headerHit:ClearAllPoints(); panel.headerHit:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0); panel.headerHit:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0); panel.headerHit:SetHeight(math.max(1, headerHeight))
        if visible and (legacyCompact or settings.raidGroupShowHeader) then header:Show(); panel.headerHit:Show(); panel.headerBackground:Show()
        else header:Hide(); panel.headerHit:Hide(); panel.headerBackground:Hide() end
        for slotIndex = 1, 5 do
            local slot = page.groupSlots[groupIndex][slotIndex]
            SetFontSize(slot.name, tileTextSize); SetFontSize(slot.level, tileTextSize); SetFontSize(slot.class, tileTextSize); SetFontSize(slot.empty, tileTextSize); SetFontSize(slot.offline, tileTextSize)
            local slotTop = math.floor(top + headerHeight + (slotIndex - 1) * slotHeight + 0.5)
            local slotBottom = slotIndex == 5 and bottom or math.floor(top + headerHeight + slotIndex * slotHeight + 0.5)
            slot:ClearAllPoints(); slot:SetPoint("TOPLEFT", page.groupCanvas, "TOPLEFT", x, -slotTop); slot:SetWidth(panelWidth); slot:SetHeight(math.max(1, slotBottom - slotTop))
            Raider.UI.Components.SetAtlasSurface(slot, settings.raidGroupMemberTexture == "game" and groupMemberArtwork or nil)
            SetGroupSlotHover(slot, settings, slot.mosRaidHovered)
            if settings.raidGroupMemberTexture == "game" then slot.topEdge:Hide(); slot.bottomEdge:Hide()
            else slot.topEdge:Show(); slot.bottomEdge:Show() end
            slot.mosGroupWidth = panelWidth
            if visible then slot:Show() else slot:Hide() end
            if page.getGroupSettings then
                slot.empty.mosFitFontSize = tileTextSize; Raider.UI.Components.FitButtonLabel(slot.empty, math.max(1, panelWidth - groupInset * 2 - 4)); slot.empty:SetJustifyH("CENTER")
            end
            Raider.UI.Components.SetAlternatingRowColor(slot, backgroundColor, slotIndex, settings.raidGroupOddLightness)
            if settings.raidGroupMemberTexture == "game" then slot:SetBackdropBorderColor(0,0,0,0)
            else
                slot:SetBackdropBorderColor(0.42,0.42,0.42,1)
                if slot.mosRaidHovered then Raider.UI.Components.SetRowColor(slot, settings.raidGroupHoverColor, 0.98) end
            end
            Raider.UI.Components.SetClassicRowShade(slot, math.mod(slotIndex, 2) == 0, false)
            slot.empty:SetTextColor(textColor[1] * 0.55, textColor[2] * 0.55, textColor[3] * 0.55); slot.offline:SetTextColor(textColor[1] * 0.55, textColor[2] * 0.55, textColor[3] * 0.55)
            slot.raidIndex = nil; slot.hasMember = nil; slot.displayedMember.name = nil; slot.displayedMember.raidRank = nil
            slot.name:Hide(); slot.level:Hide(); slot.class:Hide(); slot.crown:Hide(); slot.lootMasterIcon:Hide(); slot.offline:Hide(); slot.empty:Show()
        end
    end
    local reserved = page.groupReservedSlots
    local activeNames = page.groupActiveNames
    local groupIndex, slotIndex
    for groupIndex = 1, 8 do
        for slotIndex = 1, 5 do reserved[groupIndex][slotIndex] = nil end
    end
    local activeName
    for activeName in pairs(activeNames) do activeNames[activeName] = nil end
    local raidIndex
    for raidIndex = 1, memberCount do
        local member = roster[raidIndex]
        local name, subgroup = member[1], member[3]
        subgroup = math.max(1, math.min(8, tonumber(subgroup) or 1))
        if name then activeNames[name] = true end
        local placement = name and page.groupDisplaySlots[name]
        if placement and placement.group == subgroup and placement.slot >= 1 and placement.slot <= 5 and not reserved[subgroup][placement.slot] then
            reserved[subgroup][placement.slot] = raidIndex
        end
    end
    for activeName in pairs(page.groupDisplaySlots) do
        if not activeNames[activeName] then page.groupDisplaySlots[activeName] = nil end
    end
    for raidIndex = 1, memberCount do
        local member = roster[raidIndex]
        local name, raidRank, subgroup, level = member[1], member[2], member[3], member[4]
        local class, classFile, zone, online = member[5], member[6], member[7], member[8]
        subgroup = math.max(1, math.min(8, tonumber(subgroup) or 1))
        local placement = name and page.groupDisplaySlots[name]
        local slot = placement and placement.group == subgroup and reserved[subgroup][placement.slot] == raidIndex and page.groupSlots[subgroup][placement.slot] or nil
        if not slot then
            for slotIndex = 1, 5 do
                if not reserved[subgroup][slotIndex] and not page.groupVacantSlots[subgroup][slotIndex] and not page.groupSlots[subgroup][slotIndex].hasMember then
                    slot = page.groupSlots[subgroup][slotIndex]
                    break
                end
            end
            if not slot then
                for slotIndex = 1, 5 do
                    if not page.groupSlots[subgroup][slotIndex].hasMember then slot = page.groupSlots[subgroup][slotIndex]; break end
                end
            end
        end
        if slot and name then
            local memberIndex = renderer.getRaidMemberIndex and renderer.getRaidMemberIndex(raidIndex) or raidIndex
            slot.raidIndex = memberIndex
            slot.hasMember = true; slot.displayedMember.name = name or "Unknown"; slot.displayedMember.raidRank = raidRank or 0
            slot.displayedMember.raidIndex = memberIndex; slot.displayedMember.subgroup = subgroup
            slot.name:SetText(name or "Unknown"); slot.level:SetText(level or ""); slot.class:SetText(class or "")
            local showLootMasterIcon = settings.raidGroupShowLootMaster and lootMethod == "master" and tonumber(raidLootMasterIndex) == memberIndex
            local showRoleIcon = settings.raidGroupShowRoleIcon and (tonumber(raidRank) or 0) > 0
            local showLevel = not legacyCompact and online and settings.raidGroupShowLevel
            local showClass = not legacyCompact and settings.raidGroupShowClass
            local slotWidth = slot.mosGroupWidth
            local showOffline = not online and (not page.getGroupSettings or not settings.raidGroupShowClass)
            local columns = RaidManagement.CalculateGroupSlotColumns(slotWidth, showRoleIcon, showLootMasterIcon, showLevel, showClass, showOffline, true)
            showRoleIcon, showLootMasterIcon = columns.showRoleIcon, columns.showLootIcon
            showLevel, showClass = columns.levelWidth > 0, columns.classWidth > 0
            if showRoleIcon and (tonumber(raidRank) or 0) == 2 then
                slot.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); slot.crown:Show()
            elseif showRoleIcon and (tonumber(raidRank) or 0) == 1 then
                slot.crown:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon"); slot.crown:Show()
            else
                slot.crown:Hide()
            end
            local iconInset = columns.iconInset or 5
            slot.crown:ClearAllPoints(); slot.crown:SetPoint("LEFT", slot, "LEFT", iconInset, 0)
            slot.crown:SetWidth(10); slot.crown:SetHeight(10); slot.lootMasterIcon:SetWidth(10); slot.lootMasterIcon:SetHeight(10)
            slot.lootMasterIcon:ClearAllPoints(); slot.lootMasterIcon:SetPoint("LEFT", slot, "LEFT", iconInset + (showRoleIcon and 12 or 0), 0)
            if showLootMasterIcon then slot.lootMasterIcon:Show() else slot.lootMasterIcon:Hide() end
            local nameInset, nameWidth = columns.nameInset, columns.nameWidth
            local classWidth, levelWidth, offlineWidth = columns.classWidth, columns.levelWidth, columns.offlineWidth
            slot.name:ClearAllPoints(); slot.name:SetPoint("LEFT", slot, "LEFT", nameInset, 0); slot.name:SetWidth(nameWidth); slot.name:Show(); slot.empty:Hide()
            local rightInset = columns.rightInset or 6
            slot.offline:ClearAllPoints(); slot.offline:SetPoint("RIGHT", slot, "RIGHT", -rightInset, 0); slot.offline:SetWidth(offlineWidth); slot.offline:SetJustifyH("RIGHT")
            slot.class:ClearAllPoints(); slot.class:SetWidth(classWidth); slot.class:SetJustifyH("LEFT")
            if showClass then slot.class:SetPoint("RIGHT", slot, "RIGHT", -rightInset - offlineWidth - (offlineWidth > 0 and 4 or 0), 0) end
            slot.level:ClearAllPoints(); slot.level:SetWidth(levelWidth)
            if showLevel then
                if showClass then slot.level:SetPoint("RIGHT", slot.class, "LEFT", -5, 0)
                elseif offlineWidth > 0 then slot.level:SetPoint("RIGHT", slot.offline, "LEFT", -5, 0)
                else slot.level:SetPoint("RIGHT", slot, "RIGHT", -rightInset, 0) end
            end
            if showLevel then slot.level:Show() else slot.level:Hide() end
            if showClass then slot.class:Show() else slot.class:Hide() end
            if online or offlineWidth == 0 then slot.offline:Hide() else slot.offline:Show() end
            local shade = online and 1 or 0.55
            local baseR, baseG, baseB = online and textColor[1] or 1, online and textColor[2] or 1, online and textColor[3] or 1
            slot.name:SetTextColor(baseR * shade, baseG * shade, baseB * shade); slot.level:SetTextColor(baseR * shade, baseG * shade, baseB * shade); slot.class:SetTextColor(baseR * shade, baseG * shade, baseB * shade)
            slot.offline:SetTextColor(baseR * shade, baseG * shade, baseB * shade)
            slot.crown:SetAlpha(online and 1 or 0.55); slot.lootMasterIcon:SetAlpha(online and 1 or 0.55)
            local classKey = string.upper(classFile or class or "")
            local color = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classKey]) or Raider.UI.Components.Theme.classColors[classKey]
            if online and settings.raidGroupClassColors and color then slot.name:SetTextColor(color.r, color.g, color.b); slot.class:SetTextColor(color.r, color.g, color.b) end
        end
    end
end

function RaidManagement.CreateDragGhost(page)
    local ghost = Raider.UI.Components.CreateContainer(nil, UIParent)
    ghost:SetWidth(300); ghost:SetHeight(20); ghost:SetFrameStrata("TOOLTIP"); ghost:EnableMouse(false)
    ghost:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 9, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    ghost:SetBackdropColor(0.025, 0.025, 0.025, 0.98); ghost:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)
    ghost.topEdge = Raider.UI.Components.CreateTexture(ghost, nil, "BORDER")
    ghost.topEdge:SetPoint("TOPLEFT", ghost, "TOPLEFT", 3, -2); ghost.topEdge:SetPoint("TOPRIGHT", ghost, "TOPRIGHT", -3, -2); ghost.topEdge:SetHeight(1); ghost.topEdge:SetTexture(0.42, 0.42, 0.42, 0.8)
    ghost.bottomEdge = Raider.UI.Components.CreateTexture(ghost, nil, "BORDER")
    ghost.bottomEdge:SetPoint("BOTTOMLEFT", ghost, "BOTTOMLEFT", 3, 2); ghost.bottomEdge:SetPoint("BOTTOMRIGHT", ghost, "BOTTOMRIGHT", -3, 2); ghost.bottomEdge:SetHeight(1); ghost.bottomEdge:SetTexture(0, 0, 0, 1)
    ghost.name = Raider.UI.Components.CreateLabel(ghost, nil, "OVERLAY", "GameFontHighlightSmall")
    ghost.name:SetPoint("LEFT", ghost, "LEFT", 6, 0); ghost.name:SetJustifyH("LEFT")
    ghost.crown = Raider.UI.Components.CreateTexture(ghost, nil, "OVERLAY")
    ghost.crown:SetPoint("LEFT", ghost, "LEFT", 5, 0); ghost.crown:SetWidth(13); ghost.crown:SetHeight(13); ghost.crown:Hide()
    ghost.lootMasterIcon = Raider.UI.Components.CreateTexture(ghost, nil, "OVERLAY")
    ghost.lootMasterIcon:SetPoint("LEFT", ghost, "LEFT", 5, 0); ghost.lootMasterIcon:SetWidth(13); ghost.lootMasterIcon:SetHeight(13); ghost.lootMasterIcon:SetTexture("Interface\\GroupFrame\\UI-Group-MasterLooter"); ghost.lootMasterIcon:Hide()
    ghost.level = Raider.UI.Components.CreateLabel(ghost, nil, "OVERLAY", "GameFontHighlightSmall")
    ghost.level:SetPoint("RIGHT", ghost, "RIGHT", -76, 0); ghost.level:SetJustifyH("RIGHT")
    ghost.class = Raider.UI.Components.CreateLabel(ghost, nil, "OVERLAY", "GameFontHighlightSmall")
    ghost.class:SetPoint("RIGHT", ghost, "RIGHT", -6, 0); ghost.class:SetWidth(64); ghost.class:SetJustifyH("RIGHT")
    ghost.offline = Raider.UI.Components.CreateLabel(ghost, nil, "OVERLAY", "GameFontDisableSmall")
    ghost.offline:SetPoint("RIGHT", ghost, "RIGHT", -6, 0); ghost.offline:SetWidth(42); ghost.offline:SetJustifyH("RIGHT"); ghost.offline:SetText("Offline"); ghost.offline:Hide(); ghost:Hide()
    page.dragGhost = ghost
    page.updateDragGhost = function() RaidManagement.UpdateDragGhost(page) end
    return ghost
end

function RaidManagement.CreateGroupGrid(page)
    page.groupHeaders = {}; page.groupPanels = {}; page.groupSlots = {}; page.groupCounts = { 0, 0, 0, 0, 0, 0, 0, 0 }
    page.groupDisplaySlots = {}; page.groupActiveNames = {}; page.groupReservedSlots = { {}, {}, {}, {}, {}, {}, {}, {} }
    page.groupVacantSlots = { {}, {}, {}, {}, {}, {}, {}, {} }
    local groupIndex
    for groupIndex = 1, 8 do
        local panel = Raider.UI.Components.CreateContainer(nil, page.groupCanvas)
        panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } }); panel:SetBackdropColor(0, 0, 0, 0); panel:SetBackdropBorderColor(0, 0, 0, 0)
        panel.headerBackground = Raider.UI.Components.CreateTexture(panel, nil, "BACKGROUND")
        panel.headerBackground:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
        panel.headerBackground:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
        page.groupPanels[groupIndex] = panel
        local header = Raider.UI.Components.CreateLabel(panel, nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4); header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -4)
        header:SetText("Group " .. groupIndex); header:SetJustifyH("CENTER"); page.groupHeaders[groupIndex] = header
        panel.headerHit = Raider.UI.Components.CreateControl(nil, panel)
        panel.headerHit.groupPage, panel.headerHit.groupPanel, panel.headerHit.groupLabel = page, panel, header
        panel.headerHit:SetScript("OnEnter", OnGroupHeaderEnter); panel.headerHit:SetScript("OnLeave", OnGroupHeaderLeave); panel.headerHit:SetScript("OnHide", OnGroupHeaderLeave)
        page.groupSlots[groupIndex] = {}
        local slotIndex
        for slotIndex = 1, 5 do
            local slot = Raider.UI.Components.CreateControl(nil, page.groupCanvas)
            slot:SetHeight(18)
            slot:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
            slot:SetBackdropColor(0.025, 0.025, 0.025, 0.98); slot:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)
            Raider.UI.Components.RegisterSkinnedSurface(slot, "row", { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } }, { 0.025, 0.025, 0.025, 0.98 }, { 0.42, 0.42, 0.42, 1 })
            slot.topEdge = Raider.UI.Components.CreateTexture(slot, nil, "BORDER"); slot.topEdge:SetPoint("TOPLEFT", slot, "TOPLEFT", 3, -2); slot.topEdge:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -3, -2); slot.topEdge:SetHeight(1); slot.topEdge:SetTexture(0.42, 0.42, 0.42, 0.8)
            slot.bottomEdge = Raider.UI.Components.CreateTexture(slot, nil, "BORDER"); slot.bottomEdge:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 3, 2); slot.bottomEdge:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -3, 2); slot.bottomEdge:SetHeight(1); slot.bottomEdge:SetTexture(0, 0, 0, 1)
            slot.name = Raider.UI.Components.CreateLabel(slot, nil, "OVERLAY", "GameFontHighlightSmall"); slot.name:SetPoint("LEFT", slot, "LEFT", 6, 0); slot.name:SetJustifyH("LEFT")
            slot.crown = Raider.UI.Components.CreateTexture(slot, nil, "OVERLAY"); slot.crown:SetPoint("LEFT", slot, "LEFT", 5, 0); slot.crown:SetWidth(13); slot.crown:SetHeight(13); slot.crown:Hide()
            slot.lootMasterIcon = Raider.UI.Components.CreateTexture(slot, nil, "OVERLAY"); slot.lootMasterIcon:SetPoint("RIGHT", slot, "RIGHT", -4, 0); slot.lootMasterIcon:SetWidth(13); slot.lootMasterIcon:SetHeight(13); slot.lootMasterIcon:SetTexture("Interface\\GroupFrame\\UI-Group-MasterLooter"); slot.lootMasterIcon:Hide()
            slot.level = Raider.UI.Components.CreateLabel(slot, nil, "OVERLAY", "GameFontHighlightSmall"); slot.level:SetPoint("RIGHT", slot, "RIGHT", -76, 0); slot.level:SetWidth(24); slot.level:SetJustifyH("RIGHT")
            slot.class = Raider.UI.Components.CreateLabel(slot, nil, "OVERLAY", "GameFontHighlightSmall"); slot.class:SetPoint("RIGHT", slot, "RIGHT", -6, 0); slot.class:SetWidth(64); slot.class:SetJustifyH("RIGHT")
            slot.empty = Raider.UI.Components.CreateLabel(slot, nil, "OVERLAY", "GameFontDisableSmall"); slot.empty:SetPoint("CENTER", slot, "CENTER", 0, 0); slot.empty:SetText("Empty")
            slot.offline = Raider.UI.Components.CreateLabel(slot, nil, "OVERLAY", "GameFontDisableSmall"); slot.offline:SetPoint("RIGHT", slot, "RIGHT", -6, 0); slot.offline:SetWidth(42); slot.offline:SetJustifyH("RIGHT"); slot.offline:SetText("Offline"); slot.offline:Hide()
            slot.targetGroup = groupIndex; slot.slotIndex = slotIndex; slot.displayedMember = {}; slot:RegisterForClicks("LeftButtonUp", "RightButtonUp"); slot:RegisterForDrag("LeftButton")
            RaidManagement.AttachGroupSlotHandlers(slot, page)
            page.groupSlots[groupIndex][slotIndex] = slot
            panel.outlineLevel = math.max(panel.outlineLevel or 0, slot:GetFrameLevel() + 2)
        end
    end
end

function RaidManagement.CreateMemberMenu(page, runAction, isIgnored)
    local dismiss = Raider.UI.Components.CreateControl(nil, UIParent)
    dismiss:SetAllPoints(UIParent); dismiss:SetFrameStrata("FULLSCREEN_DIALOG"); dismiss:SetFrameLevel(210); dismiss:Hide()
    page.memberMenuDismiss = dismiss

    local menu = Raider.UI.Components.CreateContainer(nil, UIParent)
    menu:SetWidth(132); menu:SetHeight(168); menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetFrameLevel(220)
    menu:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    menu:SetBackdropColor(0.03, 0.03, 0.06, 0.98); menu:SetBackdropBorderColor(0.55, 0.55, 0.65, 1)
    menu.title = Raider.UI.Components.CreateLabel(menu, nil, "OVERLAY", "GameFontNormalSmall")
    menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -9); menu.title:SetWidth(112); menu.title:SetJustifyH("LEFT")
    menu.buttons = {}
    page.memberMenu = menu

    local menuSpecs = { { "New Leader", "leader" }, { "Promote", "assistant" }, { "Loot Master", "lootmaster" }, { "Remove", "remove" }, { "Report", "report" }, { "Ignore Player", "ignore" } }
    local menuIndex
    for menuIndex = 1, table.getn(menuSpecs) do
        local button = Raider.UI.Components.CreateControl(nil, menu)
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -24 - ((menuIndex - 1) * 20)); button:SetWidth(116); button:SetHeight(19)
        button.label = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontHighlight")
        button.label:SetPoint("LEFT", button, "LEFT", 4, 0); button.label:SetJustifyH("LEFT"); button.label:SetText(menuSpecs[menuIndex][1])
        button.action = menuSpecs[menuIndex][2]
        button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        button:SetScript("OnClick", function()
            local owner = page.contextSlot
            if owner and owner.displayedMember then runAction(owner.displayedMember, this.action) end
            menu:Hide()
        end)
        menu.buttons[menuIndex] = button
    end

    menu.cancel = Raider.UI.Components.CreateControl(nil, menu)
    menu.cancel:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -144); menu.cancel:SetWidth(116); menu.cancel:SetHeight(19)
    menu.cancel.label = Raider.UI.Components.CreateLabel(menu.cancel, nil, "OVERLAY", "GameFontHighlight")
    menu.cancel.label:SetPoint("LEFT", menu.cancel, "LEFT", 4, 0); menu.cancel.label:SetText("Cancel")
    menu.cancel:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    menu.cancel:SetScript("OnClick", function() menu:Hide() end)
    dismiss:SetScript("OnClick", function() menu:Hide() end)
    menu:SetScript("OnHide", function() dismiss:Hide() end); menu:Hide()

    page.showMemberMenu = function(owner) RaidManagement.ShowMemberMenu(page, owner, isIgnored) end
    return menu
end

function RaidManagement.ShowMemberMenu(page, owner, isIgnored)
    if not owner or not owner.displayedMember then return end
    local member = owner.displayedMember
    page.contextSlot = owner
    page.memberMenu.title:SetText(member.name or "Unknown")
    page.memberMenu.buttons[2].label:SetText((tonumber(member.raidRank) or 0) == 1 and "Demote" or "Promote")
    page.memberMenu.buttons[6].label:SetText(isIgnored(member.name) and "Unignore Player" or "Ignore Player")
    local cursorX, cursorY = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale() or 1
    page.memberMenu:ClearAllPoints(); page.memberMenu:SetPoint("TOP", UIParent, "BOTTOMLEFT", cursorX / uiScale, (cursorY / uiScale) - 2)
    page.memberMenuDismiss:Show(); page.memberMenu:Show()
end

function RaidManagement.AttachViewToggle(page, onChanged)
    page.viewButton:SetScript("OnClick", function()
        page.raidView = page.raidView == "groups" and "list" or "groups"
        onChanged()
    end)
    page.classicListButton:SetScript("OnClick", function() page.raidView = "list"; onChanged() end)
    page.classicGroupButton:SetScript("OnClick", function() page.raidView = "groups"; onChanged() end)
    page.classicTwoButton:SetScript("OnClick", function() Raider.Database.SetSetting("raidGroupColumns", 2); page.raidView = "groups"; onChanged() end)
    page.classicFourButton:SetScript("OnClick", function() Raider.Database.SetSetting("raidGroupColumns", 4); page.raidView = "groups"; onChanged() end)
end

function RaidManagement.SetActions(page, viewButton, raidLeaderToolsButton, lootMasterToolsButton, addStatisticsButton, exportButton, quitButton)
    page.raidLeaderToolsButton = raidLeaderToolsButton; page.lootMasterToolsButton = lootMasterToolsButton
    page.addStatisticsButton = addStatisticsButton; page.exportButton = exportButton; page.quitButton = quitButton
    page.actions = {
        { button = viewButton, width = 92 },
        { button = raidLeaderToolsButton, width = 118 },
        { button = lootMasterToolsButton, width = 118 },
        { button = exportButton, width = 88 },
        { button = quitButton, width = 64 },
    }
end

local function InvokeActionSource(source)
    local handler = source:GetScript("OnClick")
    if not handler then return false end
    local previous = this
    this = source
    local ok, message = pcall(handler)
    this = previous
    if not ok then error(message) end
    return true
end

local function ToolSpecs(page, kind)
    local controls = page.refreshControls
    page.toolActionSpecs = page.toolActionSpecs or {
        leader = {{key = "rl-mode", source = controls.leaderMode, caption = "RL Mode", icon = "raid_tools", openRaid = true},
            {key = "ready-check", source = controls.readyCheck, caption = "Ready Check", icon = "check"}},
        loot = {
            {key = "loot-mode", source = controls.mode, caption = "Loot Master Mode", icon = "loot_tools"},
            {key = "reset-loot", source = controls.resetLoot, caption = "Reset Loot", icon = "reset"},
            {key = "import-sr", source = controls.import, caption = "Import SR", icon = "import"},
            {key = "share-sr", source = controls.shareSr, caption = "Share SR", icon = "link"},
            {key = "loot-rules", source = controls.lootRules, caption = "Loot Rules", icon = "rules"},
            {key = "send-loot-rules", source = controls.sendLootRules, caption = "Send Loot Rules", icon = "rules"},
            {key = "reycoin", source = controls.reycoin, caption = "Reycoin list", icon = "lootmaster"},
            {key = "new-roll", source = controls.newRoll, caption = "New Roll", icon = "dice"},
        },
    }
    return page.toolActionSpecs[kind]
end

local function SourceEnabled(source)
    if not source then return false end
    if not source.IsEnabled then return true end
    local enabled = source:IsEnabled()
    return enabled ~= nil and enabled ~= false and enabled ~= 0
end

local function ToolCaption(spec)
    local caption = spec.source and spec.source.label and spec.source.label:GetText()
    return caption and caption ~= "" and caption or spec.caption
end

local function InvokeToolChoice()
    local option = this
    option:GetParent():Hide()
    InvokeActionSource(option.toolSource)
end

-- Explicit actions let other entry points reuse the actual dialogs and session
-- workflows without reaching into this module's private controls.
function RaidManagement.CreateQuickActions(options, loadSelectedRaid)
    local page, controls = options.page, options.page.refreshControls
    local actions = {}
    local function ActiveSession()
        if options.isTestRaid and options.isTestRaid() then return true end
        if options.isSessionActive then return options.isSessionActive() and true or false end
        local attendance = options.getAttendance()
        return attendance and (attendance._sessionDraft or attendance.sessionStartedAt) and true or false
    end
    function actions:GetState()
        local active = ActiveSession()
        local test = options.isTestRaid and options.isTestRaid() and true or false
        local attendance = options.getAttendance()
        return {
            active = active, test = test, primaryLabel = active and "Open Raid" or "Start new raid",
            canStart = not active and options.isInRaid() and true or false,
            canTest = not active, canLoad = not active,
            canSave = active and not test and attendance ~= nil, canQuit = active,
            canTools = active and attendance ~= nil,
        }
    end
    function actions:GetTools(kind)
        local specs, entries = ToolSpecs(page, kind), {}
        local state = self:GetState()
        RaidManagement.UpdateActionAvailability(page, state.test)
        for index = 1, table.getn(specs or {}) do
            local spec = specs[index]
            entries[index] = {id = spec.key, text = ToolCaption(spec), icon = spec.source and spec.source.mosClassicIconKey or spec.icon,
                enabled = state.canTools and SourceEnabled(spec.source)}
        end
        return entries
    end
    function actions:GetRecentSnapshots(limit)
        local history, entries = options.getRaidHistory() or {}, {}
        local canLoad = self:GetState().canLoad
        limit = math.max(0, math.min(5, math.floor(tonumber(limit) or 5)))
        for index = 1, math.min(limit, table.getn(history)) do
            local snapshot = history[index]
            local savedAt = snapshot.savedAt or snapshot.updatedAt
            local stamp = savedAt and date("%Y-%m-%d", savedAt) or ""
            entries[index] = {id = snapshot.id, date = stamp,
                text = tostring(snapshot.id or "Unknown") .. (stamp ~= "" and " | " .. stamp or ""),
                enabled = canLoad}
        end
        return entries
    end
    local function OpenRaid()
        if options.openRaidManagement then options.openRaidManagement() end
    end
    function actions:Run(key, snapshotId)
        local state = self:GetState()
        if key == "primary" then
            if not state.active and not state.canStart then return false end
            OpenRaid()
            if not state.active then return InvokeActionSource(controls.scan) end
            return true
        elseif key == "test" then
            if not state.canTest then return false end
            OpenRaid(); return InvokeActionSource(controls.testRaid)
        elseif key == "save" then
            if not state.canSave then return false end
            OpenRaid(); return InvokeActionSource(controls.export)
        elseif key == "quit" then
            if not state.canQuit then return false end
            OpenRaid(); return InvokeActionSource(controls.quit)
        elseif key == "load" then
            if not state.canLoad or not snapshotId then return false end
            local history, found = options.getRaidHistory() or {}, false
            for index = 1, table.getn(history) do
                if history[index].id == snapshotId then found = true; break end
            end
            if not found then return false end
            OpenRaid()
            if not self:GetState().canLoad then return false end
            history, found = options.getRaidHistory() or {}, false
            for index = 1, table.getn(history) do
                if history[index].id == snapshotId then found = true; break end
            end
            if not found then return false end
            page.selectedRaidHistoryId = snapshotId
            return loadSelectedRaid() and true or false
        end
        if not state.canTools then return false end
        for _, kind in ipairs({"leader", "loot"}) do
            local specs = ToolSpecs(page, kind)
            for index = 1, table.getn(specs) do
                local spec = specs[index]
                if spec.key == key then
                    if spec.openRaid then OpenRaid() end
                    local current = self:GetState()
                    RaidManagement.UpdateActionAvailability(page, current.test)
                    if not current.canTools or not SourceEnabled(spec.source) then return false end
                    return InvokeActionSource(spec.source)
                end
            end
        end
        return false
    end
    return actions
end

function RaidManagement.GetQuickActions()
    return RaidManagement.quickActions
end

function RaidManagement.UpdateToolSubmenu(page)
    local UI = Raider.UI.Components
    local controls = page.refreshControls
    controls.leaderMode:Hide(); controls.mode:Hide(); controls.resetLoot:Hide(); controls.import:Hide(); controls.shareSr:Hide(); controls.lootRules:Hide(); controls.sendLootRules:Hide()
    page.toolDropdowns = page.toolDropdowns or {}
    for key, panel in pairs(page.toolDropdowns) do if key ~= page.activeToolMenu then panel:Hide() end end
    UI.SetClassicButtonSelected(controls.raidLeaderTools, page.activeToolMenu == "leader")
    UI.SetClassicButtonSelected(controls.lootMasterTools, page.activeToolMenu == "loot")
    if not page.activeToolMenu then return end
    local key = page.activeToolMenu
    local toggle = key == "leader" and controls.raidLeaderTools or controls.lootMasterTools
    local panel = page.toolDropdowns[key]
    if not panel then
        local specs = ToolSpecs(page, key)
        panel = UI.CreateDropdownPanel(page, toggle, 230, 8 + table.getn(specs) * 24 + (table.getn(specs) - 1) * 4, 80)
        panel.mosMinimumFrameLevel = page:GetFrameLevel() + 80
        UI.Window.ApplyProjectSurface(panel)
        UI.RegisterSkinCallback(function() UI.Window.ApplyProjectSurface(panel) end)
        panel:ClearAllPoints(); panel:SetPoint("TOPRIGHT", toggle, "BOTTOMRIGHT", 0, -2)
        if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
        for index = 1, table.getn(specs) do
            local option = UI.CreateButton(panel, nil, "", 222, 24)
            option:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4 - (index - 1) * 28)
            option.toolSource = specs[index].source; option.toolCaption = specs[index].caption
            UI.SetProjectButtonOutline(option, false)
            option:SetScript("OnEnter", function() UI.SetProjectButtonOutline(this, true) end)
            option:SetScript("OnLeave", function() UI.SetProjectButtonOutline(this, false) end)
            option:SetScript("OnClick", InvokeToolChoice)
            panel.options[index] = option
        end
        local onHide = panel:GetScript("OnHide")
        panel:SetScript("OnHide", function()
            if panel.IsShown and panel:IsShown() then panel:Hide() end
            if onHide then onHide() end
            if page.activeToolMenu == key then page.activeToolMenu = nil end
            UI.SetClassicButtonSelected(toggle, false)
        end)
        page.toolDropdowns[key] = panel
    end
    local choiceWidth = 1
    for index = 1, table.getn(panel.options) do
        local option = panel.options[index]
        local sourceLabel = option.toolSource and (option.toolSource.label or option.toolSource)
        local caption = sourceLabel and sourceLabel.GetText and sourceLabel:GetText()
        option:SetText(caption and caption ~= "" and caption or option.toolCaption)
        option.label:ClearAllPoints(); option.label:SetPoint("LEFT", option, "LEFT", 4, 0); option.label:SetWidth(0)
        choiceWidth = math.max(choiceWidth, option.label:GetStringWidth() + 16)
        UI.SetButtonEnabled(option, SourceEnabled(option.toolSource))
    end
    for index = 1, table.getn(panel.options) do
        panel.options[index]:SetWidth(choiceWidth)
        panel.options[index].label:SetWidth(choiceWidth - 8)
        panel.options[index].label:SetJustifyV("MIDDLE")
    end
    panel:SetWidth(choiceWidth + 8)
    panel:Show(); UI.RefreshDropdownLayers(panel, toggle)
end

local function PlaceRaidHeaderButton(page, button, width, y, left, scale)
    button.mosCaptionBottomInset = 4
    Raider.UI.Components.SizeClassicButton(button, width, 26, scale)
    local inset = button.mosClassicIconKey and ((button.mosClassicIconInset or 7) + (button.mosClassicIconSize or 13) + 3) or 0
    button.mosLabelJustify = (button == page.classicSaved or inset > 0) and "LEFT" or "CENTER"
    if width > 26 then Raider.UI.Components.FitButtonLabel(button, math.max(1, width - (inset > 0 and inset + 4 or 16))) end
    Raider.UI.Components.ApplyButtonCaptionBaseline(button)
    button:ClearAllPoints(); button:SetPoint("TOPLEFT", page, "TOPLEFT", left, y)
    return left + width + 8
end

local function PlaceRaidHeaderLabel(page, control, width, y, left)
    local label = control.label or control
    control:ClearAllPoints(); control:SetPoint("TOPLEFT", page, "TOPLEFT", left, y)
    control:SetWidth(width); control:SetHeight(26)
    label:SetJustifyH("LEFT"); if label.SetJustifyV then label:SetJustifyV("MIDDLE") end
    Raider.UI.Components.FitButtonLabel(control, width)
    local font, size, flags = label:GetFont()
    if size < 9 then label:SetFont(font, 9, flags) end
    if label.SetWordWrap then label:SetWordWrap(false) end
    if control.label then control.mosCaptionBottomInset = 4; Raider.UI.Components.ApplyButtonCaptionBaseline(control)
    else label:SetHeight(22); label:SetJustifyV("BOTTOM") end
    return left + width + 8
end

function RaidManagement.LayoutActions(page)
    if Raider.UI.Components.IsClassicSkin() then
        local toolbarOffset = page.classicToolbarOffset or 0
        local sectionOffset = page.classicSectionOffset or 0
        local UI = Raider.UI.Components
        local pageWidth = PageSpan(page)
        local available = math.max(1, pageWidth - 12 - (page.raidInfoButton and 36 or 0))
        local showIssues = page.classicIssues:IsShown()
        RestoreHeaderFont(page.classicRaidName); RestoreHeaderFont(page.classicMeta)
        local nameLabel = page.classicRaidName.label or page.classicRaidName
        local metaLabel = page.classicMeta.label or page.classicMeta
        local raidId = page.classicMeta.mosRaidId or string.gsub(metaLabel:GetText() or "", "^|%s*", "")
        metaLabel:SetText(raidId)
        local raidName = page.classicRaidName.mosRaidName or string.gsub(nameLabel:GetText() or "", "^|%s*", "")
        nameLabel:SetText("|  " .. raidName)
        local savedText = page.classicSaved.mosRaidSavedText or page.classicSaved:GetText()
        page.classicSaved.mosRaidSavedText = savedText
        page.classicSaved:SetText(savedText)
        if showIssues then
            page.classicIssues.mosRaidIssuesText = page.classicIssues.mosRaidIssuesText or page.classicIssues:GetText()
            page.classicIssues:SetText(page.classicIssues.mosRaidIssuesText)
        end
        page.exportButton.label:Show(); page.quitButton.label:Show()
        local nameWidth = math.max(48, nameLabel:GetStringWidth() + 4)
        local metaWidth = math.max(42, metaLabel:GetStringWidth() + 4)
        local total = nameWidth + metaWidth + 108 + (showIssues and 96 or 0) + 108 + 90 + (showIssues and 40 or 32)
        local compact = total > available
        page.classicActionOffset = compact and 30 or 0
        local actionOffset = page.classicActionOffset
        local top, left = -9 - sectionOffset, 6
        local scale = 1
        if compact then
            page.classicRaidName:Hide()
            metaLabel:SetText(raidId)
            local iconOnly = pageWidth < 300
            local savedWidth = iconOnly and 72 or 108
            if iconOnly then page.classicSaved:SetText(savedText == "Not saved yet" and "Not saved" or "Saved") end
            metaWidth = math.min(math.max(42, metaLabel:GetStringWidth() + 4), math.max(1, pageWidth - 20 - savedWidth))
            left = PlaceRaidHeaderLabel(page, page.classicMeta, metaWidth, top, left)
            left = PlaceRaidHeaderButton(page, page.classicSaved, savedWidth, top, left, scale)
            left = 6
            local actionsWidth = 108 + 90 + (showIssues and 96 or 0)
            local gaps = showIssues and 16 or 8
            if iconOnly then
                if showIssues then
                    page.classicIssues:SetText(string.gsub(page.classicIssues.mosRaidIssuesText, "[^%d].*$", ""))
                    left = PlaceRaidHeaderButton(page, page.classicIssues, 40, top - actionOffset, left, 1)
                end
                left = PlaceRaidHeaderButton(page, page.exportButton, 26, top - actionOffset, left, 1)
                left = PlaceRaidHeaderButton(page, page.quitButton, 26, top - actionOffset, left, 1)
                page.exportButton.label:Hide(); page.quitButton.label:Hide()
            else
                scale = math.min(1, math.max(1, available - gaps) / actionsWidth)
                if showIssues then left = PlaceRaidHeaderButton(page, page.classicIssues, math.floor(96 * scale), top - actionOffset, left, scale) end
                left = PlaceRaidHeaderButton(page, page.exportButton, math.floor(108 * scale), top - actionOffset, left, scale)
                left = PlaceRaidHeaderButton(page, page.quitButton, math.floor(90 * scale), top - actionOffset, left, scale)
            end
        else
            page.classicRaidName:Show()
            left = PlaceRaidHeaderLabel(page, page.classicMeta, metaWidth, top, left)
            left = PlaceRaidHeaderLabel(page, page.classicRaidName, nameWidth, top, left)
            left = PlaceRaidHeaderButton(page, page.classicSaved, 108, top, left, scale)
            if showIssues then left = PlaceRaidHeaderButton(page, page.classicIssues, 96, top, left, scale) end
            left = PlaceRaidHeaderButton(page, page.exportButton, 108, top, left, scale); left = PlaceRaidHeaderButton(page, page.quitButton, 90, top, left, scale)
        end
        page.classicActionScale = scale
        UI.SetButtonLabelInsets(page.classicSaved, 8, 4)
        if page.raidInfoButton then
            page.raidInfoButton:ClearAllPoints(); page.raidInfoButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, top - actionOffset)
            page.raidInfoButton:Show()
        end
        page.classicToolbar:ClearAllPoints(); page.classicToolbar:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -48 - sectionOffset - actionOffset); page.classicToolbar:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -48 - sectionOffset - actionOffset); page.classicToolbar:SetHeight(42 + toolbarOffset)
        page.classicListButton:ClearAllPoints(); page.classicListButton:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -56 - sectionOffset - actionOffset)
        page.classicGroupButton:ClearAllPoints(); page.classicGroupButton:SetPoint("LEFT", page.classicListButton, "RIGHT", 8, 0)
        page.classicTwoButton:ClearAllPoints(); page.classicTwoButton:SetPoint("LEFT", page.classicGroupButton, "RIGHT", 8, 0)
        page.classicFourButton:ClearAllPoints(); page.classicFourButton:SetPoint("LEFT", page.classicTwoButton, "RIGHT", 8, 0)
        local selectorScale = math.min(1, math.max(1, PageSpan(page) - 32) / 300)
        if page.raidView == "groups" then
            Raider.UI.Components.SizeClassicButton(page.classicListButton, 76 * selectorScale, 26, selectorScale)
            Raider.UI.Components.SizeClassicButton(page.classicGroupButton, 76 * selectorScale, 26, selectorScale)
            Raider.UI.Components.SizeClassicButton(page.classicTwoButton, 62 * selectorScale, 26, selectorScale)
            Raider.UI.Components.SizeClassicButton(page.classicFourButton, 62 * selectorScale, 26, selectorScale)
        else
            Raider.UI.Components.SizeClassicButton(page.classicListButton, 76, 26, 1)
            Raider.UI.Components.SizeClassicButton(page.classicGroupButton, 76, 26, 1)
        end
        local pageWidth = PageSpan(page)
        local groupToolsScale = page.raidView == "groups" and toolbarOffset == 0 and math.max(0.75, math.min(1, (pageWidth - 394) / 296)) or 1
        page.lootMasterToolsButton:ClearAllPoints(); Raider.UI.Components.SizeClassicButton(page.lootMasterToolsButton, math.floor(138 * groupToolsScale), 26, groupToolsScale); page.lootMasterToolsButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -56 - sectionOffset - actionOffset - toolbarOffset)
        page.raidLeaderToolsButton:ClearAllPoints(); Raider.UI.Components.SizeClassicButton(page.raidLeaderToolsButton, math.floor(134 * groupToolsScale), 26, groupToolsScale); page.raidLeaderToolsButton:SetPoint("RIGHT", page.lootMasterToolsButton, "LEFT", -8, 0)
        if toolbarOffset > 0 then
            local toolScale = math.min(1, math.max(1, pageWidth - 16) / 296)
            Raider.UI.Components.SizeClassicButton(page.raidLeaderToolsButton, math.floor(134 * toolScale), 26, toolScale)
            Raider.UI.Components.SizeClassicButton(page.lootMasterToolsButton, math.floor(138 * toolScale), 26, toolScale)
            page.raidLeaderToolsButton:ClearAllPoints(); page.raidLeaderToolsButton:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -56 - sectionOffset - actionOffset - toolbarOffset)
            page.lootMasterToolsButton:ClearAllPoints(); page.lootMasterToolsButton:SetPoint("LEFT", page.raidLeaderToolsButton, "RIGHT", 8, 0)
        end
        page.classicSummary:Hide()
        local toolbarLevel = page.classicToolbar:GetFrameLevel() + 2
        page.classicListButton:SetFrameLevel(toolbarLevel); page.classicGroupButton:SetFrameLevel(toolbarLevel)
        page.classicTwoButton:SetFrameLevel(toolbarLevel); page.classicFourButton:SetFrameLevel(toolbarLevel)
        page.raidLeaderToolsButton:SetFrameLevel(toolbarLevel); page.lootMasterToolsButton:SetFrameLevel(toolbarLevel)
        return
    end
    local actionCount = table.getn(page.actions)
    local baseWidth = math.max(1, (actionCount - 1) * 6)
    local actionIndex
    for actionIndex = 1, actionCount do baseWidth = baseWidth + page.actions[actionIndex].width end
    local widthScale = math.min(1, math.max(1, page:GetWidth() - 12) / baseWidth)
    local actionX = 6
    for actionIndex = 1, actionCount do
        local action = page.actions[actionIndex]
        local width = math.floor(action.width * widthScale)
        action.button:ClearAllPoints(); action.button:SetScale(1); action.button:SetWidth(width); action.button:SetHeight(22)
        action.button:SetPoint("TOPLEFT", page, "TOPLEFT", actionX, -42)
        actionX = actionX + width + 6
    end
end

function RaidManagement.CreateFilterController(options)
    local controller = {
        page = options.page,
        classButton = options.classButton,
        rankButton = options.rankButton,
        classPanel = options.classPanel,
        rankPanel = options.rankPanel,
        dismiss = options.dismiss,
        searchBox = options.searchBox,
        selectedClasses = options.selectedClasses,
        selectedRanks = options.selectedRanks,
        getFilterValues = options.getFilterValues,
        refresh = options.refresh,
        onReset = options.onReset,
        initialized = false,
    }

    function controller:Hide()
        self.classPanel:Hide(); self.rankPanel:Hide(); self.dismiss:Hide()
    end

    function controller:Build(members)
        local classes, ranks = self.getFilterValues(members)
        local index
        if not self.initialized then
            for index = 1, table.getn(classes) do self.selectedClasses[classes[index]] = true end
            for index = 1, table.getn(ranks) do self.selectedRanks[ranks[index]] = true end
            self.initialized = true
        end
        for index = 1, table.getn(classes) do
            if self.selectedClasses[classes[index]] == nil then self.selectedClasses[classes[index]] = true end
        end
        for index = 1, table.getn(ranks) do
            if self.selectedRanks[ranks[index]] == nil then self.selectedRanks[ranks[index]] = true end
        end
        Raider.UI.Components.FilterPanel.Refresh(self.classPanel, classes, self.selectedClasses, self.refresh, true)
        Raider.UI.Components.FilterPanel.Refresh(self.rankPanel, ranks, self.selectedRanks, self.refresh, true)
    end

    function controller:Reset()
        local name
        for name in pairs(self.selectedClasses) do self.selectedClasses[name] = true end
        for name in pairs(self.selectedRanks) do self.selectedRanks[name] = true end
        self.page.filterData = nil
        self.searchBox:SetText("")
        self:Hide()
        self.onReset()
    end

    controller.dismiss:SetScript("OnClick", function() controller:Hide() end)
    controller.classButton:SetScript("OnClick", function()
        local show = not controller.classPanel:IsVisible()
        controller:Hide()
        if show then controller.classPanel:Show() end
    end)
    controller.rankButton:SetScript("OnClick", function()
        local show = not controller.rankPanel:IsVisible()
        controller:Hide()
        if show then controller.rankPanel:Show() end
    end)
    options.resetButton:SetScript("OnClick", function() controller:Reset() end)
    options.page.filterController = controller
    return controller
end

function RaidManagement.CreateGroupSelector(page, getGroupCounts, moveMember, refresh)
    local dismiss = Raider.UI.Components.CreateControl(nil, page)
    dismiss:SetAllPoints(page); dismiss:SetFrameLevel(page:GetFrameLevel() + 38); dismiss:Hide()
    page.groupSelectDismiss = dismiss

    local menu = Raider.UI.Components.CreateContainer(nil, page)
    menu:SetWidth(76); menu:SetHeight(164); menu:SetFrameLevel(page:GetFrameLevel() + 40)
    menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    menu:SetBackdropColor(0.025, 0.025, 0.025, 0.98); menu:Hide()
    page.groupSelectMenu = menu
    page.groupSelectButtons = {}

    dismiss:SetScript("OnClick", function() menu:Hide(); dismiss:Hide() end)
    local index
    for index = 1, 8 do
        local button = Raider.UI.Components.CreateButton(menu, nil, "Group " .. index, 66, 18)
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, -5 - ((index - 1) * 19)); button.targetGroup = index
        button:SetScript("OnClick", function()
            if this.groupFull or not page.groupSelectRow or not page.groupSelectRow.displayedMember then return end
            if moveMember(page.groupSelectRow.displayedMember, this.targetGroup) then
                menu:Hide(); dismiss:Hide(); refresh()
            end
        end)
        page.groupSelectButtons[index] = button
    end

    page.openGroupSelector = function(row) RaidManagement.OpenGroupSelector(page, row, getGroupCounts) end
    return menu
end

function RaidManagement.OpenGroupSelector(page, row, getGroupCounts)
    if not row or not row.displayedMember then return end
    local counts = getGroupCounts()
    local index
    for index = 1, 8 do
        local button = page.groupSelectButtons[index]
        button.groupFull = counts[index] >= 5 and tonumber(row.displayedMember.subgroup) ~= index
        if button.groupFull then button.label:SetTextColor(0.45, 0.45, 0.45) else button.label:SetTextColor(1, 0.82, 0) end
    end
    page.groupSelectRow = row
    page.groupSelectMenu:ClearAllPoints(); page.groupSelectMenu:SetPoint("TOPLEFT", row.groupHit, "BOTTOMLEFT", 0, -2)
    page.groupSelectDismiss:Show(); page.groupSelectMenu:Show()
end

local function OnRosterDebounceUpdate()
    local lifecycle = this.raidLifecycle
    this.remaining = this.remaining - arg1
    if this.remaining > 0 then return end
    this:Hide()
    lifecycle:FlushRosterUpdate()
end

function RaidManagement.HandleWorldContext(options, context, confirmed)
    if options.setTransitionPending then options.setTransitionPending(nil) end
    local attendance = options.getAttendance()
    local zone = options.getZone() or ""
    local inInstance, instanceType = options.getInstanceState()
    local inRaidInstance = inInstance and instanceType == "raid"
    local hasSession = options.hasSession(attendance) and options.isSessionDraft()
    if not options.isTestRaid() and inRaidInstance and not hasSession then
        local reminderKey = zone ~= "" and zone or "raid-instance"
        if options.getReminderContext() ~= reminderKey and options.getReminderShownContext() ~= reminderKey then
            options.setReminderShownContext(reminderKey)
            options.showRaidStartReminder(reminderKey)
        end
    else
        if not inRaidInstance then
            options.setReminderContext(nil)
            options.setReminderShownContext(nil)
        end
        options.hideRaidStartReminder()
    end
    if options.isTestRaid() or not hasSession then
        context.active = false
        context.raidZone = nil
        context.promptedContext = nil
        options.setContinuedContext(nil)
        options.hideSessionTransitionPrompt()
        return
    end
    local inRaid = options.isInRaid()
    if not context.active or context.sessionId ~= attendance.snapshotId or context.startedAt ~= attendance.sessionStartedAt then
        context.active = true
        context.sessionId = attendance.snapshotId
        context.startedAt = attendance.sessionStartedAt
        context.raidZone = nil
        context.promptedContext = nil
        options.setContinuedContext(nil)
        options.hideSessionTransitionPrompt()
    end
    -- A saved/session display name is not an instance identity. Observe the
    -- actual client context instead, without persisting derived zone state.
    local contextKey = options.getSessionTransitionContext and options.getSessionTransitionContext()
    if not contextKey and inRaid and (not instanceType or instanceType == "") then return end
    if contextKey then
        -- A saved roster can belong to another physical group in the same zone.
        -- Preserve it until the user makes the existing session choice.
    elseif not inRaid then
        contextKey = "outside-raid-context"
    elseif context.raidZone and not inRaidInstance then
        contextKey = "outside-raid-context"
    elseif context.raidZone and zone ~= "" and context.raidZone ~= zone then
        contextKey = "raid-instance|" .. zone
    end
    if not contextKey then
        if inRaidInstance and zone ~= "" then context.raidZone = zone end
        context.promptedContext = nil
        options.setContinuedContext(nil)
        options.hideSessionTransitionPrompt()
        return
    end
    if options.setTransitionPending then options.setTransitionPending(contextKey) end
    if options.getContinuedContext() == contextKey then
        if options.setTransitionPending then options.setTransitionPending(nil) end
        return
    end
    if context.promptedContext == contextKey then return end
    if confirmed ~= contextKey then return contextKey end
    context.promptedContext = contextKey
    options.showSessionTransitionPrompt(contextKey)
end

local function OnWorldContextConfirmationUpdate()
    this.remaining = this.remaining - arg1
    if this.remaining > 0 then return end
    local controller = this.contextController
    local contextKey = this.pendingContext
    controller:CancelConfirmation()
    controller.Update(contextKey)
end

function RaidManagement.CreateWorldContextController(options)
    local controller = { options = options, context = {} }
    function controller:CancelConfirmation()
        if not self.timer then return end
        self.timer:SetScript("OnUpdate", nil)
        self.timer:Hide()
        self.timer.pendingContext = nil
    end
    -- Event driven; a short one-shot confirmation exists only for a potential
    -- departure. Roster bursts do not restart it or allocate more frames.
    function controller.Update(confirmedContext)
        local pending = RaidManagement.HandleWorldContext(options, controller.context, confirmedContext)
        if not pending then controller:CancelConfirmation(); return end
        local timer = controller.timer
        if not timer then
            timer = Raider.UI.Components.CreateContainer(nil, UIParent)
            timer.contextController = controller
            controller.timer = timer
        end
        if timer.pendingContext == pending then return end
        timer.pendingContext = pending
        timer.remaining = 2
        timer:SetScript("OnUpdate", OnWorldContextConfirmationUpdate)
        timer:Show()
    end
    return controller
end

function RaidManagement.CreateLifecycle(options)
    local lifecycle = {}
    local rosterDebounce = Raider.UI.Components.CreateContainer(nil, UIParent)
    rosterDebounce.raidLifecycle = lifecycle
    rosterDebounce.remaining = 0
    rosterDebounce:SetScript("OnUpdate", OnRosterDebounceUpdate)
    rosterDebounce:Hide()
    lifecycle.rosterDebounce = rosterDebounce

    function lifecycle:CancelRosterUpdate()
        self.rosterDebounce.remaining = 0
        self.rosterDebounce:Hide()
    end

    function lifecycle:FlushRosterUpdate()
        local inRaid = options.isInRaid()
        local tracking = options.getTrackingEnabled() and inRaid and options.isPresentationActive()
        options.setLiveTracking(tracking and true or false)
        if not tracking then return end
        if not options.isPresentationActive() then return end
        if options.getScanReady() and not options.isHistoricalLoaded() then
            Raider.Diagnostics.Count("raidRosterBatches")
            options.saveRaidRoster()
            options.setScanReady(true)
        end
        if options.isPresentationActive() then options.refresh() end
    end

    function lifecycle:SyncTrackingSetting(skipRefresh)
        local tracking = options.isPresentationActive() and options.isInRaid() and options.getScanReady() and options.getTrackingEnabled()
        options.setLiveTracking(tracking and true or false)
        options.page.refreshControls.refreshButton:SetInactive(tracking)
        if tracking then options.saveRaidRoster() end
        if not skipRefresh and options.isPresentationActive() then options.refresh() end
    end

    function lifecycle:Hide()
        options.page.groupMovePending = nil
        local detached = options.isDetachedActive and options.isDetachedActive()
        if not detached then options.setLiveTracking(false); self:CancelRosterUpdate() end
        options.page.refreshControls.refreshButton:SetInactive(false)
        if options.page.filterController then options.page.filterController:Hide() end
        if options.page.memberMenu then options.page.memberMenu:Hide() end
        if options.page.memberMenuDismiss then options.page.memberMenuDismiss:Hide() end
        if not detached and options.page.softReserveImportDialog then options.page.softReserveImportDialog:Hide() end
        if options.page.softReserveFixDialog and options.page.softReserveFixDialog.Close then options.page.softReserveFixDialog:Close() end
        if not detached and options.page.lootRulesDialog and options.page.lootRulesDialog.Close then options.page.lootRulesDialog:Close() end
        if options.page.contestedItemsDialog then options.page.contestedItemsDialog:Hide() end
        options.page:Hide()
    end

    function lifecycle:Show()
        options.page:Show()
        self:OnWorldContextChanged()
        self:SyncTrackingSetting()
    end

    function lifecycle:Refresh()
        options.refresh()
    end

    function lifecycle:OnResize()
        options.refresh()
    end

    function lifecycle:OnRosterUpdate()
        if options.page.groupMovePending then
            options.page.groupMovePending = nil
            if not options.getTrackingEnabled() and options.isPresentationActive() then options.refresh() end
        end
        local inRaid = options.isInRaid()
        local tracking = options.getTrackingEnabled() and inRaid and options.isPresentationActive()
        options.setLiveTracking(tracking and true or false)
        if not inRaid then
            self:CancelRosterUpdate()
            options.setLiveTracking(false)
            if options.isPresentationActive() then options.refresh() end
            return
        end
        if not tracking or not options.isPresentationActive() then
            self:CancelRosterUpdate()
            return
        end
        -- RAID_ROSTER_UPDATE often arrives in bursts. Restarting this short
        -- timer coalesces the burst into one roster scan and one UI refresh.
        self.rosterDebounce.remaining = 0.25
        self.rosterDebounce:Show()
    end

    function lifecycle:OnWorldContextChanged()
        if options.onWorldContextChanged then options.onWorldContextChanged() end
    end

    options.page.lifecycle = lifecycle
    return lifecycle
end

function RaidManagement.CreateLootMasterController(options)
    local UI = Raider.UI.Components
    local window = UI.CreateContainer("BootyRaiderLootMasterMode", UIParent)
    window:SetFrameStrata("FULLSCREEN_DIALOG"); window:SetFrameLevel(100)
    window:SetWidth(400); window:SetHeight(210); window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    window:SetMovable(true); window:SetResizable(true); window:EnableMouse(true); window:RegisterForDrag("LeftButton")
    if window.SetClampedToScreen then window:SetClampedToScreen(true) end
    UI.Window.ApplyProjectSurface(window)
    UI.RegisterSkinCallback(function() UI.Window.ApplyProjectSurface(window) end)
    window:Hide()
    -- This controller owns a separate window; it never changes dashboard chrome or geometry.
    options.dashboard = window
    local controller = { dashboard = window, getSettings = options.getSettings }
    options.page.lmDashboard = options.dashboard
    options.page.lmConfigPanel:SetParent(UIParent)
    options.page.lmConfigPanel:ClearAllPoints()
    options.page.lmConfigPanel:SetPoint("TOPLEFT", options.dashboard, "TOPRIGHT", 0, 0)
    options.page.lmConfigPanel:SetFrameLevel(options.dashboard:GetFrameLevel() + 30)
    options.page.lmConfigPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    options.page.lmConfigPanel:SetFrameLevel(300)
    options.page.lmAutoLoot:SetFrameLevel(301)
    if options.page.lmConfigClose then options.page.lmConfigClose:SetFrameStrata("FULLSCREEN_DIALOG"); options.page.lmConfigClose:SetFrameLevel(305) end
    options.page.reyCoinPanel:SetParent(UIParent)
    options.page.reyCoinPanel:ClearAllPoints()
    options.page.reyCoinPanel:SetPoint("TOPLEFT", options.page.lmConfigPanel, "TOPLEFT", 0, 0)
    options.page.reyCoinPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    options.page.reyCoinPanel:SetFrameLevel(300)
    options.page.reyCoinScroll:SetFrameStrata("FULLSCREEN_DIALOG"); options.page.reyCoinScroll:SetFrameLevel(301)
    options.page.reyCoinCanvas:SetFrameStrata("FULLSCREEN_DIALOG"); options.page.reyCoinCanvas:SetFrameLevel(302)
    local reyCoinRowIndex
    for reyCoinRowIndex = 1, table.getn(options.page.reyCoinRows) do
        local row = options.page.reyCoinRows[reyCoinRowIndex]
        row:SetFrameStrata("FULLSCREEN_DIALOG"); row:SetFrameLevel(303)
        row.remove:SetFrameStrata("FULLSCREEN_DIALOG"); row.remove:SetFrameLevel(304)
    end
    if options.page.reyCoinItem then options.page.reyCoinItem:SetFrameStrata("FULLSCREEN_DIALOG"); options.page.reyCoinItem:SetFrameLevel(303) end
    options.page.reyCoinInput:SetFrameStrata("FULLSCREEN_DIALOG"); options.page.reyCoinInput:SetFrameLevel(303)
    options.page.reyCoinAdd:SetFrameStrata("FULLSCREEN_DIALOG"); options.page.reyCoinAdd:SetFrameLevel(303)
    controller.ReanchorPanels = function()
        options.page.lmConfigPanel:ClearAllPoints()
        options.page.lmConfigPanel:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, 0)
        if not options.page.reyCoinSolo then
            options.page.reyCoinPanel:ClearAllPoints()
            options.page.reyCoinPanel:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, 0)
        end
    end
    local function SetupSidePanelResize(panel, widthKey, heightKey, minimumWidth, minimumHeight)
        minimumWidth = minimumWidth or 150; minimumHeight = minimumHeight or 90
        local settings = options.getSettings()
        panel:SetResizable(true)
        panel:SetMinResize(minimumWidth, minimumHeight); panel:SetMaxResize(520, 760)
        panel:SetWidth(math.max(minimumWidth, math.min(520, tonumber(settings[widthKey]) or minimumWidth)))
        panel:SetHeight(math.max(minimumHeight, math.min(760, tonumber(settings[heightKey]) or 210)))
        local grip = Raider.UI.Components.CreateResizeGrip(panel)
        panel.resizeGrip = grip
        grip:SetScript("OnMouseDown", function() panel:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", function()
            panel:StopMovingOrSizing()
            local saved = options.getSettings()
            saved[widthKey] = panel:GetWidth(); saved[heightKey] = panel:GetHeight()
            controller.ReanchorPanels()
        end)
        grip:SetScript("OnHide", function() panel:StopMovingOrSizing(); controller.ReanchorPanels() end)
    end
    SetupSidePanelResize(options.page.lmConfigPanel, "lmConfigWidth", "lmConfigHeight", 260, 360)
    SetupSidePanelResize(options.page.reyCoinPanel, "reyCoinPanelWidth", "reyCoinPanelHeight", 240, 120)
    local configGrip = options.page.lmConfigPanel.resizeGrip
    configGrip:ClearAllPoints(); configGrip:SetPoint("BOTTOMRIGHT", options.page.lmConfigPanel, "BOTTOMRIGHT", 0, 0)
    configGrip:SetWidth(12); configGrip:SetHeight(12); configGrip.texture:Hide()
    UI.RegisterSkinCallback(function() configGrip.texture:Hide() end)
    local reyGrip = options.page.reyCoinPanel.resizeGrip
    reyGrip:ClearAllPoints(); reyGrip:SetPoint("BOTTOMRIGHT", options.page.reyCoinPanel, "BOTTOMRIGHT", 0, 0)
    reyGrip:SetWidth(12); reyGrip:SetHeight(12)
    options.page.reyCoinPanel.resizeGrip.texture:Hide()
    UI.RegisterSkinCallback(function() options.page.reyCoinPanel.resizeGrip.texture:Hide() end)
    local reyPanel = options.page.reyCoinPanel
    reyPanel:SetMovable(true); reyPanel:RegisterForDrag("LeftButton")
    reyPanel:SetScript("OnDragStart", function() if options.page.reyCoinSolo then reyPanel:StartMoving() end end)
    reyPanel:SetScript("OnDragStop", function() reyPanel:StopMovingOrSizing(); controller.ReanchorPanels() end)
    local reyClose = UI.CreateWindowButton(reyPanel, nil, "close")
    reyClose:SetPoint("TOPRIGHT", reyPanel, "TOPRIGHT", -4, -4)
    reyClose:SetFrameStrata("FULLSCREEN_DIALOG"); reyClose:SetFrameLevel(305)
    reyClose:SetScript("OnClick", function() reyPanel:Hide() end)
    controller.OpenSoloReyCoin = function()
        reyPanel:Hide()
        options.page.reyCoinSolo = true
        reyPanel:ClearAllPoints(); reyPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        if options.page.RefreshReyCoinList then options.page.RefreshReyCoinList() end
        reyPanel:Show(); reyPanel:Raise()
    end
    local alphaWatcher = Raider.UI.Components.CreateContainer(nil, options.dashboard)
    alphaWatcher.elapsed = 0; alphaWatcher.lootMasterController = controller
    alphaWatcher:Hide()
    controller.alphaWatcher = alphaWatcher

    controller.closePanels = function()
        options.page.lmConfigOpen = false
        options.page.lmConfigPanel:Hide(); if not options.page.reyCoinSolo then options.page.reyCoinPanel:Hide() end
        options.page.lmConfigToggle:Hide(); options.page.reyCoinToggle:Hide()
    end

    local compact, rows, members = nil, nil, {}
    local selectedName, sortKey, ascending = nil, nil, true
    local emptyFilters = {}
    local menus = {}
    local close, minimize, config, reycoin, sr, rules, grip, title, newRoll

    local function SaveGeometry()
        local settings = options.getSettings()
        if not window.minimized then settings.lootMasterWidth = window:GetWidth(); settings.lootMasterHeight = window:GetHeight() end
        local left, bottom = window:GetLeft(), window:GetBottom()
        if left and bottom then settings.lootMasterLeft = left; settings.lootMasterBottom = bottom end
    end

    local function HideMenus()
        for _, panel in pairs(menus) do panel:Hide() end
    end

    local function LayoutToolbar()
        local available = math.max(1, window:GetWidth() - 160)
        title.mosFitFontSize = 12
        title:ClearAllPoints(); title:SetPoint("TOPLEFT", window, "TOPLEFT", 6, window.minimized and -4 or -6)
        UI.FitButtonLabel(title, available); title:SetHeight(window.minimized and 22 or 18)
    end

    controller.Refresh = function()
        if not window:IsVisible() or not compact then return end
        LayoutToolbar()
        UI.SetButtonEnabled(newRoll, Raider.Modules.MasterLootWindow and Raider.Modules.MasterLootWindow.CanStartManualRoll and Raider.Modules.MasterLootWindow.CanStartManualRoll() or false)
        if window.minimized then return end
        local data = options.page.listRenderer.getData()
        local source = data and data.members or emptyFilters
        for index = table.getn(members), 1, -1 do table.remove(members, index) end
        local found = false
        for index = 1, table.getn(source) do
            table.insert(members, source[index])
            if source[index].name == selectedName then found = true end
        end
        if not found then selectedName = nil end
        table.sort(members, compact.listRenderer.sortMembers)
        RaidManagement.HideListTable(compact, rows)
        RaidManagement.RefreshListView(compact, rows, members, selectedName, sortKey, true, options.getSettings())
        compact.listHeaderUI.level:Hide(); compact.listHeaderUI.levelButton:Hide()
        compact.listHeaderUI.online:Hide(); compact.listHeaderUI.onlineButton:Hide()
    end

    local function BuildMenu(button, captions, sources)
        local width = 1
        local panel = UI.CreateDropdownPanel(window, button, 180, 48, 30)
        UI.Window.ApplyProjectSurface(panel)
        UI.RegisterSkinCallback(function() UI.Window.ApplyProjectSurface(panel) end)
        panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
        for index = 1, table.getn(captions) do
            local choice = UI.CreateButton(panel, nil, captions[index], 166, 18)
            UI.StyleDropdownChoice(choice)
            choice:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4 - (index - 1) * 22)
            choice.toolSource = sources[index]
            choice:SetScript("OnClick", InvokeToolChoice)
            width = math.max(width, choice.label:GetStringWidth() + 20)
            panel.options[index] = choice
        end
        panel:SetWidth(width + 8); panel:SetHeight(8 + table.getn(captions) * 18 + (table.getn(captions) - 1) * 4)
        for index = 1, table.getn(panel.options) do panel.options[index]:SetWidth(width) end
        menus[button] = panel; button.panel = panel
        button:SetScript("OnClick", function()
            local shown = panel:IsVisible()
            HideMenus()
            if not shown then
                for index = 1, table.getn(panel.options) do
                    local source = panel.options[index].toolSource
                    local enabled = not source.IsEnabled or source:IsEnabled()
                    UI.SetButtonEnabled(panel.options[index], enabled ~= false and enabled ~= 0)
                end
                panel:Show(); UI.RefreshDropdownLayers(panel, button)
            end
        end)
    end

    local function Build()
        if compact then return end
        compact = UI.CreateContainer(nil, window); compact.detachedLootMaster = true
        compact.mosLootScrollPrefix = "BootyRaiderDetachedLootScroll"
        compact:SetPoint("TOPLEFT", window, "TOPLEFT", 4, -4); compact:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -4, 24)
        controller.page = compact
        local source = options.page.rowController
        local rowController = {
            refresh = controller.Refresh, onAction = source.onAction, onContext = source.onContext,
            onGroup = source.onGroup, onRemoveSoftReserve = source.onRemoveSoftReserve,
            isSelected = function(member) return member.name == selectedName end,
            onSelect = function(row)
                if selectedName == row.displayedMember.name then selectedName = nil else selectedName = row.displayedMember.name end
                controller.Refresh()
            end,
        }
        RaidManagement.CreateListHeaders(compact, function(key, defaultAscending)
            if sortKey ~= key then sortKey = key; ascending = defaultAscending
            elseif ascending then ascending = false else sortKey = nil; ascending = true end
            controller.Refresh()
        end)
        rows = RaidManagement.CreateListViewport(compact, 35, rowController, "BootyRaiderLootMasterListScroll")
        RaidManagement.AttachListScroll(compact, controller.Refresh)
        RaidManagement.SetListRenderer(compact, {
            getLootMasterInfo = options.page.listRenderer.getLootMasterInfo,
            updateScrollFrame = options.page.listRenderer.updateScrollFrame,
            shorten = options.page.listRenderer.shorten,
            sortMembers = function(a, b) return RaidManagement.CompareMembers(a, b, sortKey, ascending) end,
        })
        close = UI.CreateWindowButton(window, nil, "close"); close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6)
        close:SetScript("OnClick", function() controller.Close() end)
        minimize = UI.CreateWindowButton(window, nil, "minimize"); minimize:SetPoint("RIGHT", close, "LEFT", -2, 0)
        minimize:SetScript("OnClick", function() controller.toggleMinimize() end)
        config = UI.CreateSettingsButton(window); config:SetPoint("RIGHT", minimize, "LEFT", -2, 0)
        UI.AttachTooltip(config, "LM Config", "Open Loot Master configuration.")
        config:SetScript("OnClick", function()
            controller.ReanchorPanels()
            options.page.reyCoinPanel:Hide()
            options.page.lmConfigOpen = not options.page.lmConfigOpen
            if options.page.lmConfigOpen then options.page.lmConfigPanel:Show() else options.page.lmConfigPanel:Hide() end
        end)
        reycoin = UI.CreateGoldToolbarButton(window, "list")
        UI.AttachTooltip(reycoin, "Reycoin List", "View used Reycoins and pending item trades.")
        reycoin:SetPoint("RIGHT", config, "LEFT", -2, 0)
        reycoin.toolSource = options.page.reyCoinToggle
        reycoin:SetScript("OnClick", function()
            if options.page.reyCoinSolo then options.page.reyCoinPanel:Hide(); options.page.reyCoinSolo = false end
            controller.ReanchorPanels()
            local handler = options.page.reyCoinToggle:GetScript("OnClick")
            if handler then handler() end
        end)
        sr = UI.CreateGoldToolbarButton(window, "import")
        rules = UI.CreateGoldToolbarButton(window, "rules")
        rules:SetPoint("RIGHT", reycoin, "LEFT", -2, 0); sr:SetPoint("RIGHT", rules, "LEFT", -2, 0)
        newRoll=UI.CreateGoldToolbarButton(window,"dice")
        newRoll:SetPoint("RIGHT",sr,"LEFT",-2,0)
        UI.AttachTooltip(newRoll,"New Roll","Link an item and choose who may roll and which roll types are allowed.")
        newRoll:SetScript("OnClick",function() if Raider.Modules.MasterLootWindow then Raider.Modules.MasterLootWindow.OpenNewRollDialog() end end)
        UI.AttachTooltip(sr, "SR", "Import SR or share the SR link.")
        UI.AttachTooltip(rules, "Loot Rules", "Set or share loot rules.")
        title = UI.CreateHeading(window, "Loot Master Mode", 3, "gold", "lootmaster")
        title:SetText("Loot Master Mode"); title:SetPoint("TOPLEFT", window, "TOPLEFT", 6, -6)
        title:SetJustifyH("LEFT"); title:SetJustifyV("MIDDLE"); title:SetHeight(18)
        controller.title = title; controller.configButton = config; controller.reycoinButton = reycoin
        local controls = options.page.refreshControls
        BuildMenu(sr, {"Import SR", "Share SR Link"}, {controls.import, controls.shareSr})
        BuildMenu(rules, {"Set Loot Rules", "Share Loot Rules"}, {controls.lootRules, controls.sendLootRules})
        controller.srButton = sr; controller.rulesButton = rules
        controller.newRollButton = newRoll
        grip = UI.CreateResizeGrip(window)
        grip:ClearAllPoints(); grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -6, 6)
        controller.resizeGrip = grip
        grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp", function() window:StopMovingOrSizing(); SaveGeometry(); controller.Refresh() end)
        grip:SetScript("OnHide", function() window:StopMovingOrSizing() end)
        controller.closeButton = close; controller.minimizeButton = minimize
    end

    controller.Close = function()
        SaveGeometry(); HideMenus(); controller.closePanels()
        alphaWatcher:Hide(); alphaWatcher:SetScript("OnUpdate", nil)
        window:Hide()
        if options.page.lifecycle then options.page.lifecycle:SyncTrackingSetting(); options.page.lifecycle:CancelRosterUpdate() end
    end
    controller.IsVisible = function() return window:IsVisible() end
    controller.resetOnLoad = function()
        Raider.lootMasterMode = false; Raider.lootMasterMinimized = false
    end
    controller.toggle = function()
        if options.page.reyCoinSolo then options.page.reyCoinPanel:Hide(); options.page.reyCoinSolo = false end
        controller.ReanchorPanels()
        Build()
        if window:IsVisible() then
            if window.minimized then controller.toggleMinimize() end
            window:Raise(); return
        end
        local settings = options.getSettings()
        window.minimized = false
        window:SetMinResize(300, 140); window:SetMaxResize(900, 760)
        window:SetWidth(math.max(300, math.min(900, tonumber(settings.lootMasterWidth) or 400)))
        window:SetHeight(math.max(140, math.min(760, tonumber(settings.lootMasterHeight) or 210)))
        window:ClearAllPoints()
        if tonumber(settings.lootMasterLeft) and tonumber(settings.lootMasterBottom) then
            window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", settings.lootMasterLeft, settings.lootMasterBottom)
        else window:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
        compact:Show(); grip:Show(); UI.SetWindowButtonAction(minimize, "minimize")
        window:Show(); alphaWatcher.elapsed = 0; alphaWatcher:SetScript("OnUpdate", OnLootMasterAlphaUpdate); alphaWatcher:Show()
        if options.page.lifecycle then options.page.lifecycle:SyncTrackingSetting() end
        controller.Refresh()
    end
    controller.toggleMinimize = function()
        if not window:IsVisible() then return end
        HideMenus(); controller.closePanels()
        if window.minimized then
            window.minimized = false; window:SetMinResize(300, 140)
            window:SetHeight(window.expandedHeight or 210); compact:Show(); grip:Show()
            UI.SetWindowButtonAction(minimize, "minimize")
        else
            SaveGeometry(); window.expandedHeight = window:GetHeight(); window.minimized = true
            window:SetMinResize(300, UI.Window.MinimizedHeight); compact:Hide(); grip:Hide(); window:SetHeight(UI.Window.MinimizedHeight)
            UI.SetWindowButtonAction(minimize, "maximize")
        end
        controller.Refresh()
    end
    window:SetScript("OnDragStart", function() window:StartMoving() end)
    window:SetScript("OnDragStop", function() window:StopMovingOrSizing(); controller.ReanchorPanels(); SaveGeometry() end)
    window:SetScript("OnSizeChanged", function() controller.Refresh() end)
    window:SetScript("OnHide", function()
        window:StopMovingOrSizing(); HideMenus(); controller.closePanels()
        alphaWatcher:Hide(); alphaWatcher:SetScript("OnUpdate", nil)
    end)
    UI.RegisterSkinCallback(function() controller.Refresh() end)
    options.page.lootMasterController = controller
    return controller
end

function RaidManagement.AttachActionHandlers(options)
    options.page.getSoftReserveRules = options.getRules
    local controls = options.page.refreshControls
    local contestedItemsDialog = RaidManagement.CreateHighlyContestedItemsDialog(options)
    options.openHighlyContestedItems = function() contestedItemsDialog:OpenItems() end
    local importDialog = RaidManagement.CreateSoftReserveImportDialog(options)
    local lootRulesDialog = RaidManagement.CreateLootRulesDialog(options)
    local selectedRaidName = "Molten Core"
    local newRaidDialog = Raider.UI.Components.CreateTextPrompt("BootyRaiderNewRaidDialog", "Start New Raid", "Unique raid ID", "Start", function(value)
        value = string.gsub(tostring(value or ""), "^%s+", ""); value = string.gsub(value, "%s+$", "")
        if value == "" then return false, "Raid ID is required." end
        if options.raidIdExists(value) then return false, "This raid ID already exists." end
        if not options.isInRaid() then return false, "Join a raid before starting a session." end
        if options.startNewRaid(value, selectedRaidName) == false then return false, "Finish the current session or scan first." end
        if options.requestRosterScan("raid") == false then
            if options.cancelPendingRaidScan then options.cancelPendingRaidScan() end
            options.refresh()
            return false, "The scan could not start. Please try again."
        end
        controls.scan:Hide(); controls.status:SetText("Scanning raid...")
        return true
    end)
    newRaidDialog:SetHeight(190)
    Raider.UI.Components.SetHeadingIcon(newRaidDialog.title,"raids")
    newRaidDialog.raidLabel = Raider.UI.Components.CreateLabel(newRaidDialog, nil, "OVERLAY", "GameFontHighlightSmall")
    newRaidDialog.raidLabel:SetPoint("TOPLEFT", newRaidDialog, "TOPLEFT", 18, -91); newRaidDialog.raidLabel:SetText("Raid")
    newRaidDialog.raidSelect = Raider.UI.Components.CreateDropdownButton(newRaidDialog, nil, selectedRaidName, 180)
    newRaidDialog.raidSelect:SetPoint("TOPLEFT", newRaidDialog, "TOPLEFT", 18, -108)
    newRaidDialog.raidPanel = Raider.UI.Components.CreateDropdownPanel(newRaidDialog, newRaidDialog.raidSelect, 180, 148, 10)
    local raidNames = Raider.Services.RaidStatistics.GetRaidNames()
    local raidNameIndex
    for raidNameIndex = 1, table.getn(raidNames) do
        local option = Raider.UI.Components.CreateButton(newRaidDialog.raidPanel, nil, raidNames[raidNameIndex], 164, 20)
        option:SetPoint("TOPLEFT", newRaidDialog.raidPanel, "TOPLEFT", 8, -8 - ((raidNameIndex - 1) * 22)); option.raidName = raidNames[raidNameIndex]
        option:SetScript("OnClick", function() selectedRaidName = this.raidName; newRaidDialog.raidSelect.label:SetText(selectedRaidName); newRaidDialog.raidPanel:Hide() end)
    end
    newRaidDialog.raidSelect:SetScript("OnClick", function() if newRaidDialog.raidPanel:IsVisible() then newRaidDialog.raidPanel:Hide() else newRaidDialog.raidPanel:Show() end end)
    local pendingShareAction = nil
    local shareSrDialog = Raider.UI.Components.CreateTextPrompt("BootyRaiderShareSrDialog", "Share SR Link", "SR URL", "Save", function(value)
        value = string.gsub(tostring(value or ""), "^%s+", ""); value = string.gsub(value, "%s+$", "")
        if value == "" then return false, "SR URL is required." end
        if not options.setSrUrl(value) then return false, "Unable to save the SR URL." end
        local action = pendingShareAction or options.shareSrUrl
        local accepted, message = action(value)
        if accepted then pendingShareAction = nil end
        return accepted, message
    end, 500)
    Raider.UI.Components.SetHeadingIcon(shareSrDialog.title,"link")
    local function ShareWithUrl(action)
        local url = options.getSrUrl()
        if url and url ~= "" then
            local sent, message = action(url)
            if sent then options.printMessage("Soft Reserve link shared in Raid Warning.") end
            return sent, message
        end
        pendingShareAction = action; shareSrDialog:Open(); return true
    end
    options.page.pingMissingSoftReserves = function()
        local attendance = options.getAttendance()
        local missingNames = Raider.Services.Raid.GetSoftReserveIssues(attendance, options.getRules()).missingNames
        if table.getn(missingNames) == 0 then return end
        ShareWithUrl(function(url)
            local sent, message = options.shareMissingSrNames(missingNames)
            if not sent then return false, message end
            return options.shareSrUrl(url)
        end)
    end
    options.page.lootRulesDialog = lootRulesDialog
    options.page.contestedItemsDialog = contestedItemsDialog
    options.page.softReserveImportDialog = importDialog
    options.page.getRaidHistory = options.getRaidHistory
    local pendingDeleteRaidId = nil
    StaticPopupDialogs["BOOTY_RAIDER_DELETE_RAID_SNAPSHOT"] = {
        text = "Delete this saved raid snapshot?", button1 = "Delete", button2 = "Cancel",
        OnAccept = function()
            if pendingDeleteRaidId and options.deleteRaidSnapshot(pendingDeleteRaidId) then
                if options.page.selectedRaidHistoryId == pendingDeleteRaidId then options.page.selectedRaidHistoryId = nil end
                RaidManagement.ShowRaidHistoryControls(options.page, controls, options.isInRaid())
            end
            pendingDeleteRaidId = nil
        end,
        OnCancel = function() pendingDeleteRaidId = nil end,
        timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
    local historyIndex
    for historyIndex = 1, 10 do
        controls.historyButtons[historyIndex]:SetScript("OnClick", function()
            local snapshot = options.page.raidHistorySnapshots and options.page.raidHistorySnapshots[this.historyIndex]
            local snapshotId = snapshot and snapshot.id or nil
            if options.page.selectedRaidHistoryId == snapshotId then options.page.selectedRaidHistoryId = nil
            else options.page.selectedRaidHistoryId = snapshotId end
            RaidManagement.ShowRaidHistoryControls(options.page, controls, options.isInRaid())
        end)
        controls.historyDeleteButtons[historyIndex]:SetScript("OnClick", function()
            local snapshot = options.page.raidHistorySnapshots and options.page.raidHistorySnapshots[this.historyIndex]
            if not snapshot then return end
            pendingDeleteRaidId = snapshot.id
            Raider.UI.Components.ShowOpaquePopup("BOOTY_RAIDER_DELETE_RAID_SNAPSHOT")
        end)
    end
    local liveLoadDialog = Raider.UI.Components.Window.CreateProjectConfirmation("BootyRaiderLiveLoad", "Live Tracking", "Yes", "refresh")
    liveLoadDialog.no:SetText("No")
    liveLoadDialog.close:Hide()
    local function StopLoadedTracking()
        options.setLiveTracking(false)
        if Raider.Database.SetSetting then Raider.Database.SetSetting("raidLiveTrackingEnabled", false) end
        controls.refreshButton:SetInactive(false)
        options.refresh()
    end
    local function OfferCurrentRaidRefresh()
        if not options.isInRaid() then return end
        liveLoadDialog:Open("Refresh members from your current raid? This replaces the member list. Matching members keep their loot and SR. Choose No to keep the current data.", function()
            local updated
            if options.refreshCurrentRaid then updated = options.refreshCurrentRaid()
            else options.saveRaidRoster(); options.setHistoricalLoaded(false); updated = true end
            if updated == false then return end
            Raider.Database.SetSetting("raidLiveTrackingEnabled", true); options.setLiveTracking(true); options.refresh()
        end, StopLoadedTracking)
    end
    options.page.OfferCurrentRaidRefresh = OfferCurrentRaidRefresh
    local function LoadSelectedRaid()
        if not options.page.selectedRaidHistoryId then return false end
        local resumeTracking = Raider.Database.GetSetting("raidLiveTrackingEnabled")
        if options.loadRaidSnapshot(options.page.selectedRaidHistoryId) then
            if resumeTracking then Raider.Database.SetSetting("raidLiveTrackingEnabled", false); options.setLiveTracking(false) end
            RaidManagement.ResetIssueAttention(options.page)
            options.beginRaidSession(); options.setHistoricalLoaded(true); options.setScanReady(true); options.refresh()
            if resumeTracking and not (options.hasPendingRaidTransition and options.hasPendingRaidTransition()) then
                options.setLiveTracking(false)
                liveLoadDialog:Open("Do you want to refresh saved raid data with current raid? Pressing No turns off Live Tracking option in Settings. Remember to turn it on if desired.", function()
                    options.saveRaidRoster(); options.setHistoricalLoaded(false); Raider.Database.SetSetting("raidLiveTrackingEnabled", true); options.setLiveTracking(true); options.refresh()
                end, StopLoadedTracking)
            end
            return true
        end
        return false
    end
    controls.loadRaid:SetScript("OnClick", LoadSelectedRaid)
    for _, button in ipairs(controls.historyLoadButtons) do
        button:SetScript("OnClick", function()
            local snapshot = options.page.raidHistorySnapshots and options.page.raidHistorySnapshots[this.historyIndex]
            if not snapshot then return end
            options.page.selectedRaidHistoryId = snapshot.id
            LoadSelectedRaid()
        end)
    end
    controls.searchBox:SetScript("OnTextChanged", function() options.refresh() end)
    Raider.UI.Components.AttachPlaceholder(controls.searchBox,"Search...")
    controls.refreshButton:SetScript("OnClick", function()
        if this.inactive or not options.isInRaid() then return end
        if options.hasPendingRaidTransition and options.hasPendingRaidTransition() then
            options.page.ShowSessionTransitionPrompt("different-raid-context|refresh")
            return
        end
        this:SetInactive(true)
        if options.refreshCurrentRaid then options.refreshCurrentRaid() else options.saveRaidRoster() end
        options.setScanReady(true); options.refresh()
        this:SetInactive(false)
    end)
    controls.scan:SetScript("OnClick", function()
        if not options.isInRaid() then options.refresh(); return end
        newRaidDialog:Open()
    end)
    controls.testRaid:SetScript("OnClick", function()
        options.startTestRaid(); options.beginRaidSession(); options.setHistoricalLoaded(false); options.setScanReady(true); options.refresh()
    end)
    local sessionPrompt
    local saveDialog = Raider.UI.Components.CreateContainer("BootyRaiderSaveRaidSessionDialog", UIParent)
    saveDialog:SetWidth(300); saveDialog:SetHeight(218); saveDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    saveDialog:SetFrameStrata("FULLSCREEN_DIALOG"); saveDialog:SetFrameLevel(245); saveDialog:EnableMouse(true)
    saveDialog:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    saveDialog:SetBackdropColor(0.03, 0.025, 0.02, 1)
    if saveDialog.SetClampedToScreen then saveDialog:SetClampedToScreen(true) end
    saveDialog.title = Raider.UI.Components.CreateHeading(saveDialog, "", 1, "gold", "save")
    saveDialog.title:SetPoint("TOPLEFT", saveDialog, "TOPLEFT", 18, -17); saveDialog.title:SetText("Save Raid")
    local function CreateSaveCheckbox(label, y)
        local checkbox = Raider.UI.Components.CreateCheckButton(nil, saveDialog, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", saveDialog, "TOPLEFT", 18, y); checkbox:SetWidth(22); checkbox:SetHeight(22)
        checkbox.label = Raider.UI.Components.CreateLabel(saveDialog, nil, "OVERLAY", "GameFontHighlightSmall")
        checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 3, 0); checkbox.label:SetText(label)
        return checkbox
    end
    Raider.UI.Components.Window.StyleProjectDialog(saveDialog)
    saveDialog.idLabel=Raider.UI.Components.CreateLabel(saveDialog,nil,"OVERLAY","GameFontHighlightSmall");saveDialog.idLabel:SetPoint("TOPLEFT",saveDialog,"TOPLEFT",18,-42);saveDialog.idLabel:SetText("Raid ID")
    saveDialog.raidId=Raider.UI.Components.CreateFramedEditBox(saveDialog,nil,190);saveDialog.raidId:SetPoint("LEFT",saveDialog.idLabel,"RIGHT",8,0);saveDialog.raidId:SetMaxLetters(80)
    saveDialog.error=Raider.UI.Components.CreateLabel(saveDialog,nil,"OVERLAY","GameFontHighlightSmall");saveDialog.error:SetPoint("TOPLEFT",saveDialog,"TOPLEFT",18,-68);saveDialog.error:SetWidth(264);saveDialog.error:SetTextColor(1,0.35,0.30);saveDialog.error:Hide()
    saveDialog.statistics = CreateSaveCheckbox("Save raid statistics", -88)
    saveDialog.attendance = CreateSaveCheckbox("Save attendance", -116)
    saveDialog.csr = CreateSaveCheckbox("Save CSR", -144)
    local function SyncAttendanceOption()
        if saveDialog.statistics:GetChecked() then
            saveDialog.attendance:Enable(); saveDialog.attendance.label:SetTextColor(1, 1, 1)
        else
            saveDialog.attendance:Disable(); saveDialog.attendance.label:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    saveDialog.statistics:SetScript("OnClick", SyncAttendanceOption)
    saveDialog.cancel = Raider.UI.Components.CreateButton(saveDialog, nil, "Cancel", 90, 24)
    saveDialog.cancel:SetPoint("BOTTOMLEFT", saveDialog, "BOTTOMLEFT", 12, 12)
    saveDialog.save = Raider.UI.Components.CreateButton(saveDialog, nil, "Save Raid", 112, 24)
    saveDialog.save:SetPoint("BOTTOMRIGHT", saveDialog, "BOTTOMRIGHT", -12, 12)
    saveDialog.cancel:SetScript("OnClick", function()
        saveDialog:Hide()
        if saveDialog.transitionContext and sessionPrompt then sessionPrompt:Show() end
        saveDialog.transitionContext = nil
    end)
    saveDialog.save:SetScript("OnClick", function()
        local raidId=string.gsub(tostring(saveDialog.raidId:GetText() or ""),"^%s+","");raidId=string.gsub(raidId,"%s+$","")
        if raidId=="" then saveDialog.error:SetText("Raid ID is required.");saveDialog.error:Show();return end
        if options.raidIdExists and options.raidIdExists(raidId) then saveDialog.error:SetText("This Raid ID is already saved.");saveDialog.error:Show();return end
        local saveStatistics = saveDialog.statistics:GetChecked() and true or false
        local saveAttendance = saveStatistics and saveDialog.attendance:GetChecked() and true or false
        local saveCSR = saveDialog.csr:GetChecked() and true or false
        if options.saveRaidSession({raidId=raidId,saveRaidStatistics=saveStatistics,saveAttendance=saveAttendance,saveCSR=saveCSR})~=false then saveDialog.transitionContext=nil; saveDialog:Hide()
        else saveDialog.error:SetText("Raid ID could not be saved.");saveDialog.error:Show() end
    end)
    saveDialog.Open = function(self)
        self.statistics:SetChecked(1); self.attendance:SetChecked(1); self.csr:SetChecked(1)
        local attendance=options.getAttendance and options.getAttendance();self.raidId:SetText(attendance and (attendance.snapshotId or (attendance.softReserveImport and attendance.softReserveImport.id)) or "")
        self.error:Hide();SyncAttendanceOption(); self:Show();self.raidId:SetFocus();self.raidId:HighlightText()
    end
    options.page.OpenSaveDialog = function(contextKey) saveDialog.transitionContext=contextKey;saveDialog:Open() end
    saveDialog:Hide()
    options.page.saveSessionDialog = saveDialog
    controls.export:SetScript("OnClick", function()
        if options.isTestRaid and options.isTestRaid() then return end
        saveDialog.transitionContext = nil
        saveDialog:Open()
    end)
    controls.addStatistics:Hide()
    StaticPopupDialogs["BOOTY_RAIDER_QUIT_RAID_SESSION"] = {
        text = "Quit the current raid session without saving?", button1 = "Quit", button2 = "Cancel",
        OnAccept = function() options.quitRaidSession(); RaidManagement.ResetIssueAttention(options.page); options.refresh() end,
        timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
    local quitDialog = Raider.UI.Components.Window.CreateProjectConfirmation("BootyRaiderQuitRaidDialog", "Quit Raid", "Quit", "quit")
    options.page.quitDialog = quitDialog
    controls.quit:SetScript("OnClick", function() quitDialog:Open("Quit the current raid session without saving?", StaticPopupDialogs.BOOTY_RAIDER_QUIT_RAID_SESSION.OnAccept) end)

    sessionPrompt = Raider.UI.Components.CreateContainer("BootyRaiderRaidSessionPrompt", UIParent)
    sessionPrompt:SetWidth(390); sessionPrompt:SetHeight(150); sessionPrompt:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    sessionPrompt:SetFrameStrata("FULLSCREEN_DIALOG"); sessionPrompt:SetFrameLevel(240); sessionPrompt:EnableMouse(true)
    sessionPrompt:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    sessionPrompt:SetBackdropColor(0.03, 0.025, 0.02, 1)
    if sessionPrompt.SetClampedToScreen then sessionPrompt:SetClampedToScreen(true) end
    local promptTitle = Raider.UI.Components.CreateHeading(sessionPrompt, "", 1, "gold", "raids")
    sessionPrompt.title = promptTitle
    promptTitle:SetPoint("TOPLEFT", sessionPrompt, "TOPLEFT", 18, -16); promptTitle:SetText("Raid session is still active")
    local promptText = Raider.UI.Components.CreateLabel(sessionPrompt, nil, "OVERLAY", "GameFontHighlight")
    promptText:SetPoint("TOPLEFT", promptTitle, "BOTTOMLEFT", 0, -12); promptText:SetWidth(350); promptText:SetJustifyH("LEFT")
    promptText:SetText("You left the raid context. Do you want to continue this session or end and save it?")
    local continueButton = Raider.UI.Components.CreateButton(sessionPrompt, nil, "Continue Session", 132, 24)
    local saveButton = Raider.UI.Components.CreateButton(sessionPrompt, nil, "End & Save", 112, 24)
    saveButton:SetPoint("BOTTOMLEFT", sessionPrompt, "BOTTOMLEFT", 48, 18)
    continueButton:SetPoint("LEFT", saveButton, "RIGHT", 18, 0)
    local closeButton = Raider.UI.Components.CreateWindowButton(sessionPrompt, nil, "close")
    sessionPrompt.close = closeButton
    closeButton:SetPoint("TOPRIGHT", sessionPrompt, "TOPRIGHT", -10, -10)
    Raider.UI.Components.AttachTooltip(closeButton, "Not now", "Keep the session data and pause tracking until you choose what to do.")
    Raider.UI.Components.Window.StyleProjectDialog(sessionPrompt)
    promptTitle:SetHeight(16); promptTitle:SetJustifyV("MIDDLE")
    promptText:ClearAllPoints(); promptText:SetPoint("TOPLEFT", sessionPrompt.projectDivider, "BOTTOMLEFT", 6, -10)
    promptText:SetPoint("TOPRIGHT", sessionPrompt.projectDivider, "BOTTOMRIGHT", -6, -10)
    promptText:SetHeight(48); promptText:SetJustifyV("TOP")
    sessionPrompt.continueButton, sessionPrompt.saveButton, sessionPrompt.closeButton = continueButton, saveButton, closeButton
    sessionPrompt:Hide()
    continueButton:SetScript("OnClick", function()
        sessionPrompt:Hide()
        if options.continueRaidSession then options.continueRaidSession(sessionPrompt.contextKey) end
        if sessionPrompt.contextKey and string.find(sessionPrompt.contextKey, "different-raid-context|", 1, true) == 1 then OfferCurrentRaidRefresh() end
    end)
    saveButton:SetScript("OnClick", function()
        sessionPrompt:Hide()
        saveDialog.transitionContext = sessionPrompt.contextKey
        saveDialog:Open()
    end)
    closeButton:SetScript("OnClick", function()
        sessionPrompt:Hide()
        if options.dismissRaidSessionTransition then options.dismissRaidSessionTransition(sessionPrompt.contextKey) end
        options.refresh()
    end)
    options.page.ShowSessionTransitionPrompt = function(contextKey)
        if sessionPrompt:IsVisible() then return end
        sessionPrompt.contextKey = contextKey
        if contextKey and string.find(contextKey, "different-raid-context|", 1, true) == 1 then
            promptText:SetText("You joined a different raid. Continue this session, or save and end it before starting a new one?")
        else promptText:SetText("You left the raid context. Continue this session, or save and end it?") end
        sessionPrompt:Show()
    end
    options.page.HideSessionTransitionPrompt = function() sessionPrompt:Hide() end

    StaticPopupDialogs["BOOTY_RAIDER_START_RAID_REMINDER"] = {
        text = "You entered a raid instance without an active Raider raid session.",
        button1 = "No", button2 = "Start New Raid",
        OnAccept = function()
            if options.dismissRaidStartReminder then options.dismissRaidStartReminder(options.page.raidStartReminderContext) end
        end,
        OnCancel = function()
            if options.dismissRaidStartReminder then options.dismissRaidStartReminder(options.page.raidStartReminderContext) end
            if options.openRaidManagement then options.openRaidManagement() end
        end,
        timeout = 0, whileDead = 1,
    }
    options.page.ShowRaidStartReminder = function(contextKey)
        options.page.raidStartReminderContext = contextKey
        Raider.UI.Components.ShowOpaquePopup("BOOTY_RAIDER_START_RAID_REMINDER")
    end
    options.page.HideRaidStartReminder = function()
        StaticPopup_Hide("BOOTY_RAIDER_START_RAID_REMINDER")
    end
    controls.raidLeaderTools:SetScript("OnClick", function()
        if options.page.activeToolMenu == "leader" then options.page.activeToolMenu = nil else options.page.activeToolMenu = "leader" end
        options.refresh()
    end)
    controls.lootMasterTools:SetScript("OnClick", function()
        if options.page.activeToolMenu == "loot" then options.page.activeToolMenu = nil else options.page.activeToolMenu = "loot" end
        options.refresh()
    end)
    controls.import:SetScript("OnClick", function()
        importDialog:Open("")
    end)
    controls.shareSr:SetScript("OnClick", function()
        local sent, message = ShareWithUrl(options.shareSrUrl)
        if not sent and message then options.printMessage(message) end
    end)
    controls.lootRules:SetScript("OnClick", function() lootRulesDialog:Open() end)
    controls.sendLootRules:SetScript("OnClick", function()
        local sent, message = Raider.Services.Raid.SendLootRules(options.getRules())
        if not sent and message then options.printMessage(message) end
    end)
    controls.live:SetScript("OnClick", function()
        local tracking = not options.getLiveTracking()
        options.setLiveTracking(tracking)
        controls.live:SetText(tracking and "Stop Live Tracking" or "Start Live Tracking")
        if tracking then
            if not options.isInRaid() then
                options.setLiveTracking(false); controls.live:SetText("Start Live Tracking")
                options.printMessage("You must be in a raid to start live tracking.")
            else
                options.saveRaidRoster(); options.setScanReady(true); options.refresh(); options.printMessage("Raid live tracking started.")
            end
        else
            options.printMessage("Raid live tracking stopped.")
        end
    end)
    RaidManagement.quickActions = RaidManagement.CreateQuickActions(options, LoadSelectedRaid)
    return RaidManagement.quickActions
end

function RaidManagement.CreateAutoLootControls(page, view)
    local UI = Raider.UI.Components
    local panel = view.lmConfigPanel
    local names = { "Poor", "Common", "Uncommon", "Rare", "Epic" }
    local selected = {}
    local function Apply()
        if Raider.Modules.MasterLootWindow and Raider.Modules.MasterLootWindow.ApplyAutoLootSetting then Raider.Modules.MasterLootWindow.ApplyAutoLootSetting() end
    end
    local modeLabel, mode = UI.CreateChoiceField({ parent = panel, x = 8, y = -34,
        label = "LM Auto Loot:", buttonOffset = 134, width = 184, height = 76,
        initialText = "Off", firstY = -8, step = 20,
        choices = { { text = "Auto Loot", value = "auto" }, { text = "Shift Loot", value = "shift" }, { text = "Off", value = "off" } },
        getValue = function() return Raider.Database.GetSetting("lmAutoLootMode") end,
        onSelect = function(value)
            Raider.Database.SetSetting("lmAutoLootMode", value)
            Raider.Database.SetSetting("lmAutoLoot", value == "auto")
        end, onChanged = Apply,
    })
    view.lmAutoLoot = mode; page.lmAutoLoot = mode
    local label = UI.CreateComponentLabel(panel, "Auto Loot Rarity:", "white")
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -64)
    local rarity = UI.CreateDropdownButton(panel, nil, "", 184)
    rarity:SetPoint("TOPLEFT", panel, "TOPLEFT", 142, -64)
    local choices = UI.CreateDropdownPanel(panel, rarity, 184, 138, 20)
    local function RefreshRarity()
        local mask = Raider.Database.GetSetting("lmAutoLootRarities")
        local index
        for index = 1, table.getn(names) do
            selected[names[index]] = math.mod(math.floor(mask / (2 ^ (index - 1))), 2) == 1
        end
        UI.FilterPanel.SetCaption(rarity,names,selected)
    end
    local function SaveRarity()
        local mask, index = 0, nil
        for index = 1, table.getn(names) do if selected[names[index]] then mask = mask + 2 ^ (index - 1) end end
        Raider.Database.SetSetting("lmAutoLootRarities", mask); RefreshRarity(); Apply()
    end
    local showMode = mode:GetScript("OnClick")
    mode:SetScript("OnClick", function() choices:Hide(); showMode() end)
    rarity:SetScript("OnClick", function()
        if choices:IsVisible() then choices:Hide() else
            mode.panel:Hide(); RefreshRarity()
            UI.FilterPanel.Refresh(choices, names, selected, SaveRarity, false, true)
            for index = 1, table.getn(names) do
                local red, green, blue = GetItemQualityColor(index - 1)
                choices.options[index].label:SetTextColor(red, green, blue)
            end
            choices:Show()
        end
    end)
    view.lmAutoLootRarity = rarity; rarity.panel = choices
    local exceptionsLabel = UI.CreateComponentLabel(panel, "Auto Loot Exclusions:", "white")
    exceptionsLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -96)
    local exceptions = UI.CreateTextArea(panel, 324, 76, 2048)
    exceptions:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -116)
    exceptions:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -116)
    exceptions:SetTextInsets(8, 8, 8, 8)
    local tooltipHit = UI.AttachLabelTooltip(panel, exceptionsLabel, "Auto Loot Exclusions:", "Never auto loot matching items; overrides Inclusions. Comma-separated names, case-insensitive. * matches any text: Recipe *, * Coin.")
    exceptions:SetScript("OnTextChanged", function() Raider.Database.SetSetting("lmAutoLootExceptions", this:GetText()) end)
    exceptions:SetScript("OnEditFocusLost", Apply)
    local inclusionsLabel = UI.CreateComponentLabel(panel, "Auto Loot Inclusions:", "white")
    local inclusions = UI.CreateTextArea(panel, 324, 76, 2048)
    inclusions:SetTextInsets(8, 8, 8, 8)
    inclusions:SetScript("OnTextChanged", function() Raider.Database.SetSetting("lmAutoLootInclusions", this:GetText()) end)
    inclusions:SetScript("OnEditFocusLost", Apply)
    local inclusionTooltip = UI.AttachLabelTooltip(panel, inclusionsLabel, "Auto Loot Inclusions", "Auto loot regardless of rarity while enabled. Exclusions win. Comma-separated names, case-insensitive; * matches any text.")
    local exclusionsArea = UI.MakeTextAreaScrollable(exceptions, panel)
    local inclusionsArea = UI.MakeTextAreaScrollable(inclusions, panel)
    local focusDismiss = UI.CreateControl(nil, UIParent)
    focusDismiss:SetAllPoints(UIParent); focusDismiss:EnableMouse(true); focusDismiss:Hide()
    local function ClearTextFocus() exceptions:ClearFocus(); inclusions:ClearFocus(); focusDismiss:Hide() end
    focusDismiss:SetScript("OnMouseDown", ClearTextFocus)
    panel:SetScript("OnMouseDown", ClearTextFocus)
    tooltipHit:SetScript("OnMouseDown", ClearTextFocus); inclusionTooltip:SetScript("OnMouseDown", ClearTextFocus)
    local function FocusText()
        focusDismiss:SetFrameStrata(panel:GetFrameStrata()); focusDismiss:SetFrameLevel(math.max(0, panel:GetFrameLevel()-1)); focusDismiss:Show()
    end
    exceptions:SetScript("OnEditFocusGained", FocusText); inclusions:SetScript("OnEditFocusGained", FocusText)
    exceptions:SetScript("OnEditFocusLost", function() focusDismiss:Hide(); Apply() end)
    inclusions:SetScript("OnEditFocusLost", function() focusDismiss:Hide(); Apply() end)
    view.lmAutoLootInclusions = inclusions
    view.lmAutoLootExceptions = exceptions
    view.lmExceptionsTooltip = tooltipHit
    local font, size, flags = view.lmConfigTitle:GetFont()
    modeLabel:SetFont(font, size, flags); label:SetFont(font, size, flags); exceptionsLabel:SetFont(font, size, flags)
    inclusionsLabel:SetFont(font, size, flags)
    view.lmConfigLabels = { modeLabel, label, exceptionsLabel, inclusionsLabel }
    local presetLabel = UI.CreateComponentLabel(panel, "Add Exclusions Preset", "white")
    presetLabel:SetFont(font, size, flags); table.insert(view.lmConfigLabels, presetLabel)
    presetLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 34)
    local presets = UI.CreateDropdownButton(panel, nil, "None", 184)
    presets:SetPoint("LEFT", presetLabel, "LEFT", 134, 0)
    local presetPanel = UI.CreateDropdownPanel(panel, presets, 184, 138, 20)
    presets.panel = presetPanel; view.lmExceptionPresets = presets
    local function StylePanels()
        UI.Window.ApplyProjectSurface(presetPanel); UI.Window.ApplyProjectSurface(mode.panel)
    end
    StylePanels(); UI.RegisterSkinCallback(StylePanels)
    presetPanel.contentPadding = 4
    local optionIndex
    mode.panel:SetHeight(70)
    for optionIndex = 1, table.getn(mode.panel.options) do
        local option = mode.panel.options[optionIndex]
        option:ClearAllPoints(); option:SetPoint("TOPLEFT", mode.panel, "TOPLEFT", 4, -4 - (optionIndex - 1) * 22)
        option:SetPoint("TOPRIGHT", mode.panel, "TOPRIGHT", -4, -4 - (optionIndex - 1) * 22)
    end
    local function LayoutConfig()
        local width = math.max(94, panel:GetWidth() - 150)
        mode:SetWidth(width); rarity:SetWidth(width); presets:SetWidth(width)
        presetLabel:ClearAllPoints(); presetLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -94)
        presets:ClearAllPoints(); presets:SetPoint("TOPLEFT", panel, "TOPLEFT", 160, -94); presets:SetWidth(math.max(84,panel:GetWidth()-168))
        exceptionsLabel:ClearAllPoints(); exceptionsLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -124)
        local areaHeight = math.max(64, (panel:GetHeight() - 188) / 2)
        exclusionsArea:ClearAllPoints(); exclusionsArea:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -144)
        exclusionsArea:SetWidth(math.max(1,panel:GetWidth()-16)); exclusionsArea:SetHeight(areaHeight)
        inclusionsLabel:ClearAllPoints(); inclusionsLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -154-areaHeight)
        inclusionsArea:ClearAllPoints(); inclusionsArea:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -174-areaHeight)
        inclusionsArea:SetWidth(math.max(1,panel:GetWidth()-16)); inclusionsArea:SetHeight(areaHeight)
        exceptions.LayoutScroll(); inclusions.LayoutScroll()
    end
    panel:SetScript("OnSizeChanged", LayoutConfig)
    LayoutConfig()
    local presetNames, presetSelected = Raider.Services.AutoLoot.PresetNames, {}
    local function RefreshPresets()
        local mask = Raider.Database.GetSetting("lmAutoLootPresets")
        local index
        for index = 1, table.getn(presetNames) do
            presetSelected[presetNames[index]] = math.mod(math.floor(mask / 2 ^ (index - 1)), 2) == 1
        end
        UI.FilterPanel.SetCaption(presets,presetNames,presetSelected)
    end
    local function SavePresets()
        local mask, index = 0, nil
        for index = 1, table.getn(presetNames) do if presetSelected[presetNames[index]] then mask = mask + 2 ^ (index - 1) end end
        Raider.Database.SetSetting("lmAutoLootPresets", mask)
        local text = Raider.Services.AutoLoot.ApplyPresets(exceptions:GetText(), mask)
        Raider.Database.SetSetting("lmAutoLootExceptions", text); exceptions:SetText(text)
        RefreshPresets(); Apply()
    end
    presets:SetScript("OnClick", function()
        ClearTextFocus()
        if presetPanel:IsVisible() then presetPanel:Hide() else
            mode.panel:Hide(); choices:Hide(); RefreshPresets()
            UI.FilterPanel.Refresh(presetPanel, presetNames, presetSelected, SavePresets, false, true); presetPanel:Show()
        end
    end)
    local modeClick, rarityClick = mode:GetScript("OnClick"), rarity:GetScript("OnClick")
    mode:SetScript("OnClick", function() ClearTextFocus(); presetPanel:Hide(); modeClick() end)
    rarity:SetScript("OnClick", function() ClearTextFocus(); presetPanel:Hide(); rarityClick() end)
    panel:SetScript("OnShow", function()
        LayoutConfig()
        if page.lootMasterController then page.lootMasterController.ReanchorPanels() end
        local strata, level = panel:GetFrameStrata(), panel:GetFrameLevel() + 1
        mode:SetFrameStrata(strata); mode:SetFrameLevel(level)
        rarity:SetFrameStrata(strata); rarity:SetFrameLevel(level)
        exceptions:SetFrameStrata(strata); exceptions:SetFrameLevel(level)
        inclusions:SetFrameStrata(strata); inclusions:SetFrameLevel(level + 2)
        exceptions:SetFrameLevel(level + 2)
        exclusionsArea:SetFrameLevel(level); inclusionsArea:SetFrameLevel(level)
        exceptions.viewport:SetFrameLevel(level+1); inclusions.viewport:SetFrameLevel(level+1)
        inclusionTooltip:SetFrameStrata(strata); inclusionTooltip:SetFrameLevel(level)
        tooltipHit:SetFrameStrata(strata); tooltipHit:SetFrameLevel(level)
        presets:SetFrameStrata(strata); presets:SetFrameLevel(level)
        RefreshPresets()
        local value = Raider.Database.GetSetting("lmAutoLootMode")
        mode:SetText(value == "auto" and "Auto Loot" or value == "shift" and "Shift Loot" or "Off")
        RefreshRarity(); exceptions:SetText(Raider.Database.GetSetting("lmAutoLootExceptions"))
        inclusions:SetText(Raider.Database.GetSetting("lmAutoLootInclusions"))
    end)
    panel:SetScript("OnHide", function() mode.panel:Hide(); choices:Hide(); presetPanel:Hide(); ClearTextFocus() end)
end
