local Raider = BootyRaider
Raider.Modules.NativeRaidTab = {}
local NativeRaidTab = Raider.Modules.NativeRaidTab
local contentLeft, contentTop, contentRight, contentBottom = 20, 56, 44, 80
local headerLeft, headerTop = 72, 37
local portraitTexture = "Interface\\AddOns\\BootyLib\\Textures\\MinimapIcon"
local buttonArtwork = {
    normal="Interface\\Buttons\\UI-Panel-Button-Up", pushed="Interface\\Buttons\\UI-Panel-Button-Down",
    disabled="Interface\\Buttons\\UI-Panel-Button-Disabled", highlight="Interface\\Buttons\\UI-Panel-Button-Highlight",
    coords={0,0.625,0,0.6875},
}

-- Vanilla's 384x512 FriendsFrame includes transparent artwork padding: its
-- native hit area excludes right30/bottom45 and the tabs sit at bottom47.
-- Keep the Raider body inside that visible panel rather than filling the canvas.
function NativeRaidTab.GetContentRect(owner, toolbarHeight, showHeader)
    local width, height = Raider.UI.Components.GetFrameSpan(owner)
    -- Stock group bodies start at70, with their14px label above the body.
    -- Include that label in the viewport so it is not clipped by ScrollFrame.
    local top = math.max(showHeader == false and 70 or contentTop, headerTop + (toolbarHeight or 0) - 3)
    return math.max(1, width - contentLeft - contentRight), math.max(1, height - top - contentBottom), contentLeft, top, contentRight, contentBottom
end

-- RaidFrame.xml places the native action row beside the portrait, at 72,-37.
function NativeRaidTab.GetHeaderRect(owner)
    local width = Raider.UI.Components.GetFrameSpan(owner)
    return math.max(1, width - headerLeft - contentRight), headerLeft, headerTop, contentRight
end

