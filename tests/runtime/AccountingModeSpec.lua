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

local function empty(map)
    for _ in pairs(map) do return false end
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
local noOp = state("Tracked")
noOp.inFlightAdvancement = { private = true }
local noTransition = service.synchronizeLoaded(player, noOp, "Tracked")
expect(noTransition.ok and noTransition.state == noOp and not noTransition.transitioned, "same-mode returns exact state")
expectEqual(calls.clear, 0, "same-mode skips observation clear")
expectEqual(calls.save, 0, "same-mode skips save")

local tracked = state("Tracked")
local toFree = service.synchronizeLoaded(player, tracked, "Free")
expect(toFree.ok and toFree.transitioned and toFree.fromMode == "Tracked" and toFree.toMode == "Free", "tracked transition succeeds")
expect(toFree.state ~= tracked and toFree.state.accountingMode == "Free" and toFree.state.revision == 5, "tracked transition is detached and revisioned")
expect(toFree.state.perks.Axe ~= nil and toFree.state.orphanedPerks.Removed ~= nil, "tracked accounting freezes into free mode")
expect(tracked.perks.Axe ~= nil and tracked.orphanedPerks.Removed ~= nil and toFree.state.survivor.spent == 3, "source and AP are preserved")
expectEqual(calls.clear, 1, "tracked-to-free clears observations once")
expectEqual(calls.save, 1, "tracked-to-free saves once")
expectEqual(calls.clearPlayer, player, "clear receives exact player")
expectEqual(calls.savePlayer, player, "save receives exact player")
expectEqual(calls.saved, toFree.state, "save receives transition candidate")
expectEqual(calls.order[1], "clear", "clear precedes save")
expectEqual(calls.order[2], "save", "save follows clear")
tracked.perks.Axe.adapterId = "changed"
expectEqual(toFree.state.perks.Axe.adapterId, "old", "later source mutation cannot change frozen candidate")

service, calls = fixtures()
local free = state("Free")
local toTracked = service.synchronizeLoaded(player, free, "Tracked")
expect(toTracked.ok and toTracked.transitioned and toTracked.state.accountingMode == "Tracked" and toTracked.state.revision == 5, "free transition succeeds")
expect(empty(toTracked.state.perks) and empty(toTracked.state.orphanedPerks), "tracked mode starts with lazy-baseline maps")
expect(free.perks.Axe ~= nil and free.orphanedPerks.Removed ~= nil and free.survivor.spent == toTracked.state.survivor.spent, "free source and AP are preserved")
expectEqual(calls.clear, 1, "free-to-tracked clears observations once")
expectEqual(calls.save, 1, "free-to-tracked saves once")

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

service, calls = fixtures({ saveResult = { ok = false } })
rejected = service.synchronizeLoaded(player, state("Tracked"), "Free")
expectEqual(rejected.code, "save_failed")
expectEqual(calls.clear, 1, "failed save follows clear")
expectEqual(calls.save, 1, "failed save is attempted once")

service, calls = fixtures({ saveResult = setmetatable({ ok = true }, {}) })
rejected = service.synchronizeLoaded(player, state("Tracked"), "Free")
expectEqual(rejected.code, "save_failed")
expectEqual(calls.save, 1, "non-plain save acknowledgement is rejected")

return assertions
