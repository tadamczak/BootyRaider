local Raider = BootyRaider
local Runtime = Raider.Runtime
local standaloneViews={{id="raid",label="Raid",icon="raids",width=78},
    {id="raidStatistics",label="Raid Stats",icon="raid_stats",width=104},
    {id="csr",label="CSR",icon="csr",width=72}}
local function CreateView(parent,host,id,create)
    if not host or not host.standalone then return create(parent) end
    local UI=Raider.UI.Components
    local frame=UI.CreateContainer(nil,parent);frame:SetAllPoints(parent)
    local body=UI.CreateContainer(nil,frame);body:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-30)
    body:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)
    body.bootyWidthOwner=parent;body.bootyWidthInset=0;body.bootyHeightOwner=parent;body.bootyHeightInset=30
    local toolbar=UI.CreateToolbarSurface(frame,false,true)
    toolbar.bootyBorderOutsetLeft=0;toolbar.bootyBorderOutsetRight=0;UI.SetSurfaceHorizontalBorders(toolbar,false,true)
    toolbar:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0);toolbar:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0);toolbar:SetHeight(28)
    body.bootyContentTopInset=body.bootyHeightInset-toolbar:GetHeight()
    local function SizeBody()
        local width,height=UI.GetFrameSpan(parent)
        frame:SetWidth(width);frame:SetHeight(height)
        body:SetWidth(math.max(1,width));body:SetHeight(math.max(1,height-30))
    end
    SizeBody()
    local view=create(body)
    view.frame=frame;view.standaloneNavigation={frame=toolbar,body=body,buttons={}}
    local left=6
    for _,entry in ipairs(standaloneViews) do
        local target=entry.id
        local button=UI.CreateButton(toolbar,nil,entry.label,entry.width,22)
        button:SetPoint("TOPLEFT",toolbar,"TOPLEFT",left,-2);left=left+entry.width+4
        button.bootyClassicKeepNormalSurface=true;button.bootyHoverTextColor={1,0.82,0.28}
        UI.SetClassicButtonIcon(button,entry.icon,13,7,0);UI.AttachGoldHoverBorder(button,0.35,0.35,0.35,1)
        UI.SetClassicButtonSelected(button,target==id)
        button:SetScript("OnClick",function()
            if target==id then return end
            local previous=host.windows and host.windows[id]
            local opened=host.OpenView(target,previous)
            if opened and previous then
                local ready,reason=previous.HideView()
                if ready==false then host.Print(reason or "Cannot close this raid view.");return end
                previous:Hide()
            end
        end)
        view.standaloneNavigation.buttons[target]=button
    end
    local show,hide,resize,stop,refresh=view.Show,view.Hide,view.OnResize,view.Stop,view.Refresh
    local function JoinNavigationEdge()
        local controls=view.page and view.page.syncHistoryControls
        local historyToolbar=controls and controls.historyToolbar
        if not historyToolbar then return end
        -- With its heading hidden, the history toolbar meets the tab strip.
        -- Keep the tabs' existing project edge instead of drawing both rails.
        local top=not (BootyRaiderDB.raidHideSectionHeader and historyToolbar:IsShown())
        if historyToolbar.bootyBorderTop~=top then UI.SetSurfaceHorizontalBorders(historyToolbar,top,true) end
    end
    local function ResizeView(self) SizeBody();if resize then resize(self) end;JoinNavigationEdge() end
    function view:OnResize()
        body.bootyResizeInProgress=true
        local ok,failure=pcall(ResizeView,self)
        body.bootyResizeInProgress=nil
        if not ok then error(failure) end
    end
    function view:Show() frame:Show();SizeBody();show(self);JoinNavigationEdge() end
    if refresh then function view:Refresh() refresh(self);JoinNavigationEdge() end end
    function view:Hide()
        local result,reason=hide(self)
        if result==false then return result,reason end
        frame:Hide();return result,reason
    end
    if stop then
        function view:Stop()
            local result,reason=stop(self)
            if result==false then return result,reason end
            frame:Hide();return result,reason
        end
    end
    return view
end
local function RequestHistoryOnShow(view)
    local show=view.Show
    function view:Show()
        show(self)
        Runtime.RequestHistoryAuthority()
    end
    return view
end
local function CreateRaid(parent,host)
    return RequestHistoryOnShow(CreateView(parent,host,"raid",function(body) return Raider.Modules.RaidScreen.Create(body,host) end))
end
local function CreateStatistics(parent,host)
    Runtime.Initialize(host)
    local view=CreateView(parent,host,"raidStatistics",function(body)
        local controller=Raider.Modules.RaidStatistics.Create(body,Raider.Database.GetRaidStatistics,Raider.Database.DeleteRaidStatistic,Raider.Database.UpdateRaidStatistic)
        controller.frame=controller.page;return controller
    end)
    Runtime.views.raidStatistics=view
    return RequestHistoryOnShow(view)