-- The original 1.12 function hides every native subframe for an unmatched
-- name. Keep its tab/header selection, replacing only the Raid body.
function NativeRaidTab.Create(options)
    options = options or {}
    local UI = Raider.UI.Components
    local service = options.service or Raider.Services.RaidTab
    local controller = {}
    local panel, groupHost, groups, inviteDialog
    local previous, wrapper, selected, enabled, binding
    local members, groupSettings = {}, {}
    local rendering = false
    local portrait, portraitOwner, savedTexture, savedCoords, appliedCoords, portraitOwned

    local function RestorePortrait()
        if not portraitOwned then return end
        local owned = portrait and portrait:GetTexture() == portraitTexture
        if owned and appliedCoords then
            local current = { portrait:GetTexCoord() }
            for index = 1, table.getn(appliedCoords) do
                if current[index] ~= appliedCoords[index] then owned = false; break end
            end
        end
        if owned then
            portrait:SetTexture(savedTexture)
            if savedCoords then portrait:SetTexCoord(unpack(savedCoords)) end
        end
        savedTexture, savedCoords, appliedCoords, portraitOwned = nil, nil, nil, nil
    end
    local function ApplyPortrait()
        if BootyRaiderDB.useMOSRaidLogo == false then RestorePortrait(); return end
        if portraitOwned then return end
        if portraitOwner ~= FriendsFrame then portrait, portraitOwner = nil, FriendsFrame end
        if not portrait and FriendsFrame.GetRegions then
            -- The stock portrait is an unnamed 60x60 background texture. Find
            -- that existing region; never replace decorative frame artwork.
            local regions = { FriendsFrame:GetRegions() }
            for index = 1, table.getn(regions) do
                local region = regions[index]
                local texture = region.GetTexture and region:GetTexture()
                if type(texture) == "string" and string.lower(string.gsub(texture, "/", "\\")) == "interface\\friendsframe\\friendsframescrollicon" then
                    portrait = region; break
                end
            end
        end
        if not portrait then return end
        savedTexture = portrait:GetTexture()
        if portrait.GetTexCoord and portrait.SetTexCoord then
            savedCoords = { portrait:GetTexCoord() }
            portrait:SetTexCoord(0, 1, 0, 1)
            appliedCoords = { portrait:GetTexCoord() }
        end
        portrait:SetTexture(portraitTexture)
        portraitOwned = true
    end

    local function IsEnabled()
        return options.isEnabled and options.isEnabled() == true
    end
    local function NativeAvailable()
        return FriendsFrame and RaidFrame and type(FriendsFrame_ShowSubFrame) == "function"
    end
    local function SelectedRaid()
        return selected or (FriendsFrame and FriendsFrame.selectedTab == 4)
    end
    local function Hide()
        if groups then groups:Hide() end
        if panel then panel:Hide() end
        if inviteDialog then inviteDialog:Hide() end
        RestorePortrait()
    end
    local function LayoutToolbar(width, inRaid)
        -- Owner bounds are authoritative; native anchored button widths can
        -- still report their previous size. Budget all three actions first.
        local gap = math.min(4, math.max(0, (width - 3) / 2))
        local count = inRaid and 3 or 2
        local available = math.max(count, width - gap * (count - 1))
        local first = math.max(1, math.floor(available / count))
        panel.invite.mosFlowWidth, panel.ready.mosFlowWidth = first, first
        panel.info.mosFlowWidth = available - first * (count - 1)
        if inRaid then panel.ready:Show() else panel.ready:Hide() end
        panel.toolbar:SetHeight(UI.LayoutFlow(panel.toolbar, inRaid and panel.toolbarControls or panel.preRaidControls, 0, 0, width, gap))
    end
    local function Refresh()
        if rendering or not panel or not panel:IsVisible() then return end
        rendering = true
        local inRaid = service.IsInRaid()
        local convert = service.CanConvert()
        local settings = service.GetGroupSettings(groupSettings)
        Raider.Modules.RaidManagement.ApplyGroupViewBackground(panel, settings, true)
        Raider.Modules.RaidManagement.ApplyGroupViewBackground(panel.toolbar, settings, true)
        for index = 1, table.getn(panel.toolbarControls) do
            UI.SetButtonArtwork(panel.toolbarControls[index], BootyRaiderDB.nativeRaidButtonStyle ~= "mos" and buttonArtwork or nil)
        end
        panel.invite:SetText(inRaid and "Add Member" or "Convert to Raid")
        ApplyPortrait()
        local headerWidth, headerX, headerY, headerRight = NativeRaidTab.GetHeaderRect(FriendsFrame)
        panel.toolbar:ClearAllPoints()
        panel.toolbar:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", headerX, -headerY)
        panel.toolbar:SetPoint("TOPRIGHT", FriendsFrame, "TOPRIGHT", -headerRight, -headerY)
        panel.toolbar:SetWidth(headerWidth)
        LayoutToolbar(headerWidth, inRaid)
        local toolbarHeight = 22
        local width, height, left, top, right, bottom = NativeRaidTab.GetContentRect(FriendsFrame, toolbarHeight, not inRaid or settings.raidGroupShowHeader ~= false)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", left, -top)
        panel:SetPoint("BOTTOMRIGHT", FriendsFrame, "BOTTOMRIGHT", -right, bottom)
        panel:SetWidth(width); panel:SetHeight(height)
        groupHost:ClearAllPoints()
        groupHost:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        groupHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        local bodyHeight = height
        groupHost:SetWidth(width); groupHost:SetHeight(bodyHeight)
        UI.SetButtonEnabled(panel.invite, inRaid and service.CanInvite() or convert)
        UI.SetButtonEnabled(panel.ready, Raider.Services.Raid.CanReadyCheck())
        if inRaid then
            panel.description:Hide(); groupHost:Show()
            service.ReadMembers(members)
            groups:Render(members, width, bodyHeight)
        else
            groups:Hide(); groupHost:Hide()
            if inviteDialog then inviteDialog:Hide() end
            panel.description:SetWidth(math.max(1, math.min(300, width - 18))); panel.description:Show()
        end
        rendering = false
    end
    local function Invite()
        if not service.IsInRaid() then
            if service.CanConvert() then service.Convert(); Refresh() end
            return
        end
        if not service.CanInvite() then return end
        if inviteDialog and inviteDialog:IsVisible() then inviteDialog:Hide(); return end
        if not inviteDialog then
            inviteDialog = UI.Window.CreateProjectConfirmation("BootyRaiderRaidTabInvite", "Add Member", "Invite", "leader", {modal = false})
            inviteDialog.memberName = UI.CreateFramedEditBox(inviteDialog, "BootyRaiderRaidTabInviteName", 304)
            inviteDialog.memberName:SetPoint("TOPLEFT", inviteDialog, "TOPLEFT", 8, -62)
            inviteDialog.memberName:SetAutoFocus(false)
            inviteDialog.memberName:SetMaxLetters(24)
            inviteDialog.memberName:SetScript("OnEscapePressed", function() inviteDialog:Hide() end)
            inviteDialog.memberName:SetScript("OnEnterPressed", function() inviteDialog.yes:GetScript("OnClick")() end)
            local hidden = inviteDialog:GetScript("OnHide")
            inviteDialog:SetScript("OnHide", function() if hidden then hidden() end; inviteDialog.memberName:ClearFocus() end)
        end
        inviteDialog:Open("Character name", function() service.Invite(inviteDialog.memberName:GetText()) end)
        inviteDialog.label:SetHeight(18); inviteDialog:SetHeight(128)
        inviteDialog.memberName:SetText("")
        inviteDialog.memberName:SetFocus()
    end
    local function CreatePanel()
        if panel then return end
        panel = UI.CreateContainer("BootyRaiderNativeRaidTab", FriendsFrame)
        local _, _, left, top, right, bottom = NativeRaidTab.GetContentRect(FriendsFrame)
        panel:Hide(); panel:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", left, -top)
        panel:SetPoint("BOTTOMRIGHT", FriendsFrame, "BOTTOMRIGHT", -right, bottom)
        panel:SetFrameLevel(FriendsFrame:GetFrameLevel() + 3)
        local toolbar = UI.CreateToolbarSurface(panel, false, true)
        UI.SetSurfaceTransparent(toolbar, true)
        toolbar:SetHeight(22)
        panel.invite = UI.CreateButton(toolbar, nil, "Add Member", 90, 22)
        panel.ready = UI.CreateButton(toolbar, nil, "Ready Check", 90, 22)
        panel.info = UI.CreateButton(toolbar, nil, "Raid Info", 80, 22)
        UI.SetClassicButtonVariant(panel.invite, "red")
        UI.SetClassicButtonVariant(panel.ready, "red")
        UI.SetClassicButtonVariant(panel.info, "red")
        UI.SetButtonBorderless(panel.invite, true)
        UI.SetButtonBorderless(panel.ready, true)
        UI.SetButtonBorderless(panel.info, true)
        UI.SetClassicButtonGold(panel.invite, true)
        UI.SetClassicButtonGold(panel.ready, true)
        UI.SetClassicButtonGold(panel.info, true)
        panel.toolbar = toolbar; panel.toolbarControls = { panel.invite, panel.ready, panel.info }
        panel.preRaidControls = {panel.invite, panel.info}
        for index = 1, table.getn(panel.toolbarControls) do
            panel.toolbarControls[index].mosFlowLabelPadding = 6
            local label = panel.toolbarControls[index].label
            if label.SetWordWrap then label:SetWordWrap(false) end
        end
        panel.invite.mosFlowFitLabel = true; panel.ready.mosFlowFitLabel = true; panel.info.mosFlowFitLabel = true
        panel.invite:SetScript("OnClick", Invite)
        panel.ready:SetScript("OnClick", function() Raider.Services.Raid.ReadyCheck() end)
        panel.info:SetScript("OnClick", function() if options.openRaidInfo then options.openRaidInfo(FriendsFrame) end end)
        groupHost = UI.CreateContainer(nil, panel)
        groupHost:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        groupHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        panel.description = UI.CreateLabel(panel, nil, "OVERLAY", "GameFontNormal")
        panel.description:SetPoint("TOPLEFT", panel, "TOPLEFT", 9, -29)
        panel.description:SetJustifyH("LEFT"); panel.description:SetJustifyV("TOP")
        panel.description:SetHeight(0)
        if panel.description.SetWordWrap then panel.description:SetWordWrap(true) end
        panel.description:SetText(RAID_DESCRIPTION or "Raids are groups of more than 5 people and are typically used to defeat unique challenges at high levels.\n\n|cffffffff- Raid members cannot earn credit toward most non-raid quests.\n\n- Raids grant substantially less experience for defeating monsters than normal groups.\n\n- Raids allow you to overcome challenges that might otherwise be nearly impossible.|r")
        groups = Raider.Modules.RaidManagement.CreateCompactGroupView(groupHost, {
            ensureDatabase = options.ensureDatabase or Raider.Database.Ensure,
            getLootMasterInfo = Raider.Services.Raid.GetLootMasterInfo,
            getGroupSettings = function() return service.GetGroupSettings(groupSettings) end,
            canManageGroups = service.CanManage,
            moveMemberToSlot = service.MoveMemberToSlot,
            runMemberAction = service.RunMemberAction,
            isPlayerIgnored = Raider.Services.Raid.IsPlayerIgnored,
            onChanged = Refresh,
        })
        panel:SetScript("OnShow", function()
            ApplyPortrait()
            panel:RegisterEvent("RAID_ROSTER_UPDATE"); panel:RegisterEvent("PARTY_MEMBERS_CHANGED"); panel:RegisterEvent("PARTY_LEADER_CHANGED"); panel:RegisterEvent("PLAYER_ENTERING_WORLD")
            Refresh()
        end)
        panel:SetScript("OnHide", function()
            panel:UnregisterEvent("RAID_ROSTER_UPDATE"); panel:UnregisterEvent("PARTY_MEMBERS_CHANGED"); panel:UnregisterEvent("PARTY_LEADER_CHANGED"); panel:UnregisterEvent("PLAYER_ENTERING_WORLD")
            groups:Hide()
            if inviteDialog then inviteDialog:Hide() end
            if options.closeRaidInfo then options.closeRaidInfo(FriendsFrame) end
            RestorePortrait()
        end)
        panel:SetScript("OnEvent", Refresh)
        panel:SetScript("OnSizeChanged", Refresh)
    end
    local function Show()
        CreatePanel()
        if panel:IsVisible() then ApplyPortrait(); Refresh() else panel:Show() end
    end

    function controller:Sync()
        enabled = IsEnabled()
        if not enabled then
            local restoreRaid = SelectedRaid() and FriendsFrame and FriendsFrame:IsVisible()
            if binding then binding.active = false end
            Hide(); selected = false
            if wrapper and FriendsFrame_ShowSubFrame == wrapper then FriendsFrame_ShowSubFrame = previous end
            if restoreRaid and type(FriendsFrame_ShowSubFrame) == "function" then FriendsFrame_ShowSubFrame("RaidFrame") end
            wrapper, previous, binding = nil, nil, nil
            return true
        end
        if not NativeAvailable() then Hide(); return false end
        if not wrapper then
            previous = FriendsFrame_ShowSubFrame
            local original = previous
            binding = { active = true }
            local currentBinding = binding
            wrapper = function(frameName)
                if currentBinding.active and IsEnabled() and frameName == "RaidFrame" then
                    original("BootyRaiderRaidReplacement")
                    selected = true; Show()
                else
                    selected = false; Hide(); original(frameName)
                end
            end
            FriendsFrame_ShowSubFrame = wrapper
        end
        if FriendsFrame:IsVisible() and SelectedRaid() then FriendsFrame_ShowSubFrame("RaidFrame") end
        return true
    end
    function controller:IsVisible() return panel and panel:IsVisible() or false end
    return controller
end
