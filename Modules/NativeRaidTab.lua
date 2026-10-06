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
local function Failure(code, message, cleanup)
    return false, {code = code, message = tostring(message or code), cleanupError = cleanup}
end
local function Finite(value) return type(value) == "number" and value == value and value - value == 0 end
function NativeRaidTab.ValidateLayoutContext(context)
    if context == nil then return true, nil end
    if type(context) ~= "table" then return Failure("invalid-layout", "Expected numeric Raid layout rectangles.") end
    local copy = {}
    for key in pairs(context) do if key ~= "header" and key ~= "content" then return Failure("invalid-layout", "Unknown Raid layout rectangle.") end end
    for _, name in ipairs({"header", "content"}) do
        if context[name] ~= nil then
            if type(context[name]) ~= "table" then return Failure("invalid-layout", "Expected a numeric Raid layout rectangle.") end
            copy[name] = {}
            local allowed = {left = true, top = true, right = true, width = true, height = true, bottom = name == "content"}
            for key in pairs(context[name]) do if not allowed[key] then return Failure("invalid-layout", "Unknown Raid layout field.") end end
            for _, key in ipairs({"left", "top", "right", "bottom", "width", "height"}) do
                local value = context[name][key]
                if value ~= nil then
                    if not Finite(value) or value < 0 or (key == "width" or key == "height") and value == 0 then
                        return Failure("invalid-layout", "Invalid Raid layout field: " .. key)
                    end
                    copy[name][key] = value
                end
            end
        end
    end
    return true, copy
