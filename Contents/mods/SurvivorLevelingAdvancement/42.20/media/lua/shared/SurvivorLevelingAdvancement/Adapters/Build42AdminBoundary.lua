local Build42AdminBoundary = {}

local MAX_SAFE_INTEGER = 9007199254740991
local MUTATIONS = {
    awardSurvivorXp = true, awardSurvivorLevels = true,
    clearAdvancementSlots = true, queueClearAdvancementSlots = true,
    cancelMailbox = true, acknowledgeMailbox = true,
}
local OFFLINE = {
    enumerateOfflineProfiles = true, inspectOfflineProfile = true,
    queueClearAdvancementSlots = true, cancelMailbox = true, acknowledgeMailbox = true,
}

local function fail(code) return { ok = false, code = code } end
local function constructionFailure(detail)
    return { ok = false, code = "invalid_dependencies", detail = detail }
end

local function readMember(value, name)
    if value == nil then return false, nil end
    local ok, member = pcall(function() return value[name] end)
    return ok, ok and member or nil
end

local function callMethod(value, name, argument)
    local found, method = readMember(value, name)
    if not found or type(method) ~= "function" then return false, nil end
    if argument ~= nil then return pcall(method, value, argument) end
    return pcall(method, value)
end

local function safeInteger(value)
    return type(value) == "number" and value == value and value >= 0
        and value <= MAX_SAFE_INTEGER and math.floor(value) == value
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function username(value)
    if type(value) ~= "string" or #value == 0 or #value > 64 then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then return false end
    end
    return true
end

local function opaque(value)
    return type(value) == "string" and value ~= "" and #value <= 64
        and string.match(value, "^[%w%._:%-]+$") ~= nil
end

local function exact(value, fields, count)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    local found = 0
    for key in pairs(value) do
        if type(key) ~= "string" or fields[key] ~= true then return false end
        found = found + 1
    end
    return found == count
end

local function usernameSelector(value)
    return exact(value, { username = true }, 1) and username(value.username)
end

local function onlineSelector(value)
    return exact(value, { onlineId = true, username = true }, 2)
        and safeInteger(value.onlineId) and username(value.username)
end

local function offlineSelector(value)
    return exact(value, {
        username = true, profileIndex = true, incarnationId = true,
    }, 3) and username(value.username) and safeInteger(value.profileIndex)
        and value.profileIndex <= 3 and opaque(value.incarnationId)
end

local function collection(value, maximum)
    local sizeOk, size = callMethod(value, "size")
    if not sizeOk or not safeInteger(size) or size > maximum then return nil end
    return size
end

