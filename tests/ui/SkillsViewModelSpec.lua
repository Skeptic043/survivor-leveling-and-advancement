local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed") end
end

local function expectEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
    end
end

local function exactFields(value, expected)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do if not expected[key] then return false end end
    for key in pairs(expected) do if rawget(value, key) == nil then return false end end
    return true
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
    return copy
end

local function snapshot(availableAp)
    local available = availableAp == nil and 4 or availableAp
    return {
        protocolVersion = 1,
        ready = true,
        sequence = 12,
        revision = 7,
        survivor = {
            level = 6,
            xpIntoLevel = 250.5,
            xpForNextLevel = 3000,
            spent = 6 - available,
            availableAp = available,
        },
        perks = {
            Axe = {
                effectiveMaximum = 10,
                naturalPosition = 100,
                highWaterPosition = 100,
                activeTargets = {
                    { targetLevel = 4, targetPosition = 250 },
                },
            },
            Woodwork = {
                effectiveMaximum = 10,
                naturalPosition = 50,
                highWaterPosition = 70,
                activeTargets = {
                    { targetLevel = 3, targetPosition = 150 },
                },
            },
            Sprinting = {
                effectiveMaximum = 10,
                naturalPosition = 5,
                highWaterPosition = 5,
                activeTargets = {
                    { targetLevel = 2, targetPosition = 20 },
                    { targetLevel = 3, targetPosition = 45 },
                },
            },
            Tailoring = {
                effectiveMaximum = 8,
                naturalPosition = 0,
                highWaterPosition = 0,
                activeTargets = {},
            },
            Hidden = {
                effectiveMaximum = 10,
                naturalPosition = 0,
                highWaterPosition = 0,
                activeTargets = {
                    { targetLevel = 1, targetPosition = 10 },
                },
            },
        },
    }
end

local function rows()
    return {
        { perkId = "Axe", currentLevel = 3, effectiveMaximum = 10 },
        { perkId = "Cooking", currentLevel = 2, effectiveMaximum = 10 },
        { perkId = "Woodwork", currentLevel = 2, effectiveMaximum = 10 },
        { perkId = "Tailoring", currentLevel = 2, effectiveMaximum = 10 },
        { perkId = "Aiming", currentLevel = 9, effectiveMaximum = 10 },
        { perkId = "Maxed", currentLevel = 10, effectiveMaximum = 10 },
    }
end

local function globalConfig(limit)
    return { mode = "Global", globalLimit = limit == nil and 5 or limit }
end

local function perSkillConfig()
    return {
        mode = "PerSkill",
        perSkillDefault = 1,
        perSkillOverrides = { Cooking = 2, Aiming = 0, Axe = 0 },
    }
end

local function build(model, ownerSnapshot, config, pending, suppliedRows)
    return model.build({
        snapshot = ownerSnapshot,
        allotment = config,
        pending = pending == true,
        rows = suppliedRows or rows(),
    })
end

local created = SkillsViewModel.create({ ClientOwnerState = ClientOwnerState, Allotment = Allotment })
expectEqual(created.ok, true, "create succeeds")
expect(exactFields(created, { ok = true, model = true }), "create result is minimal")
expect(exactFields(SkillsViewModel, { create = true }), "module surface is exact")
expect(exactFields(created.model, { build = true }), "model surface is exact")
local model = created.model

