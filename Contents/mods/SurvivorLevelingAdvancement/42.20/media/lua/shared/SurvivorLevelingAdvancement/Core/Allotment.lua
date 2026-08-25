local Allotment = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function nonnegativeInteger(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value >= 0 and value == math.floor(value)
end

local function validPerkId(perkId)
    return type(perkId) == "string" and perkId ~= ""
end

local function validateActive(activeByPerk)
    if type(activeByPerk) ~= "table" then
        return failure("invalid_active_targets", "activeByPerk must be a table")
    end
    for perkId, count in pairs(activeByPerk) do
        if not validPerkId(perkId) or not nonnegativeInteger(count) then
            return failure("invalid_active_targets", "active target counts must be nonnegative integers")
        end
    end
    return { ok = true }
end

local function globalCount(activeByPerk)
    local total = 0
    for _, count in pairs(activeByPerk) do
        total = total + count
    end
    return total
end

function Allotment.evaluate(config, perkId, activeByPerk, addsTarget)
    if type(config) ~= "table" then
        return failure("invalid_config", "config must be a table")
    end
    if not validPerkId(perkId) then
        return failure("invalid_perk", "perkId must be a nonempty string")
    end
    if type(addsTarget) ~= "boolean" then
        return failure("invalid_config", "addsTarget must be a boolean")
    end
    local active = validateActive(activeByPerk)
    if not active.ok then
        return active
    end

    local mode = config.mode
    if mode ~= "Global" and mode ~= "PerSkill" and mode ~= "Free" then
        return failure("invalid_mode", "mode must be Global, PerSkill, or Free")
    end
    local limit = nil
    if mode == "Global" then
        limit = config.globalLimit
        if not nonnegativeInteger(limit) then
            return failure("invalid_config", "globalLimit must be a nonnegative integer")
        end
    elseif mode == "PerSkill" then
        if not nonnegativeInteger(config.perSkillDefault) then
            return failure("invalid_config", "perSkillDefault must be a nonnegative integer")
        end
        limit = config.perSkillDefault
        if config.perSkillOverrides ~= nil then
            if type(config.perSkillOverrides) ~= "table" then
                return failure("invalid_config", "perSkillOverrides must be a table")
            end
            for overridePerkId, override in pairs(config.perSkillOverrides) do
                if not validPerkId(overridePerkId) or not nonnegativeInteger(override) then
                    return failure("invalid_config", "perSkillOverrides must contain nonnegative integer values")
                end
            end
            if config.perSkillOverrides[perkId] ~= nil then
                limit = config.perSkillOverrides[perkId]
            end
        end
    end
    if not addsTarget then
        return { ok = true, allowed = true, mode = mode, bypassed = true, activeCount = activeByPerk[perkId] or 0 }
    end
    if mode == "Free" then
        return { ok = true, allowed = true, mode = mode, bypassed = false, activeCount = activeByPerk[perkId] or 0 }
    end
    if mode == "Global" then
        local count = globalCount(activeByPerk)
        return { ok = true, allowed = count < limit, mode = mode, bypassed = false, activeCount = count, limit = limit }
    end

    local count = activeByPerk[perkId] or 0
    return { ok = true, allowed = count < limit, mode = mode, bypassed = false, activeCount = count, limit = limit }
end

return Allotment
