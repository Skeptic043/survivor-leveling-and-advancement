local Build42AdminTransport = {}

local MODULE = "SurvivorLevelingAdvancement"
local REQUEST_COMMAND = "adminRequest"
local RESPONSE_COMMAND = "adminResult"
local PROTOCOL_VERSION = 1
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_REQUEST_ID_LENGTH = 64
local MAX_USERNAME_LENGTH = 64
local MAX_CODE_LENGTH = 64
local MAX_DETAIL_LENGTH = 160

local nextRequestNumber = 0

local INSPECT_REQUEST_FIELDS = {
    protocolVersion = true,
    requestId = true,
    operation = true,
    target = true,
}
local XP_REQUEST_FIELDS = {
    protocolVersion = true,
    requestId = true,
    operation = true,
    target = true,
    expectedRevision = true,
    amount = true,
}
local LEVEL_REQUEST_FIELDS = {
    protocolVersion = true,
    requestId = true,
    operation = true,
    target = true,
    expectedRevision = true,
    count = true,
}
local USERNAME_TARGET_FIELDS = { username = true }
local TARGET_FIELDS = { onlineId = true, username = true }
local SUMMARY_FIELDS = {
    accountingMode = true,
    revision = true,
    level = true,
    xpIntoLevel = true,
    xpForNextLevel = true,
    spent = true,
    availableAp = true,
}
local INSPECTION_RESULT_FIELDS = { ok = true, summary = true }
local XP_APPLIED_FIELDS = {
    ok = true,
    applied = true,
    kind = true,
    amount = true,
    levelsGained = true,
    apGained = true,
    summary = true,
}
local LEVEL_APPLIED_FIELDS = {
    ok = true,
    applied = true,
    kind = true,
    count = true,
    levelsGained = true,
    apGained = true,
    summary = true,
}
local REJECTION_RESULT_FIELDS = {
    ok = true,
    applied = true,
    kind = true,
    code = true,
    detail = true,
    summary = true,
}
local SESSION_FAILURE_FIELDS = {
    ok = true,
    code = true,
    detail = true,
    committed = true,
}
local INSPECT_LOGICAL_REQUEST_FIELDS = { operation = true, target = true }
local XP_LOGICAL_REQUEST_FIELDS = {
    operation = true,
    target = true,
    expectedRevision = true,
    amount = true,
}
local LEVEL_LOGICAL_REQUEST_FIELDS = {
    operation = true,
    target = true,
    expectedRevision = true,
    count = true,
}
local INSPECTION_RESPONSE_FIELDS = {
    protocolVersion = true,
    requestId = true,
    operation = true,
    target = true,
    ok = true,
    outcome = true,
    summary = true,
}
local APPLIED_RESPONSE_FIELDS = {
    protocolVersion = true,
    requestId = true,
    operation = true,
    target = true,
    ok = true,
    outcome = true,
    levelsGained = true,
    apGained = true,
    summary = true,
}
local REJECTION_RESPONSE_FIELDS = {
    protocolVersion = true,
    requestId = true,
    operation = true,
    target = true,
    ok = true,
    outcome = true,
    code = true,
    detail = true,
    summary = true,
}
local FAILURE_RESPONSE_FIELDS = {
    protocolVersion = true,
    requestId = true,
    operation = true,
    target = true,
    ok = true,
    code = true,
    detail = true,
    committed = true,
}

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

local function positiveSafeInteger(value)
    return safeInteger(value) and value > 0
end

local function validSlot(value)
    return safeInteger(value) and value <= 3
end

local function finitePositive(value)
    return type(value) == "number"
        and value == value
        and value > 0
        and value < math.huge
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

local function safePrintable(value, maximumLength)
    if type(value) ~= "string" or #value == 0 or #value > maximumLength then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte > 126 then return false end
    end
    return true
end

local function safeUsername(value)
    if type(value) ~= "string" or #value == 0 or #value > MAX_USERNAME_LENGTH then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then return false end
    end
    return true
end

local function safeCode(value)
    return safeId(value, MAX_CODE_LENGTH)
end

