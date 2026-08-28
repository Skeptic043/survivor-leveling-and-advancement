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

local function throwingIndexResult()
    return setmetatable({}, {
        __index = function()
            error("hostile result __index")
        end,
    })
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
    local state = { accountingMode = "Tracked", revision = 3, survivor = { level = 0, xpIntoLevel = 0, spent = 0, private = "private survivor" }, perks = { Axe = { private = "private perk" } }, private = "private root" }
    local recoveredState = { accountingMode = "Tracked", revision = 4, survivor = { level = 0, xpIntoLevel = 0, spent = 0 }, perks = {}, private = "recovered private" }
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
    local accountingSettings = { mode = "Tracked", inputs = {} }
    function accountingSettings.resolve(actualPlayer)
        calls[#calls + 1] = "settings"
        accountingSettings.inputs[#accountingSettings.inputs + 1] = actualPlayer
        return { ok = true, settings = { mode = accountingSettings.mode } }
    end
    local accountingMode = { inputs = {} }
    function accountingMode.synchronizeLoaded(actualPlayer, actualState, desiredMode)
        calls[#calls + 1] = "synchronize"
        accountingMode.inputs[#accountingMode.inputs + 1] = {
            player = actualPlayer,
            state = actualState,
            desiredMode = desiredMode,
        }
        return {
            ok = true,
            state = actualState,
            transitioned = false,
            fromMode = desiredMode,
            toMode = desiredMode,
        }
    end
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
    local inheritanceSession = {
        initialize = function()
            return { ok = true, outcome = "existing", survivorLevel = 0, consumed = false }
        end,
    }
    local dependencies = { store = store, recoveryService = recovery, accountingMode = accountingMode, accountingSettings = accountingSettings, catalog = catalog, xpSource = xpSource, ownerSnapshot = ownerSnapshot, inheritanceSession = inheritanceSession }
    if overrides then overrides(dependencies, { calls = calls, loads = loads, state = state, recoveredState = recoveredState, options = options, perks = perks, player = player, store = store, recovery = recovery, accountingMode = accountingMode, accountingSettings = accountingSettings, catalog = catalog, xpSource = xpSource, ownerSnapshot = ownerSnapshot }) end
    local created = OwnerSession.create(dependencies)
    expectEqual(created.ok, true, "session creates")
    return created.session, dependencies, { calls = calls, loads = loads, state = state, recoveredState = recoveredState, options = options, perks = perks, player = player, store = store, recovery = recovery, accountingMode = accountingMode, accountingSettings = accountingSettings, catalog = catalog, xpSource = xpSource, ownerSnapshot = ownerSnapshot }
end

failure(OwnerSession.create(nil), "invalid_dependencies", "dependencies must be a table")
failure(OwnerSession.create({}), "invalid_dependencies", "store.load is required")
failure(OwnerSession.create({ store = { load = function() end } }), "invalid_dependencies", "recoveryService.recoverLoadedState is required")
local creationDependencies = { store = { load = function() end }, recoveryService = { recoverLoadedState = function() end } }
failure(OwnerSession.create(creationDependencies), "invalid_dependencies", "accountingMode.synchronizeLoaded is required")
creationDependencies.accountingMode = { synchronizeLoaded = function() end }
failure(OwnerSession.create(creationDependencies), "invalid_dependencies", "accountingSettings.resolve is required")
creationDependencies.accountingSettings = { resolve = function() end }
failure(OwnerSession.create(creationDependencies), "invalid_dependencies", "catalog capabilities are required")
creationDependencies.catalog = { allPerks = function() end, resolver = { loadOptions = {} } }
failure(OwnerSession.create(creationDependencies), "invalid_dependencies", "xpSource.initializePlayer is required")
creationDependencies.xpSource = { initializePlayer = function() end }
failure(OwnerSession.create(creationDependencies), "invalid_dependencies", "ownerSnapshot.project is required")
creationDependencies.ownerSnapshot = { project = function() end }
failure(OwnerSession.create(creationDependencies), "invalid_dependencies", "inheritanceSession.initialize is required")

do
    local session, _, values = fixture(function(dependencies, fixtureValues)
        dependencies.inheritanceSession.initialize = function(actualPlayer)
            fixtureValues.calls[#fixtureValues.calls + 1] = "inheritance"
            expectEqual(actualPlayer, fixtureValues.player, "inheritance player identity")
            return { ok = true, outcome = "existing", survivorLevel = 0, consumed = false }
        end
    end)
    expectEqual(session.ready(values.player).ok, true, "inheritance-ordered ready succeeds")
    sequenceEquals(values.calls, { "inheritance", "load", "recover", "settings", "synchronize", "catalog", "initialize", "project" },
        "inheritance initializes before first state load")
end

do
    local session, _, values = fixture(function(dependencies)
        dependencies.inheritanceSession.initialize = function()
            return { ok = true, outcome = "inherit", survivorLevel = 3, consumed = true }
        end
    end)
    local ready = session.ready(values.player)
    expectEqual(ready.ok, true, "positive inheritance ready succeeds")
    expectEqual(ready.completion.protocolVersion, 1, "inheritance completion protocol")
    expectEqual(ready.completion.kind, "survivor_level_gain", "inheritance completion kind")
    expectEqual(ready.completion.levelsGained, 3, "inheritance completion levels")
    expectEqual(ready.completion.apGained, 3, "inheritance completion AP")
    local later = session.ready(values.player)
    expectEqual(later.completion, nil, "later ready stays silent after positive inheritance")

    local freshValues
    session, _, freshValues = fixture(function(dependencies)
        dependencies.inheritanceSession.initialize = function()
            return { ok = true, outcome = "fresh", survivorLevel = 0, consumed = false }
        end
    end)
    expectEqual(session.ready(freshValues.player).completion, nil, "fresh ready stays silent")
end

do
    local session, _, values = fixture(function(dependencies, fixtureValues)
        dependencies.inheritanceSession.initialize = function()
            fixtureValues.calls[#fixtureValues.calls + 1] = "inheritance"
            return { ok = false, code = "metadata_invalid", detail = "private" }
        end
    end)
    failure(session.ready(values.player), "inheritance_initialize_failed", dependency("metadata_invalid", "private"))
    sequenceEquals(values.calls, { "inheritance" }, "inheritance failure prevents ordinary load")
end

do
    local session, _, values = fixture(function(dependencies, fixtureValues)
        dependencies.inheritanceSession.initialize = function()
            fixtureValues.calls[#fixtureValues.calls + 1] = "inheritance"
            return { ok = true, outcome = "existing", survivorLevel = 0, consumed = "no" }
        end
    end)
    failure(session.ready(values.player), "inheritance_initialize_invalid", "inheritanceSession.initialize")
    sequenceEquals(values.calls, { "inheritance" }, "malformed inheritance prevents ordinary load")
end

do
    local session, _, values = fixture()
    failure(session.snapshot(values.player), "not_ready", "ready has not succeeded")
    expectEqual(#values.calls, 0, "not-ready snapshot does no work")
    expectEqual(session.isReady(values.player), false, "not-ready state")
    local ready = session.ready(values.player)
    expectEqual(ready.ok, true, "ready succeeds")
    sequenceEquals(values.calls, { "load", "recover", "settings", "synchronize", "catalog", "initialize", "project" }, "ready order")
    expectEqual(values.loads[1].player, values.player, "store player identity")
    expectEqual(values.loads[1].options, values.options, "compatibility options identity")
    expectEqual(values.accountingSettings.inputs[1], values.player, "accounting settings player identity")
    expectEqual(values.accountingMode.inputs[1].player, values.player, "accounting mode player identity")
    expectEqual(values.accountingMode.inputs[1].state, values.recoveredState, "ready synchronization receives recovered state identity")
    expectEqual(ready.snapshot.sequence, 1, "first sequence")
    expectEqual(ready.snapshot.ready, true, "ready projection")
    expectEqual(ready.recovered, true, "recovery count")
    expectEqual(ready.initialized, 1, "initialized count")
    expectEqual(ready.skipped, 1, "skipped count")
    expect(not contains(ready, values.state) and not contains(ready, values.recoveredState) and not contains(ready, "private root") and not contains(ready, "private recovery") and not contains(ready, "compatibility"), "ready result is private")
    local snapshot = session.snapshot(values.player)
    expectEqual(snapshot.ok, true, "subsequent snapshot succeeds")
    sequenceEquals(values.calls, { "load", "recover", "settings", "synchronize", "catalog", "initialize", "project", "load", "settings", "synchronize", "project" }, "subsequent snapshot resolves and synchronizes without recovery or initialization")
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
    sequenceEquals(values.calls, { "load", "recover", "settings", "synchronize", "catalog", "initialize", "project", "load", "recover", "settings", "synchronize", "catalog", "initialize", "project" }, "replay repeats safe rebase")
    local cleared = session.clearPlayer(values.player)
    expectEqual(cleared.ok, true, "clear reports success")
    expectEqual(cleared.snapshot, nil, "clear has no snapshot")
    expectEqual(session.isReady(values.player), false, "clear forgets readiness")
    failure(session.snapshot(values.player), "not_ready", "ready has not succeeded")
    local rerun = session.ready(values.player)
    expectEqual(rerun.snapshot.sequence, 1, "clear restarts sequence")
end

do
    local session, _, values = fixture(function(dependencies, fixtureValues)
        fixtureValues.accountingSettings.mode = "Free"
        dependencies.accountingMode.synchronizeLoaded = function(actualPlayer, actualState, desiredMode)
            fixtureValues.calls[#fixtureValues.calls + 1] = "synchronize"
            expectEqual(actualPlayer, fixtureValues.player, "transition ready player identity")
            expectEqual(actualState, fixtureValues.recoveredState, "transition follows recovery state")
            expectEqual(desiredMode, "Free", "transition ready desired mode")
            local candidate = { accountingMode = "Free", revision = actualState.revision + 1, survivor = actualState.survivor, perks = "hostile frozen perks", private = "free synchronized" }
            return { ok = true, state = candidate, transitioned = true, fromMode = "Tracked", toMode = "Free" }
        end
    end)
    local ready = session.ready(values.player)
    expectEqual(ready.ok, true, "Tracked-to-Free ready succeeds")
    sequenceEquals(values.calls, { "load", "recover", "settings", "synchronize", "catalog", "initialize", "project" }, "Tracked-to-Free ready order")
    expectEqual(ready.snapshot.revision, 5, "ready projects synchronized transition revision")
    expectEqual(ready.snapshot.privateInput, "free synchronized", "ready projects synchronized state identity")
end

do
    local session, _, values = fixture(function(dependencies, fixtureValues)
        dependencies.accountingMode.synchronizeLoaded = function(_, actualState, desiredMode)
            fixtureValues.calls[#fixtureValues.calls + 1] = "synchronize"
            if actualState.accountingMode == desiredMode then
                return { ok = true, state = actualState, transitioned = false, fromMode = desiredMode, toMode = desiredMode }
            end
            local candidate = { accountingMode = desiredMode, revision = actualState.revision + 1, survivor = actualState.survivor, perks = {}, private = "tracked synchronized" }
            return { ok = true, state = candidate, transitioned = true, fromMode = actualState.accountingMode, toMode = desiredMode }
        end
    end)
    expectEqual(session.ready(values.player).ok, true, "ready before subsequent transition")
    values.state.accountingMode = "Free"
    values.state.revision = 10
    values.accountingSettings.mode = "Tracked"
    local snapshot = session.snapshot(values.player)
    expectEqual(snapshot.ok, true, "Free-to-Tracked subsequent snapshot succeeds")
    sequenceEquals(values.calls, { "load", "recover", "settings", "synchronize", "catalog", "initialize", "project", "load", "settings", "synchronize", "project" }, "Free-to-Tracked subsequent ordering")
    expectEqual(snapshot.snapshot.sequence, 2, "transition snapshot sequence")
    expectEqual(snapshot.snapshot.revision, 11, "subsequent snapshot projects synchronized revision")
    expectEqual(snapshot.snapshot.privateInput, "tracked synchronized", "subsequent snapshot projects synchronized state")
end

local function assertReadyFailure(name, configure, code, detail, expectedCalls)
    local session, _, values = fixture(configure)
    local result = session.ready(values.player)
    failure(result, code, detail)
    expectEqual(session.isReady(values.player), false, name .. " does not commit readiness")
    sequenceEquals(values.calls, expectedCalls, name .. " stops flow")
    return session, values
end

assertReadyFailure("load explicit failure", function(dependencies) dependencies.store.load = function() return { ok = false, code = "load_unavailable", detail = "temporary" } end end, "store_load_failed", dependency("load_unavailable", "temporary"), {})
assertReadyFailure("load unsafe diagnostic", function(dependencies) dependencies.store.load = function() return { ok = false, code = "unsafe code", detail = "bad\nvalue" } end end, "store_load_failed", dependency(), {})
assertReadyFailure("load throw", function(dependencies) dependencies.store.load = function() error("leak") end end, "store_load_threw", "dependency threw", {})
assertReadyFailure("load malformed", function(dependencies) dependencies.store.load = function() return { ok = true, state = "not-state" } end end, "store_load_invalid", "store.load", {})
assertReadyFailure("recovery explicit failure", function(dependencies) dependencies.recoveryService.recoverLoadedState = function() return { ok = false, code = "recovery_quarantined", detail = "reservation_state_inconsistent" } end end, "recovery_failed", dependency("recovery_quarantined", "reservation_state_inconsistent"), { "load" })
assertReadyFailure("recovery malformed", function(dependencies) dependencies.recoveryService.recoverLoadedState = function() return { ok = true, state = {}, recovered = "yes" } end end, "recovery_invalid", "recoveryService.recoverLoadedState", { "load" })
assertReadyFailure("settings explicit failure", function(dependencies) dependencies.accountingSettings.resolve = function() return { ok = false, code = "settings_unavailable", detail = "provider failed" } end end, "accounting_settings_failed", dependency("settings_unavailable", "provider failed"), { "load", "recover" })
assertReadyFailure("settings throw", function(dependencies) dependencies.accountingSettings.resolve = function() error("private") end end, "accounting_settings_threw", "dependency threw", { "load", "recover" })
assertReadyFailure("settings malformed", function(dependencies) dependencies.accountingSettings.resolve = function() return { ok = true, settings = { mode = "Bogus" } } end end, "accounting_settings_invalid", "accountingSettings.resolve", { "load", "recover" })
assertReadyFailure("settings extra", function(dependencies) dependencies.accountingSettings.resolve = function() return { ok = true, settings = { mode = "Tracked", extra = true } } end end, "accounting_settings_invalid", "accountingSettings.resolve", { "load", "recover" })
assertReadyFailure("settings wrapper metatable", function(dependencies) dependencies.accountingSettings.resolve = function() return setmetatable({ ok = true, settings = { mode = "Tracked" } }, {}) end end, "accounting_settings_invalid", "accountingSettings.resolve", { "load", "recover" })
assertReadyFailure("synchronization explicit failure", function(dependencies) dependencies.accountingMode.synchronizeLoaded = function() return { ok = false, code = "sync_unavailable", detail = "save failed" } end end, "accounting_mode_failed", dependency("sync_unavailable", "save failed"), { "load", "recover", "settings" })
assertReadyFailure("synchronization throw", function(dependencies) dependencies.accountingMode.synchronizeLoaded = function() error("private") end end, "accounting_mode_threw", "dependency threw", { "load", "recover", "settings" })
assertReadyFailure("synchronization malformed", function(dependencies) dependencies.accountingMode.synchronizeLoaded = function(_, state) return { ok = true, state = state, transitioned = "no", fromMode = "Tracked", toMode = "Tracked" } end end, "accounting_mode_invalid", "accountingMode.synchronizeLoaded", { "load", "recover", "settings" })
assertReadyFailure("synchronization wrapper metatable", function(dependencies) dependencies.accountingMode.synchronizeLoaded = function(_, state) return setmetatable({ ok = true, state = state, transitioned = false, fromMode = "Tracked", toMode = "Tracked" }, {}) end end, "accounting_mode_invalid", "accountingMode.synchronizeLoaded", { "load", "recover", "settings" })
do
    local session, values = assertReadyFailure(
        "settings throwing-index result",
        function(dependencies, fixtureValues)
            dependencies.accountingSettings.resolve = function()
                fixtureValues.calls[#fixtureValues.calls + 1] = "settings"
                return throwingIndexResult()
            end
        end,
        "accounting_settings_failed",
        dependency(),
        { "load", "recover", "settings" }
    )
    values.accountingSettings.resolve = function()
        values.calls[#values.calls + 1] = "settings"
        return { ok = true, settings = { mode = "Tracked" } }
    end
    local repaired = session.ready(values.player)
    expectEqual(repaired.ok, true, "settings throwing-index repair succeeds")
    expectEqual(repaired.snapshot.sequence, 1, "settings throwing-index failure does not advance sequence")
end
do
    local session, values = assertReadyFailure(
        "synchronization throwing-index result",
        function(dependencies, fixtureValues)
            dependencies.accountingMode.synchronizeLoaded = function()
                fixtureValues.calls[#fixtureValues.calls + 1] = "synchronize"
                return throwingIndexResult()
            end
        end,
        "accounting_mode_failed",
        dependency(),
        { "load", "recover", "settings", "synchronize" }
    )
    values.accountingMode.synchronizeLoaded = function(_, state)
        values.calls[#values.calls + 1] = "synchronize"
        return { ok = true, state = state, transitioned = false, fromMode = "Tracked", toMode = "Tracked" }
    end
    local repaired = session.ready(values.player)
    expectEqual(repaired.ok, true, "synchronization throwing-index repair succeeds")
    expectEqual(repaired.snapshot.sequence, 1, "synchronization throwing-index failure does not advance sequence")
end
do
    local session, values = assertReadyFailure(
        "settings outer extra",
        function(dependencies)
            dependencies.accountingSettings.resolve = function()
                return { ok = true, settings = { mode = "Tracked" }, extra = true }
            end
        end,
        "accounting_settings_invalid",
        "accountingSettings.resolve",
        { "load", "recover" }
    )
    values.accountingSettings.resolve = function(actualPlayer)
        values.calls[#values.calls + 1] = "settings"
        return { ok = true, settings = { mode = "Tracked" } }
    end
    local repaired = session.ready(values.player)
    expectEqual(repaired.ok, true, "settings-wrapper repair succeeds")
    expectEqual(repaired.snapshot.sequence, 1, "rejected settings wrapper does not advance sequence")
end
do
    local session, values = assertReadyFailure(
        "synchronization outer extra",
        function(dependencies)
            dependencies.accountingMode.synchronizeLoaded = function(_, state)
                return { ok = true, state = state, transitioned = false, fromMode = "Tracked", toMode = "Tracked", extra = true }
            end
        end,
        "accounting_mode_invalid",
        "accountingMode.synchronizeLoaded",
        { "load", "recover", "settings" }
    )
    values.accountingMode.synchronizeLoaded = function(_, state)
        values.calls[#values.calls + 1] = "synchronize"
        return { ok = true, state = state, transitioned = false, fromMode = "Tracked", toMode = "Tracked" }
    end
    local repaired = session.ready(values.player)
    expectEqual(repaired.ok, true, "synchronization-wrapper repair succeeds")
    expectEqual(repaired.snapshot.sequence, 1, "rejected synchronization wrapper does not advance sequence")
end
do
    local session, values = assertReadyFailure(
        "synchronized revision malformed",
        function(_, fixtureValues) fixtureValues.recoveredState.revision = -1 end,
        "accounting_mode_invalid",
        "accountingMode.synchronizeLoaded",
        { "load", "recover", "settings", "synchronize" }
    )
    values.recoveredState.revision = 4
    local repaired = session.ready(values.player)
    expectEqual(repaired.ok, true, "synchronized-state repair succeeds")
    expectEqual(repaired.snapshot.sequence, 1, "rejected synchronized state does not advance sequence")
end
assertReadyFailure("synchronized survivor malformed", function(_, values) values.recoveredState.survivor.xpIntoLevel = 0 / 0 end, "accounting_mode_invalid", "accountingMode.synchronizeLoaded", { "load", "recover", "settings", "synchronize" })
assertReadyFailure("synchronized Tracked perks malformed", function(_, values) values.recoveredState.perks = "frozen only valid in Free" end, "accounting_mode_invalid", "accountingMode.synchronizeLoaded", { "load", "recover", "settings", "synchronize" })
assertReadyFailure("transition revision malformed", function(dependencies, values)
    values.accountingSettings.mode = "Free"
    dependencies.accountingMode.synchronizeLoaded = function(_, state)
        values.calls[#values.calls + 1] = "synchronize"
        return {
            ok = true,
            state = { accountingMode = "Free", revision = state.revision + 2, survivor = state.survivor, perks = "frozen" },
            transitioned = true,
            fromMode = "Tracked",
            toMode = "Free",
        }
    end
end, "accounting_mode_invalid", "accountingMode.synchronizeLoaded", { "load", "recover", "settings", "synchronize" })
assertReadyFailure("catalog failure", function(dependencies) dependencies.catalog.allPerks = function() return { ok = false } end end, "catalog_failed", dependency(), { "load", "recover", "settings", "synchronize" })
assertReadyFailure("catalog sparse", function(dependencies) dependencies.catalog.allPerks = function() return { ok = true, perks = { [2] = {} } } end end, "catalog_invalid", "catalog.allPerks", { "load", "recover", "settings", "synchronize" })
assertReadyFailure("initialize failure", function(dependencies) dependencies.xpSource.initializePlayer = function() return { ok = false } end end, "xp_initialize_failed", dependency(), { "load", "recover", "settings", "synchronize", "catalog" })
assertReadyFailure("initialize malformed", function(dependencies) dependencies.xpSource.initializePlayer = function() return { ok = true, detail = { initialized = 1 } } end end, "xp_initialize_invalid", "xpSource.initializePlayer", { "load", "recover", "settings", "synchronize", "catalog" })
assertReadyFailure("initialize incomplete counts", function(dependencies) dependencies.xpSource.initializePlayer = function() return { ok = true, detail = { initialized = 1, skipped = 0 } } end end, "xp_initialize_invalid", "xpSource.initializePlayer", { "load", "recover", "settings", "synchronize", "catalog" })
assertReadyFailure("projection failure", function(dependencies) dependencies.ownerSnapshot.project = function() return { ok = false } end end, "snapshot_failed", dependency(), { "load", "recover", "settings", "synchronize", "catalog", "initialize" })
assertReadyFailure("projection malformed", function(dependencies) dependencies.ownerSnapshot.project = function() return { ok = true, snapshot = "bad" } end end, "snapshot_invalid", "ownerSnapshot.project", { "load", "recover", "settings", "synchronize", "catalog", "initialize" })
assertReadyFailure("projection protocol mismatch", function(dependencies) dependencies.ownerSnapshot.project = function(_, sequence) return { ok = true, snapshot = { protocolVersion = 2, ready = true, sequence = sequence } } end end, "snapshot_invalid", "ownerSnapshot.project", { "load", "recover", "settings", "synchronize", "catalog", "initialize" })
assertReadyFailure("projection readiness mismatch", function(dependencies) dependencies.ownerSnapshot.project = function(_, sequence) return { ok = true, snapshot = { protocolVersion = 1, ready = false, sequence = sequence } } end end, "snapshot_invalid", "ownerSnapshot.project", { "load", "recover", "settings", "synchronize", "catalog", "initialize" })
assertReadyFailure("projection sequence mismatch", function(dependencies) dependencies.ownerSnapshot.project = function(_, sequence) return { ok = true, snapshot = { protocolVersion = 1, ready = true, sequence = sequence + 1 } } end end, "snapshot_invalid", "ownerSnapshot.project", { "load", "recover", "settings", "synchronize", "catalog", "initialize" })

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
    expectEqual(session.ready(values.player).ok, true, "ready before hostile settings snapshot")
    for index = #values.calls, 1, -1 do values.calls[index] = nil end
    values.accountingSettings.resolve = function()
        values.calls[#values.calls + 1] = "settings"
        return throwingIndexResult()
    end
    failure(session.snapshot(values.player), "accounting_settings_failed", dependency())
    sequenceEquals(values.calls, { "load", "settings" }, "hostile settings snapshot stops before synchronization and projection")
    expectEqual(session.isReady(values.player), true, "hostile settings snapshot preserves readiness")
    values.accountingSettings.resolve = function()
        values.calls[#values.calls + 1] = "settings"
        return { ok = true, settings = { mode = "Tracked" } }
    end
    expectEqual(session.snapshot(values.player).snapshot.sequence, 2, "hostile settings snapshot does not advance sequence")
end

do
    local session, _, values = fixture()
    expectEqual(session.ready(values.player).ok, true, "ready before hostile synchronization snapshot")
    for index = #values.calls, 1, -1 do values.calls[index] = nil end
    values.accountingMode.synchronizeLoaded = function()
        values.calls[#values.calls + 1] = "synchronize"
        return throwingIndexResult()
    end
    failure(session.snapshot(values.player), "accounting_mode_failed", dependency())
    sequenceEquals(values.calls, { "load", "settings", "synchronize" }, "hostile synchronization snapshot stops before projection")
    expectEqual(session.isReady(values.player), true, "hostile synchronization snapshot preserves readiness")
    values.accountingMode.synchronizeLoaded = function(_, state)
        values.calls[#values.calls + 1] = "synchronize"
        return { ok = true, state = state, transitioned = false, fromMode = "Tracked", toMode = "Tracked" }
    end
    expectEqual(session.snapshot(values.player).snapshot.sequence, 2, "hostile synchronization snapshot does not advance sequence")
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
