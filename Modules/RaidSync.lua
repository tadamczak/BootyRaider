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
    local sizes=Raider.Database.Ensure().raidDialogSizes or {};Raider.Database.Ensure().raidDialogSizes=sizes
    local saved=sizes[title] or {}
    UI.Window.MakeResizable(frame,{minWidth=width,minHeight=height,width=saved.width,height=saved.height,
        save=function(w,h) sizes[title]={width=w,height=h} end})
    frame:Hide();return frame
end
local function Button(parent,text,x,y,width,callback)
    local button=UI.CreateButton(parent,nil,text,width,22)
    button:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);button:SetScript("OnClick",callback)
    UI.AttachGoldHoverBorder(button,0.35,0.35,0.35,1)
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
        end,nil,host:GetWidth(),host:GetHeight())
    end
    function pane:Resize(w,h)
        host:SetWidth(w);host:SetHeight(h)
        UI.LayoutResponsiveCanvas(canvas,function(resolved)
            text:SetWidth(math.max(1,resolved-12));text:SetHeight(0)
            return UI.MeasureTextHeight(text,math.max(1,resolved-12),true)+12
        end,nil,w,h)
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
    controller.status=Label(frame,"",10,-36,820,28)
    controller.message=Label(frame,"",10,-432,820,32)
    controller.empty=Label(frame,"No entries.",14,-128,800,28)
    controller.count=Label(frame,"",80,-462,250,18)
    controller.previous=Button(frame,"<",10,-458,26,function() controller.offset=math.max(0,controller.offset-(controller.visiblePageSize or pageSize));controller:Refresh() end)
    controller.next=Button(frame,">",42,-458,26,function()
        if controller.offset+(controller.visiblePageSize or pageSize)<(controller.total or 0) then controller.offset=controller.offset+(controller.visiblePageSize or pageSize);controller:Refresh() end
    end)
    controller.retry=Button(frame,"Retry sync",690,-458,120,function()
        local ok,reason=controller.api.Discover();Message(controller,ok and "Retrying officer synchronization." or reason);controller:Refresh()
    end)
    UI.SetClassicButtonIcon(controller.retry,"refresh",13,7,2);controller.retry:Hide()
    controller.tabs={}
    for index,value in ipairs({{"sessions","Raids"},{"log","Sync log"}}) do
        local key=value[1]
        controller.tabs[key]=Button(frame,value[2],10+(index-1)*98,-82,92,function() controller:SelectTab(key) end)
        UI.SetClassicButtonIcon(controller.tabs[key],key=="log" and "rules" or "refresh",13,7,0)
    end
    for _,button in pairs(controller.tabs) do button.bootyCaptionBottomInset=0;button.bootyLabelInsets={22,4};UI.ApplyButtonCaptionBaseline(button) end
    controller.officers=Label(frame,"",360,-36,470,36)
    controller.headings={Label(frame,"Raid",16,-112,260,18),Label(frame,"Type",290,-112,190,18),Label(frame,"Status",490,-112,140,18),Label(frame,"Actions",690,-112,130,18)}
    for _,heading in ipairs(controller.headings) do heading:SetTextColor(unpack(UI.Theme.colors.goldText)) end
    controller.selection=Label(frame,"",10,-398,820,24)
    controller.recover=Button(frame,"Join session",10,-400,150,function() end);controller.recover:Hide()
    controller.inspect=Button(frame,"All raids",310,-82,110,function() controller.expanded=nil;controller.offset=0;controller:Refresh() end);controller.inspect:Hide()
    local function RowAction(row,kind)
        local entry=row.entry;if not entry then return end
        if kind=="join" then
            local ok,reason=controller.api.Recover(entry.id)
            Message(controller,ok and "Joined raid session. Updates synchronize automatically." or reason)
            if ok then controller.raidId=entry.id end
        elseif kind=="reopen" then
            if not controller.reopenDialog then
                local confirm=Dialog(frame,"Reopen raid",420,150);controller.reopenDialog=confirm
                confirm.label=Label(confirm,"",12,-40,396,52)
                confirm.yes=Button(confirm,"Reopen",292,-116,108,function()
                    local ok,reason=controller.api.Reopen(confirm.raidId,confirm.revision)
                    if ok then ok,reason=controller.api.Recover(confirm.raidId);if ok then controller.raidId=confirm.raidId;confirm:Hide() end end
                    Message(controller,ok and "Raid reopened and joined. Updates synchronize automatically." or reason);controller:Refresh()
                end)
                confirm.no=Button(confirm,"Cancel",176,-116,108,function() confirm:Hide() end)
                function confirm:LayoutContent(w,h)
                    self.label:SetWidth(w-24);self.label:SetHeight(h-88)
                    self.yes:ClearAllPoints();self.yes:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT",-28,12)
                    self.no:ClearAllPoints();self.no:SetPoint("RIGHT",self.yes,"LEFT",-8,0)
                end
            end
            local confirm=controller.reopenDialog;confirm.raidId=entry.id;confirm.revision=entry.lifecycleRevision
            confirm.label:SetText("Reopen "..entry.name.." for all officers? Recording stays off until you start Live Tracking.")
            confirm:Show();confirm:LayoutContent(confirm:GetWidth(),confirm:GetHeight())
            if UI.WindowStack then UI.WindowStack.Raise(confirm,frame) end
        elseif kind=="conflicts" then
            controller.raidId=entry.id;controller.expanded=controller.expanded==entry.id and nil or entry.id;controller.offset=0
        elseif kind=="resolve" then if entry.kind=="merge" then controller:ShowCompare(entry.source) else controller:ShowConflict(entry.conflictId) end
        elseif kind=="compare" then controller.selected=entry;controller:ShowCompare(entry.id) end
        controller:Refresh()
    end
    for index=1,pageSize do
        local row=UI.CreateControl(nil,frame)
        row:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-130-(index-1)*32);row:SetWidth(820);row:SetHeight(30)
        row.label=Label(row,"",6,-7,260,20);row.typeLabel=Label(row,"",280,-7,190,20);row.stateLabel=Label(row,"",480,-7,120,20);row.actions={}
        if row.typeLabel.SetWordWrap then row.typeLabel:SetWordWrap(false);row.stateLabel:SetWordWrap(false) end
        if row.label.SetWordWrap then row.label:SetWordWrap(false) end
        for actionIndex,spec in ipairs({{"join","start","Join active raid"},{"reopen","refresh","Reopen and join raid"},{"conflicts","warning","Review conflicting changes"},{"compare","raids","Compare with the open raid"},{"resolve","fix","Resolve this conflict"}}) do
            local kind=spec[1];local button=Button(row,"",600+(actionIndex-1)*32,-3,26,function() RowAction(row,kind) end)
            UI.SetClassicButtonIcon(button,spec[2],14,6,0);UI.AttachTooltip(button,spec[3],spec[3]);row.actions[kind]=button
        end
        row:SetScript("OnClick",function() if row.entry then controller.selected=row.entry;controller:UpdateSelection() end end)
        UI.AttachTooltip(row,"Raid synchronization",function() return row.fullText or "" end)
        UI.StyleSelectableTableRow(row,math.mod(index,2)==0,false);controller.rows[index]=row
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
            local moving={"previous","next","count","use","recordPrevious","recordNext","recordCount","manualHint","itemLabel","item","recipientLabel","recipient","quantityLabel","quantity","exception","exceptionLabel","manual","resolve","progress","message"}
            local points={}
            for _,key in ipairs(moving) do local control=conflict[key];if control then local p,r,rp,x,y=control:GetPoint(1);points[key]={p,r,rp,x,y} end end
            function conflict:LayoutContent(w,h)
                local dy=h-580;self.heading:SetWidth(w-20);self.pane:Resize(w-20,200+dy)
                for key,point in pairs(points) do local control=self[key];control:ClearAllPoints();control:SetPoint(point[1],point[2],point[3],point[4],point[5]-dy) end
                self.message:SetWidth(w-20);self.manualHint:SetWidth(w-20)
            end
            conflict:SetScript("OnHide",function()
                conflict.data=nil;conflict.conflictId=nil;conflict.pane.text:SetText("");conflict.heading:SetText("")
                conflict.choices=nil;conflict.heads=nil
                conflict.item:SetText("");conflict.recipient:SetText("");conflict.quantity:SetText("")
            end)
        end
        conflict.conflictId=conflictId;conflict.index=1;conflict.recordIndex=1;conflict.choices={};conflict.heads=nil
        conflict:Show();conflict:LayoutContent(conflict:GetWidth(),conflict:GetHeight());ConflictRefresh()
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
                        function details:LayoutContent(w,h) self.pane:Resize(w-20,h-52) end
                        details:SetScript("OnHide",function() details.pane.text:SetText("") end)
                        comparison.details=details
                    end
                    comparison.details.pane:SetText(tostring(row.entry.label or row.entry.key).."\n\nCurrent raid\n"..Sync.FormatRecord(row.entry.key,row.entry.targetValue,row.entry.targetDeleted).."\n\nIncoming raid\n"..Sync.FormatRecord(row.entry.key,row.entry.sourceValue,row.entry.sourceDeleted))
                    comparison.details:Show();comparison.details:LayoutContent(comparison.details:GetWidth(),comparison.details:GetHeight())
                    if UI.WindowStack then UI.WindowStack.Raise(comparison.details,comparison) end
                end)
                UI.AttachTooltip(row,"Compare raid records",function() return row.entry and ((row.entry.label or row.entry.key or "").."\nClick for complete values. Same award counts once; separate awards both remain.") or "" end)
                UI.StyleSelectableTableRow(row,math.mod(index,2)==0,false)
                comparison.rows[index]=row
            end
            function comparison:LayoutContent(w,h)
                self.heading:SetWidth(w-20);self.message:SetWidth(w-20)
                self.merge:ClearAllPoints();self.merge:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT",-30,26)
                self.message:ClearAllPoints();self.message:SetPoint("BOTTOMLEFT",self,"BOTTOMLEFT",10,52)
                self.progress:ClearAllPoints();self.progress:SetPoint("BOTTOMLEFT",self,"BOTTOMLEFT",10,26)
                self.previous:ClearAllPoints();self.previous:SetPoint("BOTTOMLEFT",self,"BOTTOMLEFT",10,100)
                self.next:ClearAllPoints();self.next:SetPoint("LEFT",self.previous,"RIGHT",6,0)
                self.count:ClearAllPoints();self.count:SetPoint("LEFT",self.next,"RIGHT",12,0)
                for _,row in ipairs(self.rows) do
                    row:SetWidth(w-20);row.label:SetWidth(w-336)
                    for index,button in ipairs(row.buttons) do button:ClearAllPoints();button:SetPoint("RIGHT",row,"RIGHT",-6-(2-index)*154,0) end
                end
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
        comparison:Show();comparison:LayoutContent(comparison:GetWidth(),comparison:GetHeight());CompareRefresh()
        if UI.WindowStack then UI.WindowStack.Raise(comparison,frame) end
    end

    function controller:UpdateSelection()
        for index,row in ipairs(self.rows) do UI.StyleSelectableTableRow(row,math.mod(index,2)==0,row.entry~=nil and row.entry==self.selected) end
    end
    function controller:SelectTab(tab)
        self.tab=tab;self.expanded=nil;self.offset=0;self.selected=nil;Message(self,"")
        if conflict then conflict:Hide() end;if comparison then comparison:Hide() end
        self:Refresh()
    end
    function controller:Refresh(status)
        if not self:IsVisible() then return end
        self.refreshing=true
        status=status or self.api.GetStatus(self.raidId);self.revision=status.revision;self.raidName=status.raidName or self.raidName
        if status.retryAvailable then self.retry:Show() else self.retry:Hide() end
        local gold=UI.Theme.colors.goldText
        local prefix=string.format("|cff%02x%02x%02xSync status:|r |cffffffff",math.floor(gold[1]*255),math.floor(gold[2]*255),math.floor(gold[3]*255))
        self.status:SetText(prefix..(status.syncStatus or "Up to date").."|r")
        local names={}
        for _,peer in ipairs(status.peers or {}) do if peer.available or peer.syncState=="error" then table.insert(names,peer.name.." - "..(peer.syncState or "pending")) end end
        self.officers:SetText(table.getn(names)>0 and ("Connected officers: "..table.concat(names,", ")) or "No other officer connected.")
        frame:LayoutContent(frame:GetWidth(),frame:GetHeight())
        local visiblePageSize=self.visiblePageSize or pageSize
        local all,total={},0
        if self.tab=="log" then
            local log=self.api.GetSyncLog and self.api.GetSyncLog() or {};total=table.getn(log)
            for index=self.offset+1,math.min(total,self.offset+visiblePageSize) do local entry=log[index];local gold=UI.Theme.colors.goldText;local color=string.format("|cff%02x%02x%02x",math.floor(gold[1]*255),math.floor(gold[2]*255),math.floor(gold[3]*255));table.insert(all,{name=color..Timestamp(entry.timestamp).."|r  "..entry.message,log=true}) end
        elseif self.expanded then
            local conflicts;conflicts,total=self.api.ListConflicts(self.expanded,self.offset,visiblePageSize)
            for _,item in ipairs(conflicts or {}) do table.insert(all,{name=item.subject or item.id,conflictId=item.id,id=self.expanded,conflict=true,kind=item.kind,source=item.source}) end
        else all,total=self.api.ListRaids(self.offset,visiblePageSize) end
        self.total=total
        local maximum=math.max(0,math.floor(math.max(0,total-1)/visiblePageSize)*visiblePageSize)
        if self.offset>maximum then self.offset=maximum;return self:Refresh(status) end
        if self.expanded and self.tab~="log" then self.inspect:Show() else self.inspect:Hide() end
        for index,row in ipairs(self.rows) do
            local entry=all[index];row.entry=entry
            row.fullText=entry and (entry.name..(not entry.log and not entry.conflict and ("  |  "..tostring(entry.raidType).."  |  "..(entry.state=="ended" and "Ended" or "Active").."  |  "..tostring(entry.conflicts or 0).." conflicts") or "")) or ""
            row.label:SetText(entry and entry.name or "")
            row.typeLabel:SetText(entry and not entry.log and not entry.conflict and entry.raidType or "")
            row.stateLabel:SetText(entry and not entry.log and not entry.conflict and ((entry.state=="ended" and "Ended" or "Active")..((entry.conflicts or 0)>0 and (" / "..entry.conflicts.." conflicts") or "")) or "")
            for kind,button in pairs(row.actions) do
                local show=entry and not entry.log and ((entry.conflict and kind=="resolve") or (not entry.conflict and (kind=="join" and entry.state~="ended" and (not self.api.GetJoinedRaidId or self.api.GetJoinedRaidId()~=entry.id) or kind=="reopen" and entry.state=="ended" or kind=="conflicts" and (entry.conflicts or 0)>0 or kind=="compare" and self.raidId and self.raidId~=entry.id)))
                if show then button:Show() else button:Hide() end
            end
            if entry then row:Show() else row:Hide() end
        end
        self.empty:SetText(self.tab=="log" and "No synchronization events yet." or self.expanded and "No unresolved conflicts for this raid." or "No raids yet. New raids appear automatically when an officer shares them.")
        if total==0 then self.empty:Show() else self.empty:Hide() end
        self.count:SetText(total==0 and "0 entries" or (self.offset+1).."-"..math.min(self.offset+visiblePageSize,total).." / "..total)
        UI.SetButtonEnabled(self.previous,self.offset>0);UI.SetButtonEnabled(self.next,self.offset+visiblePageSize<total)
        for key,button in pairs(self.tabs) do UI.SetClassicButtonSelected(button,key==self.tab) end
        self:UpdateSelection();frame:LayoutContent(frame:GetWidth(),frame:GetHeight());self.refreshing=false
    end
    function frame:LayoutContent(w,h)
        controller.status:SetWidth(340);controller.officers:SetWidth(w-380)
        controller.officers:SetHeight(0)
        local headerHeight=math.max(36,UI.MeasureTextHeight(controller.officers,w-380,true))
        controller.officers:SetHeight(headerHeight)
        local shift=headerHeight-36
        local previousSize=controller.visiblePageSize
        controller.visiblePageSize=math.max(1,math.min(pageSize,math.floor((h-230-shift)/32)))
        controller.tabs.sessions:ClearAllPoints();controller.tabs.sessions:SetPoint("TOPLEFT",self,"TOPLEFT",10,-82-shift)
        controller.tabs.log:ClearAllPoints();controller.tabs.log:SetPoint("TOPLEFT",self,"TOPLEFT",108,-82-shift)
        controller.inspect:ClearAllPoints();controller.inspect:SetPoint("TOPLEFT",self,"TOPLEFT",206,-82-shift)
        controller.headings[1]:ClearAllPoints();controller.headings[1]:SetPoint("TOPLEFT",self,"TOPLEFT",16,-112-shift)
        controller.message:ClearAllPoints();controller.message:SetPoint("BOTTOMLEFT",self,"BOTTOMLEFT",10,40);controller.message:SetWidth(w-20)
        controller.previous:ClearAllPoints();controller.previous:SetPoint("BOTTOMLEFT",self,"BOTTOMLEFT",10,10)
        controller.next:ClearAllPoints();controller.next:SetPoint("LEFT",controller.previous,"RIGHT",6,0)
        controller.retry:ClearAllPoints();controller.retry:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT",-30,10)
        controller.count:ClearAllPoints();controller.count:SetPoint("LEFT",controller.next,"RIGHT",10,0)
        for _,heading in ipairs(controller.headings) do if controller.tab=="log" or controller.expanded then heading:Hide() else heading:Show() end end
        local titleSpace=w-38-134;local first=math.floor(titleSpace*0.44);local second=math.floor(titleSpace*0.32)
        controller.headings[4]:ClearAllPoints();controller.headings[4]:SetPoint("TOPLEFT",self,"TOPLEFT",w-144,-112-shift)
        controller.headings[2]:ClearAllPoints();controller.headings[2]:SetPoint("TOPLEFT",self,"TOPLEFT",first+22,-112-shift)
        controller.headings[3]:ClearAllPoints();controller.headings[3]:SetPoint("TOPLEFT",self,"TOPLEFT",first+second+28,-112-shift)
        for index,row in ipairs(controller.rows) do
            row:ClearAllPoints();row:SetPoint("TOPLEFT",self,"TOPLEFT",10,-130-shift-(index-1)*32)
            row:SetWidth(w-20);local right=-134
            for _,key in ipairs({"join","reopen","conflicts","compare","resolve"}) do
                local button=row.actions[key]
                if button:IsShown() then button:ClearAllPoints();button:SetPoint("LEFT",row,"RIGHT",right,0);right=right+28 end
            end
            if row.entry and (row.entry.log or row.entry.conflict) then row.label:SetWidth(w-172)
            else
                local available=w-38-134;local nameWidth=math.floor(available*0.44);local typeWidth=math.floor(available*0.32)
                row.label:SetWidth(nameWidth);row.typeLabel:ClearAllPoints();row.typeLabel:SetPoint("TOPLEFT",row,"TOPLEFT",nameWidth+12,-7);row.typeLabel:SetWidth(typeWidth)
                row.stateLabel:ClearAllPoints();row.stateLabel:SetPoint("TOPLEFT",row,"TOPLEFT",nameWidth+typeWidth+18,-7);row.stateLabel:SetWidth(available-nameWidth-typeWidth-12)
            end
        end
        if previousSize~=controller.visiblePageSize and not controller.refreshing and controller:IsVisible() then controller:Refresh() end
    end
    function controller:Open(raidId,tab)
        if conflict then conflict:Hide() end
        if comparison then comparison:Hide() end
        self.raidId=raidId;self.raidName=nil;self.offset=0;self.selected=nil;self.tab=tab=="log" and "log" or "sessions";self.expanded=tab=="conflicts" and raidId or nil
        Message(self,"");frame:Show();self:Refresh()
        if UI.WindowStack then UI.WindowStack.Raise(frame,parent) end
    end
    function controller:IsVisible() return frame:IsVisible() end
    function controller:Close() frame:Hide() end
    frame:SetScript("OnHide",function()
        if controller.reopenDialog then controller.reopenDialog:Hide() end
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