local function safeDetail(value)
    return safePrintable(value, MAX_DETAIL_LENGTH)
end

local function copyTarget(value)
    if not exactPlainTable(value, TARGET_FIELDS)
        or not safeInteger(rawget(value, "onlineId"))
        or not safeUsername(rawget(value, "username")) then
        return nil
    end
    return {
        onlineId = rawget(value, "onlineId"),
        username = rawget(value, "username"),
    }
end

local function copyUsernameTarget(value)
    if not exactPlainTable(value, USERNAME_TARGET_FIELDS)
        or not safeUsername(rawget(value, "username")) then
        return nil
    end
    return { username = rawget(value, "username") }
end

local function copyResponseTarget(value)
    local canonical = copyTarget(value)
    if canonical ~= nil then return canonical end
    return copyUsernameTarget(value)
end

local function copySummary(value)
    if not exactPlainTable(value, SUMMARY_FIELDS) then return nil end
    local accountingMode = rawget(value, "accountingMode")
    local revision = rawget(value, "revision")
    local level = rawget(value, "level")
    local xpIntoLevel = rawget(value, "xpIntoLevel")
    local xpForNextLevel = rawget(value, "xpForNextLevel")
    local spent = rawget(value, "spent")
    local availableAp = rawget(value, "availableAp")
    if (accountingMode ~= "Tracked" and accountingMode ~= "Free")
        or not safeInteger(revision)
        or not safeInteger(level)
        or type(xpIntoLevel) ~= "number" or xpIntoLevel ~= xpIntoLevel
        or xpIntoLevel < 0 or xpIntoLevel == math.huge
        or not finitePositive(xpForNextLevel)
        or xpIntoLevel >= xpForNextLevel
        or not safeInteger(spent) or spent > level
        or not safeInteger(availableAp) or availableAp ~= level - spent then
        return nil
    end
    return {
        accountingMode = accountingMode,
        revision = revision,
        level = level,
        xpIntoLevel = xpIntoLevel,
        xpForNextLevel = xpForNextLevel,
        spent = spent,
        availableAp = availableAp,
    }
end

