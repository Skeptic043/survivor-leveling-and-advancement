local AccountingMode = {}

local function failed(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function validMode(mode)
    return mode == "Tracked" or mode == "Free"
end

local function copyValue(value, seen)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" or kind == "number" then return value end
    if kind ~= "table" then return nil, "unsupported_type" end
    seen = seen or {}
    if seen[value] then return nil, "cycle" end
    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local copiedKey, keyError = copyValue(key, seen)
        if keyError then seen[value] = nil; return nil, keyError end
        local copiedChild, childError = copyValue(child, seen)
        if childError then seen[value] = nil; return nil, childError end
        copy[copiedKey] = copiedChild
    end
    seen[value] = nil
    return copy
end

local function acknowledged(result)
    return type(result) == "table" and getmetatable(result) == nil and rawget(result, "ok") == true
end

function AccountingMode.create(dependencies)
    if type(dependencies) ~= "table" then
        return failed("invalid_dependencies", "dependencies must be a table")
    end
    local store = dependencies.store
    local observation = dependencies.ActualObservation
    if type(store) ~= "table" or type(store.save) ~= "function" then
        return failed("invalid_store", "store.save must be a function")
    end
    if type(observation) ~= "table" or type(observation.clearPlayer) ~= "function" then
        return failed("invalid_observation", "ActualObservation.clearPlayer must be a function")
    end

    local save = store.save
    local clearPlayer = observation.clearPlayer

    local function synchronizeLoaded(player, state, desiredMode)
        if not validMode(desiredMode) then
            return failed("invalid_desired_mode", "desiredMode must be Tracked or Free")
        end
        if type(state) ~= "table" or not validMode(state.accountingMode) then
            return failed("invalid_state", "state accountingMode is invalid")
        end
        local fromMode = state.accountingMode
        if fromMode == desiredMode then
            return { ok = true, state = state, transitioned = false, fromMode = fromMode, toMode = desiredMode }
        end
        if state.inFlightAdvancement ~= nil then
            return failed("in_flight_advancement", "accounting mode cannot change during an advancement reservation")
        end

        local candidate, copyError = copyValue(state)
        if candidate == nil then return failed("invalid_state", copyError) end
        candidate.accountingMode = desiredMode
        candidate.revision = candidate.revision + 1
        if desiredMode == "Tracked" then
            candidate.perks = {}
            candidate.orphanedPerks = {}
        end

        local cleared, clearResult = pcall(clearPlayer, player)
        if not cleared or not acknowledged(clearResult) then
            return failed("observation_clear_failed", "actual observations could not be cleared")
        end
        local saved, saveResult = pcall(save, player, candidate)
        if not saved or not acknowledged(saveResult) then
            return failed("save_failed", "accounting mode transition could not be saved")
        end
        return { ok = true, state = candidate, transitioned = true, fromMode = fromMode, toMode = desiredMode }
    end

    return { ok = true, service = { synchronizeLoaded = synchronizeLoaded } }
end

return AccountingMode
