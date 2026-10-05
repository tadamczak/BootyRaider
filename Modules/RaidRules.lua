local Raider = BootyRaider

Raider.Modules.RaidManagement = Raider.Modules.RaidManagement or {}
local RaidManagement = Raider.Modules.RaidManagement

function RaidManagement.CreateLootRulesDialog(options)
    local frame = Raider.UI.Components.CreateContainer("BootyRaiderLootRulesDialog", UIParent)
    frame:SetWidth(690); frame:SetHeight(560); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetFrameLevel(230); frame:EnableMouse(true); frame:Hide()
    frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end); frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    local UI = Raider.UI.Components
    UI.Window.ApplyProjectSurface(frame)
    UI.RegisterSkinCallback(function() UI.Window.ApplyProjectSurface(frame) end)
    frame.title = UI.CreateHeading(frame, "Set Loot Rules", 3, "gold", "rules")
    local titleFont, _, titleFlags = frame.title:GetFont(); frame.title:SetFont(titleFont, 13, titleFlags)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    frame.close = UI.CreateWindowButton(frame, nil, "close"); frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    frame.minimize = UI.CreateWindowButton(frame, nil, "minimize"); frame.minimize:SetPoint("RIGHT", frame.close, "LEFT", -4, 0)
    local function LayoutHeader(minimized)
        frame.title:ClearAllPoints(); frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, minimized and -4 or -8)
        frame.title:SetHeight(minimized and 22 or 18)
        frame.close:ClearAllPoints(); frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, minimized and -4 or -6)
    end
    local content = UI.CreateContainer(nil, frame); content:SetAllPoints(frame); frame.content = content
    frame.divider = UI.CreateContainer(nil, content)
    frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -24); frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -24); frame.divider:SetHeight(4)
    UI.RegisterSkinnedSurface(frame.divider, "content", nil, {0,0,0,0}, {0.68,0.54,0.27,1})
    UI.JoinSurfaceEdges(frame.divider, true, false)
    frame.minimize:SetScript("OnClick", function()
        frame.minimized = not frame.minimized
        LayoutHeader(frame.minimized)
        if frame.minimized then content:Hide(); frame:SetHeight(UI.Window.MinimizedHeight); UI.SetWindowButtonAction(frame.minimize, "maximize")
        else frame:SetHeight(560); content:Show(); UI.SetWindowButtonAction(frame.minimize, "minimize") end
    end)
    local headers = { { "Guild rank", 8, 190 }, { "SR", 224, 66 }, { "Reycoin", 310, 92 }, { "CSR", 422, 66 }, { "Highly Contested Items", 508, 158 } }
    local index
    for index = 1, table.getn(headers) do
        local header = Raider.UI.Components.CreateColumnLabel(content, "", "orange"); header:SetPoint("TOPLEFT", frame, "TOPLEFT", headers[index][2], -40); header:SetWidth(headers[index][3]); header:SetJustifyH(index == 1 and "LEFT" or "CENTER"); header:SetText(headers[index][1])
    end
    frame.rows = {}; frame.working = {}
    local keys = { "sr", "reyCoin", "csr", "highlyContested" }
    local checkX = { 257, 356, 455, 587 }
    for index = 1, 10 do
        local row = Raider.UI.Components.CreateContainer(nil, content); row:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -60 - ((index - 1) * 27)); row:SetWidth(674); row:SetHeight(24)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); local shade = math.mod(index, 2) == 0 and 0.13 or 0.085; row:SetBackdropColor(shade, shade, shade, 1)
        row.rank = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall"); row.rank:SetPoint("LEFT", row, "LEFT", 5, 0); row.rank:SetWidth(190); row.rank:SetJustifyH("LEFT")
        row.checks = {}
        local keyIndex
        for keyIndex = 1, 4 do
            local check = Raider.UI.Components.CreateCheckButton(nil, row, "UICheckButtonTemplate"); check:SetWidth(22); check:SetHeight(22); check:SetPoint("CENTER", frame, "TOPLEFT", checkX[keyIndex], -72 - ((index - 1) * 27)); check.ruleKey = keys[keyIndex]; check.ownerRow = row
            check:SetScript("OnClick", function() if this.ownerRow.rankIndex then frame.working[this.ownerRow.rankIndex][this.ruleKey] = this:GetChecked() and true or false end end)
            row.checks[keyIndex] = check
        end
        frame.rows[index] = row
    end
    frame.empty = Raider.UI.Components.CreateLabel(content, nil, "OVERLAY", "GameFontDisable"); frame.empty:SetPoint("CENTER", frame, "CENTER", 0, 0); frame.empty:SetText("Refresh the guild roster before setting loot rules."); frame.empty:Hide()
    frame.rulesTitle = Raider.UI.Components.CreateColumnLabel(content, "", "orange"); frame.rulesTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -236); frame.rulesTitle:SetText("Loot rights reference")
    frame.rulesPanel = Raider.UI.Components.CreateContainer(nil, content); frame.rulesPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -254); frame.rulesPanel:SetWidth(682); frame.rulesPanel:SetHeight(268)
    UI.RegisterSkinnedSurface(frame.rulesPanel, "content", nil, {0,0,0,0}, {0.68,0.54,0.27,1})
    UI.SetSurfaceHorizontalBorders(frame.rulesPanel, true, true)
    frame.rulesScroll = Raider.UI.Components.CreateScrollFrame("BootyRaiderLootRulesReferenceScroll", frame.rulesPanel, "UIPanelScrollFrameTemplate")
    Raider.UI.Components.RegisterSkinnedScrollBar(getglobal("BootyRaiderLootRulesReferenceScrollScrollBar"))
    frame.rulesScroll:SetPoint("TOPLEFT", frame.rulesPanel, "TOPLEFT", 4, -8); frame.rulesScroll:SetPoint("BOTTOMRIGHT", frame.rulesPanel, "BOTTOMRIGHT", -28, 7)
    frame.rulesCanvas = Raider.UI.Components.CreateContainer(nil, frame.rulesScroll); frame.rulesCanvas:SetWidth(604); frame.rulesCanvas:SetHeight(280); frame.rulesScroll:SetScrollChild(frame.rulesCanvas)
    frame.rulesText = Raider.UI.Components.CreateLabel(frame.rulesCanvas, nil, "OVERLAY", "GameFontHighlightSmall"); frame.rulesText:SetPoint("TOPLEFT", frame.rulesCanvas, "TOPLEFT", 0, 0); frame.rulesText:SetWidth(596); frame.rulesText:SetJustifyH("LEFT"); frame.rulesText:SetJustifyV("TOP")
    frame.rulesText:SetText("MACAQUE\nLoot rights: none. Lower raid priority than other ranks and may not be selected for the raid.\n\nGUEST\nStarts with Macaque rights and may earn Baboon or Chimp rights under the same requirements as guild members. Silverback rights are unavailable.\n\nALT\nAn alt requested by the raid leader receives the main character's loot rights. A voluntary alt has no loot rights and receives loot after mains. Rights may change with progression and guild needs.\n\nBABOON\nLoot rights: SR excluding Highly Contested Items, plus Reycoin.\n\nCHIMP\nLoot rights: SR plus Reycoin.\n\nSILVERBACK\nLoot rights: CSR, SR and Reycoin. Gains +10 CSR after each unsuccessful SR.")
    frame.rulesCanvas:SetHeight(math.max(280, UI.MeasureTextHeight(frame.rulesText, 596) + 8))
    frame.contestedItems = Raider.UI.Components.CreateButton(content, nil, "Set Highly Contested Items", 154, 22)
    frame.contestedItems:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
    frame.contestedItems:SetScript("OnClick", function() options.openHighlyContestedItems() end)
    frame.save = Raider.UI.Components.CreateButton(content, nil, "Save", 78, 22); frame.save:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -94, 8)
    frame.cancel = Raider.UI.Components.CreateButton(content, nil, "Cancel", 78, 22); frame.cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    local function Close() frame:Hide() end
    frame.Close = Close
    frame.close:SetScript("OnClick", Close); frame.cancel:SetScript("OnClick", Close)
    frame.save:SetScript("OnClick", function()
        options.saveRules(frame.working); frame:Hide()
        options.refresh()
        options.printMessage(options.isTestRaid and options.isTestRaid() and "Loot rules saved for this Test Raid session." or "Loot rules saved.")
    end)
    local function MeasureReference(width)
        frame.rulesText:SetWidth(width)
        return UI.MeasureTextHeight(frame.rulesText, width)
    end
    frame.LayoutReference = function()
        local width, height, overflow = UI.ResolveScrollLayout(frame:GetWidth()-16, frame.rulesPanel:GetHeight()-16, 20, MeasureReference)
        frame.rulesScroll:ClearAllPoints()
        frame.rulesScroll:SetPoint("TOPLEFT", frame.rulesPanel, "TOPLEFT", 4, -8)
        frame.rulesScroll:SetPoint("BOTTOMRIGHT", frame.rulesPanel, "BOTTOMRIGHT", overflow and -24 or -4, 8)
        frame.rulesCanvas:SetWidth(width); frame.rulesCanvas:SetHeight(math.max(1,height))
        local slider=getglobal("BootyRaiderLootRulesReferenceScrollScrollBar")
        if slider then if overflow then slider:Show() else slider:Hide() end end
    end
    frame.Open = function(self)
        self.LayoutReference()
        self.minimized = false; self:SetHeight(560); content:Show(); UI.SetWindowButtonAction(self.minimize, "minimize")
        LayoutHeader(false)
        local ranks = {
            { index = "silverback", name = "Silverback" }, { index = "chimp", name = "Chimp" }, { index = "baboon", name = "Baboon" },
            { index = "alt", name = "Alt" }, { index = "guest", name = "Guest" }, { index = "macaque", name = "Macaque" },
        }
        local saved = options.getRules(); self.working = {}
        for index = 1, table.getn(self.rows) do
            local row, rank = self.rows[index], ranks[index]
            if rank then
                row.rankIndex = rank.index; row.rank:SetText(rank.name); self.working[rank.index] = {}
                local savedRule = saved[rank.index] or saved[tostring(rank.index)]
                if not savedRule then
                    if rank.index == "baboon" then savedRule = { sr = true, reyCoin = true }
                    elseif rank.index == "chimp" then savedRule = { sr = true, reyCoin = true, highlyContested = true }
                    elseif rank.index == "silverback" then savedRule = { sr = true, reyCoin = true, csr = true, highlyContested = true }
                    else savedRule = {} end
                end
                local keyIndex
                for keyIndex = 1, 4 do local key = keys[keyIndex]; self.working[rank.index][key] = savedRule[key] and true or false; row.checks[keyIndex]:SetChecked(self.working[rank.index][key] and 1 or nil) end
                row:Show()
            else row.rankIndex = nil; row:Hide() end
        end
        self:Show()
    end
    return frame
