local Raider = BootyRaider
Raider.Modules.RaidManagement = Raider.Modules.RaidManagement or {}
local RaidManagement = Raider.Modules.RaidManagement

local function ShowItemTooltip() Raider.UI.Components.ShowItemTooltip(this) end
local function HideItemTooltip() GameTooltip:Hide() end
local function HandleItemClick() Raider.UI.Components.HandleItemClick(this) end
local warningRowColor = {0.10, 0.085, 0.055}

local function CenterOnScreen(frame)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function IsCursorOverFrame(frame)
    if not frame or not frame:IsVisible() or not frame:GetLeft() then return false end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x = x / scale; y = y / scale
    return x >= frame:GetLeft() and x <= frame:GetRight() and y >= frame:GetBottom() and y <= frame:GetTop()
end

function RaidManagement.CreateSoftReserveImportDialog(options)
    local dialog
    dialog = Raider.UI.Components.CreateTextEditor("BootyRaiderSoftReserveImport", "Import Soft Reserves", 16000, function(value)
        if options.isTestRaid and options.isTestRaid() then
            local url = dialog.url:GetText() or ""
            if not options.setSrUrl(url) then dialog:SetMessage("SR URL is required.", true); return false end
            options.refresh(); options.printMessage("Test Raid Soft Reserve URL updated.")
            return true
        end
        local result, importError = options.importData(value, dialog.url:GetText() or "")
        if not result then dialog:SetMessage(importError or "The Soft Reserve import failed.", true); return false end
        options.refresh()
        options.printMessage("Soft Reserves imported. Matched: " .. result.matched .. ", outside raid: " .. result.unmatched .. ", raid members without SR: " .. result.missing .. ".")
        return true
    end)
    dialog.close = Raider.UI.Components.CreateWindowButton(dialog, nil, "close")
    dialog.close:SetScript("OnClick", function() dialog:Hide() end)
    Raider.UI.Components.Window.StyleProjectDialog(dialog)
    dialog:SetWidth(620); dialog:SetHeight(360); dialog.save:SetText("Import"); dialog.cancel:SetText("Cancel")
    dialog.urlLabel = Raider.UI.Components.CreateLabel(dialog, nil, "OVERLAY", "GameFontNormalSmall")
    dialog.urlLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -36); dialog.urlLabel:SetText("SR URL")
    dialog.url = Raider.UI.Components.CreateFramedEditBox(dialog, nil, 580)
    dialog.url:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -52); dialog.url:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -8, -52); dialog.url:SetMaxLetters(500)
    dialog.exportLabel = Raider.UI.Components.CreateLabel(dialog, nil, "OVERLAY", "GameFontNormalSmall")
    dialog.exportLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -80); dialog.exportLabel:SetText("RollFor export")
    dialog.exportFrame = Raider.UI.Components.CreateContainer(nil, dialog)
    dialog.exportFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -97)
    dialog.exportFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -28, 38)
    dialog.exportFrame:SetBackdrop(dialog.scroll:GetBackdrop())
    dialog.exportFrame:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
    dialog.scroll:SetBackdrop(nil)
    dialog.scroll:ClearAllPoints(); dialog.scroll:SetPoint("TOPLEFT", dialog.exportFrame, "TOPLEFT", 6, -6)
    dialog.scroll:SetPoint("BOTTOMRIGHT", dialog.exportFrame, "BOTTOMRIGHT", -6, 6)
    local openEditor = dialog.Open
    dialog.Open = function(self, value)
        local testMode = options.isTestRaid and options.isTestRaid()
        self.url:SetText(options.getSrUrl() or "")
        if testMode then
            self:SetHeight(175); self.exportLabel:Hide(); self.exportFrame:Hide(); self.scroll:Hide(); self.counter:Hide(); self.save:SetText("Save")
        else
            self:SetHeight(360); self.exportLabel:Show(); self.exportFrame:Show(); self.scroll:Show(); self.counter:Show(); self.save:SetText("Import")
        end
        openEditor(self, testMode and "" or (options.getRollForExport() or value or ""))
        if testMode then self.url:SetFocus() end
    end
    dialog.cancel:ClearAllPoints(); dialog.cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -86, 8)
    dialog.save:ClearAllPoints(); dialog.save:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -8, 8)
    if Raider.UI.Components.WindowStack then Raider.UI.Components.WindowStack.SetOwner(dialog, options.page) end
    return dialog
end

