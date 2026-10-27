local Raider=BootyRaider
local SyncRuntime={}
Raider.Modules.RaidSyncRuntime=SyncRuntime
local runtime,nextWake,changed,statusChanged,registered,rosterAt,lastRosterFailure
local lastSyncError
local onlineOfficers
local maintenance,waitingConfirmation,compactedAt,maintenanceArmed={},{},{},false
local function Now() return type(GetTime)=="function" and GetTime() or time() end
local function Combat() return type(UnitAffectingCombat)=="function" and UnitAffectingCombat("player") and true or false end
local function Scope()
    local snapshot=BootyLib.GuildDirectory and BootyLib.GuildDirectory.GetSnapshot()
    return snapshot and snapshot.realmName.."|"..snapshot.guildName or nil
end
local function Authority(name,scope)
    if not Raider.active or not runtime or Raider.Database.GetSetting("raidSyncEnabled")==false or scope~=Scope() then return false end
    return Raider.Services.RankPolicy.HasOfficerAuthority(name)
end
local function LocalAuthority()
    return Raider.Services.RankPolicy.CanManageHistory()
end
function SyncRuntime.WantsDirectory()
    return Raider.active and type(SendAddonMessage)=="function" and Raider.Database.GetSetting("raidSyncEnabled")~=false
end
local function MaintenanceReady()
    return maintenanceArmed and next(maintenance)~=nil and not Combat()
        and runtime and runtime.raidSync and not runtime.raidSync:HasWork()
end
local function HasWork()
    return changed or statusChanged or rosterAt or MaintenanceReady() or runtime and runtime.replica and runtime.replica.HasWork()
        or runtime and runtime.raidSync and runtime.raidSync:HasWork()
end
local function QueueMaintenance(id)
    local journal=BootyRaiderDB.raidJournal;local raid=journal and journal.raids[id]
    if raid and table.getn(raid.operationIds or {})>=(compactedAt[id] or 0)+128 then maintenance[id]=true;maintenanceArmed=true end
end
local function ArmMaintenance()
    for id in pairs(waitingConfirmation) do maintenance[id]=true;waitingConfirmation[id]=nil end
    maintenanceArmed=true
end
local function CompactOne()
    if not MaintenanceReady() then return end
    local id=next(maintenance);maintenance[id]=nil
    local journal=BootyRaiderDB.raidJournal;local raid=journal and journal.raids[id]
    local confirmed=runtime.raidSync:GetConfirmedFrontiers(id)
    local report,reason=Raider.Services.RaidJournal.Compact(BootyRaiderDB,id,confirmed)
    if not report then runtime.Print("Raid checkpoint: "..tostring(reason));return end
    if (report.pendingConfirmation or 0)==0 then compactedAt[id]=table.getn(raid.operationIds or {})
    else
        -- Retry on a later receipt; one waiting raid must not starve maintenance
        -- for other raids, nor keep an idle frame handler installed.
        waitingConfirmation[id]=true
    end
end
local function HiddenRecording()
    if not runtime or not runtime.replica or not LocalAuthority() then return false end
    local view=runtime.views.raid
    if view and view.page and (view.page:IsVisible() or view.page.lootMasterController and view.page.lootMasterController.IsVisible()) then return false end
    return Raider.Database.GetSetting("raidLiveTrackingEnabled") and not Raider.raidSessionPaused and not Raider.raidSessionTransitionPending
        and not runtime.IsTestRaid() and Raider.raidScanReady and not runtime.historicalLoaded and Raider.Services.Raid.IsInRaid()
        and Raider.Services.RaidRes.HasSession(Raider.Database.GetRaidAttendance())
