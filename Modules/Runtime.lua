local Raider = BootyRaider
local UI = Raider.UI.Components
local Runtime = {views = {}, historicalLoaded = false}
Raider.Runtime = Runtime

function Runtime.Print(message)
    if Runtime.host and Runtime.host.Print then Runtime.host.Print(message)
    elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("BootyRaider: " .. tostring(message)) end
end
function Runtime.PrintAction(message)
    if Raider.Database.GetSetting("chatActionLogs") then Runtime.Print(message) end
end
function Runtime.OpenView(id)
    if Runtime.host and Runtime.host.OpenView then return Runtime.host.OpenView(id or "raid") end
    return false
end
function Runtime.GetView(id)
    return Runtime.host and Runtime.host.GetView and Runtime.host.GetView(id)
end
function Runtime.IsTestRaid() return Raider.Services.TestRaid.IsActive() end
function Runtime.GetAttendance()
    return Runtime.IsTestRaid() and Raider.Services.TestRaid.GetAttendance() or Raider.Database.GetRaidAttendance()
end
function Runtime.IsInRaid() return Runtime.IsTestRaid() or Raider.Services.Raid.IsInRaid() end
function Runtime.ActiveRaidService() return Runtime.IsTestRaid() and Raider.Services.TestRaid or Raider.Services.Raid end
function Runtime.RefreshViews()
    local _,view
    for _,view in pairs(Runtime.views) do if view.Refresh then view:Refresh() end end
end
function Runtime.CaptureActiveRoster()
    return Runtime.sessionController:CaptureActiveRoster()
end
function Runtime.RequestRaidScan()
    if not Raider.active or not Raider.pendingRaidSessionId then return false end
    local count = Runtime.sessionController:CompletePendingRaidScan()
    Runtime.RefreshViews()
    return count ~= nil and count > 0
end
function Runtime.SaveSession(options)
    local saved=Runtime.sessionController:Complete(options)
    if saved then Runtime.RefreshViews() end
    return saved
end
function Runtime.IsBusy()
    local loot=Raider.Modules.MasterLootWindow
    return Raider.raidSessionDraft or Raider.pendingRaidSessionId ~= nil or Runtime.IsTestRaid()
        or Raider.raidScanReady and not Runtime.historicalLoaded
        or Raider.Services.Raid.HasPendingReyCoinAward() or Raider.Services.Raid.HasPendingSoftReserveTrade()
        or loot and loot.IsBusy and loot.IsBusy() or false
end

local function Reload()
    if type(ReloadUI)=="function" then ReloadUI()
    elseif type(ConsoleExec)=="function" then ConsoleExec("reloadui") end
end
local function RaidPromptOwner()
    local host = Runtime.host
    return host and (host.windows and host.windows.raid or host.window)
end
local function RegisterPrompts()
    StaticPopupDialogs["BOOTY_RAIDER_ATTENDANCE_RELOAD"]={
        mosProjectTitle="Save Raid",mosProjectOwner=RaidPromptOwner,text="Raid data is saved in memory. Reload the UI now to write it to disk?",
        button1="Reload now",button2="Later",OnAccept=Reload,
        OnCancel=function() Runtime.Print("Raid data remains in memory until /reload or normal logout.") end,
        timeout=0,whileDead=1,hideOnEscape=1,
    }
    StaticPopupDialogs["BOOTY_RAIDER_START_RAID_REMINDER"]={
        mosProjectTitle="Start Raid",mosProjectOwner=RaidPromptOwner,
        text="You entered a raid instance without an active BootyRaider session.",button1="Later",button2="New Raid",
        OnAccept=function() Raider.raidStartReminderContext=Raider.raidStartReminderShownContext end,
        OnCancel=function()
            Raider.raidStartReminderContext=Raider.raidStartReminderShownContext
            Runtime.OpenView("raid")
            local view=Runtime.GetView("raid")
            if view and view.quickActions then view.quickActions:Run("primary") end
        end,timeout=0,whileDead=1,
    }
end

local function HideTransitionPrompt()
    if Runtime.transitionPrompt then Runtime.transitionPrompt:Hide() end
