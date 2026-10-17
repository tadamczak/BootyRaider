local Raider = BootyRaider

Raider.Services = Raider.Services or {}
local RaidSession = {}
Raider.Services.RaidSession = RaidSession

local Session = {}
Session.__index = Session
local presetKeys = {"lmAutoLootExceptions", "lmAutoLootPresets"}

-- Dependencies are domain adapters, never UI objects or session flag owners.
-- Keeping their namespaces also preserves instrumentation installed afterward.
function RaidSession.Create(dependencies)
    return setmetatable({ dependencies = dependencies }, Session)
end

function Session:RaidIdExists(raidId)
    local database = self.dependencies.database
    return database.HasSoftReserveSnapshot(raidId) or database.HasRaidStatistic(raidId)
end

local function SaveRequest(options, attendance)
    if type(options) ~= "table" then
        local enabled = options and true or false
        options = {saveRaidStatistics = enabled, saveAttendance = enabled, saveCSR = enabled}
    end
    local raidId = options.raidId or attendance and attendance.snapshotId or ""
    if type(raidId) ~= "string" then return nil, "Raid ID must be text." end
    raidId = string.gsub(string.gsub(raidId, "^%s+", ""), "%s+$", "")
    if raidId == "" then return nil, "Raid ID is required." end
    if string.len(raidId) > 80 or string.find(raidId, "%c") then return nil, "Raid ID must contain at most 80 bytes without control characters." end
    local previousEnd = attendance and tonumber(attendance.endedAt)
    local modifyEnd = options.modifyRaidEndTime == true
    if modifyEnd and not previousEnd then return nil,"This raid does not have an end time to modify." end
    local endedAt = previousEnd
    if modifyEnd then endedAt = tonumber(options.endedAt) end
    if modifyEnd and (not endedAt or endedAt - endedAt ~= 0 or endedAt ~= math.floor(endedAt)) then
        return nil,"Enter a valid raid end time."
    end
    return {raidId = raidId, saveRaidStatistics = options.saveRaidStatistics and true or false,
        saveAttendance = options.saveAttendance and true or false, saveCSR = options.saveCSR and true or false,
        saveRaidEndTime = not previousEnd and options.saveRaidEndTime == true or false,
        modifyRaidEndTime = modifyEnd, endedAt = endedAt}
end

function Session:PrepareSave(options)
    local attendance = self.dependencies.database.GetRaidAttendance()
    if not attendance or self.dependencies.testRaid.IsActive() then return nil, "There is no saved raid session to save." end
    local request, failure = SaveRequest(options, attendance)
    if not request then return nil, failure end
    local canonical, snapshot, statistic = self.dependencies.database.GetSavedRaidState(request.raidId)
    request.raidId = canonical or request.raidId
    local confirmation = {attendance = attendance, raidId = request.raidId, snapshot = snapshot, statistic = statistic,
        saveRaidStatistics = request.saveRaidStatistics, saveAttendance = request.saveAttendance, saveCSR = request.saveCSR,
        saveRaidEndTime = request.saveRaidEndTime, modifyRaidEndTime = request.modifyRaidEndTime, endedAt = request.endedAt}
    self.preparedSave = confirmation
    request.confirmation = confirmation
    return request, canonical ~= nil
end

function Session:CancelPreparedSave(confirmation)
    if self.preparedSave ~= confirmation then return false end
    self.preparedSave = nil
    return true
end

function Session:CaptureActiveRoster(isDraft)
    local dependencies = self.dependencies
    if dependencies.testRaid.IsActive() then return dependencies.testRaid.GetRaidMemberCount() end
    local previousAttendance = dependencies.database.GetRaidAttendance()
    local count, failure = dependencies.raid.SaveRoster()
    if count == nil then return nil, failure end
    local attendance = dependencies.database.GetRaidAttendance()
    dependencies.raidRes.Reconcile(previousAttendance, attendance)
    if attendance and isDraft() then attendance._sessionDraft = true end
    return count
end

