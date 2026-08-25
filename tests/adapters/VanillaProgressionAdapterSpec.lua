local Adapter = VanillaProgressionAdapter
local assertions = 0

local function assertTrue(value, message)
    assertions = assertions + 1
    if not value then
        error(message or "expected a truthy value")
    end
end

local function assertFalse(value, message)
    assertions = assertions + 1
    if value then
        error(message or "expected a false value")
    end
end

local function assertEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error((message or "values differ")
                .. ": expected " .. tostring(expected)
                .. ", got " .. tostring(actual))
    end
end

local function assertFailure(result, code, message)
    assertFalse(result.ok, message or (code .. " should fail"))
    assertEqual(result.code, code, message or "failure code should be stable")
    assertTrue(type(result.detail) == "string" and result.detail ~= "", "failure detail should be nonempty")
end

local function makePerk(requirements, thresholds)
    local perk = {
        requirements = requirements,
        thresholds = thresholds,
    }
    function perk:getXpForLevel(level)
        local value = self.requirements[level]
        if value == nil then
            return -1
        end
        return value
    end
    function perk:getTotalXpForLevel(level)
        return self.thresholds[level]
    end
    return perk
end

local function makePlayer(level, totalXp)
    local player = {
        level = level,
        totalXp = totalXp,
        xpWrites = 0,
        levelWrites = 0,
        throwXpWrite = false,
        throwLevelWrite = false,
        wrongXpPlacement = nil,
        levelIncrement = 1,
        xpChangeOnLevel = 0,
    }
    player.xpStore = {}
    function player.xpStore:getXP(perk)
        return player.totalXp
    end
    function player.xpStore:setXPToLevel(perk, targetLevel)
        player.xpWrites = player.xpWrites + 1
        if player.throwXpWrite then
            error("mock XP write failure")
        end
        if player.wrongXpPlacement ~= nil then
            player.totalXp = player.wrongXpPlacement
        else
            player.totalXp = perk:getTotalXpForLevel(targetLevel)
        end
    end
    function player:getPerkLevel(perk)
        return self.level
    end
    function player:getXp()
        return self.xpStore
    end
    function player:LevelPerk(perk)
        self.levelWrites = self.levelWrites + 1
        if self.throwLevelWrite then
            error("mock level write failure")
        end
        self.level = self.level + self.levelIncrement
        self.totalXp = self.totalXp + self.xpChangeOnLevel
    end
    return player
end

local perk = makePerk(
    { [1] = 100, [2] = 200, [3] = 300 },
    { [1] = 100, [2] = 300, [3] = 600 }
)
local built = Adapter.build(perk)
assertTrue(built.ok, "valid dynamic curve should build")
local handle = built.handle
assertEqual(handle.adapterId, "sla.vanilla", "adapter ID should be stable")
assertEqual(handle.adapterVersion, 1, "adapter version should be stable")
assertEqual(handle.effectiveMaximum, 3, "maximum should come from the first negative sentinel")
assertTrue(type(handle.curveFingerprint) == "string" and handle.curveFingerprint ~= "", "fingerprint should be nonempty")
assertTrue(handle.curveFingerprint:match("^[-A-Za-z0-9._:]+$") ~= nil, "fingerprint should contain only StateCodec-safe ID characters")

local sameCurve = Adapter.build(makePerk(
    { [1] = 8, [2] = 9, [3] = 10 },
    { [1] = 100, [2] = 300, [3] = 600 }
))
assertTrue(sameCurve.ok, "a second curve should build")
assertEqual(sameCurve.handle.curveFingerprint, handle.curveFingerprint, "fingerprint should depend on exact cumulative thresholds")
local sameDescription = Adapter.describe(sameCurve.handle)
assertTrue(sameDescription.ok, "same cumulative curve should describe")
assertEqual(sameDescription.perLevelRequirements[1], 100, "requirements should derive from cumulative threshold differences")
assertEqual(sameDescription.perLevelRequirements[2], 200, "requirements should ignore non-sentinel discovery values")
assertEqual(sameDescription.perLevelRequirements[3], 300, "identical cumulative curves should expose identical requirements")
local differentCurve = Adapter.build(makePerk(
    { [1] = 100, [2] = 200, [3] = 301 },
    { [1] = 100, [2] = 300, [3] = 601 }
))
assertTrue(differentCurve.ok, "different curve should build")
assertTrue(differentCurve.handle.curveFingerprint ~= handle.curveFingerprint, "different cumulative threshold should change fingerprint")