end
local function ShowTransitionPrompt(contextKey)
    Runtime.sessionController:ConfirmTransition(contextKey)
    if not Runtime.transitionPrompt then
        local dialog=UI.Window.CreateProjectConfirmation("BootyRaiderSessionTransition","Raid session is still active","Continue Session","raids",{modal=false})
        if UI.WindowStack then UI.WindowStack.SetOwner(dialog, function()
            local host = Runtime.host
            return host and (host.windows and host.windows.raid or host.window)
        end) end
        dialog:SetWidth(390);dialog.no:SetText("End & Save");dialog.no:SetWidth(112);dialog.yes:SetWidth(132)
        dialog.no:ClearAllPoints();dialog.no:SetPoint("BOTTOMLEFT",dialog,"BOTTOMLEFT",48,12)
        dialog.yes:ClearAllPoints();dialog.yes:SetPoint("LEFT",dialog.no,"RIGHT",18,0)
        dialog.close:SetScript("OnClick",function()
            Runtime.sessionController:DismissTransition(dialog.contextKey);dialog:Hide();Runtime.RefreshViews()
        end)
        Runtime.transitionPrompt=dialog
    end
    local dialog=Runtime.transitionPrompt
    local message=string.find(contextKey or "","different-raid-context|",1,true)==1
        and "You joined a different raid. Continue this session, or save and end it before starting a new one?"
        or "You left the raid context. Continue this session, or save and end it?"
    dialog.contextKey=contextKey
    dialog:Open(message,function()
        Runtime.sessionController:Continue(contextKey)
        if string.find(contextKey or "","different-raid-context|",1,true)==1 then
            Runtime.OpenView("raid")
            local view=Runtime.GetView("raid")
            if view and view.OfferCurrentRaidRefresh then view:OfferCurrentRaidRefresh() end
        end
        Runtime.RefreshViews()
    end,function()
        Runtime.OpenView("raid")
        local view=Runtime.GetView("raid")
        if view and view.OpenSaveDialog then view:OpenSaveDialog(contextKey) end
    end)
end

local function InstallLootHook()
    if Runtime.lootBinding then Runtime.lootBinding.active=true;return end
    if type(LootFrame_OnEvent)~="function" then return end
    local binding={active=true,original=LootFrame_OnEvent}
    binding.wrapper=function(lootEvent)
        if binding.active and Raider.active and lootEvent=="LOOT_OPENED" and Raider.Services.Raid.IsPlayerLootMaster() then
            local ok,message=pcall(Raider.Modules.MasterLootWindow.Open)
            if ok then return end
            Runtime.Print("Master Loot: "..tostring(message))
        end
        return binding.original(lootEvent)
    end
    Runtime.lootBinding=binding;LootFrame_OnEvent=binding.wrapper
end
local function RestoreLootHook()
    local binding=Runtime.lootBinding
    if not binding then return end
    binding.active=false
    if LootFrame_OnEvent==binding.wrapper then LootFrame_OnEvent=binding.original end
    Runtime.lootBinding=nil
end

local eventNames={"RAID_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA","CHAT_MSG_LOOT"}
local function Dispatch()
    if not Raider.active then return end
    Raider.Diagnostics.Count("events")
    if event=="CHAT_MSG_LOOT" then
        local attendance=Raider.Database.GetRaidAttendance()
        if BootyRaiderDB.raidLiveTrackingEnabled and not Raider.raidSessionPaused and not Raider.raidSessionTransitionPending
            and not Runtime.IsTestRaid() and Raider.Services.Raid.IsInRaid() and Raider.Services.RaidRes.HasSession(attendance) then
            if Raider.Services.Raid.RecordLoot(arg1) then Runtime.RefreshViews() end
        end
    else
        Runtime.worldContext.Update()
        local view=Runtime.views.raid
        if event=="RAID_ROSTER_UPDATE" and view and view.OnRosterUpdate then view:OnRosterUpdate() end
    end
end

