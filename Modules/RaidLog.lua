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
    ["raid.session.delete"]="Deleted active raid session",
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
local fieldNames={id="Raid ID",raidName="Raid type",name="Player",items="Soft Reserve",srItems="Soft Reserve",lootItems="Loot",exception="Loot rights exception",recipient="Recipient",item="Item",itemId="Item",count="Quantity",raidRank="Raid role",subgroup="Group",level="Level",online="Online",guildRank="Guild rank",class="Class",classFile="Class",attendance="Attendance",savedAt="Saved at",endedAt="Ended at",startedAt="Started at",joinedAt="Joined raid",leftAt="Left raid",timestamp="Received at",saveCSR="CSR",saveRaidStatistics="Raid statistics"}
local function Value(value,key)
    if value==nil then return "None" end
    if key=="item" or key=="itemId" then return Item(value) end
    if key=="items" and type(value)=="table" then local names={};for _,item in ipairs(value) do table.insert(names,Item(item)) end;return table.getn(names)>0 and table.concat(names,", ") or "None" end
    if type(value)=="boolean" then return value and "Yes" or "No" end
    if type(value)=="table" then return "Nested values" end
    if key=="savedAt" or key=="endedAt" or key=="startedAt" or key=="joinedAt" or key=="leftAt" or key=="timestamp" then return Timestamp(value) end
    return tostring(value)
end

local function Field(value,key) if type(value)=="table" then return value[key] end end
local function White(text) return "|cffffffff"..tostring(text or "None").."|r" end
local function Same(a,b) return Raider.Services.RaidJournal and Raider.Services.RaidJournal.Equal(a,b) or a==b end
local function DetailsFields(change)
    local fields={}
    if not change then return fields end
    local key=change.key or "";local archived=string.sub(key,1,8)=="archive:"
    if archived then key=string.sub(key,9) end
    local before,after=change.before,change.value
    if change.beforeDeleted then before=nil end;if change.deleted then after=nil end
    if archived and string.find(key,"^saved:") then if before==false then before=nil end;if after==false then after=nil end end
    local function Add(label,old,new,field,rightLabel)
        if table.getn(fields)>=24 then fields.omitted=true;return end
        table.insert(fields,{leftLabel=label,rightLabel=rightLabel or label,before=old,after=new,field=field})
    end
    if string.find(key,"^sr:") then
        local name=Field(after,"name") or Field(before,"name") or string.sub(key,4)
        Add("Player",Field(before,"name") or name,Field(after,"name") or name,"name")
        Add("Previous SR",Field(before,"optOut") and "No Soft Reserve" or Field(before,"items") or Field(before,"item"),Field(after,"optOut") and "No Soft Reserve" or Field(after,"items") or Field(after,"item"),"items","New SR")
        if not Same(Field(before,"exception"),Field(after,"exception")) then Add("Loot rights exception",Field(before,"exception"),Field(after,"exception"),"exception") end
        return fields
    end
    if string.find(key,"^loot:") then
        Add("Recipient",Field(before,"recipient"),Field(after,"recipient"),"recipient")
        Add("Item",Field(before,"item"),Field(after,"item"),"item")
        Add("Quantity",Field(before,"count"),Field(after,"count"),"count")
        if Field(before,"timestamp") or Field(after,"timestamp") then Add("Received at",Field(before,"timestamp"),Field(after,"timestamp"),"timestamp") end
        return fields
    end
    local named=string.find(key,"^member:") or string.find(key,"^saved:member:")
    if named then Add("Player",Field(before,"name") or Field(after,"name"),Field(after,"name") or Field(before,"name"),"name") end
    local function Walk(old,new,path,field,depth)
        if Same(old,new) then return end
        if field=="items" or field=="srItems" or field=="lootItems" or field=="item" or field=="itemId" then Add(path,old,new,field);return end
        if (type(old)=="table" or type(new)=="table") and depth<4 then
            local keys={};for k in pairs(type(old)=="table" and old or {}) do keys[k]=true end;for k in pairs(type(new)=="table" and new or {}) do keys[k]=true end
            local sorted={};for k in pairs(keys) do table.insert(sorted,k) end;table.sort(sorted,function(a,b)return tostring(a)<tostring(b) end)
            for _,k in ipairs(sorted) do
                if k~="custom" and k~="sourceName" and k~="syncRecordId" and k~="historyKey" and not (named and k=="name") then
                    local label=fieldNames[k] or tostring(k)
                    Walk(Field(old,k),Field(new,k),path=="" and label or path.." / "..label,k,depth+1)
                end
            end
        else Add(path~="" and path or (key=="raid:lifecycle" and "Session status" or "Value"),old,new,field) end
    end
    Walk(before,after,"",nil,0)
    return fields
