local Build42WorldSettingsProvider = {}

local POSITIVE_INFINITY = math.huge
local NEGATIVE_INFINITY = -math.huge
local OVERRIDE_PREFIX = 'PerSkillLimit_'

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

    if readSandboxOption ~= nil then
        local liveNamespace = {}
        for key, value in pairs(namespace) do
            local liveValue = readSandboxOption(key)
            if liveValue == nil then
                liveNamespace[key] = value
            else
                liveNamespace[key] = liveValue
            end
        end
        namespace = liveNamespace
    end

    local survivorMultiplier = namespace.SurvivorXpMultiplier
    if not isFiniteNumber(survivorMultiplier) or survivorMultiplier < 0 or survivorMultiplier > 100 then
        return nil
    end

    local fitnessStrengthContributionPercent = namespace.FitnessStrengthContributionPercent
    if not isFiniteNumber(fitnessStrengthContributionPercent)
        or fitnessStrengthContributionPercent < 0
        or fitnessStrengthContributionPercent > 100 then
        return nil
    end
    local fitnessStrengthNormalization = fitnessStrengthContributionPercent / 100

    local automaticCurveNormalization = namespace.AutomaticCurveNormalization
    if type(automaticCurveNormalization) ~= 'boolean' then
        return nil
    end

    local inheritanceEnabled = namespace.EnableSurvivorLevelInheritance
    if type(inheritanceEnabled) ~= 'boolean' then
        return nil
    end

    local retainedPercent = namespace.SurvivorLevelRetainedPercent
    if not isFiniteNumber(retainedPercent) or retainedPercent < 0 or retainedPercent > 100 then
        return nil
    end
    local retainedRatio = retainedPercent / 100

    local allotmentModeValue = namespace.AllotmentMode
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

    local globalLimit = namespace.GlobalAdvancementLimit
    if not isNonnegativeInteger(globalLimit) then
        return nil
    end

    local perSkillDefault = namespace.PerSkillDefaultLimit
    if not isNonnegativeInteger(perSkillDefault) then
        return nil
    end

    local perSkillOverrides = {}
    for key, value in pairs(namespace) do
        if type(key) == 'string' and string.sub(key, 1, string.len(OVERRIDE_PREFIX)) == OVERRIDE_PREFIX then
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
