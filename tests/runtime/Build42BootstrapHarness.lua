local key = "__SLA_Build42Lifecycle_42_20_v1"
local signature = "sla.build42-lifecycle/42.20/v1"
local evidence = rawget(_G, "__C10T_BOOTSTRAP_EVIDENCE")

local function check(condition, message)
    if not condition then error(message, 2) end
    evidence.checks = evidence.checks + 1
end

local function event()
    local callbacks, adds = {}, 0
    return {
        Add = function(callback)
            adds = adds + 1
            callbacks[#callbacks + 1] = callback
        end,
        fire = function(...)
            local index = 1
            while index <= #callbacks do
                callbacks[index](...)
                index = index + 1
            end
        end,
        adds = function() return adds end,
    }
end

local function events()
    return { OnGameStart = event(), OnCreatePlayer = event() }
end

local function exactOwner(owner)
    local allowed = {
        install = true, status = true, clientState = true, refreshOwner = true,
        setClientStateListener = true, requestAdvancement = true,
        advancementStatus = true, requestAdmin = true, adminStatus = true,
    }
    if type(owner) ~= "table" or getmetatable(owner) ~= nil then return false end
    local count = 0
    for name in pairs(owner) do
        count = count + 1
        if not allowed[name] or type(rawget(owner, name)) ~= "function" then return false end
    end
    return count == 9
end

local function validOwner(install)
    return {
        install = install,
        status = function() return { ok = true } end,
        clientState = function() return { ok = true, present = false } end,
        refreshOwner = function() return { ok = false } end,
        setClientStateListener = function() return { ok = true } end,
        requestAdvancement = function() return { ok = false } end,
        advancementStatus = function() return { ok = true, pending = false } end,
        requestAdmin = function() return { ok = false } end,
        adminStatus = function() return { ok = true, pending = false } end,
    }
end

local function prepareFresh(serverValue, clientValue, nextPhase)
    rawset(_G, key, nil)
    evidence.serverValue, evidence.clientValue = serverValue, clientValue
    evidence.events = events()
    Events = evidence.events
    evidence.modeBaselineServer = evidence.serverCalls
    evidence.modeBaselineClient = evidence.clientCalls
    evidence.createBaseline = evidence.creates
    evidence.installBaseline = evidence.installs
    evidence.phase = nextPhase
end

local function prepareUnresolved(nextPhase)
    prepareFresh(false, false, nextPhase)
end

if evidence == nil then
    evidence = {
        phase = 1,
        checks = 0,
        requires = {},
        creates = 0,
        installs = 0,
        serverCalls = 0,
        clientCalls = 0,
        serverValue = false,
        clientValue = false,
        events = events(),
    }
    rawset(_G, "__C10T_BOOTSTRAP_EVIDENCE", evidence)

    evidence.runtimeFactory = {}
    evidence.accountingMode = {}
    evidence.advancementSession = {}
    evidence.adminSession = {}
    evidence.advancementTransport = {}
    evidence.adminTransport = {}
    evidence.adminBoundary = {}

    local function concreteOwner(mode)
        local owner = validOwner(function()
            evidence.installs = evidence.installs + 1
            if evidence.concreteInstallBehavior == "throw" then error("install boom") end
            if evidence.concreteInstallBehavior == "malformed" then return "bad" end
            if evidence.concreteInstallBehavior == "failure" then
                return { ok = false, code = "event_register_threw", detail = "OnServerCommand" }
            end
            return { ok = true }
        end)
        owner.status = function()
            return { ok = true, mode = mode, installed = true, started = false, ready = false }
        end
        return owner
    end

    evidence.lifecycle = {
        create = function(argument)
            evidence.creates = evidence.creates + 1
            evidence.created = argument
            evidence.firstCreated = evidence.firstCreated or argument
            if evidence.createBehavior == "throw" then error("create boom") end
            if evidence.createBehavior == "malformed_owner" then
                return { ok = true, owner = { install = function() return { ok = true } end } }
            end
            local mode = evidence.serverValue == true and "server"
                or evidence.clientValue == true and "client" or "single_player"
            return { ok = true, owner = concreteOwner(mode) }
        end,
    }

    require = function(path)
        evidence.requires[path] = (evidence.requires[path] or 0) + 1
        if path == "SurvivorLevelingAdvancement/Runtime/Build42Lifecycle" then return evidence.lifecycle end
        if path == "SurvivorLevelingAdvancement/Runtime/Build42RuntimeFactory" then return evidence.runtimeFactory end
        if path == "SurvivorLevelingAdvancement/Runtime/AccountingMode" then return evidence.accountingMode end
        if path == "SurvivorLevelingAdvancement/Runtime/AdvancementSession" then return evidence.advancementSession end
        if path == "SurvivorLevelingAdvancement/Runtime/AdminSession" then return evidence.adminSession end
        if path == "SurvivorLevelingAdvancement/Runtime/Build42AdvancementTransport" then return evidence.advancementTransport end
        if path == "SurvivorLevelingAdvancement/Runtime/Build42AdminTransport" then return evidence.adminTransport end
        if path == "SurvivorLevelingAdvancement/Adapters/Build42AdminBoundary" then return evidence.adminBoundary end
        return {}
    end

    evidence.perkFactory, evidence.perks, evidence.options = {}, {}, {}
    evidence.vars, evidence.math = {}, {}
    PerkFactory, Perks, SandboxOptions = evidence.perkFactory, evidence.perks, evidence.options
    SandboxVars, PZMath = evidence.vars, evidence.math
    Events = evidence.events
    addXp, addXpNoMultiplier = function() end, function() end
    isServer = function()
        evidence.serverCalls = evidence.serverCalls + 1
        if evidence.serverValue == "throw" then error("server mode") end
        return evidence.serverValue
    end
    isClient = function()
        evidence.clientCalls = evidence.clientCalls + 1
        if evidence.clientValue == "throw" then error("client mode") end
        return evidence.clientValue
    end
    instanceof = function() return false end
    getSpecificPlayer = function() return nil end
    sendClientCommand, sendServerCommand = function() end, function() end
    rawset(_G, key, nil)
elseif evidence.phase == 1 then
    local sentinel = rawget(_G, key)
    check(type(sentinel) == "table" and sentinel.signature == signature, "first unresolved sentinel")
    check(exactOwner(sentinel.owner), "first unresolved facade has exact owner surface")
    check(evidence.creates == 0, "first unresolved load creates no lifecycle")
    check(evidence.serverCalls == 1 and evidence.clientCalls == 1, "first load checks each mode once")
    check(evidence.events.OnGameStart.adds() == 1, "first load adds one game-start resolver")
    check(evidence.events.OnCreatePlayer.adds() == 1, "first load adds one create-player resolver")
    check(sentinel.owner.status().mode == "unresolved", "first facade reports unresolved mode")
    check(sentinel.owner.status().installed == true, "first facade reports resolver installation")
    check(sentinel.owner.clientState(0).code == "lifecycle_unresolved", "unresolved facade exposes bounded views")
    evidence.facade = sentinel.owner
    evidence.phase = 2
elseif evidence.phase == 2 then
    local sentinel = rawget(_G, key)
    check(sentinel.owner == evidence.facade, "both-false reload preserves facade identity")
    check(evidence.creates == 0, "both-false reload stays unresolved")
    check(evidence.serverCalls == 2 and evidence.clientCalls == 2, "both-false reload checks each mode once")
    check(evidence.events.OnGameStart.adds() == 1, "reload does not duplicate game-start resolver")
    check(evidence.events.OnCreatePlayer.adds() == 1, "reload does not duplicate create-player resolver")
    evidence.clientValue = true
    evidence.phase = 3
elseif evidence.phase == 3 then
    local sentinel = rawget(_G, key)
    check(sentinel.owner == evidence.facade, "client reload preserves facade identity")
    check(evidence.creates == 1 and evidence.installs == 1, "client reload creates and installs one lifecycle")
    check(evidence.serverCalls == 3 and evidence.clientCalls == 3, "client reload checks each mode once")
    check(evidence.firstCreated.globals == _G, "bootstrap passes exact global table")
    check(evidence.firstCreated.modules.Build42RuntimeFactory == evidence.runtimeFactory, "bootstrap passes exact module table")
    check(evidence.firstCreated.mode == "client", "client reload passes one authoritative mode")
    check(evidence.firstCreated.modules.AccountingMode == evidence.accountingMode, "bootstrap includes accounting mode")
    check(evidence.firstCreated.modules.AdvancementSession == evidence.advancementSession, "bootstrap includes advancement session")
    check(evidence.firstCreated.modules.AdminSession == evidence.adminSession, "bootstrap includes admin session")
    check(evidence.firstCreated.modules.Build42AdvancementTransport == evidence.advancementTransport, "bootstrap includes advancement transport")
    check(evidence.firstCreated.modules.Build42AdminTransport == evidence.adminTransport, "bootstrap includes admin transport")
    check(evidence.firstCreated.modules.Build42AdminBoundary == evidence.adminBoundary, "bootstrap includes admin boundary")
    check(sentinel.owner.status().mode == "client", "client reload resolves facade")
    local creates, serverCalls, clientCalls = evidence.creates, evidence.serverCalls, evidence.clientCalls
    evidence.serverValue, evidence.clientValue = true, false
    evidence.events.OnGameStart.fire()
    evidence.events.OnCreatePlayer.fire(0, {})
    check(evidence.creates == creates, "resolved callbacks are inert")
    check(evidence.serverCalls == serverCalls and evidence.clientCalls == clientCalls, "resolved callbacks do not recheck mode")
    prepareUnresolved(4)
elseif evidence.phase == 4 then
    local sentinel = rawget(_G, key)
    local facade = sentinel.owner
    check(facade.status().mode == "unresolved", "SP scenario begins unresolved")
    local creates = evidence.creates
    evidence.events.OnCreatePlayer.fire(0, {})
    check(evidence.creates == creates, "both-false create-player does not resolve SP")
    evidence.events.OnGameStart.fire()
    check(evidence.creates == creates + 1, "actual game-start resolves one SP lifecycle")
    check(evidence.created.mode == "single_player", "game-start passes authoritative SP mode")
    check(facade.status().mode == "single_player", "game-start selects single player")
    evidence.spFacade = facade
    evidence.serverValue, evidence.clientValue = true, false
    evidence.phase = 5
elseif evidence.phase == 5 then
    check(rawget(_G, key).owner == evidence.spFacade, "resolved SP reload preserves facade")
    check(rawget(_G, key).owner.status().mode == "single_player", "resolved SP cannot switch to server")
    prepareUnresolved(6)
elseif evidence.phase == 6 then
    local sentinel = rawget(_G, key)
    local creates = evidence.creates
    evidence.clientValue = true
    evidence.events.OnCreatePlayer.fire(2, {})
    check(evidence.creates == creates + 1, "create-player gate resolves one client lifecycle")
    check(evidence.created.mode == "client", "create-player gate passes authoritative client mode")
    check(sentinel.owner.status().mode == "client", "create-player gate selects client")
    check(rawget(_G, key).owner == sentinel.owner, "create-player resolution preserves facade")
    prepareUnresolved(7)
elseif evidence.phase == 7 then
    local facade = rawget(_G, key).owner
    check(evidence.events.OnGameStart.adds() == 1 and evidence.events.OnCreatePlayer.adds() == 1,
        "ownership scenario installs exact resolver gates")
    local creates, serverCalls, clientCalls = evidence.creates, evidence.serverCalls, evidence.clientCalls
    Events = events()
    evidence.clientValue = true
    local lost = facade.install()
    check(lost.ok == false and lost.code == "event_ownership_lost", "true-flag reload cannot heal replaced resolver events")
    check(evidence.creates == creates, "true-flag replacement creates no lifecycle")
    check(evidence.serverCalls == serverCalls and evidence.clientCalls == clientCalls,
        "ownership failure precedes any new mode check")
    Events = evidence.events
    lost = facade.install()
    check(lost.ok == false and lost.code == "event_ownership_lost", "ownership failure is terminal")
    check(evidence.serverCalls == serverCalls and evidence.clientCalls == clientCalls,
        "terminal ownership failure is not retried")
    prepareFresh(true, true, 8)
elseif evidence.phase == 8 then
    local result, facade = rawget(_G, "C10TBootstrapBothTrue"), rawget(_G, key).owner
    check(result.ok == false and result.code == "mode_invalid", "both-true top-level load fails closed")
    check(evidence.events.OnGameStart.adds() == 0 and evidence.events.OnCreatePlayer.adds() == 0,
        "both-true load installs no resolver gates")
    check(evidence.creates == evidence.createBaseline, "both-true load creates no lifecycle")
    check(evidence.serverCalls == evidence.modeBaselineServer + 1
        and evidence.clientCalls == evidence.modeBaselineClient + 1, "both-true load checks each mode once")
    local serverCalls, clientCalls = evidence.serverCalls, evidence.clientCalls
    evidence.serverValue, evidence.clientValue = false, true
    local repeated = facade.install()
    check(repeated.ok == false and repeated.code == "mode_invalid", "both-true facade remains terminal")
    check(evidence.serverCalls == serverCalls and evidence.clientCalls == clientCalls,
        "both-true facade never retries mode resolution")
    prepareFresh("throw", false, 9)
elseif evidence.phase == 9 then
    local result, facade = rawget(_G, "C10TBootstrapThrowMode"), rawget(_G, key).owner
    check(result.ok == false and result.code == "mode_invalid", "throwing mode top-level load fails closed")
    check(evidence.events.OnGameStart.adds() == 0 and evidence.events.OnCreatePlayer.adds() == 0,
        "throwing mode load installs no resolver gates")
    check(evidence.creates == evidence.createBaseline, "throwing mode load creates no lifecycle")
    check(evidence.serverCalls == evidence.modeBaselineServer + 1
        and evidence.clientCalls == evidence.modeBaselineClient + 1, "throwing mode load calls each resolver once")
    local serverCalls, clientCalls = evidence.serverCalls, evidence.clientCalls
    evidence.serverValue = false
    check(facade.install().code == "mode_invalid", "throwing mode facade remains terminal")
    check(evidence.serverCalls == serverCalls and evidence.clientCalls == clientCalls,
        "throwing mode facade never retries")
    prepareFresh(false, "malformed", 10)
elseif evidence.phase == 10 then
    local result, facade = rawget(_G, "C10TBootstrapMalformedMode"), rawget(_G, key).owner
    check(result.ok == false and result.code == "mode_invalid", "malformed mode top-level load fails closed")
    check(evidence.events.OnGameStart.adds() == 0 and evidence.events.OnCreatePlayer.adds() == 0,
        "malformed mode load installs no resolver gates")
    check(evidence.creates == evidence.createBaseline, "malformed mode load creates no lifecycle")
    check(evidence.serverCalls == evidence.modeBaselineServer + 1
        and evidence.clientCalls == evidence.modeBaselineClient + 1, "malformed mode load calls each resolver once")
    local serverCalls, clientCalls = evidence.serverCalls, evidence.clientCalls
    evidence.clientValue = false
    check(facade.install().code == "mode_invalid", "malformed mode facade remains terminal")
    check(evidence.serverCalls == serverCalls and evidence.clientCalls == clientCalls,
        "malformed mode facade never retries")
    rawset(_G, key, { signature = signature, owner = { install = function() return { ok = true } end } })
    evidence.phase = 11
elseif evidence.phase == 11 then
    check(rawget(_G, "C10TBootstrapCollision").code == "lifecycle_sentinel_collision", "malformed collision")
    rawset(_G, key, { signature = signature, owner = validOwner(function() error("install boom") end) })
    evidence.phase = 12
elseif evidence.phase == 12 then
    check(rawget(_G, "C10TBootstrapThrow").code == "lifecycle_install_threw", "thrown install")
    rawset(_G, key, { signature = signature, owner = validOwner(function() return "bad" end) })
    evidence.phase = 13
elseif evidence.phase == 13 then
    check(rawget(_G, "C10TBootstrapMalformed").code == "lifecycle_install_invalid", "malformed install")
    prepareFresh(false, true, 14)
    evidence.concreteInstallBehavior = "failure"
elseif evidence.phase == 14 then
    local result, facade = rawget(_G, "C10TBootstrapCandidateFailure"), rawget(_G, key).owner
    check(result.ok == false and result.code == "event_register_threw", "candidate install failure is returned")
    check(evidence.creates == evidence.createBaseline + 1, "failed candidate is created once")
    check(evidence.installs == evidence.installBaseline + 1, "failed candidate install is attempted once")
    check(facade.clientState(0).code == "lifecycle_unresolved", "failed candidate remains private")
    local installs = evidence.installs
    check(facade.install().code == "event_register_threw", "failed candidate facade is terminal")
    check(evidence.installs == installs, "failed candidate install is never retried")
    evidence.concreteInstallBehavior = nil
    rawset(_G, key, nil)
    evidence.serverValue, evidence.clientValue = true, false
    evidence.events = events()
    Events = evidence.events
    evidence.createBehavior = "malformed_owner"
    evidence.phase = 15
elseif evidence.phase == 15 then
    check(rawget(_G, "C10TBootstrapMalformedOwner").code == "lifecycle_create_invalid", "malformed concrete owner")
    check(exactOwner(rawget(_G, key).owner), "malformed concrete result keeps stable facade sentinel")
    evidence.createBehavior = nil
    rawset(_G, key, { signature = signature, owner = validOwner(function() return { ok = true } end) })
    rawget(_G, key).owner.dependencies = {}
    evidence.phase = 16
elseif evidence.phase == 16 then
    check(rawget(_G, "C10TBootstrapExtraOwner").code == "lifecycle_sentinel_collision", "extra owner field collision")
    rawset(_G, key, setmetatable({}, { __index = function() error("index boom") end }))
    evidence.phase = 17
elseif evidence.phase == 17 then
    check(rawget(_G, "C10TBootstrapIndexOwner").code == "lifecycle_sentinel_collision", "indexed sentinel collision")
    local required = {
        "SurvivorLevelingAdvancement/Runtime/Build42Lifecycle", "SurvivorLevelingAdvancement/Runtime/Build42RuntimeFactory", "SurvivorLevelingAdvancement/Runtime/Build42OwnerTransport", "SurvivorLevelingAdvancement/Runtime/Build42AdvancementTransport", "SurvivorLevelingAdvancement/Runtime/Build42AdminTransport", "SurvivorLevelingAdvancement/Adapters/Build42AdminBoundary", "SurvivorLevelingAdvancement/Runtime/ClientOwnerState",
        "SurvivorLevelingAdvancement/Adapters/Build42PerkCatalog", "SurvivorLevelingAdvancement/Adapters/VanillaProgressionAdapter", "SurvivorLevelingAdvancement/Adapters/Build42NormalizationSnapshot", "SurvivorLevelingAdvancement/Adapters/Build42WorldSettingsProvider", "SurvivorLevelingAdvancement/Adapters/Build42SandboxMultiplier", "SurvivorLevelingAdvancement/Adapters/Build42XpPositionArithmetic",
        "SurvivorLevelingAdvancement/State/StateCodec", "SurvivorLevelingAdvancement/Persistence/PlayerStateStore", "SurvivorLevelingAdvancement/Core/NaturalLedger", "SurvivorLevelingAdvancement/Core/SurvivorEconomy", "SurvivorLevelingAdvancement/Core/Allotment", "SurvivorLevelingAdvancement/Core/PostMax", "SurvivorLevelingAdvancement/State/MutationScope", "SurvivorLevelingAdvancement/State/ActualObservation", "SurvivorLevelingAdvancement/Runtime/AccountingMode", "SurvivorLevelingAdvancement/Runtime/OwnerSnapshot", "SurvivorLevelingAdvancement/Runtime/OwnerSession", "SurvivorLevelingAdvancement/Runtime/AdvancementSession", "SurvivorLevelingAdvancement/Runtime/AdminSession", "SurvivorLevelingAdvancement/Advancement/ApTransaction", "SurvivorLevelingAdvancement/XP/SupportedAwardProcessor", "SurvivorLevelingAdvancement/Runtime/WorldSettings", "SurvivorLevelingAdvancement/XP/EventDerivedXpSource", "SurvivorLevelingAdvancement/Runtime/ServiceComposition",
    }
    for index = 1, #required do
        check(evidence.requires[required[index]] == 9, "exact bootstrap require count " .. index)
    end
    evidence.phase = 18
end

return evidence.checks