local global = build(model, snapshot(), globalConfig(), false)
expectEqual(global.ok, true, "global build succeeds: " .. tostring(global.code) .. ":" .. tostring(global.detail))
expect(exactFields(global, { ok = true, view = true }), "build result is minimal")
local view = global.view
expect(exactFields(view, {
    sequence = true,
    revision = true,
    survivor = true,
    allotment = true,
    pending = true,
    rows = true,
}), "view fields are exact")
expectEqual(view.sequence, 12, "sequence projected")
expectEqual(view.revision, 7, "revision projected")
expectEqual(view.pending, false, "pending projected")
expect(exactFields(view.survivor, {
    level = true,
    xpIntoLevel = true,
    xpForNextLevel = true,
    spent = true,
    availableAp = true,
}), "survivor projection is exact")
expectEqual(view.survivor.level, 6, "survivor level projected")
expectEqual(view.survivor.xpIntoLevel, 250.5, "survivor xp projected")
expectEqual(view.survivor.xpForNextLevel, 3000, "survivor cost projected")
expectEqual(view.survivor.spent, 2, "spent AP projected")
expectEqual(view.survivor.availableAp, 4, "available AP projected")
expect(exactFields(view.allotment, { mode = true, activeCount = true, limit = true }), "global allotment fields")
expectEqual(view.allotment.mode, "Global", "global mode projected")
expectEqual(view.allotment.activeCount, 5, "global count includes rows not supplied")
expectEqual(view.allotment.limit, 5, "global limit projected")

local axe = view.rows.Axe
expect(exactFields(axe, {
    currentLevel = true,
    effectiveMaximum = true,
    nextTargetLevel = true,
    apCost = true,
    enabled = true,
    activeTargetLevels = true,
    naturalPosition = true,
    highWaterPosition = true,
}), "enabled published row shape")
expectEqual(axe.enabled, true, "reboost bypasses full global capacity")
expectEqual(axe.nextTargetLevel, 4, "ordinary next target")
expectEqual(axe.apCost, 1, "ordinary cost")
expectEqual(axe.activeTargetLevels[1], 4, "target level projected")
expectEqual(axe.naturalPosition, 100, "natural position projected")
expectEqual(axe.highWaterPosition, 100, "high-water position projected")

