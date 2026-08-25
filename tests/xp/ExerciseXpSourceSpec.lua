local assertions = 0

local function packValues(...)
    return { n = select("#", ...), ... }
end

local function assertTrue(value, message)
    assertions = assertions + 1
    if not value then
        error(message or "expected true")
    end
end

local function assertFalse(value, message)
    assertions = assertions + 1
    if value then
        error(message or "expected false")
    end
end

local function assertEqual(expected, actual, message)
    assertions = assertions + 1
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertNear(expected, actual, tolerance, message)
    assertions = assertions + 1
    if math.abs(expected - actual) > tolerance then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertNil(value, message)
    assertions = assertions + 1
    if value ~= nil then
        error(message or "expected nil")
    end
end

local function shallowCopy(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function makeEvent(options)
    local event = { observers = {}, addCalls = 0 }
    function event.Add(observer)
        event.addCalls = event.addCalls + 1
        if options and options.throwAdd then
            error("add failed")
        end
        event.observers[#event.observers + 1] = observer
    end
    function event.fire(owner, perk, amount)
        for index = 1, #event.observers do
            event.observers[index](owner, perk, amount)
        end
    end
    return event
end

local DEFINITIONS = {
    squats = { type = "squats", stiffness = "legs", xpMod = 1 },
    pushups = { type = "pushups", stiffness = "arms,chest", xpMod = 1 },
    situp = { type = "situp", stiffness = "abs", xpMod = 1 },
    burpees = { type = "burpees", stiffness = "legs,arms,chest", xpMod = 0.8 },
    barbellcurl = { type = "barbellcurl", stiffness = "arms,chest", xpMod = 1.2 },
    dumbbellpress = { type = "dumbbellpress", stiffness = "arms", xpMod = 1.8 },
    bicepscurl = { type = "bicepscurl", stiffness = "arms", xpMod = 1.8 },
}

local function makeFixture(options)
    options = options or {}
    local strength = {}
    local fitnessPerk = {}
    local event = options.event or makeEvent()
    local positions = { Strength = 100, Fitness = 200 }
    local calls = {
        handlers = {}, prior = {}, round = {}, reads = {}, resolves = {},
        claims = {}, releases = {},
    }
    local hosted = {}
    for name, definition in pairs(DEFINITIONS) do
        hosted[name] = shallowCopy(definition)
    end

    local player = { levels = { [strength] = options.strengthLevel or 5, [fitnessPerk] = options.fitnessLevel or 5 } }
    local fitness = {}
    function player:getFitness()
        return fitness
    end
    function player:getPerkLevel(perk)
        return self.levels[perk]
    end
    function fitness:getParent()
        return player
    end
    function fitness:getCurrentExe()
        if options.currentExercise == false then
            return nil
        end
        return "active"
    end

    local globals = {
        FitnessExercises = { exercisesType = hosted },
        Perks = { Strength = strength, Fitness = fitnessPerk },
        PZMath = {},
        Events = { AddXP = event },
    }

    function globals.PZMath.clampFloat(value, minimum, maximum)
        calls.round[#calls.round + 1] = { value, minimum, maximum }
        if options.roundThrow then
            error("round failed")
        end
        if options.roundNonFinite then
            return 0 / 0
        end
        if options.rounder then
            return options.rounder(value)
        end
        return value
    end

    local actionTable = {}
    local priorError = options.priorError
    function actionTable.exeLooped(...)
        local args = { n = select("#", ...), ... }
        calls.prior[#calls.prior + 1] = args
        if priorError then
            error(priorError)
        end
        if options.prior then
            return options.prior(event, player, strength, fitnessPerk, positions, ...)
        end
        event.fire(player, strength, 1.25)
        positions.Strength = positions.Strength + 1.25
        event.fire(player, fitnessPerk, 2.5)
        positions.Fitness = positions.Fitness + 2.5
        return "first", nil, "third"
    end
    globals.ISFitnessAction = actionTable

    local authorityCalls = 0
    local dependencies = {
        environment = { globals = globals },
        authority = {
            describe = function()
                authorityCalls = authorityCalls + 1
                if options.authoritySequence then
                    return options.authoritySequence[authorityCalls]
                end
                if options.authorityThrow then
                    error("authority failed")
                end
                if options.authorityInvalid then
                    return { ok = true, authoritative = "yes", serverRoute = false }
                end
                return {
                    ok = true,
                    authoritative = options.authoritative ~= false,
                    serverRoute = options.serverRoute == true,
                }
            end,
        },
        perkIdentity = {
            resolve = function(perk)
                calls.resolves[#calls.resolves + 1] = perk
                if options.resolveThrow then
                    error("resolve failed")
                end
                if options.resolveFail then
                    return { ok = false, code = "no-id" }
                end
                if perk == strength then
                    return { ok = true, perkId = "Strength" }
                elseif perk == fitnessPerk then
                    return { ok = true, perkId = options.duplicateId and "Strength" or "Fitness" }
                end
                return { ok = false }
            end,
        },
        positionReader = {
            read = function(owner, perkId)
                calls.reads[#calls.reads + 1] = { owner, perkId }
                if options.readThrow then
                    error("read failed")
                end
                if options.readFail then
                    return { ok = false, code = "no-position" }
                end
                return { ok = true, position = positions[perkId] }
            end,
        },
        awardHandler = {
            process = function(owner, award)
                calls.handlers[#calls.handlers + 1] = { owner = owner, award = shallowCopy(award) }
                if options.handler then
                    return options.handler(event, player, strength, fitnessPerk, positions, owner, award)
                end
                if options.handlerThrow then
                    error("handler failed")
                end
                if options.handlerFail then
                    return { ok = false, code = "rejected" }
                end
                return { ok = true }
            end,
        },
        exactXpClaims = {
            claim = function(token, owner, perk, amount)
                calls.claims[#calls.claims + 1] = {
                    token = token, owner = owner, perk = perk, amount = amount,
                }
                if options.claimThrow then
                    error("claim failed")
                elseif options.claimFalse then
                    return false
                elseif options.claimFail then
                    return { ok = false }
                end
                return { ok = true }
            end,
            release = function(token)
                calls.releases[#calls.releases + 1] = token
                if options.releaseThrow then
                    error("release failed")
                elseif options.releaseFail then
                    return { ok = false }
                end
                return { ok = true }
            end,
        },
    }

    local exerciseType = options.exerciseType or "squats"
    local action = {
        character = player,
        fitness = fitness,
        exeDataType = exerciseType,
        exeData = shallowCopy(DEFINITIONS[exerciseType] or { type = exerciseType, stiffness = "other", xpMod = 9 }),
        marker = "unchanged",
    }

    return {
        dependencies = dependencies,
        globals = globals,
        event = event,
        actionTable = actionTable,
        player = player,
        fitness = fitness,
        strength = strength,
        fitnessPerk = fitnessPerk,
        positions = positions,
        calls = calls,
        action = action,
        authorityCalls = function() return authorityCalls end,
    }
end

-- Dependency validation.
do
    local ok, message = pcall(ExerciseXpSource.create, nil)
    assertFalse(ok)
    assertTrue(string.find(tostring(message), "dependencies") ~= nil)

    local fixture = makeFixture()
    fixture.dependencies.awardHandler.process = nil
    ok, message = pcall(ExerciseXpSource.create, fixture.dependencies)
    assertFalse(ok)
    assertTrue(string.find(tostring(message), "awardHandler.process") ~= nil)
end

-- Local authoritative install, exact arguments/returns, order, positions, and data-only envelopes.
do
    local fixture = makeFixture()
    local source = ExerciseXpSource.create(fixture.dependencies)
    local installed = source.install()
    assertTrue(installed.ok)
    assertEqual("installed", installed.code)
    assertEqual(1, fixture.authorityCalls())
    assertEqual(1, fixture.event.addCalls)

    local first, second, third = fixture.actionTable.exeLooped(fixture.action, "arg", nil, "tail")
    assertEqual("first", first)
    assertNil(second)
    assertEqual("third", third)
    assertEqual(4, fixture.calls.prior[1].n)
    assertEqual(fixture.action, fixture.calls.prior[1][1])
    assertEqual("arg", fixture.calls.prior[1][2])
    assertNil(fixture.calls.prior[1][3])
    assertEqual("tail", fixture.calls.prior[1][4])
    assertEqual(2, #fixture.calls.handlers)
    assertEqual("Strength", fixture.calls.handlers[1].award.perkId)
    assertEqual(0, fixture.calls.handlers[1].award.baseAward)
    assertEqual(1.25, fixture.calls.handlers[1].award.appliedDelta)
    assertEqual(100, fixture.calls.handlers[1].award.actualPositionBefore)
    assertEqual(101.25, fixture.calls.handlers[1].award.actualPositionAfter)
    assertEqual("Fitness", fixture.calls.handlers[2].award.perkId)
    assertEqual(4, fixture.calls.handlers[2].award.baseAward)
    assertEqual(2.5, fixture.calls.handlers[2].award.appliedDelta)
    assertEqual(200, fixture.calls.handlers[2].award.actualPositionBefore)
    assertEqual(202.5, fixture.calls.handlers[2].award.actualPositionAfter)
    assertNil(fixture.calls.handlers[1].award.effectiveDelta)
    assertEqual("unchanged", fixture.action.marker)
    assertEqual("squats", fixture.action.exeData.type)
    assertEqual("legs", fixture.globals.FitnessExercises.exercisesType.squats.stiffness)

    local status = source.status()
    assertTrue(status.installed)
    assertTrue(status.captureEnabled)
    assertTrue(status.actionTableOwned)
    assertTrue(status.wrapperOwned)
    assertTrue(status.eventOwned)
    assertEqual("award-processed", status.lastCode)
    assertNil(status.stack)
    assertNil(status.observer)
    assertNil(status.priorMethod)

    local again = source.install()
    assertTrue(again.ok)
    assertEqual("already-installed", again.code)
    assertEqual(1, fixture.event.addCalls)
    assertEqual(1, fixture.authorityCalls())
    local verified = source.verifyOwnership()
    assertTrue(verified.ok)
    assertEqual("ownership-verified", verified.code)
end

-- Non-authoritative mode is inert and cached.
do
    local fixture = makeFixture({ authoritative = false })
    local original = fixture.actionTable.exeLooped
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    assertTrue(source.install().ok)
    assertEqual(original, fixture.actionTable.exeLooped)
    assertEqual(0, fixture.event.addCalls)
    assertEqual(1, fixture.authorityCalls())
    assertTrue(source.verifyOwnership().ok)
    assertFalse(source.status().captureEnabled)
    assertEqual("non-authoritative", source.status().lastCode)
end

-- Failed authority descriptors retry at a later install attempt.
do
    local fixture = makeFixture({
        authoritySequence = {
            { ok = false, code = "not-ready" },
            { ok = true, authoritative = true, serverRoute = false },
        },
    })
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertFalse(source.install().ok)
    assertTrue(source.install().ok)
    assertEqual(2, fixture.authorityCalls())

    local thrown = makeFixture({ authorityThrow = true })
    source = ExerciseXpSource.create(thrown.dependencies)
    assertFalse(source.install().ok)
    assertEqual("authority-threw", source.status().lastCode)
end

-- All seven exact definitions accept hosted-equivalent tables and preserve formula order.
do
    local expected = {
        squats = { 0, 4 },
        pushups = { 6, 0 },
        situp = { 0, 2 },
        burpees = { 4.8, 3.2 },
        barbellcurl = { 7.2, 0 },
        dumbbellpress = { 7.2, 0 },
        bicepscurl = { 7.2, 0 },
    }
    for exerciseType, bases in pairs(expected) do
        local fixture = makeFixture({ exerciseType = exerciseType })
        assertTrue(fixture.action.exeData ~= fixture.globals.FitnessExercises.exercisesType[exerciseType])
        local source = ExerciseXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        fixture.actionTable.exeLooped(fixture.action)
        assertNear(bases[1], fixture.calls.handlers[1].award.baseAward, 0.000001, exerciseType .. " Strength")
        assertNear(bases[2], fixture.calls.handlers[2].award.baseAward, 0.000001, exerciseType .. " Fitness")
        assertEqual(12, #fixture.calls.round)
        assertNear(-3.4028234663852886e38, fixture.calls.round[1][2], 1e30)
        assertNear(3.4028234663852886e38, fixture.calls.round[1][3], 1e30)
    end
end

-- Level factors and server truncation use the routed binary32 result.
do
    local levelFactors = {
        { level = 0, factor = 1 },
        { level = 5, factor = 1 },
        { level = 6, factor = 1 },
        { level = 14, factor = 1 },
        { level = 15, factor = 2 },
        { level = 24, factor = 2 },
        { level = 25, factor = 3 },
    }
    for index = 1, #levelFactors do
        local entry = levelFactors[index]
        local boundary = makeFixture({ exerciseType = "pushups", strengthLevel = entry.level })
        local boundarySource = ExerciseXpSource.create(boundary.dependencies)
        assertTrue(boundarySource.install().ok)
        boundary.actionTable.exeLooped(boundary.action)
        assertEqual(6 * entry.factor, boundary.calls.handlers[1].award.baseAward)
    end

    local fixture = makeFixture({ exerciseType = "burpees", strengthLevel = 25, fitnessLevel = 16, serverRoute = true })
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.actionTable.exeLooped(fixture.action)
    assertEqual(14, fixture.calls.handlers[1].award.baseAward)
    assertEqual(6, fixture.calls.handlers[2].award.baseAward)

    local rounded = makeFixture({
        exerciseType = "barbellcurl",
        strengthLevel = 15,
        serverRoute = true,
        rounder = function(value)
            if value > 14.3 and value < 14.5 then
                return 15.000001
            end
            return value
        end,
    })
    source = ExerciseXpSource.create(rounded.dependencies)
    assertTrue(source.install().ok)
    rounded.actionTable.exeLooped(rounded.action)
    assertEqual(15, rounded.calls.handlers[1].award.baseAward)
end

-- A final-position failure suppresses only that exact pair and preserves the other pair.
do
    local fixture = makeFixture()
    local reads = 0
    fixture.dependencies.positionReader.read = function(owner, perkId)
        reads = reads + 1
        if reads == 3 then
            return { ok = false, code = "lost" }
        end
        return { ok = true, position = fixture.positions[perkId] }
    end
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.actionTable.exeLooped(fixture.action)
    assertEqual(1, #fixture.calls.handlers)
    assertEqual("Fitness", fixture.calls.handlers[1].award.perkId)
    assertEqual("position-after-failed", source.status().lastCode)
end

-- One vanilla-gated missing pair remains independent of the valid pair, including zero awards.
do
    local fixture = makeFixture({
        exerciseType = "pushups",
        prior = function(event, player, strength, fitnessPerk, positions)
            event.fire(player, fitnessPerk, 0)
            return "ok"
        end,
    })
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    assertEqual("ok", fixture.actionTable.exeLooped(fixture.action))
    assertEqual(1, #fixture.calls.handlers)
    assertEqual("Fitness", fixture.calls.handlers[1].award.perkId)
    assertEqual(0, fixture.calls.handlers[1].award.baseAward)
    assertEqual(0, fixture.calls.handlers[1].award.appliedDelta)
end

-- Definition, identity, level, rounding, resolver, and position failures fail closed per repeat.
do
    local cases = {
        function(f) f.action.character = nil end,
        function(f) f.action.fitness = nil end,
        function(f) f.action.exeDataType = 7 end,
        function(f) f.action.exeData = nil end,
        function(f) f.action.exeData.xpMod = 99 end,
        function(f) f.action.exeData.xpMod = 0 / 0 end,
        function(f) f.action.exeData.type = "pushups" end,
        function(f) f.globals.FitnessExercises.exercisesType.squats.stiffness = "arms" end,
        function(f) f.globals.FitnessExercises = nil end,
        function(f) f.globals.FitnessExercises.exercisesType.squats = nil end,
        function(f) f.action.exeDataType = "modded"; f.action.exeData = { type = "modded", stiffness = "legs", xpMod = 1 } end,
        function(f) f.action.character = {} end,
        function(f) f.action.fitness = {} end,
        function(f) f.player.getFitness = nil end,
        function(f) f.player.getFitness = function() return {} end end,
        function(f) f.fitness.getParent = nil end,
        function(f) f.fitness.getParent = function() return {} end end,
        function(f) f.fitness.getCurrentExe = nil end,
        function(f) f.fitness.getCurrentExe = function() return nil end end,
        function(f) f.player.getPerkLevel = nil end,
        function(f) f.player.getPerkLevel = function() error("level failed") end end,
        function(f) f.player.levels[f.strength] = -1 end,
        function(f) f.player.levels[f.strength] = 1.5 end,
        function(f) f.player.levels[f.fitnessPerk] = 0 / 0 end,
        function(f) f.globals.Perks = nil end,
        function(f) f.globals.Perks.Strength = nil end,
        function(f) f.globals.Perks.Fitness = f.globals.Perks.Strength end,
        function(f) f.globals.PZMath = nil end,
        function(f) f.globals.PZMath.clampFloat = nil end,
        function(f) f.dependencies.perkIdentity.resolve = function() return { ok = false } end end,
        function(f) f.dependencies.perkIdentity.resolve = function() error("resolve failed") end end,
        function(f) f.dependencies.perkIdentity.resolve = function() return { ok = true, perkId = 7 } end end,
        function(f)
            f.dependencies.perkIdentity.resolve = function()
                return { ok = true, perkId = "duplicate" }
            end
        end,
        function(f) f.dependencies.positionReader.read = function() return { ok = false } end end,
        function(f) f.dependencies.positionReader.read = function() error("read failed") end end,
        function(f) f.dependencies.positionReader.read = function() return { ok = true, position = -1 } end end,
        function(f) f.dependencies.positionReader.read = function() return { ok = true, position = math.huge } end end,
    }
    for index = 1, #cases do
        local fixture = makeFixture()
        cases[index](fixture)
        local source = ExerciseXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok, "case install " .. tostring(index))
        local a, b, c = fixture.actionTable.exeLooped(fixture.action)
        assertEqual("first", a)
        assertNil(b)
        assertEqual("third", c)
        assertEqual(0, #fixture.calls.handlers, "case handlers " .. tostring(index))
    end

    local thrownRound = makeFixture({ roundThrow = true })
    local source = ExerciseXpSource.create(thrownRound.dependencies)
    assertTrue(source.install().ok)
    thrownRound.actionTable.exeLooped(thrownRound.action)
    assertEqual(0, #thrownRound.calls.handlers)

    local nonFiniteRound = makeFixture({ roundNonFinite = true })
    source = ExerciseXpSource.create(nonFiniteRound.dependencies)
    assertTrue(source.install().ok)
    nonFiniteRound.actionTable.exeLooped(nonFiniteRound.action)
    assertEqual(0, #nonFiniteRound.calls.handlers)
end

-- Ambiguous paired events invalidate the entire repeat; unrelated events remain unrelated.
do
    local otherPlayer = {}
    local otherPerk = {}
    local variants = {
        function(event, player, strength, fitnessPerk)
            event.fire(player, fitnessPerk, 1)
            event.fire(player, strength, 1)
        end,
        function(event, player, strength)
            event.fire(player, strength, 1)
            event.fire(player, strength, 2)
        end,
        function(event, player, strength)
            event.fire(player, strength, 0 / 0)
        end,
        function(event, player, strength)
            event.fire(otherPlayer, strength, 1)
        end,
    }
    for index = 1, #variants do
        local fixture = makeFixture({ prior = variants[index] })
        local source = ExerciseXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        fixture.actionTable.exeLooped(fixture.action)
        assertEqual(0, #fixture.calls.handlers, "ambiguous variant " .. tostring(index))
        assertEqual("repeat-ambiguous", source.status().lastCode)
    end

    local unrelated = makeFixture({
        prior = function(event, player, strength, fitnessPerk, positions)
            event.fire(otherPlayer, otherPerk, 9)
            event.fire(player, strength, 1)
            positions.Strength = positions.Strength + 1
        end,
    })
    local source = ExerciseXpSource.create(unrelated.dependencies)
    assertTrue(source.install().ok)
    unrelated.actionTable.exeLooped(unrelated.action)
    assertEqual(1, #unrelated.calls.handlers)
    assertEqual("Strength", unrelated.calls.handlers[1].award.perkId)
end

-- Nested repeats pair only with the exact top transaction.
do
    local nested = false
    local fixture
    fixture = makeFixture({
        exerciseType = "situp",
        prior = function(event, player, strength, fitnessPerk, positions, action, depth)
            if not nested then
                nested = true
                fixture.actionTable.exeLooped(action, "inner")
            end
            event.fire(player, fitnessPerk, depth == "inner" and 3 or 2)
            positions.Fitness = positions.Fitness + (depth == "inner" and 3 or 2)
            return depth
        end,
    })
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    assertEqual("outer", fixture.actionTable.exeLooped(fixture.action, "outer"))
    assertEqual(2, #fixture.calls.handlers)
    assertEqual(200, fixture.calls.handlers[1].award.actualPositionBefore)
    assertEqual(203, fixture.calls.handlers[1].award.actualPositionAfter)
    assertEqual(200, fixture.calls.handlers[2].award.actualPositionBefore)
    assertEqual(205, fixture.calls.handlers[2].award.actualPositionAfter)
    assertEqual(2, #fixture.calls.claims, "nested events both claimed")
    assertTrue(fixture.calls.claims[1].token ~= fixture.calls.claims[2].token,
        "nested repeats use distinct claim tokens")
    assertEqual(fixture.calls.claims[1].token, fixture.calls.releases[1], "inner token released first")
    assertEqual(fixture.calls.claims[2].token, fixture.calls.releases[2], "outer token released second")
end

-- Unsupported nested passthrough is ignored while an outer supported repeat is suspended.
do
    local fixture
    local returnAction
    local throwAction
    fixture = makeFixture({
        prior = function(event, player, strength, fitnessPerk, positions, action, marker, nilArgument)
            if action == returnAction then
                event.fire(player, strength, 91)
                event.fire(player, fitnessPerk, 92)
                assertEqual("return-marker", marker)
                assertNil(nilArgument)
                return "inner-first", nil, "inner-third", nil
            elseif action == throwAction then
                event.fire(player, strength, 93)
                event.fire(player, fitnessPerk, 94)
                assertEqual("throw-marker", marker)
                assertNil(nilArgument)
                error("unsupported nested failure")
            end

            local returned = packValues(fixture.actionTable.exeLooped(returnAction, "return-marker", nil))
            assertEqual(4, returned.n)
            assertEqual("inner-first", returned[1])
            assertNil(returned[2])
            assertEqual("inner-third", returned[3])
            assertNil(returned[4])

            local ok = pcall(fixture.actionTable.exeLooped, throwAction, "throw-marker", nil)
            assertFalse(ok)

            event.fire(player, strength, 1.25)
            positions.Strength = positions.Strength + 1.25
            event.fire(player, fitnessPerk, 2.5)
            positions.Fitness = positions.Fitness + 2.5
            return "outer-first", nil, "outer-third"
        end,
    })
    returnAction = {
        character = fixture.player,
        fitness = fixture.fitness,
        exeDataType = "unsupported-return",
        exeData = { type = "unsupported-return", stiffness = "legs", xpMod = 1 },
    }
    throwAction = {
        character = fixture.player,
        fitness = fixture.fitness,
        exeDataType = "unsupported-throw",
        exeData = { type = "unsupported-throw", stiffness = "arms", xpMod = 1 },
    }
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    local first, second, third = fixture.actionTable.exeLooped(fixture.action)
    assertEqual("outer-first", first)
    assertNil(second)
    assertEqual("outer-third", third)
    assertEqual(3, #fixture.calls.prior)
    assertEqual(2, #fixture.calls.handlers)
    assertEqual("Strength", fixture.calls.handlers[1].award.perkId)
    assertEqual(1.25, fixture.calls.handlers[1].award.appliedDelta)
    assertEqual("Fitness", fixture.calls.handlers[2].award.perkId)
    assertEqual(2.5, fixture.calls.handlers[2].award.appliedDelta)
    assertEqual("award-processed", source.status().lastCode)
end

-- Handler event suppression and handler-started supported repeats coexist.
do
    local invokedNested = false
    local fixture
    fixture = makeFixture({
        exerciseType = "situp",
        handler = function(event, player, strength, fitnessPerk, positions)
            event.fire(player, strength, 99)
            if not invokedNested then
                invokedNested = true
                fixture.actionTable.exeLooped(fixture.action, "handler-nested")
            end
            return { ok = true }
        end,
    })
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.actionTable.exeLooped(fixture.action, "outer")
    assertEqual(4, #fixture.calls.handlers)
    assertEqual("Strength", fixture.calls.handlers[1].award.perkId)
    assertEqual("Strength", fixture.calls.handlers[2].award.perkId)
    assertEqual("Fitness", fixture.calls.handlers[3].award.perkId)
    assertEqual("Fitness", fixture.calls.handlers[4].award.perkId)
end

-- Both exact final positions are snapshotted before either handler can mutate progression.
do
    local changed = false
    local fixture = makeFixture({
        handler = function(event, player, strength, fitnessPerk, positions)
            if not changed then
                changed = true
                positions.Fitness = positions.Fitness + 100
            end
            return { ok = true }
        end,
    })
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.actionTable.exeLooped(fixture.action)
    assertEqual(2, #fixture.calls.handlers)
    assertEqual(101.25, fixture.calls.handlers[1].award.actualPositionAfter)
    assertEqual(202.5, fixture.calls.handlers[2].award.actualPositionAfter)
    assertEqual(302.5, fixture.positions.Fitness)
end

-- Handler failure/throw and prior throw never alter vanilla returns/errors.
do
    local failed = makeFixture({ handlerFail = true })
    local source = ExerciseXpSource.create(failed.dependencies)
    assertTrue(source.install().ok)
    local a, b, c = failed.actionTable.exeLooped(failed.action)
    assertEqual("first", a)
    assertNil(b)
    assertEqual("third", c)
    assertEqual("handler-failed", source.status().lastCode)

    local thrown = makeFixture({ handlerThrow = true })
    source = ExerciseXpSource.create(thrown.dependencies)
    assertTrue(source.install().ok)
    a, b, c = thrown.actionTable.exeLooped(thrown.action)
    assertEqual("first", a)
    assertNil(b)
    assertEqual("third", c)
    assertEqual("handler-threw", source.status().lastCode)

    local prior = makeFixture({ priorError = "exact prior failure" })
    source = ExerciseXpSource.create(prior.dependencies)
    assertTrue(source.install().ok)
    local ok, message = pcall(prior.actionTable.exeLooped, prior.action)
    assertFalse(ok)
    assertTrue(string.find(tostring(message), "exact prior failure") ~= nil)
    assertEqual(0, #prior.calls.handlers)

    local errorToken = {}
    prior = makeFixture({ priorError = errorToken })
    source = ExerciseXpSource.create(prior.dependencies)
    assertTrue(source.install().ok)
    ok, message = pcall(prior.actionTable.exeLooped, prior.action)
    assertFalse(ok)
    assertEqual(errorToken, message)

    local nilReturns = makeFixture({
        prior = function()
            return "one", nil, "three", nil
        end,
    })
    source = ExerciseXpSource.create(nilReturns.dependencies)
    assertTrue(source.install().ok)
    local returns = packValues(nilReturns.actionTable.exeLooped(nilReturns.action, nil, "tail", nil))
    assertEqual(4, returns.n)
    assertEqual("one", returns[1])
    assertNil(returns[2])
    assertEqual("three", returns[3])
    assertNil(returns[4])
    assertEqual(4, nilReturns.calls.prior[1].n)
    assertNil(nilReturns.calls.prior[1][2])
    assertEqual("tail", nilReturns.calls.prior[1][3])
    assertNil(nilReturns.calls.prior[1][4])
end

-- Install prevalidation mutates neither seam when a required capability is absent.
do
    local cases = {
        function(f) f.globals.ISFitnessAction = nil end,
        function(f) f.actionTable.exeLooped = nil end,
        function(f) f.globals.Events = nil end,
        function(f) f.globals.Events.AddXP = nil end,
        function(f) f.globals.Events.AddXP.Add = nil end,
    }
    for index = 1, #cases do
        local fixture = makeFixture()
        local original = fixture.actionTable.exeLooped
        cases[index](fixture)
        local source = ExerciseXpSource.create(fixture.dependencies)
        assertFalse(source.install().ok)
        assertEqual(0, fixture.event.addCalls)
        if index ~= 2 then
            assertEqual(original, fixture.actionTable.exeLooped)
        end
        assertFalse(source.status().installed)
    end
end

-- Event registration ambiguity is per object; a replacement can retry.
do
    local firstEvent = makeEvent({ throwAdd = true })
    local fixture = makeFixture({ event = firstEvent })
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertFalse(source.install().ok)
    assertEqual(1, firstEvent.addCalls)
    assertFalse(source.install().ok)
    assertEqual(1, firstEvent.addCalls)
    local replacement = makeEvent()
    fixture.globals.Events.AddXP = replacement
    assertTrue(source.install().ok)
    assertEqual(1, replacement.addCalls)
end

-- Later action-table, method, and event replacement disable capture without overwrite.
do
    local variants = {
        {
            expected = "action-table-replaced",
            replace = function(f) f.globals.ISFitnessAction = { exeLooped = function() return "later" end } end,
        },
        {
            expected = "method-replaced",
            replace = function(f) f.actionTable.exeLooped = function() return "later" end end,
        },
        {
            expected = "event-replaced",
            replace = function(f) f.globals.Events.AddXP = makeEvent() end,
        },
    }
    for index = 1, #variants do
        local fixture = makeFixture()
        local source = ExerciseXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        variants[index].replace(fixture)
        local verification = source.verifyOwnership()
        assertFalse(verification.ok)
        assertEqual(variants[index].expected, verification.code)
        assertFalse(source.status().captureEnabled)
        assertEqual(variants[index].expected, source.status().ownershipReason)
        assertFalse(source.install().ok)
    end
end

-- Ownership is checked only at explicit finite gates, never on the repeat hot path.
do
    local fixture = makeFixture()
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.globals.Events.AddXP = makeEvent()
    fixture.actionTable.exeLooped(fixture.action)
    assertEqual(2, #fixture.calls.handlers)
    assertFalse(source.verifyOwnership().ok)
    fixture.actionTable.exeLooped(fixture.action)
    assertEqual(2, #fixture.calls.handlers)
end

do
    local fixture = makeFixture()
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    local returned = packValues(fixture.actionTable.exeLooped(fixture.action, nil, "tail"))
    assertEqual(3, returned.n, "successful claims preserve return arity")
    assertEqual(2, #fixture.calls.claims, "both exact events are claimed")
    assertEqual(fixture.calls.claims[1].token, fixture.calls.claims[2].token, "repeat claims share token")
    assertEqual(1, #fixture.calls.releases, "successful repeat releases once")
    assertEqual(fixture.calls.claims[1].token, fixture.calls.releases[1], "released token is exact")
    assertEqual(2, #fixture.calls.handlers, "successful claims retain envelopes")
    assertEqual(1.25, fixture.calls.handlers[1].award.appliedDelta, "strength envelope unchanged")
    assertEqual(2.5, fixture.calls.handlers[2].award.appliedDelta, "fitness envelope unchanged")
    local firstToken = fixture.calls.claims[1].token
    fixture.actionTable.exeLooped(fixture.action)
    assertEqual(4, #fixture.calls.claims, "repeated same-tuple events are claimed separately")
    assertTrue(firstToken ~= fixture.calls.claims[3].token, "repeated calls use distinct tokens")
    assertEqual(2, #fixture.calls.releases, "repeated calls each release")
end

do
    local variants = {
        { claimFalse = true, code = "claim-failed" },
        { claimFail = true, code = "claim-failed" },
        { claimThrow = true, code = "claim-threw" },
    }
    for index = 1, #variants do
        local fixture = makeFixture(variants[index])
        local source = ExerciseXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        local first, second, third = fixture.actionTable.exeLooped(fixture.action)
        assertEqual("first", first, "claim failure preserves first return " .. index)
        assertNil(second, "claim failure preserves nil return " .. index)
        assertEqual("third", third, "claim failure preserves third return " .. index)
        assertEqual(0, #fixture.calls.handlers, "claim failure suppresses envelopes " .. index)
        assertEqual(1, #fixture.calls.releases, "claim failure releases " .. index)
        assertEqual(variants[index].code, source.status().lastCode, "claim status " .. index)
    end
end

do
    local errorToken = {}
    local fixture = makeFixture({ priorError = errorToken })
    local source = ExerciseXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    local ok, thrown = pcall(fixture.actionTable.exeLooped, fixture.action)
    assertFalse(ok, "prior error preserved")
    assertEqual(errorToken, thrown, "prior error identity preserved")
    assertEqual(1, #fixture.calls.releases, "prior error releases")
end

do
    local variants = { { releaseFail = true }, { releaseThrow = true } }
    for index = 1, #variants do
        local fixture = makeFixture(variants[index])
        local source = ExerciseXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        assertEqual("first", fixture.actionTable.exeLooped(fixture.action),
            "release failure preserves return " .. index)
        assertEqual(2, #fixture.calls.handlers, "release failure retains envelopes " .. index)
        assertEqual("claim-release-failed", source.status().lastCode,
            "release failure is bounded " .. index)
    end
end

return assertions
