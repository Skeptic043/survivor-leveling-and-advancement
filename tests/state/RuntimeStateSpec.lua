local C = StateCodec
local StoreFactory = PlayerStateStore
local Scope = MutationScope
local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed") end
end

local function validPerk()
    return {
        adapterId = "sla.vanilla", adapterVersion = 1, curveFingerprint = "curve-a",
        effectiveMaximum = 10, naturalPosition = 4, highWaterPosition = 5,
        activeTargets = { { targetId = "target-a", targetLevel = 6, targetPosition = 6 } },
        postMaxFullRateUsed = 0,
    }
end

local function validState()
    return {
        schemaVersion = 1, revision = 3,
        survivor = { level = 2, xpIntoLevel = 100, spent = 1 },
        perks = { Axe = validPerk() }, orphanedPerks = {},
    }
end

local function inFlight()
    return {
        requestId = "request-a", perkId = "Axe", preRevision = 3, preSpent = 1,
        preLevel = 5, prePosition = 1000, targetLevel = 6, targetPosition = 1200,
        adapterId = "sla.vanilla", adapterVersion = 1, curveFingerprint = "curve-a",
        effectiveMaximum = 10,
    }
end

local function invalid(value, code, message)
    local result = C.decode(value)
    expect(not result.ok and result.code == code, message or ("expected " .. code))
end

local absent = C.encode(validState())
expect(absent.ok and absent.state.inFlightAdvancement == nil, "absent in-flight round trip")
local presentRaw = validState()
presentRaw.inFlightAdvancement = inFlight()
local present = C.decode(presentRaw)
expect(present.ok and present.state.inFlightAdvancement.requestId == "request-a", "present in-flight round trip")
present.state.inFlightAdvancement.requestId = "changed"
expect(presentRaw.inFlightAdvancement.requestId == "request-a", "in-flight result is detached")
local same = validState()
same.inFlightAdvancement = inFlight()
expect(C.encode(presentRaw).canonical == C.encode(same).canonical, "in-flight canonical field order")
expect(C.encode(validState()).canonical ~= C.encode(same).canonical, "canonical distinguishes in-flight absence")

local unknownInFlight = validState()
unknownInFlight.inFlightAdvancement = inFlight()
unknownInFlight.inFlightAdvancement.extra = true
invalid(unknownInFlight, "invalid_in_flight_advancement", "in-flight unknown field")
local targetAboveMax = validState()
targetAboveMax.inFlightAdvancement = inFlight()
targetAboveMax.inFlightAdvancement.targetLevel = 11
invalid(targetAboveMax, "invalid_in_flight_advancement", "in-flight maximum bound")
local malformedPosition = validState()
malformedPosition.inFlightAdvancement = inFlight()
malformedPosition.inFlightAdvancement.targetPosition = -1
invalid(malformedPosition, "invalid_in_flight_advancement", "in-flight position bound")
local malformedCurve = validState()
malformedCurve.inFlightAdvancement = inFlight()
malformedCurve.inFlightAdvancement.curveFingerprint = ""
invalid(malformedCurve, "invalid_in_flight_advancement", "in-flight curve fingerprint")
local skippedTarget = validState()
skippedTarget.inFlightAdvancement = inFlight()
skippedTarget.inFlightAdvancement.targetLevel = 7
invalid(skippedTarget, "invalid_in_flight_advancement", "in-flight target must be the next level")
local backwardTarget = validState()
backwardTarget.inFlightAdvancement = inFlight()
backwardTarget.inFlightAdvancement.targetPosition = 1000
invalid(backwardTarget, "invalid_in_flight_advancement", "in-flight target must advance position")
local excessivePreSpent = validState()
excessivePreSpent.inFlightAdvancement = inFlight()
excessivePreSpent.inFlightAdvancement.preSpent = 3
invalid(excessivePreSpent, "invalid_in_flight_advancement", "in-flight pre-spent cannot exceed Survivor level")
local unexpectedRevision = validState()
unexpectedRevision.inFlightAdvancement = inFlight()
unexpectedRevision.revision = 5
invalid(unexpectedRevision, "invalid_in_flight_advancement", "in-flight revision is bounded")
local unexpectedSpent = validState()
unexpectedSpent.inFlightAdvancement = inFlight()
unexpectedSpent.survivor.spent = 0
invalid(unexpectedSpent, "invalid_in_flight_advancement", "in-flight spent is bounded")
local completedReservation = validState()
completedReservation.inFlightAdvancement = inFlight()
completedReservation.revision = 4
completedReservation.survivor.spent = 2
expect(C.decode(completedReservation).ok, "in-flight accepts completed reservation counters")
local survivorAtCost = validState()
survivorAtCost.survivor.xpIntoLevel = 1800
invalid(survivorAtCost, "invalid_survivor", "survivor XP at level cost fails")
local targetAtHighWater = validState()
targetAtHighWater.perks.Axe.activeTargets[1].targetPosition = 5
invalid(targetAtHighWater, "invalid_perk", "target at high water fails")

