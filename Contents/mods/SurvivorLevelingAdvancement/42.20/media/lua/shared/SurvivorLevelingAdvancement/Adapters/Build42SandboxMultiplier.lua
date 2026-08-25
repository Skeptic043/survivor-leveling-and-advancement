local Build42SandboxMultiplier = {}

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
        and value ~= math.huge
        and value ~= -math.huge
        and value > 0
end

local function isSafePerkId(perkId)
    return type(perkId) == "string"
        and perkId:match("^[%w%._:%-]+$") ~= nil
end

local function readField(owner, name)
    if owner == nil then
        return false, nil
    end

    return pcall(function()
        return owner[name]
    end)
end

local function callMethod(owner, name, ...)
    local fieldOK, method = readField(owner, name)
    if not fieldOK or type(method) ~= "function" then
        return false, nil
    end

    return pcall(method, owner, ...)
end

local function callStatic(owner, name, ...)
    local fieldOK, method = readField(owner, name)
    if not fieldOK or type(method) ~= "function" then
        return false, nil
    end

    return pcall(method, ...)
end

function Build42SandboxMultiplier.create(dependencies)
    if type(dependencies) ~= "table" then
        return failure("invalid-dependencies", "dependencies must be a table")
    end

    local sandboxOK, sandboxOptions = readField(dependencies, "SandboxOptions")
    if not sandboxOK or sandboxOptions == nil then
        return failure("invalid-dependencies", "SandboxOptions is required")
    end
    local mathOK, pzMath = readField(dependencies, "PZMath")
    if not mathOK or pzMath == nil then
        return failure("invalid-dependencies", "PZMath is required")
    end

    local resolver = {}

    function resolver.resolve(_, perkId)
        if not isSafePerkId(perkId) then
            return failure("invalid-perk-id", "perkId must be a safe nonempty ID")
        end

        local sandboxOK, sandboxOptions = readField(dependencies, "SandboxOptions")
        if not sandboxOK or sandboxOptions == nil then
            return failure("capability.sandbox-options", "SandboxOptions is required")
        end

        local configOK, multipliersConfig = readField(sandboxOptions, "multipliersConfig")
        if not configOK or multipliersConfig == nil then
            return failure("capability.multipliers-config", "SandboxOptions.multipliersConfig is required")
        end

        local toggleOK, globalToggle = readField(multipliersConfig, "xpMultiplierGlobalToggle")
        if not toggleOK or globalToggle == nil then
            return failure("capability.global-toggle", "xpMultiplierGlobalToggle is required")
        end

        local valueOK, globalMode = callMethod(globalToggle, "getValue")
        if not valueOK or type(globalMode) ~= "boolean" then
            return failure("capability.global-toggle", "xpMultiplierGlobalToggle.getValue must return boolean")
        end

        local mathOK, pzMath = readField(dependencies, "PZMath")
        if not mathOK or pzMath == nil then
            return failure("capability.pz-math", "PZMath is required")
        end

        if globalMode then
            local multiplierOK, globalMultiplier = readField(multipliersConfig, "xpMultiplierGlobal")
            if not multiplierOK or globalMultiplier == nil then
                return failure("capability.global-multiplier", "xpMultiplierGlobal is required")
            end

            local value
            valueOK, value = callMethod(globalMultiplier, "getValue")
            if not valueOK or not isFinitePositive(value) then
                return failure("invalid-global-multiplier", "xpMultiplierGlobal.getValue must return a finite positive number")
            end

            local routedOK, multiplier = callStatic(pzMath, "clampFloat", value, value, value)
            if not routedOK or not isFinitePositive(multiplier) then
                return failure("invalid-global-multiplier", "PZMath.clampFloat must return a finite positive number")
            end

            return {
                ok = true,
                multiplier = multiplier,
            }
        end

        local optionName = "MultiplierConfig." .. perkId
        local optionOK, option = callMethod(sandboxOptions, "getOptionByName", optionName)
        if not optionOK or option == nil then
            return failure("capability.perk-option", "SandboxOptions.getOptionByName must resolve the perk option")
        end

        local configOK, configOption = callMethod(option, "asConfigOption")
        if not configOK or configOption == nil then
            return failure("capability.perk-option", "perk option must expose a config option")
        end

        local nameOK, resolvedName = callMethod(configOption, "getName")
        if not nameOK or resolvedName ~= optionName then
            return failure("invalid-perk-option", "resolved option name must match the requested perk option")
        end

        local encoded
        valueOK, encoded = callMethod(configOption, "getValueAsString")
        if not valueOK or type(encoded) ~= "string" then
            return failure("invalid-perk-option", "perk option must provide an encoded value")
        end

        local parsedOK, multiplier = callStatic(pzMath, "tryParseFloat", encoded, -1)
        if not parsedOK or not isFinitePositive(multiplier) then
            return failure("invalid-perk-multiplier", "perk multiplier must parse to a finite positive number")
        end

        return {
            ok = true,
            multiplier = multiplier,
        }
    end

    return {
        ok = true,
        resolver = resolver,
    }
end

return Build42SandboxMultiplier
