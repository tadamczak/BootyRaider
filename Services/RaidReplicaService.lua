local Raider=BootyRaider
local Replica={policy=1}
Raider.Services.RaidReplica=Replica
local function Copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=Copy(item) end;return result
end
local function Lower(value) return string.lower(tostring(value or "")) end
local function Text(value,limit)
    return type(value)=="string" and string.len(value)>0 and string.len(value)<=(limit or 120) and not string.find(value,"%c")
end
local function Number(value,maximum)
    return type(value)=="number" and value==value and value>=0 and value<=maximum and value==math.floor(value)
end
local function Item(value) return Number(value,2147483647) and value>0 or Text(value,120) end
local function Optional(value,kind,limit)
    if value==nil then return true end
    if kind=="number" then return Number(value,limit or 2147483647) end
    if kind=="string" then return type(value)=="string" and string.len(value)<=(limit or 120) and not string.find(value,"%c") end
    return type(value)==kind
end
local function Fields(value,spec)
    if type(value)~="table" then return false end
    for key,field in pairs(value) do if not spec[key] or not Optional(field,spec[key]) then return false end end
    return true
end
local function List(value,limit,validate)
    if type(value)~="table" or table.getn(value)>limit then return false end
    local count=0
    for index,item in pairs(value) do
        if not Number(index,limit) or index<1 or not validate(item) then return false end
        count=count+1
    end
    return count==table.getn(value)
end
local memberFields={name="string",class="string",classFile="string",guildRank="string",guildMember="boolean",level="number",subgroup="number",raidRank="number",online="boolean",zone="string"}
local function CustomReserve(value)
    if value==nil then return true end
    if type(value)~="table" then return false end
    for kind,change in pairs(value) do
        if kind=="items" then
            if type(change)~="table" or not List(change.itemIds,40,Item) or not Optional(change.sourceName,"string",128) then return false end
            for field in pairs(change) do if field~="itemIds" and field~="sourceName" then return false end end
        elseif kind=="exception" then
            if not Fields(change,{allowed="boolean"}) or type(change.allowed)~="boolean" then return false end
        else return false end
    end
    return true
end
local function CustomReview(values)
    return List(values or {},400,function(change)
        if type(change)~="table" or not Text(change.name,96) or not Optional(change.sourceName,"string",128) then return false end
        for key in pairs(change) do if key~="name" and key~="kind" and key~="sourceName" and key~="allowed" and key~="itemIds" then return false end end
        if change.kind=="items" then return change.allowed==nil and List(change.itemIds,40,Item) end
        return change.kind=="exception" and change.itemIds==nil and type(change.allowed)=="boolean"
    end)
end
local function ImportExport(chunks)
    local bytes=0
    return List(chunks or {},4,function(chunk)
        if type(chunk)~="string" or string.len(chunk)>4096 then return false end
        bytes=bytes+string.len(chunk)
        return bytes<=16000
    end)
end
local function Heads(value)
    if type(value)~="table" then return false end
    for key,ids in pairs(value) do
        if not Text(key,340) or not List(ids,256,function(id)return Text(id,300) end) then return false end
    end
    return true
end
local function KnownKey(key)
    return type(key)=="string" and (key=="raid:metadata" or key=="raid:lifecycle" or key=="raid:alias-decision" or key=="raid:save" or key=="raid:loot-rules"
        or key=="saved:snapshot" or key=="saved:statistic" or key=="saved:flags" or key=="import:sr"
        or string.find(key,"^member:") or string.find(key,"^sr:") or string.find(key,"^loot:") or string.find(key,"^entitlement:")
        or string.find(key,"^saved:member:") or string.find(key,"^csr:") or string.find(key,"^recorder:")
        or string.find(key,"^merge:") or string.find(key,"^allocation:"))
end
local function Keys(value)
    local result={};for key in pairs(value or {}) do table.insert(result,key) end;table.sort(result);return result
end
local function Page(values,offset,limit)
    offset=math.max(0,math.floor(tonumber(offset) or 0));limit=math.max(1,math.min(50,math.floor(tonumber(limit) or 8)))
    local result={};for index=offset+1,math.min(table.getn(values),offset+limit) do table.insert(result,values[index]) end
    return result,table.getn(values)
end
local function ShortId(value)
    local hash=0;for index=1,string.len(value) do hash=math.mod(hash*31+string.byte(value,index),16777213) end
    return string.format("%06x",hash)
end

-- Semantic validation is separate from the journal's structural bounds. A
-- trusted officer relay still cannot publish frames, executable code or an
-- invalid SR/loot value into the application's durable domain tables.
function Replica.ValidateOperation(operation)
    if type(operation)~="table" or not List(operation.changes,512,function(change)
        return type(change)=="table" and type(change.key)=="string"
    end) then return false,"invalid-domain-operation" end
    for _,change in ipairs(operation.changes) do
        local key,value=change.key,change.value
        if type(key)~="string" then return false,"invalid-domain-key" end
        if not KnownKey(key) then return false,"unknown-domain-record" end
        if not change.deleted then
            if key=="raid:metadata" then
                if not Fields(value,{id="string",raidName="string",displayName="string",startedAt="number",endedAt="number",savedAt="number",modifiedAt="number"})
                    or not Text(value.id) or not Text(value.raidName) then return false,"invalid-raid-metadata" end
            elseif string.find(key,"^sr:") then
                if type(value)~="table" or not Text(value.name,96) or type(value.items)~="table" or table.getn(value.items)>40
                    or type(value.exception)~="boolean" then return false,"invalid-reserve" end
                for _,item in ipairs(value.items) do if not Item(item) then return false,"invalid-reserve-item" end end
                if not List(value.items,40,Item) or string.sub(key,4)~=Lower(value.name) then return false,"invalid-reserve-identity" end
                if not Optional(value.sourceName,"string",128) or not CustomReserve(value.custom) then return false,"invalid-reserve-custom-intent" end
            elseif string.find(key,"^entitlement:") then
                if type(value)~="table" or not Text(value.name,96) or string.sub(key,13)~=Lower(value.name)
                    or type(value.srConsumedAt)~="table" or not Optional(value.reyCoinUsedAt,"number")
                    or not Optional(value.reyCoinItemLink,"string",1024) then return false,"invalid-entitlement" end
                local count=0
                for item,stamp in pairs(value.srConsumedAt) do
                    count=count+1
                    if count>512 or not (Number(item,2147483647) and item>0 or Text(item,160) and string.find(item,"^name:"))
                        or not Number(stamp,2147483647) then return false,"invalid-entitlement-consumption" end
                end
                for field in pairs(value) do if field~="name" and field~="srConsumedAt" and field~="reyCoinUsedAt" and field~="reyCoinItemLink" then return false,"invalid-entitlement-field" end end
            elseif string.find(key,"^loot:") then
                if type(value)~="table" or not Text(value.recipient,96) or not Item(value.item) or not Number(value.count,1000000) or value.count<1 then return false,"invalid-allocation" end
                if not Optional(value.name,"string") or not Optional(value.link,"string",1024) or not Optional(value.ordinary,"boolean")
                    or not Optional(value.historyKey,"string",300) then return false,"invalid-allocation-context" end
            elseif string.find(key,"^member:") then
                if not Fields(value,memberFields) or not Text(value.name,96) or string.sub(key,8)~=Lower(value.name) then return false,"invalid-member" end
            elseif string.find(key,"^saved:member:") then
                if type(value)~="table" or not Text(value.name,96) or string.sub(key,14)~=Lower(value.name)
                    or not Optional(value.class,"string") or not Optional(value.guildRank,"string") or not Optional(value.lootRank,"string")
                    or not Optional(value.attendance,"number",1000000) then return false,"invalid-saved-member" end
            elseif key=="raid:alias-decision" then
                if type(value)~="table" or not List(value.members,128,function(id)return Text(id,300) end) or table.getn(value.members)<2
                    or type(value.claims)~="table" or type(value.observed)~="table" or not Text(value.selectionFingerprint,100) then return false,"invalid-alias-decision" end
                local members,previous={},nil
                for _,id in ipairs(value.members) do if previous and previous>=id then return false,"invalid-alias-members" end;members[id]=true;previous=id end
                for id,claims in pairs(value.claims) do
                    if not members[id] or not Heads(claims) then return false,"invalid-alias-claims" end
                    for claim in pairs(claims) do if not string.find(claim,"^merge:") then return false,"invalid-alias-claims" end end
                end
                for id,fingerprint in pairs(value.observed) do if not members[id] or id==value.members[1] or not Text(fingerprint,100) then return false,"invalid-alias-observations" end end
            elseif key=="raid:lifecycle" then
                if value~="active" and value~="saved" and value~="ended" then return false,"invalid-lifecycle" end
            elseif key=="saved:snapshot" or key=="saved:statistic" then
                if type(value)~="boolean" then return false,"invalid-save-flag" end
            elseif key=="saved:flags" then
                if not Fields(value,{attendanceEnabled="boolean",csrEnabled="boolean",statisticsEnabled="boolean"}) then return false,"invalid-save-options" end
            elseif key=="raid:save" then
                if not Fields(value,{saveRaidStatistics="boolean",saveAttendance="boolean",saveCSR="boolean"}) then return false,"invalid-save-options" end
            elseif key=="raid:loot-rules" then
                if type(value)~="table" then return false,"invalid-loot-rules" end
                for rank,rule in pairs(value) do
                    if not Text(rank,96) or not Fields(rule,{sr="boolean",csr="boolean",reyCoin="boolean",highlyContested="boolean"}) then return false,"invalid-loot-rules" end
                end
            elseif key=="import:sr" then
                if type(value)~="table" or not Optional(value.url,"string",2048) or not List(value.unmatched or {},200,function(entry)
                    return type(entry)=="table" and Text(entry.name,96) and (entry.itemIds==nil or List(entry.itemIds,40,Item))
                end) then return false,"invalid-import" end
                if not Optional(value.id,"string",128) or not Optional(value.origin,"string",128)
                    or not CustomReview(value.review) or not ImportExport(value.exportChunks) then return false,"invalid-import-review" end
            elseif string.find(key,"^csr:") then
                if type(value)~="table" or not Text(value.player,96) or not Item(value.item) or type(value.archived)~="boolean" then return false,"invalid-csr-source" end
            elseif string.find(key,"^recorder:") then
                if type(value)~="table" or not Text(value.name,96) or string.sub(key,10)~=Lower(value.name)
                    or (value.state~="active" and value.state~="saved" and value.state~="ended") then return false,"invalid-recorder" end
            elseif string.find(key,"^merge:") then
                if type(value)~="table" or not Text(value.source,300) or string.sub(key,7)~=value.source
                    or type(value.token)~="table" or value.token.id~=value.source or not Heads(value.token.heads) or type(value.mapping)~="table" then return false,"invalid-merge" end
                for from,to in pairs(value.mapping) do if not Text(from,340) or not Text(to,340) then return false,"invalid-merge-mapping" end end
            elseif string.find(key,"^allocation:") then
                if type(value)~="table" or not List(value.observed,2,function(id)return Text(id,300) end) or table.getn(value.observed)~=2
                    or (not Text(value.duplicateOf,300) and value.separate~=true) then return false,"invalid-allocation-decision" end
            else return false,"invalid-domain-value" end
        end
    end
    return true
