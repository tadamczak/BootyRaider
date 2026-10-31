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
function Audit.IsLogRecording(id,db)
    db=db or Raider.Database.Ensure()
    return type(db.raidLogRecording)=="table" and db.raidLogRecording[id]==true or false
end
function Audit.StartLogRecording(id)
    if type(id)~="string" or id=="" or string.len(id)>300 then return false,"Select a raid session first." end
    local db=Store()
    db.raidLogRecording=db.raidLogRecording or {}
    db.raidLogRecording[id]=true
    return true
end
function Audit.EnsureIdentity(record)
    if not record then return nil end
    if not record.syncRaidId then record.syncRaidId = Raider.Services.RaidJournal.NewRaidId(Store()) end
    return record.syncRaidId
end
function Audit.OwnsRecordId(id)
    local state=Raider.Services.RaidJournal.Ensure(Store())
    local prefix=state.replicaId..":record:"
    return type(id)=="string" and string.sub(id,1,string.len(prefix))==prefix
end
function Audit.Commit(record, kind, changes, detail, visible)
    if not record or IsTest() then return true end
    local replica=Raider.Runtime and Raider.Runtime.replica
    if record.syncRaidId and replica and replica.IsSessionDeleted and replica.IsSessionDeleted(record.syncRaidId) then
        local historyKinds={['raid.edit']=true,['raid.metadata']=true,['raid.flags']=true,['raid.snapshot.delete']=true,['raid.statistic.delete']=true,['csr.archive']=true,['csr.activate']=true}
        if not historyKinds[kind] then return false,"This active session was deleted. Load its saved snapshot to start a new session." end
        local archived={}
        for _,change in ipairs(changes) do
            local key=change.key
            if key=="raid:metadata" or key=="raid:loot-rules" or string.find(key,"^saved:") or string.find(key,"^csr:") then
                local entry={key="archive:"..key,value=change.value}
                if change.deleted then entry.value=false end
                table.insert(archived,entry)
            end
        end
        changes=archived
    end
    if Raider.Services.RaidReplica then
        local valid,reason=Raider.Services.RaidReplica.ValidateOperation({changes=changes})
        if not valid then return false,reason end
    end
    local id = Audit.EnsureIdentity(record)
    local ok,operation=Raider.Services.RaidJournal.Commit(Store(), id, kind, changes, detail, visible)
    local replica=Raider.Runtime and Raider.Runtime.replica
    if ok and operation and replica then replica.OnOperation(operation,"applied",true) end
    return ok,operation
end
function Audit.Metadata(record)
    return {id=record.snapshotId or record.id or "", raidName=record.raidName or "Other",
        displayName=record.displayName or "", endedAt=record.endedAt,
        startedAt=record.sessionStartedAt or record.startedAt or record.createdAt,
        savedAt=record.lastSavedAt or record.savedAt,modifiedAt=record.modifiedAt}
end
local function ReserveItems(values)
    local items={};for index,item in ipairs(values or {}) do items[index]=item end;return items
end
function Audit.SRValue(member,attendance)
    local items = {}
    for index, item in ipairs(member.srItemIds or {}) do items[index] = item end
    local value={name=member.name, items=items, exception=member.srException==true,sourceName=member.srSourceName,optOut=member.srOptOut==true and true or nil}
    local custom=attendance and attendance.srCustomChanges
    local key=string.lower(member.name or "")
    local itemChange=custom and custom["items:"..key]
    local exceptionChange=custom and custom["exception:"..key]
    if itemChange or exceptionChange then
        value.custom={}
        if itemChange then value.custom.items={itemIds=ReserveItems(itemChange.itemIds),sourceName=itemChange.sourceName,optOut=itemChange.optOut} end
        if exceptionChange then value.custom.exception={allowed=exceptionChange.allowed==true} end
    end
    return value
end
function Audit.MemberChanges(members,attendance,departedMembers)
    local changes, included = {}, {}
    for collectionIndex=1,2 do
      local collection=collectionIndex==1 and members or departedMembers
      for _, member in ipairs(collection or {}) do
        local key = string.lower(member.name or "")
        if key ~= "" and not included[key] then
            table.insert(changes,{key="sr:"..key,value=Audit.SRValue(member,attendance)})
            table.insert(changes,{key="member:"..key,value=Audit.MemberValue(member)})
            included[key]=true
        end
      end
    end
    return changes
