local PerkProgressionRecord = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isNonnegativeInteger(value)
    return isFinite(value) and value >= 0 and value == math.floor(value)
end

local function isPositiveInteger(value)
    return isFinite(value) and value > 0 and value == math.floor(value)
end

local function isSafeId(value)
    return type(value) == "string" and value:match("^[%w%._:%-]+$") ~= nil
end

local function cloneValue(value, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "string" or valueType == "number" then
        if valueType == "number" and not isFinite(value) then
            return nil, "non_finite_number"
        end
        return value
    end
    if valueType ~= "table" then return nil, "unsupported_type" end
    seen = seen or {}
    if seen[value] then return nil, "cycle" end
    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local copiedKey, keyError = cloneValue(key, seen)
        if keyError then seen[value] = nil; return nil, keyError end
        local copiedChild, childError = cloneValue(child, seen)
        if childError then seen[value] = nil; return nil, childError end
        copy[copiedKey] = copiedChild
    end
    seen[value] = nil
    return copy
end

function PerkProgressionRecord.sameIdentity(record, identity)
    return type(record) == "table"
        and record.adapterId == identity.adapterId
        and record.adapterVersion == identity.adapterVersion
        and record.curveFingerprint == identity.curveFingerprint
        and record.effectiveMaximum == identity.effectiveMaximum
end

function PerkProgressionRecord.replacementOrphan(state, perkId, identity)
    local orphaned = state.orphanedPerks
    if orphaned == nil then return { ok = true, present = false } end
    if type(orphaned) ~= "table" then
        return failure("perk_quarantined", "orphaned_perks_invalid")
    end
    local record = orphaned[perkId]
    if record == nil then return { ok = true, present = false } end
    if type(record) ~= "table"
        or not isSafeId(record.adapterId)
        or not isNonnegativeInteger(record.adapterVersion)
        or not isSafeId(record.curveFingerprint)
        or not isPositiveInteger(record.effectiveMaximum) then
        return failure("perk_quarantined", "orphan_invalid")
    end
    if PerkProgressionRecord.sameIdentity(record, identity) then
        return failure("perk_quarantined", "same_identity_orphan")
    end
    return { ok = true, present = true }
end

function PerkProgressionRecord.ledger(record)
    return {
        naturalPosition = record.naturalPosition,
        highWaterPosition = record.highWaterPosition,
        activeTargets = record.activeTargets,
    }
end

function PerkProgressionRecord.durableBoundary(record)
    if record.observedPosition ~= nil then return record.observedPosition end
    local boundary = record.naturalPosition
    if type(record.activeTargets) == "table" and #record.activeTargets > 0 then
        boundary = record.activeTargets[#record.activeTargets].targetPosition
    end
    return boundary
end

function PerkProgressionRecord.applyLedger(record, ledger, observedPosition)
    local copy, copyError = cloneValue(record)
    if not copy then return nil, copyError end
    if ledger ~= nil then
        copy.naturalPosition = ledger.naturalPosition
        copy.highWaterPosition = ledger.highWaterPosition
        copy.activeTargets = ledger.activeTargets
    end
    if observedPosition ~= nil then copy.observedPosition = observedPosition end
    return copy
end

function PerkProgressionRecord.fromBaseline(identity, ledger)
    return {
        adapterId = identity.adapterId,
        adapterVersion = identity.adapterVersion,
        curveFingerprint = identity.curveFingerprint,
        effectiveMaximum = identity.effectiveMaximum,
        naturalPosition = ledger.naturalPosition,
        highWaterPosition = ledger.highWaterPosition,
        activeTargets = ledger.activeTargets,
        postMaxFullRateUsed = 0,
    }
end

return PerkProgressionRecord
