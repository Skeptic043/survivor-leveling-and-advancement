local Build42GlobalMaximumProbe = assert(Build42GlobalMaximumProbe)

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

local function makeHarness(options)
    options = options or {}
    local h = {
        processCalls = 0,
        playerCalls = 0,
        perkCalls = 0,
        worldCalls = 0,
        readCalls = 0,
        evaluatorCalls = 0,
        position = options.position or 100,
    }
    h.player = {}
    h.player.isExistInTheWorld = function(self)
        h.worldCalls = h.worldCalls + 1
        if h.worldThrow then
            error("world", 0)
        end
        if h.worldMalformed then
            return "yes"
        end
        return self == h.player and h.worldAnswer ~= false
    end
    h.perk = { id = "Axe" }
    h.dependencies = {
        processSide = {
            isServer = function()
                h.processCalls = h.processCalls + 1
                if options.processThrow then
                    error("process side", 0)
                end
                if options.processMalformed then
                    return "false"
                end
                return options.server == true
            end,
        },
        playerIdentity = {
            isPlayer = function(player)
                h.playerCalls = h.playerCalls + 1
                if h.playerThrow then
                    error("player", 0)
                end
                if h.playerMalformed then
                    return "yes"
                end
                return player == h.player and not h.playerRejected
            end,
        },
        perkIdentity = {
            resolve = function(perk)
                h.perkCalls = h.perkCalls + 1
                if h.perkThrow then
                    error("perk", 0)
                end
                if h.perkMalformed then
                    return { ok = true, perkId = "bad id" }
                end
                return {
                    ok = perk == h.perk,
                    perkId = h.perkId or "Axe",
                    perk = h.returnedPerk or perk,
                }
            end,
        },
        positionReader = {
            read = function(player, perkId)
                h.readCalls = h.readCalls + 1
                if h.readThrow then
                    error("read", 0)
                end
                if h.readMalformed then
                    return { ok = true, position = 0 / 0 }
                end
                return { ok = player == h.player and perkId == (h.perkId or "Axe"), position = h.position }
            end,
        },
        maximumEvaluator = {
            evaluate = function(player, perk, base, mode)
                h.evaluatorCalls = h.evaluatorCalls + 1
                h.evaluatorArgs = { player, perk, base, mode }
                if h.evaluatorThrow then
                    error("evaluate", 0)
                end
                if h.evaluatorAnswer then
                    return h.evaluatorAnswer
                end
                return { ok = true, effectiveDelta = 7.5, survivorCreditBase = 3.25 }
            end,
        },
    }
    function h.create()
        local probe, failure = Build42GlobalMaximumProbe.create(h.dependencies)
        expect(probe ~= nil, failure and failure.code)
        h.probe = probe
        return probe
    end
    function h.begin(base, mode)
        return h.probe.begin(h.player, h.perk, base or 2, mode == nil and true or mode)
    end
    return h
end

do
    local source = makeHarness().dependencies
    local probe, failure = Build42GlobalMaximumProbe.create(nil)
    equal(probe, nil, "nil dependencies fail")
    equal(failure.code, "invalid_dependencies", "nil dependency code")
    local missing = {
        { "processSide", "isServer" },
        { "playerIdentity", "isPlayer" },
        { "perkIdentity", "resolve" },
        { "positionReader", "read" },
        { "maximumEvaluator", "evaluate" },
    }
    for index = 1, #missing do
        local owner = source[missing[index][1]]
        local saved = owner[missing[index][2]]
        owner[missing[index][2]] = nil
        local absent, absentFailure = Build42GlobalMaximumProbe.create(source)
        equal(absent, nil, "missing dependency fails")
        equal(absentFailure.code, "invalid_dependencies", "missing dependency code")
        owner[missing[index][2]] = saved
    end
end

do
    local throwing, failure = Build42GlobalMaximumProbe.create(
        makeHarness({ processThrow = true }).dependencies
    )
    equal(throwing, nil, "throwing process detector fails creation")
    equal(failure.code, "process_side_threw", "process throw is stable")
    local malformed, malformedFailure = Build42GlobalMaximumProbe.create(
        makeHarness({ processMalformed = true }).dependencies
    )
    equal(malformed, nil, "malformed process detector fails creation")
    equal(malformedFailure.code, "process_side_failed", "process malformed is stable")