end
function SyncRuntime.Tick()
    if not Raider.active or not HasWork() then this:SetScript("OnUpdate",nil);nextWake=nil;return end
    local now=Now();if nextWake and now<nextWake then return end
    if runtime.raidSync then runtime.raidSync:Tick() end
    if rosterAt and now>=rosterAt then
        rosterAt=nil
        if HiddenRecording() then
            local count,reason=runtime.CaptureActiveRoster()
            if count==nil then
                if reason~=lastRosterFailure then runtime.Print("Raid observation retained previous data: "..tostring(reason)) end
                lastRosterFailure=reason
            else lastRosterFailure=nil end
        end
    end
    runtime.replica.Flush(1)
    CompactOne()
    if changed or statusChanged then
        local refresh=changed;changed=false;statusChanged=false
        if refresh then runtime.RefreshViews() end
        if Raider.Modules.RaidSync then Raider.Modules.RaidSync.RefreshVisible() end
    end
    if runtime.replica.HasWork() then nextWake=now else nextWake=runtime.raidSync and runtime.raidSync:NextWake() end
    if rosterAt and (not nextWake or rosterAt<nextWake) then nextWake=rosterAt end
    if changed or statusChanged or MaintenanceReady() then nextWake=now end
    if not HasWork() then runtime.events:SetScript("OnUpdate",nil);nextWake=nil end
end
local function Update() SyncRuntime.Tick() end
function SyncRuntime.OnRosterUpdate()
    if HiddenRecording() then rosterAt=Now()+0.25;SyncRuntime.Wake() else rosterAt=nil end
end
function SyncRuntime.Wake()
    if runtime and runtime.events and Raider.active and HasWork() then nextWake=nil;runtime.events:SetScript("OnUpdate",Update) end
end
local function Restore(attendance)
    if runtime.IsTestRaid() or Raider.Services.Raid.HasPendingReyCoinAward() or Raider.Services.Raid.HasPendingSoftReserveTrade()
        or Raider.Modules.MasterLootWindow.IsBusy and Raider.Modules.MasterLootWindow.IsBusy() then return false,"Finish the current loot action or Test Raid before recovering a session." end
    Raider.Database.StoreRaidAttendance(attendance)
    runtime.sessionController:RestoreActive();runtime.sessionController:Begin();runtime.historicalLoaded=true
    if attendance.syncEnded then Raider.raidSessionPaused=true;Raider.raidLiveTracking=false end
    runtime.CloseSessionPrompts()
    attendance.syncRecoveryNotice="Recovered agreed data. Events missed by every recorder cannot be reconstructed."
    runtime.RefreshViews();return true
end
function SyncRuntime.Initialize(owner)
    runtime=owner
    if not runtime.replica then
        runtime.replica=Raider.Services.RaidReplica.Create({db=Raider.Database.Ensure(),authorize=LocalAuthority,wake=SyncRuntime.Wake,
            recorderAvailable=function(name,id,peers)
                if string.lower(name)==string.lower(UnitName("player") or "") then
                    local active=Raider.Database.GetRaidAttendance()
                    return active and active.syncRaidId==id and Raider.Services.Raid.IsInRaid()
                        and Raider.Database.GetSetting("raidLiveTrackingEnabled") and not Raider.raidSessionPaused
                        and not Raider.raidSessionTransitionPending and not runtime.historicalLoaded
                end
                local member=BootyLib.GuildDirectory.Find(name)
                if not member or member.online==false then return false end
                for _,peer in ipairs(peers) do
                    if string.lower(peer.name)==string.lower(name) and peer.available then return true end
                end
                return false
            end,
            restore=Restore,onChanged=function(id) changed=true;QueueMaintenance(id) end,
            onAttendance=function(previous,attendance)
                Raider.Services.Raid.PreserveLootSession(previous,attendance)
                if attendance.syncEnded then
                    Raider.raidSessionPaused=true
                    if not previous.syncEnded then runtime.Print(runtime.replica.GetStatus(attendance.syncRaidId).message) end
                end
                if previous.raidName~=attendance.raidName then
                    Raider.Services.AutoLoot.ApplyRaidPreset(attendance.raidName);Raider.OnSettingChanged("lmAutoLootPresets")
                end
            end})
    end
    if not registered and type(SendAddonMessage)=="function" then
        runtime.events:RegisterEvent("CHAT_MSG_ADDON");runtime.events:RegisterEvent("PLAYER_REGEN_ENABLED");registered=true
    end
    return SyncRuntime.RefreshAuthority()
