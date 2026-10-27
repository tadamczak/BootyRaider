local Raider = BootyRaider
local Audit = {}
Raider.Services.RaidAudit = Audit

local function Store()
    local db = Raider.Database.Ensure()
    local journal, reason = Raider.Services.RaidJournal.Ensure(db)
    if not journal then error(reason) end
    return db
end
local function IsTest()
    return Raider.Services.TestRaid and Raider.Services.TestRaid.IsActive()
end
function Audit.EnsureIdentity(record)
    if not record then return nil end
    if not record.syncRaidId then record.syncRaidId = Raider.Services.RaidJournal.NewRaidId(Store()) end
    return record.syncRaidId
end
function Audit.Commit(record, kind, changes, detail, visible)
    if not record or IsTest() then return true end
    local id = Audit.EnsureIdentity(record)
    return Raider.Services.RaidJournal.Commit(Store(), id, kind, changes, detail, visible)
end
function Audit.Metadata(record)
    return {id=record.snapshotId or record.id or "", raidName=record.raidName or "Other",
        displayName=record.displayName or "", endedAt=record.endedAt,
        startedAt=record.sessionStartedAt or record.startedAt or record.createdAt}
end
function Audit.SRValue(member)
    local items = {}
    for index, item in ipairs(member.srItemIds or {}) do items[index] = item end
    return {name=member.name, items=items, exception=member.srException==true}
end
function Audit.MemberChanges(members)
    local changes = {}
    for _, member in ipairs(members or {}) do
        local key = string.lower(member.name or "")
        if key ~= "" then
            table.insert(changes,{key="sr:"..key,value=Audit.SRValue(member)})
            table.insert(changes,{key="member:"..key,value={name=member.name,class=member.class or "",
                classFile=member.classFile or "",guildRank=member.guildRank or ""}})
        end
    end
    return changes
end
function Audit.Reserves(attendance,kind,members,detail,importInfo)
    local changes = {}
    for _, member in ipairs(members or attendance.members or {}) do
        table.insert(changes,{key="sr:"..string.lower(member.name),value=Audit.SRValue(member)})
    end
    if importInfo then
        table.insert(changes,{key="import:sr",value={url=importInfo.url or "",unmatched=importInfo.unmatchedReservations or {}}})
    end
    return Audit.Commit(attendance,kind,changes,detail)
end
function Audit.Start(attendance)
    local changes = Audit.MemberChanges(attendance.members)
    table.insert(changes,{key="raid:metadata",value=Audit.Metadata(attendance)})
    table.insert(changes,{key="raid:lifecycle",value="active"})
    return Audit.Commit(attendance,"raid.start",changes,{subject=attendance.snapshotId or "",raidName=attendance.raidName})
end
function Audit.LootValue(member,loot)
    return {recipient=member.name,item=loot.itemId or loot.name,count=loot.count or 1,
        ordinary=loot.ordinaryReceipt==true,historyKey=loot.awardHistoryKey}
end
function Audit.Loot(attendance,member,loot,kind,visible)
    if IsTest() then return true end
    if not loot.syncRecordId then loot.syncRecordId=Raider.Services.RaidJournal.NewRecordId(Store()) end
    return Audit.Commit(attendance,kind,{{key="loot:"..loot.syncRecordId,value=Audit.LootValue(member,loot)}},
        {subject=member.name,item=loot.name or loot.itemId},visible)
end
function Audit.ResetLoot(attendance)
    local changes={}
    for _, group in ipairs({attendance.members or {},attendance.departedMembers or {}}) do
        for _,member in ipairs(group) do
            for _,loot in ipairs(member.loot or {}) do
                if loot.syncRecordId then table.insert(changes,{key="loot:"..loot.syncRecordId,deleted=true}) end
            end
        end
    end
    return Audit.Commit(attendance,"loot.reset",changes,{subject=attendance.snapshotId or ""})
end
function Audit.Trade(attendance,sender,remainder,recipient,loot)
    if IsTest() then return true end
    local changes={}
    if remainder then
        if not remainder.syncRecordId then remainder.syncRecordId=Raider.Services.RaidJournal.NewRecordId(Store()) end
        table.insert(changes,{key="loot:"..remainder.syncRecordId,value=Audit.LootValue(sender,remainder)})
    end
    if not loot.syncRecordId then loot.syncRecordId=Raider.Services.RaidJournal.NewRecordId(Store()) end
    table.insert(changes,{key="loot:"..loot.syncRecordId,value=Audit.LootValue(recipient,loot)})
    return Audit.Commit(attendance,"loot.correct",changes,{subject=recipient.name,item=loot.name or loot.itemId})
end
function Audit.Save(attendance,entry)
    local changes=Audit.MemberChanges(attendance.members)
    table.insert(changes,{key="raid:metadata",value=Audit.Metadata(attendance)})
    table.insert(changes,{key="raid:lifecycle",value="saved"})
    table.insert(changes,{key="raid:save",value=attendance.saveOptions or {}})
    table.insert(changes,{key="saved:snapshot",value=true})
    table.insert(changes,{key="saved:statistic",value=attendance.saveOptions and (attendance.saveOptions.saveRaidStatistics or attendance.saveOptions.saveCSR) or false})
    if entry then
        table.insert(changes,{key="saved:flags",value={attendanceEnabled=entry.attendanceEnabled,csrEnabled=entry.csrEnabled}})
        for _,member in ipairs(entry.members or {}) do
            table.insert(changes,{key="saved:member:"..string.lower(member.name),value={name=member.name,class=member.class,guildRank=member.guildRank,
                lootRank=member.lootRank,attendance=member.attendance,srItems=member.srItems,lootItems=member.lootItems}})
        end
    end
    return Audit.Commit(attendance,"raid.save",changes,{subject=attendance.snapshotId or ""})
end
function Audit.End(attendance)
    return Audit.Commit(attendance,"raid.end",{{key="raid:lifecycle",value="ended"}},{subject=attendance.snapshotId or ""})
end
function Audit.GetLog(record,offset,limit)
    local id=type(record)=="table" and record.syncRaidId or record
    if not id then return {},0 end
    return Raider.Services.RaidJournal.GetLog(Store(),id,offset,limit)
end
function Audit.GetRevision(record)
    local id=type(record)=="table" and record.syncRaidId or record
    if not id then return 0 end
    return Raider.Services.RaidJournal.GetRevision(Store(),id)
end
function Audit.GetLogSummary(record,offset,limit)
    local id=type(record)=="table" and record.syncRaidId or record
    if not id then return {},0 end
    return Raider.Services.RaidJournal.GetLogSummary(Store(),id,offset,limit)
end
function Audit.GetChange(operationId,index)
    return Raider.Services.RaidJournal.GetChange(Store(),operationId,index)
end
function Audit.FindRaidId(displayId)
    local db=Store()
    local wanted=string.lower(tostring(displayId or ""))
    for id,raid in pairs(db.raidJournal.raids) do
        local metadata=raid.records["raid:metadata"]
        if metadata and metadata.value and string.lower(tostring(metadata.value.id or ""))==wanted then return id end
    end
end
function Audit.LootFailure(loot,reason)
    -- A confirmed physical receipt cannot be rolled back. Retain the fact and
    -- its explicit audit failure instead of losing awarded loot on validation.
    loot.auditFailure=tostring(reason)
    local runtime=Raider.Runtime
    if runtime and runtime.Print then runtime.Print("Loot recorded, but Raid Log needs attention: "..tostring(reason)) end
end
