local C = StateCodec
local assertions = 0
local function expect(condition, message) assertions = assertions + 1; if not condition then error(message or "assertion failed") end end
expect(C.canonical == nil, "canonical is not public")
local function validPerk(seed)
    return { adapterId = "adapter", adapterVersion = 1, capabilityEpoch = 2, curveFingerprint = "curve-" .. seed,
        effectiveMaximum = 10, naturalPosition = 4.5, highWaterPosition = 5, fractionalCarry = 0.25,
        activeTargets = { { targetId = "target-1", targetLevel = 6, targetPosition = 5.5 } }, postMaxFullRateUsed = 0, postMaxEpoch = 0 }
end
local function validState()
    return { schemaVersion = 1, writerVersion = 1, revision = 4, survivor = { level = 2, xpIntoLevel = 3.5, earned = 2, spent = 1 }, perks = { Axe = validPerk("a") }, orphanedPerks = {} }
end
local function bad(value, code)
    local result = C.decode(value)
    expect(not result.ok and result.code == code, "expected " .. code .. ", got " .. tostring(result.code))
end

local fresh = C.decode(nil); expect(fresh.ok and fresh.state.revision == 0 and fresh.state.survivor.level == 0, "fresh")
local input = validState(); local decoded = C.decode(input); expect(decoded.ok, "decode valid"); decoded.state.perks.Axe.adapterId = "changed"; expect(input.perks.Axe.adapterId == "adapter", "decode deep copy")
local encoded = C.encode(validState()); expect(encoded.ok, "encode valid"); encoded.state.survivor.level = 99; expect(validState().survivor.level == 2, "encode deep copy")
bad(12, "invalid_state"); bad({}, "unversioned_state"); local nonempty = { foo = true }; bad(nonempty, "unversioned_state")
local cyclic = validState(); cyclic.loop = cyclic; bad(cyclic, "invalid_raw")
local nan = validState(); nan.survivor.xpIntoLevel = 0 / 0; bad(nan, "invalid_raw")
local inf = validState(); inf.survivor.xpIntoLevel = math.huge; bad(inf, "invalid_raw")
local unknown = validState(); unknown.extra = true; bad(unknown, "invalid_state")
local newer = validState(); newer.schemaVersion = 2; local r = C.decode(newer); expect(not r.ok and r.code == "newer_schema" and newer.schemaVersion == 2, "newer schema preserves raw")
local writer = validState(); writer.writerVersion = 2; bad(writer, "newer_writer")
local legacy = validState(); legacy.schemaVersion = 0; legacy.old = true; local migrated = C.decode(legacy, { schemaMigrations = { [0] = function(raw) raw.schemaVersion = 1; raw.old = nil; return raw end } }); expect(migrated.ok, "consecutive migration")
bad(legacy, "missing_schema_migration"); local skip = C.decode(legacy, { schemaMigrations = { [0] = function(raw) raw.schemaVersion = 2; return raw end } }); expect(not skip.ok and skip.code == "schema_migration_not_consecutive", "skip migration")
local loaded = { Axe = { adapterId = "adapter", adapterVersion = 1, capabilityEpoch = 2, curveFingerprint = "curve-a", effectiveMaximum = 10 } }
expect(C.decode(validState(), { loadedPerks = loaded }).ok, "matching adapter")
local mismatch = { Axe = { adapterId = "adapter", adapterVersion = 2, capabilityEpoch = 2, curveFingerprint = "curve-a", effectiveMaximum = 10 } }
local quarantine = C.decode(validState(), { loadedPerks = mismatch }); expect(quarantine.ok and quarantine.state.perks.Axe == nil and quarantine.state.orphanedPerks.Axe ~= nil, "quarantine mismatch")
local changed = C.decode(validState(), { loadedPerks = mismatch, perkMigrator = function(id, record, spec) record.adapterVersion = spec.adapterVersion; return record end }); expect(changed.ok and changed.state.perks.Axe.adapterVersion == 2, "explicit perk migration")
local cyclicSpec = { adapterId = "adapter", adapterVersion = 2, capabilityEpoch = 2, curveFingerprint = "curve-a", effectiveMaximum = 10 }; cyclicSpec.self = cyclicSpec; local activeMigratorCalled = false; local activeCloneFailure = C.decode(validState(), { loadedPerks = { Axe = cyclicSpec }, perkMigrator = function() activeMigratorCalled = true; return validPerk("a") end }); expect(not activeCloneFailure.ok and activeCloneFailure.code == "perk_migration_failed" and not activeMigratorCalled, "active migration clone failure")
local missing = C.decode(validState(), { loadedPerks = {} }); expect(missing.ok and missing.state.orphanedPerks.Axe ~= nil, "missing moves orphan")
local restoreRaw = validState(); restoreRaw.orphanedPerks.Axe = restoreRaw.perks.Axe; restoreRaw.perks.Axe = nil; local restore = C.decode(restoreRaw, { loadedPerks = loaded, perkMigrator = function(id, record) return record end }); expect(restore.ok and restore.state.perks.Axe ~= nil and restore.state.orphanedPerks.Axe == nil, "explicit restore")
local restoreChangedRaw = validState(); restoreChangedRaw.orphanedPerks.Axe = restoreChangedRaw.perks.Axe; restoreChangedRaw.perks.Axe = nil; local restoreChanged = C.decode(restoreChangedRaw, { loadedPerks = mismatch, perkMigrator = function(id, record, spec) record.adapterVersion = spec.adapterVersion; return record end }); expect(restoreChanged.ok and restoreChanged.state.perks.Axe.adapterVersion == 2 and restoreChanged.state.orphanedPerks.Axe == nil, "changed identity restore")
local restoreCloneRaw = validState(); restoreCloneRaw.orphanedPerks.Axe = restoreCloneRaw.perks.Axe; restoreCloneRaw.perks.Axe = nil; local orphanMigratorCalled = false; local orphanCloneFailure = C.decode(restoreCloneRaw, { loadedPerks = { Axe = cyclicSpec }, perkMigrator = function() orphanMigratorCalled = true; return validPerk("a") end }); expect(not orphanCloneFailure.ok and orphanCloneFailure.code == "perk_migration_failed" and not orphanMigratorCalled, "orphan migration clone failure")
local restoreErrorRaw = validState(); restoreErrorRaw.orphanedPerks.Axe = restoreErrorRaw.perks.Axe; restoreErrorRaw.perks.Axe = nil; local restoreError = C.decode(restoreErrorRaw, { loadedPerks = loaded, perkMigrator = function() error("test migrator failure") end }); expect(not restoreError.ok and restoreError.code == "perk_migration_failed" and restoreErrorRaw.orphanedPerks.Axe.adapterId == "adapter" and restoreErrorRaw.perks.Axe == nil, "restore exception preserves input")
local restoreInvalidRaw = validState(); restoreInvalidRaw.orphanedPerks.Axe = restoreInvalidRaw.perks.Axe; restoreInvalidRaw.perks.Axe = nil; local restoreInvalid = C.decode(restoreInvalidRaw, { loadedPerks = loaded, perkMigrator = function() return {} end }); expect(not restoreInvalid.ok and restoreInvalid.code == "perk_migration_failed" and restoreInvalidRaw.orphanedPerks.Axe.adapterVersion == 1 and restoreInvalidRaw.perks.Axe == nil, "invalid restore preserves input")
local targetOrder = validState(); targetOrder.perks.Axe.activeTargets[1].targetPosition = 2; targetOrder.perks.Axe.activeTargets[2] = { targetId = "t2", targetLevel = 7, targetPosition = 2 }; bad(targetOrder, "invalid_perk")
local high = validState(); high.perks.Axe.highWaterPosition = 4; bad(high, "invalid_perk")
local ap = validState(); ap.survivor.spent = 3; bad(ap, "invalid_survivor")
local carry = validState(); carry.perks.Axe.fractionalCarry = 1; bad(carry, "invalid_perk")
local post = validState(); post.perks.Axe.postMaxEpoch = -1; bad(post, "invalid_perk")
local orderedA = validState(); orderedA.perks.B = validPerk("b"); local orderedB = validState(); orderedB.perks = {}; orderedB.perks.B = validPerk("b"); orderedB.perks.Axe = validPerk("a"); expect(C.encode(orderedA).canonical == C.encode(orderedB).canonical, "canonical map order")
local negativeZero = validState(); negativeZero.perks.Axe.fractionalCarry = -0.0; local positiveZero = validState(); positiveZero.perks.Axe.fractionalCarry = 0; expect(C.encode(negativeZero).canonical == C.encode(positiveZero).canonical, "canonical zero")
return assertions
