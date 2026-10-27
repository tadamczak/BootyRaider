local Raider = BootyRaider
local UI = Raider.UI.Components
local Sync = {}
Raider.Modules.RaidSync = Sync
local pageSize, serial = 8, 0

local function Label(parent,text,x,y,width,height)
    local label=UI.CreateLabel(parent,nil,"OVERLAY","GameFontHighlightSmall")
    label:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);label:SetWidth(width)
    label:SetJustifyH("LEFT");label:SetJustifyV("TOP");label:SetText(text or "")
    if height then label:SetHeight(height) end
    return label
end
local function Dialog(parent,title,width,height)
    local frame=UI.CreateContainer(nil,UIParent)
    frame:SetWidth(width);frame:SetHeight(height);frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame.title=UI.CreateHeading(frame,title,3,"gold","raids")
    frame.close=UI.CreateWindowButton(frame,nil,"close")
    UI.Window.StyleProjectDialog(frame,"raids")
    if UI.WindowStack then UI.WindowStack.SetOwner(frame,parent) end
    frame.close:SetScript("OnClick",function() frame:Hide() end)
    frame:Hide();return frame
end
local function Button(parent,text,x,y,width,callback)
    local button=UI.CreateButton(parent,nil,text,width,22)
    button:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);button:SetScript("OnClick",callback)
    return button
end
local function Timestamp(value)
    return type(value)=="number" and date("%Y-%m-%d %H:%M:%S",value) or "Unknown time"
end
local function Trim(value) return string.gsub(string.gsub(value or "","^%s+",""),"%s+$","") end
local function Copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=Copy(item) end;return result
end
local function Describe(value,indent,lines)
    if type(value)~="table" then table.insert(lines,indent..tostring(value==nil and "(none)" or value));return end
    local keys={};for key in pairs(value) do table.insert(keys,key) end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    if table.getn(keys)==0 then table.insert(lines,indent.."(empty)") end
    for _,key in ipairs(keys) do
        if type(value[key])=="table" then table.insert(lines,indent..tostring(key)..":");Describe(value[key],indent.."  ",lines)
        else table.insert(lines,indent..tostring(key)..": "..tostring(value[key])) end
    end
end
function Sync.FormatValue(value,deleted)
    if deleted then return "(deleted)" end
    local lines={};Describe(value,"",lines);return table.concat(lines,"\n")
end
local function Item(value)
    local reference=Raider.Services.ItemReference
    return reference and reference.Name(value) or (tonumber(value) and ("Item #"..tostring(value)) or tostring(value or "None"))
end
function Sync.FormatRecord(key,value,deleted)
    if deleted or type(value)~="table" then return Sync.FormatValue(value,deleted) end
    if string.sub(key or "",1,3)=="sr:" then
        return "Player: "..tostring(value.name or string.sub(key,4)).."\nReserved item: "..Item(value.items and value.items[1]).."\nAllow without loot rights: "..(value.exception and "Yes" or "No")
    elseif string.sub(key or "",1,5)=="loot:" then
        return "Recipient: "..tostring(value.recipient or "Unknown").."\nItem: "..Item(value.item).."\nQuantity: "..tostring(value.count or 1)..(value.historyKey and ("\nAward reference: "..tostring(value.historyKey)) or "")
    end
    return Sync.FormatValue(value,deleted)
end
local function RecordName(record)
    local key=record.key or "Raid data"
    local value=record.variant and record.variant.value or record.base and record.base.value
    if string.sub(key,1,3)=="sr:" then return "Soft Reserve: "..tostring(type(value)=="table" and value.name or string.sub(key,4)) end
    if string.sub(key,1,5)=="loot:" then return "Loot: "..Item(type(value)=="table" and value.item).." - "..tostring(type(value)=="table" and value.recipient or "Unknown") end
    local names={["raid:metadata"]="Raid details",["raid:lifecycle"]="Raid session status",["raid:rules"]="Loot rules",["import:sr"]="SR import"}
    return names[key] or key
end
local function Message(controller,text)
    controller.message:SetText(tostring(text or ""))
