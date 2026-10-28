local Raider = BootyRaider

Raider.Modules.RaidManagement = Raider.Modules.RaidManagement or {}
local RaidManagement = Raider.Modules.RaidManagement
local UI=Raider.UI.Components

function RaidManagement.RefreshSyncStatus(page)
    local controls=page.syncHistoryControls
    if not controls or not controls.syncStatus or not controls.syncStatus:IsShown() then return end
    local replica=Raider.Runtime and Raider.Runtime.replica
    local status=replica and replica.GetStatus()
    controls.syncStatus:SetText("Sync status: "..(status and status.syncStatus or "Up to date"))
    local canJoin=Raider.Modules.RaidSyncRuntime.CanJoinRaid()
    UI.SetButtonEnabled(controls.scan,controls.canStartRaid and canJoin)
end

local function ActiveSessions(page,controls,width,y)
    local api=Raider.Runtime and Raider.Runtime.replica
    if not api or not api.ListActiveRaids then return y end
    if not controls.activeTitle then
        controls.activeTitle=UI.CreateLabel(page,nil,"OVERLAY","GameFontNormal")
        controls.activeTitle:SetText("Active raid sessions");UI.SetHeadingIcon(controls.activeTitle,"ping")
        controls.activeRows={};controls.activeOffset=0
        for index=1,4 do
            local row=UI.CreateButton(page,nil,"",width,24);row.name=UI.CreateLabel(row,nil,"OVERLAY","GameFontHighlightSmall")
            row.raidType=UI.CreateLabel(row,nil,"OVERLAY","GameFontHighlightSmall")
            row.join=UI.CreateButton(row,nil,"",24,22);UI.SetClassicButtonIcon(row.join,"start",13,6,0)
            UI.AttachTooltip(row.join,"Join session","Continue this shared raid session.")
            row.join:SetScript("OnClick",function()
                local allowed,reason=Raider.Modules.RaidSyncRuntime.CanJoinRaid(row.raidId)
                if allowed then allowed,reason=Raider.Runtime.replica.Recover(row.raidId) end
                if not allowed then Raider.Runtime.Print(reason) end
                Raider.Runtime.RefreshViews()
            end)
            controls.activeRows[index]=row
        end
        controls.activeEmpty=UI.CreateLabel(page,nil,"OVERLAY","GameFontHighlightSmall");controls.activeEmpty:SetText("No active raid sessions")
        controls.activePrevious=UI.CreateButton(page,nil,"<",24,22)
        controls.activeNext=UI.CreateButton(page,nil,">",24,22)
        controls.activePrevious:SetScript("OnClick",function() controls.activeOffset=math.max(0,controls.activeOffset-4);Raider.Runtime.RefreshViews() end)
        controls.activeNext:SetScript("OnClick",function() controls.activeOffset=controls.activeOffset+4;Raider.Runtime.RefreshViews() end)
    end
    controls.activeTitle:SetFont(controls.historyTitle:GetFont())
    local list,total=api.ListActiveRaids(controls.activeOffset,4)
    if controls.activeOffset>=total and controls.activeOffset>0 then controls.activeOffset=0;list,total=api.ListActiveRaids(0,4) end
    controls.activeTitle:ClearAllPoints();controls.activeTitle:SetPoint("TOPLEFT",page,"TOPLEFT",8,y-34);controls.activeTitle:Show()
    controls.activePrevious:ClearAllPoints();controls.activePrevious:SetPoint("TOPRIGHT",page,"TOPRIGHT",-40,y-30)
    controls.activeNext:ClearAllPoints();controls.activeNext:SetPoint("TOPRIGHT",page,"TOPRIGHT",-8,y-30)
    if total>4 then controls.activePrevious:Show();controls.activeNext:Show() else controls.activePrevious:Hide();controls.activeNext:Hide() end
    UI.SetButtonEnabled(controls.activePrevious,controls.activeOffset>0);UI.SetButtonEnabled(controls.activeNext,controls.activeOffset+4<total)
    for index,row in ipairs(controls.activeRows) do
        local entry=list[index];row.raidId=entry and entry.id
        if entry then
            row:ClearAllPoints();row:SetPoint("TOPLEFT",page,"TOPLEFT",8,y-60-(index-1)*26);row:SetWidth(width)
            row.name:ClearAllPoints();row.name:SetPoint("LEFT",row,"LEFT",6,0);row.name:SetWidth((width-52)*0.55);row.name:SetText(entry.name)
            row.raidType:ClearAllPoints();row.raidType:SetPoint("LEFT",row,"LEFT",(width-52)*0.55+10,0);row.raidType:SetWidth((width-52)*0.45);row.raidType:SetText(entry.raidType)
            row.join:ClearAllPoints();row.join:SetPoint("RIGHT",row,"RIGHT",-4,0)
            UI.StyleSelectableTableRow(row,math.mod(index,2)==0,false);row:Show()
        else row:Hide() end
    end
    controls.activeEmpty:ClearAllPoints();controls.activeEmpty:SetPoint("TOPLEFT",page,"TOPLEFT",8,y-60)
    if total==0 then controls.activeEmpty:Show() else controls.activeEmpty:Hide() end
    return y-60-math.max(1,table.getn(list))*26