end

do
    local h = makeHarness({ server = true })
    local probe = h.create()
    equal(probe.begin(h.player, h.perk, 2, true).code, "unsupported_server", "server begin inert")
    equal(probe.begin(h.player, h.perk, 2, false).code, "unsupported_server", "server stays inert")
    equal(probe.complete(function() end).code, "unsupported_server", "server complete inert")
    equal(h.processCalls, 1, "server capability determined once")
    equal(h.playerCalls, 0, "server does no player work")
    equal(h.perkCalls, 0, "server does no perk work")
    equal(h.readCalls, 0, "server does no position work")
    equal(h.evaluatorCalls, 0, "server does no evaluator work")
end

do
    local h = makeHarness()
    local probe = h.create()
    local invalid = {
        { 0, true, "invalid_routed_base" },
        { -1, true, "invalid_routed_base" },
        { math.huge, true, "invalid_routed_base" },
        { 2, "true", "invalid_multiplier_mode" },
    }
    for index = 1, #invalid do
        local case = invalid[index]
        equal(probe.begin(h.player, h.perk, case[1], case[2]).code, case[3],
            "invalid begin input fails")
    end
    equal(h.playerCalls, 0, "invalid scalars stop before identity")
end

do
    local cases = {
        { field = "playerThrow", code = "player_identity_threw" },
        { field = "playerMalformed", code = "player_identity_failed" },
        { field = "playerRejected", code = "non_player_owner" },
        { field = "perkThrow", code = "perk_identity_threw" },
        { field = "perkMalformed", code = "perk_identity_failed" },
        { field = "readThrow", code = "initial_position_threw" },
        { field = "readMalformed", code = "initial_position_failed" },
    }
    for index = 1, #cases do
        local h = makeHarness()
        local probe = h.create()
        h[cases[index].field] = true
        equal(probe.begin(h.player, h.perk, 2, true).code, cases[index].code,
            "begin dependency failure is stable")
    end
    local h = makeHarness()
    local probe = h.create()
    h.returnedPerk = {}
    equal(probe.begin(h.player, h.perk, 2, true).code, "perk_identity_failed",
        "canonical handle mismatch fails")
end

do
    local h = makeHarness()
    local probe = h.create()
    local begun = probe.begin(h.player, h.perk, 2, true)
    expect(begun.ok, "candidate begins")
    equal(type(begun.candidate), "function", "candidate is opaque")
    equal(begun.candidate(), nil, "candidate reveals no caller data")
    h.position = 100
    local complete = probe.complete(begun.candidate)
    expect(complete.ok, "unchanged maximum completes")
    equal(complete.perkId, "Axe", "safe perk id preserved")
    equal(complete.survivorCreditBase, 3.25, "evaluator credit preserved")
    equal(complete.appliedDelta, 0, "maximum has zero movement")
    equal(complete.actualPositionBefore, 100, "before is captured")
    equal(complete.actualPositionAfter, 100, "after is unchanged")
    equal(complete.effectiveDelta, 7.5, "effective delta preserved")
    equal(h.evaluatorArgs[1], h.player, "evaluator gets exact player")
    equal(h.evaluatorArgs[2], h.perk, "evaluator gets exact perk")
    equal(h.evaluatorArgs[3], 2, "evaluator gets exact base")
    equal(h.evaluatorArgs[4], true, "standard multiplier mode preserved")
    equal(h.processCalls, 1, "local process capability checked once")
    equal(h.worldCalls, 2, "world presence checked at both boundaries")
end

do
    local cases = {
        {
            setup = function(h) h.player.isExistInTheWorld = nil end,
            code = "world_presence_missing",
        },
        { setup = function(h) h.worldAnswer = false end, code = "player_not_in_world" },
        { setup = function(h) h.worldThrow = true end, code = "world_presence_threw" },
        { setup = function(h) h.worldMalformed = true end, code = "world_presence_failed" },
    }
    for index = 1, #cases do
        local h = makeHarness()
        local probe = h.create()
        cases[index].setup(h)
        equal(probe.begin(h.player, h.perk, 2, true).code, cases[index].code,
            "begin world-presence gate fails closed")
        equal(h.perkCalls, 0, "begin world failure stops before perk work")
        equal(h.readCalls, 0, "begin world failure stops before position work")
        equal(h.evaluatorCalls, 0, "begin world failure stops before evaluator")
    end
