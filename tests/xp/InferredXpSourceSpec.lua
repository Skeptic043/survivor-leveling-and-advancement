local assertions = 0

local function assertTrue(value, message)
    assertions = assertions + 1
    if value ~= true then
        error(message or "expected true")
    end
end

local function assertFalse(value, message)
    assertions = assertions + 1
    if value ~= false then
        error(message or "expected false")
    end
end

local function assertEqual(expected, actual, message)
    assertions = assertions + 1
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertNear(expected, actual, tolerance, message)
    assertions = assertions + 1
    if math.abs(expected - actual) > tolerance then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertNil(value, message)
    assertions = assertions + 1
    if value ~= nil then
        error(message or "expected nil")
    end
end

local function fieldCount(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function shallowCopy(value)
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = entry
    end
    return copy
end

local function makeEvent(options)
    local event = { observers = {}, addCalls = 0, fireCalls = 0 }
    function event.Add(observer)
        event.addCalls = event.addCalls + 1
        if options and options.throwAdd then
            error("registration failed")
        end
        event.observers[#event.observers + 1] = observer
    end
    function event.fire(...)
        event.fireCalls = event.fireCalls + 1
        for index = 1, #event.observers do
            event.observers[index](...)
        end
    end
    return event
end

local function makeFixture(options)
    options = options or {}
    local addXpEvent = options.addXpEvent or makeEvent()
    local onTickEvent = options.onTickEvent or makeEvent()
    local playerA = {}
    local playerB = {}
    local perkA = {}
    local perkB = {}
    local perkAlias = {}
    local perkIds = {
        [perkA] = "Carpentry",
        [perkB] = "Fitness",
        [perkAlias] = "Carpentry",
    }
    local positions = {
        [playerA] = { Carpentry = 100, Fitness = 200 },
        [playerB] = { Carpentry = 300, Fitness = 400 },
    }
    local multipliers = {
        [playerA] = { Carpentry = 3, Fitness = 2 },
        [playerB] = { Carpentry = 4, Fitness = 5 },
    }
    local now = options.now or 0
    local enabled = options.enabled ~= false
    local authorityCalls = 0
    local calls = {
        claims = {}, enabled = 0, identities = {}, positions = {}, multipliers = {},
        arithmetic = {}, clocks = 0, handlers = {}, order = {},
    }
    local globals = {
        Events = { AddXP = addXpEvent, OnTick = onTickEvent },
    }
    local dependencies = {
        environment = { globals = globals },
        authority = {
            describe = function()
                authorityCalls = authorityCalls + 1
                if options.authorityThrow then
                    error("authority failed")
                end
                if options.authoritySequence then
                    return options.authoritySequence[authorityCalls]
                end
                return { ok = true, authoritative = options.authoritative ~= false }
            end,
        },
        clock = {
            now = function()
                calls.clocks = calls.clocks + 1
                if options.clockThrow then
                    error("clock failed")
                end
                return now
            end,
        },
        exactXpClaims = {
            consume = function(owner, perk, amount)
                calls.claims[#calls.claims + 1] = { owner = owner, perk = perk, amount = amount }
                calls.order[#calls.order + 1] = "claim"
                if options.claimThrow then
                    error("claim failed")
                end
                if options.claimResult ~= nil then
                    return options.claimResult
                end
                if options.claim then
                    return options.claim(owner, perk, amount)
                end
                return { ok = true, claimed = false }
            end,
        },
        perkIdentity = {
            resolve = function(perk)
                calls.identities[#calls.identities + 1] = perk
                calls.order[#calls.order + 1] = "identity"
                if options.identityThrow then
                    error("identity failed")
                end
                if options.identityResult ~= nil then
                    return options.identityResult
                end
                local perkId = perkIds[perk]
                if perkId == nil then
                    return { ok = false, code = "unknown" }
                end
                return { ok = true, perkId = perkId }
            end,
        },
        positionReader = {
            read = function(owner, perkId)
                calls.positions[#calls.positions + 1] = { owner = owner, perkId = perkId }
                calls.order[#calls.order + 1] = "position"
                if options.positionThrow then
                    error("position failed")
                end
                if options.positionResult ~= nil then
                    return options.positionResult
                end
                local playerPositions = positions[owner]
                if playerPositions == nil then
                    return { ok = false }
                end
                return { ok = true, position = playerPositions[perkId] }
            end,
        },
        positionArithmetic = {
            previous = function(positionAfter, eventAmount)
                calls.arithmetic[#calls.arithmetic + 1] = {
                    positionAfter = positionAfter,
                    eventAmount = eventAmount,
                }
                calls.order[#calls.order + 1] = "arithmetic"
                if options.arithmeticThrow then
                    error("arithmetic failed")
                end
                if options.arithmeticResult ~= nil then
                    return options.arithmeticResult
                end
                if options.arithmetic then
                    return options.arithmetic(positionAfter, eventAmount)
                end
                return { ok = true, positionBefore = positionAfter - eventAmount }
            end,
        },
        enabledSetting = {
            read = function()
                calls.enabled = calls.enabled + 1
                calls.order[#calls.order + 1] = "enabled"
                if options.settingThrow then
                    error("setting failed")
                end
                if options.settingResult ~= nil then
                    return options.settingResult
                end
                return { ok = true, enabled = enabled }
            end,
        },
        sandboxMultiplier = {
            resolve = function(owner, perkId)
                calls.multipliers[#calls.multipliers + 1] = { owner = owner, perkId = perkId }
                calls.order[#calls.order + 1] = "multiplier"
                if options.multiplierThrow then
                    error("multiplier failed")
                end
                if options.multiplierResult ~= nil then
                    return options.multiplierResult
                end
                local playerMultipliers = multipliers[owner]
                if playerMultipliers == nil then
                    return { ok = false }
                end
                return { ok = true, multiplier = playerMultipliers[perkId] }
            end,
        },
        awardHandler = {
            process = function(owner, award)
                calls.order[#calls.order + 1] = "handler"
                calls.handlers[#calls.handlers + 1] = { owner = owner, award = shallowCopy(award) }
                if options.handlerThrow then
                    error("handler failed")
                end
                if options.handler then
                    return options.handler(owner, award, addXpEvent, onTickEvent)
                end
                if options.handlerResult ~= nil then
                    return options.handlerResult
                end
                return { ok = true }
            end,
        },
    }

    local fixture = {
        dependencies = dependencies,
        globals = globals,
        addXpEvent = addXpEvent,
        onTickEvent = onTickEvent,
        playerA = playerA,
        playerB = playerB,
        perkA = perkA,
        perkB = perkB,
        perkAlias = perkAlias,
        perkIds = perkIds,
        positionsByPlayer = positions,
        multipliersByPlayer = multipliers,
        calls = calls,
        authorityCalls = function() return authorityCalls end,
        setNow = function(value) now = value end,
        getNow = function() return now end,
        setEnabled = function(value) enabled = value end,
    }
    function fixture.award(owner, perk, amount, movement)
        local perkId = perkIds[perk]
        if movement == nil then
            movement = amount
        end
        if movement ~= false and positions[owner] ~= nil and perkId ~= nil then
            positions[owner][perkId] = positions[owner][perkId] + movement
        end
        addXpEvent.fire(owner, perk, amount)
    end
    return fixture
end

-- API and strict dependency boundary.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    assertEqual("function", type(source.install))
    assertEqual("function", type(source.verifyOwnership))
    assertEqual("function", type(source.flushPlayerPerk))
    assertEqual("function", type(source.flushPlayer))
    assertEqual("function", type(source.flushAll))
    assertEqual("function", type(source.status))
    local status = source.status()
    assertEqual(7, fieldCount(status))
    assertFalse(status.installed)
    assertFalse(status.captureEnabled)
    assertFalse(status.eventsOwned)
    assertEqual(0, status.pendingBatches)
    assertEqual("created", status.lastCode)
    assertNil(status.player)
    assertNil(status.perk)
    assertNil(status.perkId)
    assertNil(status.amount)
    assertNil(status.position)
    assertNil(status.queue)

    local ok, message = pcall(InferredXpSource.create, nil)
    assertFalse(ok)
    assertTrue(string.find(tostring(message), "dependencies") ~= nil)

    local missing = {
        function(d) d.environment = nil end,
        function(d) d.environment.globals = nil end,
        function(d) d.authority = nil end,
        function(d) d.authority.describe = nil end,
        function(d) d.clock = nil end,
        function(d) d.clock.now = nil end,
        function(d) d.exactXpClaims = nil end,
        function(d) d.exactXpClaims.consume = nil end,
        function(d) d.perkIdentity = nil end,
        function(d) d.perkIdentity.resolve = nil end,
        function(d) d.positionReader = nil end,
        function(d) d.positionReader.read = nil end,
        function(d) d.positionArithmetic = nil end,
        function(d) d.positionArithmetic.previous = nil end,
        function(d) d.enabledSetting = nil end,
        function(d) d.enabledSetting.read = nil end,
        function(d) d.sandboxMultiplier = nil end,
        function(d) d.sandboxMultiplier.resolve = nil end,
        function(d) d.awardHandler = nil end,
        function(d) d.awardHandler.process = nil end,
    }
    for index = 1, #missing do
        fixture = makeFixture()
        missing[index](fixture.dependencies)
        ok = pcall(InferredXpSource.create, fixture.dependencies)
        assertFalse(ok, "missing dependency " .. index)
    end
end

-- Authoritative installation uses one stable observer per event and is idempotent.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    local installed = source.install()
    assertTrue(installed.ok)
    assertEqual("installed", installed.code)
    assertEqual(1, fixture.authorityCalls())
    assertEqual(1, fixture.addXpEvent.addCalls)
    assertEqual(1, fixture.onTickEvent.addCalls)
    assertEqual(1, #fixture.addXpEvent.observers)
    assertEqual(1, #fixture.onTickEvent.observers)
    local addObserver = fixture.addXpEvent.observers[1]
    local tickObserver = fixture.onTickEvent.observers[1]
    local again = source.install()
    assertTrue(again.ok)
    assertEqual("already-installed", again.code)
    assertEqual(1, fixture.authorityCalls())
    assertEqual(1, fixture.addXpEvent.addCalls)
    assertEqual(1, fixture.onTickEvent.addCalls)
    assertEqual(addObserver, fixture.addXpEvent.observers[1])
    assertEqual(tickObserver, fixture.onTickEvent.observers[1])
    local verified = source.verifyOwnership()
    assertTrue(verified.ok)
    assertEqual("ownership-verified", verified.code)
    local status = source.status()
    assertTrue(status.authoritative)
    assertTrue(status.installed)
    assertTrue(status.captureEnabled)
    assertTrue(status.eventsOwned)
end

-- Non-authoritative processes remain inert and cache the finite authority result.
do
    local fixture = makeFixture({ authoritative = false })
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    assertEqual("non-authoritative", source.status().lastCode)
    assertTrue(source.install().ok)
    assertEqual(1, fixture.authorityCalls())
    assertEqual(0, fixture.addXpEvent.addCalls)
    assertEqual(0, fixture.onTickEvent.addCalls)
    assertFalse(source.status().installed)
    assertFalse(source.status().captureEnabled)
    assertTrue(source.verifyOwnership().ok)
end

-- Failed authority probes may retry at a later explicit install gate.
do
    local fixture = makeFixture({
        authoritySequence = {
            { ok = false, code = "not-ready" },
            { ok = true, authoritative = true },
        },
    })
    local source = InferredXpSource.create(fixture.dependencies)
    assertFalse(source.install().ok)
    assertEqual("authority-failed", source.status().lastCode)
    assertTrue(source.install().ok)
    assertEqual(2, fixture.authorityCalls())

    fixture = makeFixture({ authorityThrow = true })
    source = InferredXpSource.create(fixture.dependencies)
    assertFalse(source.install().ok)
    assertEqual("authority-threw", source.status().lastCode)

    fixture = makeFixture({ authoritySequence = { { ok = true, authoritative = "yes" } } })
    source = InferredXpSource.create(fixture.dependencies)
    assertFalse(source.install().ok)
    assertEqual(0, fixture.addXpEvent.addCalls)
end

-- Both event seams are prevalidated before either is registered.
do
    local variants = {
        function(f) f.globals.Events = nil end,
        function(f) f.globals.Events.AddXP = nil end,
        function(f) f.globals.Events.AddXP.Add = nil end,
        function(f) f.globals.Events.OnTick = nil end,
        function(f) f.globals.Events.OnTick.Add = nil end,
    }
    for index = 1, #variants do
        local fixture = makeFixture()
        variants[index](fixture)
        local source = InferredXpSource.create(fixture.dependencies)
        assertFalse(source.install().ok, "unavailable event " .. index)
        assertEqual(0, fixture.addXpEvent.addCalls, "AddXP untouched " .. index)
        assertEqual(0, fixture.onTickEvent.addCalls, "OnTick untouched " .. index)
        assertFalse(source.status().installed)
    end
end

-- Malformed event identities still consume claims first and then fail closed.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    local fired = pcall(fixture.addXpEvent.fire, nil, fixture.perkA, 3)
    assertTrue(fired)
    assertEqual(1, #fixture.calls.claims)
    assertEqual("invalid-event-identity", source.status().lastCode)
    assertEqual(0, source.status().pendingBatches)
    fired = pcall(fixture.addXpEvent.fire, fixture.playerA, nil, 3)
    assertTrue(fired)
    assertEqual(2, #fixture.calls.claims)
    assertEqual("invalid-event-identity", source.status().lastCode)
    assertEqual(0, source.status().pendingBatches)
end

-- Registration ambiguity is remembered per exact event object and replacements can retry.
do
    local badAddXp = makeEvent({ throwAdd = true })
    local fixture = makeFixture({ addXpEvent = badAddXp })
    local source = InferredXpSource.create(fixture.dependencies)
    assertFalse(source.install().ok)
    assertEqual("addxp-registration-threw", source.status().lastCode)
    assertEqual(1, badAddXp.addCalls)
    assertFalse(source.install().ok)
    assertEqual("addxp-registration-ambiguous", source.status().lastCode)
    assertEqual(1, badAddXp.addCalls)
    local replacement = makeEvent()
    fixture.globals.Events.AddXP = replacement
    assertTrue(source.install().ok)
    assertEqual(1, replacement.addCalls)
    assertEqual(1, fixture.onTickEvent.addCalls)

    local badTick = makeEvent({ throwAdd = true })
    fixture = makeFixture({ onTickEvent = badTick })
    source = InferredXpSource.create(fixture.dependencies)
    assertFalse(source.install().ok)
    assertEqual("ontick-registration-threw", source.status().lastCode)
    assertEqual(1, fixture.addXpEvent.addCalls)
    assertEqual(1, badTick.addCalls)
    assertFalse(source.install().ok)
    assertEqual(1, fixture.addXpEvent.addCalls)
    assertEqual(1, badTick.addCalls)
    replacement = makeEvent()
    fixture.globals.Events.OnTick = replacement
    assertTrue(source.install().ok)
    assertEqual(1, fixture.addXpEvent.addCalls)
    assertEqual(1, replacement.addCalls)
end

-- Positive events consume claims first, including while inference is disabled.
do
    local fixture = makeFixture({ enabled = false })
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 6)
    assertEqual(1, #fixture.calls.claims)
    assertEqual(1, fixture.calls.enabled)
    assertEqual("claim", fixture.calls.order[1])
    assertEqual("enabled", fixture.calls.order[2])
    assertEqual(0, #fixture.calls.identities)
    assertEqual(0, #fixture.calls.handlers)
    assertEqual(0, source.status().pendingBatches)
    assertFalse(source.status().enabled)
    assertEqual("inference-disabled", source.status().lastCode)

    local ignored = { 0, -1, 0 / 0, math.huge, -math.huge, "6" }
    for index = 1, #ignored do
        fixture.addXpEvent.fire(fixture.playerA, fixture.perkA, ignored[index])
    end
    assertEqual(1, #fixture.calls.claims, "nonpositive and nonfinite events never consume")
end

-- Claimed events are never inferred and flush older inferred work first.
do
    local shouldClaim = false
    local fixture = makeFixture({
        claim = function()
            return { ok = true, claimed = shouldClaim }
        end,
    })
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 6)
    assertEqual(1, source.status().pendingBatches)
    shouldClaim = true
    fixture.award(fixture.playerA, fixture.perkA, 3)
    assertEqual(2, #fixture.calls.claims)
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(0, source.status().pendingBatches)
    assertNear(2, fixture.calls.handlers[1].award.baseAward, 0.0000001)
    assertEqual(6, fixture.calls.handlers[1].award.appliedDelta)
    assertEqual(100, fixture.calls.handlers[1].award.actualPositionBefore)
    assertEqual(106, fixture.calls.handlers[1].award.actualPositionAfter)
    assertEqual("handler", fixture.calls.order[#fixture.calls.order])
    assertEqual("exact-claimed", source.status().lastCode)

    fixture = makeFixture({ enabled = false, claimResult = { ok = true, claimed = true } })
    source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 6)
    assertEqual(1, #fixture.calls.claims)
    assertEqual(0, fixture.calls.enabled)
    assertEqual(0, #fixture.calls.identities)
    assertEqual(0, source.status().pendingBatches)
end

-- Claim errors and malformed claim results fail closed before any other reader.
do
    local variants = {
        { claimThrow = true, code = "claim-threw" },
        { claimResult = false, code = "claim-failed" },
        { claimResult = {}, code = "claim-failed" },
        { claimResult = { ok = false, claimed = false }, code = "claim-failed" },
        { claimResult = { ok = true }, code = "claim-failed" },
        { claimResult = { ok = true, claimed = "no" }, code = "claim-failed" },
    }
    for index = 1, #variants do
        local fixture = makeFixture(variants[index])
        local source = InferredXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        fixture.award(fixture.playerA, fixture.perkA, 6)
        assertEqual(1, #fixture.calls.claims, "claim called " .. index)
        assertEqual(0, fixture.calls.enabled, "setting untouched " .. index)
        assertEqual(0, #fixture.calls.identities, "identity untouched " .. index)
        assertEqual(0, source.status().pendingBatches, "no batch " .. index)
        assertEqual(variants[index].code, source.status().lastCode, "claim code " .. index)
    end
end

-- Unsafe identities, positions, multipliers, settings, and clocks fail closed.
do
    local variants = {
        { identityResult = false, code = "perk-identity-failed" },
        { identityResult = {}, code = "perk-identity-failed" },
        { identityResult = { ok = true, perkId = "" }, code = "perk-identity-failed" },
        { identityResult = { ok = true, perkId = 7 }, code = "perk-identity-failed" },
        { identityThrow = true, code = "perk-identity-threw" },
        { positionResult = false, code = "position-failed" },
        { positionResult = { ok = true, position = -1 }, code = "position-failed" },
        { positionResult = { ok = true, position = 0 / 0 }, code = "position-failed" },
        { positionResult = { ok = true, position = math.huge }, code = "position-failed" },
        { positionThrow = true, code = "position-threw" },
        { arithmeticResult = false, code = "position-arithmetic-failed" },
        { arithmeticResult = {}, code = "position-arithmetic-failed" },
        { arithmeticResult = { ok = false }, code = "position-arithmetic-failed" },
        { arithmeticResult = { ok = true }, code = "position-arithmetic-failed" },
        { arithmeticResult = { ok = true, positionBefore = -1 }, code = "position-arithmetic-failed" },
        { arithmeticResult = { ok = true, positionBefore = 0 / 0 }, code = "position-arithmetic-failed" },
        { arithmeticResult = { ok = true, positionBefore = math.huge }, code = "position-arithmetic-failed" },
        { arithmeticThrow = true, code = "position-arithmetic-threw" },
        { multiplierResult = false, code = "multiplier-failed" },
        { multiplierResult = { ok = true, multiplier = 0 }, code = "multiplier-failed" },
        { multiplierResult = { ok = true, multiplier = -1 }, code = "multiplier-failed" },
        { multiplierResult = { ok = true, multiplier = 0 / 0 }, code = "multiplier-failed" },
        { multiplierResult = { ok = true, multiplier = math.huge }, code = "multiplier-failed" },
        { multiplierThrow = true, code = "multiplier-threw" },
        { settingResult = false, code = "setting-failed" },
        { settingResult = { ok = true, enabled = "yes" }, code = "setting-failed" },
        { settingThrow = true, code = "setting-threw" },
        { clockThrow = true, code = "clock-threw" },
    }
    for index = 1, #variants do
        local fixture = makeFixture(variants[index])
        local source = InferredXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        fixture.award(fixture.playerA, fixture.perkA, 6)
        assertEqual(0, source.status().pendingBatches, "invalid input no batch " .. index)
        assertEqual(0, #fixture.calls.handlers, "invalid input no handler " .. index)
        assertEqual(variants[index].code, source.status().lastCode, "invalid input code " .. index)
    end

    local invalidTimes = { -1, 0 / 0, math.huge, -math.huge, "0" }
    for index = 1, #invalidTimes do
        local fixture = makeFixture()
        fixture.dependencies.clock.now = function() return invalidTimes[index] end
        local source = InferredXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        fixture.award(fixture.playerA, fixture.perkA, 6)
        assertEqual(0, source.status().pendingBatches)
        assertEqual("clock-failed", source.status().lastCode)
    end
end

-- The exact inferred formula and first-event boundary are preserved without rounding.
do
    local fixture = makeFixture()
    fixture.multipliersByPlayer[fixture.playerA].Carpentry = 7
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 2.345678901234)
    assertEqual(1, source.status().pendingBatches)
    local flushed = source.flushPlayerPerk(fixture.playerA, "Carpentry")
    assertTrue(flushed.ok)
    assertEqual(1, flushed.flushed)
    assertEqual(0, flushed.dropped)
    assertEqual(1, #fixture.calls.handlers)
    local award = fixture.calls.handlers[1].award
    assertEqual("Carpentry", award.perkId)
    assertEqual(2.345678901234 / 7, award.baseAward)
    assertEqual(102.345678901234 - 100, award.appliedDelta)
    assertEqual(100, award.actualPositionBefore)
    assertEqual(102.345678901234, award.actualPositionAfter)
    assertEqual(5, fieldCount(award))
    assertNil(award.effectiveDelta)
    assertNil(award.modId)
    assertNil(award.recipe)
end

-- Version-pinned arithmetic preserves Java-float boundaries across consecutive awards.
do
    local eventAmount = 0.10000000149011612
    local observedPositions = { 100.0999984741211, 100.19999694824219 }
    local expectedPrevious = { 100, 100.0999984741211 }
    local readIndex = 0
    local arithmeticIndex = 0
    local fixture = makeFixture({
        arithmetic = function(positionAfter, amount)
            arithmeticIndex = arithmeticIndex + 1
            assertEqual(observedPositions[arithmeticIndex], positionAfter,
                "binary32 arithmetic receives exact after position")
            assertEqual(eventAmount, amount, "binary32 arithmetic receives exact event amount")
            return { ok = true, positionBefore = expectedPrevious[arithmeticIndex] }
        end,
    })
    fixture.dependencies.positionReader.read = function(owner, perkId)
        readIndex = readIndex + 1
        assertEqual(fixture.playerA, owner)
        assertEqual("Carpentry", perkId)
        return { ok = true, position = observedPositions[readIndex] }
    end
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.addXpEvent.fire(fixture.playerA, fixture.perkA, eventAmount)
    fixture.addXpEvent.fire(fixture.playerA, fixture.perkA, eventAmount)
    assertEqual(2, readIndex)
    assertEqual(2, arithmeticIndex)
    assertEqual(2, #fixture.calls.arithmetic)
    assertEqual(1, source.status().pendingBatches, "exact float boundary remains contiguous")
    assertEqual(0, #fixture.calls.handlers)
    local outcome = source.flushAll()
    assertTrue(outcome.ok)
    assertEqual(1, outcome.flushed)
    assertEqual(1, #fixture.calls.handlers)
    local award = fixture.calls.handlers[1].award
    assertEqual(eventAmount / 3 + eventAmount / 3, award.baseAward)
    assertEqual(observedPositions[2] - 100, award.appliedDelta)
    assertEqual(100, award.actualPositionBefore)
    assertEqual(observedPositions[2], award.actualPositionAfter)
end

-- Contiguous events coalesce until the real-time deadline; empty ticks are constant work.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    fixture.setNow(500)
    fixture.award(fixture.playerA, fixture.perkA, 6)
    fixture.setNow(999)
    fixture.onTickEvent.fire()
    assertEqual(0, #fixture.calls.handlers)
    assertEqual(1, source.status().pendingBatches)
    assertEqual(3, fixture.calls.clocks)
    fixture.setNow(1000)
    fixture.onTickEvent.fire()
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(0, source.status().pendingBatches)
    local award = fixture.calls.handlers[1].award
    assertEqual(3, award.baseAward)
    assertEqual(9, award.appliedDelta)
    assertEqual(100, award.actualPositionBefore)
    assertEqual(109, award.actualPositionAfter)
    assertEqual(4, fixture.calls.clocks)
    for _ = 1, 100 do
        fixture.onTickEvent.fire()
    end
    assertEqual(4, fixture.calls.clocks, "empty ticks do not read time")
    assertEqual(1, #fixture.calls.handlers)
end

-- Event arrival at the deadline flushes the prior batch before accepting the new event.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    fixture.setNow(1000)
    fixture.award(fixture.playerA, fixture.perkA, 6)
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(1, source.status().pendingBatches)
    assertEqual(1, fixture.calls.handlers[1].award.baseAward)
    assertEqual(3, fixture.calls.handlers[1].award.appliedDelta)
    source.flushAll()
    assertEqual(2, #fixture.calls.handlers)
    assertEqual(2, fixture.calls.handlers[2].award.baseAward)
    assertEqual(6, fixture.calls.handlers[2].award.appliedDelta)
end

-- Divisor changes and cumulative discontinuities flush before starting a new boundary.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    fixture.multipliersByPlayer[fixture.playerA].Carpentry = 6
    fixture.award(fixture.playerA, fixture.perkA, 6)
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(1, fixture.calls.handlers[1].award.baseAward)
    assertEqual(1, source.status().pendingBatches)
    source.flushAll()
    assertEqual(2, #fixture.calls.handlers)
    assertEqual(1, fixture.calls.handlers[2].award.baseAward)

    fixture = makeFixture()
    source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    fixture.positionsByPlayer[fixture.playerA].Carpentry = 150
    fixture.award(fixture.playerA, fixture.perkA, 6)
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(100, fixture.calls.handlers[1].award.actualPositionBefore)
    assertEqual(103, fixture.calls.handlers[1].award.actualPositionAfter)
    assertEqual(1, source.status().pendingBatches)
    source.flushAll()
    assertEqual(150, fixture.calls.handlers[2].award.actualPositionBefore)
    assertEqual(156, fixture.calls.handlers[2].award.actualPositionAfter)
end

-- Invalid first boundaries and nonrepresentable positive movement fail closed.
do
    local fixture = makeFixture()
    fixture.positionsByPlayer[fixture.playerA].Carpentry = 1
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.addXpEvent.fire(fixture.playerA, fixture.perkA, 2)
    assertEqual(0, source.status().pendingBatches)
    assertEqual("position-arithmetic-failed", source.status().lastCode)

    fixture = makeFixture()
    fixture.positionsByPlayer[fixture.playerA].Carpentry = 1e30
    source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.addXpEvent.fire(fixture.playerA, fixture.perkA, 0.0000001)
    assertEqual(0, source.status().pendingBatches)
    assertEqual("invalid-boundary", source.status().lastCode)
end

-- Players and perks remain isolated; explicit flushes are bounded and idempotent.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    fixture.award(fixture.playerA, fixture.perkB, 2)
    fixture.award(fixture.playerB, fixture.perkA, 4)
    fixture.award(fixture.playerB, fixture.perkB, 5)
    assertEqual(4, source.status().pendingBatches)
    local outcome = source.flushPlayerPerk(fixture.playerA, "Carpentry")
    assertTrue(outcome.ok)
    assertEqual(1, outcome.flushed)
    assertEqual(3, source.status().pendingBatches)
    assertEqual(fixture.playerA, fixture.calls.handlers[1].owner)
    assertEqual("Carpentry", fixture.calls.handlers[1].award.perkId)
    outcome = source.flushPlayer(fixture.playerB)
    assertTrue(outcome.ok)
    assertEqual(2, outcome.flushed)
    assertEqual(1, source.status().pendingBatches)
    outcome = source.flushAll()
    assertTrue(outcome.ok)
    assertEqual(1, outcome.flushed)
    assertEqual(0, source.status().pendingBatches)
    outcome = source.flushAll()
    assertTrue(outcome.ok)
    assertEqual("nothing-pending", outcome.code)
    assertEqual(0, outcome.flushed)
    assertEqual(0, outcome.dropped)
    assertEqual(4, #fixture.calls.handlers)
    assertFalse(source.flushPlayer(nil).ok)
    assertFalse(source.flushPlayerPerk(nil, "Carpentry").ok)
    assertFalse(source.flushPlayerPerk(fixture.playerA, nil).ok)
    assertFalse(source.flushPlayerPerk(fixture.playerA, "").ok)
    assertFalse(source.flushPlayerPerk(fixture.playerA, 7).ok)
end

-- A replacement perk handle with the same safe ID creates a deterministic boundary.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    fixture.award(fixture.playerA, fixture.perkAlias, 3)
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(1, source.status().pendingBatches)
    assertEqual(100, fixture.calls.handlers[1].award.actualPositionBefore)
    assertEqual(103, fixture.calls.handlers[1].award.actualPositionAfter)
    source.flushAll()
    assertEqual(2, #fixture.calls.handlers)
    assertEqual(103, fixture.calls.handlers[2].award.actualPositionBefore)
    assertEqual(106, fixture.calls.handlers[2].award.actualPositionAfter)
end

-- Handler-generated same-player/perk events are ignored only inside that scoped flush.
do
    local nested = false
    local fixture
    fixture = makeFixture({
        handler = function(owner, award, addXpEvent)
            if not nested then
                nested = true
                fixture.positionsByPlayer[owner][award.perkId] = fixture.positionsByPlayer[owner][award.perkId] + 9
                addXpEvent.fire(owner, fixture.perkA, 9)
            end
            return { ok = true }
        end,
    })
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    local outcome = source.flushAll()
    assertTrue(outcome.ok)
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(2, #fixture.calls.claims, "nested event still consumes a claim first")
    assertEqual(0, source.status().pendingBatches)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    assertEqual(1, source.status().pendingBatches, "ignore scope is popped after handler")
end

-- Ignore scope is exact player/perk; a different perk may start its own batch.
do
    local nested = false
    local fixture
    fixture = makeFixture({
        handler = function(owner, award, addXpEvent)
            if not nested then
                nested = true
                fixture.positionsByPlayer[owner].Fitness = fixture.positionsByPlayer[owner].Fitness + 2
                addXpEvent.fire(owner, fixture.perkB, 2)
            end
            return { ok = true }
        end,
    })
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    source.flushPlayerPerk(fixture.playerA, "Carpentry")
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(1, source.status().pendingBatches)
    source.flushAll()
    assertEqual(2, #fixture.calls.handlers)
    assertEqual("Fitness", fixture.calls.handlers[2].award.perkId)
end

-- Handler failure and throw drop the batch without retry or vanilla-event failure.
do
    local variants = {
        { handlerResult = { ok = false }, code = "handler-failed" },
        { handlerResult = false, code = "handler-failed" },
        { handlerThrow = true, code = "handler-threw" },
    }
    for index = 1, #variants do
        local fixture = makeFixture(variants[index])
        local source = InferredXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        local fired = pcall(fixture.award, fixture.playerA, fixture.perkA, 3)
        assertTrue(fired, "event unaffected " .. index)
        local outcome = source.flushAll()
        assertFalse(outcome.ok, "handler failure returned " .. index)
        assertEqual(0, outcome.flushed)
        assertEqual(1, outcome.dropped)
        assertEqual(0, source.status().pendingBatches)
        assertEqual(variants[index].code, source.status().lastCode)
        outcome = source.flushAll()
        assertTrue(outcome.ok)
        assertEqual(1, #fixture.calls.handlers, "no retry " .. index)
    end
end

-- Claimed-boundary handler failure does not infer the exact event or disturb its dispatch.
do
    local shouldClaim = false
    local fixture = makeFixture({
        claim = function() return { ok = true, claimed = shouldClaim } end,
        handlerThrow = true,
    })
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    shouldClaim = true
    local fired = pcall(fixture.award, fixture.playerA, fixture.perkA, 3)
    assertTrue(fired)
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(0, source.status().pendingBatches)
    assertEqual("handler-threw", source.status().lastCode)
end

-- Clock regression creates a boundary instead of joining a non-monotonic batch.
do
    local fixture = makeFixture({ now = 100 })
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    fixture.setNow(99)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    assertEqual(1, #fixture.calls.handlers)
    assertEqual(1, source.status().pendingBatches)
    source.flushAll()
    assertEqual(2, #fixture.calls.handlers)
end

-- A failed monotonic clock drops bounded best-effort work instead of retaining it indefinitely.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    fixture.award(fixture.playerA, fixture.perkA, 3)
    assertEqual(1, source.status().pendingBatches)
    fixture.dependencies.clock.now = function() error("clock unavailable") end
    fixture.onTickEvent.fire()
    assertEqual(0, source.status().pendingBatches)
    assertEqual(0, #fixture.calls.handlers)
    assertEqual("clock-threw", source.status().lastCode)
end

-- Ownership replacement is checked only at explicit gates and disables capture/flush.
do
    local variants = {
        {
            code = "addxp-event-replaced",
            replace = function(f) f.globals.Events.AddXP = makeEvent() end,
        },
        {
            code = "ontick-event-replaced",
            replace = function(f) f.globals.Events.OnTick = makeEvent() end,
        },
    }
    for index = 1, #variants do
        local fixture = makeFixture()
        local source = InferredXpSource.create(fixture.dependencies)
        assertTrue(source.install().ok)
        fixture.award(fixture.playerA, fixture.perkA, 3)
        assertEqual(1, source.status().pendingBatches)
        variants[index].replace(fixture)
        fixture.award(fixture.playerA, fixture.perkA, 3)
        assertEqual(1, source.status().pendingBatches, "no hot-path ownership poll " .. index)
        local verified = source.verifyOwnership()
        assertFalse(verified.ok)
        assertEqual(variants[index].code, verified.code)
        local status = source.status()
        assertTrue(status.installed)
        assertFalse(status.captureEnabled)
        assertFalse(status.eventsOwned)
        assertEqual(0, status.pendingBatches)
        assertEqual(variants[index].code, status.ownershipReason)
        assertFalse(source.install().ok)
        local handlerCount = #fixture.calls.handlers
        fixture.addXpEvent.fire(fixture.playerA, fixture.perkA, 3)
        fixture.onTickEvent.fire()
        assertEqual(handlerCount, #fixture.calls.handlers)
        assertEqual(0, source.status().pendingBatches)
        assertTrue(source.flushAll().ok)
    end
end

-- Pending storage stays at one batch per exact player/perk during a hot stream.
do
    local fixture = makeFixture()
    local source = InferredXpSource.create(fixture.dependencies)
    assertTrue(source.install().ok)
    for index = 1, 500 do
        fixture.setNow(index)
        fixture.award(fixture.playerA, fixture.perkA, 0.25)
        assertEqual(1, source.status().pendingBatches, "bounded stream " .. index)
    end
    assertEqual(0, #fixture.calls.handlers)
    source.flushAll()
    assertEqual(1, #fixture.calls.handlers)
    local expectedBase = 0
    for _ = 1, 500 do
        expectedBase = expectedBase + 0.25 / 3
    end
    assertEqual(expectedBase, fixture.calls.handlers[1].award.baseAward)
    assertEqual(125, fixture.calls.handlers[1].award.appliedDelta)
end

return assertions
