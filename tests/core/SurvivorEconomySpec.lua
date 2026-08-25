local E = SurvivorEconomy
local A = Allotment
local P = PostMax
local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed") end
end

local function bad(result, code)
    expect(not result.ok and result.code == code, "expected " .. code .. ", got " .. tostring(result.code))
end

expect(E.ORDINARY_NORMALIZATION == 1, "ordinary normalization constant")
expect(E.FITNESS_STRENGTH_DEFAULT_NORMALIZATION == 21850 / 325000, "passive normalization constant")
expect(E.nextLevelCost(0).ok and E.nextLevelCost(0).cost == 1200, "level zero cost")
expect(E.nextLevelCost(4).cost == 2400, "level cost curve")
bad(E.nextLevelCost(-1), "invalid_level")
bad(E.nextLevelCost(0 / 0), "invalid_level")

local state = { level = 0, xpIntoLevel = 0, spent = 0 }
local available = E.availableAp(state)
expect(available.ok and available.availableAp == 0, "initial AP")
local zero = E.applyXp(state, 0)
expect(zero.ok and zero.state.level == 0 and zero.state.xpIntoLevel == 0 and zero.effects.levelsGained == 0 and zero.effects.apGained == 0, "zero XP")
expect(zero.state ~= state, "zero XP does not alias state")
local one = E.applyXp(state, 1200)
expect(one.ok and one.state.level == 1 and one.state.xpIntoLevel == 0 and one.effects.levelsGained == 1 and one.effects.apGained == 1, "single level crossing")
expect(one.levelsGained == nil and one.apGained == nil, "level effects have one canonical shape")
local partial = E.applyXp({ level = 1, xpIntoLevel = 1400, spent = 0 }, 99)
expect(partial.ok and partial.state.level == 1 and partial.state.xpIntoLevel == 1499, "partial XP")
local multi = E.applyXp({ level = 0, xpIntoLevel = 0, spent = 0 }, 3900)
expect(multi.ok and multi.state.level == 2 and multi.state.xpIntoLevel == 1200 and multi.effects.levelsGained == 2 and multi.effects.apGained == 2, "multiple level crossings")
local spent = { level = 4, xpIntoLevel = 0, spent = 3 }
expect(E.availableAp(spent).availableAp == 1, "AP derives from level minus spent")
local beforeLevel = spent.level
local immutable = E.applyXp(spent, 2400)
immutable.state.level = 99
expect(spent.level == beforeLevel and spent.xpIntoLevel == 0 and spent.spent == 3, "apply XP retains input")
bad(E.availableAp({ level = 1, xpIntoLevel = 0, spent = 2 }), "impossible_spent_level")
bad(E.applyXp({ level = 0, xpIntoLevel = 1200, spent = 0 }, 1), "invalid_state")
bad(E.applyXp(state, -1), "invalid_gain")
bad(E.applyXp(state, math.huge), "invalid_gain")

local award = E.computeAward(100, 2, 3, 0.25)
expect(award.ok and award.eligibleBase == 25 and award.normalizedBase == 50 and award.survivorXp == 150, "award factor isolation")
local noEligible = E.computeAward(100, 2, 3, 0)
expect(noEligible.ok and noEligible.eligibleBase == 0 and noEligible.normalizedBase == 0 and noEligible.survivorXp == 0, "zero eligibility")
bad(E.computeAward(-1, 1, 1, 1), "invalid_award")
bad(E.computeAward(1, 0, 1, 1), "invalid_normalization")
bad(E.computeAward(1, 1, -1, 1), "invalid_multiplier")
bad(E.computeAward(1, 1, 1, 1.01), "invalid_eligible_ratio")
bad(E.computeAward(1, 1, 1, 0 / 0), "invalid_eligible_ratio")

local curve = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
local normalized = E.normalizationFromCoreCurve(curve)
expect(normalized.ok and normalized.normalization == 21850 / 55, "core curve normalization")
expect(curve[1] == 1, "curve is not mutated")
bad(E.normalizationFromCoreCurve({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }), "invalid_curve")
bad(E.normalizationFromCoreCurve({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 0 }), "invalid_curve")
bad(E.normalizationFromCoreCurve({ 1, 2, 3, 4, 5, 6, 7, 8, 9, math.huge }), "invalid_curve")
local extraCurve = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }; extraCurve.extra = 11
bad(E.normalizationFromCoreCurve(extraCurve), "invalid_curve")

