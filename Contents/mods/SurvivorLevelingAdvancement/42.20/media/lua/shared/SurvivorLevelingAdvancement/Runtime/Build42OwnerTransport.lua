local Build42OwnerTransport = {}

local MODULE = "SurvivorLevelingAdvancement"
local READY_COMMAND = "ownerReady"
local SNAPSHOT_COMMAND = "ownerSnapshot"
local PROTOCOL_VERSION = 1
local MAX_CORRELATION_LENGTH = 64
local MAX_CODE_LENGTH = 64
local MAX_DETAIL_LENGTH = 160
local MAX_SAFE_INTEGER = 9007199254740991

local REQUEST_FIELDS = { protocolVersion = true, correlationId = true }
local SUCCESS_FIELDS = {
    protocolVersion = true,
    correlationId = true,
    ok = true,
    snapshot = true,
}
local FAILURE_FIELDS = {
    protocolVersion = true,
    correlationId = true,
    ok = true,
    code = true,
    detail = true,
}
local VALIDATION_SUCCESS_FIELDS = { ok = true, snapshot = true }

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
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

local function printable(value, maximumLength)
    return type(value) == "string" and #value > 0 and #value <= maximumLength
        and value:find("[%c]") == nil
end

local function nonnegativeInteger(value)
    return type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value >= 0 and value == math.floor(value)
end

local function positiveInteger(value)
    return nonnegativeInteger(value) and value > 0
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

local function boundedDependencyFailure(result, fallbackCode, fallbackDetail)
    if type(result) == "table" and result.ok == false
        and safeId(rawget(result, "code"), MAX_CODE_LENGTH)
        and printable(rawget(result, "detail"), MAX_DETAIL_LENGTH) then
        return failure(rawget(result, "code"), rawget(result, "detail"))
    end
    return failure(fallbackCode, fallbackDetail)
end

local function validateRequest(args)
    if not exactPlainTable(args, REQUEST_FIELDS) then
        return nil, failure("invalid_request", "request shape")
    end
    if args.protocolVersion ~= PROTOCOL_VERSION then
        return nil, failure("protocol_mismatch", "protocolVersion")
    end
    if not safeId(args.correlationId, MAX_CORRELATION_LENGTH) then
        return nil, failure("invalid_request", "correlationId")
    end
    return args.correlationId
end

local function validateResponse(args)
    if type(args) ~= "table" or getmetatable(args) ~= nil then
        return nil, failure("invalid_response", "response shape")
    end
    local isSuccess = rawget(args, "ok")
    if isSuccess ~= true and isSuccess ~= false then
        return nil, failure("invalid_response", "response shape")
    end
    local fields = isSuccess and SUCCESS_FIELDS or FAILURE_FIELDS
    if not exactPlainTable(args, fields) then
        return nil, failure("invalid_response", "response shape")
    end
    if args.protocolVersion ~= PROTOCOL_VERSION then
        return nil, failure("protocol_mismatch", "protocolVersion")
    end
    if not safeId(args.correlationId, MAX_CORRELATION_LENGTH) then
        return nil, failure("invalid_response", "correlationId")
    end
    if isSuccess then
        if type(args.snapshot) ~= "table" then
            return nil, failure("invalid_response", "snapshot")
        end
    elseif not safeId(args.code, MAX_CODE_LENGTH)
        or not printable(args.detail, MAX_DETAIL_LENGTH) then
        return nil, failure("invalid_response", "failure detail")
    end
    return args
end

local function sessionSnapshot(callable, operation, player)
    local called, result = pcall(callable, player)
    if not called then
        return nil, failure("session_" .. operation .. "_threw", "ownerSession." .. operation)
    end
    if type(result) == "table" and result.ok == true and type(result.snapshot) == "table" then
        return result.snapshot
    end
    return nil, boundedDependencyFailure(
        result,
        "session_" .. operation .. "_invalid",
        "ownerSession." .. operation
    )
end

local function validateServerSnapshot(validateSnapshot, snapshot)
    local called, result = pcall(validateSnapshot, snapshot)
    if not called then
        return nil, failure("snapshot_validation_threw", "snapshotValidator.validate")
    end
    if exactPlainTable(result, VALIDATION_SUCCESS_FIELDS)
        and result.ok == true and type(result.snapshot) == "table" then
        return result.snapshot
    end
    return nil, boundedDependencyFailure(
        result,
        "snapshot_validation_invalid",
        "snapshotValidator.validate"
    )
