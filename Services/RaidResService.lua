local Raider = BootyRaider

Raider.Services = Raider.Services or {}
local RaidResService = {}
Raider.Services.RaidRes = RaidResService

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decodeMap = {}
local alphabetIndex
for alphabetIndex = 1, string.len(alphabet) do
    decodeMap[string.sub(alphabet, alphabetIndex, alphabetIndex)] = alphabetIndex - 1
end
decodeMap["-"] = 62
decodeMap["_"] = 63

-- Import is an explicit user operation, bounded by the existing editor budget.
-- Keep parsing local to Raider: no shared codec, polling or client dependency.
local MAX_IMPORT_BYTES, MAX_JSON_DEPTH = 16000, 32
local JSON_NULL = {}
local jsonEscapes = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function DecodeBase64(value)
    if type(value) ~= "string" then return nil, "Paste a Base64 RaidRes export." end
    if string.len(value) > MAX_IMPORT_BYTES then return nil, "The RaidRes export exceeds the 16000-byte import limit." end
    value = string.gsub(value, "%s", "")
    if value == "" then return nil, "Paste the RaidRes export first." end
    if math.mod(string.len(value), 4) == 1 then return nil, "The Base64 text has an invalid length." end
    local output = {}
    local outputCount = 0
    local index = 1
    while index <= string.len(value) do
        local a = decodeMap[string.sub(value, index, index)]
        local b = decodeMap[string.sub(value, index + 1, index + 1)]
        local cChar = string.sub(value, index + 2, index + 2)
        local dChar = string.sub(value, index + 3, index + 3)
        local c, d
        if cChar ~= "=" and cChar ~= "" then c = decodeMap[cChar] end
        if dChar ~= "=" and dChar ~= "" then d = decodeMap[dChar] end
        if not a or not b or (cChar ~= "=" and cChar ~= "" and not c) or (dChar ~= "=" and dChar ~= "" and not d) then
            return nil, "The pasted text is not valid Base64."
        end
        if (cChar == "=" and dChar ~= "=") or (d and not c)
            or ((cChar == "=" or dChar == "=") and index + 3 ~= string.len(value))
            or (not c and math.mod(b, 16) ~= 0) or (c and not d and math.mod(c, 4) ~= 0) then
            return nil, "The pasted text has invalid Base64 padding."
        end
        local combined = (a * 262144) + (b * 4096) + ((c or 0) * 64) + (d or 0)
        outputCount = outputCount + 1; output[outputCount] = string.char(math.floor(combined / 65536))
        if c then outputCount = outputCount + 1; output[outputCount] = string.char(math.mod(math.floor(combined / 256), 256)) end
        if d then outputCount = outputCount + 1; output[outputCount] = string.char(math.mod(combined, 256)) end
        index = index + 4
    end
    return table.concat(output)
end

local function Utf8(code)
    if code < 128 then return string.char(code) end
    if code < 2048 then return string.char(192 + math.floor(code / 64), 128 + math.mod(code, 64)) end
    if code < 65536 then return string.char(224 + math.floor(code / 4096), 128 + math.mod(math.floor(code / 64), 64), 128 + math.mod(code, 64)) end
    return string.char(240 + math.floor(code / 262144), 128 + math.mod(math.floor(code / 4096), 64), 128 + math.mod(math.floor(code / 64), 64), 128 + math.mod(code, 64))
end

local function RawUtf8Length(text, index)
    local first, second = string.byte(text, index), string.byte(text, index + 1)
    local third, fourth = string.byte(text, index + 2), string.byte(text, index + 3)
    if not second or second < 128 or second > 191 then return nil end
    if first >= 194 and first <= 223 then return 2 end
    if not third or third < 128 or third > 191 then return nil end
    if first >= 224 and first <= 239 then
        if first == 224 and second < 160 or first == 237 and second > 159 then return nil end
        return 3
    end
    if not fourth or fourth < 128 or fourth > 191 then return nil end
    if first >= 240 and first <= 244 then
        if first == 240 and second < 144 or first == 244 and second > 143 then return nil end
        return 4
    end
    return nil
end

