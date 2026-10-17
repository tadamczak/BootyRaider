local Raider = BootyRaider
local UI = Raider.UI.Components
local RaidEdit = {}
Raider.Modules = Raider.Modules or {}
Raider.Modules.RaidEdit = RaidEdit

function RaidEdit.AttachRaidSelector(dialog, labelY, buttonY)
    dialog.raidLabel = UI.CreateLabel(dialog, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.raidLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, labelY); dialog.raidLabel:SetText("Raid Type")
    dialog.raidSelect = UI.CreateDropdownButton(dialog, nil, "Choose raid", 220)
    dialog.raidSelect:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, buttonY)
    local names = Raider.Services.RaidStatistics.GetRaidNames()
    dialog.raidPanel = UI.CreateDropdownPanel(dialog, dialog.raidSelect, 220, table.getn(names) * 22 + 16, 10)
    dialog.raidOptions = {}
    for index = 1, table.getn(names) do
        local button = UI.CreateButton(dialog.raidPanel, nil, names[index], 204, 20)
        button:SetPoint("TOPLEFT", dialog.raidPanel, "TOPLEFT", 8, -8 - (index - 1) * 22)
        button.raidName = names[index]
        button:SetScript("OnClick", function()
            dialog.selectedRaidName = this.raidName; dialog.raidSelect.label:SetText(this.raidName); dialog.raidPanel:Hide()
        end)
        dialog.raidOptions[index] = button
    end
    dialog.raidSelect:SetScript("OnClick", function()
        if dialog.raidPanel:IsShown() then dialog.raidPanel:Hide() else dialog.raidPanel:Show() end
    end)
    dialog.SetRaidType = function(self, value)
        self.selectedRaidName = value; self.raidSelect.label:SetText(value or "Choose raid"); self.raidPanel:Hide()
    end
end

function RaidEdit.Create(name, owner, saveMetadata, onSaved, showSavedPopup)
    local dialog
    dialog = UI.CreateTextPrompt(name, "Edit Raid", "Raid ID", "Save", function(value)
        if not saveMetadata then return false, "Editing saved raids is unavailable." end
        local success, result = saveMetadata(dialog.raidId, {id=value,raidName=dialog.selectedRaidName})
        if not success then return false, result end
        if onSaved then onSaved(dialog.raidId, result) end
        if showSavedPopup then showSavedPopup() end
        return true
    end, 80)
    dialog:SetWidth(420); dialog:SetHeight(238)
    dialog.edit:SetWidth(384)
    RaidEdit.AttachRaidSelector(dialog, -95, -113)
    dialog.message:ClearAllPoints(); dialog.message:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -153)
    dialog.message:SetWidth(384); dialog.message:SetHeight(38); dialog.message:SetJustifyH("LEFT")
    local open = dialog.Open
    dialog.Open = function(self, snapshot)
        if not snapshot then return false end
        self.raidId = snapshot.id
        open(self); self.edit:SetText(tostring(snapshot.id or ""))
        self:SetRaidType(snapshot.raidName); return true
    end
    UI.Window.StyleProjectDialog(dialog)
    if UI.WindowStack then UI.WindowStack.SetOwner(dialog, owner) end
    return dialog
end
