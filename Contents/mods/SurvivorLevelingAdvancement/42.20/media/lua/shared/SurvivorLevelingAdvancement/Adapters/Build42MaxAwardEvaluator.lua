local Build42MaxAwardEvaluator = {}

local MAX_PERK_LIST_SIZE = 256

local function failure(reason)
    return { ok = false, reason = reason }
end

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function readField(owner, name)
    if owner == nil then
        return false, nil
    end

    return pcall(function()
        return owner[name]
    end)
end

local function readCallable(owner, name)
    local ok, value = readField(owner, name)
    return ok and type(value) == "function", value
end

local function callMethod(owner, name, ...)
    local ok, method = readCallable(owner, name)
    if not ok then
        return false, nil
    end

    return pcall(method, owner, ...)
end

local function callStatic(owner, name, ...)
    local ok, method = readCallable(owner, name)
    if not ok then
        return false, nil
    end

    return pcall(method, ...)
end

local function requireField(owner, name, reason)
    local ok, value = readField(owner, name)
    if not ok or value == nil then
        return nil, failure(reason)
    end

    return value, nil
end

local function requireCallable(owner, name, reason)
    local ok, value = readCallable(owner, name)
    if not ok then
        return nil, failure(reason)
    end

    return value, nil
end

function Build42MaxAwardEvaluator.create(dependencies)
    if type(dependencies) ~= "table" then
        return failure("capability.dependencies")
    end

    local pzMath, createFailure = requireField(dependencies, "PZMath", "capability.PZMath")
    if createFailure then return createFailure end
    local _, missing = requireCallable(pzMath, "clampFloat", "capability.PZMath.clampFloat")
    if missing then return missing end
    _, missing = requireCallable(pzMath, "tryParseFloat", "capability.PZMath.tryParseFloat")
    if missing then return missing end

    local perkFactory
    perkFactory, createFailure = requireField(dependencies, "PerkFactory", "capability.PerkFactory")
    if createFailure then return createFailure end
    local perkList
    perkList, createFailure = requireField(perkFactory, "PerkList", "capability.PerkFactory.PerkList")
    if createFailure then return createFailure end
    _, missing = requireCallable(perkList, "size", "capability.PerkFactory.PerkList.size")
    if missing then return missing end
    _, missing = requireCallable(perkList, "get", "capability.PerkFactory.PerkList.get")
    if missing then return missing end

    local perks
    perks, createFailure = requireField(dependencies, "Perks", "capability.Perks")
    if createFailure then return createFailure end
    local requiredPerks = {
        "Fitness", "Strength", "Sprinting", "SmallBlade", "LongBlade",
        "SmallBlunt", "Spear", "Blunt", "Axe", "Aiming", "Crafting",
    }
    for _, name in ipairs(requiredPerks) do
        local _, perkFailure = requireField(perks, name, "capability.Perks." .. name)
        if perkFailure then return perkFailure end
    end

    local characterTrait
    characterTrait, createFailure = requireField(dependencies, "CharacterTrait", "capability.CharacterTrait")
    if createFailure then return createFailure end
    local requiredTraits = { "FAST_LEARNER", "SLOW_LEARNER", "PACIFIST", "CRAFTY" }
    for _, name in ipairs(requiredTraits) do
        local _, traitFailure = requireField(characterTrait, name, "capability.CharacterTrait." .. name)
        if traitFailure then return traitFailure end
    end

    local sandboxOptions
    sandboxOptions, createFailure = requireField(dependencies, "SandboxOptions", "capability.SandboxOptions")
    if createFailure then return createFailure end
    _, missing = requireCallable(sandboxOptions, "getOptionByName", "capability.SandboxOptions.getOptionByName")
    if missing then return missing end
    local multipliersConfig
    multipliersConfig, createFailure = requireField(sandboxOptions, "multipliersConfig", "capability.SandboxOptions.multipliersConfig")
    if createFailure then return createFailure end
    local globalToggle
    globalToggle, createFailure = requireField(multipliersConfig, "xpMultiplierGlobalToggle", "capability.MultiplierConfig.xpMultiplierGlobalToggle")
    if createFailure then return createFailure end
    _, missing = requireCallable(globalToggle, "getValue", "capability.MultiplierConfig.xpMultiplierGlobalToggle.getValue")
    if missing then return missing end
    local globalMultiplier
    globalMultiplier, createFailure = requireField(multipliersConfig, "xpMultiplierGlobal", "capability.MultiplierConfig.xpMultiplierGlobal")
    if createFailure then return createFailure end
    _, missing = requireCallable(globalMultiplier, "getValue", "capability.MultiplierConfig.xpMultiplierGlobal.getValue")
    if missing then return missing end

    local function routeFloat(value)
        if not isFinite(value) then
            return nil
        end

        local ok, routed = callStatic(pzMath, "clampFloat", value, value, value)
        if not ok or not isFinite(routed) then
            return nil
        end

        return routed
    end

    local function findCanonicalPerk(perk)
        local sizeOk, size = callMethod(perkList, "size")
        if not sizeOk or not isFinite(size) or size ~= math.floor(size)
            or size < 1 or size > MAX_PERK_LIST_SIZE then
            return nil, "perk.registry"
        end

        for index = 0, size - 1 do
            local getOk, candidate = callMethod(perkList, "get", index)
            if not getOk or candidate == nil then
                return nil, "perk.registry"
            end

            local typeOk, candidateType = callMethod(candidate, "getType")
            if not typeOk or candidateType == nil then
                return nil, "perk.registry"
            end
            if candidateType == perk then
                return candidate, nil
            end
        end

        return nil, "perk.noncanonical"
    end

    local function readBooleanMethod(owner, name, reason, ...)
        local ok, value = callMethod(owner, name, ...)
        if not ok or type(value) ~= "boolean" then
            return nil, failure(reason)
        end

        return value, nil
    end

    local function readTrait(player, trait, reason)
        return readBooleanMethod(player, "hasTrait", reason, trait)
    end

    local function multiplyFloat(left, right)
        local routedRight = routeFloat(right)
        if routedRight == nil then
            return nil
        end

        return routeFloat(left * routedRight)
    end

    local function readSandboxMultiplier(canonicalPerk)
        local toggle, toggleFailure = readBooleanMethod(
            globalToggle,
            "getValue",
            "sandbox.global-toggle"
        )
        if toggleFailure then return nil, toggleFailure end

        if toggle then
            local valueOk, value = callMethod(globalMultiplier, "getValue")
            if not valueOk or not isFinite(value) or value < 0 then
                return nil, failure("sandbox.global-multiplier")
            end

            local routed = routeFloat(value)
            if routed == nil or routed < 0 then
                return nil, failure("sandbox.global-multiplier")
            end
            return routed, nil
        end

        local idOk, perkId = callMethod(canonicalPerk, "getId")
        if not idOk or type(perkId) ~= "string" or perkId == "" then
            return nil, failure("sandbox.perk-identity")
        end

        local optionName = "MultiplierConfig." .. perkId
        local optionOk, option = callMethod(sandboxOptions, "getOptionByName", optionName)
        if not optionOk or option == nil then
            return nil, failure("sandbox.perk-option")
        end

        local configOk, config = callMethod(option, "asConfigOption")
        if not configOk or config == nil then
            return nil, failure("sandbox.perk-option")
        end
        local nameOk, resolvedName = callMethod(config, "getName")
        if not nameOk or resolvedName ~= optionName then
            return nil, failure("sandbox.perk-option")
        end
        local valueOk, encoded = callMethod(config, "getValueAsString")
        if not valueOk or type(encoded) ~= "string" then
            return nil, failure("sandbox.perk-option")
        end

        local parseOk, value = callStatic(pzMath, "tryParseFloat", encoded, -1)
        if not parseOk or not isFinite(value) or value < 0 then
            return nil, failure("sandbox.perk-multiplier")
        end
        return value, nil
    end

    local evaluator = {}

    function evaluator.describe()
        return {
            ok = true,
            adapterId = "sla.pz42-max-award",
            adapterVersion = 1,
            representation = "java-binary32",
        }
    end

    function evaluator.evaluate(player, perk, routedBaseAward, useMultipliers)
        if player == nil then
            return failure("player.missing")
        end
        if perk == nil then
            return failure("perk.missing")
        end
        if type(useMultipliers) ~= "boolean" then
            return failure("input.useMultipliers")
        end

        local dead, readFailure = readBooleanMethod(player, "isDead", "player.isDead")
        if readFailure then return readFailure end
        if dead then return failure("player.dead") end

        local asleep
        asleep, readFailure = readBooleanMethod(player, "isAsleep", "player.isAsleep")
        if readFailure then return readFailure end
        if asleep then return failure("player.asleep") end

        local canonicalPerk, perkFailure = findCanonicalPerk(perk)
        if perkFailure then return failure(perkFailure) end

        local baseAward = routeFloat(routedBaseAward)
        if baseAward == nil or baseAward <= 0 then
            return failure("award.base")
        end

        if perk == perks.Fitness then
            local nutritionOk, nutrition = callMethod(player, "getNutrition")
            if not nutritionOk or nutrition == nil then
                return failure("fitness.nutrition")
            end
            local allowed, fitnessFailure = readBooleanMethod(
                nutrition,
                "canAddFitnessXp",
                "fitness.eligibility"
            )
            if fitnessFailure then return fitnessFailure end
            if not allowed then return failure("fitness.ineligible") end
        elseif perk == perks.Strength then
            local nutritionOk, nutrition = callMethod(player, "getNutrition")
            if not nutritionOk or nutrition == nil then
                return failure("strength.nutrition")
            end
            local proteinsOk, proteins = callMethod(nutrition, "getProteins")
            if not proteinsOk or not isFinite(proteins) then
                return failure("strength.proteins")
            end

            if proteins > 50 and proteins < 300 then
                baseAward = multiplyFloat(baseAward, 1.5)
            elseif proteins < -300 then
                baseAward = multiplyFloat(baseAward, 0.7)
            end
            if baseAward == nil or baseAward <= 0 then
                return failure("award.strength")
            end
        end

        local xpOk, xp = callMethod(player, "getXp")
        if not xpOk or xp == nil then
            return failure("player.xp")
        end

        local currentOk, currentXp = callMethod(xp, "getXP", perk)
        if not currentOk or not isFinite(currentXp) then
            return failure("cap.current-xp")
        end
        local maximumOk, maximumXp = callMethod(canonicalPerk, "getTotalXpForLevel", 10)
        if not maximumOk or not isFinite(maximumXp) then
            return failure("cap.maximum-xp")
        end
        if maximumXp <= 0 then
            return failure("cap.maximum-nonpositive")
        end
        if currentXp < maximumXp then
            return failure("cap.below-maximum")
        end
        if currentXp > maximumXp then
            return failure("cap.above-maximum")
        end

        if not useMultipliers then
            return { ok = true, effectiveDelta = baseAward }
        end

        local boostOk, boost = callMethod(xp, "getPerkBoost", perk)
        if not boostOk or not isFinite(boost) or boost < 0 or boost ~= math.floor(boost) then
            return failure("boost.value")
        end

        local factor = 1
        if boost == 0 then
            if perk ~= perks.Sprinting and perk ~= perks.Fitness and perk ~= perks.Strength then
                factor = routeFloat(0.25)
            end
        elseif boost == 1 then
            if perk == perks.Sprinting then
                factor = multiplyFloat(factor, 1.25)
            else
                factor = multiplyFloat(factor, 1)
            end
        elseif boost == 2 then
            if perk ~= perks.Fitness and perk ~= perks.Strength then
                factor = multiplyFloat(factor, 1.33)
            end
        elseif perk ~= perks.Fitness and perk ~= perks.Strength then
            factor = multiplyFloat(factor, 1.66)
        end
        if factor == nil or factor < 0 then
            return failure("boost.result")
        end

        local fastLearner
        fastLearner, readFailure = readTrait(player, characterTrait.FAST_LEARNER, "trait.fast-learner")
        if readFailure then return readFailure end
        if fastLearner and perk ~= perks.Fitness and perk ~= perks.Strength then
            factor = multiplyFloat(factor, 1.3)
        end

        local slowLearner
        slowLearner, readFailure = readTrait(player, characterTrait.SLOW_LEARNER, "trait.slow-learner")
        if readFailure then return readFailure end
        if slowLearner and perk ~= perks.Sprinting and perk ~= perks.Fitness and perk ~= perks.Strength then
            factor = multiplyFloat(factor, 0.7)
        end

        local pacifist
        pacifist, readFailure = readTrait(player, characterTrait.PACIFIST, "trait.pacifist")
        if readFailure then return readFailure end
        if pacifist and (
            perk == perks.SmallBlade
            or perk == perks.LongBlade
            or perk == perks.SmallBlunt
            or perk == perks.Spear
            or perk == perks.Blunt
            or perk == perks.Axe
            or perk == perks.Aiming
        ) then
            factor = multiplyFloat(factor, 0.75)
        end

        local crafty
        crafty, readFailure = readTrait(player, characterTrait.CRAFTY, "trait.crafty")
        if readFailure then return readFailure end
        if crafty then
            local parentOk, parent = callMethod(canonicalPerk, "getParent")
            if not parentOk then
                return failure("perk.parent")
            end
            if parent == perks.Crafting then
                factor = multiplyFloat(factor, 1.3)
            end
        end

        if factor == nil or factor < 0 then
            return failure("factor.result")
        end
        local effectiveDelta = multiplyFloat(baseAward, factor)
        if effectiveDelta == nil then
            return failure("award.factor")
        end

        local multiplierOk, bookMultiplier = callMethod(xp, "getMultiplier", perk)
        if not multiplierOk or not isFinite(bookMultiplier) or bookMultiplier < 0 then
            return failure("book.multiplier")
        end
        if bookMultiplier > 1 then
            effectiveDelta = multiplyFloat(effectiveDelta, bookMultiplier)
            if effectiveDelta == nil then
                return failure("award.book")
            end
        end

        local sandboxMultiplier, sandboxFailure = readSandboxMultiplier(canonicalPerk)
        if sandboxFailure then return sandboxFailure end
        effectiveDelta = multiplyFloat(effectiveDelta, sandboxMultiplier)
        if effectiveDelta == nil or effectiveDelta <= 0 then
            return failure("award.effective")
        end

        return { ok = true, effectiveDelta = effectiveDelta }
    end

    return { ok = true, evaluator = evaluator }
end

return Build42MaxAwardEvaluator
