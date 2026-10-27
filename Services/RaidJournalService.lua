local Raider = BootyRaider
Raider.Services = Raider.Services or {}
local Journal = {schema = 1}
Raider.Services.RaidJournal = Journal

-- Engineering bounds for one atomic operation, not measured network budgets.
-- No frame, transport, timer, presentation text or game action belongs here.
Journal.limits = {changes = 512, nodes = 32768, depth = 12, bytes = 262144, string = 4096, page = 50}
local contexts = setmetatable({}, {__mode = "k"})
local nextIdentity = 0
local maxCounter = 9007199254740991
local operationKeys = {schema=true,id=true,origin=true,sequence=true,raidId=true,author=true,timestamp=true,kind=true,changes=true,detail=true,audit=true,resolution=true}
local changeKeys = {key=true,base=true,bases=true,before=true,beforeDeleted=true,value=true,deleted=true}
local MakeMarker

local function Finite(value)
    return type(value) == "number" and value == value and value - value == 0
end

local function Integer(value)
    return Finite(value) and value >= 0 and value <= maxCounter and value == math.floor(value)
end
local function PageNumber(value,default,minimum,maximum)
    value=tonumber(value)
    if not Finite(value) then value=default end
    value=math.max(minimum,math.floor(value))
    return maximum and math.min(maximum,value) or value
end

local function Text(value, maximum)
    return type(value) == "string" and string.len(value) > 0 and string.len(value) <= maximum and not string.find(value, "%c")
end

local function Equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not Equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
Journal.Equal = Equal

local function Clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = Clone(entry) end
    return copy
end

local function CopyBounded(value, budget, seen, depth)
    budget.nodes = budget.nodes + 1
    if budget.nodes > Journal.limits.nodes then return nil, "operation-node-limit" end
    local kind = type(value)
    if kind == "nil" or kind == "boolean" then return value end
    if kind == "number" then
        if not Finite(value) then return nil, "invalid-number" end
        return value
    end
    if kind == "string" then
        local length = string.len(value)
        budget.bytes = budget.bytes + length
        if length > Journal.limits.string or budget.bytes > Journal.limits.bytes then return nil, "operation-byte-limit" end
        return value
    end
    if kind ~= "table" or getmetatable(value) then return nil, "non-plain-data" end
    if depth >= Journal.limits.depth then return nil, "operation-depth-limit" end
    if seen[value] then return nil, "cyclic-data" end
    seen[value] = true
    local copy = {}
    for key, entry in pairs(value) do
        if type(key) ~= "string" and not Integer(key) then return nil, "invalid-data-key" end
        local copiedKey, failure = CopyBounded(key, budget, seen, depth + 1)
        if failure then return nil, failure end
        local copiedValue
        copiedValue, failure = CopyBounded(entry, budget, seen, depth + 1)
        if failure then return nil, failure end
        copy[copiedKey] = copiedValue
    end
    seen[value] = nil
    return copy
end

local function Bounded(value)
    return CopyBounded(value, {nodes=0,bytes=0}, {}, 0)
end

-- Deterministic integrity fingerprint, not authentication or a signature.
function Journal.Fingerprint(value)
    local hash,second,length=1,7,0
    local function Feed(text)
        length=length+string.len(text)
        for index=1,string.len(text) do
            local byte=string.byte(text,index)
            local firstValue,secondValue=hash*31+byte,second*131+byte
            hash=firstValue-math.floor(firstValue/2147483647)*2147483647
            second=secondValue-math.floor(secondValue/2147483629)*2147483629
        end
    end
    local function Visit(entry)
        local kind=type(entry)
        if kind=="table" then
            Feed("{");local keys={};for key in pairs(entry) do table.insert(keys,key) end
            table.sort(keys,function(a,b) if type(a)~=type(b) then return type(a)<type(b) end;return a<b end)
            for _,key in ipairs(keys) do Visit(key);Visit(entry[key]) end;Feed("}")
        elseif kind=="string" then Feed("s"..string.len(entry)..":");Feed(entry)
        elseif kind=="number" then Feed("n"..string.format("%.17g",entry)..";")
        elseif kind=="boolean" then Feed(entry and "t" or "f") else Feed("z") end
    end
    Visit(value);return tostring(hash)..":"..tostring(second)..":"..length