end

local function sendServer(send, player, envelope)
    local called = pcall(send, player, MODULE, SNAPSHOT_COMMAND, envelope)
    if not called then return failure("send_threw", "sendServerCommand") end
    return { ok = true }
end

local function sendClient(send, player, envelope)
    local called = pcall(send, player, MODULE, READY_COMMAND, envelope)
    if not called then return failure("send_threw", "sendClientCommand") end
    return { ok = true }
end

local function serverSuccess(correlationId, snapshot)
    return {
        protocolVersion = PROTOCOL_VERSION,
        correlationId = correlationId,
        ok = true,
        snapshot = snapshot,
    }
end

local function serverFailure(correlationId, failed)
    return {
        protocolVersion = PROTOCOL_VERSION,
        correlationId = correlationId,
        ok = false,
        code = failed.code,
        detail = failed.detail,
    }
end

function Build42OwnerTransport.createServer(dependencies)
    if type(dependencies) ~= "table" then
        return failure("invalid_dependencies", "dependencies")
    end
    local ownerSession = dependencies.ownerSession
    if type(ownerSession) ~= "table" or type(ownerSession.ready) ~= "function"
        or type(ownerSession.snapshot) ~= "function"
        or type(ownerSession.clearPlayer) ~= "function" then
        return failure("invalid_dependencies", "ownerSession")
    end
    local snapshotValidator = dependencies.snapshotValidator
    local validateSnapshot = type(snapshotValidator) == "table" and snapshotValidator.validate or nil
    if type(validateSnapshot) ~= "function" then
        return failure("invalid_dependencies", "snapshotValidator.validate")
    end
    local send = dependencies.sendServerCommand
    if type(send) ~= "function" then
        return failure("invalid_dependencies", "sendServerCommand")
    end

    local bindings = setmetatable({}, { __mode = "k" })
    local server = {}

    function server.handle(module, command, player, args)
        if module ~= MODULE then return { ok = true, handled = false } end
        if command ~= READY_COMMAND then
            return failure("unknown_command", "owner command")
        end
        if player == nil then return failure("invalid_player", "player") end

        local correlationId, requestFailure = validateRequest(args)
        if correlationId == nil then return requestFailure end

        local snapshot, readyFailure = sessionSnapshot(ownerSession.ready, "ready", player)
        if snapshot == nil then
            local sentFailure = sendServer(send, player, serverFailure(correlationId, readyFailure))
            if not sentFailure.ok then return sentFailure end
            return readyFailure
        end

        local checkedSnapshot, validationFailure = validateServerSnapshot(validateSnapshot, snapshot)
        if checkedSnapshot == nil then
            local sentFailure = sendServer(send, player, serverFailure(correlationId, validationFailure))
            if not sentFailure.ok then return sentFailure end
            return validationFailure
        end

        local sent = sendServer(send, player, serverSuccess(correlationId, checkedSnapshot))
        if not sent.ok then return sent end
        bindings[player] = correlationId
        return { ok = true, handled = true }
    end

    function server.publish(player)
        if player == nil then return failure("invalid_player", "player") end
        local correlationId = bindings[player]
        if correlationId == nil then return failure("not_bound", "player route") end

        local snapshot, snapshotFailure = sessionSnapshot(ownerSession.snapshot, "snapshot", player)
        if snapshot == nil then
            local sentFailure = sendServer(send, player, serverFailure(correlationId, snapshotFailure))
            if not sentFailure.ok then return sentFailure end
            return snapshotFailure
        end

        local checkedSnapshot, validationFailure = validateServerSnapshot(validateSnapshot, snapshot)
        if checkedSnapshot == nil then
            local sentFailure = sendServer(send, player, serverFailure(correlationId, validationFailure))
            if not sentFailure.ok then return sentFailure end
            return validationFailure
        end

        local sent = sendServer(send, player, serverSuccess(correlationId, checkedSnapshot))
        if not sent.ok then return sent end
        return { ok = true, published = true }
    end

    function server.clearPlayer(player)
        if player == nil then return failure("invalid_player", "player") end
        local called, result = pcall(ownerSession.clearPlayer, player)
        if not called then return failure("session_clearPlayer_threw", "ownerSession.clearPlayer") end
        if type(result) ~= "table" or result.ok ~= true then
            return boundedDependencyFailure(result, "session_clearPlayer_invalid", "ownerSession.clearPlayer")
        end
        bindings[player] = nil
        return { ok = true }
    end

    return { ok = true, server = server }
