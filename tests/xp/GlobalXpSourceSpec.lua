local assertions = 0

local function fail(message)
    error(message)
end

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        fail((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function truthy(value, message)
    assertions = assertions + 1
    if not value then
        fail(message or "expected truthy value")
    end
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local function fieldCount(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function newEvent(mode)
    local event = { handlers = {}, addCalls = 0 }
    event.Add = function(handler)
        event.addCalls = event.addCalls + 1
        if mode == "store_then_throw" then
            event.handlers[#event.handlers + 1] = handler
            error("ambiguous add")
        elseif mode == "throw" then
            error("failed add")
        end
        event.handlers[#event.handlers + 1] = handler
        if mode == "return_false" then
            return false
        end
    end
    event.fire = function(...)
        for index = 1, #event.handlers do
            event.handlers[index](...)
        end
    end
    return event
end

local function newHarness(options)
    options = options or {}
    local event = options.event or newEvent()
    local authorityState = options.authoritative
    if authorityState == nil then
        authorityState = true
    end
    local calls = { addXp = {}, addXpNoMultiplier = {}, awards = {}, authority = 0 }
    local globals = { Events = { AddXP = event } }
    local player = { positions = { Axe = 10, Cooking = 20 } }
    local perk = { id = "Axe" }

    local function prior(kind, ...)
        local args = pack(...)
        calls[kind][#calls[kind] + 1] = args
        local owner = args[1]
        local exactPerk = args[2]
        local base = args[3]
        if options.priorBehavior then
            return options.priorBehavior(kind, globals, event, args)
        end
        owner.positions[exactPerk.id] = owner.positions[exactPerk.id] + base
        event.fire(owner, exactPerk, base)
        return kind, nil, "tail", nil
    end

    globals.addXp = function(...)
        return prior("addXp", ...)
    end
    globals.addXpNoMultiplier = function(...)
        return prior("addXpNoMultiplier", ...)
    end
    local originalAddXp = globals.addXp
    local originalNoMultiplier = globals.addXpNoMultiplier
    local readCalls = 0
    local dependencies = {
        environment = { globals = globals },
        authority = {
            isAuthoritative = function()
                calls.authority = calls.authority + 1
                if options.authorityThrow then
                    error("authority boom")
                end
                if options.authorityFailure then
                    return { ok = false }
                end
                return { ok = true, authoritative = authorityState }
            end,
        },
        perkIdentity = {
            resolve = function(exactPerk)
                if options.identityThrow then
                    error("identity boom")
                end
                if options.identityFailure then
                    return { ok = false }
                end
                if options.invalidIdentity then
                    return { ok = true, perkId = options.invalidIdentity }
                end
                return { ok = true, perkId = exactPerk.id }
            end,
        },
        positionReader = {
            read = function(owner, perkId)
                readCalls = readCalls + 1
                if options.readThrow then
                    error("read boom")
                end
                if options.readFailure then
                    return { ok = false }
                end
                if readCalls > 1 and options.afterReadThrow then
                    error("after read boom")
                end
                if readCalls > 1 and options.afterReadFailure then
                    return { ok = false }
                end
                local value = owner.positions[perkId]
                if options.positionOverride ~= nil then
                    value = options.positionOverride
                end
                if readCalls > 1 and options.afterPositionOverride ~= nil then
                    value = options.afterPositionOverride
                end
                return { ok = true, position = value }
            end,
        },
        awardHandler = {
            process = function(owner, award)
                calls.awards[#calls.awards + 1] = { player = owner, award = award }
                if options.handlerThrow then
                    error("handler boom")
                end
                if options.handlerFailure then
                    return { ok = false, code = "private " .. tostring(owner) }
                end
                return { ok = true }
            end,
        },
    }
    local source, creationFailure = GlobalXpSource.create(dependencies)
    return {
        source = source,
        creationFailure = creationFailure,
        dependencies = dependencies,
        globals = globals,
        event = event,
        player = player,
        perk = perk,
        calls = calls,
        originalAddXp = originalAddXp,
        originalNoMultiplier = originalNoMultiplier,
        setAuthoritative = function(value)
            authorityState = value
        end,
        getReadCalls = function()
            return readCalls
        end,
    }
end

do
    local source, failure = GlobalXpSource.create(nil)
    equal(source, nil, "nil dependencies rejected")
    equal(failure.code, "invalid_dependencies", "nil dependency code")
    local invalid = {
        {},
        { environment = {} },
        { environment = { globals = {} }, authority = {} },
        { environment = { globals = {} }, authority = { isAuthoritative = function() end }, perkIdentity = {} },
        {
            environment = { globals = {} },
            authority = { isAuthoritative = function() end },
            perkIdentity = { resolve = function() end },
            positionReader = {},
        },
        {
            environment = { globals = {} },
            authority = { isAuthoritative = function() end },
            perkIdentity = { resolve = function() end },
            positionReader = { read = function() end },
            awardHandler = {},
        },
    }
    for index = 1, #invalid do
        local rejected, reason = GlobalXpSource.create(invalid[index])
        equal(rejected, nil, "partial dependency rejected " .. index)
        equal(reason.code, "invalid_dependencies", "partial dependency code " .. index)
    end
end

do
    local harness = newHarness({ authoritative = false })
    local installed = harness.source.install()
    truthy(installed.ok, "non-authoritative install is inert success")
    equal(installed.code, "inert_non_authoritative", "inert install code")
    equal(harness.event.addCalls, 0, "inert install does not register")
    equal(harness.globals.addXp, harness.originalAddXp, "inert install leaves addXp")
    equal(harness.globals.addXpNoMultiplier, harness.originalNoMultiplier, "inert install leaves no multiplier")
    local status = harness.source.status()
    equal(status.installed, false, "inert status not installed")
    equal(status.captureEnabled, false, "inert status capture disabled")
    equal(status.observerRegistration, "not_attempted", "inert observer state")
end

do
    local harness = newHarness({ authorityFailure = true })
    equal(harness.source.install().code, "authority_failed", "authority failure code")
    equal(harness.event.addCalls, 0, "authority failure does not register")
    harness = newHarness({ authorityThrow = true })
    equal(harness.source.install().code, "authority_threw", "authority throw code")
    equal(harness.event.addCalls, 0, "authority throw does not register")
end

do
    local seamCases = {
        { name = "addXp", mutate = function(h) h.globals.addXp = nil end },
        { name = "addXpNoMultiplier", mutate = function(h) h.globals.addXpNoMultiplier = false end },
        { name = "Events.AddXP.Add", mutate = function(h) h.globals.Events.AddXP.Add = nil end },
        { name = "Events.AddXP.Add", mutate = function(h) h.globals.Events = nil end },
    }
    for index = 1, #seamCases do
        local harness = newHarness()
        seamCases[index].mutate(harness)
        local installed = harness.source.install()
        equal(installed.ok, false, "missing seam rejected " .. index)
        equal(installed.detail, seamCases[index].name, "missing seam detail " .. index)
        equal(harness.event.addCalls, 0, "prevalidation before registration " .. index)
        if seamCases[index].name ~= "addXp" then
            equal(harness.globals.addXp, harness.originalAddXp, "prevalidation before mutation " .. index)
        end
    end
end

do
    local eventA = newEvent("store_then_throw")
    local harness = newHarness({ event = eventA })
    local first = harness.source.install()
    equal(first.code, "observer_registration_ambiguous", "ambiguous registration code")
    equal(eventA.addCalls, 1, "ambiguous registration attempted once")
    equal(harness.globals.addXp, harness.originalAddXp, "ambiguous add leaves global")
    equal(harness.source.status().observerRegistration, "ambiguous", "ambiguous status")
    local second = harness.source.install()
    equal(second.code, "observer_registration_ambiguous", "ambiguous retry rejected")
    equal(eventA.addCalls, 1, "ambiguous event not retried")
    local eventB = newEvent("store_then_throw")
    harness.globals.Events.AddXP = eventB
    equal(harness.source.install().code, "observer_registration_ambiguous",
        "replacement event can become independently ambiguous")
    equal(eventB.addCalls, 1, "replacement ambiguity attempted once")
    harness.globals.Events.AddXP = eventA
    equal(harness.source.install().code, "observer_registration_ambiguous",
        "return to first ambiguous event is never retried")
    equal(eventA.addCalls, 1, "first ambiguous event remains non-retryable")
    local eventC = newEvent()
    harness.globals.Events.AddXP = eventC
    equal(harness.source.install().code, "installed",
        "fresh event can still install successfully")
    equal(eventC.addCalls, 1, "fresh event is registered once")
end

do
    local event = newEvent("return_false")
    local harness = newHarness({ event = event })
    equal(harness.source.install().code, "installed", "non-throwing registration is accepted")
    equal(event.addCalls, 1, "non-throwing registration attempted once")
end

do
    local harness = newHarness()
    local installed = harness.source.install()
    truthy(installed.ok, "authoritative install succeeds")
    equal(installed.code, "installed", "install code")
    equal(harness.event.addCalls, 1, "observer registered once")
    local wrapper = harness.globals.addXp
    local noMultiplierWrapper = harness.globals.addXpNoMultiplier
    local again = harness.source.install()
    equal(again.code, "already_installed", "repeat install idempotent")
    equal(harness.event.addCalls, 1, "repeat install does not register")
    equal(harness.globals.addXp, wrapper, "repeat install retains wrapper")
    equal(harness.globals.addXpNoMultiplier, noMultiplierWrapper, "repeat retains other wrapper")
    local status = harness.source.status()
    equal(status.installed, true, "installed status")
    equal(status.captureEnabled, true, "capture enabled status")
    equal(status.observerRegistration, "registered", "registered status")
    equal(status.ownsAddXp, true, "owns addXp")
    equal(status.ownsAddXpNoMultiplier, true, "owns no multiplier")
    equal(status.ownsEvent, true, "owns event")
end

do
    local harness = newHarness()
    harness.source.install()
    local marker = {}
    local returned = pack(harness.globals.addXp(harness.player, harness.perk, 2.5, nil, marker, nil))
    equal(returned.n, 4, "exact return arity")
    equal(returned[1], "addXp", "first return")
    equal(returned[2], nil, "middle nil return")
    equal(returned[3], "tail", "third return")
    equal(returned[4], nil, "trailing nil return")
    local priorArgs = harness.calls.addXp[1]
    equal(priorArgs.n, 6, "exact argument arity")
    equal(priorArgs[4], nil, "argument nil position")
    equal(priorArgs[5], marker, "argument identity")
    equal(priorArgs[6], nil, "trailing argument nil")
    equal(#harness.calls.awards, 1, "one envelope")
    local award = harness.calls.awards[1].award
    equal(award.perkId, "Axe", "safe perk identity")
    equal(award.baseAward, 2.5, "exact base award")
    equal(award.appliedDelta, 2.5, "exact applied delta")
    equal(award.actualPositionBefore, 10, "exact before position")
    equal(award.actualPositionAfter, 12.5, "exact after position")
    equal(fieldCount(award), 5, "envelope contains only contracted fields")
    equal(harness.source.status().lastCode, "award_processed", "success status")
end

do
    local harness = newHarness()
    harness.source.install()
    harness.globals.addXpNoMultiplier(harness.player, harness.perk, 4)
    equal(#harness.calls.addXp, 0, "no-multiplier avoids standard prior")
    equal(#harness.calls.addXpNoMultiplier, 1, "no-multiplier prior once")
    equal(harness.calls.awards[1].award.baseAward, 4, "no-multiplier base isolated")
end

do
    local function exactFailure()
        error("prior exact error")
    end
    local baseline = pack(pcall(exactFailure))
    local harness = newHarness({
        priorBehavior = function(kind, globals, event, args)
            return exactFailure()
        end,
    })
    harness.source.install()
    local called = pack(pcall(harness.globals.addXp, harness.player, harness.perk, 1))
    equal(called[1], false, "prior error preserved")
    equal(called[2], baseline[2], "prior error value preserved")
    equal(#harness.calls.awards, 0, "prior error has no envelope")
    equal(harness.source.status().lastCode, "prior_threw", "prior error status")
end

local function assertNoEnvelope(options, expectedCode, behavior)
    options = options or {}
    options.priorBehavior = behavior or options.priorBehavior
    local harness = newHarness(options)
    harness.source.install()
    harness.globals.addXp(harness.player, harness.perk, 1)
    equal(#harness.calls.awards, 0, expectedCode .. " has no envelope")
    equal(harness.source.status().lastCode, expectedCode, expectedCode .. " status")
end

assertNoEnvelope({}, "missing_event", function(kind, globals, event, args)
    args[1].positions[args[2].id] = args[1].positions[args[2].id] + 1
end)

assertNoEnvelope({}, "mismatched_event", function(kind, globals, event, args)
    args[1].positions[args[2].id] = args[1].positions[args[2].id] + 1
    event.fire({}, args[2], 1)
    event.fire(args[1], args[2], 1)
end)

assertNoEnvelope({}, "mismatched_event", function(kind, globals, event, args)
    args[1].positions[args[2].id] = args[1].positions[args[2].id] + 1
    event.fire(args[1], {}, 1)
end)

assertNoEnvelope({}, "multiple_events", function(kind, globals, event, args)
    args[1].positions[args[2].id] = args[1].positions[args[2].id] + 2
    event.fire(args[1], args[2], 1)
    event.fire(args[1], args[2], 1)
end)

assertNoEnvelope({}, "invalid_applied_delta", function(kind, globals, event, args)
    event.fire(args[1], args[2], 0 / 0)
end)

assertNoEnvelope({}, "invalid_applied_delta", function(kind, globals, event, args)
    event.fire(args[1], args[2], math.huge)
end)

do
    local invalidBases = { 0 / 0, math.huge, -math.huge, "1", nil }
    for index = 1, #invalidBases do
        local harness = newHarness({
            priorBehavior = function(kind, globals, event, args)
                return "vanilla"
            end,
        })
        harness.source.install()
        equal(harness.globals.addXp(harness.player, harness.perk, invalidBases[index]), "vanilla",
            "invalid base preserves prior " .. index)
        equal(#harness.calls.awards, 0, "invalid base no envelope " .. index)
        equal(harness.source.status().lastCode, "invalid_base_award", "invalid base status " .. index)
    end
    local nilHarness = newHarness({
        priorBehavior = function()
            return "vanilla nil base"
        end,
    })
    nilHarness.source.install()
    equal(nilHarness.globals.addXp(nilHarness.player, nilHarness.perk, nil), "vanilla nil base",
        "nil base preserves prior")
    equal(#nilHarness.calls.awards, 0, "nil base no envelope")
    equal(nilHarness.source.status().lastCode, "invalid_base_award", "nil base status")
end

do
    local invalidIdentityCases = {
        { identityFailure = true, code = "identity_failed" },
        { identityThrow = true, code = "identity_threw" },
        { invalidIdentity = 4, code = "identity_failed" },
        { invalidIdentity = "", code = "identity_failed" },
        { invalidIdentity = "bad id", code = "identity_failed" },
        { invalidIdentity = "bad/id", code = "identity_failed" },
    }
    for index = 1, #invalidIdentityCases do
        local harness = newHarness(invalidIdentityCases[index])
        harness.source.install()
        harness.globals.addXp(harness.player, harness.perk, 1)
        equal(#harness.calls.awards, 0, "invalid identity no envelope " .. index)
        equal(harness.source.status().lastCode, invalidIdentityCases[index].code,
            "invalid identity status " .. index)
    end

    local safeId = "mod.perk:skill-1"
    local safeHarness = newHarness({
        invalidIdentity = safeId,
        priorBehavior = function(kind, globals, event, args)
            args[1].positions[safeId] = args[1].positions[safeId] + args[3]
            event.fire(args[1], args[2], args[3])
        end,
    })
    safeHarness.player.positions[safeId] = 7
    safeHarness.source.install()
    safeHarness.globals.addXp(safeHarness.player, safeHarness.perk, 2)
    equal(#safeHarness.calls.awards, 1, "safe punctuation identity accepted")
    equal(safeHarness.calls.awards[1].award.perkId, safeId, "safe identity preserved exactly")
end

do
    local invalidPositionCases = {
        { readFailure = true, code = "before_position_failed" },
        { readThrow = true, code = "before_position_threw" },
        { positionOverride = -1, code = "before_position_failed" },
        { positionOverride = math.huge, code = "before_position_failed" },
        { positionOverride = 0 / 0, code = "before_position_failed" },
    }
    for index = 1, #invalidPositionCases do
        local harness = newHarness(invalidPositionCases[index])
        harness.source.install()
        harness.globals.addXp(harness.player, harness.perk, 1)
        equal(#harness.calls.awards, 0, "invalid before position no envelope " .. index)
        equal(harness.source.status().lastCode, invalidPositionCases[index].code,
            "invalid before position status " .. index)
    end
end


do
    local afterCases = {
        { afterReadFailure = true, code = "after_position_failed" },
        { afterReadThrow = true, code = "after_position_threw" },
        { afterPositionOverride = -1, code = "after_position_failed" },
        { afterPositionOverride = math.huge, code = "after_position_failed" },
    }
    for index = 1, #afterCases do
        local harness = newHarness(afterCases[index])
        harness.source.install()
        harness.globals.addXp(harness.player, harness.perk, 1)
        equal(#harness.calls.awards, 0, "invalid after position no envelope " .. index)
        equal(harness.source.status().lastCode, afterCases[index].code,
            "invalid after position status " .. index)
        equal(harness.getReadCalls(), 2, "after position read attempted " .. index)
    end
end

do
    local reads = 0
    local harness = newHarness()
    harness.dependencies.positionReader.read = function() end
    local originalRead = harness.dependencies.positionReader.read
    equal(harness.dependencies.positionReader.read, originalRead, "dependency table remains mutable by owner")
    harness.source.install()
    harness.globals.addXp(harness.player, harness.perk, 1)
    equal(#harness.calls.awards, 1, "captured dependency callable is stable")
    equal(reads, 0, "source does not invoke replacement dependency member")
end

do
    local harness = newHarness()
    harness.source.install()
    harness.globals.addXp(harness.player, harness.perk, 1)
    harness.globals.addXp(harness.player, harness.perk, 1)
    equal(#harness.calls.awards, 2, "installed source captures awards")
    equal(harness.calls.authority, 1, "authority is not checked on award calls")
    equal(harness.source.install().code, "already_installed", "reinstall remains idempotent")
    equal(harness.calls.authority, 2, "authority is checked on reinstall")
    harness.globals.addXp(harness.player, harness.perk, 1)
    equal(harness.calls.authority, 2, "authority remains off the hot path after reinstall")
end

do
    local outerPlayer = { positions = { Axe = 10 } }
    local innerPlayer = { positions = { Cooking = 30 } }
    local outerPerk = { id = "Axe" }
    local innerPerk = { id = "Cooking" }
    local harness
    harness = newHarness({
        priorBehavior = function(kind, globals, event, args)
            if kind == "addXp" then
                globals.addXpNoMultiplier(innerPlayer, innerPerk, 3)
            end
            args[1].positions[args[2].id] = args[1].positions[args[2].id] + args[3]
            event.fire(args[1], args[2], args[3])
            return kind
        end,
    })
    harness.source.install()
    harness.globals.addXp(outerPlayer, outerPerk, 2)
    equal(#harness.calls.awards, 2, "nested transactions both captured")
    equal(harness.calls.awards[1].player, innerPlayer, "inner handled first")
    equal(harness.calls.awards[1].award.baseAward, 3, "inner exact base")
    equal(harness.calls.awards[2].player, outerPlayer, "outer handled second")
    equal(harness.calls.awards[2].award.baseAward, 2, "outer exact base")
    equal(harness.calls.awards[2].award.actualPositionBefore, 10, "outer before isolated")
    equal(harness.calls.awards[2].award.actualPositionAfter, 12, "outer after isolated")
end

do
    local failureHarness = newHarness({ handlerFailure = true })
    failureHarness.source.install()
    equal(failureHarness.globals.addXp(failureHarness.player, failureHarness.perk, 1), "addXp",
        "handler failure preserves vanilla return")
    equal(failureHarness.source.status().lastCode, "handler_failed", "handler failure bounded code")
    local throwHarness = newHarness({ handlerThrow = true })
    throwHarness.source.install()
    local returned = pack(throwHarness.globals.addXp(throwHarness.player, throwHarness.perk, 1))
    equal(returned[1], "addXp", "handler throw preserves vanilla return")
    equal(returned.n, 4, "handler throw preserves return arity")
    equal(throwHarness.source.status().lastCode, "handler_threw", "handler throw bounded code")
    local status = throwHarness.source.status()
    equal(status.player, nil, "status omits player")
    equal(status.perk, nil, "status omits perk")
    equal(status.amount, nil, "status omits amount")
    equal(status.transactions, nil, "status omits transactions")
end

do
    local function ownershipCase(replace, detail)
        local harness = newHarness()
        harness.source.install()
        replace(harness)
        local verified = harness.source.verifyOwnership()
        equal(verified.ok, false, detail .. " ownership failure")
        equal(verified.code, "ownership_lost", detail .. " ownership code")
        equal(verified.detail, detail, detail .. " ownership detail")
        equal(harness.source.status().captureEnabled, false, detail .. " disables capture")
        local installed = harness.source.install()
        equal(installed.code, "ownership_lost", detail .. " reinstall blocked")
        equal(installed.detail, detail, detail .. " reinstall reason")
        return harness
    end
    local laterAdd = function() return "later" end
    local addHarness = ownershipCase(function(h) h.globals.addXp = laterAdd end, "addXp")
    equal(addHarness.globals.addXp, laterAdd, "later addXp not overwritten")
    ownershipCase(function(h) h.globals.addXpNoMultiplier = function() end end, "addXpNoMultiplier")
    local replacementEvent = newEvent()
    local eventHarness = ownershipCase(function(h) h.globals.Events.AddXP = replacementEvent end, "Events.AddXP")
    equal(eventHarness.globals.Events.AddXP, replacementEvent, "later event not overwritten")
end

do
    local harness = newHarness()
    local beforeDependencies = harness.dependencies.environment.globals
    local beforeAuthority = harness.dependencies.authority
    local beforeIdentity = harness.dependencies.perkIdentity
    local beforeReader = harness.dependencies.positionReader
    local beforeHandler = harness.dependencies.awardHandler
    harness.source.install()
    equal(harness.dependencies.environment.globals, beforeDependencies, "globals dependency not replaced")
    equal(harness.dependencies.authority, beforeAuthority, "authority dependency not replaced")
    equal(harness.dependencies.perkIdentity, beforeIdentity, "identity dependency not replaced")
    equal(harness.dependencies.positionReader, beforeReader, "reader dependency not replaced")
    equal(harness.dependencies.awardHandler, beforeHandler, "handler dependency not replaced")
    local firstStatus = harness.source.status()
    firstStatus.installed = false
    firstStatus.lastCode = "private"
    local secondStatus = harness.source.status()
    equal(secondStatus.installed, true, "status result is fresh")
    equal(secondStatus.lastCode, "installed", "status mutation is isolated")
    harness.event.fire(harness.player, harness.perk, 99)
    equal(#harness.calls.awards, 0, "event outside a transaction is inert")
end

return assertions
