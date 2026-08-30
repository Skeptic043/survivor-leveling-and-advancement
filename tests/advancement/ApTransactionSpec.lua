local assertions = 0

local function fail(message)
    error(message, 0)
end

local function assertTrue(value, message)
    assertions = assertions + 1
    if value ~= true then fail(message or "expected true") end
end

local function assertFalse(value, message)
    assertions = assertions + 1
    if value ~= false then fail(message or "expected false") end
end

local function assertEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        fail((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then fail("cycle in fixture") end
    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
    seen[value] = nil
    return copy
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

local function assertSame(actual, expected, message)
    assertions = assertions + 1
    if not same(actual, expected) then fail(message or "tables differ") end
end

local function assertCode(result, code)
    assertFalse(result.ok, "expected failure " .. code)
    assertEqual(result.code, code, "failure code")
    assertEqual(result.state, nil, "failure must not expose state")
end

local function newState(level, spent)
    return {
        schemaVersion = 3,
        accountingMode = "Tracked",
        revision = 0,
        survivor = { level = level or 3, xpIntoLevel = 0, spent = spent or 0 },
        perks = {},
        orphanedPerks = {},
        inFlightAdvancement = nil,
    }
end

local function newPerk(natural, high, targets, perkId)
    perkId = perkId or "Axe"
    return {
        adapterId = "fake.adapter",
        adapterVersion = 1,
        curveFingerprint = "curve_" .. perkId,
        effectiveMaximum = 3,
        naturalPosition = natural or 0,
        highWaterPosition = high or 0,
        activeTargets = targets or {},
        postMaxFullRateUsed = 0,
        observedPosition = natural or 0,
    }
end

local function newPlayer(perkId, level, position)
    local player = { skills = {}, behavior = {} }
    player.skills[perkId or "Axe"] = { level = level or 0, position = position or 0 }
    return player
end

local function addSkill(player, perkId, level, position)
    player.skills[perkId] = { level = level or 0, position = position or 0 }
end

local function makeStore(initial, events)
    local store = {
        current = clone(initial),
        loads = 0,
        saves = 0,
        failSaveAt = {},
        receivedOptions = nil,
    }
    function store.load(player, options)
        store.loads = store.loads + 1
        store.receivedOptions = options
        if store.failLoad then return { ok = false, code = "fake_load", detail = "failed" } end
        return { ok = true, state = clone(store.current) }
    end
    function store.save(player, state)
        store.saves = store.saves + 1
        if state.inFlightAdvancement then
            store.scopeAtReservation = MutationScope.isActive(player, state.inFlightAdvancement.perkId)
        else
            store.scopeAtCommit = MutationScope.isActive(player, "Axe")
        end
        if store.failSaveAt[store.saves] then
            return { ok = false, code = "fake_save", detail = "failed" }
        end
        store.current = clone(state)
        if events then
            if state.inFlightAdvancement then
                events[#events + 1] = "reservation"
            else
                events[#events + 1] = "commit"
            end
        end
        return { ok = true }
    end
    return store
end

local function makeRuntime(events)
    local adapter = { describeCalls = 0, inspectCalls = 0, ensureCalls = 0, scopeSeen = false }
    local handles = {}
    local thresholds = { [0] = 0, 100, 250, 450 }
    local function handleFor(perkId)
        if handles[perkId] == nil then
            handles[perkId] = {
                perkId = perkId,
                adapterId = "fake.adapter",
                adapterVersion = 1,
                curveFingerprint = "curve_" .. perkId,
                effectiveMaximum = 3,
            }
        end
        return handles[perkId]
    end
    local function derivedLevel(position)
        local level = 0
        for candidate = 1, 3 do
            if position >= thresholds[candidate] then level = candidate end
        end
        return level
    end
    function adapter.describe(handle)
        adapter.describeCalls = adapter.describeCalls + 1
        return {
            ok = true,
            adapterId = handle.adapterId,
            adapterVersion = handle.adapterVersion,
            curveFingerprint = handle.curveFingerprint,
            effectiveMaximum = handle.effectiveMaximum,
        }
    end
    function adapter.inspect(handle, player)
        adapter.inspectCalls = adapter.inspectCalls + 1
        local skill = player.skills[handle.perkId]
        if not skill then return { ok = false, code = "missing_skill", detail = handle.perkId } end
        local derived = derivedLevel(skill.position)
        local nextLevel = nil
        local nextPosition = nil
        if skill.level < handle.effectiveMaximum then
            nextLevel = skill.level + 1
            nextPosition = thresholds[nextLevel]
        end
        local alignment = "aligned"
        if skill.level < derived then alignment = "xp-ahead" elseif skill.level > derived then alignment = "level-ahead" end
        return {
            ok = true,
            adapterId = handle.adapterId,
            adapterVersion = handle.adapterVersion,
            curveFingerprint = handle.curveFingerprint,
            effectiveMaximum = handle.effectiveMaximum,
            storedLevel = skill.level,
            actualPosition = skill.position,
            nextTargetLevel = nextLevel,
            nextTargetPosition = nextPosition,
            levelAligned = skill.level == derived,
            alignment = alignment,
        }
    end
    function adapter.ensureTarget(handle, player, targetLevel, targetPosition)
        adapter.ensureCalls = adapter.ensureCalls + 1
        adapter.scopeSeen = adapter.scopeSeen or MutationScope.isActive(player, handle.perkId)
        if events then events[#events + 1] = "engine" end
        local skill = player.skills[handle.perkId]
        local behavior = player.behavior[handle.perkId] or {}
        if behavior.failNoWrite then
            return { ok = false, code = "fake_ensure", detail = "no_write", xpWriteInvoked = false, levelWriteInvoked = false }
        end
        local xpWrite = false
        local levelWrite = false
        if skill.position < targetPosition then
            skill.position = targetPosition
            xpWrite = true
            if behavior.throwAfterXp then error("interrupted after XP") end
            if behavior.failAfterXp then
                return { ok = false, code = "fake_ensure", detail = "after_xp", xpWriteInvoked = true, levelWriteInvoked = false }
            end
        end
        if skill.level < targetLevel then
            skill.level = targetLevel
            levelWrite = true
        end
        return {
            ok = true,
            xpWriteInvoked = xpWrite,
            levelWriteInvoked = levelWrite,
            storedLevel = skill.level,
            actualPosition = skill.position,
        }
    end
    local resolver = {
        loadOptions = { loadedPerks = { marker = true } },
        resolveCount = 0,
    }
    function resolver.resolve(perkId)
        resolver.resolveCount = resolver.resolveCount + 1
        if perkId == "Unknown" then return { ok = false, code = "unsupported", detail = perkId } end
        return { ok = true, adapter = adapter, handle = handleFor(perkId) }
    end
    return adapter, resolver, handles
end

local function dependenciesFor(store, resolver)
    if store.accountingMode == nil then
        store.accountingMode = { calls = 0 }
        function store.accountingMode.synchronizeLoaded(player, state, desiredMode)
            store.accountingMode.calls = store.accountingMode.calls + 1
            store.accountingMode.lastState = state
            store.accountingMode.lastDesiredMode = desiredMode
            if state.accountingMode == desiredMode then
                return {
                    ok = true,
                    state = state,
                    transitioned = false,
                    fromMode = desiredMode,
                    toMode = desiredMode,
                }
            end
            local candidate = clone(state)
            local fromMode = candidate.accountingMode
            candidate.accountingMode = desiredMode
            candidate.revision = candidate.revision + 1
            if desiredMode == "Tracked" then
                candidate.perks = {}
                candidate.orphanedPerks = {}
            end
            local saved = store.save(player, candidate)
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
    return {
        NaturalLedger = NaturalLedger,
        SurvivorEconomy = SurvivorEconomy,
        Allotment = Allotment,
        MutationScope = MutationScope,
        store = store,
        ActualObservation = ActualObservation,
        AccountingMode = store.accountingMode,
        resolver = resolver,
    }
end

local function createService(store, adapter, resolver, overrides)
    local dependencies = dependenciesFor(store, resolver)
    if overrides then
        for key, value in pairs(overrides) do dependencies[key] = value end
    end
    local created = ApTransaction.create(dependencies)
    assertTrue(created.ok, "service creation")
    return created.service
end

local globalThree = { mode = "Global", globalLimit = 3 }

local function throwingFreeSentinels()
    local function forbidden() error("tracked accounting must not run in Free") end
    return {
        NaturalLedger = {
            baseline = forbidden,
            inspect = forbidden,
            reconcileExternal = forbidden,
            appendTarget = forbidden,
            master = forbidden,
        },
        Allotment = { evaluate = forbidden },
        ActualObservation = {
            get = forbidden,
            set = forbidden,
            clearPlayer = forbidden,
        },
    }
end

-- Volatile observation semantics and validation.
do
    local player = {}
    assertCode(ActualObservation.get(nil, "Axe"), "invalid_observation")
    assertCode(ActualObservation.set(player, "bad id", 1), "invalid_observation")
    assertCode(ActualObservation.set(player, "Axe", -1), "invalid_observation")
    local missing = ActualObservation.get(player, "Axe")
    assertTrue(missing.ok)
    assertFalse(missing.present)
    assertTrue(ActualObservation.set(player, "Axe", 12.5).ok)
    local present = ActualObservation.get(player, "Axe")
    assertTrue(present.present)
    assertEqual(present.position, 12.5)
    assertTrue(ActualObservation.clearPlayer(player).ok)
    assertFalse(ActualObservation.get(player, "Axe").present)
end

-- Dependency failures are explicit.
do
    assertCode(ApTransaction.create({}), "invalid_dependencies")
    local store = makeStore(newState(3, 0))
    local adapter, resolver = makeRuntime()
    local functionResolver = dependenciesFor(store, resolver)
    functionResolver.resolver = function() return { ok = true, adapter = adapter, handle = {} } end
    assertCode(ApTransaction.create(functionResolver), "invalid_dependencies")
    local callableOptions = dependenciesFor(store, resolver)
    callableOptions.resolver = { resolve = resolver.resolve, loadOptions = function() return {} end }
    assertCode(ApTransaction.create(callableOptions), "invalid_dependencies")
end
do
    local store = makeStore(newState(3, 0))
    local adapter, resolver = makeRuntime()
    local exact = resolver.resolve("Axe")
    local multiReturnResolver = {}
    function multiReturnResolver.resolve(perkId) return exact.adapter, exact.handle end
    local created = ApTransaction.create(dependenciesFor(store, multiReturnResolver))
    assertTrue(created.ok)
    local player = newPlayer("Axe", 0, 0)
    assertCode(created.service.spend(player, { perkId = "Axe", requestId = "multi_return", expectedRevision = 0 }, globalThree), "resolver_failed")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.saves, 0)
end

-- Loaded-state recovery trusts the store boundary and never performs another load.
do
    local store = makeStore(newState(3, 0))
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    local loaded = store.load(player, resolver.loadOptions)
    local result = service.recoverLoadedState(player, loaded.state)
    assertTrue(result.ok)
    assertFalse(result.recovered)
    assertTrue(result.state == loaded.state, "no-reservation recovery preserves loaded working state")
    assertEqual(store.loads, 1, "loaded-state recovery performs no load")
    assertEqual(store.saves, 0, "no-reservation loaded-state recovery performs no save")
end

-- Fresh bootstrap, reservation/engine/commit order, AP effects, and scope cleanup.
do
    local events = {}
    local state = newState(3, 0)
    local store = makeStore(state, events)
    local adapter, resolver = makeRuntime(events)
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    local request = { perkId = "Axe", requestId = "fresh_one", expectedRevision = 0 }
    local requestBefore = clone(request)
    local configBefore = clone(globalThree)
    local result = service.spend(player, request, globalThree)
    assertTrue(result.ok)
    assertEqual(result.requestId, "fresh_one")
    assertEqual(result.revision, 1)
    assertEqual(result.spent, 1)
    assertEqual(result.availableAp, 2)
    assertEqual(result.apCost, 1)
    assertFalse(result.mastered)
    assertTrue(result.addedTarget)
    assertEqual(#result.clearedTargetIds, 0)
    assertTrue(result.xpWriteInvoked)
    assertTrue(result.levelWriteInvoked)
    assertFalse(result.recovered)
    assertSame(events, { "reservation", "engine", "commit" }, "atomic order")
    assertTrue(store.scopeAtReservation, "scope must precede reservation save")
    assertFalse(store.scopeAtCommit, "scope must finish before commit save")
    assertTrue(adapter.scopeSeen, "engine must run inside scope")
    assertFalse(MutationScope.isActive(player, "Axe"), "scope must be cleaned")
    assertEqual(player.skills.Axe.level, 1)
    assertEqual(player.skills.Axe.position, 100)
    assertEqual(store.current.revision, 1)
    assertEqual(store.current.survivor.spent, 1)
    assertEqual(store.current.inFlightAdvancement, nil)
    assertEqual(#store.current.perks.Axe.activeTargets, 1)
    assertEqual(store.current.perks.Axe.activeTargets[1].targetId, "fresh_one:revision:0")
    assertEqual(store.current.perks.Axe.naturalPosition, 0)
    assertEqual(store.current.perks.Axe.highWaterPosition, 0)
    assertEqual(store.current.perks.Axe.observedPosition, 100, "AP commit persists final actual position")
    assertEqual(ActualObservation.get(player, "Axe").position, 100)
    assertSame(request, requestBefore, "request immutable")
    assertSame(globalThree, configBefore, "config immutable")
    assertSame(store.receivedOptions, resolver.loadOptions, "resolver options reach load")
    assertEqual(store.loads, 1, "spend loads once")
end

-- A restarted process may reuse its first transport ID; the durable revision keeps the new slot distinct.
do
    local state = newState(4, 1)
    state.revision = 9
    state.perks.Axe = newPerk(0, 0, {
        { targetId = "advancement-local:1", targetLevel = 1, targetPosition = 100 },
    })
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 1, 100)
    local result = service.spend(player, {
        perkId = "Axe", requestId = "advancement-local:1", expectedRevision = 9,
    }, globalThree)
    assertTrue(result.ok, "post-restart advancement succeeds despite reused request ID")
    assertEqual(result.requestId, "advancement-local:1", "transport correlation ID remains unchanged")
    assertEqual(result.revision, 10)
    assertEqual(result.spent, 2)
    assertEqual(#store.current.perks.Axe.activeTargets, 2)
    assertEqual(store.current.perks.Axe.activeTargets[1].targetId, "advancement-local:1")
    assertEqual(store.current.perks.Axe.activeTargets[2].targetId, "advancement-local:1:revision:9")
end

-- Final-level mastery derives a two-AP cost, reserves two slots, and collapses the full target chain.
do
    local state = newState(4, 0)
    state.perks.Axe = newPerk(0, 0, {
        { targetId = "chain_one", targetLevel = 1, targetPosition = 100 },
        { targetId = "chain_two", targetLevel = 2, targetPosition = 250 },
    })
    state.perks.Carpentry = newPerk(0, 0, {
        { targetId = "other", targetLevel = 1, targetPosition = 100 },
    }, "Carpentry")
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    local result = service.spend(player, { perkId = "Axe", requestId = "master_full", expectedRevision = 0 }, { mode = "Global", globalLimit = 3 })
    assertCode(result, "allotment_rejected")
    assertEqual(adapter.ensureCalls, 0, "blocked mastery never writes engine XP")
    assertEqual(store.saves, 0, "blocked mastery never reserves or commits")
end
do
    local state = newState(2, 0)
    state.survivor.xpIntoLevel = 33
    state.perks.Axe = newPerk(0, 0, {
        { targetId = "chain_one", targetLevel = 1, targetPosition = 100 },
        { targetId = "chain_two", targetLevel = 2, targetPosition = 250 },
    })
    state.perks.Axe.postMaxFullRateUsed = 12
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    local result = service.spend(player, { perkId = "Axe", requestId = "master_exact", expectedRevision = 0 }, { mode = "Global", globalLimit = 4 })
    assertTrue(result.ok, "exact mastery succeeds: " .. tostring(result.code) .. ":" .. tostring(result.detail))
    assertEqual(result.apCost, 2)
    assertTrue(result.mastered)
    assertFalse(result.addedTarget)
    assertSame(result.clearedTargetIds, { "chain_one", "chain_two" }, "mastery clear order")
    assertEqual(result.spent, 2)
    assertEqual(result.availableAp, 0)
    assertEqual(result.revision, 1)
    assertEqual(adapter.ensureCalls, 1)
    assertEqual(player.skills.Axe.level, 3)
    assertEqual(player.skills.Axe.position, 450)
    assertEqual(store.current.perks.Axe.naturalPosition, 450)
    assertEqual(store.current.perks.Axe.highWaterPosition, 450)
    assertEqual(store.current.perks.Axe.observedPosition, 450, "mastery commit persists final actual position")
    assertEqual(#store.current.perks.Axe.activeTargets, 0)
    assertEqual(store.current.survivor.xpIntoLevel, 33)
    assertEqual(store.current.perks.Axe.postMaxFullRateUsed, 12)
    assertEqual(store.current.inFlightAdvancement, nil)
end
do
    local state = newState(4, 1)
    state.perks.Axe = newPerk(0, 0, {
        { targetId = "one", targetLevel = 1, targetPosition = 100 },
        { targetId = "two", targetLevel = 2, targetPosition = 250 },
    })
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    local result = service.spend(player, { perkId = "Axe", requestId = "master_extra", expectedRevision = 0 }, { mode = "PerSkill", perSkillDefault = 4 })
    assertTrue(result.ok, "extra AP mastery succeeds: " .. tostring(result.code) .. ":" .. tostring(result.detail))
    assertEqual(result.apCost, 2)
    assertEqual(result.spent, 3)
    assertEqual(result.availableAp, 1)
end
do
    local state = newState(2, 0)
    state.perks.Axe = newPerk(250, 250, {})
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    local result = service.spend(player, { perkId = "Axe", requestId = "master_one_slot", expectedRevision = 0 }, { mode = "PerSkill", perSkillDefault = 1 })
    assertTrue(result.ok, "one free slot admits mastery when the per-skill limit is one")
    assertTrue(result.mastered)
    assertEqual(result.apCost, 2)
    assertEqual(result.spent, 2)
end
do
    local state = newState(3, 0)
    state.accountingMode = "Free"
    state.perks.Axe = newPerk(17, 29, { { targetId = "frozen", targetLevel = 1, targetPosition = 100 } })
    state.orphanedPerks.Old = newPerk(4, 9, {}, "Old")
    local frozenPerks = clone(state.perks)
    local frozenOrphans = clone(state.orphanedPerks)
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver, throwingFreeSentinels())
    local player = newPlayer("Axe", 2, 250)
    local result = service.spend(player, { perkId = "Axe", requestId = "master_free", expectedRevision = 0 }, { mode = "Free" })
    assertTrue(result.ok, "free mastery succeeds: " .. tostring(result.code) .. ":" .. tostring(result.detail))
    assertEqual(result.apCost, 2, "Free final step uses universal final cost")
    assertTrue(result.mastered, "Free final step reports the universal final advancement")
    assertFalse(result.addedTarget, "Free final step creates no target")
    assertEqual(#result.clearedTargetIds, 0, "Free final step clears no targets")
    assertEqual(result.spent, 2)
    assertEqual(result.revision, 1)
    assertEqual(player.skills.Axe.level, 3)
    assertEqual(player.skills.Axe.position, 450)
    assertSame(store.current.perks, frozenPerks, "Free final step preserves frozen perk map byte-for-byte")
    assertSame(store.current.orphanedPerks, frozenOrphans, "Free final step preserves frozen orphan map byte-for-byte")
end
do
    local state = newState(1, 0)
    state.accountingMode = "Free"
    local before = clone(state)
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver, throwingFreeSentinels())
    local player = newPlayer("Axe", 2, 250)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "free_final_short", expectedRevision = 0 }, { mode = "Free" }), "no_ap")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.saves, 0)
    assertSame(store.current, before, "insufficient Free final step preserves state")
end

-- One AP and zero-limit configurations reject final mastery without reservation or engine mutation.
do
    local cases = {
        { state = newState(2, 1), config = globalThree, code = "no_ap" },
        { state = newState(3, 0), config = { mode = "Global", globalLimit = 0 }, code = "allotment_rejected" },
        { state = newState(3, 0), config = { mode = "PerSkill", perSkillDefault = 0 }, code = "allotment_rejected" },
        { state = newState(3, 0), config = { mode = "PerSkill", perSkillDefault = 1, perSkillOverrides = { Axe = 0 } }, code = "allotment_rejected" },
    }
    for index = 1, #cases do
        cases[index].state.perks.Axe = newPerk(0, 0)
        local store = makeStore(cases[index].state)
        local adapter, resolver = makeRuntime()
        local service = createService(store, adapter, resolver)
        local player = newPlayer("Axe", 2, 250)
        local result = service.spend(player, { perkId = "Axe", requestId = "master_blocked_" .. index, expectedRevision = 0 }, cases[index].config)
        assertCode(result, cases[index].code)
        if index == 1 then assertEqual(result.detail, "insufficient_ap_for_advancement") end
        assertEqual(adapter.ensureCalls, 0)
        assertEqual(store.saves, 0)
        assertEqual(player.skills.Axe.level, 2)
        assertEqual(player.skills.Axe.position, 250)
    end
end

-- Final mastery remains fail-closed for red, stale, and misaligned state.
do
    local scenarios = {
        { code = "red_recovery", natural = 200, high = 250, expected = 0, position = 250 },
        { code = "stale_revision", natural = 250, high = 250, expected = 1, position = 250 },
        { code = "misaligned_progression", natural = 200, high = 200, expected = 0, position = 200 },
    }
    for index = 1, #scenarios do
        local item = scenarios[index]
        local state = newState(3, 0)
        state.perks.Axe = newPerk(item.natural, item.high)
        local store = makeStore(state)
        local adapter, resolver = makeRuntime()
        local service = createService(store, adapter, resolver)
        local player = newPlayer("Axe", 2, item.position)
        assertCode(service.spend(player, { perkId = "Axe", requestId = "master_fail_" .. index, expectedRevision = item.expected }, globalThree), item.code)
        assertEqual(adapter.ensureCalls, 0)
        assertEqual(store.saves, 0)
    end
end

-- A final engine or commit failure leaves the upward mutation/reservation available for recovery and never refunds AP.
do
    local state = newState(3, 0)
    state.perks.Axe = newPerk(0, 0, { { targetId = "prior", targetLevel = 2, targetPosition = 250 } })
    local store = makeStore(state)
    store.failSaveAt[2] = true
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "master_commit_fail", expectedRevision = 0 }, globalThree), "commit_save_failed")
    assertEqual(player.skills.Axe.level, 3)
    assertEqual(player.skills.Axe.position, 450)
    assertEqual(store.current.survivor.spent, 0)
    assertEqual(store.current.inFlightAdvancement.targetLevel, 3)
    assertEqual(store.current.inFlightAdvancement.effectiveMaximum, 3)
    local recovered = service.recover(player)
    assertTrue(recovered.ok, "commit failure mastery recovers: " .. tostring(recovered.code) .. ":" .. tostring(recovered.detail))
    assertEqual(recovered.apCost, 2)
    assertTrue(recovered.mastered)
    assertEqual(recovered.spent, 2)
    assertEqual(#store.current.perks.Axe.activeTargets, 0)
    assertEqual(player.skills.Axe.level, 3)
end
do
    local state = newState(3, 0)
    state.perks.Axe = newPerk(0, 0)
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    player.behavior.Axe = { failNoWrite = true }
    assertCode(service.spend(player, { perkId = "Axe", requestId = "master_engine_fail", expectedRevision = 0 }, globalThree), "engine_mutation_failed")
    assertEqual(player.skills.Axe.level, 2)
    assertEqual(player.skills.Axe.position, 250)
    assertEqual(store.current.survivor.spent, 0)
    assertEqual(store.current.inFlightAdvancement.requestId, "master_engine_fail")
end

-- Malformed, forged, unsupported, stale, and rejected fresh requests do not persist bootstrap state.
do
    local cases = {
        { request = { perkId = "Axe", requestId = "bad", expectedRevision = 0, playerId = "forged" }, code = "invalid_request" },
        { request = { perkId = "bad id", requestId = "bad", expectedRevision = 0 }, code = "invalid_request" },
        { request = { perkId = "Unknown", requestId = "bad", expectedRevision = 0 }, code = "resolver_failed" },
        { request = { perkId = "Axe", requestId = "stale", expectedRevision = 2 }, code = "stale_revision" },
    }
    for index = 1, #cases do
        local store = makeStore(newState(3, 0))
        local adapter, resolver = makeRuntime()
        local service = createService(store, adapter, resolver)
        local player = newPlayer("Axe", 0, 0)
        local result = service.spend(player, cases[index].request, globalThree)
        assertCode(result, cases[index].code)
        assertEqual(store.saves, 0, "rejection save count")
        assertEqual(store.current.perks.Axe, nil, "no rejected bootstrap")
        assertEqual(adapter.ensureCalls, 0, "no rejected engine write")
    end
end

-- No AP, red recovery, maximum, and adapter misalignment all fail before engine mutation.
do
    local scenarios = {
        { code = "no_ap", state = newState(1, 1), level = 0, position = 0 },
        { code = "red_recovery", state = newState(2, 0), level = 0, position = 50, natural = 50, high = 100 },
        { code = "at_maximum", state = newState(2, 0), level = 3, position = 450 },
        { code = "misaligned_progression", state = newState(2, 0), level = 0, position = 100 },
    }
    for index = 1, #scenarios do
        local item = scenarios[index]
        if item.natural then item.state.perks.Axe = newPerk(item.natural, item.high) end
        local store = makeStore(item.state)
        local adapter, resolver = makeRuntime()
        local service = createService(store, adapter, resolver)
        local player = newPlayer("Axe", item.level, item.position)
        local result = service.spend(player, { perkId = "Axe", requestId = "blocked_" .. index, expectedRevision = 0 }, globalThree)
        assertCode(result, item.code)
        assertEqual(adapter.ensureCalls, 0)
    end
end

-- Adapter identity changes quarantine an existing perk.
do
    local state = newState(2, 0)
    state.perks.Axe = newPerk(0, 0)
    state.perks.Axe.curveFingerprint = "old_curve"
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "identity", expectedRevision = 0 }, globalThree), "perk_quarantined")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.saves, 0)
end

