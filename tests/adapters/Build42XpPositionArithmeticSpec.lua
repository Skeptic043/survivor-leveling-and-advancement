local Adapter = Build42XpPositionArithmetic
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

local FLOAT_MAX = 3.4028234663852886e38

local function buildWithClamp(clampFloat)
    return Adapter.create({
        environment = {
            globals = {
                PZMath = {
                    clampFloat = clampFloat,
                },
            },
        },
    })
end

local function assertRoutedMovement(positionAfter, eventAmount, expectedArgument, expectedBefore, message)
    local calls = 0
    local observedValue = nil
    local observedMinimum = nil
    local observedMaximum = nil
    local built = buildWithClamp(function(value, minimum, maximum)
        calls = calls + 1
        observedValue = value
        observedMinimum = minimum
        observedMaximum = maximum
        return expectedBefore
    end)
    assertTrue(built.ok, message .. " should create")
    local result = built.arithmetic.previous(positionAfter, eventAmount)
    assertTrue(result.ok, message .. " should reconstruct")
    assertEqual(result.positionBefore, expectedBefore, message .. " should return the exact routed value")
    assertEqual(calls, 1, message .. " should call clampFloat exactly once")
    assertEqual(observedValue, expectedArgument, message .. " should route the exact subtraction")
    assertEqual(observedMinimum, -FLOAT_MAX, message .. " should route the exact lower bound")
    assertEqual(observedMaximum, FLOAT_MAX, message .. " should route the exact upper bound")
end

local created = buildWithClamp(function(value)
    return value
end)
assertTrue(created.ok, "complete capability should create")
local description = created.arithmetic.describe()
assertTrue(description.ok, "description should succeed")
assertEqual(description.adapterId, "sla.pz42-xp-position", "adapter ID should be stable")
assertEqual(description.adapterVersion, 1, "adapter version should be stable")
assertEqual(description.representation, "java-binary32", "representation should be stable")

assertRoutedMovement(
    100.09999847412109,
    0.10000000149011612,
    99.99999847263098,
    100,
    "100f plus 0.1f"
)
assertRoutedMovement(
    100.19999694824219,
    0.10000000149011612,
    100.09999694675207,
    100.09999847412109,
    "second consecutive 0.1f award"
)
assertRoutedMovement(
    100.29999542236328,
    0.10000000149011612,
    100.19999542087317,
    100.19999694824219,
    "third consecutive 0.1f award"
)
assertRoutedMovement(
    0.10000000149011612,
    0.10000000149011612,
    0,
    0,
    "zero-origin movement"
)
assertRoutedMovement(
    100,
    0.0500030517578125,
    99.94999694824219,
    99.94999694824219,
    "cap-adjusted movement"
)

assertFailure(Adapter.create(nil), "invalid-dependencies", "nil dependencies should fail")
assertFailure(Adapter.create({}), "invalid-dependencies", "missing environment should fail")
assertFailure(Adapter.create({ environment = {} }), "invalid-dependencies", "missing globals should fail")
assertFailure(
    Adapter.create({ environment = { globals = {} } }),
    "missing-capability",
    "missing PZMath should fail"
)
assertFailure(
    Adapter.create({ environment = { globals = { PZMath = true } } }),
    "missing-capability",
    "malformed PZMath should fail"
)
assertFailure(
    Adapter.create({ environment = { globals = { PZMath = {} } } }),
    "missing-capability",
    "missing clampFloat should fail"
)
assertFailure(
    Adapter.create({ environment = { globals = { PZMath = { clampFloat = true } } } }),
    "missing-capability",
    "non-callable clampFloat should fail"
)

local inputCalls = 0
local inputBuilt = buildWithClamp(function(value)
    inputCalls = inputCalls + 1
    return value
end)
assertFailure(inputBuilt.arithmetic.previous(nil, 1), "invalid-position-after", "nil position should fail")
assertFailure(inputBuilt.arithmetic.previous("1", 1), "invalid-position-after", "nonnumeric position should fail")
assertFailure(inputBuilt.arithmetic.previous(-1, 1), "invalid-position-after", "negative position should fail")
assertFailure(inputBuilt.arithmetic.previous(0 / 0, 1), "invalid-position-after", "NaN position should fail")
assertFailure(inputBuilt.arithmetic.previous(math.huge, 1), "invalid-position-after", "infinite position should fail")
assertFailure(inputBuilt.arithmetic.previous(1, nil), "invalid-event-amount", "nil amount should fail")
assertFailure(inputBuilt.arithmetic.previous(1, "1"), "invalid-event-amount", "nonnumeric amount should fail")
assertFailure(inputBuilt.arithmetic.previous(1, 0), "invalid-event-amount", "zero amount should fail")
assertFailure(inputBuilt.arithmetic.previous(1, -1), "invalid-event-amount", "negative amount should fail")
assertFailure(inputBuilt.arithmetic.previous(1, 0 / 0), "invalid-event-amount", "NaN amount should fail")
assertFailure(inputBuilt.arithmetic.previous(1, math.huge), "invalid-event-amount", "infinite amount should fail")
assertEqual(inputCalls, 0, "invalid inputs should not call clampFloat")

local throwingCalls = 0
local throwing = buildWithClamp(function()
    throwingCalls = throwingCalls + 1
    error("mock clamp failure")
end)
assertFailure(throwing.arithmetic.previous(1, 0.5), "capability-error", "throwing capability should fail")
assertEqual(throwingCalls, 1, "throwing capability should be invoked exactly once")

local invalidResults = {
    { value = nil, label = "nil result" },
    { value = "0", label = "nonnumeric result" },
    { value = 0 / 0, label = "NaN result" },
    { value = math.huge, label = "infinite result" },
    { value = -1, label = "negative result" },
    { value = 2, label = "result above positionAfter" },
}
for _, fixture in ipairs(invalidResults) do
    local calls = 0
    local built = buildWithClamp(function()
        calls = calls + 1
        return fixture.value
    end)
    assertFailure(built.arithmetic.previous(1, 0.5), "invalid-result", fixture.label .. " should fail")
    assertEqual(calls, 1, fixture.label .. " should call clampFloat exactly once")
end

local stationaryCalls = 0
local stationary = buildWithClamp(function(value, minimum, maximum)
    stationaryCalls = stationaryCalls + 1
    assertEqual(value, 33554431, "small large-position award should route exact subtraction")
    assertEqual(minimum, -FLOAT_MAX, "stationary case should route exact lower bound")
    assertEqual(maximum, FLOAT_MAX, "stationary case should route exact upper bound")
    return 33554432
end)
assertFailure(
    stationary.arithmetic.previous(33554432, 1),
    "no-representable-movement",
    "amount too small to move a large stored float should fail"
)
assertEqual(stationaryCalls, 1, "stationary reconstruction should call clampFloat exactly once")

return assertions