local created = StoreFactory.create(C)
expect(created.ok, "store creation")
local store = created.store
local modData = { untouched = "value" }
local player = { calls = 0 }
function player:getModData()
    self.calls = self.calls + 1
    return modData
end
local missing = store.load(player)
expect(missing.ok and missing.state.revision == 0 and modData.SurvivorLevelingAdvancement == nil, "missing load is fresh and non-writing")
local source = validState()
local saved = store.save(player, source)
expect(saved.ok and modData.untouched == "value" and modData.SurvivorLevelingAdvancement ~= nil, "save writes only namespace")
source.survivor.level = 9
saved.state.survivor.level = 8
local loaded = store.load(player)
expect(loaded.ok and loaded.state.survivor.level == 2, "store save and load tables are detached")
loaded.state.survivor.level = 7
local reloaded = store.load(player)
expect(reloaded.ok and reloaded.state.survivor.level == 2, "load result is detached")
local invalidPlayer = { calls = 0 }
function invalidPlayer:getModData()
    self.calls = self.calls + 1
    return { untouched = true }
end
local rejected = store.save(invalidPlayer, { schemaVersion = 1 })
expect(not rejected.ok and invalidPlayer.calls == 0, "invalid save does not read or write ModData")
local missingCapability = store.save({}, validState())
expect(not missingCapability.ok and missingCapability.code == "missing_player_mod_data", "save missing capability fails closed")
expect(not StoreFactory.create({ decode = C.decode }).ok, "store requires both codec operations")

local playerA, playerB = {}, {}
local first = Scope.begin(playerA, "Axe")
expect(first.ok and Scope.isActive(playerA, "Axe"), "scope becomes active")
local duplicate = Scope.begin(playerA, "Axe")
expect(not duplicate.ok and duplicate.code == "scope_active", "same player perk collision")
local otherPerk = Scope.begin(playerA, "Spear")
local otherPlayer = Scope.begin(playerB, "Axe")
expect(otherPerk.ok and otherPlayer.ok and Scope.isActive(playerA, "Spear") and Scope.isActive(playerB, "Axe"), "scope isolation")
expect(not Scope.begin(playerA, "not a perk").ok, "scope rejects unsafe perk ID")
expect(not Scope.finish({}).ok, "foreign handle fails")
expect(Scope.finish(first.handle).ok and not Scope.isActive(playerA, "Axe"), "finish clears exact scope")
expect(not Scope.finish(first.handle).ok, "double finish fails")
local replacement = Scope.begin(playerA, "Axe")
expect(replacement.ok and not Scope.finish(first.handle).ok and Scope.isActive(playerA, "Axe"), "stale handle cannot clear replacement")
expect(Scope.finish(replacement.handle).ok and Scope.finish(otherPerk.handle).ok and Scope.finish(otherPlayer.handle).ok, "isolated scopes finish")
expect(not Scope.isActive(nil, "Axe"), "invalid lookup is inactive")

return assertions
