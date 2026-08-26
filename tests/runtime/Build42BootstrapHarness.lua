local key = "__SLA_Build42Lifecycle_42_20_v1"
local signature = "sla.build42-lifecycle/42.20/v1"
local evidence = rawget(_G, "__C10T_BOOTSTRAP_EVIDENCE")

local function check(condition, message)
    if not condition then error(message, 2) end
    evidence.checks = evidence.checks + 1
end

if evidence == nil then
    evidence = { requires = {}, creates = 0, installs = 0, checks = 0, events = {} }
    rawset(_G, "__C10T_BOOTSTRAP_EVIDENCE", evidence)
    local owner = {
        install = function() evidence.installs = evidence.installs + 1; return { ok = true } end,
        status = function() return { ok = true } end,
        clientState = function() return { ok = true, present = false } end,
        refreshOwner = function() return { ok = false } end,
        setClientStateListener = function() return { ok = true } end,
        requestAdvancement = function() return { ok = false } end,
        advancementStatus = function() return { ok = true, pending = false } end,
    }
    evidence.owner = owner
    evidence.runtimeFactory = {}
    evidence.accountingMode = {}
    evidence.advancementSession = {}
    evidence.advancementTransport = {}
    local lifecycle = {
        create = function(argument)
            evidence.creates = evidence.creates + 1
            evidence.created = argument
            return { ok = true, owner = owner }
        end,
    }
    evidence.lifecycle = lifecycle
    require = function(path)
        evidence.requires[path] = (evidence.requires[path] or 0) + 1
        if path == "SurvivorLevelingAdvancement/Runtime/Build42Lifecycle" then return lifecycle end
        if path == "SurvivorLevelingAdvancement/Runtime/Build42RuntimeFactory" then return evidence.runtimeFactory end
        if path == "SurvivorLevelingAdvancement/Runtime/AccountingMode" then return evidence.accountingMode end
        if path == "SurvivorLevelingAdvancement/Runtime/AdvancementSession" then return evidence.advancementSession end
        if path == "SurvivorLevelingAdvancement/Runtime/Build42AdvancementTransport" then return evidence.advancementTransport end
        return {}
    end
    evidence.perkFactory, evidence.perks, evidence.options, evidence.vars, evidence.math = {}, {}, {}, {}, {}
    PerkFactory, Perks, SandboxOptions, SandboxVars, PZMath = evidence.perkFactory, evidence.perks, evidence.options, evidence.vars, evidence.math
    Events = evidence.events
    addXp, addXpNoMultiplier = function() end, function() end
    isServer, isClient, instanceof = function() return false end, function() return false end, function() return false end
    sendClientCommand, sendServerCommand = function() end, function() end
    rawset(_G, key, nil)
    evidence.phase = 1
