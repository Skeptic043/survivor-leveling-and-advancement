local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed") end
end

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
    end
end

local function same(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not same(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function exact(value, fields)
    local count, expected = 0, 0
    for key in pairs(value) do
        if not fields[key] then return false end
        count = count + 1
    end
    for key in pairs(fields) do
        expected = expected + 1
        if value[key] == nil then return false end
    end
    return count == expected
end

local function snapshot(sequence, revision, level, ready)
    level = level or 3
    return {
        protocolVersion = 1,
        ready = ready == nil and true or ready,
        sequence = sequence or 1,
        revision = revision or 0,
        survivor = {
            level = level,
            xpIntoLevel = 10.5,
            xpForNextLevel = 2100,
            spent = 1,
            availableAp = level - 1,
        },
        perks = {
            Axe = {
                effectiveMaximum = 10,
                naturalPosition = 2,
                highWaterPosition = 2.5,
                activeTargets = {
                    { targetLevel = 4, targetPosition = 4.5 },
                },
            },
        },
    }
end

local function failed(result, code, detail)
    equal(result.ok, false, "failure expected")
    equal(result.code, code, "failure code")
    equal(result.detail, detail, "failure detail")
    equal(result.snapshot, nil, "failure has no snapshot")
end

local function request(correlationId)
    return { protocolVersion = 1, correlationId = correlationId or "owner-ready-1" }
end

failed(Build42OwnerTransport.createServer(nil), "invalid_dependencies", "dependencies")
failed(Build42OwnerTransport.createServer({}), "invalid_dependencies", "ownerSession")
failed(Build42OwnerTransport.createServer({ ownerSession = {} }), "invalid_dependencies", "ownerSession")
failed(Build42OwnerTransport.createServer({
    ownerSession = { ready = function() end, snapshot = function() end, clearPlayer = function() end },
}), "invalid_dependencies", "snapshotValidator.validate")
failed(Build42OwnerTransport.createServer({
    ownerSession = { ready = function() end, snapshot = function() end, clearPlayer = function() end },
    snapshotValidator = {},
}), "invalid_dependencies", "snapshotValidator.validate")
failed(Build42OwnerTransport.createServer({
    ownerSession = { ready = function() end, snapshot = function() end, clearPlayer = function() end },
    snapshotValidator = ClientOwnerState,
}), "invalid_dependencies", "sendServerCommand")
failed(Build42OwnerTransport.createClient(nil), "invalid_dependencies", "dependencies")
failed(Build42OwnerTransport.createClient({}), "invalid_dependencies", "ClientOwnerState.create")
failed(Build42OwnerTransport.createClient({ ClientOwnerState = {} }), "invalid_dependencies", "ClientOwnerState.create")
failed(Build42OwnerTransport.createClient({ ClientOwnerState = ClientOwnerState }), "invalid_dependencies", "sendClientCommand")

local serverCalls = { ready = 0, snapshot = 0, clear = 0, validate = 0, sends = {} }
local readySnapshot = snapshot(1, 4, 3)
local publishedSnapshot = snapshot(2, 5, 4)
local serverPlayer = {}
local session = {
    ready = function(player)
        serverCalls.ready = serverCalls.ready + 1
        serverCalls.readyPlayer = player
        return { ok = true, snapshot = readySnapshot, recovered = false, initialized = 2, skipped = 0 }
    end,
    snapshot = function(player)
        serverCalls.snapshot = serverCalls.snapshot + 1
        serverCalls.snapshotPlayer = player
        return { ok = true, snapshot = publishedSnapshot }
    end,
    clearPlayer = function(player)
        serverCalls.clear = serverCalls.clear + 1
        serverCalls.clearPlayer = player
        return { ok = true }
    end,
}
local function captureServerSend(player, module, command, args)
    serverCalls.sends[#serverCalls.sends + 1] = {
        player = player,
        module = module,
        command = command,
        args = args,
    }
end
local serverValidator = {
    validate = function(value)
        serverCalls.validate = serverCalls.validate + 1
        return ClientOwnerState.validate(value)
    end,
}
local serverCreated = Build42OwnerTransport.createServer({
    ownerSession = session,
    snapshotValidator = serverValidator,
    sendServerCommand = captureServerSend,
})
expect(same(serverCreated, { ok = true, server = serverCreated.server }), "server creation shape")
local server = serverCreated.server

expect(same(server.handle("OtherMod", "ownerReady", nil, nil), { ok = true, handled = false }), "foreign module ignored")
equal(serverCalls.ready, 0, "foreign module does not call session")
equal(#serverCalls.sends, 0, "foreign module does not send")
failed(server.handle("SurvivorLevelingAdvancement", "unknown", serverPlayer, request()), "unknown_command", "owner command")
equal(serverCalls.ready, 0, "unknown same-module command does not call session")
failed(server.handle("SurvivorLevelingAdvancement", "ownerReady", nil, request()), "invalid_player", "player")

local function invalidRequest(value, code, detail)
    local beforeReady, beforeSends = serverCalls.ready, #serverCalls.sends
    failed(server.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, value), code, detail)
    equal(serverCalls.ready, beforeReady, "invalid request does not call ready")
    equal(#serverCalls.sends, beforeSends, "invalid request does not send")
end

invalidRequest(nil, "invalid_request", "request shape")
invalidRequest({}, "invalid_request", "request shape")
invalidRequest({ protocolVersion = 1, correlationId = "ok", playerIndex = 0 }, "invalid_request", "request shape")
invalidRequest({ protocolVersion = 1, correlationId = "ok", username = "private" }, "invalid_request", "request shape")
invalidRequest({ protocolVersion = 2, correlationId = "ok" }, "protocol_mismatch", "protocolVersion")
invalidRequest({ protocolVersion = 1, correlationId = "" }, "invalid_request", "correlationId")
invalidRequest({ protocolVersion = 1, correlationId = "bad id" }, "invalid_request", "correlationId")
local unicodeId = "ready-" .. string.char(195, 169)
invalidRequest({ protocolVersion = 1, correlationId = unicodeId }, "invalid_request", "correlationId")
invalidRequest({ protocolVersion = 1, correlationId = string.rep("a", 65) }, "invalid_request", "correlationId")
local metatableRequest = request("meta")
setmetatable(metatableRequest, {})
invalidRequest(metatableRequest, "invalid_request", "request shape")

local correlation64 = string.rep("a", 64)
local handled = server.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request(correlation64))
expect(same(handled, { ok = true, handled = true }), "ready request handled")
equal(serverCalls.ready, 1, "ready called once")
equal(serverCalls.validate, 1, "ready snapshot validated once")
equal(serverCalls.readyPlayer, serverPlayer, "callback player is authoritative identity")
equal(#serverCalls.sends, 1, "ready sends once")
local sent = serverCalls.sends[1]
equal(sent.player, serverPlayer, "response targets callback player")
equal(sent.module, "SurvivorLevelingAdvancement", "exact response module")
equal(sent.command, "ownerSnapshot", "exact response command")
expect(exact(sent.args, { protocolVersion = true, correlationId = true, ok = true, snapshot = true }), "success response exact fields")
equal(sent.args.protocolVersion, 1, "success response protocol")
equal(sent.args.correlationId, correlation64, "success echoes correlation")
equal(sent.args.ok, true, "success flag")
expect(sent.args.snapshot ~= readySnapshot, "server sends the validator's detached snapshot")
expect(same(sent.args.snapshot, readySnapshot), "validated snapshot preserves the exact public shape")
expect(sent.args.snapshot.survivor ~= readySnapshot.survivor, "validated survivor is detached")
expect(sent.args.snapshot.perks.Axe ~= readySnapshot.perks.Axe, "validated perk is detached")
readySnapshot.survivor.level = 99
readySnapshot.perks.Axe.activeTargets[1].targetPosition = 99
equal(sent.args.snapshot.survivor.level, 3, "sent snapshot ignores later session-output mutation")
equal(sent.args.snapshot.perks.Axe.activeTargets[1].targetPosition, 4.5, "sent nested snapshot ignores later session-output mutation")
equal(sent.args.player, nil, "response carries no player object")
equal(sent.args.playerIndex, nil, "response carries no player index")
equal(sent.args.username, nil, "response carries no username")

local published = server.publish(serverPlayer)
expect(same(published, { ok = true, published = true }), "publish succeeds")
equal(serverCalls.snapshot, 1, "snapshot called once")
equal(serverCalls.validate, 2, "published snapshot validated once")
equal(serverCalls.snapshotPlayer, serverPlayer, "publish uses exact bound player")
equal(#serverCalls.sends, 2, "publish sends once")
equal(serverCalls.sends[2].args.correlationId, correlation64, "publish reuses bound correlation")
expect(serverCalls.sends[2].args.snapshot ~= publishedSnapshot, "publish sends detached validated output")
expect(same(serverCalls.sends[2].args.snapshot, publishedSnapshot), "publish preserves exact public snapshot")

expect(same(server.clearPlayer(serverPlayer), { ok = true }), "clear succeeds")
equal(serverCalls.clear, 1, "session clear called once")
equal(serverCalls.clearPlayer, serverPlayer, "session clear uses exact player")
failed(server.publish(serverPlayer), "not_bound", "player route")
equal(serverCalls.snapshot, 1, "unbound publish does not call snapshot")

local function serverHarness(readyResult, snapshotResult, sendFunction, clearResult, validator)
    local calls = { ready = 0, snapshot = 0, clear = 0, validate = 0, sends = {} }
    local owner = {
        ready = function(player)
            calls.ready = calls.ready + 1
            if type(readyResult) == "function" then return readyResult(player) end
            return readyResult
        end,
        snapshot = function(player)
            calls.snapshot = calls.snapshot + 1
            if type(snapshotResult) == "function" then return snapshotResult(player) end
            return snapshotResult
        end,
        clearPlayer = function(player)
            calls.clear = calls.clear + 1
            if type(clearResult) == "function" then return clearResult(player) end
            return clearResult or { ok = true }
        end,
    }
    local sender = sendFunction or function(player, module, command, args)
        calls.sends[#calls.sends + 1] = { player = player, module = module, command = command, args = args }
    end
    local checkedValidator = validator or {
        validate = function(value)
            calls.validate = calls.validate + 1
            return ClientOwnerState.validate(value)
        end,
    }
    return Build42OwnerTransport.createServer({
        ownerSession = owner,
        snapshotValidator = checkedValidator,
        sendServerCommand = sender,
    }).server, calls
end

local rejectedServer, rejectedCalls = serverHarness(
    { ok = false, code = "store_load_failed", detail = "unavailable:unavailable" },
    { ok = true, snapshot = snapshot(2) }
)
failed(rejectedServer.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request("failure")), "store_load_failed", "unavailable:unavailable")
equal(rejectedCalls.ready, 1, "failed ready called once")
equal(#rejectedCalls.sends, 1, "failed ready sends bounded response")
expect(same(rejectedCalls.sends[1].args, {
    protocolVersion = 1,
    correlationId = "failure",
    ok = false,
    code = "store_load_failed",
    detail = "unavailable:unavailable",
}), "failure response exact shape")
failed(rejectedServer.publish(serverPlayer), "not_bound", "player route")

local malformedServer, malformedCalls = serverHarness({}, { ok = true, snapshot = snapshot(2) })
failed(malformedServer.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request("malformed")), "session_ready_invalid", "ownerSession.ready")
equal(malformedCalls.sends[1].args.code, "session_ready_invalid", "malformed session failure is bounded")
local throwingServer, throwingCalls = serverHarness(function() error("secret thrown detail") end, { ok = true, snapshot = snapshot(2) })
failed(throwingServer.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request("throwing")), "session_ready_threw", "ownerSession.ready")
equal(throwingCalls.sends[1].args.detail, "ownerSession.ready", "thrown detail is not leaked")
local unsafeServer, unsafeCalls = serverHarness({ ok = false, code = "bad code", detail = "bad\nprivate" }, { ok = true, snapshot = snapshot(2) })
failed(unsafeServer.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request("unsafe")), "session_ready_invalid", "ownerSession.ready")
equal(unsafeCalls.sends[1].args.code, "session_ready_invalid", "unsafe dependency code is replaced")

local function validatorFailureCase(label, sessionSnapshot, validator, expectedCode, expectedDetail)
    local checkedServer, calls = serverHarness(
        { ok = true, snapshot = sessionSnapshot },
        { ok = true, snapshot = snapshot(2) },
        nil,
        nil,
        validator
    )
    failed(checkedServer.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request(label)), expectedCode, expectedDetail)
    equal(calls.ready, 1, label .. " calls ready once")
    equal(#calls.sends, 1, label .. " sends only a bounded failure envelope")
    equal(calls.sends[1].args.ok, false, label .. " never sends snapshot success")
    equal(calls.sends[1].args.snapshot, nil, label .. " failure envelope has no snapshot")
    equal(calls.sends[1].args.code, expectedCode, label .. " failure response code")
    failed(checkedServer.publish(serverPlayer), "not_bound", "player route")
end

local privateRootSnapshot = snapshot(1)
privateRootSnapshot.rawModData = { private = true }
validatorFailureCase("private-root", privateRootSnapshot, ClientOwnerState, "invalid_snapshot", "fields")
local privateNestedSnapshot = snapshot(1)
privateNestedSnapshot.perks.Axe.adapterId = "private.adapter"
validatorFailureCase("private-nested", privateNestedSnapshot, ClientOwnerState, "invalid_perk", "fields")
validatorFailureCase("validator-throw", snapshot(1), {
    validate = function() error("private validator detail") end,
}, "snapshot_validation_threw", "snapshotValidator.validate")
validatorFailureCase("validator-malformed", snapshot(1), {
    validate = function(value) return { ok = true, snapshot = value, extra = true } end,
}, "snapshot_validation_invalid", "snapshotValidator.validate")
validatorFailureCase("validator-explicit", snapshot(1), {
    validate = function() return { ok = false, code = "invalid_snapshot", detail = "fields" } end,
}, "invalid_snapshot", "fields")

local sendThrowsServer, sendThrowsCalls = serverHarness(
    { ok = true, snapshot = snapshot(1) },
    { ok = true, snapshot = snapshot(2) },
    function() error("network detail") end
)
failed(sendThrowsServer.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request("send-fail")), "send_threw", "sendServerCommand")
equal(sendThrowsCalls.ready, 1, "send failure follows one ready call")
failed(sendThrowsServer.publish(serverPlayer), "not_bound", "player route")

local publishFailureServer, publishFailureCalls = serverHarness(
    { ok = true, snapshot = snapshot(1) },
    { ok = false, code = "store_load_failed", detail = "unavailable:unavailable" }
)
expect(publishFailureServer.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request("bound")).ok, "publish failure server binds")
failed(publishFailureServer.publish(serverPlayer), "store_load_failed", "unavailable:unavailable")
equal(publishFailureCalls.snapshot, 1, "failed publish calls snapshot once")
equal(#publishFailureCalls.sends, 2, "failed publish sends bounded response")
equal(publishFailureCalls.sends[2].args.ok, false, "publish failure response flag")

local publishValidationCount = 0
local publishValidationServer, publishValidationCalls = serverHarness(
    { ok = true, snapshot = snapshot(1) },
    { ok = true, snapshot = snapshot(2) },
    nil,
    nil,
    {
        validate = function(value)
            publishValidationCount = publishValidationCount + 1
            if publishValidationCount == 1 then return ClientOwnerState.validate(value) end
            return { ok = false, code = "invalid_snapshot", detail = "fields" }
        end,
    }
)
expect(publishValidationServer.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request("publish-validation")).ok, "validator accepts ready snapshot")
failed(publishValidationServer.publish(serverPlayer), "invalid_snapshot", "fields")
equal(publishValidationCalls.snapshot, 1, "publish validator failure follows one session snapshot")
equal(publishValidationCount, 2, "every successful session snapshot is validated once")
equal(#publishValidationCalls.sends, 2, "publish validator failure sends one bounded failure after ready success")
equal(publishValidationCalls.sends[2].args.ok, false, "publish validator failure is not a success response")
equal(publishValidationCalls.sends[2].args.snapshot, nil, "publish validator failure sends no snapshot")

local clearFailureServer, clearFailureCalls = serverHarness(
    { ok = true, snapshot = snapshot(1) },
    { ok = true, snapshot = snapshot(2) },
    nil,
    { ok = false, code = "clear_failed", detail = "bounded" }
)
expect(clearFailureServer.handle("SurvivorLevelingAdvancement", "ownerReady", serverPlayer, request("clear")).ok, "clear failure server binds")
failed(clearFailureServer.clearPlayer(serverPlayer), "clear_failed", "bounded")
equal(clearFailureCalls.clear, 1, "clear failure called once")
expect(clearFailureServer.publish(serverPlayer).ok, "failed session clear preserves server binding")
equal(clearFailureCalls.snapshot, 1, "preserved binding can still publish")

local clientSends = {}
local function captureClientSend(player, module, command, args)
    clientSends[#clientSends + 1] = { player = player, module = module, command = command, args = args }
end
local clientCreated = Build42OwnerTransport.createClient({
    ClientOwnerState = ClientOwnerState,
    sendClientCommand = captureClientSend,
})
expect(same(clientCreated, { ok = true, client = clientCreated.client }), "client creation shape")
local client = clientCreated.client
local player0, player1 = {}, {}

failed(client.ready(-1, player0), "invalid_slot", "localSlot")
failed(client.ready(0.5, player0), "invalid_slot", "localSlot")
failed(client.ready(4, player0), "invalid_slot", "localSlot")
failed(client.ready(0, nil), "invalid_player", "player")
failed(client.get(-1), "invalid_slot", "localSlot")
failed(client.get(4), "invalid_slot", "localSlot")
failed(client.status("0"), "invalid_slot", "localSlot")
failed(client.acceptLocal(-1, snapshot(1)), "invalid_slot", "localSlot")
failed(client.acceptLocal(4, snapshot(1)), "invalid_slot", "localSlot")
failed(client.resetSlot(4), "invalid_slot", "localSlot")

local ready0 = client.ready(0, player0)
equal(ready0.ok, true, "slot zero ready succeeds")
equal(#clientSends, 1, "ready sends once")
equal(clientSends[1].player, player0, "ready uses supplied local player")
equal(clientSends[1].module, "SurvivorLevelingAdvancement", "exact request module")
equal(clientSends[1].command, "ownerReady", "exact request command")
expect(exact(clientSends[1].args, { protocolVersion = true, correlationId = true }), "request exact fields")
equal(clientSends[1].args.protocolVersion, 1, "request protocol")
equal(clientSends[1].args.correlationId, ready0.correlationId, "returned correlation matches request")
expect(#ready0.correlationId <= 64 and ready0.correlationId:match("^[%w%._:%-]+$") ~= nil, "correlation is bounded and safe")
equal(clientSends[1].args.playerIndex, nil, "request has no player index")
equal(clientSends[1].args.player, nil, "request has no player object")
equal(clientSends[1].args.username, nil, "request has no username")
expect(same(client.get(0), { ok = true, present = false }), "ready resets inbox")
expect(same(client.status(0), { ok = true, present = false, route = "pending" }), "ready creates pending route")

local ready1 = client.ready(1, player1)
equal(ready1.ok, true, "slot one ready succeeds")
expect(ready1.correlationId ~= ready0.correlationId, "split-screen tokens are unique")
equal(clientSends[2].player, player1, "slot one uses exact player")

expect(same(client.handle("OtherMod", "ownerSnapshot", nil), { ok = true, handled = false }), "client ignores foreign module")
expect(same(client.handle("SurvivorLevelingAdvancement", "unknown", nil), { ok = true, handled = false }), "client ignores other command")

local slot1Snapshot = snapshot(1, 2, 5)
local slot1Handled = client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = ready1.correlationId,
    ok = true,
    snapshot = slot1Snapshot,
})
expect(same(slot1Handled, { ok = true, handled = true, accepted = true }), "slot one snapshot accepted")
equal(client.get(1).snapshot.survivor.level, 5, "slot one receives its response")
equal(client.get(0).present, false, "slot zero remains pending")
equal(client.status(1).route, "active", "accepted route becomes active")

local slot0Snapshot = snapshot(1, 3, 3)
expect(client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = ready0.correlationId,
    ok = true,
    snapshot = slot0Snapshot,
}).accepted, "slot zero snapshot accepted")
equal(client.get(0).snapshot.survivor.level, 3, "slot zero receives its response")
equal(client.get(1).snapshot.survivor.level, 5, "slot one remains isolated")

