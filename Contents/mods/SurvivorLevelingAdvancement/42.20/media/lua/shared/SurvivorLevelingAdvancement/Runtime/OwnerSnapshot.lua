local OwnerSnapshot = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonnegativeInteger(value)
    return finite(value) and value >= 0 and value == math.floor(value)
end

local function positiveInteger(value)
    return nonnegativeInteger(value) and value > 0
end

local function safeId(value)
    return type(value) == "string" and value ~= "" and value:match("^[%w%._:%-]+$") ~= nil
end

local function denseArray(value)
    if type(value) ~= "table" then return false end
    local length = #value
    for key in pairs(value) do
        if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > length then
            return false
        end
    end
    return true
end

local function validateState(state)
    if type(state) ~= "table" then return nil, failure("invalid_state", "state must be a table") end
    if not nonnegativeInteger(state.revision) then return nil, failure("invalid_state", "state.revision must be a nonnegative integer") end
    if type(state.survivor) ~= "table" then return nil, failure("invalid_state", "state.survivor must be a table") end
    if type(state.perks) ~= "table" then return nil, failure("invalid_state", "state.perks must be a table") end

    local survivor = state.survivor
    if not nonnegativeInteger(survivor.level) or not finite(survivor.xpIntoLevel) or survivor.xpIntoLevel < 0
        or not nonnegativeInteger(survivor.spent) then
        return nil, failure("invalid_state", "survivor display fields are malformed")
    end
    return survivor
end

local function projectTargets(record)
    if not denseArray(record.activeTargets) then return nil, failure("invalid_target", "activeTargets must be a dense array") end

    local targets = {}
    local previousLevel, previousPosition = 0, record.highWaterPosition
    for index = 1, #record.activeTargets do
        local target = record.activeTargets[index]
        if type(target) ~= "table" then return nil, failure("invalid_target", "target must be a table") end
        if not positiveInteger(target.targetLevel) or target.targetLevel > record.effectiveMaximum
            or not finite(target.targetPosition) or target.targetPosition < 0 then
            return nil, failure("invalid_target", "target display fields are malformed")
        end
        if target.targetLevel <= previousLevel or target.targetPosition <= previousPosition then
            return nil, failure("invalid_target", "target order is malformed")
        end
        targets[index] = {
            targetLevel = target.targetLevel,
            targetPosition = target.targetPosition,
        }
        previousLevel, previousPosition = target.targetLevel, target.targetPosition
    end
    return targets
end

local function projectPerk(record)
    if type(record) ~= "table" then return nil, failure("invalid_perk", "perk record must be a table") end
    if not positiveInteger(record.effectiveMaximum) or not finite(record.naturalPosition) or record.naturalPosition < 0
        or not finite(record.highWaterPosition) or record.highWaterPosition < record.naturalPosition then
        return nil, failure("invalid_perk", "perk display fields are malformed")
    end

    local targets, targetFailure = projectTargets(record)
    if targets == nil then return nil, targetFailure end
    return {
        effectiveMaximum = record.effectiveMaximum,
        naturalPosition = record.naturalPosition,
        highWaterPosition = record.highWaterPosition,
        activeTargets = targets,
    }
end

local function validateCatalogResult(result)
    return type(result) == "table" and result.ok == true and denseArray(result.perks)
end

local function validateEconomyResult(result, field, detail, valid)
    if type(result) ~= "table" or result.ok ~= true or not valid(result[field]) then
        return nil, failure("economy_failure", detail)
    end
    return result[field]
end

function OwnerSnapshot.create(dependencies)
    if type(dependencies) ~= "table" then return failure("invalid_dependencies", "dependencies must be a table") end
    local catalog = dependencies.catalog
    if type(catalog) ~= "table" or type(catalog.allPerks) ~= "function" then
        return failure("invalid_dependencies", "catalog.allPerks is required")
    end
    if type(catalog.perkIdentity) ~= "table" or type(catalog.perkIdentity.resolve) ~= "function" then
        return failure("invalid_dependencies", "catalog.perkIdentity.resolve is required")
    end
    local economy = dependencies.SurvivorEconomy
    if type(economy) ~= "table" or type(economy.availableAp) ~= "function" then
        return failure("invalid_dependencies", "SurvivorEconomy.availableAp is required")
    end
    if type(economy.nextLevelCost) ~= "function" then
        return failure("invalid_dependencies", "SurvivorEconomy.nextLevelCost is required")
    end

    local projector = {}

    function projector.project(state, sequence, ready)
        local survivor, stateFailure = validateState(state)
        if survivor == nil then return stateFailure end
        if not positiveInteger(sequence) then return failure("invalid_sequence", "sequence must be a positive integer") end
        if type(ready) ~= "boolean" then return failure("invalid_ready", "ready must be a boolean") end

        local catalogCalled, catalogResult = pcall(catalog.allPerks)
        if not catalogCalled then return failure("invalid_catalog", "catalog.allPerks failed") end
        if not validateCatalogResult(catalogResult) then
            return failure("invalid_catalog", "catalog.allPerks returned an invalid result")
        end

        local published = {}
        for index = 1, #catalogResult.perks do
            local resolvedCalled, resolved = pcall(catalog.perkIdentity.resolve, catalogResult.perks[index])
            if not resolvedCalled then return failure("invalid_catalog", "catalog.perkIdentity.resolve failed") end
            if type(resolved) ~= "table" or resolved.ok ~= true or not safeId(resolved.perkId) then
                return failure("invalid_catalog", "catalog.perkIdentity.resolve returned an invalid result")
            end
            if published[resolved.perkId] then return failure("invalid_catalog", "catalog contains duplicate perk IDs") end
            published[resolved.perkId] = true
        end

        for perkId in pairs(state.perks) do
            if not safeId(perkId) then return failure("invalid_state", "state.perks contains an unsafe perk ID") end
        end

        local perks = {}
        for perkId in pairs(published) do
            local record = state.perks[perkId]
            if record ~= nil then
                local projected, perkFailure = projectPerk(record)
                if projected == nil then return perkFailure end
                perks[perkId] = projected
            end
        end

        local availableCalled, availableResult = pcall(function()
            return economy.availableAp(survivor)
        end)
        if not availableCalled then return failure("economy_failure", "SurvivorEconomy.availableAp failed") end
        local availableAp, availableFailure = validateEconomyResult(availableResult, "availableAp", "SurvivorEconomy.availableAp returned an invalid result", nonnegativeInteger)
        if availableAp == nil then return availableFailure end

        local costCalled, costResult = pcall(function()
            return economy.nextLevelCost(survivor.level)
        end)
        if not costCalled then return failure("economy_failure", "SurvivorEconomy.nextLevelCost failed") end
        local xpForNextLevel, costFailure = validateEconomyResult(costResult, "cost", "SurvivorEconomy.nextLevelCost returned an invalid result", positiveInteger)
        if xpForNextLevel == nil then return costFailure end
        if survivor.xpIntoLevel >= xpForNextLevel then
            return failure("economy_failure", "SurvivorEconomy.nextLevelCost must exceed survivor.xpIntoLevel")
        end

        return {
            ok = true,
            snapshot = {
                protocolVersion = 1,
                ready = ready,
                sequence = sequence,
                revision = state.revision,
                survivor = {
                    level = survivor.level,
                    xpIntoLevel = survivor.xpIntoLevel,
                    xpForNextLevel = xpForNextLevel,
                    spent = survivor.spent,
                    availableAp = availableAp,
                },
                perks = perks,
            },
        }
    end

    return { ok = true, projector = projector }
end

return OwnerSnapshot