-- Global, PerSkill, Free, invalid configuration, and exact-reboost bypass paths.
do
    local state = newState(3, 0)
    state.perks.Spear = newPerk(0, 0, { { targetId = "spear_one", targetLevel = 1, targetPosition = 100 } }, "Spear")
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    addSkill(player, "Spear", 0, 0)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "global_full", expectedRevision = 0 }, { mode = "Global", globalLimit = 1 }), "allotment_rejected")
    assertEqual(adapter.ensureCalls, 0)
end
do
    local state = newState(3, 0)
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "per_zero", expectedRevision = 0 }, { mode = "PerSkill", perSkillDefault = 0 }), "allotment_rejected")
    assertCode(service.spend(player, { perkId = "Axe", requestId = "invalid_allotment", expectedRevision = 0 }, { mode = "Bogus" }), "allotment_invalid")
    local allowed = service.spend(player, { perkId = "Axe", requestId = "per_override", expectedRevision = 0 }, { mode = "PerSkill", perSkillDefault = 0, perSkillOverrides = { Axe = 1 } })
    assertTrue(allowed.ok)
end
do
    local state = newState(3, 0)
    state.accountingMode = "Free"
    state.perks.Axe = newPerk(12, 34, { { targetId = "frozen", targetLevel = 2, targetPosition = 250 } })
    state.orphanedPerks.Old = newPerk(5, 8, {}, "Old")
    local frozenPerks = clone(state.perks)
    local frozenOrphans = clone(state.orphanedPerks)
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver, throwingFreeSentinels())
    local player = newPlayer("Axe", 0, 0)
    local result = service.spend(player, { perkId = "Axe", requestId = "free_one", expectedRevision = 0 }, { mode = "Free" })
    assertTrue(result.ok)
    assertEqual(result.apCost, 1, "ordinary Free step costs one AP")
    assertFalse(result.mastered)
    assertFalse(result.addedTarget)
    assertEqual(#result.clearedTargetIds, 0)
    assertEqual(store.saves, 2, "Free spend reserves and commits exactly once")
    assertEqual(store.current.survivor.spent, 1)
    assertEqual(store.current.revision, 1)
    assertSame(store.current.perks, frozenPerks, "ordinary Free spend preserves frozen perks")
    assertSame(store.current.orphanedPerks, frozenOrphans, "ordinary Free spend preserves frozen orphans")
end
do
    local state = newState(3, 0)
    state.accountingMode = "Free"
    state.perks.Axe = newPerk(7, 11)
    local before = clone(state)
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver, throwingFreeSentinels())
    local player = newPlayer("Axe", 0, 0)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "bad_mode", expectedRevision = 0 }, { mode = "Bogus" }), "allotment_invalid")
    assertEqual(store.loads, 0, "unknown allotment mode does not load")
    assertEqual(store.saves, 0, "unknown allotment mode does not save")
    assertEqual(store.accountingMode.calls, 0, "unknown allotment mode does not synchronize")
    assertEqual(resolver.resolveCount, 0, "unknown allotment mode does not resolve")
    assertEqual(adapter.ensureCalls, 0, "unknown allotment mode does not mutate engine")
    assertSame(store.current, before, "unknown allotment mode preserves persisted Free state")
