local Raider = BootyRaider
local UI = Raider.UI.Components
local Raid = Raider.Modules.RaidManagement
local Runtime = Raider.Runtime
local Screen = {}
Raider.Modules.RaidScreen = Screen

function Screen.Create(parent, host)
    Runtime.Initialize(host)
    local page = UI.CreateContainer(nil,parent)
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
    Refresh=function()
        if not page:IsVisible() and not (page.lootMasterController and page.lootMasterController.IsVisible()) then return end
        if page:IsVisible() then Raid.RefreshPage(renderer) end
        if page.lootMasterController then page.lootMasterController.Refresh() end
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
        setHistoricalLoaded=function(value) Runtime.historicalLoaded=value and true or false end,getRules=Rules,
        saveRules=function(rules)
            if Runtime.IsTestRaid() then Raider.Services.TestRaid.SaveLootRules(rules) else Raider.Database.SaveLootRules(rules) end
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
        startNewRaid=function(id,name) return Runtime.sessionController:StartNew(id,name) end,
        saveRaidSession=Runtime.SaveSession,quitRaidSession=function() Runtime.sessionController:Quit() end,
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
    function controller:OnResize() SizePage();Refresh() end
    function controller:OnRosterUpdate() lifecycle:OnRosterUpdate() end
    function controller:SyncTrackingSetting(skipRefresh) lifecycle:SyncTrackingSetting(skipRefresh) end
    function controller:Stop()
        if page.lootMasterController then page.lootMasterController.Close() end
        page:Hide();lifecycle:Hide();lifecycle:CancelRosterUpdate()
    end
    function controller:ClearSelection() selectedName=nil end
    function controller:OpenSaveDialog(context) page.OpenSaveDialog(context) end
    function controller:OfferCurrentRaidRefresh() page.OfferCurrentRaidRefresh() end
    page.lootMasterController.resetOnLoad()
    return controller
end