end

local function DefaultActor()
    return type(UnitName) == "function" and UnitName("player") or "Unknown"
end

local function Now(context)
    local value = context and context.now
    if type(value) == "function" then value = value() end
    if value == nil then value = type(time) == "function" and time() or 0 end
    if not Finite(value) or value < 0 then return nil, "invalid-clock" end
    return math.floor(value)
end

function Journal.Ensure(db, context)
    if type(db) ~= "table" then return nil, "invalid-database" end
    if context ~= nil then
        if type(context) ~= "table" then return nil, "invalid-context" end
        contexts[db] = context
    end
    context = contexts[db] or {}
    local state = db.raidJournal
    if state ~= nil then
        if type(state) ~= "table" or state.schema ~= Journal.schema or not Text(state.replicaId, 256)
            or not Integer(state.sequence) or not Integer(state.identitySequence)
            or type(state.raids) ~= "table" or type(state.operations) ~= "table" then
            return nil, "unsupported-journal-state"
        end
        return state
    end
    local actor = context.actor or DefaultActor()
    local realm = context.realm or (type(GetRealmName) == "function" and GetRealmName()) or "Unknown"
    if not Text(actor, 96) or not Text(realm, 96) then return nil, "invalid-local-identity" end
    local timestamp, failure = Now(context)
    if not timestamp then return nil, failure end
    nextIdentity = nextIdentity + 1
    local entropy = context.entropy
    if entropy == nil then
        -- Persistent identity + monotonic sequence supplies local uniqueness.
        -- Epoch/random/session salt reduces fresh-install collisions; this is
        -- an identifier, never authentication of a relayed officer.
        entropy = tostring(math.random(1, 100000000)) .. "-" .. tostring(nextIdentity)
    end
    entropy = tostring(entropy)
    if not Text(entropy, 48) then return nil, "invalid-identity-entropy" end
    local identity = "r:" .. string.len(realm) .. ":" .. realm .. ":" .. string.len(actor) .. ":" .. actor .. ":" .. timestamp .. ":" .. entropy
    if not Text(identity, 256) then return nil, "invalid-local-identity" end
    state = {schema=Journal.schema,replicaId=identity,sequence=0,identitySequence=0,raids={},operations={}}
    db.raidJournal = state
    return state
end

local function NewId(db, kind)
    local state, failure = Journal.Ensure(db)
    if not state then return nil, failure end
    if state.identitySequence >= maxCounter then return nil, "identity-sequence-exhausted" end
    state.identitySequence = state.identitySequence + 1
    return state.replicaId .. ":" .. kind .. ":" .. state.identitySequence
end

function Journal.NewRaidId(db) return NewId(db, "raid") end
function Journal.NewRecordId(db) return NewId(db, "record") end

