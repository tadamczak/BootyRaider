local Raider = BootyRaider
local UI = Raider.UI.Components
local Raid = Raider.Modules.RaidManagement
local Runtime = Raider.Runtime
local Screen = {}
Raider.Modules.RaidScreen = Screen

function Screen.Create(parent, host)
    Runtime.Initialize(host)
    local page = UI.CreateContainer(nil,parent)
    page.bootyStandalone = host and host.standalone or false
    page:SetAllPoints(parent);page.bootyWidthOwner=parent;page.bootyHeightOwner=parent
    page.bootyWidthInset=0;page.bootyHeightInset=0;page:Hide()
    local function SizePage()
        local width,height=UI.GetFrameSpan(parent)
        page:SetWidth(math.max(1,width));page:SetHeight(math.max(1,height))
    end
    SizePage()
    local controller={page=page,frame=page}
    Runtime.views.raid=controller
    local selectedClasses,selectedRanks,visibleMembers={},{},{}
    local sortKey,ascending,selectedName=nil,true,nil
    local Refresh
    local chrome=Raid.CreateChrome(page,{
        toggleLootMaster=function() if page.lootMasterController then page.lootMasterController.toggle() end end,
        toggleMinimize=function() if page.lootMasterController then page.lootMasterController.toggleMinimize() end end,
    })
    local actions=Raid.CreateActionControls(page)
    function page.OpenRaidLog(record)
        if Runtime.IsTestRaid() then return false end
        local ok,result=Raider.Modules.RaidLog.Open(record or Runtime.GetAttendance(),page)
        if not ok then Runtime.Print(result) end
        return ok,result
    end
    function page.OpenRaidSync(record)
        local ok,result=Raider.Modules.RaidSync.Open(record or Runtime.GetAttendance(),page)
        if not ok then Runtime.Print(result) end
        return ok,result
    end
    local function RunAction(member,action) return Runtime.ActiveRaidService().RunMemberAction(member,action) end
    local function Counts() return Runtime.ActiveRaidService().GetGroupCounts() end
    local function MoveGroup(member,group) return Runtime.ActiveRaidService().MoveMemberToGroup(member,group) end
    local function MoveSlot(member,target,group) return Runtime.ActiveRaidService().MoveMemberToSlot(member,target,group) end
    local function LootInfo() return Runtime.ActiveRaidService().GetLootMasterInfo() end
    local function MemberCount() return Runtime.ActiveRaidService().GetRaidMemberCount() end
    local function MemberInfo(index) return Runtime.ActiveRaidService().GetRaidMemberInfo(index) end
    local function Ignored(name) return Runtime.ActiveRaidService().IsPlayerIgnored(name) end
    local function Rules()
        local rules=Raider.Database.GetLootRules()
        return Runtime.IsTestRaid() and Raider.Services.TestRaid.GetLootRules(rules) or rules
    end
    local list=Raid.MountList(page,chrome,{
        selectedClasses=selectedClasses,selectedRanks=selectedRanks,getData=Runtime.GetAttendance,getRules=Rules,
        getFilterValues=Raider.Services.Raid.GetFilterValues,runMemberAction=RunAction,
        isSelected=function(member) return selectedName==member.name end,
        refresh=function() Refresh() end,
        onReset=function() sortKey=nil;ascending=true;selectedName=nil;Refresh() end,
        onSort=function(key,defaultAscending)
            if sortKey~=key then sortKey=key;ascending=defaultAscending
            elseif ascending then ascending=false else sortKey=nil;ascending=true end
            Refresh()
        end,
        onSelect=function(row)
            if selectedName==row.displayedMember.name then selectedName=nil
            else selectedName=row.displayedMember.name end
            Refresh()
        end,
        applySoftReserveAssignments=Raider.Services.RaidRes.ApplyAssignments,
        clearUnmatchedSoftReserves=Raider.Services.RaidRes.ClearUnmatched,
        removeSoftReserve=function(name) return Raider.Services.RaidRes.RemoveMemberReservation(Runtime.GetAttendance(),name) end,
        rowCount=25,
    })
    Raid.MountGroupView(page,{
        getGroupCounts=Counts,moveMemberToGroup=MoveGroup,moveMemberToSlot=MoveSlot,isTestRaid=Runtime.IsTestRaid,
        isPlayerIgnored=Ignored,runMemberAction=RunAction,ensureDatabase=Raider.Database.Ensure,getLootMasterInfo=LootInfo,
        getRaidMemberCount=MemberCount,getRaidMemberInfo=MemberInfo,refresh=function() Refresh() end,
        onViewChanged=function() selectedName=nil;Refresh() end,
    })
    Raider.OpenRaidGroupSelector=page.openGroupSelector;Raider.UpdateRaidDragGhost=page.updateDragGhost
    Raider.ShowRaidMemberMenu=page.showMemberMenu;Raider.RefreshRaidGroupView=page.refreshGroupView
    Raid.MountChrome(page,chrome,actions)
    Raid.SetListRenderer(page,{
        updateScrollFrame=UI.UpdateScrollFrame,getLootMasterInfo=LootInfo,getData=Runtime.GetAttendance,shorten=UI.ShortenText,
        sortMembers=function(a,b) return Raid.CompareMembers(a,b,sortKey,ascending) end,
        onSelectionMissing=function() selectedName=nil end,
    })
    local renderer=Raid.CreateRenderer({
        page=page,rows=list.rows,unavailable=chrome.unavailable,searchBox=chrome.searchBox,visibleMembers=visibleMembers,
        selectedClasses=selectedClasses,selectedRanks=selectedRanks,countRefresh=function() Raider.Diagnostics.Count("uiRefreshes") end,
        isLootMasterMode=function() return false end,isLootMasterMinimized=function() return false end,
        isTestRaid=Runtime.IsTestRaid,isInRaid=Runtime.IsInRaid,isHistoricalLoaded=function() return Runtime.historicalLoaded end,
        isScanReady=function() return Raider.raidScanReady end,setScanReady=function(value) Raider.raidScanReady=value end,
        getData=Runtime.GetAttendance,getSelectedName=function() return selectedName end,getSortKey=function() return sortKey end,
        getSettings=function() return BootyRaiderDB end,
    })
    local raidTypeButton=UI.CreateControl(nil,page)
    page.raidTypeButton=raidTypeButton
    UI.AttachTooltip(raidTypeButton,"Raid Type","Click to change the type of this session. Existing SR and loot are preserved.")
    raidTypeButton:Hide()
    local selectedAttendance
    raidTypeButton:SetScript("OnClick",function()
        if page.raidTypePanel and page.raidTypePanel:IsShown() then page.raidTypePanel:Hide();return end
        selectedAttendance=Runtime.GetAttendance()
        if Runtime.IsTestRaid() or not Raider.Services.RaidRes.HasSession(selectedAttendance) then return end
        if not page.raidTypePanel then
            local names=Raider.Services.RaidStatistics.GetRaidNames()
            local panel=UI.CreateDropdownPanel(page,raidTypeButton,200,16+table.getn(names)*24,10)
            page.raidTypePanel=panel
            panel.options={}
            for _,name in ipairs(names) do
                local choice=UI.CreateButton(panel,nil,name,184,22)
                choice:SetPoint("TOPLEFT",panel,"TOPLEFT",8,-8-table.getn(panel.options)*24)
                choice.raidName=name;table.insert(panel.options,choice)
                choice:SetScript("OnClick",function()
                    local ok,reason=Runtime.session:SetRaidType(this.raidName,selectedAttendance)
                    if not ok then Runtime.Print(reason);panel:Hide();return end
                    if page.srEditor then page.srEditor:Hide() end
                    if page.srReview then page.srReview:Hide() end
                    panel:Hide();Refresh()
                end)
            end
        end
        page.raidTypePanel:Show()
    end)
    Refresh=function()
        if Raider.Modules.RaidLog then Raider.Modules.RaidLog.RefreshVisible() end
        if Raider.Modules.RaidSync then Raider.Modules.RaidSync.RefreshVisible() end
        if not page:IsVisible() and not (page.lootMasterController and page.lootMasterController.IsVisible()) then return end
        if page:IsVisible() then
            Raid.RefreshPage(renderer)
            local attendance=Runtime.GetAttendance()
            local label=UI.IsClassicSkin() and page.classicRaidName or page.refreshControls.title
            if not Runtime.IsTestRaid() and Raider.Services.RaidRes.HasSession(attendance) and label:IsShown() then
                raidTypeButton:ClearAllPoints();raidTypeButton:SetAllPoints(label);raidTypeButton:Show()
            else raidTypeButton:Hide();if page.raidTypePanel then page.raidTypePanel:Hide() end end
        end
        if page.lootMasterController then page.lootMasterController.Refresh() end
        if page.lmConfigPanel:IsShown() and page.RefreshAutoLootConfig then page.RefreshAutoLootConfig() end
    end
    Raid.RegisterResetLootDialog({getAttendance=Runtime.GetAttendance,clearSelection=function() selectedName=nil end,
        refresh=Refresh,printMessage=Runtime.PrintAction})
    local lifecycle=Raid.CreateLifecycle({
        page=page,isInRaid=Runtime.IsInRaid,getTrackingEnabled=function()
            return Raider.active and BootyRaiderDB.raidLiveTrackingEnabled and not Raider.raidSessionPaused and not Raider.raidSessionTransitionPending
        end,
        getScanReady=function() return Raider.raidScanReady end,isHistoricalLoaded=function() return Runtime.historicalLoaded end,
        isPresentationActive=function() return page:IsVisible() or page.lootMasterController and page.lootMasterController.IsVisible() end,
        isDetachedActive=function() return page.lootMasterController and page.lootMasterController.IsVisible() end,
        saveRaidRoster=Runtime.CaptureActiveRoster,setLiveTracking=function(value) Raider.raidLiveTracking=value end,
        setScanReady=function(value) Raider.raidScanReady=value end,refresh=Refresh,onWorldContextChanged=Runtime.worldContext.Update,
    })
    Raid.CreateLootMasterController({page=page,getSettings=function() return BootyRaiderDB end,refresh=Refresh})
    controller.quickActions=Raid.AttachActionHandlers({
        page=page,isTestRaid=Runtime.IsTestRaid,
        importData=function(value,url) return Raider.Services.RaidRes.Import(value,Runtime.GetAttendance(),url) end,
        getSrUrl=function() return Raider.Services.RaidRes.GetUrl(Runtime.GetAttendance()) end,
        getRollForExport=function() return Raider.Services.RaidRes.GetRollForExport(Runtime.GetAttendance()) end,
        setSrUrl=function(value) return Raider.Services.RaidRes.SetUrl(Runtime.GetAttendance(),value) end,
        shareSrUrl=function(value) return Raider.Services.Raid.SendLootMessage("SRLink",{link=tostring(value or "")}) end,
        shareMissingSrNames=Raider.Services.Raid.SendRaidWarningList,getAttendance=Runtime.GetAttendance,
        getRaidHistory=Raider.Database.GetSoftReserveHistory,raidIdExists=function(id) return Runtime.session:RaidIdExists(id) end,
        deleteRaidSnapshot=Raider.Database.DeleteSoftReserveSnapshot,loadRaidSnapshot=function(id) return Runtime.session:LoadSnapshot(id) end,
        prepareRaidSave=function(options) return Runtime.session:PrepareSave(options) end,
        cancelRaidSave=function(confirmation) return Runtime.session:CancelPreparedSave(confirmation) end,
        updateRaidMetadata=Raider.Database.UpdateRaidMetadata,
        showSavedPopup=function() UI.ShowOpaquePopup("BOOTY_RAIDER_ATTENDANCE_RELOAD") end,
        acceptLoadedRaid=Runtime.AcceptLoadedSnapshot,
        setHistoricalLoaded=function(value) Runtime.historicalLoaded=value and true or false end,getRules=Rules,
        saveRules=function(rules)
            if Runtime.IsTestRaid() then return Raider.Services.TestRaid.SaveLootRules(rules) else return Raider.Database.SaveLootRules(rules) end
        end,
        getHighlyContestedItems=function()
            local items=Raider.Database.GetHighlyContestedItems()
            return Runtime.IsTestRaid() and Raider.Services.TestRaid.GetHighlyContestedItems(items) or items
        end,
        saveHighlyContestedItems=function(items)
            if Runtime.IsTestRaid() then return Raider.Services.TestRaid.SaveHighlyContestedItems(items) end
            return Raider.Database.SaveHighlyContestedItems(items)
        end,
        isInRaid=Runtime.IsInRaid,isSessionActive=function() return Raider.raidSessionDraft or Raider.raidScanReady or Runtime.IsTestRaid() end,
        requestRosterScan=Runtime.RequestRaidScan,saveRaidRoster=Runtime.CaptureActiveRoster,
        beginRaidSession=function() Runtime.sessionController:Begin();Runtime.worldContext.Update() end,
        startNewRaid=function(id,name,syncEnabled) return Runtime.sessionController:StartNew(id,name,syncEnabled) end,
        saveRaidSession=Runtime.SaveSession,quitRaidSession=Runtime.QuitSession,
        handleEndedSession=Runtime.ShowEndedSessionPrompt,
        continueRaidSession=function(context) Runtime.sessionController:Continue(context) end,
        dismissRaidSessionTransition=function(context) Runtime.sessionController:DismissTransition(context) end,
        hasPendingRaidTransition=function() return Raider.raidSessionTransitionPending end,
        refreshCurrentRaid=function() return Runtime.sessionController:RefreshCurrentRaid() end,
        cancelPendingRaidScan=function() return Runtime.sessionController:CancelPendingRaidScan() end,
        getPendingRaidToken=function() return Runtime.session.pendingRaid end,
        dismissRaidStartReminder=function(context) Raider.raidStartReminderContext=context end,openRaidManagement=function() Runtime.OpenView("raid") end,
        startTestRaid=function() Runtime.sessionController:StartTest() end,refresh=Refresh,printMessage=Runtime.PrintAction,showPopup=UI.ShowOpaquePopup,
        getLiveTracking=function() return Raider.raidLiveTracking end,setLiveTracking=function(value) Raider.raidLiveTracking=value end,
        setScanReady=function(value) Raider.raidScanReady=value end,
    })
    Raid.AttachResizeHandler(page,Refresh);Raid.AttachListScroll(page,Refresh)
    function controller:Show() if not Raider.active then return end;SizePage();lifecycle:Show();Refresh() end
    function controller:Hide() page:Hide();lifecycle:Hide() end
    function controller:Refresh() Refresh() end
    function controller:HideSessionTransitionPrompt() page.HideSessionTransitionPrompt() end
    function controller:CancelSessionSave() page.CancelSessionSave() end
    function controller:OnResize() SizePage();Refresh() end
    function controller:OnGroupChanged()
        if page:IsVisible() then Raid.UpdateConvertRaidButton(page, false) end
    end
    function controller:OnRosterUpdate() self:OnGroupChanged();lifecycle:OnRosterUpdate() end
    function controller:SyncTrackingSetting(skipRefresh) lifecycle:SyncTrackingSetting(skipRefresh) end
    function controller:Stop()
        if Raider.Modules.RaidLog then Raider.Modules.RaidLog.Close() end
        if page.lootMasterController then page.lootMasterController.Close() end
        page:Hide();lifecycle:Hide();lifecycle:CancelRosterUpdate()
    end
    function controller:ClearSelection() selectedName=nil end
    function controller:OpenSaveDialog(context, endSession) page.OpenSaveDialog(context, endSession) end
    function controller:OfferCurrentRaidRefresh() page.OfferCurrentRaidRefresh() end
    page.lootMasterController.resetOnLoad()
    return controller
end
