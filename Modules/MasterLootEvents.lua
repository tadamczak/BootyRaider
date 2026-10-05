local Raider = BootyRaider
local Match = Raider.Core and Raider.Core.Compatibility and Raider.Core.Compatibility.Match or string.match

Raider.Modules.MasterLootEvents = Raider.Modules.MasterLootEvents or {}
local MasterLootEvents = Raider.Modules.MasterLootEvents

-- WoW event subscriptions live here; award state belongs to RaidService.
function MasterLootEvents.Create(raid, announce)
    local lootEvents = Raider.UI.Components.CreateContainer(nil, UIParent)
    local bagEvents = Raider.UI.Components.CreateContainer(nil, UIParent)
    local messageEvents = Raider.UI.Components.CreateContainer(nil, UIParent)
    local expiryTimer = Raider.UI.Components.CreateContainer(nil, UIParent)
    expiryTimer:Hide()
    local pendingBagLink, pendingBagCount, pendingLocalTrade
    local listeningForLoot, listeningForTrade, listeningForSay = false, false, false

    local function SetLootListening(enabled)
        if listeningForLoot == enabled then return end
        listeningForLoot = enabled
        local method = enabled and "RegisterEvent" or "UnregisterEvent"
        lootEvents[method](lootEvents, "CHAT_MSG_LOOT")
        lootEvents[method](lootEvents, "TRADE_SHOW")
        lootEvents[method](lootEvents, "TRADE_ACCEPT_UPDATE")
        lootEvents[method](lootEvents, "UI_INFO_MESSAGE")
    end

    local function SetTradeListening(enabled)
        if listeningForTrade ~= enabled then
            listeningForTrade = enabled
            if enabled then messageEvents:RegisterEvent("CHAT_MSG_SYSTEM")
            else messageEvents:UnregisterEvent("CHAT_MSG_SYSTEM") end
        end
        local sayEnabled = enabled and raid.allowReyCoinSayTests and true or false
        if listeningForSay ~= sayEnabled then
            listeningForSay = sayEnabled
            if sayEnabled then messageEvents:RegisterEvent("CHAT_MSG_SAY")
            else messageEvents:UnregisterEvent("CHAT_MSG_SAY") end
        end
    end

    local function Sync()
        local transfers = raid.GetPendingReyCoinTransfers()
        local count = table.getn(transfers)
        local awaitingTrade = false
        local index
        for index = 1, count do
            if transfers[index].state == "awaiting_trade" then awaitingTrade = true; break end
        end
        SetLootListening(count > 0 or raid.HasPendingSoftReserveAward())
        SetTradeListening(awaitingTrade or raid.HasPendingSoftReserveTrade())
        if count == 0 then
            bagEvents:UnregisterEvent("BAG_UPDATE")
            pendingBagLink = nil
            pendingLocalTrade = nil
        end
    end

    raid.onReyCoinPendingChanged = Sync

    local function OnExpiryUpdate()
        this.remaining = this.remaining - arg1
        if this.remaining > 0 then return end
        this.deadline = nil
        raid.PrunePendingLoot()
    end

    local function SyncExpiry()
        local deadline = raid.GetNextPendingLootExpiry()
        if not deadline then
            expiryTimer.deadline = nil
            expiryTimer:SetScript("OnUpdate", nil); expiryTimer:Hide()
        elseif expiryTimer.deadline ~= deadline then
            expiryTimer.deadline = deadline
            expiryTimer.remaining = math.max(0, deadline - GetTime())
            expiryTimer:SetScript("OnUpdate", OnExpiryUpdate); expiryTimer:Show()
        end
    end
    raid.onPendingLootExpiryChanged = SyncExpiry
    SyncExpiry()

    messageEvents:SetScript("OnEvent", function()
        if event ~= "CHAT_MSG_SYSTEM" and not (event == "CHAT_MSG_SAY" and raid.allowReyCoinSayTests) then return end
        if not raid.HasPendingReyCoinAward() and not raid.HasPendingSoftReserveTrade() then Sync(); return end
        local sender, itemName, recipient = Match(tostring(arg1 or ""),
            "^%s*(%S+) trades item (.+) to (%S+)%.%s*$")
        if not sender then
            sender, itemName, recipient = Match(tostring(arg1 or ""),
                "^%s*(%S+) traded (.+) to (%S+)%.%s*$")
        end
        if not sender then return end
        local confirmed, link = raid.ConfirmReyCoinTrade(sender, recipient, itemName)
        if not confirmed then confirmed, link = raid.ConfirmSoftReserveTrade(sender, recipient, itemName) end
        if confirmed then announce("TradeConfirmed", {player=sender, item=link, recipient=recipient}) end
    end)

    bagEvents:SetScript("OnEvent", function()
        if not pendingBagLink or not raid.HasPendingReyCoinAward() then Sync(); return end
        if raid.GetBagItemCount(pendingBagLink) > (pendingBagCount or 0) then
            raid.ConfirmReyCoinReceipt(UnitName("player"), pendingBagLink)
            bagEvents:UnregisterEvent("BAG_UPDATE")
            pendingBagLink = nil
        end
    end)

    lootEvents:SetScript("OnEvent", function()
        if event == "CHAT_MSG_LOOT" then
            local message = tostring(arg1 or "")
            if string.find(message, "^You receive loot:") then
                raid.ConfirmReyCoinReceipt(UnitName("player"), message)
            else raid.ConfirmReyCoinLoot(message) end
        elseif event == "TRADE_SHOW" then
            pendingLocalTrade = nil
        elseif event == "TRADE_ACCEPT_UPDATE" and tonumber(arg1) == 1 and tonumber(arg2) == 1 then
            local player, target = UnitName("player"), UnitName("NPC")
            local slot
            for slot = 1, 6 do
                local offered = type(GetTradePlayerItemLink) == "function" and GetTradePlayerItemLink(slot)
                local received = type(GetTradeTargetItemLink) == "function" and GetTradeTargetItemLink(slot)
                if offered and (raid.IsPendingReyCoinTrade(player, offered) or raid.IsPendingSoftReserveTrade(player, offered)) then
                    pendingLocalTrade = { sender = player, recipient = target, link = offered }; break
                end
                if received and (raid.IsPendingReyCoinTrade(target, received) or raid.IsPendingSoftReserveTrade(target, received)) then
                    pendingLocalTrade = { sender = target, recipient = player, link = received }; break
                end
            end
        elseif event == "UI_INFO_MESSAGE" and pendingLocalTrade and ERR_TRADE_COMPLETE and arg1 == ERR_TRADE_COMPLETE then
            local trade = pendingLocalTrade
            pendingLocalTrade = nil
            local confirmed, link = raid.ConfirmReyCoinTrade(trade.sender, trade.recipient, trade.link)
            if not confirmed then confirmed, link = raid.ConfirmSoftReserveTrade(trade.sender, trade.recipient, trade.link) end
            if confirmed then announce("TradeConfirmed", {player=trade.sender, item=link, recipient=trade.recipient}) end
        end
    end)

    return {
        TrackLocalBag = function(link)
            pendingBagLink = link
            pendingBagCount = raid.GetBagItemCount(link)
            bagEvents:RegisterEvent("BAG_UPDATE")
        end,
        ConfirmAwardReceipt = function(recipient, link)
            return raid.ConfirmReyCoinReceipt(recipient, link)
        end,
        Sync = Sync,
    }
end
