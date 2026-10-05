local Raider = BootyRaider
local UI = Raider.UI.Components

Raider.Modules = Raider.Modules or {}
local RaidStatistics = {}
Raider.Modules.RaidStatistics = RaidStatistics

local function OnRaidSelect()
    local controller = this.statisticsController
    controller.editMode=false;controller.editMembers=nil
    if controller.selectedHistoryIds[this.raidId] then controller.selectedHistoryIds[this.raidId] = nil
    else controller.selectedHistoryIds[this.raidId] = true end
    controller.summaryDirty = true
    controller:Render()
end

local function CopyItems(source)
    local target,index={},nil
    for index=1,table.getn(source or {}) do local item={};local key,value;for key,value in pairs(source[index]) do item[key]=value end;target[index]=item end
    return target
end

local function CopyEditableMember(source)
    local target={};local key,value
    for key,value in pairs(source or {}) do if key~="srItems" and key~="lootItems" then target[key]=value end end
    target.srItems=CopyItems(source and source.srItems);target.lootItems=CopyItems(source and source.lootItems)
    target.attendance=tonumber(target.attendance);if target.attendance==nil then target.attendance=1 end
    target.attendanceText=tostring(target.attendance)
    target.srItemText=tostring(target.srItems[1] and target.srItems[1].itemId or "")
    return target
end

local function UpdateEditMember(row)
    local member=row and row.editMember
    if not member or row.bindingEditMember then return end
    member.name=row.nameEdit:GetText() or ""
    member.attendanceText=row.attendanceEdit:GetText() or ""
    member.srItemText=row.srEdit:GetText() or ""
end

local function OnItemsClick()
    if this.inactive or not this.ownerRow or not this.ownerRow.player then return end
    local player = this.ownerRow.player
    local items = this.itemKind == "sr" and player.srItems or player.lootItems
    local kind = this.itemKind == "sr" and "Soft Reserves" or "Loot received"
    this.statisticsController.itemDialog:Open(kind .. " - " .. tostring(player.name or "Player"), items)
end

local function OnDirectItemEnter()
    Raider.UI.Components.ShowItemTooltip(this)
end

