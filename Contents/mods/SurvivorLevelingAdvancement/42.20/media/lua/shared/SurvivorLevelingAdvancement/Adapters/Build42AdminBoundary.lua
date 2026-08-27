local Build42AdminBoundary = {}

local MAX_SAFE_INTEGER = 9007199254740991

local MUTATION_OPERATIONS = {
    awardSurvivorXp = true,
    awardSurvivorLevels = true,
    advancePerkNormally = true,
    resetAccounting = true,
    setAccounting = true,
}

local function fail(code)
    return {
        ok = false,
        code = code,
    }
end

local function constructionFailure(detail)
    return {
        ok = false,
        code = "invalid_dependencies",
        detail = detail,
    }
end

local function readMember(value, name)
    if value == nil then
        return false, nil
    end

    local ok, member = pcall(function()
        return value[name]
    end)

    if not ok then
        return false, nil
    end

    return true, member
end

local function callMethod(value, name, argument)
    local found, method = readMember(value, name)
    if not found or type(method) ~= "function" then
        return false, nil
    end

    if argument ~= nil then
        return pcall(method, value, argument)
    end

    return pcall(method, value)
end

local function isSafeOnlineId(value)
    return type(value) == "number"
        and value == value
        and value >= 0
        and value <= MAX_SAFE_INTEGER
        and math.floor(value) == value
end

local function isPrintableUsername(value)
    if type(value) ~= "string" or #value == 0 or #value > 64 then
        return false
    end

    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then
            return false
        end
    end

    return true
end

local function isExactSelector(selector)
    if type(selector) ~= "table" or getmetatable(selector) ~= nil then
        return false
    end

    local count = 0
    for key in pairs(selector) do
        if key ~= "onlineId" and key ~= "username" then
            return false
        end
        count = count + 1
    end

    return count == 2
        and isSafeOnlineId(selector.onlineId)
        and isPrintableUsername(selector.username)
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function Build42AdminBoundary.create(dependencies)
    if type(dependencies) ~= "table" or getmetatable(dependencies) ~= nil then
        return constructionFailure("dependencies must be an exact plain table")
    end

    local dependencyCount = 0
    for key in pairs(dependencies) do
        if key ~= "Capability" and key ~= "getPlayerByOnlineID" then
            return constructionFailure("dependencies must be an exact plain table")
        end
        dependencyCount = dependencyCount + 1
    end
    if dependencyCount ~= 2 then
        return constructionFailure("dependencies must be an exact plain table")
    end

    local capabilityFound, Capability = readMember(dependencies, "Capability")
    local lookupFound, getPlayerByOnlineID = readMember(dependencies, "getPlayerByOnlineID")
    if not capabilityFound or Capability == nil then
        return constructionFailure("Capability is required")
    end
    if not lookupFound or type(getPlayerByOnlineID) ~= "function" then
        return constructionFailure("getPlayerByOnlineID must be a function")
    end

    local inspectFound, inspectCapability = readMember(Capability, "CanSeePlayersStats")
    local mutationFound, mutationCapability = readMember(
        Capability,
        "CanModifyPlayerStatsInThePlayerStatsUI"
    )
    if not inspectFound or inspectCapability == nil then
        return constructionFailure("Capability.CanSeePlayersStats is required")
    end
    if not mutationFound or mutationCapability == nil then
        return constructionFailure(
            "Capability.CanModifyPlayerStatsInThePlayerStatsUI is required"
        )
    end

    local operationCapabilities = {
        inspect = inspectCapability,
        awardSurvivorXp = mutationCapability,
        awardSurvivorLevels = mutationCapability,
        advancePerkNormally = mutationCapability,
        resetAccounting = mutationCapability,
        setAccounting = mutationCapability,
    }

    local boundary = {}

    function boundary.authorizeAndResolve(actor, operation, selector)
        if type(operation) ~= "string" then
            return fail("invalid_request")
        end
        local requiredCapability = operationCapabilities[operation]
        if requiredCapability == nil then
            return fail("invalid_request")
        end
        if not isExactSelector(selector) then
            return fail("invalid_request")
        end

        local roleOk, actorRole = callMethod(actor, "getRole")
        if not roleOk or actorRole == nil then
            return fail("unauthorized")
        end

        local capabilityOk, authorized = callMethod(
            actorRole,
            "hasCapability",
            requiredCapability
        )
        if not capabilityOk or authorized ~= true then
            return fail("unauthorized")
        end

        local lookupOk, target = pcall(getPlayerByOnlineID, selector.onlineId)
        if not lookupOk or target == nil then
            return fail("target_unavailable")
        end

        local onlineIdOk, onlineId = callMethod(target, "getOnlineID")
        local usernameOk, username = callMethod(target, "getUsername")
        if not onlineIdOk or not usernameOk then
            return fail("target_mismatch")
        end
        if onlineId ~= selector.onlineId or username ~= selector.username then
            return fail("target_mismatch")
        end

        if MUTATION_OPERATIONS[operation] then
            local targetRoleOk, targetRole = callMethod(target, "getRole")
            if not targetRoleOk or targetRole == nil then
                return fail("unauthorized")
            end

            local actorPositionOk, actorPosition = callMethod(actorRole, "getPosition")
            local targetPositionOk, targetPosition = callMethod(targetRole, "getPosition")
            if not actorPositionOk
                or not targetPositionOk
                or not isFiniteNumber(actorPosition)
                or not isFiniteNumber(targetPosition)
                or targetPosition > actorPosition
            then
                return fail("unauthorized")
            end
        end

        return {
            ok = true,
            target = target,
            targetRef = {
                onlineId = onlineId,
                username = username,
            },
        }
    end

    return {
        ok = true,
        boundary = boundary,
    }
end

return Build42AdminBoundary
