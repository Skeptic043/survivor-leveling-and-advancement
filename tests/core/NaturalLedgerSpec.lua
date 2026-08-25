local assertions = 0

local function check(condition, message)
    assertions = assertions + 1
    if not condition then
        error(message)
    end
end

local function equal(actual, expected, message)
    check(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local function failed(result, code, message)
    equal(result.ok, false, message .. " should fail")
    equal(result.code, code, message .. " code")
    check(type(result.detail) == "string" and result.detail ~= "", message .. " detail")
end

local function target(id, level, position)
    return { targetId = id, targetLevel = level, targetPosition = position }
end

local function ledger(natural, highWater, targets)
    return {
        naturalPosition = natural,
        highWaterPosition = highWater,
        activeTargets = targets or {},
    }
end

local function sameLedger(actual, expected, message)
    equal(actual.naturalPosition, expected.naturalPosition, message .. " natural")
    equal(actual.highWaterPosition, expected.highWaterPosition, message .. " high water")
    equal(#actual.activeTargets, #expected.activeTargets, message .. " target count")
    for index = 1, #expected.activeTargets do
        equal(actual.activeTargets[index].targetId, expected.activeTargets[index].targetId, message .. " target ID " .. index)
        equal(actual.activeTargets[index].targetLevel, expected.activeTargets[index].targetLevel, message .. " target level " .. index)
        equal(actual.activeTargets[index].targetPosition, expected.activeTargets[index].targetPosition, message .. " target position " .. index)
    end
end

local baseline = NaturalLedger.baseline(100)
equal(baseline.ok, true, "baseline succeeds")
sameLedger(baseline.state, ledger(100, 100), "baseline")
local inspection = NaturalLedger.inspect(baseline.state)
equal(inspection.ok, true, "inspection succeeds")
equal(inspection.red, false, "baseline is not red")
equal(inspection.recoveryRemaining, 0, "baseline has no recovery")
equal(inspection.activeCount, 0, "baseline has no targets")

local zeroInput = ledger(90, 100, { target("one", 2, 120) })
local zeroTarget = zeroInput.activeTargets[1]
local zero = NaturalLedger.applySupported(zeroInput, 0, 120)
equal(zero.ok, true, "zero delta succeeds")
sameLedger(zero.state, zeroInput, "zero delta")
equal(zero.effect.recoveryApplied, 0, "zero recovery")
equal(zero.effect.eligibleApplied, 0, "zero eligibility")
equal(zero.effect.eligibleRatio, 0, "zero ratio")
equal(#zero.effect.clearedTargetIds, 0, "zero clears nothing")
equal(zeroInput.activeTargets[1], zeroTarget, "zero does not replace caller target")
check(zero.state ~= zeroInput, "zero returns a new state")
check(zero.state.activeTargets ~= zeroInput.activeTargets, "zero returns a new target array")
check(zero.state.activeTargets[1] ~= zeroInput.activeTargets[1], "zero returns a new target record")

failed(NaturalLedger.baseline("100"), "INCONSISTENT_POSITION", "string baseline")
failed(NaturalLedger.baseline(math.huge), "NON_FINITE_NUMBER", "infinite baseline")
failed(NaturalLedger.inspect(nil), "MALFORMED_STATE", "missing state")
failed(NaturalLedger.inspect(ledger(101, 100)), "MALFORMED_STATE", "natural beyond high water")
failed(NaturalLedger.inspect({ naturalPosition = 1, highWaterPosition = 1, activeTargets = "none" }), "MALFORMED_STATE", "non-table targets")
failed(NaturalLedger.inspect(ledger(1, math.huge)), "NON_FINITE_NUMBER", "non-finite state")
failed(NaturalLedger.inspect(ledger(0, 0, { target("zero-level", 0, 10) })), "MALFORMED_STATE", "zero active target level")
failed(NaturalLedger.inspect(ledger(0, 0, { target("b", 2, 20), target("a", 1, 30) })), "TARGET_ORDER", "unordered levels")
failed(NaturalLedger.inspect(ledger(0, 0, { target("same", 1, 10), target("same", 2, 20) })), "TARGET_CONFLICT", "duplicate active ID")
failed(NaturalLedger.applySupported(baseline.state, "1", 101), "INVALID_DELTA", "string delta")
failed(NaturalLedger.applySupported(baseline.state, 0 / 0, 100), "NON_FINITE_NUMBER", "NaN delta")
failed(NaturalLedger.applySupported(baseline.state, 1, math.huge), "NON_FINITE_NUMBER", "infinite actual position")

local loss = NaturalLedger.applySupported(baseline.state, -150, 0)
equal(loss.ok, true, "loss succeeds")
sameLedger(loss.state, ledger(0, 100), "loss clamps at zero")
equal(loss.effect.recoveryApplied, 0, "loss does not recover")
equal(loss.effect.eligibleApplied, 0, "loss is not eligible")
equal(loss.effect.eligibleRatio, 0, "loss ratio is zero")
local redInspection = NaturalLedger.inspect(loss.state)
equal(redInspection.red, true, "loss creates red")
equal(redInspection.recoveryRemaining, 100, "loss creates exact recovery")

local partial = NaturalLedger.applySupported(loss.state, 40, 40)
equal(partial.ok, true, "partial recovery succeeds")
sameLedger(partial.state, ledger(40, 100), "partial recovery")
equal(partial.effect.recoveryApplied, 40, "partial recovery amount")
equal(partial.effect.eligibleApplied, 0, "partial recovery is ineligible")
equal(partial.effect.eligibleRatio, 0, "partial recovery ratio")
local complete = NaturalLedger.applySupported(partial.state, 60, 100)
equal(complete.ok, true, "complete recovery succeeds")
sameLedger(complete.state, ledger(100, 100), "complete recovery")
equal(complete.effect.recoveryApplied, 60, "complete recovery amount")
equal(complete.effect.eligibleApplied, 0, "complete recovery is ineligible")

local split = NaturalLedger.applySupported(ledger(70, 100), 50, 120)
equal(split.ok, true, "split recovery award succeeds")
sameLedger(split.state, ledger(120, 120), "split recovery award")
equal(split.effect.recoveryApplied, 30, "split recovery portion")
equal(split.effect.eligibleApplied, 20, "split eligible portion")
equal(split.effect.eligibleRatio, 0.4, "split eligible ratio")

local orderedState = ledger(100, 100, {
    target("first", 2, 110),
    target("second", 3, 120),
    target("final", 4, 200),
})
local crossings = NaturalLedger.applySupported(orderedState, 25, 225)
equal(crossings.ok, true, "ordered crossings succeed")
sameLedger(crossings.state, ledger(125, 125, { target("final", 4, 200) }), "ordered crossings")
equal(#crossings.effect.clearedTargetIds, 2, "two targets clear")
equal(crossings.effect.clearedTargetIds[1], "first", "first clear stays ordered")
equal(crossings.effect.clearedTargetIds[2], "second", "second clear stays ordered")
equal(crossings.effect.eligibleApplied, 25, "crossing award remains eligible")
equal(#orderedState.activeTargets, 3, "crossing does not mutate caller targets")

local finalClear = NaturalLedger.applySupported(ledger(100, 100, { target("last", 2, 110) }), 15, 130)
equal(finalClear.ok, true, "final clearing succeeds")
sameLedger(finalClear.state, ledger(130, 130), "final target synchronization")
equal(finalClear.effect.eligibleApplied, 15, "synchronization leap is not eligible")
equal(finalClear.effect.eligibleRatio, 1, "final award ratio excludes synchronization")
equal(finalClear.effect.clearedTargetIds[1], "last", "final target ID is reported")

local appendInput = ledger(100, 100, { target("original", 2, 150) })
local reboostRequest = target("different-request", 2, 150)
local reboost = NaturalLedger.appendTarget(appendInput, reboostRequest, 10)
equal(reboost.ok, true, "exact reboost succeeds")
equal(reboost.added, false, "exact reboost is not added")
sameLedger(reboost.state, appendInput, "exact reboost")
equal(reboost.state.activeTargets[1].targetId, "original", "exact reboost preserves stored ID")
check(reboost.state ~= appendInput, "reboost returns a new state")
check(reboost.state.activeTargets ~= appendInput.activeTargets, "reboost returns a new target array")
check(reboost.state.activeTargets[1] ~= appendInput.activeTargets[1], "reboost returns a new target record")
equal(reboostRequest.targetId, "different-request", "reboost does not mutate request")
local reboostAboveNewMaximum = NaturalLedger.appendTarget(appendInput, reboostRequest, 1)
equal(reboostAboveNewMaximum.ok, true, "exact reboost is recognized above a lowered maximum")
equal(reboostAboveNewMaximum.added, false, "exact reboost above lowered maximum is not new")

local appended = NaturalLedger.appendTarget(appendInput, target("next", 3, 200), 10)
equal(appended.ok, true, "ordered append succeeds")
equal(appended.added, true, "ordered append reports addition")
equal(#appended.state.activeTargets, 2, "ordered append stores target")
equal(#appendInput.activeTargets, 1, "ordered append leaves caller unchanged")
failed(NaturalLedger.appendTarget(appendInput, target("original", 3, 200), 10), "TARGET_CONFLICT", "duplicate ID conflict")
failed(NaturalLedger.appendTarget(appendInput, target("other", 2, 175), 10), "TARGET_CONFLICT", "duplicate level conflict")
failed(NaturalLedger.appendTarget(appendInput, target("backward", 3, 140), 10), "TARGET_ORDER", "non-increasing position")
failed(NaturalLedger.appendTarget(appendInput, target("too-high", 11, 250), 10), "TARGET_ABOVE_MAXIMUM", "above maximum")
failed(NaturalLedger.appendTarget(appendInput, target("behind", 3, 90), 10), "POSITION_BEHIND_HIGH_WATER", "target behind high water")
failed(NaturalLedger.appendTarget(appendInput, target("zero-level", 0, 200), 10), "MALFORMED_TARGET", "zero appended target level")
failed(NaturalLedger.appendTarget(appendInput, target("valid-level", 3, 200), 0), "MALFORMED_TARGET", "zero effective maximum")
failed(NaturalLedger.appendTarget(appendInput, { targetId = "bad", targetLevel = 3 }, 10), "MALFORMED_TARGET", "malformed target")
failed(NaturalLedger.appendTarget(appendInput, target("infinite", 3, math.huge), 10), "NON_FINITE_NUMBER", "non-finite target")

local externalLoss = NaturalLedger.reconcileExternal(baseline.state, -40, 60)
equal(externalLoss.ok, true, "external loss succeeds")
sameLedger(externalLoss.state, ledger(60, 100), "external loss")
equal(externalLoss.effect.eligibleApplied, 0, "external loss is ineligible")
local externalGain = NaturalLedger.reconcileExternal(externalLoss.state, 50, 110)
equal(externalGain.ok, true, "external gain succeeds")
sameLedger(externalGain.state, ledger(110, 110), "external recovery and gain")
equal(externalGain.effect.recoveryApplied, 40, "external gain restores recovery")
equal(externalGain.effect.eligibleApplied, 0, "external gain is ineligible")
equal(externalGain.effect.eligibleRatio, 0, "external gain ratio is zero")
local externalClear = NaturalLedger.reconcileExternal(ledger(100, 100, { target("external", 2, 110) }), 15, 130)
equal(externalClear.ok, true, "external target clear succeeds")
sameLedger(externalClear.state, ledger(130, 130), "external final synchronization")
equal(externalClear.effect.eligibleApplied, 0, "external synchronization is ineligible")
equal(externalClear.effect.clearedTargetIds[1], "external", "external clear reports target")

local masteryInput = ledger(25, 50, {
    target("first-mastery", 2, 100),
    target("second-mastery", 3, 200),
})
local mastery = NaturalLedger.master(masteryInput, 450)
equal(mastery.ok, true, "mastery succeeds")
sameLedger(mastery.state, ledger(450, 450), "mastery exact maximum")
equal(mastery.effect.recoveryApplied, 0, "mastery has no recovery")
equal(mastery.effect.eligibleApplied, 0, "mastery has no eligibility")
equal(mastery.effect.eligibleRatio, 0, "mastery has zero ratio")
equal(#mastery.effect.clearedTargetIds, 2, "mastery clears complete chain")
equal(mastery.effect.clearedTargetIds[1], "first-mastery", "mastery preserves first clear order")
equal(mastery.effect.clearedTargetIds[2], "second-mastery", "mastery preserves second clear order")
sameLedger(masteryInput, ledger(25, 50, {
    target("first-mastery", 2, 100),
    target("second-mastery", 3, 200),
}), "mastery leaves caller unchanged")
check(mastery.state ~= masteryInput, "mastery returns a new state")
check(mastery.effect.clearedTargetIds ~= masteryInput.activeTargets, "mastery clear IDs do not alias targets")
local emptyMastery = NaturalLedger.master(ledger(4, 4), 9)
equal(emptyMastery.ok, true, "empty mastery succeeds")
sameLedger(emptyMastery.state, ledger(9, 9), "empty mastery exact maximum")
equal(#emptyMastery.effect.clearedTargetIds, 0, "empty mastery clears nothing")
failed(NaturalLedger.master(nil, 9), "MALFORMED_STATE", "mastery missing state")
failed(NaturalLedger.master(ledger(0, 0), -1), "INCONSISTENT_POSITION", "mastery negative maximum")
failed(NaturalLedger.master(ledger(0, 0), math.huge), "NON_FINITE_NUMBER", "mastery infinite maximum")
failed(NaturalLedger.master(ledger(50, 100), 99), "POSITION_BEHIND_HIGH_WATER", "mastery cannot lower high water")

failed(NaturalLedger.applySupported(baseline.state, 10, 115), "INCONSISTENT_POSITION", "inconsistent delta and position")
failed(NaturalLedger.applySupported(ledger(100, 100, { target("ahead", 2, 200) }), 20, 110), "POSITION_BEHIND_HIGH_WATER", "actual behind earned high water")
failed(NaturalLedger.applySupported(ledger(80, 100, { target("ahead", 2, 200) }), 10, 85), "INCONSISTENT_POSITION", "active recovery position behind movement")

local wholeRecovery = NaturalLedger.applySupported(
    NaturalLedger.applySupported(baseline.state, -60, 40).state,
    80,
    120
)
local chunkedRecovery = baseline.state
chunkedRecovery = NaturalLedger.applySupported(chunkedRecovery, -20, 80).state
chunkedRecovery = NaturalLedger.applySupported(chunkedRecovery, -40, 40).state
local recoveryTotal = 0
local eligibleTotal = 0
local chunk
chunk = NaturalLedger.applySupported(chunkedRecovery, 10, 50)
chunkedRecovery = chunk.state
recoveryTotal = recoveryTotal + chunk.effect.recoveryApplied
eligibleTotal = eligibleTotal + chunk.effect.eligibleApplied
chunk = NaturalLedger.applySupported(chunkedRecovery, 30, 80)
chunkedRecovery = chunk.state
recoveryTotal = recoveryTotal + chunk.effect.recoveryApplied
eligibleTotal = eligibleTotal + chunk.effect.eligibleApplied
chunk = NaturalLedger.applySupported(chunkedRecovery, 40, 120)
chunkedRecovery = chunk.state
recoveryTotal = recoveryTotal + chunk.effect.recoveryApplied
eligibleTotal = eligibleTotal + chunk.effect.eligibleApplied
sameLedger(chunkedRecovery, wholeRecovery.state, "loss and recovery chunk equivalence")
equal(recoveryTotal, wholeRecovery.effect.recoveryApplied, "chunked recovery total")
equal(eligibleTotal, wholeRecovery.effect.eligibleApplied, "chunked eligibility total")

local thresholdStart = ledger(100, 100, {
    target("threshold-one", 2, 120),
    target("threshold-two", 3, 140),
    target("uncleared-final", 4, 200),
})
local wholeThreshold = NaturalLedger.applySupported(thresholdStart, 50, 250)
local chunkedThreshold = thresholdStart
local cleared = {}
local thresholdChunk
thresholdChunk = NaturalLedger.applySupported(chunkedThreshold, 10, 210)
chunkedThreshold = thresholdChunk.state
thresholdChunk = NaturalLedger.applySupported(chunkedThreshold, 15, 225)
chunkedThreshold = thresholdChunk.state
for index = 1, #thresholdChunk.effect.clearedTargetIds do
    cleared[#cleared + 1] = thresholdChunk.effect.clearedTargetIds[index]
end
thresholdChunk = NaturalLedger.applySupported(chunkedThreshold, 25, 250)
chunkedThreshold = thresholdChunk.state
for index = 1, #thresholdChunk.effect.clearedTargetIds do
    cleared[#cleared + 1] = thresholdChunk.effect.clearedTargetIds[index]
end
sameLedger(chunkedThreshold, wholeThreshold.state, "multi-threshold chunk equivalence")
equal(#cleared, #wholeThreshold.effect.clearedTargetIds, "chunked clear count")
equal(cleared[1], wholeThreshold.effect.clearedTargetIds[1], "chunked first clear order")
equal(cleared[2], wholeThreshold.effect.clearedTargetIds[2], "chunked second clear order")

return assertions