local exponentToken = string.format("%.17g", 1e20)
assertTrue(string.find(exponentToken, "+", 1, true) ~= nil, "exponent fixture should exercise a plus sign")
local exponentCurveA = Adapter.build(makePerk(
    { [1] = 1, [2] = 1 },
    { [1] = 1e20, [2] = 2e20 }
))
local exponentCurveB = Adapter.build(makePerk(
    { [1] = 1, [2] = 1 },
    { [1] = 1e20, [2] = 3e20 }
))
assertTrue(exponentCurveA.ok and exponentCurveB.ok, "finite exponent-plus curves should build")
assertTrue(exponentCurveA.handle.curveFingerprint:match("^[-A-Za-z0-9._:]+$") ~= nil, "exponent-plus fingerprint should remain StateCodec-safe")
assertTrue(exponentCurveB.handle.curveFingerprint:match("^[-A-Za-z0-9._:]+$") ~= nil, "second exponent-plus fingerprint should remain StateCodec-safe")
assertTrue(string.find(exponentCurveA.handle.curveFingerprint, "+", 1, true) == nil, "encoded exponent should not retain unsafe plus")
assertTrue(exponentCurveA.handle.curveFingerprint ~= exponentCurveB.handle.curveFingerprint, "different exponent-plus thresholds should remain distinguishable")

local description = Adapter.describe(handle)
assertTrue(description.ok, "valid handle should describe")
assertEqual(description.effectiveMaximum, 3, "description should include the maximum")
assertEqual(description.cumulativeThresholds[0], 0, "description should include the level-zero origin")
assertEqual(description.cumulativeThresholds[2], 300, "description should copy cumulative thresholds")
assertEqual(description.perLevelRequirements[2], 200, "description should copy per-level requirements")
description.cumulativeThresholds[2] = 999
description.perLevelRequirements[2] = 999
local descriptionAgain = Adapter.describe(handle)
assertEqual(descriptionAgain.cumulativeThresholds[2], 300, "threshold descriptions should be detached")
assertEqual(descriptionAgain.perLevelRequirements[2], 200, "requirement descriptions should be detached")
local mutationOK = pcall(function()
    handle.adapterId = "changed"
end)
assertFalse(mutationOK, "handle identity should reject mutation")
assertEqual(handle.adapterId, "sla.vanilla", "rejected handle mutation should preserve identity")
assertFailure(Adapter.describe({}), "invalid-handle", "foreign handles should fail closed")

local ordinaryPlayer = makePlayer(1, 150)
local ordinary = Adapter.inspect(handle, ordinaryPlayer)
assertTrue(ordinary.ok, "ordinary partial progress should inspect")
assertEqual(ordinary.storedLevel, 1, "inspection should report separately stored level")
assertEqual(ordinary.totalXp, 150, "inspection should report total cumulative XP")
assertEqual(ordinary.actualPosition, 150, "actual position should be the cumulative XP coordinate")
assertEqual(ordinary.xpDerivedLevel, 1, "inspection should derive level from cumulative thresholds")
assertEqual(ordinary.effectiveMaximum, 3, "inspection should report effective maximum")
assertEqual(ordinary.nextTargetLevel, 2, "inspection should report exact next stored level")
assertEqual(ordinary.nextTargetPosition, 300, "inspection should report exact next cumulative target")
assertTrue(ordinary.levelAligned, "ordinary partial progress should be level aligned")
assertEqual(ordinary.alignment, "aligned", "ordinary alignment should be explicit")

local maximum = Adapter.inspect(handle, makePlayer(3, 725))
assertTrue(maximum.ok, "maximum progress should inspect")
assertEqual(maximum.xpDerivedLevel, 3, "XP-derived level should cap at effective maximum")
assertEqual(maximum.nextTargetLevel, nil, "maximum should have no next target level")
assertEqual(maximum.nextTargetPosition, nil, "maximum should have no next target position")