function Runtime.Initialize(host)
    if host then Runtime.host=host end
    Raider.Database.Ensure()
    local provider = Raider.Modules.RaidContentProvider
    provider.MarkDataReady()
    local prepared, prepareFailure = provider.Prepare()
    if not prepared then Runtime.Print(type(prepareFailure) == "table" and prepareFailure.message or prepareFailure) end
    if Runtime.initialized then
        if not Raider.active then
            Raider.active=true
            for _,name in ipairs(eventNames) do Runtime.events:RegisterEvent(name) end
            InstallLootHook()
            local ok, failure = provider.Sync()
            if not ok then Runtime.Print(type(failure)=="table" and failure.message or failure) end
        end
        return true
    end
    Runtime.initialized=true;Raider.active=true
    if Raider.Diagnostics.Wrap then
        Raider.Services.Raid.SaveRoster=Raider.Diagnostics.Wrap("Raid roster scan",Raider.Services.Raid.SaveRoster,0)
        Raider.Services.Raid.RecordLoot=Raider.Diagnostics.Wrap("Loot message",Raider.Services.Raid.RecordLoot,2)
        Raider.Services.RaidStatistics.BuildSummary=Raider.Diagnostics.Wrap("Raid summary",Raider.Services.RaidStatistics.BuildSummary,2)
        Raider.Services.CSR.BuildSummary=Raider.Diagnostics.Wrap("CSR model",Raider.Services.CSR.BuildSummary,7)
        Raider.Services.RaidRes.Import=Raider.Diagnostics.Wrap("SR import",Raider.Services.RaidRes.Import,3)
        Raider.Services.RaidRes.BuildSnapshot=Raider.Diagnostics.Wrap("SR snapshot",Raider.Services.RaidRes.BuildSnapshot,1)
        Raider.Modules.RaidManagement.RefreshPage=Raider.Diagnostics.Wrap("Raid refresh",Raider.Modules.RaidManagement.RefreshPage,1)
    end
    Raider.Database.onRaidAttendanceChanged=Raider.Services.Raid.OnRaidAttendanceChanged
    Runtime.session=Raider.Services.RaidSession.Create({database=Raider.Database,raid=Raider.Services.Raid,raidRes=Raider.Services.RaidRes,
        raidStatistics=Raider.Services.RaidStatistics,testRaid=Raider.Services.TestRaid,now=function() return time() end})
    Runtime.sessionController=Raider.Modules.RaidSessionController.Create({state=Raider,session=Runtime.session,
        setHistoricalLoaded=function(value) Runtime.historicalLoaded=value and true or false end,
        clearSelection=function() if Runtime.views.raid then Runtime.views.raid:ClearSelection() end end,
        showSavedPopup=function() UI.ShowOpaquePopup("BOOTY_RAIDER_ATTENDANCE_RELOAD") end,
        isLiveTrackingWanted=function() return BootyRaiderDB.raidLiveTrackingEnabled and true or false end,
        canStartNewRaid=function()
            return Raider.Services.Raid.IsInRaid() and not Raider.raidSessionDraft and not Raider.raidScanReady and not Runtime.IsTestRaid()
        end,
        applyRaidPreset=Raider.Services.AutoLoot.ApplyRaidPreset,
    })
    RegisterPrompts()
    Runtime.sessionController:RestoreActive()
    Runtime.worldContext=Raider.Modules.RaidManagement.CreateWorldContextController({
        getAttendance=Raider.Database.GetRaidAttendance,getZone=function() return GetRealZoneText() or "" end,
        getInstanceState=function() if type(IsInInstance)=="function" then return IsInInstance() end return false,"" end,
        hasSession=Raider.Services.RaidRes.HasSession,isSessionDraft=function() return Raider.raidSessionDraft end,
        isTestRaid=Runtime.IsTestRaid,isInRaid=Raider.Services.Raid.IsInRaid,
        getReminderContext=function() return Raider.raidStartReminderContext end,
        setReminderContext=function(value) Raider.raidStartReminderContext=value end,
        getReminderShownContext=function() return Raider.raidStartReminderShownContext end,
        setReminderShownContext=function(value) Raider.raidStartReminderShownContext=value end,
        getContinuedContext=function() return Raider.raidSessionContinuedContext end,
        setContinuedContext=function(value) Raider.raidSessionContinuedContext=value end,
        getSessionTransitionContext=function() return Runtime.sessionController:GetTransitionContext() end,
        setTransitionPending=function(value) Runtime.sessionController:SetTransitionPending(value) end,
        showRaidStartReminder=function() UI.ShowOpaquePopup("BOOTY_RAIDER_START_RAID_REMINDER") end,
        hideRaidStartReminder=function() UI.HideOpaquePopup("BOOTY_RAIDER_START_RAID_REMINDER") end,
        showSessionTransitionPrompt=ShowTransitionPrompt,hideSessionTransitionPrompt=HideTransitionPrompt,
    })
    Runtime.nativeRaidTab=Raider.Modules.NativeRaidTab.Create({
        isEnabled=function() return Raider.active and not Runtime.stoppingNativeContent and provider.IsSelected() end,
        getLayoutContext=provider.GetLayoutContext,onLayoutChanged=provider.LayoutChanged,onStatusChanged=provider.Notify,
        onError=function(failure) Runtime.Print(type(failure)=="table" and failure.message or failure) end,
        ensureDatabase=Raider.Database.Ensure,openRaidInfo=Raider.Modules.RaidInfo.Toggle,closeRaidInfo=Raider.Modules.RaidInfo.CloseOwned,
    })
    provider.BindController(Runtime.nativeRaidTab)
    Runtime.events=UI.CreateContainer("BootyRaiderEvents",UIParent)
    for _,name in ipairs(eventNames) do Runtime.events:RegisterEvent(name) end
    Runtime.events:SetScript("OnEvent",Dispatch)
    InstallLootHook()
    local synced, failure = provider.Sync()
    Raider.CompleteRaidSession=Runtime.SaveSession
    if not synced then Runtime.Print(type(failure)=="table" and failure.message or failure) end
    return true