end

function RaidManagement.CreateHighlyContestedItemsDialog(options)
    local dialog
    dialog = Raider.UI.Components.CreateTextEditor("BootyRaiderHighlyContestedItemsDialog", "Set Highly Contested Items", 8000, function(value)
        local items = {}
        for line in string.gfind((value or "") .. "\n", "([^\r\n]*)[\r\n]") do table.insert(items, line) end
        local count = options.saveHighlyContestedItems(items)
        options.refresh()
        options.printMessage("Highly Contested Items saved: " .. count .. ".")
        return true
    end)
    dialog:SetWidth(560); dialog:SetHeight(400); dialog.save:SetText("Save"); dialog.cancel:SetText("Close")
    dialog:BringToFront(500)
    dialog.description = Raider.UI.Components.CreateLabel(dialog, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.description:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -39); dialog.description:SetWidth(528); dialog.description:SetJustifyH("LEFT")
    dialog.description:SetText("Enter one exact item name per line. Empty and duplicate lines are removed when saved.")
    dialog.scroll:ClearAllPoints(); dialog.scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -68); dialog.scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -32, 52)
    dialog.OpenItems = function(self)
        self:Open(table.concat(options.getHighlyContestedItems(), "\n"))
        self.scroll:Show(); self.edit:Show(); self:BringToFront(500); self.edit:SetFocus()
    end
    return dialog
end
