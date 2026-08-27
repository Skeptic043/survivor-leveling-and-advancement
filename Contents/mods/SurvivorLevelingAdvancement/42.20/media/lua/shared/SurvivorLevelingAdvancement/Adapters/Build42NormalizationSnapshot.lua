local Build42NormalizationSnapshot = {}

local function failure(code, detail)
    return {
        ok = false,
        code = code,
        detail = detail,
    }
end

local function isFinitePositive(value)
    return type(value) == "number"
        and value == value
        and value > 0
        and value ~= (1 / 0)
end

local function isSafePerkId(value)
    return type(value) == "string"
        and value ~= ""
        and value:match("^[%w%._:%-]+$") ~= nil
end

local function isDenseArray(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= key or key % 1 ~= 0 then
            return false
        end
        count = count + 1
    end

    for index = 1, count do
        if rawget(value, index) == nil then
            return false
        end
    end

    return true, count
end

local function firstTenRequirements(description)
    if type(description) ~= "table" then
        return nil
    end

    local requirements = description.perLevelRequirements
    if type(requirements) ~= "table" then
        return nil
    end

    local firstTen = {}
    for index = 1, 10 do
        local requirement = requirements[index]
        if not isFinitePositive(requirement) then
            return nil
        end
        firstTen[index] = requirement
    end

    return firstTen
end

local function automaticNormalization(economy, description)
    local requirements = firstTenRequirements(description)
    if requirements == nil then
        return nil
    end

    local called, result = pcall(economy.normalizationFromCoreCurve, requirements)
    if not called or type(result) ~= "table" or result.ok ~= true then
        return nil
    end
    if not isFinitePositive(result.normalization) then
        return nil
    end

    return result.normalization
end

local function isMarkedCustom(perk)
    local read, marker = pcall(function()
        return perk.isCustom
    end)
    if not read or type(marker) ~= "function" then
        return false
    end

    local called, result = pcall(marker, perk)
    return called and result == true
end

function Build42NormalizationSnapshot.build(dependencies)
    if type(dependencies) ~= "table"
        or type(dependencies.catalog) ~= "table"
        or type(dependencies.catalog.allPerks) ~= "function"
        or type(dependencies.catalog.perkIdentity) ~= "table"
        or type(dependencies.catalog.perkIdentity.resolve) ~= "function"
        or type(dependencies.catalog.resolver) ~= "table"
        or type(dependencies.catalog.resolver.resolve) ~= "function"
        or type(dependencies.SurvivorEconomy) ~= "table"
        or type(dependencies.SurvivorEconomy.normalizationFromCoreCurve) ~= "function" then
        return failure("INVALID_DEPENDENCIES", "catalog and SurvivorEconomy surfaces are required")
    end

    local catalog = dependencies.catalog
    local economy = dependencies.SurvivorEconomy
    local enumerated, enumeration = pcall(catalog.allPerks)
    if not enumerated then
        return failure("CATALOG_ENUMERATION_FAILED", "allPerks threw")
    end
    if type(enumeration) ~= "table" or enumeration.ok ~= true then
        return failure("CATALOG_ENUMERATION_FAILED", "allPerks did not succeed")
    end

    local dense, perkCount = isDenseArray(enumeration.perks)
    if not dense then
        return failure("CATALOG_ENUMERATION_INVALID", "published perks must be a dense array")
    end

    local normalizationByPerk = {}
    local automaticCount = 0
    local fallbackCount = 0

    for index = 1, perkCount do
        local perk = enumeration.perks[index]
        local identified, identity = pcall(catalog.perkIdentity.resolve, perk)
        if not identified or type(identity) ~= "table" or identity.ok ~= true then
            return failure("PERK_IDENTITY_FAILED", "published perk identity did not succeed")
        end
        if not isSafePerkId(identity.perkId) then
            return failure("PERK_ID_INVALID", "published perk identity is empty, unsafe, or non-string")
        end
        if normalizationByPerk[identity.perkId] ~= nil then
            return failure("PERK_ID_DUPLICATE", "published perk identities must be unique")
        end

        local resolved, resolution = pcall(catalog.resolver.resolve, identity.perkId)
        if not resolved or type(resolution) ~= "table" or resolution.ok ~= true then
            return failure("PERK_RESOLUTION_FAILED", "published perk did not resolve")
        end
        if type(resolution.adapter) ~= "table" or type(resolution.adapter.describe) ~= "function"
            or resolution.handle == nil then
            return failure("PERK_RESOLUTION_INVALID", "resolved perk is missing its adapter or handle")
        end

        local described, description = pcall(resolution.adapter.describe, resolution.handle)
        if not described or type(description) ~= "table" or description.ok ~= true then
            return failure("PERK_DESCRIPTION_FAILED", "resolved perk description did not succeed")
        end

        local normalization = nil
        if isMarkedCustom(perk) then
            normalization = automaticNormalization(economy, description)
        end
        if normalization == nil then
            normalizationByPerk[identity.perkId] = 1.0
            fallbackCount = fallbackCount + 1
        else
            normalizationByPerk[identity.perkId] = normalization
            automaticCount = automaticCount + 1
        end
    end

    return {
        ok = true,
        normalizationByPerk = normalizationByPerk,
        automaticCount = automaticCount,
        fallbackCount = fallbackCount,
    }
end

return Build42NormalizationSnapshot
