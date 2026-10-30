local Raider = BootyRaider
local UI = Raider.UI.Components
local Log = {}
Raider.Modules.RaidLog = Log
local serial = 0
local pageSize = 8
local captions = {
    ["raid.leave"]="Left session", ["raid.reopen"]="Reopened raid", ["raid.start"]="Started raid", ["raid.save"]="Saved raid", ["raid.end"]="Ended raid",
    ["raid.metadata"]="Changed raid details", ["raid.edit"]="Edited saved raid", ["raid.delete"]="Deleted raid",
    ["raid.snapshot.delete"]="Deleted raid snapshot", ["raid.statistic.delete"]="Deleted raid statistics",
    ["sr.edit"]="Changed SR", ["sr.assign"]="Assigned SR", ["sr.clear"]="Removed SR",
    ["sr.link"]="Changed SR link", ["sr.import"]="Imported SR", ["sr.reapply"]="Reapplied custom SR changes",
    ["loot.award"]="Recorded loot", ["loot.correct"]="Corrected loot", ["loot.reset"]="Reset loot history",
    ["csr.archive"]="Archived CSR source", ["csr.activate"]="Activated CSR source",
    ["raid.flags"]="Changed raid options", ["raid.members"]="Changed raid participants",
    ["raid.rules"]="Changed loot rules",
    ["conflict.resolve"]="Resolved conflict", ["raid.merge"]="Merged recordings",
    ["loot.reconcile"]="Reconciled loot recordings",
    ["raid.alias.resolve"]="Resolved recording identities", ["reycoin.set"]="Marked Reycoin used", ["reycoin.reset"]="Reset Reycoin usage",
}
local statusCaptions={accepted="Accepted",pending="Pending decision",rejected="Rejected",partial="Partly accepted"}
local function WithStatus(text,entry)
    local status=statusCaptions[entry.status]
    if status and (entry.status~="accepted" or entry.kind=="conflict.resolve") then return status.." - "..text end
    return text
end

local function Item(value)
    local reference=Raider.Services.ItemReference
    return reference and reference.Name(value) or (tonumber(value) and ("Item #"..value) or tostring(value or ""))
end

function Log.FormatAction(entry)
    local detail=entry.detail or {}
    if entry.kind=="conflict.resolve" and detail.conflictKind=="sr" then
        local item=detail.item and (tonumber(detail.item) and UI.GetItemLabel and UI.GetItemLabel(tonumber(detail.item)) or Item(detail.item)) or "None"
        if tonumber(detail.item) and type(GetItemInfo)=="function" then local _,link=GetItemInfo(tonumber(detail.item));if link then item=link end end
        return "SR conflict for "..tostring(detail.raidName or entry.raidId or "raid")..": "..tostring(detail.player or "Unknown").." SR resolved to "..item
    end
    if entry.kind=="conflict.resolve" and detail.raidName then return "Resolved "..tostring(detail.count or 1).." conflicts for "..detail.raidName end
    local text=entry.kind=="raid.save" and detail.endSession and "Saved and ended raid" or captions[entry.kind] or "Changed raid data"
    if entry.kind=="sr.import" or entry.kind=="sr.reapply" then
        local count=tonumber(detail.count)
        if count then return WithStatus(text..": "..count..(count==1 and " player changed" or " players changed"),entry) end
    end
    if detail.subject and detail.subject~="" then text=text..": "..tostring(detail.subject) end
    if detail.item then text=text.." - "..Item(detail.item) end
    return WithStatus(text,entry)
end

local function Timestamp(value)
    if type(value)~="number" then return "Unknown" end
    return date("%Y-%m-%d %H:%M:%S",value)
end

-- Only the selected change is expanded. The journal validates bounded plain
-- payloads; refreshing rows never copies or formats whole historical batches.
local function Gold(text)
    local color=UI.Theme.colors.goldText
    return string.format("|cff%02x%02x%02x",math.floor(color[1]*255),math.floor(color[2]*255),math.floor(color[3]*255))..text.."|r"