end
function Audit.MemberValue(member)
    return {name=member.name,class=member.class or "",classFile=member.classFile or "",guildRank=member.guildRank or "",
        guildMember=member.guildMember,level=member.level,subgroup=member.subgroup,raidRank=member.raidRank,online=member.online,zone=member.zone,
        joinedAt=member.joinedAt,leftAt=member.leftAt}
end
function Audit.ObserveRoster(attendance)
    if not attendance or not attendance.syncRaidId or IsTest() then return true end
    local changes,included={},{}
    for collectionIndex=1,2 do
        local collection=collectionIndex==1 and attendance.members or attendance.departedMembers
        for _,member in ipairs(collection or {}) do
            local key=string.lower(member.name)
            if not included[key] then
                table.insert(changes,{key="member:"..key,value=Audit.MemberValue(member)});included[key]=true
            end
        end
    end
    local actor=type(UnitName)=="function" and UnitName("player") or "Unknown"
    table.insert(changes,{key="recorder:"..string.lower(actor),value={name=actor,state="active"}})
    return Audit.Commit(attendance,"raid.observe",changes,nil,false)
end
function Audit.EntitlementValue(member)
    local consumed={}
    for key,value in pairs(member.srConsumedAt or {}) do consumed[key]=value end
    return {name=member.name,srConsumedAt=consumed,reyCoinUsedAt=member.reyCoinUsedAt,reyCoinItemLink=member.reyCoinItemLink}
end
function Audit.Entitlement(attendance,member,value,kind,visible)
    return Audit.Commit(attendance,kind or "entitlement.observe",{{key="entitlement:"..string.lower(member.name),value=value}},
        {subject=member.name},visible)
end
local function AppendEntitlements(changes,attendance,reset)
    local included={}
    for _,group in ipairs({attendance.members or {},attendance.departedMembers or {}}) do
        for _,member in ipairs(group) do
            local key=string.lower(member.name)
            if not included[key] then
                included[key]=true
                table.insert(changes,{key="entitlement:"..key,value=reset and {name=member.name,srConsumedAt={}} or Audit.EntitlementValue(member)})
            end
        end
    end
end
local function Recorder(state)
    local actor=type(UnitName)=="function" and UnitName("player") or "Unknown"
    return {key="recorder:"..string.lower(actor),value={name=actor,state=state}}
end
-- Edit dialogs retain only causal identities, never copied raid payloads. A
-- received edit invalidates the draft even before its visible projection runs.
function Audit.CaptureEditBase(record,keys)
    local id=type(record)=="table" and record.syncRaidId or record
    if not id or IsTest() then return nil end
    local db=Store();local raid=db.raidJournal.raids[id]
    local baseline={raidId=id,heads={},keys=keys}
    local selected={}
    if keys then for _,key in ipairs(keys) do selected[key]=true end
    else for key in pairs(raid and raid.records or {}) do if not string.find(key,"^recorder:") then selected[key]=true end end end
    for key in pairs(selected) do
        local heads={}
        for head in pairs(raid and raid.heads and raid.heads[key] or {}) do table.insert(heads,head) end
        if table.getn(heads)==0 and raid and raid.records[key] and raid.records[key].revision then heads[1]=raid.records[key].revision end
        table.sort(heads);baseline.heads[key]=heads
    end
    return baseline
end
function Audit.CheckEditBase(baseline)
    if not baseline then return true end
    local current=Audit.CaptureEditBase(baseline.raidId,baseline.keys)
    if not current or not Raider.Services.RaidJournal.Equal(baseline.heads,current.heads) then
        return false,"Raid data changed. Draft kept.\nReopen the editor to review new values."
    end
    return true
