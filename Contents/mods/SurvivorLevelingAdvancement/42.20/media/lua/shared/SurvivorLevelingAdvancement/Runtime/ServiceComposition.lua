local ServiceComposition = {}

local function failure(code, detail)
    return {
        ok = false,
        code = code,
        detail = detail,
    }
end

local function isCallable(value)
    return type(value) == "function"
end

local function hasFunctions(value, names)
    if type(value) ~= "table" then
        return false
    end

    for index = 1, #names do
        if not isCallable(value[names[index]]) then
            return false
        end
    end

    return true
end

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isSafeId(value)
    return type(value) == "string"
        and value ~= ""
        and string.match(value, "^[%w%._:%-]+$") ~= nil
end

local function detachNormalization(source)
    if type(source) ~= "table" or getmetatable(source) ~= nil then
        return nil
    end

    local detached = {}
    for perkId, normalization in pairs(source) do
        if not isSafeId(perkId) or not isFinite(normalization) or normalization <= 0 then
            return nil
        end
        detached[perkId] = normalization
    end

    return detached
end

local function stableDetail(detail, fallback)
    if type(detail) == "string" and detail ~= "" then
        return detail
    end
    return fallback
end

local function boundedCode(value)
    if type(value) ~= "string" or value == "" or #value > 64 then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if not ((byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
            or byte == 45 or byte == 46 or byte == 58 or byte == 95) then return false end
    end
    return true
end

local function boundedDetail(value)
    if type(value) ~= "string" or value == "" or #value > 160 then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte > 126 then return false end
    end
    return true
end

local function exactPlain(value, fields)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do if type(key) ~= "string" or not fields[key] then return false end end
    for key in pairs(fields) do if rawget(value, key) == nil then return false end end
    return true
end

local function validateDependencies(dependencies)
    if type(dependencies) ~= "table" then
        return failure("invalid_dependencies", "dependencies must be a table")
    end

    local requiredCapabilities = {
        { "StateCodec", { "decode", "encode" } },
        { "NaturalLedger", { "baseline", "inspect", "reconcileExternal", "appendTarget", "master", "applySupported" } },
        { "SurvivorEconomy", { "availableAp", "nextLevelCost", "computeAward", "applyXp" } },
        { "Allotment", { "evaluate" } },
        { "PostMax", { "apply" } },
        { "sandboxMultiplier", { "resolve" } },
        { "positionArithmetic", { "add" } },
        { "authority", { "describe" } },
        { "playerIdentity", { "isPlayer" } },
    }
    for index = 1, #requiredCapabilities do
        local entry = requiredCapabilities[index]
        if not hasFunctions(dependencies[entry[1]], entry[2]) then
            return failure("invalid_dependencies", entry[1] .. " capabilities are required")
        end
    end

    if type(dependencies.environment) ~= "table" or type(dependencies.environment.globals) ~= "table" then
        return failure("invalid_dependencies", "environment.globals is required")
    end

    local factories = {
        "PlayerStateStore",
        "AccountingMode",
        "OwnerSnapshot",
        "ApTransaction",
        "SupportedAwardProcessor",
        "WorldSettings",
        "EventDerivedXpSource",
        "OwnerSession",
    }
    for index = 1, #factories do
        local name = factories[index]
        if not hasFunctions(dependencies[name], { "create" }) then
            return failure("invalid_dependencies", name .. ".create is required")
        end
    end

    local advancement = rawget(dependencies, "AdvancementSession")
    if type(advancement) ~= "table" or getmetatable(advancement) ~= nil or type(rawget(advancement, "create")) ~= "function" then
        return failure("invalid_dependencies", "AdvancementSession.create is required")
    end

    local admin = rawget(dependencies, "AdminSession")
    if type(admin) ~= "table" or getmetatable(admin) ~= nil or type(rawget(admin, "create")) ~= "function" then
        return failure("invalid_dependencies", "AdminSession.create is required")
    end

    if not hasFunctions(dependencies.MutationScope, { "begin", "isActive", "finish" }) then
        return failure("invalid_dependencies", "MutationScope capabilities are required")
    end
    if not hasFunctions(dependencies.ActualObservation, { "get", "set", "clearPlayer" }) then
        return failure("invalid_dependencies", "ActualObservation capabilities are required")
    end
    if not hasFunctions(dependencies.worldSettingsProvider, { "read" }) then
        return failure("invalid_dependencies", "worldSettingsProvider.read is required")
    end

    local catalog = dependencies.catalog
    if type(catalog) ~= "table"
        or not isCallable(catalog.allPerks)
        or not hasFunctions(catalog.resolver, { "resolve" })
        or type(catalog.resolver.loadOptions) ~= "table"
        or not hasFunctions(catalog.perkIdentity, { "resolve" })
        or not hasFunctions(catalog.positionReader, { "read" }) then
        return failure("invalid_dependencies", "catalog capabilities are required")
    end

    local normalizationCallOk, normalizationByPerk = pcall(detachNormalization, dependencies.normalizationByPerk)
    if not normalizationCallOk or normalizationByPerk == nil then
        return failure("invalid_dependencies", "normalizationByPerk is malformed")
    end

    return {
        ok = true,
        normalizationByPerk = normalizationByPerk,
    }