end

local function validateInbox(value)
    return type(value) == "table" and type(value.accept) == "function"
        and type(value.get) == "function" and type(value.reset) == "function"
        and type(value.status) == "function"
end

local function inboxCall(inbox, method, ...)
    local called, result = pcall(inbox[method], ...)
    if not called then return nil, failure("inbox_" .. method .. "_threw", "ClientOwnerState." .. method) end
    if type(result) ~= "table" or type(result.ok) ~= "boolean" then
        return nil, failure("inbox_" .. method .. "_invalid", "ClientOwnerState." .. method)
    end
    if not result.ok then
        return nil, boundedDependencyFailure(
            result,
            "inbox_" .. method .. "_invalid",
            "ClientOwnerState." .. method
        )
    end
    return result
end

function Build42OwnerTransport.createClient(dependencies)
    if type(dependencies) ~= "table" then
        return failure("invalid_dependencies", "dependencies")
    end
    local inboxFactory = dependencies.ClientOwnerState
    if type(inboxFactory) ~= "table" or type(inboxFactory.create) ~= "function" then
        return failure("invalid_dependencies", "ClientOwnerState.create")
    end
    local send = dependencies.sendClientCommand
    if type(send) ~= "function" then
        return failure("invalid_dependencies", "sendClientCommand")
    end

    local slots = {}
    local routes = {}
    local counter = 0
    local client = {}

    local function validSlot(localSlot)
        return nonnegativeInteger(localSlot) and localSlot <= 3
    end

    local function removeRoutes(entry)
        if entry.pending ~= nil then routes[entry.pending] = nil end
        if entry.active ~= nil then routes[entry.active] = nil end
        entry.pending = nil
        entry.active = nil
    end

    local function createInbox()
        local called, created = pcall(inboxFactory.create)
        if not called then return nil, failure("inbox_create_threw", "ClientOwnerState.create") end
        if type(created) ~= "table" or created.ok ~= true or not validateInbox(created.state) then
            return nil, boundedDependencyFailure(
                created,
                "inbox_create_invalid",
                "ClientOwnerState.create"
            )
        end
        return created.state
    end

    local function entryFor(localSlot, create)
        local entry = slots[localSlot]
        if entry == nil and create then
            local inbox, createFailure = createInbox()
            if inbox == nil then return nil, createFailure end
            entry = { inbox = inbox, pending = nil, active = nil, failure = nil }
            slots[localSlot] = entry
        end
        return entry
    end

    local function allocateCorrelation()
        if counter >= MAX_SAFE_INTEGER then
            return nil, failure("correlation_exhausted", "correlation counter")
        end
        counter = counter + 1
        local correlationId = "owner-ready-" .. tostring(counter)
        if not safeId(correlationId, MAX_CORRELATION_LENGTH) then
            return nil, failure("correlation_exhausted", "correlation counter")
        end
        return correlationId
    end

    function client.ready(localSlot, player)
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        if player == nil then return failure("invalid_player", "player") end

        local resetResult = client.resetSlot(localSlot)
        if not resetResult.ok then return resetResult end
        local entry, entryFailure = entryFor(localSlot, true)
        if entry == nil then return entryFailure end

        local correlationId, correlationFailure = allocateCorrelation()
        if correlationId == nil then return correlationFailure end
        entry.pending = correlationId
        routes[correlationId] = { slot = localSlot, phase = "pending" }

        local sent = sendClient(send, player, {
            protocolVersion = PROTOCOL_VERSION,
            correlationId = correlationId,
        })
        if not sent.ok then
            routes[correlationId] = nil
            entry.pending = nil
            entry.failure = { code = sent.code, detail = sent.detail }
            return sent
        end
        return { ok = true, correlationId = correlationId }
    end

    function client.handle(module, command, args)
        if module ~= MODULE or command ~= SNAPSHOT_COMMAND then
            return { ok = true, handled = false }
        end

        local response, responseFailure = validateResponse(args)
        if response == nil then return responseFailure end
        local route = routes[response.correlationId]
        if type(route) ~= "table" then
            return failure("unknown_correlation", "correlationId")
        end
        local entry = slots[route.slot]
        if type(entry) ~= "table"
            or (route.phase == "pending" and entry.pending ~= response.correlationId)
            or (route.phase == "active" and entry.active ~= response.correlationId)
            or (route.phase ~= "pending" and route.phase ~= "active") then
            return failure("unknown_correlation", "correlationId")
        end

        if response.ok == false then
            if route.phase == "pending" then
                routes[response.correlationId] = nil
                entry.pending = nil
            end
            entry.failure = { code = response.code, detail = response.detail }
            return {
                ok = true,
                handled = true,
                accepted = false,
                code = response.code,
            }
        end

        local accepted, acceptFailure = inboxCall(entry.inbox, "accept", response.snapshot)
        if accepted == nil then return acceptFailure end
        if type(accepted.accepted) ~= "boolean" then
            return failure("inbox_accept_invalid", "ClientOwnerState.accept")
        end
        if not accepted.accepted then
            local code = safeId(accepted.code, MAX_CODE_LENGTH) and accepted.code or "not_accepted"
            return { ok = true, handled = true, accepted = false, code = code }
        end

        if entry.active ~= nil and entry.active ~= response.correlationId then
            routes[entry.active] = nil
        end
        entry.pending = nil
        entry.active = response.correlationId
        route.phase = "active"
        entry.failure = nil
        return { ok = true, handled = true, accepted = true }
    end

    function client.acceptLocal(localSlot, snapshot)
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        local entry, entryFailure = entryFor(localSlot, true)
        if entry == nil then return entryFailure end
        local accepted, acceptFailure = inboxCall(entry.inbox, "accept", snapshot)
        if accepted == nil then return acceptFailure end
        if type(accepted.accepted) ~= "boolean" then
            return failure("inbox_accept_invalid", "ClientOwnerState.accept")
        end
        if accepted.accepted then entry.failure = nil end
        return accepted
    end

    function client.resetSlot(localSlot)
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        local entry = entryFor(localSlot, false)
        if entry == nil then return { ok = true } end
        local resetResult, resetFailure = inboxCall(entry.inbox, "reset")
        if resetResult == nil then return resetFailure end
        removeRoutes(entry)
        entry.failure = nil
        return { ok = true }
    end

    function client.get(localSlot)
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        local entry = entryFor(localSlot, false)
        if entry == nil then return { ok = true, present = false } end
        local result, getFailure = inboxCall(entry.inbox, "get")
        if result == nil then return getFailure end
        if type(result.present) ~= "boolean" then
            return failure("inbox_get_invalid", "ClientOwnerState.get")
        end
        if not result.present then return { ok = true, present = false } end
        if type(result.snapshot) ~= "table" then
            return failure("inbox_get_invalid", "ClientOwnerState.get")
        end
        return { ok = true, present = true, snapshot = result.snapshot }
    end

    function client.status(localSlot)
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        local entry = entryFor(localSlot, false)
        if entry == nil then return { ok = true, present = false, route = "none" } end
        local inboxStatus, statusFailure = inboxCall(entry.inbox, "status")
        if inboxStatus == nil then return statusFailure end
        if type(inboxStatus.present) ~= "boolean" then
            return failure("inbox_status_invalid", "ClientOwnerState.status")
        end

        local result = {
            ok = true,
            present = inboxStatus.present,
            route = entry.pending ~= nil and "pending" or entry.active ~= nil and "active" or "none",
        }
        if inboxStatus.present then
            if type(inboxStatus.ready) ~= "boolean" or not positiveInteger(inboxStatus.sequence)
                or not nonnegativeInteger(inboxStatus.revision) then
                return failure("inbox_status_invalid", "ClientOwnerState.status")
            end
            result.ready = inboxStatus.ready
            result.sequence = inboxStatus.sequence
            result.revision = inboxStatus.revision
        end
        if entry.failure ~= nil then
            result.failure = { code = entry.failure.code, detail = entry.failure.detail }
        end
        return result
    end

    function client.reset()
        local firstFailure = nil
        for _, entry in pairs(slots) do
            local resetResult, resetFailure = inboxCall(entry.inbox, "reset")
            if resetResult == nil and firstFailure == nil then firstFailure = resetFailure end
        end
        slots = {}
        routes = {}
        if firstFailure ~= nil then return firstFailure end
        return { ok = true }
    end

    return { ok = true, client = client }
end

return Build42OwnerTransport
