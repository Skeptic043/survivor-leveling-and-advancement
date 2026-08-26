local ClientOwnerState = {}

local PROTOCOL_VERSION = 1
local ROOT_FIELDS = {
    protocolVersion = true,
    ready = true,
    sequence = true,
    revision = true,
    survivor = true,
    perks = true,
}
local SURVIVOR_FIELDS = {
    level = true,
    xpIntoLevel = true,
    xpForNextLevel = true,
    spent = true,
    availableAp = true,
}
local PERK_FIELDS = {
    effectiveMaximum = true,
    naturalPosition = true,
    highWaterPosition = true,
    activeTargets = true,
}
local TARGET_FIELDS = {
    targetLevel = true,
    targetPosition = true,
}

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

local function beginTable(value, active)
    if type(value) ~= "table" then return nil, "not_table" end
    if getmetatable(value) ~= nil then return nil, "metatable" end
    if active[value] then return nil, "cycle" end
    active[value] = true
    return true
end

local function beginExactTable(value, fields, active)
    local entered, reason = beginTable(value, active)
    if not entered then return nil, reason end
    for key in pairs(value) do
        if type(key) ~= "string" or not fields[key] then
            active[value] = nil
            return nil, "fields"
        end
    end
    for key in pairs(fields) do
        if value[key] == nil then
            active[value] = nil
            return nil, "fields"
        end
    end
    return true
end

local function copySnapshot(snapshot)
    local perks = {}
    for perkId, perk in pairs(snapshot.perks) do
        local targets = {}
        for index = 1, #perk.activeTargets do
            local target = perk.activeTargets[index]
            targets[index] = {
                targetLevel = target.targetLevel,
                targetPosition = target.targetPosition,
            }
        end
        perks[perkId] = {
            effectiveMaximum = perk.effectiveMaximum,
            naturalPosition = perk.naturalPosition,
            highWaterPosition = perk.highWaterPosition,
            activeTargets = targets,
        }
    end
    return {
        protocolVersion = snapshot.protocolVersion,
        ready = snapshot.ready,
        sequence = snapshot.sequence,
        revision = snapshot.revision,
        survivor = {
            level = snapshot.survivor.level,
            xpIntoLevel = snapshot.survivor.xpIntoLevel,
            xpForNextLevel = snapshot.survivor.xpForNextLevel,
            spent = snapshot.survivor.spent,
            availableAp = snapshot.survivor.availableAp,
        },
        perks = perks,
    }
end

local function validateSurvivor(value, active)
    local entered, reason = beginExactTable(value, SURVIVOR_FIELDS, active)
    if not entered then return nil, failure("invalid_survivor", reason) end

    local valid = nonnegativeInteger(value.level)
        and finite(value.xpIntoLevel) and value.xpIntoLevel >= 0
        and positiveInteger(value.xpForNextLevel)
        and value.xpIntoLevel < value.xpForNextLevel
        and nonnegativeInteger(value.spent)
        and nonnegativeInteger(value.availableAp)
        and value.spent <= value.level
        and value.availableAp == value.level - value.spent
    if not valid then
        active[value] = nil
        return nil, failure("invalid_survivor", "values")
    end

    local survivor = {
        level = value.level,
        xpIntoLevel = value.xpIntoLevel,
        xpForNextLevel = value.xpForNextLevel,
        spent = value.spent,
        availableAp = value.availableAp,
    }
    active[value] = nil
    return survivor
end

local function validateTarget(value, effectiveMaximum, previousLevel, previousPosition, active)
    local entered, reason = beginExactTable(value, TARGET_FIELDS, active)
    if not entered then return nil, failure("invalid_target", reason) end

    local valid = positiveInteger(value.targetLevel)
        and value.targetLevel <= effectiveMaximum
        and finite(value.targetPosition) and value.targetPosition >= 0
        and value.targetLevel > previousLevel
        and value.targetPosition > previousPosition
    if not valid then
        active[value] = nil
        return nil, failure("invalid_target", "values")
    end

    local target = {
        targetLevel = value.targetLevel,
        targetPosition = value.targetPosition,
    }
    active[value] = nil
    return target
end

