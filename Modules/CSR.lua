local Raider = BootyRaider
local UI = Raider.UI.Components

Raider.Modules = Raider.Modules or {}
local CSR = {}
Raider.Modules.CSR = CSR

local function CreateTestLab(onChanged, onExit)
    local dialog = UI.CreateContainer("BootyRaiderCSRTestLab", UIParent)
    dialog:SetWidth(500); dialog:SetHeight(420); dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG"); dialog:SetFrameLevel(230)
    dialog:SetResizable(true); dialog:SetMinResize(280, 240); dialog:SetMaxResize(850, 700)
    if dialog.SetClampedToScreen then dialog:SetClampedToScreen(true) end
    dialog.title = UI.CreateHeading(dialog, "CSR Test Lab", 1, "gold", "csr")
    dialog.close = UI.CreateWindowButton(dialog, nil, "close")
    UI.Window.StyleProjectDialog(dialog)
    dialog.host = UI.CreateContainer(nil, dialog)
    dialog.body = UI.CreateResponsiveCanvas(dialog.host, "BootyRaiderCSRTestLabBody")
    local body = dialog.body
    dialog.help = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.help:SetText("Temporary simulation: add players and reserves, award items, change rank or advance time. Saved raids are unchanged.")
    dialog.state = Raider.Services.CSRTest.Create(); dialog.summary = { players = {} }
    dialog.status = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.item = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.result = UI.CreateLabel(body, nil, "OVERLAY", "GameFontNormal")
    dialog.logTitle = UI.CreateLabel(body, nil, "OVERLAY", "GameFontNormal")
    dialog.logTitle:SetText("Simulation log")
    dialog.logLines = {}
    for index = 1, 5 do dialog.logLines[index] = UI.CreateLabel(body, nil, "OVERLAY", "GameFontHighlightSmall") end
    local function Action(text, width, callback)
        local button = UI.CreateButton(body, nil, text, width, 26)
        UI.StyleActionButton(button); button.mosFlowWidth = width
        button:SetScript("OnClick", function() callback(dialog.state); dialog:Refresh() end)
        return button
    end
    dialog.actions = {
        Action("Add player", 90, Raider.Services.CSRTest.AddPlayer),
        Action("Add unsuccessful SR", 142, Raider.Services.CSRTest.AddMissedReserve),
        Action("Award item", 94, Raider.Services.CSRTest.AwardItem),
        Action("Next item", 84, Raider.Services.CSRTest.NextItem),
        Action("Toggle rank", 94, Raider.Services.CSRTest.ToggleRank),
        Action("+7 days", 76, function(state) Raider.Services.CSRTest.AdvanceDays(state, 7) end),
    }
    dialog.reset = UI.CreateButton(dialog, nil, "Reset Test", 90, 26)
    dialog.exit = UI.CreateButton(dialog, nil, "Exit Test", 80, 26)
    UI.StyleActionButton(dialog.reset); UI.StyleActionButton(dialog.exit)
    dialog.exit:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 8)
    dialog.reset:SetPoint("RIGHT", dialog.exit, "LEFT", -8, 0)
    local function Exit() dialog:Hide(); if onExit then onExit() end end
    dialog.close:SetScript("OnClick", Exit); dialog.exit:SetScript("OnClick", Exit)
    dialog.reset:SetScript("OnClick", function() Raider.Services.CSRTest.Reset(dialog.state); dialog:Refresh() end)
    dialog.grip = UI.CreateControl(nil, dialog)
    dialog.grip:SetWidth(12); dialog.grip:SetHeight(12); dialog.grip:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", 0, 0)
    dialog.grip:SetFrameLevel(dialog:GetFrameLevel()+100)
    dialog.grip:SetScript("OnMouseDown", function() dialog:StartSizing("BOTTOMRIGHT") end)
    dialog.grip:SetScript("OnMouseUp", function() dialog:StopMovingOrSizing() end)
    local function LayoutContent(width)
        local y = 0
        local function Line(line)
            line:ClearAllPoints(); line:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            line:SetWidth(width); line:SetHeight(0); line:SetJustifyH("LEFT")
            if line.SetWordWrap then line:SetWordWrap(true) end
            y = y + math.max(16, UI.MeasureTextHeight(line, width)) + 8
        end
        Line(dialog.help); Line(dialog.status); Line(dialog.item); Line(dialog.result)
        y = UI.LayoutFlow(body, dialog.actions, 0, y, width, 8) + 8
        Line(dialog.logTitle)
        for i = 1, table.getn(dialog.logLines) do
            if dialog.logLines[i]:GetText() ~= "" then Line(dialog.logLines[i]); dialog.logLines[i]:Show() else dialog.logLines[i]:Hide() end
        end
        return y
    end
    function dialog:Layout()
        self.host:ClearAllPoints(); self.host:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -36)
        self.host:SetWidth(self:GetWidth()-16); self.host:SetHeight(self:GetHeight()-78)
        UI.LayoutResponsiveCanvas(body, LayoutContent)
    end
    dialog:SetScript("OnSizeChanged", function() dialog:Layout() end)
    function dialog:Refresh()
        Raider.Services.CSRTest.BuildSummary(self.state, self.summary)
        local totalItems, totalCsr = 0, 0
        for _, player in ipairs(self.summary.players) do totalItems=totalItems+player.items; totalCsr=totalCsr+player.csr end
        local selected = self.state.currentPlayer
        self.status:SetText("Player: " .. (selected or "none") .. "   Rank: " .. (selected and self.state.ranks[selected] or "-") .. "   Date: " .. date("%Y-%m-%d", self.state.now))
        self.item:SetText("Item: " .. UI.GetItemLabel(Raider.Services.CSRTest.GetItemId(self.state)))
        self.result:SetText("Rows: " .. table.getn(self.summary.players) .. "   Reserves: " .. totalItems .. "   CSR: " .. totalCsr)
        for i=1,table.getn(self.logLines) do self.logLines[i]:SetText(self.state.log[i] or "") end
        self:Layout()
        if onChanged then onChanged() end
    end
    function dialog:Open() self:Refresh(); self:Show() end
    dialog:Hide()
    return dialog