end
function SyncRuntime.RefreshAuthority()
    if not runtime or not runtime.replica then return false end
    local scope=Scope()
    if not Raider.active or type(SendAddonMessage)~="function" or Raider.Database.GetSetting("raidSyncEnabled")==false or not LocalAuthority() then
        if runtime.raidSync then runtime.raidSync:Stop("officer-authority-or-messaging-unavailable") end
        SyncRuntime.Wake();return false
    end
    if runtime.raidSync and runtime.raidSync.scope~=scope then runtime.raidSync:Stop("guild-scope-changed");runtime.raidSync=nil end
    if not runtime.raidSync then
        runtime.raidSync=Raider.Services.RaidSync.Create({db=Raider.Database.Ensure(),journal=Raider.Services.RaidJournal,
            codec=Raider.Services.RaidSyncCodec,now=Now,actor=function() return UnitName("player") end,scope=Scope,authorize=Authority,
            isOnline=function(name) local member=BootyLib.GuildDirectory.Find(name);return member and member.online~=false end,
            presenceRevision=BootyLib.GuildDirectory.GetGeneration,
            send=function(prefix,text,channel) return SendAddonMessage(prefix,text,channel) end,
            activeRaidId=function() local current=Raider.Database.GetRaidAttendance();return current and current.syncRaidId end,
            priority=function(id)
                local current=Raider.Database.GetRaidAttendance();if current and current.syncRaidId==id then return 1 end
                local record=Raider.Services.RaidJournal.GetRecord(BootyRaiderDB,id,"saved:flags")
                return record and record.value and record.value.csrEnabled and 2 or 3
            end,
            inCombat=Combat,
            validateOperation=Raider.Services.RaidReplica.ValidateOperation,
            validateCheckpoint=Raider.Services.RaidReplica.ValidateCheckpoint,
            onApply=function(operation,reason) runtime.replica.OnOperation(operation,reason,false) end,
            onConnected=function(name) runtime.replica.LogSync("Connected to "..name..". Checking raid updates.") end,
            onDelivered=function(name,id)
                local operation=Raider.Services.RaidJournal.GetOperation(BootyRaiderDB,id)
                if operation and operation.kind~="raid.observe" and not operation.compacted then
                    local action=Raider.Modules.RaidLog and Raider.Modules.RaidLog.FormatAction(operation) or operation.kind
                    runtime.replica.LogSync(name.." confirmed receipt: "..tostring(action))
                end
            end,
            onStatus=function(status)
                if status.lastError and status.lastError~=lastSyncError then runtime.replica.LogSync(status.message) end
                lastSyncError=status.lastError
                runtime.replica._state.revision=runtime.replica._state.revision+1;statusChanged=true;ArmMaintenance();SyncRuntime.Wake() end})
        runtime.replica.SetTransport(runtime.raidSync)
    end
    local ok,reason=runtime.raidSync:Start()
    local names={};local snapshot=BootyLib.GuildDirectory.GetSnapshot()
    for _,member in ipairs(snapshot and snapshot.members or {}) do
        if member.online~=false and Authority(member.name,scope) then table.insert(names,member.name) end
    end
    table.sort(names);local signature=table.concat(names,",")
    if ok and signature~=onlineOfficers then onlineOfficers=signature;runtime.raidSync:Discover() end
    SyncRuntime.Wake();return ok,reason
end
function SyncRuntime.Receive(prefix,text,channel,sender)
    if runtime and runtime.raidSync then
        local accepted=runtime.raidSync:Receive(prefix,text,channel,sender)
        if accepted then statusChanged=true;ArmMaintenance() end
        SyncRuntime.Wake()
    end
end
function SyncRuntime.Stop()
    if runtime and runtime.raidSync then runtime.raidSync:Stop("disabled") end
    if runtime and runtime.events then
        runtime.events:SetScript("OnUpdate",nil)
        if registered then runtime.events:UnregisterEvent("CHAT_MSG_ADDON");runtime.events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    end
    lastSyncError=nil;onlineOfficers=nil;registered=nil;nextWake=nil;rosterAt=nil;changed=nil;statusChanged=nil;maintenanceArmed=false;lastRosterFailure=nil
    if Raider.Modules.RaidSync then Raider.Modules.RaidSync.Close() end
end
