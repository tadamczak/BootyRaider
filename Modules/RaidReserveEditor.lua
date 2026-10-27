local Raider = BootyRaider
local UI = Raider.UI.Components
local Management = Raider.Modules.RaidManagement

local function Dialog(name, title, page)
    local frame = UI.CreateContainer(name, UIParent)
    frame:SetWidth(640); frame:SetHeight(410); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:EnableMouse(true); frame:Hide()
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    UI.Window.ApplyProjectSurface(frame)
    frame.title = UI.CreateHeading(frame, title, 1, "gold", "raids")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    frame.close = UI.CreateWindowButton(frame, nil, "close")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.message = UI.CreateLabel(frame, nil, "OVERLAY", "GameFontHighlightSmall")
    frame.message:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 42)
    frame.message:SetWidth(610); frame.message:SetHeight(32); frame.message:SetJustifyH("LEFT")
    frame.save = UI.CreateButton(frame, nil, "Save", 130, 22)
    frame.save:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    UI.Window.StyleProjectDialog(frame, "raids")
    if UI.WindowStack then UI.WindowStack.SetOwner(frame, page) end
    return frame
end

-- Fixed-size row pools with explicit pages avoid hidden overflowing rows and
-- never allocate new controls while filtering or paging.
local function PagedList(frame, x, width, render, clicked)
    local list = {offset=0, values={}, rows={}}
    list.previous = UI.CreateButton(frame, nil, "<", 26, 20)
    list.previous:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -286)
    list.next = UI.CreateButton(frame, nil, ">", 26, 20)
    list.next:SetPoint("LEFT", list.previous, "RIGHT", 8, 0)
    list.count = UI.CreateLabel(frame, nil, "OVERLAY", "GameFontHighlightSmall")
    list.count:SetPoint("LEFT", list.next, "RIGHT", 8, 0)
    function list:Refresh()
        self.offset = math.max(0, math.min(self.offset, math.max(0, math.floor((table.getn(self.values)-1)/9)*9)))
        for index = 1, 9 do
            local row, value = self.rows[index], self.values[self.offset+index]
            row.value, row.valueIndex = value, self.offset+index
            if value then render(row, value); row:Show() else row:Hide() end
        end
        self.count:SetText(table.getn(self.values) .. " entries")
        if self.offset == 0 then self.previous:Disable() else self.previous:Enable() end
        if self.offset+9 >= table.getn(self.values) then self.next:Disable() else self.next:Enable() end
    end
    for index = 1, 9 do
        local row = UI.CreateSelectionButton(frame, nil, "", width, 22)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -78-(index-1)*23)
        UI.SetButtonLabelInsets(row, 6, 6); row.label:SetJustifyH("LEFT")
        row:SetScript("OnClick", function() if this.value then clicked(this.value, this.valueIndex) end end)
        UI.AttachTooltip(row, "Soft Reserve", function() return row.fullText or "" end)
        list.rows[index] = row
    end
    list.previous:SetScript("OnClick", function() list.offset=math.max(0,list.offset-9); list:Refresh() end)
    list.next:SetScript("OnClick", function() if list.offset+9<table.getn(list.values) then list.offset=list.offset+9; list:Refresh() end end)
    return list
end

local function ItemText(id)
    return Raider.Services.ItemReference.Name(id) or ("Item #" .. id)
end