end
local function CreateCSR(parent,host)
    Runtime.Initialize(host)
    local view=CreateView(parent,host,"csr",function(body)
        local controller=Raider.Modules.CSR.Create(body,Raider.Database.GetRaidStatistics,Raider.Database.GetLootRules,Raider.Database.GetRosterData,
            function(id)
                Runtime.OpenView("raidStatistics")
                local statistics=Runtime.GetView("raidStatistics")
                if statistics and statistics.SelectRaid then statistics:SelectRaid(id) end
            end,{canManageHistory=Raider.Services.RankPolicy.CanManageHistory,setSourceArchived=Raider.Database.SetCSRSourceArchived})
        controller.frame=controller.page;return controller
    end)
    Runtime.views.csr=view
    return RequestHistoryOnShow(view)
end
local function RollHelp()
    Runtime.Print("/br roll <item link> [players] [Tmog OS MS RC SR] - start a custom roll.")
    Runtime.Print("Players: space-separated names; omit for everyone. Types: choose one or more; omit for OS/MS/RC and eligible Tmog.")
    Runtime.Print("Tmog: appearance; OS: off-spec; MS: main-spec; RC: Reycoin; SR: Soft Reserve. Requires raid leader, assistant or Loot Master.")
end
local function CommandHelp()
    Runtime.Print("/br raid - Open Raid.")
    Runtime.Print("/br stats - Open Raid Stats.")
    Runtime.Print("/br csr - Open CSR.")
    Runtime.Print("/br config - Open Settings.")
    RollHelp()
end
function Raider.HandleCommand(text)
    if not Raider.active then Runtime.Print("BootyRaider is stopped. Resume it in Plugins or reload with the addon enabled.");return false end
    local _,_,command,arguments=string.find(tostring(text or ""),"^%s*(%S*)%s*(.-)%s*$")
    command=string.lower(command or "")
    if command=="" then CommandHelp();return true end
    if command=="roll" then
        if arguments=="" then RollHelp();return true end
        if not Raider.Services.LootRollRequest.CanOrganize() then
            Runtime.Print("Only the Loot Master, raid leader or an assistant can start a roll.");return false
        end
        return Raider.Modules.MasterLootWindow.OpenLinkedItemRoll(arguments)
    elseif command=="stats" then return Runtime.OpenView("raidStatistics")
    elseif command=="csr" then return Runtime.OpenView("csr")
    elseif command=="config" then if Runtime.host and Runtime.host.OpenSettings then return Runtime.host.OpenSettings() end
    elseif command=="raid" then return Runtime.OpenView("raid") end
    CommandHelp()
    return false
end
local function QuickMenu(host)
    if host then Runtime.host=host end
    local function RaidView() return Runtime.GetView("raid") end
    local function Run(action,id)
        local view=RaidView()
        return view and view.quickActions and view.quickActions:Run(action,id)
    end
    local function Entry(text,icon,action,enabled,children)
        return {text=text,icon=icon,onClick=action,action=action,enabled=enabled~=false,children=children}
    end
    local view=RaidView()
    local quick=view and view.quickActions
    local state=quick and quick:GetState() or {}
    local leader,loot,snapshots={},{},{}
    if quick then
        for _,kind in ipairs({"leader","loot"}) do
            local target=kind=="leader" and leader or loot
            for _,tool in ipairs(quick:GetTools(kind)) do
                local id=tool.id
                table.insert(target,Entry(tool.text,tool.icon,function() return Run(id) end,tool.enabled))
            end
        end
        for _,snapshot in ipairs(quick:GetRecentSnapshots(5)) do
            local id=snapshot.id
            table.insert(snapshots,Entry(snapshot.text,"archive",function() return Run("load",id) end,snapshot.enabled))
        end
    end
    local raid={
        Entry(state.active and "Open Raid" or "New raid","start",function() return Run("primary") end,state.active or state.canStart),
        Entry("RL Tools","raid_tools",nil,state.canTools,leader),Entry("ML Tools","loot_tools",nil,state.canTools,loot),
        Entry("Test Raid","groups",function() return Run("test") end,state.canTest),
        Entry("Load Raid","archive",nil,state.canLoad and table.getn(snapshots)>0,snapshots),
        Entry("Save Raid","save",function() return Run("save") end,state.canSave),
        Entry("End & Save","save",function() return Run("quit") end,state.canQuit),
        Entry("Leave Session","quit",function() return Run("leave") end,state.canQuit),
    }
    local stats=Entry("Raid Stats","raid_stats",function() return Runtime.OpenView("raidStatistics") end)
    local entries={Entry("Raid","raids",function() return Runtime.OpenView("raid") end,true,raid)}
    if host and host.standalone then table.insert(entries,stats) else table.insert(raid,stats) end
    table.insert(entries,Entry("CSR","csr",function() return Runtime.OpenView("csr") end))
    if host and host.standalone then table.insert(entries,Entry("Settings","settings",function() return host.OpenSettings() end)) end
    return entries
end