end

do
    local cases = {
        {
            setup = function(h) h.player.isExistInTheWorld = nil end,
            code = "world_presence_missing",
        },
        { setup = function(h) h.worldThrow = true end, code = "world_presence_threw" },
        { setup = function(h) h.worldMalformed = true end, code = "world_presence_failed" },
    }
    for index = 1, #cases do
        local h = makeHarness()
        local probe = h.create()
        local candidate = probe.begin(h.player, h.perk, 2, true).candidate
        cases[index].setup(h)
        equal(probe.complete(candidate).code, cases[index].code,
            "complete world-presence gate fails closed")
        equal(h.evaluatorCalls, 0, "complete world failure stops before evaluator")
    end
end

do
    local h = makeHarness()
    local probe = h.create()
    local candidate = probe.begin(h.player, h.perk, 2, true).candidate
    h.worldAnswer = false
    equal(probe.complete(candidate).code, "player_not_in_world",
        "leaving the world during the prior gap fails completion")
    equal(h.evaluatorCalls, 0, "leaving world never reaches evaluator")
end

do
    local h = makeHarness()
    local probe = h.create()
    local begun = probe.begin(h.player, h.perk, 4, false)
    expect(begun.ok, "no-multiplier candidate begins")
    expect(probe.complete(begun.candidate).ok, "no-multiplier candidate completes")
    equal(h.evaluatorArgs[3], 4, "no-multiplier base exact")
    equal(h.evaluatorArgs[4], false, "no-multiplier mode exact")
end

do
    local h = makeHarness()
    local probe = h.create()
    local candidate = probe.begin(h.player, h.perk, 2, true).candidate
    h.position = 101
    equal(probe.complete(candidate).code, "position_changed", "changed position rejects")
    equal(h.evaluatorCalls, 0, "changed position stops before evaluator")
    equal(probe.complete({}).code, "invalid_candidate", "table candidate rejected")
    equal(probe.complete(function() error("tamper", 0) end).code, "invalid_candidate",
        "throwing candidate rejected")
    equal(probe.complete(function() return h.player end).code, "invalid_candidate",
        "forged candidate rejected")
end

do
    local cases = {
        { setup = function(h) h.playerRejected = true end, code = "non_player_owner" },
        { setup = function(h) h.perkId = "Blade" end, code = "perk_identity_changed" },
        { setup = function(h) h.readThrow = true end, code = "current_position_threw" },
        { setup = function(h) h.readMalformed = true end, code = "current_position_failed" },
        { setup = function(h) h.evaluatorThrow = true end, code = "evaluator_threw" },
        { setup = function(h) h.evaluatorAnswer = { ok = false } end, code = "evaluator_failed" },
        { setup = function(h) h.evaluatorAnswer = { ok = true, effectiveDelta = 0, survivorCreditBase = 1 } end, code = "evaluator_failed" },
        { setup = function(h) h.evaluatorAnswer = { ok = true, effectiveDelta = 1, survivorCreditBase = math.huge } end, code = "evaluator_failed" },
    }
    for index = 1, #cases do
        local h = makeHarness()
        local probe = h.create()
        local candidate = probe.begin(h.player, h.perk, 2, true).candidate
        cases[index].setup(h)
        equal(probe.complete(candidate).code, cases[index].code,
            "complete dependency failure is stable")
    end
end

do
    local h = makeHarness()
    local probe = h.create()
    local candidate = probe.begin(h.player, h.perk, 2, true).candidate
    local before = h.position
    probe.complete(candidate)
    equal(h.position, before, "probe never mutates position")
    equal(rawget(probe, "candidate"), nil, "probe stores no candidate")
    equal(rawget(probe, "state"), nil, "probe stores no state")
end

return assertions
