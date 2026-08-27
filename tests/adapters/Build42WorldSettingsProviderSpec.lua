local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then
        error(message)
    end
end

local function expectEqual(actual, expected, message)
    expect(actual == expected, message .. ' (expected ' .. tostring(expected) .. ', got ' .. tostring(actual) .. ')')
end

local function expectNil(actual, message)
    expect(actual == nil, message .. ' (got ' .. tostring(actual) .. ')')
end

local function expectKeys(tableValue, expectedKeys, message)
    for key, _ in pairs(tableValue) do
        expect(expectedKeys[key] == true, message .. ': unexpected key ' .. tostring(key))
    end
    for key, _ in pairs(expectedKeys) do
        expect(tableValue[key] ~= nil, message .. ': missing key ' .. tostring(key))
    end
end

local function makeNamespace(allotmentMode, overrides)
    local namespace = {
        SurvivorXpMultiplier = 1.25,
        FitnessStrengthContributionPercent = 75,
        AutomaticCurveNormalization = true,
        AllotmentMode = allotmentMode,
        GlobalAdvancementLimit = 9,
        PerSkillDefaultLimit = 4,
        FutureSetting = 'ignored'
    }
    for key, value in pairs(overrides or {}) do
        namespace['PerSkillLimit_' .. key] = value
    end
    return namespace
end

local currentSandboxVars = { SurvivorLevelingAdvancement = makeNamespace(1, { ['A:opaque-ID._-9'] = 1, ['Fitness.Strength'] = 2, ['Other:Skill'] = 12 }) }
local reads = 0
local function readSandboxVars()
    reads = reads + 1
    return currentSandboxVars
end

local creation = Build42WorldSettingsProvider.create({ readSandboxVars = readSandboxVars })
expect(creation.ok == true, 'valid capability should create successfully')
expect(type(creation.provider) == 'table', 'creation should return a provider')
expectEqual(reads, 0, 'creation must not read the capability')

expect(Build42WorldSettingsProvider.create(nil).ok == false, 'nil capability should be rejected')
expect(Build42WorldSettingsProvider.create({}).ok == false, 'missing capability should be rejected')
expect(Build42WorldSettingsProvider.create({ readSandboxVars = true }).ok == false, 'malformed capability should be rejected')

local settings = creation.provider.read()
expectEqual(reads, 1, 'a read should invoke the capability once')
expect(type(settings) == 'table', 'valid read should return a table')
expectKeys(settings, {
    survivorMultiplier = true,
    fitnessStrengthNormalization = true,
    automaticCurveNormalization = true,
    allotmentMode = true,
    globalLimit = true,
    perSkillDefault = true,
    perSkillOverrides = true
}, 'raw settings shape')
expectEqual(settings.survivorMultiplier, 1.25, 'survivor multiplier')
expectEqual(settings.fitnessStrengthNormalization, 0.75, 'fitness/strength normalization')
expectEqual(settings.automaticCurveNormalization, true, 'automatic normalization')
expectEqual(settings.allotmentMode, 'Global', 'allotment enum 1')
expectEqual(settings.globalLimit, 9, 'global limit')
expectEqual(settings.perSkillDefault, 4, 'per-skill default')
expectEqual(settings.perSkillOverrides['A:opaque-ID._-9'], nil, 'Use default override should be omitted')
expectEqual(settings.perSkillOverrides['Fitness.Strength'], 0, 'override enum 2 should map to zero')
expectEqual(settings.perSkillOverrides['Other:Skill'], 10, 'override enum 12 should map to ten')
expectEqual(settings.perSkillOverrides.FutureSetting, nil, 'unrelated namespace key should be ignored')

settings.perSkillOverrides['Fitness.Strength'] = 99
local detached = creation.provider.read()
expectEqual(reads, 2, 'each read should invoke the capability once')
expectEqual(detached.perSkillOverrides['Fitness.Strength'], 0, 'returned override maps should be detached')

currentSandboxVars = { SurvivorLevelingAdvancement = makeNamespace(2, {}) }
expectEqual(creation.provider.read().allotmentMode, 'PerSkill', 'allotment enum 2')
currentSandboxVars = { SurvivorLevelingAdvancement = makeNamespace(3, {}) }
expectEqual(creation.provider.read().allotmentMode, 'Free', 'allotment enum 3')

local malformedCases = {
    { name = 'missing root', value = nil },
    { name = 'non-table root', value = 'bad' },
    { name = 'missing namespace', value = {} },
    { name = 'non-table namespace', value = { SurvivorLevelingAdvancement = false } },
    { name = 'missing scalar', value = { SurvivorLevelingAdvancement = makeNamespace(1, {}) } },
}
malformedCases[5].value.SurvivorLevelingAdvancement.SurvivorXpMultiplier = nil
for _, case in ipairs(malformedCases) do
    currentSandboxVars = case.value
    expectNil(creation.provider.read(), case.name .. ' should fail closed')