function Build42AdminBoundary.create(dependencies)
    if type(dependencies) ~= "table" or getmetatable(dependencies) ~= nil then
        return constructionFailure("dependencies must be an exact plain table")
    end
    local dependencyCount = 0
    for key in pairs(dependencies) do
        if key ~= "Capability" and key ~= "getPlayerByOnlineID"
            and key ~= "getOnlinePlayers" and key ~= "getRoles"
            and key ~= "resolveProfile" then
            return constructionFailure("dependencies must be an exact plain table")
        end
        dependencyCount = dependencyCount + 1
    end
    if dependencyCount ~= 3 and dependencyCount ~= 5 then
        return constructionFailure("dependencies must be an exact plain table")
    end
    local Capability = dependencies.Capability
    local getPlayerByOnlineID, getOnlinePlayers = dependencies.getPlayerByOnlineID,
        dependencies.getOnlinePlayers
    local getRoles, resolveProfile = dependencies.getRoles, dependencies.resolveProfile
    if Capability == nil then return constructionFailure("Capability is required") end
    if type(getPlayerByOnlineID) ~= "function" then
        return constructionFailure("getPlayerByOnlineID must be a function")
    end
    if type(getOnlinePlayers) ~= "function" then
        return constructionFailure("getOnlinePlayers must be a function")
    end
    if dependencyCount == 5 and type(getRoles) ~= "function" then
        return constructionFailure("getRoles must be a function")
    end
    if dependencyCount == 5 and type(resolveProfile) ~= "function" then
        return constructionFailure("resolveProfile must be a function")
    end
    if dependencyCount == 3 then
        getRoles = function() return nil end
        resolveProfile = function() return nil end
    end
    local inspectCapability = select(2, readMember(Capability, "CanSeePlayersStats"))
    local mutationCapability = select(2, readMember(
        Capability, "CanModifyPlayerStatsInThePlayerStatsUI"
    ))
    if inspectCapability == nil then
        return constructionFailure("Capability.CanSeePlayersStats is required")
    end
    if mutationCapability == nil then
        return constructionFailure("Capability.CanModifyPlayerStatsInThePlayerStatsUI is required")
    end

    local function onlineProfiles()
        local called, players = pcall(getOnlinePlayers)
        if not called or players == nil then return nil end
        local size = collection(players, 32768)
        if size == nil then return nil end
        local result = {}
        for index = 0, size - 1 do
            local got, player = callMethod(players, "get", index)
            if not got or player == nil then return nil end
            local resolvedCalled, resolved = pcall(resolveProfile, player)
            if not resolvedCalled or type(resolved) ~= "table" or resolved.ok ~= true
                or type(resolved.profile) ~= "table" or not username(resolved.profile.username)
                or not safeInteger(resolved.profile.profileIndex)
                or resolved.profile.profileIndex > 3 then return nil end
            result[#result + 1] = {
                player = player, username = resolved.profile.username,
                profileIndex = resolved.profile.profileIndex,
            }
        end
        return result
    end

    local function maximumRole(actorRole)
        local actorPositionOk, actorPosition = callMethod(actorRole, "getPosition")
        if not actorPositionOk or not safeInteger(actorPosition) then return false end
        local called, roles = pcall(getRoles)
        if not called or roles == nil then return false end
        local size = collection(roles, 256)
        if size == nil or size == 0 then return false end
        local maximum = nil
        for index = 0, size - 1 do
            local got, role = callMethod(roles, "get", index)
            local positioned, position = false, nil
            if got then positioned, position = callMethod(role, "getPosition") end
            if not got or not positioned or not safeInteger(position) then return false end
            if maximum == nil or position > maximum then maximum = position end
        end
        return actorPosition == maximum
    end

    local boundary = {}
    function boundary.authorizeAndResolve(actor, operation, selector)
        local inspection = operation == "inspect"
        local offline = OFFLINE[operation] == true
            or ((operation == "awardSurvivorXp" or operation == "awardSurvivorLevels")
                and offlineSelector(selector))
        if operation ~= "inspect" and operation ~= "enumerateOfflineProfiles"
            and operation ~= "inspectOfflineProfile" and not MUTATIONS[operation] then
            return fail("invalid_request")
        end
        if inspection and not usernameSelector(selector) then return fail("invalid_request") end
        if operation == "enumerateOfflineProfiles" and not usernameSelector(selector) then
            return fail("invalid_request")
        end
        if operation == "inspectOfflineProfile" and not offlineSelector(selector) then
            return fail("invalid_request")
        end
        if MUTATIONS[operation] and not (onlineSelector(selector) or offlineSelector(selector)) then
            return fail("invalid_request")
        end
        if (operation == "clearAdvancementSlots" and not onlineSelector(selector))
            or ((operation == "queueClearAdvancementSlots" or operation == "cancelMailbox"
                or operation == "acknowledgeMailbox") and not offlineSelector(selector)) then
            return fail("invalid_request")
        end

        local roleOk, actorRole = callMethod(actor, "getRole")
        if not roleOk or actorRole == nil then return fail("unauthorized") end
        local required = MUTATIONS[operation] and mutationCapability or inspectCapability
        local capabilityOk, authorized = callMethod(actorRole, "hasCapability", required)
        if not capabilityOk or authorized ~= true then return fail("unauthorized") end
        if offline and MUTATIONS[operation] and not maximumRole(actorRole) then
            return fail("unauthorized")
        end

        if offline then
            if operation == "enumerateOfflineProfiles" then
                return {
                    ok = true, offline = true,
                    targetRef = { username = selector.username },
                }
            end
            local profiles = onlineProfiles()
            if profiles == nil then return fail("target_unavailable") end
            for index = 1, #profiles do
                if profiles[index].username == selector.username
                    and profiles[index].profileIndex == selector.profileIndex then
                    return fail("target_online")
                end
            end
            local targetRef = {
                username = selector.username, profileIndex = selector.profileIndex,
                incarnationId = selector.incarnationId,
            }
            return { ok = true, offline = true, targetRef = targetRef }
        end

        local target
        if inspection then
            local actorUsernameOk, actorUsername = callMethod(actor, "getUsername")
            if actorUsernameOk and actorUsername == selector.username then
                target = actor
            else
                local called, players = pcall(getOnlinePlayers)
                local size = called and collection(players, 32768) or nil
                if size == nil then return fail("target_unavailable") end
                local matches = 0
                for index = 0, size - 1 do
                    local got, candidate = callMethod(players, "get", index)
                    local named, candidateUsername = false, nil
                    if got then named, candidateUsername = callMethod(candidate, "getUsername") end
                    if not got or not named or not username(candidateUsername) then
                        return fail("target_mismatch")
                    end
                    if candidateUsername == selector.username then
                        matches, target = matches + 1, candidate
                    end
                end
                if matches ~= 1 then return fail("target_unavailable") end
            end
        else
            local called
            called, target = pcall(getPlayerByOnlineID, selector.onlineId)
            if not called then target = nil end
        end
        if target == nil then return fail("target_unavailable") end
        local idOk, onlineId = callMethod(target, "getOnlineID")
        local nameOk, targetUsername = callMethod(target, "getUsername")
        if not idOk or not nameOk or not safeInteger(onlineId)
            or not username(targetUsername) or targetUsername ~= selector.username
            or (not inspection and onlineId ~= selector.onlineId) then
            return fail("target_mismatch")
        end
        if MUTATIONS[operation] then
            local targetRoleOk, targetRole = callMethod(target, "getRole")
            local actorPositionOk, actorPosition = callMethod(actorRole, "getPosition")
            local targetPositionOk, targetPosition = false, nil
            if targetRoleOk then targetPositionOk, targetPosition = callMethod(targetRole, "getPosition") end
            if not targetRoleOk or not actorPositionOk or not targetPositionOk
                or not safeInteger(actorPosition) or not safeInteger(targetPosition)
                or targetPosition > actorPosition then return fail("unauthorized") end
        end
        return {
            ok = true, target = target,
            targetRef = { onlineId = onlineId, username = targetUsername },
        }
    end
    return { ok = true, boundary = boundary }
end

return Build42AdminBoundary
