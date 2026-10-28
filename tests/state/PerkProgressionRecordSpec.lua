local R = PerkProgressionRecord
local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed") end
end

local function equal(actual, expected, message)
    expect(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local function identity()
    return { adapterId = "sla.vanilla", adapterVersion = 1, curveFingerprint = "curve-a", effectiveMaximum = 10 }
end

local function record()
    return {
        adapterId = "sla.vanilla", adapterVersion = 1, curveFingerprint = "curve-a", effectiveMaximum = 10,
        naturalPosition = 4, highWaterPosition = 5, postMaxFullRateUsed = 2,
        activeTargets = { { targetId = "target-a", targetLevel = 6, targetPosition = 6 } },
    }
end

local function quarantined(result, detail, message)
    equal(result.ok, false, message .. " fails")
    equal(result.code, "perk_quarantined", message .. " code")
    equal(result.detail, detail, message .. " detail")
end

-- Identity comparison.
do
    expect(R.sameIdentity(record(), identity()), "identical identity matches")
    for field, value in pairs({ adapterId = "sla.other", adapterVersion = 2, curveFingerprint = "curve-b", effectiveMaximum = 9 }) do
        local changed = record()
        changed[field] = value
        expect(not R.sameIdentity(changed, identity()), "record " .. field .. " mismatch")
        local described = identity()
        described[field] = value
        expect(not R.sameIdentity(record(), described), "identity " .. field .. " mismatch")
    end
    expect(not R.sameIdentity(nil, identity()), "nil record never matches")
    expect(not R.sameIdentity("sla.vanilla", identity()), "string record never matches")
    expect(not R.sameIdentity(1, identity()), "number record never matches")
end

-- Replacement-orphan inspection.
do
    local absentContainer = R.replacementOrphan({}, "Axe", identity())
    equal(absentContainer.ok, true, "missing orphan container succeeds")
    equal(absentContainer.present, false, "missing orphan container reports absent")
    local absent = R.replacementOrphan({ orphanedPerks = { Fitness = record() } }, "Axe", identity())
    equal(absent.ok, true, "absent orphan succeeds")
    equal(absent.present, false, "absent orphan reports absent")

    local replaced = record()
    replaced.curveFingerprint = "curve-old"
    local present = R.replacementOrphan({ orphanedPerks = { Axe = replaced } }, "Axe", identity())
    equal(present.ok, true, "incompatible orphan succeeds")
    equal(present.present, true, "incompatible orphan reports present")

    quarantined(R.replacementOrphan({ orphanedPerks = "invalid" }, "Axe", identity()), "orphaned_perks_invalid", "non-table container")
    quarantined(R.replacementOrphan({ orphanedPerks = { Axe = record() } }, "Axe", identity()), "same_identity_orphan", "same-identity orphan")
    quarantined(R.replacementOrphan({ orphanedPerks = { Axe = "invalid" } }, "Axe", identity()), "orphan_invalid", "non-table orphan")
    local malformed = {
        { "adapterId", "bad id" }, { "adapterId", 7 },
        { "adapterVersion", -1 }, { "adapterVersion", 1.5 }, { "adapterVersion", 0 / 0 }, { "adapterVersion", math.huge }, { "adapterVersion", "1" },
        { "curveFingerprint", "" }, { "curveFingerprint", false },
        { "effectiveMaximum", 0 }, { "effectiveMaximum", -3 }, { "effectiveMaximum", 2.5 }, { "effectiveMaximum", -math.huge }, { "effectiveMaximum", nil },
    }
    for index = 1, #malformed do
        local orphan = record()
        orphan[malformed[index][1]] = malformed[index][2]
        quarantined(R.replacementOrphan({ orphanedPerks = { Axe = orphan } }, "Axe", identity()), "orphan_invalid", "malformed orphan " .. index)
    end
    local zeroVersion = record()
    zeroVersion.adapterVersion = 0
    equal(R.replacementOrphan({ orphanedPerks = { Axe = zeroVersion } }, "Axe", identity()).present, true, "zero adapter version is a valid orphan")
end

-- Ledger projection.
do
    local source = record()
    local projected = R.ledger(source)
    equal(projected.naturalPosition, 4, "ledger natural")
    equal(projected.highWaterPosition, 5, "ledger high water")
    equal(projected.activeTargets, source.activeTargets, "ledger shares target chain")
    local keys = 0
    for _ in pairs(projected) do keys = keys + 1 end
    equal(keys, 3, "ledger has only ledger fields")
end

-- Detached ledger application.
do
    local source = record()
    source.futureField = { nested = { value = 3 } }
    local ledger = { naturalPosition = 6, highWaterPosition = 6, activeTargets = {} }
    local applied, reason = R.applyLedger(source, ledger)
    equal(reason, nil, "apply succeeds")
    expect(applied ~= source, "apply returns a new table")
    equal(applied.naturalPosition, 6, "apply natural")
    equal(applied.highWaterPosition, 6, "apply high water")
    equal(applied.activeTargets, ledger.activeTargets, "apply adopts ledger target chain")
    equal(applied.observedPosition, nil, "apply without position leaves observation absent")
    equal(applied.postMaxFullRateUsed, 2, "apply keeps post-max usage")
    equal(applied.adapterId, "sla.vanilla", "apply keeps identity")
    equal(applied.futureField.nested.value, 3, "apply preserves unknown fields")
    expect(applied.futureField ~= source.futureField, "unknown fields are detached")
    applied.futureField.nested.value = 9
    applied.adapterId = "changed"
    equal(source.futureField.nested.value, 3, "copy mutation leaves input unknown field")
    equal(source.adapterId, "sla.vanilla", "copy mutation leaves input identity")
    equal(source.naturalPosition, 4, "apply leaves input natural")

    local observed = R.applyLedger(source, ledger, 12)
    equal(observed.observedPosition, 12, "apply sets observed position")
    equal(source.observedPosition, nil, "apply leaves input observation")

    local positioned = record()
    positioned.observedPosition = 8
    local kept = R.applyLedger(positioned, ledger)
    equal(kept.observedPosition, 8, "apply without position keeps existing observation")

    local copy = R.applyLedger(source, nil, 7)
    equal(copy.naturalPosition, 4, "nil ledger keeps natural")
    equal(copy.highWaterPosition, 5, "nil ledger keeps high water")
    equal(copy.observedPosition, 7, "nil ledger sets observed position")
    expect(copy.activeTargets ~= source.activeTargets, "nil ledger detaches target chain")
    copy.activeTargets[1].targetPosition = 99
    copy.activeTargets[2] = { targetId = "target-b", targetLevel = 7, targetPosition = 100 }
    equal(source.activeTargets[1].targetPosition, 6, "nested target mutation leaves input")
    equal(#source.activeTargets, 1, "target append leaves input")
end

-- Clone rejection reasons.
do
    local cases = {
        { "non_finite_number", function(value) value.naturalPosition = 0 / 0 end },
        { "non_finite_number", function(value) value.futureField = math.huge end },
        { "non_finite_number", function(value) value.activeTargets[1].targetPosition = -math.huge end },
        { "unsupported_type", function(value) value.futureField = function() end end },
        { "cycle", function(value) value.futureField = value end },
        { "cycle", function(value) value.activeTargets[1].parent = value.activeTargets end },
    }
    local ledger = { naturalPosition = 6, highWaterPosition = 6, activeTargets = {} }
    for index = 1, #cases do
        local source = record()
        cases[index][2](source)
        local applied, reason = R.applyLedger(source, ledger, 1)
        equal(applied, nil, "rejected copy " .. index)
        equal(reason, cases[index][1], "rejection reason " .. index)
        local copied, copyReason = R.applyLedger(source, nil, 1)
        equal(copied, nil, "rejected nil-ledger copy " .. index)
        equal(copyReason, cases[index][1], "nil-ledger rejection reason " .. index)
    end
    local shared = { value = 1 }
    local source = record()
    source.left, source.right = shared, shared
    local copied = R.applyLedger(source, nil, 1)
    expect(copied ~= nil, "shared acyclic subtable is accepted")
    equal(copied.left.value, 1, "shared subtable copied")
end

-- Baseline construction.
do
    local ledger = { naturalPosition = 15, highWaterPosition = 15, activeTargets = {} }
    local built = R.fromBaseline(identity(), ledger)
    equal(built.adapterId, "sla.vanilla", "baseline adapter")
    equal(built.adapterVersion, 1, "baseline version")
    equal(built.curveFingerprint, "curve-a", "baseline curve")
    equal(built.effectiveMaximum, 10, "baseline maximum")
    equal(built.naturalPosition, 15, "baseline natural")
    equal(built.highWaterPosition, 15, "baseline high water")
    equal(built.activeTargets, ledger.activeTargets, "baseline target chain")
    equal(built.postMaxFullRateUsed, 0, "baseline post-max usage")
    equal(built.observedPosition, nil, "baseline has no observation")
    local keys = 0
    for _ in pairs(built) do keys = keys + 1 end
    equal(keys, 8, "baseline has exact persisted fields")
    expect(R.sameIdentity(built, identity()), "baseline matches its identity")
end

-- Durable observed boundary.
do
    local observed = record()
    observed.observedPosition = 3
    equal(R.durableBoundary(observed), 3, "observed position wins")
    local zero = record()
    zero.observedPosition = 0
    equal(R.durableBoundary(zero), 0, "zero observed position wins")
    equal(R.durableBoundary(record()), 6, "last active target without observation")
    local chained = record()
    chained.activeTargets[2] = { targetId = "target-b", targetLevel = 7, targetPosition = 9 }
    equal(R.durableBoundary(chained), 9, "last of several active targets")
    local empty = record()
    empty.activeTargets = {}
    equal(R.durableBoundary(empty), 4, "natural position without targets")
    local missing = record()
    missing.activeTargets = nil
    equal(R.durableBoundary(missing), 4, "natural position without target table")
end

return assertions
