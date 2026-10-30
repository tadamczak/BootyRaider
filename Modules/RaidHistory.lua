local Raider = BootyRaider

Raider.Modules.RaidManagement = Raider.Modules.RaidManagement or {}
local RaidManagement = Raider.Modules.RaidManagement
local UI=Raider.UI.Components
local function ShortRaid(name) return Raider.Services.RaidRes.ShortRaidName(name) end
local function Stamp(value) return value and date("%Y-%m-%d %H:%M",value) or "Not saved yet" end

function RaidManagement.RefreshSyncStatus(page)
    local controls=page.syncHistoryControls
    if not controls or not controls.syncStatus or not controls.syncStatus:IsShown() then return end
    local replica=Raider.Runtime and Raider.Runtime.replica
    local status=replica and replica.GetStatus()
    local gold=UI.Theme.colors.goldText
    local prefix=string.format("|cff%02x%02x%02xSync status:|r |cffffffff",math.floor(gold[1]*255),math.floor(gold[2]*255),math.floor(gold[3]*255))
    controls.syncStatus:SetText(prefix..(status and status.syncStatus or "Up to date").."|r")
    local canJoin=Raider.Modules.RaidSyncRuntime.CanJoinRaid()
    UI.SetButtonEnabled(controls.scan,controls.canStartRaid and canJoin)
end

function RaidManagement.ToggleRaidSync(id)
    local api=Raider.Runtime.replica
    local ok,reason=api.SetRaidSyncEnabled(id,not api.IsRaidSyncEnabled(id))
    if not ok then Raider.Runtime.Print(reason) end
    Raider.Runtime.RefreshViews()
    if Raider.Modules.RaidSync then Raider.Modules.RaidSync.RefreshVisible() end
end
local function SyncButtonState(button,enabled)
    button.bootySyncEnabled=enabled and true or false
    local key=enabled and "refresh" or "disable"
    button.icon:SetTexture("Interface\\AddOns\\BootyLib\\Assets\\Skins\\Classic\\Icons\\"..key..".tga")
    UI.AttachTooltip(button,enabled and "Raid sync: on" or "Raid sync: off",enabled and "Stop synchronization on this character. Previously shared copies remain with other officers." or "Start synchronization with authorized officers.")
end
local function FitColumns(page,controls,headers,values,available,actionWidth)
    if not controls.columnMeasure then controls.columnMeasure=UI.CreateLabel(page,nil,"OVERLAY","GameFontHighlightSmall");controls.columnMeasure:Hide() end
    local measure=controls.columnMeasure;local columns={};local total=0
    for index,header in ipairs(headers) do
        measure:SetText(header:GetText());local desired=measure:GetStringWidth()+12
        for _,row in ipairs(values) do measure:SetText(tostring(row[index] or ""));desired=math.max(desired,measure:GetStringWidth()+12) end
        if index==1 then desired=28 elseif index==table.getn(headers) then desired=math.max(actionWidth,desired) end
        columns[index]={desiredWidth=desired,minimumWidth=index==1 and 28 or math.min(desired,64),growthWeight=0};total=total+desired
    end
    UI.Table.AllocateColumnWidths(columns,math.min(available,total))
    local widths={};for index,column in ipairs(columns) do widths[index]=column.width end
    return widths
end

RaidManagement.FitRaidColumns=FitColumns