local cooking = view.rows.Cooking
expectEqual(cooking.enabled, false, "ordinary add blocked at global capacity")
expectEqual(cooking.reasonCode, "allotment_capacity", "capacity reason")
expectEqual(cooking.nextTargetLevel, 3, "absent record still gets next target")
expectEqual(cooking.apCost, 1, "absent record ordinary cost")
expectEqual(#cooking.activeTargetLevels, 0, "absent record has no target overlays")
expectEqual(cooking.naturalPosition, nil, "absent record has no natural position")
expectEqual(cooking.highWaterPosition, nil, "absent record has no high-water position")

expectEqual(view.rows.Woodwork.enabled, false, "red recovery disables")
expectEqual(view.rows.Woodwork.reasonCode, "red_recovery", "red reason")
expectEqual(view.rows.Tailoring.enabled, false, "maximum mismatch disables row")
expectEqual(view.rows.Tailoring.reasonCode, "maximum_mismatch", "mismatch reason")
expectEqual(view.rows.Tailoring.naturalPosition, 0, "mismatch still detaches overlay position")
expectEqual(view.rows.Aiming.enabled, true, "mastery bypasses positive global capacity")
expectEqual(view.rows.Aiming.nextTargetLevel, 10, "mastery target")
expectEqual(view.rows.Aiming.apCost, 2, "mastery costs two AP")
expectEqual(view.rows.Maxed.enabled, false, "maximum row disabled")
expectEqual(view.rows.Maxed.reasonCode, "at_maximum", "maximum reason")
expectEqual(view.rows.Maxed.nextTargetLevel, nil, "maximum row has no next target")
expectEqual(view.rows.Maxed.apCost, nil, "maximum row has no AP cost")

local openGlobal = build(model, snapshot(), globalConfig(6), false, {
    { perkId = "Cooking", currentLevel = 2, effectiveMaximum = 10 },
})
expectEqual(openGlobal.ok, true, "open global build succeeds")
expectEqual(openGlobal.view.rows.Cooking.enabled, true, "global capacity admits ordinary target")
expectEqual(openGlobal.view.rows.Cooking.apCost, 1, "global ordinary spend costs one AP")

local zeroGlobal = build(model, snapshot(), globalConfig(0), false, {
    { perkId = "Aiming", currentLevel = 9, effectiveMaximum = 10 },
})
expectEqual(zeroGlobal.ok, true, "zero global build succeeds")
expectEqual(zeroGlobal.view.rows.Aiming.enabled, false, "zero limit disables mastery")
expectEqual(zeroGlobal.view.rows.Aiming.reasonCode, "allotment_disabled", "zero-limit mastery reason")

local lowAp = build(model, snapshot(1), globalConfig(5), false, {
    { perkId = "Aiming", currentLevel = 9, effectiveMaximum = 10 },
})
expectEqual(lowAp.ok, true, "low AP build succeeds")
expectEqual(lowAp.view.rows.Aiming.enabled, false, "one AP cannot buy mastery")
expectEqual(lowAp.view.rows.Aiming.reasonCode, "insufficient_ap", "insufficient AP reason")

local pending = build(model, snapshot(0), globalConfig(0), true)
expectEqual(pending.ok, true, "pending build succeeds")
for perkId, row in pairs(pending.view.rows) do
    expectEqual(row.enabled, false, "pending disables " .. perkId)
    expectEqual(row.reasonCode, "pending", "pending reason for " .. perkId)
end

local perSkillRows = {
    { perkId = "Axe", currentLevel = 3, effectiveMaximum = 10 },
    { perkId = "Cooking", currentLevel = 2, effectiveMaximum = 10 },
    { perkId = "Aiming", currentLevel = 9, effectiveMaximum = 10 },
    { perkId = "Sprinting", currentLevel = 1, effectiveMaximum = 10 },
    { perkId = "NewSkill", currentLevel = 0, effectiveMaximum = 6 },
}
local perSkill = build(model, snapshot(), perSkillConfig(), false, perSkillRows)
expectEqual(perSkill.ok, true, "per-skill build succeeds")
expect(exactFields(perSkill.view.allotment, { mode = true }), "per-skill top-level has no aggregate")
expectEqual(perSkill.view.rows.Cooking.activeCount, 0, "per-skill empty count")
expectEqual(perSkill.view.rows.Cooking.limit, 2, "per-skill override")
expectEqual(perSkill.view.rows.Cooking.enabled, true, "per-skill override admits ordinary target")
expectEqual(perSkill.view.rows.NewSkill.activeCount, 0, "absent row count is zero")
expectEqual(perSkill.view.rows.NewSkill.limit, 1, "per-skill default")
expectEqual(perSkill.view.rows.NewSkill.enabled, true, "per-skill default admits target")
expectEqual(perSkill.view.rows.Axe.activeCount, 1, "reboost row count")
expectEqual(perSkill.view.rows.Axe.limit, 0, "zero override projected")
expectEqual(perSkill.view.rows.Axe.enabled, true, "ordinary reboost bypasses disabled capacity")
expectEqual(perSkill.view.rows.Sprinting.activeCount, 2, "multiple active targets counted")
expectEqual(perSkill.view.rows.Sprinting.limit, 1, "default limit projected at capacity")
expectEqual(perSkill.view.rows.Sprinting.enabled, true, "matching next target reboost bypasses capacity")
expectEqual(perSkill.view.rows.Aiming.enabled, false, "zero override blocks final mastery")
expectEqual(perSkill.view.rows.Aiming.reasonCode, "allotment_disabled", "per-skill zero reason")

local zeroPerSkill = build(model, snapshot(), {
    mode = "PerSkill",
    perSkillDefault = 1,
    perSkillOverrides = { Cooking = 0 },
}, false, {
    { perkId = "Cooking", currentLevel = 2, effectiveMaximum = 10 },
})
expectEqual(zeroPerSkill.ok, true, "per-skill ordinary zero build succeeds")
expectEqual(zeroPerSkill.view.rows.Cooking.enabled, false, "zero override blocks ordinary target")
expectEqual(zeroPerSkill.view.rows.Cooking.reasonCode, "allotment_disabled", "ordinary zero-limit reason")

local fullPerSkill = build(model, snapshot(), {
    mode = "PerSkill",
    perSkillDefault = 1,
    perSkillOverrides = {},
}, false, {
    { perkId = "Woodwork", currentLevel = 3, effectiveMaximum = 10 },
})
expectEqual(fullPerSkill.ok, true, "per-skill full build succeeds")
expectEqual(fullPerSkill.view.rows.Woodwork.reasonCode, "red_recovery", "red takes precedence over capacity")

local alignedSnapshot = snapshot()
alignedSnapshot.perks.Woodwork.naturalPosition = 70
local fullAligned = build(model, alignedSnapshot, {
    mode = "PerSkill",
    perSkillDefault = 1,
    perSkillOverrides = {},
}, false, {
    { perkId = "Woodwork", currentLevel = 3, effectiveMaximum = 10 },
})
expectEqual(fullAligned.ok, true, "aligned capacity build succeeds")
expectEqual(fullAligned.view.rows.Woodwork.enabled, false, "per-skill capacity blocks new target")
expectEqual(fullAligned.view.rows.Woodwork.reasonCode, "allotment_capacity", "per-skill capacity reason")

local free = build(model, snapshot(), { mode = "Free" }, false, {
    { perkId = "Cooking", currentLevel = 2, effectiveMaximum = 10 },
})
expectEqual(free.ok, true, "free build succeeds")
expect(exactFields(free.view.allotment, { mode = true }), "free mode has no limits")
expectEqual(free.view.rows.Cooking.enabled, true, "free mode admits ordinary target")
expectEqual(free.view.rows.Cooking.activeCount, nil, "free row has no active count")
expectEqual(free.view.rows.Cooking.limit, nil, "free row has no limit")

local split = build(model, snapshot(), globalConfig(), false, {
    { perkId = "Cooking", currentLevel = 2, effectiveMaximum = 10 },
})
expectEqual(split.ok, true, "split row set succeeds")
expectEqual(split.view.rows.Cooking ~= nil, true, "supplied row present")
expectEqual(split.view.rows.Axe, nil, "unsupplied row absent")
expectEqual(split.view.allotment.activeCount, 5, "hidden snapshot targets still count globally")

local mutationSnapshot = snapshot()
local mutationConfig = perSkillConfig()
local mutationRows = perSkillRows
local detached = build(model, mutationSnapshot, mutationConfig, false, mutationRows)
expectEqual(detached.ok, true, "detachment build succeeds")
mutationSnapshot.survivor.level = 99
mutationSnapshot.perks.Axe.naturalPosition = 999
mutationSnapshot.perks.Axe.activeTargets[1].targetLevel = 9
mutationConfig.perSkillOverrides.Axe = 9
mutationRows[1].currentLevel = 9
expectEqual(detached.view.survivor.level, 6, "survivor detached from caller")
expectEqual(detached.view.rows.Axe.naturalPosition, 100, "position detached from caller")
expectEqual(detached.view.rows.Axe.activeTargetLevels[1], 4, "target levels detached from caller")
expectEqual(detached.view.rows.Axe.limit, 0, "limit detached from caller")
expectEqual(detached.view.rows.Axe.currentLevel, 3, "row detached from caller")
detached.view.rows.Axe.activeTargetLevels[1] = 77
detached.view.survivor.level = 77
local rebuilt = build(model, snapshot(), perSkillConfig(), false, perSkillRows)
expectEqual(rebuilt.view.rows.Axe.activeTargetLevels[1], 4, "returned array mutation does not affect later build")
expectEqual(rebuilt.view.survivor.level, 6, "returned survivor mutation does not affect later build")

local function expectFailure(result, code)
    expectEqual(result.ok, false, "failure expected")
    expectEqual(result.code, code, "failure code")
    expectEqual(result.view, nil, "failure has no view")
end

local notReady = snapshot()
notReady.ready = false
local notReadyResult = build(model, notReady, globalConfig(6), false, {
    { perkId = "Cooking", currentLevel = 2, effectiveMaximum = 10 },
})
expectFailure(notReadyResult, "invalid_snapshot")
expectEqual(notReadyResult.detail, "not_ready", "not-ready snapshot fails at the readiness boundary")
expectEqual(notReadyResult.view, nil, "not-ready snapshot cannot expose an enabled row")

expectFailure(SkillsViewModel.create({}), "invalid_dependencies")
expectFailure(SkillsViewModel.create({ ClientOwnerState = ClientOwnerState, Allotment = Allotment, extra = true }), "invalid_dependencies")
expectFailure(SkillsViewModel.create(setmetatable({ ClientOwnerState = ClientOwnerState, Allotment = Allotment }, {})), "invalid_dependencies")
expectFailure(SkillsViewModel.create({ ClientOwnerState = {}, Allotment = Allotment }), "invalid_dependencies")
expectFailure(SkillsViewModel.create({ ClientOwnerState = ClientOwnerState, Allotment = {} }), "invalid_dependencies")

local baseInput = {
    snapshot = snapshot(),
    allotment = globalConfig(),
    pending = false,
    rows = rows(),
}
local malformedInput = clone(baseInput)
malformedInput.extra = true
expectFailure(model.build(malformedInput), "invalid_input")
malformedInput = clone(baseInput)
malformedInput.pending = 0
expectFailure(model.build(malformedInput), "invalid_input")
malformedInput = clone(baseInput)
setmetatable(malformedInput, {})
expectFailure(model.build(malformedInput), "invalid_input")

local function rejectRows(mutator)
    local value = clone(baseInput)
    mutator(value.rows)
    expectFailure(model.build(value), "invalid_rows")
end

rejectRows(function(value) value[2] = nil end)
rejectRows(function(value) value[2].perkId = value[1].perkId end)
rejectRows(function(value) value[1].perkId = "bad id" end)
rejectRows(function(value) value[1].perkId = "Axe\195\169" end)
rejectRows(function(value) value[1].currentLevel = -1 end)
rejectRows(function(value) value[1].currentLevel = 1.5 end)
rejectRows(function(value) value[1].effectiveMaximum = 0 end)
rejectRows(function(value) value[1].currentLevel = 11 end)
rejectRows(function(value) value[1].extra = true end)
rejectRows(function(value) setmetatable(value, {}) end)
rejectRows(function(value) setmetatable(value[1], {}) end)
rejectRows(function(value) value[1] = value end)

local function rejectConfig(config)
    local value = clone(baseInput)
    value.allotment = config
    expectFailure(model.build(value), "invalid_allotment")
end

rejectConfig({ mode = "Other" })
rejectConfig({ mode = "Global", globalLimit = -1 })
rejectConfig({ mode = "Global", globalLimit = 1, extra = true })
rejectConfig({ mode = "Free", globalLimit = 1 })
rejectConfig({ mode = "PerSkill", perSkillDefault = 1 })
rejectConfig({ mode = "PerSkill", perSkillDefault = 1, perSkillOverrides = { ["bad id"] = 1 } })
rejectConfig({ mode = "PerSkill", perSkillDefault = 1, perSkillOverrides = { Axe = math.huge } })
local metatableOverrides = { mode = "PerSkill", perSkillDefault = 1, perSkillOverrides = {} }
setmetatable(metatableOverrides.perSkillOverrides, {})
rejectConfig(metatableOverrides)
local cyclicOverrides = { mode = "PerSkill", perSkillDefault = 1, perSkillOverrides = {} }
cyclicOverrides.perSkillOverrides.Axe = cyclicOverrides.perSkillOverrides
rejectConfig(cyclicOverrides)

local function rejectSnapshot(mutator)
    local value = clone(baseInput)
    mutator(value.snapshot)
    expectFailure(model.build(value), "invalid_snapshot")
end

rejectSnapshot(function(value) value.extra = true end)
rejectSnapshot(function(value) setmetatable(value, {}) end)
rejectSnapshot(function(value) value.survivor.xpIntoLevel = math.huge end)
rejectSnapshot(function(value) value.perks.Axe.activeTargets[1].extra = true end)
rejectSnapshot(function(value) value.perks.Axe.activeTargets = value.perks.Axe end)

local capturedClient = { validate = ClientOwnerState.validate }
local capturedAllotment = { evaluate = Allotment.evaluate }
local captured = SkillsViewModel.create({ ClientOwnerState = capturedClient, Allotment = capturedAllotment }).model
capturedClient.validate = function() return { ok = false } end
capturedAllotment.evaluate = function() return { ok = false } end
expectEqual(build(captured, snapshot(), globalConfig(), false).ok, true, "creation captures dependency callables")

local throwingValidator = SkillsViewModel.create({
    ClientOwnerState = { validate = function() error("boom") end },
    Allotment = Allotment,
}).model
expectFailure(build(throwingValidator, snapshot(), globalConfig(), false), "invalid_snapshot")
local malformedValidator = SkillsViewModel.create({
    ClientOwnerState = { validate = function(value) return { ok = true, snapshot = value, private = true } end },
    Allotment = Allotment,
}).model
expectFailure(build(malformedValidator, snapshot(), globalConfig(), false), "invalid_snapshot")
local hostileValidator = SkillsViewModel.create({
    ClientOwnerState = { validate = function() return { ok = true, snapshot = { sequence = 1 } } end },
    Allotment = Allotment,
}).model
expectFailure(build(hostileValidator, snapshot(), globalConfig(), false), "invalid_snapshot")

local function rejectEvaluator(evaluator)
    local hostile = SkillsViewModel.create({
        ClientOwnerState = ClientOwnerState,
        Allotment = { evaluate = evaluator },
    }).model
    expectFailure(build(hostile, snapshot(), globalConfig(), false, {
        { perkId = "Cooking", currentLevel = 2, effectiveMaximum = 10 },
    }), "invalid_allotment")
end

rejectEvaluator(function() error("boom") end)
rejectEvaluator(function() return { ok = false, code = "no" } end)
rejectEvaluator(function()
    return {
        ok = true,
        allowed = true,
        spendingEnabled = true,
        mode = "Global",
        bypassed = false,
        activeCount = 5,
        limit = 5,
        private = true,
    }
end)
rejectEvaluator(function()
    return {
        ok = true,
        allowed = true,
        spendingEnabled = true,
        mode = "Free",
        bypassed = false,
        activeCount = 5,
        limit = 5,
    }
end)
rejectEvaluator(function()
    return {
        ok = true,
        allowed = true,
        spendingEnabled = true,
        mode = "Global",
        bypassed = true,
        activeCount = 5,
        limit = 5,
    }
end)
rejectEvaluator(function()
    return {
        ok = true,
        allowed = true,
        spendingEnabled = true,
        mode = "Global",
        bypassed = false,
        activeCount = 99,
        limit = 5,
    }
end)

local mutatingAllotment = SkillsViewModel.create({
    ClientOwnerState = ClientOwnerState,
    Allotment = {
        evaluate = function(config, perkId, activeByPerk, addsTarget)
            local result = Allotment.evaluate(config, perkId, activeByPerk, addsTarget)
            config.globalLimit = 99
            activeByPerk.Hidden = 99
            return result
        end,
    },
}).model
local mutationSafe = build(mutatingAllotment, snapshot(), globalConfig(), false, {
    { perkId = "Axe", currentLevel = 3, effectiveMaximum = 10 },
    { perkId = "Cooking", currentLevel = 2, effectiveMaximum = 10 },
})
expectEqual(mutationSafe.ok, true, "dependency input mutation is isolated per call")
expectEqual(mutationSafe.view.allotment.limit, 5, "dependency cannot mutate output limit")
expectEqual(mutationSafe.view.rows.Axe.enabled, true, "first result remains valid")
expectEqual(mutationSafe.view.rows.Cooking.reasonCode, "allotment_capacity", "later row sees original active map")

local reasonAllowlist = {
    pending = true,
    maximum_mismatch = true,
    at_maximum = true,
    red_recovery = true,
    insufficient_ap = true,
    allotment_disabled = true,
    allotment_capacity = true,
}
for _, candidate in pairs({ view, pending.view, perSkill.view, lowAp.view }) do
    for _, row in pairs(candidate.rows) do
        if row.reasonCode ~= nil then
            expectEqual(reasonAllowlist[row.reasonCode], true, "reason is a stable machine code")
            expectEqual(string.find(row.reasonCode, ";", 1, true), nil, "reason contains no semicolon")
        end
    end
end

return assertions