end

function RaidManagement.HideRaidHistoryControls(controls)
    for _,key in ipairs({"activeTitle","activeEmpty","activePrevious","activeNext","syncStatus","historyToolbar"}) do if controls[key] then controls[key]:Hide() end end
    for _,row in ipairs(controls.activeRows or {}) do row:Hide() end
    controls.historyScroll:Hide()
    controls.loadRaid:Hide(); controls.testRaid:Hide(); controls.historyTitle:Hide(); controls.historyEmpty:Hide()
    if controls.raidSync then controls.raidSync:Hide() end
    for _, group in ipairs({controls.historyButtons, controls.historyDeleteButtons, controls.historyLoadButtons, controls.historyEditButtons or {}, controls.historyLogButtons or {}, controls.historyHeaders}) do
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
    local canEdit = Raider.Services.RankPolicy.CanManageHistory()
    local dataWidth = math.max(60, width - (canEdit and 98 or 76))
    local numberWidth = 28
    local remainingWidth = math.max(32, dataWidth - numberWidth)
    local nameWidth, raidWidth = math.floor(remainingWidth * 0.17), math.floor(remainingWidth * 0.12)
    local durationWidth, createdWidth = math.floor(remainingWidth * 0.15), math.floor(remainingWidth * 0.16)
    local modifiedWidth,storageWidth=math.floor(remainingWidth * 0.16),math.floor(remainingWidth * 0.11)
    local authorWidth=remainingWidth-nameWidth-raidWidth-durationWidth-createdWidth-modifiedWidth-storageWidth
    local widths = {numberWidth, nameWidth, raidWidth, durationWidth, createdWidth, modifiedWidth,storageWidth,authorWidth}
    local x = 8
    for index = 1, table.getn(controls.historyHeaders) do
        local heading = controls.historyHeaders[index]
        heading:ClearAllPoints(); heading:SetPoint("TOPLEFT", page, "TOPLEFT", x, actionY - 62); heading:SetWidth(widths[index] - 6); heading:SetJustifyH("LEFT"); heading:Show()
        x = x + widths[index]
    end
    controls.historyCanvas:SetWidth(width)
    local y = 0
    for index = 1, 10 do
        local snapshot, button = snapshots[index], controls.historyButtons[index]
        local deleteButton, load = controls.historyDeleteButtons[index], controls.historyLoadButtons[index]
        local edit = controls.historyEditButtons and controls.historyEditButtons[index]
        local log = controls.historyLogButtons and controls.historyLogButtons[index]
        button:ClearAllPoints(); button:SetPoint("TOPLEFT", controls.historyCanvas, "TOPLEFT", 0, y); button:SetWidth(dataWidth)
        if snapshot then
            if not button.storage then button.storage=UI.CreateLabel(button,nil,"OVERLAY","GameFontHighlightSmall");button.author=UI.CreateLabel(button,nil,"OVERLAY","GameFontHighlightSmall") end
            local api=Raider.Runtime and Raider.Runtime.replica
            local info=api and api.GetRaidInfo and api.GetRaidInfo(snapshot.syncRaidId) or {storage="In memory",lastAuthor="Unknown"}
            local createdAt, modifiedAt, duration = Raider.Services.RaidRes.GetSnapshotTimes(snapshot)
            modifiedAt=info.modifiedAt or modifiedAt
            local durationText = Raider.Services.RaidRes.FormatDuration(duration)
            local durationX = numberWidth + nameWidth + raidWidth
            local height = math.max(26,
                Cell(button.number, button, 4, numberWidth - 6, tostring(index)),
                Cell(button.label, button, numberWidth, nameWidth, tostring(snapshot.id or "Unknown")),
                Cell(button.raidName, button, numberWidth + nameWidth, raidWidth, snapshot.raidName or "Unknown zone"),
                Cell(button.duration, button, durationX, durationWidth, durationText),
                Cell(button.createdAt, button, durationX + durationWidth, createdWidth, createdAt and date("%Y-%m-%d %H:%M", createdAt) or "Unknown"),
                Cell(button.savedAt, button, durationX + durationWidth + createdWidth, modifiedWidth, modifiedAt and date("%Y-%m-%d %H:%M", modifiedAt) or "Unknown"),
                Cell(button.storage,button,dataWidth-storageWidth-authorWidth,storageWidth,info.storage),
                Cell(button.author,button,dataWidth-authorWidth,authorWidth,info.lastAuthor or "Unknown"))
            button:SetHeight(height); button:Show()
            Raider.UI.Components.StyleSelectableTableRow(button, math.mod(index, 2) == 0, page.selectedRaidHistoryId == snapshot.id)
            load:SetWidth(24); load:SetHeight(24); deleteButton:SetWidth(16); deleteButton:SetHeight(16)
            load:ClearAllPoints(); load:SetPoint("LEFT", button, "RIGHT", 4, 0); load:Show()
            if edit then
                edit:SetWidth(18); edit:SetHeight(18); edit:ClearAllPoints(); edit:SetPoint("LEFT", load, "RIGHT", 4, 0)
                if canEdit then edit:Show() else edit:Hide() end
            end
            if log then
                log:SetWidth(18); log:SetHeight(18); log:ClearAllPoints(); log:SetPoint("LEFT", canEdit and edit or load, "RIGHT", 4, 0)
                Raider.UI.Components.SetButtonEnabled(log,snapshot.syncRaidId~=nil);log:Show()
            end
            deleteButton:ClearAllPoints(); deleteButton:SetPoint("LEFT", log or canEdit and edit or load, "RIGHT", 4, 0); deleteButton:Show()
            y = y - height - 2
        else button.number:Hide(); button:Hide(); load:Hide(); deleteButton:Hide(); if edit then edit:Hide() end; if log then log:Hide() end end
    end
    return math.max(1, -y - 2)
