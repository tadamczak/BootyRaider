local Raider=BootyRaider
local J=Raider.Services.RaidJournal
local C={}
Raider.Services.RaidConflict=C
local compactBases=setmetatable({}, {__mode="k"})
local initialized=setmetatable({}, {__mode="k"})
local auditIndexes=setmetatable({}, {__mode="k"})
function C.RememberBase(state,id,key,value,deleted)
    local cache=compactBases[state] or {};compactBases[state]=cache
    cache[id]=cache[id] or {};cache[id][key]={revision=id,value=value,deleted=deleted}
end
local function Copy(value)
    if type(value)~="table" then return value end
    local out={};for key,entry in pairs(value) do out[key]=Copy(entry) end;return out
end
local function Sorted(set)
    local result={};for key in pairs(set or {}) do table.insert(result,key) end;table.sort(result);return result
end
local function Parents(change)
    if change.bases then return change.bases end
    return change.base and {change.base} or {}
end
local function Change(state,id,key)
    local operation=state.operations[id]
    if operation then for _,change in ipairs(operation.changes) do if change.key==key then return change end end end
end
local function Ancestors(state,id,key,result)
    local pending={id}
    while table.getn(pending)>0 do
        local current=table.remove(pending)
        if not result[current] then
            result[current]=true
            local change=Change(state,current,key)
            if change then for _,parent in ipairs(Parents(change)) do if not result[parent] then table.insert(pending,parent) end end end
        end
    end
end
local function Record(state,key,id)
    local change=Change(state,id,key)
    if change and change.valueFingerprint then
        local cache=compactBases[state]
        return cache and cache[id] and cache[id][key] or {revision=id,deleted=change.deleted,pendingCheckpoint=not change.deleted and true or nil}
    end
    return change and {revision=id,value=change.value,deleted=change.deleted} or nil
end
local function AuditIndex(state,raid)
    local result={pending={},changes={}}
    for _,conflict in pairs(raid.conflicts or {}) do
        for _,id in ipairs(conflict.operationIds or conflict.heads) do result.pending[id]=true end
    end
    -- A later accepted resolution decides which earlier resolution has effect.
    -- Rejected resolutions only supply weak rejection defaults, so an accepted
    -- sibling's explicit choice remains authoritative for their shared parents.
    for position=table.getn(raid.operationIds or {}),1,-1 do
        local id=raid.operationIds[position];local operation=state.operations[id]
        if operation.resolution and not result.pending[id] then
            for _,change in ipairs(operation.changes) do
                local own=result.changes[id] and result.changes[id][change.key]
                local rejected=own and own.status=="rejected"
                for _,parent in ipairs(Parents(change)) do
                    local value=Record(state,change.key,parent)
                    local status=not rejected and value and value.deleted==change.deleted and J.Equal(value.value,change.value) and "accepted" or "rejected"
                    local strength=rejected and 1 or 2
                    result.changes[parent]=result.changes[parent] or {}
                    local previous=result.changes[parent][change.key]
                    if not previous or strength>previous.strength then result.changes[parent][change.key]={status=status,strength=strength} end
                end
            end
        end
    end
    return result
end
local function RefreshAuditIndex(state,raid)
    local previous=auditIndexes[raid]
    local current=AuditIndex(state,raid)
    if previous and not J.Equal(previous,current) then raid.logStatusRevision=(raid.logStatusRevision or 0)+1 end
    auditIndexes[raid]=current
end
function C.AuditStatus(state,raid,id,key)
    if not raid then return "accepted" end
    local index=auditIndexes[raid]
    if not index then index=AuditIndex(state,raid);auditIndexes[raid]=index end
    if index.pending[id] then return "pending" end
    local changes=index.changes[id]
    if not changes then return "accepted" end
    if key then return changes[key] and changes[key].status or "accepted" end
    local accepted,rejected=false,false
    for _,change in ipairs(state.operations[id].changes) do
        if changes[change.key] and changes[change.key].status=="rejected" then rejected=true else accepted=true end
    end
    return rejected and (accepted and "partial" or "rejected") or "accepted"
end
function C.Common(state,key,heads)
    if table.getn(heads)==0 then return nil end
    local first=Record(state,key,heads[1]);local same=true
    for index=2,table.getn(heads) do
        local value=Record(state,key,heads[index])
        if not value or not first or value.pendingCheckpoint or first.pendingCheckpoint or value.deleted~=first.deleted or not J.Equal(value.value,first.value) then same=false;break end
    end
    if same then return first end
    local common={};Ancestors(state,heads[1],key,common)
    for index=2,table.getn(heads) do
        local ancestors={};Ancestors(state,heads[index],key,ancestors)
        for id in pairs(common) do if not ancestors[id] then common[id]=nil end end
    end
    -- Common ancestry is closed under parents. Only direct parents need to be
    -- removed to find its maximal revisions; avoid pairwise ancestry walks.
    local dominated={};local best={}
    for id in pairs(common) do
        local change=Change(state,id,key)
        for _,parent in ipairs(change and Parents(change) or {}) do dominated[parent]=true end
    end
    for id in pairs(common) do if not dominated[id] then table.insert(best,id) end end
    table.sort(best)
    if table.getn(best)==0 then return nil end
    local value=Record(state,key,best[1])
    for index=2,table.getn(best) do
        local other=Record(state,key,best[index])
        if not other or not value then return nil end
        if other.pendingCheckpoint or value.pendingCheckpoint then return {pendingCheckpoint=true} end
        if other.deleted~=value.deleted or not J.Equal(other.value,value.value) then return C.Common(state,key,best) end
    end
    return value