local function Validate(operation)
    local copy, failure = Bounded(operation)
    if failure then return nil, failure end
    if type(copy) ~= "table" then return nil, "invalid-operation" end
    for key in pairs(copy) do if not operationKeys[key] then return nil, "unknown-operation-field" end end
    if copy.schema ~= Journal.schema or not Text(copy.origin, 256) or not Integer(copy.sequence) or copy.sequence < 1
        or copy.id ~= copy.origin .. ":op:" .. copy.sequence or not Text(copy.raidId, 300)
        or not Text(copy.author, 96) or not Integer(copy.timestamp) or not Text(copy.kind, 64)
        or type(copy.audit) ~= "boolean" or type(copy.changes) ~= "table" then return nil, "invalid-operation" end
    local count = table.getn(copy.changes)
    if count < 1 or count > Journal.limits.changes then return nil, "operation-change-limit" end
    for key in pairs(copy.changes) do
        if not Integer(key) or key < 1 or key > count then return nil, "invalid-change-array" end
    end
    local keys = {}
    for index = 1, count do
        local change = copy.changes[index]
        if type(change) ~= "table" then return nil, "invalid-change" end
        for key in pairs(change) do if not changeKeys[key] then return nil, "unknown-change-field" end end
        if not Text(change.key, 256) or keys[change.key] or (change.base ~= nil and not Text(change.base, 300))
            or (change.deleted ~= nil and change.deleted ~= true) or (change.beforeDeleted ~= nil and change.beforeDeleted ~= true)
            or (change.deleted and change.value ~= nil) or (not change.deleted and change.value == nil)
            or (change.beforeDeleted and change.before ~= nil)
            or (change.base == nil and change.bases == nil and (change.before ~= nil or change.beforeDeleted)) then return nil, "invalid-change" end
        if change.bases ~= nil then
            if change.base ~= nil or type(change.bases) ~= "table" or table.getn(change.bases)<1 or table.getn(change.bases)>64 then return nil,"invalid-bases" end
            local previous
            for position=1,table.getn(change.bases) do
                local base=change.bases[position]
                if not Text(base,300) or previous and base<=previous then return nil,"invalid-bases" end
                previous=base
            end
            for position in pairs(change.bases) do if not Integer(position) or position<1 or position>table.getn(change.bases) then return nil,"invalid-bases" end end
        end
        keys[change.key] = true
    end
    if copy.resolution~=nil and copy.resolution~=true then return nil,"invalid-resolution" end
    return copy
end

local function BaseChange(state, id, raidId, key, checkpoint)
    local operation = state.operations[id]
    if not operation then return nil, "missing-dependency" end
    if operation.raidId ~= raidId then return nil, "invalid-dependency" end
    if operation.compacted and not checkpoint then return nil,"checkpoint-required" end
    for _, change in ipairs(operation.changes) do if change.key == key then return change end end
    return nil, "invalid-dependency"
end

function Journal.Apply(db, operation, checkpoint)
    local incoming, failure = Validate(operation)
    if not incoming then return false, failure end
    local state
    state, failure = Journal.Ensure(db)
    if not state then return false, failure end
    local conflicts=Raider.Services.RaidConflict
    if conflicts then conflicts.Ensure(state) end
    local existing = state.operations[incoming.id]
    if existing then
        if existing.compacted then
            if incoming.audit or not Equal(existing,MakeMarker(incoming)) then return false,"operation-id-collision" end
            state.operations[incoming.id]=incoming
            if conflicts then conflicts.Refresh(state,state.raids[incoming.raidId]) end
            return true,"restored"
        end
        if Equal(existing, incoming) then return true, "duplicate" end
        return false, "operation-id-collision"
    end
    local raid = state.raids[incoming.raidId]
    if raid and (type(raid.records) ~= "table" or type(raid.log) ~= "table" or not Integer(raid.logRevision)) then return false, "invalid-raid-state" end
    local remembered={}
    for _, change in ipairs(incoming.changes) do
        local current = raid and raid.records[change.key]
        if change.base then
            local base
            base, failure = BaseChange(state, change.base, incoming.raidId, change.key, checkpoint)
            if not base then return false, failure end
            if base.valueFingerprint then
                if base.valueFingerprint~=Journal.Fingerprint(change.before) or base.deleted~=change.beforeDeleted then return false,"invalid-before-value" end
                if conflicts then table.insert(remembered,{id=change.base,key=change.key,value=change.before,deleted=change.beforeDeleted}) end
            elseif not Equal(base.value, change.before) or base.deleted ~= change.beforeDeleted then return false, "invalid-before-value" end
        end
        if change.bases then
            if not conflicts then return false,"unsupported-causal-bases" end
            for _,id in ipairs(change.bases) do
                local base; base,failure=BaseChange(state,id,incoming.raidId,change.key,checkpoint)
                if not base then return false,failure end
            end
            local base=conflicts.Common(state,change.key,change.bases)
            if base and base.pendingCheckpoint then return false,"checkpoint-required" end
            if not Equal(base and base.value,change.before) or (base and base.deleted)~=change.beforeDeleted then return false,"invalid-before-value" end
        end
        if not conflicts then
            if (current and current.revision or nil) ~= change.base then return false, "conflict" end
            if current and (not Equal(current.value, change.before) or current.deleted ~= change.beforeDeleted) then return false, "invalid-record-state" end
        end
    end
    -- Only publish after every record in the batch has passed validation.
    for _,base in ipairs(remembered) do conflicts.RememberBase(state,base.id,base.key,base.value,base.deleted) end
    if not raid then raid = {records={},log={},logRevision=0}; state.raids[incoming.raidId] = raid end
    state.operations[incoming.id] = incoming
    if conflicts then conflicts.Publish(state,incoming)
    else for _, change in ipairs(incoming.changes) do raid.records[change.key] = {revision=incoming.id,value=change.value,deleted=change.deleted} end end
    if incoming.audit then
        raid.logRevision = raid.logRevision + 1
        raid.log[raid.logRevision] = incoming.id
    end
    if incoming.origin == state.replicaId and incoming.sequence > state.sequence then state.sequence = incoming.sequence end
    if Journal.IndexOperation then Journal.IndexOperation(state,incoming) end
    return true, raid.conflicts and next(raid.conflicts) and "conflict" or "applied"