function Session:CapturePendingRaid(getPendingId, getPendingName)
    local dependencies = self.dependencies
    local count, attendance = dependencies.raid.CaptureRoster(true)
    if count == nil then return nil, attendance end
    if count <= 0 then return nil, "The physical raid roster is not ready. Retry or cancel the new session." end
    if attendance and getPendingId() then
        attendance.snapshotId = getPendingId()
        attendance.raidName = getPendingName() or attendance.raidName
        attendance.sessionStartedAt = dependencies.now()
        attendance.createdAt = attendance.sessionStartedAt
        attendance.softReserveImport = { id = getPendingId(), origin = "booty", importedAt = dependencies.now(), unmatchedNames = {}, unmatchedReservations = {}, missingNames = {} }
        attendance._sessionDraft = true
        attendance.lootRules = dependencies.database.CopyLootRules(dependencies.database.GetDefaultLootRules())
        attendance.saveOptions = {saveRaidStatistics = true, saveAttendance = true, saveCSR = true}
    end
    dependencies.database.StoreRaidAttendance(attendance)
    return count
end

function Session:BeginPendingRaid()
    -- This reference is transient, never another durable copy of attendance.
    local database = self.dependencies.database
    local pending = {attendance = database.GetRaidAttendance(), presets = {}}
    self.pendingRaid = pending
    local index
    for index = 1, table.getn(presetKeys) do pending.presets[presetKeys[index]] = database.GetSetting(presetKeys[index]) end
    self:ClearAttendance()
end

function Session:CapturePendingPreset()
    local pending = self.pendingRaid
    if not pending then return end
    pending.appliedPresets = {}
    local index
    for index = 1, table.getn(presetKeys) do
        pending.appliedPresets[presetKeys[index]] = self.dependencies.database.GetSetting(presetKeys[index])
    end
end

function Session:CommitPendingRaid()
    self.pendingRaid = nil
end

function Session:CancelPendingRaid()
    local pending = self.pendingRaid
    if pending then
        local database, firstFailure = self.dependencies.database, nil
        if pending.appliedPresets then
            local index
            for index = 1, table.getn(presetKeys) do
                local key = presetKeys[index]
                local current = database.GetSetting(key)
                local retry = pending.failedPresetRestores and pending.failedPresetRestores[key]
                -- A later setting edit has its own owner. Roll back only the
                -- values still belonging to this attempted Start. A setter
                -- may write the old value before its owner refresh throws;
                -- retain that restoration until its effects also succeed.
                if retry and current == pending.presets[key] or pending.presets[key] ~= pending.appliedPresets[key]
                    and current == pending.appliedPresets[key] then
                    local ok, failure = pcall(database.SetSetting, key, pending.presets[key])
                    if not ok then
                        pending.failedPresetRestores = pending.failedPresetRestores or {}
                        pending.failedPresetRestores[key] = true
                        if not firstFailure then firstFailure = tostring(failure) end
                    elseif pending.failedPresetRestores then pending.failedPresetRestores[key] = nil end
                elseif retry then pending.failedPresetRestores[key] = nil
                end
            end
        end
        local ok, failure = pcall(database.StoreRaidAttendance, pending.attendance)
        if not ok and not firstFailure then firstFailure = tostring(failure) end
        if firstFailure then return false, firstFailure end
        self.pendingRaid = nil
    end
    return true
end