local function validateRequestEnvelope(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil
        or rawget(value, "protocolVersion") ~= PROTOCOL_VERSION
        or not safeId(rawget(value, "requestId"), MAX_REQUEST_ID_LENGTH) then
        return nil
    end

    local operation = rawget(value, "operation")
    local fields
    if operation == "inspect" then
        fields = INSPECT_REQUEST_FIELDS
    elseif operation == "awardSurvivorXp" then
        fields = XP_REQUEST_FIELDS
    elseif operation == "awardSurvivorLevels" then
        fields = LEVEL_REQUEST_FIELDS
    else
        return nil
    end
    if not exactPlainTable(value, fields) then return nil end

    local target
    if operation == "inspect" then
        target = copyUsernameTarget(rawget(value, "target"))
    else
        target = copyTarget(rawget(value, "target"))
    end
    if target == nil then return nil end
    if operation == "awardSurvivorXp" then
        if not safeInteger(rawget(value, "expectedRevision"))
            or not finitePositive(rawget(value, "amount")) then
            return nil
        end
    elseif operation == "awardSurvivorLevels" then
        if not safeInteger(rawget(value, "expectedRevision"))
            or not positiveSafeInteger(rawget(value, "count")) then
            return nil
        end
    end

    return {
        requestId = rawget(value, "requestId"),
        operation = operation,
        target = target,
        expectedRevision = rawget(value, "expectedRevision"),
        amount = rawget(value, "amount"),
        count = rawget(value, "count"),
    }
end

local function responseBase(request, target)
    local detachedTarget = copyResponseTarget(target)
    return {
        protocolVersion = PROTOCOL_VERSION,
        requestId = request.requestId,
        operation = request.operation,
        target = detachedTarget,
    }
end

local function failureEnvelope(request, target, code, detail, committed)
    local result = responseBase(request, target)
    result.ok = false
    result.code = code
    result.detail = detail
    result.committed = committed
    return result
end

local function sendResult(sender, actor, envelope, committed)
    local called = pcall(sender, actor, MODULE, RESPONSE_COMMAND, envelope)
    if not called then return failure("send_failed", "sendServerCommand", committed) end
    return { ok = true, handled = true }
end

local function publicBoundaryFailure(request, sender, actor)
    return sendResult(sender, actor, failureEnvelope(
        request,
        request.target,
        "request_denied",
        "unavailable",
        false
    ), false)
end

local function validDependencySuccess(result)
    return type(result) == "table"
        and getmetatable(result) == nil
        and rawget(result, "ok") == true
end

local function validateBoundaryResult(result)
    if not exactPlainTable(result, { ok = true, target = true, targetRef = true })
        or rawget(result, "ok") ~= true
        or rawget(result, "target") == nil then
        return nil, nil
    end
    local targetRef = copyTarget(rawget(result, "targetRef"))
    if targetRef == nil then return nil, nil end
    return rawget(result, "target"), targetRef
end

local function validateInspectionResult(result)
    if not exactPlainTable(result, INSPECTION_RESULT_FIELDS)
        or rawget(result, "ok") ~= true then
        return nil
    end
    return copySummary(rawget(result, "summary"))
end

local function validGains(levelsGained, apGained, summary)
    return safeInteger(levelsGained)
        and safeInteger(apGained)
        and apGained == levelsGained
        and levelsGained <= summary.level
end

local function validateAppliedResult(result, request)
    local fields = request.operation == "awardSurvivorXp"
        and XP_APPLIED_FIELDS or LEVEL_APPLIED_FIELDS
    if not exactPlainTable(result, fields)
        or rawget(result, "ok") ~= true
        or rawget(result, "applied") ~= true
        or rawget(result, "kind") ~= request.operation then
        return nil
    end

    if request.operation == "awardSurvivorXp" then
        if rawget(result, "amount") ~= request.amount then return nil end
    else
        if rawget(result, "count") ~= request.count
            or rawget(result, "levelsGained") ~= request.count
            or rawget(result, "apGained") ~= request.count then
            return nil
        end
    end

    local summary = copySummary(rawget(result, "summary"))
    if summary == nil
        or request.expectedRevision >= MAX_SAFE_INTEGER
        or summary.revision ~= request.expectedRevision + 1
        or not validGains(rawget(result, "levelsGained"), rawget(result, "apGained"), summary) then
        return nil
    end
    return summary
end

local function validateRejectionResult(result, request)
    if not exactPlainTable(result, REJECTION_RESULT_FIELDS)
        or rawget(result, "ok") ~= true
        or rawget(result, "applied") ~= false
        or rawget(result, "kind") ~= request.operation
        or rawget(result, "code") ~= "stale_revision"
        or not safeDetail(rawget(result, "detail")) then
        return nil
    end
    local summary = copySummary(rawget(result, "summary"))
    if summary == nil or summary.revision == request.expectedRevision then return nil end
    return summary
end

local function validateSessionFailure(result)
    return exactPlainTable(result, SESSION_FAILURE_FIELDS)
        and rawget(result, "ok") == false
        and safeCode(rawget(result, "code"))
        and safeDetail(rawget(result, "detail"))
        and rawget(result, "committed") == false
end

local function inspectionEnvelope(request, targetRef, summary)
    local result = responseBase(request, targetRef)
    result.ok = true
    result.outcome = "inspected"
    result.summary = summary
    return result
end

local function appliedEnvelope(request, targetRef, sessionResult, summary)
    local result = responseBase(request, targetRef)
    result.ok = true
    result.outcome = "applied"
    result.levelsGained = rawget(sessionResult, "levelsGained")
    result.apGained = rawget(sessionResult, "apGained")
    result.summary = summary
    return result
end

local function rejectionEnvelope(request, targetRef, sessionResult, summary)
    local result = responseBase(request, targetRef)
    result.ok = true
    result.outcome = "rejected"
    result.code = rawget(sessionResult, "code")
    result.detail = rawget(sessionResult, "detail")
    result.summary = summary
    return result
end

function Build42AdminTransport.createServer(dependencies)
    if not exactPlainTable(dependencies, {
        adminBoundary = true,
        adminSession = true,
        ownerPublisher = true,
        audit = true,
        sendServerCommand = true,
    }) then
        return failure("invalid_dependencies", "dependencies")
    end

    local adminBoundary = rawget(dependencies, "adminBoundary")
    local adminSession = rawget(dependencies, "adminSession")
    local ownerPublisher = rawget(dependencies, "ownerPublisher")
    local audit = rawget(dependencies, "audit")
    local sender = rawget(dependencies, "sendServerCommand")
    if type(adminBoundary) ~= "table" or getmetatable(adminBoundary) ~= nil
        or type(rawget(adminBoundary, "authorizeAndResolve")) ~= "function"
        or type(adminSession) ~= "table" or getmetatable(adminSession) ~= nil
        or type(rawget(adminSession, "inspect")) ~= "function"
        or type(rawget(adminSession, "request")) ~= "function"
        or type(ownerPublisher) ~= "table" or getmetatable(ownerPublisher) ~= nil
        or type(rawget(ownerPublisher, "publish")) ~= "function"
        or type(audit) ~= "table" or getmetatable(audit) ~= nil
        or type(rawget(audit, "record")) ~= "function"
        or type(sender) ~= "function" then
        return failure("invalid_dependencies", "dependencies")
    end

    local authorizeAndResolve = rawget(adminBoundary, "authorizeAndResolve")
    local inspect = rawget(adminSession, "inspect")
    local requestMutation = rawget(adminSession, "request")
    local publish = rawget(ownerPublisher, "publish")
    local record = rawget(audit, "record")
    local server = {}

    function server.handle(module, command, actor, args)
        if module ~= MODULE or command ~= REQUEST_COMMAND then
            return { ok = true, handled = false }
        end

        local request = validateRequestEnvelope(args)
        if request == nil then return failure("invalid_request", "request", false) end

        local selector = { username = request.target.username }
        if request.operation ~= "inspect" then
            selector.onlineId = request.target.onlineId
        end
        local boundaryCalled, boundaryResult = pcall(
            authorizeAndResolve,
            actor,
            request.operation,
            selector
        )
        if not boundaryCalled then return publicBoundaryFailure(request, sender, actor) end

        local target, targetRef = validateBoundaryResult(boundaryResult)
        if target == nil then return publicBoundaryFailure(request, sender, actor) end

        if request.operation == "inspect" then
            local sessionCalled, sessionResult = pcall(inspect, target)
            if not sessionCalled then
                return sendResult(sender, actor, failureEnvelope(
                    request, request.target, "session_failed", "unavailable", false
                ), false)
            end
            local summary = validateInspectionResult(sessionResult)
            if summary == nil then
                return sendResult(sender, actor, failureEnvelope(
                    request, request.target, "session_failed", "malformed", false
                ), false)
            end
            return sendResult(sender, actor, inspectionEnvelope(request, targetRef, summary), false)
        end

        local sessionRequest = {
            kind = request.operation,
            expectedRevision = request.expectedRevision,
        }
        if request.operation == "awardSurvivorXp" then
            sessionRequest.amount = request.amount
        else
            sessionRequest.count = request.count
        end

        local sessionCalled, sessionResult = pcall(requestMutation, target, sessionRequest)
        if not sessionCalled then
            return sendResult(sender, actor, failureEnvelope(
                request, targetRef, "session_failed", "unavailable", false
            ), false)
        end

        local appliedSummary = validateAppliedResult(sessionResult, request)
        if appliedSummary ~= nil then
            local auditCalled, auditResult = pcall(
                record,
                actor,
                {
                    onlineId = targetRef.onlineId,
                    username = targetRef.username,
                },
                request.operation,
                "committed"
            )
            local publicationCalled, publicationResult = pcall(publish, target)
            local auditSucceeded = auditCalled and validDependencySuccess(auditResult)
            local publicationSucceeded = publicationCalled
                and validDependencySuccess(publicationResult)

            if not auditSucceeded or not publicationSucceeded then
                local code = "post_commit_failed"
                local detail = "audit and publication"
                if auditSucceeded then
                    code = "publication_failed"
                    detail = "publication"
                elseif publicationSucceeded then
                    code = "audit_failed"
                    detail = "audit"
                end
                return sendResult(sender, actor, failureEnvelope(
                    request, targetRef, code, detail, true
                ), true)
            end

            return sendResult(
                sender,
                actor,
                appliedEnvelope(request, targetRef, sessionResult, appliedSummary),
                true
            )
        end

        local rejectionSummary = validateRejectionResult(sessionResult, request)
        if rejectionSummary ~= nil then
            return sendResult(
                sender,
                actor,
                rejectionEnvelope(request, targetRef, sessionResult, rejectionSummary),
                false
            )
        end

        if validateSessionFailure(sessionResult) then
            return sendResult(sender, actor, failureEnvelope(
                request,
                targetRef,
                rawget(sessionResult, "code"),
                rawget(sessionResult, "detail"),
                false
            ), false)
        end

        return sendResult(sender, actor, failureEnvelope(
            request, targetRef, "session_failed", "malformed", false
        ), false)
    end

    return { ok = true, server = server }
end

local function validateLogicalRequest(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end

    local operation = rawget(value, "operation")
    local fields
    if operation == "inspect" then
        fields = INSPECT_LOGICAL_REQUEST_FIELDS
    elseif operation == "awardSurvivorXp" then
        fields = XP_LOGICAL_REQUEST_FIELDS
    elseif operation == "awardSurvivorLevels" then
        fields = LEVEL_LOGICAL_REQUEST_FIELDS
    else
        return nil
    end
    if not exactPlainTable(value, fields) then return nil end

    local target
    if operation == "inspect" then
        target = copyUsernameTarget(rawget(value, "target"))
    else
        target = copyTarget(rawget(value, "target"))
    end
    if target == nil then return nil end
    if operation == "awardSurvivorXp" then
        if not safeInteger(rawget(value, "expectedRevision"))
            or not finitePositive(rawget(value, "amount")) then
            return nil
        end
    elseif operation == "awardSurvivorLevels" then
        if not safeInteger(rawget(value, "expectedRevision"))
            or not positiveSafeInteger(rawget(value, "count")) then
            return nil
        end
    end

    return {
        operation = operation,
        target = target,
        expectedRevision = rawget(value, "expectedRevision"),
        amount = rawget(value, "amount"),
        count = rawget(value, "count"),
    }
end

local function copyResponseBase(value, target)
    if rawget(value, "protocolVersion") ~= PROTOCOL_VERSION
        or not safeId(rawget(value, "requestId"), MAX_REQUEST_ID_LENGTH) then
        return nil
    end
    local operation = rawget(value, "operation")
    if operation ~= "inspect" and operation ~= "awardSurvivorXp"
        and operation ~= "awardSurvivorLevels" then
        return nil
    end
    if target == nil then return nil end
    return {
        requestId = rawget(value, "requestId"),
        operation = operation,
        target = target,
    }
end

local function validateResponseEnvelope(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    local operation = rawget(value, "operation")

    if rawget(value, "ok") == true and rawget(value, "outcome") == "inspected"
        and exactPlainTable(value, INSPECTION_RESPONSE_FIELDS)
        and operation == "inspect" then
        local base = copyResponseBase(value, copyTarget(rawget(value, "target")))
        local summary = copySummary(rawget(value, "summary"))
        if base == nil or summary == nil then return nil end
        base.ok = true
        base.outcome = "inspected"
        base.summary = summary
        return base
    end

    if rawget(value, "ok") == true and rawget(value, "outcome") == "applied"
        and exactPlainTable(value, APPLIED_RESPONSE_FIELDS)
        and (operation == "awardSurvivorXp" or operation == "awardSurvivorLevels") then
        local base = copyResponseBase(value, copyTarget(rawget(value, "target")))
        local levelsGained = rawget(value, "levelsGained")
        local apGained = rawget(value, "apGained")
        local summary = copySummary(rawget(value, "summary"))
        if base == nil or summary == nil or not validGains(levelsGained, apGained, summary) then
            return nil
        end
        base.ok = true
        base.outcome = "applied"
        base.levelsGained = levelsGained
        base.apGained = apGained
        base.summary = summary
        return base
    end

    if rawget(value, "ok") == true and rawget(value, "outcome") == "rejected"
        and exactPlainTable(value, REJECTION_RESPONSE_FIELDS)
        and (operation == "awardSurvivorXp" or operation == "awardSurvivorLevels")
        and rawget(value, "code") == "stale_revision"
        and safeDetail(rawget(value, "detail")) then
        local base = copyResponseBase(value, copyTarget(rawget(value, "target")))
        local summary = copySummary(rawget(value, "summary"))
        if base == nil or summary == nil then
            return nil
        end
        base.ok = true
        base.outcome = "rejected"
        base.code = "stale_revision"
        base.detail = rawget(value, "detail")
        base.summary = summary
        return base
    end

    if rawget(value, "ok") == false and exactPlainTable(value, FAILURE_RESPONSE_FIELDS)
        and safeCode(rawget(value, "code"))
        and safeDetail(rawget(value, "detail"))
        and type(rawget(value, "committed")) == "boolean" then
        local committed = rawget(value, "committed")
        if operation == "inspect" and committed ~= false then return nil end
        local target
        if operation == "inspect" then
            target = copyUsernameTarget(rawget(value, "target"))
        elseif operation == "awardSurvivorXp" or operation == "awardSurvivorLevels" then
            target = copyTarget(rawget(value, "target"))
        end
        local base = copyResponseBase(value, target)
        if base == nil then return nil end
        base.ok = false
        base.code = rawget(value, "code")
        base.detail = rawget(value, "detail")
        base.committed = committed
        return base
    end

    return nil
end

local function sameTarget(left, right)
    return left.onlineId == right.onlineId and left.username == right.username
end

local function responseMatchesRoute(terminal, route)
    if terminal.operation ~= route.operation then return false end
    if route.operation == "inspect" then
        if terminal.target.username ~= route.target.username then return false end
        if terminal.ok then
            return terminal.outcome == "inspected" and safeInteger(terminal.target.onlineId)
        end
        return terminal.target.onlineId == nil and terminal.committed == false
    end
    if not sameTarget(terminal.target, route.target) then return false end
    if terminal.outcome == "applied" then
        if route.expectedRevision >= MAX_SAFE_INTEGER
            or terminal.summary.revision ~= route.expectedRevision + 1 then
            return false
        end
        return terminal.operation ~= "awardSurvivorLevels"
            or (terminal.levelsGained == route.count and terminal.apGained == route.count)
    end
    if terminal.outcome == "rejected" then
        return terminal.summary.revision ~= route.expectedRevision
    end
    return true
end

local function copyTerminal(value)
    if value == nil then return nil end
    local target = { username = value.target.username }
    if value.target.onlineId ~= nil then target.onlineId = value.target.onlineId end
    local result = {
        ok = value.ok,
        requestId = value.requestId,
        operation = value.operation,
        target = target,
    }
    if value.ok then
        result.outcome = value.outcome
        if value.outcome == "applied" then
            result.levelsGained = value.levelsGained
            result.apGained = value.apGained
        elseif value.outcome == "rejected" then
            result.code = value.code
            result.detail = value.detail
        end
        result.summary = copySummary(value.summary)
    else
        result.code = value.code
        result.detail = value.detail
        result.committed = value.committed
    end
    return result
end

function Build42AdminTransport.createClient(dependencies)
    if not exactPlainTable(dependencies, { sendClientCommand = true }) then
        return failure("invalid_dependencies", "dependencies")
    end

    local sender = rawget(dependencies, "sendClientCommand")
    if type(sender) ~= "function" then return failure("invalid_dependencies", "dependencies") end

    local pendingBySlot = {}
    local terminalBySlot = {}
    local client = {}

    local function findPending(requestId)
        for localSlot = 0, 3 do
            local route = pendingBySlot[localSlot]
            if route ~= nil and route.requestId == requestId then return localSlot, route end
        end
        return nil, nil
    end

    function client.request(localSlot, actor, request)
        if not validSlot(localSlot) or actor == nil then
            return failure("invalid_request", "request")
        end
        local logical = validateLogicalRequest(request)
        if logical == nil then return failure("invalid_request", "request") end
        if pendingBySlot[localSlot] ~= nil then return failure("pending_request", "slot") end
        if nextRequestNumber >= MAX_SAFE_INTEGER then
            return failure("request_id_exhausted", "counter")
        end

        nextRequestNumber = nextRequestNumber + 1
        local requestId = "admin:" .. tostring(nextRequestNumber)
        local envelope = {
            protocolVersion = PROTOCOL_VERSION,
            requestId = requestId,
            operation = logical.operation,
            target = { username = logical.target.username },
        }
        if logical.operation ~= "inspect" then
            envelope.target.onlineId = logical.target.onlineId
        end
        if logical.operation == "awardSurvivorXp" then
            envelope.expectedRevision = logical.expectedRevision
            envelope.amount = logical.amount
        elseif logical.operation == "awardSurvivorLevels" then
            envelope.expectedRevision = logical.expectedRevision
            envelope.count = logical.count
        end
        pendingBySlot[localSlot] = {
            requestId = requestId,
            operation = logical.operation,
            target = logical.target,
            expectedRevision = logical.expectedRevision,
            count = logical.count,
        }
        terminalBySlot[localSlot] = nil

        if not pcall(sender, actor, MODULE, REQUEST_COMMAND, envelope) then
            pendingBySlot[localSlot] = nil
            local failedTerminal = {
                ok = false,
                requestId = requestId,
                operation = logical.operation,
                target = { username = logical.target.username },
                code = "send_failed",
                detail = "sendClientCommand",
                committed = false,
            }
            if logical.operation ~= "inspect" then
                failedTerminal.target.onlineId = logical.target.onlineId
            end
            terminalBySlot[localSlot] = failedTerminal
            return failure("send_failed", "sendClientCommand", false)
        end
        return { ok = true, requestId = requestId }
    end

    function client.handle(module, command, args)
        if module ~= MODULE or command ~= RESPONSE_COMMAND then
            return { ok = true, handled = false }
        end

        local terminal = validateResponseEnvelope(args)
        if terminal == nil then return failure("invalid_response", "response") end
        local localSlot, route = findPending(terminal.requestId)
        if route == nil or terminal.operation ~= route.operation then
            return failure("unknown_response", "route")
        end
        if not responseMatchesRoute(terminal, route) then
            return failure("invalid_response", "response")
        end

        pendingBySlot[localSlot] = nil
        terminalBySlot[localSlot] = terminal
        return {
            ok = true,
            handled = true,
            localSlot = localSlot,
            result = copyTerminal(terminal),
        }
    end

    function client.status(localSlot)
        if not validSlot(localSlot) then return failure("invalid_slot", "slot") end
        local route = pendingBySlot[localSlot]
        if route ~= nil then
            local result = {
                ok = true,
                pending = true,
                requestId = route.requestId,
                operation = route.operation,
                target = {
                    username = route.target.username,
                },
            }
            if route.operation ~= "inspect" then
                result.target.onlineId = route.target.onlineId
            end
            return result
        end
        local terminal = copyTerminal(terminalBySlot[localSlot])
        if terminal == nil then return { ok = true, pending = false } end
        return { ok = true, pending = false, result = terminal }
    end

    function client.resetSlot(localSlot)
        if not validSlot(localSlot) then return failure("invalid_slot", "slot") end
        pendingBySlot[localSlot] = nil
        terminalBySlot[localSlot] = nil
        return { ok = true }
    end

    function client.reset()
        for localSlot = 0, 3 do
            pendingBySlot[localSlot] = nil
            terminalBySlot[localSlot] = nil
        end
        return { ok = true }
    end

    return { ok = true, client = client }
end

return Build42AdminTransport
