local Build42AdminTransport = Build42AdminTransport

local assertions = 0

local function check(condition, message)
    assertions = assertions + 1
    if not condition then error(message, 2) end
end

local function equal(actual, expected, message)
    check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function exact(value, expected, message)
    check(type(value) == "table" and getmetatable(value) == nil, message .. ": plain table")
    for key, item in pairs(expected) do
        check(rawget(value, key) == item, message .. ": field " .. key)
    end
    for key in pairs(value) do
        check(rawget(expected, key) ~= nil, message .. ": unexpected field " .. tostring(key))
    end
end

local function eventNames(events)
    local result = ""
    for index = 1, #events do
        local event = events[index]
        if index > 1 then result = result .. "," end
        result = result .. event.name
    end
    return result
end

local function repeated(character, count)
    local result = ""
    for _ = 1, count do result = result .. character end
    return result
end

local function summary(overrides)
    local result = {
        accountingMode = "Tracked",
        revision = 7,
        level = 5,
        xpIntoLevel = 25,
        xpForNextLevel = 100,
        spent = 2,
        availableAp = 3,
    }
    if overrides ~= nil then
        for key, value in pairs(overrides) do result[key] = value end
    end
    return result
end

local function target(onlineId, username)
    return { onlineId = onlineId or 41, username = username or "ClientTarget" }
end

local function usernameTarget(username)
    return { username = username or "ClientTarget" }
end

local function inspectRequest()
    return {
        protocolVersion = 1,
        requestId = "admin:inspect-1",
        operation = "inspect",
        target = usernameTarget(),
    }
end

local function xpRequest()
    return {
        protocolVersion = 1,
        requestId = "admin:xp-1",
        operation = "awardSurvivorXp",
        target = target(),
        expectedRevision = 7,
        amount = 125.5,
    }
end

local function levelRequest()
    return {
        protocolVersion = 1,
        requestId = "admin:levels-1",
        operation = "awardSurvivorLevels",
        target = target(),
        expectedRevision = 7,
        count = 2,
    }
end

local function clearRequest()
    return {
        protocolVersion = 1,
        requestId = "admin:clear-1",
        operation = "clearAdvancementSlots",
        target = target(),
        expectedRevision = 7,
    }
end

