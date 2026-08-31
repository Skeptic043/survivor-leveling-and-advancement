local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if condition ~= true then error(message or "expected true", 0) end
end

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 0)
    end
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("cycle in fixture", 0) end
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

local function sameTable(actual, expected, message)
    assertions = assertions + 1
    if not same(actual, expected) then error(message or "tables differ", 0) end
end

local NAMESPACE = "SurvivorLevelingAdvancement"
local CURVE_A = {
    adapterId = "curve.adapter",
    adapterVersion = 1,
    curveFingerprint = "curve.a",
    effectiveMaximum = 3,
}
local CURVE_B = {
    adapterId = "curve.adapter",
    adapterVersion = 2,
    curveFingerprint = "curve.b",
    effectiveMaximum = 4,
}
local OTHER = {
    adapterId = "other.adapter",
    adapterVersion = 1,
    curveFingerprint = "other.curve",
    effectiveMaximum = 3,
}
local OLD = {
    adapterId = "old.adapter",
    adapterVersion = 1,
    curveFingerprint = "old.curve",
    effectiveMaximum = 2,
}

local function perk(spec, natural, highWater, targets, postMaxUsed, observed)
    local record = {
        adapterId = spec.adapterId,
        adapterVersion = spec.adapterVersion,
        curveFingerprint = spec.curveFingerprint,
        effectiveMaximum = spec.effectiveMaximum,
        naturalPosition = natural,
        highWaterPosition = highWater,
        activeTargets = targets or {},
        postMaxFullRateUsed = postMaxUsed or 0,
    }
    if observed ~= nil then record.observedPosition = observed end
    return record
end

local function curveAState()
    return {
        schemaVersion = 3,
        accountingMode = "Tracked",
        revision = 7,
        survivor = { level = 5, xpIntoLevel = 25, spent = 2 },
        perks = {
            X = perk(CURVE_A, 120, 200, {
                { targetId = "old_target", targetLevel = 3, targetPosition = 450 },
            }, 33, 450),
            Woodwork = perk(OTHER, 15, 15, {}, 2, 15),
        },
        orphanedPerks = {
            OldSkill = perk(OLD, 5, 5, {}, 4, 5),
        },
        inFlightAdvancement = nil,
    }
end

local function curveBRecord(position)
    return perk(CURVE_B, position, position, {}, 0, position)
end

local function loadOptions(spec)
    return {
        loadedPerks = {
            X = clone(spec or CURVE_B),
            Woodwork = clone(OTHER),
        },
    }
end

local function encoded(state)
    local result = StateCodec.encode(state)
    expect(result.ok, "fixture encodes through real StateCodec")
    return result.state
end

local function playerWith(state, level, position)
    local player = {
        modData = { [NAMESPACE] = encoded(state) },
        skills = { X = { level = level or 2, position = position or 250 } },
    }
    function player:getModData() return self.modData end
    return player
end

local function realPlayerStore(codec)
    local created = PlayerStateStore.create(codec or StateCodec)
    expect(created.ok, "real PlayerStateStore creation")
    return created.store
end

local function runtime(options)
    options = options or loadOptions(CURVE_B)
    local thresholds = { [0] = 0, 100, 250, 450, 700 }
    local adapter = { ensureCalls = 0 }
    local resolver = { loadOptions = options, resolveCalls = 0 }

    function adapter.describe(handle)
        return {
            ok = true,
            adapterId = CURVE_B.adapterId,
            adapterVersion = CURVE_B.adapterVersion,
            curveFingerprint = CURVE_B.curveFingerprint,
            effectiveMaximum = CURVE_B.effectiveMaximum,
            cumulativeThresholds = thresholds,
        }
    end

    function adapter.inspect(handle, player)
        local skill = player.skills.X
        local derivedLevel = 0
        for candidate = 1, CURVE_B.effectiveMaximum do
            if skill.position >= thresholds[candidate] then derivedLevel = candidate end
        end
        local nextLevel = nil
        local nextPosition = nil
        if skill.level < CURVE_B.effectiveMaximum then
            nextLevel = skill.level + 1
            nextPosition = thresholds[nextLevel]
        end
        return {
            ok = true,
            adapterId = CURVE_B.adapterId,
            adapterVersion = CURVE_B.adapterVersion,
            curveFingerprint = CURVE_B.curveFingerprint,
            effectiveMaximum = CURVE_B.effectiveMaximum,
            storedLevel = skill.level,
            actualPosition = skill.position,
            nextTargetLevel = nextLevel,
            nextTargetPosition = nextPosition,
            levelAligned = skill.level == derivedLevel,
            alignment = skill.level == derivedLevel and "aligned" or "unaligned",
        }
    end

    function adapter.ensureTarget(handle, player, targetLevel, targetPosition)
        adapter.ensureCalls = adapter.ensureCalls + 1
        local skill = player.skills.X
        local xpWrite = false
        local levelWrite = false
        if skill.position < targetPosition then skill.position = targetPosition; xpWrite = true end
        if skill.level < targetLevel then skill.level = targetLevel; levelWrite = true end
        return {
            ok = true,
            storedLevel = skill.level,
            actualPosition = skill.position,
            xpWriteInvoked = xpWrite,
            levelWriteInvoked = levelWrite,
        }
    end

    function resolver.resolve(perkId)
        resolver.resolveCalls = resolver.resolveCalls + 1
        if perkId ~= "X" then return { ok = false, code = "unsupported", detail = perkId } end
        return { ok = true, adapter = adapter, handle = { perkId = perkId } }
    end
    return adapter, resolver
