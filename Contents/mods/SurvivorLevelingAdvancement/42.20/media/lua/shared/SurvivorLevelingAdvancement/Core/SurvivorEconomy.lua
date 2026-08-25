local SurvivorEconomy = {}

SurvivorEconomy.ORDINARY_NORMALIZATION = 1
SurvivorEconomy.FITNESS_STRENGTH_DEFAULT_NORMALIZATION = 21850 / 325000
SurvivorEconomy.CORE_TEN_LEVEL_NORMALIZATION_BASE = 21850

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonnegativeInteger(value)
    return finite(value) and value >= 0 and value == math.floor(value)
end

local function copyState(state)
    return { level = state.level, xpIntoLevel = state.xpIntoLevel, spent = state.spent }
end

local function validateState(state)
    if type(state) ~= "table" then
        return failure("invalid_state", "state must be a table")
    end
    if not nonnegativeInteger(state.level) or not finite(state.xpIntoLevel) or state.xpIntoLevel < 0 or not nonnegativeInteger(state.spent) then
        return failure("invalid_state", "state fields are malformed")
    end
    if state.spent > state.level then
        return failure("impossible_spent_level", "spent cannot exceed level")
    end
    local cost = 1200 + 300 * state.level
    if state.xpIntoLevel >= cost then
        return failure("invalid_state", "xpIntoLevel must be below the next level cost")
    end
    return { ok = true }
end

function SurvivorEconomy.nextLevelCost(level)
    if not nonnegativeInteger(level) then
        return failure("invalid_level", "level must be a nonnegative integer")
    end
    local cost = 1200 + 300 * level
    if not finite(cost) then
        return failure("invalid_level", "level cost is not finite")
    end
    return { ok = true, cost = cost }
end

function SurvivorEconomy.availableAp(state)
    local valid = validateState(state)
    if not valid.ok then
        return valid
    end
    return { ok = true, availableAp = state.level - state.spent }
end

function SurvivorEconomy.applyXp(state, gain)
    local valid = validateState(state)
    if not valid.ok then
        return valid
    end
    if not finite(gain) or gain < 0 then
        return failure("invalid_gain", "gain must be finite and nonnegative")
    end

    local nextState = copyState(state)
    local total = state.xpIntoLevel + gain
    if not finite(total) then
        return failure("invalid_gain", "gain exceeds representable Survivor state")
    end
    local linear = 1050 + 300 * state.level
    local discriminant = linear * linear + 600 * total
    if not finite(linear) or not finite(discriminant) then
        return failure("invalid_gain", "gain exceeds representable Survivor state")
    end
    local levelsGained = math.floor((math.sqrt(discriminant) - linear) / 300)
    if levelsGained < 0 then levelsGained = 0 end
    local spentForLevels = 150 * levelsGained * levelsGained + linear * levelsGained
    while levelsGained > 0 and spentForLevels > total do
        levelsGained = levelsGained - 1
        spentForLevels = 150 * levelsGained * levelsGained + linear * levelsGained
    end
    local nextCost = 1200 + 300 * (state.level + levelsGained)
    while total - spentForLevels >= nextCost do
        levelsGained = levelsGained + 1
        spentForLevels = 150 * levelsGained * levelsGained + linear * levelsGained
        nextCost = 1200 + 300 * (state.level + levelsGained)
    end
    nextState.level = state.level + levelsGained
    nextState.xpIntoLevel = total - spentForLevels
    if not finite(nextState.xpIntoLevel) or not finite(nextState.level) or nextState.xpIntoLevel < 0 or nextState.xpIntoLevel >= nextCost then
        return failure("invalid_gain", "gain exceeds representable Survivor state")
    end

    local effects = { levelsGained = levelsGained, apGained = levelsGained }
    return { ok = true, state = nextState, effects = effects }
end

function SurvivorEconomy.computeAward(baseAward, normalization, survivorMultiplier, eligibleRatio)
    if not finite(baseAward) or baseAward < 0 then
        return failure("invalid_award", "baseAward must be finite and nonnegative")
    end
    if not finite(normalization) or normalization <= 0 then
        return failure("invalid_normalization", "normalization must be finite and positive")
    end
    if not finite(survivorMultiplier) or survivorMultiplier < 0 then
        return failure("invalid_multiplier", "survivorMultiplier must be finite and nonnegative")
    end
    if not finite(eligibleRatio) or eligibleRatio < 0 or eligibleRatio > 1 then
        return failure("invalid_eligible_ratio", "eligibleRatio must be between zero and one")
    end

    local eligibleBase = baseAward * eligibleRatio
    local normalizedBase = eligibleBase * normalization
    local survivorXp = normalizedBase * survivorMultiplier
    if not finite(eligibleBase) or not finite(normalizedBase) or not finite(survivorXp) then
        return failure("invalid_award", "award calculation is not finite")
    end
    return { ok = true, eligibleBase = eligibleBase, normalizedBase = normalizedBase, survivorXp = survivorXp }
end

function SurvivorEconomy.normalizationFromCoreCurve(requirements)
    if type(requirements) ~= "table" then
        return failure("invalid_curve", "requirements must be a table")
    end
    local sum = 0
    for index = 1, 10 do
        local requirement = requirements[index]
        if not finite(requirement) or requirement <= 0 then
            return failure("invalid_curve", "requirements must contain ten finite positive values")
        end
        sum = sum + requirement
    end
    for key in pairs(requirements) do
        if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > 10 then
            return failure("invalid_curve", "requirements must be an ordered ten-level curve")
        end
    end
    if not finite(sum) or sum <= 0 then
        return failure("invalid_curve", "curve total is not finite and positive")
    end
    return { ok = true, normalization = SurvivorEconomy.CORE_TEN_LEVEL_NORMALIZATION_BASE / sum }
end

return SurvivorEconomy
