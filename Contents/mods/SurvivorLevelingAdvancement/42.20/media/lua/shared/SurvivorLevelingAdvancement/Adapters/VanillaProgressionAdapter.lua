local Adapter = {}
local DEFAULT_DISCOVERY_LIMIT = 512
local privateByHandle = setmetatable({}, { __mode = "k" })

local function failure(code, detail, fields)
    local result = fields or {}
    result.ok = false
    result.code = code
    result.detail = detail
    return result
end

local function success(fields)
    local result = fields or {}
    result.ok = true
    return result
end

local function isFiniteNumber(value)
    return type(value) == "number"
            and value == value
            and value ~= math.huge
            and value ~= -math.huge
end

local function isInteger(value)
    return isFiniteNumber(value) and value == math.floor(value)
end

local function getMethod(target, methodName, ownerLabel)
    if target == nil then
        return nil, failure("missing-capability", ownerLabel .. " is required")
    end

    local ok, methodOrError = pcall(function()
        return target[methodName]
    end)
    if not ok then
        return nil, failure(
            "capability-error",
            ownerLabel .. "." .. methodName .. " lookup failed: " .. tostring(methodOrError)
        )
    end
    if type(methodOrError) ~= "function" then
        return nil, failure(
            "missing-capability",
            ownerLabel .. "." .. methodName .. " is required"
        )
    end
    return methodOrError, nil
end

local function callOneArgumentNumber(target, method, argument, label)
    local ok, valueOrError = pcall(function()
        return method(target, argument)
    end)
    if not ok then
        return nil, failure("capability-error", label .. " failed: " .. tostring(valueOrError))
    end
    if not isFiniteNumber(valueOrError) then
        return nil, failure("invalid-value", label .. " must return a finite number")
    end
    return valueOrError, nil
end

local function copyCurve(curve, maximum)
    local copied = { [0] = curve[0] }
    for level = 1, maximum do
        copied[level] = curve[level]
    end
    return copied
end

local function copyRequirements(requirements, maximum)
    local copied = {}
    for level = 1, maximum do
        copied[level] = requirements[level]
    end
    return copied
end

local function numberToken(value)
    if value == 0 then
        return "0"
    end
    return string.format("%.17g", value)
end