local function validateTargets(value, effectiveMaximum, highWaterPosition, active)
    local entered, reason = beginTable(value, active)
    if not entered then return nil, failure("invalid_targets", reason) end

    local length = #value
    for key in pairs(value) do
        if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > length then
            active[value] = nil
            return nil, failure("invalid_targets", "array_shape")
        end
    end

    local targets = {}
    local previousLevel = 0
    local previousPosition = highWaterPosition
    for index = 1, length do
        local target, targetFailure = validateTarget(value[index], effectiveMaximum, previousLevel, previousPosition, active)
        if target == nil then
            active[value] = nil
            return nil, targetFailure
        end
        targets[index] = target
        previousLevel = target.targetLevel
        previousPosition = target.targetPosition
    end
    active[value] = nil
    return targets
end

local function validatePerk(value, active)
    local entered, reason = beginExactTable(value, PERK_FIELDS, active)
    if not entered then return nil, failure("invalid_perk", reason) end

    local valid = positiveInteger(value.effectiveMaximum)
        and finite(value.naturalPosition) and value.naturalPosition >= 0
        and finite(value.highWaterPosition) and value.highWaterPosition >= value.naturalPosition
    if not valid then
        active[value] = nil
        return nil, failure("invalid_perk", "values")
    end

    local targets, targetFailure = validateTargets(
        value.activeTargets,
        value.effectiveMaximum,
        value.highWaterPosition,
        active
    )
    if targets == nil then
        active[value] = nil
        return nil, targetFailure
    end

    local perk = {
        effectiveMaximum = value.effectiveMaximum,
        naturalPosition = value.naturalPosition,
        highWaterPosition = value.highWaterPosition,
        activeTargets = targets,
    }
    active[value] = nil
    return perk
end

local function validatePerks(value, active)
    local entered, reason = beginTable(value, active)
    if not entered then return nil, failure("invalid_perks", reason) end

    local perks = {}
    for perkId, rawPerk in pairs(value) do
        if not safeId(perkId) then
            active[value] = nil
            return nil, failure("invalid_perks", "perk_id")
        end
        local perk, perkFailure = validatePerk(rawPerk, active)
        if perk == nil then
            active[value] = nil
            return nil, perkFailure
        end
        perks[perkId] = perk
    end
    active[value] = nil
    return perks
end

local function validateSnapshot(snapshot)
    local active = {}
    local entered, reason = beginExactTable(snapshot, ROOT_FIELDS, active)
    if not entered then return nil, failure("invalid_snapshot", reason) end
    if snapshot.protocolVersion ~= PROTOCOL_VERSION then
        active[snapshot] = nil
        return nil, failure("protocol_mismatch", "protocol_version")
    end
    if type(snapshot.ready) ~= "boolean" or not positiveInteger(snapshot.sequence)
        or not nonnegativeInteger(snapshot.revision) then
        active[snapshot] = nil
        return nil, failure("invalid_snapshot", "values")
    end

    local survivor, survivorFailure = validateSurvivor(snapshot.survivor, active)
    if survivor == nil then
        active[snapshot] = nil
        return nil, survivorFailure
    end
    local perks, perksFailure = validatePerks(snapshot.perks, active)
    if perks == nil then
        active[snapshot] = nil
        return nil, perksFailure
    end

    local checked = {
        protocolVersion = PROTOCOL_VERSION,
        ready = snapshot.ready,
        sequence = snapshot.sequence,
        revision = snapshot.revision,
        survivor = survivor,
        perks = perks,
    }
    active[snapshot] = nil
    return checked
end

function ClientOwnerState.validate(snapshot)
    local checked, invalid = validateSnapshot(snapshot)
    if checked == nil then return invalid end
    return { ok = true, snapshot = checked }
end

function ClientOwnerState.create()
    local current = nil
    local state = {}

    function state.accept(snapshot)
        local validated = ClientOwnerState.validate(snapshot)
        if not validated.ok then return validated end
        local checked = validated.snapshot
        if current ~= nil and checked.sequence <= current.sequence then
            return { ok = true, accepted = false, code = "stale_snapshot" }
        end
        current = checked
        return { ok = true, accepted = true }
    end

    function state.get()
        if current == nil then return { ok = true, present = false } end
        return { ok = true, present = true, snapshot = copySnapshot(current) }
    end

    function state.reset()
        current = nil
        return { ok = true }
    end

    function state.status()
        if current == nil then return { ok = true, present = false } end
        return {
            ok = true,
            present = true,
            ready = current.ready,
            sequence = current.sequence,
            revision = current.revision,
        }
    end

    return { ok = true, state = state }
end

return ClientOwnerState