end
do
    local state = newState(3, 0)
    state.perks.Axe = newPerk(3, 9)
    local frozen = clone(state.perks)
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    local result = service.spend(player, { perkId = "Axe", requestId = "transition_stale", expectedRevision = 0 }, { mode = "Free" })
    assertCode(result, "stale_revision")
    assertEqual(store.loads, 1)
    assertEqual(store.saves, 1, "Tracked-to-Free transition saves exactly once")
    assertEqual(store.current.accountingMode, "Free")
    assertEqual(store.current.revision, 1, "mode transition increments revision once")
    assertSame(store.current.perks, frozen, "Tracked-to-Free transition freezes perk map")
    assertEqual(resolver.resolveCount, 0, "transition-stale request does not resolve")
    assertEqual(adapter.ensureCalls, 0, "transition-stale request does not mutate engine")
end
do
    local cases = {
        { name = "misaligned", level = 1, position = 0, code = "misaligned_progression" },
        { name = "maxed", level = 3, position = 450, code = "at_maximum" },
    }
    for index = 1, #cases do
        local state = newState(3, 0)
        state.accountingMode = "Free"
        state.perks.Axe = newPerk(2, 6)
        local before = clone(state)
        local store = makeStore(state)
        local adapter, resolver = makeRuntime()
        local service = createService(store, adapter, resolver, throwingFreeSentinels())
        local player = newPlayer("Axe", cases[index].level, cases[index].position)
        assertCode(service.spend(player, { perkId = "Axe", requestId = "free_" .. cases[index].name, expectedRevision = 0 }, { mode = "Free" }), cases[index].code)
        assertEqual(store.saves, 0, "rejected Free validation does not save")
        assertEqual(adapter.ensureCalls, 0, "rejected Free validation does not mutate engine")
        assertSame(store.current, before, "rejected Free validation preserves state")
    end