local function ParseJson(text)
    local position, length, kinds = 1, string.len(text), {}
    local failure, ReadValue
    local function Fail(message)
        failure = failure or ("Invalid RaidRes JSON at byte " .. position .. ": " .. message)
        return nil
    end
    local function SkipSpace()
        while position <= length do
            local byte = string.byte(text, position)
            if byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then return end
            position = position + 1
        end
    end
    local function ReadHex()
        local hex = string.sub(text, position, position + 3)
        if string.len(hex) ~= 4 or string.find(hex, "[^%x]") then return Fail("invalid Unicode escape.") end
        position = position + 4
        return tonumber(hex, 16)
    end
    local function ReadString()
        position = position + 1
        local parts, segment = {}, position
        while position <= length do
            local byte = string.byte(text, position)
            if byte == 34 then
                table.insert(parts, string.sub(text, segment, position - 1))
                position = position + 1
                return table.concat(parts)
            elseif byte == 92 then
                table.insert(parts, string.sub(text, segment, position - 1))
                position = position + 1
                local escape = string.sub(text, position, position)
                position = position + 1
                if escape == "u" then
                    local code = ReadHex()
                    if not code then return nil end
                    if code >= 55296 and code <= 56319 then
                        if string.sub(text, position, position + 1) ~= "\\u" then return Fail("missing low surrogate.") end
                        position = position + 2
                        local low = ReadHex()
                        if not low then return nil end
                        if low < 56320 or low > 57343 then return Fail("invalid low surrogate.") end
                        code = 65536 + (code - 55296) * 1024 + low - 56320
                    elseif code >= 56320 and code <= 57343 then return Fail("unexpected low surrogate.") end
                    table.insert(parts, Utf8(code))
                elseif jsonEscapes[escape] then table.insert(parts, jsonEscapes[escape])
                else return Fail("invalid string escape.") end
                segment = position
            elseif byte < 32 then return Fail("unescaped control character.")
            elseif byte >= 128 then
                local size = RawUtf8Length(text, position)
                if not size then return Fail("invalid UTF-8.") end
                position = position + size
            else position = position + 1 end
        end
        return Fail("unterminated string.")
    end
    local function ReadNumber()
        local start = position
        if string.sub(text, position, position) == "-" then position = position + 1 end
        local first = string.sub(text, position, position)
        if first == "0" then position = position + 1
        elseif first ~= "" and string.find(first, "[1-9]") then
            repeat position = position + 1 until not string.find(string.sub(text, position, position), "%d")
        else return Fail("invalid number.") end
        if string.sub(text, position, position) == "." then
            position = position + 1
            if not string.find(string.sub(text, position, position), "%d") then return Fail("missing decimal digits.") end
            repeat position = position + 1 until not string.find(string.sub(text, position, position), "%d")
        end
        local exponent = string.sub(text, position, position)
        if exponent == "e" or exponent == "E" then
            position = position + 1
            local sign = string.sub(text, position, position)
            if sign == "+" or sign == "-" then position = position + 1 end
            if not string.find(string.sub(text, position, position), "%d") then return Fail("missing exponent digits.") end
            repeat position = position + 1 until not string.find(string.sub(text, position, position), "%d")
        end
        local number = tonumber(string.sub(text, start, position - 1))
        if not number or number - number ~= 0 then return Fail("number is outside the supported range.") end
        return number
    end
    local function ReadCollection(depth, object)
        local result, closing = {}, object and "}" or "]"
        kinds[result] = object and "object" or "array"
        position = position + 1; SkipSpace()
        if string.sub(text, position, position) == closing then position = position + 1; return result end
        while true do
            local key
            if object then
                if string.sub(text, position, position) ~= '"' then return Fail("object key must be a string.") end
                key = ReadString()
                if key == nil then return nil end
                if result[key] ~= nil then return Fail("duplicate object key.") end
                SkipSpace()
                if string.sub(text, position, position) ~= ":" then return Fail("missing colon.") end
                position = position + 1
            end
            local value = ReadValue(depth + 1)
            if value == nil then return nil end
            if object then result[key] = value else table.insert(result, value) end
            SkipSpace()
            local separator = string.sub(text, position, position)
            position = position + 1
            if separator == closing then return result end
            if separator ~= "," then return Fail("missing collection separator or closing bracket.") end
            SkipSpace()
        end
    end
    ReadValue = function(depth)
        SkipSpace()
        if depth > MAX_JSON_DEPTH then return Fail("import structure limit exceeded.") end
        local char = string.sub(text, position, position)
        if char == '"' then return ReadString() end
        if char == "{" then return ReadCollection(depth, true) end
        if char == "[" then return ReadCollection(depth, false) end
        if char == "-" or string.find(char, "%d") then return ReadNumber() end
        if string.sub(text, position, position + 3) == "true" then position = position + 4; return true end
        if string.sub(text, position, position + 4) == "false" then position = position + 5; return false end
        if string.sub(text, position, position + 3) == "null" then position = position + 4; return JSON_NULL end
        return Fail("expected a JSON value.")
    end
    local result = ReadValue(1)
    if result == nil then return nil, failure end
    SkipSpace()
    if position <= length then return nil, "Invalid RaidRes JSON: unexpected trailing input." end
    return result, nil, kinds
