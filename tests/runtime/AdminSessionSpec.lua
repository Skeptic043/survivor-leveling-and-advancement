local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed") end
end

local function expectEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
    end
end

local function exactKeys(value, expected, message)
    expect(type(value) == "table", (message or "table") .. " type")
    local count = 0
    for key in pairs(value) do
        count = count + 1
        expect(expected[key] == true, (message or "table") .. " unexpected key " .. tostring(key))
    end
    local expectedCount = 0
    for key in pairs(expected) do
        expectedCount = expectedCount + 1
        expect(value[key] ~= nil, (message or "table") .. " missing key " .. tostring(key))
    end
    expectEqual(count, expectedCount, (message or "table") .. " key count")
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
    if type(left) ~= "table" then
        if type(left) == "number" and left ~= left and right ~= right then return true end
        return left == right
    end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not deepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function sequenceEquals(actual, expected, message)
    expectEqual(#actual, #expected, (message or "sequence") .. " length")
    for index = 1, #expected do
        expectEqual(actual[index], expected[index], (message or "sequence") .. " item " .. index)
    end
end

local function assertFailure(result, code, message)
    exactKeys(result, { ok = true, code = true, detail = true, committed = true }, message or "failure")
    expectEqual(result.ok, false, (message or "failure") .. " ok")
    expectEqual(result.code, code, (message or "failure") .. " code")
    expect(type(result.detail) == "string" and #result.detail > 0, (message or "failure") .. " detail")
    expectEqual(result.committed, false, (message or "failure") .. " committed")
end

local function baseState()
    return {
        accountingMode = "Tracked",
        revision = 7,
        survivor = { level = 2, xpIntoLevel = 100, spent = 1 },
        perks = {
            Axe = {
                adapterId = "core",
                adapterVersion = 1,
                curveFingerprint = "curve",
                effectiveMaximum = 10,
                naturalPosition = 42.25,
                highWaterPosition = 61.5,
                activeTargets = { { targetId = "r1", targetLevel = 3, targetPosition = 75.5 } },
                postMaxFullRateUsed = 3.75,
            },
        },
        orphanedPerks = { Old = { marker = "preserve" } },
        privateRoot = { nested = { 1, 2, 3 } },
    }
end

local function fixture(configure)
    local calls = {}
    local state = baseState()
    local original = deepCopy(state)
    local target = {}
    local options = { published = { Axe = true } }
    local savedStates = {}
    local applyInputs = {}
    local dependencies = {
        store = {
            load = function(actualTarget, actualOptions)
                calls[#calls + 1] = "load"
                expectEqual(actualTarget, target, "load target identity")
                expectEqual(actualOptions, options, "load options identity")
                return { ok = true, state = state }
            end,
            save = function(actualTarget, candidate)
                calls[#calls + 1] = "save"
                expectEqual(actualTarget, target, "save target identity")
                savedStates[#savedStates + 1] = candidate
                return { ok = true }
            end,
        },
        catalog = { resolver = { loadOptions = options } },
        ownerSession = {
            isReady = function(actualTarget)
                calls[#calls + 1] = "ready"
                expectEqual(actualTarget, target, "ready target identity")
                return true
            end,
        },
        SurvivorEconomy = {
            nextLevelCost = function(level)
                calls[#calls + 1] = "cost"
                return SurvivorEconomy.nextLevelCost(level)
            end,
            availableAp = function(survivor)
                calls[#calls + 1] = "available"
                return SurvivorEconomy.availableAp(survivor)
            end,
            applyXp = function(survivor, amount)
                calls[#calls + 1] = "apply"
                applyInputs[#applyInputs + 1] = { survivor = survivor, amount = amount }
                return SurvivorEconomy.applyXp(survivor, amount)
            end,
        },
    }
    local values = {
        calls = calls,
        state = state,
        original = original,
        target = target,
        options = options,
        savedStates = savedStates,
        applyInputs = applyInputs,
        dependencies = dependencies,
    }
    if configure then configure(dependencies, values) end
    local created = AdminSession.create(dependencies)
    expectEqual(created.ok, true, "session creates")
    exactKeys(created, { ok = true, session = true }, "creation result")
    return created.session, values
end

assertFailure(AdminSession.create(nil), "invalid_dependencies", "nil dependencies")
assertFailure(AdminSession.create({}), "invalid_dependencies", "missing dependencies")
assertFailure(AdminSession.create(setmetatable({}, {})), "invalid_dependencies", "metatable dependencies")
do
    local dependencies = {
        store = { load = function() end, save = function() end },
        catalog = { resolver = { loadOptions = {} } },
        ownerSession = { isReady = function() end },
        SurvivorEconomy = {
            nextLevelCost = function() end,
            availableAp = function() end,
            applyXp = function() end,
        },
        extra = true,
    }
    assertFailure(AdminSession.create(dependencies), "invalid_dependencies", "extra dependency")
    dependencies.extra = nil
    dependencies.store.save = nil
    assertFailure(AdminSession.create(dependencies), "invalid_dependencies", "missing save")
    dependencies.store.save = function() end
    dependencies.catalog.resolver.loadOptions = nil
    assertFailure(AdminSession.create(dependencies), "invalid_dependencies", "missing load options")
    dependencies.catalog.resolver.loadOptions = {}
    dependencies.ownerSession.isReady = nil
    assertFailure(AdminSession.create(dependencies), "invalid_dependencies", "missing readiness")
    dependencies.ownerSession.isReady = function() end
    dependencies.SurvivorEconomy.applyXp = nil
    assertFailure(AdminSession.create(dependencies), "invalid_dependencies", "missing apply XP")
end
do
    local function validDependencies()
        return {
            store = { load = function() end, save = function() end },
            catalog = { resolver = { loadOptions = {} } },
            ownerSession = { isReady = function() end },
            SurvivorEconomy = {
                nextLevelCost = function() end,
                availableAp = function() end,
                applyXp = function() end,
            },
        }
    end
    local dependencies = validDependencies()
    dependencies.store = setmetatable(dependencies.store, {})
    assertFailure(AdminSession.create(dependencies), "invalid_dependencies", "metatable store")
    dependencies = validDependencies()
    dependencies.catalog.resolver = setmetatable(dependencies.catalog.resolver, {})
    assertFailure(AdminSession.create(dependencies), "invalid_dependencies", "metatable resolver")
    dependencies = validDependencies()
    dependencies.ownerSession = setmetatable(dependencies.ownerSession, {})
    assertFailure(AdminSession.create(dependencies), "invalid_dependencies", "metatable owner session")
    dependencies = validDependencies()
    dependencies.SurvivorEconomy = setmetatable(dependencies.SurvivorEconomy, {})
    assertFailure(AdminSession.create(dependencies), "invalid_dependencies", "metatable economy")
end

do
    local session, values = fixture()
    local result = session.inspect(values.target)
    exactKeys(result, { ok = true, summary = true }, "inspection result")
    expectEqual(result.ok, true, "inspection succeeds")
    exactKeys(result.summary, {
        accountingMode = true,
        revision = true,
        level = true,
        xpIntoLevel = true,
        xpForNextLevel = true,
        spent = true,
        availableAp = true,
    }, "inspection summary")
    expectEqual(result.summary.accountingMode, "Tracked", "inspection accounting mode")
    expectEqual(result.summary.revision, 7, "inspection revision")
    expectEqual(result.summary.level, 2, "inspection level")
    expectEqual(result.summary.xpIntoLevel, 100, "inspection XP")
    expectEqual(result.summary.xpForNextLevel, 1800, "inspection level cost")
    expectEqual(result.summary.spent, 1, "inspection spent")
    expectEqual(result.summary.availableAp, 1, "inspection available AP")
    sequenceEquals(values.calls, { "ready", "load", "cost", "available" }, "inspection ordering")
    result.summary.level = 99
    expectEqual(values.state.survivor.level, 2, "inspection summary detached")
    expectEqual(#values.savedStates, 0, "inspection never saves")
end

do
    local session, values = fixture()
    local capturedLoad = values.dependencies.store.load
    local capturedSave = values.dependencies.store.save
    local capturedReady = values.dependencies.ownerSession.isReady
    local capturedCost = values.dependencies.SurvivorEconomy.nextLevelCost
    local capturedAvailable = values.dependencies.SurvivorEconomy.availableAp
    local capturedApply = values.dependencies.SurvivorEconomy.applyXp
    values.dependencies.store.load = function() error("replacement load") end
    values.dependencies.store.save = function() error("replacement save") end
    values.dependencies.ownerSession.isReady = function() error("replacement ready") end
    values.dependencies.SurvivorEconomy.nextLevelCost = function() error("replacement cost") end
    values.dependencies.SurvivorEconomy.availableAp = function() error("replacement available") end
    values.dependencies.SurvivorEconomy.applyXp = function() error("replacement apply") end
    values.dependencies.catalog.resolver.loadOptions = { replacement = true }
    expect(capturedLoad ~= values.dependencies.store.load, "load replacement differs")
    expect(capturedSave ~= values.dependencies.store.save, "save replacement differs")
    expect(capturedReady ~= values.dependencies.ownerSession.isReady, "ready replacement differs")
    expect(capturedCost ~= values.dependencies.SurvivorEconomy.nextLevelCost, "cost replacement differs")
    expect(capturedAvailable ~= values.dependencies.SurvivorEconomy.availableAp, "available replacement differs")
    expect(capturedApply ~= values.dependencies.SurvivorEconomy.applyXp, "apply replacement differs")
    local result = session.request(values.target, { kind = "awardSurvivorXp", expectedRevision = 7, amount = 50 })
    expectEqual(result.ok, true, "captured callables remain usable")
    sequenceEquals(values.calls, { "ready", "load", "cost", "available", "apply", "cost", "available", "save" }, "captured callable ordering")
end

local function assertXpAward(amount, expectedLevel, expectedXp, expectedGained)
    local session, values = fixture()
    local result = session.request(values.target, {
        kind = "awardSurvivorXp",
        expectedRevision = 7,
        amount = amount,
    })
    exactKeys(result, {
        ok = true,
        applied = true,
        kind = true,
        amount = true,
        levelsGained = true,
        apGained = true,
        summary = true,
    }, "XP success")
    expectEqual(result.ok, true, "XP succeeds")
    expectEqual(result.applied, true, "XP applies")
    expectEqual(result.kind, "awardSurvivorXp", "XP kind")
    expectEqual(result.amount, amount, "XP amount")
    expectEqual(result.levelsGained, expectedGained, "XP levels gained")
    expectEqual(result.apGained, expectedGained, "XP AP gained")
    expectEqual(result.summary.revision, 8, "XP revision increments once")
    expectEqual(result.summary.level, expectedLevel, "XP resulting level")
    expectEqual(result.summary.xpIntoLevel, expectedXp, "XP resulting position")
    expectEqual(result.summary.spent, 1, "XP preserves spent")
    expectEqual(result.summary.availableAp, expectedLevel - 1, "XP derives available AP")
    expectEqual(#values.applyInputs, 1, "XP calls economy apply once")
    expectEqual(values.applyInputs[1].amount, amount, "XP passes direct amount")
    expect(values.applyInputs[1].survivor ~= values.state.survivor, "XP applies over detached Survivor state")
    expectEqual(#values.savedStates, 1, "XP saves once")
    expect(values.savedStates[1] ~= values.state, "saved XP root detached")
    expect(values.savedStates[1].perks ~= values.state.perks, "saved XP perk map detached")
    expect(deepEqual(values.state, values.original), "XP does not mutate loaded fixture")
    sequenceEquals(values.calls, { "ready", "load", "cost", "available", "apply", "cost", "available", "save" }, "XP ordering")
end

assertXpAward(50, 2, 150, 0)
assertXpAward(1700, 3, 0, 1)
assertXpAward(3801, 4, 1, 2)

do
    local session, values = fixture(function(_, configured)
        configured.state.survivor.xpIntoLevel = 123.75
        configured.original.survivor.xpIntoLevel = 123.75
    end)
    local originalPerks = deepCopy(values.state.perks)
    local originalOrphans = deepCopy(values.state.orphanedPerks)
    local result = session.request(values.target, {
        kind = "awardSurvivorLevels",
        expectedRevision = 7,
        count = 3,
    })
    exactKeys(result, {
        ok = true,
        applied = true,
        kind = true,
        count = true,
        levelsGained = true,
        apGained = true,
        summary = true,
    }, "level success")
    expectEqual(result.ok, true, "level award succeeds")
    expectEqual(result.applied, true, "level award applies")
    expectEqual(result.kind, "awardSurvivorLevels", "level kind")
    expectEqual(result.count, 3, "level count")
    expectEqual(result.levelsGained, 3, "direct levels gained")
    expectEqual(result.apGained, 3, "direct AP gained")
    expectEqual(result.summary.revision, 8, "level revision increments once")
    expectEqual(result.summary.level, 5, "direct level increase")
    expectEqual(result.summary.xpIntoLevel, 123.75, "fractional in-level XP preserved")
    expectEqual(result.summary.spent, 1, "level award spent preserved")
    expectEqual(result.summary.availableAp, 4, "level award derives AP")
    expectEqual(#values.applyInputs, 0, "level award does not call apply XP")
    expectEqual(#values.savedStates, 1, "level award saves once")
    local saved = values.savedStates[1]
    expect(deepEqual(saved.perks, originalPerks), "per-skill records preserved exactly")
    expect(deepEqual(saved.orphanedPerks, originalOrphans), "orphaned records preserved exactly")
    expect(saved.perks ~= values.state.perks and saved.perks.Axe ~= values.state.perks.Axe, "per-skill tables detached")
    expect(saved.privateRoot ~= values.state.privateRoot, "accounting-adjacent tables detached")
    expect(deepEqual(values.state, values.original), "level award does not mutate loaded fixture")
    sequenceEquals(values.calls, { "ready", "load", "cost", "available", "cost", "available", "save" }, "level ordering")
end

do
    local session, values = fixture()
    local result = session.request(values.target, {
        kind = "awardSurvivorXp",
        expectedRevision = 6,
        amount = 1800,
    })
    exactKeys(result, {
        ok = true,
        applied = true,
        kind = true,
        code = true,
        detail = true,
        summary = true,
    }, "stale result")
    expectEqual(result.ok, true, "stale is handled result")
    expectEqual(result.applied, false, "stale does not apply")
    expectEqual(result.kind, "awardSurvivorXp", "stale preserves kind")
    expectEqual(result.code, "stale_revision", "stale code")
    expectEqual(result.summary.revision, 7, "stale summary current revision")
    expectEqual(#values.applyInputs, 0, "stale does not apply XP")
    expectEqual(#values.savedStates, 0, "stale does not save")
    expect(deepEqual(values.state, values.original), "stale does not mutate loaded fixture")
    sequenceEquals(values.calls, { "ready", "load", "cost", "available" }, "stale ordering")
end

local invalidRequests = {
    { value = nil, label = "nil" },
    { value = "request", label = "non-table" },
    { value = setmetatable({ kind = "awardSurvivorXp", expectedRevision = 7, amount = 1 }, {}), label = "metatable" },
    { value = { kind = "bogus", expectedRevision = 7, amount = 1 }, label = "unknown kind" },
    { value = { kind = "awardSurvivorXp", expectedRevision = 7 }, label = "missing amount" },
    { value = { kind = "awardSurvivorXp", expectedRevision = 7, amount = 1, extra = true }, label = "XP extra" },
    { value = { kind = "awardSurvivorXp", expectedRevision = 7, amount = 1, count = 1 }, label = "XP second operand" },
    { value = { kind = "awardSurvivorXp", expectedRevision = 7, amount = 0 }, label = "zero XP" },
    { value = { kind = "awardSurvivorXp", expectedRevision = 7, amount = -1 }, label = "negative XP" },
    { value = { kind = "awardSurvivorXp", expectedRevision = 7, amount = 0 / 0 }, label = "NaN XP" },
    { value = { kind = "awardSurvivorXp", expectedRevision = 7, amount = math.huge }, label = "infinite XP" },
    { value = { kind = "awardSurvivorXp", expectedRevision = -1, amount = 1 }, label = "negative revision" },
    { value = { kind = "awardSurvivorXp", expectedRevision = 1.5, amount = 1 }, label = "fractional revision" },
    { value = { kind = "awardSurvivorXp", expectedRevision = 9007199254740992, amount = 1 }, label = "unsafe revision" },
    { value = { kind = "awardSurvivorLevels", expectedRevision = 7 }, label = "missing count" },
    { value = { kind = "awardSurvivorLevels", expectedRevision = 7, count = 1, extra = true }, label = "level extra" },
    { value = { kind = "awardSurvivorLevels", expectedRevision = 7, count = 1, amount = 1 }, label = "level second operand" },
    { value = { kind = "awardSurvivorLevels", expectedRevision = 7, count = 0 }, label = "zero count" },
    { value = { kind = "awardSurvivorLevels", expectedRevision = 7, count = -1 }, label = "negative count" },
    { value = { kind = "awardSurvivorLevels", expectedRevision = 7, count = 1.5 }, label = "fractional count" },
    { value = { kind = "awardSurvivorLevels", expectedRevision = 7, count = math.huge }, label = "infinite count" },
    { value = { kind = "awardSurvivorLevels", expectedRevision = 7, count = 9007199254740992 }, label = "unsafe count" },
}

for index = 1, #invalidRequests do
    local session, values = fixture()
    local result = session.request(values.target, invalidRequests[index].value)
    assertFailure(result, "invalid_request", invalidRequests[index].label)
    expectEqual(#values.calls, 0, invalidRequests[index].label .. " rejected before readiness")
    expectEqual(#values.savedStates, 0, invalidRequests[index].label .. " does not save")
    expect(deepEqual(values.state, values.original), invalidRequests[index].label .. " does not mutate")
end

local function assertOperationFailure(name, configure, invoke, expectedCode, expectedCalls)
    local session, values = fixture(configure)
    local result = invoke(session, values)
    assertFailure(result, expectedCode, name)
    sequenceEquals(values.calls, expectedCalls, name .. " ordering")
    expectEqual(#values.savedStates, 0, name .. " does not record a successful save")
    expect(deepEqual(values.state, values.original), name .. " does not mutate loaded fixture")
end

assertOperationFailure("nil target", nil, function(session) return session.inspect(nil) end, "invalid_target", {})
assertOperationFailure("not ready", function(dependencies) dependencies.ownerSession.isReady = function() return false end end, function(session, values) return session.inspect(values.target) end, "not_ready", {})
assertOperationFailure("readiness throw", function(dependencies) dependencies.ownerSession.isReady = function() error("private") end end, function(session, values) return session.inspect(values.target) end, "readiness_threw", {})
assertOperationFailure("readiness malformed", function(dependencies) dependencies.ownerSession.isReady = function() return "yes" end end, function(session, values) return session.inspect(values.target) end, "readiness_invalid", {})
assertOperationFailure("load throw", function(dependencies) dependencies.store.load = function() error("private") end end, function(session, values) return session.inspect(values.target) end, "store_load_threw", { "ready" })
assertOperationFailure("load malformed", function(dependencies) dependencies.store.load = function() return "bad" end end, function(session, values) return session.inspect(values.target) end, "store_load_invalid", { "ready" })
assertOperationFailure("load explicit failure", function(dependencies) dependencies.store.load = function() return { ok = false, code = "private", detail = "private" } end end, function(session, values) return session.inspect(values.target) end, "store_load_failed", { "ready" })
assertOperationFailure("load extra field", function(dependencies, values) dependencies.store.load = function() return { ok = true, state = values.state, extra = true } end end, function(session, values) return session.inspect(values.target) end, "store_load_invalid", { "ready" })
assertOperationFailure("cost throw", function(dependencies) dependencies.SurvivorEconomy.nextLevelCost = function() error("private") end end, function(session, values) return session.inspect(values.target) end, "economy_cost_threw", { "ready", "load" })
assertOperationFailure("cost malformed", function(dependencies) dependencies.SurvivorEconomy.nextLevelCost = function() return { ok = true, cost = "bad" } end end, function(session, values) return session.inspect(values.target) end, "invalid_state", { "ready", "load" })
assertOperationFailure("available throw", function(dependencies) dependencies.SurvivorEconomy.availableAp = function() error("private") end end, function(session, values) return session.inspect(values.target) end, "economy_ap_threw", { "ready", "load", "cost" })
assertOperationFailure("available malformed", function(dependencies) dependencies.SurvivorEconomy.availableAp = function() return { ok = true, availableAp = -1 } end end, function(session, values) return session.inspect(values.target) end, "invalid_state", { "ready", "load", "cost" })

local impossibleStates = {
    { label = "accounting mode", mutate = function(state) state.accountingMode = "Bogus" end, calls = { "ready", "load" } },
    { label = "negative revision", requestRevision = 0, mutate = function(state) state.revision = -1 end, calls = { "ready", "load" } },
    { label = "unsafe revision", requestRevision = 0, mutate = function(state) state.revision = 9007199254740992 end, calls = { "ready", "load" } },
    { label = "survivor extra field", mutate = function(state) state.survivor.extra = true end, calls = { "ready", "load" } },
    { label = "unsafe level", mutate = function(state) state.survivor.level = 9007199254740992 end, calls = { "ready", "load" } },
    { label = "spent above level", mutate = function(state) state.survivor.spent = 3 end, calls = { "ready", "load" } },
    { label = "nonfinite XP", mutate = function(state) state.survivor.xpIntoLevel = 0 / 0 end, calls = { "ready", "load" } },
    { label = "XP at cost", mutate = function(state) state.survivor.xpIntoLevel = 1800 end, calls = { "ready", "load", "cost" } },
}

for index = 1, #impossibleStates do
    local entry = impossibleStates[index]
    assertOperationFailure(entry.label, function(_, values)
        entry.mutate(values.state)
        values.original = deepCopy(values.state)
    end, function(session, values)
        return session.request(values.target, { kind = "awardSurvivorLevels", expectedRevision = entry.requestRevision or values.state.revision, count = 1 })
    end, "invalid_state", entry.calls)
end

assertOperationFailure("loaded state metatable", function(_, values)
    setmetatable(values.state, {})
    setmetatable(values.original, {})
end, function(session, values)
    return session.inspect(values.target)
end, "invalid_state", { "ready", "load" })

assertOperationFailure("revision overflow", function(_, values)
    values.state.revision = 9007199254740991
    values.original.revision = 9007199254740991
end, function(session, values)
    return session.request(values.target, { kind = "awardSurvivorLevels", expectedRevision = 9007199254740991, count = 1 })
end, "revision_overflow", { "ready", "load", "cost", "available" })

assertOperationFailure("level overflow", function(_, values)
    values.state.survivor.level = 9007199254740991
    values.state.survivor.spent = 0
    values.original.survivor.level = 9007199254740991
    values.original.survivor.spent = 0
end, function(session, values)
    return session.request(values.target, { kind = "awardSurvivorLevels", expectedRevision = 7, count = 1 })
end, "level_overflow", { "ready", "load", "cost", "available" })

assertOperationFailure("apply throw", function(dependencies) dependencies.SurvivorEconomy.applyXp = function() error("private") end end, function(session, values)
    return session.request(values.target, { kind = "awardSurvivorXp", expectedRevision = 7, amount = 1 })
end, "economy_apply_threw", { "ready", "load", "cost", "available" })

assertOperationFailure("apply malformed", function(dependencies) dependencies.SurvivorEconomy.applyXp = function() return { ok = true } end end, function(session, values)
    return session.request(values.target, { kind = "awardSurvivorXp", expectedRevision = 7, amount = 1 })
end, "economy_apply_invalid", { "ready", "load", "cost", "available" })

assertOperationFailure("apply unsafe level", function(dependencies) dependencies.SurvivorEconomy.applyXp = function(_, _)
    return {
        ok = true,
        state = { level = 9007199254740992, xpIntoLevel = 0, spent = 1 },
        effects = { levelsGained = 9007199254740990, apGained = 9007199254740990 },
    }
end end, function(session, values)
    return session.request(values.target, { kind = "awardSurvivorXp", expectedRevision = 7, amount = 1 })
end, "economy_apply_invalid", { "ready", "load", "cost", "available" })

local function assertSaveFailure(name, saveMethod, code)
    local session, values = fixture(function(dependencies)
        dependencies.store.save = saveMethod
    end)
    local result = session.request(values.target, {
        kind = "awardSurvivorLevels",
        expectedRevision = 7,
        count = 1,
    })
    assertFailure(result, code, name)
    sequenceEquals(values.calls, { "ready", "load", "cost", "available", "cost", "available" }, name .. " pre-save ordering")
    expect(deepEqual(values.state, values.original), name .. " preserves loaded fixture")
end

assertSaveFailure("save throw", function() error("private") end, "store_save_threw")
assertSaveFailure("save explicit failure", function() return { ok = false, code = "private", detail = "private" } end, "store_save_failed")
assertSaveFailure("save malformed", function() return "bad" end, "store_save_invalid")
assertSaveFailure("save extra field", function() return { ok = true, extra = true } end, "store_save_invalid")

return assertions
