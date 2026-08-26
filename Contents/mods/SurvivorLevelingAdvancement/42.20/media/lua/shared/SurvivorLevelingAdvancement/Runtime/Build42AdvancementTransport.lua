local Build42AdvancementTransport = {}

local MODULE = "SurvivorLevelingAdvancement"
local REQUEST_COMMAND = "advancementRequest"
local RESPONSE_COMMAND = "advancementResult"
local PROTOCOL_VERSION = 1
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_REQUEST_ID_LENGTH = 64
local MAX_PERK_ID_LENGTH = 128
local MAX_CODE_LENGTH = 64
local MAX_DETAIL_LENGTH = 160

local nextRequestNumber = 0

local REQUEST_FIELDS = {
    protocolVersion = true,
    requestId = true,
    perkId = true,
    expectedRevision = true,
}
local APPLIED_RESPONSE_FIELDS = {
    protocolVersion = true,
    requestId = true,
    perkId = true,
    ok = true,
    applied = true,
    apCost = true,
    mastered = true,
    snapshot = true,
}
local REJECTION_RESPONSE_FIELDS = {
    protocolVersion = true,
    requestId = true,
    perkId = true,
    ok = true,
    applied = true,
    code = true,
    detail = true,
}
local FAILURE_RESPONSE_FIELDS = {
    protocolVersion = true,
    requestId = true,
    perkId = true,
    ok = true,
    code = true,
    detail = true,
    committed = true,
}
local SESSION_APPLIED_FIELDS = {
    ok = true,
    applied = true,
    requestId = true,
    perkId = true,
    apCost = true,
    mastered = true,
    snapshot = true,
}
local SESSION_REJECTION_FIELDS = {
    ok = true,
    applied = true,
    requestId = true,
    perkId = true,
    code = true,
    detail = true,
}
local SESSION_FAILURE_FIELDS = {
    ok = true,
    code = true,
    detail = true,
    committed = true,
}
local SNAPSHOT_VALIDATION_FIELDS = { ok = true, snapshot = true }
local OWNER_ABSENT_FIELDS = { ok = true, present = true }
local OWNER_PRESENT_FIELDS = { ok = true, present = true, snapshot = true }
local ACCEPTED_FIELDS = { ok = true, accepted = true }
local STALE_ACCEPTANCE_FIELDS = { ok = true, accepted = true, code = true }

local function failure(code, detail, committed)
    local result = { ok = false, code = code, detail = detail }
    if committed ~= nil then result.committed = committed end
    return result
end

local function exactPlainTable(value, fields)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not fields[key] then return false end
    end
    for key in pairs(fields) do
        if rawget(value, key) == nil then return false end
    end
    return true
end

local function safeInteger(value)
    return type(value) == "number"
        and value == value
        and value >= 0
        and value <= MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function safeId(value, maximumLength)
    if type(value) ~= "string" or #value == 0 or #value > maximumLength then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        local allowed = (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or byte == 95 or byte == 46 or byte == 58 or byte == 45
        if not allowed then return false end
    end
    return true
end

local function safeCode(value)
    return safeId(value, MAX_CODE_LENGTH)
end

local function safeDetail(value)
    if type(value) ~= "string" or #value == 0 or #value > MAX_DETAIL_LENGTH then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte > 126 then return false end
    end
    return true
end

local function validSlot(localSlot)
    return safeInteger(localSlot) and localSlot <= 3
end

local function validAppliedEffect(value)
    local apCost = rawget(value, "apCost")
    local mastered = rawget(value, "mastered")
    return (apCost == 1 or apCost == 2)
        and type(mastered) == "boolean"
        and mastered == (apCost == 2)
end

local function validateRequestEnvelope(value)
    return exactPlainTable(value, REQUEST_FIELDS)
        and rawget(value, "protocolVersion") == PROTOCOL_VERSION
        and safeId(rawget(value, "requestId"), MAX_REQUEST_ID_LENGTH)
        and safeId(rawget(value, "perkId"), MAX_PERK_ID_LENGTH)
        and safeInteger(rawget(value, "expectedRevision"))