end

function CSR.Create(host, getEntries, getRules, getRosterData, openRaidStatistics)
    local page=UI.CreateResponsiveCanvas(host,"BootyRaiderCSRPage")
    local controller = { page = page, rows = {}, summary = { players = {} }, testMode = false, selectedRaids = {}, expandedKey = nil }
    local raidNames = Raider.Services.RaidStatistics.GetRaidNames()
    local raidFilterIndex
    for raidFilterIndex = 1, table.getn(raidNames) do controller.selectedRaids[raidNames[raidFilterIndex]] = true end
    page.csrController=controller;host.csrController=controller
    controller.testLab = CreateTestLab(function() controller.testMode = true; controller:Refresh() end, function() controller.testMode = false; controller:Refresh() end)
    controller.title = Raider.UI.Components.CreateHeading(page, "", 1, "gold", "csr"); controller.title:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -10); controller.title:SetText("CSR")
    controller.description = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontHighlightSmall"); controller.description:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -40); controller.description:SetPoint("RIGHT", page, "RIGHT", -6, 0); controller.description:SetJustifyH("LEFT")
    controller.description:SetText("Unsuccessful Soft Reserves from the last 60 days. Each player-item pair accumulates independently. Each miss grants 10 CSR.")
    controller.testButton = Raider.UI.Components.CreateButton(page, nil, "CSR Test Lab", 96, 22); controller.testButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -10); controller.testButton:SetScript("OnClick", function() controller.testLab:Open() end)
    controller.filterLabel = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontHighlightSmall"); controller.filterLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -75); controller.filterLabel:SetText("Filters")
    controller.raidFilter = Raider.UI.Components.CreateDropdownButton(page, nil, "Raid", 150); controller.raidFilter:SetPoint("LEFT", controller.filterLabel, "RIGHT", 10, 0)
    controller.raidPanel = Raider.UI.Components.CreateDropdownPanel(page, controller.raidFilter, 190, 178, 20)
    controller.searchLabel = Raider.UI.Components.CreateLabel(page, nil, "OVERLAY", "GameFontHighlightSmall"); controller.searchLabel:SetPoint("LEFT", controller.raidFilter, "RIGHT", 18, 0); controller.searchLabel:SetText("Search")
    controller.search = Raider.UI.Components.CreateFramedEditBox(page, nil, 180); controller.search:ClearAllPoints(); controller.search:SetPoint("LEFT", controller.searchLabel, "RIGHT", 7, 0); controller.search:SetHeight(22); controller.search:SetAutoFocus(false); controller.search:SetScript("OnEscapePressed", function() this:ClearFocus() end); controller.search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    controller.raidDismiss = controller.raidPanel.dismiss
    controller.raidFilter:SetScript("OnClick", function()
        if controller.raidPanel:IsVisible() then controller.raidPanel:Hide()
        else controller.raidPanel:Show() end
    end)
    UI.FilterPanel.Refresh(controller.raidPanel,raidNames,controller.selectedRaids,function() controller:Refresh() end,true,true)
    controller.raidChecks=controller.raidPanel.options
    controller.search:SetScript("OnTextChanged", function() controller:Refresh() end)
    UI.AttachPlaceholder(controller.search,"Search...");controller.searchLabel:SetText("");controller.searchLabel:Hide()
    controller.playerHeader = Raider.UI.Components.Table.CreateHeader(page, nil, "Player name", 16, -108, 154, nil, false)
    controller.itemsHeader = Raider.UI.Components.Table.CreateHeader(page, nil, "Item", 180, -108, 140, nil, false)
    controller.csrHeader = Raider.UI.Components.Table.CreateHeader(page, nil, "CSR", 0, -108, 60, nil, false)
    controller.csrHeader:ClearAllPoints(); controller.csrHeader:SetPoint("TOPRIGHT", page, "TOPRIGHT", -24, -108)
    controller.playerHeader:SetHeight(16); controller.itemsHeader:SetHeight(16); controller.csrHeader:SetHeight(16)
    controller.scroll = Raider.UI.Components.CreateScrollFrame("BootyRaiderCSRScroll", page, "UIPanelScrollFrameTemplate"); controller.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -124); controller.scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -22, 5)
    Raider.UI.Components.RegisterSkinnedScrollBar(getglobal("BootyRaiderCSRScrollScrollBar"))
    controller.canvas=UI.CreateContainer(nil,controller.scroll);controller.scroll:SetScrollChild(controller.canvas)
    controller.detailRows={};controller.detailLines={};controller.viewButtons={}
    local index
    for index = 1, 30 do
        local row = Raider.UI.Components.CreateControl(nil, controller.canvas); row:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -98 - ((index - 1) * 24)); row:SetPoint("RIGHT", page, "RIGHT", -26, 0); row:SetHeight(23)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); row:SetBackdropColor(0.035, 0.035, 0.032, math.mod(index, 2) == 0 and 0.82 or 0.58)
        Raider.UI.Components.RegisterSkinnedSurface(row, "row", { bgFile = "Interface\\Buttons\\WHITE8X8" }, { 0.035, 0.035, 0.032, math.mod(index, 2) == 0 and 0.82 or 0.58 }, { 0, 0, 0, 0 })
        row.name = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall"); row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -4); row.name:SetWidth(150); row.name:SetJustifyH("LEFT")
        row.iconRegion = Raider.UI.Components.CreateTexture(row, nil, "ARTWORK"); row.iconRegion:SetPoint("TOPLEFT", row, "TOPLEFT", 163, -2); row.iconRegion:SetWidth(19); row.iconRegion:SetHeight(19)
        row.label = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall"); row.label:SetPoint("TOPLEFT", row.iconRegion, "TOPRIGHT", 5, -2); row.label:SetPoint("RIGHT", row, "RIGHT", -84, 0); row.label:SetJustifyH("LEFT")
        row.csr = Raider.UI.Components.CreateLabel(row, nil, "OVERLAY", "GameFontHighlightSmall"); row.csr:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4); row.csr:SetWidth(60)
        row.itemHit = Raider.UI.Components.CreateControl(nil, row); row.itemHit:SetPoint("TOPLEFT", row, "TOPLEFT", 160, 0); row.itemHit:SetPoint("TOPRIGHT", row, "TOPRIGHT", -78, 0); row.itemHit:SetHeight(23); row.itemHit.ownerRow = row
        row.itemHit:SetScript("OnEnter", function() Raider.UI.Components.ShowItemTooltip(this.ownerRow) end); row.itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end); row.itemHit:SetScript("OnClick", function() this.ownerRow:Click() end)
        row.detailRows=controller.detailRows;row.detailLines=controller.detailLines;row.viewButtons=controller.viewButtons
        local detailIndex
        function row:AcquireDetail(detailIndex)
            if self.detailRows[detailIndex] then self.detailRows[detailIndex]:SetParent(self);return self.detailRows[detailIndex] end
            local detail = Raider.UI.Components.CreateContainer(nil, row); detail:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -29 - ((detailIndex - 1) * 22)); detail:SetPoint("RIGHT", row, "RIGHT", -6, 0); detail:SetHeight(21)
            detail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); detail.normalAlpha = math.mod(detailIndex, 2) == 0 and 0.28 or 0.16; detail:SetBackdropColor(0.20, 0.16, 0.08, detail.normalAlpha); detail:EnableMouse(true)
            detail:SetScript("OnEnter", function() this:SetBackdropColor(0.34, 0.25, 0.08, 0.55) end); detail:SetScript("OnLeave", function() this:SetBackdropColor(0.20, 0.16, 0.08, this.normalAlpha) end); detail:Hide(); row.detailRows[detailIndex] = detail
            local line = Raider.UI.Components.CreateLabel(detail, nil, "OVERLAY", "GameFontDisableSmall"); line:SetPoint("LEFT", detail, "LEFT", 7, 0); line:SetPoint("RIGHT", detail, "RIGHT", -60, 0); line:SetJustifyH("LEFT"); row.detailLines[detailIndex] = line
            local view = Raider.UI.Components.CreateButton(detail, nil, "View", 52, 20); UI.StyleActionButton(view);view:SetHeight(20); view:SetPoint("RIGHT", detail, "RIGHT", -1, 0); view:SetScript("OnClick", function() if openRaidStatistics and this.raidId then openRaidStatistics(this.raidId) end end); row.viewButtons[detailIndex] = view
            return detail
        end
        row:SetScript("OnClick", function()
            if not this.player then return end
            local key = string.lower(this.player.name or "") .. ":" .. tostring(this.player.itemId or "")
            local collapsing = controller.expandedKey == key
            if collapsing then
                controller.expandedKey = nil
                local detailIndex
                for detailIndex = 1, table.getn(this.detailRows) do this.detailRows[detailIndex]:Hide() end
            else
                controller.expandedKey = key
            end
            controller:Refresh()
        end)
        row:Hide(); controller.rows[index] = row
    end
    UI.StyleProjectPopup(controller.raidPanel)
    UI.StyleActionButton(controller.testButton)
    controller.searchGroup=UI.CreateContainer(nil,page);controller.searchGroup:SetWidth(162);controller.searchGroup:SetHeight(26);controller.searchGroup.mosFlowWidth=162
    controller.searchLabel:Hide()
    controller.search:SetParent(controller.searchGroup);controller.search:ClearAllPoints();controller.search:SetPoint("LEFT",controller.searchGroup,"LEFT",0,0);controller.search:SetWidth(162)
    controller.raidFilter.mosFlowWidth=130;controller.raidFilter:SetHeight(26)
    controller.flow={controller.raidFilter,controller.searchGroup}
    controller.headers={controller.playerHeader,controller.itemsHeader,controller.csrHeader}
    controller.measure=UI.CreateLabel(page,nil,"ARTWORK","GameFontHighlightSmall");controller.measure:SetAlpha(0)
    controller.detailHeights={};controller.detailTexts={};controller.layoutRows={}
    controller.empty=UI.CreateLabel(page,nil,"OVERLAY","GameFontDisableSmall");controller.empty:SetText("No matching Soft Reserves.")
    local function DetailText(raid,index)
        return tostring(index) .. ".  " .. tostring(raid.id or "-") .. " | " .. tostring(raid.raidName or "Other") .. " | " .. date("%Y-%m-%d",tonumber(raid.savedAt) or 0)
    end
    local function MeasureRows(width,self)
        local total=0
        for index,player in ipairs(self.summary.players) do
            local entry=self.layoutRows[index]
            if not entry then entry={};table.insert(self.layoutRows,entry) end
            entry.y=total;entry.player=player;entry.count=0
            local height=24
            if self.expandedKey==string.lower(player.name or "")..":"..tostring(player.itemId or "") then
                entry.count=table.getn(player.raids or {})
                for i,raid in ipairs(player.raids or {}) do
                    self.detailTexts[i]=DetailText(raid,i)
                    self.measure:SetWidth(math.max(1,width-78));self.measure:SetText(self.detailTexts[i])
                    self.detailHeights[i]=math.max(24,UI.MeasureTextHeight(self.measure,math.max(1,width-78))+8);height=height+self.detailHeights[i]
                end
            end
            entry.height=height
            total=total+height
        end
        for i=table.getn(self.layoutRows),table.getn(self.summary.players)+1,-1 do table.remove(self.layoutRows,i) end
        return total
    end
    local function LayoutContent(width,height,self)
        local available=math.max(80,width-16)
        self.title:ClearAllPoints();self.title:SetPoint("TOPLEFT",page,"TOPLEFT",8,-8);UI.FitButtonLabel(self.title,math.max(1,available-104))
        self.testButton:ClearAllPoints();self.testButton:SetPoint("TOPRIGHT",page,"TOPRIGHT",-8,-8)
        self.description:ClearAllPoints();self.description:SetPoint("TOPLEFT",page,"TOPLEFT",8,-42);self.description:SetWidth(available);self.description:SetHeight(0)
        local top=42+math.max(24,UI.MeasureTextHeight(self.description,available))+8
        self.filterLabel:Hide()
        top=UI.LayoutFlow(page,self.flow,8,top,available,8)+8
        self.search:SetWidth(math.max(24,self.searchGroup:GetWidth()))
        self.headerTop=top;self.bodyTop=top+24;self.bodyHeight=math.max(48,height-self.bodyTop-8);self.bodyWidth=available
        return self.bodyTop+self.bodyHeight+8
    end
    function controller:Layout() UI.LayoutResponsiveCanvas(page,LayoutContent,self) end
    function controller:Render(changed)
        if self.rendering then return end
        self.rendering=true
        if changed or not self.renderWidth or self.renderedExpandedKey~=self.expandedKey then
            local width,total,_,maximum=UI.ResolveScrollLayout(self.bodyWidth,self.bodyHeight,20,MeasureRows,self)
            self.renderWidth,self.renderHeight,self.renderMaximum=width,total,maximum
            self.renderedExpandedKey=self.expandedKey
        end
        local width,contentHeight,maximum=self.renderWidth,self.renderHeight,self.renderMaximum
        self.scroll:ClearAllPoints();self.scroll:SetPoint("TOPLEFT",page,"TOPLEFT",8,-self.bodyTop);self.scroll:SetWidth(width);self.scroll:SetHeight(self.bodyHeight)
        self.canvas:SetWidth(width);self.canvas:SetHeight(contentHeight)
        local bar=getglobal(self.scroll:GetName().."ScrollBar")
        if bar then bar:ClearAllPoints();bar:SetPoint("TOPLEFT",page,"TOPLEFT",12+width,-self.bodyTop-16);bar:SetHeight(math.max(1,self.bodyHeight-32));bar:SetWidth(16) end
        UI.ApplyScrollRange(self.scroll,bar,maximum)
        local nameWidth=math.floor(width*0.32);local csrWidth=40;local itemWidth=width-nameWidth-csrWidth
        local starts={0,nameWidth,width-csrWidth};local widths={nameWidth,itemWidth,csrWidth}
        for i=1,3 do local header=self.headers[i];header:ClearAllPoints();header:SetPoint("TOPLEFT",page,"TOPLEFT",8+starts[i],-self.headerTop);header:SetWidth(widths[i]);header:SetHeight(20) end
        self.playerHeader.label:SetText(width<420 and "Player" or "Player name")
        UI.Table.FitHeaders(self.headers,12)
        local top=self.scroll:GetVerticalScroll();local bottom=top+self.bodyHeight
        local y,used=0,0
        for _,detail in ipairs(self.detailRows) do detail:Hide() end
        for logicalIndex,entry in ipairs(self.layoutRows) do
            local player,count,rowHeight=entry.player,entry.count,entry.height
            local expanded=count>0
            y=entry.y
            if y>=bottom then break end
            if y+rowHeight>top and y<bottom and used<table.getn(self.rows) then
                used=used+1;local row=self.rows[used]
                row:ClearAllPoints();row:SetPoint("TOPLEFT",self.canvas,"TOPLEFT",0,-y);row:SetWidth(width);row:SetHeight(rowHeight-1)
                row.player=player;row.itemId=player.itemId
                UI.Table.Cell(row.name,row,6,nameWidth-8,23,player.name)
                row.iconRegion:ClearAllPoints();row.iconRegion:SetPoint("TOPLEFT",row,"TOPLEFT",nameWidth,-2)
                UI.Table.Cell(row.label,row,nameWidth+24,itemWidth-28,23,UI.GetItemLabel(player.itemId)..(player.items>1 and (" x "..player.items) or ""))
                UI.Table.Cell(row.csr,row,width-csrWidth,csrWidth-4,23,tostring(player.csr))
                row.itemHit:ClearAllPoints();row.itemHit:SetPoint("TOPLEFT",row,"TOPLEFT",nameWidth,0);row.itemHit:SetWidth(itemWidth);row.itemHit:SetHeight(23)
                local texture=type(GetItemIcon)=="function" and GetItemIcon(player.itemId) or nil;row.iconRegion:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                UI.ApplyRowBackground(row,logicalIndex,expanded)
                local detailY,detailUsed=24,0
                for i=1,count do
                    local detailHeight=self.detailHeights[i]
                    if y+detailY+detailHeight>top and y+detailY<bottom then
                        detailUsed=detailUsed+1
                        local detail=row:AcquireDetail(detailUsed)
                        detail:ClearAllPoints();detail:SetPoint("TOPLEFT",row,"TOPLEFT",4,-detailY);detail:SetWidth(width-8);detail:SetHeight(detailHeight-2)
                        self.detailLines[detailUsed]:SetText(self.detailTexts[i]);self.detailLines[detailUsed]:SetJustifyV("MIDDLE")
                        self.viewButtons[detailUsed].raidId=player.raids[i].id
                        detail:Show()
                    end
                    detailY=detailY+detailHeight
                end
                row:Show()
            end
            y=y+rowHeight
        end
        for i=used+1,table.getn(self.rows) do self.rows[i].player=nil;self.rows[i]:Hide() end
        self.empty:ClearAllPoints();self.empty:SetPoint("TOPLEFT",page,"TOPLEFT",8,-self.bodyTop-4);self.empty:SetWidth(width)
        if table.getn(self.summary.players)==0 then self.empty:Show() else self.empty:Hide() end
        self.rendering=false
    end
    function controller:Refresh()
        if not host:IsShown() then return end
        Raider.Diagnostics.Count("uiRefreshes")
        if self.testMode then Raider.Services.CSRTest.BuildSummary(self.testLab.state,self.summary) else Raider.Services.CSR.BuildSummary(getEntries(),getRules(),time(),self.summary,getRosterData(),self.selectedRaids,self.search:GetText()) end
        self:Layout();self:Render(true)
    end
    controller.scroll:SetScript("OnVerticalScroll",function() this:SetVerticalScroll(arg1 or 0);controller:Render() end)
    return { frame=page,page=page,Show=function(self) host:Show();page:Show();controller:Refresh() end,
        Hide=function(self) controller.testLab:Hide();controller.raidPanel:Hide();controller.raidDismiss:Hide();page:Hide();host:Hide() end,
        Refresh=function(self) controller:Refresh() end,OnResize=function(self) controller.raidPanel:Hide();controller:Refresh() end }
end