end
local fieldNames={id="Raid ID",raidName="Raid type",name="Player",items="Soft Reserve",exception="Loot rights exception",recipient="Recipient",item="Item",count="Quantity",raidRank="Raid role",subgroup="Group",level="Level",online="Online",guildRank="Guild rank",savedAt="Saved at",endedAt="Ended at",startedAt="Started at",saveCSR="CSR",saveRaidStatistics="Raid statistics"}
local function Value(value,key)
    if value==nil then return "None" end
    if key=="item" then return Item(value) end
    if key=="items" and type(value)=="table" then local names={};for _,item in ipairs(value) do table.insert(names,Item(item)) end;return table.getn(names)>0 and table.concat(names,", ") or "None" end
    if type(value)=="boolean" then return value and "Yes" or "No" end
    if type(value)=="table" then return "Nested values" end
    if key=="savedAt" or key=="endedAt" or key=="startedAt" then return Timestamp(value) end
    return tostring(value)
end
local function Field(value,key)
    if type(value)=="table" then return value[key] end
end
function Log.FormatChange(change)
    local key=change.key or "";local before=change.before;local after=change.value
    if change.beforeDeleted then before=nil end
    if change.deleted then after=nil end
    local subject=string.sub(key,1,3)=="sr:" and ("Soft Reserve: "..tostring(type(after)=="table" and after.name or type(before)=="table" and before.name or string.sub(key,4)))
        or string.sub(key,1,5)=="loot:" and "Loot" or key=="raid:lifecycle" and "Session status" or key=="raid:metadata" and "Raid details" or "Changed data"
    local lines={Gold(subject),""};local shown=0
    local function Diff(old,new,path,field,depth)
        if Raider.Services.RaidJournal and Raider.Services.RaidJournal.Equal(old,new) or old==new then return end
        if shown>=12 then return end
        if (type(old)=="table" or type(new)=="table") and field~="items" and depth<5 then
            local keys={};for k in pairs(type(old)=="table" and old or {}) do keys[k]=true end;for k in pairs(type(new)=="table" and new or {}) do keys[k]=true end
            local sorted={};for k in pairs(keys) do table.insert(sorted,k) end;table.sort(sorted,function(a,b)return tostring(a)<tostring(b) end)
            for _,k in ipairs(sorted) do
                if k~="custom" and k~="sourceName" then Diff(Field(old,k),Field(new,k),path=="" and (fieldNames[k] or tostring(k)) or path.." / "..(fieldNames[k] or tostring(k)),k,depth+1) end
            end
        else
            shown=shown+1;table.insert(lines,Gold((path~="" and path or subject)..":").." "..Value(old,field).." → "..Value(new,field))
        end
    end
    Diff(before,after,"",nil,0)
    if shown==0 then table.insert(lines,change.deleted and "Removed." or "No visible value changed.") end
    if shown>=12 then table.insert(lines,"Further fields omitted from this summary.") end
    if change.status and change.status~="accepted" then table.insert(lines,"\n"..Gold("Status:").." "..(statusCaptions[change.status] or change.status)) end
    return table.concat(lines,"\n")
end

local function Label(parent,text,x,y,width)
    local label=UI.CreateLabel(parent,nil,"OVERLAY","GameFontHighlightSmall")
    label:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);label:SetWidth(width)
    label:SetJustifyH("LEFT");label:SetJustifyV("TOP");label:SetText(text)
    return label
end

local function Dialog(parent,title,width,height)
    local frame=UI.CreateContainer(nil,UIParent)
    frame:SetWidth(width);frame:SetHeight(height);frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame.title=UI.CreateHeading(frame,title,3,"gold","rules")
    frame.close=UI.CreateWindowButton(frame,nil,"close")
    UI.Window.StyleProjectDialog(frame,"rules")
    if UI.WindowStack then UI.WindowStack.SetOwner(frame,parent) end
    frame.close:SetScript("OnClick",function() frame:Hide() end)
    local sizes=Raider.Database.Ensure().raidDialogSizes or {};Raider.Database.Ensure().raidDialogSizes=sizes
    local saved=sizes[title] or {}
    UI.Window.MakeResizable(frame,{minWidth=title=="Raid Log" and 520 or 480,minHeight=title=="Raid Log" and 200 or 240,width=saved.width,height=saved.height,
        save=function(w,h) sizes[title]={width=w,height=h} end})
    frame:Hide()
    return frame
end

local function DefaultProvider(raidId,offset,limit)
    return Raider.Services.RaidAudit.GetLogSummary(raidId,offset,limit)
