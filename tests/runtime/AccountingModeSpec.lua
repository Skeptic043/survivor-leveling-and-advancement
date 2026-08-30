local ServiceFactory = AccountingMode
local assertions = 0

local function expect(value, message)
    assertions = assertions + 1
    if not value then error(message or "expectation failed") end
end

local function expectEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error(message or (tostring(actual) .. " ~= " .. tostring(expected))) end
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

local function state(mode)
    return {
        schemaVersion = 2,
        accountingMode = mode,
        revision = 4,
        survivor = { level = 6, xpIntoLevel = 100, spent = 3 },
        perks = {
            Axe = {
                adapterId = "old", adapterVersion = 1, curveFingerprint = "old-curve", effectiveMaximum = 10,
                naturalPosition = 1, highWaterPosition = 4, activeTargets = {}, postMaxFullRateUsed = 2,
            },
        },
        orphanedPerks = {
            Removed = {
                adapterId = "old", adapterVersion = 1, curveFingerprint = "old-curve", effectiveMaximum = 10,
                naturalPosition = 1, highWaterPosition = 4, activeTargets = {}, postMaxFullRateUsed = 2,
            },
        },
    }
end

local function fixtures(options)
    options = options or {}
    local calls = { clear = 0, save = 0, order = {} }
    local clearPlayer = function(receivedPlayer)
        calls.clear = calls.clear + 1
        calls.clearPlayer = receivedPlayer
        calls.order[#calls.order + 1] = "clear"
        if options.clearThrows then error("clear failure") end
        return options.clearResult or { ok = true, diagnostic = "accepted" }
    end
    local save = function(receivedPlayer, candidate)
        calls.save = calls.save + 1
        calls.savePlayer = receivedPlayer
        calls.saved = candidate
        calls.order[#calls.order + 1] = "save"
        if options.saveThrows then error("save failure") end
        return options.saveResult or { ok = true, diagnostic = "accepted" }
    end
    local created = ServiceFactory.create({
        store = { save = save },
        ActualObservation = { clearPlayer = clearPlayer },
        catalog = { allPerks = function() error("accounting mode must not enumerate perks") end },
    })
    expect(created.ok, "service creation")
    return created.service, calls
end

expectEqual(ServiceFactory.create(nil).code, "invalid_dependencies")
expectEqual(ServiceFactory.create({}).code, "invalid_store")
expectEqual(ServiceFactory.create({ store = { save = function() end } }).code, "invalid_observation")

local player = {}
local service, calls = fixtures()
expectEqual(service.transitionGeneration(player).generation, 0, "new player begins at transition generation zero")
local noOp = state("Tracked")
noOp.inFlightAdvancement = { private = true }
local noTransition = service.synchronizeLoaded(player, noOp, "Tracked")
expect(noTransition.ok and noTransition.state == noOp and not noTransition.transitioned, "same-mode returns exact state")
expectEqual(calls.clear, 0, "same-mode skips observation clear")
expectEqual(calls.save, 0, "same-mode skips save")
expectEqual(service.transitionGeneration(player).generation, 0, "same-mode synchronization does not advance transition generation")

local tracked = state("Tracked")
local toFree = service.synchronizeLoaded(player, tracked, "Free")
expect(toFree.ok and toFree.transitioned and toFree.fromMode == "Tracked" and toFree.toMode == "Free", "tracked transition succeeds")
expect(toFree.state ~= tracked and toFree.state.accountingMode == "Free" and toFree.state.revision == 5, "tracked transition is detached and revisioned")
expect(toFree.state.perks.Axe ~= nil and toFree.state.orphanedPerks.Removed ~= nil, "tracked accounting freezes into free mode")
expect(same(toFree.state.perks, tracked.perks) and same(toFree.state.orphanedPerks, tracked.orphanedPerks), "tracked-to-free preserves accounting maps byte-for-byte")
expect(tracked.perks.Axe ~= nil and tracked.orphanedPerks.Removed ~= nil and toFree.state.survivor.spent == 3, "source and AP are preserved")
expectEqual(calls.clear, 1, "tracked-to-free clears observations once")
expectEqual(calls.save, 1, "tracked-to-free saves once")
expectEqual(calls.clearPlayer, player, "clear receives exact player")
expectEqual(calls.savePlayer, player, "save receives exact player")
expectEqual(calls.saved, toFree.state, "save receives transition candidate")
expectEqual(calls.order[1], "clear", "clear precedes save")
expectEqual(calls.order[2], "save", "save follows clear")
expectEqual(service.transitionGeneration(player).generation, 1, "successful transition advances generation once")
tracked.perks.Axe.adapterId = "changed"
expectEqual(toFree.state.perks.Axe.adapterId, "old", "later source mutation cannot change frozen candidate")

service, calls = fixtures()
local free = state("Free")
local frozenPerks = free.perks
local frozenOrphans = free.orphanedPerks
local toTracked = service.synchronizeLoaded(player, free, "Tracked")
expect(toTracked.ok and toTracked.transitioned and toTracked.state.accountingMode == "Tracked" and toTracked.state.revision == 5, "free transition succeeds")
expect(toTracked.state.perks.Axe ~= nil and toTracked.state.orphanedPerks.Removed ~= nil, "tracked mode restores preserved accounting maps")
expect(toTracked.state.perks ~= frozenPerks and toTracked.state.orphanedPerks ~= frozenOrphans, "restored accounting remains detached")
expect(same(toTracked.state.perks, free.perks) and same(toTracked.state.orphanedPerks, free.orphanedPerks), "free-to-tracked restores accounting maps byte-for-byte")
expect(free.perks.Axe ~= nil and free.orphanedPerks.Removed ~= nil and free.survivor.spent == toTracked.state.survivor.spent, "free source and AP are preserved")
expectEqual(calls.clear, 1, "free-to-tracked clears observations once")
expectEqual(calls.save, 1, "free-to-tracked saves once")
expectEqual(service.transitionGeneration(player).generation, 1, "independent service transition starts at generation one")

service, calls = fixtures()
local reserved = state("Free")
reserved.inFlightAdvancement = { private = true }
local rejected = service.synchronizeLoaded(player, reserved, "Tracked")
expectEqual(rejected.code, "in_flight_advancement")
expectEqual(calls.clear, 0, "in-flight rejection skips observation clear")
expectEqual(calls.save, 0, "in-flight rejection skips save")

service, calls = fixtures({ clearThrows = true })
local failedSource = state("Tracked")
rejected = service.synchronizeLoaded(player, failedSource, "Free")
expectEqual(rejected.code, "observation_clear_failed")
expectEqual(calls.clear, 1, "throwing clear is attempted once")
expectEqual(calls.save, 0, "throwing clear skips save")
expectEqual(failedSource.accountingMode, "Tracked", "throwing clear preserves supplied state")

service, calls = fixtures({ clearResult = {} })
rejected = service.synchronizeLoaded(player, state("Tracked"), "Free")
expectEqual(rejected.code, "observation_clear_failed")
expectEqual(calls.save, 0, "malformed clear skips save")

service, calls = fixtures({ clearResult = setmetatable({ ok = true }, {}) })
rejected = service.synchronizeLoaded(player, state("Tracked"), "Free")
expectEqual(rejected.code, "observation_clear_failed")
expectEqual(calls.save, 0, "non-plain clear acknowledgement skips save")

service, calls = fixtures({ saveThrows = true })
failedSource = state("Tracked")
rejected = service.synchronizeLoaded(player, failedSource, "Free")
expectEqual(rejected.code, "save_failed")
expectEqual(calls.clear, 1, "throwing save follows clear")
expectEqual(calls.save, 1, "throwing save is attempted once")
expectEqual(failedSource.accountingMode, "Tracked", "throwing save preserves supplied state")
expectEqual(service.transitionGeneration(player).generation, 0, "throwing save does not advance transition generation")

service, calls = fixtures({ saveResult = { ok = false } })
rejected = service.synchronizeLoaded(player, state("Tracked"), "Free")
expectEqual(rejected.code, "save_failed")
expectEqual(calls.clear, 1, "failed save follows clear")
expectEqual(calls.save, 1, "failed save is attempted once")
expectEqual(service.transitionGeneration(player).generation, 0, "failed save does not advance transition generation")

local retryOptions = { saveResult = { ok = false } }
service, calls = fixtures(retryOptions)
failedSource = state("Free")
rejected = service.synchronizeLoaded(player, failedSource, "Tracked")
expectEqual(rejected.code, "save_failed", "failed restore is reported")
expect(failedSource.perks.Axe ~= nil and failedSource.orphanedPerks.Removed ~= nil, "failed restore preserves supplied accounting")
retryOptions.saveResult = { ok = true }
local retried = service.synchronizeLoaded(player, failedSource, "Tracked")
expect(retried.ok and retried.state.perks.Axe ~= nil and retried.state.orphanedPerks.Removed ~= nil, "failed restore retries with preserved accounting")
expectEqual(retried.state.revision, 5, "restore retry increments revision exactly once")
expectEqual(service.transitionGeneration(player).generation, 1, "successful retry advances transition generation exactly once")

local roundTripService = fixtures()
local roundTripPlayer = {}
local roundTripFree = roundTripService.synchronizeLoaded(roundTripPlayer, state("Tracked"), "Free")
local roundTripTracked = roundTripService.synchronizeLoaded(roundTripPlayer, roundTripFree.state, "Tracked")
expect(roundTripTracked.ok, "unobserved round trip succeeds")
expectEqual(roundTripService.transitionGeneration(roundTripPlayer).generation, 2, "round trip retains both monotonic transition boundaries")
expectEqual(roundTripService.transitionGeneration({}).generation, 0, "transition generations are player-scoped")

service, calls = fixtures({ saveResult = setmetatable({ ok = true }, {}) })
rejected = service.synchronizeLoaded(player, state("Tracked"), "Free")
expectEqual(rejected.code, "save_failed")
expectEqual(calls.save, 1, "non-plain save acknowledgement is rejected")

return assertions
