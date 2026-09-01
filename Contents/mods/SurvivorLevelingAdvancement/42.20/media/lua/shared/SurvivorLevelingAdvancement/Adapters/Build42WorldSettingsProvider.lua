local Build42WorldSettingsProvider = {}

local POSITIVE_INFINITY = math.huge
local NEGATIVE_INFINITY = -math.huge
local OVERRIDE_PREFIX = 'PerSkillLimit_'
local SURVIVOR_XP_PREFIX = 'SkillSurvivorXp_'
local VANILLA_PERK_IDS = {
    'Fitness', 'Strength', 'Sprinting', 'Lightfoot', 'Nimble', 'Sneak', 'Axe', 'Blunt',
    'SmallBlunt', 'LongBlade', 'SmallBlade', 'Spear', 'Maintenance', 'Farming', 'Husbandry',
    'Woodwork', 'Carving', 'Cooking', 'Electricity', 'Doctor', 'FlintKnapping', 'Masonry',
    'Mechanics', 'Blacksmith', 'Pottery', 'Tailoring', 'MetalWelding', 'Aiming', 'Reloading',
    'Fishing', 'PlantScavenging', 'Tracking', 'Trapping', 'Butchering', 'Glassmaking'
}

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= POSITIVE_INFINITY
        and value ~= NEGATIVE_INFINITY
end

local function isNonnegativeInteger(value)
    return isFiniteNumber(value) and value >= 0 and value % 1 == 0
end

local function isSafePerkId(value)
    return type(value) == 'string' and string.match(value, '^[%w%._:%-]+$') ~= nil
end

local function isPlainTable(value)
    return type(value) == 'table' and getmetatable(value) == nil
end

local function readSettings(readSandboxVars, readSandboxOption)
    local sandboxVars = readSandboxVars()
    if not isPlainTable(sandboxVars) then
        return nil
    end

    local namespace = sandboxVars.SurvivorLevelingAdvancement
    if not isPlainTable(namespace) then
        return nil
    end

    local function namedValue(name)
        if readSandboxOption ~= nil then
            local liveValue = readSandboxOption(name)
            if liveValue ~= nil then return liveValue end
        end
        return namespace[name]
    end

    local survivorMultiplier = namedValue('SurvivorXpMultiplier')
    if not isFiniteNumber(survivorMultiplier) or survivorMultiplier < 0 or survivorMultiplier > 100 then
        return nil
    end

    local fitnessStrengthContributionPercent = namedValue('FitnessStrengthContributionPercent')
    if not isFiniteNumber(fitnessStrengthContributionPercent)
        or fitnessStrengthContributionPercent < 0
        or fitnessStrengthContributionPercent > 100 then
        return nil
    end
    local fitnessStrengthNormalization = fitnessStrengthContributionPercent / 100

    local automaticCurveNormalization = namedValue('AutomaticCurveNormalization')
    if type(automaticCurveNormalization) ~= 'boolean' then
        return nil
    end

    local customSkillSurvivorXpEnabled = namedValue('CustomSkillSurvivorXp')
    if type(customSkillSurvivorXpEnabled) ~= 'boolean' then
        return nil
    end

    local perSkillSurvivorXpEnabled = {}
    for index = 1, #VANILLA_PERK_IDS do
        local perkId = VANILLA_PERK_IDS[index]
        local enabled = namedValue(SURVIVOR_XP_PREFIX .. perkId)
        if type(enabled) ~= 'boolean' then
            return nil
        end
        perSkillSurvivorXpEnabled[perkId] = enabled
    end

    local inheritanceEnabled = namedValue('EnableSurvivorLevelInheritance')
    if type(inheritanceEnabled) ~= 'boolean' then
        return nil
    end

    local retainedPercent = namedValue('SurvivorLevelRetainedPercent')
    if not isFiniteNumber(retainedPercent) or retainedPercent < 0 or retainedPercent > 100 then
        return nil
    end
    local retainedRatio = retainedPercent / 100

    local allotmentModeValue = namedValue('AllotmentMode')
    local allotmentMode
    if allotmentModeValue == 1 then
        allotmentMode = 'Global'
    elseif allotmentModeValue == 2 then
        allotmentMode = 'PerSkill'
    elseif allotmentModeValue == 3 then
        allotmentMode = 'Free'
    else
        return nil
    end

    local globalLimit = namedValue('GlobalAdvancementLimit')
    if not isNonnegativeInteger(globalLimit) then
        return nil
    end

    local perSkillDefault = namedValue('PerSkillDefaultLimit')
    if not isNonnegativeInteger(perSkillDefault) then
        return nil
    end

    local perSkillOverrides = {}
    for key in pairs(namespace) do
        if type(key) == 'string' and string.sub(key, 1, string.len(OVERRIDE_PREFIX)) == OVERRIDE_PREFIX then
            local value = namedValue(key)
            local perkId = string.sub(key, string.len(OVERRIDE_PREFIX) + 1)
            if not isSafePerkId(perkId) then
                return nil
            end
            if type(value) ~= 'number' or value ~= value or value % 1 ~= 0 or value < 1 or value > 12 then
                return nil
            end
            if value ~= 1 then
                perSkillOverrides[perkId] = value - 2
            end
        end
    end

    return {
        survivorMultiplier = survivorMultiplier,
        fitnessStrengthNormalization = fitnessStrengthNormalization,
        automaticCurveNormalization = automaticCurveNormalization,
        customSkillSurvivorXpEnabled = customSkillSurvivorXpEnabled,
        perSkillSurvivorXpEnabled = perSkillSurvivorXpEnabled,
        allotmentMode = allotmentMode,
        globalLimit = globalLimit,
        perSkillDefault = perSkillDefault,
        perSkillOverrides = perSkillOverrides,
        inheritanceEnabled = inheritanceEnabled,
        retainedRatio = retainedRatio
    }
end

function Build42WorldSettingsProvider.create(dependencies)
    if type(dependencies) ~= 'table' or getmetatable(dependencies) ~= nil then
        return { ok = false, code = 'invalid_capability', detail = 'readSandboxVars capability is required' }
    end

    local readSandboxVars = dependencies.readSandboxVars
    if type(readSandboxVars) ~= 'function' then
        return { ok = false, code = 'invalid_capability', detail = 'readSandboxVars capability is required' }
    end
    local readSandboxOption = dependencies.readSandboxOption
    if readSandboxOption ~= nil and type(readSandboxOption) ~= 'function' then
        return { ok = false, code = 'invalid_capability', detail = 'readSandboxOption capability must be callable' }
    end

    local provider = {}
    function provider.read()
        local ok, settings = pcall(readSettings, readSandboxVars, readSandboxOption)
        if not ok then
            return nil
        end
        return settings
    end

    return { ok = true, provider = provider }
end

return Build42WorldSettingsProvider