function Management.CreateReserveEditor(page, getAttendance, refresh)
    local frame = Dialog("BootyRaiderReserveEditor", "Edit Soft Reserves", page)
    local selected, allItems, originalIds, originalException = {}, {}, {}, false
    frame.search = UI.CreateFramedEditBox(frame, nil, 197)
    frame.search:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -42); frame.search:SetAutoFocus(false)
    UI.AttachPlaceholder(frame.search, "Search or type item name...")
    frame.selectedTitle = UI.CreateLabel(frame, nil, "OVERLAY", "GameFontNormalSmall")
    frame.selectedTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 330, -48)
    frame.selectedTitle:SetText("Selected SR (click to remove)")
    local available, chosen
    local itemLoader = UI.CreateTooltip("BootyRaiderReserveItemLoader", frame)
    frame.itemLoader=itemLoader
    local requested = {}
    -- Keep successful lookups for this editor's lifetime, including across
    -- row reuse and transient client cache misses. Never persist UI labels.
    local itemNames, itemLabels = {}, {}
    local function ResolvedName(id)
        return itemNames[tonumber(id)] or ItemText(id)
    end
    local function RefreshItemTick()
        frame.itemWait=frame.itemWait+(arg1 or 0);frame.itemElapsed=frame.itemElapsed+(arg1 or 0)
        if frame.itemElapsed>=0.25 then frame.itemElapsed=0;chosen:Refresh();available:Refresh() end
        if frame.itemWait>=2 then frame:SetScript("OnUpdate",nil);frame.itemWait=nil end
    end
    local function LoadItem(id)
        id=tonumber(id)
        if not id or itemLabels[id] or GetItemInfo(id) or requested[id] then return end
        requested[id]=true
        itemLoader:SetOwner(frame,"ANCHOR_NONE");itemLoader:SetHyperlink("item:"..id..":0:0:0");itemLoader:Hide()
        frame.itemWait=0;frame.itemElapsed=0
        frame:SetScript("OnUpdate",RefreshItemTick)
    end
    local function RenderItem(row, id)
        LoadItem(id)
        row.itemId = tonumber(id)
        if row.itemId and GetItemInfo(row.itemId) then
            itemNames[row.itemId]=Raider.Services.ItemReference.Name(row.itemId)
            itemLabels[row.itemId]=UI.GetItemLabel(row.itemId)
        end
        row.fullText = ResolvedName(id)
        if row.itemId then
            row:SetText(itemLabels[row.itemId] or UI.GetItemLabel(row.itemId))
        else row:SetText(UI.ShortenText(row.fullText, 38)) end
        UI.SetClassicButtonSelected(row, selected[1]==id)
        UI.ApplyDropdownChoiceSurface(row)
    end
    local function Filter()
        local query = string.lower(frame.search:GetText() or "")
        available.values = {}
        for _, id in ipairs(allItems) do
            if query=="" or string.find(string.lower(ResolvedName(id)),query,1,true) or string.find(tostring(id),query,1,true) then
                table.insert(available.values,id)
            end
        end
        available.offset=0; available:Refresh()
    end
    available = PagedList(frame, 12, 295, RenderItem, function(id)
        selected={id}; chosen.values=selected; chosen:Refresh(); available:Refresh()
    end)
    chosen = PagedList(frame, 330, 298, RenderItem, function(_, index)
        table.remove(selected,index); chosen:Refresh(); available:Refresh()
    end)
    for _, list in ipairs({available, chosen}) do
        for _, row in ipairs(list.rows) do
            local enter,leave=row:GetScript("OnEnter"),row:GetScript("OnLeave")
            row:SetScript("OnEnter", function()
                if enter then enter() end
                if this.itemId then
                    UI.ShowItemTooltip(this)
                    -- Tooltip requests can resolve an item immediately. Both
                    -- lists must use the same presentation as subsequent clicks.
                    chosen:Refresh();available:Refresh()
                else UI.AnchorTooltip(this); GameTooltip:SetText(this.fullText); GameTooltip:Show() end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide();if leave then leave() end end)
        end
    end
    frame.addName = UI.CreateButton(frame, nil, "Add name", 90, 22)
    frame.addName:SetPoint("TOPLEFT", frame, "TOPLEFT", 217, -42)
    frame.addName:SetScript("OnClick", function()
        local name = Raider.Services.ItemReference.NormalizeName(frame.search:GetText())
        if not name then frame.message:SetText("Enter an item name (up to 120 characters)."); return end
        selected={name}; chosen.values=selected; chosen:Refresh(); available:Refresh()
        frame.message:SetText("Added by name: " .. name)
    end)
    frame.available, frame.chosen = available, chosen
    frame.search:SetScript("OnTextChanged", Filter)
    frame.exception = UI.CreateCheckButton(nil, frame, "UICheckButtonTemplate")
    frame.exception:SetWidth(22); frame.exception:SetHeight(22)
    frame.exception:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -314)
    frame.exceptionLabel = UI.CreateLabel(frame, nil, "OVERLAY", "GameFontHighlightSmall")
    frame.exceptionLabel:SetPoint("LEFT", frame.exception, "RIGHT", 4, 0)
    frame.exceptionLabel:SetText("Allow to SR without loot rights")
    local function CurrentMember()
        for _,member in ipairs(frame.attendance and frame.attendance.members or {}) do if member.name==frame.memberName then return member end end
    end
    local function Save(confirmed)
        if getAttendance() ~= frame.attendance then frame.message:SetText("The session roster changed. Reopen the editor."); return end
        local member=CurrentMember()
        if not member then frame.message:SetText("This player is no longer in the session. Reopen the editor.");return end
        local hasRights=Raider.Services.Raid.HasSoftReserveRights(member)
        local allowed = not hasRights and frame.exception:GetChecked() and true or false
        if allowed and table.getn(selected)==0 then frame.message:SetText("Select an SR before enabling an exception."); return end
        if not hasRights and not allowed and table.getn(selected)>0 and not confirmed then
            if not frame.confirm then
                frame.confirm=UI.Window.CreateProjectConfirmation("BootyRaiderReserveRightsConfirm","No loot rights","Save anyway","raids")
                if UI.WindowStack then UI.WindowStack.SetOwner(frame.confirm,frame) end
            end
            local confirm=frame.confirm
            confirm.label:SetWidth(confirm:GetWidth()-16);confirm.label:SetHeight(0)
            confirm:Open(frame.memberName.." has no loot rights.\nNo SR exception selected.\nSave this SR anyway?",function() Save(true) end)
            -- Some clients report the old constrained FontString height. The
            -- three explicit lines still need their full line boxes.
            local _,size=confirm.label:GetFont()
            local spacing=confirm.label.GetSpacing and confirm.label:GetSpacing() or 0
            local height=math.max(confirm.label:GetHeight(),3*(size+2)+2*spacing)
            confirm.label:SetHeight(height);confirm:SetHeight(height+78)
            return
        end
        local changed = table.getn(selected) ~= table.getn(originalIds)
        for index, id in ipairs(selected) do if id ~= originalIds[index] then changed = true end end
        if changed or allowed ~= originalException then
            local ok, failure = Raider.Services.RaidRes.SetMemberReservations(frame.attendance,frame.memberName,selected,allowed)
            if not ok then frame.message:SetText(failure); return end
        end
        frame:Hide(); refresh()
    end
    frame.save:SetScript("OnClick",function() Save(false) end)
    function frame:Open(member)
        self.attendance=getAttendance(); self.memberName=member.name
        self.title:SetText("Soft Reserves: " .. member.name)
        local failure
        allItems,failure=Raider.Services.RaidItemCatalog.GetItems(self.attendance.raidName)
        allItems=allItems or {}; selected={}; originalIds={}
        for index,id in ipairs(member.srItemIds or {}) do originalIds[index]=id end
        if originalIds[1] then selected[1]=originalIds[1] end
        originalException=member.srException==true
        local hasRights=Raider.Services.Raid.HasSoftReserveRights(member)
        UI.SetButtonEnabled(self.exception,not hasRights)
        self.exceptionLabel:SetAlpha(hasRights and 0.45 or 1)
        self.exception:SetChecked(not hasRights and originalException); self.message:SetText(failure and "No catalogue for this raid. Type the item name and click Add name." or "Choose one item, or type its name and click Add name. A new choice replaces the previous SR.")
        if table.getn(originalIds)>1 then self.message:SetText("This editor saves one SR. Choose the item to keep; Cancel by closing this window to keep the imported reservations.") end
        chosen.values=selected; chosen.offset=0; chosen:Refresh(); self.search:SetText(""); Filter(); self:Show()
        if selected[1] then
            for index,id in ipairs(available.values) do if id==selected[1] then available.offset=math.floor((index-1)/9)*9;break end end
            available:Refresh()
        end
    end
    frame:SetScript("OnHide", function()
        frame:SetScript("OnUpdate",nil);frame.itemWait=nil;requested={};itemLoader:Hide()
        if frame.confirm then frame.confirm:Hide() end
        allItems={}; selected={}; originalIds={}; available.values={}; chosen.values={}
        available:Refresh(); chosen:Refresh(); frame.attendance=nil
    end)
    return frame
