local Module = Build42MaxAwardEvaluator
local assertions = 0

local NULL = {}
local THROW = {}

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

local function assertFailure(result, reason, message)
    assertEqual(type(result), "table", (message or reason) .. " result")
    assertFalse(result.ok, (message or reason) .. " status")
    assertEqual(result.reason, reason, (message or reason) .. " reason")
    assertEqual(result.effectiveDelta, nil, (message or reason) .. " hides values")
end

local function pick(config, name, default)
    local value = config[name]
    if value == nil then
        return default
    end
    return value
end

local function resolve(value, ...)
    if value == THROW then
        error("fixture throw")
    end
    if value == NULL then
        return nil
    end
    if type(value) == "function" then
        return value(...)
    end
    return value
end

local function countKeys(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function makeFixture(config)
    config = config or {}
    local state = {
        clampCalls = {},
        parsed = {},
        optionNames = {},
        traitReads = {},
        parentReads = 0,
        sandboxGlobalReads = 0,
        sandboxPerkReads = 0,
    }

    local perks = {}
    local perkNames = {
        "Fitness", "Strength", "Sprinting", "SmallBlade", "LongBlade",
        "SmallBlunt", "Spear", "Blunt", "Axe", "Aiming", "Crafting",
    }
    for _, name in ipairs(perkNames) do
        perks[name] = { id = name }
    end
    for _, perk in pairs(perks) do
        function perk:getType()
            return resolve(pick(config, "perkType", self), self)
        end
        function perk:getId()
            return resolve(pick(config, "perkId", self.id), self)
        end
        function perk:getParent()
            state.parentReads = state.parentReads + 1
            return resolve(pick(config, "perkParent", nil), self)
        end
        function perk:getTotalXpForLevel(level)
            assertEqual(level, 10, "maximum level query")
            return resolve(pick(config, "maximumXp", 100), self, level)
        end
    end

    local characterTrait = {
        FAST_LEARNER = "FAST_LEARNER",
        SLOW_LEARNER = "SLOW_LEARNER",
        PACIFIST = "PACIFIST",
        CRAFTY = "CRAFTY",
    }

    local xp = {}
    function xp:getXP(perk)
        return resolve(pick(config, "currentXp", 100), perk)
    end
    function xp:getPerkBoost(perk)
        return resolve(pick(config, "boost", 1), perk)
    end
    function xp:getMultiplier(perk)
        return resolve(pick(config, "bookMultiplier", 0), perk)
    end

    local nutrition = {}
    function nutrition:canAddFitnessXp()
        return resolve(pick(config, "canAddFitnessXp", true))
    end
    function nutrition:getProteins()
        return resolve(pick(config, "proteins", 0))
    end

    local player = {}
    function player:isDead()
        return resolve(pick(config, "dead", false))
    end
    function player:isAsleep()
        return resolve(pick(config, "asleep", false))
    end
    function player:getXp()
        return resolve(pick(config, "xp", xp))
    end
    function player:getNutrition()
        return resolve(pick(config, "nutrition", nutrition))
    end
    function player:hasTrait(trait)
        state.traitReads[#state.traitReads + 1] = trait
        local traits = pick(config, "traits", {})
        return resolve(pick(traits, trait, false), trait)
    end

    local orderedPerks = {}
    for _, name in ipairs(perkNames) do
        orderedPerks[#orderedPerks + 1] = perks[name]
    end
    local perkList = {}
    function perkList:size()
        return resolve(pick(config, "perkListSize", #orderedPerks))
    end
    function perkList:get(index)
        if config.perkListGet == THROW then
            error("fixture throw")
        end
        if type(config.perkListGet) == "function" then
            return config.perkListGet(index, orderedPerks)
        end
        return orderedPerks[index + 1]
    end

    local globalToggleOption = {}
    function globalToggleOption:getValue()
        return resolve(pick(config, "globalToggle", true))
    end
    local globalMultiplierOption = {}
    function globalMultiplierOption:getValue()
        state.sandboxGlobalReads = state.sandboxGlobalReads + 1
        return resolve(pick(config, "globalMultiplier", 1))
    end

    local configOption = {}
    function configOption:getName()
        return resolve(pick(config, "resolvedOptionName", state.optionNames[#state.optionNames]))
    end
    function configOption:getValueAsString()
        state.sandboxPerkReads = state.sandboxPerkReads + 1
        return resolve(pick(config, "perkMultiplierText", "1"))
    end
    local sandboxOption = {}
    function sandboxOption:asConfigOption()
        return resolve(pick(config, "configOption", configOption))
    end
    local sandboxOptions = {
        multipliersConfig = {
            xpMultiplierGlobalToggle = globalToggleOption,
            xpMultiplierGlobal = globalMultiplierOption,
        },
    }
    function sandboxOptions:getOptionByName(name)
        state.optionNames[#state.optionNames + 1] = name
        return resolve(pick(config, "sandboxOption", sandboxOption), name)
    end

    local pzMath = {}
    function pzMath.clampFloat(value, minimum, maximum)
        state.clampCalls[#state.clampCalls + 1] = {
            value = value,
            minimum = minimum,
            maximum = maximum,
        }
        local implementation = pick(config, "clampFloat", nil)
        if implementation == THROW then
            error("fixture throw")
        end
        if implementation then
            return implementation(value, minimum, maximum, #state.clampCalls)
        end
        return value
    end
    function pzMath.tryParseFloat(value, fallback)
        state.parsed[#state.parsed + 1] = { value = value, fallback = fallback }
        local implementation = pick(config, "tryParseFloat", nil)
        if implementation == THROW then
            error("fixture throw")
        end
        if implementation then
            return implementation(value, fallback)
        end
        return tonumber(value) or fallback
    end

    local dependencies = {
        PZMath = pzMath,
        PerkFactory = { PerkList = perkList },
        Perks = perks,
        CharacterTrait = characterTrait,
        SandboxOptions = sandboxOptions,
    }
    if config.beforeCreate then
        config.beforeCreate(dependencies)
    end

    local created = Module.create(dependencies)
    return {
        created = created,
        state = state,
        dependencies = dependencies,
        player = player,
        xp = xp,
        nutrition = nutrition,
        perks = perks,
    }
end

local function evaluate(config, perkName, baseAward, useMultipliers)
    local fixture = makeFixture(config)
    assertTrue(fixture.created.ok, "fixture creates evaluator")
    local perk = fixture.perks[perkName or "Axe"]
    return fixture.created.evaluator.evaluate(
        fixture.player,
        perk,
        baseAward == nil and 8 or baseAward,
        useMultipliers == nil and true or useMultipliers
    ), fixture
end

do
    local fixture = makeFixture()
    assertTrue(fixture.created.ok, "create succeeds")
    local description = fixture.created.evaluator.describe()
    assertTrue(description.ok, "adapter status")
    assertEqual(description.adapterId, "sla.pz42-max-award", "adapter identity")
    assertEqual(description.adapterVersion, 1, "adapter version")
    assertEqual(description.representation, "java-binary32", "adapter representation")
end

do
    local result = Module.create(nil)
    assertFailure(result, "capability.dependencies", "nil dependencies")

    local missingCases = {
        { "capability.PZMath", function(deps) deps.PZMath = nil end },
        { "capability.PZMath.clampFloat", function(deps) deps.PZMath.clampFloat = nil end },
        { "capability.PZMath.tryParseFloat", function(deps) deps.PZMath.tryParseFloat = 1 end },
        { "capability.PerkFactory", function(deps) deps.PerkFactory = nil end },
        { "capability.PerkFactory.PerkList", function(deps) deps.PerkFactory.PerkList = nil end },
        { "capability.PerkFactory.PerkList.size", function(deps) deps.PerkFactory.PerkList.size = nil end },
        { "capability.PerkFactory.PerkList.get", function(deps) deps.PerkFactory.PerkList.get = false end },
        { "capability.Perks.Fitness", function(deps) deps.Perks.Fitness = nil end },
        { "capability.CharacterTrait.FAST_LEARNER", function(deps) deps.CharacterTrait.FAST_LEARNER = nil end },
        { "capability.SandboxOptions", function(deps) deps.SandboxOptions = nil end },
        { "capability.SandboxOptions.getOptionByName", function(deps) deps.SandboxOptions.getOptionByName = nil end },
        { "capability.SandboxOptions.multipliersConfig", function(deps) deps.SandboxOptions.multipliersConfig = nil end },
        { "capability.MultiplierConfig.xpMultiplierGlobalToggle", function(deps) deps.SandboxOptions.multipliersConfig.xpMultiplierGlobalToggle = nil end },
        { "capability.MultiplierConfig.xpMultiplierGlobal.getValue", function(deps) deps.SandboxOptions.multipliersConfig.xpMultiplierGlobal.getValue = nil end },
    }
    for index, entry in ipairs(missingCases) do
        local fixture = makeFixture({ beforeCreate = entry[2] })
        assertFailure(fixture.created, entry[1], "missing capability " .. tostring(index))
    end
end

do
    local fixture = makeFixture()
    local evaluator = fixture.created.evaluator
    assertFailure(evaluator.evaluate(nil, fixture.perks.Axe, 8, true), "player.missing")
    assertFailure(evaluator.evaluate(fixture.player, nil, 8, true), "perk.missing")
    assertFailure(evaluator.evaluate(fixture.player, fixture.perks.Axe, 8, 1), "input.useMultipliers")
end

local simpleFailures = {
    { { dead = true }, "player.dead" },
    { { dead = NULL }, "player.isDead" },
    { { dead = THROW }, "player.isDead" },
    { { asleep = true }, "player.asleep" },
    { { asleep = NULL }, "player.isAsleep" },
    { { asleep = THROW }, "player.isAsleep" },
    { { xp = NULL }, "player.xp" },
    { { xp = THROW }, "player.xp" },
    { { currentXp = NULL }, "cap.current-xp" },
    { { currentXp = 0 / 0 }, "cap.current-xp" },
    { { currentXp = THROW }, "cap.current-xp" },
    { { maximumXp = NULL }, "cap.maximum-xp" },
    { { maximumXp = math.huge }, "cap.maximum-xp" },
    { { maximumXp = THROW }, "cap.maximum-xp" },
    { { currentXp = 0, maximumXp = 0 }, "cap.maximum-nonpositive" },
    { { currentXp = -1, maximumXp = -1 }, "cap.maximum-nonpositive" },
    { { currentXp = 99, maximumXp = 100 }, "cap.below-maximum" },
    { { currentXp = 101, maximumXp = 100 }, "cap.above-maximum" },
}
for index, entry in ipairs(simpleFailures) do
    local result = evaluate(entry[1], "Axe", 8, true)
    assertFailure(result, entry[2], "pre-cap failure " .. tostring(index))
end

do
    local invalidBases = { 0, -1, math.huge, -math.huge, 0 / 0 }
    for index, value in ipairs(invalidBases) do
        local result = evaluate({}, "Axe", value, true)
        assertFailure(result, "award.base", "invalid base " .. tostring(index))
    end
    local result = evaluate({ clampFloat = THROW }, "Axe", 8, true)
    assertFailure(result, "award.base", "base routing throw")
    result = evaluate({ clampFloat = function() return math.huge end }, "Axe", 8, true)
    assertFailure(result, "award.base", "base routing overflow")
end

do
    local fixture = makeFixture()
    local alien = {}
    assertFailure(
        fixture.created.evaluator.evaluate(fixture.player, alien, 8, true),
        "perk.noncanonical",
        "alien perk"
    )
    local result = evaluate({ perkListSize = 0 }, "Axe", 8, true)
    assertFailure(result, "perk.registry", "empty perk registry")
    result = evaluate({ perkListSize = 257 }, "Axe", 8, true)
    assertFailure(result, "perk.registry", "unbounded perk registry")
    result = evaluate({ perkListSize = 1.5 }, "Axe", 8, true)
    assertFailure(result, "perk.registry", "fractional perk registry")
    result = evaluate({ perkListSize = THROW }, "Axe", 8, true)
    assertFailure(result, "perk.registry", "throwing perk registry")
    result = evaluate({ perkListGet = THROW }, "Axe", 8, true)
    assertFailure(result, "perk.registry", "throwing perk read")
    result = evaluate({ perkType = THROW }, "Axe", 8, true)
    assertFailure(result, "perk.registry", "unsafe canonical read")
end

do
    local result, fixture = evaluate({ boost = THROW }, "Axe", 8, false)
    assertTrue(result.ok, "disabled multipliers succeed")
    assertEqual(result.effectiveDelta, 8, "disabled multipliers preserve base")
    assertEqual(#fixture.state.traitReads, 0, "disabled multipliers skip traits")
    assertEqual(fixture.state.sandboxGlobalReads, 0, "disabled multipliers skip sandbox")
end

do
    local result = evaluate({}, "Fitness", 8, false)
    assertTrue(result.ok, "fitness eligible")
    assertEqual(result.effectiveDelta, 8, "fitness eligible value")
    result = evaluate({ canAddFitnessXp = false }, "Fitness", 8, false)
    assertFailure(result, "fitness.ineligible")
    result = evaluate({ nutrition = NULL }, "Fitness", 8, false)
    assertFailure(result, "fitness.nutrition")
    result = evaluate({ nutrition = THROW }, "Fitness", 8, false)
    assertFailure(result, "fitness.nutrition", "fitness nutrition throw")
    result = evaluate({ canAddFitnessXp = NULL }, "Fitness", 8, false)
    assertFailure(result, "fitness.eligibility")
    result = evaluate({ canAddFitnessXp = THROW }, "Fitness", 8, false)
    assertFailure(result, "fitness.eligibility", "fitness eligibility throw")
end

do
    local result = evaluate({ proteins = 51 }, "Strength", 8, false)
    assertTrue(result.ok, "strength positive proteins")
    assertEqual(result.effectiveDelta, 12, "strength positive factor")
    result = evaluate({ proteins = 299.999 }, "Strength", 8, false)
    assertEqual(result.effectiveDelta, 12, "strength upper interior")
    result = evaluate({ proteins = -301 }, "Strength", 10, false)
    assertEqual(result.effectiveDelta, 7, "strength negative factor")
    for _, proteins in ipairs({ 50, 300, -300 }) do
        result = evaluate({ proteins = proteins }, "Strength", 8, false)
        assertEqual(result.effectiveDelta, 8, "strength boundary " .. tostring(proteins))
    end
    result = evaluate({ nutrition = NULL }, "Strength", 8, false)
    assertFailure(result, "strength.nutrition")
    result = evaluate({ proteins = 0 / 0 }, "Strength", 8, false)
    assertFailure(result, "strength.proteins")
    result = evaluate({ proteins = THROW }, "Strength", 8, false)
    assertFailure(result, "strength.proteins", "strength proteins throw")
    local nextRoute = 0
    local expectedRoutes = {
        { 7.25, 7.25 },
        { 0.7, 0.699999988079071 },
        { 7.25 * 0.699999988079071, 5.074999809265137 },
    }
    result = evaluate({
        proteins = -301,
        clampFloat = function(value)
            nextRoute = nextRoute + 1
            assertEqual(value, expectedRoutes[nextRoute][1], "strength float input " .. tostring(nextRoute))
            return expectedRoutes[nextRoute][2]
        end,
    }, "Strength", 7.25, false)
    assertEqual(result.effectiveDelta, 5.074999809265137, "strength exact binary32 result")
    assertEqual(nextRoute, #expectedRoutes, "strength exact route count")
    result = evaluate({
        proteins = 51,
        clampFloat = function(value, minimum, maximum, call)
            if call == 3 then return 0 end
            return value
        end,
    }, "Strength", 8, false)
    assertFailure(result, "award.strength", "strength underflow")
end

local boostCases = {
    { "Axe", 0, 2 },
    { "Sprinting", 0, 8 },
    { "Fitness", 0, 8 },
    { "Strength", 0, 8 },
    { "Sprinting", 1, 10 },
    { "Axe", 1, 8 },
    { "Axe", 2, 10.64 },
    { "Fitness", 2, 8 },
    { "Strength", 2, 8 },
    { "Axe", 3, 13.28 },
    { "Axe", 7, 13.28 },
    { "Fitness", 3, 8 },
    { "Strength", 3, 8 },
}
for index, entry in ipairs(boostCases) do
    local result = evaluate({ boost = entry[2] }, entry[1], 8, true)
    assertTrue(result.ok, "boost case " .. tostring(index))
    assertEqual(result.effectiveDelta, entry[3], "boost value " .. tostring(index))
end

do
    local expectedRoutes = {
        { 8, 8 },
        { 1.33, 1.3300000429153442 },
        { 1.3300000429153442, 1.3300000429153442 },
        { 1.3300000429153442, 1.3300000429153442 },
        { 8 * 1.3300000429153442, 10.640000343322754 },
        { 1, 1 },
        { 1, 1 },
        { 10.640000343322754, 10.640000343322754 },
    }
    local nextRoute = 0
    local result = evaluate({
        boost = 2,
        clampFloat = function(value, minimum, maximum)
            nextRoute = nextRoute + 1
            local expected = expectedRoutes[nextRoute]
            assertTrue(expected ~= nil, "unexpected boost 2 float route")
            assertEqual(value, expected[1], "boost 2 float input " .. tostring(nextRoute))
            assertEqual(minimum, value, "boost 2 float minimum " .. tostring(nextRoute))
            assertEqual(maximum, value, "boost 2 float maximum " .. tostring(nextRoute))
            return expected[2]
        end,
    }, "Axe", 8, true)
    assertTrue(result.ok, "boost 2 exact pipeline succeeds")
    assertEqual(result.effectiveDelta, 10.640000343322754, "boost 2 exact binary32 result")
    assertEqual(nextRoute, #expectedRoutes, "boost 2 exact route count")
end

for index, boost in ipairs({ -1, 1.5, math.huge, 0 / 0, THROW, NULL }) do
    local result = evaluate({ boost = boost }, "Axe", 8, true)
    assertFailure(result, "boost.value", "invalid boost " .. tostring(index))
end

do
    local fast = { FAST_LEARNER = true }
    local result = evaluate({ boost = 1, traits = fast }, "Axe", 10, true)
    assertEqual(result.effectiveDelta, 13, "fast learner applies")
    result = evaluate({ boost = 1, traits = fast }, "Fitness", 10, true)
    assertEqual(result.effectiveDelta, 10, "fast learner excludes fitness")
    result = evaluate({ boost = 1, traits = fast }, "Strength", 10, true)
    assertEqual(result.effectiveDelta, 10, "fast learner excludes strength")
    result = evaluate({ boost = 1, traits = { FAST_LEARNER = NULL } }, "Axe", 10, true)
    assertFailure(result, "trait.fast-learner")

    local slow = { SLOW_LEARNER = true }
    result = evaluate({ boost = 1, traits = slow }, "Axe", 10, true)
    assertEqual(result.effectiveDelta, 7, "slow learner applies")
    result = evaluate({ boost = 1, traits = slow }, "Sprinting", 10, true)
    assertEqual(result.effectiveDelta, 12.5, "slow learner excludes sprinting")
    result = evaluate({ boost = 1, traits = slow }, "Fitness", 10, true)
    assertEqual(result.effectiveDelta, 10, "slow learner excludes fitness")
    result = evaluate({ boost = 1, traits = slow }, "Strength", 10, true)
    assertEqual(result.effectiveDelta, 10, "slow learner excludes strength")
end

do
    local pacifist = { PACIFIST = true }
    local affected = { "SmallBlade", "LongBlade", "SmallBlunt", "Spear", "Blunt", "Axe", "Aiming" }
    for _, name in ipairs(affected) do
        local result = evaluate({ boost = 1, traits = pacifist }, name, 8, true)
        assertEqual(result.effectiveDelta, 6, "pacifist affects " .. name)
    end
    local result = evaluate({ boost = 1, traits = pacifist }, "Crafting", 8, true)
    assertEqual(result.effectiveDelta, 8, "pacifist excludes crafting")
end

do
    local crafty = { CRAFTY = true }
    local fixture = makeFixture({ boost = 1, traits = crafty })
    local result = fixture.created.evaluator.evaluate(fixture.player, fixture.perks.Axe, 8, true)
    assertEqual(result.effectiveDelta, 8, "crafty excludes non-crafting")
    assertEqual(fixture.state.parentReads, 1, "crafty reads parent once")

    result = evaluate({ boost = 1, traits = crafty, perkParent = function() return nil end }, "Axe", 8, true)
    assertEqual(result.effectiveDelta, 8, "crafty accepts nil parent")
    result = evaluate({ boost = 1, traits = crafty, perkParent = THROW }, "Axe", 8, true)
    assertFailure(result, "perk.parent")

    fixture = makeFixture({ boost = 1, traits = crafty })
    fixture.perks.Axe.getParent = function() return fixture.perks.Crafting end
    result = fixture.created.evaluator.evaluate(fixture.player, fixture.perks.Axe, 10, true)
    assertEqual(result.effectiveDelta, 13, "crafty applies to crafting parent")

    fixture = makeFixture({ boost = 1, perkParent = THROW })
    result = fixture.created.evaluator.evaluate(fixture.player, fixture.perks.Axe, 8, true)
    assertTrue(result.ok, "parent not read without crafty")
    assertEqual(fixture.state.parentReads, 0, "parent read excluded")
end

do
    local result = evaluate({ boost = 1, bookMultiplier = 2 }, "Axe", 8, true)
    assertEqual(result.effectiveDelta, 16, "book multiplier applies above one")
    for _, multiplier in ipairs({ 0, 0.5, 1 }) do
        result = evaluate({ boost = 1, bookMultiplier = multiplier }, "Axe", 8, true)
        assertEqual(result.effectiveDelta, 8, "book boundary " .. tostring(multiplier))
    end
    for index, multiplier in ipairs({ -1, math.huge, 0 / 0, NULL, THROW }) do
        result = evaluate({ boost = 1, bookMultiplier = multiplier }, "Axe", 8, true)
        assertFailure(result, "book.multiplier", "invalid book multiplier " .. tostring(index))
    end
end

do
    local result, fixture = evaluate({ boost = 1, globalMultiplier = 1.5 }, "Axe", 8, true)
    assertEqual(result.effectiveDelta, 12, "global sandbox multiplier")
    assertEqual(fixture.state.sandboxGlobalReads, 1, "global sandbox read")
    assertEqual(fixture.state.sandboxPerkReads, 0, "global branch skips per-perk")
    for index, value in ipairs({ -1, math.huge, 0 / 0, NULL, THROW }) do
        result = evaluate({ boost = 1, globalMultiplier = value }, "Axe", 8, true)
        assertFailure(result, "sandbox.global-multiplier", "invalid global multiplier " .. tostring(index))
    end
    result = evaluate({ boost = 1, globalMultiplier = 0 }, "Axe", 8, true)
    assertFailure(result, "award.effective", "zero global result")
    result = evaluate({ boost = 1, globalToggle = NULL }, "Axe", 8, true)
    assertFailure(result, "sandbox.global-toggle")
    result = evaluate({ boost = 1, globalToggle = THROW }, "Axe", 8, true)
    assertFailure(result, "sandbox.global-toggle", "global toggle throw")
end

do
    local result, fixture = evaluate({
        boost = 1,
        globalToggle = false,
        perkMultiplierText = "1.5",
    }, "Axe", 8, true)
    assertEqual(result.effectiveDelta, 12, "per-perk sandbox multiplier")
    assertEqual(fixture.state.optionNames[1], "MultiplierConfig.Axe", "canonical sandbox option")
    assertEqual(fixture.state.parsed[1].value, "1.5", "sandbox string parsed")
    assertEqual(fixture.state.parsed[1].fallback, -1, "sandbox parse fallback")
    assertEqual(fixture.state.sandboxGlobalReads, 0, "per-perk branch skips global")

    local expectedRoutes = {
        { 8, 8 },
        { 1, 1 },
        { 1, 1 },
        { 1, 1 },
        { 8, 8 },
        { 1.2000000476837158, 1.2000000476837158 },
        { 8 * 1.2000000476837158, 9.600000381469727 },
    }
    local nextRoute = 0
    fixture = makeFixture({
        boost = 1,
        globalToggle = false,
        perkMultiplierText = "1.2",
        tryParseFloat = function(value, fallback)
            assertEqual(value, "1.2", "per-perk nonexact parse input")
            assertEqual(fallback, -1, "per-perk nonexact parse fallback")
            return 1.2000000476837158
        end,
        clampFloat = function(value, minimum, maximum)
            nextRoute = nextRoute + 1
            local expected = expectedRoutes[nextRoute]
            assertTrue(expected ~= nil, "unexpected per-perk float route")
            assertEqual(value, expected[1], "per-perk float input " .. tostring(nextRoute))
            assertEqual(minimum, value, "per-perk float minimum " .. tostring(nextRoute))
            assertEqual(maximum, value, "per-perk float maximum " .. tostring(nextRoute))
            return expected[2]
        end,
    })
    result = fixture.created.evaluator.evaluate(fixture.player, fixture.perks.Axe, 8, true)
    assertTrue(result.ok, "per-perk nonexact pipeline succeeds")
    assertEqual(result.effectiveDelta, 9.600000381469727, "per-perk exact binary32 result")
    assertEqual(nextRoute, #expectedRoutes, "per-perk exact route count")
    assertEqual(#fixture.state.parsed, 1, "per-perk parse count")

    local invalidPerkCases = {
        { { globalToggle = false, perkId = NULL }, "sandbox.perk-identity" },
        { { globalToggle = false, perkId = "" }, "sandbox.perk-identity" },
        { { globalToggle = false, perkId = THROW }, "sandbox.perk-identity" },
        { { globalToggle = false, sandboxOption = NULL }, "sandbox.perk-option" },
        { { globalToggle = false, sandboxOption = THROW }, "sandbox.perk-option" },
        { { globalToggle = false, configOption = NULL }, "sandbox.perk-option" },
        { { globalToggle = false, configOption = THROW }, "sandbox.perk-option" },
        { { globalToggle = false, resolvedOptionName = "MultiplierConfig.Blunt" }, "sandbox.perk-option" },
        { { globalToggle = false, resolvedOptionName = THROW }, "sandbox.perk-option" },
        { { globalToggle = false, perkMultiplierText = NULL }, "sandbox.perk-option" },
        { { globalToggle = false, perkMultiplierText = THROW }, "sandbox.perk-option" },
        { { globalToggle = false, perkMultiplierText = "bad" }, "sandbox.perk-multiplier" },
        { { globalToggle = false, tryParseFloat = function() return math.huge end }, "sandbox.perk-multiplier" },
        { { globalToggle = false, tryParseFloat = function() return -0.5 end }, "sandbox.perk-multiplier" },
        { { globalToggle = false, tryParseFloat = THROW }, "sandbox.perk-multiplier" },
    }
    for index, entry in ipairs(invalidPerkCases) do
        result = evaluate(entry[1], "Axe", 8, true)
        assertFailure(result, entry[2], "invalid perk sandbox " .. tostring(index))
    end
end

do
    local expectedRoutes = {
        { 7.25, 7.25 },
        { 1.66, 1.659999966621399 },
        { 1.659999966621399, 1.659999966621399 },
        { 1.3, 1.2999999523162842 },
        { 1.659999966621399 * 1.2999999523162842, 2.1579999923706055 },
        { 0.7, 0.699999988079071 },
        { 2.1579999923706055 * 0.699999988079071, 1.510599970817566 },
        { 0.75, 0.75 },
        { 1.510599970817566 * 0.75, 1.132949948310852 },
        { 1.3, 1.2999999523162842 },
        { 1.132949948310852 * 1.2999999523162842, 1.472834825515747 },
        { 1.472834825515747, 1.472834825515747 },
        { 7.25 * 1.472834825515747, 10.67805290222168 },
        { 2.5, 2.5 },
        { 10.67805290222168 * 2.5, 26.695133209228516 },
        { 1.2, 1.2000000476837158 },
        { 1.2000000476837158, 1.2000000476837158 },
        { 26.695133209228516 * 1.2000000476837158, 32.03416061401367 },
    }
    local nextRoute = 0
    local fixture = makeFixture({
        boost = 3,
        bookMultiplier = 2.5,
        globalMultiplier = 1.2,
        traits = {
            FAST_LEARNER = true,
            SLOW_LEARNER = true,
            PACIFIST = true,
            CRAFTY = true,
        },
        clampFloat = function(value, minimum, maximum)
            nextRoute = nextRoute + 1
            local expected = expectedRoutes[nextRoute]
            assertTrue(expected ~= nil, "unexpected float route")
            assertEqual(value, expected[1], "float route input " .. tostring(nextRoute))
            assertEqual(minimum, value, "float route minimum " .. tostring(nextRoute))
            assertEqual(maximum, value, "float route maximum " .. tostring(nextRoute))
            return expected[2]
        end,
    })
    fixture.perks.SmallBlade.getParent = function() return fixture.perks.Crafting end
    local result = fixture.created.evaluator.evaluate(fixture.player, fixture.perks.SmallBlade, 7.25, true)
    assertTrue(result.ok, "combined multiplier pipeline succeeds")
    assertEqual(result.effectiveDelta, 32.03416061401367, "combined exact binary32 result")
    assertEqual(nextRoute, #expectedRoutes, "combined route count")
    assertEqual(#fixture.state.traitReads, 4, "combined trait order count")
    assertEqual(fixture.state.traitReads[1], "FAST_LEARNER", "fast learner order")
    assertEqual(fixture.state.traitReads[2], "SLOW_LEARNER", "slow learner order")
    assertEqual(fixture.state.traitReads[3], "PACIFIST", "pacifist order")
    assertEqual(fixture.state.traitReads[4], "CRAFTY", "crafty order")
end

do
    local fixture = makeFixture({ boost = 1 })
    local playerKeys = countKeys(fixture.player)
    local perkKeys = countKeys(fixture.perks.Axe)
    local xpKeys = countKeys(fixture.xp)
    local nutritionKeys = countKeys(fixture.nutrition)
    local result = fixture.created.evaluator.evaluate(fixture.player, fixture.perks.Axe, 8, true)
    assertTrue(result.ok, "immutability evaluation succeeds")
    assertEqual(countKeys(fixture.player), playerKeys, "player remains immutable")
    assertEqual(countKeys(fixture.perks.Axe), perkKeys, "perk remains immutable")
    assertEqual(countKeys(fixture.xp), xpKeys, "xp remains immutable")
    assertEqual(countKeys(fixture.nutrition), nutritionKeys, "nutrition remains immutable")
    for index, call in ipairs(fixture.state.clampCalls) do
        assertEqual(call.minimum, call.value, "route minimum is exact " .. tostring(index))
        assertEqual(call.maximum, call.value, "route maximum is exact " .. tostring(index))
    end
end

return assertions