end
local function TextPane(frame,x,y,width,height,name)
    local host=UI.CreateContainer(nil,frame)
    host:SetPoint("TOPLEFT",frame,"TOPLEFT",x,y);host:SetWidth(width);host:SetHeight(height)
    local canvas=UI.CreateResponsiveCanvas(host,name)
    local text=Label(canvas,"",6,-6,width-12)
    if text.SetWordWrap then text:SetWordWrap(true) end
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(true) end
    local pane={host=host,canvas=canvas,text=text}
    function pane:SetText(value)
        text:SetText(value);canvas.layoutViewport:SetVerticalScroll(0)
        UI.LayoutResponsiveCanvas(canvas,function(resolved)
            text:SetWidth(math.max(1,resolved-12));text:SetHeight(0)
            return UI.MeasureTextHeight(text,math.max(1,resolved-12),true)+12
        end,nil,width,height)
    end
    return pane
end

-- Manual corrections keep one SR item and its exception together. Every record
-- in an atomic conflict needs a choice before the service publishes any of them.
function Sync.ManualValue(kind,original,fields)
    local value=Copy(original or {})
    local item=Trim(fields.item)
    if item=="" then return nil,"Enter one item name or ID." end
    item=tonumber(item) or item
    if kind=="sr" then
        value.items={item};value.exception=fields.exception==true
        return value
    elseif kind=="loot" then
        local recipient=Trim(fields.recipient)
        local count=tonumber(fields.count)
        if recipient=="" then return nil,"Enter the recipient's nickname." end
        if not count or count<1 or count~=math.floor(count) then return nil,"Quantity must be a positive whole number." end
        value.recipient=recipient;value.item=item;value.count=count
        return value
    end
    return nil,"Choose a complete variant for this conflict."
end