end

-- The index is transient. Operations are the only durable payload owners;
-- incremental inserts avoid scanning history for every network request.
local syncIndexes=setmetatable({}, {__mode="k"})
local function GroupKey(raidId,origin) return raidId.."\031"..origin end
local function InsertIndex(index,operation)
    local key=GroupKey(operation.raidId,operation.origin)
    local group=index.groups[key]
    if not group then
        group={raidId=operation.raidId,origin=operation.origin,sequences={},ids={},ranges={},high=0}
        index.groups[key]=group;table.insert(index.order,key);table.sort(index.order)
    end
    local sequence=operation.sequence
    if group.ids[sequence] then return end
    index.summary=nil
    group.ids[sequence]=operation.id;group.high=math.max(group.high,sequence)
    local position=table.getn(group.sequences)+1
    while position>1 and group.sequences[position-1]>sequence do position=position-1 end
    table.insert(group.sequences,position,sequence)
    local rangePosition=1
    while group.ranges[rangePosition] and group.ranges[rangePosition][2]<sequence-1 do rangePosition=rangePosition+1 end
    local range=group.ranges[rangePosition]
    if range and range[1]<=sequence+1 then range[1]=math.min(range[1],sequence);range[2]=math.max(range[2],sequence)
    else range={sequence,sequence};table.insert(group.ranges,rangePosition,range) end
    local following=group.ranges[rangePosition+1]
    if following and following[1]<=range[2]+1 then range[2]=following[2];table.remove(group.ranges,rangePosition+1) end
end
local function SyncIndex(state)
    local index=syncIndexes[state]
    if not index then
        index={groups={},order={}};syncIndexes[state]=index
        for _,operation in pairs(state.operations) do InsertIndex(index,operation) end
    end
    return index
end
function Journal.IndexOperation(state,operation)
    local index=syncIndexes[state];if index then InsertIndex(index,operation) end
end
function Journal.GetSyncSummary(db,offset,limit,priorityRaidId)
    local state,reason=Journal.Ensure(db);if not state then return nil,reason end
    local index=SyncIndex(state)
    offset=PageNumber(offset,0,0);limit=PageNumber(limit,8,1,32)
    if not index.summary or index.summary.priorityRaidId~=priorityRaidId then
        local summary={priorityRaidId=priorityRaidId,entries={}}
        for pass=1,2 do
            for _,key in ipairs(index.order) do
                local group=index.groups[key]
                if (pass==1 and group.raidId==priorityRaidId) or (pass==2 and group.raidId~=priorityRaidId) then
                    for _,range in ipairs(group.ranges) do
                        table.insert(summary.entries,{raidId=group.raidId,origin=group.origin,first=range[1],last=range[2],high=group.high})
                    end
                end
            end
        end
        index.summary=summary
    end
    local result={schema=1,entries={},total=table.getn(index.summary.entries)}
    for position=offset+1,math.min(result.total,offset+limit) do table.insert(result.entries,Clone(index.summary.entries[position])) end
    if offset+table.getn(result.entries)<result.total then result.nextOffset=offset+table.getn(result.entries) end
    return result