end

local AccountingMode = {}
function AccountingMode.synchronizeLoaded(player, state, desiredMode)
    if state.accountingMode ~= desiredMode then
        return { ok = false, code = "unexpected_transition", detail = state.accountingMode .. ":" .. desiredMode }
    end
    return {
        ok = true,
        state = state,
        transitioned = false,
        fromMode = desiredMode,
        toMode = desiredMode,
    }
end

local function services(store, resolver)
    local apCreated = ApTransaction.create({
        NaturalLedger = NaturalLedger,
        SurvivorEconomy = SurvivorEconomy,
        Allotment = Allotment,
        MutationScope = MutationScope,
        PlayerStateStore = store,
        ActualObservation = ActualObservation,
        AccountingMode = AccountingMode,
        resolver = resolver,
    })
    expect(apCreated.ok, "AP service creation")
    local awardCreated = SupportedAwardProcessor.create({
        NaturalLedger = NaturalLedger,
        SurvivorEconomy = SurvivorEconomy,
        PostMax = PostMax,
        MutationScope = MutationScope,
        PlayerStateStore = store,
        ActualObservation = ActualObservation,
        AccountingMode = AccountingMode,
        resolver = resolver,
        recoveryService = apCreated.service,
    })
    expect(awardCreated.ok, "award service creation")
    return apCreated.service, awardCreated.service
end

local function trackedSettings()
    return {
        accountingMode = "Tracked",
        normalization = 1,
        survivorMultiplier = 1,
        postMax = { enabled = false, fullRateAllowance = 0, diminishedRate = 0 },
    }
end

local function freeSettings()
    local settings = trackedSettings()
    settings.accountingMode = "Free"
    return settings
end

local GLOBAL_THREE = { mode = "Global", globalLimit = 3 }

local function award(appliedDelta)
    return {
        perkId = "X",
        survivorCreditBase = 20,
        appliedDelta = appliedDelta or 25,
        actualPositionBefore = 250,
        actualPositionAfter = 275,
    }
end

local function countingStore(store)
    local wrapper = { saves = 0 }
    function wrapper.load(player, options) return store.load(player, options) end
    function wrapper.save(player, state)
        wrapper.saves = wrapper.saves + 1
        return store.save(player, state)
    end
    return wrapper
end

-- Reproduce the original codec deadlock and preserve normal compatible restoration.
do
    local player = playerWith(curveAState(), 2, 275)
    local store = realPlayerStore()
    local loaded = store.load(player, loadOptions(CURVE_B))
    expect(loaded.ok, "curve-B compatibility decode succeeds")
    equal(loaded.state.perks.X, nil, "changed curve has no active record")
    expect(loaded.state.orphanedPerks.X ~= nil, "changed curve becomes an orphan")
    loaded.state.perks.X = curveBRecord(250)
    local duplicate = StateCodec.encode(loaded.state)
    expect(not duplicate.ok, "old replacement candidate reproduces codec failure")
    equal(duplicate.code, "invalid_state", "duplicate codec failure code")
    equal(duplicate.detail, "duplicate_perk:X", "duplicate codec failure detail")

    local returning = curveAState()
    returning.orphanedPerks.X = returning.perks.X
    returning.perks.X = nil
    local returningPlayer = playerWith(returning, 2, 250)
    local restored = store.load(returningPlayer, loadOptions(CURVE_A))
    expect(restored.ok, "compatible returning orphan decodes")
    expect(restored.state.perks.X ~= nil, "compatible returning orphan restores active")
    equal(restored.state.orphanedPerks.X, nil, "compatible returning orphan is removed")
end