end

local function ImportText(value, field, optional)
    if optional and (value == nil or value == JSON_NULL) then return nil end
    if type(value) ~= "string" or string.len(value) > 128 or string.find(value, "%c") then
        return nil, "RaidRes " .. field .. " must be a string of at most 128 bytes without control characters."
    end
    local trimmed = string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")
    if trimmed == "" then return nil, "RaidRes " .. field .. " must not be blank." end
    return value
end

local function ReadImport(encoded)
    local json, decodeError = DecodeBase64(encoded)
    if not json then return nil, decodeError end
    local document, parseError, kinds = ParseJson(json)
    if document == nil then return nil, parseError end
    if kinds[document] ~= "object" or kinds[document.softreserves] ~= "array" then
        return nil, "The decoded data must contain a RaidRes softreserves array."
    end
    local id, idError = ImportText(document.id, "id", true)
    if idError then return nil, idError end
    local origin, originError = ImportText(document.origin, "origin", true)
    if originError then return nil, originError end
    local reservations, index, itemIndex = {}, nil, nil
    for index = 1, table.getn(document.softreserves) do
        local row = document.softreserves[index]
        if kinds[row] ~= "object" then return nil, "Each RaidRes reservation must be an object." end
        local name, nameError = ImportText(row.name, "reservation name", false)
        if nameError then return nil, nameError end
        if kinds[row.items] ~= "array" then return nil, "Each RaidRes reservation must contain an items array." end
        local ids = {}
        for itemIndex = 1, table.getn(row.items) do
            local item = row.items[itemIndex]
            local itemId = kinds[item] == "object" and item.id
            if type(itemId) ~= "number" or itemId < 1 or itemId > 2147483647 or itemId ~= math.floor(itemId) then
                return nil, "Each RaidRes item must contain a positive integer id."
            end
            table.insert(ids, itemId)
        end
        table.insert(reservations, { name = name, itemIds = ids })
    end
    return { id = id, origin = origin, reservations = reservations }
end

local function NormalizeName(value)
    value = string.lower(tostring(value or ""))
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    value = string.gsub(value, "%-[^%-]+$", "")
    return value
end

local function EnsureSnapshotImport(attendance)
    local importInfo = attendance.softReserveImport
    if not importInfo then
        attendance.snapshotId = attendance.snapshotId or ((attendance.raidName or "raid") .. "-" .. time())
        importInfo = { id = attendance.snapshotId, origin = "mos", importedAt = time(), unmatchedNames = {}, unmatchedReservations = {}, missingNames = {} }
        attendance.softReserveImport = importInfo
    end
    return importInfo
end

-- Mutations do not consume snapshots. Keep metadata preparation, but omit
-- member/item copies when draft or transient changes cannot be persisted.
local function SyncMutation(attendance)
    if attendance and (attendance._transient or attendance._sessionDraft) then
        if type(attendance.members) == "table" then EnsureSnapshotImport(attendance) end
        return
    end
    RaidResService.SyncHistory(attendance)
end

function RaidResService.HasSession(attendance)
    local importInfo = attendance and attendance.softReserveImport
    local raidId = attendance and (attendance.snapshotId or (importInfo and importInfo.id))
    return raidId and attendance.sessionStartedAt and type(attendance.members) == "table" and true or false
end