end
function Audit.ImportValue(importInfo)
    importInfo=importInfo or {}
    local value={id=importInfo.id,origin=importInfo.origin,url=importInfo.url or "",unmatched=importInfo.unmatchedReservations or {}}
    if importInfo.customReview and table.getn(importInfo.customReview)>0 then
        value.review={}
        for _,change in ipairs(importInfo.customReview) do
            table.insert(value.review,{name=change.name,kind=change.kind,sourceName=change.sourceName,allowed=change.allowed,
                itemIds=change.itemIds and ReserveItems(change.itemIds),optOut=change.optOut})
        end
    end
    if type(importInfo.rollForExport)=="string" and importInfo.rollForExport~="" then
        value.exportChunks={}
        for offset=1,string.len(importInfo.rollForExport),4096 do table.insert(value.exportChunks,string.sub(importInfo.rollForExport,offset,offset+4095)) end
    end
    return value
end
function Audit.Reserves(attendance,kind,members,detail,importInfo)
    local changes = {}
    for _, member in ipairs(members or attendance.members or {}) do
        table.insert(changes,{key="sr:"..string.lower(member.name),value=Audit.SRValue(member,attendance)})
    end
    if importInfo then
        table.insert(changes,{key="import:sr",value=Audit.ImportValue(importInfo)})
    end
    return Audit.Commit(attendance,kind,changes,detail)
end
function Audit.Start(attendance)
    local changes = Audit.MemberChanges(attendance.members,attendance,attendance.departedMembers)
    if attendance.softReserveImport then table.insert(changes,{key="import:sr",value=Audit.ImportValue(attendance.softReserveImport)}) end
    table.insert(changes,{key="raid:metadata",value=Audit.Metadata(attendance)})
    table.insert(changes,{key="raid:lifecycle",value="active"})
    table.insert(changes,{key="raid:loot-rules",value=Raider.Database.CopyLootRules(Raider.Database.EnsureRaidLootRules(attendance))})
    table.insert(changes,Recorder("active"))
    AppendEntitlements(changes,attendance)
    return Audit.Commit(attendance,"raid.start",changes,{subject=attendance.snapshotId or "",raidName=attendance.raidName})
end
function Audit.LootValue(member,loot)
    return {recipient=member.name,item=tonumber(loot.itemId) or loot.itemId or loot.name,name=loot.name,link=loot.link,count=loot.count or 1,
        ordinary=loot.ordinaryReceipt==true,historyKey=loot.awardHistoryKey,timestamp=tonumber(loot.timestamp or loot.time)}
end
local function Copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=Copy(item) end;return result
end
local function Item(value)
    if type(value)~="table" then return value end
    return tonumber(value.itemId or value.id) or value.name or value.itemName
end
local function SameItem(left,right)
    if tonumber(left) and tonumber(right) then return tonumber(left)==tonumber(right) end
    return string.lower(tostring(left or ""))==string.lower(tostring(right or ""))
end
local function Records(record)
    local db=Store();local journal=Raider.Services.RaidJournal
    local raid=record.syncRaidId and db.raidJournal.raids[record.syncRaidId]
    local result={}
    for key in pairs(raid and raid.records or {}) do
        local value=journal.GetRecord(db,record.syncRaidId,key)
        if value and not value.deleted then result[key]=value.value end
    end
    return result,db
end
local function FindAllocation(candidates,used,recipient,item,anyRecipient)
    for _,candidate in ipairs(candidates) do
        if not used[candidate.id] and SameItem(candidate.item,item)
            and (anyRecipient or string.lower(candidate.recipient)==string.lower(recipient)) then return candidate.id end
    end
end
local function CanonicalAllocations(records)
    local result={}
    for key,value in pairs(records) do
        if string.sub(key,1,5)=="loot:" then table.insert(result,{id=string.sub(key,6),recipient=value.recipient,item=value.item}) end
    end
    table.sort(result,function(a,b)return a.id<b.id end);return result
end