function RaidStatistics.Create(host, getEntries, deleteEntry, updateEntry)
    local page=UI.CreateResponsiveCanvas(host,"BootyRaiderRaidStatisticsPage")
    local isHostVisible = host.IsVisible or host.IsShown
    local controller = { page = page, getEntries = getEntries, deleteEntry = deleteEntry, updateEntry = updateEntry, selectedHistoryIds = {}, raidButtons = {}, rows = {}, filteredEntries = {}, selectedRaids = {}, visibleHistoryIds = {}, modelDirty = true, summaryDirty = true, emptySummary = { players = {} } }
    page.statisticsController = controller
    host.statisticsController = controller
    controller.itemDialog = Raider.UI.Components.CreateItemListDialog("BootyRaiderRaidStatisticsItems")
    controller.title = Raider.UI.Components.CreateHeading(page, "", 1, "gold", "raid_stats"); controller.title:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -10); controller.title:SetText("Raid Statistics")
    local raidNames = Raider.Services.RaidStatistics.GetRaidNames(); local raidNameIndex
    for raidNameIndex = 1, table.getn(raidNames) do controller.selectedRaids[raidNames[raidNameIndex]] = true end
    controller.filterPanel = Raider.UI.Components.CreateContainer(nil, page); controller.filterPanel:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -40); controller.filterPanel:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -40); controller.filterPanel:SetHeight(66)
    controller.filterPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } }); controller.filterPanel:SetBackdropColor(0.035, 0.03, 0.02, 0.94); controller.filterPanel:SetBackdropBorderColor(0.42, 0.34, 0.18, 1)
    controller.filterTitle = Raider.UI.Components.CreateLabel(controller.filterPanel, nil, "OVERLAY", "GameFontNormalSmall"); controller.filterTitle:SetPoint("TOPLEFT", controller.filterPanel, "TOPLEFT", 10, -8); controller.filterTitle:SetText("Filters")
    Raider.UI.Components.SetHeadingIcon(controller.filterTitle,"list")
    controller.raidFilter = Raider.UI.Components.CreateDropdownButton(controller.filterPanel, nil, "Raid", 140); controller.raidFilter:SetPoint("TOPLEFT", controller.filterPanel, "TOPLEFT", 62, -6)
    controller.raidPanel = Raider.UI.Components.CreateDropdownPanel(controller.filterPanel, controller.raidFilter, 190, 178, 20)
    controller.raidDismiss = controller.raidPanel.dismiss
    controller.raidFilter:SetScript("OnClick", function() if controller.raidPanel:IsVisible() then controller.raidPanel:Hide() else controller.datePicker:Hide();controller.raidPanel:Show() end end)
    UI.FilterPanel.Refresh(controller.raidPanel,raidNames,controller.selectedRaids,function() controller:Refresh() end,true,true)
    controller.raidChecks=controller.raidPanel.options
    controller.listTitle = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontNormal"); controller.listTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -120); controller.listTitle:SetText("Raids")
    Raider.UI.Components.SetHeadingIcon(controller.listTitle,"archive")
    controller.historyToggle = Raider.UI.Components.CreateButton(page, nil, "", 18, 18)
    Raider.UI.Components.SetClassicButtonCompact(controller.historyToggle, true); Raider.UI.Components.AttachGoldHoverBorder(controller.historyToggle, 0.35, 0.35, 0.35, 1)
    UI.SetChevronButtonIcon(controller.historyToggle,"left",11)
    Raider.UI.Components.AttachTooltip(controller.historyToggle, "Saved raids", "Collapse or restore the saved raid list.")
    controller.historyToggle:SetScript("OnClick", function() controller.historyCollapsed = not controller.historyCollapsed; controller:Render() end)
    controller.historyHeaders = {}
    for index, text in ipairs({"Name", "Raid", "Time"}) do controller.historyHeaders[index] = Raider.UI.Components.CreateColumnLabel(page, text, "gold") end
    controller.fromLabel = Raider.UI.Components.CreateLabel(controller.filterPanel, nil, "OVERLAY", "GameFontHighlightSmall"); controller.fromLabel:SetPoint("TOPLEFT", controller.filterPanel, "TOPLEFT", 10, -38); controller.fromLabel:SetText("From")
    controller.fromDate = Raider.UI.Components.CreateFramedEditBox(controller.filterPanel, nil, 80); controller.fromDate:SetPoint("TOPLEFT", controller.filterPanel, "TOPLEFT", 48, -33); controller.fromDate:SetMaxLetters(10); controller.fromDate:EnableKeyboard(false)
    controller.datePicker = Raider.UI.Components.CreateDatePicker("BootyRaiderRaidStatisticsDatePicker")
    controller.dateDismiss = Raider.UI.Components.CreateControl(nil, UIParent); controller.dateDismiss:SetAllPoints(UIParent); controller.dateDismiss:SetFrameStrata("FULLSCREEN_DIALOG"); controller.dateDismiss:SetFrameLevel(3); controller.dateDismiss:Hide()
    controller.datePicker:SetFrameStrata("FULLSCREEN_DIALOG"); controller.datePicker:SetFrameLevel(4)
    local function CloseDatePicker() controller.datePicker:Hide(); controller.dateDismiss:Hide() end
    local function ToggleDatePicker(anchor, target)
        if controller.datePicker:IsShown() then CloseDatePicker() else
            controller.raidPanel:Hide()
            local level=math.max(230,page:GetFrameLevel()+30)
            controller.dateDismiss:SetFrameLevel(level);controller.datePicker:SetFrameLevel(level+1)
            controller.dateDismiss:Show(); controller.datePicker:Open(anchor, target)
        end
    end
    controller.dateDismiss:SetScript("OnClick", CloseDatePicker)
    local datePickerOnHide = controller.datePicker:GetScript("OnHide")
    controller.datePicker:SetScript("OnHide", function() if datePickerOnHide then datePickerOnHide() end; controller.dateDismiss:Hide() end)
    controller.fromPicker = Raider.UI.Components.CreateIconButton(controller.filterPanel, nil, "Interface\\Icons\\INV_Misc_PocketWatch_01", 20, 2); controller.fromPicker:SetPoint("LEFT", controller.fromDate, "RIGHT", 2, 0)
    controller.fromPicker:SetScript("OnClick", function() ToggleDatePicker(this, controller.fromDate) end)
    controller.toLabel = Raider.UI.Components.CreateLabel(controller.filterPanel, nil, "OVERLAY", "GameFontHighlightSmall"); controller.toLabel:SetPoint("LEFT", controller.fromPicker, "RIGHT", 7, 0); controller.toLabel:SetText("To")
    controller.toDate = Raider.UI.Components.CreateFramedEditBox(controller.filterPanel, nil, 80); controller.toDate:SetPoint("LEFT", controller.toLabel, "RIGHT", 7, 0); controller.toDate:SetMaxLetters(10); controller.toDate:EnableKeyboard(false)
    controller.toPicker = Raider.UI.Components.CreateIconButton(controller.filterPanel, nil, "Interface\\Icons\\INV_Misc_PocketWatch_01", 20, 2); controller.toPicker:SetPoint("LEFT", controller.toDate, "RIGHT", 2, 0)
    controller.toPicker:SetScript("OnClick", function() ToggleDatePicker(this, controller.toDate) end)
    controller.searchLabel = Raider.UI.Components.CreateLabel(controller.filterPanel, nil, "OVERLAY", "GameFontHighlightSmall"); controller.searchLabel:SetPoint("LEFT", controller.raidFilter, "RIGHT", 14, 0); controller.searchLabel:SetText("Search")
    controller.search = Raider.UI.Components.CreateFramedEditBox(controller.filterPanel, nil, 160); controller.search:SetPoint("LEFT", controller.searchLabel, "RIGHT", 6, 0); controller.search:SetScript("OnTextChanged", function() controller:Refresh() end);Raider.UI.Components.AttachPlaceholder(controller.search,"Search...");controller.searchLabel:SetText("");controller.searchLabel:Hide()
    controller.fromDate:SetScript("OnMouseDown", function() ToggleDatePicker(this, controller.fromDate) end); controller.toDate:SetScript("OnMouseDown", function() ToggleDatePicker(this, controller.toDate) end)
    Raider.UI.Components.AttachTooltip(controller.fromDate, "From date", "Optional date in YYYY-MM-DD format."); Raider.UI.Components.AttachTooltip(controller.toDate, "To date", "Optional date in YYYY-MM-DD format.")
    Raider.UI.Components.AttachTooltip(controller.fromPicker, "Choose From date", "Open the calendar."); Raider.UI.Components.AttachTooltip(controller.toPicker, "Choose To date", "Open the calendar.")
    controller.filterStatus = Raider.UI.Components.CreateHeading(page, "", 1, "gold", "raid_stats"); controller.filterStatus:SetPoint("TOPLEFT", page, "TOPLEFT", 260, -120); controller.filterStatus:SetPoint("TOPRIGHT", page, "TOPRIGHT", -72, -120); controller.filterStatus:SetJustifyH("LEFT")
    controller.headerRemove = Raider.UI.Components.CreateDeleteButton(page, nil, 22, 2); controller.headerRemove:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -115); controller.headerRemove.statisticsController = controller; Raider.UI.Components.AttachGoldHoverBorder(controller.headerRemove, 0.35, 0.35, 0.35, 1); Raider.UI.Components.AttachTooltip(controller.headerRemove, "Remove raid", "Remove the selected raid from Raid Statistics and CSR history."); controller.headerRemove:Hide()
    controller.headerEdit = Raider.UI.Components.CreateIconButton(page, nil, "Interface\\Icons\\INV_Misc_Note_01", 22, 2); controller.headerEdit:SetPoint("RIGHT", controller.headerRemove, "LEFT", -5, 0); controller.headerEdit.statisticsController = controller; Raider.UI.Components.AttachGoldHoverBorder(controller.headerEdit, 0.35, 0.35, 0.35, 1); Raider.UI.Components.AttachTooltip(controller.headerEdit, "Edit raid", "Edit statistics options for the selected raid."); controller.headerEdit:Hide()
    controller.editAdd=UI.CreateButton(page,nil,"Add Entry",82,22);controller.editSave=UI.CreateButton(page,nil,"Save",62,22);controller.editCancel=UI.CreateButton(page,nil,"Cancel",68,22)
    for _,button in ipairs({controller.editAdd,controller.editSave,controller.editCancel}) do UI.StyleActionButton(button);button:Hide() end
    controller.editError=UI.CreateLabel(page,nil,"OVERLAY","GameFontHighlightSmall");controller.editError:SetTextColor(1,0.35,0.30);controller.editError:SetJustifyH("RIGHT");controller.editError:Hide()
    controller.raidScroll = Raider.UI.Components.CreateScrollFrame("BootyRaiderRaidStatisticsHistoryScroll", page, "FauxScrollFrameTemplate"); controller.raidScroll:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -140); controller.raidScroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", 246, 5)
    Raider.UI.Components.RegisterSkinnedScrollBar(getglobal("BootyRaiderRaidStatisticsHistoryScrollScrollBar"))
    controller.raidScroll.refreshCallback = function() controller:RenderHistory() end; controller.raidScroll:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(28, this.refreshCallback) end)
    local index
    for index = 1, 20 do
        local button = Raider.UI.Components.CreateSelectionButton(page, nil, "", 234, 26); button:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -144 - ((index - 1) * 28)); button.statisticsController = controller; button:SetScript("OnClick", OnRaidSelect); button.label:Hide()
        button.allText = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontHighlightSmall"); button.allText:SetPoint("LEFT", button, "LEFT", 8, 0); button.allText:SetPoint("RIGHT", button, "RIGHT", -8, 0); button.allText:SetJustifyH("LEFT")
        button.idText = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontHighlightSmall"); button.idText:SetPoint("LEFT", button, "LEFT", 8, 0); button.idText:SetWidth(42); button.idText:SetJustifyH("LEFT")
        button.zoneText = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontHighlightSmall"); button.zoneText:SetPoint("LEFT", button, "LEFT", 51, 0); button.zoneText:SetWidth(57); button.zoneText:SetJustifyH("LEFT")
        button.dateText = Raider.UI.Components.CreateLabel(button, nil, "OVERLAY", "GameFontDisableSmall"); button.dateText:SetPoint("RIGHT", button, "RIGHT", -91, 0); button.dateText:SetWidth(55); button.dateText:SetJustifyH("RIGHT")
        UI.AttachTooltip(button,"Saved raid",function() return this.allText:GetText() end)
        button:Hide(); controller.raidButtons[index] = button
    end
    local function CreateModal(name, title, height)
        local dialog = Raider.UI.Components.CreateContainer(name, UIParent)
        dialog:SetWidth(360); dialog:SetHeight(height); dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG"); dialog:SetFrameLevel(245); dialog:EnableMouse(true)
        dialog:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        dialog:SetBackdropColor(0.03, 0.025, 0.02, 1)
        if dialog.SetClampedToScreen then dialog:SetClampedToScreen(true) end
        dialog.title = Raider.UI.Components.CreateHeading(dialog, "", 1, "gold", "raid_stats"); dialog.title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -17); dialog.title:SetText(title)
        dialog:Hide(); return dialog
    end
    controller.removeDialog = CreateModal("BootyRaiderRemoveRaidStatisticDialog", "Remove raid from history?", 145)
    controller.removeDialog.message = Raider.UI.Components.CreateLabel(controller.removeDialog, nil, "OVERLAY", "GameFontHighlight")
    controller.removeDialog.message:SetPoint("TOPLEFT", controller.removeDialog, "TOPLEFT", 18, -50); controller.removeDialog.message:SetWidth(324); controller.removeDialog.message:SetJustifyH("LEFT")
    controller.removeDialog.cancel = Raider.UI.Components.CreateButton(controller.removeDialog, nil, "Cancel", 86, 24); controller.removeDialog.cancel:SetPoint("BOTTOMLEFT", controller.removeDialog, "BOTTOMLEFT", 72, 18)
    controller.removeDialog.remove = Raider.UI.Components.CreateButton(controller.removeDialog, nil, "Remove", 86, 24); controller.removeDialog.remove:SetPoint("BOTTOMRIGHT", controller.removeDialog, "BOTTOMRIGHT", -72, 18)
    controller.removeDialog.cancel:SetScript("OnClick", function() controller.removeDialog:Hide() end)
    controller.removeDialog.remove:SetScript("OnClick", function()
        local raidId = controller.removeDialog.raidId
        controller.removeDialog:Hide()
        if raidId and controller.deleteEntry and controller.deleteEntry(raidId) then
            controller.selectedHistoryIds[raidId] = nil
            controller:Refresh()
        end
    end)
    controller.editDialog = CreateModal("BootyRaiderEditRaidStatisticDialog", "Save raid changes", 205)
    local function CreateEditCheckbox(label, y)
        local checkbox = Raider.UI.Components.CreateCheckButton(nil, controller.editDialog, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", controller.editDialog, "TOPLEFT", 18, y); checkbox:SetWidth(22); checkbox:SetHeight(22)
        checkbox.label = Raider.UI.Components.CreateLabel(controller.editDialog, nil, "OVERLAY", "GameFontHighlightSmall"); checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 3, 0); checkbox.label:SetText(label)
        return checkbox
    end
    controller.editDialog.message=UI.CreateLabel(controller.editDialog,nil,"OVERLAY","GameFontHighlightSmall");controller.editDialog.message:SetPoint("TOPLEFT",controller.editDialog,"TOPLEFT",18,-46);controller.editDialog.message:SetWidth(324);controller.editDialog.message:SetText("Save the edited attendance and Soft Reserve values for this raid?")
    controller.editDialog.attendance = CreateEditCheckbox("Save Attendance", -86)
    controller.editDialog.csr = CreateEditCheckbox("Save CSR", -116)
    controller.editDialog.cancel = Raider.UI.Components.CreateButton(controller.editDialog, nil, "Cancel", 86, 24); controller.editDialog.cancel:SetPoint("BOTTOMLEFT", controller.editDialog, "BOTTOMLEFT", 72, 18)
    controller.editDialog.save = Raider.UI.Components.CreateButton(controller.editDialog, nil, "Save", 86, 24); controller.editDialog.save:SetPoint("BOTTOMRIGHT", controller.editDialog, "BOTTOMRIGHT", -72, 18)
    controller.editDialog.cancel:SetScript("OnClick", function() controller.editDialog:Hide() end)
    controller.editDialog.save:SetScript("OnClick", function()
        local raidId = controller.editDialog.raidId
        local attendanceEnabled = controller.editDialog.attendance:GetChecked() and true or false
        local csrEnabled = controller.editDialog.csr:GetChecked() and true or false
        controller.editDialog:Hide()
        if raidId and controller.updateEntry then
            local members, memberIndex = {}, nil
            for memberIndex = 1, table.getn(controller.editMembers or {}) do
                local member = CopyEditableMember(controller.editMembers[memberIndex])
                member.attendanceText = nil; member.srItemText = nil
                members[memberIndex] = member
            end
            if controller.updateEntry(raidId,members,attendanceEnabled,csrEnabled) then controller.editMode=false;controller.editMembers=nil;controller:Refresh() end
        end
    end)
    local function OnEditRaid()
        local raidId = this.raidId
        local entries = controller.getEntries()
        local entry, entryIndex
        for entryIndex = 1, table.getn(entries) do if entries[entryIndex].id == raidId then entry = entries[entryIndex]; break end end
        if not entry then return end
        controller.editingEntry=entry;controller.editingRaidId=raidId;controller.editMembers={}
        for entryIndex=1,table.getn(entry.members or {}) do controller.editMembers[entryIndex]=CopyEditableMember(entry.members[entryIndex]) end
        controller.editMode=true;controller.editError:Hide();controller:Render()
    end
    local function OnRemoveRaid()
        controller.removeDialog.raidId = this.raidId
        controller.removeDialog.message:SetText("Remove raid " .. tostring(this.raidId or "") .. " from Raid Statistics and CSR history?")
        local messageHeight=math.max(32,UI.MeasureTextHeight(controller.removeDialog.message,controller.removeDialog:GetWidth()-16))
        controller.removeDialog.message:SetHeight(messageHeight);controller.removeDialog:SetHeight(messageHeight+78)
        controller.removeDialog:Show()
    end
    controller.headerEdit:SetScript("OnClick", OnEditRaid); controller.headerRemove:SetScript("OnClick", OnRemoveRaid)
    controller.editCancel:SetScript("OnClick",function() controller.editMode=false;controller.editMembers=nil;controller.editError:Hide();controller:Render() end)
    controller.editAdd:SetScript("OnClick",function()
        local member={name="",class="",guildRank="Guest",lootRank="Guest",attendance=1,attendanceText="1",srItemText="",srCount=0,lootCount=0,srItems={},lootItems={}}
        table.insert(controller.editMembers,member);controller.scroll.offset=math.max(0,table.getn(controller.editMembers)-table.getn(controller.rows));controller:Render()
    end)
    controller.editSave:SetScript("OnClick",function()
        local rowIndex
        for rowIndex=1,table.getn(controller.rows) do UpdateEditMember(controller.rows[rowIndex]) end
        for rowIndex=1,table.getn(controller.editMembers or {}) do
            local member=controller.editMembers[rowIndex];local name=string.gsub(tostring(member.name or ""),"^%s+","");name=string.gsub(name,"%s+$","")
            local attendance=tonumber(member.attendanceText or member.attendance);local itemText=string.gsub(tostring(member.srItemText or ""),"%s","");local itemId=itemText~="" and tonumber(itemText) or nil
            if name=="" then controller.editError:SetText("Player name is required.");controller.editError:Show();return end
            if not attendance or attendance<0 then controller.editError:SetText("Attendance must be a non-negative number.");controller.editError:Show();return end
            if itemText~="" and not itemId then controller.editError:SetText("SR must contain a numeric Item ID.");controller.editError:Show();return end
            member.name=name;member.attendance=attendance;member.attendanceText=tostring(attendance);member.srItemText=itemId and tostring(itemId) or "";member.srItems=itemId and {{itemId=itemId,count=1}} or {};member.srCount=itemId and 1 or 0
        end
        controller.editError:Hide();controller.editDialog.raidId=controller.editingRaidId;controller.editDialog.attendance:SetChecked(controller.editingEntry.attendanceEnabled~=false and 1 or nil);controller.editDialog.csr:SetChecked(controller.editingEntry.csrEnabled~=false and 1 or nil);controller.editDialog:Show()
    end)
    UI.Window.StyleProjectDialog(controller.removeDialog); UI.Window.StyleProjectDialog(controller.editDialog)
    controller.playerHeader = Raider.UI.Components.Table.CreateHeader(page, nil, "Player", 264, -150, 120, nil, false)
    controller.attendanceHeader = Raider.UI.Components.Table.CreateHeader(page, nil, "Attendance", 386, -150, 66, nil, false)
    controller.srHeader = Raider.UI.Components.Table.CreateHeader(page, nil, "SR", 454, -150, 50, nil, false)
    controller.lootHeader = Raider.UI.Components.Table.CreateHeader(page, nil, "Loot", 0, -150, 28, nil, false)
    controller.lootHeader:ClearAllPoints(); controller.lootHeader:SetPoint("TOPRIGHT", page, "TOPRIGHT", -32, -150)
    controller.playerHeader:SetHeight(18); controller.attendanceHeader:SetHeight(18); controller.srHeader:SetHeight(18); controller.lootHeader:SetHeight(18)
    controller.scroll = Raider.UI.Components.CreateScrollFrame("BootyRaiderRaidStatisticsScroll", page, "FauxScrollFrameTemplate"); controller.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 260, -166); controller.scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -22, 5)
    Raider.UI.Components.RegisterSkinnedScrollBar(getglobal("BootyRaiderRaidStatisticsScrollScrollBar"))
    controller.scroll.refreshCallback = function() controller:RenderRows() end; controller.scroll:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(24, this.refreshCallback) end)
    for index = 1, 25 do
        local row = Raider.UI.Components.CreateContainer(nil, page); row:SetPoint("TOPLEFT", page, "TOPLEFT", 264, -170 - ((index - 1) * 24)); row:SetPoint("RIGHT", page, "RIGHT", -26, 0); row:SetHeight(23)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); row:SetBackdropColor(0, 0, 0, 0)
        Raider.UI.Components.RegisterSkinnedSurface(row, "row", { bgFile = "Interface\\Buttons\\WHITE8X8" }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
        row.name = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", row, "LEFT", 0, 0); row.name:SetWidth(112); row.name:SetJustifyH("LEFT")
        row.attendance = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall"); row.attendance:SetPoint("LEFT", row, "LEFT", 122, 0); row.attendance:SetWidth(58)
        row.sr = Raider.UI.Components.CreateIconButton(row, nil, "Interface\\Icons\\INV_Misc_Note_01", 20, 2); row.sr:SetPoint("LEFT", row, "LEFT", 190, 0); row.sr.ownerRow = row; row.sr.itemKind = "sr"; row.sr.statisticsController = controller; row.sr:SetScript("OnClick", OnItemsClick)
        row.srDirect = Raider.UI.Components.CreateControl(nil, row); row.srDirect:SetPoint("LEFT", row, "LEFT", 190, 0); row.srDirect:SetPoint("RIGHT", row, "RIGHT", -42, 0); row.srDirect:SetHeight(22)
        row.srDirect.iconRegion = Raider.UI.Components.CreateTexture(row.srDirect, nil, "ARTWORK"); row.srDirect.iconRegion:SetPoint("LEFT", row.srDirect, "LEFT", 0, 0); row.srDirect.iconRegion:SetWidth(19); row.srDirect.iconRegion:SetHeight(19)
        row.srDirect.label = Raider.UI.Components.CreateLabel(row.srDirect, nil, "OVERLAY", "GameFontHighlightSmall"); row.srDirect.label:SetPoint("LEFT", row.srDirect.iconRegion, "RIGHT", 5, 0); row.srDirect.label:SetPoint("RIGHT", row.srDirect, "RIGHT", 0, 0); row.srDirect.label:SetJustifyH("LEFT")
        row.srDirect:SetScript("OnEnter", OnDirectItemEnter); row.srDirect:SetScript("OnLeave", function() GameTooltip:Hide() end); row.srDirect:SetScript("OnClick", function() Raider.UI.Components.HandleItemClick(this) end); row.srDirect:Hide()
        row.srMissing = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall"); row.srMissing:SetPoint("LEFT", row, "LEFT", 190, 0); row.srMissing:SetText("-"); row.srMissing:Hide()
        row.loot = Raider.UI.Components.CreateIconButton(row, nil, "Interface\\Icons\\INV_Misc_Bag_10", 20, 2); row.loot:SetPoint("RIGHT", row, "RIGHT", -8, 0); row.loot.ownerRow = row; row.loot.itemKind = "loot"; row.loot.statisticsController = controller; row.loot:SetScript("OnClick", OnItemsClick)
        row.nameEdit=UI.CreateFramedEditBox(row,nil,110);row.nameEdit.ownerRow=row;row.nameEdit:SetScript("OnTextChanged",function() UpdateEditMember(this.ownerRow) end);row.nameEdit:Hide()
        row.attendanceEdit=UI.CreateFramedEditBox(row,nil,54);row.attendanceEdit.ownerRow=row;row.attendanceEdit:SetMaxLetters(8);row.attendanceEdit:SetScript("OnTextChanged",function() UpdateEditMember(this.ownerRow) end);row.attendanceEdit:Hide()
        row.srEdit=UI.CreateFramedEditBox(row,nil,70);row.srEdit.ownerRow=row;row.srEdit:SetMaxLetters(10);row.srEdit:SetScript("OnTextChanged",function() UpdateEditMember(this.ownerRow) end);row.srEdit:Hide()
        Raider.UI.Components.AttachTooltip(row.sr, "Soft Reserves", "Show every item reserved by this player in the selected raids."); Raider.UI.Components.AttachTooltip(row.loot, "Loot received", "Show every recorded item received by this player in the selected raids.")
        row:Hide(); controller.rows[index] = row
    end
    UI.StyleProjectPopup(controller.raidPanel); UI.StyleProjectPopup(controller.datePicker)
    for _,button in ipairs(controller.datePicker.days) do UI.ApplyDropdownChoiceSurface(button);UI.AttachGoldHoverBorder(button,0.35,0.35,0.35,1) end
    UI.ApplyDropdownChoiceSurface(controller.datePicker.previous);UI.ApplyDropdownChoiceSurface(controller.datePicker.next)
    UI.RegisterSkinnedSurface(controller.filterPanel,"content")
    UI.SetSurfaceHorizontalBorders(controller.filterPanel,true,true)
    controller.filterTitle:Hide()
    local function Group(width)
        local group=UI.CreateContainer(nil,controller.filterPanel);group:SetWidth(width);group:SetHeight(26);group.mosFlowWidth=width;return group
    end
    controller.searchGroup=Group(166)
    controller.searchLabel:Hide()
    controller.search:SetParent(controller.searchGroup);controller.search:ClearAllPoints();controller.search:SetPoint("LEFT",controller.searchGroup,"LEFT",0,0);controller.search:SetWidth(166)
    controller.fromGroup=Group(130);controller.toGroup=Group(114)
    for _,key in ipairs({"from","to"}) do
        local group=controller[key.."Group"];local label=controller[key.."Label"];local field=controller[key.."Date"];local picker=controller[key.."Picker"]
        label:ClearAllPoints();label:SetPoint("LEFT",group,"LEFT",0,0)
        field:SetParent(group);field:ClearAllPoints();field:SetPoint("LEFT",group,"LEFT",key=="from" and 32 or 16,0);field:SetWidth(76)
        picker:SetParent(group);picker:ClearAllPoints();picker:SetPoint("LEFT",field,"RIGHT",2,0);picker:SetWidth(18);picker:SetHeight(18)
    end
    controller.raidFilter:SetHeight(26);controller.raidFilter.mosFlowWidth=130
    controller.flow={controller.raidFilter,controller.searchGroup,controller.fromGroup,controller.toGroup}
    for _,dialog in ipairs({controller.removeDialog,controller.editDialog}) do
        dialog:SetWidth(320)
        if not dialog.close then dialog.close=UI.CreateWindowButton(dialog,nil,"close");dialog.close:SetPoint("TOPRIGHT",dialog,"TOPRIGHT",-6,-6);dialog.close:SetScript("OnClick",function() this:GetParent():Hide() end) end
        local action=dialog.remove or dialog.save
        UI.StyleActionButton(action);UI.StyleActionButton(dialog.cancel)
        action:ClearAllPoints();action:SetPoint("BOTTOMRIGHT",dialog,"BOTTOMRIGHT",-8,8)
        dialog.cancel:ClearAllPoints();dialog.cancel:SetPoint("RIGHT",action,"LEFT",-8,0)
    end
    controller.removeDialog.message:ClearAllPoints();controller.removeDialog.message:SetPoint("TOPLEFT",controller.removeDialog,"TOPLEFT",8,-36);controller.removeDialog.message:SetWidth(304);controller.removeDialog.message:SetJustifyH("CENTER")
    controller.editDialog.message:ClearAllPoints();controller.editDialog.message:SetPoint("TOPLEFT",controller.editDialog,"TOPLEFT",8,-36);controller.editDialog.message:SetWidth(304)
    controller.editDialog.attendance:ClearAllPoints();controller.editDialog.attendance:SetPoint("TOPLEFT",controller.editDialog,"TOPLEFT",8,-84)
    controller.editDialog.csr:ClearAllPoints();controller.editDialog.csr:SetPoint("TOPLEFT",controller.editDialog,"TOPLEFT",8,-114)
    UI.BindCheckboxLabel(controller.editDialog.attendance,function() end);UI.BindCheckboxLabel(controller.editDialog.csr,function() end)
    controller.editDialog:SetHeight(178)
    controller.datePicker:SetHeight(236)
    controller.datePicker.clear=UI.CreateButton(controller.datePicker,nil,"Clear date",100,26)
    UI.StyleActionButton(controller.datePicker.clear)
    controller.datePicker.clear:SetPoint("BOTTOMRIGHT",controller.datePicker,"BOTTOMRIGHT",-8,8)
    controller.datePicker.clear:SetScript("OnClick",function()
        if controller.datePicker.target then controller.datePicker.target:SetText("") end
        controller.datePicker:Hide()
        controller.raidScroll.offset=0;controller.scroll.offset=0;controller:Refresh()
    end)
    controller.datePicker.OnDateSelected=function()
        controller.raidScroll.offset=0;controller.scroll.offset=0;controller:Refresh()
    end
    controller.emptyHistory=UI.CreateLabel(page,nil,"OVERLAY","GameFontDisableSmall");controller.emptyHistory:SetText("No matching saved raids.")
    controller.emptyPlayers=UI.CreateLabel(page,nil,"OVERLAY","GameFontDisableSmall");controller.emptyPlayers:SetText("No matching players.")
    UI.AttachLabelTooltip(page,controller.filterStatus,"Selected raids",function() return controller.filterStatus:GetText() end)
    controller.headers={controller.playerHeader,controller.attendanceHeader,controller.srHeader,controller.lootHeader}
    local function LayoutContent(width,height,self)
        local available=math.max(80,width-16)
        self.title:ClearAllPoints();self.title:SetPoint("TOPLEFT",page,"TOPLEFT",8,-8);UI.FitButtonLabel(self.title,available)
        self.filterPanel:ClearAllPoints();self.filterPanel:SetPoint("TOPLEFT",page,"TOPLEFT",0,-38);self.filterPanel:SetWidth(width)
        local filterBottom=UI.LayoutFlow(self.filterPanel,self.flow,4,8,available,6)+8
        self.filterPanel:SetHeight(filterBottom)
        self.search:SetWidth(math.max(24,self.searchGroup:GetWidth()))
        for _,key in ipairs({"from","to"}) do
            self[key.."Date"]:SetWidth(math.max(24,self[key.."Group"]:GetWidth()-(key=="from" and 54 or 38)))
        end
        local top=38+filterBottom+8
        local stacked=available<650
        local historyWidth=stacked and available or math.min(270,available*0.34)
        local remaining=math.max(96,height-top-8)
        local historyHeight=stacked and math.max(56,math.min(84,math.floor((remaining-100)/28)*28)) or remaining-44
        self.listTitle:ClearAllPoints();self.listTitle:SetPoint("TOPLEFT",page,"TOPLEFT",8,-top);self.listTitle:SetWidth(historyWidth);self.listTitle:SetJustifyH("LEFT")
        self.historyToggle:SetWidth(18);self.historyToggle:SetHeight(18);self.historyToggle:ClearAllPoints();self.historyToggle:SetPoint("TOPLEFT",page,"TOPLEFT",8+historyWidth-18,-top);UI.SetChevronButtonIcon(self.historyToggle,self.historyCollapsed and "right" or "left",11)
        local headerX=8
        local headerName=math.floor(historyWidth*0.38);local headerRaid=math.floor(historyWidth*0.34);local headerTime=historyWidth-headerName-headerRaid
        local headerWidths={headerName,headerRaid,headerTime}
        for index=1,3 do local header=self.historyHeaders[index];header:ClearAllPoints();header:SetPoint("TOPLEFT",page,"TOPLEFT",headerX,-top-24);header:SetWidth(headerWidths[index]);header:SetHeight(18);headerX=headerX+headerWidths[index] end
        self.historyRect=self.historyRect or {}
        self.historyRect.x=8;self.historyRect.y=top+44;self.historyRect.width=historyWidth;self.historyRect.height=historyHeight
        local playerX=self.historyCollapsed and 34 or (stacked and 8 or 8+historyWidth+12)
        local playerTop=self.historyCollapsed and top or (stacked and top+44+historyHeight+8 or top)
        local playerWidth=self.historyCollapsed and math.max(1,available-26) or (stacked and available or available-historyWidth-12)
        if self.historyCollapsed then
            self.listTitle:Hide();self.historyToggle:ClearAllPoints();self.historyToggle:SetPoint("TOPLEFT",page,"TOPLEFT",8,-top)
            for index=1,3 do self.historyHeaders[index]:Hide() end
        else self.listTitle:Show();for index=1,3 do self.historyHeaders[index]:Show() end end
        local statusHeight=self.showResultStatus and 22 or 0
        local editReserve=self.editMode and math.min(playerWidth*0.58,226) or 54
        self.filterStatus:ClearAllPoints();self.filterStatus:SetPoint("TOPLEFT",page,"TOPLEFT",playerX,-playerTop);self.filterStatus:SetWidth(math.max(1,playerWidth-editReserve))
        local font,_,flags=self.filterStatus:GetFont();self.filterStatus:SetFont(font,12,flags);self.filterStatus:SetHeight(18)
        if self.filterStatus.SetWordWrap then self.filterStatus:SetWordWrap(false) end
        self.headerRemove:ClearAllPoints();self.headerRemove:SetPoint("TOPLEFT",page,"TOPLEFT",playerX+playerWidth-18,-playerTop);self.headerRemove:SetWidth(16);self.headerRemove:SetHeight(16)
        self.headerEdit:SetWidth(18);self.headerEdit:SetHeight(18)
        local editScale=self.editMode and math.min(1,math.max(1,playerWidth-8)/220) or 1
        UI.SizeClassicButton(self.editSave,62*editScale,22,editScale);UI.SizeClassicButton(self.editCancel,68*editScale,22,editScale);UI.SizeClassicButton(self.editAdd,82*editScale,22,editScale)
        self.editSave:ClearAllPoints();self.editSave:SetPoint("TOPRIGHT",page,"TOPLEFT",playerX+playerWidth,-playerTop)
        self.editCancel:ClearAllPoints();self.editCancel:SetPoint("RIGHT",self.editSave,"LEFT",-4,0)
        self.editAdd:ClearAllPoints();self.editAdd:SetPoint("RIGHT",self.editCancel,"LEFT",-4,0)
        self.editError:ClearAllPoints();self.editError:SetPoint("TOPRIGHT",page,"TOPLEFT",playerX+playerWidth,-playerTop-24);self.editError:SetWidth(playerWidth)
        self.playerRect=self.playerRect or {}
        self.playerRect.x=playerX;self.playerRect.y=playerTop+statusHeight+22;self.playerRect.width=playerWidth;self.playerRect.height=math.max(48,height-playerTop-statusHeight-30)
        return self.playerRect.y+self.playerRect.height+8
    end
    function controller:Layout() UI.LayoutResponsiveCanvas(page,LayoutContent,self) end
    function controller:LayoutColumns(width)
        local nameWidth=math.floor(width*0.30);local attendanceWidth=math.floor(width*0.23);local lootWidth=self.editMode and 0 or 32
        local srX=nameWidth+attendanceWidth;local srWidth=math.max(24,width-srX-lootWidth)
        self.directItemLabel=srWidth>=90
        local starts={0,nameWidth,srX,width-lootWidth};local widths={nameWidth,attendanceWidth,srWidth,lootWidth}
        for i=1,4 do local header=self.headers[i];header:ClearAllPoints();header:SetPoint("TOPLEFT",page,"TOPLEFT",self.playerRect.x+starts[i],-self.playerRect.y+22);header:SetWidth(widths[i]);header:SetHeight(20) end
        if self.editMode then self.lootHeader:Hide() else self.lootHeader:Show() end
        self.attendanceHeader.label:SetText(width<420 and "Raids" or "Attendance")
        UI.Table.FitHeaders(self.headers,12)
        for _,row in ipairs(self.rows) do
            UI.Table.Cell(row.name,row,4,nameWidth-6,23);UI.Table.Cell(row.attendance,row,nameWidth,attendanceWidth-4,23)
            row.nameEdit:ClearAllPoints();row.nameEdit:SetPoint("LEFT",row,"LEFT",2,0);row.nameEdit:SetWidth(math.max(20,nameWidth-4))
            row.attendanceEdit:ClearAllPoints();row.attendanceEdit:SetPoint("LEFT",row,"LEFT",nameWidth,0);row.attendanceEdit:SetWidth(math.max(20,attendanceWidth-4))
            row.srEdit:ClearAllPoints();row.srEdit:SetPoint("LEFT",row,"LEFT",srX,0);row.srEdit:SetWidth(math.max(20,srWidth-4))
            row.sr:ClearAllPoints();row.sr:SetPoint("LEFT",row,"LEFT",srX,0)
            row.srDirect:ClearAllPoints();row.srDirect:SetPoint("LEFT",row,"LEFT",srX,0);row.srDirect:SetWidth(srWidth-4)
            UI.Table.Cell(row.srMissing,row,srX,srWidth-4,23)
            row.loot:ClearAllPoints();row.loot:SetPoint("LEFT",row,"LEFT",width-lootWidth+4,0)
        end
    end
    -- Only data/filter changes rebuild the filtered history. Selection changes
    -- rebuild its summary; viewport work binds the retained model directly.
    function controller:RebuildModel()
        if self.modelDirty then
            local entries, filterError = Raider.Services.RaidStatistics.FilterEntries(self.getEntries(), self.fromDate:GetText(), self.toDate:GetText(), self.filteredEntries, self.selectedRaids, self.search:GetText())
            if not entries then
                for index = table.getn(self.filteredEntries), 1, -1 do table.remove(self.filteredEntries, index) end
            end
            self.filterError = filterError
            local raidId
            for raidId in pairs(self.visibleHistoryIds) do self.visibleHistoryIds[raidId] = nil end
            for index = 1, table.getn(self.filteredEntries) do
                local entry = self.filteredEntries[index]
                self.visibleHistoryIds[entry.id] = entry
            end
        end
        local visibleIds, selectedRaid, selectedCount = self.visibleHistoryIds, nil, 0
        for raidId in pairs(self.selectedHistoryIds) do
            if not visibleIds[raidId] then self.selectedHistoryIds[raidId] = nil
            else selectedCount = selectedCount + 1; selectedRaid = visibleIds[raidId] end
        end
        self.selectedCount = selectedCount
        self.singleRaid = selectedCount == 1 and selectedRaid or nil
        self.summary = selectedCount > 0 and Raider.Services.RaidStatistics.BuildSummary(self.filteredEntries, self.selectedHistoryIds) or self.emptySummary
        self.modelDirty = false; self.summaryDirty = false
    end
    function controller:RenderHeader()
        local filterError, selectedCount, singleRaid = self.filterError, self.selectedCount, self.singleRaid
        self.showResultStatus=filterError or selectedCount > 0
        if filterError then self.filterStatus:SetText(filterError);self.filterStatus:Show();self.headerEdit:Hide(); self.headerRemove:Hide()
        elseif singleRaid then self.filterStatus:SetText("|cffffd147" .. tostring(singleRaid.raidName or "Unknown zone") .. "|r |cffffffff| " .. tostring(singleRaid.id) .. " | " .. date("%Y-%m-%d", tonumber(singleRaid.savedAt) or 0) .. "|r"); self.filterStatus:Show();self.headerEdit.raidId = singleRaid.id; self.headerRemove.raidId = singleRaid.id; self.headerEdit:Show(); self.headerRemove:Show()
        elseif selectedCount > 1 then self.filterStatus:SetText("|cffffd147Selected:|r |cffffffff" .. selectedCount .. "|r");self.filterStatus:Show();self.headerEdit:Hide();self.headerRemove:Hide()
        else self.filterStatus:SetText("");self.filterStatus:Hide(); self.headerEdit:Hide(); self.headerRemove:Hide() end
        if self.editMode then self.headerEdit:Hide();self.headerRemove:Hide();self.editAdd:Show();self.editSave:Show();self.editCancel:Show()
        else self.editAdd:Hide();self.editSave:Hide();self.editCancel:Hide();self.editError:Hide() end
    end
    function controller:BindHistory()
        local entries = self.filteredEntries
        local rect=self.historyRect
        local raidOffset,visibleRaids,historyWidth=0,0,rect.width
        if self.historyCollapsed then
            self.raidScroll:Hide();UI.SetScrollBarVisible(getglobal("BootyRaiderRaidStatisticsHistoryScrollScrollBar"),false)
        else raidOffset,visibleRaids,historyWidth=UI.Table.LayoutViewport(self.raidScroll,page,rect.x,rect.y,rect.width,rect.height,table.getn(entries),28,table.getn(self.raidButtons)) end
        for index = 1, table.getn(self.raidButtons) do
            local button, logicalIndex = self.raidButtons[index], raidOffset + index
            local raid = entries[logicalIndex]
            if raid and index <= visibleRaids then
                button:ClearAllPoints();button:SetPoint("TOPLEFT",page,"TOPLEFT",rect.x,-rect.y-(index-1)*28);button:SetWidth(historyWidth)
                button.raidId = raid.id
                local nameWidth=math.floor(historyWidth*0.38);local raidWidth=math.floor(historyWidth*0.34);local timeWidth=historyWidth-nameWidth-raidWidth
                button.idText:ClearAllPoints();button.idText:SetPoint("LEFT",button,"LEFT",6,0);button.idText:SetWidth(nameWidth-8);button.idText:SetJustifyH("LEFT");button.idText:SetText(tostring(raid.id));button.idText:Show()
                button.zoneText:ClearAllPoints();button.zoneText:SetPoint("LEFT",button,"LEFT",nameWidth,0);button.zoneText:SetWidth(raidWidth-4);button.zoneText:SetJustifyH("LEFT");button.zoneText:SetText(tostring(raid.raidName or "Unknown"));button.zoneText:Show()
                button.dateText:ClearAllPoints();button.dateText:SetPoint("LEFT",button,"LEFT",nameWidth+raidWidth,0);button.dateText:SetWidth(timeWidth-4);button.dateText:SetJustifyH("LEFT");button.dateText:SetText(date("%Y-%m-%d",tonumber(raid.savedAt) or 0));button.dateText:Show();button.allText:Hide()
                button.allText:SetText(tostring(raid.id) .. " | " .. tostring(raid.raidName or "Unknown") .. " | " .. date("%Y-%m-%d",tonumber(raid.savedAt) or 0))
                local selected = self.selectedHistoryIds[raid.id] and true or false; button:Show()
                button.mosClassicSelected=false
                Raider.UI.Components.StyleSelectableTableRow(button,math.mod(logicalIndex,2)==0,selected)
            else button.mosClassicSelected=false;button.mosTableRowSelected=false;UI.SetProjectButtonOutline(button,false);button:Hide() end
        end
        self.emptyHistory:ClearAllPoints();self.emptyHistory:SetPoint("TOPLEFT",page,"TOPLEFT",rect.x,-rect.y-4);self.emptyHistory:SetWidth(historyWidth)
        if not self.historyCollapsed and table.getn(entries)==0 then self.emptyHistory:Show() else self.emptyHistory:Hide() end
    end
    function controller:RenderHistory()
        if not isHostVisible(host) or self.modelDirty or self.summaryDirty or self.renderingHistory or not self.historyRect then return end
        self.renderingHistory = true
        self:BindHistory()
        self.renderingHistory = false
    end
    function controller:BindRows()
        local displayPlayers=self.editMode and self.editMembers or self.summary.players
        local selectedCount, singleRaid = self.selectedCount, self.singleRaid
        local body=self.playerRect
        local offset,visible,rowWidth=UI.Table.LayoutViewport(self.scroll,page,body.x,body.y,body.width,body.height,table.getn(displayPlayers),24,table.getn(self.rows))
        if self.columnsWidth ~= rowWidth or self.columnsEditMode ~= self.editMode then
            self:LayoutColumns(rowWidth); self.columnsWidth = rowWidth; self.columnsEditMode = self.editMode
        end
        self.emptyPlayers:ClearAllPoints();self.emptyPlayers:SetPoint("TOPLEFT",page,"TOPLEFT",body.x,-body.y-4);self.emptyPlayers:SetWidth(rowWidth)
        self.emptyPlayers:SetText(selectedCount==0 and "No selected raid." or "No matching players.");self.emptyPlayers:SetJustifyH("CENTER")
        if table.getn(displayPlayers)==0 then self.emptyPlayers:Show() else self.emptyPlayers:Hide() end
        for index = 1, table.getn(self.rows) do
            local row, player = self.rows[index], displayPlayers[offset + index]
            if player and index <= visible then
                row:ClearAllPoints();row:SetPoint("TOPLEFT",page,"TOPLEFT",body.x,-body.y-(index-1)*24);row:SetWidth(rowWidth)
                UI.ApplyRowBackground(row,offset+index,false)
                row.player = player
                if self.editMode then
                    row.bindingEditMember = true
                    row.editMember=player;row.name:Hide();row.attendance:Hide();row.sr:Hide();row.srDirect:Hide();row.srMissing:Hide();row.loot:Hide()
                    row.nameEdit:SetText(player.name or "");row.attendanceEdit:SetText(tostring(player.attendanceText or player.attendance or 1));local editItem=player.srItemText or (player.srItems and player.srItems[1] and player.srItems[1].itemId) or "";row.srEdit:SetText(tostring(editItem));row.nameEdit:Show();row.attendanceEdit:Show();row.srEdit:Show();row:Show()
                    row.bindingEditMember = nil
                else
                row.editMember=nil;row.nameEdit:Hide();row.attendanceEdit:Hide();row.srEdit:Hide();row.name:Show();row.attendance:Show();row.loot:Show();row.name:SetText(player.name)
                local classKey=string.upper(tostring(player.class or ""));local classColor=(RAID_CLASS_COLORS and RAID_CLASS_COLORS[classKey]) or UI.Theme.classColors[classKey]
                if classColor then row.name:SetTextColor(classColor.r,classColor.g,classColor.b) else row.name:SetTextColor(1,1,1) end
                row.attendance:SetText(player.attendanceOff and "Off" or player.raids); row.loot:SetInactive(table.getn(player.lootItems or {}) == 0)
                row.srMissing:Hide()
                if singleRaid and self.directItemLabel and player.srItems and player.srItems[1] and player.srItems[1].itemId then
                    local item = player.srItems[1]; row.sr:Hide(); row.srDirect.itemId = item.itemId; row.srDirect.itemName = item.name; row.srDirect.label:SetText(Raider.UI.Components.GetItemLabel(item.itemId) .. (table.getn(player.srItems) > 1 and (" +" .. (table.getn(player.srItems) - 1)) or "")); row.srDirect:Show()
                    local texture = type(GetItemIcon) == "function" and GetItemIcon(item.itemId) or nil; row.srDirect.iconRegion:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                elseif singleRaid then row.srDirect.itemId = nil; row.srDirect:Hide(); row.sr:Hide(); row.srMissing:Show()
                else row.srDirect.itemId = nil; row.srDirect:Hide(); row.sr:SetInactive(table.getn(player.srItems or {}) == 0); row.sr:Show() end
                row:Show()
                end
            else row.player=nil;row.editMember=nil;row.nameEdit:Hide();row.attendanceEdit:Hide();row.srEdit:Hide();row.srDirect.itemId=nil;row.srDirect:Hide();row.srMissing:Hide();row:Hide() end
        end
    end
    function controller:RenderRows()
        if not isHostVisible(host) or self.modelDirty or self.summaryDirty or self.renderingRows or not self.playerRect then return end
        self.renderingRows = true
        self:BindRows()
        self.renderingRows = false
    end
    function controller:Render()
        if not isHostVisible(host) or self.refreshing then return end
        self.refreshing = true
        Raider.Diagnostics.Count("uiRefreshes")
        if self.modelDirty or self.summaryDirty then self:RebuildModel() end
        self:RenderHeader()
        self:Layout()
        -- Header positions move on resize even when the column width is equal.
        self.columnsWidth = nil
        self:RenderHistory()
        self:RenderRows()
        self.refreshing = false
    end
    function controller:Refresh()
        self.modelDirty = true; self.summaryDirty = true
        self:Render()
    end
    if Raider.Diagnostics.Wrap then
        controller.RebuildModel = Raider.Diagnostics.Wrap("Raid Statistics model", controller.RebuildModel, 1)
        controller.Layout = Raider.Diagnostics.Wrap("Raid Statistics layout", controller.Layout, 1)
        controller.BindHistory = Raider.Diagnostics.Wrap("Raid Statistics history", controller.BindHistory, 1)
        controller.BindRows = Raider.Diagnostics.Wrap("Raid Statistics rows", controller.BindRows, 1)
    end
    return {
        frame = page, page = page,
        Hide = function(self) controller.raidPanel:Hide(); controller.raidDismiss:Hide(); controller.dateDismiss:Hide(); controller.itemDialog:Hide(); controller.datePicker:Hide(); controller.editDialog:Hide(); controller.removeDialog:Hide(); page:Hide();host:Hide() end,
        Show = function(self) host:Show();page:Show(); controller:Refresh() end,
        Refresh = function(self) controller:Refresh() end,
        OnResize = function(self) controller.datePicker:Hide(); controller.raidPanel:Hide(); controller:Render() end,
        SelectRaid = function(self, raidId) for selectedId in pairs(controller.selectedHistoryIds) do controller.selectedHistoryIds[selectedId]=nil end; if raidId then controller.selectedHistoryIds[raidId]=true end; controller.raidScroll.offset = 0; controller.scroll.offset = 0; controller:Refresh() end,
    }
end