end
function Journal.GetMissingRanges(db,summary,limit)
    local state,reason=Journal.Ensure(db);if not state then return nil,reason end
    if type(summary)~="table" or summary.schema~=1 or type(summary.entries)~="table" or table.getn(summary.entries)>32 then return nil,"invalid-summary" end
    for position in pairs(summary.entries) do if not Integer(position) or position<1 or position>table.getn(summary.entries) then return nil,"invalid-summary" end end
    local index=SyncIndex(state);local result={};limit=PageNumber(limit,16,1,64)
    for position=1,table.getn(summary.entries) do
        local remote=summary.entries[position]
        if type(remote)~="table" or not Text(remote.raidId,300) or not Text(remote.origin,256) or not Integer(remote.first) or remote.first<1 or not Integer(remote.last) or remote.last<remote.first then return nil,"invalid-summary" end
        local group=index.groups[GroupKey(remote.raidId,remote.origin)]
        local cursor=remote.first
        for _,range in ipairs(group and group.ranges or {}) do
            if range[1]>cursor then
                table.insert(result,{raidId=remote.raidId,origin=remote.origin,first=cursor,last=math.min(remote.last,range[1]-1)})
                if table.getn(result)>=limit then return result end
            end
            if range[2]>=cursor then cursor=range[2]+1 end
            if cursor>remote.last then break end
        end
        if cursor<=remote.last then
            table.insert(result,{raidId=remote.raidId,origin=remote.origin,first=cursor,last=remote.last})
            if table.getn(result)>=limit then return result end
        end
    end
    return result
end
function Journal.GetOperationRange(db,raidId,origin,first,limit,last)
    local state,reason=Journal.Ensure(db);if not state then return nil,reason end
    if not Text(raidId,300) or not Text(origin,256) or not Integer(first) or first<1 then return nil,"invalid-range" end
    local group=SyncIndex(state).groups[GroupKey(raidId,origin)]
    if not group then return {},nil,0 end
    limit=PageNumber(limit,1,1,32);last=tonumber(last) or group.high
    if not Integer(last) or last<first then return nil,"invalid-range" end
    local lo,hi=1,table.getn(group.sequences)+1
    while lo<hi do local middle=math.floor((lo+hi)/2);if group.sequences[middle] and group.sequences[middle]<first then lo=middle+1 else hi=middle end end
    local result={};local nextSequence
    while group.sequences[lo] and group.sequences[lo]<=last and table.getn(result)<limit do
        local sequence=group.sequences[lo]
        table.insert(result,Clone(state.operations[group.ids[sequence]]));nextSequence=sequence+1;lo=lo+1
    end
    return result,nextSequence,group.high
end

function Journal.IsCheckpointOperation(db,operation)
    if operation.compacted then return true end
    local state=Journal.Ensure(db);if not state then return false end
    for _,change in ipairs(operation.changes or {}) do
        for _,id in ipairs(change.bases or (change.base and {change.base} or {})) do
            if state.operations[id] and state.operations[id].compacted then return true end
        end
    end
    return false
end

MakeMarker=function(operation)
    local marker={schema=operation.schema,id=operation.id,origin=operation.origin,sequence=operation.sequence,raidId=operation.raidId,
        author=operation.author,timestamp=operation.timestamp,kind=operation.kind,audit=false,compacted=true,
        fingerprint=Journal.Fingerprint(operation),changes={}}
    for _,change in ipairs(operation.changes) do
        table.insert(marker.changes,{key=change.key,base=change.base,bases=Clone(change.bases),deleted=change.deleted,valueFingerprint=Journal.Fingerprint(change.value)})
    end
    return marker
end
local function RetainedSize(value)
    local kind=type(value)
    if kind=="string" then return string.len(value)+16 end
    if kind~="table" then return 8 end
    local size=40
    for key,entry in pairs(value) do size=size+16+RetainedSize(key)+RetainedSize(entry) end
    return size
end