function RaidResService.Import(encoded, attendance, srUrl)
    if type(attendance) ~= "table" or type(attendance.members) ~= "table" then return nil, "Scan the raid roster before importing Soft Reserves." end
    local imported, importError = ReadImport(encoded)
    if not imported then return nil, importError end
    if srUrl ~= nil and type(srUrl) ~= "string" then return nil, "The SR URL must be text." end
    local cleanUrl = string.gsub(string.gsub(srUrl or "", "^%s+", ""), "%s+$", "")
    local reservations = imported.reservations
    local byName = {}
    local reservationIndex
    for reservationIndex = 1, table.getn(reservations) do
        local reservation = reservations[reservationIndex]
        -- Existing exports can repeat names or item IDs. Last normalized name
        -- wins; repeated item IDs retain their reservation multiplicity.
        byName[NormalizeName(reservation.name)] = reservation
    end

    -- Prepare every member result and metadata before replacing any live SR.
    -- Parser/schema failures, including a bad later row, leave history untouched.
    local matched, missingNames, updates = 0, {}, {}
    local memberIndex
    for memberIndex = 1, table.getn(attendance.members) do
        local member = attendance.members[memberIndex]
        if type(member) ~= "table" or type(member.name) ~= "string" or member.name == "" then
            return nil, "The raid roster contains an invalid member. Refresh it before importing Soft Reserves."
        end
        local reservation = byName[NormalizeName(member.name)]
        local update = { member = member, sr = "" }
        if reservation and table.getn(reservation.itemIds) > 0 then
            local itemIds = reservation.itemIds
            local labels = {}
            local itemIndex
            for itemIndex = 1, table.getn(itemIds) do labels[itemIndex] = tostring(itemIds[itemIndex]) end
            update.sr = table.concat(labels, ", ")
            update.itemIds = itemIds
            update.sourceName = reservation.name
            byName[NormalizeName(member.name)] = nil
            matched = matched + 1
        else
            missingNames[table.getn(missingNames) + 1] = member.name
            if reservation then byName[NormalizeName(member.name)] = nil end
        end
        table.insert(updates, update)
    end
    local unmatchedNames, unmatchedReservations, unmatched = {}, {}, 0
    for _, reservation in pairs(byName) do
        unmatched = unmatched + 1
        unmatchedNames[unmatched] = reservation.name
        unmatchedReservations[unmatched] = reservation
    end
    table.sort(unmatchedNames)
    table.sort(unmatchedReservations, function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end)
    table.sort(missingNames)
    local importInfo = {
        id = imported.id or ((attendance.raidName or "raid") .. "-" .. time()),
        origin = imported.origin,
        url = cleanUrl,
        rollForExport = encoded,
        importedAt = time(),
        unmatchedNames = unmatchedNames,
        unmatchedReservations = unmatchedReservations,
        missingNames = missingNames,
    }
    for memberIndex = 1, table.getn(updates) do
        local update = updates[memberIndex]
        update.member.sr, update.member.srItemIds, update.member.srSourceName = update.sr, update.itemIds, update.sourceName
    end
    attendance.softReserveImport = importInfo
    SyncMutation(attendance)
    return { matched = matched, total = table.getn(reservations), unmatched = unmatched, missing = table.getn(missingNames) }
end

function RaidResService.ApplyAssignments(attendance, assignments)
    local importInfo = attendance and attendance.softReserveImport
    local members = attendance and attendance.members
    local reservations = importInfo and importInfo.unmatchedReservations
    if type(members) ~= "table" or type(reservations) ~= "table" or type(assignments) ~= "table" then return false end

    local membersByName, reservationsByName = {}, {}
    local index
    for index = 1, table.getn(members) do membersByName[NormalizeName(members[index].name)] = members[index] end
    for index = 1, table.getn(reservations) do reservationsByName[NormalizeName(reservations[index].name)] = reservations[index] end

    local assignedReservations = {}
    local memberName, reservationName
    for memberName, reservationName in pairs(assignments) do
        local member = membersByName[NormalizeName(memberName)]
        local reservation = reservationsByName[NormalizeName(reservationName)]
        if member and reservation and not assignedReservations[NormalizeName(reservation.name)] then
            local labels = {}
            for index = 1, table.getn(reservation.itemIds or {}) do labels[index] = tostring(reservation.itemIds[index]) end
            if table.getn(labels) > 0 then
                member.sr = table.concat(labels, ", "); member.srItemIds = reservation.itemIds; member.srSourceName = reservation.name
                assignedReservations[NormalizeName(reservation.name)] = true
            end
        end
    end

    local remainingReservations, remainingNames, remainingCount = {}, {}, 0
    for index = 1, table.getn(reservations) do
        if not assignedReservations[NormalizeName(reservations[index].name)] then
            remainingCount = remainingCount + 1
            remainingReservations[remainingCount] = reservations[index]
            remainingNames[remainingCount] = reservations[index].name
        end
    end
    local remainingMissing, missingCount = {}, 0
    for index = 1, table.getn(members) do
        if not members[index].srItemIds or table.getn(members[index].srItemIds) == 0 then
            missingCount = missingCount + 1; remainingMissing[missingCount] = members[index].name
        end
    end
    table.sort(remainingMissing)
    importInfo.unmatchedReservations = remainingReservations
    importInfo.unmatchedNames = remainingNames
    importInfo.missingNames = remainingMissing
    SyncMutation(attendance)
    return true
end

function RaidResService.ClearUnmatched(attendance)
    local importInfo = attendance and attendance.softReserveImport
    if not importInfo then return false end
    importInfo.unmatchedNames = {}
    importInfo.unmatchedReservations = {}
    SyncMutation(attendance)
    return true
end

