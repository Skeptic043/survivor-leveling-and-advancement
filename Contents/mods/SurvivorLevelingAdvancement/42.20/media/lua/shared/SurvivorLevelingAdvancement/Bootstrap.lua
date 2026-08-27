local SENTINEL_KEY = "__SLA_Build42Lifecycle_42_20_v1"
local SENTINEL_SIGNATURE = "sla.build42-lifecycle/42.20/v1"

local OWNER_METHODS = {
    install = true,
    status = true,
    clientState = true,
    refreshOwner = true,
    setClientStateListener = true,
    requestAdvancement = true,
    advancementStatus = true,
    requestAdmin = true,
    adminStatus = true,
}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function boundedFailure(value, code, detail)
    if type(value) ~= "table" or rawget(value, "ok") ~= false
        or type(rawget(value, "code")) ~= "string" or #rawget(value, "code") == 0
        or #rawget(value, "code") > 64 or not string.match(rawget(value, "code"), "^[%w_.:-]+$")
        or type(rawget(value, "detail")) ~= "string" or #rawget(value, "detail") == 0
        or #rawget(value, "detail") > 160
        or string.find(rawget(value, "detail"), "[%z\1-\31\127]") then
        return failure(code, detail)
    end
    return failure(rawget(value, "code"), rawget(value, "detail"))
end