end
do
    local state = newState(3, 0)
    state.accountingMode = "Free"
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver, throwingFreeSentinels())
    local player = newPlayer("Axe", 0, 0)
    local held = MutationScope.begin(player, "Axe")
    assertTrue(held.ok)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "free_scope", expectedRevision = 0 }, { mode = "Free" }), "scope_begin_failed")
    assertEqual(store.saves, 0)
    assertEqual(adapter.ensureCalls, 0)
    assertTrue(MutationScope.finish(held.handle).ok)
end
do
    local cases = {
        { name = "reservation", failSave = 1, code = "reservation_save_failed", engine = false },
        { name = "engine", behavior = { failNoWrite = true }, code = "engine_mutation_failed", engine = true },
        { name = "commit", failSave = 2, code = "commit_save_failed", engine = true },
    }
    for index = 1, #cases do
        local state = newState(3, 0)
        state.accountingMode = "Free"
        state.perks.Axe = newPerk(13, 21)
        local frozen = clone(state.perks)
        local store = makeStore(state)
        if cases[index].failSave then store.failSaveAt[cases[index].failSave] = true end
        local adapter, resolver = makeRuntime()
        local service = createService(store, adapter, resolver, throwingFreeSentinels())
        local player = newPlayer("Axe", 0, 0)
        if cases[index].behavior then player.behavior.Axe = cases[index].behavior end
        assertCode(service.spend(player, { perkId = "Axe", requestId = "free_" .. cases[index].name, expectedRevision = 0 }, { mode = "Free" }), cases[index].code)
        assertEqual(adapter.ensureCalls, cases[index].engine and 1 or 0)
        assertSame(store.current.perks, frozen, "Free failure preserves frozen perks")
        assertFalse(MutationScope.isActive(player, "Axe"), "Free failure cleans mutation scope")
    end