end

function Management.CreateReserveReview(page, getAttendance, refresh)
    local frame=Dialog("BootyRaiderReserveReview", "Reapply custom SR changes", page)
    frame.help=UI.CreateLabel(frame,nil,"OVERLAY","GameFontHighlightSmall")
    frame.help:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-45)
    frame.help:SetText("Select changes to apply to the new import. Unchecked changes will be discarded.")
    frame.selected={}
    frame.list=PagedList(frame,12,616,function(row,change)
        local detail
        if change.kind=="exception" then detail=change.allowed and "Allow SR exception" or "Remove SR exception"
        else
            local labels={}
            for _,id in ipairs(change.itemIds or {}) do table.insert(labels,ItemText(id)) end
            detail=table.getn(labels)>0 and ("Set SR: " .. table.concat(labels,", ")) or "Remove SR"
        end
        row.fullText=change.name .. " - " .. detail
        row:SetText((frame.selected[row.valueIndex] and "[x] " or "[ ] ") .. UI.ShortenText(row.fullText,90))
    end,function(_,index) frame.selected[index]=not frame.selected[index]; frame.list:Refresh() end)
    frame.save:SetText("Apply selected")
    frame.save:SetScript("OnClick",function()
        if getAttendance()~=frame.attendance then frame.message:SetText("The session roster changed. Reopen the review."); return end
        local ok,failure=Raider.Services.RaidRes.ReapplyCustomChanges(frame.attendance,frame.importInfo,frame.selected)
        if not ok then frame.message:SetText(failure); return end
        frame:Hide(); refresh()
    end)
    function frame:Open()
        self.attendance=getAttendance(); self.importInfo=self.attendance and self.attendance.softReserveImport
        local changes=self.importInfo and self.importInfo.customReview
        if table.getn(changes or {})==0 then return false end
        self.selected={}; self.list.values=changes; self.list.offset=0; self.list:Refresh()
        self.message:SetText("Closing this window keeps the review pending. Reopen it from Import SR.")
        if UI.WindowStack then UI.WindowStack.WithOwner(page, function() self:Show() end) else self:Show() end
        return true
    end
    frame:SetScript("OnHide",function() frame.list.values={};frame.list:Refresh();frame.attendance=nil;frame.importInfo=nil;frame.selected={} end)
    return frame
end
