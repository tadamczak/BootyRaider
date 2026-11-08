local Raider=BootyRaider
local SyncRuntime={}
Raider.Modules.RaidSyncRuntime=SyncRuntime
local runtime,nextWake,changed,statusChanged,registered,rosterAt,lastRosterFailure
local statusRefreshAt
local lootRefresh,lootRefreshAt={},nil
local onlineOfficers
local maintenance,waitingConfirmation,compactedAt,maintenanceArmed={},{},{},false
local function Now() return type(GetTime)=="function" and GetTime() or time() end
local function RecordLog(id,kind,database) return Raider.Services.RaidAudit.IsLogRecording(id,database) end
local function Combat() return type(UnitAffectingCombat)=="function" and UnitAffectingCombat("player") and true or false end
local function Scope()
    -- A bounded directory refresh temporarily has no snapshot. Membership and
    -- scope are live client facts; officer authority still requires fresh rows.
    local member=type(IsInGuild)=="function" and IsInGuild()
    if member==false or member==0 then return nil end
    local guild=type(GetGuildInfo)=="function" and GetGuildInfo("player")
    if type(guild)~="string" or guild=="" then
        -- The client may report membership before the guild name is ready.
        -- Keep only the paused session identity; this never authorizes traffic.
        return member and runtime and runtime.raidSync and runtime.raidSync.scope or nil
    end
    local realm=type(GetRealmName)=="function" and GetRealmName() or "UnknownRealm"
    return realm.."|"..guild
end
local function DirectoryReady()
    return BootyLib.GuildDirectory and BootyLib.GuildDirectory.GetSnapshot()~=nil
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
function SyncRuntime.CanJoinRaid(id)
    if not runtime or not runtime.replica then return true end
    local raidCount=type(GetNumRaidMembers)=="function" and GetNumRaidMembers() or 0
    local partyCount=type(GetNumPartyMembers)=="function" and GetNumPartyMembers() or 0
    if raidCount==0 and partyCount==0 then return true end
    local own=runtime.replica.GetJoinedRaidId()
    if own and own~=id then return false,"An active session already exists. Join it from Active raid sessions." end
    local peers=runtime.replica.GetStatus().peers
    if table.getn(peers)==0 then return true end
    for index=1,(raidCount>0 and raidCount or partyCount) do
        local name
        if raidCount>0 then name=GetRaidRosterInfo(index) else name=UnitName("party"..index) end
        for _,peer in ipairs(peers) do
            if not id and peer.available and peer.name==name and peer.syncState=="pending" then return false,"Checking the active session with "..name.."." end
            if peer.available and peer.name==name and peer.activeRaidId and peer.activeRaidId~=id then
                local status=runtime.replica.GetStatus(peer.activeRaidId)
                if status.lifecycle~="ended" and status.lifecycle~="deleted" then return false,"Join the active raid session shared by "..name.."." end
            end
        end
    end
    return true
end
local function MaintenanceReady()
    return maintenanceArmed and next(maintenance)~=nil and not Combat()
        and not Raider.Services.Raid.IsInRaid()
        and runtime and runtime.raidSync and not runtime.raidSync:HasWork()
