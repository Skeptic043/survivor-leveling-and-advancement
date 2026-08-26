local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message or "assertion failed") end
end

local function expectEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual))) end
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

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function exactFields(value, expected)
    local count = 0
    for key in pairs(value) do
        if not expected[key] then return false end
        count = count + 1
    end
    local expectedCount = 0
    for key in pairs(expected) do
        expectedCount = expectedCount + 1
        if value[key] == nil then return false end
    end
    return count == expectedCount
end

local function validSnapshot(sequence, revision, ready)
    return {
        protocolVersion = 1,
        ready = ready == nil and true or ready,
        sequence = sequence or 10,
        revision = revision or 4,
        survivor = {
            level = 5,
            xpIntoLevel = 12.5,
            xpForNextLevel = 2700,
            spent = 2,
            availableAp = 3,
        },
        perks = {
            Axe = {
                effectiveMaximum = 10,
                naturalPosition = 3.25,
                highWaterPosition = 4,
                activeTargets = {
                    { targetLevel = 5, targetPosition = 5.5 },
                    { targetLevel = 7, targetPosition = 8.75 },
                },
            },
            ["Long_Blade.v2:test-1"] = {
                effectiveMaximum = 8,
                naturalPosition = 1,
                highWaterPosition = 1,
                activeTargets = {},
            },
        },
    }
end

local function expectFailure(result, code, detail)
    expectEqual(result.ok, false, "failure expected")
    expectEqual(result.code, code, "failure code: expected " .. code .. ", got " .. tostring(result.code))
    expectEqual(result.detail, detail, "bounded failure detail: expected " .. detail .. ", got " .. tostring(result.detail))
    expectEqual(result.accepted, nil, "failure does not claim acceptance")
    expectEqual(result.snapshot, nil, "failure does not expose a snapshot")
end

local function acceptedSnapshot(state)
    local result = state.get()
    expectEqual(result.ok, true, "get succeeds")
    expectEqual(result.present, true, "snapshot is present")
    return result.snapshot
end

local validationInput = validSnapshot(7, 3, false)
local validated = ClientOwnerState.validate(validationInput)
expectEqual(validated.ok, true, "stateless validation succeeds")
expect(exactFields(validated, { ok = true, snapshot = true }), "stateless validation result shape")
expect(sameShape(validated.snapshot, validationInput), "stateless validation preserves the exact snapshot")
expect(validated.snapshot ~= validationInput, "stateless validation detaches the root")
expect(validated.snapshot.survivor ~= validationInput.survivor, "stateless validation detaches survivor")
expect(validated.snapshot.perks ~= validationInput.perks, "stateless validation detaches perk map")
expect(validated.snapshot.perks.Axe ~= validationInput.perks.Axe, "stateless validation detaches perk records")
expect(validated.snapshot.perks.Axe.activeTargets ~= validationInput.perks.Axe.activeTargets, "stateless validation detaches target arrays")
expect(validated.snapshot.perks.Axe.activeTargets[1] ~= validationInput.perks.Axe.activeTargets[1], "stateless validation detaches targets")
validationInput.survivor.level = 99
validationInput.perks.Axe.activeTargets[1].targetPosition = 99
expectEqual(validated.snapshot.survivor.level, 5, "validated copy ignores later input mutation")
expectEqual(validated.snapshot.perks.Axe.activeTargets[1].targetPosition, 5.5, "validated nested copy ignores later input mutation")
validated.snapshot.survivor.spent = 5
expectEqual(validationInput.survivor.spent, 2, "validated output mutation does not reach input")
local invalidValidation = validSnapshot(8)
invalidValidation.privateRoot = true
expectFailure(ClientOwnerState.validate(invalidValidation), "invalid_snapshot", "fields")

local originalValidate = ClientOwnerState.validate
local validationCalls = 0
ClientOwnerState.validate = function(value)
    validationCalls = validationCalls + 1
    return originalValidate(value)
end
local reuseState = ClientOwnerState.create().state
expectEqual(reuseState.accept(validSnapshot(1)).accepted, true, "accept succeeds through public validator")
expectEqual(validationCalls, 1, "accept reuses public stateless validator exactly once")
ClientOwnerState.validate = originalValidate