local function ActiveSessions(page,controls,width,y)
    local api=Raider.Runtime and Raider.Runtime.replica
    if not api or not api.ListActiveRaids then return y end
    if not controls.activeTitle then
        controls.activeTitle=UI.CreateLabel(page,nil,"OVERLAY","GameFontNormal")
        controls.activeTitle:SetText("Active raid sessions");UI.SetHeadingIcon(controls.activeTitle,"ping")
        controls.activeRows={};controls.activeOffset=0;controls.activeHeaders={}
        for index,text in ipairs({"#","Raid ID","Raid","Members","Created At","Storage","Last Saved","Actions"}) do controls.activeHeaders[index]=UI.CreateColumnLabel(page,text,"gold") end
        for index=1,4 do
            local row=UI.CreateButton(page,nil,"",width,26);row.name=UI.CreateLabel(row,nil,"OVERLAY","GameFontHighlightSmall")
            row.raidType=UI.CreateLabel(row,nil,"OVERLAY","GameFontHighlightSmall")
            row.number=UI.CreateLabel(row,nil,"OVERLAY","GameFontHighlightSmall");row.members=UI.CreateLabel(row,nil,"OVERLAY","GameFontHighlightSmall");row.created=UI.CreateLabel(row,nil,"OVERLAY","GameFontHighlightSmall")
            row.storage=UI.CreateLabel(row,nil,"OVERLAY","GameFontHighlightSmall");row.lastSaved=UI.CreateLabel(row,nil,"OVERLAY","GameFontHighlightSmall")
            row.join=UI.CreateGoldToolbarButton(row,"start");row.join:SetWidth(24);row.join:SetHeight(24)
            UI.AttachTooltip(row.join,"Join session","Continue this shared raid session.")
            row.join:SetScript("OnClick",function()
                local allowed,reason=Raider.Modules.RaidSyncRuntime.CanJoinRaid(row.raidId)
                if allowed then allowed,reason=Raider.Runtime.replica.Recover(row.raidId) end
                if not allowed then Raider.Runtime.Print(reason) end
                Raider.Runtime.RefreshViews()
            end)
            row.sync=UI.CreateGoldToolbarButton(row,"refresh");row.sync:SetWidth(24);row.sync:SetHeight(24)
            UI.AttachTooltip(row.sync,"Raid sync","Toggle synchronization on this character. Stopping does not remove copies already shared with other officers.")
            row.sync:SetScript("OnClick",function() RaidManagement.ToggleRaidSync(row.raidId) end)
            row.delete=UI.CreateGoldToolbarButton(row,"trash");row.delete:SetWidth(24);row.delete:SetHeight(24)
            UI.AttachTooltip(row.delete,"Delete active session","Remove this active session for synchronizing officers. Saved snapshots are preserved.")
            row.delete:SetScript("OnClick",function()
                local api=Raider.Runtime.replica;local id=row.raidId
                if not id or not Raider.Services.RankPolicy.CanManageHistory() then return end
                local token=api.GetDeleteSessionToken(id)
                if not controls.deleteActiveDialog then
                    controls.deleteActiveDialog=UI.Window.CreateProjectConfirmation("BootyRaiderDeleteActiveSession","Delete active session","Delete","trash")
                    controls.deleteActiveDialog:SetWidth(390)
                end
                local dialog=controls.deleteActiveDialog
                if UI.WindowStack then UI.WindowStack.SetOwner(dialog,page) end
                dialog:Open("Delete '"..tostring(row.name:GetText()).."' for all synchronizing officers? Unsaved session changes will be discarded. Saved snapshots will stay.",function()
                    local ok,reason=api.DeleteSession(id,token)
                    if not ok then Raider.Runtime.Print(reason) end
                    Raider.Runtime.RefreshViews()
                end)
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
    local values={}
    for index,entry in ipairs(list) do local info=api.GetRaidInfo(entry.id);values[index]={tostring(controls.activeOffset+index),entry.name,ShortRaid(entry.raidType),tostring(entry.memberCount or 0).."/"..tostring(entry.memberLimit or "?"),entry.createdAt and date("%Y-%m-%d %H:%M",entry.createdAt) or "Unknown",info.storage,Stamp(info.lastSave),""} end
    local widths=FitColumns(page,controls,controls.activeHeaders,values,width,84)
    local dataWidth=0;for index=1,7 do dataWidth=dataWidth+widths[index] end
    local dataLimit=math.max(1,width-84)
    if dataWidth>dataLimit then for index=1,7 do widths[index]=widths[index]*dataLimit/dataWidth end end
    widths[8]=84
    local x=8
    for index,label in ipairs(controls.activeHeaders) do label:ClearAllPoints();label:SetPoint("TOPLEFT",page,"TOPLEFT",x,y-58);label:SetWidth(widths[index]-6);label:SetJustifyH("LEFT");label:Show();x=x+widths[index] end
    local rowY=y-82
    for index,row in ipairs(controls.activeRows) do
        local entry=list[index];row.raidId=entry and entry.id
        if entry then
            row:ClearAllPoints();row:SetPoint("TOPLEFT",page,"TOPLEFT",8,rowY);row:SetWidth(widths[1]+widths[2]+widths[3]+widths[4]+widths[5]+widths[6]+widths[7])
            local labels={row.number,row.name,row.raidType,row.members,row.created,row.storage,row.lastSaved}
            local info=api.GetRaidInfo(entry.id)
            local values={tostring(controls.activeOffset+index),entry.name,ShortRaid(entry.raidType),tostring(entry.memberCount or 0).."/"..tostring(entry.memberLimit or "?"),entry.createdAt and date("%Y-%m-%d %H:%M",entry.createdAt) or "Unknown",info.storage,Stamp(info.lastSave)}
            local cellX=0;local rowHeight=26
            for column,label in ipairs(labels) do label:ClearAllPoints();label:SetPoint("LEFT",row,"LEFT",cellX,0);label:SetWidth(widths[column]-4);label:SetJustifyH("LEFT");label:SetJustifyV("MIDDLE");label:SetText(values[column]);label:SetHeight(0);rowHeight=math.max(rowHeight,UI.MeasureTextHeight(label,widths[column]-4,true)+10);cellX=cellX+widths[column] end
            row.join:ClearAllPoints();row.join:SetPoint("LEFT",row,"LEFT",cellX,0)
            row.sync:ClearAllPoints();row.sync:SetPoint("LEFT",row.join,"RIGHT",2,0);SyncButtonState(row.sync,api.IsRaidSyncEnabled(entry.id))
            row.delete:ClearAllPoints();row.delete:SetPoint("LEFT",row.sync,"RIGHT",2,0)
            UI.SetButtonEnabled(row.delete,Raider.Services.RankPolicy.CanManageHistory())
            UI.StyleSelectableTableRow(row,math.mod(index,2)==0,false);UI.SetAlternatingRowColor(row,nil,index);row:SetHeight(rowHeight);row:Show();rowY=rowY-rowHeight-2
        else row:Hide() end
    end
    controls.activeEmpty:ClearAllPoints();controls.activeEmpty:SetPoint("TOPLEFT",page,"TOPLEFT",8,y-82)
    if total==0 then controls.activeEmpty:Show() else controls.activeEmpty:Hide() end
    return total==0 and y-86 or rowY+22
end

function RaidManagement.HideRaidHistoryControls(controls)
    if controls.deleteActiveDialog then controls.deleteActiveDialog:Hide() end
    for _,key in ipairs({"activeTitle","activeEmpty","activePrevious","activeNext","syncStatus","historyToolbar"}) do if controls[key] then controls[key]:Hide() end end
    for _,row in ipairs(controls.activeRows or {}) do row:Hide() end
    for _,label in ipairs(controls.activeHeaders or {}) do label:Hide() end
    for _,button in ipairs(controls.historyButtons or {}) do if button.sync then button.sync:Hide() end end
    controls.historyScroll:Hide()
    UI.SetScrollBarVisible(getglobal("BootyRaiderRaidHistoryScrollScrollBar"),false)
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
    local values={}
    for index,snapshot in ipairs(snapshots) do
        local created,modified,duration=Raider.Services.RaidRes.GetSnapshotTimes(snapshot)
        local api=Raider.Runtime and Raider.Runtime.replica;local info=api and api.GetRaidInfo and api.GetRaidInfo(snapshot.syncRaidId) or {}
        modified=info.modifiedAt or modified
        values[index]={index,snapshot.id,ShortRaid(snapshot.raidName),Raider.Services.RaidRes.FormatDuration(duration),created and date("%Y-%m-%d %H:%M",created) or "Unknown",modified and date("%Y-%m-%d %H:%M",modified) or "Unknown",info.storage or "In memory",info.lastAuthor or "Unknown",info.lifecycle=="deleted" and "Archived" or info.lifecycle and info.lifecycle~="ended" and "Active" or "Ended",""}
    end
    if not controls.historyHeaders[10] then controls.historyHeaders[10]=UI.CreateColumnLabel(page,"Actions","gold") end
    local widths=FitColumns(page,controls,controls.historyHeaders,values,width,canEdit and 134 or 108)
    local numberWidth,nameWidth,raidWidth,durationWidth,createdWidth,modifiedWidth,storageWidth,authorWidth,statusWidth=unpack(widths)
    local dataWidth=0;for index=1,9 do dataWidth=dataWidth+widths[index] end
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
            if not button.storage then button.storage=UI.CreateLabel(button,nil,"OVERLAY","GameFontHighlightSmall");button.author=UI.CreateLabel(button,nil,"OVERLAY","GameFontHighlightSmall");button.status=UI.CreateLabel(button,nil,"OVERLAY","GameFontHighlightSmall") end
            if not button.sync then
                button.sync=UI.CreateGoldToolbarButton(controls.historyCanvas,"refresh");button.sync:SetWidth(24);button.sync:SetHeight(24)
                UI.AttachTooltip(button.sync,"Raid sync","Toggle synchronization on this character. Stopping does not remove previously shared copies.")
                button.sync:SetScript("OnClick",function() RaidManagement.ToggleRaidSync(button.syncRaidId) end)
            end
            button.syncRaidId=snapshot.syncRaidId
            local api=Raider.Runtime and Raider.Runtime.replica
            local info=api and api.GetRaidInfo and api.GetRaidInfo(snapshot.syncRaidId) or {storage="In memory",lastAuthor="Unknown"}
            local createdAt, modifiedAt, duration = Raider.Services.RaidRes.GetSnapshotTimes(snapshot)
            modifiedAt=info.modifiedAt or modifiedAt
            local durationText = Raider.Services.RaidRes.FormatDuration(duration)
            local durationX = numberWidth + nameWidth + raidWidth
            local height = math.max(26,
                Cell(button.number, button, 4, numberWidth - 6, tostring(index)),
                Cell(button.label, button, numberWidth, nameWidth, tostring(snapshot.id or "Unknown")),
                Cell(button.raidName, button, numberWidth + nameWidth, raidWidth, ShortRaid(snapshot.raidName)),
                Cell(button.duration, button, durationX, durationWidth, durationText),
                Cell(button.createdAt, button, durationX + durationWidth, createdWidth, createdAt and date("%Y-%m-%d %H:%M", createdAt) or "Unknown"),
                Cell(button.savedAt, button, durationX + durationWidth + createdWidth, modifiedWidth, modifiedAt and date("%Y-%m-%d %H:%M", modifiedAt) or "Unknown"),
                Cell(button.storage,button,dataWidth-storageWidth-authorWidth-statusWidth,storageWidth,info.storage),
                Cell(button.author,button,dataWidth-authorWidth-statusWidth,authorWidth,info.lastAuthor or "Unknown"),
                Cell(button.status,button,dataWidth-statusWidth,statusWidth,info.lifecycle=="deleted" and "Archived" or info.lifecycle and info.lifecycle~="ended" and "Active" or "Ended"))
            button:SetHeight(height); button:Show()
            Raider.UI.Components.StyleSelectableTableRow(button, math.mod(index, 2) == 0, page.selectedRaidHistoryId == snapshot.id)
            load:SetWidth(24); load:SetHeight(24); deleteButton:SetWidth(24); deleteButton:SetHeight(24)
            load:ClearAllPoints(); load:SetPoint("LEFT", button, "RIGHT", 4, 0); load:Show()
            if edit then
                edit:SetWidth(24); edit:SetHeight(24); edit:ClearAllPoints(); edit:SetPoint("LEFT", load, "RIGHT", 2, 0)
                if canEdit then edit:Show() else edit:Hide() end
            end
            if log then
                log:SetWidth(24); log:SetHeight(24); log:ClearAllPoints(); log:SetPoint("LEFT", canEdit and edit or load, "RIGHT", 2, 0)
                Raider.UI.Components.SetButtonEnabled(log,snapshot.syncRaidId~=nil);log:Show()
            end
            button.sync:ClearAllPoints();button.sync:SetPoint("LEFT",log or canEdit and edit or load,"RIGHT",2,0);button.sync:Show()
            UI.SetButtonEnabled(button.sync,snapshot.syncRaidId~=nil and canEdit);SyncButtonState(button.sync,api and api.IsRaidSyncEnabled(snapshot.syncRaidId) and snapshot.syncRaidId~=nil)
            deleteButton:ClearAllPoints(); deleteButton:SetPoint("LEFT", button.sync, "RIGHT", 2, 0); deleteButton:Show()
            y = y - height - 2
        else if button.sync then button.sync:Hide() end;button.number:Hide(); button:Hide(); load:Hide(); deleteButton:Hide(); if edit then edit:Hide() end; if log then log:Hide() end end
    end
    return math.max(1, -y - 2)
end

function RaidManagement.ShowRaidHistoryControls(page, controls, canStartRaid)
    if page.convertRaidButton then page.convertRaidButton:Hide() end
    page.syncHistoryControls=controls;controls.canStartRaid=canStartRaid
    local fullWidth = math.max(1, Raider.UI.Components.GetFrameSpan(page) - 16)
    local width = fullWidth
    local rightInset = 8 + fullWidth - width
    local buttonWidth = math.min(110, width)
    if controls.title then
        controls.title:SetText("Raid");controls.title:ClearAllPoints();controls.title:SetPoint("TOPLEFT",page,"TOPLEFT",8,-8)
        if BootyRaiderDB.raidHideSectionHeader then controls.title:Hide() else controls.title:Show() end
    end
    local actionY=BootyRaiderDB.raidHideSectionHeader and -8 or -46
    if controls.unavailable then controls.unavailable:Hide() end
    if not controls.historyToolbar then
        controls.historyToolbar=UI.CreateToolbarSurface(page,true,true)
        controls.historyToolbar:SetFrameLevel(page:GetFrameLevel())
        -- Match the filter strip's host-specific inner rail alignment.
        local outset=page.bootyStandalone and 0 or 4
        controls.historyToolbar.bootyBorderOutsetLeft=outset;controls.historyToolbar.bootyBorderOutsetRight=outset
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
    controls.historyScroll.bootyHistoryMaximum=maximum
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