function Sync.Create(parent,api)
    serial=serial+1
    local id=serial
    local frame=Dialog(parent,"Raid synchronization",840,490)
    local controller={frame=frame,api=api or Raider.Runtime and Raider.Runtime.replica,rows={},offset=0,tab="sessions"}
    controller.status=Label(frame,"",10,-36,820,32)
    controller.message=Label(frame,"",10,-432,820,32)
    controller.empty=Label(frame,"No entries.",14,-128,800,28)
    controller.count=Label(frame,"",80,-462,250,18)
    controller.previous=Button(frame,"<",10,-458,26,function() controller.offset=math.max(0,controller.offset-pageSize);controller:Refresh() end)
    controller.next=Button(frame,">",42,-458,26,function()
        if controller.offset+pageSize<(controller.total or 0) then controller.offset=controller.offset+pageSize;controller:Refresh() end
    end)
    controller.discover=Button(frame,"Discover",730,-458,100,function()
        local ok,reason=controller.api.Discover()
        Message(controller,ok and "Discovery requested. Available officers can relay their copies." or reason)
        controller:Refresh()
    end)
    controller.tabs={}
    for index,value in ipairs({{"sessions","Sessions"},{"conflicts","Conflicts"},{"peers","Officers"},{"merge","Compare raids"}}) do
        local key=value[1]
        local button=Button(frame,value[2],10+(index-1)*135,-80,128,function() controller:SelectTab(key) end)
        controller.tabs[key]=button
    end
    controller.recover=Button(frame,"Recover and continue",10,-400,180,function()
        if not controller.selected then return end
        local ok,reason=controller.api.Recover(controller.selected.id)
        if ok then
            controller.raidId=controller.selected.id
            Message(controller,"Session recovered. Loot distribution and announcements were not replayed.")
            controller:Refresh()
        else Message(controller,reason) end
    end)
    controller.inspect=Button(frame,"Show conflicts",200,-400,140,function()
        if controller.tab=="sessions" and controller.selected then controller.raidId=controller.selected.id;controller:SelectTab("conflicts")
        elseif controller.tab=="conflicts" and controller.selected then
            if controller.selected.kind=="merge" then controller:ShowCompare(controller.selected.source or string.sub(controller.selected.id,7))
            else controller:ShowConflict(controller.selected.id) end
        elseif controller.tab=="merge" and controller.selected then controller:ShowCompare(controller.selected.id) end
    end)
    controller.selection=Label(frame,"Select an entry.",10,-370,820,24)
    for index=1,pageSize do
        local row=UI.CreateControl(nil,frame)
        row:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-112-(index-1)*32)
        row:SetWidth(820);row:SetHeight(32)
        row.label=Label(row,"",6,-3,808,28)
        if row.label.SetWordWrap then row.label:SetWordWrap(false) end
        row:SetScript("OnClick",function()
            if not row.entry then return end
            controller.selected=row.entry;controller:UpdateSelection()
        end)
        UI.AttachTooltip(row,"Raid synchronization",function() return row.fullText or "" end)
        UI.StyleSelectableTableRow(row,math.mod(index,2)==0,false)
        controller.rows[index]=row
    end

    local conflict,comparison
    local function ConflictCount()
        conflict.chosen=0;for _ in pairs(conflict.choices) do conflict.chosen=conflict.chosen+1 end
        conflict.progress:SetText(conflict.chosen.." / "..tostring(conflict.data and conflict.data.recordCount or 0).." records chosen")
        UI.SetButtonEnabled(conflict.resolve,conflict.data~=nil and conflict.chosen==conflict.data.recordCount)
    end
    local function ConflictRefresh()
        if not conflict or not conflict:IsShown() then return end
        local data,reason=controller.api.GetConflict(controller.raidId,conflict.conflictId,conflict.recordIndex,conflict.index)
        if not data then
            Message(conflict,reason or "This conflict is no longer pending.");conflict.data=nil
            UI.SetButtonEnabled(conflict.use,false);UI.SetButtonEnabled(conflict.manual,false);UI.SetButtonEnabled(conflict.resolve,false);return
        end
        conflict.data=data
        if not conflict.heads then conflict.heads=Copy(data.heads) end
        local record=data.record or {}
        local variant=record.variant or {}
        local base=record.base or {}
        local total=record.variantCount or 0
        conflict.heading:SetText(RecordName(record).."\n"..tostring(variant.author or "Unknown").."  |  "..Timestamp(variant.timestamp))
        conflict.pane:SetText("Agreed base\n"..Sync.FormatRecord(record.key,base.value,base.deleted).."\n\nProposed change\n"..Sync.FormatRecord(record.key,variant.value,variant.deleted))
        conflict.count:SetText("Variant "..conflict.index.." / "..total)
        UI.SetButtonEnabled(conflict.previous,conflict.index>1);UI.SetButtonEnabled(conflict.next,conflict.index<total)
        UI.SetButtonEnabled(conflict.use,total>0)
        UI.SetButtonEnabled(conflict.recordPrevious,conflict.recordIndex>1)
        UI.SetButtonEnabled(conflict.recordNext,conflict.recordIndex<data.recordCount)
        conflict.recordCount:SetText("Record "..conflict.recordIndex.." / "..data.recordCount)
        local kind
        if record.key then local _,_,prefix=string.find(record.key,"^([^:]+):");kind=prefix end
        local manual=kind=="sr" or kind=="loot"
        conflict.manualKind=manual and kind or nil
        local value=type(variant.value)=="table" and variant.value or {}
        conflict.item:SetText(tostring(kind=="sr" and (value.items and value.items[1] or "") or value.item or ""))
        conflict.recipient:SetText(value.recipient or "");conflict.quantity:SetText(tostring(value.count or 1))
        conflict.exception:SetChecked(value.exception==true)
        for _,control in ipairs(conflict.manualControls) do if manual then control:Show() else control:Hide() end end
        for _,control in ipairs(conflict.lootControls) do if manual and kind=="loot" then control:Show() else control:Hide() end end
        for _,control in ipairs({conflict.exception,conflict.exceptionLabel}) do if manual and kind=="sr" then control:Show() else control:Hide() end end
        UI.SetButtonEnabled(conflict.manual,manual)
        conflict.manualHint:SetText(manual and "Or enter a corrected value:" or "Choose a complete variant for this record.")
        Message(conflict,conflict.choices[record.key] and "A choice is saved for this record. Resolve when every record is chosen." or "Choose this record's value. No changes are applied until you resolve the complete conflict.")
        ConflictCount()
    end
    local function ChooseConflict(choice)
        if not conflict.data then return end
        conflict.choices[conflict.data.record.key]=choice
        ConflictCount();Message(conflict,"Choice saved. Resolve when every record is chosen.")
    end
    function controller:ShowConflict(conflictId)
        if not self:IsVisible() then return end
        if not conflict then
            conflict=Dialog(frame,"Resolve raid conflict",780,580);self.conflict=conflict
            conflict.heading=Label(conflict,"",10,-36,760,36)
            conflict.pane=TextPane(conflict,10,-78,760,200,"BootyRaidSyncConflict"..id)
            conflict.previous=Button(conflict,"<",10,-284,26,function() conflict.index=conflict.index-1;ConflictRefresh() end)
            conflict.next=Button(conflict,">",42,-284,26,function() conflict.index=conflict.index+1;ConflictRefresh() end)
            conflict.count=Label(conflict,"",80,-288,240,18)
            conflict.use=Button(conflict,"Choose this variant",590,-284,180,function()
                local variant=conflict.data and conflict.data.record.variant
                if variant then ChooseConflict({revision=variant.revision}) end
            end)
            conflict.recordPrevious=Button(conflict,"< Record",10,-316,92,function() conflict.recordIndex=conflict.recordIndex-1;conflict.index=1;ConflictRefresh() end)
            conflict.recordNext=Button(conflict,"Record >",110,-316,92,function() conflict.recordIndex=conflict.recordIndex+1;conflict.index=1;ConflictRefresh() end)
            conflict.recordCount=Label(conflict,"",212,-320,300,18)
            conflict.manualHint=Label(conflict,"",10,-350,760,20)
            conflict.itemLabel=Label(conflict,"Item name or ID",10,-376,300,18)
            conflict.item=UI.CreateFramedEditBox(conflict,nil,300)
            conflict.item:SetPoint("TOPLEFT",conflict,"TOPLEFT",10,-396);conflict.item:SetAutoFocus(false);conflict.item:SetMaxLetters(255)
            conflict.recipientLabel=Label(conflict,"Recipient",324,-376,200,18)
            conflict.recipient=UI.CreateFramedEditBox(conflict,nil,200)
            conflict.recipient:SetPoint("TOPLEFT",conflict,"TOPLEFT",324,-396);conflict.recipient:SetAutoFocus(false);conflict.recipient:SetMaxLetters(64)
            conflict.quantityLabel=Label(conflict,"Quantity",538,-376,90,18)
            conflict.quantity=UI.CreateFramedEditBox(conflict,nil,90)
            conflict.quantity:SetPoint("TOPLEFT",conflict,"TOPLEFT",538,-396);conflict.quantity:SetAutoFocus(false);conflict.quantity:SetMaxLetters(6)
            conflict.exception=UI.CreateCheckButton(nil,conflict,"UICheckButtonTemplate")
            conflict.exception:SetWidth(22);conflict.exception:SetHeight(22)
            conflict.exception:SetPoint("TOPLEFT",conflict,"TOPLEFT",324,-396)
            conflict.exceptionLabel=Label(conflict,"Allow to SR without loot rights",350,-400,400,22)
            conflict.manual=Button(conflict,"Choose correction",590,-430,180,function()
                local data=conflict.data
                if not data or not conflict.manualKind then return end
                local original=data.record.variant.value or (data.record.base and data.record.base.value)
                local value,reason=Sync.ManualValue(conflict.manualKind,original,{item=conflict.item:GetText(),
                    recipient=conflict.recipient:GetText(),count=conflict.quantity:GetText(),exception=conflict.exception:GetChecked() and true or false})
                if not value then Message(conflict,reason);return end
                if conflict.manualKind=="sr" and not value.name then value.name=string.sub(data.record.key,4) end
                ChooseConflict({value=value})
            end)
            conflict.manualControls={conflict.itemLabel,conflict.item,conflict.manual}
            conflict.lootControls={conflict.recipientLabel,conflict.recipient,conflict.quantityLabel,conflict.quantity}
            conflict.progress=Label(conflict,"",10,-482,400,22)
            conflict.resolve=Button(conflict,"Resolve conflict",590,-478,180,function()
                if not conflict.data or conflict.chosen~=conflict.data.recordCount then return end
                local ok,reason=controller.api.ResolveConflict(controller.raidId,conflict.conflictId,conflict.choices,conflict.heads)
                if not ok then Message(conflict,reason or "The conflict changed. Reopen it before deciding.");return end
                conflict:Hide();controller.selected=nil;Message(controller,"Conflict resolved.");controller:Refresh()
            end)
            conflict.message=Label(conflict,"",10,-510,760,58)
            conflict:SetScript("OnHide",function()
                conflict.data=nil;conflict.conflictId=nil;conflict.pane.text:SetText("");conflict.heading:SetText("")
                conflict.choices=nil;conflict.heads=nil
                conflict.item:SetText("");conflict.recipient:SetText("");conflict.quantity:SetText("")
            end)
        end
        conflict.conflictId=conflictId;conflict.index=1;conflict.recordIndex=1;conflict.choices={};conflict.heads=nil
        conflict:Show();ConflictRefresh()
        if UI.WindowStack then UI.WindowStack.Raise(conflict,frame) end
    end

    local choiceLabels={target="Keep current",source="Use incoming",separate="Separate awards",duplicate="Same award"}
    local function CompareProgress()
        local chosen=0;for _ in pairs(comparison.choices) do chosen=chosen+1 end
        comparison.progress:SetText(chosen.." / "..(comparison.total or 0).." decisions made")
        UI.SetButtonEnabled(comparison.merge,comparison.total~=nil and chosen==comparison.total)
    end
    local function CompareRefresh()
        if not comparison or not comparison:IsShown() then return end
        local data,reason=controller.api.CompareRaids(controller.raidId,comparison.sourceId,comparison.offset,pageSize)
        if not data then Message(comparison,reason or "These raids cannot be merged.");UI.SetButtonEnabled(comparison.merge,false);return end
        if not comparison.token then comparison.token=Copy(data.token) end
        comparison.total=data.total
        local maximum=math.max(0,math.floor(math.max(0,data.total-1)/pageSize)*pageSize)
        if comparison.offset>maximum then comparison.offset=maximum;return CompareRefresh() end
        for index,row in ipairs(comparison.rows) do
            local entry=data.rows[index];row.entry=entry
            if entry then
                row.label:SetText(entry.label or entry.key or entry.id)
                row:Show()
                for choiceIndex,button in ipairs(row.buttons) do
                    local choice=entry.choices[choiceIndex]
                    button.choice=choice;button:SetText(choiceLabels[choice] or choice or "")
                    if choice then button:Show() else button:Hide() end
                    UI.SetClassicButtonSelected(button,comparison.choices[entry.id]==choice)
                end
            else row:Hide();row.label:SetText("") end
        end
        comparison.empty:SetText("No conflicting values. Merge preserves both histories and their original authors.")
        if data.total==0 then comparison.empty:Show() else comparison.empty:Hide() end
        comparison.count:SetText(data.total==0 and "0 decisions" or (comparison.offset+1).."-"..math.min(comparison.offset+pageSize,data.total).." / "..data.total)
        UI.SetButtonEnabled(comparison.previous,comparison.offset>0)
        UI.SetButtonEnabled(comparison.next,comparison.offset+pageSize<data.total)
        CompareProgress()
    end
    function controller:ShowCompare(sourceId)
        if not self:IsVisible() or not self.raidId then return end
        if not comparison then
            comparison=Dialog(frame,"Compare independent raids",840,478);self.comparison=comparison
            comparison.heading=Label(comparison,"",10,-36,820,34)
            comparison.empty=Label(comparison,"",10,-84,820,48)
            comparison.rows={}
            comparison.message=Label(comparison,"",10,-384,820,42)
            comparison.progress=Label(comparison,"",10,-434,400,22)
            comparison.count=Label(comparison,"",80,-358,250,20)
            comparison.previous=Button(comparison,"<",10,-354,26,function() comparison.offset=math.max(0,comparison.offset-pageSize);CompareRefresh() end)
            comparison.next=Button(comparison,">",42,-354,26,function()
                if comparison.offset+pageSize<(comparison.total or 0) then comparison.offset=comparison.offset+pageSize;CompareRefresh() end
            end)
            comparison.merge=Button(comparison,"Merge raids",670,-430,160,function()
                local ok,reason=controller.api.MergeRaids(controller.raidId,comparison.sourceId,{token=comparison.token,choices=comparison.choices})
                if not ok then Message(comparison,reason or "The raids changed. Reopen the comparison before merging.");return end
                comparison:Hide();controller.selected=nil;Message(controller,"Raids merged. Original actions remain in Raid Log.");controller:Refresh()
            end)
            for index=1,pageSize do
                local row=UI.CreateControl(nil,comparison)
                row:SetPoint("TOPLEFT",comparison,"TOPLEFT",10,-78-(index-1)*34)
                row:SetWidth(820);row:SetHeight(32)
                row.label=Label(row,"",6,-4,504,26);row.buttons={}
                if row.label.SetWordWrap then row.label:SetWordWrap(false) end
                for choiceIndex=1,2 do
                    local button=Button(row,"",516+(choiceIndex-1)*154,-4,148,function()
                        if not row.entry or not this.choice then return end
                        comparison.choices[row.entry.id]=this.choice
                        for _,control in ipairs(row.buttons) do UI.SetClassicButtonSelected(control,control.choice==this.choice) end
                        CompareProgress()
                    end)
                    row.buttons[choiceIndex]=button
                end
                row:SetScript("OnClick",function()
                    if not row.entry then return end
                    if not comparison.details then
                        local details=Dialog(comparison,"Compared values",700,350)
                        details.pane=TextPane(details,10,-40,680,298,"BootyRaidSyncMergeDetails"..id)
                        details:SetScript("OnHide",function() details.pane.text:SetText("") end)
                        comparison.details=details
                    end
                    comparison.details.pane:SetText(tostring(row.entry.label or row.entry.key).."\n\nCurrent raid\n"..Sync.FormatRecord(row.entry.key,row.entry.targetValue,row.entry.targetDeleted).."\n\nIncoming raid\n"..Sync.FormatRecord(row.entry.key,row.entry.sourceValue,row.entry.sourceDeleted))
                    comparison.details:Show()
                    if UI.WindowStack then UI.WindowStack.Raise(comparison.details,comparison) end
                end)
                UI.AttachTooltip(row,"Compare raid records",function() return row.entry and ((row.entry.label or row.entry.key or "").."\nClick for complete values. Same award counts once; separate awards both remain.") or "" end)
                UI.StyleSelectableTableRow(row,math.mod(index,2)==0,false)
                comparison.rows[index]=row
            end
            comparison:SetScript("OnHide",function()
                comparison.choices=nil;comparison.token=nil;comparison.sourceId=nil;comparison.total=nil
                if comparison.details then comparison.details:Hide() end
                for _,row in ipairs(comparison.rows) do row.entry=nil;row.label:SetText("") end
            end)
        end
        comparison.sourceId=sourceId;comparison.offset=0;comparison.choices={};comparison.token=nil
        comparison.heading:SetText("Current raid: "..tostring(self.raidName or self.raidId).."\nIncoming raid: "..tostring(self.selected and self.selected.name or sourceId))
        Message(comparison,"Choose each difference explicitly. Click a record to inspect both values.")
        comparison:Show();CompareRefresh()
        if UI.WindowStack then UI.WindowStack.Raise(comparison,frame) end
    end

    function controller:UpdateSelection()
        for _,row in ipairs(self.rows) do UI.StyleSelectableTableRow(row,math.mod(_,2)==0,row.entry~=nil and row.entry==self.selected) end
        self.selection:SetText(self.selected and (self.selected.name or self.selected.subject or self.selected.id or self.selected.key or "") or "Select an entry.")
        if self.tab=="sessions" then self.recover:Show();self.inspect:Show();self.inspect:SetText("Show conflicts")
        elseif self.tab=="conflicts" then self.recover:Hide();self.inspect:Show();self.inspect:SetText("Resolve conflict")
        elseif self.tab=="merge" then self.recover:Hide();self.inspect:Show();self.inspect:SetText("Compare selected")
        else self.recover:Hide();self.inspect:Hide() end
        UI.SetButtonEnabled(self.recover,self.selected~=nil and self.selected.recoverable~=false)
        UI.SetButtonEnabled(self.inspect,self.selected~=nil)
    end
    function controller:SelectTab(tab)
        if self.tab=="sessions" and self.selected then self.raidId=self.selected.id;self.raidName=self.selected.name end
        self.tab=tab;self.offset=0;self.selected=nil;Message(self,"")
        if conflict then conflict:Hide() end
        if comparison then comparison:Hide() end
        self:Refresh()
    end
    local function RowText(tab,entry)
        if tab=="peers" then return tostring(entry.name).."  |  "..tostring(entry.status or "Unknown")..(entry.message and ("\n"..entry.message) or "") end
        if tab=="conflicts" then return tostring(entry.subject or entry.key or entry.id).."  |  "..tostring(entry.kind or "Raid data").."\n"..tostring(entry.variantCount or 0).." competing variants" end
        return tostring(entry.name or entry.displayName or entry.id).."  |  "..tostring(entry.raidType or entry.raidName or "Other").."\n"..tostring(entry.state or "Saved").."  |  "..Timestamp(entry.updatedAt)..(entry.conflicts and entry.conflicts>0 and ("  |  "..entry.conflicts.." conflicts") or "")
    end
    function controller:Refresh(status)
        if not self:IsVisible() then return end
        status=status or self.api.GetStatus(self.raidId)
        self.revision=status.revision
        local localOnly=type(status.localOnly)=="boolean" and (status.localOnly and "Yes" or "No") or tostring(status.localOnly or 0)
        self.status:SetText(tostring(status.message or (status.compatible==false and "Incompatible schema or CSR policy. Synchronization is paused." or "Changes are exchanged with available officers.")).."\nLocal only: "..localOnly.."  |  Pending: "..tostring(status.pending or 0).."  |  Conflicts: "..tostring(status.conflicts or 0))
        local entries,total
        if self.tab=="sessions" then entries,total=self.api.ListRaids(self.offset,pageSize)
        elseif self.tab=="conflicts" then
            if self.raidId then entries,total=self.api.ListConflicts(self.raidId,self.offset,pageSize) else entries,total={},0 end
        elseif self.tab=="merge" then
            if self.raidId then entries,total=self.api.ListMergeCandidates(self.raidId,self.offset,pageSize) else entries,total={},0 end
        else
            entries={};local peers=status.peers or {};total=table.getn(peers)
            for index=self.offset+1,math.min(self.offset+pageSize,total) do table.insert(entries,peers[index]) end
        end
        entries,total=entries or {},total or 0
        local maximum=math.max(0,math.floor(math.max(0,total-1)/pageSize)*pageSize)
        if self.offset>maximum then self.offset=maximum;return self:Refresh(status) end
        self.total=total
        local selectedId=self.selected and (self.selected.id or self.selected.name)
        self.selected=nil
        for index,row in ipairs(self.rows) do
            local entry=entries[index];row.entry=entry;row.fullText=entry and RowText(self.tab,entry) or ""
            row.label:SetText(row.fullText)
            if entry then row:Show();if (entry.id or entry.name)==selectedId then self.selected=entry end else row:Hide() end
        end
        self.empty:SetText((self.tab=="conflicts" or self.tab=="merge") and not self.raidId and "Select a session first." or (self.tab=="conflicts" and "No unresolved conflicts." or "No entries. Use Discover to request available copies."))
        if total==0 then self.empty:Show() else self.empty:Hide() end
        self.count:SetText(total==0 and "0 entries" or (self.offset+1).."-"..math.min(self.offset+pageSize,total).." / "..total)
        UI.SetButtonEnabled(self.previous,self.offset>0);UI.SetButtonEnabled(self.next,self.offset+pageSize<total)
        for key,button in pairs(self.tabs) do UI.SetClassicButtonSelected(button,key==self.tab) end
        self:UpdateSelection()
    end
    function controller:Open(raidId,tab)
        if conflict then conflict:Hide() end
        if comparison then comparison:Hide() end
        self.raidId=raidId;self.raidName=nil;self.offset=0;self.selected=nil;self.tab=tab or "sessions"
        Message(self,"");frame:Show();self:Refresh()
        if UI.WindowStack then UI.WindowStack.Raise(frame,parent) end
    end
    function controller:IsVisible() return frame:IsVisible() end
    function controller:Close() frame:Hide() end
    frame:SetScript("OnHide",function()
        if conflict then conflict:Hide() end
        if comparison then comparison:Hide() end
        for _,row in ipairs(controller.rows) do row.entry=nil;row.fullText=nil;row.label:SetText("") end
        controller.selected=nil;controller.raidId=nil;controller.raidName=nil;controller.revision=nil
    end)
    return controller
end

local current
function Sync.Open(record,owner)
    if not Raider.Runtime or not Raider.Runtime.replica then return false,"Raid synchronization is unavailable." end
    local id=type(record)=="table" and record.syncRaidId or record
    if not current then current=Sync.Create(owner) else current.api=Raider.Runtime.replica end
    if UI.WindowStack then UI.WindowStack.SetOwner(current.frame,owner) end
    current:Open(id);return true,current
end
function Sync.RefreshVisible()
    if not current or not current:IsVisible() then return end
    local status=current.api.GetStatus(current.raidId)
    if status.revision~=current.revision then current:Refresh(status) end
end
function Sync.Close() if current then current:Close();current.api=nil end end