function RaidResService.RemoveMemberReservation(attendance, memberName)
    local members = attendance and attendance.members
    local importInfo = attendance and attendance.softReserveImport
    if type(members) ~= "table" or not importInfo then return false end
    local member
    local index
    for index = 1, table.getn(members) do
        if NormalizeName(members[index].name) == NormalizeName(memberName) then member = members[index]; break end
    end
    if not member or not member.srItemIds or table.getn(member.srItemIds) == 0 then return false end
    local releasedItemIds = {}
    for index = 1, table.getn(member.srItemIds) do releasedItemIds[index] = member.srItemIds[index] end
    local releasedName = member.srSourceName or member.name
    member.sr = ""; member.srItemIds = nil; member.srSourceName = nil
    local unmatchedReservations = importInfo.unmatchedReservations or {}
    local unmatchedNames = importInfo.unmatchedNames or {}
    local reservationExists = false
    for index = 1, table.getn(unmatchedReservations) do
        if NormalizeName(unmatchedReservations[index].name) == NormalizeName(releasedName) then
            unmatchedReservations[index].manualOnly = true
            reservationExists = true
            break
        end
    end
    if not reservationExists then
        -- Explicit removal is durable assignment intent, not a new import that
        -- may be automatically assigned on the next roster refresh.
        table.insert(unmatchedReservations, { name = releasedName, itemIds = releasedItemIds, manualOnly = true })
        table.insert(unmatchedNames, releasedName)
        table.sort(unmatchedReservations, function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end)
        table.sort(unmatchedNames)
    end
    importInfo.unmatchedReservations = unmatchedReservations
    importInfo.unmatchedNames = unmatchedNames
    local missing, alreadyMissing = importInfo.missingNames or {}, false
    for index = 1, table.getn(missing) do
        if NormalizeName(missing[index]) == NormalizeName(member.name) then alreadyMissing = true; break end
    end
    if not alreadyMissing then table.insert(missing, member.name); table.sort(missing) end
    importInfo.missingNames = missing
    SyncMutation(attendance)
    return true
end

function RaidResService.ClearInvalidMemberReservations(attendance, rules)
    if not attendance or type(attendance.members) ~= "table" then return 0 end
    local cleared = 0
    local index
    for index = 1, table.getn(attendance.members) do
        local member = attendance.members[index]
        local invalidIds = Raider.Services.Raid.GetInvalidSoftReserveItemIds(member, rules)
        if table.getn(invalidIds) > 0 then
            local invalid = {}
            local invalidIndex
            for invalidIndex = 1, table.getn(invalidIds) do invalid[tostring(invalidIds[invalidIndex])] = true end
            local remaining = {}
            local itemIndex
            for itemIndex = 1, table.getn(member.srItemIds) do
                local itemId = member.srItemIds[itemIndex]
                if not invalid[tostring(itemId)] then remaining[table.getn(remaining) + 1] = itemId end
            end
            member.srItemIds = table.getn(remaining) > 0 and remaining or nil
            if table.getn(remaining) == 0 then member.srSourceName = nil end
            local labels = {}
            for itemIndex = 1, table.getn(remaining) do labels[itemIndex] = tostring(remaining[itemIndex]) end
            member.sr = table.concat(labels, ", ")
            cleared = cleared + table.getn(invalidIds)
        end
    end
    if cleared > 0 then SyncMutation(attendance) end
    return cleared
end

function RaidResService.GetUrl(attendance)
    return attendance and attendance.softReserveImport and attendance.softReserveImport.url or ""
end

function RaidResService.GetRollForExport(attendance)
    return attendance and attendance.softReserveImport and attendance.softReserveImport.rollForExport or ""
end

