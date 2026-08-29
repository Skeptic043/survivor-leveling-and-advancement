local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed", 2) end
end

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function empty(value)
    for _ in pairs(value) do return false end
    return true
end

local positions = { [0] = 0, [1] = 100, [2] = 250, [3] = 450 }

local function newState(mode)
    return {
        accountingMode = mode == "Free" and "Free" or "Tracked",
        revision = 0,
        survivor = { level = 6, xpIntoLevel = 0, spent = 0 },
        perks = {},
        orphanedPerks = {},
        inFlightAdvancement = nil,
    }
end

local function createPipeline(case)
    local player = { level = case.startLevel, position = positions[case.startLevel] }
    local store = { current = newState(case.config.mode), saves = 0 }

    function store.load(actualPlayer)
        equal(actualPlayer, player, case.name .. " load player")
        return { ok = true, state = store.current }
    end

    function store.save(actualPlayer, state)
        equal(actualPlayer, player, case.name .. " save player")
        store.saves = store.saves + 1
        store.current = state
        return { ok = true }
    end

    local adapter = {}

    function adapter.describe()
        return {
            ok = true,
            adapterId = "fixture",
            adapterVersion = 1,
            curveFingerprint = "fixture_curve",
            effectiveMaximum = 3,
        }
    end

    function adapter.inspect(_, actualPlayer)
        local result = {
            ok = true,
            storedLevel = actualPlayer.level,
            actualPosition = actualPlayer.position,
            effectiveMaximum = 3,
            levelAligned = true,
        }
        if actualPlayer.level < 3 then
            result.nextTargetLevel = actualPlayer.level + 1
            result.nextTargetPosition = positions[result.nextTargetLevel]
        end
        return result
    end

    function adapter.ensureTarget(_, actualPlayer, targetLevel, targetPosition)
        actualPlayer.level = targetLevel
        actualPlayer.position = targetPosition
        return { ok = true, xpWriteInvoked = true, levelWriteInvoked = true }
    end

    local resolver = {
        loadOptions = {},
        resolve = function(perkId)
            equal(perkId, "Axe", case.name .. " resolver perk")
            return { ok = true, adapter = adapter, handle = {} }
        end,
    }

    local accounting = AccountingMode.create({ store = store, ActualObservation = ActualObservation })
    expect(accounting.ok, case.name .. " accounting mode construction")
    local transaction = ApTransaction.create({
        NaturalLedger = NaturalLedger,
        SurvivorEconomy = SurvivorEconomy,
        Allotment = Allotment,
        MutationScope = MutationScope,
        store = store,
        ActualObservation = ActualObservation,
        AccountingMode = accounting.service,
        resolver = resolver,
    })
    expect(transaction.ok, case.name .. " AP transaction construction")

    local sessionResult = AdvancementSession.create({
        apTransaction = transaction.service,
        allotmentSettings = {
            resolve = function(actualPlayer, perkId)
                equal(actualPlayer, player, case.name .. " settings player")
                equal(perkId, "Axe", case.name .. " settings perk")
                return { ok = true, settings = case.config }
            end,
        },
        ownerSession = {
            isReady = function(actualPlayer)
                equal(actualPlayer, player, case.name .. " readiness player")
                return true
            end,
            snapshot = function(actualPlayer)
                equal(actualPlayer, player, case.name .. " snapshot player")
                return {
                    ok = true,
                    snapshot = {
                        revision = store.current.revision,
                        spent = store.current.survivor.spent,
                        skillLevel = player.level,
                    },
                }
            end,
        },
    })
    expect(sessionResult.ok, case.name .. " advancement session construction")
    return player, store, sessionResult.session
end

local cases = {
    { name = "Global ordinary", config = { mode = "Global", globalLimit = 3 }, startLevel = 0, cost = 1, final = false },
    { name = "Global final", config = { mode = "Global", globalLimit = 3 }, startLevel = 2, cost = 2, final = true },
    { name = "PerSkill ordinary", config = { mode = "PerSkill", perSkillDefault = 1 }, startLevel = 0, cost = 1, final = false },
    { name = "PerSkill final limit one", config = { mode = "PerSkill", perSkillDefault = 1 }, startLevel = 2, cost = 2, final = true },
    { name = "Free ordinary", config = { mode = "Free" }, startLevel = 0, cost = 1, final = false },
    { name = "Free final", config = { mode = "Free" }, startLevel = 2, cost = 2, final = true },
}

for index = 1, #cases do
    local case = cases[index]
    local player, store, session = createPipeline(case)
    local result = session.request(player, {
        perkId = "Axe",
        requestId = "pipeline_" .. tostring(index),
        expectedRevision = 0,
    })

    expect(result.ok, case.name .. " succeeds through the real pipeline: " .. tostring(result.code) .. ":" .. tostring(result.detail))
    expect(result.applied, case.name .. " reports applied")
    equal(result.apCost, case.cost, case.name .. " AP cost")
    equal(result.mastered, case.final, case.name .. " final advancement classification")
    equal(result.snapshot.revision, 1, case.name .. " snapshot revision")
    equal(result.snapshot.spent, case.cost, case.name .. " snapshot spent")
    equal(result.snapshot.skillLevel, case.startLevel + 1, case.name .. " snapshot skill level")
    equal(store.current.revision, 1, case.name .. " persisted revision")
    equal(store.current.survivor.spent, case.cost, case.name .. " persisted spent")
    equal(store.current.inFlightAdvancement, nil, case.name .. " clears reservation")
    equal(store.saves, 2, case.name .. " reserves and commits once")
    equal(player.level, case.startLevel + 1, case.name .. " engine level")

    if case.config.mode == "Free" then
        expect(empty(store.current.perks), case.name .. " preserves empty tracked accounting")
    else
        expect(type(store.current.perks.Axe) == "table", case.name .. " persists tracked accounting")
        equal(#store.current.perks.Axe.activeTargets, case.final and 0 or 1, case.name .. " tracked target count")
    end
end

return assertions