function Journal.ApplyCheckpointEntry(db,entry)
    if type(entry)~="table" then return false,"invalid-checkpoint-entry" end
    if not entry.compacted then return Journal.Apply(db,entry,true) end
    local marker,reason=Bounded(entry)
    if not marker then return false,reason end
    local fields={schema=true,id=true,origin=true,sequence=true,raidId=true,author=true,timestamp=true,kind=true,audit=true,compacted=true,fingerprint=true,changes=true}
    for key in pairs(marker) do if not fields[key] then return false,"invalid-checkpoint-marker" end end
    if marker.schema~=1 or marker.compacted~=true or marker.audit~=false or not Text(marker.fingerprint,100)
        or not Text(marker.origin,256) or not Integer(marker.sequence) or marker.sequence<1
        or marker.id~=marker.origin..":op:"..marker.sequence or not Text(marker.raidId,300)
        or not Text(marker.author,96) or not Integer(marker.timestamp) or not Text(marker.kind,64)
        or type(marker.changes)~="table" or table.getn(marker.changes)<1 or table.getn(marker.changes)>Journal.limits.changes then return false,"invalid-checkpoint-marker" end
    local changeCount=table.getn(marker.changes)
    for key in pairs(marker.changes) do if not Integer(key) or key<1 or key>changeCount then return false,"invalid-checkpoint-marker" end end
    local state;state,reason=Journal.Ensure(db);if not state then return false,reason end
    local existing=state.operations[marker.id]
    if existing then
        local expected=existing.compacted and existing or (not existing.audit and MakeMarker(existing))
        if not expected or not Equal(expected,marker) then return false,"operation-id-collision" end
        return true,"duplicate"
    end
    local keys={}
    for position=1,changeCount do
        local change=marker.changes[position]
        if type(change)~="table" then return false,"invalid-checkpoint-marker" end
        for key in pairs(change) do if key~="key" and key~="base" and key~="bases" and key~="deleted" and key~="valueFingerprint" then return false,"invalid-checkpoint-marker" end end
        if not Text(change.key,256) or keys[change.key] or not Text(change.valueFingerprint,100)
            or change.value~=nil or change.before~=nil or (change.deleted~=nil and change.deleted~=true)
            or change.base and change.bases then return false,"invalid-checkpoint-marker" end
        keys[change.key]=true
        local parents=change.bases or (change.base and {change.base} or {})
        if type(parents)~="table" or table.getn(parents)>64 or change.bases and table.getn(parents)<1 then return false,"invalid-checkpoint-marker" end
        for key in pairs(parents) do if not Integer(key) or key<1 or key>table.getn(parents) then return false,"invalid-checkpoint-marker" end end
        local previous
        for _,id in ipairs(parents) do
            if not Text(id,300) or previous and previous>=id then return false,"invalid-checkpoint-marker" end
            local parent=state.operations[id]
            if not parent then return false,"missing-dependency" end
            if parent.raidId~=marker.raidId then return false,"invalid-dependency" end
            local touchesKey=false
            for _,parentChange in ipairs(parent.changes) do if parentChange.key==change.key then touchesKey=true;break end end
            if not touchesKey then return false,"invalid-dependency" end
            previous=id
        end
    end
    local conflicts=Raider.Services.RaidConflict
    if not conflicts then return false,"checkpoint-engine-unavailable" end
    conflicts.Ensure(state)
    if not state.raids[marker.raidId] then state.raids[marker.raidId]={records={},log={},logRevision=0} end
    state.operations[marker.id]=marker
    conflicts.PublishMarker(state,marker)
    if marker.origin==state.replicaId and marker.sequence>state.sequence then state.sequence=marker.sequence end
    Journal.IndexOperation(state,marker)
    return true,"checkpoint-marker"
end