local function makeHarness(options)
    options = options or {}
    local events = {}
    local actor = { secret = "actor-secret" }
    local resolvedTarget = { secret = "target-secret" }
    local authoritativeTargetRef = options.authoritativeTargetRef
        or { onlineId = 77, username = "ServerTarget" }
    local inspectionSummary = options.inspectionSummary or summary()

    local boundary = {}
    function boundary.authorizeAndResolve(receivedActor, operation, selector)
        events[#events + 1] = {
            name = "boundary",
            actor = receivedActor,
            operation = operation,
            selector = selector,
        }
        if options.boundaryMutate then
            selector.username = "MutatedBoundaryTarget"
            selector.extra = { secret = true }
        end
        if options.boundaryThrow then error("boundary object secret") end
        if options.boundaryMatchUsername ~= nil
            and selector.username ~= options.boundaryMatchUsername then
            return { ok = false, code = "target_mismatch", detail = "target" }
        end
        if options.boundaryResult ~= nil then return options.boundaryResult end
        return {
            ok = true,
            target = resolvedTarget,
            targetRef = authoritativeTargetRef,
        }
    end

    local session = {}
    function session.inspect(receivedTarget)
        events[#events + 1] = { name = "inspect", target = receivedTarget }
        if options.inspectThrow then error("session object secret") end
        if options.inspectResult ~= nil then return options.inspectResult end
        return { ok = true, summary = inspectionSummary }
    end
    function session.request(receivedTarget, request)
        events[#events + 1] = { name = "request", target = receivedTarget, request = request }
        if options.requestThrow then error("session object secret") end
        if options.requestResult ~= nil then return options.requestResult end
        if request.kind == "awardSurvivorXp" then
            return {
                ok = true,
                applied = true,
                kind = "awardSurvivorXp",
                amount = request.amount,
                levelsGained = 1,
                apGained = 1,
                summary = summary({ revision = 8, level = 6, availableAp = 4 }),
            }
        end
        if request.kind == "clearAdvancementSlots" then
            return {
                ok = true,
                applied = true,
                kind = "clearAdvancementSlots",
                levelsGained = 0,
                apGained = 0,
                summary = summary({ revision = 8 }),
            }
        end
        return {
            ok = true,
            applied = true,
            kind = "awardSurvivorLevels",
            count = request.count,
            levelsGained = request.count,
            apGained = request.count,
            summary = summary({ revision = 8, level = 7, availableAp = 5 }),
        }
    end

    local audit = {}
    function audit.record(receivedActor, targetRef, operation, outcome)
        events[#events + 1] = {
            name = "audit",
            actor = receivedActor,
            targetRef = targetRef,
            operation = operation,
            outcome = outcome,
        }
        if options.auditMutate then
            targetRef.username = "MutatedAuditTarget"
            targetRef.extra = { secret = true }
        end
        if options.auditThrow then error("audit object secret") end
        if options.auditResult ~= nil then return options.auditResult end
        return { ok = true }
    end

    local publisher = {}
    function publisher.publish(receivedTarget)
        events[#events + 1] = { name = "publish", target = receivedTarget }
        if options.publishThrow then error("publisher object secret") end
        if options.publishResult ~= nil then return options.publishResult end
        return { ok = true }
    end

    local function sender(receivedActor, module, command, envelope)
        events[#events + 1] = {
            name = "send",
            actor = receivedActor,
            module = module,
            command = command,
            envelope = envelope,
        }
        if options.sendThrow then error("sender object secret") end
    end

    local created = Build42AdminTransport.createServer({
        adminBoundary = boundary,
        adminSession = session,
        ownerPublisher = publisher,
        audit = audit,
        sendServerCommand = sender,
    })
    check(created.ok == true, "server construction succeeds")
    exact(created, { ok = true, server = created.server }, "construction result")
    exact(created.server, { handle = created.server.handle }, "server surface")
    return {
        server = created.server,
        events = events,
        actor = actor,
        resolvedTarget = resolvedTarget,
        authoritativeTargetRef = authoritativeTargetRef,
        inspectionSummary = inspectionSummary,
        boundary = boundary,
        session = session,
        audit = audit,
        publisher = publisher,
    }
end

do
    local nilResult = Build42AdminTransport.createServer(nil)
    exact(nilResult, { ok = false, code = "invalid_dependencies", detail = "dependencies" },
        "nil construction")
    local invalidDependencies = {
        {},
        { adminBoundary = {}, adminSession = {}, ownerPublisher = {}, audit = {}, sendServerCommand = function() end },
        {
            adminBoundary = { authorizeAndResolve = function() end },
            adminSession = { inspect = function() end, request = function() end },
            ownerPublisher = { publish = function() end },
            audit = { record = function() end },
            sendServerCommand = "not callable",
        },
    }
    for index = 1, #invalidDependencies do
        local dependencies = invalidDependencies[index]
        local result = Build42AdminTransport.createServer(dependencies)
        exact(result, { ok = false, code = "invalid_dependencies", detail = "dependencies" },
            "invalid construction " .. index)
    end

    local withExtra = {
        adminBoundary = { authorizeAndResolve = function() end },
        adminSession = { inspect = function() end, request = function() end },
        ownerPublisher = { publish = function() end },
        audit = { record = function() end },
        sendServerCommand = function() end,
        future = true,
    }
    local result = Build42AdminTransport.createServer(withExtra)
    exact(result, { ok = false, code = "invalid_dependencies", detail = "dependencies" },
        "extra dependency rejected")
end

do
    local harness = makeHarness()
    local first = harness.server.handle("Elsewhere", "adminRequest", harness.actor, inspectRequest())
    exact(first, { ok = true, handled = false }, "other module untouched")
    local second = harness.server.handle("SurvivorLevelingAdvancement", "other", harness.actor, inspectRequest())
    exact(second, { ok = true, handled = false }, "other command untouched")
    equal(#harness.events, 0, "unrelated traffic calls no dependency")
end

do
    local malformed = {}
    malformed[#malformed + 1] = nil
    malformed[#malformed + 1] = "request"
    local extra = inspectRequest()
    extra.extra = true
    malformed[#malformed + 1] = extra
    local wrongVersion = inspectRequest()
    wrongVersion.protocolVersion = 2
    malformed[#malformed + 1] = wrongVersion
    local unsafeId = inspectRequest()
    unsafeId.requestId = "bad id"
    malformed[#malformed + 1] = unsafeId
    local longId = inspectRequest()
    longId.requestId = repeated("a", 65)
    malformed[#malformed + 1] = longId
    local unknown = inspectRequest()
    unknown.operation = "setAccountingMode"
    malformed[#malformed + 1] = unknown
    for _, operation in ipairs({ "advancePerkNormally", "resetAccounting", "setAccounting" }) do
        local inactive = clearRequest()
        inactive.operation = operation
        malformed[#malformed + 1] = inactive
    end
    local inspectOperand = inspectRequest()
    inspectOperand.amount = 1
    malformed[#malformed + 1] = inspectOperand
    local targetExtra = inspectRequest()
    targetExtra.target.secret = true
    malformed[#malformed + 1] = targetExtra
    local targetMeta = inspectRequest()
    setmetatable(targetMeta.target, {})
    malformed[#malformed + 1] = targetMeta
    local pairShapedInspect = inspectRequest()
    pairShapedInspect.target.onlineId = 41
    malformed[#malformed + 1] = pairShapedInspect
    local badUsername = inspectRequest()
    badUsername.target.username = "bad\nname"
    malformed[#malformed + 1] = badUsername
    local delUsername = inspectRequest()
    delUsername.target.username = "bad" .. string.char(127) .. "name"
    malformed[#malformed + 1] = delUsername
    local longUsername = inspectRequest()
    longUsername.target.username = repeated("u", 65)
    malformed[#malformed + 1] = longUsername
    local xpNoAmount = xpRequest()
    xpNoAmount.amount = nil
    malformed[#malformed + 1] = xpNoAmount
    local xpNegativeRevision = xpRequest()
    xpNegativeRevision.expectedRevision = -1
    malformed[#malformed + 1] = xpNegativeRevision
    local xpInfinite = xpRequest()
    xpInfinite.amount = 1 / 0
    malformed[#malformed + 1] = xpInfinite
    local xpNan = xpRequest()
    xpNan.amount = 0 / 0
    malformed[#malformed + 1] = xpNan
    local levelZero = levelRequest()
    levelZero.count = 0
    malformed[#malformed + 1] = levelZero
    local levelFraction = levelRequest()
    levelFraction.count = 1.5
    malformed[#malformed + 1] = levelFraction
    local clearMissingRevision = clearRequest()
    clearMissingRevision.expectedRevision = nil
    malformed[#malformed + 1] = clearMissingRevision
    local clearFractionRevision = clearRequest()
    clearFractionRevision.expectedRevision = 1.5
    malformed[#malformed + 1] = clearFractionRevision
    local clearExtra = clearRequest()
    clearExtra.count = 1
    malformed[#malformed + 1] = clearExtra
    local requestMeta = inspectRequest()
    setmetatable(requestMeta, {})
    malformed[#malformed + 1] = requestMeta

    for index = 1, #malformed do
        local request = malformed[index]
        local harness = makeHarness()
        local result = harness.server.handle(
            "SurvivorLevelingAdvancement", "adminRequest", harness.actor, request
        )
        exact(result, {
            ok = false,
            code = "invalid_request",
            detail = "request",
            committed = false,
        }, "malformed request " .. index)
        equal(#harness.events, 0, "malformed request has no dependency call " .. index)
    end
end

do
    local nonAsciiUsername = "Jos" .. string.char(195) .. string.char(169)
    local authoritativeTargetRef = { onlineId = 77, username = nonAsciiUsername }
    local harness = makeHarness({
        authoritativeTargetRef = authoritativeTargetRef,
        boundaryMatchUsername = nonAsciiUsername,
    })
    local request = inspectRequest()
    request.target.username = nonAsciiUsername
    local requestTarget = request.target
    local result = harness.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", harness.actor, request
    )
    exact(result, { ok = true, handled = true }, "non-ASCII username handled")
    equal(eventNames(harness.events), "boundary,inspect,send", "non-ASCII username flow")
    equal(harness.events[1].selector.username, nonAsciiUsername,
        "non-ASCII username reaches boundary unchanged")
    check(harness.events[1].selector ~= requestTarget,
        "non-ASCII request selector detached")
    equal(harness.events[3].envelope.target.username, nonAsciiUsername,
        "non-ASCII authoritative username reaches response unchanged")
    check(harness.events[3].envelope.target ~= authoritativeTargetRef,
        "non-ASCII response target detached")
end

do
    local harness = makeHarness()
    local request = inspectRequest()
    local clientTarget = request.target
    local result = harness.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", harness.actor, request
    )
    exact(result, { ok = true, handled = true }, "inspection handled")
    equal(eventNames(harness.events), "boundary,inspect,send", "inspection order")
    local boundaryEvent = harness.events[1]
    check(boundaryEvent.actor == harness.actor, "boundary receives authoritative actor")
    equal(boundaryEvent.operation, "inspect", "boundary receives operation")
    check(boundaryEvent.selector ~= clientTarget, "boundary selector detached from request")
    exact(boundaryEvent.selector, { username = "ClientTarget" }, "boundary selector")
    check(harness.events[2].target == harness.resolvedTarget, "inspection uses resolved target")

    local sent = harness.events[3]
    check(sent.actor == harness.actor, "response targets actor")
    equal(sent.module, "SurvivorLevelingAdvancement", "response module")
    equal(sent.command, "adminResult", "response command")
    exact(sent.envelope, {
        protocolVersion = 1,
        requestId = "admin:inspect-1",
        operation = "inspect",
        target = sent.envelope.target,
        ok = true,
        outcome = "inspected",
        summary = sent.envelope.summary,
    }, "inspection response")
    exact(sent.envelope.target, { onlineId = 77, username = "ServerTarget" }, "authoritative response target")
    check(sent.envelope.target ~= harness.authoritativeTargetRef, "response target detached")
    exact(sent.envelope.summary, summary(), "inspection summary")
    check(sent.envelope.summary ~= harness.inspectionSummary, "inspection summary detached")
end

do
    local harness = makeHarness({
        boundaryResult = { ok = false, code = "permission_denied", detail = "Administrator" },
        boundaryMutate = true,
    })
    local result = harness.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", harness.actor, xpRequest()
    )
    exact(result, { ok = true, handled = true }, "denial response sent")
    equal(eventNames(harness.events), "boundary,send", "denial stops before session")
    local response = harness.events[2].envelope
    exact(response, {
        protocolVersion = 1,
        requestId = "admin:xp-1",
        operation = "awardSurvivorXp",
        target = response.target,
        ok = false,
        code = "request_denied",
        detail = "unavailable",
        committed = false,
    }, "public-safe denial")
    exact(response.target, { onlineId = 41, username = "ClientTarget" }, "denial target copy")
    check(response.detail ~= "Administrator", "role detail not exposed")
end

do
    local harness = makeHarness({ auditMutate = true })
    harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, xpRequest())
    exact(harness.events[5].envelope.target,
        { onlineId = 77, username = "ServerTarget" },
        "audit mutation cannot alter response target")
    check(rawget(harness.events[5].envelope.target, "extra") == nil,
        "audit mutation cannot add response target fields")
end

do
    local hostileBoundaryResults = {
        { ok = true, target = { secret = true }, targetRef = { onlineId = 77, username = "ServerTarget", extra = true } },
        { ok = true, target = { secret = true }, targetRef = setmetatable({ onlineId = 77, username = "ServerTarget" }, {}) },
        { ok = true, target = { secret = true }, targetRef = { onlineId = 77, username = "bad\nname" } },
        { ok = false, code = {}, detail = {} },
    }
    for index = 1, #hostileBoundaryResults do
        local boundaryResult = hostileBoundaryResults[index]
        local harness = makeHarness({ boundaryResult = boundaryResult })
        harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, inspectRequest())
        equal(eventNames(harness.events), "boundary,send", "hostile boundary stops " .. index)
        equal(harness.events[2].envelope.code, "request_denied", "hostile boundary bounded " .. index)
        equal(harness.events[2].envelope.detail, "unavailable", "hostile boundary detail bounded " .. index)
        exact(harness.events[2].envelope.target, { username = "ClientTarget" },
            "inspect boundary failure target " .. index)
    end

    local thrown = makeHarness({ boundaryThrow = true })
    thrown.server.handle("SurvivorLevelingAdvancement", "adminRequest", thrown.actor, inspectRequest())
    equal(eventNames(thrown.events), "boundary,send", "thrown boundary stops")
    equal(thrown.events[2].envelope.detail, "unavailable", "thrown text hidden")
end

do
    local harness = makeHarness()
    local result = harness.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", harness.actor, xpRequest()
    )
    exact(result, { ok = true, handled = true }, "XP handled")
    equal(eventNames(harness.events), "boundary,request,audit,publish,send", "XP applied order")
    local requestEvent = harness.events[2]
    check(requestEvent.target == harness.resolvedTarget, "XP uses resolved target")
    exact(requestEvent.request, {
        kind = "awardSurvivorXp",
        expectedRevision = 7,
        amount = 125.5,
    }, "exact XP session request")
    local auditEvent = harness.events[3]
    check(auditEvent.actor == harness.actor, "audit receives actor")
    exact(auditEvent.targetRef, { onlineId = 77, username = "ServerTarget" }, "audit targetRef")
    check(auditEvent.targetRef ~= harness.authoritativeTargetRef, "audit targetRef detached")
    equal(auditEvent.operation, "awardSurvivorXp", "audit operation")
    equal(auditEvent.outcome, "committed", "audit outcome")
    check(harness.events[4].target == harness.resolvedTarget, "publisher receives target only")
    local response = harness.events[5].envelope
    exact(response, {
        protocolVersion = 1,
        requestId = "admin:xp-1",
        operation = "awardSurvivorXp",
        target = response.target,
        ok = true,
        outcome = "applied",
        levelsGained = 1,
        apGained = 1,
        summary = response.summary,
    }, "XP applied response")
    exact(response.target, { onlineId = 77, username = "ServerTarget" }, "XP authoritative target")
    exact(response.summary, summary({ revision = 8, level = 6, availableAp = 4 }), "XP response summary")
end

do
    local harness = makeHarness()
    harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, levelRequest())
    equal(eventNames(harness.events), "boundary,request,audit,publish,send", "levels applied order")
    exact(harness.events[2].request, {
        kind = "awardSurvivorLevels",
        expectedRevision = 7,
        count = 2,
    }, "exact levels session request")
    local response = harness.events[5].envelope
    exact(response, {
        protocolVersion = 1,
        requestId = "admin:levels-1",
        operation = "awardSurvivorLevels",
        target = response.target,
        ok = true,
        outcome = "applied",
        levelsGained = 2,
        apGained = 2,
        summary = response.summary,
    }, "levels applied response")
end

do
    local harness = makeHarness()
    harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, clearRequest())
    equal(eventNames(harness.events), "boundary,request,audit,publish,send", "clear applied order")
    exact(harness.events[1].selector, { onlineId = 41, username = "ClientTarget" },
        "clear uses canonical selector")
    exact(harness.events[2].request, {
        kind = "clearAdvancementSlots",
        expectedRevision = 7,
    }, "exact clear session request")
    equal(harness.events[3].operation, "clearAdvancementSlots", "clear audit operation")
    local response = harness.events[5].envelope
    exact(response, {
        protocolVersion = 1,
        requestId = "admin:clear-1",
        operation = "clearAdvancementSlots",
        target = response.target,
        ok = true,
        outcome = "applied",
        levelsGained = 0,
        apGained = 0,
        summary = response.summary,
    }, "clear zero-gain response")
end

do
    local revision, applications = 7, 0
    local harness = makeHarness()
    function harness.session.request(receivedTarget, request)
        harness.events[#harness.events + 1] = { name = "request", target = receivedTarget, request = request }
        if request.expectedRevision ~= revision then
            return {
                ok = true, applied = false, kind = request.kind,
                code = "stale_revision", detail = "expected revision is stale",
                summary = summary({ revision = revision }),
            }
        end
        applications, revision = applications + 1, revision + 1
        return {
            ok = true, applied = true, kind = request.kind,
            levelsGained = 0, apGained = 0, summary = summary({ revision = revision }),
        }
    end
    local recreated = Build42AdminTransport.createServer({
        adminBoundary = harness.boundary,
        adminSession = harness.session,
        ownerPublisher = harness.publisher,
        audit = harness.audit,
        sendServerCommand = function(actor, module, command, envelope)
            harness.events[#harness.events + 1] = { name = "send", envelope = envelope }
        end,
    })
    local request = clearRequest()
    recreated.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, request)
    recreated.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, request)
    equal(applications, 1, "clear replay applies once")
    equal(eventNames(harness.events),
        "boundary,request,audit,publish,send,boundary,request,send",
        "clear replay becomes stale")
    equal(harness.events[8].envelope.outcome, "rejected", "clear replay stale response")
end

do
    local harness = makeHarness({ auditThrow = true })
    harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, clearRequest())
    equal(eventNames(harness.events), "boundary,request,audit,publish,send",
        "clear audit failure still publishes")
    equal(harness.events[5].envelope.code, "audit_failed", "clear follow-up failure bounded")
    equal(harness.events[5].envelope.committed, true, "clear follow-up failure committed")
end

do
    local staleSummary = summary({ revision = 8 })
    local harness = makeHarness({
        requestResult = {
            ok = true,
            applied = false,
            kind = "awardSurvivorXp",
            code = "stale_revision",
            detail = "expected revision is stale",
            summary = staleSummary,
        },
    })
    harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, xpRequest())
    equal(eventNames(harness.events), "boundary,request,send", "stale does not audit or publish")
    local response = harness.events[3].envelope
    exact(response, {
        protocolVersion = 1,
        requestId = "admin:xp-1",
        operation = "awardSurvivorXp",
        target = response.target,
        ok = true,
        outcome = "rejected",
        code = "stale_revision",
        detail = "expected revision is stale",
        summary = response.summary,
    }, "stale response")
    check(response.summary ~= staleSummary, "stale summary detached")
end

do
    local revision = 7
    local applications = 0
    local requestResult = {}
    local harness = makeHarness({ requestResult = requestResult })
    function harness.session.request(receivedTarget, request)
        harness.events[#harness.events + 1] = { name = "request", target = receivedTarget, request = request }
        if request.expectedRevision ~= revision then
            return {
                ok = true,
                applied = false,
                kind = request.kind,
                code = "stale_revision",
                detail = "expected revision is stale",
                summary = summary({ revision = revision }),
            }
        end
        applications = applications + 1
        revision = revision + 1
        return {
            ok = true,
            applied = true,
            kind = request.kind,
            amount = request.amount,
            levelsGained = 1,
            apGained = 1,
            summary = summary({ revision = revision, level = 6, availableAp = 4 }),
        }
    end

    local recreated = Build42AdminTransport.createServer({
        adminBoundary = harness.boundary,
        adminSession = harness.session,
        ownerPublisher = harness.publisher,
        audit = harness.audit,
        sendServerCommand = function(actor, module, command, envelope)
            harness.events[#harness.events + 1] = { name = "send", envelope = envelope }
        end,
    })
    local request = xpRequest()
    recreated.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, request)
    recreated.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, request)
    equal(applications, 1, "replay applies once")
    equal(revision, 8, "replay increments revision once")
    equal(eventNames(harness.events),
        "boundary,request,audit,publish,send,boundary,request,send",
        "replay stale ordering")
    equal(harness.events[8].envelope.outcome, "rejected", "replay receives rejection")
end

do
    local harness = makeHarness({
        requestResult = { ok = false, code = "not_ready", detail = "target", committed = false },
    })
    harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, xpRequest())
    equal(eventNames(harness.events), "boundary,request,send", "session failure no follow-up")
    local response = harness.events[3].envelope
    equal(response.code, "not_ready", "bounded session code returned")
    equal(response.detail, "target", "bounded session detail returned")
    equal(response.committed, false, "session failure uncommitted")
end

do
    local malformedResults = {
        { ok = true, applied = true },
        {
            ok = true, applied = true, kind = "awardSurvivorXp", amount = 125.5,
            levelsGained = 1, apGained = 2, summary = summary(),
        },
        {
            ok = true, applied = true, kind = "awardSurvivorXp", amount = 125.5,
            levelsGained = 1, apGained = 1, summary = summary({ availableAp = 999 }),
        },
        {
            ok = true, applied = true, kind = "awardSurvivorXp", amount = 125.5,
            levelsGained = 1, apGained = 1,
            summary = summary({ revision = 7, level = 6, availableAp = 4 }),
        },
        {
            ok = true, applied = false, kind = "awardSurvivorXp", code = "other",
            detail = "not stale", summary = summary(),
        },
        {
            ok = true, applied = false, kind = "awardSurvivorXp", code = "stale_revision",
            detail = "not actually stale", summary = summary({ revision = 7 }),
        },
        { ok = false, code = {}, detail = {}, committed = false },
    }
    for index = 1, #malformedResults do
        local sessionResult = malformedResults[index]
        local harness = makeHarness({ requestResult = sessionResult })
        harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, xpRequest())
        equal(eventNames(harness.events), "boundary,request,send", "malformed session no follow-up " .. index)
        equal(harness.events[3].envelope.code, "session_failed", "malformed session bounded " .. index)
        equal(harness.events[3].envelope.detail, "malformed", "malformed session hides objects " .. index)
        equal(harness.events[3].envelope.committed, false, "malformed session uncommitted " .. index)
    end

    local thrown = makeHarness({ requestThrow = true })
    thrown.server.handle("SurvivorLevelingAdvancement", "adminRequest", thrown.actor, xpRequest())
    equal(eventNames(thrown.events), "boundary,request,send", "thrown session no follow-up")
    equal(thrown.events[3].envelope.detail, "unavailable", "thrown session hidden")
end

do
    local badSummaries = {
        summary({ accountingMode = "Global" }),
        summary({ revision = -1 }),
        summary({ level = 1.5 }),
        summary({ xpIntoLevel = -1 }),
        summary({ xpIntoLevel = 100 }),
        summary({ xpForNextLevel = 0 }),
        summary({ spent = 6 }),
        summary({ availableAp = 4 }),
    }
    for index = 1, #badSummaries do
        local badSummary = badSummaries[index]
        local harness = makeHarness({ inspectResult = { ok = true, summary = badSummary } })
        harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, inspectRequest())
        equal(eventNames(harness.events), "boundary,inspect,send", "invalid summary inspection only " .. index)
        equal(harness.events[3].envelope.code, "session_failed", "invalid summary rejected " .. index)
        exact(harness.events[3].envelope.target, { username = "ClientTarget" },
            "invalid inspect result echoes username selector " .. index)
    end

    local thrown = makeHarness({ inspectThrow = true })
    thrown.server.handle("SurvivorLevelingAdvancement", "adminRequest", thrown.actor, inspectRequest())
    equal(eventNames(thrown.events), "boundary,inspect,send", "thrown inspect calls session once")
    exact(thrown.events[3].envelope.target, { username = "ClientTarget" },
        "thrown inspect echoes username selector")
end

do
    local auditFailure = makeHarness({ auditThrow = true })
    auditFailure.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", auditFailure.actor, xpRequest()
    )
    equal(eventNames(auditFailure.events), "boundary,request,audit,publish,send",
        "audit failure still publishes")
    equal(auditFailure.events[5].envelope.code, "audit_failed", "audit failure code")
    equal(auditFailure.events[5].envelope.committed, true, "audit failure committed")

    local publicationFailure = makeHarness({ publishThrow = true })
    publicationFailure.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", publicationFailure.actor, xpRequest()
    )
    equal(eventNames(publicationFailure.events), "boundary,request,audit,publish,send",
        "publication failure follows audit")
    equal(publicationFailure.events[5].envelope.code, "publication_failed", "publication failure code")
    equal(publicationFailure.events[5].envelope.committed, true, "publication failure committed")

    local bothFailure = makeHarness({ auditResult = {}, publishResult = { ok = false } })
    bothFailure.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", bothFailure.actor, xpRequest()
    )
    equal(eventNames(bothFailure.events), "boundary,request,audit,publish,send",
        "both malformed follow-ups attempted once")
    equal(bothFailure.events[5].envelope.code, "post_commit_failed", "combined failure code")
    equal(bothFailure.events[5].envelope.committed, true, "combined failure committed")
    equal(#bothFailure.events, 5, "combined failure sends once")
end

do
    local committedSendFailure = makeHarness({ sendThrow = true })
    local committed = committedSendFailure.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", committedSendFailure.actor, xpRequest()
    )
    exact(committed, {
        ok = false,
        code = "send_failed",
        detail = "sendServerCommand",
        committed = true,
    }, "committed send failure")
    equal(eventNames(committedSendFailure.events), "boundary,request,audit,publish,send",
        "committed send not retried")

    local inspectionSendFailure = makeHarness({ sendThrow = true })
    local uncommitted = inspectionSendFailure.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", inspectionSendFailure.actor, inspectRequest()
    )
    exact(uncommitted, {
        ok = false,
        code = "send_failed",
        detail = "sendServerCommand",
        committed = false,
    }, "inspection send failure")
    equal(eventNames(inspectionSendFailure.events), "boundary,inspect,send",
        "inspection send not retried")

    local deniedSendFailure = makeHarness({ boundaryThrow = true, sendThrow = true })
    local denied = deniedSendFailure.server.handle(
        "SurvivorLevelingAdvancement", "adminRequest", deniedSendFailure.actor, inspectRequest()
    )
    equal(denied.committed, false, "denial send failure uncommitted")
    equal(eventNames(deniedSendFailure.events), "boundary,send", "denial send not retried")
end

do
    local originalCalls = 0
    local replacementCalls = 0
    local harness = makeHarness()
    local originalBoundary = harness.boundary.authorizeAndResolve
    harness.boundary.authorizeAndResolve = function()
        replacementCalls = replacementCalls + 1
        return { ok = false, code = "replacement", detail = "replacement" }
    end
    harness.session.inspect = function()
        replacementCalls = replacementCalls + 1
        return { ok = false, code = "replacement", detail = "replacement", committed = false }
    end
    originalCalls = originalCalls + 1
    harness.server.handle("SurvivorLevelingAdvancement", "adminRequest", harness.actor, inspectRequest())
    equal(replacementCalls, 0, "construction captures dependency callables")
    equal(originalCalls, 1, "capture test executed")
    check(originalBoundary ~= harness.boundary.authorizeAndResolve, "boundary method actually replaced")
    equal(eventNames(harness.events), "boundary,inspect,send", "captured callables remain active")
end

local function adminLogicalInspect(username)
    return { operation = "inspect", target = usernameTarget(username) }
end

local function adminLogicalXp(onlineId, username, revision, amount)
    return {
        operation = "awardSurvivorXp",
        target = target(onlineId, username),
        expectedRevision = revision or 7,
        amount = amount or 125.5,
    }
end

local function adminLogicalLevels(onlineId, username, revision, count)
    return {
        operation = "awardSurvivorLevels",
        target = target(onlineId, username),
        expectedRevision = revision or 7,
        count = count or 2,
    }
end

local function adminLogicalClear(onlineId, username, revision)
    return {
        operation = "clearAdvancementSlots",
        target = target(onlineId, username),
        expectedRevision = revision or 7,
    }
end

local function makeClientHarness(options)
    options = options or {}
    local events = {}
    local actor0 = { localPlayer = 0 }
    local actor1 = { localPlayer = 1 }
    local sender = function(actor, module, command, envelope)
        events[#events + 1] = {
            actor = actor,
            module = module,
            command = command,
            envelope = envelope,
        }
        if options.sendThrow then error("send failure") end
    end
    local created = Build42AdminTransport.createClient({ sendClientCommand = sender })
    check(created.ok == true, "client harness construction")
    return {
        client = created.client,
        events = events,
        actor0 = actor0,
        actor1 = actor1,
    }
end

local function pendingRoute(client, localSlot)
    local status = client.status(localSlot)
    check(status.pending == true, "pending route exists")
    return status
end

local function adminResponse(route, outcome, overrides)
    local responseTarget
    if route.operation == "inspect" then
        responseTarget = { username = route.target.username }
        if outcome == "inspected" then responseTarget.onlineId = 77 end
    else
        responseTarget = { onlineId = route.target.onlineId, username = route.target.username }
    end
    local response = {
        protocolVersion = 1,
        requestId = route.requestId,
        operation = route.operation,
        target = responseTarget,
    }
    if outcome == "inspected" then
        response.ok = true
        response.outcome = "inspected"
        response.summary = summary()
    elseif outcome == "applied" then
        response.ok = true
        response.outcome = "applied"
        response.levelsGained = route.operation == "clearAdvancementSlots" and 0
            or (route.operation == "awardSurvivorLevels" and 2 or 1)
        response.apGained = response.levelsGained
        response.summary = summary({ revision = 8, level = 6, availableAp = 4 })
    elseif outcome == "rejected" then
        response.ok = true
        response.outcome = "rejected"
        response.code = "stale_revision"
        response.detail = "expected revision is stale"
        response.summary = summary({ revision = 8 })
    else
        response.ok = false
        response.code = "request_denied"
        response.detail = "unavailable"
        response.committed = false
    end
    if overrides ~= nil then
        for key, value in pairs(overrides) do response[key] = value end
    end
    return response
end

do
    exact(Build42AdminTransport.createClient({}), {
        ok = false,
        code = "invalid_dependencies",
        detail = "dependencies",
    }, "client requires exact dependency")
    exact(Build42AdminTransport.createClient({ sendClientCommand = {} }), {
        ok = false,
        code = "invalid_dependencies",
        detail = "dependencies",
    }, "client requires callable sender")

    local calls = 0
    local captured = function() calls = calls + 1 end
    local dependencies = { sendClientCommand = captured }
    local created = Build42AdminTransport.createClient(dependencies)
    dependencies.sendClientCommand = function() error("replacement sender") end
    exact(created.client, {
        request = created.client.request,
        handle = created.client.handle,
        status = created.client.status,
        resetSlot = created.client.resetSlot,
        reset = created.client.reset,
    }, "exact client surface")
    created.client.request(0, {}, adminLogicalInspect())
    equal(calls, 1, "client construction captures sender")
end

do
    local harness = makeClientHarness()
    local nonAscii = "Jos" .. string.char(195) .. string.char(169)
    local inspect = harness.client.request(0, harness.actor0, adminLogicalInspect(nonAscii))
    local xp = harness.client.request(1, harness.actor1, adminLogicalXp(42, "XpTarget"))
    local levels = harness.client.request(2, harness.actor0, adminLogicalLevels(43, "LevelTarget"))
    local clear = harness.client.request(3, harness.actor1, adminLogicalClear(44, "ClearTarget"))
    check(inspect.ok and xp.ok and levels.ok and clear.ok, "all logical requests send")
    equal(#harness.events, 4, "four exact sends")
    check(harness.events[1].actor == harness.actor0, "inspect uses supplied actor")
    check(harness.events[2].actor == harness.actor1, "XP uses supplied actor")
    check(harness.events[3].actor == harness.actor0, "levels uses supplied actor")
    check(harness.events[4].actor == harness.actor1, "clear uses supplied actor")
    for index = 1, 4 do
        equal(harness.events[index].module, "SurvivorLevelingAdvancement", "request module " .. index)
        equal(harness.events[index].command, "adminRequest", "request command " .. index)
        equal(harness.events[index].envelope.protocolVersion, 1, "request protocol " .. index)
    end
    exact(harness.events[1].envelope, {
        protocolVersion = 1, requestId = inspect.requestId, operation = "inspect",
        target = harness.events[1].envelope.target,
    }, "exact inspect envelope")
    exact(harness.events[1].envelope.target, { username = nonAscii }, "username-only inspect target")
    equal(harness.events[1].envelope.target.username, nonAscii, "non-ASCII target preserved")
    exact(harness.events[2].envelope, {
        protocolVersion = 1, requestId = xp.requestId, operation = "awardSurvivorXp",
        target = harness.events[2].envelope.target, expectedRevision = 7, amount = 125.5,
    }, "exact XP envelope")
    exact(harness.events[3].envelope, {
        protocolVersion = 1, requestId = levels.requestId, operation = "awardSurvivorLevels",
        target = harness.events[3].envelope.target, expectedRevision = 7, count = 2,
    }, "exact levels envelope")
    exact(harness.events[4].envelope, {
        protocolVersion = 1, requestId = clear.requestId, operation = "clearAdvancementSlots",
        target = harness.events[4].envelope.target, expectedRevision = 7,
    }, "exact clear envelope")
    local pending = harness.client.status(0)
    pending.target.username = "MutatedPendingTarget"
    equal(harness.client.status(0).target.username, nonAscii, "pending target detached")
end

do
    local harness = makeClientHarness()
    local invalid = {
        function() return harness.client.request(-1, harness.actor0, adminLogicalInspect()) end,
        function() return harness.client.request(4, harness.actor0, adminLogicalInspect()) end,
        function() return harness.client.request(0, nil, adminLogicalInspect()) end,
        function() return harness.client.request(0, harness.actor0, { operation = "inspect", target = target() }) end,
        function() return harness.client.request(0, harness.actor0, { operation = "inspect", target = usernameTarget(), extra = true }) end,
        function() return harness.client.request(0, harness.actor0, { operation = "inspect", target = { username = "bad\nname" } }) end,
        function() return harness.client.request(0, harness.actor0, { operation = "inspect", target = { username = "bad" .. string.char(127) } }) end,
        function() return harness.client.request(0, harness.actor0, { operation = "awardSurvivorXp", target = usernameTarget(), expectedRevision = 7, amount = 1 }) end,
        function() return harness.client.request(0, harness.actor0, adminLogicalXp(41, "T", 7, math.huge)) end,
        function() return harness.client.request(0, harness.actor0, adminLogicalLevels(41, "T", 7, 1.5)) end,
        function() return harness.client.request(0, harness.actor0, { operation = "clearAdvancementSlots", target = target(), expectedRevision = -1 }) end,
        function() return harness.client.request(0, harness.actor0, { operation = "clearAdvancementSlots", target = target() }) end,
        function() return harness.client.request(0, harness.actor0, { operation = "clearAdvancementSlots", target = target(), expectedRevision = 7, count = 1 }) end,
        function() return harness.client.request(0, harness.actor0, { operation = "advancePerkNormally", target = target(), expectedRevision = 7 }) end,
        function() return harness.client.request(0, harness.actor0, { operation = "resetAccounting", target = target(), expectedRevision = 7 }) end,
        function() return harness.client.request(0, harness.actor0, { operation = "setAccounting", target = target(), expectedRevision = 7 }) end,
    }
    for index = 1, #invalid do
        exact(invalid[index](), { ok = false, code = "invalid_request", detail = "request" },
            "invalid logical request " .. index)
    end
    exact(harness.client.status(0), { ok = true, pending = false }, "invalid requests create no route")
    equal(#harness.events, 0, "invalid requests send nothing")
    check(harness.client.request(0, harness.actor0, adminLogicalInspect()).ok, "valid request follows invalids")
    exact(harness.client.request(0, harness.actor0, adminLogicalInspect()), {
        ok = false, code = "pending_request", detail = "slot",
    }, "pending collision sends nothing")
    equal(#harness.events, 1, "collision did not send")
end


do
    local harness = makeClientHarness()
    harness.client.request(3, harness.actor1, adminLogicalClear(44, "ClearTarget"))
    local route = pendingRoute(harness.client, 3)
    local invalid = adminResponse(route, "applied", { levelsGained = 1, apGained = 1 })
    exact(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", invalid), {
        ok = false, code = "invalid_response", detail = "response",
    }, "clear rejects nonzero gain response")
    check(harness.client.status(3).pending, "invalid clear response retains route")
    local handled = harness.client.handle(
        "SurvivorLevelingAdvancement", "adminResult", adminResponse(route, "applied")
    )
    equal(handled.localSlot, 3, "clear response correlates to exact slot")
    local terminal = harness.client.status(3).result
    equal(terminal.operation, "clearAdvancementSlots", "clear terminal operation")
    equal(terminal.levelsGained, 0, "clear terminal zero levels")
    equal(terminal.apGained, 0, "clear terminal zero AP")
end

do
    local harness = makeClientHarness()
    harness.client.request(0, harness.actor0, adminLogicalInspect())
    harness.client.request(1, harness.actor1, adminLogicalXp())
    local route0 = pendingRoute(harness.client, 0)
    local route1 = pendingRoute(harness.client, 1)
    local applied = adminResponse(route1, "applied")
    local accepted = harness.client.handle("SurvivorLevelingAdvancement", "adminResult", applied)
    equal(accepted.localSlot, 1, "out-of-order response routes by request ID")
    local remaining = harness.client.status(0)
    exact(remaining, {
        ok = true, pending = true, requestId = route0.requestId,
        operation = "inspect", target = remaining.target,
    }, "other slot remains pending")
    check(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", applied).ok == false,
        "duplicate response rejected")
    local mismatch = adminResponse({
        requestId = route0.requestId,
        operation = "awardSurvivorXp",
        target = { onlineId = 77, username = route0.target.username },
    }, "applied")
    exact(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", mismatch), {
        ok = false, code = "unknown_response", detail = "route",
    }, "operation mismatch retains route")
    mismatch = adminResponse(route0, "inspected")
    mismatch.target.username = "OtherTarget"
    exact(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", mismatch), {
        ok = false, code = "invalid_response", detail = "response",
    }, "target mismatch retains route")
    check(harness.client.status(0).pending, "mismatches leave original slot pending")
    check(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", adminResponse(route0, "inspected")).ok,
        "matching inspection resolves slot")
    equal(harness.client.status(0).result.target.onlineId, 77,
        "matching inspection stores canonical online ID")
end

do
    local harness = makeClientHarness()
    harness.client.request(0, harness.actor0, adminLogicalInspect("InspectTarget"))
    local route = pendingRoute(harness.client, 0)
    local hostile = {}
    local mismatch = adminResponse(route, "inspected")
    mismatch.target.username = "OtherTarget"
    hostile[#hostile + 1] = mismatch
    hostile[#hostile + 1] = adminResponse(route, "inspected", {
        target = { username = route.target.username },
    })
    hostile[#hostile + 1] = adminResponse(route, "inspected", {
        target = { onlineId = -1, username = route.target.username },
    })
    hostile[#hostile + 1] = adminResponse(route, "inspected", {
        target = { onlineId = 9007199254740992, username = route.target.username },
    })
    hostile[#hostile + 1] = adminResponse(route, "failure", {
        target = { onlineId = 77, username = route.target.username },
    })
    hostile[#hostile + 1] = adminResponse(route, "failure", {
        target = { username = route.target.username, extra = true },
    })
    hostile[#hostile + 1] = adminResponse(route, "inspected", { extra = true })
    hostile[#hostile + 1] = adminResponse(route, "failure", {
        target = { username = "OtherTarget" },
    })
    hostile[#hostile + 1] = adminResponse(route, "failure", { committed = true })
    for index = 1, #hostile do
        exact(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", hostile[index]), {
            ok = false, code = "invalid_response", detail = "response",
        }, "hostile inspect response " .. index)
        check(harness.client.status(0).pending,
            "hostile inspect response retains pending route " .. index)
        equal(harness.client.status(0).requestId, route.requestId,
            "hostile inspect response preserves pending identity " .. index)
    end
    local failureResponse = adminResponse(route, "failure")
    check(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", failureResponse).ok,
        "matching username-only inspect failure handled")
    local result = harness.client.status(0).result
    exact(result.target, { username = "InspectTarget" }, "inspect failure terminal target")
    check(result.ok == false and result.committed == false,
        "inspect failure terminal remains uncommitted")
end

do
    local harness = makeClientHarness()
    harness.client.request(0, harness.actor0, adminLogicalXp())
    local route = pendingRoute(harness.client, 0)
    local response = adminResponse(route, "failure", { committed = true })
    local handled = harness.client.handle(
        "SurvivorLevelingAdvancement",
        "adminResult",
        response
    )
    check(handled.ok and handled.handled, "committed mutation failure remains valid")
    local state = harness.client.status(0)
    check(not state.pending and state.result.committed == true,
        "committed mutation failure replaces its matching route")
end

do
    local outcomes = { "inspected", "applied", "rejected", "failure" }
    for index = 1, #outcomes do
        local outcome = outcomes[index]
        local harness = makeClientHarness()
        local request = outcome == "inspected" and adminLogicalInspect()
            or adminLogicalXp()
        harness.client.request(0, harness.actor0, request)
        local route = pendingRoute(harness.client, 0)
        local response = adminResponse(route, outcome)
        local handled = harness.client.handle("SurvivorLevelingAdvancement", "adminResult", response)
        check(handled.ok and handled.handled, "valid outcome handled " .. outcome)
        local state = harness.client.status(0)
        check(state.pending == false and state.result ~= nil, "terminal stored " .. outcome)
        exact(state.result, {
            ok = response.ok, requestId = route.requestId, operation = route.operation,
            target = state.result.target,
            outcome = response.outcome, levelsGained = response.levelsGained,
            apGained = response.apGained, summary = state.result.summary,
            code = response.code, detail = response.detail, committed = response.committed,
        }, "terminal exact " .. outcome)
        check(state.result.target ~= response.target, "terminal target detached " .. outcome)
        if response.summary ~= nil then
            check(state.result.summary ~= response.summary, "terminal summary detached " .. outcome)
            handled.result.target.username = "MutatedTerminalTarget"
            handled.result.summary.level = 999
            equal(harness.client.status(0).result.target.username, route.target.username,
                "handled terminal target isolated " .. outcome)
            equal(harness.client.status(0).result.summary.level,
                outcome == "applied" and 6 or 5, "handled terminal summary isolated " .. outcome)
            response.summary.level = 999
            equal(harness.client.status(0).result.summary.level,
                outcome == "applied" and 6 or 5, "terminal summary isolated " .. outcome)
        end
    end
end

do
    local harness = makeClientHarness()
    harness.client.request(0, harness.actor0, adminLogicalXp())
    harness.client.request(1, harness.actor1, adminLogicalXp())
    local route0 = pendingRoute(harness.client, 0)
    local route1 = pendingRoute(harness.client, 1)
    local hostile = {
        {},
        adminResponse(route0, "applied", { extra = true }),
        adminResponse(route0, "applied", { levelsGained = 2 }),
        adminResponse(route0, "applied", { summary = summary({ revision = 7 }) }),
        adminResponse(route0, "rejected", { code = "other" }),
        adminResponse(route0, "failure", { committed = "false" }),
    }
    for index = 1, #hostile do
        exact(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", hostile[index]), {
            ok = false, code = "invalid_response", detail = "response",
        }, "hostile response rejected " .. index)
        check(harness.client.status(0).pending and harness.client.status(1).pending,
            "hostile response retains all routes " .. index)
    end
    check(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", adminResponse(route1, "applied")).ok,
        "hostile slot cannot poison other route")
    check(harness.client.status(0).pending and not harness.client.status(1).pending,
        "only matching route clears")
end

do
    local failing = makeClientHarness({ sendThrow = true })
    local result = failing.client.request(2, failing.actor0, adminLogicalLevels())
    exact(result, { ok = false, code = "send_failed", detail = "sendClientCommand", committed = false },
        "send failure result")
    local state = failing.client.status(2)
    exact(state.result, {
        ok = false, requestId = state.result.requestId, operation = "awardSurvivorLevels",
        target = state.result.target, code = "send_failed", detail = "sendClientCommand", committed = false,
    }, "send failure terminal")
    check(not state.pending, "send failure clears only route")

    failing = makeClientHarness({ sendThrow = true })
    result = failing.client.request(2, failing.actor0, adminLogicalInspect("InspectTarget"))
    exact(result, { ok = false, code = "send_failed", detail = "sendClientCommand", committed = false },
        "inspect send failure result")
    state = failing.client.status(2)
    exact(state.result.target, { username = "InspectTarget" },
        "inspect send failure retains username-only target")

    local harness = makeClientHarness()
    harness.client.request(0, harness.actor0, adminLogicalInspect())
    harness.client.request(1, harness.actor1, adminLogicalInspect())
    local resetRoute = pendingRoute(harness.client, 0)
    harness.client.resetSlot(0)
    check(not harness.client.status(0).pending and harness.client.status(1).pending,
        "resetSlot is contained")
    exact(harness.client.handle("SurvivorLevelingAdvancement", "adminResult", adminResponse(resetRoute, "inspected")), {
        ok = false, code = "unknown_response", detail = "route",
    }, "reset route cannot return")
    harness.client.reset()
    for slot = 0, 3 do exact(harness.client.status(slot), { ok = true, pending = false }, "reset slot " .. slot) end
    exact(harness.client.status(4), { ok = false, code = "invalid_slot", detail = "slot" }, "invalid status slot")
end

return assertions
