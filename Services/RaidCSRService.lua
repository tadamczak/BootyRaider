local Raider = BootyRaider
local Service = {}
Raider.Services.RaidCSR = Service
local WINDOW = 60 * 24 * 60 * 60
local known = { ["Blackwing Lair"]=true,["Molten Core"]=true,["Onyxia's Lair"]=true,["Karazhan10"]=true,["Zul'Gurub"]=true,["Other"]=true }
local changes, sequence, generation = {}, 0, 1
local stats = {builds=0,recomputedPlayers=0,indexBuilds=0,cacheHits=0}
local function Name(value) return string.lower(tostring(value or "")) end
local function Date(entry) return tonumber(entry.createdAt) or tonumber(entry.startedAt) or tonumber(entry.savedAt) or tonumber(entry.completedAt) or 0 end
local function Same(left,right)
    for key,value in pairs(left or {}) do if not right or right[key]~=value then return false end end
    for key,value in pairs(right or {}) do if not left or left[key]~=value then return false end end
    return true
end
local function Copy(value) local result={};for key,item in pairs(value or {}) do result[key]=item end;return result end

function Service.Invalidate(raidId,names)
    if not raidId then generation=generation+1;return end
    sequence=sequence+1
    local change=changes[raidId] or {names={}}
    changes[raidId]=change;change.revision=sequence
    if names==nil then change.all=sequence
    else
        for key,value in pairs(names) do
            local name=type(key)=="number" and value or key
            if value~=false then change.names[Name(name)]=sequence end
        end
    end
end
function Service.Reset()
    changes={};sequence=0;generation=generation+1
    for key in pairs(stats) do stats[key]=0 end
end
function Service.GetStats() return Copy(stats) end

local function IndexMembers(entry)
    local members={}
    for _,member in ipairs(entry.members or {}) do
        local key=Name(member.name)
        if key~="" then
            members[key]=members[key] or {};table.insert(members[key],member)
        end
    end
    return members
end
local function DirtyMembers(dirty,members)
    for name in pairs(members or {}) do dirty[name]=true end
end
local function Inputs(cache,name)
    local entries={_csrNameIds=cache.nameIds,_csrLabels=cache.labels}
    for _,entry in ipairs(cache.ordered) do
        local members=cache.raids[entry.syncRaidId].members[name]
        if members then
            local slice=Copy(entry);slice.members=members;table.insert(entries,slice)
        end
    end
    return entries
end
local function Order(cache,now,selected,archives,awards)
    local ordered={};cache.expiry=nil;cache.future=nil
    for _,source in pairs(cache.raids) do
        local entry=source.entry
        local at=Date(entry)
        local raidName=tostring(entry.raidName or "Other")
        local filter=known[raidName] and raidName or "Other"
        if Raider.Services.CSR.IsSavedAndEnded(entry) and entry.csrEnabled==true and (not selected or selected[filter]) then
            if at>now then cache.future=math.min(cache.future or at,at)
            elseif archives or awards or at>=now-WINDOW then
                table.insert(ordered,entry)
                if at+WINDOW>=now then cache.expiry=math.min(cache.expiry or at+WINDOW,at+WINDOW) end
            end
        end
    end
    table.sort(ordered,function(a,b)
        local left,right=Date(a),Date(b)
        if left==right then return tostring(a.syncRaidId or a.id or "")<tostring(b.syncRaidId or b.id or "") end
        return left<right
    end)
    cache.ordered=ordered
end
local function SortPlayers(left,right)
    local a,b=Name(left.name),Name(right.name)
    if a~=b then return a<b end
    if type(left.itemId)~=type(right.itemId) then return type(left.itemId)=="number" end
    if type(left.itemId)=="number" then return left.itemId<right.itemId end
    return tostring(left.itemId)<tostring(right.itemId)
end