function RaidResService.Reconcile(previousAttendance, attendance)
    local previousImport = previousAttendance and previousAttendance.softReserveImport
    if not attendance or type(attendance.members) ~= "table" or not previousImport then return false end
    attendance.snapshotId = previousAttendance.snapshotId
    attendance.sessionStartedAt = previousAttendance.sessionStartedAt
    attendance.lastSavedAt = previousAttendance.lastSavedAt
    attendance._sessionDraft = previousAttendance._sessionDraft
    local reservationsByName, manualReservations, previousAssignmentState = {}, {}, {}
    local index
    for index = 1, table.getn(previousImport.unmatchedReservations or {}) do
        local reservation = previousImport.unmatchedReservations[index]
        if reservation.manualOnly == true then
            table.insert(manualReservations, { name = reservation.name, itemIds = reservation.itemIds, manualOnly = true })
        else
            reservationsByName[NormalizeName(reservation.name)] = { name = reservation.name, itemIds = reservation.itemIds }
        end
    end
    for index = 1, table.getn(previousAttendance.members or {}) do
        local member = previousAttendance.members[index]
        local key = NormalizeName(member.name)
        local assigned = member.srItemIds and table.getn(member.srItemIds) > 0
        -- nil means a new roster member, false means an existing member with
        -- no assignment, true means a previous assignment may be carried over.
        -- This preserves saved assignments even for snapshots without a marker.
        previousAssignmentState[key] = previousAssignmentState[key] == true or assigned and true or false
        if assigned then
            reservationsByName[key] = { name = member.srSourceName or member.name, itemIds = member.srItemIds }
        end
    end

    local missingNames = {}
    for index = 1, table.getn(attendance.members) do
        local member = attendance.members[index]
        local key = NormalizeName(member.name)
        local reservation = reservationsByName[key]
        if member.srItemIds and table.getn(member.srItemIds) > 0 then
            reservationsByName[key] = nil
        elseif reservation and previousAssignmentState[key] ~= false then
            member.srItemIds = reservation.itemIds
            member.srSourceName = reservation.name
            local labels, itemIndex = {}, nil
            for itemIndex = 1, table.getn(reservation.itemIds or {}) do labels[itemIndex] = tostring(reservation.itemIds[itemIndex]) end
            member.sr = table.concat(labels, ", ")
            reservationsByName[key] = nil
        else
            member.sr = ""; member.srItemIds = nil; member.srSourceName = nil
            missingNames[table.getn(missingNames) + 1] = member.name
        end
    end

    local unmatchedNames, unmatchedReservations = {}, manualReservations
    for index = 1, table.getn(manualReservations) do table.insert(unmatchedNames, manualReservations[index].name) end
    local _, reservation
    for _, reservation in pairs(reservationsByName) do
        table.insert(unmatchedNames, reservation.name)
        table.insert(unmatchedReservations, reservation)
    end
    table.sort(missingNames); table.sort(unmatchedNames)
    table.sort(unmatchedReservations, function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end)
    attendance.softReserveImport = previousImport
    previousImport.missingNames = missingNames; previousImport.unmatchedNames = unmatchedNames; previousImport.unmatchedReservations = unmatchedReservations
    return true
end

function RaidResService.SetUrl(attendance, value)
    if not attendance then return false end
    local url = string.gsub(tostring(value or ""), "^%s+", ""); url = string.gsub(url, "%s+$", "")
    if url == "" then return false end
    if not attendance.softReserveImport then
        attendance.softReserveImport = {
            id = attendance.snapshotId or ((attendance.raidName or "raid") .. "-" .. time()), origin = "manual", importedAt = time(),
            unmatchedNames = {}, unmatchedReservations = {}, missingNames = {},
        }
    end
    attendance.softReserveImport.url = url
    SyncMutation(attendance)
    return true
end

-- Saved raids own their durable loot records. Runtime award queues, lookup
-- indexes and UI objects stay with their controllers and are never copied.
local lootScalarFields = { "recordId", "sourceRecordId", "itemId", "name", "link", "icon", "count", "ordinaryReceipt", "awardHistoryKey", "tradedFrom", "tradedTo" }
local memberScalarFields = { "name", "raidRank", "subgroup", "level", "class", "classFile", "zone", "online", "guildRank", "guildMember", "sr", "srSourceName" }
local function CopyLootRecords(source)
    local records, index, fieldIndex = {}, nil, nil
    for index = 1, table.getn(source or {}) do
        local original, record = source[index], {}
        for fieldIndex = 1, table.getn(lootScalarFields) do
            local key = lootScalarFields[fieldIndex]
            local value = original[key]
            if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then record[key] = value end
        end
        if original.rollHistory and table.getn(original.rollHistory) > 0 then
            record.rollHistory = {}
            local historyIndex
            for historyIndex = 1, table.getn(original.rollHistory) do
                if type(original.rollHistory[historyIndex]) == "string" then table.insert(record.rollHistory, original.rollHistory[historyIndex]) end
            end
        end
        table.insert(records, record)
    end
    return records
end

local function CopyConsumedReserves(source)
    if type(source) ~= "table" then return nil end
    local consumed, itemId, usedAt = {}, nil, nil
    for itemId, usedAt in pairs(source) do
        if tonumber(itemId) and type(usedAt) == "number" then consumed[itemId] = usedAt end
    end
    if next(consumed) == nil then return nil end
    return consumed
end

