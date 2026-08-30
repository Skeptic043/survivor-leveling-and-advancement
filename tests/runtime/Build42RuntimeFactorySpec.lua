local assertions = 0
local function eq(a, b, m) assertions = assertions + 1; if a ~= b then error(m or "assertion failed", 2) end end
local function ok(r, m) eq(r.ok, true, m .. ": " .. tostring(r.code) .. " " .. tostring(r.detail)) end

local function globals()
    local sandboxSingleton = { liveValue = 7 }
    function sandboxSingleton:getOptionByName(name)
        if name ~= "SurvivorLevelingAdvancement.GlobalAdvancementLimit" then return nil end
        return { getValue = function() return self.liveValue end }
    end
    return { PerkFactory = { PerkList = {} }, Perks = { None = {} }, SandboxOptions = { instance = sandboxSingleton }, SandboxVars = {}, PZMath = { clampFloat = function(v) return v end }, Events = {}, addXp = function() end, addXpNoMultiplier = function() end, isServer = function() return false end, isClient = function() return false end, instanceof = function() return true end, getPlayerByOnlineID = function() end, ModData = { getOrCreate = function() return {} end, add = function() end } }
end

local function makeModules(log, g)
    local catalog = { refresh = function() log[#log + 1] = "refresh"; return { ok = true, acceptedCount = 1, skippedCount = 0 } end }
    local services = {}
    local ownerSnapshot = { create = function() end }
    local ownerSession = { create = function() end }
    local advancementSession = { create = function() end }
    local adminSession = { create = function() end }
    local accountingMode = { create = function() end }
    local inheritanceWorldStore = { readRoot = function() end, writeRoot = function() end }
    local inheritanceIdentity = { resolve = function() end }
    local legacyStateStore = { load = function() end, save = function() end }
    local legacyCharacterStore = {
        inspect = function() end, tokenNewCharacter = function() end,
        markInitialized = function() end, markDeathRecorded = function() end,
    }
    local serverStateStore = { load = function() end, save = function() end }
    local serverCharacterStore = {
        inspect = function() end, tokenNewCharacter = function() end,
        markInitialized = function() end, markDeathRecorded = function() end,
    }
    local levelGainCompletion = { create = function() end, validate = function() end }
    local m = {
        Build42PerkCatalog = { create = function(a) log[#log + 1] = "catalog"; eq(a.perkRegistry, g.PerkFactory.PerkList, "registry identity"); eq(type(a.progressionAdapter), "table", "adapter identity"); return { ok = true, catalog = catalog } end },
        VanillaProgressionAdapter = { build = function() end, describe = function() end, inspect = function() end },
        Build42NormalizationSnapshot = { build = function(a) log[#log + 1] = "normalization"; eq(a.catalog, catalog, "catalog identity"); return { ok = true, normalizationByPerk = { Cooking = 3 } } end },
        Build42WorldSettingsProvider = { create = function(a) log[#log + 1] = "provider"; eq(a.readSandboxVars(), g.SandboxVars, "live sandbox vars"); return { ok = true, provider = {} } end },
        Build42SandboxMultiplier = { create = function(a) log[#log + 1] = "multiplier"; eq(a.SandboxOptions, g.SandboxOptions.instance, "options singleton identity"); return { ok = true, resolver = { resolve = function() end } } end },
        Build42XpPositionArithmetic = { create = function(a) log[#log + 1] = "arithmetic"; eq(a.environment.globals, g, "globals identity"); return { ok = true, arithmetic = { add = function() end } } end },
        Build42InheritanceWorldStore = { create = function(a) log[#log + 1] = "inheritance_world"; eq(type(a.getOrCreate), "function", "captured ModData reader"); eq(type(a.add), "function", "captured ModData writer"); return { ok = true, capabilities = inheritanceWorldStore } end },
        Build42InheritanceIdentity = { create = function(a) log[#log + 1] = "inheritance_identity"; eq(type(a.isServer), "function", "captured server mode"); eq(type(a.isClient), "function", "captured client mode"); eq(a.getPlayerByOnlineID, g.getPlayerByOnlineID, "captured exact Lua lookup"); return { ok = true, adapter = inheritanceIdentity } end },
        ServiceComposition = { create = function(a) log[#log + 1] = "composition"; eq(a.catalog, catalog, "composition catalog"); eq(a.normalizationByPerk.Cooking, 3, "normalization map"); eq(a.AccountingMode, accountingMode, "accounting factory identity"); eq(a.OwnerSnapshot, ownerSnapshot, "snapshot factory identity"); eq(a.OwnerSession, ownerSession, "session factory identity"); eq(a.AdvancementSession, advancementSession, "advancement factory identity"); eq(a.AdminSession, adminSession, "admin factory identity"); eq(a.LevelGainCompletion, levelGainCompletion, "completion factory identity"); eq(type(a.levelGainSink), "function", "completion sink callable"); eq(a.inheritanceWorldStore, inheritanceWorldStore, "inheritance world identity"); eq(a.inheritanceIdentity, inheritanceIdentity, "inheritance identity"); eq(a.stateStore, legacyStateStore, "SP state-store identity"); eq(a.characterStore, legacyCharacterStore, "SP character-store identity"); eq(a.authority.describe().authoritative, true, "authority"); eq(a.playerIdentity.isPlayer({}), true, "identity"); return { ok = true, services = services } end },
        StateCodec = { decode = function() end, encode = function() end, fresh = function() end }, InheritancePolicy = { plan = function() end }, LevelGainCompletion = levelGainCompletion,
        PlayerStateStore = { create = function() log[#log + 1] = "player_state"; return { ok = true, store = legacyStateStore } end },
        CharacterInheritanceStore = { create = function() log[#log + 1] = "character_state"; return { ok = true, store = legacyCharacterStore } end },
        ServerPlayerRecordStore = { create = function() log[#log + 1] = "server_state"; return { ok = true, stateStore = serverStateStore, characterStore = serverCharacterStore } end },
        InheritanceRecordStore = { create = function() end }, InheritanceSession = { create = function() end }, NaturalLedger = { baseline = function() end, inspect = function() end, reconcileExternal = function() end, appendTarget = function() end, master = function() end, applySupported = function() end }, SurvivorEconomy = { availableAp = function() end, nextLevelCost = function() end, computeAward = function() end, applyXp = function() end, normalizationFromCoreCurve = function() end }, Allotment = { evaluate = function() end }, PostMax = { apply = function() end }, MutationScope = { begin = function() end, isActive = function() end, finish = function() end }, ActualObservation = { get = function() end, set = function() end, clearPlayer = function() end }, AccountingMode = accountingMode, OwnerSnapshot = ownerSnapshot, OwnerSession = ownerSession, AdvancementSession = advancementSession, AdminSession = adminSession, ApTransaction = { create = function() end }, SupportedAwardProcessor = { create = function() end }, WorldSettings = { create = function() end }, EventDerivedXpSource = { create = function() end },
    }
    return m, catalog, services
end

local g = globals(); local log = {}; local m, catalog, services = makeModules(log, g)
local result = Build42RuntimeFactory.create({ modules = m, globals = g })
ok(result, "success"); eq(result.runtime.catalog, catalog, "catalog result"); eq(result.runtime.services, services, "services result")
local resultKeys = 0; for key in pairs(result) do resultKeys = resultKeys + 1; eq(key == "ok" or key == "runtime", true, "result allowlist") end; eq(resultKeys, 2, "result key count")
local runtimeKeys = 0; for key in pairs(result.runtime) do runtimeKeys = runtimeKeys + 1; eq(key == "catalog" or key == "services", true, "runtime allowlist") end; eq(runtimeKeys, 2, "runtime key count")
eq(table.concat(log, ","), "catalog,refresh,normalization,provider,multiplier,arithmetic,inheritance_world,inheritance_identity,player_state,character_state,composition", "order")
local savedOwnerSnapshot = m.OwnerSnapshot
m.OwnerSnapshot = nil
local callsBeforeMissingSnapshot = #log
local missingSnapshot = Build42RuntimeFactory.create({ modules = m, globals = g })
eq(missingSnapshot.ok, false, "missing snapshot rejected")
eq(missingSnapshot.code, "invalid_module_OwnerSnapshot", "missing snapshot code")
eq(#log, callsBeforeMissingSnapshot, "missing snapshot runs no factory")
m.OwnerSnapshot = savedOwnerSnapshot
local savedOwnerSession = m.OwnerSession
m.OwnerSession = nil
local callsBeforeMissingSession = #log
local missingSession = Build42RuntimeFactory.create({ modules = m, globals = g })
eq(missingSession.ok, false, "missing session rejected")
eq(missingSession.code, "invalid_module_OwnerSession", "missing session code")
eq(#log, callsBeforeMissingSession, "missing session runs no factory")
m.OwnerSession = savedOwnerSession
local savedAccountingMode = m.AccountingMode
m.AccountingMode = nil
local callsBeforeMissingAccounting = #log
local missingAccounting = Build42RuntimeFactory.create({ modules = m, globals = g })
eq(missingAccounting.ok, false, "missing accounting rejected")
eq(missingAccounting.code, "invalid_module_AccountingMode", "missing accounting code")
eq(#log, callsBeforeMissingAccounting, "missing accounting runs no factory")
m.AccountingMode = setmetatable({}, { __index = function() error("hostile accounting") end })
local hostileAccounting = Build42RuntimeFactory.create({ modules = m, globals = g })
eq(hostileAccounting.ok, false, "hostile accounting rejected")
eq(hostileAccounting.code, "invalid_module_AccountingMode", "hostile accounting code")
m.AccountingMode = savedAccountingMode
local savedAdvancementSession = m.AdvancementSession
m.AdvancementSession = nil
local callsBeforeMissingAdvancement = #log
local missingAdvancement = Build42RuntimeFactory.create({ modules = m, globals = g })
eq(missingAdvancement.ok, false, "missing advancement rejected")
eq(missingAdvancement.code, "invalid_module_AdvancementSession", "missing advancement code")
eq(#log, callsBeforeMissingAdvancement, "missing advancement runs no factory")
m.AdvancementSession = savedAdvancementSession
local savedAdminSession = m.AdminSession
m.AdminSession = nil
local callsBeforeMissingAdmin = #log
local missingAdmin = Build42RuntimeFactory.create({ modules = m, globals = g })
eq(missingAdmin.ok, false, "missing admin rejected")
eq(missingAdmin.code, "invalid_module_AdminSession", "missing admin code")
eq(#log, callsBeforeMissingAdmin, "missing admin runs no factory")
m.AdminSession = savedAdminSession
local hostileGlobals = globals(); local hostileLog = {}; local hostileModules = makeModules(hostileLog, hostileGlobals)
hostileModules.AdvancementSession = setmetatable({}, { __index = function() error("hostile") end })
local hostileAdvancement = Build42RuntimeFactory.create({ modules = hostileModules, globals = hostileGlobals })
eq(hostileAdvancement.ok, false, "hostile advancement module rejected")
eq(hostileAdvancement.code, "invalid_module_AdvancementSession", "hostile advancement module code")
local hostileAdminGlobals = globals(); local hostileAdminLog = {}; local hostileAdminModules = makeModules(hostileAdminLog, hostileAdminGlobals)
hostileAdminModules.AdminSession = setmetatable({}, { __index = function() error("hostile") end })
local hostileAdmin = Build42RuntimeFactory.create({ modules = hostileAdminModules, globals = hostileAdminGlobals })
eq(hostileAdmin.ok, false, "hostile admin module rejected")
eq(hostileAdmin.code, "invalid_module_AdminSession", "hostile admin module code")
g.SandboxVars = {}; local providerArgs
m.Build42WorldSettingsProvider.create = function(a) providerArgs = a; return { ok = true, provider = {} } end
ok(Build42RuntimeFactory.create({ modules = m, globals = g }), "current settings success"); eq(providerArgs.readSandboxVars(), g.SandboxVars, "current settings")
eq(providerArgs.readSandboxOption("GlobalAdvancementLimit"), 7, "current engine sandbox option")
g.isClient = function() return true end
local clientRuntime = Build42RuntimeFactory.create({ modules = m, globals = g })
eq(clientRuntime.ok, false, "client runtime rejected")
eq(clientRuntime.code, "invalid_mode", "client runtime code")
g.isClient = function() return false end

do
    local serverGlobals = globals()
    serverGlobals.isServer = function() return true end
    local serverLog = {}
    local serverModules = makeModules(serverLog, serverGlobals)
    local serverState, serverCharacter
    serverModules.ServerPlayerRecordStore.create = function(argument)
        serverLog[#serverLog + 1] = "server_state"
        eq(argument.codec, serverModules.StateCodec, "server store codec identity")
        eq(type(argument.identity.resolve), "function", "server store identity adapter")
        eq(type(argument.legacyStateStore.load), "function", "server store legacy state source")
        eq(type(argument.legacyCharacterStore.inspect), "function", "server store legacy metadata source")
        eq(type(argument.getOrCreate), "function", "server store Global reader")
        eq(type(argument.add), "function", "server store Global writer")
        serverState = { load = function() end, save = function() end }
        serverCharacter = {
            inspect = function() end, tokenNewCharacter = function() end,
            markInitialized = function() end, markDeathRecorded = function() end,
        }
        return { ok = true, stateStore = serverState, characterStore = serverCharacter }
    end
    serverModules.ServiceComposition.create = function(argument)
        serverLog[#serverLog + 1] = "composition"
        eq(argument.stateStore, serverState, "server state surface reaches composition")
        eq(argument.characterStore, serverCharacter, "server metadata surface reaches composition")
        return { ok = true, services = {} }
    end
    ok(Build42RuntimeFactory.create({ modules = serverModules, globals = serverGlobals }),
        "server store composition")
    eq(serverLog[#serverLog - 1], "server_state", "server store built before composition")
    eq(serverLog[#serverLog], "composition", "server composition follows store")
end

do
    local boundaryGlobals = globals()
    local boundaryLog = {}
    local boundaryModules = makeModules(boundaryLog, boundaryGlobals)
    local globalCalls, fakeMemberCalls, modReads, modWrites = 0, 0, 0, 0
    boundaryGlobals.GameServer = {
        getPlayerByOnlineID = function() fakeMemberCalls = fakeMemberCalls + 1; error("fake member") end,
    }
    local capturedGlobal = function(id) globalCalls = globalCalls + 1; return "global:" .. tostring(id) end
    boundaryGlobals.getPlayerByOnlineID = capturedGlobal
    boundaryGlobals.ModData = {
        getOrCreate = function() modReads = modReads + 1; return {} end,
        add = function() modWrites = modWrites + 1 end,
    }
    boundaryModules.Build42InheritanceIdentity.create = function(argument)
        eq(argument.getPlayerByOnlineID, capturedGlobal, "identity receives exact Lua global")
        boundaryGlobals.getPlayerByOnlineID = function() return "replacement" end
        eq(argument.getPlayerByOnlineID(12), "global:12", "captured lookup ignores later global replacement")
        return { ok = true, adapter = { resolve = function() end } }
    end
    boundaryModules.ServiceComposition.create = function(argument)
        eq(type(argument.inheritanceWorldStore.readRoot), "function", "world adapter reaches composition")
        eq(type(argument.inheritanceIdentity.resolve), "function", "identity adapter reaches composition")
        return { ok = true, services = {} }
    end
    ok(Build42RuntimeFactory.create({ modules = boundaryModules, globals = boundaryGlobals }), "Build 42 inheritance boundaries")
    eq(globalCalls, 1, "Lua global lookup called once")
    eq(fakeMemberCalls, 0, "fake GameServer member is never read or called")
    eq(modReads, 0, "factory construction does not read Global ModData namespace")
    eq(modWrites, 0, "factory construction does not replace Global ModData namespace")
end
do
    local fakeOnlyGlobals = globals()
    local fakeOnlyCalls = 0
    fakeOnlyGlobals.getPlayerByOnlineID = nil
    fakeOnlyGlobals.GameServer = { getPlayerByOnlineID = function() fakeOnlyCalls = fakeOnlyCalls + 1 end }
    local fakeOnlyLog = {}
    local rejected = Build42RuntimeFactory.create({ modules = makeModules(fakeOnlyLog, fakeOnlyGlobals), globals = fakeOnlyGlobals })
    eq(rejected.ok, false, "fake GameServer member cannot replace missing Lua global")
    eq(rejected.code, "missing_global_getPlayerByOnlineID", "missing Lua lookup has exact code")
    eq(fakeOnlyCalls, 0, "fake GameServer member remains untouched on rejection")
end
local explicit = { ok = false, code = "catalog_down", detail = "catalog unavailable" }
local bad
m.Build42PerkCatalog.create = function() return explicit end
bad = Build42RuntimeFactory.create({ modules = m, globals = g }); eq(bad, explicit, "valid explicit failure propagates")
m.Build42PerkCatalog.create = function() return { ok = false, code = "bad" } end
bad = Build42RuntimeFactory.create({ modules = m, globals = g }); eq(bad.code, "catalog_create_failed", "malformed failure is bounded")
m.Build42PerkCatalog.create = function() return { ok = true, catalog = catalog } end
bad = Build42RuntimeFactory.create({ modules = {}, globals = g }); eq(bad.ok, false, "malformed failure"); eq(type(bad.detail), "string", "detail")
m.Build42NormalizationSnapshot.build = function() error("boom") end
bad = Build42RuntimeFactory.create({ modules = m, globals = g }); eq(bad.ok, false, "thrown failure"); eq(bad.code, "factory_threw", "thrown code")

local function assertRefreshCountsRejected(refreshResult, message)
    local localGlobals = globals()
    local localLog = {}
    local localModules, localCatalog = makeModules(localLog, localGlobals)
    local normalizationCalls = 0
    localCatalog.refresh = function()
        localLog[#localLog + 1] = "refresh"
        return refreshResult
    end
    localModules.Build42NormalizationSnapshot.build = function()
        normalizationCalls = normalizationCalls + 1
        return { ok = true, normalizationByPerk = {} }
    end
    local rejected = Build42RuntimeFactory.create({ modules = localModules, globals = localGlobals })
    eq(rejected.ok, false, message .. " rejected")
    eq(rejected.code, "catalog_refresh_failed", message .. " code")
    eq(normalizationCalls, 0, message .. " stops before normalization")
end

assertRefreshCountsRejected({ ok = true, acceptedCount = 0, skippedCount = 0 }, "zero count")
assertRefreshCountsRejected({ ok = true, skippedCount = 0 }, "missing accepted count")
assertRefreshCountsRejected({ ok = true, acceptedCount = 1, skippedCount = 0.5 }, "fractional skipped count")
assertRefreshCountsRejected({ ok = true, acceptedCount = math.huge, skippedCount = 0 }, "nonfinite accepted count")
assertRefreshCountsRejected({ ok = true, acceptedCount = 1, skippedCount = -1 }, "inconsistent count")

local function assertSingletonRejected(options, message)
    local localGlobals = globals()
    localGlobals.SandboxOptions = options
    local localLog = {}
    local localModules = makeModules(localLog, localGlobals)
    local multiplierCalls, compositionCalls = 0, 0
    localModules.Build42SandboxMultiplier.create = function()
        multiplierCalls = multiplierCalls + 1
        return { ok = true, resolver = { resolve = function() end } }
    end
    localModules.ServiceComposition.create = function()
        compositionCalls = compositionCalls + 1
        return { ok = true, services = {} }
    end
    local rejected = Build42RuntimeFactory.create({ modules = localModules, globals = localGlobals })
    eq(rejected.ok, false, message .. " rejected")
    eq(rejected.code, "sandbox_options_instance_missing", message .. " code")
    eq(multiplierCalls, 0, message .. " stops before multiplier")
    eq(compositionCalls, 0, message .. " stops before composition")
end

assertSingletonRejected({}, "missing singleton")
assertSingletonRejected(setmetatable({}, { __index = function() error("instance lookup") end }), "throwing singleton")
return assertions
