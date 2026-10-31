local Raider=BootyRaider
Raider.Services=Raider.Services or {}
local Sync={PREFIX="BRSYNC1",protocol=3,policy=2}
Raider.Services.RaidSync=Sync
-- Accommodate one incoming stream per supported peer while retaining the
-- aggregate byte cap and incremental single-job codec budget.
Sync.limits={packet=240,rate=1024,burst=2048,packetsPerTick=8,codecNodes=128,
    peers=12,outbox=4,incoming=12,bufferBytes=2097152,window=4,summary=8,range=16,retry=3,timeout=15}

-- The installed 1.12 addons use SendAddonMessage(prefix,text,"GUILD") and
-- CHAT_MSG_ADDON(prefix,text,channel,sender). GUILD + recipient routing avoids
-- assuming the later WHISPER API. Routing is not encryption or authentication.
local function Count(values) return table.getn(values) end
local function Text(value,maximum)
    return type(value)=="string" and string.len(value)>0 and string.len(value)<=maximum and not string.find(value,"[%c|~]")
end
local function Session(value) return Text(value,32) and not string.find(value,":",1,true) end
local function Integer(value,maximum)
    return type(value)=="number" and value==value and value>=0 and value<=maximum and value==math.floor(value)
end
local function Value(value) if type(value)=="function" then return value() end;return value end
local function Fields(text)
    local result,start={},1
    while true do
        local ending=string.find(text,"~",start,true)
        if not ending then table.insert(result,string.sub(text,start));return result end
        table.insert(result,string.sub(text,start,ending-1));start=ending+1
        if Count(result)>8 then return nil end
    end
end
local function CountMap(values) local count=0;for _ in pairs(values) do count=count+1 end;return count end
local function Scope(value)
    return type(value)=="string" and string.len(value)>0 and string.len(value)<=100 and not string.find(value,"%c")
end
-- Raw pipes are chat escapes in the native client. Scope values escape reserved bytes.
local function EncodeScope(value)
    local encoded=string.gsub(value,"%%","%%25")
    encoded=string.gsub(encoded,"|","%%7c")
    encoded=string.gsub(encoded,"~","%%7e");return encoded
end
local function DecodeScope(value)
    if type(value)~="string" then return nil end
    local remainder=string.gsub(string.gsub(string.gsub(value,"%%25",""),"%%7c",""),"%%7e","")
    if string.find(remainder,"%%") then return nil end
    return string.gsub(string.gsub(string.gsub(value,"%%7e","~"),"%%7c","|"),"%%25","%%")
end
local messages={
    ["disabled"]="Synchronization is off.",
    ["unavailable"]="Synchronization is waiting for the guild directory and client messaging.",
    ["guild-scope-changed"]="Guild changed. Previous guild data will not be sent.",
    ["guild-scope-mismatch"]="Saved data belongs to another guild. Synchronization is stopped.",
    ["officer-authority-required"]="Current guild officer access is required.",
    ["officer-authority-or-messaging-unavailable"]="Officer access or client messaging is unavailable.",
    ["unauthorized-original-author"]="A received change has no current officer author. Review the blocked officer.",
    ["source-timeout"]="An officer stopped responding. Other available sources can continue.",
    ["transfer-timeout"]="A transfer was interrupted. Missing data can resume from another officer.",
    ["send-failed"]="The client could not send a synchronization message.",
    ["incompatible-peer"]="An officer uses an incompatible version or guild scope.",
    ["peer-limit"]="The officer connection limit has been reached.",
    ["peer-authority-lost"]="An officer no longer has access; their transfer was stopped.",
    ["peer-session-changed"]="An officer reconnected. Missing changes are being checked."
}