end

function RaidManagement.ShowRaidHistoryControls(page, controls, canStartRaid)
    page.syncHistoryControls=controls;controls.canStartRaid=canStartRaid
    local fullWidth = math.max(1, Raider.UI.Components.GetFrameSpan(page) - 16)
    local width = fullWidth
    local rightInset = 8 + fullWidth - width
    local buttonWidth = math.min(110, width)
    if controls.title then
        controls.title:SetText("Raid")
        if BootyRaiderDB.raidHideSectionHeader then controls.title:Hide() else controls.title:Show() end
    end
    local actionY=BootyRaiderDB.raidHideSectionHeader and -16 or -56
    if controls.unavailable then controls.unavailable:Hide() end
    if not controls.historyToolbar then
        controls.historyToolbar=UI.CreateToolbarSurface(page,true,true)
        controls.historyToolbar:SetFrameLevel(page:GetFrameLevel())
        -- Match the existing full-width filter strip, including its frame outset.
        controls.historyToolbar.bootyBorderOutsetLeft=4;controls.historyToolbar.bootyBorderOutsetRight=4
        UI.SetSurfaceHorizontalBorders(controls.historyToolbar,true,true)
    end
    controls.scan:ClearAllPoints();controls.scan:SetPoint("TOPLEFT",page,"TOPLEFT",8,actionY)
    controls.scan:SetWidth(buttonWidth);controls.scan:SetHeight(22);controls.scan:SetText("New Raid");controls.scan:Show()
    controls.loadRaid:Hide()
    controls.testRaid:ClearAllPoints();controls.testRaid:SetPoint("LEFT",controls.scan,"RIGHT",8,0)
    controls.testRaid:SetWidth(buttonWidth);controls.testRaid:SetHeight(22);controls.testRaid:Show()
    UI.SetClassicButtonIcon(controls.scan,"start",13,7,0)
    UI.SetClassicButtonIcon(controls.testRaid,"analyze",13,7,0)
    if controls.raidSync and Raider.Services.RankPolicy.CanManageHistory() then
        controls.raidSync:SetText("Sync");controls.raidSync:SetWidth(78);controls.raidSync:SetHeight(22)
        controls.raidSync:Enable();controls.raidSync:ClearAllPoints();controls.raidSync:SetPoint("LEFT",controls.testRaid,"RIGHT",8,0);controls.raidSync:Show()
        UI.SetClassicButtonIcon(controls.raidSync,"refresh",13,7,0)
    elseif controls.raidSync then controls.raidSync:Hide() end
    if controls.raidInfo then
        controls.raidInfo:ClearAllPoints();controls.raidInfo:SetPoint("RIGHT",page,"TOPRIGHT",-8,actionY-11);controls.raidInfo:Show()
    end
    for _,button in ipairs({controls.scan,controls.testRaid,controls.raidSync,controls.raidInfo}) do
        button.bootyCaptionBottomInset=0;UI.ApplyButtonCaptionBaseline(button)
    end
    if not controls.syncStatus then controls.syncStatus=UI.CreateLabel(page,nil,"OVERLAY","GameFontHighlightSmall") end
    local statusWidth=math.max(1,width-2*buttonWidth-150)
    controls.syncStatus:ClearAllPoints();controls.syncStatus:SetPoint("TOPRIGHT",page,"TOPRIGHT",-40,actionY-4)
    controls.syncStatus:SetWidth(statusWidth);controls.syncStatus:SetJustifyH("RIGHT");controls.syncStatus:Show()
    if controls.syncStatus.SetWordWrap then controls.syncStatus:SetWordWrap(true) end
    controls.syncStatus:SetHeight(0);RaidManagement.RefreshSyncStatus(page)
    local rowHeight=math.max(22,UI.MeasureTextHeight(controls.syncStatus,statusWidth,true)+4)
    controls.historyToolbar:ClearAllPoints()
    controls.historyToolbar:SetPoint("TOPLEFT",page,"TOPLEFT",0,actionY+8)
    controls.historyToolbar:SetPoint("TOPRIGHT",page,"TOPRIGHT",0,actionY+8)
    controls.historyToolbar:SetHeight(rowHeight+16);controls.historyToolbar:Show()
    actionY=actionY-math.max(0,rowHeight-22)
    actionY=ActiveSessions(page,controls,width,actionY)
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