end

local function validateSnapshot(validator, value)
    local called, result = pcall(validator, value)
    if not called
        or not exactPlainTable(result, SNAPSHOT_VALIDATION_FIELDS)
        or rawget(result, "ok") ~= true
        or type(rawget(result, "snapshot")) ~= "table" then
        return nil
    end
    return rawget(result, "snapshot")
end

local function validateResponseEnvelope(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil
        or rawget(value, "protocolVersion") ~= PROTOCOL_VERSION
        or not safeId(rawget(value, "requestId"), MAX_REQUEST_ID_LENGTH)
        or not safeId(rawget(value, "perkId"), MAX_PERK_ID_LENGTH) then
        return nil
    end

    if rawget(value, "ok") == true and rawget(value, "applied") == true then
        if exactPlainTable(value, APPLIED_RESPONSE_FIELDS)
            and validAppliedEffect(value)
            and type(rawget(value, "snapshot")) == "table" then
            return "applied"
        end
        return nil
    end

    if rawget(value, "ok") == true and rawget(value, "applied") == false then
        local fields = REJECTION_RESPONSE_FIELDS
        local hasSnapshot = rawget(value, "snapshot") ~= nil
        if hasSnapshot then
            if rawget(value, "code") ~= "stale_revision" then return nil end
            fields = {
                protocolVersion = true,
                requestId = true,
                perkId = true,
                ok = true,
                applied = true,
                code = true,
                detail = true,
                snapshot = true,
            }
        end
        if exactPlainTable(value, fields)
            and safeCode(rawget(value, "code"))
            and safeDetail(rawget(value, "detail"))
            and (not hasSnapshot or type(rawget(value, "snapshot")) == "table") then
            return "rejected"
        end
        return nil
    end

    if rawget(value, "ok") == false
        and exactPlainTable(value, FAILURE_RESPONSE_FIELDS)
        and safeCode(rawget(value, "code"))
        and safeDetail(rawget(value, "detail"))
        and type(rawget(value, "committed")) == "boolean" then
        return "failure"
    end
    return nil
end

local function mayBeCommitted(result)
    return type(result) == "table"
        and (rawget(result, "committed") == true
            or (rawget(result, "ok") == true and rawget(result, "applied") == true))
end

local function sendServerResult(sender, player, envelope, committed)
    local called = pcall(sender, player, MODULE, RESPONSE_COMMAND, envelope)
    if not called then return failure("send_failed", "sendServerCommand", committed) end
    return { ok = true, handled = true }
end

local function boundaryEnvelope(base, code, detail, committed)
    return {
        protocolVersion = PROTOCOL_VERSION,
        requestId = base.requestId,
        perkId = base.perkId,
        ok = false,
        code = code,
        detail = detail,
        committed = committed,
    }
end

local function validateSessionApplied(result, base)
    return exactPlainTable(result, SESSION_APPLIED_FIELDS)
        and rawget(result, "ok") == true
        and rawget(result, "applied") == true
        and rawget(result, "requestId") == base.requestId
        and rawget(result, "perkId") == base.perkId
        and validAppliedEffect(result)
        and type(rawget(result, "snapshot")) == "table"
end

local function rejectionFields(result)
    if rawget(result, "snapshot") == nil then return SESSION_REJECTION_FIELDS end
    return {
        ok = true,
        applied = true,
        requestId = true,
        perkId = true,
        code = true,
        detail = true,
        snapshot = true,
    }
end

local function validateSessionRejection(result, base)
    if type(result) ~= "table" or getmetatable(result) ~= nil then return false end
    local hasSnapshot = rawget(result, "snapshot") ~= nil
    return exactPlainTable(result, rejectionFields(result))
        and rawget(result, "ok") == true
        and rawget(result, "applied") == false
        and rawget(result, "requestId") == base.requestId
        and rawget(result, "perkId") == base.perkId
        and safeCode(rawget(result, "code"))
        and safeDetail(rawget(result, "detail"))
        and (not hasSnapshot
            or (rawget(result, "code") == "stale_revision"
                and type(rawget(result, "snapshot")) == "table"))
end

local function validateSessionFailure(result)
    return exactPlainTable(result, SESSION_FAILURE_FIELDS)
        and rawget(result, "ok") == false
        and safeCode(rawget(result, "code"))
        and safeDetail(rawget(result, "detail"))
        and type(rawget(result, "committed")) == "boolean"
end

function Build42AdvancementTransport.createServer(dependencies)
    if not exactPlainTable(dependencies, {
        advancementSession = true,
        snapshotValidator = true,
        sendServerCommand = true,
    }) then
        return failure("invalid_dependencies", "dependencies")
    end

    local advancementSession = rawget(dependencies, "advancementSession")
    local validator = rawget(dependencies, "snapshotValidator")
    local sender = rawget(dependencies, "sendServerCommand")
    if type(advancementSession) ~= "table" or getmetatable(advancementSession) ~= nil
        or type(rawget(advancementSession, "request")) ~= "function"
        or type(validator) ~= "function" or type(sender) ~= "function" then
        return failure("invalid_dependencies", "dependencies")
    end

    local request = rawget(advancementSession, "request")
    local server = {}

    function server.handle(module, command, player, args)
        if module ~= MODULE or command ~= REQUEST_COMMAND then
            return { ok = true, handled = false }
        end
        if player == nil then return failure("invalid_player", "player") end
        if not validateRequestEnvelope(args) then return failure("invalid_request", "request") end

        local base = {
            requestId = rawget(args, "requestId"),
            perkId = rawget(args, "perkId"),
        }
        local sessionRequest = {
            perkId = base.perkId,
            requestId = base.requestId,
            expectedRevision = rawget(args, "expectedRevision"),
        }
        local called, result = pcall(request, player, sessionRequest)
        if not called then
            return sendServerResult(
                sender,
                player,
                boundaryEnvelope(base, "session_failed", "unavailable", false),
                false
            )
        end

        local committed = mayBeCommitted(result)
        if validateSessionApplied(result, base) then
            local checkedSnapshot = validateSnapshot(validator, rawget(result, "snapshot"))
            if checkedSnapshot == nil then
                return sendServerResult(
                    sender,
                    player,
                    boundaryEnvelope(base, "snapshot_invalid", "unavailable", true),
                    true
                )
            end
            return sendServerResult(sender, player, {
                protocolVersion = PROTOCOL_VERSION,
                requestId = base.requestId,
                perkId = base.perkId,
                ok = true,
                applied = true,
                apCost = rawget(result, "apCost"),
                mastered = rawget(result, "mastered"),
                snapshot = checkedSnapshot,
            }, true)
        end

        if validateSessionRejection(result, base) then
            local envelope = {
                protocolVersion = PROTOCOL_VERSION,
                requestId = base.requestId,
                perkId = base.perkId,
                ok = true,
                applied = false,
                code = rawget(result, "code"),
                detail = rawget(result, "detail"),
            }
            if rawget(result, "snapshot") ~= nil then
                local checkedSnapshot = validateSnapshot(validator, rawget(result, "snapshot"))
                if checkedSnapshot == nil then
                    return sendServerResult(
                        sender,
                        player,
                        boundaryEnvelope(base, "snapshot_invalid", "unavailable", false),
                        false
                    )
                end
                envelope.snapshot = checkedSnapshot
            end
            return sendServerResult(sender, player, envelope, false)
        end

        if validateSessionFailure(result) then
            return sendServerResult(sender, player, boundaryEnvelope(
                base,
                rawget(result, "code"),
                rawget(result, "detail"),
                rawget(result, "committed")
            ), rawget(result, "committed"))
        end

        return sendServerResult(
            sender,
            player,
            boundaryEnvelope(base, "session_failed", "malformed", committed),
            committed
        )
    end

    return { ok = true, server = server }
end

local function copySummary(value)
    if value == nil then return nil end
    local copy = {}
    for key, item in pairs(value) do copy[key] = item end
    return copy
end

local function appliedSummary(envelope, snapshotAccepted, snapshotCode)
    local result = {
        ok = true,
        applied = true,
        requestId = rawget(envelope, "requestId"),
        perkId = rawget(envelope, "perkId"),
        apCost = rawget(envelope, "apCost"),
        mastered = rawget(envelope, "mastered"),
        snapshotAccepted = snapshotAccepted,
    }
    if snapshotCode ~= nil then result.snapshotCode = snapshotCode end
    return result
end

local function rejectionSummary(envelope, snapshotAccepted, snapshotCode)
    local result = {
        ok = true,
        applied = false,
        requestId = rawget(envelope, "requestId"),
        perkId = rawget(envelope, "perkId"),
        code = rawget(envelope, "code"),
        detail = rawget(envelope, "detail"),
    }
    if snapshotAccepted ~= nil then result.snapshotAccepted = snapshotAccepted end
    if snapshotCode ~= nil then result.snapshotCode = snapshotCode end
    return result
end

local function failureSummary(envelope)
    return {
        ok = false,
        requestId = rawget(envelope, "requestId"),
        perkId = rawget(envelope, "perkId"),
        code = rawget(envelope, "code"),
        detail = rawget(envelope, "detail"),
        committed = rawget(envelope, "committed"),
    }
end

local function snapshotFailureSummary(envelope, kind)
    local result = {
        ok = false,
        applied = kind == "applied",
        requestId = rawget(envelope, "requestId"),
        perkId = rawget(envelope, "perkId"),
        code = "snapshot_rejected",
        detail = "ownerClient.acceptLocal",
        committed = kind == "applied",
    }
    if kind == "applied" then
        result.apCost = rawget(envelope, "apCost")
        result.mastered = rawget(envelope, "mastered")
    else
        result.upstreamCode = rawget(envelope, "code")
        result.upstreamDetail = rawget(envelope, "detail")
    end
    return result
end

local function inspectAcceptance(accept, localSlot, snapshot)
    local called, result = pcall(accept, localSlot, snapshot)
    if not called then return nil end
    if exactPlainTable(result, ACCEPTED_FIELDS)
        and rawget(result, "ok") == true and rawget(result, "accepted") == true then
        return true
    end
    if exactPlainTable(result, STALE_ACCEPTANCE_FIELDS)
        and rawget(result, "ok") == true
        and rawget(result, "accepted") == false
        and rawget(result, "code") == "stale_snapshot" then
        return false, "stale_snapshot"
    end
    return nil
end

function Build42AdvancementTransport.createClient(dependencies)
    if not exactPlainTable(dependencies, { ownerClient = true, sendClientCommand = true }) then
        return failure("invalid_dependencies", "dependencies")
    end

    local ownerClient = rawget(dependencies, "ownerClient")
    local sender = rawget(dependencies, "sendClientCommand")
    if type(ownerClient) ~= "table" or getmetatable(ownerClient) ~= nil
        or type(rawget(ownerClient, "get")) ~= "function"
        or type(rawget(ownerClient, "acceptLocal")) ~= "function"
        or type(sender) ~= "function" then
        return failure("invalid_dependencies", "dependencies")
    end

    local getOwnerState = rawget(ownerClient, "get")
    local acceptOwnerSnapshot = rawget(ownerClient, "acceptLocal")
    local pendingBySlot = {}
    local lastBySlot = {}
    local client = {}

    local function findPending(requestId)
        for localSlot = 0, 3 do
            local pending = pendingBySlot[localSlot]
            if pending ~= nil and pending.requestId == requestId then
                return localSlot, pending
            end
        end
        return nil, nil
    end

    function client.request(localSlot, player, perkId)
        if not validSlot(localSlot) or player == nil
            or not safeId(perkId, MAX_PERK_ID_LENGTH) then
            return failure("invalid_request", "request")
        end
        if pendingBySlot[localSlot] ~= nil then return failure("pending_request", "slot") end

        local called, current = pcall(getOwnerState, localSlot)
        if not called then return failure("owner_state_failed", "unavailable") end
        local absent = exactPlainTable(current, OWNER_ABSENT_FIELDS)
            and rawget(current, "ok") == true and rawget(current, "present") == false
        local present = exactPlainTable(current, OWNER_PRESENT_FIELDS)
            and rawget(current, "ok") == true and rawget(current, "present") == true
        if not absent and not present then return failure("owner_state_failed", "malformed") end
        if absent then return failure("not_ready", "owner snapshot") end

        local ownerSnapshot = rawget(current, "snapshot")
        if type(ownerSnapshot) ~= "table" or getmetatable(ownerSnapshot) ~= nil
            or rawget(ownerSnapshot, "ready") ~= true
            or not safeInteger(rawget(ownerSnapshot, "revision")) then
            return failure("not_ready", "owner snapshot")
        end
        if nextRequestNumber >= MAX_SAFE_INTEGER then
            return failure("request_id_exhausted", "counter")
        end

        nextRequestNumber = nextRequestNumber + 1
        local requestId = "advancement:" .. tostring(nextRequestNumber)
        local envelope = {
            protocolVersion = PROTOCOL_VERSION,
            requestId = requestId,
            perkId = perkId,
            expectedRevision = rawget(ownerSnapshot, "revision"),
        }
        pendingBySlot[localSlot] = { requestId = requestId, perkId = perkId }
        lastBySlot[localSlot] = nil

        local sent = pcall(sender, player, MODULE, REQUEST_COMMAND, envelope)
        if not sent then
            pendingBySlot[localSlot] = nil
            lastBySlot[localSlot] = {
                ok = false,
                requestId = requestId,
                perkId = perkId,
                code = "send_failed",
                detail = "sendClientCommand",
                committed = false,
            }
            return failure("send_failed", "sendClientCommand", false)
        end
        return { ok = true, requestId = requestId }
    end

    function client.handle(module, command, args)
        if module ~= MODULE or command ~= RESPONSE_COMMAND then
            return { ok = true, handled = false }
        end

        local kind = validateResponseEnvelope(args)
        if kind == nil then return failure("invalid_response", "response") end
        local localSlot, pending = findPending(rawget(args, "requestId"))
        if pending == nil or pending.perkId ~= rawget(args, "perkId") then
            return failure("unknown_response", "route")
        end

        pendingBySlot[localSlot] = nil
        local summary
        if kind == "applied"
            or (kind == "rejected" and rawget(args, "snapshot") ~= nil) then
            local accepted, acceptanceCode = inspectAcceptance(
                acceptOwnerSnapshot,
                localSlot,
                rawget(args, "snapshot")
            )
            if accepted == nil then
                summary = snapshotFailureSummary(args, kind)
            elseif kind == "applied" then
                summary = appliedSummary(args, accepted, acceptanceCode)
            else
                summary = rejectionSummary(args, accepted, acceptanceCode)
            end
        elseif kind == "rejected" then
            summary = rejectionSummary(args)
        else
            summary = failureSummary(args)
        end

        lastBySlot[localSlot] = summary
        return { ok = true, handled = true, localSlot = localSlot, result = copySummary(summary) }
    end

    function client.status(localSlot)
        if not validSlot(localSlot) then return failure("invalid_slot", "slot") end
        local pending = pendingBySlot[localSlot]
        if pending ~= nil then
            return {
                ok = true,
                pending = true,
                requestId = pending.requestId,
                perkId = pending.perkId,
            }
        end
        local result = copySummary(lastBySlot[localSlot])
        if result == nil then return { ok = true, pending = false } end
        return { ok = true, pending = false, result = result }
    end

    function client.resetSlot(localSlot)
        if not validSlot(localSlot) then return failure("invalid_slot", "slot") end
        pendingBySlot[localSlot] = nil
        lastBySlot[localSlot] = nil
        return { ok = true }
    end

    function client.reset()
        for localSlot = 0, 3 do
            pendingBySlot[localSlot] = nil
            lastBySlot[localSlot] = nil
        end
        return { ok = true }
    end

    return { ok = true, client = client }
end

return Build42AdvancementTransport
