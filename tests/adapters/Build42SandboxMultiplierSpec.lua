local Adapter = Build42SandboxMultiplier
local assertions = 0

local function fail(message)
    error(message, 2)
end

local function assertEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        fail((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    assertEqual(value, true, message)
end

local function assertFalse(value, message)
    assertEqual(value, false, message)
end

local function assertFailure(result, code, message)
    assertEqual(type(result), "table", (message or code) .. " result")
    assertFalse(result.ok, message or code)
    assertEqual(result.code, code, message or code)
    assertTrue(type(result.detail) == "string" and result.detail ~= "", (message or code) .. " detail")
end

local function makeFixture(overrides)
    overrides = overrides or {}
    local state = {
        globalMode = overrides.globalMode,
        globalValue = overrides.globalValue,
        perkValue = overrides.perkValue,
        perkName = overrides.perkName,
        optionRequests = {},
        clampCalls = {},
        parseCalls = {},
    }
    if state.globalMode == nil then state.globalMode = true end
    if state.globalValue == nil then state.globalValue = 1.5 end
    if state.perkValue == nil then state.perkValue = "2.25" end

    local configOption = {
        getName = function()
            return state.perkName or state.optionRequests[#state.optionRequests]
        end,
        getValueAsString = function()
            return state.perkValue
        end,
    }
    if overrides.configOption then configOption = overrides.configOption end
    local option = {
        asConfigOption = function()
            return configOption
        end,
    }
    if overrides.option then option = overrides.option end

    local sandbox = {
        multipliersConfig = {
            xpMultiplierGlobalToggle = {
                getValue = function()
                    return state.globalMode
                end,
            },
            xpMultiplierGlobal = {
                getValue = function()
                    return state.globalValue
                end,
            },
        },
        getOptionByName = function(_, name)
            state.optionRequests[#state.optionRequests + 1] = name
            return option
        end,
    }
    if overrides.sandbox then sandbox = overrides.sandbox end

    local mathApi = {
        clampFloat = function(value, minimum, maximum)
            state.clampCalls[#state.clampCalls + 1] = {
                value = value,
                minimum = minimum,
                maximum = maximum,
            }
            return value
        end,
        tryParseFloat = function(encoded, fallback)
            state.parseCalls[#state.parseCalls + 1] = {
                encoded = encoded,
                fallback = fallback,
            }
            return tonumber(encoded) or fallback
        end,
    }
    if overrides.mathApi then mathApi = overrides.mathApi end

    local dependencies = {
        SandboxOptions = sandbox,
        PZMath = mathApi,
    }
    if overrides.dependencies then dependencies = overrides.dependencies end

    local created = Adapter.create(dependencies)
    return {
        created = created,
        state = state,
        dependencies = dependencies,
        sandbox = sandbox,
        option = option,
        configOption = configOption,
        mathApi = mathApi,
    }
end

assertFailure(Adapter.create(nil), "invalid-dependencies", "nil dependencies")
assertFailure(Adapter.create({}), "invalid-dependencies", "empty dependencies")

do
    local fixture = makeFixture({ globalValue = 1.25 })
    assertTrue(fixture.created.ok, "complete fixture creates")
    local result = fixture.created.resolver.resolve({}, "Carpentry")
    assertTrue(result.ok, "global resolves")
    assertEqual(result.multiplier, 1.25, "global result")
    assertEqual(#fixture.state.clampCalls, 1, "global clamp count")
    assertEqual(fixture.state.clampCalls[1].value, 1.25, "global clamp value")
    assertEqual(fixture.state.clampCalls[1].minimum, 1.25, "global clamp lower bound")
    assertEqual(fixture.state.clampCalls[1].maximum, 1.25, "global clamp upper bound")
    assertEqual(#fixture.state.optionRequests, 0, "global does not look up a perk option")
    assertEqual(#fixture.state.parseCalls, 0, "global does not parse a perk option")

    fixture.state.globalValue = 3.5
    result = fixture.created.resolver.resolve({}, "Carpentry")
    assertTrue(result.ok, "changed global resolves")
    assertEqual(result.multiplier, 3.5, "changed global value is live")
    assertEqual(#fixture.state.clampCalls, 2, "changed global routes once more")
end

do
    local fixture = makeFixture({ globalMode = false, perkValue = "0.75" })
    local result = fixture.created.resolver.resolve({}, "SmallBlade")
    assertTrue(result.ok, "per-skill resolves")
    assertEqual(result.multiplier, 0.75, "per-skill value")
    assertEqual(#fixture.state.optionRequests, 1, "one per-skill lookup")
    assertEqual(fixture.state.optionRequests[1], "MultiplierConfig.SmallBlade", "dynamic per-skill option identity")
    assertEqual(#fixture.state.parseCalls, 1, "one per-skill parse")
    assertEqual(fixture.state.parseCalls[1].encoded, "0.75", "per-skill parse source")
    assertEqual(fixture.state.parseCalls[1].fallback, -1, "per-skill parse fallback")
    assertEqual(#fixture.state.clampCalls, 0, "per-skill path does not clamp")

    result = fixture.created.resolver.resolve({}, "Custom.Skill:Tier-2")
    assertTrue(result.ok, "safe dynamic punctuation resolves")
    assertEqual(
        fixture.state.optionRequests[2],
        "MultiplierConfig.Custom.Skill:Tier-2",
        "safe dynamic punctuation keeps its exact option identity"
    )

    fixture.state.perkValue = "1.75"
    result = fixture.created.resolver.resolve({}, "SmallBlade")
    assertTrue(result.ok, "changed per-skill resolves")
    assertEqual(result.multiplier, 1.75, "changed per-skill value is live")
    assertEqual(#fixture.state.optionRequests, 3, "changed per-skill repeats lookup")
    assertEqual(#fixture.state.parseCalls, 3, "changed per-skill repeats parse")
end

do
    local fixture = makeFixture({ globalMode = false, perkName = "MultiplierConfig.OtherSkill" })
    local result = fixture.created.resolver.resolve({}, "Axe")
    assertFailure(result, "invalid-perk-option", "mismatched option identity")

    fixture = makeFixture({ globalMode = false })
    fixture.option.getName = function()
        error("direct option name must not be used")
    end
    fixture.option.getValueAsString = function()
        error("direct option value must not be used")
    end
    result = fixture.created.resolver.resolve({}, "Axe")
    assertTrue(result.ok, "config option seam is used instead of direct option methods")

    fixture = makeFixture({ globalMode = false })
    fixture.option.asConfigOption = function()
        error("config option failure")
    end
    result = fixture.created.resolver.resolve({}, "Axe")
    assertFailure(result, "capability.perk-option", "throwing config option conversion")

    local unsafe = { "", "Axe/Other", "Axe Thing", "Axe*Thing", 12, nil }
    for index, perkId in ipairs(unsafe) do
        result = fixture.created.resolver.resolve({}, perkId)
        assertFailure(result, "invalid-perk-id", "unsafe perk id " .. tostring(index))
    end
    result = fixture.created.resolver.resolve({}, nil)
    assertFailure(result, "invalid-perk-id", "nil perk id")
    assertEqual(#fixture.state.optionRequests, 1, "unsafe IDs do not look up options")
end

do
    local fixture = makeFixture({ globalMode = true })
    local player = setmetatable({}, {
        __index = function()
            error("player must not be inspected")
        end,
    })
    local result = fixture.created.resolver.resolve(player, "Aiming")
    assertTrue(result.ok, "player argument remains opaque")
end

do
    local globalInvalid = { 0, -1, 0 / 0, math.huge, -math.huge, "1" }
    for index, value in ipairs(globalInvalid) do
        local fixture = makeFixture({ globalValue = value })
        local result = fixture.created.resolver.resolve({}, "Carpentry")
        assertFailure(result, "invalid-global-multiplier", "invalid global " .. tostring(index))
        assertEqual(#fixture.state.clampCalls, 0, "invalid global avoids clamp " .. tostring(index))
    end

    local perkInvalid = { "0", "-1", "bad" }
    for index, value in ipairs(perkInvalid) do
        local fixture = makeFixture({ globalMode = false, perkValue = value })
        local result = fixture.created.resolver.resolve({}, "Carpentry")
        assertFailure(result, "invalid-perk-multiplier", "invalid per-skill " .. tostring(index))
    end
end

do
    local fixture = makeFixture({ globalMode = "true" })
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "nonboolean toggle")

    fixture = makeFixture()
    fixture.sandbox.multipliersConfig.xpMultiplierGlobalToggle.getValue = function()
        error("toggle failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "throwing toggle")

    fixture = makeFixture()
    fixture.sandbox.multipliersConfig.xpMultiplierGlobal.getValue = function()
        error("value failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-global-multiplier", "throwing global value")

    fixture = makeFixture()
    fixture.mathApi.clampFloat = function()
        error("clamp failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-global-multiplier", "throwing clamp")
end

do
    local fixture = makeFixture({ globalMode = false })
    fixture.sandbox.getOptionByName = function()
        error("option failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.perk-option", "throwing lookup")

    fixture = makeFixture({ globalMode = false })
    fixture.configOption.getName = function()
        error("name failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-perk-option", "throwing option name")

    fixture = makeFixture({ globalMode = false })
    fixture.configOption.getValueAsString = function()
        error("value failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-perk-option", "throwing per-skill value")

    fixture = makeFixture({ globalMode = false })
    fixture.mathApi.tryParseFloat = function()
        error("parse failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-perk-multiplier", "throwing parse")
end

do
    local fixture = makeFixture()
    fixture.dependencies.SandboxOptions = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.sandbox-options", "missing live SandboxOptions")

    fixture = makeFixture()
    fixture.sandbox.multipliersConfig = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.multipliers-config", "missing live config")

    fixture = makeFixture()
    fixture.sandbox.multipliersConfig.xpMultiplierGlobalToggle = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "missing live toggle")

    fixture = makeFixture()
    fixture.dependencies.PZMath = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.pz-math", "missing live math")

    fixture = makeFixture({ globalMode = false })
    fixture.sandbox.getOptionByName = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.perk-option", "missing live option lookup")
end

do
    local fixture = makeFixture()
    fixture.mathApi.clampFloat = function()
        return 0
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-global-multiplier", "zero clamp result")

    fixture = makeFixture({ globalMode = false })
    fixture.mathApi.tryParseFloat = function()
        return math.huge
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-perk-multiplier", "nonfinite parsed result")
end

return assertions