function Session:Complete(saveOptions)
    local dependencies = self.dependencies
    if dependencies.testRaid.IsActive() then
        dependencies.testRaid.Stop()
    else
        local attendance = dependencies.database.GetRaidAttendance()
        if not attendance then return false, "There is no raid session to save." end
        local request, failure = SaveRequest(saveOptions, attendance)
        if not request then return false, failure end
        local canonical, snapshot, statistic = dependencies.database.GetSavedRaidState(request.raidId)
        request.raidId = canonical or request.raidId
        local confirmation = type(saveOptions) == "table" and saveOptions.confirmation
        local overwrite = type(saveOptions) == "table" and saveOptions.overwrite
        if confirmation or overwrite then
            if confirmation ~= self.preparedSave or not confirmation or confirmation.attendance ~= attendance
                or confirmation.raidId ~= request.raidId or confirmation.snapshot ~= snapshot or confirmation.statistic ~= statistic
                or confirmation.saveRaidStatistics ~= request.saveRaidStatistics or confirmation.saveAttendance ~= request.saveAttendance
                or confirmation.saveCSR ~= request.saveCSR or confirmation.saveRaidEndTime ~= request.saveRaidEndTime
                or confirmation.modifyRaidEndTime ~= request.modifyRaidEndTime or confirmation.endedAt ~= request.endedAt then
                self:CancelPreparedSave(confirmation)
                return false, "The raid or save destination changed. Review the save options and try again."
            end
        end
        if canonical and (not confirmation or overwrite ~= true) then return false, "Confirm replacement of the saved raid first." end
        -- Build from a staged owner so failed preparation and cancelled/stale
        -- confirmation never alter the active session or its historical source.
        local staged, key, value = {}, nil, nil
        for key, value in pairs(attendance) do staged[key] = value end
        staged.snapshotId, staged._loadedSnapshotId = request.raidId, nil
        local savedAt = dependencies.now()
        local endedAt = request.saveRaidEndTime and savedAt or request.endedAt
        local startedAt = tonumber(attendance.sessionStartedAt or attendance.createdAt)
        if endedAt and (not startedAt or endedAt < startedAt or endedAt > savedAt) then
            return false,"Raid end time must be between the raid start and the current time."
        end
        staged.lastSavedAt, staged._sessionDraft = savedAt, nil
        staged.createdAt = tonumber(attendance.createdAt or attendance.sessionStartedAt) or savedAt
        staged.modifiedAt = savedAt
        staged.endedAt = endedAt
        staged.duration = endedAt and endedAt - startedAt or nil
        staged.saveOptions = {saveRaidStatistics = request.saveRaidStatistics, saveAttendance = request.saveAttendance, saveCSR = request.saveCSR}
        local entry
        if request.saveRaidStatistics or request.saveCSR then
            entry = dependencies.raidStatistics.BuildEntry(staged, request)
            if not entry then return false, "Raid statistics could not be prepared." end
        end
        if not dependencies.raidRes.SyncHistory(staged) then return false, "The raid snapshot could not be saved." end
        if entry then dependencies.database.StoreRaidStatistic(entry)
        elseif statistic then dependencies.database.DeleteRaidStatistic(request.raidId) end
        self.preparedSave = nil
        dependencies.database.StoreRaidAttendance(nil)
    end
    return true
end

function Session:LoadSnapshot(snapshotId)
    local dependencies = self.dependencies
    local _, snapshot = dependencies.database.GetSavedRaidState(snapshotId)
    if snapshot then
        local attendance = dependencies.raidRes.RestoreSnapshot(snapshot)
        dependencies.raidRes.Reconcile(attendance, attendance)
        return attendance
    end
    return nil
end

function Session:RestoreActive(onStateResolved)
    local dependencies = self.dependencies
    local attendance = dependencies.database.GetRaidAttendance()
    local importInfo = attendance and attendance.softReserveImport
    local raidId = attendance and (attendance.snapshotId or (importInfo and importInfo.id))
    local restorable = raidId and attendance.sessionStartedAt and type(attendance.members) == "table"
    local ready = restorable and true or false
    local draft = restorable and attendance._sessionDraft and true or false
    if onStateResolved then onStateResolved(ready, draft) end
    if restorable then dependencies.raidRes.Reconcile(attendance, attendance) end
    return attendance, ready, draft
end

function Session:BeginDraft()
    local dependencies = self.dependencies
    local attendance = dependencies.testRaid.IsActive() and dependencies.testRaid.GetAttendance()
        or dependencies.database.GetRaidAttendance()
    if attendance then attendance._sessionDraft = true end
end

function Session:ClearAttendance()
    self.preparedSave = nil
    self.dependencies.database.StoreRaidAttendance(nil)
end

function Session:Quit()
    local dependencies = self.dependencies
    local wasTestRaid = dependencies.testRaid.IsActive()
    dependencies.testRaid.Stop()
    self.preparedSave = nil
    if not wasTestRaid then dependencies.database.StoreRaidAttendance(nil) end
