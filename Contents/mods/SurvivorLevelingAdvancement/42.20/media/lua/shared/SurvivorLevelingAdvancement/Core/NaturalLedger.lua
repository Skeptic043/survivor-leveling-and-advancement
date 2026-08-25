local NaturalLedger = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function isFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value)
    return isFinite(value) and value == math.floor(value)
end

local function arrayLength(value, malformedCode, detail)
    if type(value) ~= "table" then
        return nil, failure(malformedCode, detail)
    end

    local count = 0
    for key, _ in pairs(value) do
        if not isInteger(key) or key < 1 then
            return nil, failure(malformedCode, detail)
        end
        count = count + 1
    end
    for index = 1, count do
        if value[index] == nil then
            return nil, failure(malformedCode, detail)
        end
    end
    return count, nil
end

local function cloneTargets(targets, count)
    local copy = {}
    for index = 1, count do
        local target = targets[index]
        copy[index] = {
            targetId = target.targetId,
            targetLevel = target.targetLevel,
            targetPosition = target.targetPosition,
        }
    end
    return copy
end

local function validateState(state)
    if type(state) ~= "table" then
        return nil, failure("MALFORMED_STATE", "state must be a table")
    end
    if type(state.naturalPosition) ~= "number" or type(state.highWaterPosition) ~= "number" then
        return nil, failure("MALFORMED_STATE", "ledger positions must be numbers")
    end
    if not isFinite(state.naturalPosition) or not isFinite(state.highWaterPosition) then
        return nil, failure("NON_FINITE_NUMBER", "ledger positions must be finite")
    end
    if state.naturalPosition < 0 or state.highWaterPosition < 0 or state.naturalPosition > state.highWaterPosition then
        return nil, failure("MALFORMED_STATE", "ledger positions are inconsistent")
    end

    local targetCount, arrayError = arrayLength(state.activeTargets, "MALFORMED_STATE", "activeTargets must be a dense array")
    if arrayError then
        return nil, arrayError
    end

    local priorLevel = nil
    local priorPosition = nil
    local targetIds = {}
    for index = 1, targetCount do
        local target = state.activeTargets[index]
        if type(target) ~= "table" or type(target.targetId) ~= "string" or target.targetId == "" then
            return nil, failure("MALFORMED_STATE", "active target identity is malformed")
        end
        if type(target.targetLevel) ~= "number" or type(target.targetPosition) ~= "number" then
            return nil, failure("MALFORMED_STATE", "active target coordinates must be numbers")
        end
        if not isFinite(target.targetLevel) or not isFinite(target.targetPosition) then
            return nil, failure("NON_FINITE_NUMBER", "active target coordinates must be finite")
        end
        if not isInteger(target.targetLevel) or target.targetLevel <= 0 or target.targetPosition < 0 then
            return nil, failure("MALFORMED_STATE", "active target coordinates are malformed")
        end
        if targetIds[target.targetId] then
            return nil, failure("TARGET_CONFLICT", "active target IDs must be unique")
        end
        if priorLevel ~= nil and (target.targetLevel <= priorLevel or target.targetPosition <= priorPosition) then
            return nil, failure("TARGET_ORDER", "active targets must be strictly increasing")
        end
        if target.targetPosition <= state.highWaterPosition then
            return nil, failure("POSITION_BEHIND_HIGH_WATER", "active target must be ahead of high water")
        end
        targetIds[target.targetId] = true
        priorLevel = target.targetLevel
        priorPosition = target.targetPosition
    end

    return {
        naturalPosition = state.naturalPosition,
        highWaterPosition = state.highWaterPosition,
        activeTargets = cloneTargets(state.activeTargets, targetCount),
    }, nil
end

local function validateDelta(delta)
    if type(delta) ~= "number" then
        return failure("INVALID_DELTA", "delta must be a number")
    end
    if not isFinite(delta) then
        return failure("NON_FINITE_NUMBER", "delta must be finite")
    end
    return nil
end

local function validateActualPosition(actualPositionAfter)
    if type(actualPositionAfter) ~= "number" or actualPositionAfter < 0 then
        return failure("INCONSISTENT_POSITION", "actual position must be a nonnegative number")
    end
    if not isFinite(actualPositionAfter) then
        return failure("NON_FINITE_NUMBER", "actual position must be finite")
    end
    return nil
end