slot0Snapshot.survivor.level = 99
slot0Snapshot.perks.Axe.activeTargets[1].targetPosition = 99
local detached = client.get(0).snapshot
equal(detached.survivor.level, 3, "client inbox detaches accepted input")
equal(detached.perks.Axe.activeTargets[1].targetPosition, 4.5, "nested accepted input is detached")
detached.survivor.level = 88
equal(client.get(0).snapshot.survivor.level, 3, "client get remains detached")

local newerSnapshot = snapshot(2, 4, 4)
expect(client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = ready0.correlationId,
    ok = true,
    snapshot = newerSnapshot,
}).accepted, "active route accepts newer snapshot")
local staleResult = client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = ready0.correlationId,
    ok = true,
    snapshot = snapshot(2, 99, 8),
})
expect(same(staleResult, { ok = true, handled = true, accepted = false, code = "stale_snapshot" }), "stale snapshot remains unaccepted")
equal(client.get(0).snapshot.revision, 4, "stale response does not mutate inbox")
equal(client.status(0).route, "active", "stale active response preserves binding")

local unknownCorrelation = client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = "unknown",
    ok = true,
    snapshot = snapshot(3),
})
failed(unknownCorrelation, "unknown_correlation", "correlationId")
equal(client.get(0).snapshot.sequence, 2, "unknown correlation does not mutate")