end
local function HasWork()
    return changed or statusChanged or lootRefreshAt or rosterAt or MaintenanceReady() or runtime and runtime.replica and runtime.replica.HasWork()
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
    -- Count the attempted batch too: an unconfirmed history must not be scanned
    -- again after each subsequent loot event.
    compactedAt[id]=table.getn(raid.operationIds or {})
    if (report.pendingConfirmation or 0)>0 then
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
    if not Raider.active then this:SetScript("OnUpdate",nil);nextWake=nil;return end
    local now=Now();if nextWake and now<nextWake then return end
    -- Wake clears the deadline when client events add work. Until then, avoid
    -- walking peers, queues and maintenance state on every rendered frame.
    if not HasWork() then this:SetScript("OnUpdate",nil);nextWake=nil;return end
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
    if lootRefreshAt and now>=lootRefreshAt and not changed then
        for id,names in pairs(lootRefresh) do runtime.RefreshLootViews(id,names);lootRefresh[id]=nil end
        lootRefreshAt=nil
    end
    if changed or statusChanged and (not statusRefreshAt or now>=statusRefreshAt) then
        local refresh=changed;changed=false;statusChanged=false
        statusRefreshAt=now+0.25
        local view=runtime.views.raid
        if view and view.page and view.page:IsVisible() and Raider.Modules.RaidManagement.RefreshSyncStatus then Raider.Modules.RaidManagement.RefreshSyncStatus(view.page) end
        if refresh then
            lootRefresh={};lootRefreshAt=nil
            runtime.RefreshViews()
        end
        if Raider.Modules.RaidSync then Raider.Modules.RaidSync.RefreshVisible() end
    end
    if runtime.replica.HasWork() then nextWake=now else nextWake=runtime.raidSync and runtime.raidSync:NextWake() end
    if rosterAt and (not nextWake or rosterAt<nextWake) then nextWake=rosterAt end
    if lootRefreshAt and (not nextWake or lootRefreshAt<nextWake) then nextWake=lootRefreshAt end
    if statusChanged and (not nextWake or (statusRefreshAt or now)<nextWake) then nextWake=statusRefreshAt or now end
    if changed or MaintenanceReady() then nextWake=now end
    if not HasWork() then runtime.events:SetScript("OnUpdate",nil);nextWake=nil end
end
local function Update() SyncRuntime.Tick() end
function SyncRuntime.QueueLootRefresh(id,names)
    if not id then return end
    lootRefresh[id]=lootRefresh[id] or {}
    for name in pairs(names or {}) do lootRefresh[id][name]=true end
    lootRefreshAt=lootRefreshAt or Now()+0.05
    SyncRuntime.Wake()
end
function SyncRuntime.OnRosterUpdate()
    if HiddenRecording() then rosterAt=Now()+0.25 else rosterAt=nil end
    SyncRuntime.Wake()
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
    attendance.syncRecoveryNotice=attendance.syncRecoveryNotice or "Recovered agreed data. Events missed by every recorder cannot be reconstructed."
    runtime.RefreshViews();return true
