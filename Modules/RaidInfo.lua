local Raider = BootyRaider
Raider.Modules.RaidInfo = Raider.Modules.RaidInfo or {}
local RaidInfo, serial = Raider.Modules.RaidInfo, 0

function RaidInfo.Create(parent, service)
    local UI = Raider.UI.Components
    service = service or Raider.Services.RaidInfo
    local frame = UI.CreateContainer(nil, parent or UIParent)
    local dialogWidth, idWidth, resetWidth = 360, 70, 80
    local innerWidth, rightColumns = dialogWidth - 20, idWidth + resetWidth
    frame:SetWidth(dialogWidth); frame:SetHeight(130); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame.title = UI.CreateHeading(frame, "", 3, "gold", "info"); frame.title:SetText("Raid Info")
    frame.close = UI.CreateWindowButton(frame, nil, "close")
    UI.Window.StyleProjectDialog(frame)
    frame:Hide()
    serial = serial + 1
    local scrollName = "BootyRaiderRaidInfoScroll" .. serial
    local scroll = UI.CreateScrollFrame(scrollName, frame, "UIPanelScrollFrameTemplate")
    local canvas = UI.CreateContainer(nil, scroll); scroll:SetScrollChild(canvas)
    local bar = getglobal(scrollName .. "ScrollBar"); UI.RegisterSkinnedScrollBar(bar)
    local headings, rows, entries = {}, {}, {}
    frame.headerLabels = headings
    local names = {"Instance", "Raid ID", "Resets in"}
    local index
    for index = 1, 3 do
        headings[index] = UI.CreateLabel(frame, nil, "OVERLAY", "GameFontNormalSmall")
        headings[index]:SetText(names[index]); headings[index]:SetJustifyH("LEFT")
    end
    local empty = UI.CreateLabel(frame, nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -58); empty:SetWidth(innerWidth); empty:SetJustifyH("LEFT")
    local active, controller = false, {frame = frame}
    if UI.WindowStack then
        UI.WindowStack.Register(frame, {owner = function()
            local host = Raider.Runtime and Raider.Runtime.host
            return controller.owner or host and (host.windows and host.windows.raid or host.window)
        end})
    end
    local function Measure(width)
        local nameWidth = math.max(1, width - rightColumns)
        local y, index = 0, 1
        for index = 1, table.getn(entries) do
            local row = rows[index]
            if not row then
                row = UI.CreateContainer(nil, canvas); rows[index] = row
                row.cells = {}
                for cell = 1, 3 do row.cells[cell] = UI.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall"); row.cells[cell]:SetJustifyH("LEFT") end
                UI.StyleWarmListRow(row, false)
            end
            local values = {entries[index].name, tostring(entries[index].id or "-"), service.FormatReset(entries[index].resetSeconds)}
            local widths, left, height = {nameWidth, idWidth, resetWidth}, 4, 26
            for cell = 1, 3 do
                local label = row.cells[cell]
                label:ClearAllPoints(); label:SetPoint("TOPLEFT", row, "TOPLEFT", left, -6)
                label:SetWidth(math.max(1, widths[cell] - 8)); label:SetHeight(0); label:SetText(values[cell])
                if label.SetWordWrap then label:SetWordWrap(true) end
                height = math.max(height, UI.MeasureTextHeight(label, math.max(1, widths[cell] - 8), true) + 12)
                left = left + widths[cell]
            end
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y); row:SetWidth(width); row:SetHeight(height); row:Show()
            y = y + height + 2
        end
        for index = table.getn(entries) + 1, table.getn(rows) do rows[index]:Hide() end
        return math.max(1, y - 2)
    end
    local function Render()
        local available
        entries, available = service.Read(entries)
        local height = math.min(360, math.max(118, 70 + table.getn(entries) * 28))
        frame:SetHeight(height)
        local width, contentHeight, overflow, maximum = UI.ResolveScrollLayout(innerWidth, height - 68, 20, Measure)
        local positions = {10, 10 + width - rightColumns, 10 + width - resetWidth}
        for index = 1, 3 do
            headings[index]:ClearAllPoints()
            if frame.projectDivider then headings[index]:SetPoint("TOPLEFT", frame.projectDivider, "BOTTOMLEFT", positions[index] - 4, -10)
            else headings[index]:SetPoint("TOPLEFT", frame, "TOPLEFT", positions[index], -38) end
            headings[index]:SetWidth(index == 1 and width - rightColumns or (index == 2 and idWidth or resetWidth)); headings[index]:Show()
        end
        scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -58); scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10 - (overflow and 20 or 0), 10)
        canvas:SetWidth(width); canvas:SetHeight(contentHeight)
        if bar then
            bar:ClearAllPoints(); bar:SetWidth(16); bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -74); bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 26)
        end
        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        UI.ApplyScrollRange(scroll, bar, maximum); scroll.bootyRaidInfoMaximum = maximum
        if table.getn(entries) > 0 then empty:Hide(); scroll:Show()
        else empty:SetText(available and "You have no saved instances." or "Saved instance information is unavailable."); empty:Show(); scroll:Hide() end
    end
    local function Activate()
        if active then return end
        active = true; frame:RegisterEvent("UPDATE_INSTANCE_INFO")
        service.Request(); Render()
    end
    local function Deactivate() active = false; frame:UnregisterEvent("UPDATE_INSTANCE_INFO") end
    frame:SetScript("OnShow", Activate); frame:SetScript("OnHide", function() controller.owner = nil; Deactivate() end)
    frame:SetScript("OnEvent", function() if active and event == "UPDATE_INSTANCE_INFO" then Render() end end)
    frame.close:SetScript("OnClick", function() controller:Close() end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function()
        if not active then return end
        local maximum = scroll.bootyRaidInfoMaximum or 0
        local offset = math.max(0, math.min(maximum, scroll:GetVerticalScroll() - (tonumber(arg1) or 0) * 28))
        scroll:SetVerticalScroll(offset); if bar then bar:SetValue(offset) end
    end)
    function controller:Open(owner)
        self.owner = owner
        frame:ClearAllPoints()
        if owner and owner == FriendsFrame then
            -- FriendsFrame's artwork ends 33px before its canvas right edge
            -- and starts 28px below its top. Anchor to those visible edges.
            frame:SetPoint("TOPLEFT", owner, "TOPRIGHT", -33, -28)
        else frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
        if active then service.Request(); Render(); if UI.WindowStack then UI.WindowStack.Raise(frame, owner) end
        else frame:Show(); Activate() end
    end
    function controller:Close() frame:Hide(); Deactivate() end
    function controller:Toggle(owner)
        if self:IsVisible() and self.owner == owner then self:Close() else self:Open(owner) end
    end
    function controller:CloseOwned(owner)
        if owner and self.owner == owner then self:Close() end
    end
    function controller:IsVisible() return frame:IsVisible() end
    return controller
end

local dialog
function RaidInfo.Open()
    if not dialog then dialog = RaidInfo.Create(UIParent) end
    dialog:Open()
    return dialog
end

function RaidInfo.Toggle(owner)
    if not dialog then dialog = RaidInfo.Create(UIParent) end
    dialog:Toggle(owner)
    return dialog
end

function RaidInfo.CloseOwned(owner)
    if dialog then dialog:CloseOwned(owner) end
end