local serverFailureResult = client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = ready0.correlationId,
    ok = false,
    code = "store_load_failed",
    detail = "unavailable:unavailable",
})
expect(same(serverFailureResult, {
    ok = true,
    handled = true,
    accepted = false,
    code = "store_load_failed",
}), "bounded server failure is handled without inbox acceptance")
local failureStatus = client.status(0)
equal(failureStatus.route, "active", "server failure preserves active route")
expect(same(failureStatus.failure, { code = "store_load_failed", detail = "unavailable:unavailable" }), "server failure retained only as bounded status")
equal(failureStatus.snapshot, nil, "status does not expose snapshot")
equal(failureStatus.perks, nil, "status does not expose perks")
equal(client.get(0).snapshot.sequence, 2, "server failure does not enter inbox")

local replacementReady = client.ready(0, player0)
equal(replacementReady.ok, true, "ready replay succeeds")
expect(replacementReady.correlationId ~= ready0.correlationId, "ready replay gets a new token")
expect(same(client.get(0), { ok = true, present = false }), "ready replay resets slot inbox")
equal(client.status(0).route, "pending", "ready replay replaces active route")
failed(client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = ready0.correlationId,
    ok = true,
    snapshot = snapshot(3),
}), "unknown_correlation", "correlationId")

local function invalidResponse(value, code, detail)
    local before = client.status(0)
    failed(client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", value), code, detail)
    local after = client.status(0)
    equal(after.route, before.route, "invalid response preserves route")
    equal(after.present, before.present, "invalid response preserves inbox presence")
end

invalidResponse(nil, "invalid_response", "response shape")
invalidResponse({}, "invalid_response", "response shape")
invalidResponse({ protocolVersion = 1, correlationId = replacementReady.correlationId, ok = true, snapshot = snapshot(1), playerIndex = 0 }, "invalid_response", "response shape")
invalidResponse({ protocolVersion = 2, correlationId = replacementReady.correlationId, ok = true, snapshot = snapshot(1) }, "protocol_mismatch", "protocolVersion")
invalidResponse({ protocolVersion = 1, correlationId = "bad id", ok = true, snapshot = snapshot(1) }, "invalid_response", "correlationId")
invalidResponse({ protocolVersion = 1, correlationId = unicodeId, ok = true, snapshot = snapshot(1) }, "invalid_response", "correlationId")
invalidResponse({ protocolVersion = 1, correlationId = replacementReady.correlationId, ok = true, snapshot = 4 }, "invalid_response", "snapshot")
invalidResponse({ protocolVersion = 1, correlationId = replacementReady.correlationId, ok = false, code = "bad code", detail = "bounded" }, "invalid_response", "failure detail")
invalidResponse({ protocolVersion = 1, correlationId = replacementReady.correlationId, ok = false, code = "bad" .. string.char(195, 169), detail = "bounded" }, "invalid_response", "failure detail")
invalidResponse({ protocolVersion = 1, correlationId = replacementReady.correlationId, ok = false, code = "safe", detail = "bad\nvalue" }, "invalid_response", "failure detail")
local metaResponse = { protocolVersion = 1, correlationId = replacementReady.correlationId, ok = true, snapshot = snapshot(1) }
setmetatable(metaResponse, {})
invalidResponse(metaResponse, "invalid_response", "response shape")

local pendingFailure = client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = replacementReady.correlationId,
    ok = false,
    code = "ready_failed",
    detail = "bounded",
})
equal(pendingFailure.accepted, false, "pending server failure is not accepted")
equal(client.status(0).route, "none", "pending server failure consumes correlation route")
equal(client.status(0).failure.code, "ready_failed", "pending failure reaches status")
equal(client.get(0).present, false, "pending failure does not enter inbox")

