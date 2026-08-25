local C = StateCodec
local assertions = 0
local function expect(condition, message) assertions = assertions + 1; if not condition then error(message or "assertion failed") end end
expect(C.canonical == nil and C.WRITER_VERSION == nil, "removed public versioning surface")

local function validPerk(seed)
    return { adapterId = "adapter", adapterVersion = 1, curveFingerprint = "curve-" .. seed,
        effectiveMaximum = 10, naturalPosition = 4.5, highWaterPosition = 5,
        activeTargets = { { targetId = "target-1", targetLevel = 6, targetPosition = 5.5 } }, postMaxFullRateUsed = 0 }
end
local function validState()
    return { schemaVersion = 1, revision = 4, survivor = { level = 2, xpIntoLevel = 3.5, spent = 1 }, perks = { Axe = validPerk("a") }, orphanedPerks = {} }
end
local function orphanedState()
    local state = validState()
    state.orphanedPerks.Axe = state.perks.Axe
    state.perks.Axe = nil
    return state
end
local function bad(value, code)
    local result = C.decode(value)
    expect(not result.ok and result.code == code, "expected " .. code .. ", got " .. tostring(result.code))
end

local function withReservation(targetLevel, maximum, spent)
    local state = validState()
    state.survivor.level = 5
    state.survivor.spent = spent
    state.inFlightAdvancement = {
        requestId = "reserved", perkId = "Axe", preRevision = 4, preSpent = 1,
        preLevel = targetLevel - 1, prePosition = 5, targetLevel = targetLevel, targetPosition = 6,
        adapterId = "adapter", adapterVersion = 1, curveFingerprint = "curve-a", effectiveMaximum = maximum,
    }
    return state
end

local fresh = C.decode(nil); expect(fresh.ok and fresh.state.revision == 0 and fresh.state.survivor.level == 0 and fresh.state.survivor.earned == nil and fresh.state.writerVersion == nil, "fresh approved shape")
local input = validState(); local decoded = C.decode(input); expect(decoded.ok, "decode valid"); decoded.state.perks.Axe.adapterId = "changed"; expect(input.perks.Axe.adapterId == "adapter", "decode deep copy")
local original = validState(); local encoded = C.encode(original); expect(encoded.ok, "encode valid"); encoded.state.survivor.level = 99; expect(original.survivor.level == 2 and original.perks.Axe.activeTargets[1].targetId == "target-1", "encode retained input deep copy"); local roundTrip = C.decode(original); expect(roundTrip.ok and C.encode(roundTrip.state).canonical == C.encode(original).canonical, "round trip")
bad(12, "invalid_state"); bad({}, "unversioned_state"); local nonempty = { foo = true }; bad(nonempty, "unversioned_state")
local cyclic = validState(); cyclic.loop = cyclic; bad(cyclic, "invalid_raw")
local nan = validState(); nan.survivor.xpIntoLevel = 0 / 0; bad(nan, "invalid_raw")
local inf = validState(); inf.survivor.xpIntoLevel = math.huge; bad(inf, "invalid_raw")
local unknown = validState(); unknown.extra = true; bad(unknown, "invalid_state")
local removedRoot = validState(); removedRoot.writerVersion = 1; bad(removedRoot, "invalid_state")
local removedSurvivor = validState(); removedSurvivor.survivor.earned = 2; bad(removedSurvivor, "invalid_survivor")
local removedPerk = validState(); removedPerk.perks.Axe.capabilityEpoch = 0; bad(removedPerk, "invalid_perk")
local removedCarry = validState(); removedCarry.perks.Axe.fractionalCarry = 0; bad(removedCarry, "invalid_perk")
local removedEpoch = validState(); removedEpoch.perks.Axe.postMaxEpoch = 0; bad(removedEpoch, "invalid_perk")
local schemaString = validState(); schemaString.schemaVersion = "0"; bad(schemaString, "invalid_state")
local schemaFraction = validState(); schemaFraction.schemaVersion = 0.5; bad(schemaFraction, "invalid_state")
local schemaNegative = validState(); schemaNegative.schemaVersion = -1; bad(schemaNegative, "invalid_state")
local newer = validState(); newer.schemaVersion = 2; local newerResult = C.decode(newer); expect(not newerResult.ok and newerResult.code == "newer_schema" and newer.schemaVersion == 2, "newer schema preserves raw")
local legacy = validState(); legacy.schemaVersion = 0; legacy.old = true; local migrated = C.decode(legacy, { schemaMigrations = { [0] = function(raw) raw.schemaVersion = 1; raw.old = nil; return raw end } }); expect(migrated.ok, "consecutive migration")
bad(legacy, "missing_schema_migration"); local skip = C.decode(legacy, { schemaMigrations = { [0] = function(raw) raw.schemaVersion = 2; return raw end } }); expect(not skip.ok and skip.code == "schema_migration_not_consecutive", "skip migration")