end
local function AddHeads(raid,operation)
    raid.heads=raid.heads or {};raid.operationIds=raid.operationIds or {}
    table.insert(raid.operationIds,operation.id)
    for _,change in ipairs(operation.changes) do
        local heads=raid.heads[change.key] or {};raid.heads[change.key]=heads
        for _,parent in ipairs(Parents(change)) do heads[parent]=nil end
        heads[operation.id]=true
    end
end
local function Rebuild(state,raid)
    if not auditIndexes[raid] then auditIndexes[raid]=AuditIndex(state,raid) end
    local blocked,links,disputed={},{},{}
    for key,heads in pairs(raid.heads) do
        local ids=Sorted(heads)
        local first=Record(state,key,ids[1]);local different=false
        for index=2,table.getn(ids) do
            local other=Record(state,key,ids[index])
            if other.deleted~=first.deleted or not J.Equal(other.value,first.value) then different=true;break end
        end
        if different then
            disputed[key]=true
            local base=C.Common(state,key,ids)
            local branch={}
            local pending=Copy(ids)
            while table.getn(pending)>0 do
                local id=table.remove(pending)
                if not branch[id] and not (base and id==base.revision) then
                    branch[id]=true
                    local change=Change(state,id,key)
                    for _,parent in ipairs(change and Parents(change) or {}) do table.insert(pending,parent) end
                end
            end
            local root=ids[1]
            for id in pairs(branch) do
                blocked[id]=true;links[id]=links[id] or {};links[root]=links[root] or {}
                links[id][root]=true;links[root][id]=true
            end
        end
    end
    for _,id in ipairs(raid.operationIds) do
        local operation=state.operations[id]
        for _,change in ipairs(operation.changes) do
            for _,parent in ipairs(Parents(change)) do
                if blocked[parent] then
                    blocked[id]=true;links[id]=links[id] or {};links[parent]=links[parent] or {}
                    links[id][parent]=true;links[parent][id]=true
                end
            end
        end
    end
    raid.conflicts={}
    local visited={}
    for _,root in ipairs(Sorted(blocked)) do
        if not visited[root] then
            local stack={root};local component,keys={},{ }
            while table.getn(stack)>0 do
                local id=table.remove(stack)
                if not visited[id] then
                    visited[id]=true;component[id]=true
                    for _,change in ipairs(state.operations[id].changes) do keys[change.key]=true end
                    for peer in pairs(links[id] or {}) do if not visited[peer] then table.insert(stack,peer) end end
                end
            end
            local ids=Sorted(component)
            local frontier={}
            for key in pairs(keys) do for id in pairs(raid.heads[key] or {}) do frontier[id]=true end end
            -- Variants stay owned by immutable operations. The conflict index
            -- stores causal identity only; UI reads one requested value lazily.
            local conflict={id=ids[1],heads=Sorted(frontier),operationIds=ids,keys=Sorted(keys)}
            raid.conflicts[conflict.id]=conflict
        end
    end
    raid.records={}
    for key,heads in pairs(raid.heads) do
        local candidates={};local seen={};local hadBlocked=false
        local pending=Sorted(heads)
        while table.getn(pending)>0 do
            local id=table.remove(pending)
            if not seen[id] then
                seen[id]=true
                if blocked[id] then
                    hadBlocked=true
                    local change=Change(state,id,key)
                    for _,parent in ipairs(change and Parents(change) or {}) do table.insert(pending,parent) end
                else candidates[id]=true end
            end
        end
        local value=C.Common(state,key,Sorted(candidates))
        if value then value={revision=value.revision,value=value.value,deleted=value.deleted,pendingCheckpoint=value.pendingCheckpoint}
        elseif hadBlocked then value={deleted=true} end
        if value then value.conflicted=hadBlocked and true or nil;value.heads=Sorted(heads);raid.records[key]=value end
    end
    RefreshAuditIndex(state,raid)