function Raider.GetProfilingTargets()
    local D = BootyLib.Diagnostics
    local descriptor = D.CreateProfilingDescriptor(Raider.version,
        "Raid events, roster/loot, incremental synchronization, journal/projection, CSR, SR import and Raid refresh. Selected Lua entry points; not total addon or rendering time.")
    D.AddProfilingScript(descriptor, Runtime.events, "OnEvent", "Raid events", true)
    D.AddProfilingFunction(descriptor, Raider.Services.Raid, "CaptureRoster", "Capture roster")
    D.AddProfilingFunction(descriptor, Raider.Services.Raid, "RecordLoot", "Record loot")
    D.AddProfilingFunction(descriptor, Raider.Services.RaidStatistics, "BuildSummary", "Raid statistics summary")
    D.AddProfilingFunction(descriptor, Raider.Services.CSR, "BuildSummary", "CSR summary")
    D.AddProfilingFunction(descriptor, Raider.Services.RaidCSR, "BuildSummary", "Incremental CSR")
    D.AddProfilingFunction(descriptor, Raider.Services.RaidJournal, "Commit", "Journal local change")
    D.AddProfilingFunction(descriptor, Raider.Services.RaidJournal, "Apply", "Journal received change")
    D.AddProfilingFunction(descriptor, Raider.Services.RaidJournal, "Compact", "Journal checkpoint")
    D.AddProfilingFunction(descriptor, Raider.Modules.RaidSyncRuntime, "Tick", "Sync scheduled work")
    D.AddProfilingFunction(descriptor, Runtime.replica, "Flush", "Raid projection")
    D.AddProfilingFunction(descriptor, Raider.Services.RaidRes, "Import", "SR import")
    D.AddProfilingFunction(descriptor, Raider.Services.RaidRes, "BuildSnapshot", "SR snapshot")
    D.AddProfilingFunction(descriptor, Raider.Modules.RaidManagement, "RefreshPage", "Raid refresh")
    return descriptor
end
function Raider.GetDatabaseStatistics()
    return {collections = {
        {id = "savedRaids", label = "Saved raid statistics", path = {"raidStatistics", "raids"}, unit = "Raids", valueType = "table", emptyWhenMissing = true},
        {id = "srSnapshots", label = "Saved SR snapshots", path = {"softReserveHistory", "raids"}, unit = "Snapshots", valueType = "table", emptyWhenMissing = true},
        {id = "sessionMembers", label = "Current session members", path = {"raidAttendance", "members"}, unit = "Members", valueType = "table", emptyWhenMissing = true},
        {id = "sessionDeparted", label = "Current session departed members", path = {"raidAttendance", "departedMembers"}, unit = "Members", valueType = "table", emptyWhenMissing = true},
        {id = "syncRaids", label = "Synchronized raids", path = {"raidJournal", "raids"}, unit = "Raids", valueType = "table", emptyWhenMissing = true},
        {id = "syncOperations", label = "Raid changes and causal markers", path = {"raidJournal", "operations"}, unit = "Records", valueType = "table", emptyWhenMissing = true},
    }}
end

local function HostReady(host)
    local ready,reason=Runtime.Initialize(host)
    if ready==false then return ready,reason end
    if not Runtime.defaultProfileCaptured then
        BootyLib.Core.SettingsProfiles.Create({Raider.descriptor},{id="raider",scoped=true})
        Runtime.defaultProfileCaptured=true
    end
    if not Runtime.loginGreetingShown then
        BootyLib.Print(Raider.version..". Use /br to see available commands!","BootyRaider")
        Runtime.loginGreetingShown=true
    end
    return true
end
local descriptor={id="raider",name="BootyRaider",label="Raid",namespace=Raider,version=Raider.version,apiVersion=1,OnHostReady=HostReady,
    ownsCommands=true,protectedProfileName="BootyRaider Default",
    Initialize=Runtime.Initialize,Start=Runtime.Initialize,Stop=Runtime.Stop,IsBusy=Runtime.IsBusy,GetSettings=Raider.Settings.Get,
    OnActivationFailed=Runtime.OnActivationFailed,
    GetDatabase=Raider.Database.Ensure,GetProfilingTargets=Raider.GetProfilingTargets,GetDatabaseStatistics=Raider.GetDatabaseStatistics,GetQuickMenu=QuickMenu,ResetSettings=Raider.Settings.Reset,OnSettingChanged=Raider.OnSettingChanged,Command=Raider.HandleCommand,
    BeginSettingsBatch=Runtime.BeginSettingsBatch,EndSettingsBatch=Runtime.EndSettingsBatch,OnSettingsProfileApplied=Runtime.OnSettingsProfileApplied,
    GetGuildDirectoryDemand=Runtime.WantsGuildDirectory,
    OnGuildDirectoryUpdated=Runtime.OnGuildDirectoryUpdated,
    views={{id="raid",label="Raid",icon="raids",create=CreateRaid},
        {id="raidStatistics",label="Raid Stats",icon="raid_stats",create=CreateStatistics},
        {id="csr",label="CSR",icon="csr",create=CreateCSR}},
}
Raider.descriptor=descriptor
BootyLib.RegisterProduct(descriptor)
SlashCmdList=SlashCmdList or {}
SLASH_BOOTYRAIDER1="/br";SLASH_BOOTYRAIDER2="/bootyraider";SlashCmdList.BOOTYRAIDER=Raider.HandleCommand