end
do
    local state = newState(2, 1)
    state.perks.Axe = newPerk(0, 0, { { targetId = "original_target", targetLevel = 1, targetPosition = 100 } })
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    local result = service.spend(player, { perkId = "Axe", requestId = "reboost", expectedRevision = 0 }, { mode = "Global", globalLimit = 0 })
    assertTrue(result.ok)
    assertFalse(result.addedTarget)
    assertEqual(result.spent, 2)
    assertEqual(#store.current.perks.Axe.activeTargets, 1)
    assertEqual(store.current.perks.Axe.observedPosition, 100, "existing-target AP commit persists final actual position")
    assertEqual(store.current.perks.Axe.activeTargets[1].targetId, "original_target")
end

-- Unexplained positive progress clears targets without reward/revision; negative progress creates red recovery.
do
    local state = newState(3, 0)
    state.survivor.xpIntoLevel = 77
    state.perks.Axe = newPerk(0, 0, { { targetId = "natural_clear", targetLevel = 1, targetPosition = 100 } })
    state.perks.Axe.postMaxFullRateUsed = 12
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 1, 100)
    ActualObservation.set(player, "Axe", 0)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "after_external", expectedRevision = 9 }, globalThree), "stale_revision")
    assertEqual(store.saves, 1)
    assertEqual(store.current.revision, 0)
    assertEqual(store.current.survivor.spent, 0)
    assertEqual(store.current.survivor.xpIntoLevel, 77)
    assertEqual(store.current.perks.Axe.postMaxFullRateUsed, 12)
    assertEqual(#store.current.perks.Axe.activeTargets, 0)
    assertEqual(store.current.perks.Axe.naturalPosition, 100)
    assertEqual(store.current.perks.Axe.highWaterPosition, 100)
    assertEqual(adapter.ensureCalls, 0)
end
do
    local state = newState(3, 0)
    state.perks.Axe = newPerk(100, 100)
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 50)
    ActualObservation.set(player, "Axe", 100)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "after_loss", expectedRevision = 0 }, globalThree), "red_recovery")
    assertEqual(store.current.perks.Axe.naturalPosition, 50)
    assertEqual(store.current.perks.Axe.highWaterPosition, 100)
    assertEqual(store.current.revision, 0)
    assertEqual(adapter.ensureCalls, 0)
