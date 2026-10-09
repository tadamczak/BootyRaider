local Raider = BootyRaider
local UI = Raider.UI.Components
local Runtime = {views = {}, historicalLoaded = false}
Raider.Runtime = Runtime
local function CleanupMessage(value, fallback)
    if type(value)=="table" then value=value.message or value.code end
    return tostring(value or fallback or "BootyRaider cleanup failed.")
end

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
    local previousThis, previousEvent, previousArg = this, event, arg1
    local called, count, failure = pcall(Runtime.sessionController.CompletePendingRaidScan, Runtime.sessionController)
    this, event, arg1 = previousThis, previousEvent, previousArg
    if not called then failure, count = tostring(count), nil end
    Runtime.RefreshViews()
    if count == nil or count <= 0 then
        failure = failure or "The physical raid roster is not ready. Retry or cancel the new session."
        Runtime.Print(failure)
        return false, failure
    end
    return true
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
    local shared = BootyLib.Core.Runtime
    if not shared or type(shared.CanReload) ~= "function" then
        Runtime.Print("Cannot verify active Booty work before reloading.")
        return false
    end
    local checked, allowed, reason = pcall(shared.CanReload)
    if not checked or not allowed then
        Runtime.Print(CleanupMessage(reason or allowed,"Finish active Booty work before reloading."))
        return false
    end
    local reload,argument=ReloadUI,nil
    if type(reload)~="function" then reload,argument=ConsoleExec,"reloadui" end
    if type(reload)~="function" then Runtime.Print("Reload is unavailable.");return false end
    local called,result=pcall(reload,argument)
    if not called or result==false or result==0 then Runtime.Print(CleanupMessage(result,"Reload failed."));return false end
    return true
end
local function RaidPromptOwner()
    local host = Runtime.host
    return host and (host.windows and host.windows.raid or host.window)