function Journal.Compact(db,raidId,confirmed)
    local state,reason=Journal.Ensure(db);if not state then return nil,reason end
    local conflicts=Raider.Services.RaidConflict
    if not conflicts then return nil,"checkpoint-engine-unavailable" end
    conflicts.Ensure(state)
    local raid=state.raids[raidId];if not raid then return {compacted=0,retained=0,pendingConfirmation=0} end
    local protected={}
    for _,heads in pairs(raid.heads or {}) do for id in pairs(heads) do protected[id]=true end end
    for _,id in ipairs(raid.log) do protected[id]=true end
    for _,conflict in pairs(raid.conflicts or {}) do for _,id in ipairs(conflict.operationIds or conflict.heads) do protected[id]=true end end
    local direct={};for id in pairs(protected) do direct[id]=true end
    for id in pairs(direct) do
        for _,change in ipairs(state.operations[id].changes) do
            for _,base in ipairs(change.bases or (change.base and {change.base} or {})) do protected[base]=true end
        end
    end
    local report={compacted=0,retained=0,pendingConfirmation=0}
    for _,id in ipairs(raid.operationIds) do
        local operation=state.operations[id]
        local acknowledged=operation.origin~=state.replicaId or type(confirmed)=="table" and (tonumber(confirmed[operation.origin]) or 0)>=operation.sequence
        if not protected[id] and not operation.compacted and not operation.audit and not acknowledged then report.pendingConfirmation=report.pendingConfirmation+1 end
        if not protected[id] and not operation.compacted and not operation.audit and acknowledged then
            local marker=MakeMarker(operation)
            -- Small scalar observations can cost less than a causal marker.
            -- This estimate decides whether to compact, never claims native RAM.
            if RetainedSize(marker)<RetainedSize(operation) then
                state.operations[id]=marker;report.compacted=report.compacted+1
            else report.retained=report.retained+1 end
        else report.retained=report.retained+1 end
    end
    return report
end
function Journal.GetCheckpointPage(db,raidId,offset,limit)
    local state,reason=Journal.Ensure(db);if not state then return nil,reason end
    local conflicts=Raider.Services.RaidConflict;if not conflicts then return nil,"checkpoint-engine-unavailable" end;conflicts.Ensure(state)
    local raid=state.raids[raidId];local ids=raid and raid.operationIds or {}
    offset=PageNumber(offset,0,0);limit=PageNumber(limit,4,1,8)
    local page={schema=1,raidId=raidId,entries={},total=table.getn(ids)}
    for index=offset+1,math.min(page.total,offset+limit) do table.insert(page.entries,Clone(state.operations[ids[index]])) end
    if offset+table.getn(page.entries)<page.total then page.nextOffset=offset+table.getn(page.entries) end
    return page
end

function Journal.Commit(db, raidId, kind, changes, detail, audit, resolving)
    if not Text(raidId, 300) or not Text(kind, 64) or type(changes) ~= "table" then return false, "invalid-commit" end
    local supplied, failure = Bounded(changes)
    if not supplied then return false, failure end
    local count = table.getn(supplied)
    if count > Journal.limits.changes then return false, "operation-change-limit" end
    for key in pairs(supplied) do
        if not Integer(key) or key < 1 or key > count then return false, "invalid-change-array" end
    end
    local state
    state, failure = Journal.Ensure(db)
    if not state then return false, failure end
    local conflicts=Raider.Services.RaidConflict
    if conflicts then conflicts.Ensure(state) end
    local raid, keys, batch = state.raids[raidId], {}, {}
    for index = 1, count do
        local change = supplied[index]
        if type(change) ~= "table" or not Text(change.key, 256) or keys[change.key]
            or (change.deleted ~= nil and change.deleted ~= true)
            or (change.deleted and change.value ~= nil) or (not change.deleted and change.value == nil) then return false, "invalid-change" end
        for key in pairs(change) do if key ~= "key" and key ~= "value" and key ~= "deleted" then return false, "unknown-commit-field" end end
        keys[change.key] = true
        local current = raid and raid.records[change.key]
        if current and current.conflicted and not resolving then return false,"conflict-requires-resolution" end
        local unchanged = current and current.deleted == change.deleted and Equal(current.value, change.value)
        if not current and change.deleted then unchanged = true end
        if not unchanged or resolving then
            local heads=raid and raid.heads and raid.heads[change.key]
            local bases={};for id in pairs(heads or {}) do table.insert(bases,id) end;table.sort(bases)
            local baseValue=current
            if table.getn(bases)>0 then baseValue=conflicts.Common(state,change.key,bases) end
            local entry={key=change.key,base=table.getn(bases)==1 and bases[1] or (not heads and current and current.revision or nil),
                before=baseValue and baseValue.value,beforeDeleted=baseValue and baseValue.deleted,
                value=change.value,deleted=change.deleted}
            if table.getn(bases)>1 then entry.bases=bases;entry.base=nil end
            table.insert(batch,entry)
        end
    end
    if table.getn(batch) == 0 then return true, nil end
    local context = contexts[db] or {}
    local author = context.actor or DefaultActor()
    if not Text(author, 96) then return false, "invalid-author" end
    local timestamp
    timestamp, failure = Now(context)
    if not timestamp then return false, failure end
    if state.sequence >= maxCounter then return false, "sequence-exhausted" end
    local sequence = state.sequence + 1
    local operation = {schema=Journal.schema,id=state.replicaId .. ":op:" .. sequence,origin=state.replicaId,
        sequence=sequence,raidId=raidId,author=author,timestamp=timestamp,kind=kind,changes=batch,detail=detail,audit=audit ~= false,resolution=resolving and true or nil}
    local applied
    applied, failure = Journal.Apply(db, operation)
    if not applied then return false, failure end
    return true, Clone(state.operations[operation.id])