-- A tracked award replaces only the mismatched same-ID orphan and credits once.
do
    local initial = curveAState()
    local unrelatedActive = clone(initial.perks.Woodwork)
    local unrelatedOrphan = clone(initial.orphanedPerks.OldSkill)
    local player = playerWith(initial, 2, 275)
    local store = realPlayerStore()
    local adapter, resolver = runtime()
    local _, processor = services(store, resolver)
    local result = processor.process(player, award(), trackedSettings())
    expect(result.ok, "curve-B award succeeds through real codec/store")
    equal(result.survivorXp, 20, "triggering award credited exactly once")
    equal(result.levelsGained, 0, "replacement invents no Survivor level")
    expect(result.stateWritten, "replacement award writes state")
    local saved = player.modData[NAMESPACE]
    expect(saved.perks.X ~= nil, "curve-B active record persisted")
    equal(saved.perks.X.adapterVersion, CURVE_B.adapterVersion, "current adapter version persisted")
    equal(saved.perks.X.curveFingerprint, CURVE_B.curveFingerprint, "current curve persisted")
    equal(saved.perks.X.effectiveMaximum, CURVE_B.effectiveMaximum, "current maximum persisted")
    equal(saved.perks.X.naturalPosition, 275, "award baselines before and applies once")
    equal(saved.perks.X.highWaterPosition, 275, "award establishes only current high water")
    equal(#saved.perks.X.activeTargets, 0, "old targets are not translated")
    equal(saved.perks.X.postMaxFullRateUsed, 0, "old post-max usage is not translated")
    equal(saved.orphanedPerks.X, nil, "mismatched same-ID orphan retired")
    equal(saved.survivor.level, 5, "Survivor level preserved")
    equal(saved.survivor.xpIntoLevel, 45, "Survivor XP credited once")
    equal(saved.survivor.spent, 2, "spent AP preserved without refund")
    equal(saved.revision, 7, "ordinary award preserves revision")
    sameTable(saved.perks.Woodwork, unrelatedActive, "unrelated active record preserved")
    sameTable(saved.orphanedPerks.OldSkill, unrelatedOrphan, "unrelated orphan preserved")
    local encodedSaved = StateCodec.encode(saved)
    expect(encodedSaved.ok, "award output has no active/orphan duplicate")
    equal(adapter.ensureCalls, 0, "ordinary award performs no AP engine mutation")
end

-- A rejected tracked award leaves the original encoded state recoverable.
do
    local initial = curveAState()
    local player = playerWith(initial, 2, 275)
    local original = clone(player.modData[NAMESPACE])
    local realStore = realPlayerStore()
    local store = countingStore(realStore)
    local _, resolver = runtime()
    local _, processor = services(store, resolver)
    local result = processor.process(player, award(24), trackedSettings())
    expect(not result.ok, "invalid triggering award is rejected")
    equal(store.saves, 0, "rejected award performs no save")
    sameTable(player.modData[NAMESPACE], original, "rejected award preserves encoded curve-A state")
end

-- A tracked AP spend reserves, mutates, and commits once on the new curve.
do
    local initial = curveAState()
    local unrelatedActive = clone(initial.perks.Woodwork)
    local unrelatedOrphan = clone(initial.orphanedPerks.OldSkill)
    local player = playerWith(initial, 2, 250)
    local store = realPlayerStore()
    local adapter, resolver = runtime()
    local ap = services(store, resolver)
    local result = ap.spend(player, { perkId = "X", requestId = "curve_b_spend", expectedRevision = 7 }, GLOBAL_THREE)
    expect(result.ok, "curve-B AP spend succeeds through real codec/store")
    equal(result.apCost, 1, "ordinary curve-B advancement costs one AP")
    equal(result.spent, 3, "AP charged exactly once")
    equal(result.revision, 8, "AP revision increments exactly once")
    equal(adapter.ensureCalls, 1, "engine mutation invoked exactly once")
    equal(player.skills.X.level, 3, "stored perk level advanced")
    equal(player.skills.X.position, 450, "actual XP advanced to curve-B threshold")
    local saved = player.modData[NAMESPACE]
    expect(saved.perks.X ~= nil, "curve-B AP accounting persisted")
    equal(saved.perks.X.adapterVersion, CURVE_B.adapterVersion, "AP record uses current adapter")
    equal(saved.perks.X.naturalPosition, 250, "AP replacement baselines authoritative actual position")
    equal(saved.perks.X.highWaterPosition, 250, "AP replacement does not translate old high water")
    equal(#saved.perks.X.activeTargets, 1, "AP creates only the current target")
    equal(saved.perks.X.activeTargets[1].targetLevel, 3, "current target level persisted")
    equal(saved.perks.X.activeTargets[1].targetPosition, 450, "current target position persisted")
    equal(saved.orphanedPerks.X, nil, "AP replacement retires same-ID orphan")
    equal(saved.survivor.level, 5, "AP replacement preserves Survivor level")
    equal(saved.survivor.xpIntoLevel, 25, "AP replacement preserves Survivor XP")
    equal(saved.survivor.spent, 3, "committed AP total persisted")
    equal(saved.inFlightAdvancement, nil, "successful commit clears reservation")
    sameTable(saved.perks.Woodwork, unrelatedActive, "AP preserves unrelated active record")
    sameTable(saved.orphanedPerks.OldSkill, unrelatedOrphan, "AP preserves unrelated orphan")
    expect(StateCodec.encode(saved).ok, "AP output has no active/orphan duplicate")
end

-- Rejection before reservation does not persist the replacement.
do
    local player = playerWith(curveAState(), 2, 250)
    local original = clone(player.modData[NAMESPACE])
    local realStore = realPlayerStore()
    local store = countingStore(realStore)
    local adapter, resolver = runtime()
    local ap = services(store, resolver)
    local result = ap.spend(player, { perkId = "X", requestId = "stale_spend", expectedRevision = 6 }, GLOBAL_THREE)
    expect(not result.ok, "stale AP spend rejected")
    equal(result.code, "stale_revision", "stale AP failure remains stable")
    equal(store.saves, 0, "rejected AP spend performs no persistence")
    equal(adapter.ensureCalls, 0, "rejected AP spend performs no engine mutation")
    sameTable(player.modData[NAMESPACE], original, "rejected AP spend preserves encoded curve-A state")
end

-- Reservation save failure uses the real store boundary and cannot mutate the engine.
do
    local player = playerWith(curveAState(), 2, 250)
    local original = clone(player.modData[NAMESPACE])
    local failingCodec = {
        decode = StateCodec.decode,
        encode = function() return { ok = false, code = "fixture_save_failed", detail = "codec" } end,
    }
    local store = realPlayerStore(failingCodec)
    local adapter, resolver = runtime()
    local ap = services(store, resolver)
    local result = ap.spend(player, { perkId = "X", requestId = "failed_reservation", expectedRevision = 7 }, GLOBAL_THREE)
    expect(not result.ok, "reservation save failure is returned")
    equal(result.code, "reservation_save_failed", "reservation save failure code")
    equal(adapter.ensureCalls, 0, "save failure performs no engine mutation")
    equal(player.skills.X.level, 2, "save failure preserves engine level")
    equal(player.skills.X.position, 250, "save failure preserves engine position")
    expect(not MutationScope.isActive(player, "X"), "save failure releases mutation scope")
    sameTable(player.modData[NAMESPACE], original, "save failure leaves original state recoverable")
end

-- A same-identity orphan candidate is inconsistent and fails closed in both paths.
do
    local candidate = curveAState()
    candidate.perks.X = nil
    candidate.orphanedPerks.X = curveBRecord(250)
    local function fakeStore()
        local store = { state = clone(candidate), saves = 0 }
        function store.load() return { ok = true, state = clone(store.state) } end
        function store.save(player, state) store.saves = store.saves + 1; store.state = clone(state); return { ok = true } end
        return store
    end

    local awardStore = fakeStore()
    local awardAdapter, awardResolver = runtime()
    local _, processor = services(awardStore, awardResolver)
    local awardPlayer = playerWith(curveAState(), 2, 275)
    local awardResult = processor.process(awardPlayer, award(), trackedSettings())
    expect(not awardResult.ok, "same-identity award candidate fails closed")
    equal(awardResult.code, "perk_quarantined", "same-identity award failure code")
    equal(awardResult.detail, "same_identity_orphan", "same-identity award failure detail")
    equal(awardStore.saves, 0, "same-identity award candidate is not saved")
    equal(awardAdapter.ensureCalls, 0, "same-identity award performs no engine mutation")

    local apStore = fakeStore()
    local apAdapter, apResolver = runtime()
    local ap = services(apStore, apResolver)
    local apPlayer = playerWith(curveAState(), 2, 250)
    local apResult = ap.spend(apPlayer, { perkId = "X", requestId = "same_identity", expectedRevision = 7 }, GLOBAL_THREE)
    expect(not apResult.ok, "same-identity AP candidate fails closed")
    equal(apResult.code, "perk_quarantined", "same-identity AP failure code")
    equal(apResult.detail, "same_identity_orphan", "same-identity AP failure detail")
    equal(apStore.saves, 0, "same-identity AP candidate is not saved")
    equal(apAdapter.ensureCalls, 0, "same-identity AP performs no engine mutation")
end

-- A reservation made under curve A remains quarantined under curve B.
do
    local state = curveAState()
    state.perks.X = perk(CURVE_A, 200, 250, {}, 0, 250)
    state.inFlightAdvancement = {
        requestId = "curve_a_reservation",
        perkId = "X",
        preRevision = 7,
        preSpent = 2,
        preLevel = 2,
        prePosition = 250,
        targetLevel = 3,
        targetPosition = 450,
        adapterId = CURVE_A.adapterId,
        adapterVersion = CURVE_A.adapterVersion,
        curveFingerprint = CURVE_A.curveFingerprint,
        effectiveMaximum = CURVE_A.effectiveMaximum,
    }
    local player = playerWith(state, 2, 250)
    local original = clone(player.modData[NAMESPACE])
    local store = realPlayerStore()
    local adapter, resolver = runtime()
    local ap = services(store, resolver)
    local result = ap.spend(player, { perkId = "X", requestId = "later_request", expectedRevision = 7 }, GLOBAL_THREE)
    expect(not result.ok, "changed in-flight reservation is quarantined")
    equal(result.code, "recovery_quarantined", "changed reservation failure code")
    equal(result.detail, "adapter_identity_mismatch", "changed reservation failure detail")
    equal(adapter.ensureCalls, 0, "quarantined reservation performs no engine mutation")
    sameTable(player.modData[NAMESPACE], original, "quarantined reservation remains recoverable")
end

-- Free mode preserves frozen same-ID history and never runs replacement.
do
    local state = curveAState()
    state.accountingMode = "Free"
    state.orphanedPerks.X = state.perks.X
    state.perks.X = nil
    local frozen = clone(state.orphanedPerks.X)
    local player = playerWith(state, 2, 275)
    local store = realPlayerStore()
    local _, resolver = runtime()
    local _, processor = services(store, resolver)
    local beforeResolve = resolver.resolveCalls
    local result = processor.process(player, award(), freeSettings())
    expect(result.ok, "Free award succeeds with frozen changed history")
    equal(resolver.resolveCalls, beforeResolve, "Free award does not resolve current curve")
    sameTable(player.modData[NAMESPACE].orphanedPerks.X, frozen, "Free award preserves frozen same-ID orphan")
    equal(player.modData[NAMESPACE].perks.X, nil, "Free award creates no tracked record")
end

-- Proportional multiplayer proof through the real canonical server state store.
do
    local roots = {}
    local serverPlayer = { modData = {}, skills = { X = { level = 2, position = 275 } } }
    function serverPlayer:getModData() return self.modData end
    local identity = {}
    function identity.resolve()
        return { ok = true, owner = { kind = "mp", primaryLoginUsername = "curve_tester", profileIndex = 0 } }
    end
    local legacyStateStore = realPlayerStore()
    local legacyCharacterStore = {}
    function legacyCharacterStore.inspect()
        return {
            ok = true,
            metadata = {
                tokenPresent = false,
                tokenValid = false,
                initialized = false,
                deathRecorded = false,
                codecPresent = false,
            },
        }
    end
    local function getOrCreate(tag) return roots[tag] or {} end
    local function add(tag, value) roots[tag] = value; return true end
    local created = ServerPlayerRecordStore.create({
        codec = StateCodec,
        identity = identity,
        legacyStateStore = legacyStateStore,
        legacyCharacterStore = legacyCharacterStore,
        getOrCreate = getOrCreate,
        add = add,
    })
    expect(created.ok, "real server player record store creation")
    expect(created.stateStore.save(serverPlayer, curveAState()).ok, "curve-A canonical server state seeded")
    local adapter, resolver = runtime()
    local _, processor = services(created.stateStore, resolver)
    local result = processor.process(serverPlayer, award(), trackedSettings())
    expect(result.ok, "server-owned curve-B award replacement succeeds")
    local canonical = roots.SLA_ServerPlayers_v1.players.curve_tester[0].state
    expect(canonical.perks.X ~= nil, "server canonical state contains curve-B active record")
    equal(canonical.perks.X.curveFingerprint, CURVE_B.curveFingerprint, "server canonical state uses current curve")
    equal(canonical.orphanedPerks.X, nil, "server canonical state retires same-ID orphan")
    sameTable(canonical.orphanedPerks.OldSkill, curveAState().orphanedPerks.OldSkill, "server canonical state preserves unrelated orphan")
    expect(StateCodec.encode(canonical).ok, "server canonical output has no duplicate ID")
    equal(adapter.ensureCalls, 0, "server award replacement performs no AP engine mutation")
end

return assertions