local created = ClientOwnerState.create()
expectEqual(created.ok, true, "create succeeds")
expect(exactFields(created, { ok = true, state = true }), "create result shape")
local state = created.state
expectEqual(type(state.accept), "function", "accept is public")
expectEqual(type(state.get), "function", "get is public")
expectEqual(type(state.reset), "function", "reset is public")
expectEqual(type(state.status), "function", "status is public")

local empty = state.get()
expect(sameShape(empty, { ok = true, present = false }), "get reports absence before acceptance")
local emptyStatus = state.status()
expect(sameShape(emptyStatus, { ok = true, present = false }), "status reports only absence before acceptance")

local input = validSnapshot()
local accepted = state.accept(input)
expect(sameShape(accepted, { ok = true, accepted = true }), "valid snapshot is accepted")
local stored = acceptedSnapshot(state)
expect(sameShape(stored, validSnapshot()), "the complete D-060 shape is preserved")
expect(exactFields(stored, { protocolVersion = true, ready = true, sequence = true, revision = true, survivor = true, perks = true }), "root allowlist is exact")
expect(exactFields(stored.survivor, { level = true, xpIntoLevel = true, xpForNextLevel = true, spent = true, availableAp = true }), "survivor allowlist is exact")
expect(exactFields(stored.perks.Axe, { effectiveMaximum = true, naturalPosition = true, highWaterPosition = true, activeTargets = true }), "perk allowlist is exact")
expect(exactFields(stored.perks.Axe.activeTargets[1], { targetLevel = true, targetPosition = true }), "target allowlist is exact")
expectEqual(stored.perks.Axe.activeTargets[1].targetLevel, 5, "target order is preserved")
expectEqual(stored.perks.Axe.activeTargets[2].targetLevel, 7, "later target order is preserved")

input.ready = false
input.survivor.level = 99
input.perks.Axe.naturalPosition = 99
input.perks.Axe.activeTargets[1].targetPosition = 99
input.perks.NewPerk = input.perks.Axe
stored = acceptedSnapshot(state)
expectEqual(stored.ready, true, "accepted readiness is detached from input")
expectEqual(stored.survivor.level, 5, "accepted survivor is detached from input")
expectEqual(stored.perks.Axe.naturalPosition, 3.25, "accepted perk is detached from input")
expectEqual(stored.perks.Axe.activeTargets[1].targetPosition, 5.5, "accepted target is detached from input")
expectEqual(stored.perks.NewPerk, nil, "accepted perk map is detached from input")

stored.survivor.spent = 5
stored.perks.Axe.highWaterPosition = 99
stored.perks.Axe.activeTargets[1].targetLevel = 10
stored.perks.Leaked = {}
local secondRead = acceptedSnapshot(state)
expectEqual(secondRead.survivor.spent, 2, "get detaches survivor")
expectEqual(secondRead.perks.Axe.highWaterPosition, 4, "get detaches perk")
expectEqual(secondRead.perks.Axe.activeTargets[1].targetLevel, 5, "get detaches target")
expectEqual(secondRead.perks.Leaked, nil, "get detaches perk map")

local newer = validSnapshot(11, 5, false)
newer.survivor.level = 6
newer.survivor.spent = 3
newer.survivor.availableAp = 3
expect(sameShape(state.accept(newer), { ok = true, accepted = true }), "strictly newer sequence replaces")
expectEqual(acceptedSnapshot(state).sequence, 11, "newer sequence is stored")
expectEqual(acceptedSnapshot(state).ready, false, "newer readiness is stored")

local equal = validSnapshot(11, 999, true)
equal.survivor.level = 7
equal.survivor.spent = 0
equal.survivor.availableAp = 7
expect(sameShape(state.accept(equal), { ok = true, accepted = false, code = "stale_snapshot" }), "equal sequence is ignored")
local older = validSnapshot(2, 1000, true)
expect(sameShape(state.accept(older), { ok = true, accepted = false, code = "stale_snapshot" }), "older sequence is ignored")
expectEqual(acceptedSnapshot(state).sequence, 11, "stale snapshots do not replace")
expectEqual(acceptedSnapshot(state).revision, 5, "stale revision does not replace")