end
local function RegisterPrompts()
    StaticPopupDialogs["BOOTY_RAIDER_ATTENDANCE_RELOAD"]={
        bootyProjectTitle="Save Raid",bootyProjectOwner=RaidPromptOwner,text="Raid data is saved in memory. Reload the UI now to write it to disk?",
        button1="Reload now",button2="Later",OnAccept=Reload,
        OnCancel=function() Runtime.Print("Raid data remains in memory until /reload or normal logout.") end,
        timeout=0,whileDead=1,hideOnEscape=1,
    }
    StaticPopupDialogs["BOOTY_RAIDER_START_RAID_REMINDER"]={
        bootyProjectTitle="Start Raid",bootyProjectOwner=RaidPromptOwner,
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
        if not BootyRaiderDB.raidLiveTrackingEnabled or Raider.raidSessionPaused or Raider.raidSessionTransitionPending
            or Runtime.IsTestRaid() or not Raider.Services.Raid.IsInRaid() then return end
        local attendance=Raider.Database.GetRaidAttendance()
        if Raider.Services.RaidRes.HasSession(attendance) then
            if Raider.Services.Raid.RecordLoot(arg1) then Runtime.RefreshViews() end
        end
    else
        Runtime.worldContext.Update()
        local view=Runtime.views.raid
        if event=="RAID_ROSTER_UPDATE" and view and view.OnRosterUpdate then view:OnRosterUpdate() end
    end
end

function Runtime.Initialize(host)
    if Runtime.cleanupPending then return false,"BootyRaider cleanup is incomplete. Retry Stop before resuming." end
    if host then Runtime.host=host end
    Raider.Database.Ensure()
    if Runtime.initialized then
        if not Raider.active then
            local called,result,reason=pcall(function()
                Raider.active=true
                for _,name in ipairs(eventNames) do Runtime.events:RegisterEvent(name) end
                InstallLootHook()
                local ready,message=Runtime.nativeRaidTab:Sync()
                if ready==false and message then return false,message end
                return true
            end)
            if not called or result==false then
                local failure=CleanupMessage(reason or result,"BootyRaider could not resume.")
                local cleaned,message=Runtime.OnActivationFailed()
                if not cleaned then failure=failure.." Resume cleanup failed: "..message end
                return false,failure
            end
        end
        return true
    end
    Raider.active=true
    if Raider.Diagnostics.Wrap and not Runtime.diagnosticsWrapped then
        Raider.Services.Raid.SaveRoster=Raider.Diagnostics.Wrap("Raid roster scan",Raider.Services.Raid.SaveRoster,1)
        Raider.Services.Raid.CaptureRoster=Raider.Diagnostics.Wrap("Raid roster scan",Raider.Services.Raid.CaptureRoster,1)
        Raider.Services.Raid.RecordLoot=Raider.Diagnostics.Wrap("Loot message",Raider.Services.Raid.RecordLoot,2)
        Raider.Services.RaidStatistics.BuildSummary=Raider.Diagnostics.Wrap("Raid summary",Raider.Services.RaidStatistics.BuildSummary,2)
        Raider.Services.CSR.BuildSummary=Raider.Diagnostics.Wrap("CSR model",Raider.Services.CSR.BuildSummary,7)
        Raider.Services.RaidRes.Import=Raider.Diagnostics.Wrap("SR import",Raider.Services.RaidRes.Import,3)
        Raider.Services.RaidRes.BuildSnapshot=Raider.Diagnostics.Wrap("SR snapshot",Raider.Services.RaidRes.BuildSnapshot,1)
        Raider.Modules.RaidManagement.RefreshPage=Raider.Diagnostics.Wrap("Raid refresh",Raider.Modules.RaidManagement.RefreshPage,1)
        Runtime.diagnosticsWrapped=true
    end
    Raider.Database.onRaidAttendanceChanged=Raider.Services.Raid.OnRaidAttendanceChanged
    Runtime.session=Raider.Services.RaidSession.Create({database=Raider.Database,raid=Raider.Services.Raid,raidRes=Raider.Services.RaidRes,
        raidStatistics=Raider.Services.RaidStatistics,testRaid=Raider.Services.TestRaid,now=function() return time() end})
    Runtime.sessionController=Raider.Modules.RaidSessionController.Create({state=Raider,session=Runtime.session,
        setHistoricalLoaded=function(value) Runtime.historicalLoaded=value and true or false end,
        getHistoricalLoaded=function() return Runtime.historicalLoaded end,
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
        isEnabled=function() return Raider.active and not Runtime.stoppingNativeContent and Raider.Database.GetSetting("useBootyRaidTab") end,
        ensureDatabase=Raider.Database.Ensure,openRaidInfo=Raider.Modules.RaidInfo.Toggle,closeRaidInfo=Raider.Modules.RaidInfo.CloseOwned,
    })
    Runtime.events=Runtime.events or UI.CreateContainer("BootyRaiderEvents",UIParent)
    for _,name in ipairs(eventNames) do Runtime.events:RegisterEvent(name) end
    Runtime.events:SetScript("OnEvent",Dispatch)
    InstallLootHook();Runtime.nativeRaidTab:Sync()
    Raider.CompleteRaidSession=Runtime.SaveSession
    Runtime.initialized=true
    return true
end
local function SyncNative()
    if not Runtime.nativeRaidTab then return true end
    local ok,result,reason=pcall(Runtime.nativeRaidTab.Sync,Runtime.nativeRaidTab)
    if not ok or result==false then return false,CleanupMessage(reason or result,"Native Raid cleanup refused.") end
    return true
end
local function RestoreNative(reason)
    Runtime.stoppingNativeContent=nil
    local restored,failure=SyncNative()
    if not restored then reason=reason.." Native Raid content could not be restored: "..failure end
    return false,reason
end
local function ReleaseResources()
    local failures={}
    local function Attempt(callback,owner,value)
        local ok,result,reason=pcall(callback,owner,value)
        if not ok or result==false then table.insert(failures,CleanupMessage(reason or result)) end
    end
    Raider.active=false
    if Runtime.events then
        for _,name in ipairs(eventNames) do Attempt(Runtime.events.UnregisterEvent,Runtime.events,name) end
    end
    if Runtime.worldContext then Attempt(Runtime.worldContext.CancelConfirmation,Runtime.worldContext) end
    Attempt(RestoreLootHook)
    Attempt(HideTransitionPrompt)
    for _,view in pairs(Runtime.views) do
        if view.Stop then Attempt(view.Stop,view) elseif view.Hide then Attempt(view.Hide,view) end
    end
    if table.getn(failures)>0 then return false,table.concat(failures," ") end
    return true
end
function Runtime.OnActivationFailed()
    local failures={}
    Runtime.stoppingNativeContent=true
    local native,reason=SyncNative()
    if not native then table.insert(failures,reason) end
    local released,failure=ReleaseResources()
    if not released then table.insert(failures,failure) end
    local stopped,result,message=pcall(Raider.Modules.MasterLootWindow.Stop)
    if not stopped or result==false then table.insert(failures,CleanupMessage(message or result)) end
    Runtime.stoppingNativeContent=nil
    Runtime.host=nil
    Runtime.cleanupPending=table.getn(failures)>0 or nil
    if Runtime.cleanupPending then return false,table.concat(failures," ") end
    return true
end
function Runtime.Stop()
    if Runtime.cleanupPending and not Runtime.initialized then return Runtime.OnActivationFailed() end
    if Runtime.IsBusy() then return false,"Save or end the active raid and finish loot operations before stopping BootyRaider." end
    if not Runtime.initialized and not Runtime.cleanupPending then return true end
    Runtime.stoppingNativeContent=true
    local native,reason=SyncNative()
    if not native then return RestoreNative(reason) end
    local called,stopped,failure=pcall(Raider.Modules.MasterLootWindow.Stop)
    if not called or stopped==false then return RestoreNative(CleanupMessage(failure or stopped,"Loot cleanup refused.")) end
    local released,message=ReleaseResources()
    local reset,result,resetFailure=pcall(Raider.Services.Raid.ResetLootSession)
    Runtime.stoppingNativeContent=nil
    Runtime.cleanupPending=not released or not reset or result==false or nil
    if not reset or result==false then
        local failure=CleanupMessage(resetFailure or result)
        message=message and message.." "..failure or failure
    end
    if Runtime.cleanupPending then return false,message end
    return true
end
local function ApplySettingChanges(keys)
    if not Runtime.initialized or not Raider.active then return end
    local native,tracking,autoLoot=false,false,false
    for key in pairs(keys) do
        if key=="profile" or key=="useBootyRaidTab" or key=="useBootyRaidLogo" or string.find(key,"^nativeRaid") then native=true end
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