end

local function readWithNamespace(namespace)
    currentSandboxVars = { SurvivorLevelingAdvancement = namespace }
    return creation.provider.read()
end

local rootWithMetatable = setmetatable({ SurvivorLevelingAdvancement = makeNamespace(1, {}) }, { __index = function() error('root lookup') end })
currentSandboxVars = rootWithMetatable
expectNil(creation.provider.read(), 'root metatable should fail closed')
local namespaceWithMetatable = setmetatable(makeNamespace(1, {}), { __index = function() error('namespace lookup') end })
expectNil(readWithNamespace(namespaceWithMetatable), 'namespace metatable should fail closed')

local throwingRootReader = Build42WorldSettingsProvider.create({ readSandboxVars = function() error('reader throw') end })
expectNil(throwingRootReader.provider.read(), 'throwing root capability should fail closed')
local throwingNamespace = setmetatable(makeNamespace(1, {}), { __pairs = function() error('iteration throw') end })
expectNil(readWithNamespace(throwingNamespace), 'throwing namespace should fail closed')

local invalidScalars = {
    { field = 'SurvivorXpMultiplier', value = -1 },
    { field = 'SurvivorXpMultiplier', value = 100.0001 },
    { field = 'FitnessStrengthContributionPercent', value = -0.0001 },
    { field = 'FitnessStrengthContributionPercent', value = 100.0001 },
    { field = 'AutomaticCurveNormalization', value = 1 },
    { field = 'AllotmentMode', value = 4 },
    { field = 'GlobalAdvancementLimit', value = -1 },
    { field = 'PerSkillDefaultLimit', value = 1.5 }
}
for _, invalid in ipairs(invalidScalars) do
    local namespace = makeNamespace(1, {})
    namespace[invalid.field] = invalid.value
    expectNil(readWithNamespace(namespace), 'invalid ' .. invalid.field .. ' should fail closed')
end

local invalidOverrideValues = { 0, 13, 2.5, '2' }
for _, value in ipairs(invalidOverrideValues) do
    expectNil(readWithNamespace(makeNamespace(1, { ['Opaque.Skill'] = value })), 'invalid override enum should fail closed')
end

local unsafeSuffixes = { '', 'Unsafe/Skill', 'Unsafe Skill', 'Unsafe=Skill' }
for _, suffix in ipairs(unsafeSuffixes) do
    local namespace = makeNamespace(1, {})
    namespace['PerSkillLimit_' .. suffix] = 2
    expectNil(readWithNamespace(namespace), 'unsafe override suffix should fail closed')
end

currentSandboxVars = { SurvivorLevelingAdvancement = makeNamespace(1, { ['Boundary.Zero'] = 2, ['Boundary.Ten'] = 12, ['Boundary.Default'] = 1 }) }
local boundary = creation.provider.read()
expectEqual(boundary.perSkillOverrides['Boundary.Zero'], 0, 'zero boundary')
expectEqual(boundary.perSkillOverrides['Boundary.Ten'], 10, 'ten boundary')
expectEqual(boundary.perSkillOverrides['Boundary.Default'], nil, 'default boundary')

currentSandboxVars = { SurvivorLevelingAdvancement = makeNamespace(1, {}) }
currentSandboxVars.SurvivorLevelingAdvancement.SurvivorXpMultiplier = 0
expectEqual(creation.provider.read().survivorMultiplier, 0, 'zero multiplier is accepted')
currentSandboxVars.SurvivorLevelingAdvancement.SurvivorXpMultiplier = 100
expectEqual(creation.provider.read().survivorMultiplier, 100, 'one hundred multiplier is accepted')
currentSandboxVars.SurvivorLevelingAdvancement.FitnessStrengthContributionPercent = 0
expectEqual(creation.provider.read().fitnessStrengthNormalization, 0, 'zero percent resolves to zero normalization')
currentSandboxVars.SurvivorLevelingAdvancement.FitnessStrengthContributionPercent = 6.7
expectEqual(creation.provider.read().fitnessStrengthNormalization, 0.067, 'percentage conversion divides exactly once')
currentSandboxVars.SurvivorLevelingAdvancement.FitnessStrengthContributionPercent = 100
expectEqual(creation.provider.read().fitnessStrengthNormalization, 1, 'one hundred percent resolves to ordinary normalization')

return assertions
