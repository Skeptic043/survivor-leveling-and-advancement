local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "expectation failed", 0) end
end

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 0)
    end
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("fixture cycle", 0) end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    seen[value] = nil
    return result
end

local function target(id, level, position)
    return { targetId = id, targetLevel = level, targetPosition = position }
end

local function record(perkId, targetPosition)
    return {
        adapterId = "fixture.adapter",
        adapterVersion = 1,
        curveFingerprint = "curve_" .. perkId,
        effectiveMaximum = 10,
        naturalPosition = 0,
        highWaterPosition = 0,
        activeTargets = { target(perkId .. "_paid", 1, targetPosition) },
        postMaxFullRateUsed = 0,
        observedPosition = targetPosition,
    }
end

local function initialState()
    return {
        schemaVersion = 3,
        accountingMode = "Free",
        revision = 0,
        survivor = { level = 3, xpIntoLevel = 0, spent = 0 },
        perks = {
            Axe = record("Axe", 100),
            Carpentry = record("Carpentry", 50),
        },
        orphanedPerks = {},
        inFlightAdvancement = nil,
    }
end

local function environment(options)
    options = options or {}
    local startingState = initialState()
    startingState.accountingMode = options.accountingMode or "Free"
    local player = {
        positions = copy(options.positions or { Axe = 130, Carpentry = 80 }),
        levels = { Axe = 1, Carpentry = 1 },
    }
    local store = { state = startingState, loads = 0, saves = 0, failNextSave = false }
    function store.load(actualPlayer)
        store.loads = store.loads + 1
        expect(actualPlayer == player, "store player identity")
        return { ok = true, state = copy(store.state) }
    end
    function store.save(actualPlayer, state)
        store.saves = store.saves + 1
        expect(actualPlayer == player, "save player identity")
        if store.failNextSave then
            store.failNextSave = false
            return { ok = false, code = "fixture_save", detail = "retry" }
        end
        store.state = copy(state)
        return { ok = true }
    end

    local adapter = {}
    function adapter.describe(handle)
        return {
            ok = true,
            adapterId = "fixture.adapter",
            adapterVersion = 1,
            curveFingerprint = "curve_" .. handle.perkId,
            effectiveMaximum = 10,
            cumulativeThresholds = { [10] = 1000 },
        }
    end
    function adapter.inspect(handle, actualPlayer)
        return {
            ok = true,
            adapterId = "fixture.adapter",
            adapterVersion = 1,
            curveFingerprint = "curve_" .. handle.perkId,
            storedLevel = actualPlayer.levels[handle.perkId],
            actualPosition = actualPlayer.positions[handle.perkId],
            effectiveMaximum = 10,
            levelAligned = true,
            nextTargetLevel = actualPlayer.levels[handle.perkId] + 1,
            nextTargetPosition = actualPlayer.positions[handle.perkId] + 100,
        }
    end
    function adapter.ensureTarget()
        error("stale transition must not mutate the engine")
    end
    local resolver = { loadOptions = { loadedPerks = { Axe = true, Carpentry = true } } }
    function resolver.resolve(perkId)
        return { ok = true, adapter = adapter, handle = { perkId = perkId } }
    end

    local accountingCreated = AccountingMode.create({ store = store, ActualObservation = ActualObservation })
    expect(accountingCreated.ok, "accounting mode creation")
    local apCreated = ApTransaction.create({
        NaturalLedger = NaturalLedger,
        SurvivorEconomy = SurvivorEconomy,
        Allotment = Allotment,
        MutationScope = MutationScope,
        PlayerStateStore = store,
        ActualObservation = ActualObservation,
        AccountingMode = accountingCreated.service,
        resolver = resolver,
    })
    expect(apCreated.ok, "AP transaction creation")
    local awardCreated = SupportedAwardProcessor.create({
        NaturalLedger = NaturalLedger,
        SurvivorEconomy = SurvivorEconomy,
        PostMax = PostMax,
        MutationScope = MutationScope,
        PlayerStateStore = store,
        ActualObservation = ActualObservation,
        recoveryService = apCreated.service,
        AccountingMode = accountingCreated.service,
        resolver = resolver,
    })
    expect(awardCreated.ok, "award processor creation")

    local mode = startingState.accountingMode
    local ownerCreated = OwnerSession.create({
        store = store,
        recoveryService = apCreated.service,
        accountingMode = accountingCreated.service,
        accountingSettings = { resolve = function()
            return { ok = true, settings = { mode = mode } }
        end },
        catalog = {
            resolver = resolver,
            allPerks = function()
                return { ok = true, perks = { { id = "Axe" }, { id = "Carpentry" } } }
            end,
            positionReader = { read = function(actualPlayer, perkId)
                return { ok = true, position = actualPlayer.positions[perkId] }
            end },
        },
        NaturalLedger = NaturalLedger,
        ActualObservation = ActualObservation,
        xpSource = { initializePlayer = function()
            return { ok = true, detail = { initialized = 2, skipped = 0 } }
        end },
        ownerSnapshot = { project = function(state, sequence, ready)
            local perks = {}
            for perkId, perk in pairs(state.perks) do
                perks[perkId] = {
                    naturalPosition = perk.naturalPosition,
                    highWaterPosition = perk.highWaterPosition,
                    targets = #perk.activeTargets,
                }
            end
            return { ok = true, snapshot = {
                protocolVersion = 1,
                sequence = sequence,
                ready = ready,
                revision = state.revision,
                perks = perks,
            } }
        end },
        inheritanceSession = { initialize = function()
            return { ok = true, outcome = "existing", survivorLevel = 3, consumed = false }
        end },
    })
    expect(ownerCreated.ok, "owner session creation")

    return {
        player = player,
        store = store,
        ap = apCreated.service,
        award = awardCreated.service,
        owner = ownerCreated.session,
        setMode = function(value) mode = value end,
    }