local xpAhead = Adapter.inspect(handle, makePlayer(1, 300))
assertTrue(xpAhead.ok, "XP-only partial completion should inspect")
assertEqual(xpAhead.actualPosition, 300, "partial completion should retain cumulative XP exactly")
assertEqual(xpAhead.xpDerivedLevel, 2, "partial completion should report XP-derived level")
assertFalse(xpAhead.levelAligned, "partial completion should report misalignment")
assertEqual(xpAhead.alignment, "xp-ahead", "partial completion should not guess a replacement level")
assertEqual(xpAhead.nextTargetPosition, 300, "next target should remain based on stored level")

local levelAhead = Adapter.inspect(handle, makePlayer(2, 250))
assertTrue(levelAhead.ok, "level-ahead partial state should inspect")
assertEqual(levelAhead.xpDerivedLevel, 1, "XP-derived level should remain independent")
assertEqual(levelAhead.alignment, "level-ahead", "level-ahead state should be reported")

local advancing = makePlayer(1, 150)
local advanced = Adapter.ensureTarget(handle, advancing, 2, 300)
assertTrue(advanced.ok, "exact next target should advance")
assertEqual(advanced.status, "target-ensured", "advancement status should be explicit")
assertTrue(advanced.xpWriteInvoked, "advancement should report XP write invocation")
assertTrue(advanced.levelWriteInvoked, "advancement should report level write invocation")
assertEqual(advancing.xpWrites, 1, "XP placement should be invoked exactly once")
assertEqual(advancing.levelWrites, 1, "LevelPerk should be invoked exactly once")
assertEqual(advanced.storedLevel, 2, "advancement should verify exact stored level")
assertEqual(advanced.totalXp, 300, "advancement should verify exact cumulative XP")

local interrupted = makePlayer(1, 150)
interrupted.throwLevelWrite = true
local interruptedResult = Adapter.ensureTarget(handle, interrupted, 2, 300)
assertFailure(interruptedResult, "level-write-failed", "interrupted LevelPerk should fail explicitly")
assertTrue(interruptedResult.xpWriteInvoked, "interrupted result should report completed XP invocation")
assertTrue(interruptedResult.levelWriteInvoked, "interrupted result should report attempted LevelPerk invocation")
assertEqual(interrupted.totalXp, 300, "interrupted caller should retain upward XP placement")
assertEqual(interrupted.level, 1, "throwing LevelPerk should leave stored level incomplete")
interrupted.throwLevelWrite = false
local resumed = Adapter.ensureTarget(handle, interrupted, 2, 300)
assertTrue(resumed.ok, "XP-only partial completion should reconcile")
assertFalse(resumed.xpWriteInvoked, "reconciliation should not repeat completed XP placement")
assertTrue(resumed.levelWriteInvoked, "reconciliation should perform only missing LevelPerk")
assertEqual(interrupted.xpWrites, 1, "reconciliation should preserve exactly-once XP placement")
assertEqual(interrupted.levelWrites, 2, "throwing and successful LevelPerk invocations should both be reported by fake")

local idempotent = Adapter.ensureTarget(handle, interrupted, 2, 300)
assertTrue(idempotent.ok, "already-complete target should be idempotent")
assertEqual(idempotent.status, "already-complete", "already-complete status should be explicit")
assertFalse(idempotent.xpWriteInvoked, "idempotent call should not write XP")
assertFalse(idempotent.levelWriteInvoked, "idempotent call should not invoke LevelPerk")
assertEqual(interrupted.xpWrites, 1, "idempotent call should preserve XP write count")
assertEqual(interrupted.levelWrites, 2, "idempotent call should preserve level write count")

local xpBeyondTarget = makePlayer(1, 350)
local neverLower = Adapter.ensureTarget(handle, xpBeyondTarget, 2, 300)
assertTrue(neverLower.ok, "XP already beyond target should still complete the missing level")
assertFalse(neverLower.xpWriteInvoked, "XP beyond target must never be lowered")
assertTrue(neverLower.levelWriteInvoked, "missing stored level should still advance once")
assertEqual(xpBeyondTarget.totalXp, 350, "above-target XP should remain exact and unchanged")
assertEqual(neverLower.totalXp, 350, "postcondition should report unchanged above-target XP")

