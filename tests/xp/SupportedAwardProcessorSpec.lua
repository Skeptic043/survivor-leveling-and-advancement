local assertions = 0

local function expect(condition, label)
    assertions = assertions + 1
    if not condition then error(label, 0) end
end

local function equal(actual, expected, label)
    expect(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function near(actual, expected, label)
    expect(math.abs(actual - expected) < 0.000000001, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do copy[deepCopy(key, seen)] = deepCopy(child, seen) end
    return copy
end

local function deepEqual(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not deepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function freshState()
    return {
        schemaVersion = 1,
        accountingMode = "Tracked",
        revision = 0,
        survivor = { level = 0, xpIntoLevel = 0, spent = 0 },
        perks = {},
        orphanedPerks = {},
        inFlightAdvancement = nil,
    }
end

local function target(id, level, position)
    return { targetId = id, targetLevel = level, targetPosition = position }
end

local function perkRecord(natural, highWater, targets, postMaxUsed, overrides)
    local record = {
        adapterId = "test.adapter",
        adapterVersion = 3,
        curveFingerprint = "curve.v3",
        effectiveMaximum = 10,
        naturalPosition = natural,
        highWaterPosition = highWater,
        activeTargets = targets or {},
        postMaxFullRateUsed = postMaxUsed or 0,
    }
    if overrides then
        for key, value in pairs(overrides) do record[key] = value end
    end
    return record
end

local function settings(normalization, multiplier, enabled, allowance, diminished)
    return {
        accountingMode = "Tracked",
        normalization = normalization or 1,
        survivorMultiplier = multiplier or 1,
        postMax = {
            enabled = enabled == true,
            fullRateAllowance = allowance or 0,
            diminishedRate = diminished or 0,
        },
    }
end

local function freeSettings(normalization, multiplier)
    local value = settings(normalization, multiplier)
    value.accountingMode = "Free"
    return value
end

local function award(base, applied, before, after, effective)
    local value = {
        perkId = "Aiming",
        survivorCreditBase = base,
        appliedDelta = applied,
        actualPositionBefore = before,
        actualPositionAfter = after,
    }
    if effective ~= nil then value.effectiveDelta = effective end
    return value
end

local function makeObservation()
    local byPlayer = setmetatable({}, { __mode = "k" })
    local observation = { getCount = 0, setCount = 0 }
    function observation.get(player, perkId)
        observation.getCount = observation.getCount + 1
        if observation.eventLog then observation.eventLog[#observation.eventLog + 1] = "observation_get" end
        local map = byPlayer[player]
        local position = map and map[perkId] or nil
        if position == nil then return { ok = true, present = false } end
        return { ok = true, present = true, position = position }
    end
    function observation.set(player, perkId, position)
        observation.setCount = observation.setCount + 1
        if observation.eventLog then observation.eventLog[#observation.eventLog + 1] = "observation_set" end
        local map = byPlayer[player]
        if not map then map = {}; byPlayer[player] = map end
        map[perkId] = position
        return { ok = true }
    end
    function observation.peek(player, perkId)
        local map = byPlayer[player]
        return map and map[perkId] or nil
    end
    return observation
end

local function makeEnvironment(config)
    config = config or {}
    local log = {}
    local player = {
        position = config.position or 0,
        level = config.level or 0,
    }
    local state = config.state or freshState()
    local store = {
        state = state,
        loadCount = 0,
        saveCount = 0,
        lastOptions = nil,
    }
    function store.load(loadedPlayer, options)
        store.loadCount = store.loadCount + 1
        store.lastOptions = options
        log[#log + 1] = "load"
        if config.failLoad then return { ok = false, code = "load_failed", detail = "fixture" } end
        local loadedState = deepCopy(store.state)
        store.lastLoadedState = loadedState
        return { ok = true, state = loadedState }
    end
    function store.save(savedPlayer, savedState)
        store.saveCount = store.saveCount + 1
        log[#log + 1] = "save"
        if config.failSave then return { ok = false, code = "save_failed", detail = "fixture" } end
        store.state = deepCopy(savedState)
        return { ok = true }
    end

    local adapter = {}
    function adapter.describe(handle)
        log[#log + 1] = "describe"
        return {
            ok = true,
            adapterId = config.adapterId or "test.adapter",
            adapterVersion = config.adapterVersion or 3,
            curveFingerprint = config.curveFingerprint or "curve.v3",
            effectiveMaximum = config.maximum or 10,
            cumulativeThresholds = { [config.maximum or 10] = config.maximumPosition or 100 },
        }
    end
    function adapter.inspect(handle, inspectedPlayer)
        log[#log + 1] = "inspect"
        return {
            ok = true,
            adapterId = config.inspectionAdapterId or config.adapterId or "test.adapter",
            adapterVersion = config.inspectionAdapterVersion or config.adapterVersion or 3,
            curveFingerprint = config.inspectionFingerprint or config.curveFingerprint or "curve.v3",
            storedLevel = inspectedPlayer.level,
            actualPosition = inspectedPlayer.position,
            effectiveMaximum = config.inspectionMaximum or config.maximum or 10,
            levelAligned = config.levelAligned ~= false,
        }
    end

    local loadOptions = config.loadOptions or { loadedPerks = { Aiming = true } }
    local resolver = { loadOptions = loadOptions, resolveCount = 0 }
    function resolver.resolve(perkId)
        resolver.resolveCount = resolver.resolveCount + 1
        log[#log + 1] = "resolve"
        if config.throwResolve then error("resolver forbidden in Free") end
        if config.failResolve then return { ok = false, code = "not_found", detail = perkId } end
        return { ok = true, adapter = adapter, handle = {} }
    end

    local recovery = { count = 0 }
    function recovery.recoverLoadedState(recoveredPlayer, loadedState)
        recovery.count = recovery.count + 1
        recovery.lastState = loadedState
        log[#log + 1] = "recover"
        if config.throwRecovery then error("private C:\\runtime\\path " .. tostring({})) end
        if config.failRecovery then return { ok = false, code = "quarantined", detail = "fixture" } end
        if config.recoverySave then
            local saved = store.save(recoveredPlayer, loadedState)
            if not saved.ok then return saved end
        end
        return { ok = true, recovered = config.recovered == true, state = loadedState }
    end

    local accountingMode = config.accountingModeService or { count = 0 }
    if accountingMode.synchronizeLoaded == nil then
        function accountingMode.synchronizeLoaded(synchronizedPlayer, synchronizedState, desiredMode)
            accountingMode.count = accountingMode.count + 1
            log[#log + 1] = "synchronize"
            if config.throwSynchronization then error("private synchronization detail") end
            if config.malformedSynchronization then return "not-a-result" end
            if config.malformedSynchronizationShape then
                return {
                    ok = true,
                    state = synchronizedState,
                    transitioned = "yes",
                    fromMode = synchronizedState.accountingMode,
                    toMode = desiredMode,
                }
            end
            if config.failSynchronization then
                return { ok = false, code = "sync_failed", detail = "fixture" }
            end
            if synchronizedState.accountingMode == desiredMode then
                return {
                    ok = true,
                    state = synchronizedState,
                    transitioned = false,
                    fromMode = desiredMode,
                    toMode = desiredMode,
                }
            end
            local candidate = deepCopy(synchronizedState)
            local fromMode = candidate.accountingMode
            candidate.accountingMode = desiredMode
            candidate.revision = candidate.revision + 1
            if desiredMode == "Tracked" then
                candidate.perks = {}
                candidate.orphanedPerks = {}
            end
            local saved = store.save(synchronizedPlayer, candidate)
            if not saved.ok then return saved end
            return {
                ok = true,
                state = candidate,
                transitioned = true,
                fromMode = fromMode,
                toMode = desiredMode,
            }
        end
    end

    local observation = config.observation or makeObservation()
    if config.observed ~= nil then observation.set(player, "Aiming", config.observed) end
    if config.logObservation then observation.eventLog = log end
    local created = SupportedAwardProcessor.create({
        NaturalLedger = config.naturalLedger or NaturalLedger,
        SurvivorEconomy = SurvivorEconomy,
        PostMax = config.postMaxService or PostMax,
        MutationScope = config.mutationScope or MutationScope,
        PlayerStateStore = store,
        ActualObservation = observation,
        resolver = resolver,
        recoveryService = recovery,
        AccountingMode = accountingMode,
    })
    expect(created.ok, "processor creation")
    return {
        service = created.service,
        player = player,
        store = store,
        resolver = resolver,
        recovery = recovery,
        accountingMode = accountingMode,
        observation = observation,
        log = log,
        loadOptions = loadOptions,
    }
end

do
    local invalid = SupportedAwardProcessor.create({})
    expect(not invalid.ok, "missing dependencies fail")
    equal(invalid.code, "invalid_dependencies", "missing dependency code")
end

do
    local observation = makeObservation()
    local env = makeEnvironment({ observation = observation })
    local begun = MutationScope.begin(env.player, "Aiming")
    expect(begun.ok, "internal scope begins")
    local result = env.service.process(env.player, { perkId = "Aiming" }, nil)
    expect(result.ok and result.ignoredInternal, "internal award ignored before validation")
    equal(result.stateWritten, false, "internal ignore writes no state")
    equal(env.store.loadCount, 0, "internal ignore performs no load")
    equal(env.store.saveCount, 0, "internal ignore performs no save")
    equal(env.recovery.count, 0, "internal ignore performs no recovery")
    equal(env.resolver.resolveCount, 0, "internal ignore performs no resolve")
    equal(observation.getCount, 0, "internal ignore performs no observation read")
    equal(observation.setCount, 0, "internal ignore performs no observation write")
    expect(MutationScope.finish(begun.handle).ok, "internal scope finishes")
end

do
    local env = makeEnvironment()
    local malformed = award(1, 1, 0, 1)
    malformed.extra = true
    equal(env.service.process(env.player, malformed, settings()).code, "invalid_award", "unexpected envelope field")
    local legacy = award(1, 1, 0, 1)
    legacy.survivorCreditBase = nil
    legacy.baseAward = 1
    equal(env.service.process(env.player, legacy, settings()).code, "invalid_award", "legacy baseAward envelope field rejected")
    equal(env.service.process(env.player, award(1, -1, 1, 0), settings()).code, "invalid_award", "positive base negative movement")
    local badSettings = settings()
    badSettings.normalization = 0
    equal(env.service.process(env.player, award(0, 0, 0, 0), badSettings).code, "invalid_settings", "invalid normalization")
    badSettings = settings(1, 1, true, 1, 2)
    equal(env.service.process(env.player, award(0, 0, 0, 0), badSettings).code, "invalid_settings", "invalid postmax rate")
    badSettings = settings()
    badSettings.accountingMode = "Bogus"
    equal(env.service.process(env.player, award(0, 0, 0, 0), badSettings).code, "invalid_settings", "accounting mode must be exact")
    equal(env.recovery.count, 0, "validation failures precede recovery")
    equal(env.store.loadCount, 0, "validation failures precede load")
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(0, 0)
    local env = makeEnvironment({ state = state, observed = 0, position = 0 })
    local result = env.service.process(env.player, award(0, 0, 0, 0), settings())
    expect(result.ok, "loaded-state recovery success")
    equal(env.log[1], "load", "store load occurs first")
    equal(env.log[2], "recover", "loaded-state recovery follows load")
    equal(env.log[3], "synchronize", "mode synchronization follows loaded-state recovery")
    equal(env.log[4], "resolve", "resolve follows mode synchronization")
    expect(env.store.lastOptions == env.loadOptions, "resolver load options passed exactly")
    expect(env.recovery.lastState == env.store.lastLoadedState, "recovery receives loaded working state directly")
    equal(env.store.loadCount, 1, "ordinary award loads once")
    equal(env.store.saveCount, 0, "unchanged ordinary award does not save")

    local failed = makeEnvironment({ failRecovery = true })
    local failureResult = failed.service.process(failed.player, award(0, 0, 0, 0), settings())
    equal(failureResult.code, "recovery_failed", "recovery failure code")
    equal(failureResult.detail, "quarantined:fixture", "returned recovery detail remains stable")
    equal(failed.store.loadCount, 1, "recovery failure follows one load")
    equal(failed.resolver.resolveCount, 0, "recovery failure prevents resolve")

    local thrown = makeEnvironment({ throwRecovery = true })
    local thrownResult = thrown.service.process(thrown.player, award(0, 0, 0, 0), settings())
    equal(thrownResult.code, "recovery_failed", "thrown recovery failure code")
    equal(thrownResult.detail, "recovery_error:dependency_threw", "thrown recovery detail is deterministic")
    expect(not thrownResult.detail:find("private", 1, true), "thrown recovery detail hides runtime text")
    equal(thrown.store.loadCount, 1, "thrown recovery follows one load")
end

-- Free awards use only the authoritative envelope and Survivor economy.
do
    local function forbidden() error("tracked award dependency called in Free") end
    local state = freshState()
    state.accountingMode = "Free"
    state.perks.Aiming = perkRecord(7, 99, { target("frozen", 4, 40) }, 13)
    state.orphanedPerks.Old = perkRecord(3, 8)
    local frozenPerks = deepCopy(state.perks)
    local frozenOrphans = deepCopy(state.orphanedPerks)
    local env = makeEnvironment({
        state = state,
        position = 10,
        throwResolve = true,
        naturalLedger = {
            baseline = forbidden,
            inspect = forbidden,
            applySupported = forbidden,
            reconcileExternal = forbidden,
        },
        postMaxService = { apply = forbidden },
        observation = { get = forbidden, set = forbidden },
    })
    local result = env.service.process(env.player, award(10, 10, 0, 10), freeSettings(2, 3))
    expect(result.ok, "positive Free award succeeds")
    equal(result.survivorXp, 60, "Free normalization and multiplier apply once")
    equal(result.naturalEligibleBase, 10, "Free positive movement accepts the full base")
    equal(result.recoveryApplied, 0, "Free has no red recovery")
    equal(result.postMaxBase, 0, "Free has no post-max accounting")
    equal(result.postMaxXp, 0, "Free has no post-max XP")
    equal(#result.clearedTargetIds, 0, "Free clears no targets")
    expect(result.stateWritten, "positive Free award writes Survivor state")
    equal(env.store.saveCount, 1, "positive Free award saves once")
    equal(env.store.state.revision, 0, "ordinary Free award does not change revision")
    expect(deepEqual(env.store.state.perks, frozenPerks), "Free award preserves frozen perks byte-for-byte")
    expect(deepEqual(env.store.state.orphanedPerks, frozenOrphans), "Free award preserves frozen orphans byte-for-byte")
    equal(env.resolver.resolveCount, 0, "Free award does not resolve an adapter")
end
do
    local cases = {
        { name = "zero_movement", base = 9, applied = 0, before = 10, after = 10 },
        { name = "zero_credit", base = 0, applied = 5, before = 10, after = 15 },
        { name = "negative", base = 0, applied = -5, before = 10, after = 5 },
    }
    for index = 1, #cases do
        local state = freshState()
        state.accountingMode = "Free"
        local env = makeEnvironment({ state = state, position = cases[index].after })
        local result = env.service.process(
            env.player,
            award(cases[index].base, cases[index].applied, cases[index].before, cases[index].after),
            freeSettings()
        )
        expect(result.ok, "Free zero/negative case succeeds: " .. cases[index].name)
        equal(result.survivorXp, 0, "Free zero/negative movement grants zero")
        equal(result.stateWritten, false, "Free zero/negative movement avoids a write")
        equal(env.store.saveCount, 0, "Free zero/negative movement performs no save")
        equal(env.resolver.resolveCount, 0, "Free zero/negative movement performs no resolve")
        equal(env.observation.getCount, 0, "Free zero/negative movement performs no observation read")
        equal(env.observation.setCount, 0, "Free zero/negative movement performs no observation write")
    end
end
do
    local state = freshState()
    state.accountingMode = "Free"
    state.survivor.xpIntoLevel = 1195
    state.perks.Aiming = perkRecord(0, 100)
    local frozen = deepCopy(state.perks)
    local env = makeEnvironment({ state = state, position = 10 })
    local result = env.service.process(env.player, award(10, 10, 0, 10), freeSettings())
    expect(result.ok, "Free re-earned threshold-crossing XP succeeds")
    equal(result.survivorXp, 10, "threshold award Survivor XP")
    equal(result.levelsGained, 1, "threshold award levels gained")
    equal(result.apGained, 1, "threshold award AP gained")
    equal(env.store.state.survivor.level, 1, "threshold award persisted level")
    equal(env.store.state.survivor.xpIntoLevel, 5, "threshold award persisted remainder")
    expect(deepEqual(env.store.state.perks, frozen), "re-earned Free XP leaves frozen high-water state unchanged")
end
do
    local state = freshState()
    state.accountingMode = "Free"
    local env = makeEnvironment({ state = state, position = 4 })
    local result = env.service.process(env.player, award(4, 5, 0, 4), freeSettings())
    equal(result.code, "invalid_award", "Free signed movement must match the envelope positions")
    equal(env.store.saveCount, 0, "invalid Free movement does not save")
    equal(env.resolver.resolveCount, 0, "invalid Free movement does not resolve")
end

-- Mode boundaries select the synchronized branch exactly once.
do
    local state = freshState()
    state.perks.Aiming = perkRecord(5, 12, { target("frozen", 2, 20) }, 7)
    local frozen = deepCopy(state.perks)
    local env = makeEnvironment({ state = state, position = 10 })
    local result = env.service.process(env.player, award(10, 10, 0, 10), freeSettings())
    expect(result.ok, "Tracked-to-Free boundary award succeeds")
    equal(result.survivorXp, 10, "Tracked-to-Free boundary follows Free once")
    equal(env.store.saveCount, 2, "transition and award each save once")
    equal(env.store.state.accountingMode, "Free", "Tracked-to-Free persisted mode")
    equal(env.store.state.revision, 1, "Tracked-to-Free persisted revision")
    expect(deepEqual(env.store.state.perks, frozen), "Tracked-to-Free boundary freezes tracked map")
    equal(env.resolver.resolveCount, 0, "Tracked-to-Free boundary does not enter tracked processing")
end
do
    local state = freshState()
    state.accountingMode = "Free"
    state.perks.Aiming = perkRecord(50, 70, { target("discarded", 8, 80) }, 9)
    state.orphanedPerks.Old = perkRecord(1, 2)
    local env = makeEnvironment({ state = state, observed = 0, position = 10 })
    local result = env.service.process(env.player, award(10, 10, 0, 10), settings())
    expect(result.ok, "Free-to-Tracked boundary award succeeds")
    equal(result.survivorXp, 10, "Free-to-Tracked boundary credits event once")
    equal(env.store.saveCount, 2, "Free-to-Tracked transition and award each save once")
    equal(env.store.state.accountingMode, "Tracked", "Free-to-Tracked persisted mode")
    equal(env.store.state.revision, 1, "Free-to-Tracked persisted revision")
    equal(env.store.state.perks.Aiming.naturalPosition, 10, "boundary baselines before and applies event once")
    equal(env.store.state.perks.Aiming.highWaterPosition, 10, "boundary applies high water once")
    equal(env.store.state.orphanedPerks.Old, nil, "returning to Tracked clears frozen orphan map")
end
do
    local state = freshState()
    state.perks.Aiming = perkRecord(1, 2)
    local env = makeEnvironment({ state = state, position = 0 })
    local result = env.service.process(env.player, award(0, 0, 0, 0), freeSettings())
    expect(result.ok, "transition-only zero Free award succeeds")
    expect(result.stateWritten, "transition-only zero reports prior durable write")
    equal(env.store.saveCount, 1, "transition-only zero avoids a second save")
    equal(env.resolver.resolveCount, 0, "transition-only Free skips resolver")
end
do
    local state = freshState()
    state.accountingMode = "Free"
    local env = makeEnvironment({ state = state, position = 0, recovered = true, recoverySave = true })
    local result = env.service.process(env.player, award(0, 0, 0, 0), freeSettings())
    expect(result.ok, "recovery-only zero Free award succeeds")
    expect(result.stateWritten, "recovery-only zero reports prior durable write")
    equal(env.store.saveCount, 1, "recovery-only zero avoids a second save")
    equal(env.resolver.resolveCount, 0, "recovery-only Free skips resolver")
end

-- Synchronization failures are contained before branch-specific dependencies run.
do
    local cases = {
        { name = "thrown", config = { throwSynchronization = true }, detail = "accounting_mode_error:dependency_threw" },
        { name = "malformed", config = { malformedSynchronization = true }, detail = "accounting_mode_invalid:not_result" },
        { name = "malformed_shape", config = { malformedSynchronizationShape = true }, detail = "result_invalid" },
    }
    for index = 1, #cases do
        local env = makeEnvironment(cases[index].config)
        local result = env.service.process(env.player, award(0, 0, 0, 0), settings())
        equal(result.code, "accounting_mode_failed", "synchronization failure code")
        equal(result.detail, cases[index].detail, "synchronization failure detail")
        equal(env.store.loadCount, 1, "synchronization failure follows one load")
        equal(env.recovery.count, 1, "synchronization failure follows recovery")
        equal(env.store.saveCount, 0, "synchronization failure performs no save")
        equal(env.resolver.resolveCount, 0, "synchronization failure performs no resolve")
        equal(env.observation.getCount, 0, "synchronization failure performs no observation read")
        equal(env.observation.setCount, 0, "synchronization failure performs no observation write")
    end
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(0, 0)
    local env = makeEnvironment({ state = state, observed = 0, position = 10, level = 1, logObservation = true })
    local result = env.service.process(env.player, award(10, 10, 0, 10), settings())
    expect(result.ok and result.stateWritten, "state-changing ordering fixture succeeds")
    local saveIndex = nil
    local observationSetIndex = nil
    for index = 1, #env.log do
        if env.log[index] == "save" then saveIndex = index end
        if env.log[index] == "observation_set" then observationSetIndex = index end
    end
    expect(saveIndex ~= nil, "state-changing award logs save")
    expect(observationSetIndex ~= nil, "state-changing award logs observation set")
    expect(saveIndex < observationSetIndex, "state save precedes observation update")
    equal(env.store.loadCount, 1, "accepted ordinary award loads exactly once")
    equal(env.store.saveCount, 1, "accepted ordinary award saves at most once")
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(0, 0)
    local env = makeEnvironment({ state = state, observed = 0, position = 10, level = 1, recovered = true, recoverySave = true })
    local result = env.service.process(env.player, award(10, 10, 0, 10), settings())
    expect(result.ok, "award after interrupted recovery succeeds")
    equal(env.store.loadCount, 1, "interrupted recovery award still loads once")
    equal(env.store.saveCount, 2, "recovery save remains distinct from award save")
    local firstSave, secondSave = nil, nil
    for index = 1, #env.log do
        if env.log[index] == "save" then
            if firstSave == nil then firstSave = index else secondSave = index end
        end
    end
    expect(firstSave ~= nil and secondSave ~= nil and firstSave < secondSave, "recovery save precedes award save")
end

do
    local env = makeEnvironment({ position = 10, level = 1 })
    local result = env.service.process(env.player, award(10, 10, 0, 10), settings(2, 3))
    expect(result.ok, "fresh bootstrap succeeds")
    near(result.survivorXp, 60, "fresh bootstrap survivor XP")
    equal(result.naturalEligibleBase, 10, "fresh bootstrap eligible base")
    equal(result.postMaxBase, 0, "fresh bootstrap no postmax")
    expect(result.stateWritten, "fresh bootstrap writes")
    equal(env.store.state.perks.Aiming.naturalPosition, 10, "fresh bootstrap natural position")
    equal(env.store.state.perks.Aiming.highWaterPosition, 10, "fresh bootstrap high water")
    equal(env.store.state.revision, 0, "fresh bootstrap does not increment revision")
    equal(env.observation.peek(env.player, "Aiming"), 10, "fresh bootstrap sets observation")
    expect(result.state == nil and result.perkState == nil, "result omits persisted state")
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(0, 0, {}, 0, { curveFingerprint = "old.curve" })
    local env = makeEnvironment({ state = state, observed = 0, position = 1 })
    local result = env.service.process(env.player, award(1, 1, 0, 1), settings())
    equal(result.code, "perk_quarantined", "adapter mismatch quarantines perk")
    equal(env.store.saveCount, 0, "adapter mismatch writes nothing")

    local mapped = makeEnvironment({ position = 2 })
    local mismatch = mapped.service.process(mapped.player, award(1, 1, 0, 1), settings())
    equal(mismatch.code, "adapter_inspection_failed", "inspection must match envelope after position")
    equal(mapped.store.saveCount, 0, "mapping mismatch writes nothing")
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(10, 10)
    local missing = makeEnvironment({ state = state, position = 15 })
    local missingResult = missing.service.process(missing.player, award(5, 5, 10, 15), settings())
    expect(missingResult.ok, "missing observation establishes boundary")
    equal(missingResult.naturalEligibleBase, 5, "missing observation preserves award eligibility")

    state = freshState()
    state.perks.Aiming = perkRecord(0, 0)
    local positive = makeEnvironment({ state = state, observed = 0, position = 15 })
    local positiveResult = positive.service.process(positive.player, award(5, 5, 10, 15), settings())
    expect(positiveResult.ok, "external positive observation reconciles")
    equal(positiveResult.naturalEligibleBase, 5, "external positive grants no Survivor XP itself")
    equal(positive.store.state.perks.Aiming.highWaterPosition, 15, "external positive advances high water before award")

    state = freshState()
    state.perks.Aiming = perkRecord(0, 0, { target("boost-1", 1, 10) })
    local crossing = makeEnvironment({ state = state, observed = 0, position = 10, level = 1 })
    local crossingResult = crossing.service.process(crossing.player, award(0, 0, 10, 10), settings())
    expect(crossingResult.ok, "external positive target crossing reconciles")
    equal(#crossingResult.clearedTargetIds, 1, "external crossing reports cleared target")
    equal(crossingResult.clearedTargetIds[1], "boost-1", "external crossing target order")
    equal(crossingResult.survivorXp, 0, "external crossing grants no Survivor XP")

    state = freshState()
    state.perks.Aiming = perkRecord(20, 20)
    local negative = makeEnvironment({ state = state, observed = 20, position = 10, level = 1 })
    local negativeResult = negative.service.process(negative.player, award(0, 0, 10, 10), settings())
    expect(negativeResult.ok, "external negative observation reconciles")
    equal(negative.store.state.perks.Aiming.naturalPosition, 10, "external negative lowers natural position")
    equal(negative.store.state.perks.Aiming.highWaterPosition, 20, "external negative preserves high water")
    equal(negativeResult.survivorXp, 0, "external negative grants no Survivor XP")
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(10, 10)
    local zero = makeEnvironment({ state = state, observed = 10, position = 10, level = 1 })
    local zeroResult = zero.service.process(zero.player, award(0, 0, 10, 10), settings())
    expect(zeroResult.ok, "ordinary zero succeeds")
    equal(zeroResult.stateWritten, false, "ordinary zero avoids state write")
    equal(zeroResult.survivorXp, 0, "ordinary zero grants nothing")
    equal(zero.store.loadCount, 1, "accepted zero award loads exactly once")
    equal(zero.store.saveCount, 0, "accepted zero award performs no save")

    state = freshState()
    state.perks.Aiming = perkRecord(10, 10)
    local zeroBaseMovement = makeEnvironment({ state = state, observed = 10, position = 15, level = 1 })
    local zeroBaseResult = zeroBaseMovement.service.process(zeroBaseMovement.player, award(0, 5, 10, 15), settings())
    expect(zeroBaseResult.ok, "zero base with observed movement succeeds")
    equal(zeroBaseMovement.store.state.perks.Aiming.highWaterPosition, 15, "zero base movement advances ledger")
    equal(zeroBaseResult.survivorXp, 0, "zero base movement never grants Survivor XP")

    state = freshState()
    state.perks.Aiming = perkRecord(20, 20)
    local negative = makeEnvironment({ state = state, observed = 20, position = 15, level = 1 })
    local negativeResult = negative.service.process(negative.player, award(0, -5, 20, 15), settings())
    expect(negativeResult.ok, "ordinary negative succeeds")
    equal(negative.store.state.perks.Aiming.naturalPosition, 15, "ordinary negative lowers natural")
    equal(negative.store.state.perks.Aiming.highWaterPosition, 20, "ordinary negative preserves high water")
    equal(negativeResult.survivorXp, 0, "ordinary negative grants nothing")

    state = freshState()
    state.perks.Aiming = perkRecord(0, 10)
    local boundary = makeEnvironment({ state = state, observed = 0, position = 10, level = 1 })
    local boundaryResult = boundary.service.process(boundary.player, award(10, 10, 0, 10), settings())
    expect(boundaryResult.ok, "red boundary succeeds")
    equal(boundaryResult.recoveryApplied, 10, "red boundary recovery")
    equal(boundaryResult.naturalEligibleBase, 0, "red boundary has no eligible base")

    state = freshState()
    state.perks.Aiming = perkRecord(0, 10)
    local partial = makeEnvironment({ state = state, observed = 0, position = 20, level = 2 })
    local partialResult = partial.service.process(partial.player, award(20, 20, 0, 20), settings())
    expect(partialResult.ok, "partial recovery crossing succeeds")
    equal(partialResult.recoveryApplied, 10, "partial recovery amount")
    equal(partialResult.naturalEligibleBase, 10, "partial recovery eligible base")
    equal(partialResult.survivorXp, 10, "partial recovery Survivor XP")

    state = freshState()
    state.perks.Aiming = perkRecord(0, 0, { target("one", 1, 10), target("two", 2, 20) })
    local multiple = makeEnvironment({ state = state, observed = 20, position = 45, level = 4 })
    local multipleResult = multiple.service.process(multiple.player, award(25, 25, 20, 45), settings())
    expect(multipleResult.ok, "multiple target award succeeds")
    equal(#multipleResult.clearedTargetIds, 2, "multiple targets cleared")
    equal(multipleResult.clearedTargetIds[1], "one", "first target order")
    equal(multipleResult.clearedTargetIds[2], "two", "second target order")
    equal(multiple.store.state.perks.Aiming.naturalPosition, 45, "final target synchronization")

    state = freshState()
    state.perks.Aiming = perkRecord(0, 0)
    local isolated = makeEnvironment({ state = state, observed = 0, position = 20, level = 2 })
    local isolatedResult = isolated.service.process(isolated.player, award(4, 20, 0, 20), settings())
    expect(isolatedResult.ok, "skill multiplier isolation succeeds")
    equal(isolatedResult.survivorXp, 4, "applied skill multiplier does not enter Survivor XP")

    state = freshState()
    state.perks.Aiming = perkRecord(0, 0)
    local leveling = makeEnvironment({ state = state, observed = 0, position = 1 })
    local levelingResult = leveling.service.process(leveling.player, award(5000, 1, 0, 1), settings())
    expect(levelingResult.ok, "multi-level Survivor award succeeds")
    equal(levelingResult.levelsGained, 3, "multiple Survivor levels gained")
    equal(levelingResult.apGained, 3, "multiple AP gained")
    equal(leveling.store.state.survivor.level, 3, "Survivor level persisted")
    equal(leveling.store.state.survivor.xpIntoLevel, 500, "Survivor remainder persisted")
    equal(leveling.store.state.revision, 0, "ordinary awards do not increment revision")
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(90, 90)
    local landing = makeEnvironment({ state = state, observed = 90, position = 100, level = 10 })
    local landingResult = landing.service.process(landing.player, award(10, 10, 90, 100), settings(1, 1, true, 100, 0.5))
    expect(landingResult.ok, "award landing on maximum succeeds")
    equal(landingResult.naturalEligibleBase, 10, "landing award remains ordinary natural accounting")
    equal(landingResult.postMaxBase, 0, "landing award is not reclassified postmax")
    equal(landing.store.state.perks.Aiming.postMaxFullRateUsed, 0, "landing award consumes no postmax allowance")

    state = freshState()
    state.perks.Aiming = perkRecord(100, 100)
    local disabled = makeEnvironment({ state = state, observed = 100, position = 100, level = 10 })
    local disabledResult = disabled.service.process(disabled.player, award(10, 0, 100, 100), settings(2, 3, false, 100, 0.5))
    expect(disabledResult.ok, "disabled no-debt max succeeds without evaluator")
    equal(disabledResult.postMaxBase, 10, "disabled max reports routed base")
    equal(disabledResult.postMaxXp, 0, "disabled max grants no XP")
    equal(disabledResult.stateWritten, false, "disabled max consumes nothing")

    state = freshState()
    state.perks.Aiming = perkRecord(100, 100)
    local enabled = makeEnvironment({ state = state, observed = 100, position = 100, level = 10 })
    local enabledResult = enabled.service.process(enabled.player, award(10, 0, 100, 100), settings(2, 3, true, 100, 0.5))
    expect(enabledResult.ok, "enabled no-debt max succeeds without evaluator")
    equal(enabledResult.postMaxBase, 10, "enabled max base")
    equal(enabledResult.postMaxXp, 60, "enabled max normalization and multiplier")
    equal(enabled.store.state.perks.Aiming.postMaxFullRateUsed, 20, "enabled max consumes normalized base")
    equal(enabled.store.state.revision, 0, "postmax award does not increment revision")
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(100, 100)
    local maxLoss = makeEnvironment({ state = state, observed = 100, position = 90, level = 10 })
    local maxLossResult = maxLoss.service.process(
        maxLoss.player,
        award(0, -10, 100, 90),
        settings(1, 1, true, 100, 0.5)
    )
    expect(maxLossResult.ok, "signed max loss remains ordinary")
    equal(maxLossResult.survivorXp, 0, "signed max loss grants no Survivor XP")
    equal(maxLoss.store.state.perks.Aiming.naturalPosition, 90, "signed max loss lowers natural position")
    equal(maxLoss.store.state.perks.Aiming.highWaterPosition, 100, "signed max loss preserves high water")
    equal(maxLoss.store.state.perks.Aiming.postMaxFullRateUsed, 0, "signed max loss consumes no postmax allowance")

    state = freshState()
    state.perks.Aiming = perkRecord(50, 70, { target("max-boost", 10, 100) })
    local missing = makeEnvironment({ state = state, observed = 100, position = 100, level = 10 })
    local missingResult = missing.service.process(missing.player, award(80, 0, 100, 100), settings(1, 1, true, 100, 0.5))
    equal(missingResult.code, "invalid_award", "max debt requires evaluator")
    equal(missing.store.saveCount, 0, "missing evaluator writes nothing")

    state = freshState()
    state.perks.Aiming = perkRecord(50, 70, { target("max-boost", 10, 100) })
    local zero = makeEnvironment({ state = state, observed = 100, position = 100, level = 10 })
    local zeroResult = zero.service.process(zero.player, award(80, 0, 100, 100, 0), settings(1, 1, true, 100, 0.5))
    expect(zeroResult.ok, "zero evaluator succeeds inertly")
    equal(zeroResult.survivorXp, 0, "zero evaluator grants nothing")
    equal(zeroResult.stateWritten, false, "zero evaluator changes no state")

    state = freshState()
    state.perks.Aiming = perkRecord(50, 70)
    local zeroBaseDebt = makeEnvironment({ state = state, observed = 100, position = 100, level = 10 })
    local zeroBaseDebtResult = zeroBaseDebt.service.process(
        zeroBaseDebt.player,
        award(0, 0, 100, 100, 10),
        settings(1, 1, true, 100, 0.5)
    )
    expect(zeroBaseDebtResult.ok, "zero-base max debt tracks evaluator movement")
    equal(zeroBaseDebtResult.recoveryApplied, 10, "zero-base max debt recovery amount")
    equal(zeroBaseDebtResult.survivorXp, 0, "zero-base max debt grants no Survivor XP")
    equal(zeroBaseDebtResult.postMaxBase, 0, "zero-base max debt has no postmax base")
    equal(zeroBaseDebt.store.state.perks.Aiming.naturalPosition, 60, "zero-base max debt advances natural position")
    equal(zeroBaseDebt.store.state.perks.Aiming.postMaxFullRateUsed, 0, "zero-base max debt consumes no postmax allowance")

    state = freshState()
    state.perks.Aiming = perkRecord(50, 70)
    local redOnly = makeEnvironment({ state = state, observed = 100, position = 100, level = 10 })
    local redOnlyResult = redOnly.service.process(redOnly.player, award(10, 0, 100, 100, 10), settings(1, 1, true, 100, 0.5))
    expect(redOnlyResult.ok, "red-only max recovery succeeds")
    equal(redOnlyResult.recoveryApplied, 10, "red-only max recovery amount")
    equal(redOnlyResult.survivorXp, 0, "red-only max recovery grants nothing")
    equal(redOnly.store.state.perks.Aiming.naturalPosition, 60, "red-only max advances virtual natural position")
    equal(redOnly.store.state.perks.Aiming.highWaterPosition, 70, "red-only max preserves high water")

    state = freshState()
    state.perks.Aiming = perkRecord(50, 70, { target("max-boost", 10, 100) })
    local split = makeEnvironment({ state = state, observed = 100, position = 100, level = 10 })
    local splitResult = split.service.process(split.player, award(80, 0, 100, 100, 80), settings(1, 1, true, 100, 0.5))
    expect(splitResult.ok, "red blue overflow max split succeeds")
    equal(splitResult.recoveryApplied, 20, "max split red recovery")
    equal(splitResult.naturalEligibleBase, 30, "max split natural base")
    equal(splitResult.postMaxBase, 30, "max split overflow base")
    equal(splitResult.postMaxXp, 30, "max split postmax XP")
    equal(splitResult.survivorXp, 60, "max split total Survivor XP")
    equal(splitResult.clearedTargetIds[1], "max-boost", "max split clears target")
    equal(split.store.state.perks.Aiming.naturalPosition, 100, "max split natural synchronization")
    equal(split.store.state.perks.Aiming.highWaterPosition, 100, "max split high-water synchronization")
    equal(split.store.state.perks.Aiming.postMaxFullRateUsed, 30, "max split consumes only overflow")
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(100, 100)
    local env = makeEnvironment({ state = state, observed = 100, position = 100, level = 10 })
    local first = env.service.process(env.player, award(8, 0, 100, 100), settings(1, 1, true, 10, 0.5))
    expect(first.ok, "first allowance award")
    equal(first.postMaxXp, 8, "first allowance full rate")
    equal(env.store.state.perks.Aiming.postMaxFullRateUsed, 8, "first usage")
    local second = env.service.process(env.player, award(8, 0, 100, 100), settings(1, 1, true, 10, 0.5))
    expect(second.ok, "allowance crossing award")
    equal(second.postMaxXp, 5, "allowance split and diminished rate")
    equal(env.store.state.perks.Aiming.postMaxFullRateUsed, 16, "crossing usage")
    local third = env.service.process(env.player, award(8, 0, 100, 100), settings(1, 1, true, 20, 0.25))
    expect(third.ok, "changed settings award")
    equal(third.postMaxXp, 5, "changed allowance uses persisted usage")
    equal(env.store.state.perks.Aiming.postMaxFullRateUsed, 24, "settings change does not reset usage")
    equal(env.store.state.revision, 0, "allowance awards do not increment revision")
end

do
    local state = freshState()
    state.perks.Aiming = perkRecord(0, 0)
    local originalState = deepCopy(state)
    local inputAward = award(10, 10, 0, 10)
    local inputSettings = settings(1, 1, true, 100, 0.5)
    local originalAward = deepCopy(inputAward)
    local originalSettings = deepCopy(inputSettings)
    local env = makeEnvironment({
        state = state,
        observed = 0,
        position = 10,
        level = 1,
        failSave = true,
    })
    local result = env.service.process(env.player, inputAward, inputSettings)
    equal(result.code, "award_save_failed", "save failure code")
    expect(deepEqual(state, originalState), "failed save leaves persisted state unchanged")
    expect(deepEqual(inputAward, originalAward), "award input remains immutable")
    expect(deepEqual(inputSettings, originalSettings), "settings input remains immutable")
    equal(env.observation.peek(env.player, "Aiming"), 0, "failed save does not advance observation")
    equal(state.revision, 0, "failed save does not increment revision")
end

return assertions