end

function Journal.GetRecord(db, raidId, key)
    local state, failure = Journal.Ensure(db)
    if not state then return nil, failure end
    local raid = state.raids[raidId]
    return raid and Clone(raid.records[key]) or nil
end

function Journal.GetOperation(db, id)
    local state, failure = Journal.Ensure(db)
    if not state then return nil, failure end
    return Clone(state.operations[id])
end

function Journal.GetRevision(db, raidId)
    local state, failure = Journal.Ensure(db)
    if not state then return nil, failure end
    local raid = state.raids[raidId]
    return raid and (raid.logRevision+(raid.logStatusRevision or 0)) or 0
end

function Journal.GetChange(db, operationId, index)
    local state, failure = Journal.Ensure(db)
    if not state then return nil, failure end
    local operation = state.operations[operationId]
    if not operation then return nil, 0 end
    local count = table.getn(operation.changes)
    if not Integer(index) or index < 1 or index > count then return nil, count end
    local change=Clone(operation.changes[index])
    local conflicts=Raider.Services.RaidConflict
    change.status=conflicts and conflicts.AuditStatus(state,state.raids[operation.raidId],operationId,change.key) or "accepted"
    change.operationStatus=conflicts and conflicts.AuditStatus(state,state.raids[operation.raidId],operationId) or "accepted"
    return change, count
end

local function PageBounds(total, offset, limit)
    offset, limit = tonumber(offset), tonumber(limit)
    if not Finite(offset) then offset = 0 end
    if not Finite(limit) then limit = 25 end
    offset = math.max(0, math.floor(offset))
    limit = math.max(1, math.min(Journal.limits.page, math.floor(limit)))
    local first = math.max(0, total - offset)
    return first, math.max(1, first - limit + 1)
end

function Journal.GetLogSummary(db, raidId, offset, limit)
    local state, failure = Journal.Ensure(db)
    if not state then return nil, failure end
    local raid = state.raids[raidId]
    if not raid then return {}, 0 end
    local total, page = raid.logRevision, {}
    local first, last = PageBounds(total, offset, limit)
    for index = first, last, -1 do
        local operation = state.operations[raid.log[index]]
        local conflicts=Raider.Services.RaidConflict
        table.insert(page, {id=operation.id,raidId=operation.raidId,author=operation.author,
            timestamp=operation.timestamp,kind=operation.kind,detail=Clone(operation.detail),
            changeCount=table.getn(operation.changes),status=conflicts and conflicts.AuditStatus(state,raid,operation.id) or "accepted"})
    end
    return page, total
end

function Journal.GetLog(db, raidId, offset, limit)
    local state, failure = Journal.Ensure(db)
    if not state then return nil, failure end
    local raid = state.raids[raidId]
    if not raid then return {}, 0 end
    local total, page = raid.logRevision, {}
    local first, last = PageBounds(total, offset, limit)
    for index = first, last, -1 do
        table.insert(page, Clone(state.operations[raid.log[index]]))
    end
    return page, total
end