local function CopySavedMember(member, snapshot)
    local savedMember, fieldIndex = {}, nil
    for fieldIndex = 1, table.getn(memberScalarFields) do
        local key = memberScalarFields[fieldIndex]
        local value = member[key]
        if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then savedMember[key] = value end
    end
    if member.srItemIds and table.getn(member.srItemIds) > 0 then
        savedMember.srItemIds = {}
        local itemIndex
        for itemIndex = 1, table.getn(member.srItemIds) do table.insert(savedMember.srItemIds, member.srItemIds[itemIndex]) end
    end
    if member.loot and table.getn(member.loot) > 0 then
        savedMember.loot = CopyLootRecords(member.loot)
        local lootIndex
        for lootIndex = 1, table.getn(savedMember.loot) do
            snapshot.nextLootRecordId = math.max(snapshot.nextLootRecordId, tonumber(savedMember.loot[lootIndex].recordId) or 0)
        end
    end
    savedMember.reyCoinUsedAt = tonumber(member.reyCoinUsedAt)
    savedMember.reyCoinItemLink = type(member.reyCoinItemLink) == "string" and member.reyCoinItemLink or nil
    savedMember.srConsumedAt = CopyConsumedReserves(member.srConsumedAt)
    return savedMember
end

local function HasRecordedLootState(member)
    return member and ((member.loot and table.getn(member.loot) > 0)
        or (tonumber(member.reyCoinUsedAt) or 0) > 0
        or (member.srConsumedAt and next(member.srConsumedAt) ~= nil))
end

function RaidResService.BuildSnapshot(attendance)
    if not attendance or type(attendance.members) ~= "table" then return nil end
    local importInfo = EnsureSnapshotImport(attendance)
    if not importInfo.id and not attendance.snapshotId then return nil end
    local snapshot = { version = 4, id = attendance.snapshotId or importInfo.id, raidResId = importInfo.id, srUrl = importInfo.url, rollForExport = importInfo.rollForExport, raidName = attendance.raidName, source = importInfo.origin or "raidres", startedAt = attendance.sessionStartedAt or attendance.scannedAt, savedAt = attendance.lastSavedAt, updatedAt = time(), assignedCount = 0, unmatched = {}, missingNames = {}, members = {}, nextLootRecordId = tonumber(attendance.nextLootRecordId) or 0 }
    local index, itemIndex, savedNames = nil, nil, {}
    for index = 1, table.getn(attendance.members or {}) do
        local member = attendance.members[index]
        local savedMember = CopySavedMember(member, snapshot)
        if savedMember.srItemIds then snapshot.assignedCount = snapshot.assignedCount + 1 end
        savedNames[string.lower(member.name or "")] = true
        table.insert(snapshot.members, savedMember)
    end
    for index = 1, table.getn(attendance.departedMembers or {}) do
        local member = attendance.departedMembers[index]
        local key = string.lower(member.name or "")
        if key ~= "" and not savedNames[key] and HasRecordedLootState(member) then
            snapshot.departedMembers = snapshot.departedMembers or {}
            table.insert(snapshot.departedMembers, CopySavedMember(member, snapshot))
            savedNames[key] = true
        end
    end
    for index = 1, table.getn(importInfo.unmatchedReservations or {}) do
        local reservation = importInfo.unmatchedReservations[index]; local itemIds = {}
        for itemIndex = 1, table.getn(reservation.itemIds or {}) do itemIds[itemIndex] = reservation.itemIds[itemIndex] end
        table.insert(snapshot.unmatched, { name = reservation.name, itemIds = itemIds, manualOnly = reservation.manualOnly == true and true or nil })
    end
    for index = 1, table.getn(importInfo.missingNames or {}) do snapshot.missingNames[index] = importInfo.missingNames[index] end
    return snapshot
end

