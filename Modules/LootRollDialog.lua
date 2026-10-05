local Raider = BootyRaider
local Dialog = {}
Raider.Modules.LootRollDialog = Dialog

-- One lazy, compact dialog; its type and player selections are transient.
function Dialog.Create(options)
    local UI = Raider.UI.Components
    local frame = UI.Window.CreateProjectConfirmation("BootyRaiderNewRoll", "New Roll", "Start Roll", "dice", {modal=false})
    if UI.WindowStack then
        UI.WindowStack.SetOwner(frame, function()
            local host = Raider.Runtime and Raider.Runtime.host
            return host and (host.windows and host.windows.raid or host.window)
        end)
    end
    local projectOpen = frame.Open
    frame.label:SetJustifyH("LEFT")
    frame.item = UI.CreateFramedEditBox(frame, nil, 304, 22)
    frame.item:SetPoint("TOPLEFT", frame.label, "BOTTOMLEFT", 0, -8)
    frame.item:SetWidth(304); frame.item:SetHeight(22); frame.item:SetAutoFocus(false)
    frame.item:SetScript("OnEditFocusGained",function() frame.itemFocused=true end)
    frame.item:SetScript("OnEditFocusLost",function() frame.itemFocused=nil end)
    local linkBinding,bagBinding
    local function DetachLinkInput()
        if linkBinding then
            linkBinding.active=false
            if ChatEdit_InsertLink==linkBinding.wrapper then ChatEdit_InsertLink=linkBinding.original end
            linkBinding=nil
        end
        if bagBinding then
            bagBinding.active=false
            if ContainerFrameItemButton_OnClick==bagBinding.wrapper then ContainerFrameItemButton_OnClick=bagBinding.original end
            bagBinding=nil
        end
    end
    frame:SetScript("OnShow",function()
        DetachLinkInput()
        if type(ChatEdit_InsertLink)=="function" then
            local binding={active=true,original=ChatEdit_InsertLink}
            binding.wrapper=function(link)
                if binding.active and frame:IsVisible() and frame.itemFocused
                    and Raider.Services.LootRollRequest.Normalize({link=link}) then frame.item:SetText(link);return true end
                return binding.original(link)
            end
            linkBinding=binding;ChatEdit_InsertLink=binding.wrapper
        end
        if type(ContainerFrameItemButton_OnClick)=="function" then
            local binding={active=true,original=ContainerFrameItemButton_OnClick}
            binding.wrapper=function(button,ignoreModifiers)
                if binding.active and frame:IsVisible() and frame.itemFocused and button=="LeftButton" and not ignoreModifiers
                    and IsShiftKeyDown() and not IsControlKeyDown() and this and this.GetID and this:GetParent() then
                    local link=GetContainerItemLink(this:GetParent():GetID(),this:GetID())
                    if Raider.Services.LootRollRequest.Normalize({link=link}) then frame.item:SetText(link);return end
                end
                return binding.original(button,ignoreModifiers)
            end
            bagBinding=binding;ContainerFrameItemButton_OnClick=binding.wrapper
        end
    end)
    frame.types, frame.selected, frame.typeChecks, frame.memberEntries = {}, {}, {}, {}
    frame.openRoll = true
    local binding = {ensure=function() end, get=function(key) return frame.types[key] end,
        set=function(key,value) frame.types[key]=value end}
    for index,range in ipairs({98,99,100,101,102}) do
        local check = UI.Settings.CreateCheckbox(frame, 8+(index-1)*61, -92,
            Raider.Services.LootRollRequest.CategoryNames[range], range, nil, binding)
        check:SetWidth(18); check:SetHeight(18)
        local font, _, flags = check.label:GetFont(); check.label:SetFont(font, 10, flags)
        check.labelHit:SetWidth(math.max(18, check.label:GetStringWidth() + 5))
        check.labelHit:SetHeight(18)
        frame.typeChecks[range]=check
    end
    frame.membersButton = UI.CreateButton(frame, nil, "Add rollers", 140, 22)
    frame.membersButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -118)
    UI.SetClassicButtonIcon(frame.membersButton,"roster")
    UI.AttachTooltip(frame.membersButton,"Add rollers","Select players who may roll when Open roll is off.")
    local function UpdateMembersState() UI.SetButtonEnabled(frame.membersButton,not frame.openRoll) end
    frame.memberMenu = UI.CreateCascadingMenu(function(_,name)
        frame.selected[name]=not frame.selected[name] or nil
        for _,entry in ipairs(frame.memberEntries) do entry.checked=frame.selected[entry.data] and true or false end
    end)
    frame.membersButton:SetScript("OnClick",function()
        if frame.openRoll then return end
        frame.item:ClearFocus()
        if frame.memberMenu:IsOpen() then frame.memberMenu:Close()
        else frame.memberMenu:Open(frame.membersButton,frame.memberEntries) end
    end)
    local openBinding = {ensure=function() end, get=function() return frame.openRoll end,
        set=function(_,value) frame.openRoll=value end}
    frame.openCheck = UI.Settings.CreateCheckbox(frame,172,-120,"Open roll","open",function()
        frame.memberMenu:Close(); UpdateMembersState()
    end,openBinding)
    frame.openCheck:SetWidth(18); frame.openCheck:SetHeight(18); frame.openCheck.labelHit:SetHeight(18)
    local openFont, _, openFlags = frame.openCheck.label:GetFont(); frame.openCheck.label:SetFont(openFont,10,openFlags)
    frame.openCheck.labelHit:SetWidth(math.max(18,frame.openCheck.label:GetStringWidth()+5))
    UI.AttachTooltip(frame.openCheck,"Open roll","Anyone in the raid may roll, subject to the selected roll type's rules.")
    UI.AttachTooltip(frame.openCheck.labelHit,"Open roll","Anyone in the raid may roll, subject to the selected roll type's rules.")
    frame.item:SetScript("OnEscapePressed",function() if frame.memberMenu:IsOpen() then frame.memberMenu:Close() else frame:Hide() end end)
    local projectHide=frame:GetScript("OnHide")
    frame:SetScript("OnHide",function()
        DetachLinkInput();frame.itemFocused=nil
        frame.memberMenu:Close(); frame.item:ClearFocus()
        if projectHide then projectHide() end
    end)
    frame.yes:SetScript("OnClick",function()
        local names
        if not frame.openRoll then
            names={}
            for _,entry in ipairs(frame.memberEntries) do if frame.selected[entry.data] then table.insert(names,entry.data) end end
        end
        local ok,failure=options.start({link=frame.item:GetText(),types=frame.types,names=names,open=frame.openRoll})
        if ok then frame:Hide()
        else frame.label:SetText(failure or "Could not start the roll.") end
    end)
    frame.Open=function(self)
        self.memberMenu:Close()
        for key in pairs(self.selected) do self.selected[key]=nil end
        for key in pairs(self.types) do self.types[key]=nil end
        for _,range in ipairs({98,99,100,101,102}) do
            self.types[range]=range~=102
            self.typeChecks[range]:SetChecked(range~=102 and 1 or nil)
        end
        self.item:SetText("")
        self.openRoll=true; self.openCheck:SetChecked(1); UpdateMembersState()
        local count=tonumber(Raider.Services.Raid.GetRaidMemberCount()) or 0
        local used=0
        for index=1,math.min(40,math.max(0,math.floor(count))) do
            local name=Raider.Services.Raid.GetRaidMemberInfo(index)
            if name then
                used=used+1
                local entry=self.memberEntries[used] or {}
                self.memberEntries[used]=entry
                entry.text,entry.data,entry.action,entry.icon,entry.keepOpen,entry.checked=name,name,"player","roster",true,false
            end
        end
        for index=table.getn(self.memberEntries),used+1,-1 do table.remove(self.memberEntries,index) end
        projectOpen(self,"Link an item, then choose roll types and players.")
        self:SetWidth(320); self:SetHeight(184)
        self.label:ClearAllPoints(); self.label:SetPoint("TOPLEFT",self.projectDivider,"BOTTOMLEFT",4,-8)
        self.label:SetPoint("TOPRIGHT",self.projectDivider,"BOTTOMRIGHT",-4,-8)
        self.label:SetHeight(18); self.label:SetJustifyH("LEFT")
        self:Raise(); self.item:SetFocus()
    end
    return frame
end