local function transition(state, delta, actualPositionAfter, survivorEligible)
    local ledger, stateError = validateState(state)
    if stateError then
        return stateError
    end
    local deltaError = validateDelta(delta)
    if deltaError then
        return deltaError
    end
    local positionError = validateActualPosition(actualPositionAfter)
    if positionError then
        return positionError
    end

    local beganWithTargets = #ledger.activeTargets > 0
    local nextNatural = ledger.naturalPosition + delta
    if nextNatural < 0 then
        nextNatural = 0
    end

    local nextHighWater = ledger.highWaterPosition
    local recoveryApplied = 0
    local earnedHighWater = 0
    if delta > 0 then
        local recoveryRemaining = ledger.highWaterPosition - ledger.naturalPosition
        recoveryApplied = math.min(delta, recoveryRemaining)
        earnedHighWater = delta - recoveryApplied
        nextHighWater = ledger.highWaterPosition + earnedHighWater
    end

    if earnedHighWater > 0 and actualPositionAfter < nextHighWater then
        return failure("POSITION_BEHIND_HIGH_WATER", "actual position is behind newly earned high water")
    end

    if beganWithTargets then
        if actualPositionAfter < nextNatural then
            return failure("INCONSISTENT_POSITION", "actual position is behind ledger movement")
        end
    elseif actualPositionAfter ~= nextNatural then
        return failure("INCONSISTENT_POSITION", "delta does not match actual position")
    end

    local remainingTargets = {}
    local clearedTargetIds = {}
    for index = 1, #ledger.activeTargets do
        local target = ledger.activeTargets[index]
        if delta > 0 and target.targetPosition <= nextHighWater then
            clearedTargetIds[#clearedTargetIds + 1] = target.targetId
        else
            remainingTargets[#remainingTargets + 1] = {
                targetId = target.targetId,
                targetLevel = target.targetLevel,
                targetPosition = target.targetPosition,
            }
        end
    end

    local eligibleApplied = 0
    local eligibleRatio = 0
    if survivorEligible and delta > 0 then
        eligibleApplied = earnedHighWater
        eligibleRatio = eligibleApplied / delta
    end

    if beganWithTargets and #remainingTargets == 0 and #clearedTargetIds > 0 then
        nextNatural = actualPositionAfter
        nextHighWater = actualPositionAfter
    end

    return {
        ok = true,
        state = {
            naturalPosition = nextNatural,
            highWaterPosition = nextHighWater,
            activeTargets = remainingTargets,
        },
        effect = {
            recoveryApplied = recoveryApplied,
            eligibleApplied = eligibleApplied,
            eligibleRatio = eligibleRatio,
            clearedTargetIds = clearedTargetIds,
        },
    }
end

function NaturalLedger.baseline(actualPosition)
    local positionError = validateActualPosition(actualPosition)
    if positionError then
        return positionError
    end
    return {
        ok = true,
        state = {
            naturalPosition = actualPosition,
            highWaterPosition = actualPosition,
            activeTargets = {},
        },
    }
end

function NaturalLedger.inspect(state)
    local ledger, stateError = validateState(state)
    if stateError then
        return stateError
    end
    local recoveryRemaining = ledger.highWaterPosition - ledger.naturalPosition
    return {
        ok = true,
        red = recoveryRemaining > 0,
        recoveryRemaining = recoveryRemaining,
        activeCount = #ledger.activeTargets,
    }
end

function NaturalLedger.applySupported(state, appliedDelta, actualPositionAfter)
    return transition(state, appliedDelta, actualPositionAfter, true)
end

function NaturalLedger.reconcileExternal(state, actualDelta, actualPositionAfter)
    return transition(state, actualDelta, actualPositionAfter, false)
end

function NaturalLedger.appendTarget(state, target, effectiveMaximum)
    local ledger, stateError = validateState(state)
    if stateError then
        return stateError
    end
    if type(target) ~= "table" or type(target.targetId) ~= "string" or target.targetId == "" then
        return failure("MALFORMED_TARGET", "target identity is malformed")
    end
    if type(target.targetLevel) ~= "number" or type(target.targetPosition) ~= "number" then
        return failure("MALFORMED_TARGET", "target coordinates must be numbers")
    end
    if not isFinite(target.targetLevel) or not isFinite(target.targetPosition) then
        return failure("NON_FINITE_NUMBER", "target coordinates must be finite")
    end
    if not isInteger(target.targetLevel) or target.targetLevel <= 0 or target.targetPosition < 0 then
        return failure("MALFORMED_TARGET", "target coordinates are malformed")
    end
    if type(effectiveMaximum) ~= "number" or not isInteger(effectiveMaximum) or effectiveMaximum <= 0 then
        if type(effectiveMaximum) == "number" and not isFinite(effectiveMaximum) then
            return failure("NON_FINITE_NUMBER", "effective maximum must be finite")
        end
        return failure("MALFORMED_TARGET", "effective maximum must be a positive integer")
    end
    local exactMatch = false
    for index = 1, #ledger.activeTargets do
        local existing = ledger.activeTargets[index]
        if existing.targetId == target.targetId and
            (existing.targetLevel ~= target.targetLevel or existing.targetPosition ~= target.targetPosition) then
            return failure("TARGET_CONFLICT", "target ID conflicts with an active target")
        end
        if existing.targetLevel == target.targetLevel and existing.targetPosition ~= target.targetPosition then
            return failure("TARGET_CONFLICT", "target level conflicts with an active target")
        end
        if existing.targetPosition == target.targetPosition and existing.targetLevel ~= target.targetLevel then
            return failure("TARGET_CONFLICT", "target position conflicts with an active target")
        end
        if existing.targetLevel == target.targetLevel and existing.targetPosition == target.targetPosition then
            exactMatch = true
        end
    end

    if exactMatch then
        return { ok = true, state = ledger, added = false }
    end
    if target.targetLevel > effectiveMaximum then
        return failure("TARGET_ABOVE_MAXIMUM", "target level exceeds effective maximum")
    end
    if target.targetPosition <= ledger.highWaterPosition then
        return failure("POSITION_BEHIND_HIGH_WATER", "target position must be ahead of high water")
    end

    local lastTarget = ledger.activeTargets[#ledger.activeTargets]
    if lastTarget and
        (target.targetLevel <= lastTarget.targetLevel or target.targetPosition <= lastTarget.targetPosition) then
        return failure("TARGET_ORDER", "new target must extend the active target order")
    end

    ledger.activeTargets[#ledger.activeTargets + 1] = {
        targetId = target.targetId,
        targetLevel = target.targetLevel,
        targetPosition = target.targetPosition,
    }
    return { ok = true, state = ledger, added = true }
end

return NaturalLedger