end

local function callAdvancementSession(factory, argument)
    local create = rawget(factory, "create")
    local called, result = pcall(create, argument)
    if not called then return nil, failure("factory_threw", "AdvancementSession.create threw") end
    if type(result) ~= "table" or getmetatable(result) ~= nil then
        return nil, failure("invalid_factory_result", "AdvancementSession.create returned a malformed result")
    end
    if rawget(result, "ok") == false then
        if exactPlain(result, { ok = true, code = true, detail = true }) and boundedCode(rawget(result, "code")) and boundedDetail(rawget(result, "detail")) then
            return nil, failure(rawget(result, "code"), rawget(result, "detail"))
        end
        return nil, failure("invalid_factory_result", "AdvancementSession.create returned a malformed failure")
    end
    if not exactPlain(result, { ok = true, session = true }) or rawget(result, "ok") ~= true then
        return nil, failure("invalid_factory_result", "AdvancementSession.create returned a malformed result")
    end
    local session = rawget(result, "session")
    if not exactPlain(session, { request = true }) or type(rawget(session, "request")) ~= "function" then
        return nil, failure("invalid_factory_result", "AdvancementSession.create returned a malformed service")
    end
    return session, nil
end

local function callAdminSession(factory, argument)
    local create = rawget(factory, "create")
    local called, result = pcall(create, argument)
    if not called then return nil, failure("factory_threw", "AdminSession.create threw") end
    if type(result) ~= "table" or getmetatable(result) ~= nil then
        return nil, failure("invalid_factory_result", "AdminSession.create returned a malformed result")
    end
    if rawget(result, "ok") == false then
        if exactPlain(result, { ok = true, code = true, detail = true }) and boundedCode(rawget(result, "code")) and boundedDetail(rawget(result, "detail")) then
            return nil, failure(rawget(result, "code"), rawget(result, "detail"))
        end
        return nil, failure("invalid_factory_result", "AdminSession.create returned a malformed failure")
    end
    if not exactPlain(result, { ok = true, session = true }) or rawget(result, "ok") ~= true then
        return nil, failure("invalid_factory_result", "AdminSession.create returned a malformed result")
    end
    local session = rawget(result, "session")
    if not exactPlain(session, { inspect = true, request = true })
        or type(rawget(session, "inspect")) ~= "function" or type(rawget(session, "request")) ~= "function" then
        return nil, failure("invalid_factory_result", "AdminSession.create returned a malformed service")
    end
    return session, nil
end

local function callSingleFactory(name, factory, argument, field, requiredMethods)
    local called, result = pcall(function()
        return factory.create(argument)
    end)
    if not called then
        return nil, failure("factory_threw", name .. ".create threw")
    end
    if type(result) ~= "table" then
        return nil, failure("invalid_factory_result", name .. ".create returned a malformed result")
    end
    if result.ok ~= true then
        if result.ok == false and type(result.code) == "string" and result.code ~= "" then
            return nil, failure(result.code, stableDetail(result.detail, name .. ".create failed"))
        end
        return nil, failure("invalid_factory_result", name .. ".create returned a malformed result")
    end

    local service = result[field]
    if not hasFunctions(service, requiredMethods) then
        return nil, failure("invalid_factory_result", name .. ".create returned a malformed service")
    end
    return service, nil
end