end

-- Load, reservation, scope, and commit failures preserve the correct boundary.
do
    local store = makeStore(newState(3, 0))
    store.failLoad = true
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "load_fail", expectedRevision = 0 }, globalThree), "store_load_failed")
    assertEqual(adapter.ensureCalls, 0)
end
do
    local store = makeStore(newState(3, 0))
    store.failSaveAt[1] = true
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "reserve_fail", expectedRevision = 0 }, globalThree), "reservation_save_failed")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.current.inFlightAdvancement, nil)
    assertTrue(store.scopeAtReservation, "reservation failure occurs inside acquired scope")
    assertFalse(MutationScope.isActive(player, "Axe"), "reservation failure cleans scope")
end
do
    local store = makeStore(newState(3, 0))
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    local held = MutationScope.begin(player, "Axe")
    assertTrue(held.ok)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "scope_fail", expectedRevision = 0 }, globalThree), "scope_begin_failed")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.saves, 0, "scope collision must precede reservation write")
    assertEqual(store.current.inFlightAdvancement, nil)
    assertTrue(MutationScope.finish(held.handle).ok)
end
do
    local store = makeStore(newState(3, 0))
    store.failSaveAt[2] = true
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    assertCode(service.spend(player, { perkId = "Axe", requestId = "commit_fail", expectedRevision = 0 }, globalThree), "commit_save_failed")
    assertEqual(player.skills.Axe.level, 1)
    assertEqual(player.skills.Axe.position, 100)
    assertEqual(store.current.inFlightAdvancement.requestId, "commit_fail")
    assertEqual(store.current.survivor.spent, 0)
    assertEqual(store.current.revision, 0)
    assertFalse(MutationScope.isActive(player, "Axe"))
end

local function reservationState(options)
    options = options or {}
    local apCost = options.final and 2 or 1
    local state = newState(3, options.committed and apCost or 0)
    state.revision = options.committed and 1 or 0
    local prePosition = options.prePosition or (options.final and 250 or 0)
    state.perks.Axe = newPerk(options.natural or prePosition, options.high or options.natural or prePosition, options.targets or {})
    state.inFlightAdvancement = {
        requestId = options.requestId or "recover_one",
        perkId = "Axe",
        preRevision = 0,
        preSpent = 0,
        preLevel = options.preLevel or (options.final and 2 or 0),
        prePosition = prePosition,
        targetLevel = options.targetLevel or (options.final and 3 or 1),
        targetPosition = options.targetPosition or (options.final and 450 or 100),
        adapterId = "fake.adapter",
        adapterVersion = 1,
        curveFingerprint = options.fingerprint or "curve_Axe",
        effectiveMaximum = 3,
    }
    return state
end