local mismatchPlayer = makePlayer(1, 150)
local mismatch = Adapter.ensureTarget(handle, mismatchPlayer, 2, 301)
assertFailure(mismatch, "target-position-mismatch", "nonexact target position should fail")
assertFalse(mismatch.xpWriteInvoked, "mismatched target should not write XP")
assertFalse(mismatch.levelWriteInvoked, "mismatched target should not write level")
assertEqual(mismatchPlayer.xpWrites, 0, "mismatched target should not reach XP store")
assertEqual(mismatchPlayer.levelWrites, 0, "mismatched target should not reach LevelPerk")

local skipped = Adapter.ensureTarget(handle, makePlayer(0, 0), 2, 300)
assertFailure(skipped, "target-is-not-next-level", "skipped level should fail closed")
local behind = Adapter.ensureTarget(handle, makePlayer(3, 700), 2, 300)
assertFailure(behind, "target-behind-current-level", "past target should not lower level or XP")

assertFailure(Adapter.build(nil), "missing-perk", "missing perk should fail")
assertFailure(Adapter.build(perk, "bad"), "invalid-options", "non-table options should fail")
assertFailure(Adapter.build(perk, { discoveryLimit = 0 }), "invalid-discovery-limit", "zero discovery limit should fail")
assertFailure(Adapter.build(perk, { discoveryLimit = 1.5 }), "invalid-discovery-limit", "fractional discovery limit should fail")
assertFailure(Adapter.build(perk, { discoveryLimit = false }), "invalid-discovery-limit", "false discovery limit should not silently default")

local missingDiscovery = Adapter.build({})
assertFailure(missingDiscovery, "missing-capability", "missing discovery capability should fail")
local throwingDiscoveryPerk = makePerk({}, {})
function throwingDiscoveryPerk:getXpForLevel(level)
    error("mock discovery failure")
end
assertFailure(Adapter.build(throwingDiscoveryPerk), "capability-error", "throwing discovery capability should fail")

local noSentinelPerk = makePerk({}, {})
function noSentinelPerk:getXpForLevel(level)
    return 1
end
function noSentinelPerk:getTotalXpForLevel(level)
    return level
end
assertFailure(
    Adapter.build(noSentinelPerk, { discoveryLimit = 4 }),
    "discovery-limit-reached",
    "missing negative sentinel should fail by the explicit limit"
)

local zeroMaximum = makePerk({}, {})
assertFailure(Adapter.build(zeroMaximum), "invalid-effective-maximum", "sentinel at level one should reject nonpositive maximum")
local malformedRequirement = makePerk({ [1] = math.huge }, { [1] = 1 })
assertFailure(Adapter.build(malformedRequirement), "invalid-value", "non-finite requirement should fail")
local missingTotals = {
    getXpForLevel = function(self, level)
        return level == 1 and 1 or -1
    end,
}
assertFailure(Adapter.build(missingTotals), "missing-capability", "missing cumulative total capability should fail")
local throwingTotals = makePerk({ [1] = 1 }, { [1] = 1 })
function throwingTotals:getTotalXpForLevel(level)
    error("mock total failure")
end
assertFailure(Adapter.build(throwingTotals), "capability-error", "throwing cumulative total should fail")
local malformedTotal = makePerk({ [1] = 1 }, { [1] = math.huge })
assertFailure(Adapter.build(malformedTotal), "invalid-value", "non-finite cumulative total should fail")
local nonIncreasing = makePerk({ [1] = 1, [2] = 1 }, { [1] = 100, [2] = 100 })
assertFailure(Adapter.build(nonIncreasing), "invalid-curve", "non-increasing cumulative curve should fail")

assertFailure(Adapter.inspect(handle, nil), "missing-player", "missing player should fail")
local missingLevel = makePlayer(1, 150)
missingLevel.getPerkLevel = nil
assertFailure(Adapter.inspect(handle, missingLevel), "missing-capability", "missing stored-level capability should fail")
local throwingLevel = makePlayer(1, 150)
function throwingLevel:getPerkLevel(perk)
    error("mock stored-level failure")
end
assertFailure(Adapter.inspect(handle, throwingLevel), "capability-error", "throwing stored-level capability should fail")
local fractionalLevel = makePlayer(1.5, 150)
assertFailure(Adapter.inspect(handle, fractionalLevel), "invalid-stored-level", "fractional stored level should fail")
local missingXpStore = makePlayer(1, 150)
missingXpStore.getXp = nil
assertFailure(Adapter.inspect(handle, missingXpStore), "missing-capability", "missing XP-store capability should fail")
local throwingXpStore = makePlayer(1, 150)
function throwingXpStore:getXp()
    error("mock XP-store failure")