end
function C.Ensure(state)
    if initialized[state] then return end
    if state.causalModel~=1 then
        for _,raid in pairs(state.raids) do raid.heads={};raid.operationIds={} end
        local visited={}
        for _,id in ipairs(Sorted(state.operations)) do
            local pending={{id=id}}
            while table.getn(pending)>0 do
                local item=table.remove(pending);local operation=state.operations[item.id]
                if item.expanded then
                    AddHeads(state.raids[operation.raidId],operation)
                elseif not visited[item.id] and operation then
                    visited[item.id]=true;table.insert(pending,{id=item.id,expanded=true})
                    for _,change in ipairs(operation.changes) do for _,parent in ipairs(Parents(change)) do if not visited[parent] then table.insert(pending,{id=parent}) end end end
                end
            end
        end
    end
    for _,operation in pairs(state.operations) do
        if not operation.compacted then
            for _,change in ipairs(operation.changes) do
                if change.base and state.operations[change.base] and state.operations[change.base].compacted then
                    C.RememberBase(state,change.base,change.key,change.before,change.beforeDeleted)
                end
            end
        end
    end
    if state.causalModel~=1 then for _,raid in pairs(state.raids) do Rebuild(state,raid) end end
    state.causalModel=1
    initialized[state]=true
end
function C.Refresh(state,raid) Rebuild(state,raid) end
function C.PublishMarker(state,operation)
    local raid=state.raids[operation.raidId]
    AddHeads(raid,operation)
end
function C.Publish(state,operation)
    local raid=state.raids[operation.raidId]
    local needsRebuild=raid.conflicts and next(raid.conflicts)~=nil
    for _,change in ipairs(operation.changes) do
        local heads=raid.heads and raid.heads[change.key]
        local parents={};for _,id in ipairs(Parents(change)) do parents[id]=true end
        for id in pairs(heads or {}) do if not parents[id] then needsRebuild=true end end
    end
    if needsRebuild and not auditIndexes[raid] then auditIndexes[raid]=AuditIndex(state,raid) end
    AddHeads(raid,operation)
    if needsRebuild then Rebuild(state,raid)
    else
        for _,change in ipairs(operation.changes) do raid.records[change.key]={revision=operation.id,value=change.value,deleted=change.deleted,heads={operation.id}} end
        if operation.resolution then RefreshAuditIndex(state,raid) end
    end
end
function J.GetConflicts(db,raidId,offset,limit)
    local state,reason=J.Ensure(db);if not state then return nil,reason end;C.Ensure(state)
    local raid=state.raids[raidId];local ids=Sorted(raid and raid.conflicts)
    offset=math.max(0,math.floor(tonumber(offset) or 0));limit=math.max(1,math.min(50,math.floor(tonumber(limit) or 10)))
    local page={}
    for index=offset+1,math.min(table.getn(ids),offset+limit) do
        local conflict=raid.conflicts[ids[index]]
        table.insert(page,{id=conflict.id,heads=Copy(conflict.heads),keys=Copy(conflict.keys),recordCount=table.getn(conflict.keys)})
    end
    return page,table.getn(ids)
end
function J.GetConflict(db,raidId,id)
    local state,reason=J.Ensure(db);if not state then return nil,reason end;C.Ensure(state)
    local raid=state.raids[raidId];local conflict=raid and raid.conflicts and raid.conflicts[id]
    if not conflict then return nil end
    local result={id=id,heads=Copy(conflict.heads),keys=Copy(conflict.keys),records={}}
    for _,key in ipairs(conflict.keys) do
        local record={key=key,base=Copy(raid.records[key]),variants={}}
        for _,revision in ipairs(Sorted(raid.heads[key])) do
            local value=Record(state,key,revision);local operation=state.operations[revision]
            table.insert(record.variants,{revision=revision,author=operation.author,timestamp=operation.timestamp,value=Copy(value.value),deleted=value.deleted})
        end
        table.insert(result.records,record)
    end
    return result
end
function J.GetConflictRecord(db,raidId,id,recordIndex,variantIndex)
    local state,reason=J.Ensure(db);if not state then return nil,reason end;C.Ensure(state)
    local raid=state.raids[raidId];local conflict=raid and raid.conflicts and raid.conflicts[id]
    if not conflict then return nil end
    local key=conflict.keys[recordIndex]
    local result={id=conflict.id,heads=Copy(conflict.heads),recordCount=table.getn(conflict.keys)}
    if key then
        local ids=Sorted(raid.heads[key]);local revision=ids[variantIndex or 1]
        result.record={key=key,base=Copy(raid.records[key]),variantCount=table.getn(ids)}
        if revision then
            local operation=state.operations[revision];local value=Record(state,key,revision)
            result.record.variant={revision=revision,author=operation.author,timestamp=operation.timestamp,value=Copy(value.value),deleted=value.deleted}
        end
    end
    return result
end
function J.Resolve(db,raidId,conflictId,choices,detail,expectedHeads)
    local conflict=J.GetConflict(db,raidId,conflictId)
    if not conflict then return false,"conflict-no-longer-exists" end
    if not expectedHeads or not J.Equal(expectedHeads,conflict.heads) then return false,"conflict-changed" end
    if type(choices)~="table" or table.getn(choices)~=table.getn(conflict.keys) then return false,"resolve-all-records" end
    local selected={};for _,choice in ipairs(choices) do if type(choice)~="table" or selected[choice.key] then return false,"invalid-resolution" end;selected[choice.key]=true end
    for _,key in ipairs(conflict.keys) do if not selected[key] then return false,"resolve-all-records" end end
    return J.Commit(db,raidId,"conflict.resolve",choices,detail or {subject=raidId},true,true)
end