-- Free recovery derives universal costs and completes without touching frozen accounting.
do
    local cases = {
        { final = false, level = 0, position = 0, cost = 1 },
        { final = true, level = 2, position = 250, cost = 2 },
    }
    for index = 1, #cases do
        local state = reservationState({ final = cases[index].final })
        state.accountingMode = "Free"
        state.perks.Axe.naturalPosition = 19
        state.perks.Axe.highWaterPosition = 37
        state.perks.Axe.activeTargets = { { targetId = "frozen", targetLevel = 2, targetPosition = 250 } }
        state.orphanedPerks.Old = newPerk(4, 8, {}, "Old")
        local frozenPerks = clone(state.perks)
        local frozenOrphans = clone(state.orphanedPerks)
        local store = makeStore(state)
        local adapter, resolver = makeRuntime()
        local service = createService(store, adapter, resolver, throwingFreeSentinels())
        local player = newPlayer("Axe", cases[index].level, cases[index].position)
        local result = service.recover(player)
        assertTrue(result.ok, "Free recovery succeeds")
        assertTrue(result.recovered)
        assertEqual(result.apCost, cases[index].cost)
        assertEqual(result.mastered, cases[index].final, "Free recovery reports final advancement semantics")
        assertFalse(result.addedTarget, "Free recovery never adds a target")
        assertEqual(#result.clearedTargetIds, 0, "Free recovery never clears targets")
        assertEqual(store.saves, 1, "Free recovery commits exactly once")
        assertEqual(store.current.revision, 1)
        assertEqual(store.current.survivor.spent, cases[index].cost)
        assertEqual(store.current.inFlightAdvancement, nil)
        assertSame(store.current.perks, frozenPerks, "Free recovery preserves frozen perks")
        assertSame(store.current.orphanedPerks, frozenOrphans, "Free recovery preserves frozen orphans")
    end
end

-- Recovery completes under the persisted mode before a requested transition is synchronized.
do
    local state = reservationState()
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 1, 100)
    local result = service.spend(player, { perkId = "Axe", requestId = "after_recovery_transition", expectedRevision = 0 }, { mode = "Free" })
    assertCode(result, "stale_revision")
    assertEqual(store.loads, 1, "recovery-transition spend loads once")
    assertEqual(store.saves, 2, "recovery and transition each save once")
    assertEqual(adapter.ensureCalls, 1, "only recovery mutates the engine")
    assertEqual(resolver.resolveCount, 1, "stale post-transition request does not resolve again")
    assertEqual(store.accountingMode.lastState.revision, 1, "synchronization receives recovered revision")
    assertEqual(store.accountingMode.lastState.inFlightAdvancement, nil, "synchronization receives completed recovery")
    assertEqual(store.current.accountingMode, "Free")
    assertEqual(store.current.revision, 2, "recovery and transition each increment revision once")
    assertEqual(store.current.survivor.spent, 1)
end

-- Loaded-state recovery returns the authoritative committed state without reloading.
do
    local store = makeStore(reservationState())
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 1, 100)
    local loaded = store.load(player, resolver.loadOptions)
    local result = service.recoverLoadedState(player, loaded.state)
    assertTrue(result.ok)
    assertTrue(result.recovered)
    assertEqual(store.loads, 1, "loaded reservation recovery performs no second load")
    assertEqual(store.saves, 1, "loaded reservation recovery commits once")
    assertEqual(result.state.revision, 1)
    assertEqual(result.state.survivor.spent, 1)
    assertEqual(result.state.inFlightAdvancement, nil)
    assertSame(result.state, store.current, "loaded recovery returns authoritative committed state")
end

-- XP-only interruption leaves a recoverable reservation; recovery completes once and cleans scope.
do
    local store = makeStore(newState(3, 0))
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    player.behavior.Axe = { failAfterXp = true }
    local failed = service.spend(player, { perkId = "Axe", requestId = "xp_only", expectedRevision = 0 }, globalThree)
    assertCode(failed, "engine_mutation_failed")
    assertEqual(player.skills.Axe.level, 0)
    assertEqual(player.skills.Axe.position, 100)
    assertEqual(store.current.inFlightAdvancement.requestId, "xp_only")
    assertFalse(MutationScope.isActive(player, "Axe"), "error scope cleanup")
    assertEqual(ActualObservation.get(player, "Axe").position, 100)
    player.behavior.Axe = nil
    local recovered = service.recover(player)
    assertTrue(recovered.ok)
    assertTrue(recovered.recovered)
    assertEqual(recovered.apCost, 1)
    assertFalse(recovered.mastered)
    assertEqual(#recovered.clearedTargetIds, 0)
    assertFalse(recovered.xpWriteInvoked)
    assertTrue(recovered.levelWriteInvoked)
    assertEqual(player.skills.Axe.level, 1)
    assertEqual(store.current.inFlightAdvancement, nil)
    assertEqual(store.current.revision, 1)
    assertEqual(store.current.survivor.spent, 1)
    assertEqual(#store.current.perks.Axe.activeTargets, 1)
    assertEqual(store.current.perks.Axe.activeTargets[1].targetId, "xp_only:revision:0")
    assertEqual(store.current.perks.Axe.observedPosition, 100, "crash recovery commit persists final actual position")
    assertFalse(MutationScope.isActive(player, "Axe"))
end

-- Direct commit and interrupted recovery derive the same target identity from persisted inputs.
do
    local directStore = makeStore(newState(3, 0))
    local directAdapter, directResolver = makeRuntime()
    local directService = createService(directStore, directAdapter, directResolver)
    local directPlayer = newPlayer("Axe", 0, 0)
    local direct = directService.spend(directPlayer, {
        perkId = "Axe", requestId = "path_equivalence", expectedRevision = 0,
    }, globalThree)
    assertTrue(direct.ok)

    local recoveryStore = makeStore(newState(3, 0))
    local recoveryAdapter, recoveryResolver = makeRuntime()
    local recoveryService = createService(recoveryStore, recoveryAdapter, recoveryResolver)
    local recoveryPlayer = newPlayer("Axe", 0, 0)
    recoveryPlayer.behavior.Axe = { failAfterXp = true }
    assertCode(recoveryService.spend(recoveryPlayer, {
        perkId = "Axe", requestId = "path_equivalence", expectedRevision = 0,
    }, globalThree), "engine_mutation_failed")
    recoveryPlayer.behavior.Axe = nil
    local recovered = recoveryService.recover(recoveryPlayer)
    assertTrue(recovered.ok)
    assertEqual(recovered.requestId, "path_equivalence")
    assertEqual(
        recoveryStore.current.perks.Axe.activeTargets[1].targetId,
        directStore.current.perks.Axe.activeTargets[1].targetId,
        "direct and recovery target identities match"
    )
    assertEqual(recoveryStore.current.perks.Axe.activeTargets[1].targetId, "path_equivalence:revision:0")
end

-- Final recovery derives two AP in reservation, engine-complete, and committed phases and remains idempotent.
do
    local targets = {
        { targetId = "old_one", targetLevel = 1, targetPosition = 100 },
        { targetId = "old_two", targetLevel = 2, targetPosition = 250 },
    }
    local store = makeStore(reservationState({ final = true, natural = 0, high = 0, targets = targets }))
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    local result = service.recover(player)
    assertTrue(result.ok, "pre-mutation final recovery succeeds: " .. tostring(result.code) .. ":" .. tostring(result.detail))
    assertTrue(result.recovered)
    assertEqual(result.apCost, 2)
    assertTrue(result.mastered)
    assertFalse(result.addedTarget)
    assertSame(result.clearedTargetIds, { "old_one", "old_two" }, "recovery mastery clear order")
    assertTrue(result.xpWriteInvoked)
    assertTrue(result.levelWriteInvoked)
    assertEqual(result.spent, 2)
    assertEqual(store.current.revision, 1)
    assertEqual(store.current.perks.Axe.naturalPosition, 450)
    assertEqual(store.current.perks.Axe.highWaterPosition, 450)
    assertEqual(store.current.perks.Axe.observedPosition, 450, "mastery recovery persists final actual position")
    assertEqual(#store.current.perks.Axe.activeTargets, 0)
    assertEqual(store.current.inFlightAdvancement, nil)
    local repeated = service.recover(player)
    assertTrue(repeated.ok, "repeated final recovery succeeds: " .. tostring(repeated.code) .. ":" .. tostring(repeated.detail))
    assertFalse(repeated.recovered)
    assertEqual(store.saves, 1)
end
do
    local store = makeStore(reservationState({ final = true, natural = 0, high = 0, targets = { { targetId = "old", targetLevel = 2, targetPosition = 250 } } }))
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 3, 450)
    local result = service.recover(player)
    assertTrue(result.ok, "engine-complete final recovery succeeds: " .. tostring(result.code) .. ":" .. tostring(result.detail))
    assertEqual(result.apCost, 2)
    assertTrue(result.mastered)
    assertFalse(result.xpWriteInvoked)
    assertFalse(result.levelWriteInvoked)
    assertEqual(result.spent, 2)
    assertEqual(#store.current.perks.Axe.activeTargets, 0)
end
do
    local state = reservationState({ final = true, committed = true })
    state.perks.Axe.naturalPosition = 450
    state.perks.Axe.highWaterPosition = 450
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 3, 450)
    local result = service.recover(player)
    assertTrue(result.ok, "committed final recovery succeeds: " .. tostring(result.code) .. ":" .. tostring(result.detail))
    assertEqual(result.apCost, 2)
    assertTrue(result.mastered)
    assertEqual(result.spent, 2)
    assertEqual(result.revision, 1)
    assertEqual(store.current.inFlightAdvancement, nil)
end

-- A recorded final target whose adapter maximum changes is quarantined without mutation.
do
    local store = makeStore(reservationState({ final = true }))
    local adapter, resolver, handles = makeRuntime()
    resolver.resolve("Axe")
    handles.Axe.effectiveMaximum = 4
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    assertCode(service.recover(player), "recovery_quarantined")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.saves, 0)
    assertEqual(store.current.inFlightAdvancement.effectiveMaximum, 3)
end
do
    local state = reservationState({ final = true })
    state.survivor.level = 1
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    assertCode(service.recover(player), "recovery_quarantined")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.saves, 0)
    assertEqual(store.current.inFlightAdvancement.requestId, "recover_one")