end
function SyncRuntime.Initialize(owner)
    runtime=owner
    local database=Raider.Database.Ensure()
    Raider.Services.RaidJournal.SetAuditPolicy(database,RecordLog)
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
            restore=Restore,onChanged=function(id,names,kind)
                if kind=="loot" then SyncRuntime.QueueLootRefresh(id,names) else changed=true end
                QueueMaintenance(id)
            end,
            onSessionDeleted=function(previous,id) runtime.OnSessionDeleted(previous,id) end,
            onAttendance=function(previous,attendance)
                Raider.Services.Raid.PreserveLootSession(previous,attendance)
                if attendance.syncEnded then
                    Raider.raidSessionPaused=true;Raider.raidLiveTracking=false
                    runtime.ShowEndedSessionPrompt(attendance)
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
    if not Raider.active or type(SendAddonMessage)~="function" or Raider.Database.GetSetting("raidSyncEnabled")==false then
        if runtime.raidSync then runtime.raidSync:Stop("officer-authority-or-messaging-unavailable") end
        SyncRuntime.Wake();return false
    end
    if runtime.raidSync and runtime.raidSync.scope~=scope then
        runtime.raidSync:Stop("guild-scope-changed");runtime.raidSync=nil;onlineOfficers=nil
    end
    if not scope then SyncRuntime.Wake();return false,"guild-scope-unavailable" end
    if not DirectoryReady() then
        if runtime.raidSync then runtime.raidSync:RefreshReadiness() end
        SyncRuntime.Wake();return false,"directory-not-ready"
    end
    if not LocalAuthority() then
        if runtime.raidSync then runtime.raidSync:Stop("officer-authority-or-messaging-unavailable") end
        SyncRuntime.Wake();return false
    end
    if not runtime.raidSync then
        runtime.raidSync=Raider.Services.RaidSync.Create({db=Raider.Database.Ensure(),journal=Raider.Services.RaidJournal,
            codec=Raider.Services.RaidSyncCodec,now=Now,actor=function() return UnitName("player") end,scope=Scope,authorize=Authority,
            isDirectoryReady=DirectoryReady,
            isOnline=function(name) local member=BootyLib.GuildDirectory.Find(name);return member and member.online~=false end,
            presenceRevision=BootyLib.GuildDirectory.GetGeneration,
            send=function(prefix,text,channel) return SendAddonMessage(prefix,text,channel) end,
            activeRaidId=function() return runtime.replica.GetJoinedRaidId() end,
            isRaidEnabled=function(id) return runtime.replica.IsRaidSyncEnabled(id) end,
            getPendingRaidIds=function() return runtime.replica.GetPendingRaidIds() end,
            onRaidCaughtUp=function(id) runtime.replica.OnRaidCaughtUp(id) end,
            priority=function(id)
                local current=Raider.Database.GetRaidAttendance();if current and current.syncRaidId==id then return 1 end
                local record=Raider.Services.RaidJournal.GetRecord(BootyRaiderDB,id,"saved:flags")
                return record and record.value and record.value.csrEnabled and 2 or 3
            end,
            inCombat=Combat,
            validateOperation=Raider.Services.RaidReplica.ValidateOperation,
            validateCheckpoint=Raider.Services.RaidReplica.ValidateCheckpoint,
            onApply=function(operation,reason,source) runtime.replica.OnOperation(operation,reason,false,source) end,
            onConnected=function(name) runtime.replica.LogSync("Connected to "..name..". Checking raid updates.") end,
            onDisconnected=function(name,reason,reported)
                if not reported then runtime.replica.LogSync("Lost connection to "..name.." ("..tostring(reason or "offline")..").") end
            end,
            onFailure=function(message) runtime.replica.LogSync(message) end,
            onRaidDelivered=function(name,id,count,lastOperationId)
                ArmMaintenance()
                local operation=count==1 and lastOperationId and Raider.Services.RaidJournal.GetOperation(BootyRaiderDB,lastOperationId)
                if operation and operation.kind~="raid.observe" and operation.kind~="raid.seed" and not operation.compacted then
                    local action=Raider.Modules.RaidLog and Raider.Modules.RaidLog.FormatAction(operation) or operation.kind
                    runtime.replica.LogSync(name.." confirmed receipt: "..tostring(action))
                elseif count>1 then
                    local metadata=Raider.Services.RaidJournal.GetRecord(BootyRaiderDB,id,"raid:metadata")
                    runtime.replica.LogSync(name.." confirmed raid "..tostring(metadata and metadata.value and metadata.value.id or id).." ("..count.." updates).")
                end
            end,
            onStatus=function(status)
                runtime.replica._state.revision=runtime.replica._state.revision+1;statusChanged=true;SyncRuntime.Wake() end})
        runtime.replica.SetTransport(runtime.raidSync)
    end
    local ok,reason=runtime.raidSync:Start()
    if not ok then SyncRuntime.Wake();return false,reason end
    runtime.raidSync:RefreshPresence()
    local names={};local added=false;local snapshot=BootyLib.GuildDirectory.GetSnapshot()
    for _,member in ipairs(snapshot and snapshot.members or {}) do
        if member.online~=false and member.name~=UnitName("player") and Authority(member.name,scope) then
            names[member.name]=true
            if not onlineOfficers or not onlineOfficers[member.name] then added=true end
        end
    end
    onlineOfficers=names
    if ok and added then runtime.raidSync:Discover() end
    SyncRuntime.Wake();return ok,reason
end
function SyncRuntime.Receive(prefix,text,channel,sender)
    if runtime and runtime.raidSync then
        local accepted=runtime.raidSync:Receive(prefix,text,channel,sender)
        if accepted then statusChanged=true end
        SyncRuntime.Wake()
    end
end
function SyncRuntime.Stop()
    if runtime and runtime.raidSync then runtime.raidSync:Stop("disabled") end
    if runtime and runtime.events then
        runtime.events:SetScript("OnUpdate",nil)
        if registered then runtime.events:UnregisterEvent("CHAT_MSG_ADDON");runtime.events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    end
    onlineOfficers=nil;registered=nil;nextWake=nil;rosterAt=nil;changed=nil;statusChanged=nil;statusRefreshAt=nil;maintenanceArmed=false;lastRosterFailure=nil
    lootRefresh={};lootRefreshAt=nil
    if Raider.Modules.RaidSync then Raider.Modules.RaidSync.Close() end
end