local function fingerprintFor(thresholds, maximum)
    local parts = { "sla.vanilla.v1", tostring(maximum) }
    for level = 0, maximum do
        parts[#parts + 1] = tostring(level) .. "=" .. numberToken(thresholds[level])
    end
    return table.concat(parts, ";")
end

local function privateFor(handle)
    if type(handle) ~= "table" then
        return nil, failure("invalid-handle", "a VanillaProgressionAdapter handle is required")
    end
    local private = privateByHandle[handle]
    if private == nil then
        return nil, failure("invalid-handle", "the handle was not created by this adapter instance")
    end
    return private, nil
end

local function makeHandle(private)
    local identity = {
        adapterId = "sla.vanilla",
        adapterVersion = 1,
        curveFingerprint = private.curveFingerprint,
        effectiveMaximum = private.effectiveMaximum,
    }
    local handle = {}
    setmetatable(handle, {
        __index = identity,
        __newindex = function()
            error("VanillaProgressionAdapter handles are immutable")
        end,
        __metatable = "VanillaProgressionAdapter.handle",
    })
    privateByHandle[handle] = private
    return handle
end

function Adapter.build(perk, options)
    if perk == nil then
        return failure("missing-perk", "perk is required")
    end
    if options ~= nil and type(options) ~= "table" then
        return failure("invalid-options", "options must be a table when provided")
    end

    local discoveryLimit = DEFAULT_DISCOVERY_LIMIT
    if options ~= nil and options.discoveryLimit ~= nil then
        discoveryLimit = options.discoveryLimit
    end
    if not isInteger(discoveryLimit) or discoveryLimit < 1 then
        return failure("invalid-discovery-limit", "discoveryLimit must be a positive integer")
    end

    local getXpForLevel, capabilityFailure = getMethod(perk, "getXpForLevel", "perk")
    if getXpForLevel == nil then
        return capabilityFailure
    end

    local effectiveMaximum = nil
    for level = 1, discoveryLimit do
        local requirement, requirementFailure = callOneArgumentNumber(
            perk,
            getXpForLevel,
            level,
            "perk.getXpForLevel(" .. tostring(level) .. ")"
        )
        if requirement == nil then
            return requirementFailure
        end
        if requirement < 0 then
            effectiveMaximum = level - 1
            break
        end
    end

    if effectiveMaximum == nil then
        return failure(
            "discovery-limit-reached",
            "no negative getXpForLevel sentinel was found by discoveryLimit " .. tostring(discoveryLimit)
        )
    end
    if effectiveMaximum < 1 then
        return failure("invalid-effective-maximum", "the discovered effective maximum must be positive")
    end

    local getTotalXpForLevel
    getTotalXpForLevel, capabilityFailure = getMethod(perk, "getTotalXpForLevel", "perk")
    if getTotalXpForLevel == nil then
        return capabilityFailure
    end

    local thresholds = { [0] = 0 }
    local requirements = {}
    local previous = 0
    for level = 1, effectiveMaximum do
        local threshold, thresholdFailure = callOneArgumentNumber(
            perk,
            getTotalXpForLevel,
            level,
            "perk.getTotalXpForLevel(" .. tostring(level) .. ")"
        )
        if threshold == nil then
            return thresholdFailure
        end
        if threshold <= previous then
            return failure(
                "invalid-curve",
                "cumulative XP thresholds must be strictly increasing at level " .. tostring(level)
            )
        end
        thresholds[level] = threshold
        requirements[level] = threshold - previous
        previous = threshold
    end

    local private = {
        perk = perk,
        effectiveMaximum = effectiveMaximum,
        thresholds = thresholds,
        requirements = requirements,
        curveFingerprint = fingerprintFor(thresholds, effectiveMaximum),
    }
    return success({ handle = makeHandle(private) })
end

function Adapter.describe(handle)
    local private, handleFailure = privateFor(handle)
    if private == nil then
        return handleFailure
    end

    return success({
        adapterId = "sla.vanilla",
        adapterVersion = 1,
        curveFingerprint = private.curveFingerprint,
        effectiveMaximum = private.effectiveMaximum,
        cumulativeThresholds = copyCurve(private.thresholds, private.effectiveMaximum),
        perLevelRequirements = copyRequirements(private.requirements, private.effectiveMaximum),
    })
end

local function inspectState(private, player)
    if player == nil then
        return nil, failure("missing-player", "player is required")
    end

    local getPerkLevel, capabilityFailure = getMethod(player, "getPerkLevel", "player")
    if getPerkLevel == nil then
        return nil, capabilityFailure
    end
    local storedLevel, levelFailure = callOneArgumentNumber(
        player,
        getPerkLevel,
        private.perk,
        "player.getPerkLevel"
    )
    if storedLevel == nil then
        return nil, levelFailure
    end
    if not isInteger(storedLevel)
            or storedLevel < 0
            or storedLevel > private.effectiveMaximum then
        return nil, failure(
            "invalid-stored-level",
            "stored perk level must be an integer within the discovered curve"
        )
    end

    local getXp, getXpFailure = getMethod(player, "getXp", "player")
    if getXp == nil then
        return nil, getXpFailure
    end
    local xpStoreOK, xpStoreOrError = pcall(function()
        return getXp(player)
    end)
    if not xpStoreOK then
        return nil, failure("capability-error", "player.getXp failed: " .. tostring(xpStoreOrError))
    end
    if xpStoreOrError == nil then
        return nil, failure("missing-capability", "player.getXp must return an XP store")
    end

    local getTotalXp, getTotalXpFailure = getMethod(xpStoreOrError, "getXP", "XP store")
    if getTotalXp == nil then
        return nil, getTotalXpFailure
    end
    local totalXp, totalXpFailure = callOneArgumentNumber(
        xpStoreOrError,
        getTotalXp,
        private.perk,
        "XP store.getXP"
    )
    if totalXp == nil then
        return nil, totalXpFailure
    end
    if totalXp < 0 then
        return nil, failure("invalid-total-xp", "total cumulative XP cannot be negative")
    end

    local xpDerivedLevel = 0
    for level = 1, private.effectiveMaximum do
        if totalXp < private.thresholds[level] then
            break
        end
        xpDerivedLevel = level
    end

    local nextTargetLevel = nil
    local nextTargetPosition = nil
    if storedLevel < private.effectiveMaximum then
        nextTargetLevel = storedLevel + 1
        nextTargetPosition = private.thresholds[nextTargetLevel]
    end

    local alignment = "aligned"
    if storedLevel < xpDerivedLevel then
        alignment = "xp-ahead"
    elseif storedLevel > xpDerivedLevel then
        alignment = "level-ahead"
    end

    return {
        storedLevel = storedLevel,
        totalXp = totalXp,
        actualPosition = totalXp,
        xpDerivedLevel = xpDerivedLevel,
        effectiveMaximum = private.effectiveMaximum,
        nextTargetLevel = nextTargetLevel,
        nextTargetPosition = nextTargetPosition,
        levelAligned = storedLevel == xpDerivedLevel,
        alignment = alignment,
        xpStore = xpStoreOrError,
        getTotalXp = getTotalXp,
    }, nil
end

local function publicInspection(private, state)
    return success({
        adapterId = "sla.vanilla",
        adapterVersion = 1,
        curveFingerprint = private.curveFingerprint,
        storedLevel = state.storedLevel,
        totalXp = state.totalXp,
        actualPosition = state.actualPosition,
        xpDerivedLevel = state.xpDerivedLevel,
        effectiveMaximum = state.effectiveMaximum,
        nextTargetLevel = state.nextTargetLevel,
        nextTargetPosition = state.nextTargetPosition,
        levelAligned = state.levelAligned,
        alignment = state.alignment,
    })
end

function Adapter.inspect(handle, player)
    local private, handleFailure = privateFor(handle)
    if private == nil then
        return handleFailure
    end

    local state, inspectionFailure = inspectState(private, player)
    if state == nil then
        return inspectionFailure
    end
    return publicInspection(private, state)
end

local function ensureFailure(code, detail, xpWriteInvoked, levelWriteInvoked, extra)
    local fields = extra or {}
    fields.xpWriteInvoked = xpWriteInvoked
    fields.levelWriteInvoked = levelWriteInvoked
    return failure(code, detail, fields)
end

function Adapter.ensureTarget(handle, player, targetLevel, targetPosition)
    local private, handleFailure = privateFor(handle)
    if private == nil then
        handleFailure.xpWriteInvoked = false
        handleFailure.levelWriteInvoked = false
        return handleFailure
    end
    if not isInteger(targetLevel)
            or targetLevel < 1
            or targetLevel > private.effectiveMaximum then
        return ensureFailure(
            "invalid-target-level",
            "targetLevel must be a positive level within the discovered curve",
            false,
            false
        )
    end
    if not isFiniteNumber(targetPosition) or targetPosition < 0 then
        return ensureFailure(
            "invalid-target-position",
            "targetPosition must be finite and nonnegative",
            false,
            false
        )
    end
    if targetPosition ~= private.thresholds[targetLevel] then
        return ensureFailure(
            "target-position-mismatch",
            "targetPosition must exactly equal the cumulative threshold for targetLevel",
            false,
            false
        )
    end

    local state, inspectionFailure = inspectState(private, player)
    if state == nil then
        inspectionFailure.xpWriteInvoked = false
        inspectionFailure.levelWriteInvoked = false
        return inspectionFailure
    end
    if state.storedLevel > targetLevel then
        return ensureFailure(
            "target-behind-current-level",
            "targetLevel is behind the stored perk level",
            false,
            false
        )
    end
    if state.storedLevel < targetLevel - 1 then
        return ensureFailure(
            "target-is-not-next-level",
            "targetLevel must be the exact next stored level",
            false,
            false
        )
    end

    local needsXpWrite = state.totalXp < targetPosition
    local needsLevelWrite = state.storedLevel < targetLevel
    local setXpToLevel = nil
    local levelPerk = nil
    local capabilityFailure

    if needsXpWrite then
        setXpToLevel, capabilityFailure = getMethod(state.xpStore, "setXPToLevel", "XP store")
        if setXpToLevel == nil then
            capabilityFailure.xpWriteInvoked = false
            capabilityFailure.levelWriteInvoked = false
            return capabilityFailure
        end
    end
    if needsLevelWrite then
        levelPerk, capabilityFailure = getMethod(player, "LevelPerk", "player")
        if levelPerk == nil then
            capabilityFailure.xpWriteInvoked = false
            capabilityFailure.levelWriteInvoked = false
            return capabilityFailure
        end
    end

    local xpWriteInvoked = false
    local levelWriteInvoked = false
    local expectedXp = state.totalXp

    if needsXpWrite then
        xpWriteInvoked = true
        local xpWriteOK, xpWriteError = pcall(function()
            setXpToLevel(state.xpStore, private.perk, targetLevel)
        end)
        if not xpWriteOK then
            return ensureFailure(
                "xp-write-failed",
                "XP store.setXPToLevel failed: " .. tostring(xpWriteError),
                xpWriteInvoked,
                levelWriteInvoked
            )
        end

        local placedXp, placedXpFailure = callOneArgumentNumber(
            state.xpStore,
            state.getTotalXp,
            private.perk,
            "XP store.getXP"
        )
        if placedXp == nil then
            return ensureFailure(
                placedXpFailure.code,
                placedXpFailure.detail,
                xpWriteInvoked,
                levelWriteInvoked
            )
        end
        if placedXp ~= targetPosition then
            return ensureFailure(
                "xp-postcondition-failed",
                "setXPToLevel did not place XP at the exact cumulative target",
                xpWriteInvoked,
                levelWriteInvoked,
                { observedTotalXp = placedXp }
            )
        end
        expectedXp = targetPosition
    end

    if needsLevelWrite then
        levelWriteInvoked = true
        local levelWriteOK, levelWriteError = pcall(function()
            levelPerk(player, private.perk)
        end)
        if not levelWriteOK then
            return ensureFailure(
                "level-write-failed",
                "player.LevelPerk failed: " .. tostring(levelWriteError),
                xpWriteInvoked,
                levelWriteInvoked
            )
        end
    end

    local post, postFailure = inspectState(private, player)
    if post == nil then
        return ensureFailure(
            "post-inspection-failed",
            postFailure.code .. ": " .. postFailure.detail,
            xpWriteInvoked,
            levelWriteInvoked
        )
    end
    if post.storedLevel ~= targetLevel then
        return ensureFailure(
            "level-postcondition-failed",
            "stored perk level does not exactly equal targetLevel",
            xpWriteInvoked,
            levelWriteInvoked,
            { observedStoredLevel = post.storedLevel, observedTotalXp = post.totalXp }
        )
    end
    if post.totalXp ~= expectedXp then
        return ensureFailure(
            "xp-postcondition-failed",
            "total XP changed from the exact expected postcondition",
            xpWriteInvoked,
            levelWriteInvoked,
            { observedStoredLevel = post.storedLevel, observedTotalXp = post.totalXp }
        )
    end

    return success({
        status = (not xpWriteInvoked and not levelWriteInvoked) and "already-complete" or "target-ensured",
        xpWriteInvoked = xpWriteInvoked,
        levelWriteInvoked = levelWriteInvoked,
        storedLevel = post.storedLevel,
        totalXp = post.totalXp,
        actualPosition = post.actualPosition,
        targetLevel = targetLevel,
        targetPosition = targetPosition,
    })
end

return Adapter