failed(client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = replacementReady.correlationId,
    ok = true,
    snapshot = snapshot(1, 7, 6),
}), "unknown_correlation", "correlationId")
local postFailureReady = client.ready(0, player0)
expect(client.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = postFailureReady.correlationId,
    ok = true,
    snapshot = snapshot(1, 7, 6),
}).accepted, "new ready route accepts success after a failure")
equal(client.status(0).route, "active", "later success promotes pending route")
equal(client.status(0).failure, nil, "success clears retained server failure")

local sendsBeforeLocal = #clientSends
expect(client.resetSlot(2).ok, "resetSlot accepts an absent valid slot")
local localAccepted = client.acceptLocal(2, snapshot(8, 2, 7))
equal(localAccepted.ok, true, "SP local snapshot succeeds")
equal(localAccepted.accepted, true, "SP local snapshot accepted")
equal(#clientSends, sendsBeforeLocal, "SP acceptance sends no command")
equal(client.get(2).snapshot.sequence, 8, "SP snapshot stored")
equal(client.status(2).route, "none", "SP acceptance creates no token route")

local laterLocal = client.acceptLocal(2, snapshot(9, 3, 8))
equal(laterLocal.accepted, true, "later SP snapshot preserves and advances monotone ordering")
equal(client.get(2).snapshot.sequence, 9, "later SP sequence is stored")
local staleLocal = client.acceptLocal(2, snapshot(9, 99, 9))
equal(staleLocal.accepted, false, "equal SP sequence remains stale")
equal(staleLocal.code, "stale_snapshot", "SP stale result is preserved")
equal(client.get(2).snapshot.revision, 3, "stale SP snapshot does not mutate")

local localMalformed = snapshot(10, 4, 9)
localMalformed.survivor.availableAp = 99
failed(client.acceptLocal(2, localMalformed), "invalid_survivor", "values")
equal(client.get(2).snapshot.sequence, 9, "malformed SP snapshot preserves accepted state")
expect(client.resetSlot(2).ok, "resetSlot clears an existing SP slot")
equal(client.get(2).present, false, "resetSlot clears only that inbox")
equal(client.get(1).present, true, "resetSlot preserves other local slots")
expect(client.acceptLocal(2, snapshot(1, 0, 2)).accepted, "resetSlot admits a low sequence for a new character")

local tokenBeforeReset = client.ready(3, {}).correlationId
expect(client.reset().ok, "client reset succeeds")
expect(same(client.get(0), { ok = true, present = false }), "reset clears slot zero")
expect(same(client.get(1), { ok = true, present = false }), "reset clears slot one")
expect(same(client.status(3), { ok = true, present = false, route = "none" }), "reset clears routes and failures")
local tokenAfterReset = client.ready(3, {}).correlationId
expect(tokenAfterReset ~= tokenBeforeReset, "reset preserves monotone process token counter")

local throwingClient = Build42OwnerTransport.createClient({
    ClientOwnerState = ClientOwnerState,
    sendClientCommand = function() error("send private detail") end,
}).client
failed(throwingClient.ready(0, {}), "send_threw", "sendClientCommand")
local throwingStatus = throwingClient.status(0)
equal(throwingStatus.route, "none", "failed send leaves no pending route")
expect(same(throwingStatus.failure, { code = "send_threw", detail = "sendClientCommand" }), "failed send retains bounded status")
equal(throwingClient.get(0).present, false, "failed send fabricates no state")

local fakeAcceptCalls = 0
local fakeFactory = {
    create = function()
        local inbox = {}
        function inbox.accept()
            fakeAcceptCalls = fakeAcceptCalls + 1
            return { ok = true, accepted = false, code = "stale_snapshot" }
        end
        function inbox.get() return { ok = true, present = false } end
        function inbox.reset() return { ok = true } end
        function inbox.status() return { ok = true, present = false } end
        return { ok = true, state = inbox }
    end,
}
local fakeSent
local fakeClient = Build42OwnerTransport.createClient({
    ClientOwnerState = fakeFactory,
    sendClientCommand = function(_, _, _, args) fakeSent = args end,
}).client
expect(fakeClient.ready(0, {}).ok, "fake inbox ready succeeds")
local fakeHandled = fakeClient.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
    protocolVersion = 1,
    correlationId = fakeSent.correlationId,
    ok = true,
    snapshot = {},
})
equal(fakeAcceptCalls, 1, "snapshot is passed to inbox exactly once")
equal(fakeHandled.accepted, false, "unaccepted inbox result remains unaccepted")
equal(fakeClient.status(0).route, "pending", "unaccepted snapshot does not promote route")