-- Cache lifetime belongs to the view's reusable target. No timer, hidden scan or
-- persistent derived balance is needed. Projection explicitly invalidates names.
function Service.BuildSummary(entries,rules,currentTime,target,rosterData,selectedRaids,searchText,showArchived)
    local baseline=Raider.Services.CSR
    for _,entry in ipairs(entries or {}) do
        if not entry.syncRaidId then
            if target and target._raidCSR then
                -- Lua 5.0 remembers sizes changed by table.insert. Baseline
                -- scratch arrays use indexed writes, so hand it fresh arrays.
                target._raidCSR=nil;target.players={};target.orderedScratch=nil
            end
            return baseline.BuildSummary(entries,rules,currentTime,target,rosterData,selectedRaids,searchText,showArchived)
        end
    end
    local summary=target or {players={}}
    local cache=summary._raidCSR
    if not cache or cache.generation~=generation then cache={generation=generation,raids={},players={},ordered={}};summary._raidCSR=cache end
    local now=tonumber(currentTime) or time()
    local visibility=type(showArchived)=="table" and showArchived or {}
    local archives=showArchived==true or visibility.showArchived==true
    local awards=showArchived==true or visibility.showAwarded==true
    local all=cache.archives~=archives or cache.awards~=awards or cache.filtered~=(selectedRaids~=nil)
        or not Same(cache.filter,selectedRaids) or cache.now and now<cache.now
        or cache.expiry and now>cache.expiry or cache.future and now>=cache.future
    local dirty,seen={},{}
    local changed=all and true or false
    for _,entry in ipairs(entries or {}) do
        if baseline.IsSavedAndEnded(entry) then
            local id=entry.syncRaidId
            seen[id]=true
            local previous=cache.raids[id]
            local change=changes[id] or {}
            local revision=change.revision or 0
            if not previous or previous.entry~=entry or previous.revision~=revision then
                changed=true
                local members=IndexMembers(entry)
                if not previous or previous.revision==revision or (change.all or 0)>previous.revision then
                    DirtyMembers(dirty,previous and previous.members);DirtyMembers(dirty,members)
                else
                    for name,at in pairs(change.names) do if at>previous.revision then dirty[name]=true end end
                    for name in pairs(previous.members) do if not members[name] then dirty[name]=true end end
                    for name in pairs(members) do if not previous.members[name] then dirty[name]=true end end
                end
                cache.raids[id]={entry=entry,members=members,revision=revision}
            end
        end
    end
    for id,source in pairs(cache.raids) do
        if not seen[id] then DirtyMembers(dirty,source.members);cache.raids[id]=nil;changed=true end
    end
    if changed then
        Order(cache,now,selectedRaids,archives,awards)
        local nameIds,labels=baseline.BuildItemIndex(cache.ordered)
        stats.indexBuilds=stats.indexBuilds+1
        if not Same(cache.nameIds,nameIds) then all=true end
        if not Same(cache.labels,labels) then
            for name,result in pairs(cache.players) do
                for _,player in ipairs(result.players) do
                    if (cache.labels or {})[player.itemId]~=labels[player.itemId] then dirty[name]=true end
                end
            end
        end
        cache.nameIds,cache.labels=nameIds,labels
    end
    if all then
        for _,source in pairs(cache.raids) do DirtyMembers(dirty,source.members) end
        for name in pairs(cache.players) do dirty[name]=true end
    end
    local recomputed=0
    for name in pairs(dirty) do
        local inputs=Inputs(cache,name)
        if table.getn(inputs)==0 then cache.players[name]=nil
        else
            cache.players[name]=baseline.BuildSummary(inputs,rules,now,cache.players[name],rosterData,nil,"",showArchived)
            -- Only calculated balances/sources survive. Do not retain one
            -- shallow raid metadata table per player and source in scratch.
            cache.players[name].orderedScratch=nil
            stats.recomputedPlayers=stats.recomputedPlayers+1;recomputed=recomputed+1
        end
    end
    if recomputed==0 and not changed then stats.cacheHits=stats.cacheHits+1 end
    stats.builds=stats.builds+1
    cache.now,cache.archives,cache.awards,cache.filtered=now,archives,awards,selectedRaids~=nil
    if all or changed then cache.filter=Copy(selectedRaids) end
    summary.players=summary.players or {};summary.states=summary.states or {}
    for index=table.getn(summary.players),1,-1 do table.remove(summary.players,index) end
    for name in pairs(summary.states) do summary.states[name]=nil end
    local query=Name(searchText)
    summary.provisional=nil
    for name,result in pairs(cache.players) do
        for key,state in pairs(result.states or {}) do summary.states[key]=state end
        if query=="" or string.find(name,query,1,true) then
            for _,player in ipairs(result.players) do
                table.insert(summary.players,player)
                if player.provisional then summary.provisional=true end
            end
        end
    end
    table.sort(summary.players,SortPlayers)
    summary.orderedScratch=cache.ordered
    summary.cutoff=now-WINDOW;summary.now=now;summary.showArchived=archives;summary.showAwarded=awards;summary.pointsPerItem=10
    summary.rosterLootRanks=nil
    return summary
end
