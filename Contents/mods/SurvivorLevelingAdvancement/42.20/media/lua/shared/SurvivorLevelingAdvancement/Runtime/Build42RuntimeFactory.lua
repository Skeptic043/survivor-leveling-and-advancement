local Factory = {}

local function fail(code, detail)
    return { ok = false, code = code, detail = type(detail) == "string" and detail ~= "" and detail or code }
end

local function call(label, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then return nil, fail("factory_threw", label .. " threw: " .. tostring(result)) end
    return result, nil
end

local function surface(value, names)
    if type(value) ~= "table" then return false end
    for _, name in ipairs(names) do if type(value[name]) ~= "function" then return false end end
    return true
end

local function validateModules(m)
    if type(m) ~= "table" then return fail("invalid_modules", "modules must be a table") end
    local factories = { "Build42PerkCatalog", "Build42WorldSettingsProvider", "Build42SandboxMultiplier", "Build42XpPositionArithmetic", "ServiceComposition" }
    for _, name in ipairs(factories) do if not surface(m[name], { "create" }) then return fail("invalid_module_" .. name, name .. ".create is required") end end
    if not surface(m.Build42NormalizationSnapshot, { "build" }) then return fail("invalid_module_Build42NormalizationSnapshot", "Build42NormalizationSnapshot.build is required") end
    local surfaces = {
        { "VanillaProgressionAdapter", { "build", "describe", "inspect" } }, { "StateCodec", { "decode", "encode" } },
        { "NaturalLedger", { "baseline", "inspect", "reconcileExternal", "appendTarget", "master", "applySupported" } },
        { "SurvivorEconomy", { "availableAp", "nextLevelCost", "computeAward", "applyXp", "normalizationFromCoreCurve" } }, { "Allotment", { "evaluate" } }, { "PostMax", { "apply" } },
        { "MutationScope", { "begin", "isActive", "finish" } }, { "ActualObservation", { "get", "set", "clearPlayer" } },
        { "PlayerStateStore", { "create" } }, { "OwnerSnapshot", { "create" } }, { "ApTransaction", { "create" } }, { "SupportedAwardProcessor", { "create" } }, { "WorldSettings", { "create" } }, { "EventDerivedXpSource", { "create" } }, { "OwnerSession", { "create" } },
    }
    for _, item in ipairs(surfaces) do if not surface(m[item[1]], item[2]) then return fail("invalid_module_" .. item[1], item[1] .. " capabilities are required") end end
    local accounting = rawget(m, "AccountingMode")
    if type(accounting) ~= "table" or getmetatable(accounting) ~= nil or type(rawget(accounting, "create")) ~= "function" then
        return fail("invalid_module_AccountingMode", "AccountingMode.create is required")
    end
    local advancement = rawget(m, "AdvancementSession")
    if type(advancement) ~= "table" or getmetatable(advancement) ~= nil or type(rawget(advancement, "create")) ~= "function" then
        return fail("invalid_module_AdvancementSession", "AdvancementSession.create is required")
    end
    return nil
end

local function validateGlobals(g)
    if type(g) ~= "table" then return fail("invalid_globals", "globals must be a table") end
    for _, name in ipairs({ "PerkFactory", "Perks", "SandboxOptions", "PZMath" }) do
        local read, owner = pcall(function() return g[name] end)
        if not read or owner == nil then return fail("missing_global_" .. name, name .. " is required") end
    end
    for _, name in ipairs({ "SandboxVars", "Events" }) do if type(g[name]) ~= "table" then return fail("missing_global_" .. name, name .. " is required") end end
    local perkRead, perkList = pcall(function() return g.PerkFactory.PerkList end)
    local noneRead, nonePerk = pcall(function() return g.Perks.None end)
    if not perkRead or perkList == nil or not noneRead or nonePerk == nil then return fail("missing_perk_capabilities", "PerkList and None are required") end
    for _, name in ipairs({ "addXp", "addXpNoMultiplier", "isClient", "instanceof" }) do if type(g[name]) ~= "function" then return fail("missing_global_" .. name, name .. " is required") end end
    return nil
end

local function resultField(result, field, code)
    if type(result) ~= "table" then return nil, fail(code, "malformed result") end
    if result.ok == false then
        if type(result.code) == "string" and result.code ~= "" and type(result.detail) == "string" and result.detail ~= "" then return nil, result end
        return nil, fail(code, "malformed failure result")
    end
    if result.ok ~= true or result[field] == nil then return nil, fail(code, "malformed result") end
    return result[field], nil
end

function Factory.create(dependencies)
    if type(dependencies) ~= "table" then return fail("invalid_dependencies", "dependencies must be a table") end
    local bad = validateModules(dependencies.modules); if bad then return bad end
    bad = validateGlobals(dependencies.globals); if bad then return bad end
    local m, g = dependencies.modules, dependencies.globals
    local created, err = call("Build42PerkCatalog.create", m.Build42PerkCatalog.create, { perkRegistry = g.PerkFactory.PerkList, nonePerk = g.Perks.None, progressionAdapter = m.VanillaProgressionAdapter }); if err then return err end
    local catalog; catalog, err = resultField(created, "catalog", "catalog_create_failed"); if err then return err end
    if type(catalog) ~= "table" or type(catalog.refresh) ~= "function" then return fail("invalid_catalog", "catalog.refresh is required") end
    local refreshed; refreshed, err = call("catalog.refresh", catalog.refresh); if err then return err end
    if type(refreshed) ~= "table" then return fail("catalog_refresh_failed", "catalog.refresh did not succeed") end
    if refreshed.ok == false then
        if type(refreshed.code) == "string" and refreshed.code ~= "" and type(refreshed.detail) == "string" and refreshed.detail ~= "" then return refreshed end
        return fail("catalog_refresh_failed", "malformed catalog refresh failure")
    end
    if refreshed.ok ~= true then return fail("catalog_refresh_failed", "catalog.refresh did not succeed") end
    if type(refreshed.acceptedCount) ~= "number" or refreshed.acceptedCount ~= refreshed.acceptedCount
        or refreshed.acceptedCount == math.huge or refreshed.acceptedCount == -math.huge
        or refreshed.acceptedCount ~= math.floor(refreshed.acceptedCount) or refreshed.acceptedCount < 1
        or type(refreshed.skippedCount) ~= "number" or refreshed.skippedCount ~= refreshed.skippedCount
        or refreshed.skippedCount == math.huge or refreshed.skippedCount == -math.huge
        or refreshed.skippedCount ~= math.floor(refreshed.skippedCount) or refreshed.skippedCount < 0 then
        return fail("catalog_refresh_failed", "catalog.refresh counts are invalid or empty")
    end
    local snapshot; snapshot, err = call("Build42NormalizationSnapshot.build", m.Build42NormalizationSnapshot.build, { catalog = catalog, SurvivorEconomy = m.SurvivorEconomy }); if err then return err end
    local normalization; normalization, err = resultField(snapshot, "normalizationByPerk", "normalization_build_failed"); if err then return err end
    local providerResult; providerResult, err = call("Build42WorldSettingsProvider.create", m.Build42WorldSettingsProvider.create, { readSandboxVars = function() return g.SandboxVars end }); if err then return err end
    local provider; provider, err = resultField(providerResult, "provider", "world_provider_create_failed"); if err then return err end
    local singletonRead, singleton = pcall(function() return g.SandboxOptions.instance end)
    if not singletonRead or singleton == nil then return fail("sandbox_options_instance_missing", "SandboxOptions.instance is required") end
    local resolverResult; resolverResult, err = call("Build42SandboxMultiplier.create", m.Build42SandboxMultiplier.create, { SandboxOptions = singleton, PZMath = g.PZMath }); if err then return err end
    local resolver; resolver, err = resultField(resolverResult, "resolver", "sandbox_multiplier_create_failed"); if err then return err end
    local arithmeticResult; arithmeticResult, err = call("Build42XpPositionArithmetic.create", m.Build42XpPositionArithmetic.create, { environment = { globals = g } }); if err then return err end
    local arithmetic; arithmetic, err = resultField(arithmeticResult, "arithmetic", "position_arithmetic_create_failed"); if err then return err end
    local authority = { describe = function() local ok, client = pcall(g.isClient); if not ok or type(client) ~= "boolean" then return fail("authority_failed", "isClient must return boolean") end; return { ok = true, authoritative = not client } end }
    local playerIdentity = { isPlayer = function(player) local ok, value = pcall(g.instanceof, player, "IsoPlayer"); return ok and type(value) == "boolean" and value or false end }
    local composition, compositionErr = call("ServiceComposition.create", m.ServiceComposition.create, {
        StateCodec = m.StateCodec, PlayerStateStore = m.PlayerStateStore, NaturalLedger = m.NaturalLedger, SurvivorEconomy = m.SurvivorEconomy, Allotment = m.Allotment, PostMax = m.PostMax,
        MutationScope = m.MutationScope, ActualObservation = m.ActualObservation, AccountingMode = rawget(m, "AccountingMode"), OwnerSnapshot = m.OwnerSnapshot, ApTransaction = m.ApTransaction, SupportedAwardProcessor = m.SupportedAwardProcessor, WorldSettings = m.WorldSettings, EventDerivedXpSource = m.EventDerivedXpSource, OwnerSession = m.OwnerSession, AdvancementSession = rawget(m, "AdvancementSession"),
        catalog = catalog, worldSettingsProvider = provider, normalizationByPerk = normalization, sandboxMultiplier = resolver, positionArithmetic = arithmetic, environment = { globals = g }, authority = authority, playerIdentity = playerIdentity,
    }); if compositionErr then return compositionErr end
    local services; services, compositionErr = resultField(composition, "services", "service_composition_failed"); if compositionErr then return compositionErr end
    return { ok = true, runtime = { catalog = catalog, services = services } }
end

return Factory