local function callWorldSettings(factory, argument)
    local called, result = pcall(function()
        return factory.create(argument)
    end)
    if not called then
        return nil, failure("factory_threw", "WorldSettings.create threw")
    end
    if type(result) ~= "table" or result.ok ~= true
        or not hasFunctions(result.accountingSettings, { "resolve" })
        or not hasFunctions(result.awardSettings, { "resolve" })
        or not hasFunctions(result.allotmentSettings, { "resolve" }) then
        if type(result) == "table" and result.ok == false
            and type(result.code) == "string" and result.code ~= "" then
            return nil, failure(result.code, stableDetail(result.detail, "WorldSettings.create failed"))
        end
        return nil, failure("invalid_factory_result", "WorldSettings.create returned malformed views")
    end
    return result, nil
end

local function callXpSource(factory, argument)
    local called, source, sourceFailure = pcall(function()
        return factory.create(argument)
    end)
    if not called then
        return nil, failure("factory_threw", "EventDerivedXpSource.create threw")
    end
    if source == nil then
        if type(sourceFailure) == "table" and sourceFailure.ok == false
            and type(sourceFailure.code) == "string" and sourceFailure.code ~= "" then
            return nil, failure(sourceFailure.code, stableDetail(sourceFailure.detail, "EventDerivedXpSource.create failed"))
        end
        return nil, failure("invalid_factory_result", "EventDerivedXpSource.create returned no source")
    end
    if not hasFunctions(source, { "install", "initializePlayer", "rebasePlayerPerk", "status" }) then
        return nil, failure("invalid_factory_result", "EventDerivedXpSource.create returned a malformed source")
    end
    return source, nil
end