end

do
    local env = environment({
        accountingMode = "Tracked",
        positions = { Axe = 100, Carpentry = 50 },
    })
    local ready = env.owner.ready(env.player)
    expect(ready.ok and ready.snapshot.sequence == 1, "initial Tracked snapshot is accepted")

    env.setMode("Free")
    local toFree = env.ap.spend(env.player, {
        perkId = "Axe", requestId = "round_trip_free", expectedRevision = 0,
    }, { mode = "Free" })
    equal(toFree.code, "stale_revision", "external AP transition enters Free")
    equal(env.store.state.accountingMode, "Free", "round trip persists Free boundary")

    env.player.positions.Axe = 130
    env.player.positions.Carpentry = 80
    local freeProgress = env.award.process(env.player, {
        perkId = "Axe",
        survivorCreditBase = 10,
        appliedDelta = 10,
        actualPositionBefore = 120,
        actualPositionAfter = 130,
    }, {
        accountingMode = "Free",
        normalization = 1,
        survivorMultiplier = 1,
        postMax = { enabled = false },
    })
    expect(freeProgress.ok, "supported Free progress is processed during hidden round trip")
    equal(env.store.state.perks.Axe.naturalPosition, 30, "Free event reconciles its matching preserved perk")
    equal(env.store.state.perks.Carpentry.naturalPosition, 0, "other preserved perk remains pending before tracked snapshot")

    env.setMode("Tracked")
    local toTracked = env.ap.spend(env.player, {
        perkId = "Axe", requestId = "round_trip_tracked", expectedRevision = 1,
    }, { mode = "Global", globalLimit = 3 })
    equal(toTracked.code, "stale_revision", "external AP transition re-enters Tracked")
    equal(env.store.state.accountingMode, "Tracked", "round trip persists Tracked boundary")

    env.store.failNextSave = true
    local failed = env.owner.snapshot(env.player)
    equal(failed.code, "readiness_reconciliation_save_failed", "hidden round-trip reconciliation failure is surfaced")
    equal(env.store.state.perks.Carpentry.naturalPosition, 0, "failed hidden round-trip snapshot remains atomic")

    local snapshot = env.owner.snapshot(env.player)
    expect(snapshot.ok, "hidden round-trip snapshot retries")
    equal(snapshot.snapshot.sequence, 2, "failed hidden round-trip snapshot does not advance sequence")
    equal(snapshot.snapshot.perks.Axe.naturalPosition, 30, "hidden round trip retains processed perk accounting")
    equal(snapshot.snapshot.perks.Carpentry.naturalPosition, 30, "hidden round trip reconciles every compatible perk")
    equal(snapshot.snapshot.perks.Axe.targets, 1, "hidden round trip retains Axe obligation")
    equal(snapshot.snapshot.perks.Carpentry.targets, 1, "hidden round trip retains Carpentry obligation")
