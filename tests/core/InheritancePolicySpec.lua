local Policy = InheritancePolicy
local assertions = 0

local function yes(value, message)
    assertions = assertions + 1
    if not value then error(message, 2) end
end

local function eq(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local function input(status, enabled, ratio, level, token)
    return {
        initializationStatus = status,
        enabled = enabled,
        retainedRatio = ratio,
        pendingDeadLevel = level,
        tokenStatus = token,
    }
end

local existing = Policy.plan(input("existing", true, 0.5, 20, "valid"))
yes(existing.ok, "existing initialization succeeds")
eq(existing.outcome, "existing", "existing outcome")
eq(existing.consumePending, false, "existing never consumes")
eq(existing.survivorLevel, 0, "existing grants nothing")

local fresh = Policy.plan(input("fresh_unmarked", true, 1, 20, "valid"))
eq(fresh.outcome, "fresh", "fresh-unmarked initializes fresh")
eq(fresh.consumePending, false, "fresh-unmarked never consumes")

local noToken = Policy.plan(input("genuine_new", true, 1, 20, "absent"))
eq(noToken.outcome, "fresh", "missing token initializes fresh")
eq(noToken.consumePending, false, "missing token never consumes")

local disabled = Policy.plan(input("genuine_new", false, 1, 20, "valid"))
eq(disabled.outcome, "fresh", "disabled initializes fresh")
eq(disabled.consumePending, false, "disabled never consumes")

local noPending = Policy.plan(input("genuine_new", true, 1, nil, "valid"))
eq(noPending.outcome, "fresh", "no pending initializes fresh")
eq(noPending.consumePending, false, "no pending never consumes")

local ratios = {
    { ratio = 0, expected = 0 },
    { ratio = 0.5, expected = 5 },
    { ratio = 0.8, expected = 8 },
    { ratio = 1, expected = 10 },
}
for index = 1, #ratios do
    local item = ratios[index]
    local planned = Policy.plan(input("genuine_new", true, item.ratio, 10, "valid"))
    eq(planned.outcome, "inherit", "valid genuine-new plans inheritance")
    eq(planned.consumePending, true, "valid genuine-new consumes")
    eq(planned.survivorLevel, item.expected, "retained ratio boundary")
end
eq(Policy.plan(input("genuine_new", true, 0.5, 9, "valid")).survivorLevel, 4, "retained level floors")
local zero = Policy.plan(input("genuine_new", true, 0.8, 0, "valid"))
eq(zero.survivorLevel, 0, "zero dead level remains zero")
eq(zero.consumePending, true, "valid zero-level record is still one-use")

local maximumSafe = 9007199254740991
local maximumPlan = Policy.plan(input("genuine_new", true, 1, maximumSafe, "valid"))
yes(maximumPlan.ok, "maximum safe pending level is accepted")
eq(maximumPlan.survivorLevel, maximumSafe, "maximum safe survivor level remains exact")
eq(Policy.plan(input("genuine_new", true, 1, 9007199254740992, "valid")).code, "invalid_input",
    "just-over-safe pending level is rejected")
eq(Policy.plan(input("genuine_new", true, 0, 1e300, "valid")).code, "invalid_input",
    "huge finite pending level is rejected even when retained ratio is zero")

eq(Policy.plan(nil).code, "invalid_input", "nil policy input fails closed")
local malformed = {
    "bad",
    setmetatable(input("genuine_new", true, 0.5, 1, "valid"), {}),
    input("unknown", true, 0.5, 1, "valid"),
    input("genuine_new", "true", 0.5, 1, "valid"),
    input("genuine_new", true, -0.1, 1, "valid"),
    input("genuine_new", true, 1.1, 1, "valid"),
    input("genuine_new", true, 0 / 0, 1, "valid"),
    input("genuine_new", true, 0.5, -1, "valid"),
    input("genuine_new", true, 0.5, 1.2, "valid"),
    input("genuine_new", true, 0.5, 1, "invalid"),
}
local extra = input("genuine_new", true, 0.5, 1, "valid")
extra.rawPlayer = {}
malformed[#malformed + 1] = extra
for index = 1, #malformed do
    local result = Policy.plan(malformed[index])
    eq(result.ok, false, "malformed policy input fails closed")
    eq(result.code, "invalid_input", "malformed policy result is bounded")
end

local detached = Policy.plan(input("genuine_new", true, 0.5, 12, "valid"))
detached.outcome, detached.survivorLevel = "changed", 99
local repeated = Policy.plan(input("genuine_new", true, 0.5, 12, "valid"))
eq(repeated.outcome, "inherit", "policy outcome is detached")
eq(repeated.survivorLevel, 6, "detached mutation cannot affect later plan")

return assertions