local function CreateWarningCard(page, dialogName, dialogTitle, background, border, textColor)
    local warning = Raider.UI.Components.CreateControl(nil, page)
    warning:SetHeight(58)
    warning:SetFrameLevel(page:GetFrameLevel() + 50)
    warning:EnableMouse(true)
    Raider.UI.Components.Window.ApplyProjectSurface(warning)
    warning.badge = Raider.UI.Components.CreateLabel(warning, nil, "OVERLAY", "GameFontDisableSmall")
    warning.badge:SetPoint("TOPLEFT", warning, "TOPLEFT", 8, -5); warning.badge:SetText("Warning")
    warning.badge:SetTextColor(textColor[1], textColor[2], textColor[3])
    warning.classicHeader = Raider.UI.Components.CreateContainer(nil, warning)
    warning.classicHeader:SetPoint("TOPLEFT", warning, "TOPLEFT", 4, -4); warning.classicHeader:SetPoint("TOPRIGHT", warning, "TOPRIGHT", -4, -4); warning.classicHeader:SetHeight(22)
    warning.classicHeader.divider = Raider.UI.Components.CreateContainer(nil, warning)
    local divider = warning.classicHeader.divider
    divider:SetPoint("TOPLEFT", warning, "TOPLEFT", 4, -28)
    divider:SetPoint("TOPRIGHT", warning, "TOPRIGHT", -4, -28); divider:SetHeight(4)
    Raider.UI.Components.RegisterSkinnedSurface(divider, "content", nil, {0,0,0,0}, {0.68,0.54,0.27,1})
    Raider.UI.Components.JoinSurfaceEdges(divider, true, false)
    warning.classicHeader.icon = Raider.UI.Components.CreateTexture(warning.classicHeader, nil, "ARTWORK")
    warning.classicHeader.icon:SetTexture(Raider.UI.Components.ClassicAsset("Icons\\warning_triangle.tga")); warning.classicHeader.icon:SetWidth(12); warning.classicHeader.icon:SetHeight(12)
    warning.classicHeader.icon:SetPoint("LEFT", warning.classicHeader, "LEFT", 4, 0); warning.classicHeader.icon:SetVertexColor(1, 0.82, 0.28)
    warning.classicHeader.title = Raider.UI.Components.CreateLabel(warning.classicHeader, nil, "OVERLAY", "GameFontNormalSmall")
    warning.classicHeader.title:SetPoint("LEFT", warning.classicHeader.icon, "RIGHT", 6, 0); warning.classicHeader.title:SetText("Warning")
    warning.classicHeader.title:SetTextColor(1, 0.82, 0.28)
    local _, warningFontSize = warning.classicHeader.title:GetFont()
    warning.classicHeader.icon:SetWidth(warningFontSize); warning.classicHeader.icon:SetHeight(warningFontSize)
    warning.classicHeader.close = Raider.UI.Components.CreateWindowButton(warning.classicHeader, nil, "close")
    warning.classicHeader.close:SetPoint("RIGHT", warning.classicHeader, "RIGHT", -3, 0)
    warning.classicHeader.minimize = Raider.UI.Components.CreateWindowButton(warning.classicHeader, nil, "minimize")
    warning.classicHeader.minimize:SetPoint("RIGHT", warning.classicHeader.close, "LEFT", -2, 0)
    warning.classicHeader.title:SetPoint("RIGHT", warning.classicHeader.minimize, "LEFT", -4, 0)
    warning.classicHeader.title:SetJustifyH("LEFT")
    warning.classicHeader.minimize:SetScript("OnClick", function()
        warning.userMinimized = not warning.docked
        warning.forceExpanded = not warning.userMinimized
        if warning.onDismiss then warning.onDismiss() end
    end)
    warning.classicHeader.close:SetScript("OnClick", function()
        warning.userDismissed = true
        warning:Hide()
        if warning.onDismiss then warning.onDismiss() end
    end)
    Raider.UI.Components.AttachTooltip(warning.classicHeader.close, "Dismiss warning", "Hide this warning until its data is refreshed.")
    warning.classicHeader:Hide()
    warning.text = Raider.UI.Components.CreateLabel(warning, nil, "OVERLAY", "GameFontHighlightSmall")
    warning.text:SetPoint("LEFT", warning, "LEFT", 9, -5); warning.text:SetPoint("RIGHT", warning, "RIGHT", -9, -5)
    warning.text:SetJustifyH("CENTER"); warning.text:SetTextColor(textColor[1], textColor[2], textColor[3])
    Raider.UI.Components.RegisterSkinCallback(function()
        Raider.UI.Components.Window.ApplyProjectSurface(warning)
        warning.classicHeader:Show(); warning.badge:Hide()
        warning.text:SetTextColor(0.92, 0.91, 0.87)
    end)
    warning.dialog = Raider.UI.Components.CreateReadOnlyDialog(dialogName, dialogTitle, 430, 260, background)
    if Raider.UI.Components.WindowStack then Raider.UI.Components.WindowStack.SetOwner(warning.dialog, warning) end
    Raider.UI.Components.Window.StyleProjectDialog(warning.dialog, "warning_triangle")
    warning.dialog.title:SetTextColor(1, 1, 1)
    warning.dialog.icon = warning.dialog.title.mosHeadingIcon
    warning.dialog.ok:ClearAllPoints(); warning.dialog.ok:SetPoint("BOTTOMRIGHT", warning.dialog, "BOTTOMRIGHT", -8, 8)
    warning.dialog.description = Raider.UI.Components.CreateLabel(warning.dialog, nil, "OVERLAY", "GameFontHighlightSmall")
    warning.dialog.description:SetPoint("TOPLEFT", warning.dialog, "TOPLEFT", 8, -36)
    warning.dialog.description:SetPoint("TOPRIGHT", warning.dialog, "TOPRIGHT", -8, -36)
    warning.dialog.description:SetHeight(20); warning.dialog.description:SetJustifyH("LEFT"); warning.dialog.description:SetJustifyV("TOP")
    warning.dialog:SetScript("OnShow", function() warning.dialog.dismiss:Hide() end)
    warning.dialog:SetScript("OnHide", function() warning.dialog.dismiss:Hide() end)
    warning.dialog.playerRows = {}
    warning.info = Raider.UI.Components.CreateButton(warning, nil, "INFO", 66, 20)
    warning.info:SetPoint("BOTTOMRIGHT", warning, "BOTTOMRIGHT", -8, 6); warning.info:SetFrameLevel(warning:GetFrameLevel() + 2)
    warning.info:SetScript("OnClick", function()
        warning.dialog.title:SetText("|cffffd147Warning:|r " .. (warning.text:GetText() or dialogTitle))
        local attendance = page.getWarningAttendance and page.getWarningAttendance() or page.listRenderer and page.listRenderer.getData()
        local issues = Raider.Services.Raid.GetSoftReserveIssues(attendance, page.getSoftReserveRules and page.getSoftReserveRules())
        local key = warning == page.softReserveWarning and "unmatchedNames" or warning == page.missingSoftReserveWarning and "missingNames" or "invalidNames"
        local names = issues[key] or {}
        local dialog = warning.dialog
        local descriptions = {
            unmatchedNames = "Imported Soft Reserves that are not assigned to a current raid member.",
            missingNames = "Current raid members who do not have an imported Soft Reserve.",
            invalidNames = "Raid members whose Soft Reserve is excluded by their loot rights.",
        }
        dialog.description:SetText(descriptions[key])
        dialog:SetHeight(math.min(300, math.max(150, 106 + table.getn(names) * 24)))
        CenterOnScreen(dialog)
        dialog:Open(""); dialog.text:Hide()
        local contentHeight = table.getn(names) * 24
        local overflow = contentHeight > dialog:GetHeight() - 98
        dialog.scroll:ClearAllPoints(); dialog.scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -60)
        dialog.scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", overflow and -28 or -8, 38)
        local width = dialog:GetWidth() - (overflow and 36 or 16)
        dialog.canvas:SetWidth(width); dialog.canvas:SetHeight(math.max(1, contentHeight))
        if dialog.scrollBar then if overflow then dialog.scrollBar:Show() else dialog.scrollBar:Hide() end end
        for index=1, table.getn(names) do
            local row = dialog.playerRows[index]
            if not row then
                row = Raider.UI.Components.CreateButton(dialog.canvas, nil, "", width, 22)
                Raider.UI.Components.SetButtonLabelInsets(row, 6, 6)
                Raider.UI.Components.SetRowColor(row, warningRowColor, 1)
                dialog.playerRows[index] = row
            end
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", dialog.canvas, "TOPLEFT", 0, -(index-1)*24)
            local caption = RaidManagement.SoftReservePlayerLabel(names[index], attendance)
            if key == "invalidNames" then
                for _, member in ipairs(attendance and attendance.members or {}) do
                    if string.lower(member.name or "") == string.lower(names[index]) then
                        caption = caption .. " - " .. Raider.Services.RankPolicy.GetDisplayName((member.guildRank and member.guildRank ~= "" and member.guildRank) or "Guest") .. " rank has no SR"
                        break
                    end
                end
            end
            row:SetWidth(width); row:SetText(caption); row:Show()
        end
        for index=table.getn(names)+1, table.getn(dialog.playerRows) do dialog.playerRows[index]:Hide() end
    end)
    warning:Hide()
    return warning
