local ActualObservation = {}

local observationsByPlayer = setmetatable({}, { __mode = "k" })

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function isSafeId(value)
    return type(value) == "string" and value:match("^[%w%._:%-]+$") ~= nil
end

local function isPosition(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value >= 0
end

local function validateKey(player, perkId)
    if player == nil then
        return failure("invalid_observation", "player_required")
    end
    if not isSafeId(perkId) then
        return failure("invalid_observation", "perkId_required")
    end
    return nil
end

function ActualObservation.get(player, perkId)
    local invalid = validateKey(player, perkId)
    if invalid then return invalid end

    local observations = observationsByPlayer[player]
    local position = observations and observations[perkId] or nil
    if position == nil then
        return { ok = true, present = false }
    end
    return { ok = true, present = true, position = position }
end

function ActualObservation.set(player, perkId, position)
    local invalid = validateKey(player, perkId)
    if invalid then return invalid end
    if not isPosition(position) then
        return failure("invalid_observation", "position_must_be_finite_and_nonnegative")
    end

    local observations = observationsByPlayer[player]
    if observations == nil then
        observations = {}
        observationsByPlayer[player] = observations
    end
    observations[perkId] = position
    return { ok = true, position = position }
end

function ActualObservation.clearPlayer(player)
    if player == nil then
        return failure("invalid_observation", "player_required")
    end
    observationsByPlayer[player] = nil
    return { ok = true }
end

return ActualObservation