function RaidResService.RestoreSnapshot(snapshot)
    if not snapshot or not snapshot.id then return nil end
    local members, index, itemIndex = {}, 0, 0
    local hasLootHistory = (tonumber(snapshot.version) or 0) >= 4
    local nextLootRecordId = hasLootHistory and (tonumber(snapshot.nextLootRecordId) or 0) or 0
    if snapshot.members and table.getn(snapshot.members) > 0 then
        for index = 1, table.getn(snapshot.members) do
            local source, member = snapshot.members[index], {}
            local key, value
            if hasLootHistory then
                local fieldIndex
                for fieldIndex = 1, table.getn(memberScalarFields) do
                    key = memberScalarFields[fieldIndex]; value = source[key]
                    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then member[key] = value end
                end
            else
                for key, value in pairs(source) do
                    if key ~= "srItemIds" and key ~= "loot" and key ~= "srConsumedAt"
                        and key ~= "reyCoinUsedAt" and key ~= "reyCoinItemLink" then member[key] = value end
                end
            end
            if source.srItemIds then member.srItemIds = {}; for itemIndex = 1, table.getn(source.srItemIds) do member.srItemIds[itemIndex] = source.srItemIds[itemIndex] end end
            member.loot = hasLootHistory and CopyLootRecords(source.loot) or {}
            if hasLootHistory then
                member.reyCoinUsedAt = tonumber(source.reyCoinUsedAt)
                member.reyCoinItemLink = type(source.reyCoinItemLink) == "string" and source.reyCoinItemLink or nil
                member.srConsumedAt = CopyConsumedReserves(source.srConsumedAt)
                local lootIndex
                for lootIndex = 1, table.getn(member.loot) do
                    nextLootRecordId = math.max(nextLootRecordId, tonumber(member.loot[lootIndex].recordId) or 0)
                end
            end
            table.insert(members, member)
        end
    else
        for index = 1, table.getn(snapshot.softReserves or {}) do
            local reserve = snapshot.softReserves[index]; local ids, labels = {}, {}
            for itemIndex = 1, table.getn(reserve.itemIds or {}) do ids[itemIndex] = reserve.itemIds[itemIndex]; labels[itemIndex] = tostring(reserve.itemIds[itemIndex]) end
            table.insert(members, { name = reserve.name, subgroup = 0, level = 0, class = "", classFile = "", zone = "", online = false, guildRank = "", srItemIds = ids, sr = table.concat(labels, ", "), loot = {} })
        end
        for index = 1, table.getn(snapshot.missingNames or {}) do table.insert(members, { name = snapshot.missingNames[index], subgroup = 0, level = 0, class = "", classFile = "", zone = "", online = false, guildRank = "", sr = "", loot = {} }) end
    end
    local unmatched, unmatchedNames, missingNames = {}, {}, {}
    for index = 1, table.getn(snapshot.unmatched or {}) do
        local source, ids = snapshot.unmatched[index], {}
        for itemIndex = 1, table.getn(source.itemIds or {}) do ids[itemIndex] = source.itemIds[itemIndex] end
        unmatched[index] = { name = source.name, itemIds = ids, manualOnly = source.manualOnly == true and true or nil }; unmatchedNames[index] = source.name
    end
    for index = 1, table.getn(snapshot.missingNames or {}) do missingNames[index] = snapshot.missingNames[index] end
    local departedMembers
    if hasLootHistory then
        local savedNames = {}
        for index = 1, table.getn(members) do savedNames[string.lower(members[index].name or "")] = true end
        for index = 1, table.getn(snapshot.departedMembers or {}) do
            local source = snapshot.departedMembers[index]
            local key = string.lower(source.name or "")
            if key ~= "" and not savedNames[key] and HasRecordedLootState(source) then
                local member = CopySavedMember(source, { nextLootRecordId = nextLootRecordId })
                member.loot = member.loot or {}
                local lootIndex
                for lootIndex = 1, table.getn(member.loot) do nextLootRecordId = math.max(nextLootRecordId, tonumber(member.loot[lootIndex].recordId) or 0) end
                departedMembers = departedMembers or {}
                table.insert(departedMembers, member)
                savedNames[key] = true
            end
        end
    end
    local attendance = {
        addonVersion = Raider.version, scannedAt = snapshot.updatedAt, scannedAtText = snapshot.updatedAt and date("%Y-%m-%d %H:%M:%S", snapshot.updatedAt) or "", sessionStartedAt = snapshot.startedAt or snapshot.updatedAt, lastSavedAt = snapshot.savedAt or snapshot.updatedAt,
        raidName = snapshot.raidName, snapshotId = snapshot.id, updatedBy = UnitName("player"), members = members, departedMembers = departedMembers, nextLootRecordId = nextLootRecordId,
        softReserveImport = { id = snapshot.raidResId or snapshot.id, origin = snapshot.source, url = snapshot.srUrl or "", rollForExport = snapshot.rollForExport or "", importedAt = snapshot.updatedAt, unmatchedNames = unmatchedNames, unmatchedReservations = unmatched, missingNames = missingNames },
        _loadedSnapshotId = snapshot.id,
        _sessionDraft = true,
    }
    return Raider.Database.StoreRaidAttendance(attendance)
end

function RaidResService.SyncHistory(attendance)
    -- Explicit calls retain the public copy-return contract, including draft
    -- and transient attendance. Only durable attendance is stored in history.
    local snapshot = RaidResService.BuildSnapshot(attendance)
    if snapshot and not attendance._transient and not attendance._sessionDraft then Raider.Database.StoreSoftReserveSnapshot(snapshot) end
    return snapshot
end
