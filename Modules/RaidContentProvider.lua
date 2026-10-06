local Raider, Lib = BootyRaider, BootyLib
local Provider = {id = "raider", placeId = "friends.raid", apiVersion = 1}
Raider.Modules.RaidContentProvider = Provider
local control, native, dataReady, busy, lastError, lastStatus

local function Failure(code, message, detail)
    return false, {code = code, message = tostring(message or code), detail = detail, lease = control and control.lease or nil}
end
local function NativeAvailable()
    return FriendsFrame ~= nil and RaidFrame ~= nil and type(FriendsFrame_ShowSubFrame) == "function"
end
local function ErrorMessage(value)
    if type(value) == "table" then return tostring(value.message or value.code or "Raid content operation failed.") end
    return value and tostring(value) or nil
end
local function ErrorStatus(value)
    if not value then return nil end
    if type(value) ~= "table" then return {code = "provider-error", message = tostring(value)} end
    return {code = value.code, message = ErrorMessage(value), partial = value.partial,
        cleanupError = ErrorMessage(value.cleanupError), rollbackError = ErrorMessage(value.rollbackError),
        notificationError = ErrorMessage(value.notificationError), idleError = ErrorMessage(value.idleError)}
end
function Provider.IsControlled() return control ~= nil end
function Provider.IsSelected()
    if control then return control.selected == true end
    return type(BootyRaiderDB) == "table" and BootyRaiderDB.useMOSRaidTab == true
end
function Provider.GetLayoutContext() return control and control.layout or nil end
function Provider.GetStatus()
    local observed = native and native:GetStatus() or {}
    local active = Raider.active == true
    local available = NativeAvailable() == true
    local state = (lastError or observed.error) and "error" or not dataReady and "pending" or not active and "unavailable"
        or not available and "unavailable" or observed.conflict and "conflict" or "ready"
    local legacy
    if dataReady then legacy = BootyRaiderDB.useMOSRaidTab == true end
    local effective
    if observed.bound == true and observed.owned == true and active and not lastError and not observed.error then effective = "raider"
    elseif available and not lastError and not observed.error and (not native or observed.nativeReady == true) then effective = "native" end
    return {ready = dataReady == true, initialized = native ~= nil, active = active, available = available, busy = busy == true,
        canEmbed = active and available and native ~= nil, controlled = control ~= nil, selected = Provider.IsSelected(),
        effective = effective, visible = observed.visible == true,
        nativeOwned = observed.conflict ~= true, state = state, error = ErrorStatus(lastError or observed.error),
        legacySelected = legacy}
end
local statusKeys = {"ready", "initialized", "active", "available", "canEmbed", "controlled", "selected", "effective", "visible", "nativeOwned", "state", "legacySelected"}
function Provider.Notify()
    local status = Provider.GetStatus()
    local changed = not lastStatus
    if lastStatus then for _, key in ipairs(statusKeys) do if status[key] ~= lastStatus[key] then changed = true; break end end end
    if lastStatus then
        for _, key in ipairs({"code", "message", "partial", "cleanupError", "rollbackError", "notificationError", "idleError"}) do
            if (status.error and status.error[key]) ~= (lastStatus.error and lastStatus.error[key]) then changed = true; break end
        end
    end
    lastStatus = status
    if changed and control and control.callbacks.OnStatusChanged then
        local ok, result, message = pcall(control.callbacks.OnStatusChanged, status)
        if not ok or result == false then
            lastError = {code = "notification-failed", message = tostring(ok and message or result)}
            return Failure("notification-failed", lastError.message)
        end
    end
    return true, status
end
function Provider.LayoutChanged(rects)
    if control and control.callbacks.OnLayoutChanged then
        local ok, result, message = pcall(control.callbacks.OnLayoutChanged, rects)
        if not ok or result == false then return Failure("notification-failed", ok and message or result) end
    end
    return true
end
local function Sync()
    if not native then return true end
    return native:Sync()
end
local function NeedsSync()
    local status = native and native:GetStatus()
    return lastError ~= nil or status and (status.conflict or status.error) or false
end
local function SameLayout(first, second)
    if first == second then return true end
    if not first or not second then return false end
    for _, name in ipairs({"header", "content"}) do
        for _, key in ipairs({"left", "top", "right", "bottom", "width", "height"}) do
            if (first[name] and first[name][key]) ~= (second[name] and second[name][key]) then return false end
        end
    end
    return true
end
local function RefreshSettings()
    local settings = Lib.Core and Lib.Core.SettingsHost
    if not settings or type(settings.RefreshProvider) ~= "function" then return true end
    local ok, result, message = pcall(settings.RefreshProvider, "raider")
    if not ok or result == false then return Failure("settings-refresh-failed", ok and message or result) end
    return true
