local Raider = BootyRaider
Raider.Modules.RaidSessionController = Raider.Modules.RaidSessionController or {}
local RaidSessionController = Raider.Modules.RaidSessionController

-- Feature lifecycle state is separate from durable session transformations and
-- presentation. Explicit callbacks retain the original ordering at UI boundaries.
function RaidSessionController.Create(dependencies)
    local state, session = dependencies.state, dependencies.session
    local controller = {}
    local pendingState
    local pendingFields = {"raidSessionDraft", "raidSessionPaused", "raidScanReady", "raidLiveTracking",
        "raidSessionContinuedContext", "raidSessionTransitionPending", "raidSessionMismatchContext",
        "raidPhysicalRosterReady", "raidSessionAwaitingPhysicalAcceptance"}

    -- Read after the service work, preserving the legacy callback order without
    -- allocating closures on each roster capture.
    local function IsDraft() return state.raidSessionDraft end
    local function PendingId() return state.pendingRaidSessionId end
    local function PendingName() return state.pendingRaidName end

    function controller:CaptureActiveRoster()
        if state.raidSessionTransitionPending then return nil end
        return session:CaptureActiveRoster(IsDraft)
    end

    function controller:CompletePendingRaidScan()
        local count, failure = session:CapturePendingRaid(PendingId, PendingName)
        if count == nil or count <= 0 then return nil, failure or "The physical raid roster is not ready. Retry or cancel the new session." end
        local live = dependencies.isLiveTrackingWanted()
        state.pendingRaidSessionId = nil
        state.pendingRaidName = nil
        state.raidScanReady = true
        state.raidLiveTracking = live
        if session.CommitPendingRaid then session:CommitPendingRaid() end
        pendingState = nil
        return count
    end

    function controller:Complete(saveOptions)
        if not session:Complete(saveOptions) then return false end
        state.raidSessionDraft = false; state.raidSessionPaused = true; state.raidLiveTracking = false
        state.raidScanReady = false; state.raidSessionContinuedContext = nil
        state.raidSessionTransitionPending = false; state.raidSessionMismatchContext = nil
        state.raidPhysicalRosterReady = nil; state.raidSessionAwaitingPhysicalAcceptance = nil
        if session.ResetPhysicalRaid then session:ResetPhysicalRaid() end
        dependencies.setHistoricalLoaded(false); dependencies.clearSelection()
        dependencies.showSavedPopup()
        return true
    end

    function controller:Begin()
        state.raidSessionPaused = false; state.raidSessionDraft = true
        state.raidSessionContinuedContext = nil
        state.raidSessionTransitionPending = false; state.raidSessionMismatchContext = nil
        state.raidPhysicalRosterReady = nil; state.raidSessionAwaitingPhysicalAcceptance = nil
        if session.ResetPhysicalRaid then session:ResetPhysicalRaid() end
        session:BeginDraft()
    end

    function controller:StartNew(raidId, raidName)
        if dependencies.canStartNewRaid and not dependencies.canStartNewRaid() then return false end
        pendingState = {historical = dependencies.getHistoricalLoaded and dependencies.getHistoricalLoaded() or false}
        local index
        for index = 1, table.getn(pendingFields) do pendingState[pendingFields[index]] = state[pendingFields[index]] end
        state.pendingRaidSessionId = raidId; state.pendingRaidName = raidName
        local previousThis, previousEvent, previousArg = this, event, arg1
        local ok, reason = pcall(function()
            if session.BeginPendingRaid then session:BeginPendingRaid() else session:ClearAttendance() end
            dependencies.setHistoricalLoaded(false)
            state.raidSessionPaused = false; state.raidSessionDraft = true
            state.raidScanReady = false; state.raidLiveTracking = false
            state.raidSessionTransitionPending = false; state.raidSessionMismatchContext = nil
            state.raidPhysicalRosterReady = nil; state.raidSessionAwaitingPhysicalAcceptance = nil
            if session.ResetPhysicalRaid then session:ResetPhysicalRaid() end
            if dependencies.applyRaidPreset then dependencies.applyRaidPreset(raidName) end
        end)
        if session.CapturePendingPreset then
            local captured, failure = pcall(session.CapturePendingPreset, session)
            if not captured then
                reason = ok and tostring(failure) or tostring(reason) .. " Preset ownership: " .. tostring(failure)
                ok = false
            end
        end
        this, event, arg1 = previousThis, previousEvent, previousArg
        if not ok then
            local restored, cancelled, failure = pcall(self.CancelPendingRaidScan, self)
            this, event, arg1 = previousThis, previousEvent, previousArg
            if not restored then reason = tostring(reason) .. " Restoration: " .. tostring(cancelled)
            elseif cancelled == false then reason = tostring(reason) .. " Restoration: " .. tostring(failure) end
            return false, tostring(reason)
        end
        return true
    end

    function controller:CancelPendingRaidScan()
        if not state.pendingRaidSessionId then return false end
        if session.CancelPendingRaid then
            local ok, failure = session:CancelPendingRaid()
            if ok == false then return false, failure end
        end
        state.pendingRaidSessionId = nil; state.pendingRaidName = nil
        if pendingState then
            local index
            for index = 1, table.getn(pendingFields) do state[pendingFields[index]] = pendingState[pendingFields[index]] end
            dependencies.setHistoricalLoaded(pendingState.historical)
            pendingState = nil
        else
            state.raidSessionDraft = false; state.raidScanReady = false
            state.raidLiveTracking = false; state.raidSessionPaused = true
        end
        return true
    end

    function controller:Quit()
        if dependencies.cancelRaidScan then dependencies.cancelRaidScan() end
        session:Quit()
        if session.CommitPendingRaid then session:CommitPendingRaid() end
        pendingState = nil
        state.pendingRaidSessionId = nil; state.pendingRaidName = nil
        state.raidSessionPaused = true; state.raidSessionDraft = false; state.raidLiveTracking = false
        dependencies.setHistoricalLoaded(false); state.raidScanReady = false; dependencies.clearSelection()
        state.raidSessionContinuedContext = nil
        state.raidSessionTransitionPending = false; state.raidSessionMismatchContext = nil
        state.raidPhysicalRosterReady = nil; state.raidSessionAwaitingPhysicalAcceptance = nil
        if session.ResetPhysicalRaid then session:ResetPhysicalRaid() end
    end

    function controller:Continue(contextKey)
        state.raidSessionContinuedContext = contextKey; state.raidSessionPaused = false
        state.raidSessionTransitionPending = state.raidPhysicalRosterReady == false
        if contextKey and string.find(contextKey, "different-raid-context|", 1, true) == 1 then
            if session.AcceptPhysicalRaid and session:AcceptPhysicalRaid() == false then state.raidSessionAwaitingPhysicalAcceptance = contextKey end
            state.raidSessionMismatchContext = nil; state.raidSessionPaused = true
            dependencies.setHistoricalLoaded(true)
        end
    end

    function controller:GetTransitionContext()
        if not state.raidSessionDraft or not session.GetPhysicalTransition then return nil end
        local contextKey, ready = session:GetPhysicalTransition()
        state.raidPhysicalRosterReady = ready
        if ready and contextKey and contextKey == state.raidSessionAwaitingPhysicalAcceptance then
            session:AcceptPhysicalRaid()
            state.raidSessionAwaitingPhysicalAcceptance = nil; contextKey = nil
        end
        if ready and state.raidSessionContinuedContext == "outside-raid-context" and session.ConfirmPhysicalDeparture then session:ConfirmPhysicalDeparture() end
        if ready then state.raidSessionMismatchContext = contextKey end
        state.raidSessionTransitionPending = not ready or state.raidSessionMismatchContext ~= nil
        if state.raidSessionTransitionPending then state.raidLiveTracking = false end
        return state.raidSessionMismatchContext
    end

    function controller:SetTransitionPending(contextKey)
        state.raidSessionTransitionPending = contextKey ~= nil or state.raidPhysicalRosterReady == false
        if state.raidSessionTransitionPending then state.raidLiveTracking = false end
    end

    function controller:ConfirmTransition(contextKey)
        if contextKey == "outside-raid-context" and session.ConfirmPhysicalDeparture then session:ConfirmPhysicalDeparture() end
    end

    function controller:DismissTransition(contextKey)
        state.raidSessionContinuedContext = contextKey
        state.raidSessionPaused = true; state.raidLiveTracking = false
        state.raidSessionTransitionPending = true
    end

    function controller:RefreshCurrentRaid()
        if state.raidSessionTransitionPending then return false end
        local count = self:CaptureActiveRoster()
        if not count or count <= 0 then return false end
        if session.AcceptPhysicalRaid then session:AcceptPhysicalRaid() end
        state.raidSessionPaused = false; state.raidScanReady = true
        dependencies.setHistoricalLoaded(false)
        return true
    end

    function controller:StartTest()
        session:StartTest(); state.raidLiveTracking = false; dependencies.clearSelection()
    end

    local function RestoreState(ready, draft)
        state.raidScanReady = ready; state.raidSessionDraft = draft; state.raidSessionPaused = false
        state.raidSessionTransitionPending = false; state.raidSessionMismatchContext = nil
        state.raidPhysicalRosterReady = nil; state.raidSessionAwaitingPhysicalAcceptance = nil
        if session.ResetPhysicalRaid then session:ResetPhysicalRaid() end
        dependencies.setHistoricalLoaded(false)
    end
    function controller:RestoreActive()
        return session:RestoreActive(RestoreState)
    end

    return controller
end
