local assertions = 0
local function eq(a, b, m) assertions = assertions + 1; if a ~= b then error(m or "assertion failed", 2) end end
local function ok(r, m) eq(r.ok, true, m .. ": " .. tostring(r.code) .. " " .. tostring(r.detail)) end

local function globals()
    return { PerkFactory = { PerkList = {} }, Perks = { None = {} }, SandboxOptions = {}, SandboxVars = {}, PZMath = { clampFloat = function(v) return v end }, Events = {}, addXp = function() end, addXpNoMultiplier = function() end, isClient = function() return false end, instanceof = function() return true end }
end

local function makeModules(log, g)
    local catalog = { refresh = function() log[#log + 1] = "refresh"; return { ok = true } end }
    local services = {}
    local ownerSnapshot = { create = function() end }
    local m = {
        Build42PerkCatalog = { create = function(a) log[#log + 1] = "catalog"; eq(a.perkRegistry, g.PerkFactory.PerkList, "registry identity"); eq(type(a.progressionAdapter), "table", "adapter identity"); return { ok = true, catalog = catalog } end },
        VanillaProgressionAdapter = { build = function() end, describe = function() end, inspect = function() end },
        Build42NormalizationSnapshot = { build = function(a) log[#log + 1] = "normalization"; eq(a.catalog, catalog, "catalog identity"); return { ok = true, normalizationByPerk = { Cooking = 3 } } end },
        Build42WorldSettingsProvider = { create = function(a) log[#log + 1] = "provider"; eq(a.readSandboxVars(), g.SandboxVars, "live sandbox vars"); return { ok = true, provider = {} } end },
        Build42SandboxMultiplier = { create = function(a) log[#log + 1] = "multiplier"; eq(a.SandboxOptions, g.SandboxOptions, "options identity"); return { ok = true, resolver = { resolve = function() end } } end },
        Build42XpPositionArithmetic = { create = function(a) log[#log + 1] = "arithmetic"; eq(a.environment.globals, g, "globals identity"); return { ok = true, arithmetic = { add = function() end } } end },
        ServiceComposition = { create = function(a) log[#log + 1] = "composition"; eq(a.catalog, catalog, "composition catalog"); eq(a.normalizationByPerk.Cooking, 3, "normalization map"); eq(a.OwnerSnapshot, ownerSnapshot, "snapshot factory identity"); eq(a.authority.describe().authoritative, true, "authority"); eq(a.playerIdentity.isPlayer({}), true, "identity"); return { ok = true, services = services } end },
        StateCodec = { decode = function() end, encode = function() end }, PlayerStateStore = { create = function() end }, NaturalLedger = { baseline = function() end, inspect = function() end, reconcileExternal = function() end, appendTarget = function() end, master = function() end, applySupported = function() end }, SurvivorEconomy = { availableAp = function() end, nextLevelCost = function() end, computeAward = function() end, applyXp = function() end, normalizationFromCoreCurve = function() end }, Allotment = { evaluate = function() end }, PostMax = { apply = function() end }, MutationScope = { begin = function() end, isActive = function() end, finish = function() end }, ActualObservation = { get = function() end, set = function() end, clearPlayer = function() end }, OwnerSnapshot = ownerSnapshot, ApTransaction = { create = function() end }, SupportedAwardProcessor = { create = function() end }, WorldSettings = { create = function() end }, EventDerivedXpSource = { create = function() end },
    }
    return m, catalog, services
end

local g = globals(); local log = {}; local m, catalog, services = makeModules(log, g)
local result = Build42RuntimeFactory.create({ modules = m, globals = g })
ok(result, "success"); eq(result.runtime.catalog, catalog, "catalog result"); eq(result.runtime.services, services, "services result")
local resultKeys = 0; for key in pairs(result) do resultKeys = resultKeys + 1; eq(key == "ok" or key == "runtime", true, "result allowlist") end; eq(resultKeys, 2, "result key count")
local runtimeKeys = 0; for key in pairs(result.runtime) do runtimeKeys = runtimeKeys + 1; eq(key == "catalog" or key == "services", true, "runtime allowlist") end; eq(runtimeKeys, 2, "runtime key count")
eq(table.concat(log, ","), "catalog,refresh,normalization,provider,multiplier,arithmetic,composition", "order")
local savedOwnerSnapshot = m.OwnerSnapshot
m.OwnerSnapshot = nil
local callsBeforeMissingSnapshot = #log
local missingSnapshot = Build42RuntimeFactory.create({ modules = m, globals = g })
eq(missingSnapshot.ok, false, "missing snapshot rejected")
eq(missingSnapshot.code, "invalid_module_OwnerSnapshot", "missing snapshot code")
eq(#log, callsBeforeMissingSnapshot, "missing snapshot runs no factory")
m.OwnerSnapshot = savedOwnerSnapshot
g.SandboxVars = {}; local providerArgs
m.Build42WorldSettingsProvider.create = function(a) providerArgs = a; return { ok = true, provider = {} } end
ok(Build42RuntimeFactory.create({ modules = m, globals = g }), "current settings success"); eq(providerArgs.readSandboxVars(), g.SandboxVars, "current settings")
g.isClient = function() return true end
m.ServiceComposition.create = function(a) eq(a.authority.describe().authoritative, false, "client authority"); g.isClient = function() return "bad" end; eq(a.authority.describe().ok, false, "invalid authority"); g.isClient = function() return true end; g.instanceof = function() error("boom") end; eq(a.playerIdentity.isPlayer({}), false, "thrown identity"); return { ok = true, services = services } end
ok(Build42RuntimeFactory.create({ modules = m, globals = g }), "authority variants")
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
return assertions
