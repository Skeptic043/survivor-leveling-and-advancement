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

local function assertRoutedTransition(
    positionBefore,
    eventAmount,
    expectedArgument,
    expectedAfter,
    expectedMoved,
    message
)
    local calls = 0
    local observedValue = nil
    local observedMinimum = nil
    local observedMaximum = nil
    local built = buildWithClamp(function(value, minimum, maximum)
        calls = calls + 1
        observedValue = value
        observedMinimum = minimum
        observedMaximum = maximum
        return expectedAfter
    end)
    assertTrue(built.ok, message .. " should create")
    local result = built.arithmetic.add(positionBefore, eventAmount)
    assertTrue(result.ok, message .. " should evaluate")
    assertEqual(result.positionAfter, expectedAfter, message .. " should return the exact routed value")
    assertEqual(result.moved, expectedMoved, message .. " should report movement")
    assertEqual(calls, 1, message .. " should call clampFloat exactly once")
    assertEqual(observedValue, expectedArgument, message .. " should route the exact addition")
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
assertEqual(description.adapterVersion, 2, "adapter version should be stable")
assertEqual(description.representation, "java-binary32", "representation should be stable")
assertEqual(created.arithmetic.previous, nil, "obsolete reverse interface should be absent")

assertRoutedTransition(
    100,
    0.10000000149011612,
    100.10000000149012,
    100.09999847412109,
    true,
    "100f plus 0.1f"
)
assertRoutedTransition(
    100.09999847412109,
    0.10000000149011612,
    100.19999847561121,
    100.19999694824219,
    true,
    "second consecutive 0.1f award"
)
assertRoutedTransition(
    100.09999847412109,
    -0.10000000149011612,
    99.99999847263098,
    100,
    true,
    "negative 0.1f transition"
)
assertRoutedTransition(
    0,
    0.10000000149011612,
    0.10000000149011612,
    0.10000000149011612,
    true,
    "zero-origin movement"
)
assertRoutedTransition(42, 0, 42, 42, false, "zero award")
assertRoutedTransition(33554432, 1, 33554433, 33554432, false, "sub-ULP award")

-- Both valid prior floats reach the same result, so reverse subtraction is ambiguous.
assertRoutedTransition(16777215, 1, 16777216, 16777216, true, "lower ambiguous prior")
assertRoutedTransition(16777216, 1, 16777217, 16777216, false, "upper ambiguous prior")

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
assertFailure(inputBuilt.arithmetic.add(nil, 1), "invalid-position-before", "nil position should fail")
assertFailure(inputBuilt.arithmetic.add("1", 1), "invalid-position-before", "nonnumeric position should fail")
assertFailure(inputBuilt.arithmetic.add(-1, 1), "invalid-position-before", "negative position should fail")
assertFailure(inputBuilt.arithmetic.add(0 / 0, 1), "invalid-position-before", "NaN position should fail")
assertFailure(inputBuilt.arithmetic.add(math.huge, 1), "invalid-position-before", "infinite position should fail")
assertFailure(inputBuilt.arithmetic.add(1, nil), "invalid-event-amount", "nil amount should fail")
assertFailure(inputBuilt.arithmetic.add(1, "1"), "invalid-event-amount", "nonnumeric amount should fail")
assertFailure(inputBuilt.arithmetic.add(1, 0 / 0), "invalid-event-amount", "NaN amount should fail")
assertFailure(inputBuilt.arithmetic.add(1, math.huge), "invalid-event-amount", "infinite amount should fail")
assertFailure(inputBuilt.arithmetic.add(1, -math.huge), "invalid-event-amount", "negative infinity should fail")
assertEqual(inputCalls, 0, "invalid inputs should not call clampFloat")

local throwingCalls = 0
local throwing = buildWithClamp(function()
    throwingCalls = throwingCalls + 1
    error("mock clamp failure")
end)
assertFailure(throwing.arithmetic.add(1, -0.5), "capability-error", "throwing capability should fail")
assertEqual(throwingCalls, 1, "throwing capability should be invoked exactly once")

local negativeResult = buildWithClamp(function(value)
    assertEqual(value, -0.25, "negative transition should route the exact addition")
    return value
end)
assertFailure(
    negativeResult.arithmetic.add(0.25, -0.5),
    "invalid-result",
    "negative resulting position should fail"
)

local invalidResults = {
    { value = nil, label = "nil result" },
    { value = "0", label = "nonnumeric result" },
    { value = 0 / 0, label = "NaN result" },
    { value = math.huge, label = "infinite result" },
    { value = -1, label = "negative result" },
    { value = FLOAT_MAX * 2, label = "out-of-range finite result" },
}
for _, fixture in ipairs(invalidResults) do
    local calls = 0
    local built = buildWithClamp(function()
        calls = calls + 1
        return fixture.value
    end)
    assertFailure(built.arithmetic.add(1, 0.5), "invalid-result", fixture.label .. " should fail")
    assertEqual(calls, 1, fixture.label .. " should call clampFloat exactly once")
end

return assertions
