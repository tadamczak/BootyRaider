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
local operationKeys = {schema=true,id=true,origin=true,sequence=true,raidId=true,author=true,timestamp=true,kind=true,changes=true,detail=true,audit=true}
local changeKeys = {key=true,base=true,before=true,beforeDeleted=true,value=true,deleted=true}

local function Finite(value)
    return type(value) == "number" and value == value and value - value == 0
end

local function Integer(value)
    return Finite(value) and value >= 0 and value <= maxCounter and value == math.floor(value)
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
            or (change.base == nil and (change.before ~= nil or change.beforeDeleted)) then return nil, "invalid-change" end
        keys[change.key] = true
    end
    return copy
end

local function BaseChange(state, id, raidId, key)
    local operation = state.operations[id]
    if not operation then return nil, "missing-dependency" end
    if operation.raidId ~= raidId then return nil, "invalid-dependency" end
    for _, change in ipairs(operation.changes) do if change.key == key then return change end end
    return nil, "invalid-dependency"
end

function Journal.Apply(db, operation)
    local incoming, failure = Validate(operation)
    if not incoming then return false, failure end
    local state
    state, failure = Journal.Ensure(db)
    if not state then return false, failure end
    local existing = state.operations[incoming.id]
    if existing then
        if Equal(existing, incoming) then return true, "duplicate" end
        return false, "operation-id-collision"
    end
    local raid = state.raids[incoming.raidId]
    if raid and (type(raid.records) ~= "table" or type(raid.log) ~= "table" or not Integer(raid.logRevision)) then return false, "invalid-raid-state" end
    for _, change in ipairs(incoming.changes) do
        local current = raid and raid.records[change.key]
        if change.base then
            local base
            base, failure = BaseChange(state, change.base, incoming.raidId, change.key)
            if not base then return false, failure end
            if not Equal(base.value, change.before) or base.deleted ~= change.beforeDeleted then return false, "invalid-before-value" end
        end
        if (current and current.revision or nil) ~= change.base then return false, "conflict" end
        if current and (not Equal(current.value, change.before) or current.deleted ~= change.beforeDeleted) then return false, "invalid-record-state" end
    end
    -- Only publish after every record in the batch has passed validation.
    if not raid then raid = {records={},log={},logRevision=0}; state.raids[incoming.raidId] = raid end
    state.operations[incoming.id] = incoming
    for _, change in ipairs(incoming.changes) do
        raid.records[change.key] = {revision=incoming.id,value=change.value,deleted=change.deleted}
    end
    if incoming.audit then
        raid.logRevision = raid.logRevision + 1
        raid.log[raid.logRevision] = incoming.id
    end
    if incoming.origin == state.replicaId and incoming.sequence > state.sequence then state.sequence = incoming.sequence end
    return true, "applied"
end

function Journal.Commit(db, raidId, kind, changes, detail, audit)
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
    local raid, keys, batch = state.raids[raidId], {}, {}
    for index = 1, count do
        local change = supplied[index]
        if type(change) ~= "table" or not Text(change.key, 256) or keys[change.key]
            or (change.deleted ~= nil and change.deleted ~= true)
            or (change.deleted and change.value ~= nil) or (not change.deleted and change.value == nil) then return false, "invalid-change" end
        for key in pairs(change) do if key ~= "key" and key ~= "value" and key ~= "deleted" then return false, "unknown-commit-field" end end
        keys[change.key] = true
        local current = raid and raid.records[change.key]
        local unchanged = current and current.deleted == change.deleted and Equal(current.value, change.value)
        if not current and change.deleted then unchanged = true end
        if not unchanged then
            table.insert(batch, {key=change.key,base=current and current.revision,
                before=current and current.value,beforeDeleted=current and current.deleted,
                value=change.value,deleted=change.deleted})
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
        sequence=sequence,raidId=raidId,author=author,timestamp=timestamp,kind=kind,changes=batch,detail=detail,audit=audit ~= false}
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
    return raid and raid.logRevision or 0
end

function Journal.GetChange(db, operationId, index)
    local state, failure = Journal.Ensure(db)
    if not state then return nil, failure end
    local operation = state.operations[operationId]
    if not operation then return nil, 0 end
    local count = table.getn(operation.changes)
    if not Integer(index) or index < 1 or index > count then return nil, count end
    return Clone(operation.changes[index]), count
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
        table.insert(page, {id=operation.id,raidId=operation.raidId,author=operation.author,
            timestamp=operation.timestamp,kind=operation.kind,detail=Clone(operation.detail),
            changeCount=table.getn(operation.changes)})
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