elseif evidence.phase == 1 then
    check(evidence.creates == 1 and evidence.installs == 2, "bootstrap first load and reload")
    check(evidence.requires["SurvivorLevelingAdvancement/Runtime/Build42Lifecycle"] == 1, "lifecycle required exactly once")
    check(evidence.created.modules.Build42RuntimeFactory == evidence.runtimeFactory, "exact runtime factory")
    check(evidence.created.modules.AccountingMode == evidence.accountingMode, "exact accounting mode factory")
    check(evidence.created.modules.AdvancementSession == evidence.advancementSession, "exact advancement session factory")
    check(evidence.created.modules.Build42AdvancementTransport == evidence.advancementTransport, "exact advancement transport factory")
    check(evidence.created.globals == _G, "bootstrap passes exact global table")
    local originalAddXp = addXp
    local replacementAddXp = function() end
    evidence.created.globals.addXp = replacementAddXp
    check(addXp == replacementAddXp, "lifecycle globals owns real addXp cell")
    addXp = originalAddXp
    check(evidence.owner.modules == nil and type(rawget(_G, key).owner.status) == "function"
        and type(rawget(_G, key).owner.refreshOwner) == "function"
        and type(rawget(_G, key).owner.setClientStateListener) == "function", "no dependencies exposed")
    local required = {
        "SurvivorLevelingAdvancement/Runtime/Build42Lifecycle", "SurvivorLevelingAdvancement/Runtime/Build42RuntimeFactory", "SurvivorLevelingAdvancement/Runtime/Build42OwnerTransport", "SurvivorLevelingAdvancement/Runtime/Build42AdvancementTransport", "SurvivorLevelingAdvancement/Runtime/ClientOwnerState",
        "SurvivorLevelingAdvancement/Adapters/Build42PerkCatalog", "SurvivorLevelingAdvancement/Adapters/VanillaProgressionAdapter", "SurvivorLevelingAdvancement/Adapters/Build42NormalizationSnapshot", "SurvivorLevelingAdvancement/Adapters/Build42WorldSettingsProvider", "SurvivorLevelingAdvancement/Adapters/Build42SandboxMultiplier", "SurvivorLevelingAdvancement/Adapters/Build42XpPositionArithmetic",
        "SurvivorLevelingAdvancement/State/StateCodec", "SurvivorLevelingAdvancement/Persistence/PlayerStateStore", "SurvivorLevelingAdvancement/Core/NaturalLedger", "SurvivorLevelingAdvancement/Core/SurvivorEconomy", "SurvivorLevelingAdvancement/Core/Allotment", "SurvivorLevelingAdvancement/Core/PostMax", "SurvivorLevelingAdvancement/State/MutationScope", "SurvivorLevelingAdvancement/State/ActualObservation", "SurvivorLevelingAdvancement/Runtime/AccountingMode", "SurvivorLevelingAdvancement/Runtime/OwnerSnapshot", "SurvivorLevelingAdvancement/Runtime/OwnerSession", "SurvivorLevelingAdvancement/Runtime/AdvancementSession", "SurvivorLevelingAdvancement/Advancement/ApTransaction", "SurvivorLevelingAdvancement/XP/SupportedAwardProcessor", "SurvivorLevelingAdvancement/Runtime/WorldSettings", "SurvivorLevelingAdvancement/XP/EventDerivedXpSource", "SurvivorLevelingAdvancement/Runtime/ServiceComposition",
    }
    for index = 1, #required do check(evidence.requires[required[index]] == 1, "exact bootstrap require " .. index) end
    rawset(_G, key, { signature = signature, owner = { install = function() return { ok = true } end } })
    evidence.phase = 2
elseif evidence.phase == 2 then
    check(rawget(_G, "C10TBootstrapCollision").code == "lifecycle_sentinel_collision", "malformed collision")
    rawset(_G, key, { signature = signature, owner = {
        install = function() error("install boom") end, status = function() end, clientState = function() end,
        refreshOwner = function() end, setClientStateListener = function() end,
        requestAdvancement = function() end, advancementStatus = function() end,
    } })
    evidence.phase = 3
elseif evidence.phase == 3 then
    check(rawget(_G, "C10TBootstrapThrow").code == "lifecycle_install_threw", "thrown install")
    rawset(_G, key, { signature = signature, owner = {
        install = function() return "bad" end, status = function() end, clientState = function() end,
        refreshOwner = function() end, setClientStateListener = function() end,
        requestAdvancement = function() end, advancementStatus = function() end,
    } })
    evidence.phase = 4
elseif evidence.phase == 4 then
    check(rawget(_G, "C10TBootstrapMalformed").code == "lifecycle_install_invalid", "malformed install")
    rawset(_G, key, nil)
    evidence.lifecycle.create = function() return { ok = true, owner = { install = function() return { ok = true } end } } end
    evidence.phase = 5
elseif evidence.phase == 5 then
    check(rawget(_G, "C10TBootstrapMalformedOwner").code == "lifecycle_create_invalid", "malformed owner leaves no sentinel")
    check(rawget(_G, key) == nil, "malformed owner sentinel absent")
    rawset(_G, key, { signature = signature, owner = {
        install = function() return { ok = true } end, status = function() end, clientState = function() end,
        refreshOwner = function() end, setClientStateListener = function() end,
        requestAdvancement = function() end, advancementStatus = function() end, dependencies = {},
    } })
    evidence.phase = 6
elseif evidence.phase == 6 then
    check(rawget(_G, "C10TBootstrapExtraOwner").code == "lifecycle_sentinel_collision", "extra owner field collision")
    rawset(_G, key, setmetatable({}, { __index = function() error("index boom") end }))
    evidence.phase = 7
end

return evidence.checks