local active = { Axe = 1, Carpentry = 1 }
local globalOpen = A.evaluate({ mode = "Global", globalLimit = 3 }, "Axe", active, true)
expect(globalOpen.ok and globalOpen.allowed and globalOpen.activeCount == 2, "global capacity open")
local globalFull = A.evaluate({ mode = "Global", globalLimit = 2 }, "Axe", active, true)
expect(globalFull.ok and not globalFull.allowed and globalFull.limit == 2, "global boundary")
local free = A.evaluate({ mode = "Free" }, "Axe", active, true)
expect(free.ok and free.allowed, "free allotment")
local perSkillOpen = A.evaluate({ mode = "PerSkill", perSkillDefault = 2 }, "Axe", active, true)
expect(perSkillOpen.ok and perSkillOpen.allowed and perSkillOpen.activeCount == 1, "per skill default open")
local perSkillFull = A.evaluate({ mode = "PerSkill", perSkillDefault = 1 }, "Axe", active, true)
expect(perSkillFull.ok and not perSkillFull.allowed, "per skill boundary")
local overridden = A.evaluate({ mode = "PerSkill", perSkillDefault = 1, perSkillOverrides = { Axe = 3 } }, "Axe", active, true)
expect(overridden.ok and overridden.allowed and overridden.limit == 3, "per skill override")
local disabled = A.evaluate({ mode = "PerSkill", perSkillDefault = 2, perSkillOverrides = { Axe = 0 } }, "Axe", active, true)
expect(disabled.ok and not disabled.allowed and disabled.limit == 0, "per skill zero disables new target")
local reboost = A.evaluate({ mode = "Global", globalLimit = 0 }, "Axe", active, false)
expect(reboost.ok and reboost.allowed and reboost.bypassed and reboost.activeCount == 1, "exact reboost bypasses capacity")
bad(A.evaluate({ mode = "Global", globalLimit = -1 }, "Axe", active, false), "invalid_config")
bad(A.evaluate({ mode = "PerSkill", perSkillDefault = 1, perSkillOverrides = { Axe = -1 } }, "Axe", active, false), "invalid_config")
expect(active.Axe == 1 and active.Carpentry == 1, "allotment never modifies existing counts")
bad(A.evaluate({ mode = "Other" }, "Axe", active, true), "invalid_mode")
bad(A.evaluate({ mode = "Global", globalLimit = -1 }, "Axe", active, true), "invalid_config")
bad(A.evaluate({ mode = "PerSkill", perSkillDefault = 1, perSkillOverrides = { Axe = -1 } }, "Axe", active, true), "invalid_config")
bad(A.evaluate({ mode = "Free" }, "", active, true), "invalid_perk")
bad(A.evaluate({ mode = "Free" }, "Axe", { Axe = -1 }, true), "invalid_active_targets")

local postState = { fullRateUsed = 2 }
local disabledPost = P.apply(postState, 10, 2, { enabled = false })
expect(disabledPost.ok and disabledPost.effect.survivorXp == 0 and disabledPost.state.fullRateUsed == 2, "disabled post maximum consumes nothing")
expect(disabledPost.state ~= postState, "disabled post maximum does not alias state")
local underAllowance = P.apply({ fullRateUsed = 2 }, 3, 2, { enabled = true, fullRateAllowance = 10, diminishedRate = 0.25 })
expect(underAllowance.ok and underAllowance.effect.fullRateBase == 3 and underAllowance.effect.diminishedBase == 0 and underAllowance.effect.survivorXp == 6 and underAllowance.state.fullRateUsed == 5, "full rate below allowance")
local boundary = P.apply({ fullRateUsed = 8 }, 2, 3, { enabled = true, fullRateAllowance = 10, diminishedRate = 0.25 })
expect(boundary.ok and boundary.effect.fullRateBase == 2 and boundary.effect.diminishedBase == 0 and boundary.effect.survivorXp == 6, "full rate allowance boundary")
local split = P.apply({ fullRateUsed = 8 }, 5, 2, { enabled = true, fullRateAllowance = 10, diminishedRate = 0.25 })
expect(split.ok and split.effect.fullRateBase == 2 and split.effect.diminishedBase == 3 and split.effect.survivorXp == 5.5 and split.state.fullRateUsed == 13, "one award split after crossing allowance")
local exhausted = P.apply({ fullRateUsed = 10 }, 4, 2, { enabled = true, fullRateAllowance = 10, diminishedRate = 0.5 })
expect(exhausted.ok and exhausted.effect.fullRateBase == 0 and exhausted.effect.diminishedBase == 4 and exhausted.effect.survivorXp == 4, "exhausted allowance")
local changedSettings = P.apply({ fullRateUsed = 13 }, 2, 1, { enabled = true, fullRateAllowance = 20, diminishedRate = 0.5 })
expect(changedSettings.ok and changedSettings.effect.fullRateBase == 2 and changedSettings.state.fullRateUsed == 15, "setting changes retain lifetime usage")
bad(P.apply({ fullRateUsed = -1 }, 1, 1, { enabled = false }), "invalid_postmax_state")
bad(P.apply({ fullRateUsed = 0 }, math.huge, 1, { enabled = false }), "invalid_award")
bad(P.apply({ fullRateUsed = 0 }, 1, 1, { enabled = true, fullRateAllowance = -1, diminishedRate = 0.5 }), "invalid_postmax_settings")
bad(P.apply({ fullRateUsed = 0 }, 1, 1, { enabled = true, fullRateAllowance = 1, diminishedRate = math.huge }), "invalid_postmax_settings")

return assertions