end
local function Protected(operation)
    if busy then return Failure("busy", "A Raid content operation is already in progress.") end
    busy = true
    local ok, result, detail = pcall(operation)
    if not ok then result, detail = Failure("provider-error", result) end
    if result ~= true then
        lastError = type(detail) == "table" and detail or {code = "provider-error", message = tostring(detail or "Raid content operation failed.")}
        detail = lastError
    else lastError = nil end
    local notified, status = Provider.Notify()
    busy = false
    local idle = control and control.callbacks.OnIdle
    if idle then
        local completed, value, message = pcall(idle)
        if not completed or value == false then
            local _, failure = Failure("idle-notification-failed", completed and message or value)
            lastError = failure
            if result ~= true then detail.idleError = failure else return false, failure end
        end
    end
    if result ~= true then return false, detail or lastError end
    if not notified then return notified, status end
    return true, detail or Provider.GetStatus()
end
function Provider.Acquire(ownerToken, callbacks)
    if type(ownerToken) ~= "table" then return Failure("invalid-owner", "Expected a Raid content owner token.") end
    callbacks = callbacks or {}
    if type(callbacks) ~= "table" or callbacks.OnStatusChanged ~= nil and type(callbacks.OnStatusChanged) ~= "function"
        or callbacks.OnLayoutChanged ~= nil and type(callbacks.OnLayoutChanged) ~= "function"
        or callbacks.OnIdle ~= nil and type(callbacks.OnIdle) ~= "function" then
        return Failure("invalid-callback", "Expected Raid content callbacks.")
    end
    if control and control.owner ~= ownerToken then return Failure("owner-conflict", "Raid content is controlled by another owner.") end
    return Protected(function()
        if control then
            if NeedsSync() then local ok, failure = Sync(); if not ok then return ok, failure end end
            return true, control.lease
        end
        local acquired = {owner = ownerToken, callbacks = callbacks, selected = false}
        local lease = {}
        acquired.lease, control = lease, acquired
        function lease.SetSelected(enabled, layoutContext)
            if control ~= acquired then return Failure("stale-lease", "The Raid content lease has ended.") end
            if type(enabled) ~= "boolean" then return Failure("invalid-selection", "Expected a Raid content selection.") end
            return Protected(function()
                local ok, context = Raider.Modules.NativeRaidTab.ValidateLayoutContext(layoutContext)
                if not ok then return ok, context end
                if acquired.selected == enabled and SameLayout(acquired.layout, context) and not NeedsSync() then return true end
                acquired.selected, acquired.layout = enabled, context
                local synced, failure = Sync(); if not synced then return synced, failure end
                return true
            end)
        end
        function lease.Release()
            if control ~= acquired then return Failure("stale-lease", "The Raid content lease has ended.") end
            return Protected(function()
                acquired.selected = false
                local ok, failure = Sync(); if not ok then return ok, failure end
                -- Keep the lease if fallback attachment fails. Legacy must not
                -- run beside an activation whose cleanup could not be verified.
                control = nil
                ok, failure = Sync()
                if not ok then
                    control = acquired; acquired.selected = false
                    local cleaned, cleanup = Sync()
                    if not cleaned then
                        failure = {code = "release-failed", message = "Fallback activation and cleanup failed.", cause = failure, rollbackError = cleanup, partial = true, lease = lease}
                    end
                    return false, failure
                end
                local refreshed, refreshFailure = RefreshSettings()
                if not refreshed then
                    control = acquired
                    local cleaned, cleanup = Sync()
                    refreshFailure.detail = not cleaned and cleanup or nil
                    return false, refreshFailure
                end
                return true
            end)
        end
        local ok, failure = Sync()
        local refreshed, refreshFailure = RefreshSettings()
        if not ok then
            local detail = type(failure) == "table" and failure or {code = "acquire-failed", message = tostring(failure)}
            detail.lease = lease
            return false, detail
        end
        if not refreshed then return false, refreshFailure end
        return true, lease
    end)
end
function Provider.MarkDataReady() dataReady = true end
function Provider.BindController(controller) native = controller end
function Provider.Sync() return Protected(Sync) end
function Provider.Prepare()
    local coordinator = Lib.GetProduct and Lib.GetProduct("bootyui")
    if not coordinator or coordinator.stopped or coordinator.failure or type(coordinator.PrepareContentProvider) ~= "function" then return true end
    local ok, result, reason = pcall(coordinator.PrepareContentProvider, Provider)
    if not ok then return Failure("prepare-failed", result) end
    if result == false then return false, reason end
    return true
end
function Provider.OpenSelection()
    local coordinator = Lib.GetProduct and Lib.GetProduct("bootyui")
    if not coordinator or type(coordinator.OpenContentSelection) ~= "function" then return Failure("unavailable", "BootyUI content selection is unavailable.") end
    return coordinator.OpenContentSelection("friends.raid")
end
