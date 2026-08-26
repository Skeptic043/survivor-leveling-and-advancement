local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed") end
end

local function expectEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual))) end
end

local function failure(result, code, detail)
    expectEqual(result.ok, false, "failure expected")
    expectEqual(result.code, code, "failure code")
    expectEqual(result.detail, detail, "failure detail")
    expectEqual(result.snapshot, nil, "failure has no partial snapshot")
end

local function sameShape(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not sameShape(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function contains(value, forbidden, seen)
    if value == forbidden then return true end
    if type(value) ~= "table" then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, child in pairs(value) do
        if contains(key, forbidden, seen) or contains(child, forbidden, seen) then return true end
    end
    return false
end

local function published(ids)
    local perks = {}
    for index = 1, #ids do perks[index] = { id = ids[index] } end
    return {
        allPerks = function()
            return { ok = true, perks = perks }
        end,
        perkIdentity = {
            resolve = function(perk)
                return { ok = true, perkId = perk.id }
            end,
        },
    }
end

local function economy()
    return {
        availableAp = function(state)
            return { ok = true, availableAp = state.level - state.spent }
        end,
        nextLevelCost = function(level)
            return { ok = true, cost = 1200 + level * 300 }
        end,
    }
end

local function record(seed)
    return {
        adapterId = "private.adapter." .. seed,
        adapterVersion = 4,
        curveFingerprint = "private.curve." .. seed,
        effectiveMaximum = 10,
        naturalPosition = 3.5,
        highWaterPosition = 4,
        activeTargets = {
            { targetId = "private-target-1", targetLevel = 5, targetPosition = 5.5, privateTarget = "do-not-send" },
            { targetId = "private-target-2", targetLevel = 7, targetPosition = 8.5 },
        },
        postMaxFullRateUsed = 19,
        privateRecord = "do-not-send",
    }
end

local function state()
    return {
        schemaVersion = 1,
        revision = 9,
        survivor = { level = 4, xpIntoLevel = 120, spent = 1, privateSurvivor = "do-not-send" },
        perks = { Axe = record("axe"), Carpentry = record("carpentry"), Orphan = record("orphan") },
        orphanedPerks = { Removed = record("removed") },
        inFlightAdvancement = { requestId = "private-request", perkId = "Axe" },
        privateRoot = "do-not-send",
    }
end

failure(OwnerSnapshot.create(nil), "invalid_dependencies", "dependencies must be a table")
failure(OwnerSnapshot.create({}), "invalid_dependencies", "catalog.allPerks is required")
failure(OwnerSnapshot.create({ catalog = { allPerks = function() end } }), "invalid_dependencies", "catalog.perkIdentity.resolve is required")
failure(OwnerSnapshot.create({ catalog = published({}), SurvivorEconomy = {} }), "invalid_dependencies", "SurvivorEconomy.availableAp is required")
failure(OwnerSnapshot.create({ catalog = published({}), SurvivorEconomy = { availableAp = function() end } }), "invalid_dependencies", "SurvivorEconomy.nextLevelCost is required")

local catalog = published({ "Carpentry", "Axe" })
local created = OwnerSnapshot.create({ catalog = catalog, SurvivorEconomy = economy(), ignored = true })
expectEqual(created.ok, true, "only required capabilities are validated")
local projector = created.projector
local original = state()
local result = projector.project(original, 12, true)
expectEqual(result.ok, true, "projection succeeds")
local snapshot = result.snapshot
expect(sameShape(snapshot, {
    protocolVersion = 1,
    ready = true,
    sequence = 12,
    revision = 9,
    survivor = { level = 4, xpIntoLevel = 120, xpForNextLevel = 2400, spent = 1, availableAp = 3 },
    perks = {
        Axe = { effectiveMaximum = 10, naturalPosition = 3.5, highWaterPosition = 4, activeTargets = { { targetLevel = 5, targetPosition = 5.5 }, { targetLevel = 7, targetPosition = 8.5 } } },
        Carpentry = { effectiveMaximum = 10, naturalPosition = 3.5, highWaterPosition = 4, activeTargets = { { targetLevel = 5, targetPosition = 5.5 }, { targetLevel = 7, targetPosition = 8.5 } } },
    },
}), "complete snapshot allowlist and catalog filtering")
expectEqual(snapshot.perks.Orphan, nil, "unpublished perk is excluded")
expectEqual(snapshot.perks.Removed, nil, "orphaned state is excluded")
expectEqual(snapshot.perks.Axe.activeTargets[1].targetLevel, 5, "target order is preserved")
expect(not contains(snapshot, "private.adapter.axe") and not contains(snapshot, "private-target-1") and not contains(snapshot, "private-request") and not contains(snapshot, "do-not-send"), "secrets and private fields never appear recursively")
snapshot.survivor.level = 99
snapshot.perks.Axe.activeTargets[1].targetPosition = 99
expectEqual(original.survivor.level, 4, "survivor data is detached")
expectEqual(original.perks.Axe.activeTargets[1].targetPosition, 5.5, "targets are deeply detached")

failure(projector.project(nil, 1, true), "invalid_state", "state must be a table")
failure(projector.project({ revision = 0, survivor = {}, perks = {} }, 1, true), "invalid_state", "survivor display fields are malformed")
failure(projector.project(state(), 0, true), "invalid_sequence", "sequence must be a positive integer")
failure(projector.project(state(), 1, "yes"), "invalid_ready", "ready must be a boolean")
local unsafeState = state(); unsafeState.perks["bad id"] = record("bad")
failure(projector.project(unsafeState, 1, true), "invalid_state", "state.perks contains an unsafe perk ID")
local invalidPerk = state(); invalidPerk.perks.Axe.naturalPosition = math.huge
failure(projector.project(invalidPerk, 1, true), "invalid_perk", "perk display fields are malformed")
local invalidTarget = state(); invalidTarget.perks.Axe.activeTargets[2].targetPosition = 5
failure(projector.project(invalidTarget, 1, true), "invalid_target", "target order is malformed")
local sparseTargets = state(); sparseTargets.perks.Axe.activeTargets[3] = sparseTargets.perks.Axe.activeTargets[2]; sparseTargets.perks.Axe.activeTargets[2] = nil
failure(projector.project(sparseTargets, 1, true), "invalid_target", "activeTargets must be a dense array")

local duplicateCatalog = published({ "Axe", "Axe" })
failure(OwnerSnapshot.create({ catalog = duplicateCatalog, SurvivorEconomy = economy() }).projector.project(state(), 1, true), "invalid_catalog", "catalog contains duplicate perk IDs")
local unsafeCatalog = published({ "bad id" })
failure(OwnerSnapshot.create({ catalog = unsafeCatalog, SurvivorEconomy = economy() }).projector.project(state(), 1, true), "invalid_catalog", "catalog.perkIdentity.resolve returned an invalid result")
local emptyCatalogId = published({ "" })
failure(OwnerSnapshot.create({ catalog = emptyCatalogId, SurvivorEconomy = economy() }).projector.project(state(), 1, true), "invalid_catalog", "catalog.perkIdentity.resolve returned an invalid result")
local malformedCatalog = {
    allPerks = function() return { ok = true, perks = { [2] = {} } } end,
    perkIdentity = { resolve = function() return { ok = true, perkId = "Axe" } end },
}
failure(OwnerSnapshot.create({ catalog = malformedCatalog, SurvivorEconomy = economy() }).projector.project(state(), 1, true), "invalid_catalog", "catalog.allPerks returned an invalid result")
local throwingCatalog = {
    allPerks = function() error("catalog failure") end,
    perkIdentity = { resolve = function() return { ok = true, perkId = "Axe" } end },
}
failure(OwnerSnapshot.create({ catalog = throwingCatalog, SurvivorEconomy = economy() }).projector.project(state(), 1, true), "invalid_catalog", "catalog.allPerks failed")

local observedState, observedLevel
local derivedEconomy = {
    availableAp = function(value) observedState = value; return { ok = true, availableAp = 8 } end,
    nextLevelCost = function(level) observedLevel = level; return { ok = true, cost = 4321 } end,
}
local derived = OwnerSnapshot.create({ catalog = published({ "Axe" }), SurvivorEconomy = derivedEconomy }).projector.project(state(), 2, false)
expectEqual(derived.snapshot.ready, false, "readiness is projected")
expectEqual(derived.snapshot.survivor.availableAp, 8, "AP is economy-derived")
expectEqual(derived.snapshot.survivor.xpForNextLevel, 4321, "next-level cost is economy-derived")
expect(observedState.level == 4 and observedState.spent == 1 and observedLevel == 4, "economy receives the survivor state and level")
local rejectedEconomy = { availableAp = function() return { ok = false } end, nextLevelCost = function() return { ok = true, cost = 1 } end }
failure(OwnerSnapshot.create({ catalog = published({ "Axe" }), SurvivorEconomy = rejectedEconomy }).projector.project(state(), 1, true), "economy_failure", "SurvivorEconomy.availableAp returned an invalid result")
local malformedEconomy = { availableAp = function() return { ok = true, availableAp = 1 } end, nextLevelCost = function() return { ok = true, cost = 0 / 0 } end }
failure(OwnerSnapshot.create({ catalog = published({ "Axe" }), SurvivorEconomy = malformedEconomy }).projector.project(state(), 1, true), "economy_failure", "SurvivorEconomy.nextLevelCost returned an invalid result")
local fractionalAp = { availableAp = function() return { ok = true, availableAp = 1.5 } end, nextLevelCost = function() return { ok = true, cost = 9999 } end }
failure(OwnerSnapshot.create({ catalog = published({ "Axe" }), SurvivorEconomy = fractionalAp }).projector.project(state(), 1, true), "economy_failure", "SurvivorEconomy.availableAp returned an invalid result")
local fractionalCost = { availableAp = function() return { ok = true, availableAp = 1 } end, nextLevelCost = function() return { ok = true, cost = 2400.5 } end }
failure(OwnerSnapshot.create({ catalog = published({ "Axe" }), SurvivorEconomy = fractionalCost }).projector.project(state(), 1, true), "economy_failure", "SurvivorEconomy.nextLevelCost returned an invalid result")
local tooLowCost = { availableAp = function() return { ok = true, availableAp = 1 } end, nextLevelCost = function() return { ok = true, cost = 120 } end }
failure(OwnerSnapshot.create({ catalog = published({ "Axe" }), SurvivorEconomy = tooLowCost }).projector.project(state(), 1, true), "economy_failure", "SurvivorEconomy.nextLevelCost must exceed survivor.xpIntoLevel")

return assertions