-- Stage historical edits against the same SR/member/allocation identities used
-- by live edits. Saved-only fields remain in saved:member; their parallel copy
-- is never allowed to overwrite a newer canonical SR simply because Save ran.
function Audit.PrepareSavedMemberChanges(record,members,changes)
    local prepared=Copy(members)
    local canonical,db=Records(record)
    local journal=Raider.Services.RaidJournal
    local current,candidates,matchedOld={},{},{}
    local available=CanonicalAllocations(canonical)
    for _,member in ipairs(record.members or {}) do
        local name=string.lower(member.name or "");current[name]=member
        for _,loot in ipairs(member.lootItems or {}) do
            local id=loot.syncRecordId or FindAllocation(available,matchedOld,member.name,Item(loot))
            if id then
                matchedOld[id]=true
                table.insert(candidates,{id=id,recipient=member.name,item=Item(loot)})
            end
        end
    end
    local used,changedLoot={},{}
    -- Reserve explicit identities before matching rows whose editor omitted IDs.
    for _,member in ipairs(prepared) do
        for _,loot in ipairs(member.lootItems or {}) do
            if loot.syncRecordId then
                if used[loot.syncRecordId] then return nil,"One loot allocation cannot occur twice in the saved raid." end
                used[loot.syncRecordId]=true
            end
        end
    end
    for _,member in ipairs(prepared) do
        local name=string.lower(member.name or "")
        local previous=current[name]
        local sr=canonical["sr:"..name]
        if not previous or not sr or not journal.Equal(previous.srItems or {},member.srItems or {}) then
            local items={}
            for _,item in ipairs(member.srItems or {}) do
                local reference=Item(item)
                if reference==nil then return nil,"Every saved SR needs an item name or ID." end
                table.insert(items,reference)
            end
            local value=Copy(sr or {})
            value.name=member.name;value.items=items;value.exception=sr and sr.exception==true or false
            value.optOut=nil
            value.sourceName=table.getn(items)>0 and (value.sourceName or member.name) or nil;value.custom=value.custom or {}
            value.custom.items={itemIds=Copy(items),sourceName=value.sourceName}
            table.insert(changes,{key="sr:"..name,value=value})
        end
        if not previous or not canonical["member:"..name] or previous.class~=member.class or previous.guildRank~=member.guildRank then
            local value=Copy(canonical["member:"..name] or {})
            value.name=member.name;value.class=member.class or "";value.guildRank=member.guildRank or ""
            if member.classFile then value.classFile=member.classFile
            elseif previous and previous.class~=member.class then value.classFile=string.upper(tostring(member.class or "")) end
            table.insert(changes,{key="member:"..name,value=value})
        end
        local edited=not previous or not journal.Equal(previous.lootItems or {},member.lootItems or {})
        changedLoot[name]=edited
        for _,loot in ipairs(member.lootItems or {}) do
            if not loot.syncRecordId then
                loot.syncRecordId=FindAllocation(candidates,used,member.name,Item(loot))
                    or FindAllocation(candidates,used,member.name,Item(loot),true)
                    or journal.NewRecordId(db)
                used[loot.syncRecordId]=true
            end
            local existing=canonical["loot:"..loot.syncRecordId]
            if edited or not existing then
                local value=Copy(existing or {})
                local item=Item(loot)
                value.recipient=member.name;value.item=item
                value.name=loot.name or (existing and SameItem(existing.item,item) and existing.name or nil)
                if existing and not SameItem(existing.item,item) then value.link=nil end
                value.count=tonumber(loot.count) or 1;value.ordinary=existing and existing.ordinary==true or false
                if not existing then value.timestamp=loot.timestamp end
                table.insert(changes,{key="loot:"..loot.syncRecordId,value=value})
            end
        end
    end
    for _,candidate in ipairs(candidates) do
        if not used[candidate.id] and changedLoot[string.lower(candidate.recipient)] then
            table.insert(changes,{key="loot:"..candidate.id,deleted=true})
        end
    end
    return prepared
end

local function PrepareLiveLoot(attendance,changes)
    local canonical,db=Records(attendance)
    local candidates=CanonicalAllocations(canonical)
    local used,names,pending,ids,explicit={},{},{},{},{}
    for _,group in ipairs({attendance.members or {},attendance.departedMembers or {}}) do
        for _,member in ipairs(group) do
            for _,loot in ipairs(member.loot or {}) do if loot.syncRecordId then explicit[loot.syncRecordId]=true end end
        end
    end
    local unavailable=Copy(explicit)
    for _,group in ipairs({attendance.members or {},attendance.departedMembers or {}}) do
        for _,member in ipairs(group) do
            local name=string.lower(member.name or "")
            if not names[name] then
                names[name]=true;ids[name]={}
                for index,loot in ipairs(member.loot or {}) do
                    local id=loot.syncRecordId or FindAllocation(candidates,unavailable,member.name,loot.itemId or loot.name)
                        or Raider.Services.RaidJournal.NewRecordId(db)
                    if used[id] then return nil,"One loot allocation cannot occur twice in a raid." end
                    used[id]=true;unavailable[id]=true;ids[name][index]=id
                    table.insert(changes,{key="loot:"..id,value=Audit.LootValue(member,loot)})
                    table.insert(pending,{loot=loot,id=id})
                end
            end
        end
    end
    return {pending=pending,ids=ids}
