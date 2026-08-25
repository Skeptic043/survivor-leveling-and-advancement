local EventDerivedXpSource = assert(EventDerivedXpSource)
local ReloadedEventDerivedXpSource = assert(ReloadedEventDerivedXpSource)

local assertions = 0

local function expect(value, message)
    assertions = assertions + 1
    if not value then
        error(message or "expectation failed", 2)
    end
end

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error((message or "values differ")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function makeEvent(options)
    local event = { callbacks = {}, attempts = 0 }
    event.Add = function(callback)
        event.attempts = event.attempts + 1
        if options and options.throwOnAdd then
            error("registration failed", 0)
        end
        event.callbacks[#event.callbacks + 1] = callback
    end
    event.fire = function(...)
        for index = 1, #event.callbacks do
            event.callbacks[index](...)
        end
    end
    return event
end

local function makeHarness(options)
    options = options or {}
    local h = {
        awards = {},
        positions = setmetatable({}, { __mode = "k" }),
        divisors = setmetatable({}, { __mode = "k" }),
        internal = setmetatable({}, { __mode = "k" }),
        arithmeticCalls = 0,
        resolverFailures = setmetatable({}, { __mode = "k" }),
    }
    h.addXpEvent = makeEvent(options.addXpEvent)

    local function perkId(perk)
        return type(perk) == "table" and perk.id or nil
    end

    function h.setPosition(player, perk, position)
        local positions = h.positions[player] or {}
        h.positions[player] = positions
        positions[perkId(perk) or perk] = position
    end

    function h.getPosition(player, perk)
        local positions = h.positions[player]
        return positions and positions[perkId(perk) or perk] or nil
    end

    local function nativeAward(player, perk, amount, ...)
        local before = h.getPosition(player, perk) or 0
        h.setPosition(player, perk, before + amount)
        h.addXpEvent.fire(player, perk, amount)
        if options.prior then
            return options.prior(player, perk, amount, ...)
        end
        return nil, "native", select("#", ...)
    end

    h.globals = {
        Events = {
            AddXP = h.addXpEvent,
        },
        addXp = nativeAward,
        addXpNoMultiplier = nativeAward,
    }
    h.originalAddXp = h.globals.addXp
    h.originalNoMultiplier = h.globals.addXpNoMultiplier

    h.dependencies = {
        environment = { globals = h.globals },
        authority = {
            describe = function()
                if options.authorityThrow then
                    error("authority", 0)
                end
                if options.authorityMalformed then
                    return { ok = true, authoritative = "yes" }
                end
                return { ok = true, authoritative = options.authoritative ~= false }
            end,
        },
        playerIdentity = {
            isPlayer = function(player)
                if player.identityAnswer ~= nil then
                    return player.identityAnswer
                end
                return player.isPlayer ~= false
            end,
        },
        perkIdentity = {
            resolve = function(perk)
                if h.resolverFailures[perk] then
                    return { ok = false }
                end
                if type(perk) ~= "table" or type(perk.id) ~= "string" then
                    return { ok = false }
                end
                return { ok = true, perkId = perk.id }
            end,
        },
        positionReader = {
            read = function(player, id)
                local positions = h.positions[player]
                local position = positions and positions[id] or nil
                if position == nil then
                    return { ok = false }
                end
                return { ok = true, position = position }
            end,
        },
        positionArithmetic = {
            add = function(before, amount)
                h.arithmeticCalls = h.arithmeticCalls + 1
                if h.arithmeticAnswer then
                    return h.arithmeticAnswer(before, amount)
                end
                local after = before + amount
                return { ok = after >= 0, positionAfter = after, moved = after ~= before }
            end,
        },
        sandboxMultiplier = {
            resolve = function(player, id)
                if h.sandboxThrow then
                    error("sandbox", 0)
                end
                local divisors = h.divisors[player]
                return { ok = true, multiplier = divisors and divisors[id] or 2 }
            end,
        },
        mutationScope = {
            isActive = function(player, id)
                if h.scopeMalformed then
                    return "no"
                end
                local active = h.internal[player]
                return active and active[id] == true or false
            end,
        },
        awardHandler = {
            process = function(player, award)
                h.awards[#h.awards + 1] = { player = player, award = award }
                if h.onProcess then
                    h.onProcess(player, award)
                end
                if h.handlerThrow then
                    error("handler", 0)
                end
                if h.handlerFail then
                    return { ok = false }
                end
                return { ok = true }
            end,
        },
    }

    function h.createAndInstall()
        local source, failure = EventDerivedXpSource.create(h.dependencies)
        expect(source ~= nil, failure and failure.code)
        local installed = source.install()
        expect(installed.ok, installed.code)
        h.source = source
        return source
    end

    function h.initialize(player, perks)
        for index = 1, #perks do
            local perk = perks[index]
            if type(perk) == "table" and type(perk.id) == "string"
                and h.getPosition(player, perk) == nil then
                h.setPosition(player, perk, 0)
            end
        end
        return h.source.initializePlayer(player, perks)
    end

    function h.emit(player, perk, amount, observedAfter)
        if observedAfter == nil then
            observedAfter = (h.getPosition(player, perk) or 0) + amount
        end
        h.setPosition(player, perk, observedAfter)
        h.addXpEvent.fire(player, perk, amount)
    end

    return h
end

do
    local base = makeHarness().dependencies
    local source, failure = EventDerivedXpSource.create(nil)
    equal(source, nil, "nil dependencies fail")
    equal(failure.code, "invalid_dependencies", "nil dependency code")
    local missing = {
        { "authority", "describe" },
        { "playerIdentity", "isPlayer" },
        { "perkIdentity", "resolve" },
        { "positionReader", "read" },
        { "positionArithmetic", "add" },
        { "sandboxMultiplier", "resolve" },
        { "mutationScope", "isActive" },
        { "awardHandler", "process" },
    }
    for index = 1, #missing do
        local owner = base[missing[index][1]]
        local saved = owner[missing[index][2]]
        owner[missing[index][2]] = nil
        local absent, absentFailure = EventDerivedXpSource.create(base)
        equal(absent, nil, "missing dependency fails")
        equal(absentFailure.code, "invalid_dependencies", "missing dependency code")
        owner[missing[index][2]] = saved
    end
    local savedEnvironment = base.environment
    base.environment = nil
    local noEnvironment, environmentFailure = EventDerivedXpSource.create(base)
    equal(noEnvironment, nil, "missing environment fails")
    equal(environmentFailure.detail, "environment.globals", "missing environment detail")
    base.environment = savedEnvironment
end

do
    local h = makeHarness({ authoritative = false })
    local source = assert(EventDerivedXpSource.create(h.dependencies))
    local answer = source.install()
    expect(answer.ok, "non-authority is inert")
    equal(answer.code, "inert_non_authoritative", "non-authority result")
    equal(#h.addXpEvent.callbacks, 0, "non-authority has no XP observer")
    equal(h.globals.addXp, h.originalAddXp, "non-authority leaves global alone")
end

do
    local throwing = makeHarness({ authorityThrow = true })
    local source = assert(EventDerivedXpSource.create(throwing.dependencies))
    equal(source.install().code, "authority_threw", "authority exception fails closed")
    local malformed = makeHarness({ authorityMalformed = true })
    source = assert(EventDerivedXpSource.create(malformed.dependencies))
    equal(source.install().code, "authority_failed", "malformed authority fails closed")
end

do
    local seamNames = { "addXp", "addXpNoMultiplier" }
    for index = 1, #seamNames do
        local h = makeHarness()
        h.globals[seamNames[index]] = nil
        local source = assert(EventDerivedXpSource.create(h.dependencies))
        equal(source.install().code, "missing_seam", "missing wrapper seam rejected")
    end
    local h = makeHarness()
    h.globals.Events.AddXP = nil
    local source = assert(EventDerivedXpSource.create(h.dependencies))
    equal(source.install().code, "missing_seam", "missing XP event rejected")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    equal(#h.addXpEvent.callbacks, 1, "one XP observer")
    expect(h.globals.addXp ~= h.originalAddXp, "addXp wrapped")
    expect(h.globals.addXpNoMultiplier ~= h.originalNoMultiplier, "no-multiplier wrapped")
    local again = source.install()
    equal(again.code, "already_installed", "repeat install is idempotent")
    equal(#h.addXpEvent.callbacks, 1, "repeat install keeps one XP observer")
    expect(source.verifyOwnership().ok, "ownership verified")
    local status = source.status()
    expect(status.ownsAddXp and status.ownsAddXpNoMultiplier, "owns globals")
    expect(status.ownsAddXpEvent, "owns XP event")
    h.globals.Events.AddXP = makeEvent()
    local lost = source.verifyOwnership()
    equal(lost.code, "ownership_lost", "event ownership loss found")
    equal(source.status().capturing, false, "capture stops after ownership loss")
end

do
    local replacements = {
        {
            detail = "addXp",
            apply = function(h) h.globals.addXp = h.originalAddXp end,
        },
        {
            detail = "addXpNoMultiplier",
            apply = function(h) h.globals.addXpNoMultiplier = h.originalNoMultiplier end,
        },
        {
            detail = "reloadRegistry.Events.AddXP",
            apply = function(h) h.globals.Events.AddXP = makeEvent() end,
        },
    }
    for index = 1, #replacements do
        local h = makeHarness()
        local source = h.createAndInstall()
        replacements[index].apply(h)
        local lost = source.verifyOwnership()
        equal(lost.detail, replacements[index].detail, "each owned seam loss is identified")
        equal(source.status().capturing, false, "each owned seam loss stops capture")
    end
end

do
    local h = makeHarness()
    local first = assert(EventDerivedXpSource.create(h.dependencies))
    expect(first.install().ok, "first singleton installs")
    local sentinel = h.globals.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A
    equal(sentinel.owner, first, "globals reload sentinel owns the live instance")
    equal(sentinel.signature, "sla.event-derived-xp-source/42.20/v1/7f2c9d4a",
        "globals reload sentinel has exact namespace identity")
    local wrappedAddXp = h.globals.addXp
    local wrappedNoMultiplier = h.globals.addXpNoMultiplier
    local second = assert(EventDerivedXpSource.create(h.dependencies))
    equal(second, first, "second create returns the per-globals singleton")
    equal(second.install().code, "already_installed", "second-create install is idempotent")
    local reloaded = assert(ReloadedEventDerivedXpSource.create(h.dependencies))
    equal(reloaded, first, "fresh source chunk adopts the globals sentinel owner")
    equal(reloaded.install().code, "already_installed", "fresh source chunk adds no ownership layer")
    equal(#h.addXpEvent.callbacks, 1, "second create adds no XP observer")
    equal(h.globals.addXp, wrappedAddXp, "second create adds no addXp wrapper layer")
    equal(h.globals.addXpNoMultiplier, wrappedNoMultiplier, "second create adds no no-multiplier layer")
    h.globals.addXp = h.originalAddXp
    equal(first.verifyOwnership().code, "ownership_lost", "singleton records ownership loss")
    local afterLoss = assert(ReloadedEventDerivedXpSource.create(h.dependencies))
    equal(afterLoss, first, "create after loss retains failed-closed singleton")
    equal(afterLoss.install().code, "ownership_lost", "create after loss does not rehook")
    equal(#h.addXpEvent.callbacks, 1, "ownership loss does not add observers")
end

do
    local h = makeHarness()
    h.globals.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A = {}
    local source, failure = ReloadedEventDerivedXpSource.create(h.dependencies)
    equal(source, nil, "fresh source chunk refuses a colliding reload sentinel")
    equal(failure.code, "reload_registry_collision", "reload sentinel collision is stable")
    equal(#h.addXpEvent.callbacks, 0, "reload collision adds no observer")
end

do
    local firstHarness = makeHarness()
    local secondHarness = makeHarness()
    assert(EventDerivedXpSource.create(firstHarness.dependencies))
    assert(EventDerivedXpSource.create(secondHarness.dependencies))
    firstHarness.addXpEvent.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A =
        secondHarness.globals.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A
    local source, failure = ReloadedEventDerivedXpSource.create(firstHarness.dependencies)
    equal(source, nil, "fresh chunk refuses conflicting valid anchors")
    equal(failure.code, "reload_registry_conflict", "anchor conflict is stable")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    h.globals.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A = {}
    equal(source.verifyOwnership().detail, "reloadRegistry.globals",
        "reload sentinel replacement is ownership loss")
    local replacement = assert(ReloadedEventDerivedXpSource.create(h.dependencies))
    equal(replacement, source, "event anchor recovers owner after globals replacement")
    equal(replacement.install().code, "ownership_lost", "recovered owner remains failed closed")
    equal(#h.addXpEvent.callbacks, 1, "lost sentinel does not add another observer")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    h.globals.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A = nil
    local reloaded = assert(ReloadedEventDerivedXpSource.create(h.dependencies))
    equal(reloaded, source, "event anchor survives globals-anchor deletion")
    local failed = reloaded.install()
    equal(failed.code, "ownership_lost", "globals-anchor deletion fails install closed")
    equal(failed.detail, "reloadRegistry.globals", "globals deletion reports exact anchor")
    equal(#h.addXpEvent.callbacks, 1, "globals deletion adds no observer")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    h.addXpEvent.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A = nil
    local reloaded = assert(ReloadedEventDerivedXpSource.create(h.dependencies))
    equal(reloaded, source, "globals anchor survives event-anchor deletion")
    local failed = reloaded.install()
    equal(failed.code, "ownership_lost", "event-anchor deletion fails install closed")
    equal(failed.detail, "reloadRegistry.Events.AddXP", "event deletion reports exact anchor")
    equal(#h.addXpEvent.callbacks, 1, "event deletion adds no observer")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    h.addXpEvent.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A = {}
    local reloaded = assert(ReloadedEventDerivedXpSource.create(h.dependencies))
    equal(reloaded, source, "globals anchor recovers owner after event replacement")
    local failed = reloaded.install()
    equal(failed.code, "ownership_lost", "event-anchor replacement fails install closed")
    equal(failed.detail, "reloadRegistry.Events.AddXP", "event replacement reports exact anchor")
    equal(#h.addXpEvent.callbacks, 1, "event replacement adds no observer")
end

do
    local replacements = {
        {
            detail = "reloadRegistry.globals",
            apply = function(h)
                h.globals.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A = {}
            end,
        },
        {
            detail = "reloadRegistry.Events.AddXP",
            apply = function(h)
                h.addXpEvent.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A = {}
            end,
        },
    }
    for index = 1, #replacements do
        local h = makeHarness()
        local source = assert(EventDerivedXpSource.create(h.dependencies))
        replacements[index].apply(h)
        local failed = source.install()
        equal(failed.code, "ownership_lost", "pre-install anchor replacement fails closed")
        equal(failed.detail, replacements[index].detail, "pre-install replacement identifies anchor")
        equal(#h.addXpEvent.callbacks, 0, "pre-install replacement adds no observer")
        equal(h.globals.addXp, h.originalAddXp, "pre-install replacement adds no wrapper")
    end
end

do
    local h = makeHarness()
    h.globals.Events.AddXP = nil
    local source = assert(EventDerivedXpSource.create(h.dependencies))
    h.globals.Events.AddXP = h.addXpEvent
    expect(source.install().ok, "install claims a newly available event anchor")
    equal(h.addXpEvent.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A.owner, source,
        "newly available event receives the exact globals owner")
end

do
    local h = makeHarness()
    h.globals.Events.AddXP = nil
    local source = assert(EventDerivedXpSource.create(h.dependencies))
    h.globals.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A = {}
    h.globals.Events.AddXP = h.addXpEvent
    local failed = source.install()
    equal(failed.detail, "reloadRegistry.globals",
        "unavailable event is not claimed after globals ownership loss")
    equal(h.addXpEvent.__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A, nil,
        "failed-closed install leaves the newly available event unclaimed")
    equal(#h.addXpEvent.callbacks, 0, "failed event-anchor claim adds no observer")
end

do
    local h = makeHarness({ addXpEvent = { throwOnAdd = true } })
    local source = assert(EventDerivedXpSource.create(h.dependencies))
    equal(source.install().code, "observer_registration_ambiguous", "XP registration ambiguity")
    equal(source.install().code, "observer_registration_ambiguous", "ambiguity is sticky")
    equal(h.addXpEvent.attempts, 1, "ambiguous XP registration attempted once")
end

do
    local seen = nil
    local h = makeHarness({
        prior = function(...)
            seen = { n = select("#", ...), ... }
            return nil, "second", 7
        end,
    })
    h.createAndInstall()
    local player = {}
    local perk = { id = "Axe" }
    local first, second, third = h.globals.addXp(player, perk, 1, nil, "tail")
    equal(first, nil, "wrapper preserves nil return")
    equal(second, "second", "wrapper preserves second return")
    equal(third, 7, "wrapper preserves third return")
    equal(seen.n, 5, "wrapper preserves argument count")
    equal(seen[4], nil, "wrapper preserves nil argument")
    equal(seen[5], "tail", "wrapper preserves trailing argument")
end

do
    local marker = {}
    local shouldThrow = true
    local h = makeHarness({
        prior = function()
            if shouldThrow then
                error(marker)
            end
            return nil, "native", 0
        end,
    })
    local source = h.createAndInstall()
    local player = {}
    local perk = { id = "Axe" }
    h.setPosition(player, perk, 0)
    source.initializePlayer(player, { perk })
    local ok, thrown = pcall(h.globals.addXpNoMultiplier, player, perk, 0)
    equal(ok, false, "wrapper rethrows")
    equal(thrown == marker, false, "Kahlua does not preserve a table error sentinel")
    equal(tostring(thrown), "Method name is null java.lang.NullPointerException",
        "Kahlua table-error limitation is exact and stable")
    equal(source.status().lastCode, "prior_threw", "wrapper records the original throw path")
    shouldThrow = false
    h.emit(player, perk, 2)
    equal(#h.awards, 1, "wrapper error leaves no route frame behind")
    equal(h.awards[1].award.survivorCreditBase, 1,
        "follow-up unmarked event uses its sandbox divisor")
end

do
    local h = makeHarness()
    local baseAddXp = h.globals.addXp
    h.globals.addXp = function(player, perk, amount)
        h.globals.addXpNoMultiplier(player, perk, 2)
        return baseAddXp(player, perk, amount)
    end
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    h.globals.addXp(player, axe, 4)
    source.flushAll()
    equal(#h.awards, 2, "nested route boundary preserves both events")
    equal(h.awards[1].award.survivorCreditBase, 2, "nested no-multiplier frame is innermost")
    equal(h.awards[2].award.survivorCreditBase, 2, "outer standard frame resumes after nesting")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local nonPlayer = { isPlayer = false }
    local malformed = { identityAnswer = "yes" }
    local axe = { id = "Axe" }
    local sprint = { id = "Sprinting" }
    h.setPosition(player, axe, 5)
    h.setPosition(player, sprint, 9)
    local initialized = source.initializePlayer(player, { axe, {}, sprint })
    expect(initialized.ok, "valid initialization")
    equal(initialized.detail.initialized, 2, "valid perks initialized independently")
    equal(initialized.detail.skipped, 1, "invalid perk skipped")
    equal(source.initializePlayer(nonPlayer, { axe }).code, "non_player_owner", "non-player lifecycle rejected")
    equal(source.initializePlayer(malformed, { axe }).code, "player_identity_failed", "player identity must be boolean")
    equal(source.initializePlayer(player, { [1] = axe, [3] = sprint }).code, "invalid_perks", "perks must be dense")
    local repeated = source.initializePlayer(player, { axe, sprint })
    equal(repeated.detail.initialized, 2, "repeat initialization refreshes cursors")
    h.setPosition(nonPlayer, axe, 1)
    h.emit(nonPlayer, axe, 1, 2)
    equal(#h.awards, 0, "non-player event owner is ignored")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    local sprint = { id = "Sprinting" }
    h.setPosition(player, axe, 0)
    h.setPosition(player, sprint, 0)
    source.initializePlayer(player, { axe, sprint })
    h.emit(player, sprint, 2)
    local repeated = source.initializePlayer(player, { axe })
    expect(repeated.ok, "repeat initialization has no pending work")
    equal(repeated.detail.flushed, nil, "repeat initialization exposes no flush facts")
    equal(source.status().cursorCount, 1, "repeat initialization removes omitted cursors")
    h.emit(player, sprint, 1)
    equal(#h.awards, 1, "omitted perk must establish a new cursor")
    h.emit(player, sprint, 1)
    equal(#h.awards, 2, "omitted perk continues only after its new boundary")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    h.emit(player, axe, 4)
    equal(#h.awards, 1, "standard route delivers synchronously")
    equal(h.awards[1].award.survivorCreditBase, 2, "standard route removes sandbox divisor")
    equal(h.awards[1].award.appliedDelta, 4, "event movement preserved")
    equal(h.awards[1].award.actualPositionBefore, 0, "event keeps exact prior position")
    equal(h.awards[1].award.actualPositionAfter, 4, "event keeps exact observed position")

    h.globals.addXpNoMultiplier(player, axe, 2)
    equal(h.awards[2].award.survivorCreditBase, 2, "no-multiplier route uses divisor one")

    h.emit(player, axe, 6)
    equal(h.awards[3].award.survivorCreditBase, 3, "unmarked event uses sandbox divisor")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    local amount = 0.10000000149011612
    local observed = { 100.09999847412109, 100.19999694824219 }
    local transitionIndex = 0
    h.setPosition(player, axe, 100)
    source.initializePlayer(player, { axe })
    h.arithmeticAnswer = function()
        transitionIndex = transitionIndex + 1
        return { ok = true, positionAfter = observed[transitionIndex], moved = true }
    end
    h.emit(player, axe, amount, observed[1])
    h.emit(player, axe, amount, observed[2])
    equal(#h.awards, 2, "binary32 events deliver one envelope each")
    equal(h.awards[1].award.appliedDelta, 0.09999847412109375,
        "first event uses exact observed binary32 movement")
    equal(h.awards[2].award.appliedDelta, 0.09999847412109375,
        "second event uses exact observed binary32 movement")
    equal(h.awards[1].award.survivorCreditBase, amount / 2,
        "each event retains its exact divided credit")
    h.arithmeticAnswer = function()
        return { ok = true, positionAfter = observed[1], moved = true }
    end
    h.emit(player, axe, -amount, observed[1])
    equal(h.awards[3].award.appliedDelta, -0.09999847412109375,
        "signed loss uses the exact observed cumulative difference")
    equal(h.awards[3].award.survivorCreditBase, 0,
        "signed binary32 loss retains zero survivor credit")
end

do
    local cases = {
        { amount = 1, after = 10, positive = true },
        { amount = 1, after = 9, positive = true },
        { amount = -1, after = 11, positive = false },
    }
    for index = 1, #cases do
        local h = makeHarness()
        local source = h.createAndInstall()
        local player = {}
        local axe = { id = "Axe" }
        local case = cases[index]
        h.setPosition(player, axe, 10)
        source.initializePlayer(player, { axe })
        h.arithmeticAnswer = function()
            return { ok = true, positionAfter = case.after, moved = true }
        end
        h.emit(player, axe, case.amount, case.after)
        equal(#h.awards, 0, "invalid movement sign or zero never reaches handler")
        equal(source.status().lastCode, "invalid_event_movement",
            "invalid movement has a stable synchronous status")
    end
end


do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 1.5)
    source.initializePlayer(player, { axe })
    h.emit(player, axe, 0.25, 1.75)
    h.emit(player, axe, -0.5, 1.25)
    equal(#h.awards, 2, "positive and negative binary fractions preserve order")
    equal(h.awards[1].award.actualPositionAfter, 1.75, "positive binary-fraction position exact")
    equal(h.awards[2].award.appliedDelta, -0.5, "negative binary-fraction movement exact")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local dynamic = { id = "Dynamic" }
    h.setPosition(player, dynamic, 10)
    h.emit(player, dynamic, 2, 12)
    equal(#h.awards, 0, "first dynamic event only rebases")
    h.emit(player, dynamic, 2, 14)
    equal(#h.awards, 1, "next continuous dynamic event is accepted")
    equal(h.awards[1].award.actualPositionBefore, 12, "dynamic cursor starts at first observation")

    h.emit(player, dynamic, 2, 99)
    equal(#h.awards, 1, "mismatch does not create an award")
    h.emit(player, dynamic, 1, 100)
    equal(#h.awards, 2, "event after mismatch can proceed")
    equal(h.awards[2].award.actualPositionBefore, 99, "mismatch rebased cursor")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local oldHandle = { id = "Axe" }
    local newHandle = { id = "Axe" }
    h.setPosition(player, oldHandle, 0)
    source.initializePlayer(player, { oldHandle })
    h.emit(player, oldHandle, 2)
    h.setPosition(player, newHandle, 3)
    h.emit(player, newHandle, 1, 3)
    equal(#h.awards, 1, "handle discontinuity preserves older delivered work")
    h.emit(player, newHandle, 1, 4)
    equal(#h.awards, 2, "new exact handle continues after rebase")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local perk = { id = "Axe" }
    h.setPosition(player, perk, 0)
    source.initializePlayer(player, { perk })
    h.emit(player, perk, 2)
    perk.id = "Blade"
    h.setPosition(player, perk, 3)
    h.emit(player, perk, 1, 3)
    equal(#h.awards, 1, "ID discontinuity preserves prior delivered work")
    equal(h.awards[1].award.perkId, "Axe", "prior event retains its identity")
    h.emit(player, perk, 1, 4)
    equal(#h.awards, 2, "same handle continues under rebased ID")
    equal(h.awards[2].award.perkId, "Blade", "rebased ID is exact")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    h.emit(player, axe, 2)
    h.resolverFailures[axe] = true
    h.emit(player, axe, 1)
    equal(#h.awards, 1, "resolver failure does not duplicate delivered work")
    h.resolverFailures[axe] = nil
    h.emit(player, axe, 1)
    equal(#h.awards, 2, "cached handle boundary permits later resolved continuity")
    equal(h.awards[2].award.actualPositionBefore, 3, "resolver failure rebases from current position")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 10)
    source.initializePlayer(player, { axe })
    h.emit(player, axe, 4)
    h.emit(player, axe, -1)
    equal(#h.awards, 2, "positive and negative movements process immediately in order")
    equal(h.awards[1].award.survivorCreditBase, 2, "positive precedes loss")
    equal(h.awards[2].award.survivorCreditBase, 0, "loss has zero survivor credit")
    equal(h.awards[2].award.appliedDelta, -1, "loss preserves signed movement")
    equal(h.awards[2].award.actualPositionBefore, 14, "loss before position exact")
    equal(h.awards[2].award.actualPositionAfter, 13, "loss after position exact")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 100000000)
    source.initializePlayer(player, { axe })
    h.arithmeticAnswer = function(before)
        return { ok = true, positionAfter = before, moved = false }
    end
    h.emit(player, axe, 0.01, 100000000)
    equal(#h.awards, 0, "sub-ULP transition gives no award")
    h.emit(player, axe, 0, 100000000)
    equal(#h.awards, 0, "zero transition gives no award")
    h.arithmeticAnswer = nil
    h.emit(player, axe, 1 / 0, 100000000)
    equal(h.arithmeticCalls, 2, "nonfinite amount never reaches arithmetic")
    equal(#h.awards, 0, "nonfinite amount rebases without work")
    h.emit(player, axe, 1, math.huge)
    equal(#h.awards, 0, "nonfinite observed position fails closed")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    h.divisors[player] = { Axe = math.huge }
    h.emit(player, axe, 2)
    equal(#h.awards, 0, "nonfinite sandbox divisor fails closed")
    h.divisors[player].Axe = 2
    h.arithmeticAnswer = function()
        return { ok = true, positionAfter = math.huge, moved = true }
    end
    h.emit(player, axe, 2)
    equal(#h.awards, 0, "nonfinite forward result fails closed")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local playerA = {}
    local playerB = {}
    local axe = { id = "Axe" }
    local sprint = { id = "Sprinting" }
    for _, player in ipairs({ playerA, playerB }) do
        h.setPosition(player, axe, 0)
        h.setPosition(player, sprint, 0)
        source.initializePlayer(player, { axe, sprint })
    end
    h.emit(playerA, axe, 2)
    h.emit(playerA, sprint, 4)
    h.emit(playerB, axe, 6)
    equal(#h.awards, 3, "players and perks deliver immediately")
    equal(h.awards[3].player, playerB, "exact player identity retained")
    equal(h.awards[1].award.perkId, "Axe", "first accepted event stays first")
    equal(h.awards[2].award.perkId, "Sprinting", "second accepted event stays second")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    h.emit(player, axe, 2)
    equal(h.awards[1].award.survivorCreditBase, 1, "initial divisor is applied immediately")
    local divisors = {}
    h.divisors[player] = divisors
    divisors.Axe = 4
    h.emit(player, axe, 4)
    equal(#h.awards, 2, "divisor changes do not delay either event")
    equal(h.awards[2].award.survivorCreditBase, 1, "new divisor is used")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    h.internal[player] = { Axe = true }
    h.emit(player, axe, 3)
    equal(#h.awards, 0, "capture-time mutation scope suppresses event")
    h.internal[player].Axe = false
    h.emit(player, axe, 2)
    equal(#h.awards, 1, "continuous event after internal rebase proceeds")
    equal(h.awards[1].award.actualPositionBefore, 3, "internal event rebased cursor")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    local recursed = false
    h.onProcess = function()
        if not recursed then
            recursed = true
            h.emit(player, axe, 1)
        end
    end
    h.emit(player, axe, 2)
    equal(#h.awards, 1, "handler-scoped recursion is suppressed")
    h.onProcess = nil
    h.emit(player, axe, 1)
    equal(#h.awards, 2, "cursor follows scoped recursion rebase")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    h.emit(player, axe, 2)
    h.emit(player, axe, 1, 99)
    equal(#h.awards, 1, "discontinuity leaves the prior event delivered exactly once")
    h.emit(player, axe, 1)
    equal(#h.awards, 2, "post-boundary event remains continuous")
    equal(h.awards[2].award.actualPositionBefore, 99,
        "post-boundary cursor uses the observed rebase")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    for index = 1, 500 do
        h.emit(player, axe, 1)
        local award = h.awards[index].award
        equal(award.actualPositionBefore, index - 1, "stress prior position is sequential")
        equal(award.actualPositionAfter, index, "stress observed position is sequential")
        equal(award.survivorCreditBase, 0.5, "stress credit is not sampled")
    end
    equal(h.arithmeticCalls, 500, "bounded stream validates once per event")
    equal(#h.awards, 500, "bounded stream delivers every event immediately")
    equal(source.flushAll().detail.flushed, 0, "bounded stream leaves zero pending work")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 0)
    source.initializePlayer(player, { axe })
    h.handlerFail = true
    h.emit(player, axe, 2)
    equal(source.status().lastCode, "handler_failed", "handler failure is reported synchronously")
    h.handlerFail = false
    equal(source.flushAll().detail.flushed, 0, "failed event is not retried")
    h.handlerThrow = true
    h.emit(player, axe, 2)
    equal(source.status().lastCode, "handler_threw", "handler throw is reported synchronously")
    h.handlerThrow = false
    equal(source.flushAll().detail.flushed, 0, "thrown event is not retried")
    equal(#h.awards, 2, "each failed handler is attempted only for its own event")
    h.emit(player, axe, 2)
    equal(#h.awards, 3, "successful event follows failed handlers")
    equal(h.awards[3].award.actualPositionBefore, 4,
        "failed handlers still advance the source cursor")
    equal(h.awards[3].award.actualPositionAfter, 6,
        "follow-up event preserves exact cursor continuity")
    equal(source.status().lastCode, "award_processed",
        "handler scope is cleaned after failures")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 1)
    source.initializePlayer(player, { axe })
    h.emit(player, axe, 2)
    equal(#h.awards, 1, "positive event is delivered before lifecycle boundary")
    local byPerk = source.flushPlayerPerk(player, "Axe")
    local unconditionalByPerk = source.flushPlayerPerk(nil, nil)
    local byPlayer = source.flushPlayer(player)
    local all = source.flushAll()
    expect(byPerk.ok and unconditionalByPerk.ok and byPlayer.ok and all.ok,
        "all flush compatibility surfaces succeed")
    equal(byPerk.detail.flushed, 0, "perk flush has zero work")
    equal(unconditionalByPerk.detail.flushed, 0, "perk flush is unconditionally inert")
    equal(byPlayer.detail.flushed, 0, "player flush has zero work")
    equal(all.detail.flushed, 0, "global flush has zero work")
    equal(#h.awards, 1, "save or disconnect boundary cannot redispatch work")
    local status = source.status()
    equal(status.batchCount, nil, "status exposes no batch facts")
    equal(status.ownsTickEvent, nil, "status exposes no tick ownership")
end

do
    local h = makeHarness()
    local source = h.createAndInstall()
    local player = {}
    local axe = { id = "Axe" }
    h.setPosition(player, axe, 1)
    source.initializePlayer(player, { axe })
    h.emit(player, axe, 2)
    h.setPosition(player, axe, 20)
    local rebased = source.rebasePlayerPerk(player, axe)
    expect(rebased.ok, "explicit rebase succeeds")
    equal(#h.awards, 1, "explicit rebase has no deferred work")
    h.emit(player, axe, 2)
    equal(h.awards[2].award.actualPositionBefore, 20,
        "explicit rebase snapshots the current position")
end

return assertions