end
function Runtime.Stop()
    if Runtime.IsBusy() then return false,"Save or end the active raid and finish loot operations before stopping BootyRaider." end
    if not Runtime.initialized then return true end
    if Runtime.stoppingNativeContent then return false,"BootyRaider is already stopping." end
    local provider = Raider.Modules.RaidContentProvider
    local function Message(failure)
        return tostring(type(failure)=="table" and (failure.message or failure.code) or failure or "BootyRaider could not stop safely.")
    end
    local function Refuse(failure)
        Runtime.stoppingNativeContent=nil
        local ok, restored, rollback = pcall(provider.Sync)
        if not ok then rollback=restored;restored=false end
        if restored ~= true then
            return false,{code=type(failure)=="table" and failure.code or "stop-failed",
                message=Message(failure).." Raid content could not be restored: "..Message(rollback),
                cause=failure,rollbackError=rollback,partial=true}
        end
        return false,failure
    end
    -- Native content can fail to detach when another addon owns its wrapper.
    -- Verify that cleanup before stopping domain events, loot or feature views.
    Runtime.stoppingNativeContent=true
    local ok, synced, failure = pcall(provider.Sync)
    if not ok then failure=synced;synced=false end
    if synced ~= true then return Refuse(failure) end
    local stopped, result, reason = pcall(Raider.Modules.MasterLootWindow.Stop)
    if not stopped or result == false then return Refuse(stopped and reason or result) end
    Raider.active=false
    Runtime.stoppingNativeContent=nil
    for _,name in ipairs(eventNames) do Runtime.events:UnregisterEvent(name) end
    Runtime.worldContext:CancelConfirmation()
    RestoreLootHook();HideTransitionPrompt()
    for _,view in pairs(Runtime.views) do
        if view.Stop then view:Stop() elseif view.Hide then view:Hide() end
    end
    Raider.Services.Raid.ResetLootSession()
    -- A notification error cannot make the already stopped domain appear live.
    local notified, result, detail = pcall(provider.Notify)
    if not notified or result == false then Runtime.Print(Message(notified and detail or result)) end
    return true
end
local function ApplySettingChanges(keys)
    if not Runtime.initialized or not Raider.active then return end
    local native,tracking,autoLoot=false,false,false
    for key in pairs(keys) do
        if key=="profile" or key=="useMOSRaidTab" or key=="useMOSRaidLogo" or string.find(key,"^nativeRaid") then native=true end
        if key=="profile" or key=="raidLiveTrackingEnabled" then tracking=true end
        if key=="profile" or string.find(key,"^lmAutoLoot") then autoLoot=true end
    end
    if native then Runtime.nativeRaidTab:Sync() end
    if autoLoot then Raider.Modules.MasterLootWindow.ApplyAutoLootSetting() end
    local view=Runtime.views.raid
    if view then
        if tracking and view.SyncTrackingSetting then view:SyncTrackingSetting(true) end
        view:Refresh()
    end
end
function Runtime.BeginSettingsBatch()
    Runtime.settingsBatchDepth=(Runtime.settingsBatchDepth or 0)+1
    if not Runtime.pendingSettings then Runtime.pendingSettings={} end
end
function Runtime.EndSettingsBatch(success)
    Runtime.settingsBatchDepth=math.max(0,(Runtime.settingsBatchDepth or 0)-1)
    if Runtime.settingsBatchDepth>0 then return end
    local keys=Runtime.pendingSettings
    Runtime.pendingSettings=nil
    if success==false then return end
    if keys and next(keys) then ApplySettingChanges(keys) end
end
function Raider.OnSettingChanged(key)
    if type(key)~="string" then return end
    if (Runtime.settingsBatchDepth or 0)>0 then Runtime.pendingSettings[key]=true;return end
    ApplySettingChanges({[key]=true})
end
function Runtime.OnSettingsProfileApplied(keys)
    if (Runtime.settingsBatchDepth or 0)>0 then
        for key in pairs(keys or {}) do Runtime.pendingSettings[key]=true end
    else ApplySettingChanges(keys or {profile=true}) end
end
