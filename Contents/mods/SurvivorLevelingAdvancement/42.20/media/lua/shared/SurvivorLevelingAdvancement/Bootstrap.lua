local SENTINEL_KEY = "__SLA_Build42Lifecycle_42_20_v1"
local SENTINEL_SIGNATURE = "sla.build42-lifecycle/42.20/v1"

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function validSentinel(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    local allowed = { signature = true, owner = true }
    for key in pairs(value) do if type(key) ~= "string" or not allowed[key] then return false end end
    if rawget(value, "signature") ~= SENTINEL_SIGNATURE then return false end
    local owner = rawget(value, "owner")
    if type(owner) ~= "table" or getmetatable(owner) ~= nil then return false end
    local ownerAllowed = { install = true, status = true, clientState = true }
    for key in pairs(owner) do if type(key) ~= "string" or not ownerAllowed[key] then return false end end
    return type(rawget(owner, "install")) == "function" and type(rawget(owner, "status")) == "function"
        and type(rawget(owner, "clientState")) == "function"
end

local function installOwner(owner)
    local called, result = pcall(owner.install)
    if not called then return failure("lifecycle_install_threw", "owner.install") end
    if type(result) ~= "table" or result.ok ~= true then
        return failure("lifecycle_install_invalid", "owner.install")
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
    OwnerSnapshot = require "SurvivorLevelingAdvancement/Runtime/OwnerSnapshot",
    OwnerSession = require "SurvivorLevelingAdvancement/Runtime/OwnerSession",
    ApTransaction = require "SurvivorLevelingAdvancement/Advancement/ApTransaction",
    SupportedAwardProcessor = require "SurvivorLevelingAdvancement/XP/SupportedAwardProcessor",
    WorldSettings = require "SurvivorLevelingAdvancement/Runtime/WorldSettings",
    EventDerivedXpSource = require "SurvivorLevelingAdvancement/XP/EventDerivedXpSource",
    ServiceComposition = require "SurvivorLevelingAdvancement/Runtime/ServiceComposition",
}

local globals = {
    PerkFactory = PerkFactory,
    Perks = Perks,
    SandboxOptions = SandboxOptions,
    SandboxVars = SandboxVars,
    PZMath = PZMath,
    Events = Events,
    addXp = addXp,
    addXpNoMultiplier = addXpNoMultiplier,
    isServer = isServer,
    isClient = isClient,
    instanceof = instanceof,
    sendClientCommand = sendClientCommand,
    sendServerCommand = sendServerCommand,
}

local created = modules.Build42Lifecycle.create({ modules = modules, globals = globals })
if type(created) ~= "table" or created.ok ~= true or type(created.owner) ~= "table" then
    return type(created) == "table" and created or failure("lifecycle_create_invalid", "Build42Lifecycle.create")
end
local sentinel = { signature = SENTINEL_SIGNATURE, owner = created.owner }
if not validSentinel(sentinel) then return failure("lifecycle_create_invalid", "Build42Lifecycle owner surface") end
rawset(_G, SENTINEL_KEY, sentinel)
local installed = installOwner(created.owner)
if not installed.ok then return installed end
return created.owner