local function validSentinel(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    local allowed = { signature = true, owner = true }
    for key in pairs(value) do if type(key) ~= "string" or not allowed[key] then return false end end
    if rawget(value, "signature") ~= SENTINEL_SIGNATURE then return false end
    local owner = rawget(value, "owner")
    if type(owner) ~= "table" or getmetatable(owner) ~= nil then return false end
    for key in pairs(owner) do if type(key) ~= "string" or not OWNER_METHODS[key] then return false end end
    for key in pairs(OWNER_METHODS) do if type(rawget(owner, key)) ~= "function" then return false end end
    return true
end

local function installOwner(owner)
    local called, result = pcall(owner.install)
    if not called then return failure("lifecycle_install_threw", "owner.install") end
    if type(result) ~= "table" or result.ok ~= true then
        return boundedFailure(result, "lifecycle_install_invalid", "owner.install")
    end
    return { ok = true }
end

local existing = rawget(_G, SENTINEL_KEY)
if existing ~= nil then
    if not validSentinel(existing) then return failure("lifecycle_sentinel_collision", "existing sentinel is malformed") end
    local installed = installOwner(existing.owner)
    if not installed.ok then return installed end
    return existing.owner
end

local modules = {
    Build42Lifecycle = require "SurvivorLevelingAdvancement/Runtime/Build42Lifecycle",
    Build42RuntimeFactory = require "SurvivorLevelingAdvancement/Runtime/Build42RuntimeFactory",
    Build42OwnerTransport = require "SurvivorLevelingAdvancement/Runtime/Build42OwnerTransport",
    Build42AdvancementTransport = require "SurvivorLevelingAdvancement/Runtime/Build42AdvancementTransport",
    Build42AdminTransport = require "SurvivorLevelingAdvancement/Runtime/Build42AdminTransport",
    Build42AdminBoundary = require "SurvivorLevelingAdvancement/Adapters/Build42AdminBoundary",
    ClientOwnerState = require "SurvivorLevelingAdvancement/Runtime/ClientOwnerState",
    Build42PerkCatalog = require "SurvivorLevelingAdvancement/Adapters/Build42PerkCatalog",
    VanillaProgressionAdapter = require "SurvivorLevelingAdvancement/Adapters/VanillaProgressionAdapter",
    Build42NormalizationSnapshot = require "SurvivorLevelingAdvancement/Adapters/Build42NormalizationSnapshot",
    Build42WorldSettingsProvider = require "SurvivorLevelingAdvancement/Adapters/Build42WorldSettingsProvider",
    Build42SandboxMultiplier = require "SurvivorLevelingAdvancement/Adapters/Build42SandboxMultiplier",
    Build42XpPositionArithmetic = require "SurvivorLevelingAdvancement/Adapters/Build42XpPositionArithmetic",
    StateCodec = require "SurvivorLevelingAdvancement/State/StateCodec",
    PlayerStateStore = require "SurvivorLevelingAdvancement/Persistence/PlayerStateStore",
    NaturalLedger = require "SurvivorLevelingAdvancement/Core/NaturalLedger",
    SurvivorEconomy = require "SurvivorLevelingAdvancement/Core/SurvivorEconomy",
    Allotment = require "SurvivorLevelingAdvancement/Core/Allotment",
    PostMax = require "SurvivorLevelingAdvancement/Core/PostMax",
    MutationScope = require "SurvivorLevelingAdvancement/State/MutationScope",
    ActualObservation = require "SurvivorLevelingAdvancement/State/ActualObservation",
    AccountingMode = require "SurvivorLevelingAdvancement/Runtime/AccountingMode",
    OwnerSnapshot = require "SurvivorLevelingAdvancement/Runtime/OwnerSnapshot",
    OwnerSession = require "SurvivorLevelingAdvancement/Runtime/OwnerSession",
    AdvancementSession = require "SurvivorLevelingAdvancement/Runtime/AdvancementSession",
    AdminSession = require "SurvivorLevelingAdvancement/Runtime/AdminSession",
    ApTransaction = require "SurvivorLevelingAdvancement/Advancement/ApTransaction",
    SupportedAwardProcessor = require "SurvivorLevelingAdvancement/XP/SupportedAwardProcessor",
    WorldSettings = require "SurvivorLevelingAdvancement/Runtime/WorldSettings",
    EventDerivedXpSource = require "SurvivorLevelingAdvancement/XP/EventDerivedXpSource",
    ServiceComposition = require "SurvivorLevelingAdvancement/Runtime/ServiceComposition",
}

local function unavailable(detail)
    return failure("lifecycle_unresolved", detail)
end

local function createFacade()
    local createLifecycle = type(modules.Build42Lifecycle) == "table"
        and rawget(modules.Build42Lifecycle, "create") or nil
    if type(createLifecycle) ~= "function" then
        return failure("lifecycle_create_invalid", "Build42Lifecycle.create")
    end

    local globals = _G
    local isServer, isClient = rawget(globals, "isServer"), rawget(globals, "isClient")
    local eventTable = rawget(globals, "Events")
    local resolverEvents = type(eventTable) == "table" and {
        OnGameStart = rawget(eventTable, "OnGameStart"),
        OnCreatePlayer = rawget(eventTable, "OnCreatePlayer"),
    } or {}
    local concreteOwner, retainedFailure
    local resolverInstallAttempted, resolverInstalled = false, false
    local resolutionAttempted = false
    local facade, callbacks = {}, {}

    local function retain(code, detail)
        retainedFailure = failure(code, detail)
        return retainedFailure
    end

    local function checkMode()
        if type(isServer) ~= "function" or type(isClient) ~= "function" then
            return nil, retain("mode_invalid", "isServer and isClient must be callable")
        end
        local serverCalled, server = pcall(isServer)
        local clientCalled, client = pcall(isClient)
        if not serverCalled or not clientCalled
            or type(server) ~= "boolean" or type(client) ~= "boolean"
            or (server and client) then
            return nil, retain("mode_invalid", "isServer and isClient must identify one mode")
        end
        if server then return "server" end
        if client then return "client" end
        return "unresolved"
    end

    local function validOwner(owner)
        if type(owner) ~= "table" or getmetatable(owner) ~= nil then return false end
        for key in pairs(owner) do if type(key) ~= "string" or not OWNER_METHODS[key] then return false end end
        for key in pairs(OWNER_METHODS) do if type(rawget(owner, key)) ~= "function" then return false end end
        return true
    end

    local function resolve(mode)
        if concreteOwner ~= nil or resolutionAttempted then return concreteOwner ~= nil end
        resolutionAttempted = true
        local called, created = pcall(createLifecycle, {
            modules = modules,
            globals = globals,
            mode = mode,
        })
        if not called or type(created) ~= "table" or rawget(created, "ok") ~= true
            or not validOwner(rawget(created, "owner")) then
            retainedFailure = called
                and boundedFailure(created, "lifecycle_create_invalid", "Build42Lifecycle.create")
                or retain("lifecycle_create_invalid", "Build42Lifecycle.create")
            return false
        end
        local candidateOwner = rawget(created, "owner")
        local installed = installOwner(candidateOwner)
        if not installed.ok then retainedFailure = installed; return false end
        concreteOwner = candidateOwner
        retainedFailure = nil
        return true
    end

    local function ownsResolverEvents()
        local current = rawget(globals, "Events")
        return type(current) == "table"
            and rawget(current, "OnGameStart") == resolverEvents.OnGameStart
            and rawget(current, "OnCreatePlayer") == resolverEvents.OnCreatePlayer
    end

    local function installResolvers()
        if resolverInstallAttempted then
            if not ownsResolverEvents() then return retain("event_ownership_lost", "resolver events") end
            return resolverInstalled and { ok = true }
                or retainedFailure or failure("install_failed", "resolver event registration")
        end
        resolverInstallAttempted = true
        if not ownsResolverEvents()
            or type(resolverEvents.OnGameStart) ~= "table"
            or type(rawget(resolverEvents.OnGameStart, "Add")) ~= "function"
            or type(resolverEvents.OnCreatePlayer) ~= "table"
            or type(rawget(resolverEvents.OnCreatePlayer, "Add")) ~= "function" then
            return retain("invalid_dependencies", "resolver lifecycle events are required")
        end
        if not pcall(rawget(resolverEvents.OnGameStart, "Add"), callbacks.OnGameStart) then
            return retain("event_register_threw", "OnGameStart")
        end
        if not pcall(rawget(resolverEvents.OnCreatePlayer, "Add"), callbacks.OnCreatePlayer) then
            return retain("event_register_threw", "OnCreatePlayer")
        end
        resolverInstalled = true
        return { ok = true }
    end

    local function resolveFrom(gate)
        if concreteOwner ~= nil or resolutionAttempted then return end
        if not ownsResolverEvents() then retain("event_ownership_lost", gate); return end
        local mode = checkMode()
        if mode == nil then resolutionAttempted = true; return end
        if gate == "OnCreatePlayer" then
            if mode == "client" then resolve(mode) end
        elseif mode == "client" then
            resolve(mode)
        elseif mode == "unresolved" then
            resolve("single_player")
        else
            resolutionAttempted = true
            retain("mode_invalid", "OnGameStart cannot resolve server mode")
        end
    end

    callbacks.OnGameStart = function() resolveFrom("OnGameStart") end
    callbacks.OnCreatePlayer = function() resolveFrom("OnCreatePlayer") end

    function facade.install()
        if concreteOwner ~= nil then return concreteOwner.install() end
        if resolutionAttempted then return retainedFailure or failure("lifecycle_create_invalid", "resolution") end
        if resolverInstallAttempted and not ownsResolverEvents() then
            resolutionAttempted = true
            return retain("event_ownership_lost", "resolver events")
        end
        local mode = checkMode()
        if mode == nil then
            resolutionAttempted = true
            return retainedFailure
        end
        if mode == "server" or mode == "client" then
            if resolve(mode) then return { ok = true } end
            return retainedFailure
        end
        local installed = installResolvers()
        if not installed.ok then return installed end
        return { ok = true }
    end

    function facade.status()
        if concreteOwner ~= nil then return concreteOwner.status() end
        local result = {
            ok = true,
            mode = "unresolved",
            installed = resolverInstalled,
            started = false,
            ready = false,
        }
        if retainedFailure ~= nil then
            result.failure = { code = retainedFailure.code, detail = retainedFailure.detail }
        end
        return result
    end

    function facade.clientState(localSlot)
        if concreteOwner ~= nil then return concreteOwner.clientState(localSlot) end
        return unavailable("clientState")
    end
    function facade.refreshOwner(localSlot)
        if concreteOwner ~= nil then return concreteOwner.refreshOwner(localSlot) end
        return unavailable("refreshOwner")
    end
    function facade.setClientStateListener(listener)
        if concreteOwner ~= nil then return concreteOwner.setClientStateListener(listener) end
        return unavailable("setClientStateListener")
    end
    function facade.requestAdvancement(localSlot, perkId)
        if concreteOwner ~= nil then return concreteOwner.requestAdvancement(localSlot, perkId) end
        return unavailable("requestAdvancement")
    end
    function facade.advancementStatus(localSlot)
        if concreteOwner ~= nil then return concreteOwner.advancementStatus(localSlot) end
        return unavailable("advancementStatus")
    end
    function facade.requestAdmin(localSlot, request)
        if concreteOwner ~= nil then return concreteOwner.requestAdmin(localSlot, request) end
        return unavailable("requestAdmin")
    end
    function facade.adminStatus(localSlot)
        if concreteOwner ~= nil then return concreteOwner.adminStatus(localSlot) end
        return unavailable("adminStatus")
    end

    return { ok = true, owner = facade }
end

local created = createFacade()
if type(created) ~= "table" or created.ok ~= true or type(created.owner) ~= "table" then return created end
local sentinel = { signature = SENTINEL_SIGNATURE, owner = created.owner }
if not validSentinel(sentinel) then return failure("lifecycle_create_invalid", "Build42Lifecycle owner surface") end
rawset(_G, SENTINEL_KEY, sentinel)
local installed = installOwner(created.owner)
if not installed.ok then return installed end
return created.owner