end
local function NeedsRecording(raidId)
    local runtime=Raider.Runtime
    local current=runtime and runtime.GetAttendance and runtime.GetAttendance()
    if not current or current.syncRaidId~=raidId or current.syncEnded then return false end
    local replica=runtime.replica
    if replica and replica.GetRaidInfo and replica.GetRaidInfo(raidId).lifecycle=="ended" then return false end
    local audit=Raider.Services.RaidAudit
    return audit and not audit.IsLogRecording(raidId) or false
end

local dialog
function Log.Open(record,owner)
    local id=type(record)=="table" and record.syncRaidId or record
    if type(id)~="string" or id=="" then return false,"No Raid Log is available for this raid." end
    if not dialog then dialog=Log.Create(owner) end
    if UI.WindowStack then UI.WindowStack.SetOwner(dialog.frame,owner) end
    dialog:Open(id)
    dialog.revision=Raider.Services.RaidAudit.GetRevision(id)
    if UI.WindowStack then UI.WindowStack.Raise(dialog.frame,owner) end
    return true,dialog
end

function Log.RefreshVisible()
    if not dialog or not dialog:IsVisible() or not dialog.raidId then return end
    local revision=Raider.Services.RaidAudit.GetRevision(dialog.raidId)
    if revision~=dialog.revision or dialog.recordingRequired~=NeedsRecording(dialog.raidId) then dialog.revision=revision;dialog:Refresh() end
end

function Log.Close()
    if dialog then dialog:Close() end
end

