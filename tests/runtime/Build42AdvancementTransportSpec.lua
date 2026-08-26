local assertions = 0

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error((message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
    end
end

local function truthy(value, message)
    equal(value, true, message)
end

local function falsy(value, message)
    equal(value, false, message)
end

local function hasOnly(value, fields, message)
    assertions = assertions + 1
    if type(value) ~= "table" or getmetatable(value) ~= nil then
        error((message or "not exact table") .. ": not a plain table")
    end
    local actualCount = 0
    local expectedCount = 0
    for key in pairs(value) do
        actualCount = actualCount + 1
        if not fields[key] then error((message or "not exact table") .. ": extra " .. tostring(key)) end
    end
    for key in pairs(fields) do
        expectedCount = expectedCount + 1
        if rawget(value, key) == nil then error((message or "not exact table") .. ": missing " .. tostring(key)) end
    end
    if actualCount ~= expectedCount then
        error((message or "not exact table") .. ": key count " .. actualCount .. " ~= " .. expectedCount)
    end
end

local function snapshot(revision, sequence)
    return {
        protocolVersion = 1,
        ready = true,
        sequence = sequence or revision + 1,
        revision = revision,
        survivor = {},
        perks = {},
    }
end

local function requestEnvelope(requestId, perkId, expectedRevision)
    return {
        protocolVersion = 1,
        requestId = requestId,
        perkId = perkId,
        expectedRevision = expectedRevision,
    }
end

local function appliedSessionResult(request, cost, projected)
    return {
        ok = true,
        applied = true,
        requestId = request.requestId,
        perkId = request.perkId,
        apCost = cost,
        mastered = cost == 2,
        snapshot = projected or snapshot(request.expectedRevision + 1),
    }
end

local function rejectionSessionResult(request, code, projected)
    local result = {
        ok = true,
        applied = false,
        requestId = request.requestId,
        perkId = request.perkId,
        code = code,
        detail = "rejected",
    }
    if projected ~= nil then result.snapshot = projected end
    return result
end

local function appliedResponse(requestId, perkId, cost, projected)
    return {
        protocolVersion = 1,
        requestId = requestId,
        perkId = perkId,
        ok = true,
        applied = true,
        apCost = cost,
        mastered = cost == 2,
        snapshot = projected or snapshot(1),
    }
end

local function rejectionResponse(requestId, perkId, code, projected)
    local result = {
        protocolVersion = 1,
        requestId = requestId,
        perkId = perkId,
        ok = true,
        applied = false,
        code = code,
        detail = "rejected",
    }
    if projected ~= nil then result.snapshot = projected end
    return result
end

local function boundaryResponse(requestId, perkId, committed)
    return {
        protocolVersion = 1,
        requestId = requestId,
        perkId = perkId,
        ok = false,
        code = "boundary_failed",
        detail = "unavailable",
        committed = committed,
    }
end

local function makeServer(resultProvider, validatorProvider, senderProvider)
    local trace = {
        player = {},
        requests = {},
        validations = {},
        sends = {},
    }
    local session = {
        request = function(player, request)
            trace.requests[#trace.requests + 1] = { player = player, request = request }
            return resultProvider(request)
        end,
    }
    local validator = validatorProvider or function(value)
        trace.validations[#trace.validations + 1] = value
        return { ok = true, snapshot = value }
    end
    local sender = senderProvider or function(player, module, command, args)
        trace.sends[#trace.sends + 1] = {
            player = player,
            module = module,
            command = command,
            args = args,
        }
    end
    local created = Build42AdvancementTransport.createServer({
        advancementSession = session,
        snapshotValidator = validator,
        sendServerCommand = sender,
    })
    truthy(created.ok, "server construction")
    trace.session = session
    return created.server, trace
end

local function callServer(server, trace, requestId, perkId, revision)
    return server.handle(
        "SurvivorLevelingAdvancement",
        "advancementRequest",
        trace.player,
        requestEnvelope(requestId, perkId, revision)
    )
end

-- Server construction is strict, captures callables, and has no side effects.
do
    local calls, validationCalls = 0, 0
    local session = { request = function(_, request)
        calls = calls + 1
        return appliedSessionResult(request, 1)
    end }
    local validator = function(value)
        validationCalls = validationCalls + 1
        return { ok = true, snapshot = value }
    end
    local senderCalls = 0
    local sender = function() senderCalls = senderCalls + 1 end
    local dependencies = {
        advancementSession = session,
        snapshotValidator = validator,
        sendServerCommand = sender,
    }
    local created = Build42AdvancementTransport.createServer(dependencies)
    truthy(created.ok, "captured server constructed")
    equal(calls, 0, "server construction does not request")
    equal(validationCalls, 0, "server construction does not validate")
    equal(senderCalls, 0, "server construction does not send")

    session.request = function() error("replacement request used") end
    dependencies.snapshotValidator = function() error("replacement validator used") end
    dependencies.sendServerCommand = function() error("replacement sender used") end
    setmetatable(session, {})
    setmetatable(dependencies, {})
    local result = created.server.handle(
        "SurvivorLevelingAdvancement",
        "advancementRequest",
        {},
        requestEnvelope("capture", "Axe", 0)
    )
    truthy(result.ok, "captured server callables remain active")
    equal(calls, 1, "original request callable captured")
    equal(validationCalls, 1, "original validator callable captured")
    equal(senderCalls, 1, "original sender callable captured")

    equal(Build42AdvancementTransport.createServer(nil).code, "invalid_dependencies", "nil server dependencies")
    local invalid = {
        {},
        { advancementSession = session, snapshotValidator = validator },
        { advancementSession = session, snapshotValidator = validator, sendServerCommand = sender, extra = true },
        setmetatable({ advancementSession = session, snapshotValidator = validator, sendServerCommand = sender }, {}),
        { advancementSession = setmetatable({ request = function() end }, {}), snapshotValidator = validator, sendServerCommand = sender },
        { advancementSession = {}, snapshotValidator = validator, sendServerCommand = sender },
        { advancementSession = session, snapshotValidator = {}, sendServerCommand = sender },
        { advancementSession = session, snapshotValidator = validator, sendServerCommand = {} },
    }
    for index = 1, #invalid do
        equal(Build42AdvancementTransport.createServer(invalid[index]).code, "invalid_dependencies", "invalid server dependency " .. index)
    end
end

-- Server ignores unowned commands and rejects nil authority before session invocation.
do
    local server, trace = makeServer(function(request) return appliedSessionResult(request, 1) end)
    local foreign = server.handle("Other", "advancementRequest", trace.player, {})
    truthy(foreign.ok, "foreign module ignored")
    falsy(foreign.handled, "foreign module unhandled")
    local otherCommand = server.handle("SurvivorLevelingAdvancement", "other", trace.player, {})
    truthy(otherCommand.ok, "unowned command ignored")
    falsy(otherCommand.handled, "unowned command unhandled")
    equal(#trace.requests, 0, "ignored commands do not call session")
    equal(#trace.sends, 0, "ignored commands do not send")
    equal(server.handle("SurvivorLevelingAdvancement", "advancementRequest", nil, requestEnvelope("nil", "Axe", 0)).code, "invalid_player", "nil server player")
    equal(#trace.requests, 0, "nil player does not call session")
end

-- Server request allowlist, ASCII bounds, safe integers, and identity privacy.
do
    local server, trace = makeServer(function(request) return appliedSessionResult(request, 1) end)
    equal(server.handle("SurvivorLevelingAdvancement", "advancementRequest", trace.player, nil).code, "invalid_request", "nil server request")
    equal(#trace.requests, 0, "nil request does not call session")
    equal(#trace.sends, 0, "nil request does not send")
    local invalidRequests = {
        {},
        setmetatable(requestEnvelope("meta", "Axe", 0), {}),
        { protocolVersion = 1, requestId = "extra", perkId = "Axe", expectedRevision = 0, player = {} },
        requestEnvelope("version", "Axe", 0),
        requestEnvelope("", "Axe", 0),
        requestEnvelope(string.rep("r", 65), "Axe", 0),
        requestEnvelope("bad space", "Axe", 0),
        requestEnvelope("unicode\195\169", "Axe", 0),
        requestEnvelope("valid", "", 0),
        requestEnvelope("valid", string.rep("p", 129), 0),
        requestEnvelope("valid", "bad/perk", 0),
        requestEnvelope("valid", "unicode\195\169", 0),
        requestEnvelope("valid", "Axe", -1),
        requestEnvelope("valid", "Axe", 0.5),
        requestEnvelope("valid", "Axe", math.huge),
        requestEnvelope("valid", "Axe", 0 / 0),
        requestEnvelope("valid", "Axe", 9007199254740992),
    }
    invalidRequests[4].protocolVersion = 2
    for index = 1, #invalidRequests do
        equal(server.handle("SurvivorLevelingAdvancement", "advancementRequest", trace.player, invalidRequests[index]).code, "invalid_request", "invalid server request " .. index)
        equal(#trace.requests, 0, "invalid request does not call session " .. index)
        equal(#trace.sends, 0, "invalid request does not send " .. index)
    end
    equal(#trace.requests, 0, "invalid requests do not call session")
    equal(#trace.sends, 0, "invalid requests do not send")

    truthy(callServer(server, trace, "safe._:-09", string.rep("P", 128), 9007199254740991).ok, "request bounds accepted")
    equal(#trace.requests, 1, "valid request calls session once")
    local forwarded = trace.requests[1].request
    hasOnly(forwarded, { perkId = true, requestId = true, expectedRevision = true }, "authoritative request privacy")
    equal(trace.requests[1].player, trace.player, "authoritative player identity")
    equal(forwarded.requestId, "safe._:-09", "request identity forwarded")
    equal(forwarded.expectedRevision, 9007199254740991, "safe revision forwarded")
end

-- Applied responses validate once, detach through the validator, and preserve exact effects.
for cost = 1, 2 do
    local sourceSnapshot = snapshot(4)
    local detachedSnapshot = snapshot(4)
    detachedSnapshot.detached = true
    local validatedValue = nil
    local validationCount = 0
    local server, trace = makeServer(
        function(request) return appliedSessionResult(request, cost, sourceSnapshot) end,
        function(value)
            validationCount = validationCount + 1
            validatedValue = value
            return { ok = true, snapshot = detachedSnapshot }
        end
    )
    local handled = callServer(server, trace, "applied" .. cost, "Axe", 3)
    truthy(handled.ok, "applied handled " .. cost)
    truthy(handled.handled, "applied terminal " .. cost)
    equal(#trace.requests, 1, "applied session once " .. cost)
    equal(validationCount, 1, "applied validator once " .. cost)
    equal(validatedValue, sourceSnapshot, "applied validator exact identity " .. cost)
    equal(#trace.sends, 1, "applied send once " .. cost)
    local sent = trace.sends[1]
    equal(sent.player, trace.player, "applied targeted player " .. cost)
    equal(sent.module, "SurvivorLevelingAdvancement", "applied module " .. cost)
    equal(sent.command, "advancementResult", "applied command " .. cost)
    hasOnly(sent.args, {
        protocolVersion = true, requestId = true, perkId = true, ok = true,
        applied = true, apCost = true, mastered = true, snapshot = true,
    }, "applied envelope " .. cost)
    equal(sent.args.apCost, cost, "applied cost " .. cost)
    equal(sent.args.mastered, cost == 2, "applied mastery " .. cost)
    equal(sent.args.snapshot, detachedSnapshot, "only validator copy sent " .. cost)
end

-- Every ordinary C10-U rejection is terminal and only stale may carry a snapshot.
do
    local codes = {
        "store_load_failed", "recovery_quarantined", "invalid_request", "resolver_failed",
        "adapter_description_failed", "adapter_inspection_failed", "adapter_identity_mismatch",
        "perk_quarantined", "observation_failed", "stale_revision", "invalid_state", "no_ap",
        "misaligned_progression", "at_maximum", "red_recovery", "target_rejected",
        "allotment_invalid", "allotment_rejected", "scope_begin_failed", "reservation_save_failed",
        "scope_finish_failed", "engine_mutation_failed", "post_inspection_failed", "commit_save_failed",
    }
    for index = 1, #codes do
        local code = codes[index]
        local server, trace = makeServer(function(request)
            return rejectionSessionResult(request, code)
        end)
        local handled = callServer(server, trace, "reject" .. index, "Axe", 0)
        truthy(handled.ok, "ordinary rejection handled " .. code)
        truthy(handled.handled, "ordinary rejection terminal " .. code)
        equal(#trace.sends, 1, "ordinary rejection sent " .. code)
        equal(trace.sends[1].args.ok, true, "ordinary rejection protocol ok " .. code)
        equal(trace.sends[1].args.applied, false, "ordinary rejection applied false " .. code)
        equal(trace.sends[1].args.code, code, "ordinary rejection code " .. code)
        equal(trace.sends[1].args.snapshot, nil, "ordinary rejection no snapshot " .. code)
        hasOnly(trace.sends[1].args, {
            protocolVersion = true, requestId = true, perkId = true, ok = true,
            applied = true, code = true, detail = true,
        }, "ordinary rejection envelope " .. code)
        equal(#trace.validations, 0, "ordinary rejection no validation " .. code)
    end
end

do
    local projected = snapshot(7)
    local detached = snapshot(7)
    detached.detached = true
    local validatedValue = nil
    local validationCount = 0
    local server, trace = makeServer(function(request)
        return rejectionSessionResult(request, "stale_revision", projected)
    end, function(value)
        validationCount = validationCount + 1
        validatedValue = value
        return { ok = true, snapshot = detached }
    end)
    truthy(callServer(server, trace, "stale", "Axe", 1).ok, "stale snapshot handled")
    equal(validationCount, 1, "stale snapshot validated once")
    equal(validatedValue, projected, "stale validator receives source identity")
    equal(trace.sends[1].args.snapshot, detached, "stale sends detached validator output")
    truthy(trace.sends[1].args.snapshot ~= projected, "stale never sends source snapshot identity")
    hasOnly(trace.sends[1].args, {
        protocolVersion = true, requestId = true, perkId = true, ok = true,
        applied = true, code = true, detail = true, snapshot = true,
    }, "stale rejection envelope with snapshot")

    local noSnapshotServer, noSnapshotTrace = makeServer(function(request)
        return rejectionSessionResult(request, "stale_revision")
    end)
    truthy(callServer(noSnapshotServer, noSnapshotTrace, "stale-none", "Axe", 1).ok, "stale without snapshot handled")
    equal(noSnapshotTrace.sends[1].args.snapshot, nil, "stale snapshot optional")
    hasOnly(noSnapshotTrace.sends[1].args, {
        protocolVersion = true, requestId = true, perkId = true, ok = true,
        applied = true, code = true, detail = true,
    }, "stale rejection envelope without snapshot")
    equal(#noSnapshotTrace.validations, 0, "absent stale snapshot not validated")
end

-- Invalid supplied snapshots become boundary failures with the correct commitment.
for _, stale in ipairs({ false, true }) do
    local validationCalls = 0
    local server, trace = makeServer(
        function(request)
            if stale then return rejectionSessionResult(request, "stale_revision", snapshot(2)) end
            return appliedSessionResult(request, 1, snapshot(2))
        end,
        function()
            validationCalls = validationCalls + 1
            return { ok = false, code = "invalid_snapshot", detail = "bad" }
        end
    )
    truthy(callServer(server, trace, stale and "bad-stale" or "bad-applied", "Axe", 0).ok, "invalid snapshot handled")
    equal(validationCalls, 1, "invalid snapshot validator once")
    equal(trace.sends[1].args.ok, false, "invalid snapshot boundary")
    equal(trace.sends[1].args.code, "snapshot_invalid", "invalid snapshot code")
    equal(trace.sends[1].args.committed, not stale, "invalid snapshot commitment")
end

do
    local validatorCases = {
        function() error("validator threw") end,
        function() return nil end,
        function() return { ok = true } end,
        function() return { ok = true, snapshot = {}, extra = true } end,
        function() return setmetatable({ ok = true, snapshot = {} }, {}) end,
    }
    for index = 1, #validatorCases do
        local server, trace = makeServer(function(request)
            return appliedSessionResult(request, 1)
        end, validatorCases[index])
        truthy(callServer(server, trace, "validator" .. index, "Axe", 0).ok, "validator failure handled " .. index)
        equal(trace.sends[1].args.committed, true, "validator failure committed " .. index)
    end
end

-- Exact server result validation, identity echo, bounds, and commitment inference.
do
    local malformedProviders = {
        function() return nil end,
        function() return {} end,
        function(request) local value = appliedSessionResult(request, 1); value.extra = true; return value end,
        function(request) local value = appliedSessionResult(request, 1); value.requestId = "other"; return value end,
        function(request) local value = appliedSessionResult(request, 1); value.perkId = "Other"; return value end,
        function(request) local value = appliedSessionResult(request, 1); value.mastered = true; return value end,
        function(request) local value = rejectionSessionResult(request, "no_ap", snapshot(1)); return value end,
        function(request) local value = rejectionSessionResult(request, "bad code"); return value end,
        function(request) local value = rejectionSessionResult(request, "no_ap"); value.detail = "bad\nline"; return value end,
        function() return { ok = false, code = "bad code", detail = "failed", committed = false } end,
        function() return { ok = false, code = "failed", detail = "failed", committed = "yes" } end,
    }
    for index = 1, #malformedProviders do
        local server, trace = makeServer(malformedProviders[index])
        truthy(callServer(server, trace, "malformed" .. index, "Axe", 0).ok, "malformed result handled " .. index)
        equal(trace.sends[1].args.ok, false, "malformed result boundary " .. index)
        equal(trace.sends[1].args.code, "session_failed", "malformed result code " .. index)
    end

    local server, trace = makeServer(function(request)
        return setmetatable({
            ok = true,
            applied = true,
            requestId = request.requestId,
            perkId = request.perkId,
            apCost = 1,
            mastered = false,
            snapshot = snapshot(1),
            committed = true,
        }, {})
    end)
    truthy(callServer(server, trace, "meta-commit", "Axe", 0).ok, "metatable result handled")
    equal(trace.sends[1].args.committed, true, "metatable result preserves commitment")

    local mismatchServer, mismatchTrace = makeServer(function(request)
        local result = appliedSessionResult(request, 1)
        result.requestId = "mismatch"
        return result
    end)
    truthy(callServer(mismatchServer, mismatchTrace, "identity", "Axe", 0).ok, "applied identity mismatch handled")
    equal(mismatchTrace.sends[1].args.committed, true, "applied identity mismatch remains committed")
end

-- Exact boundary failures and thrown dependencies preserve known commitment through send failure.
for _, committed in ipairs({ false, true }) do
    local server, trace = makeServer(function()
        return { ok = false, code = "boundary_failed", detail = "unavailable", committed = committed }
    end)
    truthy(callServer(server, trace, "boundary" .. tostring(committed), "Axe", 0).ok, "boundary sent")
    equal(trace.sends[1].args.committed, committed, "boundary commitment echoed")
    hasOnly(trace.sends[1].args, {
        protocolVersion = true, requestId = true, perkId = true, ok = true,
        code = true, detail = true, committed = true,
    }, "boundary failure envelope " .. tostring(committed))
end

do
    local server, trace = makeServer(function() error("session threw") end)
    truthy(callServer(server, trace, "throw", "Axe", 0).ok, "session throw sent")
    equal(trace.sends[1].args.committed, false, "session throw uncommitted")
    equal(trace.sends[1].args.code, "session_failed", "session throw bounded")
end

for _, scenario in ipairs({ "applied", "rejected", "committed_failure", "uncommitted_failure" }) do
    local server, trace = makeServer(
        function(request)
            if scenario == "applied" then return appliedSessionResult(request, 1) end
            if scenario == "rejected" then return rejectionSessionResult(request, "no_ap") end
            return {
                ok = false,
                code = "boundary_failed",
                detail = "unavailable",
                committed = scenario == "committed_failure",
            }
        end,
        nil,
        function() error("send threw") end
    )
    local result = callServer(server, trace, "send-" .. scenario, "Axe", 0)
    equal(result.code, "send_failed", "send throw code " .. scenario)
    equal(result.committed, scenario == "applied" or scenario == "committed_failure", "send throw commitment " .. scenario)
end

local function makeClient(options)
    options = options or {}
    local trace = { gets = {}, accepts = {}, sends = {} }
    local owner = {
        get = options.get or function(localSlot)
            trace.gets[#trace.gets + 1] = localSlot
            return { ok = true, present = true, snapshot = snapshot(localSlot) }
        end,
        acceptLocal = options.accept or function(localSlot, value)
            trace.accepts[#trace.accepts + 1] = { localSlot = localSlot, snapshot = value }
            return { ok = true, accepted = true }
        end,
    }
    local sender = options.send or function(player, module, command, args)
        trace.sends[#trace.sends + 1] = {
            player = player,
            module = module,
            command = command,
            args = args,
        }
    end
    local dependencies = { ownerClient = owner, sendClientCommand = sender }
    local created = Build42AdvancementTransport.createClient(dependencies)
    truthy(created.ok, "client construction")
    trace.owner = owner
    trace.dependencies = dependencies
    return created.client, trace
end

-- Client construction is strict, side-effect-free, and captures callables.
do
    local getCalls, acceptCalls, sendCalls = 0, 0, 0
    local owner = {
        get = function()
            getCalls = getCalls + 1
            return { ok = true, present = true, snapshot = snapshot(0) }
        end,
        acceptLocal = function()
            acceptCalls = acceptCalls + 1
            return { ok = true, accepted = true }
        end,
    }
    local sender = function() sendCalls = sendCalls + 1 end
    local dependencies = { ownerClient = owner, sendClientCommand = sender }
    local created = Build42AdvancementTransport.createClient(dependencies)
    truthy(created.ok, "captured client constructed")
    equal(getCalls, 0, "client construction does not read owner")
    equal(acceptCalls, 0, "client construction does not accept")
    equal(sendCalls, 0, "client construction does not send")

    owner.get = function() error("replacement get used") end
    owner.acceptLocal = function() error("replacement accept used") end
    dependencies.sendClientCommand = function() error("replacement sender used") end
    setmetatable(owner, {})
    setmetatable(dependencies, {})
    local requested = created.client.request(0, {}, "Axe")
    truthy(requested.ok, "captured client request")
    equal(getCalls, 1, "original get captured")
    equal(sendCalls, 1, "original sender captured")
    truthy(created.client.handle(
        "SurvivorLevelingAdvancement",
        "advancementResult",
        appliedResponse(requested.requestId, "Axe", 1)
    ).ok, "captured accept handled")
    equal(acceptCalls, 1, "original accept captured")

    equal(Build42AdvancementTransport.createClient(nil).code, "invalid_dependencies", "nil client dependencies")
    local invalid = {
        {},
        { ownerClient = owner },
        { ownerClient = owner, sendClientCommand = sender, extra = true },
        setmetatable({ ownerClient = owner, sendClientCommand = sender }, {}),
        { ownerClient = setmetatable({ get = function() end, acceptLocal = function() end }, {}), sendClientCommand = sender },
        { ownerClient = { get = function() end }, sendClientCommand = sender },
        { ownerClient = owner, sendClientCommand = {} },
    }
    for index = 1, #invalid do
        equal(Build42AdvancementTransport.createClient(invalid[index]).code, "invalid_dependencies", "invalid client dependency " .. index)
    end
end

-- A malformed inbox result for stale state retains the authoritative rejection alongside the local failure.
do
    local client = makeClient({ accept = function() return { ok = true } end })
    local requested = client.request(0, {}, "Axe")
    local handled = client.handle(
        "SurvivorLevelingAdvancement",
        "advancementResult",
        rejectionResponse(requested.requestId, "Axe", "stale_revision", snapshot(4))
    )
    truthy(handled.ok, "stale malformed inbox remains terminal")
    hasOnly(handled, { ok = true, handled = true, localSlot = true, result = true }, "stale snapshot-rejected handle shape")
    hasOnly(handled.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true, committed = true,
        upstreamCode = true, upstreamDetail = true,
    }, "stale snapshot-rejected result shape")
    equal(handled.result.code, "snapshot_rejected", "stale malformed inbox local code")
    equal(handled.result.upstreamCode, "stale_revision", "stale malformed inbox upstream code")
    equal(handled.result.upstreamDetail, "rejected", "stale malformed inbox upstream detail")
    equal(handled.result.requestId, requested.requestId, "stale malformed inbox request ID")
    equal(handled.result.perkId, "Axe", "stale malformed inbox perk")
    equal(handled.result.committed, false, "stale malformed inbox uncommitted")
    local status = client.status(0)
    hasOnly(status, { ok = true, pending = true, result = true }, "stale snapshot-rejected status shape")
    hasOnly(status.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true, committed = true,
        upstreamCode = true, upstreamDetail = true,
    }, "stale snapshot-rejected status result shape")
end

-- Client request derives revision once, preserves player identity, and sends the exact private envelope.
do
    local client, trace = makeClient()
    local player = {}
    local requested = client.request(2, player, string.rep("P", 128))
    truthy(requested.ok, "client request accepted")
    equal(#trace.gets, 1, "owner read once")
    equal(trace.gets[1], 2, "owner slot exact")
    equal(#trace.sends, 1, "client send once")
    equal(trace.sends[1].player, player, "client player exact")
    equal(trace.sends[1].module, "SurvivorLevelingAdvancement", "client module")
    equal(trace.sends[1].command, "advancementRequest", "client command")
    hasOnly(trace.sends[1].args, {
        protocolVersion = true, requestId = true, perkId = true, expectedRevision = true,
    }, "client request privacy")
    equal(trace.sends[1].args.expectedRevision, 2, "revision from owner snapshot")
    equal(trace.sends[1].args.requestId, requested.requestId, "request ID echo")
    local pendingStatus = client.status(2)
    hasOnly(pendingStatus, {
        ok = true, pending = true, requestId = true, perkId = true,
    }, "pending status shape")
    equal(pendingStatus.requestId, requested.requestId, "pending status ID")
    equal(pendingStatus.perkId, string.rep("P", 128), "pending status perk")
end

-- Invalid request inputs do not read owner state or send.
do
    local client, trace = makeClient()
    local cases = {
        { -1, {}, "Axe" }, { 4, {}, "Axe" }, { 0.5, {}, "Axe" },
        { 0 / 0, {}, "Axe" }, { 0, nil, "Axe" }, { 0, {}, "" },
        { 0, {}, string.rep("p", 129) }, { 0, {}, "bad/perk" }, { 0, {}, "unicode\195\169" },
    }
    for index = 1, #cases do
        equal(client.request(cases[index][1], cases[index][2], cases[index][3]).code, "invalid_request", "invalid client request " .. index)
    end
    equal(#trace.gets, 0, "invalid client requests do not read owner")
    equal(#trace.sends, 0, "invalid client requests do not send")
    equal(client.status(-1).code, "invalid_slot", "status rejects low slot")
    equal(client.status(4).code, "invalid_slot", "status rejects high slot")
end

-- Owner read failures and malformed/not-ready snapshots fail before allocation/send.
do
    local ownerCases = {
        function() error("get threw") end,
        function() return nil end,
        function() return { ok = true } end,
        function() return { ok = true, present = false, extra = true } end,
        function() return { ok = true, present = false } end,
        function() return { ok = true, present = true, snapshot = {} } end,
        function() return { ok = true, present = true, snapshot = { ready = false, revision = 0 } } end,
        function() return { ok = true, present = true, snapshot = { ready = true, revision = -1 } } end,
        function() return { ok = true, present = true, snapshot = { ready = true, revision = 0.5 } } end,
        function() return { ok = true, present = true, snapshot = { ready = true, revision = math.huge } } end,
        function() return { ok = true, present = true, snapshot = setmetatable({ ready = true, revision = 0 }, {}) } end,
    }
    for index = 1, #ownerCases do
        local client, trace = makeClient({ get = ownerCases[index] })
        local result = client.request(0, {}, "Axe")
        truthy(result.ok == false, "owner case fails " .. index)
        equal(#trace.sends, 0, "owner case does not send " .. index)
        falsy(client.status(0).pending, "owner case leaves no pending " .. index)
    end
end

-- Four slots isolate one pending request each; request IDs are process-monotone and unique.
do
    local client, trace = makeClient()
    local ids = {}
    for localSlot = 0, 3 do
        local requested = client.request(localSlot, {}, "Perk" .. localSlot)
        truthy(requested.ok, "slot request " .. localSlot)
        ids[localSlot] = requested.requestId
        equal(client.request(localSlot, {}, "Again").code, "pending_request", "single pending " .. localSlot)
    end
    equal(#trace.sends, 4, "four isolated sends")
    for left = 0, 3 do
        for right = left + 1, 3 do
            truthy(ids[left] ~= ids[right], "unique IDs " .. left .. "/" .. right)
        end
    end
    truthy(client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(ids[2], "Perk2", "no_ap")).ok, "slot two terminal")
    falsy(client.status(2).pending, "slot two consumed")
    truthy(client.status(0).pending, "slot zero remains pending")
    truthy(client.status(1).pending, "slot one remains pending")
    truthy(client.status(3).pending, "slot three remains pending")
end

-- Applied responses update the owner once and retain complete detached summaries.
for cost = 1, 2 do
    local client, trace = makeClient()
    local requested = client.request(0, {}, "Axe")
    local handled = client.handle(
        "SurvivLevelingAdvancement",
        "advancementResult",
        appliedResponse(requested.requestId, "Axe", cost)
    )
    falsy(handled.handled == true, "misspelled module ignored " .. cost)
    truthy(client.status(0).pending, "ignored response retains route " .. cost)

    handled = client.handle(
        "SurvivorLevelingAdvancement",
        "advancementResult",
        appliedResponse(requested.requestId, "Axe", cost)
    )
    truthy(handled.ok, "applied client handled " .. cost)
    truthy(handled.handled, "applied client terminal " .. cost)
    hasOnly(handled, { ok = true, handled = true, localSlot = true, result = true }, "applied handle shape " .. cost)
    equal(handled.localSlot, 0, "applied terminal returns validated local slot " .. cost)
    hasOnly(handled.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        apCost = true, mastered = true, snapshotAccepted = true,
    }, "applied result shape " .. cost)
    equal(#trace.accepts, 1, "applied owner accept once " .. cost)
    equal(trace.accepts[1].localSlot, 0, "applied owner slot " .. cost)
    equal(handled.result.apCost, cost, "handled applied cost " .. cost)
    equal(handled.result.mastered, cost == 2, "handled applied mastery " .. cost)
    truthy(handled.result.snapshotAccepted, "handled snapshot accepted " .. cost)

    handled.result.apCost = 99
    local status = client.status(0)
    hasOnly(status, { ok = true, pending = true, result = true }, "applied status shape " .. cost)
    hasOnly(status.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        apCost = true, mastered = true, snapshotAccepted = true,
    }, "applied status result shape " .. cost)
    equal(status.result.apCost, cost, "handle result detached " .. cost)
    status.result.apCost = 88
    equal(client.status(0).result.apCost, cost, "status result detached " .. cost)
    equal(client.handle("SurvivorLevelingAdvancement", "advancementResult", appliedResponse(requested.requestId, "Axe", cost)).code, "unknown_response", "applied replay rejected " .. cost)
end

-- An ahead owner inbox leaves the AP outcome terminal without lowering state.
do
    local acceptedCalls = 0
    local client = makeClient({
        accept = function()
            acceptedCalls = acceptedCalls + 1
            return { ok = true, accepted = false, code = "stale_snapshot" }
        end,
    })
    local requested = client.request(0, {}, "Axe")
    local handled = client.handle("SurvivorLevelingAdvancement", "advancementResult", appliedResponse(requested.requestId, "Axe", 1))
    truthy(handled.ok, "ahead inbox handled")
    hasOnly(handled.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        apCost = true, mastered = true, snapshotAccepted = true, snapshotCode = true,
    }, "ahead inbox result shape")
    truthy(handled.result.applied, "ahead inbox preserves applied")
    falsy(handled.result.snapshotAccepted, "ahead inbox does not replace")
    equal(handled.result.snapshotCode, "stale_snapshot", "ahead inbox reason")
    equal(acceptedCalls, 1, "ahead inbox called once")
    local status = client.status(0)
    hasOnly(status, { ok = true, pending = true, result = true }, "ahead inbox status shape")
    hasOnly(status.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        apCost = true, mastered = true, snapshotAccepted = true, snapshotCode = true,
    }, "ahead inbox status result shape")

    local staleRequest = client.request(1, {}, "Axe")
    local staleHandled = client.handle(
        "SurvivorLevelingAdvancement",
        "advancementResult",
        rejectionResponse(staleRequest.requestId, "Axe", "stale_revision", snapshot(2))
    )
    truthy(staleHandled.ok, "ahead inbox stale handled")
    hasOnly(staleHandled.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true, snapshotAccepted = true, snapshotCode = true,
    }, "ahead inbox stale result shape")
    falsy(staleHandled.result.snapshotAccepted, "ahead inbox stale does not replace")
    equal(staleHandled.result.snapshotCode, "stale_snapshot", "ahead inbox stale reason")
    local staleStatus = client.status(1)
    hasOnly(staleStatus, { ok = true, pending = true, result = true }, "ahead inbox stale status shape")
    hasOnly(staleStatus.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true, snapshotAccepted = true, snapshotCode = true,
    }, "ahead inbox stale status result shape")
end

-- Ordinary and stale rejections have exact inbox and terminal behavior.
do
    local client, trace = makeClient()
    local ordinary = client.request(0, {}, "Axe")
    local handled = client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(ordinary.requestId, "Axe", "no_ap"))
    truthy(handled.ok, "ordinary rejection handled")
    hasOnly(handled, { ok = true, handled = true, localSlot = true, result = true }, "ordinary rejection handle shape")
    hasOnly(handled.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true,
    }, "ordinary rejection result shape")
    falsy(handled.result.applied, "ordinary rejection not applied")
    equal(handled.result.code, "no_ap", "ordinary rejection code")
    local ordinaryStatus = client.status(0)
    hasOnly(ordinaryStatus, { ok = true, pending = true, result = true }, "ordinary rejection status shape")
    hasOnly(ordinaryStatus.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true,
    }, "ordinary rejection status result shape")
    equal(#trace.accepts, 0, "ordinary rejection does not enter inbox")

    local stale = client.request(1, {}, "Axe")
    handled = client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(stale.requestId, "Axe", "stale_revision", snapshot(3)))
    truthy(handled.ok, "stale rejection handled")
    hasOnly(handled.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true, snapshotAccepted = true,
    }, "stale rejection result shape")
    falsy(handled.result.applied, "stale rejection not applied")
    truthy(handled.result.snapshotAccepted, "stale snapshot accepted")
    local staleStatus = client.status(1)
    hasOnly(staleStatus, { ok = true, pending = true, result = true }, "stale rejection status shape")
    hasOnly(staleStatus.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true, snapshotAccepted = true,
    }, "stale rejection status result shape")
    equal(#trace.accepts, 1, "stale snapshot enters inbox once")

    local staleWithout = client.request(2, {}, "Axe")
    handled = client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(staleWithout.requestId, "Axe", "stale_revision"))
    truthy(handled.ok, "stale without snapshot handled")
    hasOnly(handled.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true,
    }, "stale without snapshot result shape")
    equal(handled.result.snapshotAccepted, nil, "stale without snapshot has no acceptance field")
    local staleWithoutStatus = client.status(2)
    hasOnly(staleWithoutStatus, { ok = true, pending = true, result = true }, "stale without snapshot status shape")
    hasOnly(staleWithoutStatus.result, {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true,
    }, "stale without snapshot status result shape")
    equal(#trace.accepts, 1, "stale without snapshot does not enter inbox")
end

-- Client fails closed on malformed envelopes without consuming routes.
do
    local client = makeClient()
    local requested = client.request(0, {}, "Axe")
    local baseApplied = appliedResponse(requested.requestId, "Axe", 1)
    equal(client.handle("SurvivorLevelingAdvancement", "advancementResult", nil).code, "invalid_response", "nil response")
    local invalid = {
        {},
        setmetatable(appliedResponse(requested.requestId, "Axe", 1), {}),
        { protocolVersion = 1, requestId = requested.requestId, perkId = "Axe", ok = true, applied = true, apCost = 1, mastered = false, snapshot = {}, extra = true },
        { protocolVersion = 2, requestId = requested.requestId, perkId = "Axe", ok = true, applied = true, apCost = 1, mastered = false, snapshot = {} },
        { protocolVersion = 1, requestId = "bad id", perkId = "Axe", ok = true, applied = true, apCost = 1, mastered = false, snapshot = {} },
        { protocolVersion = 1, requestId = requested.requestId, perkId = "unicode\195\169", ok = true, applied = true, apCost = 1, mastered = false, snapshot = {} },
        { protocolVersion = 1, requestId = requested.requestId, perkId = "Axe", ok = true, applied = true, apCost = 1, mastered = true, snapshot = {} },
        { protocolVersion = 1, requestId = requested.requestId, perkId = "Axe", ok = true, applied = false, code = "no_ap", detail = "none", snapshot = {} },
        { protocolVersion = 1, requestId = requested.requestId, perkId = "Axe", ok = true, applied = false, code = "bad code", detail = "none" },
        { protocolVersion = 1, requestId = requested.requestId, perkId = "Axe", ok = true, applied = false, code = "no_ap", detail = "bad\nline" },
        { protocolVersion = 1, requestId = requested.requestId, perkId = "Axe", ok = false, code = "failed", detail = "bad", committed = "yes" },
    }
    equal(baseApplied.ok, true, "valid base fixture")
    for index = 1, #invalid do
        equal(client.handle("SurvivorLevelingAdvancement", "advancementResult", invalid[index]).code, "invalid_response", "invalid response " .. index)
        truthy(client.status(0).pending, "invalid response preserves route " .. index)
    end
end

-- Unknown IDs and mismatched perks preserve the live route; valid completion consumes it once.
do
    local client = makeClient()
    local requested = client.request(0, {}, "Axe")
    equal(client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse("unknown", "Axe", "no_ap")).code, "unknown_response", "unknown request ID")
    truthy(client.status(0).pending, "unknown ID preserves pending")
    equal(client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(requested.requestId, "Blade", "no_ap")).code, "unknown_response", "mismatched perk")
    truthy(client.status(0).pending, "mismatched perk preserves pending")
    truthy(client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(requested.requestId, "Axe", "no_ap")).ok, "matching response terminal")
    equal(client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(requested.requestId, "Axe", "no_ap")).code, "unknown_response", "terminal response cannot replay")
end

-- Boundary responses bypass the owner inbox and retain complete detached commitment status.
for _, committed in ipairs({ false, true }) do
    local client, trace = makeClient()
    local requested = client.request(0, {}, "Axe")
    local handled = client.handle("SurvivorLevelingAdvancement", "advancementResult", boundaryResponse(requested.requestId, "Axe", committed))
    truthy(handled.ok, "boundary client handled")
    truthy(handled.handled, "boundary client terminal")
    hasOnly(handled, { ok = true, handled = true, localSlot = true, result = true }, "boundary handle shape")
    hasOnly(handled.result, {
        ok = true, requestId = true, perkId = true,
        code = true, detail = true, committed = true,
    }, "boundary result shape")
    equal(handled.result.ok, false, "boundary summary ok false")
    equal(handled.result.requestId, requested.requestId, "boundary summary ID")
    equal(handled.result.perkId, "Axe", "boundary summary perk")
    equal(handled.result.committed, committed, "boundary summary commitment")
    equal(#trace.accepts, 0, "boundary does not enter inbox")
    handled.result.committed = not committed
    local status = client.status(0)
    hasOnly(status, { ok = true, pending = true, result = true }, "boundary status shape")
    hasOnly(status.result, {
        ok = true, requestId = true, perkId = true,
        code = true, detail = true, committed = true,
    }, "boundary status result shape")
    equal(status.result.committed, committed, "boundary handle detached")
end

-- Thrown, failed, and malformed inbox outcomes become complete terminal snapshot failures.
do
    local acceptanceCases = {
        function() error("accept threw") end,
        function() return nil end,
        function() return { ok = true } end,
        function() return { ok = true, accepted = false, code = "wrong" } end,
        function() return { ok = false, code = "bad", detail = "bad" } end,
        function() return { ok = true, accepted = true, extra = true } end,
        function() return setmetatable({ ok = true, accepted = true }, {}) end,
    }
    for index = 1, #acceptanceCases do
        local client = makeClient({ accept = acceptanceCases[index] })
        local requested = client.request(0, {}, "Axe")
        local handled = client.handle("SurvivorLevelingAdvancement", "advancementResult", appliedResponse(requested.requestId, "Axe", 2))
        truthy(handled.ok, "invalid inbox result remains handled " .. index)
        hasOnly(handled, { ok = true, handled = true, localSlot = true, result = true }, "applied snapshot-rejected handle shape " .. index)
        hasOnly(handled.result, {
            ok = true, applied = true, requestId = true, perkId = true,
            code = true, detail = true, committed = true, apCost = true, mastered = true,
        }, "applied snapshot-rejected result shape " .. index)
        equal(handled.result.ok, false, "invalid inbox summary boundary " .. index)
        equal(handled.result.code, "snapshot_rejected", "invalid inbox summary code " .. index)
        equal(handled.result.requestId, requested.requestId, "invalid inbox summary ID " .. index)
        equal(handled.result.perkId, "Axe", "invalid inbox summary perk " .. index)
        equal(handled.result.apCost, 2, "invalid inbox summary cost " .. index)
        truthy(handled.result.mastered, "invalid inbox summary mastery " .. index)
        truthy(handled.result.committed, "invalid inbox summary commitment " .. index)
        local status = client.status(0)
        hasOnly(status, { ok = true, pending = true, result = true }, "applied snapshot-rejected status shape " .. index)
        hasOnly(status.result, {
            ok = true, applied = true, requestId = true, perkId = true,
            code = true, detail = true, committed = true, apCost = true, mastered = true,
        }, "applied snapshot-rejected status result shape " .. index)
        falsy(status.pending, "invalid inbox consumes route " .. index)
    end
end

-- Send failure is terminal locally, clears pending state, and remains visible in detached status.
do
    local client = makeClient({ send = function() error("send threw") end })
    local failed = client.request(0, {}, "Axe")
    hasOnly(failed, { ok = true, code = true, detail = true, committed = true }, "client send failure return shape")
    equal(failed.code, "send_failed", "client send throw")
    equal(failed.committed, false, "client send throw uncommitted")
    local status = client.status(0)
    hasOnly(status, { ok = true, pending = true, result = true }, "client send failure status shape")
    hasOnly(status.result, {
        ok = true, requestId = true, perkId = true,
        code = true, detail = true, committed = true,
    }, "client send failure result shape")
    falsy(status.pending, "client send failure clears pending")
    equal(status.result.code, "send_failed", "client send failure status")
    equal(status.result.requestId ~= nil, true, "client send failure retains request ID")
    status.result.code = "mutated"
    equal(client.status(0).result.code, "send_failed", "client send failure status detached")
end

-- Reset operations clear only intended routes/results and preserve process-monotone IDs.
do
    local client = makeClient()
    local first = client.request(0, {}, "Axe")
    local second = client.request(1, {}, "Blade")
    truthy(client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(first.requestId, "Axe", "no_ap")).ok, "slot zero terminal before reset")
    truthy(client.resetSlot(0).ok, "reset slot zero")
    local emptyStatus = client.status(0)
    hasOnly(emptyStatus, { ok = true, pending = true }, "empty status shape")
    falsy(emptyStatus.pending, "reset slot clears result")
    equal(emptyStatus.result, nil, "reset slot removes terminal")
    truthy(client.status(1).pending, "reset slot preserves other route")
    equal(client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(first.requestId, "Axe", "no_ap")).code, "unknown_response", "reset slot route gone")

    truthy(client.reset().ok, "reset all")
    falsy(client.status(1).pending, "reset all clears route")
    equal(client.handle("SurvivorLevelingAdvancement", "advancementResult", rejectionResponse(second.requestId, "Blade", "no_ap")).code, "unknown_response", "reset all route gone")
    local afterReset = client.request(0, {}, "Axe")
    truthy(afterReset.ok, "request after reset")
    truthy(afterReset.requestId ~= first.requestId and afterReset.requestId ~= second.requestId, "reset preserves monotone counter")
    equal(client.resetSlot(-1).code, "invalid_slot", "reset slot validates low")
    equal(client.resetSlot(4).code, "invalid_slot", "reset slot validates high")
end

return assertions