local function resetFailureHarness(mode)
    local stored = nil
    local calls = { sends = 0 }
    local factory = {
        create = function()
            local inbox = {}
            function inbox.accept(value)
                stored = value
                return { ok = true, accepted = true }
            end
            function inbox.get()
                if stored == nil then return { ok = true, present = false } end
                return { ok = true, present = true, snapshot = stored }
            end
            function inbox.status()
                if stored == nil then return { ok = true, present = false } end
                return {
                    ok = true,
                    present = true,
                    ready = stored.ready,
                    sequence = stored.sequence,
                    revision = stored.revision,
                }
            end
            function inbox.reset()
                if mode == "throw" then error("private reset detail") end
                return {}
            end
            return { ok = true, state = inbox }
        end,
    }
    local transport = Build42OwnerTransport.createClient({
        ClientOwnerState = factory,
        sendClientCommand = function() calls.sends = calls.sends + 1 end,
    }).client
    local readyResult = transport.ready(0, {})
    expect(readyResult.ok, "reset failure harness ready succeeds")
    expect(transport.handle("SurvivorLevelingAdvancement", "ownerSnapshot", {
        protocolVersion = 1,
        correlationId = readyResult.correlationId,
        ok = true,
        snapshot = snapshot(5, 4, 6),
    }).accepted, "reset failure harness establishes active view")
    return transport, calls
end

local thrownResetClient, thrownResetCalls = resetFailureHarness("throw")
failed(thrownResetClient.resetSlot(0), "inbox_reset_threw", "ClientOwnerState.reset")
equal(thrownResetClient.status(0).route, "active", "thrown reset preserves active route")
equal(thrownResetClient.get(0).snapshot.sequence, 5, "thrown reset preserves public view")
equal(thrownResetCalls.sends, 1, "thrown reset sends nothing")

local malformedResetClient, malformedResetCalls = resetFailureHarness("malformed")
failed(malformedResetClient.ready(0, {}), "inbox_reset_invalid", "ClientOwnerState.reset")
equal(malformedResetClient.status(0).route, "active", "malformed reset preserves active route")
equal(malformedResetClient.get(0).snapshot.sequence, 5, "malformed reset preserves public view")
equal(malformedResetCalls.sends, 1, "ready aborts before send when reset is malformed")

return assertions