end

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
    local panel, panelReady, groupHost, groups, inviteDialog
    local previous, wrapper, selected, enabled, binding, lastError
    local members, groupSettings = {}, {}
    local rendering = false
    local portrait, portraitOwner, savedTexture, savedCoords, appliedCoords, portraitOwned
    local function NotifyStatus()
        if not options.onStatusChanged then return true end
        local ok, result, message = pcall(options.onStatusChanged)
        if not ok or result == false then return Failure("notification-failed", ok and type(message) == "table" and message.message or message or result) end
        return true
    end

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
    local function Cleanup()
        local failure
        local function Run(callback)
            local ok, message = pcall(callback)
            if not ok and not failure then failure = tostring(message) end
        end
        if panel then
            for _, name in ipairs({"RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD"}) do
                Run(function() panel:UnregisterEvent(name) end)
            end
        end
        if groups then Run(function() groups:Hide() end) end
        if inviteDialog then Run(function() inviteDialog:Hide() end) end
        if options.closeRaidInfo then Run(function() options.closeRaidInfo(FriendsFrame) end) end
        Run(RestorePortrait)
        if failure then return Failure("cleanup-failed", failure) end
        return true
    end
    local function Hide()
        local ok, failure = true, nil
        if panel then
            local hidden, message = pcall(function() panel:Hide() end)
            if not hidden then ok, failure = Failure("cleanup-failed", message) end
        end
        local cleaned, detail = Cleanup()
        if not cleaned then return cleaned, detail end
        return ok, failure
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
    local function Render()
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
        local layout = options.getLayoutContext and options.getLayoutContext()
        local header = layout and layout.header
        if header then headerWidth, headerX, headerY, headerRight = header.width or headerWidth, header.left or headerX, header.top or headerY, header.right or headerRight end
        panel.toolbar:ClearAllPoints()
        panel.toolbar:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", headerX, -headerY)
        panel.toolbar:SetPoint("TOPRIGHT", FriendsFrame, "TOPRIGHT", -headerRight, -headerY)
        panel.toolbar:SetWidth(headerWidth)
        LayoutToolbar(headerWidth, inRaid)
        local toolbarHeight = header and header.height or 22
        if header and header.height then panel.toolbar:SetHeight(toolbarHeight) end
        local width, height, left, top, right, bottom = NativeRaidTab.GetContentRect(FriendsFrame, toolbarHeight, not inRaid or settings.raidGroupShowHeader ~= false)
        local content = layout and layout.content
        if content then
            width, height = content.width or width, content.height or height
            left, top, right, bottom = content.left or left, content.top or top, content.right or right, content.bottom or bottom
        end
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
        if options.onLayoutChanged then
            local ok, reason = options.onLayoutChanged({header = {left = headerX, top = headerY, right = headerRight,
                width = headerWidth, height = toolbarHeight}, content = {left = left, top = top, right = right, bottom = bottom, width = width, height = height}})
            if ok == false then error(type(reason) == "table" and reason.message or reason) end
        end
    end
    local function Refresh()
        if rendering or not panel or not panel:IsVisible() then return true end
        rendering = true
        local ok, message = pcall(Render)
        rendering = false
        if not ok then lastError = {code = "render-failed", message = tostring(message)}; return false, lastError end
        return true
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
            if UI.WindowStack then UI.WindowStack.SetOwner(inviteDialog, FriendsFrame) end
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
        if panel then
            if not panelReady then error("Raid content construction failed; reload before retrying it.") end
            return
        end
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
            local ok, reason = Refresh()
            if not ok then error(reason.message) end
        end)
        panel:SetScript("OnHide", function()
            local ok, reason = Cleanup()
            if not ok then error(reason.message) end
        end)
        local function RefreshObserved()
            local ok, reason = Refresh()
            if not ok then
                if binding then binding.active = false end
                local hidden, cleanup = Hide()
                if not hidden then reason.cleanupError = cleanup end
                local notified, notification = NotifyStatus()
                if not notified then reason.notificationError = notification end
                if options.onError then options.onError(reason) end
            end
            return ok, reason
        end
        panel:SetScript("OnEvent", RefreshObserved)
        panel:SetScript("OnSizeChanged", RefreshObserved)
        panelReady = true
    end
    local function Show()
        if not FriendsFrame:IsVisible() then return true end
        CreatePanel()
        if panel:IsVisible() then ApplyPortrait(); return Refresh() else panel:Show() end
        return true
    end

    function controller:Sync()
        enabled = IsEnabled()
        if not enabled then
            local restoreRaid = SelectedRaid() and FriendsFrame and FriendsFrame:IsVisible()
            if binding then binding.active = false end
            local hidden, failure = Hide(); selected = false
            if wrapper and FriendsFrame_ShowSubFrame == wrapper then FriendsFrame_ShowSubFrame = previous end
            if wrapper and FriendsFrame_ShowSubFrame ~= previous then
                lastError = {code = "wrapper-conflict", message = "Another addon changed the Raid tab wrapper; the Raider binding is inactive but cannot be safely removed."}
                return false, lastError
            end
            if not hidden then lastError = failure; return false, failure end
            wrapper, previous, binding = nil, nil, nil
            if restoreRaid and type(FriendsFrame_ShowSubFrame) == "function" then
                local ok, message = pcall(FriendsFrame_ShowSubFrame, "RaidFrame")
                if not ok then lastError = {code = "native-restore-failed", message = tostring(message)}; return false, lastError end
            end
            lastError = nil
            return true
        end
        if not NativeAvailable() then Hide(); return Failure("unavailable", "The native Raid tab is unavailable.") end
        if wrapper and FriendsFrame_ShowSubFrame == previous and binding and not binding.active then
            local cleaned, failure = Hide()
            if not cleaned then lastError = failure; return false, failure end
            -- Our failed attachment already removed this wrapper from the
            -- global slot. Retry from the original function, without chaining it.
            wrapper, previous, binding = nil, nil, nil
        end
        if wrapper and FriendsFrame_ShowSubFrame ~= wrapper then
            if binding then binding.active = false end
            Hide()
            lastError = {code = "wrapper-conflict", message = "Another addon changed the Raid tab wrapper; reload before reactivating Raider content."}
            return false, lastError
        end
        if not wrapper then
            previous = FriendsFrame_ShowSubFrame
            local original = previous
            binding = { active = true }
            local currentBinding = binding
            wrapper = function(frameName)
                if currentBinding.active and IsEnabled() and frameName == "RaidFrame" and FriendsFrame:IsVisible() then
                    local ok, shown, reason = pcall(function()
                        original("BootyRaiderRaidReplacement")
                        selected = true
                        return Show()
                    end)
                    if not ok or shown == false then
                        currentBinding.active = false
                        local cleaned, cleanup = Hide()
                        if FriendsFrame_ShowSubFrame == wrapper then FriendsFrame_ShowSubFrame = original end
                        local restored, message = pcall(original, "RaidFrame")
                        lastError = {code = "attach-failed", message = tostring(ok and type(reason) == "table" and reason.message or reason or shown),
                            cleanupError = not cleaned and cleanup or not restored and tostring(message) or nil}
                        local notified, notification = NotifyStatus()
                        if not notified then lastError.notificationError = notification end
                        return false, lastError
                    end
                else
                    selected = frameName == "RaidFrame"
                    local ok, reason = Hide()
                    original(frameName)
                    if not ok then lastError = reason; return false, reason end
                end
                local notified, notification = NotifyStatus()
                if not notified then lastError = notification; return false, notification end
                return true
            end
            FriendsFrame_ShowSubFrame = wrapper
        end
        if binding then binding.active = true end
        if FriendsFrame:IsVisible() and SelectedRaid() then
            local ok, result, detail = pcall(FriendsFrame_ShowSubFrame, "RaidFrame")
            if not ok then return Failure("attach-failed", result) end
            if result == false then return false, detail end
        end
        lastError = nil
        return true
    end
    function controller:IsVisible() return panel and panel:IsVisible() or false end
    function controller:GetStatus()
        return {available = NativeAvailable() and true or false, bound = binding and binding.active == true or false,
            owned = wrapper ~= nil and FriendsFrame_ShowSubFrame == wrapper, conflict = wrapper ~= nil and FriendsFrame_ShowSubFrame ~= wrapper and FriendsFrame_ShowSubFrame ~= previous,
            nativeReady = wrapper == nil and lastError == nil and NativeAvailable() and true or false,
            visible = self:IsVisible(), error = lastError}
    end
    return controller
end