end
local function PublishLootIds(prepared,entry,snapshot)
    for _,value in ipairs(prepared.pending) do value.loot.syncRecordId=value.id;value.loot.auditFailure=nil end
    for _,member in ipairs(entry and entry.members or {}) do
        local ids=prepared.ids[string.lower(member.name or "")] or {}
        for index,loot in ipairs(member.lootItems or {}) do if ids[index] then loot.syncRecordId=ids[index] end end
    end
    for _,group in ipairs({snapshot and snapshot.members or {},snapshot and snapshot.departedMembers or {}}) do
        for _,member in ipairs(group) do
            local ids=prepared.ids[string.lower(member.name or "")] or {}
            for index,loot in ipairs(member.loot or {}) do if ids[index] then loot.syncRecordId=ids[index];loot.auditFailure=nil end end
        end
    end
end
function Audit.Loot(attendance,member,loot,kind,visible)
    if IsTest() then return true end
    if not loot.syncRecordId then loot.syncRecordId=Raider.Services.RaidJournal.NewRecordId(Store()) end
    return Audit.Commit(attendance,kind,{{key="loot:"..loot.syncRecordId,value=Audit.LootValue(member,loot)},
        {key="entitlement:"..string.lower(member.name),value=Audit.EntitlementValue(member)}},
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
    AppendEntitlements(changes,attendance,true)
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
    table.insert(changes,{key="entitlement:"..string.lower(recipient.name),value=Audit.EntitlementValue(recipient)})
    return Audit.Commit(attendance,"loot.correct",changes,{subject=recipient.name,item=loot.name or loot.itemId})
end
local function ReplaceSavedContent(attendance,changes)
    local included={}
    for _,change in ipairs(changes) do included[change.key]=true end
    local db=Store()
    local raid=attendance.syncRaidId and db.raidJournal.raids[attendance.syncRaidId]
    for key,record in pairs(raid and raid.records or {}) do
        -- An explicit replacement must not resurrect the destination's former
        -- roster/loot on projection. Archive choices keep their saved identity.
        local content=key=="import:sr" or string.find(key,"^member:") or string.find(key,"^sr:")
            or string.find(key,"^loot:") or string.find(key,"^entitlement:")
            or string.find(key,"^saved:member:") or string.find(key,"^allocation:")
        if content and not included[key] and not record.deleted then table.insert(changes,{key=key,deleted=true}) end
    end
end
function Audit.Save(attendance,entry,snapshot,endSession,copySource)
    local changes=Audit.MemberChanges(attendance.members,attendance,attendance.departedMembers)
    if attendance.softReserveImport then table.insert(changes,{key="import:sr",value=Audit.ImportValue(attendance.softReserveImport)}) end
    local prepared,reason=PrepareLiveLoot(attendance,changes)
    if not prepared then return false,reason end
    AppendEntitlements(changes,attendance)
    table.insert(changes,{key="raid:metadata",value=Audit.Metadata(attendance)})
    table.insert(changes,Recorder(endSession and "ended" or "active"))
    local db=Store()
    local raid=attendance.syncRaidId and db.raidJournal.raids[attendance.syncRaidId]
    if copySource or not raid then
        table.insert(changes,{key="raid:loot-rules",value=Copy(attendance.lootRules or {})})
    end
    if endSession or copySource or not raid or not raid.records["raid:lifecycle"] then
        table.insert(changes,{key="raid:lifecycle",value=(endSession or attendance.syncEnded) and "ended" or "active"})
    end
    table.insert(changes,{key="raid:save",value=attendance.saveOptions or {}})
    table.insert(changes,{key="saved:snapshot",value=true})
    table.insert(changes,{key="saved:statistic",value=attendance.saveOptions and (attendance.saveOptions.saveRaidStatistics or attendance.saveOptions.saveCSR) or false})
    if entry then
        table.insert(changes,{key="saved:flags",value={attendanceEnabled=entry.attendanceEnabled,csrEnabled=entry.csrEnabled}})
        for _,member in ipairs(entry.members or {}) do
            local lootItems=Copy(member.lootItems)
            local ids=prepared.ids[string.lower(member.name or "")] or {}
            for index,loot in ipairs(lootItems or {}) do if ids[index] then loot.syncRecordId=ids[index] end end
            table.insert(changes,{key="saved:member:"..string.lower(member.name),value={name=member.name,class=member.class,guildRank=member.guildRank,
                lootRank=member.lootRank,attendance=member.attendance,joinedAt=member.joinedAt,leftAt=member.leftAt,srItems=member.srItems,lootItems=lootItems}})
        end
    end
    if copySource then ReplaceSavedContent(attendance,changes) end
    local disabledCopy=copySource and not attendance.syncRaidId and db.raidSyncDisabled and db.raidSyncDisabled[copySource.syncRaidId]
    if disabledCopy then db.raidSyncDisabled[Audit.EnsureIdentity(attendance)]=true end
    local ok,operation=Audit.Commit(attendance,"raid.save",changes,{subject=attendance.snapshotId or "",
        endSession=endSession and true or nil,saveAs=copySource and true or nil})
    if disabledCopy then
        if ok then db.raidSyncPolicyRevision=(db.raidSyncPolicyRevision or 0)+1
        else db.raidSyncDisabled[attendance.syncRaidId]=nil end
    end
    if ok then
        PublishLootIds(prepared,entry,snapshot)
        attendance.syncLocalAuditFailure=nil
        for _,group in ipairs({attendance.members or {},attendance.departedMembers or {}}) do
            for _,member in ipairs(group) do member.entitlementAuditFailure=nil end
        end
    end
    return ok,operation
end
function Audit.StartFromSnapshot(attendance)
    local changes=Audit.MemberChanges(attendance.members,attendance,attendance.departedMembers)
    if attendance.softReserveImport then table.insert(changes,{key="import:sr",value=Audit.ImportValue(attendance.softReserveImport)}) end
    local prepared,reason=PrepareLiveLoot(attendance,changes)
    if not prepared then return false,reason end
    AppendEntitlements(changes,attendance)
    table.insert(changes,{key="raid:metadata",value=Audit.Metadata(attendance)})
    table.insert(changes,{key="raid:lifecycle",value="active"})
    table.insert(changes,{key="raid:loot-rules",value=Copy(attendance.lootRules or {})})
    table.insert(changes,Recorder("active"))
    local ok,operation=Audit.Commit(attendance,"raid.start",changes,{subject=attendance.snapshotId})
    if ok then PublishLootIds(prepared) end
    return ok,operation
end
function Audit.Leave(attendance)
    return Audit.Commit(attendance,"raid.leave",{Recorder("ended")},{subject=attendance.snapshotId or ""})
end
function Audit.End(attendance)
    if not attendance or IsTest() then return true end
    -- Ending explicitly chooses lifecycle only; disputed SR/loot remains unresolved.
    local ok,operation=Raider.Services.RaidJournal.Commit(Store(),Audit.EnsureIdentity(attendance),"raid.end",
        {{key="raid:lifecycle",value="ended"},Recorder("ended")},{subject=attendance.snapshotId or ""},true,true)
    local replica=Raider.Runtime and Raider.Runtime.replica
    if ok and operation and replica then replica.OnOperation(operation,"applied",true) end
    return ok,operation
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
    local attendance=Raider.Database.GetRaidAttendance()
    if attendance then attendance.syncLocalAuditFailure=tostring(reason) end
    local runtime=Raider.Runtime
    if runtime and runtime.Print then runtime.Print("Loot recorded, but Raid Log needs attention: "..tostring(reason)) end
end
