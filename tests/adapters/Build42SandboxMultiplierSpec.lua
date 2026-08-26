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
        optionRequests = {},
        clampCalls = {},
        parseCalls = {},
    }
    if state.globalMode == nil then state.globalMode = true end
    if state.globalValue == nil then state.globalValue = 1.5 end
    if state.perkValue == nil then state.perkValue = "2.25" end

    local options = {}
    local function makeOption(name, value, encoded)
        local config = {}
        local option = {}
        config.getName = function(self)
            assertEqual(self, config, name .. " config receiver")
            return name
        end
        config.getValueAsString = function(self)
            assertEqual(self, config, name .. " config value receiver")
            return encoded()
        end
        option.asConfigOption = function(self)
            assertEqual(self, option, name .. " option receiver")
            return config
        end
        option.getValue = function(self)
            assertEqual(self, option, name .. " option value receiver")
            return value()
        end
        return option, config
    end

    local toggle, toggleConfig = makeOption("MultiplierConfig.GlobalToggle", function()
        return state.globalMode
    end, function()
        return "unused"
    end)
    local global, globalConfig = makeOption("MultiplierConfig.Global", function()
        return state.globalValue
    end, function()
        return "unused"
    end)
    local function perkOption(name)
        return makeOption(name, function()
            return "unused"
        end, function()
            return state.perkValue
        end)
    end
    options["MultiplierConfig.GlobalToggle"] = toggle
    options["MultiplierConfig.Global"] = global
    options["MultiplierConfig.Axe"] = perkOption("MultiplierConfig.Axe")

    local sandbox
    sandbox = {
        getOptionByName = function(self, name)
            assertEqual(self, sandbox, "SandboxOptions receiver")
            state.optionRequests[#state.optionRequests + 1] = name
            local option = options[name]
            if option == nil and name:match("^MultiplierConfig%.") then
                option = perkOption(name)
                options[name] = option
            end
            return option
        end,
    }
    setmetatable(sandbox, {
        __index = function(_, key)
            if key == "multipliersConfig" or key == "SandboxVars" then
                error("legacy sandbox seam must not be read")
            end
            return nil
        end,
    })
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

    local dependencies = { SandboxOptions = sandbox, PZMath = mathApi }
    if overrides.dependencies then dependencies = overrides.dependencies end
    local created = Adapter.create(dependencies)
    return {
        created = created,
        state = state,
        dependencies = dependencies,
        sandbox = sandbox,
        options = options,
        toggle = toggle,
        global = global,
        toggleConfig = toggleConfig,
        globalConfig = globalConfig,
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
    assertEqual(#fixture.state.optionRequests, 2, "global named lookup count")
    assertEqual(fixture.state.optionRequests[1], "MultiplierConfig.GlobalToggle", "global toggle name")
    assertEqual(fixture.state.optionRequests[2], "MultiplierConfig.Global", "global value name")
    assertEqual(#fixture.state.clampCalls, 1, "global clamp count")
    assertEqual(fixture.state.clampCalls[1].value, 1.25, "global clamp value")
    assertEqual(fixture.state.clampCalls[1].minimum, 1.25, "global clamp lower bound")
    assertEqual(fixture.state.clampCalls[1].maximum, 1.25, "global clamp upper bound")
    assertEqual(#fixture.state.parseCalls, 0, "global does not parse")

    fixture.state.globalValue = 3.5
    result = fixture.created.resolver.resolve({}, "Carpentry")
    assertTrue(result.ok, "changed global resolves")
    assertEqual(result.multiplier, 3.5, "changed global value is live")
    assertEqual(#fixture.state.optionRequests, 4, "changed global repeats named lookups")
    assertEqual(#fixture.state.clampCalls, 2, "changed global routes once more")
end

do
    local fixture = makeFixture({ globalMode = false, perkValue = "0.75" })
    local result = fixture.created.resolver.resolve({}, "SmallBlade")
    assertTrue(result.ok, "per-skill resolves")
    assertEqual(result.multiplier, 0.75, "per-skill value")
    assertEqual(#fixture.state.optionRequests, 2, "per-skill named lookup count")
    assertEqual(fixture.state.optionRequests[1], "MultiplierConfig.GlobalToggle", "per-skill toggle name")
    assertEqual(fixture.state.optionRequests[2], "MultiplierConfig.SmallBlade", "per-skill option name")
    assertEqual(#fixture.state.parseCalls, 1, "one per-skill parse")
    assertEqual(fixture.state.parseCalls[1].encoded, "0.75", "per-skill parse source")
    assertEqual(fixture.state.parseCalls[1].fallback, -1, "per-skill parse fallback")
    assertEqual(#fixture.state.clampCalls, 0, "per-skill path does not clamp")

    fixture.state.perkValue = "1.75"
    result = fixture.created.resolver.resolve({}, "SmallBlade")
    assertTrue(result.ok, "changed same per-skill resolves")
    assertEqual(result.multiplier, 1.75, "changed per-skill value is live")
    assertEqual(fixture.state.optionRequests[4], "MultiplierConfig.SmallBlade", "same dynamic option identity")
    assertEqual(#fixture.state.parseCalls, 2, "changed per-skill parses once")

    result = fixture.created.resolver.resolve({}, "Custom.Skill:Tier-2")
    assertTrue(result.ok, "safe dynamic punctuation resolves")
    assertEqual(fixture.state.optionRequests[6], "MultiplierConfig.Custom.Skill:Tier-2", "punctuated dynamic option identity")
end

do
    local fixture = makeFixture({ globalMode = false })
    fixture.options["MultiplierConfig.Axe"].asConfigOption = function()
        return { getName = function() return "MultiplierConfig.Other" end }
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.perk-option", "mismatched option identity")

    fixture = makeFixture({ globalMode = false })
    fixture.sandbox.getOptionByName = function()
        error("option failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "throwing named lookup")

    fixture = makeFixture()
    fixture.options["MultiplierConfig.GlobalToggle"].getValue = function()
        error("toggle failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "throwing toggle")

    fixture = makeFixture()
    fixture.options["MultiplierConfig.Global"].getValue = function()
        error("value failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-global-multiplier", "throwing global value")

    fixture = makeFixture()
    fixture.options["MultiplierConfig.GlobalToggle"].getValue = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "missing toggle value")

    fixture = makeFixture()
    fixture.options["MultiplierConfig.Global"].getValue = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-global-multiplier", "missing global value")
end

do
    local fixture = makeFixture({ globalMode = false })
    local axe = fixture.options["MultiplierConfig.Axe"]
    axe.asConfigOption = function()
        error("config conversion failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.perk-option", "throwing config conversion")

    fixture = makeFixture({ globalMode = false })
    fixture.options["MultiplierConfig.Axe"].asConfigOption = function()
        return { getName = function() error("name failure") end }
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.perk-option", "throwing config name")

    fixture = makeFixture({ globalMode = false })
    fixture.options["MultiplierConfig.Axe"].asConfigOption = function()
        return {
            getName = function() return "MultiplierConfig.Axe" end,
            getValueAsString = function() error("encoded value failure") end,
        }
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-perk-option", "throwing encoded value")

    fixture = makeFixture({ globalMode = false })
    fixture.mathApi.tryParseFloat = function()
        error("parse failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-perk-multiplier", "throwing parse")

    fixture = makeFixture({ globalMode = false })
    fixture.options["MultiplierConfig.Axe"].asConfigOption = function()
        return {
            getName = function() return "MultiplierConfig.Axe" end,
            getValueAsString = nil,
        }
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-perk-option", "missing encoded value")
end

do
    local fixture = makeFixture()
    fixture.sandbox.getOptionByName = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "missing named lookup")

    fixture = makeFixture()
    fixture.sandbox.getOptionByName = function()
        return nil
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "nil toggle option")

    fixture = makeFixture()
    local originalLookup = fixture.sandbox.getOptionByName
    fixture.sandbox.getOptionByName = function(self, name)
        if name == "MultiplierConfig.Global" then return nil end
        return originalLookup(self, name)
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-multiplier", "nil global option")

    fixture = makeFixture({ globalMode = false })
    originalLookup = fixture.sandbox.getOptionByName
    fixture.sandbox.getOptionByName = function(self, name)
        if name == "MultiplierConfig.Axe" then return nil end
        return originalLookup(self, name)
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.perk-option", "nil perk option")

    fixture = makeFixture()
    fixture.options["MultiplierConfig.GlobalToggle"].asConfigOption = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "missing toggle config conversion")

    fixture = makeFixture()
    fixture.toggleConfig.getName = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "missing toggle config name")

    fixture = makeFixture({ globalMode = false })
    fixture.options["MultiplierConfig.Axe"].asConfigOption = function()
        return {}
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.perk-option", "missing perk config name")
end

do
    local invalid = { "", "Axe/Other", "Axe Thing", "Axe*Thing", 12 }
    for index, perkId in ipairs(invalid) do
        local fixture = makeFixture()
        assertFailure(fixture.created.resolver.resolve({}, perkId), "invalid-perk-id", "unsafe perk id " .. tostring(index))
        assertEqual(#fixture.state.optionRequests, 0, "unsafe ID does not look up options " .. tostring(index))
    end
    local fixture = makeFixture()
    assertFailure(fixture.created.resolver.resolve({}, nil), "invalid-perk-id", "nil perk id")
    assertEqual(#fixture.state.optionRequests, 0, "nil ID does not look up options")
end

do
    local globalInvalid = { 0, -1, 0 / 0, math.huge, -math.huge, "1" }
    for index, value in ipairs(globalInvalid) do
        local fixture = makeFixture({ globalValue = value })
        assertFailure(fixture.created.resolver.resolve({}, "Carpentry"), "invalid-global-multiplier", "invalid global " .. tostring(index))
        assertEqual(#fixture.state.clampCalls, 0, "invalid global avoids clamp " .. tostring(index))
    end

    local perkInvalid = { "0", "-1", "bad" }
    for index, value in ipairs(perkInvalid) do
        local fixture = makeFixture({ globalMode = false, perkValue = value })
        assertFailure(fixture.created.resolver.resolve({}, "Carpentry"), "invalid-perk-multiplier", "invalid per-skill " .. tostring(index))
    end
end

do
    local fixture = makeFixture({ globalMode = "true" })
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.global-toggle", "nonboolean toggle")

    fixture = makeFixture()
    fixture.mathApi.clampFloat = function()
        error("clamp failure")
    end
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-global-multiplier", "throwing clamp")

    local invalidClamp = { 0, 0 / 0, math.huge, -math.huge }
    for index, value in ipairs(invalidClamp) do
        fixture = makeFixture()
        fixture.mathApi.clampFloat = function()
            return value
        end
        assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-global-multiplier", "invalid clamp result " .. tostring(index))
    end

    local invalidParsed = { 0 / 0, math.huge, -math.huge }
    for index, value in ipairs(invalidParsed) do
        fixture = makeFixture({ globalMode = false })
        fixture.mathApi.tryParseFloat = function()
            return value
        end
        assertFailure(fixture.created.resolver.resolve({}, "Axe"), "invalid-perk-multiplier", "invalid parsed result " .. tostring(index))
    end

    fixture = makeFixture({ dependencies = { SandboxOptions = nil, PZMath = {} } })
    assertFailure(fixture.created, "invalid-dependencies", "missing construction SandboxOptions")

    fixture = makeFixture()
    fixture.dependencies.SandboxOptions = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.sandbox-options", "missing live SandboxOptions")

    fixture = makeFixture()
    fixture.dependencies.PZMath = nil
    assertFailure(fixture.created.resolver.resolve({}, "Axe"), "capability.pz-math", "missing live PZMath")
end

do
    local fixture = makeFixture()
    local player = setmetatable({}, {
        __index = function()
            error("player must remain opaque")
        end,
    })
    local result = fixture.created.resolver.resolve(player, "Aiming")
    assertTrue(result.ok, "opaque player resolves")
end

return assertions