end

function RaidManagement.CreateSoftReserveWarnings(page, clearUnmatched, refresh, getAttendance)
    page.getWarningAttendance = getAttendance
    page.softReserveWarning = CreateWarningCard(page, "BootyRaiderSoftReserveWarningDetails", "Soft Reserves outside raid", { 0.18, 0.08, 0.01 }, { 1, 0.55, 0.08 }, { 1, 0.72, 0.18 })
    page.softReserveWarning.onDismiss = refresh
    page.softReserveWarning.text:ClearAllPoints(); page.softReserveWarning.text:SetPoint("LEFT", page.softReserveWarning, "LEFT", 9, -5); page.softReserveWarning.text:SetPoint("RIGHT", page.softReserveWarning, "RIGHT", -84, -5)
    page.softReserveWarning.fix = Raider.UI.Components.CreateButton(page.softReserveWarning, nil, "FIX SR", 66, 22)
    Raider.UI.Components.SetClassicButtonVariant(page.softReserveWarning.fix, "red"); Raider.UI.Components.SetClassicButtonVariant(page.softReserveWarning.info, "red")
    Raider.UI.Components.SetClassicButtonIcon(page.softReserveWarning.fix, "fix", 12); Raider.UI.Components.SetClassicButtonIcon(page.softReserveWarning.info, "info", 12)
    page.softReserveWarning.fix:SetPoint("TOPRIGHT", page.softReserveWarning, "TOPRIGHT", -8, -6); page.softReserveWarning.fix:SetHeight(20); page.softReserveWarning.fix:SetFrameLevel(page.softReserveWarning:GetFrameLevel() + 2)
    StaticPopupDialogs["BOOTY_RAIDER_CLEAR_UNMATCHED_SR"] = {
        text = "Remove every unassigned Soft Reserve from the current import? Assigned raid members will not be changed.", button1 = "Remove", button2 = "Cancel",
        OnAccept = function() if clearUnmatched(page.listRenderer.getData()) then refresh() end end,
        timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
    local confirmBOOTY_RAIDER_CLEAR_UNMATCHED_SR = Raider.UI.Components.Window.CreateProjectConfirmation("BOOTY_RAIDER_CLEAR_UNMATCHED_SRDialog", "Fix Soft Reserves", "Remove", "fix")
    page.softReserveWarning.fix:SetScript("OnClick", function() local spec=StaticPopupDialogs.BOOTY_RAIDER_CLEAR_UNMATCHED_SR; CenterOnScreen(confirmBOOTY_RAIDER_CLEAR_UNMATCHED_SR); confirmBOOTY_RAIDER_CLEAR_UNMATCHED_SR:Open(spec.text, spec.OnAccept) end)
    page.missingSoftReserveWarning = CreateWarningCard(page, "BootyRaiderMissingSoftReserveDetails", "Raid members without Soft Reserve", { 0.18, 0.08, 0.01 }, { 1, 0.55, 0.08 }, { 1, 0.72, 0.18 })
    page.missingSoftReserveWarning.onDismiss = refresh
    page.missingSoftReserveWarning.text:ClearAllPoints(); page.missingSoftReserveWarning.text:SetPoint("LEFT", page.missingSoftReserveWarning, "LEFT", 9, -5); page.missingSoftReserveWarning.text:SetPoint("RIGHT", page.missingSoftReserveWarning, "RIGHT", -84, -5)
    page.missingSoftReserveWarning.fix = Raider.UI.Components.CreateButton(page.missingSoftReserveWarning, nil, "FIX SR", 66, 22)
    Raider.UI.Components.SetClassicButtonVariant(page.missingSoftReserveWarning.fix, "red"); Raider.UI.Components.SetClassicButtonVariant(page.missingSoftReserveWarning.info, "red")
    Raider.UI.Components.SetClassicButtonIcon(page.missingSoftReserveWarning.fix, "fix", 10, 5); Raider.UI.Components.SetClassicButtonIcon(page.missingSoftReserveWarning.info, "info", 10, 5)
    page.missingSoftReserveWarning.fix:SetPoint("TOPRIGHT", page.missingSoftReserveWarning, "TOPRIGHT", -8, -4); page.missingSoftReserveWarning.fix:SetHeight(14); page.missingSoftReserveWarning.fix:SetFrameLevel(page.missingSoftReserveWarning:GetFrameLevel() + 2)
    page.missingSoftReserveWarning.info:ClearAllPoints(); page.missingSoftReserveWarning.info:SetPoint("TOPRIGHT", page.missingSoftReserveWarning, "TOPRIGHT", -8, -21); page.missingSoftReserveWarning.info:SetHeight(14)
    page.missingSoftReserveWarning.ping = Raider.UI.Components.CreateButton(page.missingSoftReserveWarning, nil, "PING", 66, 14)
    Raider.UI.Components.SetClassicButtonVariant(page.missingSoftReserveWarning.ping, "red")
    Raider.UI.Components.SetClassicButtonIcon(page.missingSoftReserveWarning.ping, "ping", 10, 5)
    page.missingSoftReserveWarning.ping:SetPoint("TOPRIGHT", page.missingSoftReserveWarning, "TOPRIGHT", -8, -38); page.missingSoftReserveWarning.ping:SetFrameLevel(page.missingSoftReserveWarning:GetFrameLevel() + 2)
    page.missingSoftReserveWarning.fix:SetScript("OnClick", function() if page.softReserveFixDialog then CenterOnScreen(page.softReserveFixDialog); page.softReserveFixDialog:Open(getAttendance()) end end)
    page.missingSoftReserveWarning.ping:SetScript("OnClick", function() if page.pingMissingSoftReserves then page.pingMissingSoftReserves() end end)
    page.invalidSoftReserveWarning = CreateWarningCard(page, "BootyRaiderInvalidSoftReserveDetails", "Soft Reserve without loot rights", { 0.18, 0.08, 0.01 }, { 1, 0.55, 0.08 }, { 1, 0.72, 0.18 })
    page.invalidSoftReserveWarning.onDismiss = refresh
    local invalidWarning = page.invalidSoftReserveWarning
    invalidWarning.text:ClearAllPoints(); invalidWarning.text:SetPoint("LEFT", invalidWarning, "LEFT", 9, -5); invalidWarning.text:SetPoint("RIGHT", invalidWarning, "RIGHT", -84, -5)
    invalidWarning.fix = Raider.UI.Components.CreateButton(invalidWarning, nil, "FIX SR", 66, 14)
    invalidWarning.ping = Raider.UI.Components.CreateButton(invalidWarning, nil, "PING", 66, 14)
    Raider.UI.Components.SetClassicButtonVariant(invalidWarning.fix, "red"); Raider.UI.Components.SetClassicButtonVariant(invalidWarning.info, "red"); Raider.UI.Components.SetClassicButtonVariant(invalidWarning.ping, "red")
    Raider.UI.Components.SetClassicButtonIcon(invalidWarning.fix, "fix", 10, 5); Raider.UI.Components.SetClassicButtonIcon(invalidWarning.info, "info", 10, 5); Raider.UI.Components.SetClassicButtonIcon(invalidWarning.ping, "ping", 10, 5)
    invalidWarning.fix:SetPoint("TOPRIGHT", invalidWarning, "TOPRIGHT", -8, -4); invalidWarning.fix:SetFrameLevel(invalidWarning:GetFrameLevel() + 2)
    invalidWarning.info:ClearAllPoints(); invalidWarning.info:SetPoint("TOPRIGHT", invalidWarning, "TOPRIGHT", -8, -21); invalidWarning.info:SetWidth(66); invalidWarning.info:SetHeight(14)
    invalidWarning.ping:SetPoint("TOPRIGHT", invalidWarning, "TOPRIGHT", -8, -38); invalidWarning.ping:SetFrameLevel(invalidWarning:GetFrameLevel() + 2)
    StaticPopupDialogs["BOOTY_RAIDER_CLEAR_INVALID_SR"] = {
        text = "Remove invalid Soft Reserves from raid members?", button1 = "Remove SR", button2 = "Cancel",
        OnAccept = function()
            if Raider.Services.RaidRes.ClearInvalidMemberReservations(getAttendance(), page.getSoftReserveRules and page.getSoftReserveRules()) > 0 then refresh() end
        end,
        timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
    local confirmBOOTY_RAIDER_CLEAR_INVALID_SR = Raider.UI.Components.Window.CreateProjectConfirmation("BOOTY_RAIDER_CLEAR_INVALID_SRDialog", "Fix Soft Reserves", "Remove SR", "fix")
    confirmBOOTY_RAIDER_CLEAR_INVALID_SR:SetWidth(300)
    invalidWarning.fix:SetScript("OnClick", function() local spec=StaticPopupDialogs.BOOTY_RAIDER_CLEAR_INVALID_SR; CenterOnScreen(confirmBOOTY_RAIDER_CLEAR_INVALID_SR); confirmBOOTY_RAIDER_CLEAR_INVALID_SR:Open(spec.text, spec.OnAccept) end)
    invalidWarning.ping:SetScript("OnClick", function()
        local names = Raider.Services.Raid.GetSoftReserveIssues(getAttendance(), page.getSoftReserveRules and page.getSoftReserveRules()).invalidNames
        if table.getn(names) == 0 then return end
        local sent = Raider.Services.Raid.SendLootMessage("InvalidSR", {players=table.concat(names, ", "), playerNames=names})
        if sent then Raider.Services.Raid.SendLootMessage("InvalidSRNotice") end
    end)
end

function RaidManagement.SoftReservePlayerLabel(name, attendance, reservation)
    local member = reservation
    local function Find(members)
        for _, candidate in ipairs(members or {}) do
            if string.lower(candidate.name or "") == string.lower(name or "") then return candidate end
        end
    end
    member = Find(attendance and attendance.members) or member or Find(attendance and attendance.softReserveImport and attendance.softReserveImport.unmatchedReservations)
    if not member or not (member.classFile or member.class) then
        local roster = Raider.Database and Raider.Database.GetRosterData and Raider.Database.GetRosterData()
        member = Find(roster and roster.members) or member
    end
    local key = string.upper(member and (member.classFile or member.class) or "")
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[key] or Raider.UI.Components.Theme.classColors[key]
    if not color then return name or "" end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(color.r*255), math.floor(color.g*255), math.floor(color.b*255), name or "")
end

function RaidManagement.CreateSoftReserveFixDialog(page, applyAssignments, refresh)
    local dismiss = Raider.UI.Components.CreateControl(nil, UIParent)
    dismiss:SetAllPoints(UIParent); dismiss:Hide()
    local dialog = Raider.UI.Components.CreateContainer("BootyRaiderSoftReserveFixDialog", UIParent)
    dialog:SetWidth(700); dialog:SetHeight(430); dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dialog:EnableMouse(true); dialog:Hide()
    if dialog.SetClampedToScreen then dialog:SetClampedToScreen(true) end
    dialog:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 7, right = 7, top = 7, bottom = 7 } }); dialog:SetBackdropColor(0.018, 0.018, 0.016, 1)
    Raider.UI.Components.RegisterDialogSurface(dialog, "panel", { 0.018, 0.018, 0.016, 1 })
    dialog.title = Raider.UI.Components.CreateHeading(dialog, "", 1, "gold", "fix"); dialog.title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -16); dialog.title:SetText("Fix Soft Reserve assignments")
    Raider.UI.Components.Window.StyleProjectDialog(dialog)
    dialog.help = Raider.UI.Components.CreateLabel(dialog, nil, "OVERLAY", "GameFontHighlightSmall"); dialog.help:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -36); dialog.help:SetText("Drag an unassigned Soft Reserve from the right onto the correct raid member.")
    dialog.leftTitle = Raider.UI.Components.CreateLabel(dialog, nil, "OVERLAY", "GameFontNormal"); dialog.leftTitle:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -72); dialog.leftTitle:SetText("Raid members without SR")
    dialog.rightTitle = Raider.UI.Components.CreateLabel(dialog, nil, "OVERLAY", "GameFontNormal"); dialog.rightTitle:SetPoint("TOPLEFT", dialog, "TOPLEFT", 354, -72); dialog.rightTitle:SetText("Unassigned Soft Reserves")
    dialog.leftPanel = Raider.UI.Components.CreateContainer(nil, dialog); dialog.leftPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -92); dialog.leftPanel:SetWidth(338); dialog.leftPanel:SetHeight(278)
    dialog.rightPanel = Raider.UI.Components.CreateContainer(nil, dialog); dialog.rightPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 354, -92); dialog.rightPanel:SetWidth(338); dialog.rightPanel:SetHeight(278)
    local panels = { dialog.leftPanel, dialog.rightPanel }
    local panelIndex, rowIndex
    for panelIndex = 1, 2 do
        panels[panelIndex]:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        panels[panelIndex]:SetBackdropColor(0.035, 0.035, 0.03, 1); panels[panelIndex]:SetBackdropBorderColor(0.38, 0.34, 0.24, 1); panels[panelIndex]:EnableMouseWheel(true)
    end
    dialog.leftRows = {}; dialog.rightRows = {}; dialog.assignments = {}
    for rowIndex = 1, 12 do
        local left = Raider.UI.Components.CreateButton(dialog.leftPanel, nil, "", 324, 20); left:SetPoint("TOPLEFT", dialog.leftPanel, "TOPLEFT", 7, -7 - ((rowIndex - 1) * 22)); left.label:SetJustifyH("LEFT")
        local right = Raider.UI.Components.CreateButton(dialog.rightPanel, nil, "", 324, 20); right:SetPoint("TOPLEFT", dialog.rightPanel, "TOPLEFT", 7, -7 - ((rowIndex - 1) * 22)); right.label:SetJustifyH("LEFT"); right:RegisterForDrag("LeftButton")
        Raider.UI.Components.SetRowColor(left, warningRowColor, 1); Raider.UI.Components.SetRowColor(right, warningRowColor, 1)
        Raider.UI.Components.SetButtonLabelInsets(left, 6, 6); Raider.UI.Components.SetButtonLabelInsets(right, 6, 6)
        right.itemHit = Raider.UI.Components.CreateControl(nil, right)
        right.itemHit:SetHeight(20); right.itemHit:RegisterForDrag("LeftButton")
        right.itemHit:SetScript("OnEnter", ShowItemTooltip); right.itemHit:SetScript("OnLeave", HideItemTooltip)
        right.itemHit:SetScript("OnClick", HandleItemClick)
        dialog.leftRows[rowIndex] = left; dialog.rightRows[rowIndex] = right
    end
    dialog.save = Raider.UI.Components.CreateButton(dialog, nil, "Save", 78, 22); dialog.save:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -94, 8)
    dialog.close = Raider.UI.Components.CreateButton(dialog, nil, "Close", 78, 22); dialog.close:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -8, 8)
    dialog.ghost = Raider.UI.Components.CreateContainer(nil, UIParent); dialog.ghost:SetWidth(260); dialog.ghost:SetHeight(22)
    dialog.ghost:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } }); dialog.ghost:SetBackdropColor(0.12, 0.09, 0.03, 0.98)
    dialog.ghost.text = Raider.UI.Components.CreateLabel(dialog.ghost, nil, "OVERLAY", "GameFontHighlightSmall"); dialog.ghost.text:SetPoint("LEFT", dialog.ghost, "LEFT", 8, 0); dialog.ghost:Hide()
    dialog.ghost:SetScript("OnUpdate", function() local x, y = GetCursorPosition(); local scale = UIParent:GetEffectiveScale(); this:ClearAllPoints(); this:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale) end)

    local function CloseDialog() dialog.ghost:Hide(); dialog:Hide(); dismiss:Hide() end
    dialog.Close = CloseDialog
    local function BuildAvailable()
        local used = {}; local _, reservationName
        for _, reservationName in pairs(dialog.assignments) do used[string.lower(reservationName)] = true end
        dialog.available = {}; local count = 0
        local reservations = dialog.importInfo and dialog.importInfo.unmatchedReservations or {}
        local index
        for index = 1, table.getn(reservations) do if not used[string.lower(reservations[index].name or "")] then count = count + 1; dialog.available[count] = reservations[index] end end
    end
    local function RefreshDialog()
        BuildAvailable()
        dialog.leftOffset = math.max(0, math.min(math.max(0, table.getn(dialog.missing) - 12), dialog.leftOffset or 0))
        dialog.rightOffset = math.max(0, math.min(math.max(0, table.getn(dialog.available) - 12), dialog.rightOffset or 0))
        local index
        for index = 1, 12 do
            local memberName = dialog.missing[dialog.leftOffset + index]; local left = dialog.leftRows[index]; left.memberName = memberName
            if memberName then local assigned = dialog.assignments[memberName]; left.label:SetText(RaidManagement.SoftReservePlayerLabel(memberName, dialog.attendance) .. (assigned and ("  <-  " .. RaidManagement.SoftReservePlayerLabel(assigned, dialog.attendance, dialog.reservationByName and dialog.reservationByName[string.lower(assigned)])) or "")); left:Show() else left:Hide() end
            local reservation = dialog.available[dialog.rightOffset + index]; local right = dialog.rightRows[index]; right.reservation = reservation
            if reservation then
                right.itemId = reservation.itemIds and reservation.itemIds[1] or nil
                right.labelPrefix = RaidManagement.SoftReservePlayerLabel(reservation.name, dialog.attendance, reservation) .. "  -  "
                right.label:SetText(right.labelPrefix)
                local inset = math.min(260, right.label:GetStringWidth()) + 6
                local itemText = right.itemId and Raider.UI.Components.GetItemLabel(right.itemId) or "No item"
                right.label:SetText(itemText)
                local itemWidth = math.min(306 - inset, right.label:GetStringWidth())
                right.label:SetText(right.labelPrefix .. itemText)
                right.itemHit.itemId = right.itemId
                right.itemHit:ClearAllPoints(); right.itemHit:SetPoint("LEFT", right, "LEFT", inset, 0)
                right.itemHit:SetWidth(math.max(1,itemWidth)); right.itemHit:Show(); right:Show()
            else right.itemId = nil; right.labelPrefix = nil; right:Hide() end
        end
    end
    dialog.leftPanel:SetScript("OnMouseWheel", function() dialog.leftOffset = (dialog.leftOffset or 0) - arg1; RefreshDialog() end)
    dialog.rightPanel:SetScript("OnMouseWheel", function() dialog.rightOffset = (dialog.rightOffset or 0) - arg1; RefreshDialog() end)
    for rowIndex = 1, 12 do
        local left = dialog.leftRows[rowIndex]; left:SetScript("OnClick", function() if this.memberName and dialog.assignments[this.memberName] then dialog.assignments[this.memberName] = nil; RefreshDialog() end end)
        local right = dialog.rightRows[rowIndex]
        right:SetScript("OnEnter", nil); right:SetScript("OnLeave", HideItemTooltip)
        right:SetScript("OnDragStart", function() if this.reservation then dialog.dragged = this.reservation; dialog.ghost.text:SetText(this.label:GetText() or this.reservation.name); dialog.ghost:Show() end end)
        right:SetScript("OnDragStop", function()
            dialog.ghost:Hide(); if not dialog.dragged then return end
            local targetIndex
            for targetIndex = 1, 12 do local target = dialog.leftRows[targetIndex]; if target.memberName and IsCursorOverFrame(target) then dialog.assignments[target.memberName] = dialog.dragged.name; break end end
            dialog.dragged = nil; RefreshDialog()
        end)
    end
    for _, row in ipairs(dialog.rightRows) do
        local owner = row
        for _, script in ipairs({"OnDragStart", "OnDragStop"}) do
            local handler = owner:GetScript(script)
            owner.itemHit:SetScript(script, function() local previous=this; this=owner; handler(); this=previous end)
        end
    end
    dismiss:SetScript("OnClick", CloseDialog); dialog.close:SetScript("OnClick", CloseDialog)
    dialog.save:SetScript("OnClick", function() if applyAssignments(dialog.attendance, dialog.assignments) then CloseDialog(); refresh() end end)
    dialog.Open = function(self, attendance)
        local importInfo = attendance and attendance.softReserveImport
        if not importInfo or not importInfo.missingNames or not importInfo.unmatchedReservations then return end
        self.attendance = attendance; self.importInfo = importInfo; self.missing = importInfo.missingNames; self.assignments = {}; self.leftOffset = 0; self.rightOffset = 0
        self.reservationByName = {}
        for _, reservation in ipairs(importInfo.unmatchedReservations) do self.reservationByName[string.lower(reservation.name or "")] = reservation end
        CenterOnScreen(self); RefreshDialog(); dismiss:Show(); self:Show()
    end
    page.softReserveFixDialog = dialog
    if Raider.UI.Components.WindowStack then
        local stack = Raider.UI.Components.WindowStack
        stack.Register(dialog, {owner = page, dismiss = dismiss})
        stack.Attach(dialog.ghost, dialog, 100)
    end
end