end

do
    local env = environment()
    local ready = env.owner.ready(env.player)
    expect(ready.ok and ready.snapshot.sequence == 1, "Free owner readiness")
    env.setMode("Tracked")
    local transitioned = env.ap.spend(env.player, {
        perkId = "Axe", requestId = "ap_transition", expectedRevision = 0,
    }, { mode = "Global", globalLimit = 3 })
    equal(transitioned.code, "stale_revision", "AP commits only the mode transition")
    equal(env.store.state.accountingMode, "Tracked", "AP transition persists tracked mode")
    equal(env.store.state.revision, 1, "AP transition revision")

    env.store.failNextSave = true
    local failed = env.owner.snapshot(env.player)
    equal(failed.code, "readiness_reconciliation_save_failed", "all-perk reconciliation failure is surfaced")
    equal(env.store.state.perks.Axe.naturalPosition, 0, "failed snapshot preserves Axe accounting")
    equal(env.store.state.perks.Carpentry.naturalPosition, 0, "failed snapshot preserves Carpentry accounting")

    local snapshot = env.owner.snapshot(env.player)
    expect(snapshot.ok, "AP transition snapshot retries")
    equal(snapshot.snapshot.sequence, 2, "failed snapshot does not advance sequence")
    equal(snapshot.snapshot.perks.Axe.naturalPosition, 30, "AP transition reconciles Axe before first snapshot")
    equal(snapshot.snapshot.perks.Carpentry.naturalPosition, 30, "AP transition reconciles every compatible perk")
    equal(snapshot.snapshot.perks.Axe.targets, 1, "AP transition retains remaining Axe obligation")
    equal(snapshot.snapshot.perks.Carpentry.targets, 1, "AP transition retains remaining Carpentry obligation")
end

do
    local env = environment()
    expect(env.owner.ready(env.player).ok, "award case Free readiness")
    env.setMode("Tracked")
    env.player.positions.Axe = 130
    local processed = env.award.process(env.player, {
        perkId = "Axe",
        survivorCreditBase = 10,
        appliedDelta = 10,
        actualPositionBefore = 120,
        actualPositionAfter = 130,
    }, {
        accountingMode = "Tracked",
        normalization = 1,
        survivorMultiplier = 1,
        postMax = { enabled = false },
    })
    expect(processed.ok, "award-triggered transition succeeds")
    equal(processed.survivorXp, 10, "transition award credits only the current tracked event")
    equal(env.store.state.perks.Axe.naturalPosition, 30, "award transition reconciles and applies Axe event")
    equal(env.store.state.perks.Carpentry.naturalPosition, 0, "award transition has not fabricated Carpentry progress")

    env.store.failNextSave = true
    local failed = env.owner.snapshot(env.player)
    equal(failed.code, "readiness_reconciliation_save_failed", "award transition reconciliation failure is surfaced")
    equal(env.store.state.perks.Axe.naturalPosition, 30, "failed award snapshot preserves processed perk accounting")
    equal(env.store.state.perks.Carpentry.naturalPosition, 0, "failed award snapshot preserves unreconciled perk accounting")

    local snapshot = env.owner.snapshot(env.player)
    expect(snapshot.ok, "award transition first snapshot retries")
    equal(snapshot.snapshot.sequence, 2, "award transition snapshot sequence")
    equal(snapshot.snapshot.perks.Axe.naturalPosition, 30, "award transition snapshot keeps exact Axe accounting")
    equal(snapshot.snapshot.perks.Carpentry.naturalPosition, 30, "award transition snapshot reconciles other compatible perks")
    equal(snapshot.snapshot.perks.Axe.targets, 1, "award transition keeps Axe target")
    equal(snapshot.snapshot.perks.Carpentry.targets, 1, "award transition keeps Carpentry target")
end

return assertions