end
assertFailure(Adapter.inspect(handle, throwingXpStore), "capability-error", "throwing XP-store capability should fail")
local missingGetXP = makePlayer(1, 150)
missingGetXP.xpStore.getXP = nil
assertFailure(Adapter.inspect(handle, missingGetXP), "missing-capability", "missing cumulative XP getter should fail")
local throwingGetXP = makePlayer(1, 150)
function throwingGetXP.xpStore:getXP(perk)
    error("mock XP read failure")
end
assertFailure(Adapter.inspect(handle, throwingGetXP), "capability-error", "throwing cumulative XP getter should fail")
local negativeXp = makePlayer(1, -1)
assertFailure(Adapter.inspect(handle, negativeXp), "invalid-total-xp", "negative total XP should fail")
local infiniteXp = makePlayer(1, math.huge)
assertFailure(Adapter.inspect(handle, infiniteXp), "invalid-value", "non-finite total XP should fail")

local missingSetter = makePlayer(1, 150)
missingSetter.xpStore.setXPToLevel = nil
local missingSetterResult = Adapter.ensureTarget(handle, missingSetter, 2, 300)
assertFailure(missingSetterResult, "missing-capability", "missing XP setter should fail")
assertFalse(missingSetterResult.xpWriteInvoked, "missing setter should not report XP invocation")
assertFalse(missingSetterResult.levelWriteInvoked, "missing setter should not invoke level")

local missingLeveler = makePlayer(1, 150)
missingLeveler.LevelPerk = nil
local missingLevelerResult = Adapter.ensureTarget(handle, missingLeveler, 2, 300)
assertFailure(missingLevelerResult, "missing-capability", "missing LevelPerk should fail before any write")
assertFalse(missingLevelerResult.xpWriteInvoked, "capability preflight should avoid partial XP writes")
assertEqual(missingLeveler.xpWrites, 0, "missing LevelPerk should leave XP untouched")

local throwingSetter = makePlayer(1, 150)
throwingSetter.throwXpWrite = true
local throwingSetterResult = Adapter.ensureTarget(handle, throwingSetter, 2, 300)
assertFailure(throwingSetterResult, "xp-write-failed", "throwing XP setter should fail")
assertTrue(throwingSetterResult.xpWriteInvoked, "throwing setter was invoked")
assertFalse(throwingSetterResult.levelWriteInvoked, "level write should not follow throwing XP setter")

local wrongPlacement = makePlayer(1, 150)
wrongPlacement.wrongXpPlacement = 299
local wrongPlacementResult = Adapter.ensureTarget(handle, wrongPlacement, 2, 300)
assertFailure(wrongPlacementResult, "xp-postcondition-failed", "inexact XP placement should fail")
assertTrue(wrongPlacementResult.xpWriteInvoked, "inexact setter should report invocation")
assertFalse(wrongPlacementResult.levelWriteInvoked, "LevelPerk should not follow inexact XP placement")
assertEqual(wrongPlacement.level, 1, "failed XP postcondition should preserve stored level")

local wrongLevel = makePlayer(1, 150)
wrongLevel.levelIncrement = 2
local wrongLevelResult = Adapter.ensureTarget(handle, wrongLevel, 2, 300)
assertFailure(wrongLevelResult, "level-postcondition-failed", "inexact stored-level mutation should fail")
assertTrue(wrongLevelResult.xpWriteInvoked, "wrong level case should report XP invocation")
assertTrue(wrongLevelResult.levelWriteInvoked, "wrong level case should report LevelPerk invocation")
assertEqual(wrongLevelResult.observedStoredLevel, 3, "failure should report exact observed stored level")

local xpChangedByLevel = makePlayer(1, 150)
xpChangedByLevel.xpChangeOnLevel = 1
local xpChangedResult = Adapter.ensureTarget(handle, xpChangedByLevel, 2, 300)
assertFailure(xpChangedResult, "xp-postcondition-failed", "unexpected post-LevelPerk XP change should fail exact postcondition")
assertEqual(xpChangedResult.observedTotalXp, 301, "failure should report exact observed XP")

return assertions
