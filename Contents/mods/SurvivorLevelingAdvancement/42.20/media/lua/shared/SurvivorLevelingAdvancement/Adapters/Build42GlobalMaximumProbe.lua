local Build42GlobalMaximumProbe = {}

local CANDIDATE_KEY = {}

local function result(ok, code, detail)
    return { ok = ok, code = code, detail = detail }
end

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isPosition(value)
    return isFinite(value) and value >= 0
end

local function isSafePerkId(value)
    return type(value) == "string" and value:match("^[%w%._:%-]+$") ~= nil
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local function callSafely(callable, ...)
    return pack(pcall(callable, ...))
end

local function validateDependencies(dependencies)
    if type(dependencies) ~= "table" then
        return nil, result(false, "invalid_dependencies", "dependencies")
    end
    if type(dependencies.processSide) ~= "table"
        or type(dependencies.processSide.isServer) ~= "function" then
        return nil, result(false, "invalid_dependencies", "processSide.isServer")
    end
    if type(dependencies.playerIdentity) ~= "table"
        or type(dependencies.playerIdentity.isPlayer) ~= "function" then
        return nil, result(false, "invalid_dependencies", "playerIdentity.isPlayer")
    end
    if type(dependencies.perkIdentity) ~= "table"
        or type(dependencies.perkIdentity.resolve) ~= "function" then
        return nil, result(false, "invalid_dependencies", "perkIdentity.resolve")
    end
    if type(dependencies.positionReader) ~= "table"
        or type(dependencies.positionReader.read) ~= "function" then
        return nil, result(false, "invalid_dependencies", "positionReader.read")
    end
    if type(dependencies.maximumEvaluator) ~= "table"
        or type(dependencies.maximumEvaluator.evaluate) ~= "function" then
        return nil, result(false, "invalid_dependencies", "maximumEvaluator.evaluate")
    end
    return {
        isServer = dependencies.processSide.isServer,
        isPlayer = dependencies.playerIdentity.isPlayer,
        resolvePerk = dependencies.perkIdentity.resolve,
        readPosition = dependencies.positionReader.read,
        evaluate = dependencies.maximumEvaluator.evaluate,
    }, nil
end