local loaded = { Axe = { adapterId = "adapter", adapterVersion = 1, curveFingerprint = "curve-a", effectiveMaximum = 10 } }
expect(C.decode(validState(), { loadedPerks = loaded }).ok, "matching active perk")
local mismatch = { Axe = { adapterId = "adapter", adapterVersion = 2, curveFingerprint = "curve-a", effectiveMaximum = 10 } }
local quarantine = C.decode(validState(), { loadedPerks = mismatch }); expect(quarantine.ok and quarantine.state.perks.Axe == nil and quarantine.state.orphanedPerks.Axe ~= nil, "changed active quarantines")
local changed = C.decode(validState(), { loadedPerks = mismatch, perkMigrator = function(id, record, spec) record.adapterVersion = spec.adapterVersion; return record end }); expect(changed.ok and changed.state.perks.Axe.adapterVersion == 2, "changed active migration")
local failedActiveRaw = validState(); local failedActive = C.decode(failedActiveRaw, { loadedPerks = mismatch, perkMigrator = function() error("test migration error") end }); expect(not failedActive.ok and failedActive.code == "perk_migration_failed" and failedActiveRaw.perks.Axe.adapterVersion == 1 and failedActiveRaw.orphanedPerks.Axe == nil, "failed active migration preserves input")
local invalidActiveRaw = validState(); local invalidActive = C.decode(invalidActiveRaw, { loadedPerks = mismatch, perkMigrator = function() return {} end }); expect(not invalidActive.ok and invalidActive.code == "perk_migration_failed" and invalidActiveRaw.perks.Axe.adapterId == "adapter" and invalidActiveRaw.orphanedPerks.Axe == nil, "invalid active migration preserves input")
local missing = C.decode(validState(), { loadedPerks = {} }); expect(missing.ok and missing.state.perks.Axe == nil and missing.state.orphanedPerks.Axe ~= nil, "missing active becomes orphan")
local missingOrphan = C.decode(orphanedState(), { loadedPerks = {} }); expect(missingOrphan.ok and missingOrphan.state.perks.Axe == nil and missingOrphan.state.orphanedPerks.Axe ~= nil, "missing orphan remains quarantined")
local automatic = C.decode(orphanedState(), { loadedPerks = loaded }); expect(automatic.ok and automatic.state.perks.Axe ~= nil and automatic.state.orphanedPerks.Axe == nil, "unchanged orphan auto restore")
local changedOrphan = C.decode(orphanedState(), { loadedPerks = mismatch, perkMigrator = function(id, record, spec) record.adapterVersion = spec.adapterVersion; return record end }); expect(changedOrphan.ok and changedOrphan.state.perks.Axe.adapterVersion == 2 and changedOrphan.state.orphanedPerks.Axe == nil, "changed orphan migration")
local failedOrphanRaw = orphanedState(); local failedOrphan = C.decode(failedOrphanRaw, { loadedPerks = mismatch, perkMigrator = function() error("test migration error") end }); expect(not failedOrphan.ok and failedOrphan.code == "perk_migration_failed" and failedOrphanRaw.orphanedPerks.Axe.adapterVersion == 1 and failedOrphanRaw.perks.Axe == nil, "failed migration preserves input")
local invalidOrphanRaw = orphanedState(); local invalidOrphan = C.decode(invalidOrphanRaw, { loadedPerks = mismatch, perkMigrator = function() return {} end }); expect(not invalidOrphan.ok and invalidOrphan.code == "perk_migration_failed" and invalidOrphanRaw.orphanedPerks.Axe.adapterId == "adapter", "invalid migration preserves input")

local ap = validState(); ap.survivor.spent = 3; bad(ap, "invalid_survivor")
local duplicateTarget = validState(); duplicateTarget.perks.Axe.activeTargets[2] = { targetId = "target-1", targetLevel = 7, targetPosition = 6.5 }; bad(duplicateTarget, "invalid_perk")
local levelOrder = validState(); levelOrder.perks.Axe.activeTargets[2] = { targetId = "target-2", targetLevel = 6, targetPosition = 6.5 }; bad(levelOrder, "invalid_perk")
local positionOrder = validState(); positionOrder.perks.Axe.activeTargets[2] = { targetId = "target-2", targetLevel = 7, targetPosition = 5.5 }; bad(positionOrder, "invalid_perk")
local aboveMaximum = validState(); aboveMaximum.perks.Axe.activeTargets[1].targetLevel = 11; bad(aboveMaximum, "invalid_target")
local high = validState(); high.perks.Axe.highWaterPosition = 4; bad(high, "invalid_perk")
local orderedA = validState(); orderedA.perks.B = validPerk("b"); local orderedB = validState(); orderedB.perks = {}; orderedB.perks.B = validPerk("b"); orderedB.perks.Axe = validPerk("a"); expect(C.encode(orderedA).canonical == C.encode(orderedB).canonical, "canonical map order")
local negativeZero = validState(); negativeZero.perks.Axe.postMaxFullRateUsed = -0.0; local positiveZero = validState(); positiveZero.perks.Axe.postMaxFullRateUsed = 0; expect(C.encode(negativeZero).canonical == C.encode(positiveZero).canonical, "canonical zero")
local ordinaryReserved = withReservation(6, 10, 2); expect(C.decode(ordinaryReserved).ok, "ordinary reservation accepts preSpent plus one")
local ordinaryWrongSpent = withReservation(6, 10, 3); bad(ordinaryWrongSpent, "invalid_in_flight_advancement")
local masteryReserved = withReservation(10, 10, 3); expect(C.decode(masteryReserved).ok, "mastery reservation accepts preSpent plus two")
local masteryWrongSpent = withReservation(10, 10, 2); bad(masteryWrongSpent, "invalid_in_flight_advancement")
local noCostField = withReservation(10, 10, 1); noCostField.inFlightAdvancement.apCost = 2; bad(noCostField, "invalid_in_flight_advancement")
expect(C.SCHEMA_VERSION == 1, "mastery keeps schema v1")

return assertions