local malformedNewer = validSnapshot(12, 6, true)
malformedNewer.survivor.availableAp = 4
expectFailure(state.accept(malformedNewer), "invalid_survivor", "values")
expectEqual(acceptedSnapshot(state).sequence, 11, "malformed newer snapshot does not mutate")
local malformedOlder = validSnapshot(1, 0, true)
malformedOlder.extra = true
expectFailure(state.accept(malformedOlder), "invalid_snapshot", "fields")
expectEqual(acceptedSnapshot(state).sequence, 11, "malformed older input is validated and does not mutate")

local wrongProtocol = validSnapshot(12)
wrongProtocol.protocolVersion = 2
expectFailure(state.accept(wrongProtocol), "protocol_mismatch", "protocol_version")
expectEqual(acceptedSnapshot(state).sequence, 11, "protocol mismatch does not mutate")

local status = state.status()
expect(sameShape(status, { ok = true, present = true, ready = false, sequence = 11, revision = 5 }), "status exposes only owner-state cursors")
expectEqual(status.survivor, nil, "status does not expose survivor state")
expectEqual(status.perks, nil, "status does not expose perk state")

expect(sameShape(state.reset(), { ok = true }), "reset succeeds")
expect(sameShape(state.get(), { ok = true, present = false }), "reset clears snapshot")
expect(sameShape(state.status(), { ok = true, present = false }), "reset clears status")
local newSession = validSnapshot(1, 0, false)
expect(sameShape(state.accept(newSession), { ok = true, accepted = true }), "reset admits a low sequence from a new session")
expectEqual(acceptedSnapshot(state).sequence, 1, "new-session sequence is stored")

local function freshState()
    return ClientOwnerState.create().state
end

local function rejectChanged(mutator, code, detail)
    local inbox = freshState()
    local baseline = validSnapshot(20, 8, true)
    expectEqual(inbox.accept(baseline).accepted, true, "test baseline accepted")
    local candidate = validSnapshot(21, 9, false)
    mutator(candidate)
    expectFailure(inbox.accept(candidate), code, detail)
    local after = inbox.get().snapshot
    expectEqual(after.sequence, 20, "rejection preserves sequence")
    expectEqual(after.revision, 8, "rejection preserves revision")
end

rejectChanged(function(value) value.unknown = true end, "invalid_snapshot", "fields")
rejectChanged(function(value) value.survivor.unknown = true end, "invalid_survivor", "fields")
rejectChanged(function(value) value.perks.Axe.unknown = true end, "invalid_perk", "fields")
rejectChanged(function(value) value.perks.Axe.activeTargets[1].unknown = true end, "invalid_target", "fields")
rejectChanged(function(value) value.perks.Axe.activeTargets.label = true end, "invalid_targets", "array_shape")
rejectChanged(function(value)
    value.perks.Axe.activeTargets[3] = value.perks.Axe.activeTargets[2]
    value.perks.Axe.activeTargets[2] = nil
end, "invalid_targets", "array_shape")

rejectChanged(function(value) setmetatable(value, {}) end, "invalid_snapshot", "metatable")
rejectChanged(function(value) setmetatable(value.survivor, {}) end, "invalid_survivor", "metatable")
rejectChanged(function(value) setmetatable(value.perks, {}) end, "invalid_perks", "metatable")
rejectChanged(function(value) setmetatable(value.perks.Axe, {}) end, "invalid_perk", "metatable")
rejectChanged(function(value) setmetatable(value.perks.Axe.activeTargets, {}) end, "invalid_targets", "metatable")
rejectChanged(function(value) setmetatable(value.perks.Axe.activeTargets[1], {}) end, "invalid_target", "metatable")

rejectChanged(function(value) value.survivor = value end, "invalid_survivor", "cycle")
rejectChanged(function(value) value.perks.Axe = value.perks end, "invalid_perk", "cycle")
rejectChanged(function(value) value.perks.Axe.activeTargets = value.perks.Axe end, "invalid_targets", "cycle")
rejectChanged(function(value) value.perks.Axe.activeTargets[1] = value.perks.Axe.activeTargets end, "invalid_target", "cycle")