function ServiceComposition.create(dependencies)
    local validationCalled, validated = pcall(validateDependencies, dependencies)
    if not validationCalled then
        return failure("invalid_dependencies", "dependency validation failed")
    end
    if not validated.ok then
        return validated
    end

    local store, storeFailure = callSingleFactory(
        "PlayerStateStore",
        dependencies.PlayerStateStore,
        dependencies.StateCodec,
        "store",
        { "load", "save" }
    )
    if store == nil then
        return storeFailure
    end

    local worldSettings, worldSettingsFailure = callWorldSettings(dependencies.WorldSettings, {
        provider = dependencies.worldSettingsProvider,
        normalizationByPerk = validated.normalizationByPerk,
    })
    if worldSettings == nil then
        return worldSettingsFailure
    end

    local accountingMode, accountingModeFailure = callSingleFactory(
        "AccountingMode",
        dependencies.AccountingMode,
        {
            store = store,
            ActualObservation = dependencies.ActualObservation,
        },
        "service",
        { "synchronizeLoaded" }
    )
    if accountingMode == nil then
        return accountingModeFailure
    end

    local ownerSnapshot, ownerSnapshotFailure = callSingleFactory(
        "OwnerSnapshot",
        dependencies.OwnerSnapshot,
        {
            catalog = dependencies.catalog,
            SurvivorEconomy = dependencies.SurvivorEconomy,
        },
        "projector",
        { "project" }
    )
    if ownerSnapshot == nil then
        return ownerSnapshotFailure
    end

    local apTransaction, apFailure = callSingleFactory(
        "ApTransaction",
        dependencies.ApTransaction,
        {
            NaturalLedger = dependencies.NaturalLedger,
            SurvivorEconomy = dependencies.SurvivorEconomy,
            Allotment = dependencies.Allotment,
            MutationScope = dependencies.MutationScope,
            store = store,
            ActualObservation = dependencies.ActualObservation,
            AccountingMode = accountingMode,
            resolver = dependencies.catalog.resolver,
        },
        "service",
        { "spend", "recover", "recoverLoadedState" }
    )
    if apTransaction == nil then
        return apFailure
    end

    local awardProcessor, processorFailure = callSingleFactory(
        "SupportedAwardProcessor",
        dependencies.SupportedAwardProcessor,
        {
            NaturalLedger = dependencies.NaturalLedger,
            SurvivorEconomy = dependencies.SurvivorEconomy,
            PostMax = dependencies.PostMax,
            store = store,
            ActualObservation = dependencies.ActualObservation,
            MutationScope = dependencies.MutationScope,
            resolver = dependencies.catalog.resolver,
            recoveryService = apTransaction,
            AccountingMode = accountingMode,
        },
        "service",
        { "process" }
    )
    if awardProcessor == nil then
        return processorFailure
    end

    local awardHandler = {}

    function awardHandler.process(player, award)
        if type(award) ~= "table" or not isSafeId(award.perkId) then
            return failure("invalid_award", "award.perkId is required")
        end

        local settingsCalled, settingsResult = pcall(function()
            return worldSettings.awardSettings.resolve(player, award.perkId)
        end)
        if not settingsCalled then
            return failure("settings_threw", "award settings resolution threw")
        end
        if type(settingsResult) ~= "table" or type(settingsResult.ok) ~= "boolean" then
            return failure("invalid_settings_result", "award settings resolution returned a malformed result")
        end
        if not settingsResult.ok then
            if type(settingsResult.code) == "string" and settingsResult.code ~= "" then
                return failure(settingsResult.code, stableDetail(settingsResult.detail, "award settings resolution failed"))
            end
            return failure("invalid_settings_result", "award settings resolution returned a malformed failure")
        end
        if type(settingsResult.settings) ~= "table" then
            return failure("invalid_settings_result", "award settings resolution returned malformed settings")
        end

        local processorCalled, processorResult = pcall(function()
            return awardProcessor.process(player, award, settingsResult.settings)
        end)
        if not processorCalled then
            return failure("processor_threw", "award processor threw")
        end
        if type(processorResult) ~= "table" or type(processorResult.ok) ~= "boolean" then
            return failure("invalid_processor_result", "award processor returned a malformed result")
        end
        if not processorResult.ok
            and (type(processorResult.code) ~= "string" or processorResult.code == ""
                or type(processorResult.detail) ~= "string" or processorResult.detail == "") then
            return failure("invalid_processor_result", "award processor returned a malformed failure")
        end
        return processorResult
    end

    local xpSource, xpSourceFailure = callXpSource(dependencies.EventDerivedXpSource, {
        environment = dependencies.environment,
        authority = dependencies.authority,
        playerIdentity = dependencies.playerIdentity,
        perkIdentity = dependencies.catalog.perkIdentity,
        positionReader = dependencies.catalog.positionReader,
        positionArithmetic = dependencies.positionArithmetic,
        sandboxMultiplier = dependencies.sandboxMultiplier,
        mutationScope = dependencies.MutationScope,
        awardHandler = awardHandler,
    })
    if xpSource == nil then
        return xpSourceFailure
    end

    local ownerSession, ownerSessionFailure = callSingleFactory(
        "OwnerSession",
        dependencies.OwnerSession,
        {
            store = store,
            recoveryService = apTransaction,
            accountingMode = accountingMode,
            accountingSettings = worldSettings.accountingSettings,
            catalog = dependencies.catalog,
            xpSource = xpSource,
            ownerSnapshot = ownerSnapshot,
        },
        "session",
        { "ready", "snapshot", "isReady", "clearPlayer" }
    )
    if ownerSession == nil then
        return ownerSessionFailure
    end

    local advancementSession, advancementSessionFailure = callAdvancementSession(
        rawget(dependencies, "AdvancementSession"),
        {
            apTransaction = apTransaction,
            allotmentSettings = worldSettings.allotmentSettings,
            ownerSession = ownerSession,
        },
        "session",
        { "request" }
    )
    if advancementSession == nil then
        return advancementSessionFailure
    end

    local adminSession, adminSessionFailure = callAdminSession(
        rawget(dependencies, "AdminSession"),
        {
            store = store,
            catalog = dependencies.catalog,
            ownerSession = ownerSession,
            SurvivorEconomy = dependencies.SurvivorEconomy,
            NaturalLedger = dependencies.NaturalLedger,
            ActualObservation = dependencies.ActualObservation,
        }
    )
    if adminSession == nil then
        return adminSessionFailure
    end

    return {
        ok = true,
        services = {
            store = store,
            worldSettings = worldSettings,
            accountingMode = accountingMode,
            ownerSnapshot = ownerSnapshot,
            apTransaction = apTransaction,
            awardProcessor = awardProcessor,
            awardHandler = awardHandler,
            xpSource = xpSource,
            ownerSession = ownerSession,
            advancementSession = advancementSession,
            adminSession = adminSession,
        },
    }
end

return ServiceComposition