function Sync.New(options)
    options=options or {}
    local self={options=options,journal=options.journal or Raider.Services.RaidJournal,
        codec=options.codec or Raider.Services.RaidSyncCodec,db=options.db,enabled=false,
        peers={},incompatiblePeers={},retiredSessions={},outbox={},controls={},incoming={},completed={},decodes={},exports={},dependencies={},sentOperations={},receipts={},receiptRanges=0,
        sequence=0,generation=0,revision=0,tokens=Sync.limits.burst,bufferBytes=0,
        stats={sentBytes=0,receivedBytes=0,applied=0,duplicates=0,conflicts=0,retries=0,rejected=0}}
    local function Now() return options.now and options.now() or 0 end
    local function Status(reason)
        self.reason=reason;self.revision=self.revision+1;self.statusDirty=nil
        if options.onStatus then options.onStatus(self:GetStatus()) end
    end
    local function Authority(name)
        return type(options.authorize)=="function" and options.authorize(name,self.scope)==true
    end
    local function Allowed(raidId)
        return not raidId or (not options.isRaidEnabled or options.isRaidEnabled(raidId)) and not (self.db.raidSyncDisabled and self.db.raidSyncDisabled[raidId])
    end
    local function ActiveRaid() local id=Value(options.activeRaidId);return Allowed(id) and id or nil end
    local function Summary(offset,limit,priority)
        return self.journal.GetSyncSummary(self.db,offset,limit,priority,Allowed,self.db.raidSyncPolicyRevision or 0)
    end
    local function Priority(raidId)
        if raidId and raidId==ActiveRaid() then return 1 end
        local priority=options.priority and options.priority(raidId) or 3
        return priority==1 and 1 or priority==2 and 2 or 3
    end
    local function Combat()
        local active=Value(options.inCombat)==true
        if active then
            if not self.combatPauseAt then self.combatPauseAt=Now() end
        elseif self.combatPauseAt then
            local duration=math.max(0,Now()-self.combatPauseAt);self.combatPauseAt=nil
            if self.request and self.request.priority>1 then self.request.activity=self.request.activity+duration end
            if self.outgoing and self.outgoing.priority>1 then self.outgoing.activity=self.outgoing.activity+duration end
            for _,transfer in pairs(self.incoming) do if transfer.priority>1 then transfer.activity=transfer.activity+duration end end
            for _,receipt in pairs(self.completed) do receipt.time=receipt.time+duration end
        end
        return active
    end
    local function Ready()
        if not self.enabled then return false,"disabled" end
        if Value(options.scope)~=self.scope then self:Stop("guild-scope-changed");return false,"guild-scope-changed" end
        if not Authority(self.actor) then self:Stop("officer-authority-required");return false,"officer-authority-required" end
        return true
    end
    local function Reject(reason)
        self.stats.rejected=self.stats.rejected+1;self.lastError=reason;self.revision=self.revision+1;self.statusDirty=true;return false,reason
    end
    local function Control(text)
        if string.len(text)>Sync.limits.packet then return false,"packet-limit" end
        if Count(self.controls)>=64 then return false,"control-backpressure" end
        -- ACKs and coalesced discovery have no durable side effects.
        for _,queued in ipairs(self.controls) do if queued==text then return true end end
        table.insert(self.controls,text);return true
    end
    local function Hello(target)
        return Control(table.concat({"H",target or "*",self.session,tostring(Sync.protocol),tostring(self.journal.schema),tostring(Sync.policy),tostring(self.generation),EncodeScope(self.scope)},"~"))
    end
    local function Queue(target,payload,priority)
        if Count(self.outbox)>=Sync.limits.outbox then return false,"outbox-backpressure" end
        local peer=self.peers[target]
        if not peer or peer.unavailable or peer.blocked then return false,"handshake-pending" end
        payload.scope=self.scope
        payload.recipientSession=peer.session
        table.insert(self.outbox,{target=target,payload=payload,priority=priority or 1})
        return true
    end
    local function Request(peer,payload,priority)
        self.sequence=self.sequence+1;payload.request=self.sequence
        local queued,failure=Queue(peer.name,payload,priority)
        if not queued then return false,failure end
        self.request={peer=peer.name,id=payload.request,payload=payload,priority=priority,started=Now(),activity=Now()}
        return true
    end
    local function ReleaseIncoming(key)
        local transfer=self.incoming[key]
        if transfer then self.bufferBytes=self.bufferBytes-transfer.bytes;self.incoming[key]=nil end
    end
    local function ClearPeerWork(name)
        if self.request and self.request.peer==name then self.request=nil end
        if self.outgoing and self.outgoing.target==name then self.outgoing=nil end
        if self.encoding and self.encoding.target==name then self.encoding=nil end
        for index=Count(self.outbox),1,-1 do if self.outbox[index].target==name then table.remove(self.outbox,index) end end
        for index=Count(self.exports),1,-1 do if self.exports[index].peer==name then table.remove(self.exports,index) end end
        for index=Count(self.decodes),1,-1 do
            local decode=self.decodes[index]
            if decode.sender==name then self.bufferBytes=self.bufferBytes-decode.bytes;table.remove(self.decodes,index) end
        end
        for key,transfer in pairs(self.incoming) do if transfer.sender==name then ReleaseIncoming(key) end end
        for key in pairs(self.completed) do if string.sub(key,1,string.len(name)+1)==name..":" then self.completed[key]=nil end end
        for id,sent in pairs(self.sentOperations) do if sent.peer==name then self.sentOperations[id]=nil end end
        for _,dependency in pairs(self.dependencies) do if dependency.peer==name then dependency.peer=nil end end
        for index=Count(self.controls),1,-1 do
            local fields=Fields(self.controls[index]);if fields and fields[2]==name then table.remove(self.controls,index) end
        end
    end
    local function Disconnect(peer,reason)
        if peer.connected and options.onDisconnected then options.onDisconnected(peer.name,reason) end
        peer.connected=false
    end
    local function InterruptPeer(name,reason)
        local peer=self.peers[name]
        if not peer then return end
        ClearPeerWork(name);Disconnect(peer,reason)
        peer.unavailable=true;peer.interrupted=reason;peer.needsSummary=nil;peer.summary=nil;peer.offset=0;peer.contactConfirmed=nil
        self.lastError=reason;self.revision=self.revision+1;self.statusDirty=true
    end
    local function RemovePeer(name,reason)
        local peer=self.peers[name]
        if peer then Disconnect(peer,reason) end
        ClearPeerWork(name);self.peers[name]=nil
        local receipts=self.receipts[name]
        for _,raid in pairs(receipts or {}) do for _,ranges in pairs(raid) do self.receiptRanges=self.receiptRanges-Count(ranges) end end
        self.receipts[name]=nil
        self.lastError=reason or "peer-authority-lost";self.revision=self.revision+1;self.statusDirty=true
    end
    local function RetireSession(name,session)
        if not self.retiredSessions[name] and CountMap(self.retiredSessions)>=Sync.limits.peers then
            for old in pairs(self.retiredSessions) do if not self.peers[old] then self.retiredSessions[old]=nil;break end end
        end
        local retired=self.retiredSessions[name] or {};self.retiredSessions[name]=retired
        if Count(retired)>=8 then table.remove(retired,1) end
        table.insert(retired,session)
    end
    local function PeerBusy(peer)
        local name=peer.name
        if peer.needsSummary or self.request and self.request.peer==name or self.outgoing and self.outgoing.target==name
            or self.encoding and self.encoding.target==name then return true end
        for _,queued in ipairs(self.outbox) do if queued.target==name then return true end end
        for _,queued in ipairs(self.exports) do if queued.peer==name then return true end end
        for _,queued in ipairs(self.decodes) do if queued.sender==name then return true end end
        for _,queued in pairs(self.incoming) do if queued.sender==name then return true end end
        return false
    end
    local function Confirm(sender,sent)
        local peers=self.receipts[sender] or {};self.receipts[sender]=peers
        local raid=peers[sent.raidId] or {};peers[sent.raidId]=raid
        local ranges=raid[sent.origin] or {};raid[sent.origin]=ranges
        local value=sent.sequence;local position=1
        while ranges[position] and ranges[position][2]<value-1 do position=position+1 end
        local range=ranges[position]
        local already=range and range[1]<=value and range[2]>=value
        if range and range[1]<=value+1 then
            range[1]=math.min(range[1],value);range[2]=math.max(range[2],value)
            local following=ranges[position+1]
            if following and following[1]<=range[2]+1 then range[2]=following[2];table.remove(ranges,position+1);self.receiptRanges=self.receiptRanges-1 end
        elseif self.receiptRanges<512 then table.insert(ranges,position,{value,value});self.receiptRanges=self.receiptRanges+1 end
        self.statusDirty=true
        return not already
    end
    local function ValidateSummary(summary)
        if type(summary)~="table" or summary.schema~=self.journal.schema or type(summary.entries)~="table"
            or Count(summary.entries)>Sync.limits.summary or not Integer(summary.total,9007199254740991)
            or (summary.nextOffset~=nil and not Integer(summary.nextOffset,9007199254740991)) then return false end
        for key,entry in pairs(summary.entries) do
            if not Integer(key,Count(summary.entries)) or key<1 or type(entry)~="table" or not Text(entry.raidId,300)
                or not Text(entry.origin,256) or not Integer(entry.first,9007199254740991) or entry.first<1
                or not Integer(entry.last,9007199254740991) or entry.last<entry.first
                or not Integer(entry.high,9007199254740991) or entry.high<entry.last then return false end
        end
        return true
    end
    local function Dependency(operation,peer,restore)
        for _,change in ipairs(operation.changes or {}) do
            for _,id in ipairs(change.bases or (change.base and {change.base} or {})) do
                local known=self.journal.GetOperation(self.db,id)
                if not known or (restore and known.compacted) then
                    if CountMap(self.dependencies)>=128 and not self.dependencies[id] then return false,"dependency-limit" end
                    self.dependencies[id]={peer=peer,raidId=operation.raidId}
                end
            end
        end
        return true
    end
    local function Dispatch(peer,payload,receiptId,receiptSession)
        if peer.blocked then return true,"blocked-peer" end
        if type(payload)~="table" or payload.scope~=self.scope then return Reject("invalid-message-scope") end
        -- A surviving sender can still have chunks addressed to our previous
        -- client process. Request numbers alone restart at one after login.
        if not Text(payload.recipientSession,32) then return Reject("invalid-recipient-session") end
        if payload.recipientSession~=self.session then return true,"stale-recipient-session" end
        if not Integer(payload.request,9007199254740991) or payload.request<1 then return Reject("invalid-request") end
        local kind=payload.type
        local function Busy()
            Control(table.concat({"B",peer.name,peer.session,tostring(payload.request)},"~"));return true,"source-busy"
        end
        if kind=="summary-request" then
            if not Integer(payload.offset,9007199254740991) then return Reject("invalid-summary-offset") end
            local summary,failure=Summary(payload.offset,Sync.limits.summary,ActiveRaid())
            if not summary then return Reject(failure) end
            local queued=Queue(peer.name,{type="summary",request=payload.request,summary=summary,activeRaidId=ActiveRaid()},1)
            if not queued then return Busy() end
            return true
        elseif kind=="range-request" then
            if not Text(payload.raidId,300) or not Text(payload.origin,256) or not Integer(payload.first,9007199254740991)
                or payload.first<1 or not Integer(payload.last,9007199254740991) or payload.last<payload.first
                or payload.last-payload.first>=Sync.limits.range then return Reject("invalid-range") end
            if not Allowed(payload.raidId) then Queue(peer.name,{type="done",request=payload.request,missing=true},1);return true,"raid-sync-disabled" end
            if Count(self.exports)>=8 then return Busy() end
            table.insert(self.exports,{peer=peer.name,request=payload.request,raidId=payload.raidId,origin=payload.origin,
                cursor=payload.first,last=payload.last,priority=Priority(payload.raidId)})
            return true
        elseif kind=="operation-request" then
            if not Text(payload.id,300) then return Reject("invalid-operation-request") end
            local operation=self.journal.GetOperation(self.db,payload.id)
            if operation and Allowed(operation.raidId) then
                if Count(self.exports)>=8 then return Busy() end
                table.insert(self.exports,{peer=peer.name,request=payload.request,operation=operation,priority=Priority(operation.raidId)})
            else if not Queue(peer.name,{type="done",request=payload.request,missing=true},1) then return Busy() end end
            return true
        end
        local request=self.request
        if not request or request.peer~=peer.name or request.id~=payload.request then return true,"stale-response" end
        request.activity=Now()
        if kind=="summary" then
            if request.payload.type~="summary-request" or not ValidateSummary(payload.summary) then return Reject("invalid-summary") end
            if payload.summary.nextOffset and (payload.summary.nextOffset<=request.payload.offset
                or payload.summary.nextOffset>payload.summary.total or Count(payload.summary.entries)==0) then return Reject("invalid-summary-cursor") end
            if payload.activeRaidId~=nil and not Text(payload.activeRaidId,300) then return Reject("invalid-active-raid") end
            for index=Count(payload.summary.entries),1,-1 do if not Allowed(payload.summary.entries[index].raidId) then table.remove(payload.summary.entries,index) end end
            peer.activeRaidId=Allowed(payload.activeRaidId) and payload.activeRaidId or nil
            peer.summary=payload.summary;peer.needsSummary=false;self.request=nil
            return true
        elseif kind=="operation" then
            local operation=payload.operation
            if type(operation)~="table" or not Authority(operation.author) then return Reject("unauthorized-original-author") end
            if request.payload.type=="operation-request" then
                if request.payload.id~=operation.id then return Reject("unexpected-operation") end
            elseif request.payload.type=="range-request" then
                local wanted=request.payload
                if operation.raidId~=wanted.raidId or operation.origin~=wanted.origin or not Integer(operation.sequence,9007199254740991)
                    or operation.sequence<wanted.first or operation.sequence>wanted.last then return Reject("operation-outside-range") end
            else return Reject("unexpected-operation") end
            if not Allowed(operation.raidId) then return true,"raid-sync-disabled" end
            local validator=payload.checkpoint and options.validateCheckpoint or options.validateOperation
            if validator then
                local valid,failure=validator(operation,self.scope,peer.name)
                if not valid then return Reject(failure or "invalid-domain-operation") end
            end
            if operation.compacted and payload.checkpoint~=true then return Reject("checkpoint-envelope-required") end
            if payload.checkpoint and type(self.journal.ApplyCheckpointEntry)~="function" then return Reject("checkpoint-unsupported") end
            local apply=payload.checkpoint and self.journal.ApplyCheckpointEntry or self.journal.Apply
            local applied,reason=apply(self.db,operation)
            if not applied then
                if reason=="missing-dependency" or reason=="checkpoint-required" then
                    local ok,failure=Dependency(operation,peer.name,reason=="checkpoint-required")
                    if not ok then return Reject(failure) end
                    return true,"dependency-pending"
                end
                return Reject(reason)
            end
            self.dependencies[operation.id]=nil
            self.lastError=nil
            -- A validated complete export also proves that this source held the
            -- same operation in RAM when it sent it; no disk claim is inferred.
            Confirm(peer.name,{raidId=operation.raidId,origin=operation.origin,sequence=operation.sequence})
            if receiptId then Control(table.concat({"R",peer.name,receiptSession,receiptId},"~")) end
            if reason=="duplicate" then self.stats.duplicates=self.stats.duplicates+1
            else
                self.stats.applied=self.stats.applied+1
                if reason=="conflict" then self.stats.conflicts=self.stats.conflicts+1 end
                if options.onApply and reason~="checkpoint-marker" then options.onApply(operation,reason,peer.name,self.scope) end
                self:NotifyChanged()
            end
            return true,reason
        elseif kind=="done" then
            if request.payload.type=="summary-request" then return Reject("unexpected-done") end
            if payload.missing then
                peer.cooldown=Now()+Sync.limits.timeout
                if request.payload.id and self.dependencies[request.payload.id] then self.dependencies[request.payload.id].peer=nil end
            end
            self.request=nil;return true
        end
        return Reject("unknown-message")
    end

    function self:GetStatus(raidId)
        local peers,available,confirmed,interrupted={},0,0,false
        local hasError=self.lastError and self.lastError~="source-timeout" and self.lastError~="transfer-timeout" and self.lastError~="peer-session-changed" or false
        local confirmedNames={}
        for name,peer in pairs(self.peers) do
            -- A validated message is newer evidence than the cached roster it
            -- arrived against. Only a subsequent roster revision can override it.
            local witnessed=options.presenceRevision and peer.presenceRevision==options.presenceRevision()
            local stale=options.isOnline and not options.isOnline(name) and not witnessed
                or not options.isOnline and Now()-(peer.seen or 0)>120
            local authorized=Authority(name)
            local busy=PeerBusy(peer)
            local connecting=not peer.connected and not peer.blocked and not peer.unavailable and authorized and busy
            local fresh=peer.connected and not peer.blocked and not peer.unavailable and not stale and authorized
            local receipts=self.receipts[name]
            local received=fresh and receipts and (raidId and receipts[raidId] and next(receipts[raidId])~=nil or not raidId and next(receipts)~=nil) and true or false
            if fresh then available=available+1 end
            if received then confirmed=confirmed+1;table.insert(confirmedNames,name) end
            if peer.interrupted then interrupted=true end
            if peer.blocked then hasError=true end
            local status=not authorized and "No officer access" or peer.blocked and "Blocked" or peer.interrupted and "Sync interrupted" or connecting and "Connecting" or peer.unavailable and "Unavailable" or stale and "Possibly stale"
                or self.request and self.request.peer==name and "Synchronizing" or received and "Received changes" or "Available"
            local syncState=peer.blocked and "error" or peer.interrupted and "interrupted" or connecting and "pending" or not fresh and "offline" or busy and "pending" or "synced"
            table.insert(peers,{name=name,status=status,syncState=syncState,activeRaidId=peer.activeRaidId,available=fresh,compatible=true,lastSeen=peer.seen,confirmed=received,
                message=peer.interrupted and "Sync interrupted. Stored changes are safe; retry when the officer is available."
                    or received and "This officer holds some raid data. Check Synchro Log for individual deliveries." or peer.blocked and "Received data was rejected. Retry after reviewing the cause." or nil})
        end
        for name,peer in pairs(self.incompatiblePeers) do
            if not self.peers[name] then table.insert(peers,{name=name,status="Incompatible",compatible=false,lastSeen=peer.seen,message="Version, data schema or guild scope differs."}) end
        end
        table.sort(peers,function(left,right) return left.name<right.name end)
        local pending=Count(self.outbox)+Count(self.exports)+Count(self.decodes)+Count(self.controls)+CountMap(self.incoming)
            +(self.request and 1 or 0)+(self.outgoing and 1 or 0)+(self.encoding and 1 or 0)+(self.announce and 1 or 0)
        if raidId then
            -- Incoming envelopes do not reveal their raid until decoding. Keep
            -- the status pending rather than claiming a completed exchange.
            pending=Count(self.decodes)+CountMap(self.incoming)+(self.announce and 1 or 0)
            for _,message in ipairs(self.outbox) do local p=message.payload;if p.raidId==raidId or p.operation and p.operation.raidId==raidId then pending=pending+1 end end
            for _,task in ipairs(self.exports) do if task.raidId==raidId or task.operation and task.operation.raidId==raidId then pending=pending+1 end end
            if self.encoding and self.encoding.receipt and self.encoding.receipt.raidId==raidId then pending=pending+1 end
            local sent=self.outgoing and self.sentOperations[self.outgoing.id];if sent and sent.raidId==raidId then pending=pending+1 end
            if self.request and (self.request.payload.raidId==raidId or self.request.payload.type=="summary-request") then pending=pending+1 end
            for _,peer in pairs(self.peers) do if not peer.unavailable and not peer.blocked and peer.needsSummary then pending=pending+1 end end
        end
        local message
        if not self.enabled then message=messages[self.reason] or "Synchronization is stopped."
        elseif self.lastError and messages[self.lastError] then message=messages[self.lastError]
        elseif self.lastError then message="Received data was rejected. Review the blocked officer and retry."
        elseif available==0 then message="Waiting for another officer to come online. Your raid is kept on this character."
        elseif confirmed==0 then message="Checking raid updates with online officers."
        elseif pending>0 then message="Sending and receiving raid updates."
        else table.sort(confirmedNames);message="Raid updates checked with "..table.concat(confirmedNames,", ")..". See Synchro Log for received changes." end
        return {enabled=self.enabled,localOnly=confirmed==0,compatible=available>0 or CountMap(self.incompatiblePeers)==0,reason=self.reason,message=message,
            lastError=self.lastError,interrupted=interrupted,hasError=hasError,scope=self.scope,revision=self.revision,
            peers=peers,peerCount=Count(peers),availableCount=available,confirmedCount=confirmed,pending=pending,queued=Count(self.outbox),receiving=CountMap(self.incoming),
            bufferBytes=self.bufferBytes,request=self.request and self.request.payload.type or nil,
            sentBytes=self.stats.sentBytes,receivedBytes=self.stats.receivedBytes,applied=self.stats.applied,
            duplicates=self.stats.duplicates,conflicts=self.stats.conflicts,retries=self.stats.retries,rejected=self.stats.rejected}
    end
    function self:Start()
        if self.enabled then return true end
        self.actor=Value(options.actor);self.scope=Value(options.scope)
        if type(self.db)~="table" or not self.journal or not self.codec or type(options.send)~="function" or type(options.now)~="function"
            or not Text(self.actor,96) or not Scope(self.scope) then Status("unavailable");return false,"unavailable" end
        if not Authority(self.actor) then Status("officer-authority-required");return false,self.reason end
        if self.db.raidSyncScope and self.db.raidSyncScope~=self.scope then Status("guild-scope-mismatch");return false,self.reason end
        local state,failure=self.journal.Ensure(self.db)
        if not state then Status(failure);return false,failure end
        self.db.raidSyncScope=self.scope
        self.session=tostring(Value(options.session) or (math.floor(Now()*1000).."-"..math.random(1,999999)))
        self.starts=(self.starts or 0)+1
        if self.starts>1 then self.session=string.sub(self.session,1,20).."-r"..self.starts end
        if self.policyEpoch then self.session=string.sub(self.session,1,20).."-p"..tostring(self.policyEpoch) end
        if not Session(self.session) then Status("invalid-session");return false,self.reason end
        self.enabled=true;self.lastError=nil;self.lastTick=Now();self.tokens=Sync.limits.burst;self.discoveryRemaining=2;self.discoveryAt=Now()+3
        local queued,reason=Hello()
        if not queued then self:Stop(reason);return false,reason end
        Status("discovering");return true
    end
    function self:Stop(reason)
        self.enabled=false;self.peers={};self.incompatiblePeers={};self.outbox={};self.controls={};self.incoming={};self.completed={};self.decodes={};self.exports={}
        self.dependencies={};self.sentOperations={};self.receipts={};self.receiptRanges=0;self.outgoing=nil;self.encoding=nil;self.request=nil;self.bufferBytes=0;self.discoveryAt=nil;self.announce=nil;self.combatPauseAt=nil
        Status(reason or "disabled")
    end
    function self:RefreshRaidPolicy()
        if not self.enabled then return true end
        -- A fresh transport session invalidates already encoded chunks on both
        -- sides. No private payload can escape an in-flight encoder after Stop.
        self.policyEpoch=(self.policyEpoch or 0)+1
        self:Stop("raid-policy-changed")
        return self:Start()
    end
    function self:NotifyChanged(raidId)
        if not Ready() then return false end
        if raidId and not Allowed(raidId) then return true end
        self.generation=self.generation+1;self.announce=true;self.discoveryRemaining=2;self.discoveryAt=Now()+3;return true
    end
    function self:Discover()
        if not Ready() then return false end
        for _,peer in pairs(self.peers) do peer.needsSummary=true;peer.offset=0;peer.cooldown=nil;peer.unavailable=nil;peer.blocked=nil;peer.interrupted=nil end
        self.lastError=nil;self.statusDirty=true
        self.announce=true;self.discoveryRemaining=2;self.discoveryAt=Now()+3;return true
    end
    function self:Retry()
        if not Ready() then return false,self.reason end
        local peers=self.peers
        self:Stop("retrying")
        self.peers=peers
        for _,peer in pairs(peers) do
            peer.summary=nil;peer.offset=0;peer.cooldown=nil;peer.unavailable=nil;peer.blocked=nil;peer.interrupted=nil
            peer.contactConfirmed=nil;peer.connected=false;peer.needsSummary=true
        end
        return self:Start()
    end
    local function ReceivePacket(prefix,text,channel,sender)
        if prefix~=Sync.PREFIX then return false,"other-prefix" end
        if not Ready() then return false,self.reason end
        -- Guild addon messages also return to their sender. This is not peer input.
        if channel=="GUILD" and sender==self.actor then return false,"self-echo" end
        if channel~="GUILD" or not Text(sender,96) or not Authority(sender) then return Reject("unauthorized-peer") end
        if type(text)~="string" or string.len(text)>Sync.limits.packet then return Reject("packet-limit") end
        local fields=Fields(text)
        if not fields then return Reject("invalid-packet") end
        if fields[2]~=self.actor and fields[2]~="*" then
            -- GUILD transports share a single sender budget. Valid chunks to
            -- another recipient prove a selected source is working, not offline.
            local peer=self.peers[sender]
            if peer and fields[1]=="D" and Count(fields)==8 and string.sub(fields[3],1,string.len(peer.session)+1)==peer.session..":"
                and Integer(tonumber(fields[5]),16384) and Integer(tonumber(fields[6]),16384) then
                peer.seen=Now()
                if self.request and self.request.peer==sender then self.request.activity=Now() end
            end
            return false,"other-recipient"
        end
        self.stats.receivedBytes=self.stats.receivedBytes+string.len(text)+string.len(Sync.PREFIX);self.revision=self.revision+1
        if fields[1]=="H" then
            if Count(fields)~=8 or not Session(fields[3]) or tonumber(fields[4])~=Sync.protocol
                or tonumber(fields[5])~=self.journal.schema or tonumber(fields[6])~=Sync.policy
                or not Integer(tonumber(fields[7]),9007199254740991) or DecodeScope(fields[8])~=self.scope then
                if self.peers[sender] then RemovePeer(sender,"incompatible-peer") end
                if CountMap(self.incompatiblePeers)<Sync.limits.peers or self.incompatiblePeers[sender] then self.incompatiblePeers[sender]={seen=Now()} end
                return Reject("incompatible-peer")
            end
            self.incompatiblePeers[sender]=nil
            for _,session in ipairs(self.retiredSessions[sender] or {}) do if session==fields[3] then return false,"stale-session" end end
            local peer=self.peers[sender]
            if peer and peer.session and peer.session~=fields[3] then
                RetireSession(sender,peer.session)
                RemovePeer(sender,"peer-session-changed");peer=nil
            end
            local connected=not peer
            if not peer then
                if CountMap(self.peers)>=Sync.limits.peers then return Reject("peer-limit") end
                peer={name=sender,offset=0};self.peers[sender]=peer
            end
            if peer.session~=fields[3] then
                for _,raid in pairs(self.receipts[sender] or {}) do for _,ranges in pairs(raid) do self.receiptRanges=self.receiptRanges-Count(ranges) end end
                self.receipts[sender]=nil
            end
            if peer.session~=fields[3] or peer.generation~=fields[7] or peer.unavailable or not peer.connected then peer.needsSummary=true;peer.offset=0 end
            local returning=peer.unavailable or not peer.connected
            peer.session=fields[3];peer.generation=fields[7];peer.seen=Now();peer.cooldown=nil;peer.unavailable=nil;peer.interrupted=nil
            peer.presenceRevision=options.presenceRevision and options.presenceRevision() or nil
            if self.lastError=="peer-session-changed" or self.lastError=="source-timeout" or self.lastError=="transfer-timeout" then self.lastError=nil end
            if (connected or not peer.connected) and options.onConnected then options.onConnected(sender) end
            peer.connected=true
            -- Suppress echo bursts only after addressed traffic proves the
            -- peer knows us. Retry the greeting if our first reply was lost.
            if fields[2]=="*" and (connected or returning or not peer.contactConfirmed) then Hello(sender) end
            return true
        end
        local peer=self.peers[sender]
        if not peer or fields[2]~=self.actor then
            if not self.incompatiblePeers[sender] and (fields[1]=="D" or fields[1]=="A" or fields[1]=="R" or fields[1]=="B") then return false,"handshake-pending" end
            return Reject("handshake-required")
        end
        if peer.blocked then return false,"blocked-peer" end
        if peer.unavailable then return false,"handshake-pending" end
        if fields[1]=="B" then
            local request=self.request
            if Count(fields)~=4 or fields[3]~=self.session or not request or request.peer~=sender or tostring(request.id)~=fields[4] then return false,"stale-busy" end
            peer.cooldown=Now()+3;self.request=nil;return true
        elseif fields[1]=="R" then
            local sent=self.sentOperations[fields[4]]
            if Count(fields)~=4 or fields[3]~=self.session or not sent or sent.peer~=sender or sent.peerSession~=peer.session then return false,"stale-receipt" end
            local newlyConfirmed=Confirm(sender,sent);self.sentOperations[fields[4]]=nil
            if newlyConfirmed and options.onDelivered then options.onDelivered(sender,sent.operationId) end
            return true
        elseif fields[1]=="A" then
            local outgoing=self.outgoing;local acknowledged=tonumber(fields[5])
            if Count(fields)~=5 or not outgoing or outgoing.target~=sender or fields[3]~=self.session or fields[4]~=outgoing.id
                or not Integer(acknowledged,outgoing.total) then return false,"stale-ack" end
            if acknowledged>outgoing.sent then return Reject("invalid-ack") end
            if acknowledged>outgoing.ack then outgoing.ack=acknowledged;outgoing.activity=Now();outgoing.attempts=0 end
            if outgoing.ack==outgoing.total then self.outgoing=nil end
            return true
        elseif fields[1]=="D" then
            -- Both endpoints identify their client process. Old addressed
            -- chunks must not refresh activity or keep a new request alive.
            local separator=string.find(fields[3] or "",":",1,true)
            local sourceSession=separator and string.sub(fields[3],1,separator-1) or fields[3]
            local targetSession=separator and string.sub(fields[3],separator+1)
            if sourceSession~=peer.session then return false,"stale-session" end
            if targetSession~=self.session then return false,"stale-recipient-session" end
            local index,total,priority=tonumber(fields[5]),tonumber(fields[6]),tonumber(fields[7])
            if Count(fields)~=8 or not Text(fields[4],20) or not Integer(index,16384) or index<1
                or not Integer(total,16384) or total<index or not Integer(priority,3) or priority<1
                or string.len(fields[8])==0 then return Reject("invalid-chunk") end
            local key=sender..":"..fields[3]..":"..fields[4]
            local completed=self.completed[key]
            if completed then
                if completed.total~=total then return Reject("chunk-collision") end
                Control(table.concat({"A",sender,sourceSession,fields[4],tostring(total)},"~"));return true,"duplicate-chunk"
            end
            local transfer=self.incoming[key]
            if not transfer then
                if CountMap(self.incoming)+Count(self.decodes)>=Sync.limits.incoming then return Reject("incoming-backpressure") end
                transfer={sender=sender,id=fields[4],session=sourceSession,total=total,priority=priority,chunks={},received=0,contiguous=0,bytes=0,activity=Now()}
                self.incoming[key]=transfer
            end
            if transfer.total~=total or transfer.priority~=priority then ReleaseIncoming(key);return Reject("chunk-collision") end
            if index>transfer.contiguous+Sync.limits.window*2 then return Reject("chunk-window") end
            local existing=transfer.chunks[index]
            if existing and existing~=fields[8] then ReleaseIncoming(key);return Reject("chunk-collision") end
            if not existing then
                local bytes=string.len(fields[8])
                if transfer.bytes+bytes>self.codec.limits.bytes or self.bufferBytes+bytes>Sync.limits.bufferBytes then ReleaseIncoming(key);return Reject("buffer-limit") end
                transfer.chunks[index]=fields[8];transfer.bytes=transfer.bytes+bytes;self.bufferBytes=self.bufferBytes+bytes;transfer.received=transfer.received+1
            end
            transfer.activity=Now()
            while transfer.chunks[transfer.contiguous+1] do transfer.contiguous=transfer.contiguous+1 end
            if math.mod(transfer.contiguous,Sync.limits.window)==0 or transfer.contiguous==total or existing then
                Control(table.concat({"A",sender,sourceSession,fields[4],tostring(transfer.contiguous)},"~"))
            end
            if transfer.contiguous==total then
                table.insert(self.decodes,{sender=sender,bytes=transfer.bytes,priority=priority,chunks=transfer.chunks,receiptId=transfer.id,receiptSession=transfer.session})
                self.incoming[key]=nil
                if CountMap(self.completed)>=64 then
                    local oldestKey,oldest
                    for cachedKey,cached in pairs(self.completed) do if not oldest or cached.time<oldest then oldestKey=cachedKey;oldest=cached.time end end
                    self.completed[oldestKey]=nil
                end
                self.completed[key]={total=total,time=Now()}
            end
            return true
        end
        return Reject("unknown-packet")
    end

    function self:Receive(prefix,text,channel,sender)
        local accepted,reason=ReceivePacket(prefix,text,channel,sender)
        local peer=self.peers[sender]
        if accepted and peer then
            peer.seen=Now()
            if self.request and self.request.peer==sender then self.request.activity=Now() end
        end
        if accepted and peer and string.sub(text,1,4)~="H~*~" then peer.contactConfirmed=true end
        if accepted and peer and options.presenceRevision then peer.presenceRevision=options.presenceRevision() end
        if accepted and peer and not peer.connected then
            peer.connected=true
            if options.onConnected then options.onConnected(sender) end
        end
        return accepted,reason
    end

    function self:RefreshPresence()
        for name,peer in pairs(self.peers) do
            local witnessed=options.presenceRevision and peer.presenceRevision==options.presenceRevision()
            local offline=options.isOnline and not options.isOnline(name) and not witnessed
            if peer.connected and offline and PeerBusy(peer) then InterruptPeer(name,"source-timeout")
            elseif peer.connected and (offline or peer.unavailable or not Authority(name)) then
                peer.connected=false;self.revision=self.revision+1;self.statusDirty=true
                if options.onDisconnected then options.onDisconnected(name,peer.unavailable and "no response" or "offline") end
            end
        end
    end

    local function Schedule()
        if self.request then return end
        local now=Now()
        -- Drain known live-raid updates before refreshing inventories. Historic
        -- bulk transfers still yield to discovery of new live-raid data.
        for id,dependency in pairs(self.dependencies) do
            local chosen=self.peers[dependency.peer or ""]
            if not chosen or chosen.blocked or chosen.unavailable or (chosen.cooldown and chosen.cooldown>now) then
                chosen=nil
                for _,peer in pairs(self.peers) do if not peer.blocked and not peer.unavailable and (not peer.cooldown or peer.cooldown<=now) then chosen=peer;break end end
            end
            if chosen and (not Combat() or Priority(dependency.raidId)==1) then
                Request(chosen,{type="operation-request",id=id},Priority(dependency.raidId));return
            end
        end
        local chosen,range,priority
        for _,peer in pairs(self.peers) do
            if not peer.blocked and not peer.unavailable and peer.summary and (not peer.cooldown or peer.cooldown<=now) then
                local missing,failure=self.journal.GetMissingRanges(self.db,peer.summary,Sync.limits.range)
                if not missing then Reject(failure);peer.summary=nil
                else
                    for _,candidate in ipairs(missing) do
                        local rank=Priority(candidate.raidId)
                        if (not Combat() or rank==1) and (not priority or rank<priority) then chosen=peer;range=candidate;priority=rank end
                    end
                    if Count(missing)==0 and peer.summary.nextOffset then
                        peer.offset=peer.summary.nextOffset;peer.needsSummary=true
                    end
                end
            end
        end
        if chosen and priority==1 then
            Request(chosen,{type="range-request",raidId=range.raidId,origin=range.origin,first=range.first,last=math.min(range.last,range.first+Sync.limits.range-1)},priority)
            return
        end
        for _,peer in pairs(self.peers) do
            if not peer.blocked and not peer.unavailable and peer.needsSummary and (not peer.cooldown or peer.cooldown<=now) then
                Request(peer,{type="summary-request",offset=peer.offset or 0},1);return
            end
        end
        if chosen then
            Request(chosen,{type="range-request",raidId=range.raidId,origin=range.origin,first=range.first,last=math.min(range.last,range.first+Sync.limits.range-1)},priority)
        end
    end
    local function Export()
        if Count(self.exports)==0 or Count(self.outbox)>=Sync.limits.outbox-1 then return end
        local index
        for candidate,task in ipairs(self.exports) do if not Combat() or task.priority==1 then index=candidate;break end end
        if not index then return end
        local task=self.exports[index]
        if not Allowed(task.raidId or task.operation and task.operation.raidId) then task.operation=nil;task.done=true end
        if task.done then
            Queue(task.peer,{type="done",request=task.request},task.priority);table.remove(self.exports,index);return
        end
        local operation=task.operation
        if operation then task.operation=nil;task.done=true
        else
            local operations,nextSequence=self.journal.GetOperationRange(self.db,task.raidId,task.origin,task.cursor,1,task.last)
            if not operations then Reject(nextSequence);task.done=true;return end
            operation=operations[1];task.cursor=nextSequence or task.last+1
            task.done=not operation or task.cursor>task.last
        end
        if operation then
            local checkpoint=self.journal.IsCheckpointOperation and self.journal.IsCheckpointOperation(self.db,operation) or operation.compacted==true
            Queue(task.peer,{type="operation",request=task.request,operation=operation,checkpoint=checkpoint or nil},task.priority)
            -- Rotate after each operation so one long range cannot monopolize
            -- another officer's pending recovery request.
            table.remove(self.exports,index);table.insert(self.exports,task)
        end
    end
    local function Encode()
        if self.outgoing then return end
        if not self.encoding then
            local index
            for candidate,message in ipairs(self.outbox) do
                if (not Combat() or message.priority==1) and (not index or message.priority<self.outbox[index].priority) then index=candidate end
            end
            if not index then return end
            local message=table.remove(self.outbox,index)
            local operation=message.payload.type=="operation" and message.payload.operation
            if operation and not Allowed(operation.raidId) then return end
            self.encoding={target=message.target,priority=message.priority,job=self.codec.BeginEncode(message.payload),
                receipt=operation and {peer=message.target,peerSession=self.peers[message.target] and self.peers[message.target].session,
                    raidId=operation.raidId,origin=operation.origin,sequence=operation.sequence,operationId=operation.id} or nil}
        end
        local encoding=self.encoding
        if Combat() and encoding.priority>1 then return end
        local done,text,failure=encoding.job:Step(Sync.limits.codecNodes)
        if not done then return end
        self.encoding=nil
        if failure then Reject(failure);return end
        self.sequence=self.sequence+1
        local recipient=self.peers[encoding.target]
        if not recipient or recipient.unavailable or recipient.blocked then return end
        local session=self.session..":"..recipient.session
        local size=math.min(160,Sync.limits.packet-string.len(encoding.target)-string.len(session)-44)
        if size<32 then Reject("chunk-envelope-limit");return end
        local total=math.ceil(string.len(text)/size)
        if total>16384 then Reject("chunk-count-limit");return end
        self.outgoing={target=encoding.target,session=session,id=tostring(self.sequence),priority=encoding.priority,text=text,size=size,total=total,ack=0,sent=0,activity=Now(),attempts=0}
        if encoding.receipt then
            if CountMap(self.sentOperations)>=128 then
                local oldest
                for id in pairs(self.sentOperations) do if not oldest or tonumber(id)<tonumber(oldest) then oldest=id end end
                self.sentOperations[oldest]=nil
            end
            self.sentOperations[self.outgoing.id]=encoding.receipt
        end
    end
    local function Send(text)
        local cost=string.len(text)+string.len(Sync.PREFIX)
        if self.tokens<cost then return false end
        if string.len(text)>Sync.limits.packet then Reject("packet-limit");return false end
        local ok,result=pcall(options.send,Sync.PREFIX,text,"GUILD")
        if not ok or result==false then self.lastError="send-failed";return false end
        self.tokens=self.tokens-cost;self.stats.sentBytes=self.stats.sentBytes+cost;self.revision=self.revision+1;return true
    end
    function self:Tick()
        if not Ready() then return false end
        self:RefreshPresence()
        local now=Now();self.tokens=math.min(Sync.limits.burst,self.tokens+math.max(0,now-self.lastTick)*Sync.limits.rate);self.lastTick=now
        for name in pairs(self.peers) do if not Authority(name) then RemovePeer(name) end end
        for key,transfer in pairs(self.incoming) do
            if not (Combat() and transfer.priority>1) and now-transfer.activity>Sync.limits.timeout then InterruptPeer(transfer.sender,"transfer-timeout") end
        end
        for key,cached in pairs(self.completed) do if not Combat() and now-cached.time>60 then self.completed[key]=nil end end
        if self.request and not (Combat() and self.request.priority>1) and now-self.request.activity>Sync.limits.timeout then
            InterruptPeer(self.request.peer,"source-timeout")
            self.stats.retries=self.stats.retries+1
        end
        if self.announce then Hello();self.announce=nil end
        if self.discoveryAt and now>=self.discoveryAt then
            Hello();self.discoveryRemaining=self.discoveryRemaining-1
            self.discoveryAt=self.discoveryRemaining>0 and now+3 or nil
        end
        for index,decode in ipairs(self.decodes) do
            if not Combat() or decode.priority==1 then
                if not decode.job then decode.job=self.codec.BeginDecode(table.concat(decode.chunks));decode.chunks=nil end
                local done,payload,failure=decode.job:Step(Sync.limits.codecNodes)
                if done then
                    table.remove(self.decodes,index);self.bufferBytes=self.bufferBytes-decode.bytes
                    if failure then
                        Reject(failure)
                        local peer=self.peers[decode.sender]
                        if peer then peer.blocked=true;peer.blockReason=failure end
                        if self.request and self.request.peer==decode.sender then self.request=nil end
                    elseif self.peers[decode.sender] and Authority(decode.sender) then
                        local accepted=Dispatch(self.peers[decode.sender],payload,decode.receiptId,decode.receiptSession)
                        if not accepted then
                            self.peers[decode.sender].blocked=true;self.peers[decode.sender].blockReason=self.lastError
                            if self.request and self.request.peer==decode.sender then self.request=nil end
                        end
                    end
                end
                break
            end
        end
        Schedule();Export();Encode()
        local outgoing=self.outgoing
        if outgoing and not (Combat() and outgoing.priority>1) and now-outgoing.activity>Sync.limits.retry then
            outgoing.sent=outgoing.ack;outgoing.activity=now;outgoing.attempts=outgoing.attempts+1;self.stats.retries=self.stats.retries+1
            if outgoing.attempts>3 then
                InterruptPeer(outgoing.target,"transfer-timeout");outgoing=nil
            end
        end
        for packet=1,Sync.limits.packetsPerTick do
            local text=self.controls[1]
            if text then
                if not Send(text) then break end
                table.remove(self.controls,1)
            elseif outgoing and (not Combat() or outgoing.priority==1) and outgoing.sent<outgoing.total and outgoing.sent<outgoing.ack+Sync.limits.window then
                local index=outgoing.sent+1
                text=table.concat({"D",outgoing.target,outgoing.session,outgoing.id,tostring(index),tostring(outgoing.total),tostring(outgoing.priority),string.sub(outgoing.text,(index-1)*outgoing.size+1,index*outgoing.size)},"~")
                if not Send(text) then break end
                outgoing.sent=index;outgoing.activity=now
            else break end
        end
        if self.statusDirty then Status(self.reason) end
        return self:HasWork()
    end
    function self:HasWork()
        if not self.enabled then return false end
        if self.statusDirty then return true end
        if Count(self.controls)>0 or self.announce or self.discoveryAt then return true end
        if self.request and (not Combat() or self.request.priority==1) then return true end
        for _,transfer in pairs(self.incoming) do if not Combat() or transfer.priority==1 then return true end end
        if self.outgoing and (not Combat() or self.outgoing.priority==1) then return true end
        if self.encoding and (not Combat() or self.encoding.priority==1) then return true end
        for _,entry in ipairs(self.decodes) do if not Combat() or entry.priority==1 then return true end end
        for _,entry in ipairs(self.outbox) do if not Combat() or entry.priority==1 then return true end end
        for _,entry in ipairs(self.exports) do if not Combat() or entry.priority==1 then return true end end
        if next(self.dependencies) and not Combat() then
            for _,peer in pairs(self.peers) do if not peer.blocked and not peer.unavailable then return true end end
        end
        for _,peer in pairs(self.peers) do
            if not peer.blocked and not peer.unavailable and peer.needsSummary then return true end
            if not peer.blocked and not peer.unavailable and peer.summary then
                local missing=self.journal.GetMissingRanges(self.db,peer.summary,1)
                if missing and missing[1] and (not Combat() or Priority(missing[1].raidId)==1) then return true end
                if missing and not missing[1] and peer.summary.nextOffset then return true end
            end
        end
        return false
    end
    function self:GetConfirmedFrontiers(raidId)
        if not Ready() or not Text(raidId,300) then return {} end
        local localRanges,offset,seen={},0,0
        while true do
            local summary=Summary(offset,8,raidId)
            if not summary then return {} end
            local complete=false
            for _,entry in ipairs(summary.entries) do
                if entry.raidId~=raidId then complete=true;break end
                seen=seen+1;if seen>128 then return {},"confirmation-budget" end
                local ranges=localRanges[entry.origin] or {};localRanges[entry.origin]=ranges
                table.insert(ranges,{entry.first,entry.last})
            end
            if complete or not summary.nextOffset then break end
            offset=summary.nextOffset
        end
        local confirmed={}
        for name,peer in pairs(self.peers) do
            if not peer.unavailable and not peer.blocked and Authority(name) and Now()-(peer.seen or 0)<=120 then
                local received=self.receipts[name] and self.receipts[name][raidId] or {}
                for origin,localList in pairs(localRanges) do
                    local ranges=received[origin] or {};local position,frontier=1,0
                    for _,required in ipairs(localList) do
                        local cursor=required[1]
                        while ranges[position] and ranges[position][2]<cursor do position=position+1 end
                        while ranges[position] and ranges[position][1]<=cursor do
                            frontier=math.min(required[2],ranges[position][2]);cursor=frontier+1
                            if cursor>required[2] then break end
                            position=position+1
                        end
                        if cursor<=required[2] then break end
                    end
                    if frontier>0 then confirmed[origin]=math.max(confirmed[origin] or 0,frontier) end
                end
            end
        end
        return confirmed
    end
    function self:NextWake()
        if not self:HasWork() then return nil end
        local now=Now()
        if self.statusDirty then return now end
        local combat=Combat()
        if self.announce or (self.encoding and (not combat or self.encoding.priority==1)) then return now end
        for _,entry in ipairs(self.decodes) do if not combat or entry.priority==1 then return now end end
        for _,entry in ipairs(self.exports) do if (not combat or entry.priority==1) and Count(self.outbox)<Sync.limits.outbox-1 then return now end end
        if not self.outgoing then for _,entry in ipairs(self.outbox) do if not combat or entry.priority==1 then return now end end end
        local wake=self.discoveryAt
        local outgoing=self.outgoing
        if Count(self.controls)>0 or (outgoing and (not combat or outgoing.priority==1)
            and outgoing.sent<math.min(outgoing.total,outgoing.ack+Sync.limits.window)) then
            local available=math.min(Sync.limits.burst,self.tokens+math.max(0,now-self.lastTick)*Sync.limits.rate)
            local ready=now+math.max(0,Sync.limits.packet+string.len(Sync.PREFIX)-available)/Sync.limits.rate
            if not wake or ready<wake then wake=ready end
        elseif outgoing and (not combat or outgoing.priority==1) then
            local retry=outgoing.activity+Sync.limits.retry;if not wake or retry<wake then wake=retry end
        end
        if self.request and (not combat or self.request.priority==1) then
            local timeout=self.request.activity+Sync.limits.timeout;if not wake or timeout<wake then wake=timeout end
        end
        for _,transfer in pairs(self.incoming) do
            if not combat or transfer.priority==1 then
                local timeout=transfer.activity+Sync.limits.timeout;if not wake or timeout<wake then wake=timeout end
            end
        end
        for _,peer in pairs(self.peers) do
            if not self.request and not peer.blocked and not peer.unavailable then
                if peer.cooldown and peer.cooldown>now then
                    if not wake or peer.cooldown<wake then wake=peer.cooldown end
                elseif peer.needsSummary or next(self.dependencies) then return now
                elseif peer.summary then
                    local missing=self.journal.GetMissingRanges(self.db,peer.summary,1)
                    if missing and ((missing[1] and (not combat or Priority(missing[1].raidId)==1)) or (not missing[1] and peer.summary.nextOffset)) then return now end
                end
            end
        end
        return wake and math.max(now,wake) or nil
    end
    return self
end
Sync.Create=Sync.New