function Log.Create(parent)
    serial=serial+1
    local id=serial
    local frame=Dialog(parent,"Raid Log",820,340)
    local controller={frame=frame,rows={},offset=0}
    controller.startRecording=UI.CreateButton(frame,nil,"Start Recording Raid Events",240,26)
    controller.startRecording:SetPoint("CENTER",frame,"CENTER",0,0)
    UI.StyleActionButton(controller.startRecording)
    UI.AttachTooltip(controller.startRecording,"Record Raid Log","Record future officer actions performed on this character for this raid. Live Tracking and raid synchronization are unchanged.")
    controller.startRecording:SetScript("OnClick",function()
        local ok,reason=Raider.Services.RaidAudit.StartLogRecording(controller.raidId)
        if not ok then if Raider.Runtime and Raider.Runtime.Print then Raider.Runtime.Print(reason) end;return end
        controller:Refresh()
    end)
    controller.startRecording:Hide()
    controller.hint=Label(frame,"Click an action for before/after details.",10,-36,800)
    local headings={"Timestamp","Nickname","Action"}
    local positions,widths={10,156,260},{140,98,550}
    controller.headings={}
    for index=1,3 do
        local label=Label(frame,headings[index],positions[index],-58,widths[index])
        label:SetTextColor(unpack(UI.Theme.colors.goldText));controller.headings[index]=label
    end
    controller.empty=Label(frame,"No officer changes recorded for this raid.",10,-84,800)
    controller.previous=UI.CreateButton(frame,nil,"<",26,22)
    controller.next=UI.CreateButton(frame,nil,">",26,22)
    controller.previous:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",10,10)
    controller.next:SetPoint("LEFT",controller.previous,"RIGHT",6,0)
    controller.count=UI.CreateLabel(frame,nil,"OVERLAY","GameFontHighlightSmall")
    controller.count:SetPoint("LEFT",controller.next,"RIGHT",8,0)

    local detail
    local function ShowChange()
        if not detail or not detail.entry then return end
        local changes=detail.entry.changes
        local total=changes and table.getn(changes) or detail.entry.changeCount or 0
        detail.index=math.max(1,math.min(detail.index,total))
        local change
        if changes then change=changes[detail.index]
        else change,total=Raider.Services.RaidAudit.GetChange(detail.entry.id,detail.index) end
        if change and change.operationStatus then detail.entry.status=change.operationStatus end
        detail.summary:SetText(Gold(Log.FormatAction(detail.entry)).."\n"..tostring(detail.entry.author or "Unknown").."  •  "..Gold(Timestamp(detail.entry.timestamp)))
        detail.text:SetText(change and Log.FormatChange(change) or "No record details.")
        detail.count:SetText(total==0 and "No changes" or ("Change "..detail.index.." / "..total))
        UI.SetButtonEnabled(detail.previous,detail.index>1)
        UI.SetButtonEnabled(detail.next,detail.index<total)
        detail.canvas.layoutViewport:SetVerticalScroll(0)
        UI.LayoutResponsiveCanvas(detail.canvas,function(width)
            detail.text:SetWidth(math.max(1,width-12));detail.text:SetHeight(0)
            return UI.MeasureTextHeight(detail.text,math.max(1,width-12),true)+12
        end,nil,detail:GetWidth()-20,detail:GetHeight()-106)
    end
    function controller:ShowDetails(entry)
        if not self:IsVisible() or not entry then return end
        if not detail then
            detail=Dialog(frame,"Raid Log details",660,348)
            self.details=detail
            detail.summary=Label(detail,"",10,-36,640);detail.summary:SetHeight(32)
            UI.AttachLabelTooltip(detail,detail.summary,"Raid Log",function() return detail.summary:GetText() end)
            detail.body=UI.CreateContainer(nil,detail)
            detail.body:SetPoint("TOPLEFT",detail,"TOPLEFT",10,-72);detail.body:SetWidth(640);detail.body:SetHeight(242)
            detail.canvas=UI.CreateResponsiveCanvas(detail.body,"BootyRaiderLogDetail"..id)
            detail.text=Label(detail.canvas,"",6,-6,628)
            if detail.text.SetWordWrap then detail.text:SetWordWrap(true) end
            if detail.text.SetNonSpaceWrap then detail.text:SetNonSpaceWrap(true) end
            detail.previous=UI.CreateButton(detail,nil,"<",26,22)
            detail.next=UI.CreateButton(detail,nil,">",26,22)
            detail.previous:SetPoint("BOTTOMLEFT",detail,"BOTTOMLEFT",10,8)
            detail.next:SetPoint("LEFT",detail.previous,"RIGHT",6,0)
            detail.count=UI.CreateLabel(detail,nil,"OVERLAY","GameFontHighlightSmall")
            detail.count:SetPoint("LEFT",detail.next,"RIGHT",8,0)
            detail.previous:SetScript("OnClick",function() detail.index=detail.index-1;ShowChange() end)
            detail.next:SetScript("OnClick",function() detail.index=detail.index+1;ShowChange() end)
            function detail:LayoutContent(w,h)
                self.summary:SetWidth(w-20);self.body:SetWidth(w-20);self.body:SetHeight(h-106)
                UI.LayoutResponsiveCanvas(self.canvas,function(width)
                    self.text:SetWidth(math.max(1,width-12));self.text:SetHeight(0)
                    return UI.MeasureTextHeight(self.text,math.max(1,width-12),true)+12
                end,nil,w-20,h-106)
            end
            detail:SetScript("OnHide",function() detail.entry=nil;detail.text:SetText("");detail.summary:SetText("") end)
        end
        detail.entry=entry;detail.index=1
        detail.summary:SetText(Timestamp(entry.timestamp).."  |  "..tostring(entry.author or "Unknown").."\n"..Log.FormatAction(entry))
        detail:Show();detail:LayoutContent(detail:GetWidth(),detail:GetHeight());ShowChange()
        if UI.WindowStack then UI.WindowStack.Raise(detail,frame) end
    end

    for index=1,pageSize do
        local row=UI.CreateControl(nil,frame)
        row:SetWidth(800);row:SetHeight(26);row.cells={}
        for cell=1,3 do
            row.cells[cell]=Label(row,"",positions[cell]-10+4,-5,widths[cell]-8)
            if cell==1 then row.cells[cell]:SetTextColor(unpack(UI.Theme.colors.goldText)) end
            if row.cells[cell].SetWordWrap then row.cells[cell]:SetWordWrap(false) end
        end
        row:SetScript("OnClick",function() controller:ShowDetails(this.entry) end)
        UI.AttachTooltip(row,"Raid Log",function()
            if not row.entry then return "" end
            return Timestamp(row.entry.timestamp).." - "..tostring(row.entry.author or "Unknown").."\n"..Log.FormatAction(row.entry)
        end)
        UI.StyleSelectableTableRow(row,math.mod(index,2)==0,false)
        controller.rows[index]=row
    end

    function controller:Refresh()
        local pageSize=self.pageSize or 8
        if not self:IsVisible() or not self.raidId then return end
        self.recordingRequired=NeedsRecording(self.raidId)
        for _,widget in ipairs({self.hint,self.previous,self.next,self.count}) do if self.recordingRequired then widget:Hide() else widget:Show() end end
        for _,heading in ipairs(self.headings) do if self.recordingRequired then heading:Hide() else heading:Show() end end
        if self.recordingRequired then
            self.startRecording:Show();self.empty:Hide()
            if detail then detail:Hide() end
            for _,row in ipairs(self.rows) do row.entry=nil;row:Hide() end
            return
        end
        self.startRecording:Hide()
        local entries,total=self.provider(self.raidId,self.offset,pageSize)
        if type(entries)~="table" or type(total)~="number" then error("Raid Log provider must return entries and total") end
        local offset=math.max(0,math.floor(math.max(0,total-1)/pageSize)*pageSize)
        if self.offset>offset then
            self.offset=offset;entries,total=self.provider(self.raidId,self.offset,pageSize)
        end
        self.total=total
        local y=80
        for index=1,pageSize do
            local row,entry=self.rows[index],entries[index]
            row.entry=entry
            if entry then
                local texts={Timestamp(entry.timestamp),tostring(entry.author or "Unknown"),Log.FormatAction(entry)}
                local height=26
                for cell=1,3 do
                    row.cells[cell]:SetText(texts[cell]);row.cells[cell]:SetHeight(16)
                end
                row:ClearAllPoints();row:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-y)
                row:SetHeight(height);row:Show();y=y+height
            else
                row:Hide()
                for cell=1,3 do row.cells[cell]:SetText("") end
            end
        end
        for index=pageSize+1,8 do self.rows[index].entry=nil;self.rows[index]:Hide() end
        if total==0 then self.empty:Show();y=112 else self.empty:Hide() end
        -- Keep the user-selected window height.
        self.count:SetText(total==0 and "0 actions" or (self.offset+1).."-"..math.min(self.offset+pageSize,total).." / "..total.." actions")
        UI.SetButtonEnabled(self.previous,self.offset>0)
        UI.SetButtonEnabled(self.next,self.offset+pageSize<total)
        if detail and detail:IsVisible() and detail.entry then ShowChange() end
    end
    function frame:LayoutContent(w,h)
        controller.hint:SetWidth(w-20);controller.empty:SetWidth(w-20)
        local previous=controller.pageSize;controller.pageSize=math.max(1,math.min(pageSize,math.floor((h-116)/26)))
        local actionWidth=w-270;controller.headings[3]:SetWidth(actionWidth)
        for _,row in ipairs(controller.rows) do row:SetWidth(w-20);row.cells[3]:SetWidth(actionWidth-8) end
        if previous~=nil and previous~=controller.pageSize and controller:IsVisible() and controller.raidId then controller:Refresh() end
    end
    function controller:Open(raidId,provider)
        self.raidId=raidId;self.provider=provider or DefaultProvider;self.offset=0
        if detail then detail:Hide() end
        frame:Show();frame:LayoutContent(frame:GetWidth(),frame:GetHeight());self:Refresh()
        if UI.WindowStack then UI.WindowStack.Raise(frame,parent) end
    end
    function controller:Close() frame:Hide() end
    function controller:IsVisible() return frame:IsVisible() end
    controller.previous:SetScript("OnClick",function() controller.offset=math.max(0,controller.offset-(controller.pageSize or pageSize));controller:Refresh() end)
    controller.next:SetScript("OnClick",function()
        if controller.offset+(controller.pageSize or pageSize)<(controller.total or 0) then controller.offset=controller.offset+(controller.pageSize or pageSize);controller:Refresh() end
    end)
    frame:SetScript("OnHide",function()
        if detail then detail:Hide();detail.entry=nil;detail.text:SetText("");detail.summary:SetText("") end
        for _,row in ipairs(controller.rows) do row.entry=nil;for _,cell in ipairs(row.cells) do cell:SetText("") end end
        controller.provider=nil;controller.raidId=nil;controller.total=nil;controller.revision=nil
    end)
    return controller
end