end

local function ItemValues(value,field)
    if value==nil or value==false then return {} end
    if field=="item" or field=="itemId" or type(value)~="table" then return {value} end
    return value
end
function Log.FormatChange(change)
    local key=change.key or "";local before=change.before;local after=change.value
    if string.sub(key,1,8)=="archive:" then key=string.sub(key,9) end
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
    local function ItemControl(parent)
        local control=UI.CreateControl(nil,parent)
        control.label=Label(control,"",0,0,100)
        control.label:SetTextColor(1,1,1)
        if control.label.SetWordWrap then control.label:SetWordWrap(true) end
        if control.label.SetNonSpaceWrap then control.label:SetNonSpaceWrap(true) end
        control:SetScript("OnEnter",function()
            UI.ShowItemTooltip(this)
            if detail and detail:IsShown() then detail:LayoutContent(detail:GetWidth(),detail:GetHeight()) end
        end)
        control:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        control:SetScript("OnClick",function() UI.HandleItemClick(this) end)
        return control
    end
    local function Cell(parent)
        local cell=UI.CreateContainer(nil,parent);cell.links={}
        cell.caption=Label(cell,"",0,0,100);cell.caption:SetTextColor(unpack(UI.Theme.colors.goldText))
        cell.text=Label(cell,"",0,-18,100);cell.text:SetTextColor(1,1,1)
        if cell.text.SetWordWrap then cell.text:SetWordWrap(true) end
        if cell.text.SetNonSpaceWrap then cell.text:SetNonSpaceWrap(true) end
        return cell
    end
    local function LayoutCell(cell,value,field,label,width)
        cell:SetWidth(width);cell.caption:SetText(label..":");cell.caption:SetWidth(0);cell.caption:SetHeight(0)
        local captionWidth=math.min(cell.caption:GetStringWidth(),width*0.6)
        cell.caption:SetWidth(captionWidth)
        local captionHeight=UI.MeasureTextHeight(cell.caption,captionWidth,true);cell.caption:SetHeight(captionHeight)
        local valueX=captionWidth+8;local valueWidth=math.max(1,width-valueX)
        local y=0;local items=field=="items" or field=="srItems" or field=="lootItems" or field=="item" or field=="itemId"
        local values=items and ItemValues(value,field) or nil
        local count=values and table.getn(values) or 0
        if count>0 then
            cell.text:Hide()
            for index=1,math.min(count,40) do
                local control=cell.links[index]
                if not control then control=ItemControl(cell);cell.links[index]=control end
                local item=values[index];local reference=type(item)=="table" and (item.itemId or item.name or item.item) or item
                control.itemId=tonumber(reference);control.itemName=type(item)=="table" and item.name or (type(reference)=="string" and reference or nil)
                local quantity=type(item)=="table" and tonumber(item.count) or 1
                control.labelSuffix=quantity and quantity>1 and (" x "..quantity) or ""
                control.label:SetText((control.itemId and UI.GetItemLabel(control.itemId) or tostring(reference or "None"))..control.labelSuffix)
                control:ClearAllPoints();control:SetPoint("TOPLEFT",cell,"TOPLEFT",valueX,-y);control:SetWidth(valueWidth)
                control.label:SetWidth(valueWidth);control.label:SetHeight(0)
                local height=math.max(18,UI.MeasureTextHeight(control.label,valueWidth,true));control.label:SetHeight(height);control:SetHeight(height)
                control:EnableMouse(control.itemId~=nil);control:Show();y=y+height+2
            end
            if count>40 then cell.text:SetText(White((count-40).." additional items."));cell.text:Show() end
        else cell.text:SetText(White(items and "None" or Value(value,field)));cell.text:Show() end
        if cell.text:IsShown() then
            cell.text:ClearAllPoints();cell.text:SetPoint("TOPLEFT",cell,"TOPLEFT",valueX,-y);cell.text:SetWidth(valueWidth);cell.text:SetHeight(0)
            local height=UI.MeasureTextHeight(cell.text,valueWidth,true);cell.text:SetHeight(height);y=y+height
        end
        for index=math.min(count,40)+1,table.getn(cell.links) do cell.links[index].itemId=nil;cell.links[index]:Hide() end
        y=math.max(y,captionHeight);cell:SetHeight(y);cell:Show();return y
    end
    local function LayoutDetails(width,height)
        if not detail or not detail.entry then return end
        detail.summary:SetWidth(width-20);detail.summary:SetHeight(0)
        local summaryHeight=UI.MeasureTextHeight(detail.summary,width-20,true);detail.summary:SetHeight(summaryHeight)
        local top=36+summaryHeight+8;local bodyHeight=math.max(1,height-top-40)
        detail.body:ClearAllPoints();detail.body:SetPoint("TOPLEFT",detail,"TOPLEFT",10,-top);detail.body:SetWidth(width-20);detail.body:SetHeight(bodyHeight)
        UI.LayoutResponsiveCanvas(detail.canvas,function(available)
            local gap=16;local column=math.max(1,(available-gap)/2)
            detail.before:SetWidth(column);detail.after:ClearAllPoints();detail.after:SetPoint("TOPLEFT",detail.canvas,"TOPLEFT",column+gap,0);detail.after:SetWidth(column)
            local y=24
            for index,field in ipairs(detail.fields or {}) do
                local row=detail.fieldRows[index]
                if not row then row={left=Cell(detail.canvas),right=Cell(detail.canvas)};detail.fieldRows[index]=row end
                row.left:ClearAllPoints();row.left:SetPoint("TOPLEFT",detail.canvas,"TOPLEFT",0,-y)
                row.right:ClearAllPoints();row.right:SetPoint("TOPLEFT",detail.canvas,"TOPLEFT",column+gap,-y)
                local left=LayoutCell(row.left,field.before,field.field,field.leftLabel,column)
                local right=LayoutCell(row.right,field.after,field.field,field.rightLabel,column)
                y=y+math.max(left,right)+8
            end
            for index=table.getn(detail.fields or {})+1,table.getn(detail.fieldRows) do detail.fieldRows[index].left:Hide();detail.fieldRows[index].right:Hide() end
            detail.empty:ClearAllPoints();detail.empty:SetPoint("TOPLEFT",detail.canvas,"TOPLEFT",0,-y);detail.empty:SetWidth(available)
            if table.getn(detail.fields or {})==0 then detail.empty:SetText("No record details.");detail.empty:Show();y=y+20
            elseif detail.fields.omitted then detail.empty:SetText("Further changed fields omitted from this summary.");detail.empty:Show();y=y+28 else detail.empty:Hide() end
            return y
        end,nil,width-20,bodyHeight)
    end
    local function ShowChange()
        if not detail or not detail.entry then return end
        local changes=detail.entry.changes
        local total=changes and table.getn(changes) or detail.entry.changeCount or 0
        detail.index=math.max(1,math.min(detail.index,total))
        local change
        if changes then change=changes[detail.index]
        else change,total=Raider.Services.RaidAudit.GetChange(detail.entry.id,detail.index) end
        if change and change.operationStatus then detail.entry.status=change.operationStatus end
        local action=string.gsub(string.gsub(Log.FormatAction(detail.entry),"|c%x%x%x%x%x%x%x%x",""),"|r","")
        detail.summary:SetText(Gold("Who:").." "..White(detail.entry.author or "Unknown").."\n"..Gold("Action:").." "..White(action).."\n"..Gold("Time:").." "..White(Timestamp(detail.entry.timestamp)))
        if change and change.status and change.status~="accepted" then detail.summary:SetText(detail.summary:GetText().."\n"..Gold("Status:").." "..White(statusCaptions[change.status] or change.status)) end
        detail.fields=DetailsFields(change)
        detail.count:SetText(total==0 and "No changes" or ("Change "..detail.index.." / "..total))
        UI.SetButtonEnabled(detail.previous,detail.index>1);UI.SetButtonEnabled(detail.next,detail.index<total)
        detail.canvas.layoutViewport:SetVerticalScroll(0)
        LayoutDetails(detail:GetWidth(),detail:GetHeight())
    end
    function controller:ShowDetails(entry)
        if not self:IsVisible() or not entry then return end
        if not detail then
            detail=Dialog(frame,"Raid Log details",660,348);self.details=detail;detail.fieldRows={}
            detail.summary=Label(detail,"",10,-36,640);detail.summary:SetTextColor(1,1,1)
            if detail.summary.SetWordWrap then detail.summary:SetWordWrap(true) end
            if detail.summary.SetNonSpaceWrap then detail.summary:SetNonSpaceWrap(true) end
            detail.body=UI.CreateContainer(nil,detail)
            detail.canvas=UI.CreateResponsiveCanvas(detail.body,"BootyRaiderLogDetail"..id)
            detail.before=Label(detail.canvas,"Before",0,0,300);detail.before:SetTextColor(unpack(UI.Theme.colors.goldText))
            detail.after=Label(detail.canvas,"After",320,0,300);detail.after:SetTextColor(unpack(UI.Theme.colors.goldText))
            detail.empty=Label(detail.canvas,"",0,0,640)
            detail.previous=UI.CreateButton(detail,nil,"<",26,22);detail.next=UI.CreateButton(detail,nil,">",26,22)
            detail.previous:SetPoint("BOTTOMLEFT",detail,"BOTTOMLEFT",10,8);detail.next:SetPoint("LEFT",detail.previous,"RIGHT",6,0)
            detail.count=UI.CreateLabel(detail,nil,"OVERLAY","GameFontHighlightSmall");detail.count:SetPoint("LEFT",detail.next,"RIGHT",8,0)
            detail.previous:SetScript("OnClick",function() detail.index=detail.index-1;ShowChange() end)
            detail.next:SetScript("OnClick",function() detail.index=detail.index+1;ShowChange() end)
            function detail:LayoutContent(w,h) if self:IsShown() then LayoutDetails(w,h) end end
            detail:SetScript("OnHide",function()
                detail.entry=nil;detail.fields=nil;detail.summary:SetText("")
                for _,row in ipairs(detail.fieldRows) do for _,cell in ipairs({row.left,row.right}) do
                    cell:Hide();for _,link in ipairs(cell.links) do link.itemId=nil;link:Hide() end
                end end
            end)
        end
        detail.entry=entry;detail.index=1;detail:Show();ShowChange()
        if UI.WindowStack then UI.WindowStack.Raise(detail,frame) end
    end

    for index=1,pageSize do
        local row=UI.CreateControl(nil,frame)
        row:SetWidth(800);row:SetHeight(26);row.cells={}
        for cell=1,3 do
            row.cells[cell]=Label(row,"",positions[cell]-10,-5,widths[cell])
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
        for _,row in ipairs(controller.rows) do row:SetWidth(w-20);row.cells[3]:SetWidth(actionWidth) end
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
        if detail then detail:Hide();detail.entry=nil;detail.fields=nil;detail.summary:SetText("") end
        for _,row in ipairs(controller.rows) do row.entry=nil;for _,cell in ipairs(row.cells) do cell:SetText("") end end
        controller.provider=nil;controller.raidId=nil;controller.total=nil;controller.revision=nil
    end)
    return controller
end
