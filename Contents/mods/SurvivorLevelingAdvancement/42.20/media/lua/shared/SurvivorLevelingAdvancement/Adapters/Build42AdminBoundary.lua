local Build42AdminBoundary = {}

local MAX_SAFE_INTEGER = 9007199254740991

local MUTATION_OPERATIONS = {
    awardSurvivorXp = true,
    awardSurvivorLevels = true,
    clearAdvancementSlots = true,
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

local function isExactUsernameSelector(selector)
    if type(selector) ~= "table" or getmetatable(selector) ~= nil then
        return false
    end

    local count = 0
    for key in pairs(selector) do
        if key ~= "username" then
            return false
        end
        count = count + 1
    end

    return count == 1 and isPrintableUsername(selector.username)
end

local function isExactCanonicalSelector(selector)
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
        if key ~= "Capability" and key ~= "getPlayerByOnlineID"
            and key ~= "getOnlinePlayers" then
            return constructionFailure("dependencies must be an exact plain table")
        end
        dependencyCount = dependencyCount + 1
    end
    if dependencyCount ~= 3 then
        return constructionFailure("dependencies must be an exact plain table")
    end

    local capabilityFound, Capability = readMember(dependencies, "Capability")
    local lookupFound, getPlayerByOnlineID = readMember(dependencies, "getPlayerByOnlineID")
    local onlinePlayersFound, getOnlinePlayers = readMember(dependencies, "getOnlinePlayers")
    if not capabilityFound or Capability == nil then
        return constructionFailure("Capability is required")
    end
    if not lookupFound or type(getPlayerByOnlineID) ~= "function" then
        return constructionFailure("getPlayerByOnlineID must be a function")
    end
    if not onlinePlayersFound or type(getOnlinePlayers) ~= "function" then
        return constructionFailure("getOnlinePlayers must be a function")
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
        clearAdvancementSlots = mutationCapability,
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
        local inspection = operation == "inspect"
        if inspection and not isExactUsernameSelector(selector) then
            return fail("invalid_request")
        end
        if not inspection and not isExactCanonicalSelector(selector) then
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

        local lookupOk, target
        if inspection then
            local actorUsernameOk, actorUsername = callMethod(actor, "getUsername")
            if actorUsernameOk
                and isPrintableUsername(actorUsername)
                and actorUsername == selector.username
            then
                lookupOk, target = true, actor
            else
                local collectionOk, onlinePlayers = pcall(getOnlinePlayers)
                if not collectionOk or onlinePlayers == nil then
                    return fail("target_unavailable")
                end
                local sizeOk, size = callMethod(onlinePlayers, "size")
                if not sizeOk or not isSafeOnlineId(size) or size > 32768 then
                    return fail("target_unavailable")
                end
                local matches = 0
                for index = 0, size - 1 do
                    local elementOk, candidate = callMethod(onlinePlayers, "get", index)
                    if not elementOk or candidate == nil then
                        return fail("target_unavailable")
                    end
                    local candidateUsernameOk, candidateUsername = callMethod(candidate, "getUsername")
                    if not candidateUsernameOk or not isPrintableUsername(candidateUsername) then
                        return fail("target_mismatch")
                    end
                    if candidateUsername == selector.username then
                        matches = matches + 1
                        target = candidate
                    end
                end
                if matches ~= 1 then return fail("target_unavailable") end
                lookupOk = true
            end
        else
            lookupOk, target = pcall(getPlayerByOnlineID, selector.onlineId)
        end
        if not lookupOk or target == nil then
            return fail("target_unavailable")
        end

        local onlineIdOk, onlineId = callMethod(target, "getOnlineID")
        local usernameOk, username = callMethod(target, "getUsername")
        if not onlineIdOk or not usernameOk then
            return fail("target_mismatch")
        end
        if not isSafeOnlineId(onlineId) or not isPrintableUsername(username)
            or username ~= selector.username
            or (not inspection and onlineId ~= selector.onlineId) then
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