end
do
    local state = reservationState({ final = true, natural = 200, high = 450 })
    local before = clone(state)
    local store = makeStore(state)
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 2, 250)
    local result = service.recover(player)
    assertCode(result, "recovery_quarantined")
    assertEqual(result.detail, "natural_recovery_required")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.saves, 0)
    assertEqual(player.skills.Axe.level, 2)
    assertEqual(player.skills.Axe.position, 250)
    assertSame(store.current, before, "red final reservation remains unchanged")
end

-- Already-complete and committed-but-not-cleared reservations normalize without duplicate writes/targets.
do
    local store = makeStore(reservationState())
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 1, 100)
    local result = service.recover(player)
    assertTrue(result.ok)
    assertTrue(result.recovered)
    assertFalse(result.xpWriteInvoked)
    assertFalse(result.levelWriteInvoked)
    assertTrue(result.addedTarget)
    assertEqual(store.current.revision, 1)
    assertEqual(store.current.survivor.spent, 1)
end
do
    local target = { targetId = "recover_one", targetLevel = 1, targetPosition = 100 }
    local store = makeStore(reservationState({ committed = true, targets = { target } }))
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 1, 100)
    local result = service.recover(player)
    assertTrue(result.ok)
    assertFalse(result.addedTarget)
    assertEqual(store.current.revision, 1)
    assertEqual(store.current.survivor.spent, 1)
    assertEqual(#store.current.perks.Axe.activeTargets, 1)
    assertEqual(store.current.perks.Axe.activeTargets[1].targetId, "recover_one", "legacy committed target identity is preserved")
    local second = service.recover(player)
    assertTrue(second.ok)
    assertFalse(second.recovered)
    assertEqual(store.saves, 1, "idempotent no-reservation recovery performs no write")
end

-- Recovery identity mismatch, target conflict, downward state, and save failure quarantine the reservation.
do
    local store = makeStore(reservationState({ fingerprint = "old_curve" }))
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    assertCode(service.recover(player), "recovery_quarantined")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.saves, 0)
    assertEqual(store.current.inFlightAdvancement.fingerprint, nil)
    assertEqual(store.current.inFlightAdvancement.curveFingerprint, "old_curve")
end
do
    local conflict = { targetId = "recover_one", targetLevel = 2, targetPosition = 250 }
    local store = makeStore(reservationState({ targets = { conflict } }))
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    assertCode(service.recover(player), "recovery_quarantined")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.current.inFlightAdvancement.requestId, "recover_one")
end
do
    local store = makeStore(reservationState({ prePosition = 50, targetPosition = 100 }))
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 0, 0)
    assertCode(service.recover(player), "recovery_quarantined")
    assertEqual(adapter.ensureCalls, 0)
    assertEqual(store.saves, 0)
end
do
    local store = makeStore(reservationState())
    store.failSaveAt[1] = true
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 1, 100)
    assertCode(service.recover(player), "recovery_quarantined")
    assertEqual(store.current.inFlightAdvancement.requestId, "recover_one")
    assertEqual(store.current.revision, 0)
    assertEqual(store.current.survivor.spent, 0)
end

-- spend() recovers a prior commit before validating the new request revision.
do
    local store = makeStore(reservationState())
    local adapter, resolver = makeRuntime()
    local service = createService(store, adapter, resolver)
    local player = newPlayer("Axe", 1, 100)
    local result = service.spend(player, { perkId = "Axe", requestId = "new_after_recovery", expectedRevision = 0 }, globalThree)
    assertCode(result, "stale_revision")
    assertEqual(store.current.inFlightAdvancement, nil)
    assertEqual(store.current.revision, 1)
    assertEqual(store.current.survivor.spent, 1)
end

return assertions
