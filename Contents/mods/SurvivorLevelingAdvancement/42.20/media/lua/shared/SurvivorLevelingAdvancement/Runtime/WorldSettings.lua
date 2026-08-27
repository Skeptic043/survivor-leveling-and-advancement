local WorldSettings = {}

local allowedRawKeys = {
    survivorMultiplier = true,
    fitnessStrengthNormalization = true,
    automaticCurveNormalization = true,
    allotmentMode = true,
    globalLimit = true,
    perSkillDefault = true,
    perSkillOverrides = true,
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isNonnegativeInteger(value)
    return isFiniteNumber(value) and value >= 0 and value == math.floor(value)
end

local function isSafePerkId(perkId)
    return type(perkId) == "string"
        and perkId:match("^[%w%._:%-]+$") ~= nil
end

local function failed(code, detail)
    return {
        ok = false,
        code = code,
        detail = detail,
    }
end

local function noMetatable(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function copyNormalization(normalizationByPerk)
    if not noMetatable(normalizationByPerk) then
        return nil
    end

    local copy = {}
    local ok = pcall(function()
        for perkId, normalization in pairs(normalizationByPerk) do
            if not isSafePerkId(perkId)
                or not isFiniteNumber(normalization)
                or normalization <= 0 then
                error("invalid normalization")
            end
            copy[perkId] = normalization
        end
    end)

    if not ok then
        return nil
    end

    return copy
end

local function copyOverrides(overrides)
    if not noMetatable(overrides) then
        return nil
    end

    local copy = {}
    local ok = pcall(function()
        for perkId, limit in pairs(overrides) do
            if not isSafePerkId(perkId) or not isNonnegativeInteger(limit) then
                error("invalid per-skill override")
            end
            copy[perkId] = limit
        end
    end)

    if not ok then
        return nil
    end

    return copy
end

local function readRaw(provider)
    local called, raw = pcall(provider.read)
    if not called then
        return nil, "provider_failure", "provider.read failed"
    end
    if not noMetatable(raw) then
        return nil, "invalid_settings", "provider returned an invalid settings table"
    end

    local valid = pcall(function()
        for key in pairs(raw) do
            if not allowedRawKeys[key] then
                error("unexpected setting")
            end
        end
    end)
    if not valid then
        return nil, "invalid_settings", "settings contain an unexpected field"
    end

    local survivorMultiplier = rawget(raw, "survivorMultiplier")
    local fitnessStrengthNormalization = rawget(raw, "fitnessStrengthNormalization")
    local automaticCurveNormalization = rawget(raw, "automaticCurveNormalization")
    local allotmentMode = rawget(raw, "allotmentMode")
    local globalLimit = rawget(raw, "globalLimit")
    local perSkillDefault = rawget(raw, "perSkillDefault")
    local overrides = rawget(raw, "perSkillOverrides")

    if not isFiniteNumber(survivorMultiplier)
        or survivorMultiplier < 0
        or not isFiniteNumber(fitnessStrengthNormalization)
        or fitnessStrengthNormalization < 0
        or type(automaticCurveNormalization) ~= "boolean"
        or (allotmentMode ~= "Global" and allotmentMode ~= "PerSkill" and allotmentMode ~= "Free")
        or not isNonnegativeInteger(globalLimit)
        or not isNonnegativeInteger(perSkillDefault) then
        return nil, "invalid_settings", "settings contain an invalid scalar"
    end

    local copiedOverrides = copyOverrides(overrides)
    if copiedOverrides == nil then
        return nil, "invalid_settings", "settings contain invalid per-skill overrides"
    end

    return {
        survivorMultiplier = survivorMultiplier,
        fitnessStrengthNormalization = fitnessStrengthNormalization,
        automaticCurveNormalization = automaticCurveNormalization,
        allotmentMode = allotmentMode,
        globalLimit = globalLimit,
        perSkillDefault = perSkillDefault,
        perSkillOverrides = copiedOverrides,
    }
end

function WorldSettings.create(dependencies)
    if type(dependencies) ~= "table" then
        return failed("invalid_dependencies", "dependencies must be a table")
    end

    local provider = dependencies.provider
    if type(provider) ~= "table" or type(provider.read) ~= "function" then
        return failed("invalid_provider", "provider.read must be a function")
    end

    local normalizationByPerk = copyNormalization(dependencies.normalizationByPerk)
    if normalizationByPerk == nil then
        return failed("invalid_normalization", "normalizationByPerk must be a safe finite map")
    end

    local function resolveRaw(perkId)
        if not isSafePerkId(perkId) then
            return nil, "invalid_perk_id", "perkId is unsafe"
        end
        if normalizationByPerk[perkId] == nil then
            return nil, "unknown_perk", "perkId is not published"
        end
        return readRaw(provider)
    end

    local accountingSettings = {}

    function accountingSettings.resolve(_)
        local raw, code, detail = readRaw(provider)
        if raw == nil then
            return failed(code, detail)
        end
        local mode = "Tracked"
        if raw.allotmentMode == "Free" then mode = "Free" end
        return { ok = true, settings = { mode = mode } }
    end

    local awardSettings = {}

    function awardSettings.resolve(_, perkId)
        local raw, code, detail = resolveRaw(perkId)
        if raw == nil then
            return failed(code, detail)
        end

        local normalization = 1
        if perkId == "Fitness" or perkId == "Strength" then
            normalization = raw.fitnessStrengthNormalization
        elseif raw.automaticCurveNormalization then
            normalization = normalizationByPerk[perkId]
        end

        return {
            ok = true,
            settings = {
                accountingMode = raw.allotmentMode == "Free" and "Free" or "Tracked",
                normalization = normalization,
                survivorMultiplier = raw.survivorMultiplier,
                postMax = { enabled = false },
            },
        }
    end

    local allotmentSettings = {}

    function allotmentSettings.resolve(_, perkId)
        local raw, code, detail = resolveRaw(perkId)
        if raw == nil then
            return failed(code, detail)
        end

        if raw.allotmentMode == "Global" then
            return {
                ok = true,
                settings = {
                    mode = "Global",
                    globalLimit = raw.globalLimit,
                },
            }
        end

        if raw.allotmentMode == "PerSkill" then
            return {
                ok = true,
                settings = {
                    mode = "PerSkill",
                    perSkillDefault = raw.perSkillDefault,
                    perSkillOverrides = raw.perSkillOverrides,
                },
            }
        end

        return {
            ok = true,
            settings = { mode = "Free" },
        }
    end

    return {
        ok = true,
        accountingSettings = accountingSettings,
        awardSettings = awardSettings,
        allotmentSettings = allotmentSettings,
    }
end

return WorldSettings