rejectChanged(function(value) value.ready = 1 end, "invalid_snapshot", "values")
rejectChanged(function(value) value.sequence = 0 end, "invalid_snapshot", "values")
rejectChanged(function(value) value.sequence = 1.5 end, "invalid_snapshot", "values")
rejectChanged(function(value) value.sequence = math.huge end, "invalid_snapshot", "values")
rejectChanged(function(value) value.revision = -1 end, "invalid_snapshot", "values")
rejectChanged(function(value) value.revision = 0 / 0 end, "invalid_snapshot", "values")

rejectChanged(function(value) value.survivor.level = -1 end, "invalid_survivor", "values")
rejectChanged(function(value) value.survivor.level = 1.5 end, "invalid_survivor", "values")
rejectChanged(function(value) value.survivor.xpIntoLevel = -1 end, "invalid_survivor", "values")
rejectChanged(function(value) value.survivor.xpIntoLevel = math.huge end, "invalid_survivor", "values")
rejectChanged(function(value) value.survivor.xpIntoLevel = value.survivor.xpForNextLevel end, "invalid_survivor", "values")
rejectChanged(function(value) value.survivor.xpForNextLevel = 0 end, "invalid_survivor", "values")
rejectChanged(function(value) value.survivor.xpForNextLevel = 1.25 end, "invalid_survivor", "values")
rejectChanged(function(value) value.survivor.spent = value.survivor.level + 1 end, "invalid_survivor", "values")
rejectChanged(function(value) value.survivor.availableAp = value.survivor.availableAp + 1 end, "invalid_survivor", "values")
rejectChanged(function(value) value.survivor.availableAp = 1.5 end, "invalid_survivor", "values")

rejectChanged(function(value) value.perks[""] = value.perks.Axe end, "invalid_perks", "perk_id")
rejectChanged(function(value) value.perks["bad id"] = value.perks.Axe end, "invalid_perks", "perk_id")
rejectChanged(function(value) value.perks[1] = value.perks.Axe end, "invalid_perks", "perk_id")
rejectChanged(function(value) value.perks.Axe.effectiveMaximum = 0 end, "invalid_perk", "values")
rejectChanged(function(value) value.perks.Axe.effectiveMaximum = 10.5 end, "invalid_perk", "values")
rejectChanged(function(value) value.perks.Axe.naturalPosition = -1 end, "invalid_perk", "values")
rejectChanged(function(value) value.perks.Axe.naturalPosition = 0 / 0 end, "invalid_perk", "values")
rejectChanged(function(value) value.perks.Axe.highWaterPosition = value.perks.Axe.naturalPosition - 1 end, "invalid_perk", "values")
rejectChanged(function(value) value.perks.Axe.highWaterPosition = math.huge end, "invalid_perk", "values")

rejectChanged(function(value) value.perks.Axe.activeTargets[1].targetLevel = 0 end, "invalid_target", "values")
rejectChanged(function(value) value.perks.Axe.activeTargets[1].targetLevel = 1.5 end, "invalid_target", "values")
rejectChanged(function(value) value.perks.Axe.activeTargets[1].targetLevel = 11 end, "invalid_target", "values")
rejectChanged(function(value) value.perks.Axe.activeTargets[1].targetPosition = -1 end, "invalid_target", "values")
rejectChanged(function(value) value.perks.Axe.activeTargets[1].targetPosition = math.huge end, "invalid_target", "values")
rejectChanged(function(value) value.perks.Axe.activeTargets[1].targetPosition = value.perks.Axe.highWaterPosition end, "invalid_target", "values")
rejectChanged(function(value) value.perks.Axe.activeTargets[2].targetLevel = value.perks.Axe.activeTargets[1].targetLevel end, "invalid_target", "values")
rejectChanged(function(value) value.perks.Axe.activeTargets[2].targetPosition = value.perks.Axe.activeTargets[1].targetPosition end, "invalid_target", "values")

local noPerks = validSnapshot(22, 10, true)
noPerks.perks = {}
expectEqual(freshState().accept(noPerks).accepted, true, "empty perk map is valid")

return assertions