end
function Replica.ValidateCheckpoint(entry)
    if type(entry)~="table" then return false,"invalid-checkpoint" end
    if not entry.compacted then return Replica.ValidateOperation(entry) end
    if not List(entry.changes,512,function(change) return type(change)=="table" and type(change.key)=="string" end) then return false,"invalid-checkpoint-records" end
    for _,change in ipairs(entry.changes) do if not KnownKey(change.key) then return false,"unknown-domain-record" end end
    return true
end

function Replica.Create(options)
    options=options or {}
    local J=Raider.Services.RaidJournal
    local db=options.db or Raider.Database.Ensure()
    local state={revision=0,dirty={},dirtyNames={},aliases={},aliasSources={},mergeConflicts={},metadata={},transport=nil,projected={},waiting={}}
    local api={}
    local function DirectlyFollows(operation,previous)
        for _,change in ipairs(operation.changes or {}) do
            if change.base==previous.id then return true end
            for _,base in ipairs(change.bases or {}) do if base==previous.id then return true end end
        end
        return false
    end
    local function LaterChange(operation,previous)
        if not previous then return true end
        if DirectlyFollows(operation,previous) then return true end
        if DirectlyFollows(previous,operation) then return false end
        return operation.timestamp>previous.timestamp or operation.timestamp==previous.timestamp and operation.id>previous.id
    end
    state.loadedRaids={};state.changedRaids={};state.raidInfo={};state.latestOperations={}
    for id in pairs(db.raidJournal and db.raidJournal.raids or {}) do state.loadedRaids[id]=true end
    local syncLog=type(db.raidSyncLog)=="table" and db.raidSyncLog or {};db.raidSyncLog=syncLog
    function api.LogSync(message)
        if syncLog[1] and syncLog[1].message==message then return end
        table.insert(syncLog,1,{timestamp=time(),message=message});if table.getn(syncLog)>100 then table.remove(syncLog) end
        state.revision=state.revision+1
    end
    function api.GetSyncLog() return syncLog end
    local function Authorized()
        if options.authorize then return options.authorize() end
        return Raider.Services.RankPolicy.CanManageHistory()
    end
    local function Record(id,key)
        local record=J.GetRecord(db,id,key)
        return record and not record.deleted and record.value or nil,record
    end
    local function Raid(id) local journal=J.Ensure(db);return journal and journal.raids[id] end
    local function Canonical(id)
        local visited={}
        while state.aliases[id] and not visited[id] do visited[id]=true;id=state.aliases[id] end
        if visited[id] then
            local values=Keys(visited);return values[1]
        end
        return id
    end
    local function ReindexAliases()
        state.aliases={};state.aliasSources={};state.mergeConflicts={};state.aliasBlocked={};state.aliasGroups={};state.aliasDecisions={};state.aliasPlans={}
        local journal=J.Ensure(db)
        local graph,claims,targets,uncertain={},{},{},{}
        for _,target in ipairs(Keys(journal.raids)) do
            local raid=journal.raids[target]
            for _,key in ipairs(Keys(raid.records)) do
                if string.find(key,"^merge:") then
                    local merge,record=Record(target,key);local source=merge and merge.source or string.sub(key,7)
                    if record and not record.deleted and Text(source,300) and source~=target then
                        graph[source]=graph[source] or {};graph[target]=graph[target] or {}
                        graph[source][target]=true;graph[target][source]=true
                        targets[source]=targets[source] or {};targets[source][target]=true
                        claims[target]=claims[target] or {};claims[target][key]=Copy(record.heads or {record.revision})
                        if record.conflicted or record.pendingCheckpoint then uncertain[target]=true;uncertain[source]=true end
                    end
                end
            end
        end
        local visited={}
        for _,start in ipairs(Keys(graph)) do
            if not visited[start] then
                local stack={start};local members={};local componentClaims={};local blocked=false
                while table.getn(stack)>0 do
                    local id=table.remove(stack)
                    if not visited[id] then
                        visited[id]=true;table.insert(members,id)
                        if claims[id] then componentClaims[id]=claims[id] end
                        if uncertain[id] or table.getn(Keys(targets[id]))>1 then blocked=true end
                        for peer in pairs(graph[id]) do if not visited[peer] then table.insert(stack,peer) end end
                    end
                end
                table.sort(members);local coordinator=members[1]
                local finished={}
                for _,id in ipairs(members) do
                    local path={};local cursor=id
                    while cursor and not finished[cursor] do
                        if path[cursor] then blocked=true;break end
                        path[cursor]=true;cursor=Keys(targets[cursor])[1]
                    end
                    for seen in pairs(path) do finished[seen]=true end
                end
                local decision,record=Record(coordinator,"raid:alias-decision")
                local valid=decision and record and not record.conflicted and not record.pendingCheckpoint
                    and J.Equal(decision.members,members) and J.Equal(decision.claims,componentClaims)
                if valid then
                    state.aliasDecisions[coordinator]=decision
                    state.aliasSources[coordinator]={}
                    for _,id in ipairs(members) do if id~=coordinator then state.aliases[id]=coordinator;table.insert(state.aliasSources[coordinator],id) end end
                elseif blocked or record then
                    local group={id=coordinator,members=members,claims=componentClaims,decisionConflict=record and record.conflicted}
                    state.aliasGroups[coordinator]=group
                    for _,id in ipairs(members) do state.aliasBlocked[id]=group;state.mergeConflicts[id]=true end
                else
                    for _,source in ipairs(members) do local values=Keys(targets[source]);if values[1] then state.aliases[source]=values[1] end end
                end
            end
        end
        for source in pairs(state.aliases) do
            local target=Canonical(source)
            if target~=source and not state.aliasDecisions[target] then
                state.aliasSources[target]=state.aliasSources[target] or {};table.insert(state.aliasSources[target],source)
            end
        end
        for _,entry in pairs(db.raidStatistics and db.raidStatistics.raids or {}) do
            if state.aliasBlocked[entry.syncRaidId] then
                entry.csrEnabled=false;entry.syncDisputed=true;entry.syncAliasBlocked=true
                if Raider.Services.RaidCSR then Raider.Services.RaidCSR.Invalidate(entry.syncRaidId) end
            end
        end
    end
    local function AllRecords(id)
        local result={};local raid=Raid(id)
        for _,key in ipairs(Keys(raid and raid.records)) do result[key]=J.GetRecord(db,id,key) end
        return result
    end
    local function RevisionToken(id)
        local values={id=id,heads={}}
        for key,record in pairs(AllRecords(id)) do values.heads[key]=record.heads or {record.revision} end
        return values
    end
    local function Queue(id,names)
        state.catalog=nil;state.conflictCache=nil
        id=Canonical(id)
        state.dirty[id]=true;state.revision=state.revision+1
        if not names then state.dirtyNames[id]=false
        elseif state.dirtyNames[id]~=false then
            state.dirtyNames[id]=state.dirtyNames[id] or {}
            for name in pairs(names) do state.dirtyNames[id][name]=true end
        end
    end
    function api.OnOperation(operation,status,localChange)
        if not operation or status=="duplicate" then return end
        state.changedRaids[operation.raidId]=true;state.raidInfo[operation.raidId]=nil
        local latestId=state.latestOperations[operation.raidId]
        local latest=latestId and J.GetOperation(db,latestId)
        if latestId~=nil and operation.kind~="raid.observe" and LaterChange(operation,latest) then state.latestOperations[operation.raidId]=operation.id end
        if not localChange then state.receivedSinceLoad=true end
        if localChange and (operation.kind=="raid.start" or operation.kind=="raid.reopen" or operation.kind=="raid.save") then db.syncJoinedRaidId=operation.raidId end
        if not localChange and operation.kind~="raid.observe" then
            local action=Raider.Modules and Raider.Modules.RaidLog and Raider.Modules.RaidLog.FormatAction(operation) or operation.kind
            api.LogSync("Received update by "..tostring(operation.author)..": "..tostring(action))
        end
        if localChange and operation.kind=="raid.leave" and db.syncJoinedRaidId==operation.raidId then db.syncJoinedRaidId=nil end
        local reindex=operation.kind=="raid.merge"
        for _,change in ipairs(operation.changes or {}) do if change.key=="raid:alias-decision" or string.find(change.key,"^merge:") then reindex=true end end
        local previousTargets={}
        if reindex then
            for id in pairs(J.Ensure(db).raids) do previousTargets[id]={canonical=Canonical(id),blocked=state.aliasBlocked[id] and true or false} end
        end
        if reindex then ReindexAliases() else state.aliasPlans={} end
        local names={};local all=false
        for _,change in ipairs(operation.changes or {}) do
            local _,_,name=string.find(change.key,"^sr:(.+)$")
            if not name then _,_,name=string.find(change.key,"^member:(.+)$") end
            if not name then _,_,name=string.find(change.key,"^saved:member:(.+)$") end
            if name then names[name]=true
            elseif string.find(change.key,"^loot:") then
                if change.value then names[Lower(change.value.recipient)]=true end
                if change.before then names[Lower(change.before.recipient)]=true end
            elseif string.find(change.key,"^csr:") and change.value then names[Lower(change.value.player)]=true
            elseif not string.find(change.key,"^recorder:") then all=true end
        end
        Queue(operation.raidId,not all and names or nil)
        if reindex then
            for id,previous in pairs(previousTargets) do
                if Canonical(id)~=previous.canonical or (state.aliasBlocked[id] and true or false)~=previous.blocked then Queue(id) end
            end
        end
        if localChange and state.transport and state.transport.NotifyChanged then state.transport:NotifyChanged(operation.raidId) end
        if options.wake then options.wake() end
    end
    local function Commit(id,kind,changes,detail)
        local allowed,reason=Authorized();if not allowed then return false,reason or "Current guild officer authority is required." end
        local ok,operation=J.Commit(db,id,kind,changes,detail)
        if ok and operation then api.OnOperation(operation,"applied",true) end
        return ok,operation
    end
    function api.SetTransport(transport) state.transport=transport end
    function api.Discover()
        local allowed,reason=Authorized();if not allowed then return false,reason end
        if not state.transport then return false,"Synchronization is unavailable until the guild directory and client messaging are ready." end
        local ok,failure=state.transport:Discover()
        if options.wake then options.wake() end
        return ok,failure
    end

    local function Ambiguities(id)
        local groups,results={},{}
        for key,record in pairs(AllRecords(id)) do
            if string.find(key,"^loot:") and not record.deleted and record.value then
                local value=record.value
                local group=Lower(value.recipient).."|"..Lower(value.item)
                groups[group]=groups[group] or {};table.insert(groups[group],{key=key,record=record})
            end
        end
        for _,group in pairs(groups) do
            table.sort(group,function(a,b)return a.key<b.key end)
            local first=group[1]
            local original=first and J.GetOperation(db,first.record.revision)
            for index=2,table.getn(group) do
                local candidate=group[index];local operation=J.GetOperation(db,candidate.record.revision)
                local decision=Record(id,"allocation:"..string.sub(candidate.key,6))
                local resolved=decision and decision.observed and decision.observed[1]==first.record.revision and decision.observed[2]==candidate.record.revision
                if original and operation and original.origin~=operation.origin and not resolved then
                    table.insert(results,{id="duplicate:"..candidate.key,kind="loot",subject="Possible duplicate: "..tostring(candidate.record.value.item),
                        first=first,second=candidate,heads={first.record.revision,candidate.record.revision},variantCount=2})
                end
            end
        end
        table.sort(results,function(a,b)return a.id<b.id end);return results
    end
    local function PendingMerges(id)
        local result={}
        local blocked=state.aliasBlocked[id]
        if blocked then return {{id="alias:"..blocked.id,kind="alias",subject="Overlapping raid recordings - CSR withheld",variantCount=table.getn(blocked.members)}} end
        local decision=state.aliasDecisions[id]
        for _,source in ipairs(state.aliasSources[id] or {}) do
            local merge=Record(id,"merge:"..source)
            local current=decision and decision.observed[source]==J.Fingerprint(RevisionToken(source))
            if not current and (decision or not merge or not J.Equal(merge.token,RevisionToken(source)) or state.mergeConflicts[source]) then
                table.insert(result,{id="merge:"..source,source=source,kind="merge",subject="Merged recording has new changes",variantCount=2})
            end
        end
        return result
    end
    local function Conflicts(id)
        id=Canonical(id)
        state.conflictCache=state.conflictCache or {}
        if state.conflictCache[id] then return state.conflictCache[id] end
        local result={};local offset,total=0,0
        repeat
            local values,count=J.GetConflicts(db,id,offset,50);total=count or 0
            for _,entry in ipairs(values or {}) do table.insert(result,entry) end
            offset=offset+50
        until offset>=total
        for _,entry in ipairs(result) do
            entry.subject=entry.subject or (entry.keys and table.concat(entry.keys,", ")) or "Conflicting changes"
            entry.kind=entry.kind or "change";entry.variantCount=entry.variantCount or table.getn(entry.heads or {})
        end
        for _,entry in ipairs(Ambiguities(id)) do table.insert(result,entry) end
        for _,entry in ipairs(PendingMerges(id)) do table.insert(result,entry) end
        state.conflictCache[id]=result
        return result
    end
    function api.ListConflicts(id,offset,limit) return Page(Conflicts(id),offset,limit) end

    local function Build(id)
        id=Canonical(id)
        local records=AllRecords(id)
        for _,record in pairs(records) do
            if record.pendingCheckpoint then return nil,"Waiting for checkpoint data. The previous agreed raid is retained." end
        end
        local metadata=Record(id,"raid:metadata")
        if not metadata then return nil,"Raid metadata is not available yet. Wait for synchronization." end
        local attendance={syncRaidId=id,snapshotId=metadata.id,raidName=metadata.raidName,displayName=metadata.displayName,
            sessionStartedAt=metadata.startedAt,createdAt=metadata.startedAt,endedAt=metadata.endedAt,lastSavedAt=metadata.savedAt,
            members={},departedMembers={},lootRules=Copy(Record(id,"raid:loot-rules") or {}),
            saveOptions=Copy(Record(id,"raid:save") or {}),_sessionDraft=true,nextLootRecordId=0}
        attendance.syncEnded=Record(id,"raid:lifecycle")=="ended" or nil
        local ambiguous={}
        for _,entry in ipairs(Ambiguities(id)) do ambiguous[entry.second.key]=true end
        local byName={}
        local function Member(name)
            local key=Lower(name);local member=byName[key]
            if not member then member={name=name,sr="",srItemIds={},loot={},guildRank="Guest"};byName[key]=member;table.insert(attendance.members,member) end
            return member
        end
        for _,key in ipairs(Keys(records)) do
            local record=records[key];local value=not record.deleted and record.value
            if value and string.find(key,"^member:") then
                local member=Member(value.name);for field,item in pairs(value) do member[field]=Copy(item) end
            end
        end
        for _,key in ipairs(Keys(records)) do
            local record=records[key];local value=not record.deleted and record.value
            if value and string.find(key,"^sr:") then
                local member=Member(value.name);member.srItemIds=Copy(value.items or {});member.srException=value.exception and true or nil
                local labels={};for _,item in ipairs(member.srItemIds) do table.insert(labels,tostring(item)) end;member.sr=table.concat(labels,", ")
                member.srSourceName=table.getn(member.srItemIds)>0 and (value.sourceName or member.name) or nil
                for kind,change in pairs(value.custom or {}) do
                    attendance.srCustomChanges=attendance.srCustomChanges or {}
                    attendance.srCustomChanges[kind..":"..Lower(member.name)]={name=member.name,kind=kind,itemIds=Copy(change.itemIds),sourceName=change.sourceName,allowed=change.allowed}
                end
            elseif value and string.find(key,"^entitlement:") then
                local member=Member(value.name)
                member.srConsumedAt=next(value.srConsumedAt or {}) and Copy(value.srConsumedAt) or nil
                member.reyCoinUsedAt=value.reyCoinUsedAt;member.reyCoinItemLink=value.reyCoinItemLink
                member.syncEntitlementDisputed=record.conflicted and true or nil
            elseif value and string.find(key,"^loot:") then
                local decision=Record(id,"allocation:"..string.sub(key,6))
                if not ambiguous[key] and (not decision or not decision.duplicateOf) then
                    local member=Member(value.recipient);attendance.nextLootRecordId=attendance.nextLootRecordId+1
                    table.insert(member.loot,{syncRecordId=string.sub(key,6),recordId=attendance.nextLootRecordId,itemId=type(value.item)=="number" and value.item or nil,
                        name=value.name or tostring(value.item),link=value.link,count=value.count,ordinaryReceipt=value.ordinary or nil,awardHistoryKey=value.historyKey})
                end
            end
        end
        table.sort(attendance.members,function(a,b)return Lower(a.name)<Lower(b.name) end)
        local imported=Record(id,"import:sr") or {}
        attendance.softReserveImport={id=imported.id or metadata.id,origin=imported.origin or "officer-sync",url=imported.url or "",
            rollForExport=table.concat(imported.exportChunks or {}),customReview=Copy(imported.review),
            unmatchedReservations=Copy(imported.unmatched or {}),unmatchedNames={},missingNames={}}
        for _,reserve in ipairs(attendance.softReserveImport.unmatchedReservations) do table.insert(attendance.softReserveImport.unmatchedNames,reserve.name) end
        for _,member in ipairs(attendance.members) do if table.getn(member.srItemIds)==0 then table.insert(attendance.softReserveImport.missingNames,member.name) end end
        local conflicts=Conflicts(id);attendance.syncConflictCount=table.getn(conflicts)
        attendance.syncDisputedMembers={}
        for _,conflict in ipairs(conflicts) do
            local keys=conflict.keys or (conflict.second and {conflict.second.key}) or {}
            if conflict.kind=="merge" or table.getn(keys)==0 then attendance.syncDisputed=true end
            for _,key in ipairs(keys) do
                local _,_,name=string.find(key,"^sr:(.+)$")
                if not name then _,_,name=string.find(key,"^saved:member:(.+)$") end
                if not name then _,_,name=string.find(key,"^entitlement:(.+)$");if name then Member(name).syncEntitlementDisputed=true end end
                if name then attendance.syncDisputedMembers[name]=true
                elseif string.find(key,"^loot:") then
                    local value=records[key] and records[key].value
                    if value then attendance.syncDisputedMembers[Lower(value.recipient)]=true else attendance.syncDisputed=true end
                else attendance.syncDisputed=true end
            end
        end
        local flags=Record(id,"saved:flags") or {}
        local statistic={id=metadata.id,syncRaidId=id,displayName=metadata.displayName,raidName=metadata.raidName,
            createdAt=metadata.startedAt,startedAt=metadata.startedAt,endedAt=metadata.endedAt,savedAt=metadata.savedAt or metadata.startedAt,
            modifiedAt=metadata.modifiedAt or metadata.savedAt or metadata.startedAt,members={},lootRules=Copy(attendance.lootRules),
            attendanceEnabled=flags.attendanceEnabled~=false,csrEnabled=flags.csrEnabled==true,
            statisticsEnabled=attendance.saveOptions.saveRaidStatistics~=false,csrArchived={},
            syncDisputed=attendance.syncDisputed,syncDisputedMembers=Copy(attendance.syncDisputedMembers)}
        for _,member in ipairs(attendance.members) do
            local saved,savedRecord=Record(id,"saved:member:"..Lower(member.name))
            local target={name=member.name,class=member.class or member.classFile or "",guildRank=member.guildRank,lootRank=member.guildRank,
                attendance=1,srItems={},lootItems={},srCount=table.getn(member.srItemIds),lootCount=0}
            if saved then
                target.class=saved.class or target.class;target.guildRank=saved.guildRank or target.guildRank
                target.lootRank=saved.lootRank or target.guildRank;target.attendance=saved.attendance or 0
            end
            for _,item in ipairs(member.srItemIds) do table.insert(target.srItems,{itemId=type(item)=="number" and item or nil,name=type(item)=="string" and item or nil,count=1}) end
            for _,loot in ipairs(member.loot) do table.insert(target.lootItems,{itemId=loot.itemId,name=loot.name,count=loot.count,syncRecordId=loot.syncRecordId});target.lootCount=target.lootCount+loot.count end
            if not savedRecord or not savedRecord.deleted then table.insert(statistic.members,target) end
        end
        for key,record in pairs(records) do
            local value=not record.deleted and record.value
            if value and string.find(key,"^csr:") and value.archived then
                local player=Lower(value.player);statistic.csrArchived[player]=statistic.csrArchived[player] or {};statistic.csrArchived[player][value.item]=true
            end
        end
        if state.aliasBlocked[id] then
            attendance.syncDisputed=true;attendance.syncAliasBlocked=true
            attendance.syncRecoveryNotice="Overlapping raid recordings: CSR is withheld until their identities are resolved."
            statistic.syncDisputed=true;statistic.syncAliasBlocked=true;statistic.csrEnabled=false
        end
        return attendance,statistic
    end
    function api.GetProjection(id) return Build(id) end
    function api.GetJoinedRaidId()
        local id=db.syncJoinedRaidId
        if db.raidAttendance then id=db.raidAttendance.syncRaidId end
        return id and Raid(Canonical(id)) and Record(Canonical(id),"raid:lifecycle")~="ended" and id or nil
    end
    function api.GetRaidInfo(id)
        if not id then return {storage="In memory"} end
        id=Canonical(id)
        if state.raidInfo[id] then return state.raidInfo[id] end
        local metadata=Record(id,"raid:metadata") or {};local latestId=state.latestOperations[id]
        local latest=latestId and J.GetOperation(db,latestId)
        local raid=Raid(id)
        if latestId==nil then
            for _,operationId in ipairs(raid and raid.operationIds or {}) do
                local operation=J.GetOperation(db,operationId)
                if operation and operation.kind~="raid.observe" and LaterChange(operation,latest) then latest=operation end
            end
            state.latestOperations[id]=latest and latest.id or false
        end
        local info={storage=state.loadedRaids[id] and not state.changedRaids[id] and "On disk" or "In memory",
            lastAuthor=latest and latest.author or "Unknown",lastSave=metadata.savedAt,modifiedAt=latest and latest.timestamp}
        state.raidInfo[id]=info;return info
    end

    local function RemoveHistory(history,id)
        if not history or not history.raids then return end
        for key,entry in pairs(history.raids) do
            if entry.syncRaidId==id then
                history.raids[key]=nil
                for index=table.getn(history.order or {}),1,-1 do if history.order[index]==key then table.remove(history.order,index) end end
            end
        end
    end
    local function AvailableHistoryId(history,name,raidId)
        local stem=name.." ["..ShortId(raidId).."]"
        local candidate,index=stem,2
        while history.raids[candidate] do
            candidate=stem.." "..index;index=index+1
        end
        return candidate
    end
    local function StoreHistory(field,entry)
        local history=db[field]
        if not history then history={raids={},order={}};db[field]=history end
        RemoveHistory(history,entry.syncRaidId)
        local other=history.raids[entry.id]
        if other and other.syncRaidId~=entry.syncRaidId then
            local otherId=other.syncRaidId
            if otherId and otherId>entry.syncRaidId then
                local oldId=other.id;other.id=AvailableHistoryId(history,oldId,otherId);history.raids[oldId]=nil;history.raids[other.id]=other
                for index,value in ipairs(history.order) do if value==oldId then history.order[index]=other.id end end
            else entry.id=AvailableHistoryId(history,entry.id,entry.syncRaidId) end
        end
        history.raids[entry.id]=entry;table.insert(history.order,1,entry.id)
    end
    local function Snapshot(attendance)
        return {version=4,id=attendance.snapshotId,syncRaidId=attendance.syncRaidId,raidName=attendance.raidName,displayName=attendance.displayName,
            startedAt=attendance.sessionStartedAt,createdAt=attendance.createdAt,endedAt=attendance.endedAt,
            savedAt=attendance.lastSavedAt,updatedAt=attendance.lastSavedAt,members=Copy(attendance.members),
            lootRules=Copy(attendance.lootRules),saveOptions=Copy(attendance.saveOptions),raidResId=attendance.softReserveImport.id or attendance.snapshotId,
            srUrl=attendance.softReserveImport.url,rollForExport=attendance.softReserveImport.rollForExport,
            srCustomChanges=Copy(attendance.srCustomChanges),srCustomReview=Copy(attendance.softReserveImport.customReview),
            unmatched=Copy(attendance.softReserveImport.unmatchedReservations),source=attendance.softReserveImport.origin or "officer-sync"}
    end
    function api.Flush(limit)
        local used=0
        for _,id in ipairs(Keys(state.dirty)) do
            if used>=(limit or 1) then break end
            state.dirty[id]=nil;used=used+1
            local affected=state.dirtyNames[id];state.dirtyNames[id]=nil
            local attendance,statistic=Build(id)
            state.waiting[id]=not attendance and statistic or nil
            if attendance then
                local active=db.raidAttendance
                if active and Canonical(active.syncRaidId)==id then
                    -- Publish data only. Pending award/roll controllers are never
                    -- reconstructed or invoked by remote state projection.
                    local copied=Copy(attendance)
                    copied._sessionDraft=active._sessionDraft;copied.lastSavedAt=active.lastSavedAt
                    local localLoot,localMembers,failedLoot={},{},{}
                    for _,group in ipairs({active.members or {},active.departedMembers or {}}) do
                        for _,member in ipairs(group) do
                            localMembers[Lower(member.name)]=member
                            for _,loot in ipairs(member.loot or {}) do
                                if loot.syncRecordId then localLoot[loot.syncRecordId]=loot end
                                if loot.auditFailure then
                                    local key=loot.syncRecordId or "local:"..Lower(member.name)..":"..tostring(loot.recordId)
                                    failedLoot[key]={member=member,loot=loot}
                                end
                            end
                        end
                    end
                    local projectedMembers={}
                    for _,member in ipairs(copied.members) do
                        projectedMembers[Lower(member.name)]=member
                        local previous=localMembers[Lower(member.name)]
                        -- Physical roster positions belong to this client. The
                        -- journal's alphabetical projection is not a native index.
                        if previous and previous.raidIndex then
                            member.raidIndex=previous.raidIndex;member.dead=previous.dead
                            member.subgroup=previous.subgroup;member.online=previous.online
                            member.raidRank=previous.raidRank;member.zone=previous.zone;member.level=previous.level
                        end
                        if previous and previous.entitlementAuditFailure then
                            member.srConsumedAt=Copy(previous.srConsumedAt);member.reyCoinUsedAt=previous.reyCoinUsedAt
                            member.reyCoinItemLink=previous.reyCoinItemLink;member.entitlementAuditFailure=previous.entitlementAuditFailure
                            copied.syncLocalAuditFailure=previous.entitlementAuditFailure
                        end
                        for index=table.getn(member.loot or {}),1,-1 do
                            local loot=member.loot[index]
                            local previousLoot=localLoot[loot.syncRecordId]
                            if failedLoot[loot.syncRecordId] then table.remove(member.loot,index)
                            elseif previousLoot then loot.icon=previousLoot.icon;loot.rollHistory=previousLoot.rollHistory end
                        end
                    end
                    -- Confirmed physical receipts survive an unrelated remote
                    -- projection until Save successfully journals their facts.
                    for _,failure in pairs(failedLoot) do
                        local name=Lower(failure.member.name)
                        local member=projectedMembers[name]
                        if not member then
                            member=Copy(failure.member);member.loot={}
                            table.insert(copied.members,member);projectedMembers[name]=member
                        end
                        table.insert(member.loot,Copy(failure.loot))
                        copied.syncLocalAuditFailure=failure.loot.auditFailure
                    end
                    db.raidAttendance=copied
                    if options.onAttendance then options.onAttendance(active,copied) end
                end
                local _,saved=Record(id,"saved:snapshot")
                if saved and not saved.deleted and saved.value then StoreHistory("softReserveHistory",Snapshot(attendance))
                elseif saved and saved.deleted then RemoveHistory(db.softReserveHistory,id) end
                local _,stats=Record(id,"saved:statistic")
                if stats and not stats.deleted and stats.value then StoreHistory("raidStatistics",statistic)
                elseif stats and (stats.deleted or not stats.value) then RemoveHistory(db.raidStatistics,id) end
                for _,source in ipairs(state.aliasSources[id] or {}) do RemoveHistory(db.softReserveHistory,source);RemoveHistory(db.raidStatistics,source) end
                if Raider.Services.RaidCSR then Raider.Services.RaidCSR.Invalidate(id,affected or nil) end
                state.projected[id]=true
            end
            if options.onChanged then options.onChanged(id) end
        end
        return used
    end
    function api.HasWork() return next(state.dirty)~=nil end
    function api.Recover(id,viewEnded)
        local allowed,reason=Authorized();if not allowed then return false,reason end
        id=Canonical(id)
        local active=db.raidAttendance
        -- Physical receipts cannot be replayed. Preserve their local fallback
        -- until Save has successfully included them in the journal projection.
        local localFacts=active and active.syncLocalAuditFailure
        for _,members in ipairs({active and active.members or {},active and active.departedMembers or {}}) do
            for _,member in ipairs(members) do
                if member.entitlementAuditFailure then localFacts=true end
                for _,loot in ipairs(member.loot or {}) do if loot.auditFailure then localFacts=true end end
            end
        end
        if localFacts then return false,"Save the current raid successfully before recovering a session. Confirmed loot or loot-right changes are still recorded only locally." end
        if active and active.syncRaidId and Canonical(active.syncRaidId)~=id then return false,"Save or end your current session before recovering another raid." end
        local attendance,failure=Build(id);if not attendance then return false,failure end
        if Record(id,"raid:lifecycle")=="ended" and not viewEnded then return false,"This raid was explicitly ended. Its history is still available." end
        if options.restore then
            local ok,message=options.restore(attendance);if ok==false then return false,message end
        else db.raidAttendance=attendance end
        db.syncJoinedRaidId=id
        if state.transport and state.transport.NotifyChanged then state.transport:NotifyChanged() end
        state.revision=state.revision+1
        return true
    end
    function api.Reopen(id,expected)
        local current=Record(Canonical(id),"raid:lifecycle")
        if current~="ended" then return false,"This session is no longer ended. Refresh and try again." end
        local _,record=Record(Canonical(id),"raid:lifecycle")
        if expected and record.revision~=expected then return false,"Session status changed. Review it again." end
        local ok,reason=Commit(Canonical(id),"raid.reopen",{{key="raid:lifecycle",value="active"}},{subject="Reopened raid session"})
        if ok then api.LogSync("Reopened the raid session for all officers.") end
        return ok,reason
    end
    function api.GetStatus(id)
        local transport=state.transport and state.transport.GetStatus and state.transport:GetStatus(id) or {}
        local conflicts=id and table.getn(Conflicts(Canonical(id))) or 0
        local blocked=id and state.aliasBlocked[Canonical(id)]
        local message=blocked and "Overlapping raid recordings: CSR is withheld until their identities are resolved." or id and state.waiting[Canonical(id)] or transport.message or "Waiting for another officer."
        local recordingGap
        if id and options.recorderAvailable and Record(Canonical(id),"raid:lifecycle")~="ended" then
            local found=false
            local raid=Raid(Canonical(id))
            for key in pairs(raid and raid.records or {}) do
                if string.find(key,"^recorder:") then
                    local value=Record(Canonical(id),key)
                    if value and value.state=="active" and options.recorderAvailable(value.name,id,transport.peers or {}) then found=true;break end
                end
            end
            recordingGap=not found
            if recordingGap and not blocked and not transport.lastError then message="Nobody is recording new raid events. Use Start Live Tracking to record on this character." end
        end
        local active=db.raidAttendance
        local localFailure=active and id and Canonical(active.syncRaidId)==Canonical(id) and active.syncLocalAuditFailure
        local lifecycle=id and Record(Canonical(id),"raid:lifecycle")
        local metadata=id and Record(Canonical(id),"raid:metadata")
        if lifecycle=="ended" and not blocked and not transport.lastError then
            local _,record=Record(Canonical(id),"raid:lifecycle")
            local operation=record and record.revision and J.GetOperation(db,record.revision)
            message=tostring(operation and operation.author or "An officer").." ended this raid. Updates still synchronize. Reopen it to continue recording."
        end
        if localFailure then message="Needs attention: a confirmed loot change is stored only locally. Save the raid to retry synchronization. "..tostring(localFailure) end
        local syncStatus=transport.lastError and "Sync error! Send log" or state.receivedSinceLoad and "New data received. Please reload!"
            or (transport.pending or 0)>0 and "Syncing…" or "Up to date"
        return {syncStatus=syncStatus,revision=state.revision+(transport.revision or 0),localOnly=transport.localOnly~=false,pending=transport.pending or 0,
            conflicts=conflicts,compatible=transport.compatible~=false,peers=type(transport.peers)=="table" and transport.peers or {},
            raidName=metadata and metadata.id,retryAvailable=transport.lastError~=nil,lifecycle=lifecycle,recordingGap=recordingGap,csrWithheld=blocked and true or false,needsAttention=localFailure and true or false,message=message}
    end
    local function RaidList()
        if state.catalog then return state.catalog end
        local list={};local journal=J.Ensure(db)
        for id in pairs(journal.raids) do
            if Canonical(id)==id then
                local metadata,record=Record(id,"raid:metadata")
                if metadata then
                    local operation=record.revision and J.GetOperation(db,record.revision)
                    local lifecycle,lifecycleRecord=Record(id,"raid:lifecycle");lifecycle=lifecycle or "active"
                    local memberCount=0
                    for key,value in pairs(Raid(id).records or {}) do if string.find(key,"^member:") and not value.deleted then memberCount=memberCount+1 end end
                    local limits={["Molten Core"]=40,["Blackwing Lair"]=40,["Onyxia's Lair"]=40,["Zul'Gurub"]=20,["Karazhan10"]=10,["Lower Karazhan Halls"]=10}
                    table.insert(list,{createdAt=metadata.startedAt,memberCount=memberCount,memberLimit=limits[metadata.raidName],id=id,name=metadata.id,raidType=metadata.raidName,state=lifecycle,author=operation and operation.author,
                        updatedAt=operation and operation.timestamp or metadata.startedAt or 0,conflicts=table.getn(Conflicts(id)),lifecycleRevision=lifecycleRecord and lifecycleRecord.revision,recoverable=true})
                end
            end
        end
        table.sort(list,function(a,b)if a.updatedAt==b.updatedAt then return a.id<b.id end return a.updatedAt>b.updatedAt end)
        state.catalog=list;return list
    end
    function api.ListRaids(offset,limit)
        return Page(RaidList(),offset,limit)
    end
    function api.ListActiveRaids(offset,limit)
        local list={};for _,entry in ipairs(RaidList()) do if entry.state~="ended" then table.insert(list,entry) end end
        return Page(list,offset,limit)
    end
    function api.ListMergeCandidates(id,offset,limit)
        local list,result=RaidList(),{};id=Canonical(id)
        local metadata=Record(id,"raid:metadata") or {}
        local members=Raid(id) and Raid(id).records or {}
        for _,entry in ipairs(list) do
            if entry.id~=id and entry.raidType==metadata.raidName then
                local candidate=Copy(entry);candidate.overlap=0
                for key in pairs(Raid(entry.id).records) do
                    if string.find(key,"^member:") and members[key] then candidate.overlap=candidate.overlap+1 end
                end
                local other=Record(entry.id,"raid:metadata")
                candidate.timeDistance=math.abs((tonumber(metadata.startedAt) or 0)-(tonumber(other.startedAt) or 0))
                table.insert(result,candidate)
            end
        end
        for _,source in ipairs(state.aliasSources[id] or {}) do
            local meta=Record(source,"raid:metadata")
            if meta then table.insert(result,{id=source,name=meta.id,raidType=meta.raidName,state="merged",conflicts=1,recoverable=false,overlap=1000000,timeDistance=0}) end
        end
        table.sort(result,function(a,b)
            if a.overlap~=b.overlap then return a.overlap>b.overlap end
            if a.timeDistance~=b.timeDistance then return a.timeDistance<b.timeDistance end
            return a.id<b.id
        end)
        return Page(result,offset,limit)
    end

    local function MergePlan(target,source)
        target=Canonical(target)
        if state.aliasBlocked[target] or state.aliasBlocked[source] then return nil,"Resolve the overlapping recording identities in Conflicts before comparing another merge." end
        if target==source or not Raid(target) or not Raid(source) then return nil,"Select two distinct known raid recordings." end
        local targetMeta=Record(target,"raid:metadata");local sourceMeta=Record(source,"raid:metadata")
        if not targetMeta or not sourceMeta then return nil,"Wait for both raid recordings to finish synchronizing." end
        local _,sourceConflicts=J.GetConflicts(db,source,0,1)
        if sourceConflicts>0 then return nil,"Resolve source recording conflicts before merging it." end
        local previous=Record(target,"merge:"..source)
        local targetRecords,sourceRecords=AllRecords(target),AllRecords(source)
        local plan={target=target,source=source,rows={},automatic={},mapping=Copy(previous and previous.mapping or {}),
            token={target=RevisionToken(target),source=RevisionToken(source)}}
        for _,sourceKey in ipairs(Keys(sourceRecords)) do
            local incoming=sourceRecords[sourceKey]
            local known=previous and previous.token and previous.token.heads and previous.token.heads[sourceKey]
            if not string.find(sourceKey,"^merge:") and not string.find(sourceKey,"^recorder:") and sourceKey~="raid:lifecycle" and sourceKey~="raid:alias-decision"
                and not J.Equal(known,plan.token.source.heads[sourceKey]) then
                local key=plan.mapping[sourceKey] or sourceKey
                local current=targetRecords[key]
                local same=current and current.deleted==incoming.deleted and J.Equal(current.value,incoming.value)
                if not same and not (not current and incoming.deleted) then
                    local duplicate
                    if string.find(sourceKey,"^loot:") and not current and not incoming.deleted then
                        for _,candidate in ipairs(Keys(targetRecords)) do
                            local other=targetRecords[candidate]
                            if string.find(candidate,"^loot:") and not other.deleted and other.value
                                and Lower(other.value.item)==Lower(incoming.value.item) and Lower(other.value.recipient)==Lower(incoming.value.recipient) then duplicate=candidate;break end
                        end
                    end
                    if current or duplicate then
                        table.insert(plan.rows,{id=sourceKey,key=key,label=duplicate and "Same drop or a separate allocation?" or sourceKey,
                            sourceValue=Copy(incoming.value),targetValue=Copy(current and current.value or duplicate and targetRecords[duplicate].value),
                            sourceDeleted=incoming.deleted,targetDeleted=current and current.deleted,duplicate=duplicate,
                            choices=duplicate and {"separate","duplicate"} or {"target","source"}})
                    else table.insert(plan.automatic,{key=key,value=Copy(incoming.value),deleted=incoming.deleted}) end
                end
            end
        end
        return plan
    end
    function api.CompareRaids(target,source,offset,limit)
        local plan,reason=MergePlan(target,source);if not plan then return nil,reason end
        local rows,total=Page(plan.rows,offset,limit)
        return {rows=rows,total=total,token=plan.token}
    end
    local function SelectionFingerprint(id,changes)
        local selected={}
        local function Include(key) return key~="raid:alias-decision" and not string.find(key,"^merge:") and not string.find(key,"^recorder:") end
        for key,record in pairs(AllRecords(id)) do if Include(key) then selected[key]={value=record.value,deleted=record.deleted} end end
        for _,change in ipairs(changes) do if Include(change.key) then selected[change.key]={value=change.value,deleted=change.deleted} end end
        return J.Fingerprint(selected)
    end
    function api.MergeRaids(target,source,decisions)
        local allowed,reason=Authorized();if not allowed then return false,reason end
        local plan,failure=MergePlan(target,source);if not plan then return false,failure end
        if type(decisions)~="table" or not J.Equal(decisions.token,plan.token) then return false,"The recordings changed. Compare them again before merging." end
        local changes=plan.automatic
        for _,row in ipairs(plan.rows) do
            local choice=decisions.choices and decisions.choices[row.id]
            if choice~=row.choices[1] and choice~=row.choices[2] then return false,"Choose an outcome for every difference before merging." end
            if choice=="source" or choice=="separate" then
                local value=Copy(row.sourceValue)
                if row.key=="raid:metadata" and value and row.targetValue then
                    value.startedAt=math.min(tonumber(value.startedAt) or 0,tonumber(row.targetValue.startedAt) or 0)
                end
                table.insert(changes,{key=row.key,value=value,deleted=row.sourceDeleted})
                plan.mapping[row.id]=row.key
            elseif choice=="duplicate" then plan.mapping[row.id]=row.duplicate
            else plan.mapping[row.id]=row.key end
        end
        local decision=state.aliasDecisions[plan.target]
        if decision then
            decision=Copy(decision);decision.observed[source]=J.Fingerprint(plan.token.source)
            decision.selectionFingerprint=SelectionFingerprint(plan.target,changes)
            table.insert(changes,{key="raid:alias-decision",value=decision})
        else table.insert(changes,{key="merge:"..source,value={source=source,token=plan.token.source,mapping=plan.mapping}}) end
        local ok,operation=Commit(plan.target,"raid.merge",changes,{subject=Record(source,"raid:metadata").id})
        if ok then ReindexAliases();Queue(plan.target);api.Flush(1) end
        return ok,not ok and operation or nil
    end
    local function AliasNativeConflict(group)
        if not group.decisionConflict then return nil end
        local offset,total=0,0
        repeat
            local entries,count=J.GetConflicts(db,group.id,offset,50);total=count or 0
            for _,entry in ipairs(entries or {}) do for _,key in ipairs(entry.keys) do if key=="raid:alias-decision" then return entry.id end end end
            offset=offset+50
        until offset>=total
    end
    local function AliasPlan(group)
        if state.aliasPlans[group.id] then return state.aliasPlans[group.id] end
        local plan={group=group,token={claims=Copy(group.claims),records={}},all={},rows={}}
        local count=0
        for _,member in ipairs(group.members) do
            if not Raid(member) or not Record(member,"raid:metadata") then return nil,"Wait for every overlapping recording to finish synchronizing." end
            local _,conflicts=J.GetConflicts(db,member,0,1)
            if conflicts>0 then return nil,"Resolve record conflicts in the overlapping recordings before deciding their shared identity." end
            plan.token.records[member]=RevisionToken(member)
            local metadata=Record(member,"raid:metadata")
            for key,record in pairs(AllRecords(member)) do
                if record.pendingCheckpoint then return nil,"Wait for checkpoint data before resolving these recording identities." end
                if key~="raid:alias-decision" and not string.find(key,"^merge:") and not string.find(key,"^recorder:") then
                    local variants=plan.all[key]
                    if not variants then variants={};plan.all[key]=variants;count=count+1 end
                    if count>510 then return nil,"This identity comparison exceeds the atomic record limit. Resolve smaller recording groups first." end
                    local same=false
                    for _,variant in ipairs(variants) do if variant.deleted==record.deleted and J.Equal(variant.value,record.value) then same=true;break end end
                    if not same then table.insert(variants,{revision=member,author="Recording: "..metadata.id,timestamp=metadata.startedAt or 0,value=record.value,deleted=record.deleted}) end
                end
            end
        end
        local awards={}
        for _,key in ipairs(Keys(plan.all)) do
            local variants=plan.all[key]
            if table.getn(variants)>1 then table.insert(plan.rows,{key=key,base=J.GetRecord(db,group.id,key),variants=variants}) end
            local first=variants[1]
            if string.find(key,"^loot:") and not first.deleted and first.value then
                local decision=plan.all["allocation:"..string.sub(key,6)]
                if not (decision and table.getn(decision)==1 and decision[1].value and (decision[1].value.separate or decision[1].value.duplicateOf)) then
                    local signature=Lower(first.value.recipient).."|"..Lower(first.value.item)
                    awards[signature]=awards[signature] or {};table.insert(awards[signature],{key=key,value=first.value})
                end
            end
        end
        for _,signature in ipairs(Keys(awards)) do
            local groupAwards=awards[signature];local first=groupAwards[1]
            for position=2,table.getn(groupAwards) do
                local candidate=groupAwards[position]
                table.insert(plan.rows,{key="alias-award:"..candidate.key,keep=first.key,duplicate=candidate.key,base={value=first.value},variants={
                    {revision="separate",author="Separate allocations",timestamp=0,value={decision="Separate awards",keep=first.value,other=candidate.value}},
                    {revision="duplicate",author="Same physical allocation",timestamp=0,value={decision="Same award",keep=first.value,other=candidate.value}},
                }})
            end
        end
        if table.getn(plan.rows)==0 then
            table.insert(plan.rows,{key="alias-confirm",confirm=true,variants={{revision="confirm",author="Confirm one shared recording",timestamp=0,value={recordings=Copy(group.members)}}}})
        end
        state.aliasPlans[group.id]=plan;return plan
    end
    local function ResolveAlias(group,choices,expected)
        local plan,reason=AliasPlan(group);if not plan then return false,reason end
        if not J.Equal(expected,plan.token) then return false,"The overlapping recordings changed. Review their identities again." end
        local selected={}
        for key,variants in pairs(plan.all) do selected[key]={value=Copy(variants[1].value),deleted=variants[1].deleted} end
        local duplicateChoices={}
        for _,row in ipairs(plan.rows) do
            local choice=choices and choices[row.key];if not choice then return false,"Choose an outcome for every identity difference." end
            local value,deleted,found
            for _,variant in ipairs(row.variants) do if choice.revision==variant.revision then value,deleted,found=variant.value,variant.deleted,true;break end end
            if row.duplicate then
                if not found then return false,"Choose the same physical award or separate awards." end
                if choice.revision=="duplicate" then table.insert(duplicateChoices,row) end
            elseif row.confirm then if not found then return false,"Confirm the shared recording identity." end
            else
                if not found and choice.value and (string.find(row.key,"^sr:") or string.find(row.key,"^loot:")) then value,deleted,found=choice.value,choice.deleted,true end
                if not found then return false,"Choose an available recording variant." end
                if string.find(row.key,"^sr:") and value and table.getn(value.items or {})>1 then return false,"A corrected SR may contain only one item." end
                selected[row.key]={value=Copy(value),deleted=deleted}
            end
        end
        for _,row in ipairs(duplicateChoices) do
            local first,candidate=selected[row.keep],selected[row.duplicate]
            if not first or not candidate or first.deleted or candidate.deleted or Lower(first.value.item)~=Lower(candidate.value.item)
                or Lower(first.value.recipient)~=Lower(candidate.value.recipient) then return false,"These chosen allocations differ. Keep them as separate awards." end
            selected[row.duplicate]={deleted=true}
        end
        local decision={members=Copy(group.members),claims=Copy(group.claims),observed={},selectionFingerprint=J.Fingerprint(selected)}
        for _,member in ipairs(group.members) do if member~=group.id then decision.observed[member]=J.Fingerprint(plan.token.records[member]) end end
        local changes={}
        for _,key in ipairs(Keys(selected)) do local value=selected[key];table.insert(changes,{key=key,value=value.value,deleted=value.deleted}) end
        table.insert(changes,{key="raid:alias-decision",value=decision})
        local valid,failure=Replica.ValidateOperation({changes=changes});if not valid then return false,failure end
        local ok,operation=Commit(group.id,"raid.alias.resolve",changes,{subject="Shared recording identity"})
        if ok then api.Flush(1) end
        return ok,not ok and operation or nil
    end
    function api.GetConflict(id,conflictId,recordIndex,variantIndex)
        id=Canonical(id);recordIndex=math.max(1,tonumber(recordIndex) or 1);variantIndex=math.max(1,tonumber(variantIndex) or 1)
        if string.find(conflictId or "","^alias:") then
            local group=state.aliasGroups[string.sub(conflictId,7)]
            if not group or state.aliasBlocked[id]~=group then return nil,"This identity comparison is no longer pending." end
            local native=AliasNativeConflict(group)
            if native then
                local detail=J.GetConflictRecord(db,group.id,native,recordIndex,variantIndex)
                detail.id=conflictId;detail.heads={coordinator=group.id,conflictId=native,heads=detail.heads};return detail
            end
            local plan,reason=AliasPlan(group);if not plan then return nil,reason end
            local row=plan.rows[recordIndex]
            return {id=conflictId,heads=Copy(plan.token),recordCount=table.getn(plan.rows),record=row and {
                key=row.key,base=Copy(row.base),variant=Copy(row.variants[variantIndex]),variantCount=table.getn(row.variants)}}
        end
        if string.find(conflictId or "","^merge:") then
            local source=string.sub(conflictId,7);local plan,reason=MergePlan(id,source)
            if not plan then return nil,reason end
            local row=plan.rows[recordIndex]
            if not row then return nil,"Use Compare to acknowledge the newly received recording changes." end
            local choice=row.choices[math.min(2,variantIndex)]
            return {id=conflictId,heads=plan.token,recordCount=table.getn(plan.rows),record={key=row.id,base={value=row.targetValue},
                variant={revision=choice,author=choice,timestamp=0,value=(choice=="target" or choice=="duplicate") and row.targetValue or row.sourceValue},variantCount=2}}
        end
        if string.find(conflictId or "","^duplicate:") then
            for _,conflict in ipairs(Ambiguities(id)) do
                if conflict.id==conflictId then
                    local choice=variantIndex==1 and "separate" or "duplicate"
                    return {id=conflictId,heads=conflict.heads,recordCount=1,record={key="allocation:"..string.sub(conflict.second.key,6),
                        base={value=Copy(conflict.first.record.value)},variant={revision=choice,author=choice,timestamp=0,
                            value={decision=choice,first=Copy(conflict.first.record.value),second=Copy(conflict.second.record.value)}},variantCount=2}}
                end
            end
            return nil,"This allocation comparison is no longer pending."
        end
        if J.GetConflictRecord then return J.GetConflictRecord(db,id,conflictId,recordIndex,variantIndex) end
        local conflict=J.GetConflict(db,id,conflictId)
        if not conflict then return nil,"This conflict is no longer pending." end
        local record=conflict.records[recordIndex]
        if not record then return nil,"This conflict record is no longer available." end
        local variant=record.variants[variantIndex]
        return {id=conflict.id,heads=Copy(conflict.heads),recordCount=table.getn(conflict.records),record={key=record.key,
            base=Copy(record.base),variant=Copy(variant),variantCount=table.getn(record.variants)}}
    end
    function api.ResolveConflict(id,conflictId,choices,expectedHeads)
        local allowed,reason=Authorized();if not allowed then return false,reason end
        id=Canonical(id)
        if string.find(conflictId or "","^alias:") then
            local group=state.aliasGroups[string.sub(conflictId,7)]
            if not group or state.aliasBlocked[id]~=group then return false,"This identity comparison is no longer pending." end
            local native=AliasNativeConflict(group)
            if native then
                if type(expectedHeads)~="table" or expectedHeads.coordinator~=group.id or expectedHeads.conflictId~=native then return false,"The identity decisions changed. Review them again." end
                return api.ResolveConflict(group.id,native,choices,expectedHeads.heads)
            end
            return ResolveAlias(group,choices,expectedHeads)
        end
        if string.find(conflictId or "","^merge:") then
            local values={};for key,choice in pairs(choices or {}) do values[key]=choice.revision end
            return api.MergeRaids(id,string.sub(conflictId,7),{token=expectedHeads,choices=values})
        end
        if string.find(conflictId or "","^duplicate:") then
            for _,conflict in ipairs(Ambiguities(id)) do
                if conflict.id==conflictId then
                    if not J.Equal(expectedHeads,conflict.heads) then return false,"The allocation changed. Review it again." end
                    local key="allocation:"..string.sub(conflict.second.key,6);local choice=choices and choices[key] and choices[key].revision
                    if choice~="separate" and choice~="duplicate" then return false,"Choose separate allocations or the same drop." end
                    local ok,op=Commit(id,"loot.reconcile",{{key=key,value={duplicateOf=choice=="duplicate" and string.sub(conflict.first.key,6) or nil,
                        separate=choice=="separate",observed=conflict.heads}}},{subject="Allocation comparison"})
                    return ok,not ok and op or nil
                end
            end
            return false,"This allocation comparison is no longer pending."
        end
        local conflict=J.GetConflict(db,id,conflictId)
        if not conflict then return false,"This conflict is no longer pending." end
        local changes={}
        for _,record in ipairs(conflict.records) do
            local choice=choices and choices[record.key];if not choice then return false,"Choose a value for every affected record." end
            local value,deleted=choice.value,choice.deleted
            if choice.revision then
                local found
                for _,variant in ipairs(record.variants) do if variant.revision==choice.revision then value,deleted,found=variant.value,variant.deleted,true;break end end
                if not found then return false,"The selected variant changed. Review the conflict again." end
            elseif string.find(record.key,"^sr:") then
                if type(value)~="table" or type(value.items)~="table" or table.getn(value.items)>1 then return false,"A corrected SR may contain only one item." end
            elseif not string.find(record.key,"^loot:") then return false,"Select an existing variant for this record." end
            table.insert(changes,{key=record.key,value=Copy(value),deleted=deleted})
        end
        for _,change in ipairs(changes) do
            if change.key=="raid:alias-decision" and change.value then change.value.selectionFingerprint=SelectionFingerprint(id,changes) end
        end
        local valid,failure=Replica.ValidateOperation({changes=changes});if not valid then return false,failure end
        local ok,operation=J.Resolve(db,id,conflictId,changes,{subject="Officer conflict decision"},expectedHeads)
        if ok and operation then api.OnOperation(operation,"applied",true) end
        return ok,not ok and operation or nil
    end
    api._state=state;api._db=db;api._record=Record;api._records=AllRecords;api._canonical=Canonical
    api._token=RevisionToken;api._commit=Commit;api._conflicts=Conflicts;api._copy=Copy;api._page=Page;api._reindex=ReindexAliases
    ReindexAliases()
    for id in pairs(J.Ensure(db).raids) do if Canonical(id)==id then Queue(id) end end
    return api
end
