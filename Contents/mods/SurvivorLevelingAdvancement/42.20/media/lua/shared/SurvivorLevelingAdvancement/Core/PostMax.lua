local PostMax = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function copyState(state)
    return { fullRateUsed = state.fullRateUsed }
end

local function validateState(state)
    if type(state) ~= "table" or not finite(state.fullRateUsed) or state.fullRateUsed < 0 then
        return failure("invalid_postmax_state", "fullRateUsed must be finite and nonnegative")
    end
    return { ok = true }
end

function PostMax.apply(state, normalizedBase, survivorMultiplier, settings)
    local validState = validateState(state)
    if not validState.ok then
        return validState
    end
    if not finite(normalizedBase) or normalizedBase < 0 then
        return failure("invalid_award", "normalizedBase must be finite and nonnegative")
    end
    if not finite(survivorMultiplier) or survivorMultiplier < 0 then
        return failure("invalid_multiplier", "survivorMultiplier must be finite and nonnegative")
    end
    if type(settings) ~= "table" or type(settings.enabled) ~= "boolean" then
        return failure("invalid_postmax_settings", "settings.enabled must be a boolean")
    end

    local nextState = copyState(state)
    if not settings.enabled then
        return { ok = true, state = nextState, effect = { fullRateBase = 0, diminishedBase = 0, survivorXp = 0 } }
    end
    if not finite(settings.fullRateAllowance) or settings.fullRateAllowance < 0 or not finite(settings.diminishedRate) or settings.diminishedRate < 0 or settings.diminishedRate > 1 then
        return failure("invalid_postmax_settings", "enabled settings require a nonnegative allowance and diminished rate from zero to one")
    end

    local remainingAllowance = settings.fullRateAllowance - state.fullRateUsed
    if remainingAllowance < 0 then
        remainingAllowance = 0
    end
    local fullRateBase = normalizedBase
    if fullRateBase > remainingAllowance then
        fullRateBase = remainingAllowance
    end
    local diminishedBase = normalizedBase - fullRateBase
    local survivorXp = (fullRateBase + diminishedBase * settings.diminishedRate) * survivorMultiplier
    nextState.fullRateUsed = state.fullRateUsed + normalizedBase
    if not finite(nextState.fullRateUsed) or not finite(survivorXp) then
        return failure("invalid_award", "post-maximum award is not finite")
    end
    return { ok = true, state = nextState, effect = { fullRateBase = fullRateBase, diminishedBase = diminishedBase, survivorXp = survivorXp } }
end

return PostMax