end

function Session:StartTest()
    self.dependencies.testRaid.Start()
end

local function ClearNames(names)
    local name
    for name in pairs(names) do names[name] = nil end
end

local function CopyMemberNames(names, members, playerName)
    ClearNames(names)
    local index, count = 0, 0
    if not members then return count end
    for index = 1, table.getn(members) do
        local name = members[index].name
        if name then
            name = string.lower(name)
            if name ~= playerName and not names[name] then names[name] = true; count = count + 1 end
        end
    end
    return count
end

function Session:ResetPhysicalRaid()
    local physical = self.physicalRaid
    if not physical then return end
    ClearNames(physical.reference); ClearNames(physical.current)
    physical.sessionId, physical.startedAt, physical.initialized = nil, nil, false
    physical.left, physical.candidate = false, nil
    physical.present, physical.ready, physical.currentCount, physical.referenceCount = false, false, 0, 0
end

-- The 1.12 client has no physical raid ID. Use observed group departure and
-- overlap with the accepted roster; subgroup/leader changes are not a new raid.
-- Tables are reused, and this is called only by client context events or their
-- existing one-shot confirmation, never an idle poll or a roster capture.
function Session:ReadPhysicalRaid(attendance)
    if type(GetNumRaidMembers) ~= "function" or type(GetRaidRosterInfo) ~= "function" then return nil, false end
    local physical = self.physicalRaid
    if not physical then
        physical = { reference = {}, current = {}, serial = 0 }
        self.physicalRaid = physical
    end
    local playerName = type(UnitName) == "function" and UnitName("player") or nil
    playerName = playerName and string.lower(playerName)
    if not attendance then self:ResetPhysicalRaid(); return nil, true end
    if not physical.initialized or physical.sessionId ~= attendance.snapshotId or physical.startedAt ~= attendance.sessionStartedAt then
        physical.sessionId, physical.startedAt = attendance.snapshotId, attendance.sessionStartedAt
        physical.referenceCount = CopyMemberNames(physical.reference, attendance.members, playerName)
        physical.initialized, physical.left, physical.candidate = true, false, nil
    end
    local count = math.min(40, tonumber(GetNumRaidMembers()) or 0)
    ClearNames(physical.current)
    physical.currentCount = 0
    if count <= 0 then physical.present = false; physical.ready = true; return nil, true end
    local index, namedCount, overlap = 0, 0, false
    for index = 1, count do
        local name = GetRaidRosterInfo(index)
        if name then
            namedCount = namedCount + 1; name = string.lower(name)
            if name ~= playerName then
                if not physical.current[name] then physical.currentCount = physical.currentCount + 1 end
                physical.current[name] = true
                if physical.reference[name] then overlap = true end
            end
        end
    end
    physical.present = true
    physical.ready = namedCount == count
    if not physical.ready then return nil, false end
    local different = physical.left or (physical.referenceCount > 0 and physical.currentCount > 0 and not overlap)
    if not different then
        ClearNames(physical.reference)
        local name
        for name in pairs(physical.current) do physical.reference[name] = true end
        physical.referenceCount = physical.currentCount
        physical.candidate = nil
        return nil, true
    end
    if not physical.candidate then
        physical.serial = physical.serial + 1
        physical.candidate = "different-raid-context|" .. physical.serial
    end
    return physical.candidate, true
end

function Session:GetPhysicalTransition()
    if self.dependencies.testRaid.IsActive() then return nil, true end
    return self:ReadPhysicalRaid(self.dependencies.database.GetRaidAttendance())
end

function Session:ConfirmPhysicalDeparture()
    if self.physicalRaid and not self.physicalRaid.present then self.physicalRaid.left = true end
end

function Session:AcceptPhysicalRaid()
    local physical = self.physicalRaid
    if not physical or not physical.present or not physical.ready then return false end
    ClearNames(physical.reference)
    local name
    for name in pairs(physical.current) do physical.reference[name] = true end
    physical.referenceCount = physical.currentCount
    physical.left, physical.candidate = false, nil
    return true
end
