local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed") end
end

local function expectEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual))) end
end

local function failure(result, code, detail)
    expectEqual(result.ok, false, "failure expected")
    expectEqual(result.code, code, "failure code")
    expectEqual(result.detail, detail, "failure detail")
    expectEqual(result.snapshot, nil, "failure does not expose snapshot")
end

local function dependency(code, detail)
    return (code or "unavailable") .. ":" .. (detail or "unavailable")
end

local function sequenceEquals(actual, expected, message)
    expectEqual(#actual, #expected, (message or "sequence") .. " length")
    for index = 1, #expected do expectEqual(actual[index], expected[index], (message or "sequence") .. " item " .. index) end
end

local function contains(value, sought, seen)
    if value == sought then return true end
    if type(value) ~= "table" then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, child in pairs(value) do
        if contains(key, sought, seen) or contains(child, sought, seen) then return true end
    end
    return false
end

local function fixture(overrides)
    local calls, loads = {}, {}
    local state = { revision = 3, survivor = { private = "private survivor" }, perks = { Axe = { private = "private perk" } }, private = "private root" }
    local recoveredState = { revision = 4, survivor = {}, perks = {}, private = "recovered private" }
    local options = { loadedPerks = { Axe = { private = "compatibility" } } }
    local perks = { { id = "Axe" }, { id = "Fitness" } }
    local player = {}
    local store = {
        load = function(actualPlayer, actualOptions)
            calls[#calls + 1] = "load"
            loads[#loads + 1] = { player = actualPlayer, options = actualOptions }
            return { ok = true, state = state }
        end,
    }
    local recovery = {
        recoverLoadedState = function(actualPlayer, actualState)
            calls[#calls + 1] = "recover"
            expectEqual(actualPlayer, player, "recovery player identity")
            expectEqual(actualState, state, "recovery loaded-state identity")
            return { ok = true, state = recoveredState, recovered = true, private = "private recovery" }
        end,
    }
    local catalog = {
        resolver = { loadOptions = options },
        allPerks = function()
            calls[#calls + 1] = "catalog"
            return { ok = true, perks = perks }
        end,
    }
    local xpSource = {
        initializePlayer = function(actualPlayer, actualPerks)
            calls[#calls + 1] = "initialize"
            expectEqual(actualPlayer, player, "initialize player identity")
            expectEqual(actualPerks, perks, "catalog perk-list identity")
            return { ok = true, detail = { initialized = 1, skipped = 1, private = "private source" } }
        end,
    }
    local ownerSnapshot = {
        project = function(actualState, sequence, ready)
            calls[#calls + 1] = "project"
            return { ok = true, snapshot = { protocolVersion = 1, sequence = sequence, ready = ready, revision = actualState.revision, privateInput = actualState.private } }
        end,
    }
    local dependencies = { store = store, recoveryService = recovery, catalog = catalog, xpSource = xpSource, ownerSnapshot = ownerSnapshot }
    if overrides then overrides(dependencies, { calls = calls, loads = loads, state = state, recoveredState = recoveredState, options = options, perks = perks, player = player, store = store, recovery = recovery, catalog = catalog, xpSource = xpSource, ownerSnapshot = ownerSnapshot }) end
    local created = OwnerSession.create(dependencies)
    expectEqual(created.ok, true, "session creates")
    return created.session, dependencies, { calls = calls, loads = loads, state = state, recoveredState = recoveredState, options = options, perks = perks, player = player, store = store, recovery = recovery, catalog = catalog, xpSource = xpSource, ownerSnapshot = ownerSnapshot }
end

failure(OwnerSession.create(nil), "invalid_dependencies", "dependencies must be a table")
failure(OwnerSession.create({}), "invalid_dependencies", "store.load is required")
failure(OwnerSession.create({ store = { load = function() end } }), "invalid_dependencies", "recoveryService.recoverLoadedState is required")
failure(OwnerSession.create({ store = { load = function() end }, recoveryService = { recoverLoadedState = function() end } }), "invalid_dependencies", "catalog capabilities are required")
failure(OwnerSession.create({ store = { load = function() end }, recoveryService = { recoverLoadedState = function() end }, catalog = { allPerks = function() end, resolver = { loadOptions = {} } } }), "invalid_dependencies", "xpSource.initializePlayer is required")
failure(OwnerSession.create({ store = { load = function() end }, recoveryService = { recoverLoadedState = function() end }, catalog = { allPerks = function() end, resolver = { loadOptions = {} } }, xpSource = { initializePlayer = function() end } }), "invalid_dependencies", "ownerSnapshot.project is required")

do
    local session, _, values = fixture()
    failure(session.snapshot(values.player), "not_ready", "ready has not succeeded")
    expectEqual(#values.calls, 0, "not-ready snapshot does no work")
    expectEqual(session.isReady(values.player), false, "not-ready state")
    local ready = session.ready(values.player)
    expectEqual(ready.ok, true, "ready succeeds")
    sequenceEquals(values.calls, { "load", "recover", "catalog", "initialize", "project" }, "ready order")
    expectEqual(values.loads[1].player, values.player, "store player identity")
    expectEqual(values.loads[1].options, values.options, "compatibility options identity")
    expectEqual(ready.snapshot.sequence, 1, "first sequence")
    expectEqual(ready.snapshot.ready, true, "ready projection")
    expectEqual(ready.recovered, true, "recovery count")
    expectEqual(ready.initialized, 1, "initialized count")
    expectEqual(ready.skipped, 1, "skipped count")
    expect(not contains(ready, values.state) and not contains(ready, values.recoveredState) and not contains(ready, "private root") and not contains(ready, "private recovery") and not contains(ready, "compatibility"), "ready result is private")
    local snapshot = session.snapshot(values.player)
    expectEqual(snapshot.ok, true, "subsequent snapshot succeeds")
    sequenceEquals(values.calls, { "load", "recover", "catalog", "initialize", "project", "load", "project" }, "subsequent snapshot only loads and projects")
    expectEqual(values.loads[2].options, values.options, "subsequent load option identity")
    expectEqual(snapshot.snapshot.sequence, 2, "subsequent sequence")
    expectEqual(snapshot.recovered, nil, "subsequent result has no recovery field")
    expectEqual(snapshot.initialized, nil, "subsequent result has no initialization field")
end

do
    local session, _, values = fixture()
    local first = session.ready(values.player)
    local replay = session.ready(values.player)
    expectEqual(first.snapshot.sequence, 1, "first ready sequence")
    expectEqual(replay.snapshot.sequence, 2, "replay rebase gets new sequence")
    sequenceEquals(values.calls, { "load", "recover", "catalog", "initialize", "project", "load", "recover", "catalog", "initialize", "project" }, "replay repeats safe rebase")
    local cleared = session.clearPlayer(values.player)
    expectEqual(cleared.ok, true, "clear reports success")
    expectEqual(cleared.snapshot, nil, "clear has no snapshot")
    expectEqual(session.isReady(values.player), false, "clear forgets readiness")
    failure(session.snapshot(values.player), "not_ready", "ready has not succeeded")
    local rerun = session.ready(values.player)
    expectEqual(rerun.snapshot.sequence, 1, "clear restarts sequence")
end

local function assertReadyFailure(name, configure, code, detail, expectedCalls)
    local session, _, values = fixture(configure)
    local result = session.ready(values.player)
    failure(result, code, detail)
    expectEqual(session.isReady(values.player), false, name .. " does not commit readiness")
    sequenceEquals(values.calls, expectedCalls, name .. " stops flow")
end

assertReadyFailure("load explicit failure", function(dependencies) dependencies.store.load = function() return { ok = false, code = "load_unavailable", detail = "temporary" } end end, "store_load_failed", dependency("load_unavailable", "temporary"), {})
assertReadyFailure("load unsafe diagnostic", function(dependencies) dependencies.store.load = function() return { ok = false, code = "unsafe code", detail = "bad\nvalue" } end end, "store_load_failed", dependency(), {})
assertReadyFailure("load throw", function(dependencies) dependencies.store.load = function() error("leak") end end, "store_load_threw", "dependency threw", {})
assertReadyFailure("load malformed", function(dependencies) dependencies.store.load = function() return { ok = true, state = "not-state" } end end, "store_load_invalid", "store.load", {})
assertReadyFailure("recovery explicit failure", function(dependencies) dependencies.recoveryService.recoverLoadedState = function() return { ok = false, code = "recovery_quarantined", detail = "reservation_state_inconsistent" } end end, "recovery_failed", dependency("recovery_quarantined", "reservation_state_inconsistent"), { "load" })
assertReadyFailure("recovery malformed", function(dependencies) dependencies.recoveryService.recoverLoadedState = function() return { ok = true, state = {}, recovered = "yes" } end end, "recovery_invalid", "recoveryService.recoverLoadedState", { "load" })
assertReadyFailure("catalog failure", function(dependencies) dependencies.catalog.allPerks = function() return { ok = false } end end, "catalog_failed", dependency(), { "load", "recover" })
assertReadyFailure("catalog sparse", function(dependencies) dependencies.catalog.allPerks = function() return { ok = true, perks = { [2] = {} } } end end, "catalog_invalid", "catalog.allPerks", { "load", "recover" })
assertReadyFailure("initialize failure", function(dependencies) dependencies.xpSource.initializePlayer = function() return { ok = false } end end, "xp_initialize_failed", dependency(), { "load", "recover", "catalog" })
assertReadyFailure("initialize malformed", function(dependencies) dependencies.xpSource.initializePlayer = function() return { ok = true, detail = { initialized = 1 } } end end, "xp_initialize_invalid", "xpSource.initializePlayer", { "load", "recover", "catalog" })
assertReadyFailure("initialize incomplete counts", function(dependencies) dependencies.xpSource.initializePlayer = function() return { ok = true, detail = { initialized = 1, skipped = 0 } } end end, "xp_initialize_invalid", "xpSource.initializePlayer", { "load", "recover", "catalog" })
assertReadyFailure("projection failure", function(dependencies) dependencies.ownerSnapshot.project = function() return { ok = false } end end, "snapshot_failed", dependency(), { "load", "recover", "catalog", "initialize" })
assertReadyFailure("projection malformed", function(dependencies) dependencies.ownerSnapshot.project = function() return { ok = true, snapshot = "bad" } end end, "snapshot_invalid", "ownerSnapshot.project", { "load", "recover", "catalog", "initialize" })
assertReadyFailure("projection protocol mismatch", function(dependencies) dependencies.ownerSnapshot.project = function(_, sequence) return { ok = true, snapshot = { protocolVersion = 2, ready = true, sequence = sequence } } end end, "snapshot_invalid", "ownerSnapshot.project", { "load", "recover", "catalog", "initialize" })
assertReadyFailure("projection readiness mismatch", function(dependencies) dependencies.ownerSnapshot.project = function(_, sequence) return { ok = true, snapshot = { protocolVersion = 1, ready = false, sequence = sequence } } end end, "snapshot_invalid", "ownerSnapshot.project", { "load", "recover", "catalog", "initialize" })
assertReadyFailure("projection sequence mismatch", function(dependencies) dependencies.ownerSnapshot.project = function(_, sequence) return { ok = true, snapshot = { protocolVersion = 1, ready = true, sequence = sequence + 1 } } end end, "snapshot_invalid", "ownerSnapshot.project", { "load", "recover", "catalog", "initialize" })

do
    local session, _, values = fixture()
    expectEqual(session.ready(values.player).ok, true, "ready before snapshot failures")
    values.store.load = function() return { ok = false } end
    failure(session.snapshot(values.player), "store_load_failed", dependency())
    expectEqual(session.isReady(values.player), true, "failed subsequent snapshot preserves readiness")
    values.store.load = function() return { ok = true, state = values.state } end
    values.ownerSnapshot.project = function() return { ok = false } end
    failure(session.snapshot(values.player), "snapshot_failed", dependency())
    values.ownerSnapshot.project = function(_, sequence) return { ok = true, snapshot = { protocolVersion = 1, ready = true, sequence = sequence } } end
    expectEqual(session.snapshot(values.player).snapshot.sequence, 2, "failed snapshots do not advance sequence")
end

do
    local session, _, values = fixture()
    failure(session.ready(nil), "invalid_player", "player is required")
    failure(session.snapshot(nil), "invalid_player", "player is required")
    expectEqual(session.isReady(nil), false, "nil player is never ready")
    expectEqual(session.clearPlayer(nil).ok, true, "nil clear reports success")
    local playerTwo = {}
    expectEqual(session.ready(values.player).snapshot.sequence, 1, "first player sequence")
    values.recovery.recoverLoadedState = function(_, actualState)
        return { ok = true, state = actualState, recovered = false }
    end
    values.xpSource.initializePlayer = function()
        return { ok = true, detail = { initialized = 0, skipped = 2 } }
    end
    expectEqual(session.ready(playerTwo).snapshot.sequence, 1, "weak-key second player has independent sequence")
end

return assertions