function Build42GlobalMaximumProbe.create(dependencies)
    local validated, failure = validateDependencies(dependencies)
    if not validated then
        return nil, failure
    end

    local serverCall = callSafely(validated.isServer)
    if not serverCall[1] then
        return nil, result(false, "process_side_threw", nil)
    end
    if type(serverCall[2]) ~= "boolean" then
        return nil, result(false, "process_side_failed", nil)
    end
    local unsupportedServer = serverCall[2]
    local probe = {}

    local function resolvePlayer(player)
        local called = callSafely(validated.isPlayer, player)
        if not called[1] then
            return false, "player_identity_threw"
        end
        if type(called[2]) ~= "boolean" then
            return false, "player_identity_failed"
        end
        if not called[2] then
            return false, "non_player_owner"
        end
        return true, nil
    end

    local function resolvePerk(perk)
        local called = callSafely(validated.resolvePerk, perk)
        if not called[1] then
            return nil, "perk_identity_threw"
        end
        local answer = called[2]
        if type(answer) ~= "table" or answer.ok ~= true
            or not isSafePerkId(answer.perkId)
            or (answer.perk ~= nil and answer.perk ~= perk) then
            return nil, "perk_identity_failed"
        end
        return answer.perkId, nil
    end

    local function playerIsInWorld(player)
        local accessed = callSafely(function()
            return player and player.isExistInTheWorld
        end)
        if not accessed[1] then
            return false, "world_presence_threw"
        end
        if type(accessed[2]) ~= "function" then
            return false, "world_presence_missing"
        end
        local called = callSafely(accessed[2], player)
        if not called[1] then
            return false, "world_presence_threw"
        end
        if type(called[2]) ~= "boolean" then
            return false, "world_presence_failed"
        end
        if not called[2] then
            return false, "player_not_in_world"
        end
        return true, nil
    end

    local function readPosition(player, perkId, phase)
        local called = callSafely(validated.readPosition, player, perkId)
        if not called[1] then
            return nil, phase .. "_position_threw"
        end
        local answer = called[2]
        if type(answer) ~= "table" or answer.ok ~= true
            or not isPosition(answer.position) then
            return nil, phase .. "_position_failed"
        end
        return answer.position, nil
    end

    function probe.begin(player, perk, routedBaseAward, useMultipliers)
        if unsupportedServer then
            return result(false, "unsupported_server", nil)
        end
        if not isFinite(routedBaseAward) or routedBaseAward <= 0 then
            return result(false, "invalid_routed_base", nil)
        end
        if type(useMultipliers) ~= "boolean" then
            return result(false, "invalid_multiplier_mode", nil)
        end
        local eligible, playerFailure = resolvePlayer(player)
        if not eligible then
            return result(false, playerFailure, nil)
        end
        local inWorld, worldFailure = playerIsInWorld(player)
        if not inWorld then
            return result(false, worldFailure, nil)
        end
        local perkId, perkFailure = resolvePerk(perk)
        if not perkId then
            return result(false, perkFailure, nil)
        end
        local position, positionFailure = readPosition(player, perkId, "initial")
        if not position then
            return result(false, positionFailure, nil)
        end

        local candidate = function(key)
            if key ~= CANDIDATE_KEY then
                return nil
            end
            return player, perk, perkId, routedBaseAward, useMultipliers, position
        end
        return { ok = true, code = "candidate_created", candidate = candidate }
    end

    function probe.complete(candidate)
        if unsupportedServer then
            return result(false, "unsupported_server", nil)
        end
        if type(candidate) ~= "function" then
            return result(false, "invalid_candidate", nil)
        end
        local opened = callSafely(candidate, CANDIDATE_KEY)
        if not opened[1] or opened.n ~= 7 then
            return result(false, "invalid_candidate", nil)
        end
        local player, perk, perkId = opened[2], opened[3], opened[4]
        local routedBaseAward, useMultipliers, initialPosition = opened[5], opened[6], opened[7]
        if not isSafePerkId(perkId)
            or not isFinite(routedBaseAward) or routedBaseAward <= 0
            or type(useMultipliers) ~= "boolean"
            or not isPosition(initialPosition) then
            return result(false, "invalid_candidate", nil)
        end

        local eligible, playerFailure = resolvePlayer(player)
        if not eligible then
            return result(false, playerFailure, nil)
        end
        local inWorld, worldFailure = playerIsInWorld(player)
        if not inWorld then
            return result(false, worldFailure, nil)
        end
        local currentPerkId, perkFailure = resolvePerk(perk)
        if not currentPerkId then
            return result(false, perkFailure, nil)
        end
        if currentPerkId ~= perkId then
            return result(false, "perk_identity_changed", nil)
        end
        local currentPosition, positionFailure = readPosition(player, perkId, "current")
        if not currentPosition then
            return result(false, positionFailure, nil)
        end
        if currentPosition ~= initialPosition then
            return result(false, "position_changed", nil)
        end

        local evaluated = callSafely(
            validated.evaluate, player, perk, routedBaseAward, useMultipliers
        )
        if not evaluated[1] then
            return result(false, "evaluator_threw", nil)
        end
        local answer = evaluated[2]
        if type(answer) ~= "table" or answer.ok ~= true
            or not isFinite(answer.effectiveDelta) or answer.effectiveDelta <= 0
            or not isFinite(answer.survivorCreditBase)
            or answer.survivorCreditBase <= 0 then
            return result(false, "evaluator_failed", nil)
        end
        return {
            ok = true,
            code = "maximum_confirmed",
            perkId = perkId,
            survivorCreditBase = answer.survivorCreditBase,
            appliedDelta = 0,
            actualPositionBefore = initialPosition,
            actualPositionAfter = currentPosition,
            effectiveDelta = answer.effectiveDelta,
        }
    end

    return probe, nil
end

return Build42GlobalMaximumProbe
