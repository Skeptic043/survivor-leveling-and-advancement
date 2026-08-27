local assertions = 0
local function eq(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end
local function yes(value, message) eq(value, true, message) end
local function no(value, message) eq(value, false, message) end
local function exactKeys(value, allowed, expectedCount, message)
    local count = 0
    for key in pairs(value) do
        count = count + 1
        yes(allowed[key] == true, (message or "shape") .. " key " .. tostring(key))
    end
    eq(count, expectedCount, (message or "shape") .. " count")
end

local function event()
    local callbacks, adds, removes = {}, 0, 0
    return {
        Add = function(callback) adds = adds + 1; callbacks[#callbacks + 1] = callback end,
        Remove = function(callback)
            removes = removes + 1
            for index = 1, #callbacks do
                if callbacks[index] == callback then table.remove(callbacks, index); break end
            end
        end,
        fire = function(...) for index = 1, #callbacks do callbacks[index](...) end end,
        adds = function() return adds end,
        removes = function() return removes end,
    }
end

local function fixture(server, client, configure)
    local calls = {}
    local debugCalls = 0
    local specificPlayers, specificPlayerCalls = {}, {}
    local events = { OnServerStarted = event(), OnClientCommand = event(), OnCreatePlayer = event(), OnMiniScoreboardUpdate = event(), OnTick = event(), OnServerCommand = event(), OnDisconnect = event(), OnGameStart = event() }
    local session = {
        ready = function(player) calls[#calls + 1] = { "ready", player }; return { ok = true, snapshot = { marker = player, ready = true, revision = 0 } } end,
        snapshot = function(player) calls[#calls + 1] = { "snapshot", player }; return { ok = true, snapshot = { marker = player } } end,
        isReady = function() return true end,
        clearPlayer = function() return { ok = true } end,
    }
    local advancementSession = {
        request = function(player, request)
            calls[#calls + 1] = { "session_request", player, request }
            return {
                ok = true,
                applied = true,
                requestId = request.requestId,
                perkId = request.perkId,
                apCost = 1,
                mastered = false,
                snapshot = { ready = true, revision = request.expectedRevision + 1 },
            }
        end,
    }
    local adminSession = {
        inspect = function(player)
            calls[#calls + 1] = { "admin_inspect", player }
            return { ok = true, summary = {
                accountingMode = "Tracked", revision = 0, level = 0, xpIntoLevel = 0,
                xpForNextLevel = 100, spent = 0, availableAp = 0,
            } }
        end,
        request = function(player, request)
            calls[#calls + 1] = { "admin_session_request", player, request }
            local gain = request.kind == "awardSurvivorLevels" and request.count
                or (request.kind == "clearAdvancementSlots" and 0 or 1)
            local result = {
                ok = true, applied = true, kind = request.kind,
                levelsGained = gain,
                apGained = gain,
                summary = {
                    accountingMode = "Tracked", revision = request.expectedRevision + 1,
                    level = gain,
                    xpIntoLevel = 0, xpForNextLevel = 100, spent = 0,
                    availableAp = gain,
                },
            }
            if request.kind == "awardSurvivorXp" then result.amount = request.amount
            elseif request.kind == "awardSurvivorLevels" then result.count = request.count end
            return result
        end,
    }
    local source = { install = function() calls[#calls + 1] = { "install_source" }; return { ok = true } end }
    local runtime = { catalog = {}, services = {
        xpSource = source, ownerSession = session, advancementSession = advancementSession, adminSession = adminSession,
    } }
    local localClient = {
        ready = function(slot, player) calls[#calls + 1] = { "client_ready", slot, player }; return { ok = true } end,
        refresh = function(slot, player) calls[#calls + 1] = { "client_refresh", slot, player }; return { ok = true } end,
        handle = function(module, command, args) calls[#calls + 1] = { "client_handle", module, command, args }; return { ok = true, handled = true, accepted = true, localSlot = 0 } end,
        reset = function() calls[#calls + 1] = { "client_reset" }; return { ok = true } end,
        resetSlot = function(slot) calls[#calls + 1] = { "client_reset_slot", slot }; return { ok = true } end,
        acceptLocal = function(slot, snapshot) calls[#calls + 1] = { "client_accept", slot, snapshot }; return { ok = true, accepted = true } end,
        get = function() return { ok = true, present = false } end,
        status = function() return { ok = true } end,
    }
    local serverTransport = {
        handle = function(module, command, player, args) calls[#calls + 1] = { "server_handle", module, command, player, args }; return { ok = true, handled = true } end,
        clearPlayer = function() return { ok = true } end,
        publish = function(player) calls[#calls + 1] = { "owner_publish", player }; return { ok = true } end,
    }
    local advancementServer = {
        handle = function(module, command, player, args) calls[#calls + 1] = { "adv_server_handle", module, command, player, args }; return { ok = true, handled = true } end,
    }
    local advancementClient = {
        request = function(slot, player, perkId) calls[#calls + 1] = { "adv_request", slot, player, perkId }; return { ok = true, requestId = "mp:1" } end,
        handle = function(module, command, args)
            calls[#calls + 1] = { "adv_handle", module, command, args }
            return { ok = true, handled = true, localSlot = 0, result = {
                ok = true, applied = false, requestId = "mp:1", perkId = "Strength",
                code = "insufficient_ap", detail = "ap",
            } }
        end,
        status = function() return { ok = true, pending = false } end,
        resetSlot = function(slot) calls[#calls + 1] = { "adv_reset_slot", slot }; return { ok = true } end,
        reset = function() calls[#calls + 1] = { "adv_reset" }; return { ok = true } end,
    }
    local adminServer = {
        handle = function(module, command, player, args) calls[#calls + 1] = { "admin_server_handle", module, command, player, args }; return { ok = true, handled = true } end,
    }
    local adminClient = {
        request = function(slot, player, request) calls[#calls + 1] = { "admin_request", slot, player, request }; return { ok = true, requestId = "admin:1" } end,
        handle = function(module, command, args)
            calls[#calls + 1] = { "admin_handle", module, command, args }
            return { ok = true, handled = true, localSlot = 0, result = {
                ok = true, requestId = "admin:1", operation = "inspect", target = { onlineId = 4, username = "Target" },
                outcome = "inspected", summary = {
                    accountingMode = "Tracked", revision = 0, level = 0, xpIntoLevel = 0,
                    xpForNextLevel = 100, spent = 0, availableAp = 0,
                },
            } }
        end,
        status = function() return { ok = true, pending = false } end,
        resetSlot = function(slot) calls[#calls + 1] = { "admin_reset_slot", slot }; return { ok = true } end,
        reset = function() calls[#calls + 1] = { "admin_reset" }; return { ok = true } end,
    }
    local adminBoundary = { authorizeAndResolve = function() return { ok = false } end }
    local factoryCalls, clientCreates, serverCreates, advancementClientCreates, advancementServerCreates = 0, 0, 0, 0, 0
    local adminClientCreates, adminServerCreates, adminBoundaryCreates = 0, 0, 0
    local validator = function(snapshot)
        local copy = {}
        for key, value in pairs(snapshot) do if key ~= "private" then copy[key] = value end end
        return { ok = true, snapshot = copy }
    end
    local modules = {
        Build42RuntimeFactory = { create = function(argument) factoryCalls = factoryCalls + 1; calls[#calls + 1] = { "factory", argument }; return { ok = true, runtime = runtime } end },
        Build42OwnerTransport = {
            createClient = function(argument) clientCreates = clientCreates + 1; calls[#calls + 1] = { "create_client", argument }; return { ok = true, client = localClient } end,
            createServer = function(argument) serverCreates = serverCreates + 1; calls[#calls + 1] = { "create_server", argument }; return { ok = true, server = serverTransport } end,
        },
        Build42AdvancementTransport = {
            createClient = function(argument) advancementClientCreates = advancementClientCreates + 1; calls[#calls + 1] = { "create_adv_client", argument }; return { ok = true, client = advancementClient } end,
            createServer = function(argument) advancementServerCreates = advancementServerCreates + 1; calls[#calls + 1] = { "create_adv_server", argument }; return { ok = true, server = advancementServer } end,
        },
        Build42AdminTransport = {
            createClient = function(argument) adminClientCreates = adminClientCreates + 1; calls[#calls + 1] = { "create_admin_client", argument }; return { ok = true, client = adminClient } end,
            createServer = function(argument) adminServerCreates = adminServerCreates + 1; calls[#calls + 1] = { "create_admin_server", argument }; return { ok = true, server = adminServer } end,
        },
        Build42AdminBoundary = {
            create = function(argument) adminBoundaryCreates = adminBoundaryCreates + 1; calls[#calls + 1] = { "create_admin_boundary", argument }; return { ok = true, boundary = adminBoundary } end,
        },
        ClientOwnerState = { create = function() end, validate = validator },
    }
    local globals = {
        Events = events,
        isServer = function() calls[#calls + 1] = { "isServer" }; return server end,
        isClient = function() calls[#calls + 1] = { "isClient" }; return client end,
        isDebugEnabled = function()
            debugCalls = debugCalls + 1
            calls[#calls + 1] = { "isDebugEnabled" }
            return true
        end,
        sendClientCommand = function() end,
        sendServerCommand = function() end,
        getSpecificPlayer = function(slot)
            specificPlayerCalls[#specificPlayerCalls + 1] = slot
            return specificPlayers[slot]
        end,
        Capability = { CanSeePlayersStats = "inspect", CanModifyPlayerStatsInThePlayerStatsUI = "mutate" },
        getPlayerByOnlineID = function() end,
        getPlayerFromUsername = function() end,
        writeLog = function(name, line) calls[#calls + 1] = { "write_log", name, line } end,
    }
    if configure ~= nil then configure({ modules = modules, globals = globals, events = events, specificPlayers = specificPlayers, localClient = localClient, session = session, advancementSession = advancementSession, adminSession = adminSession, source = source, serverTransport = serverTransport, advancementClient = advancementClient, advancementServer = advancementServer, adminClient = adminClient, adminServer = adminServer, adminBoundary = adminBoundary }) end
    local created = Build42Lifecycle.create({ modules = modules, globals = globals })
    return created, { calls = calls, events = events, modules = modules, globals = globals, session = session, source = source, runtime = runtime, localClient = localClient, serverTransport = serverTransport,
        advancementSession = advancementSession, advancementClient = advancementClient, advancementServer = advancementServer,
        adminSession = adminSession, adminClient = adminClient, adminServer = adminServer, adminBoundary = adminBoundary,
        factoryCalls = function() return factoryCalls end, clientCreates = function() return clientCreates end, serverCreates = function() return serverCreates end,
        advancementClientCreates = function() return advancementClientCreates end, advancementServerCreates = function() return advancementServerCreates end,
        adminClientCreates = function() return adminClientCreates end, adminServerCreates = function() return adminServerCreates end,
        adminBoundaryCreates = function() return adminBoundaryCreates end,
        debugCalls = function() return debugCalls end, validator = validator,
        specificPlayers = specificPlayers, specificPlayerCalls = specificPlayerCalls }
end

local function acknowledge(f, localSlot, player)
    f.specificPlayers[localSlot] = player
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
end

do
    local created, f = fixture(true, false)
    yes(created.ok, "server creates")
    exactKeys(created.owner, {
        install = true, status = true, clientState = true,
        refreshOwner = true, setClientStateListener = true,
        requestAdvancement = true, advancementStatus = true,
        requestAdmin = true, adminStatus = true,
    }, 9, "exact owner API")
    eq(f.clientCreates(), 0, "server creates no client transport")
    eq(f.factoryCalls(), 0, "server construction is inert")
    eq(f.events.OnServerStarted.adds(), 0, "server construction registers no event")
    yes(created.owner.install().ok, "server installs")
    yes(created.owner.install().ok, "server install idempotent")
    eq(f.events.OnServerStarted.adds(), 1, "one server start callback")
    eq(f.events.OnClientCommand.adds(), 1, "one client-command callback")
    eq(f.events.OnCreatePlayer.adds(), 0, "server event set has no create-player callback")
    eq(f.events.OnMiniScoreboardUpdate.adds(), 0, "server event set has no post-ack callback")
    f.events.OnServerStarted.fire()
    eq(f.factoryCalls(), 1, "server factory once")
    eq(f.serverCreates(), 1, "server transport after source")
    eq(f.calls[3][1], "factory", "startup factory order")
    eq(f.calls[4][1], "install_source", "source installs after factory")
    eq(f.calls[5][1], "create_server", "server transport follows source install")
    eq(f.calls[5][2].snapshotValidator.validate, f.validator, "server receives construction-captured validator")
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "ownerReady", {}, { correlationId = "x" })
    eq(f.calls[#f.calls][1], "server_handle", "server command delegated")
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "ownerRefresh", {}, { correlationId = "x" })
    eq(f.calls[#f.calls][3], "ownerRefresh", "server refresh exact-dispatched")
    yes(created.owner.status().started, "server started")
    no(created.owner.clientState(0).ok, "server has no client state")
end

do
    local created, f = fixture(true, false)
    f.modules.ClientOwnerState.validate = function() return { ok = false, code = "mutated", detail = "wrong" } end
    yes(created.owner.install().ok, "validator-freeze hooks install")
    f.events.OnServerStarted.fire()
    eq(f.calls[5][2].snapshotValidator.validate, f.validator, "server validator resists later module replacement")
end

do
    local private = { marker = "public", private = "do-not-return" }
    local created, f = fixture(false, true, function(values)
        values.localClient.get = function() return { ok = true, present = true, snapshot = private } end
    end)
    yes(created.ok, "present client-state fixture creates")
    f.modules.ClientOwnerState.validate = function() return { ok = false, code = "mutated", detail = "wrong" } end
    local view = created.owner.clientState(0)
    yes(view.ok, "present client state succeeds through captured validator")
    eq(view.snapshot.marker, "public", "captured validator result returned")
    eq(view.snapshot.private, nil, "client state returns detached validated snapshot")
    created = fixture(false, true, function(values) values.localClient.get = function() error("get boom") end end)
    eq(created.owner.clientState(0).code, "client_state_threw", "client get throw is bounded")
    created = fixture(false, true, function(values) values.localClient.get = function() return { ok = true, present = false, private = true } end end)
    eq(created.owner.clientState(0).code, "client_state_invalid", "extra absent field is rejected")
    created = fixture(false, true, function(values) values.localClient.get = function() return { ok = true, present = true, snapshot = {}, private = true } end end)
    eq(created.owner.clientState(0).code, "client_state_invalid", "extra present field is rejected")
    created = fixture(false, true, function(values) values.localClient.get = function() return { ok = false, code = "invalid_slot", detail = "localSlot" } end end)
    local failed = created.owner.clientState(8)
    eq(failed.code, "invalid_slot", "exact client failure is preserved")
    eq(failed.detail, "localSlot", "exact client failure detail is preserved")
end

do
    local created, f = fixture(true, false, function(values)
        values.serverTransport.handle = function() error("handle boom") end
    end)
    yes(created.owner.install().ok, "server callback-failure hooks install")
    f.events.OnServerStarted.fire()
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "ownerReady", {}, {})
    eq(created.owner.status().failure.code, "owner_server_handle_invalid", "server command throw retained")
end

do
    local created, f = fixture("bad", false)
    no(created.ok, "non-boolean server mode fails")
    eq(created.code, "mode_invalid", "non-boolean server mode code")
    eq(#f.calls, 2, "both mode functions called for invalid server mode")
    created, f = fixture(false, "bad")
    no(created.ok, "non-boolean client mode fails")
    eq(created.code, "mode_invalid", "non-boolean client mode code")
    eq(#f.calls, 2, "both mode functions called for invalid client mode")
end

do
    local attempts = 0
    local created, f = fixture(true, false, function(values)
        values.modules.Build42RuntimeFactory.create = function() attempts = attempts + 1; error("factory boom") end
    end)
    yes(created.owner.install().ok, "factory-failure hooks install")
    f.events.OnServerStarted.fire(); f.events.OnServerStarted.fire()
    eq(attempts, 1, "throwing factory is attempted once")
    eq(created.owner.status().failure.code, "runtime_factory_invalid", "factory throw retained")
end

do
    local attempts = 0
    local created, f = fixture(true, false, function(values)
        values.source.install = function() attempts = attempts + 1; error("install boom") end
    end)
    yes(created.owner.install().ok, "source-failure hooks install")
    f.events.OnServerStarted.fire(); f.events.OnServerStarted.fire()
    eq(attempts, 1, "source failure does not rebuild runtime")
    eq(created.owner.status().failure.code, "xp_source_install_invalid", "source throw retained")
end

do
    local created, f = fixture(true, false, function(values)
        values.modules.Build42OwnerTransport.createServer = function() error("transport boom") end
    end)
    yes(created.owner.install().ok, "server-transport hooks install")
    f.events.OnServerStarted.fire()
    eq(created.owner.status().failure.code, "owner_server_invalid", "server transport throw retained")
end

do
    local created, f = fixture(false, true, function(values)
        values.localClient.ready = function() error("ready boom") end
        values.localClient.handle = function() return "bad" end
        values.localClient.reset = function() error("disconnect boom") end
    end)
    yes(created.owner.install().ok, "callback client installs")
    f.specificPlayers[0] = {}
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(created.owner.status().failure.code, "owner_ready_invalid", "client ready throw retained")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "ownerSnapshot", {})
    eq(created.owner.status().failure.code, "owner_client_handle_invalid", "client handle malformed retained")
    f.events.OnDisconnect.fire()
    eq(created.owner.status().failure.code, "owner_reset_invalid", "disconnect throw retained")
    local before = #f.calls
    f.events.OnCreatePlayer.fire(4, {})
    eq(#f.calls, before, "invalid slot is ignored before transport")
end

do
    local created, f = fixture(false, false, function(values)
        values.localClient.resetSlot = function() error("reset boom") end
    end)
    yes(created.owner.install().ok, "SP failure hooks install")
    f.events.OnGameStart.fire()
    f.events.OnCreatePlayer.fire(0, {})
    eq(created.owner.status().failure.code, "owner_slot_reset_invalid", "SP reset throw retained")
end

do
    local created, f = fixture(false, false)
    local first, second = {}, {}
    yes(created.owner.install().ok, "SP replacement hooks install")
    f.events.OnCreatePlayer.fire(0, first)
    f.events.OnCreatePlayer.fire(0, second)
    f.events.OnGameStart.fire()
    eq(f.calls[#f.calls - 1][2], second, "SP same-slot pending replacement keeps latest player")
end

do
    local created, f = fixture(true, false)
    yes(created.owner.install().ok, "ownership hooks install")
    f.globals.Events = {}
    no(created.owner.install().ok, "event container replacement fails closed")
    eq(created.owner.status().failure.code, "event_ownership_lost", "event container loss retained")
    created, f = fixture(true, false)
    yes(created.owner.install().ok, "second ownership hooks install")
    f.globals.Events.OnServerStarted = event()
    no(created.owner.install().ok, "required event replacement fails closed")
    eq(created.owner.status().failure.code, "event_ownership_lost", "required event loss retained")
end

do
    local readyCalls = 0
    local created, f = fixture(false, true, function(values)
        values.specificPlayers[0] = {}
        values.localClient.ready = function() readyCalls = readyCalls + 1; return { ok = true } end
    end)
    yes(created.owner.install().ok, "client ownership hooks install")
    eq(readyCalls, 0, "installation does not send readiness")
    local capturedPostAckEvent = f.events.OnMiniScoreboardUpdate
    f.globals.Events.OnMiniScoreboardUpdate = event()
    capturedPostAckEvent.fire()
    eq(readyCalls, 0, "replaced post-ack event leaves original callback inert")
    yes(created.owner.status().failure ~= nil, "post-ack ownership loss retains a failure")
    eq(created.owner.status().failure.code, "event_ownership_lost",
        "post-ack event replacement is retained")
    no(created.owner.install().ok, "post-ack ownership loss prevents reinstall")
end

do
    local created, f = fixture(true, false)
    f.source.install = function() return { ok = false, code = "é", detail = "unsafe" } end
    yes(created.owner.install().ok, "unicode failure hooks install")
    f.events.OnServerStarted.fire()
    eq(created.owner.status().failure.code, "xp_source_install_invalid", "non-ASCII dependency code is rejected")
    local status = created.owner.status()
    local allowed, count = { ok = true, mode = true, installed = true, started = true, ready = true, failure = true }, 0
    for key in pairs(status) do count = count + 1; yes(allowed[key] == true, "status allowlist") end
    eq(count, 6, "failed status has only approved fields")
    local client = fixture(false, true)
    local view = client.owner.clientState(0)
    eq(view.ok, true, "client state delegates")
    eq(view.present, false, "client state remains detached view")
end

do
    local created, f = fixture(false, true)
    yes(created.ok, "client creates")
    eq(f.clientCreates(), 1, "client transport created at construction")
    yes(created.owner.install().ok, "client installs")
    eq(f.events.OnCreatePlayer.adds(), 0, "client owns no create-player callback")
    eq(f.events.OnMiniScoreboardUpdate.adds(), 1, "client owns one post-ack callback")
    eq(f.events.OnTick.adds(), 0, "client tick callback waits for an acknowledgment")
    eq(f.events.OnServerCommand.adds(), 1, "client owns one server-command callback")
    eq(f.events.OnDisconnect.adds(), 1, "client owns one disconnect callback")
    eq(f.events.OnServerStarted.adds(), 0, "client does not own server startup")
    eq(f.events.OnGameStart.adds(), 0, "client does not own single-player startup")
    f.specificPlayers[2] = {}
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(f.calls[#f.calls][1], "client_ready", "post-acceptance event readies local player")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "ownerSnapshot", { ok = true })
    eq(f.calls[#f.calls][1], "client_handle", "client response delegated")
    f.events.OnDisconnect.fire()
    eq(f.calls[#f.calls - 2][1], "client_reset", "disconnect resets owner client")
    eq(f.calls[#f.calls - 1][1], "adv_reset", "disconnect resets advancement client")
    eq(f.calls[#f.calls][1], "admin_reset", "disconnect resets admin client")
    local view, count = created.owner.clientState(0), 0
    for key in pairs(view) do count = count + 1; yes(key == "ok" or key == "present", "client state allowlist") end
    eq(count, 2, "client state delegates only its public view")
end

do
    local created = fixture(false, true, function(values)
        values.events.OnMiniScoreboardUpdate = nil
    end)
    no(created.ok, "client construction requires exact post-ack event")
    eq(created.code, "invalid_dependencies", "missing post-ack event fails closed")

    created = fixture(false, true, function(values)
        values.events.OnTick.Remove = nil
    end)
    no(created.ok, "client construction requires removable exact tick event")
    eq(created.code, "invalid_dependencies", "missing tick removal fails closed")
end

do
    local first, replacement, returned, split = {}, {}, {}, {}
    local ready, f = {}, nil
    local created
    created, f = fixture(false, true, function(values)
        values.localClient.ready = function(slot, player)
            eq(f.events.OnTick.removes(), #ready + 1, "tick removes itself before readiness")
            ready[#ready + 1] = { slot, player }
            return { ok = true }
        end
    end)
    yes(created.owner.install().ok, "deferred readiness installs")
    yes(created.owner.install().ok, "deferred readiness reload remains idempotent")
    eq(f.events.OnTick.adds(), 0, "install does not register a persistent tick")
    f.specificPlayers[0] = first
    f.events.OnMiniScoreboardUpdate.fire()
    eq(#ready, 0, "acknowledgment performs no immediate readiness send")
    eq(f.events.OnTick.adds(), 1, "first deferred slot registers one tick")
    f.specificPlayers[0] = replacement
    f.events.OnMiniScoreboardUpdate.fire()
    eq(f.events.OnTick.adds(), 1, "repeated acknowledgment coalesces the active batch")
    f.events.OnTick.fire()
    eq(#ready, 1, "one deferred tick sends once")
    eq(ready[1][2], replacement, "coalesced batch keeps latest identity")
    f.events.OnMiniScoreboardUpdate.fire()
    eq(f.events.OnTick.adds(), 1, "unchanged identity schedules no tick")
    f.specificPlayers[1] = split
    f.events.OnMiniScoreboardUpdate.fire()
    eq(f.events.OnTick.adds(), 2, "later split-screen identity schedules a new tick")
    f.events.OnTick.fire()
    eq(#ready, 2, "later split-screen identity readies once")
    f.specificPlayers[0] = returned
    f.events.OnMiniScoreboardUpdate.fire(); f.events.OnTick.fire()
    f.specificPlayers[0] = replacement
    f.events.OnMiniScoreboardUpdate.fire(); f.events.OnTick.fire()
    eq(#ready, 4, "A-B-A changes each receive later one-shot batches")
end

do
    local player, ownerResets = {}, 0
    local created, f = fixture(false, true, function(values)
        values.localClient.resetSlot = function() ownerResets = ownerResets + 1; return { ok = true } end
    end)
    created.owner.install(); acknowledge(f, 0, player)
    ownerResets = 0
    f.specificPlayers[0] = nil
    f.events.OnMiniScoreboardUpdate.fire()
    eq(ownerResets, 0, "nil transition remains deferred until tick")
    f.events.OnTick.fire()
    eq(ownerResets, 1, "nil transition clears on deferred tick")
end

do
    local readyCalls = 0
    local created, f = fixture(false, true, function(values)
        values.localClient.ready = function() readyCalls = readyCalls + 1; return { ok = true } end
    end)
    created.owner.install()
    f.specificPlayers[0] = {}
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnDisconnect.fire()
    eq(f.events.OnTick.removes(), 1, "disconnect removes a queued tick once")
    f.events.OnTick.fire()
    eq(readyCalls, 0, "disconnect discards queued readiness")
end

do
    local playerA, playerB = {}, {}
    local readyCalls, ownerResets, advancementResets, adminResets, removeCalls = 0, 0, 0, 0, 0
    local failRemove = false
    local created, f = fixture(false, true, function(values)
        values.events.OnTick.Remove = function()
            removeCalls = removeCalls + 1
            if failRemove then error("tick remove") end
        end
        values.localClient.ready = function() readyCalls = readyCalls + 1; return { ok = true } end
        values.localClient.reset = function() ownerResets = ownerResets + 1; return { ok = true } end
        values.advancementClient.reset = function() advancementResets = advancementResets + 1; return { ok = true } end
        values.adminClient.reset = function() adminResets = adminResets + 1; return { ok = true } end
    end)
    created.owner.install(); f.specificPlayers[1] = playerA; f.events.OnMiniScoreboardUpdate.fire(); f.events.OnTick.fire()
    yes(created.owner.requestAdvancement(1, "Strength").ok, "prior player route is usable before disconnect")
    removeCalls = 0
    f.specificPlayers[1] = playerB; f.events.OnMiniScoreboardUpdate.fire(); failRemove = true
    f.events.OnDisconnect.fire()
    eq(removeCalls, 1, "disconnect attempts a queued tick removal once")
    eq(ownerResets, 1, "failed queued removal still resets owner client")
    eq(advancementResets, 1, "failed queued removal still resets advancement client")
    eq(adminResets, 1, "failed queued removal still resets admin client")
    eq(created.owner.status().failure.code, "event_remove_threw", "queued removal failure is retained")
    f.events.OnTick.fire()
    eq(readyCalls, 1, "failed queued removal cannot send a later readiness")
    eq(created.owner.requestAdvancement(1, "Strength").code, "player_not_ready",
        "failed queued removal clears the prior usable request route")
end

do
    local player, readyCalls = {}, 0
    local created, f = fixture(false, true, function(values)
        values.localClient.ready = function() readyCalls = readyCalls + 1; return { ok = true } end
    end)
    created.owner.install(); f.specificPlayers[0] = player; f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnDisconnect.fire()
    eq(f.events.OnTick.removes(), 1, "successful queued disconnect removes the first tick")
    f.events.OnMiniScoreboardUpdate.fire()
    eq(f.events.OnTick.adds(), 2, "reconnect registers a fresh one-shot tick")
    eq(readyCalls, 0, "reconnect remains deferred until its tick")
    f.events.OnTick.fire()
    eq(readyCalls, 1, "reconnect one-shot tick sends readiness once")
end

do
    local readyCalls = 0
    local created, f = fixture(false, true, function(values)
        values.events.OnTick.Add = function() error("tick add") end
        values.localClient.ready = function() readyCalls = readyCalls + 1; return { ok = true } end
    end)
    created.owner.install(); f.specificPlayers[0] = {}; f.events.OnMiniScoreboardUpdate.fire(); f.events.OnTick.fire()
    eq(readyCalls, 0, "thrown tick add cannot send readiness")
    eq(created.owner.status().failure.code, "event_register_threw", "thrown tick add is retained")
    f.specificPlayers[0] = {}; f.events.OnMiniScoreboardUpdate.fire(); f.events.OnTick.fire()
    eq(readyCalls, 0, "thrown tick add never creates recurring sends")

    created, f = fixture(false, true, function(values)
        values.events.OnTick.Remove = function() error("tick remove") end
        values.localClient.ready = function() readyCalls = readyCalls + 1; return { ok = true } end
    end)
    created.owner.install(); f.specificPlayers[0] = {}; f.events.OnMiniScoreboardUpdate.fire(); f.events.OnTick.fire(); f.events.OnTick.fire()
    eq(readyCalls, 0, "thrown tick remove never creates recurring sends")
    eq(created.owner.status().failure.code, "event_remove_threw", "thrown tick remove is retained")
end

do
    local player = {}
    local readyCalls, advancementResets, adminResets = 0, 0, 0
    local created, f = fixture(false, true, function(values)
        values.localClient.ready = function(slot, value)
            readyCalls = readyCalls + 1
            eq(slot, 0, "post-ack ready keeps local slot")
            eq(value, player, "post-ack ready keeps exact player")
            return { ok = true }
        end
        values.advancementClient.resetSlot = function() advancementResets = advancementResets + 1; return { ok = true } end
        values.adminClient.resetSlot = function() adminResets = adminResets + 1; return { ok = true } end
    end)
    yes(created.owner.install().ok, "post-acceptance client installs")
    eq(#f.specificPlayerCalls, 0, "installation does not inspect player slots")
    eq(readyCalls, 0, "installation does not send readiness")
    f.events.OnCreatePlayer.fire(0, player)
    eq(readyCalls, 0, "unowned create-player event does not send readiness")
    f.events.OnMiniScoreboardUpdate.fire({ remote = true })
    f.events.OnTick.fire()
    eq(readyCalls, 0, "remote-only acknowledgment finds no local player")
    eq(advancementResets, 0, "initial nil observations do not reset advancement slots")
    eq(adminResets, 0, "initial nil observations do not reset admin slots")
    f.specificPlayers[0] = player
    f.events.OnMiniScoreboardUpdate.fire({ remote = true })
    f.events.OnTick.fire()
    eq(readyCalls, 1, "post-acceptance player sends readiness once")
    eq(advancementResets, 1, "exact pair resets advancement once")
    eq(adminResets, 1, "exact pair resets admin once")
    f.events.OnMiniScoreboardUpdate.fire({ remote = true })
    f.events.OnTick.fire()
    eq(readyCalls, 1, "repeated remote updates do not resend readiness")
    eq(#f.specificPlayerCalls, 12, "each acknowledgment inspects only four local slots")
    for scan = 0, 2 do
        for slot = 0, 3 do
            eq(f.specificPlayerCalls[scan * 4 + slot + 1], slot,
                "bounded local scan order " .. scan .. ":" .. slot)
        end
    end
end

do
    local slotZero, slotOne = {}, {}
    local ready = {}
    local created, f = fixture(false, true, function(values)
        values.specificPlayers[0] = slotZero
        values.localClient.ready = function(slot, player)
            ready[#ready + 1] = { slot, player }
            return { ok = true }
        end
    end)
    yes(created.owner.install().ok, "split-screen acknowledgment fixture installs")
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(#ready, 1, "first local slot acknowledges independently")
    eq(ready[1][1], 0, "first acknowledgment keeps slot zero")
    f.specificPlayers[1] = slotOne
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(#ready, 2, "later split-screen slot remains eligible")
    eq(ready[2][1], 1, "second acknowledgment keeps slot one")
    eq(ready[2][2], slotOne, "second acknowledgment keeps exact split-screen player")
end

do
    local first, replacement = {}, {}
    local ready = {}
    local created, f = fixture(false, true, function(values)
        values.localClient.ready = function(slot, player)
            ready[#ready + 1] = { slot, player }
            return { ok = true }
        end
    end)
    created.owner.install()
    f.specificPlayers[2] = first
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    first.marker = "same exact player"
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    f.specificPlayers[2] = replacement
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    f.specificPlayers[2] = first
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(#ready, 3, "A-B-A rebinds on every consecutive identity change")
    eq(ready[1][2], first, "first identity uses original player")
    eq(ready[2][2], replacement, "changed exact player remains eligible")
    eq(ready[3][2], first, "returning exact player rebinds after an intervening identity")
    yes(created.owner.requestAdvancement(2, "Strength").ok, "rebound player can request advancement")
    eq(f.calls[#f.calls][3], first, "request identity follows the final A observation")
    f.events.OnDisconnect.fire()
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(#ready, 4, "disconnect clears the retained observation for reconnect")
end

do
    local player = {}
    local ownerResets, advancementResets, adminResets = 0, 0, 0
    local created, f = fixture(false, true, function(values)
        values.localClient.resetSlot = function() ownerResets = ownerResets + 1; return { ok = true } end
        values.advancementClient.resetSlot = function() advancementResets = advancementResets + 1; return { ok = true } end
        values.adminClient.resetSlot = function() adminResets = adminResets + 1; return { ok = true } end
    end)
    created.owner.install(); acknowledge(f, 0, player)
    ownerResets, advancementResets, adminResets = 0, 0, 0
    f.specificPlayers[0] = nil
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(ownerResets, 1, "non-nil-to-nil clears owner transport slot once")
    eq(advancementResets, 1, "non-nil-to-nil clears advancement transport slot once")
    eq(adminResets, 1, "non-nil-to-nil clears admin transport slot once")
    eq(created.owner.requestAdvancement(0, "Strength").code, "player_not_ready",
        "non-nil-to-nil clears retained request identity")
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(ownerResets, 1, "repeated nil does not clear owner slot again")
    eq(advancementResets, 1, "repeated nil does not clear advancement slot again")
    eq(adminResets, 1, "repeated nil does not clear admin slot again")
end

do
    local slotOne, slotThree = {}, {}
    local ready = {}
    local created, f = fixture(false, true, function(values)
        values.specificPlayers[1], values.specificPlayers[3] = slotOne, slotThree
        values.localClient.ready = function()
            ready[#ready + 1] = true
            return { ok = true }
        end
    end)
    yes(created.owner.install().ok, "assigned local players install without adoption")
    eq(#ready, 0, "installation does not adopt assigned local players")
    eq(#f.specificPlayerCalls, 0, "installation performs no local-slot scan")
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(#ready, 2, "post-acceptance event readies assigned local players")
    eq(#f.specificPlayerCalls, 4, "post-acceptance scan remains bounded to four slots")
end

do
    local calls, retained = {}, {}
    local created, f = fixture(false, true, function(values)
        values.globals.getSpecificPlayer = function(slot)
            calls[#calls + 1] = slot
            if slot == 1 then error("resolver boom") end
            if slot == 3 then return retained end
            return nil
        end
    end)
    yes(created.owner.install().ok, "throwing resolver fixture installs")
    eq(#calls, 0, "installation does not invoke resolver")
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(#calls, 4, "throwing resolver remains bounded to four slots")
    yes(created.owner.status().failure ~= nil, "throwing readiness resolver retains a failure")
    eq(created.owner.status().failure.code, "player_resolver_threw", "throwing readiness resolver is retained")
    yes(created.owner.requestAdvancement(3, "Strength").ok, "later bounded slot still adopts after resolver throw")
end

do
    local readyCalls, onlineIdCalls = 0, 0
    local player = { getOnlineID = function() onlineIdCalls = onlineIdCalls + 1; error("must not run") end }
    local created, f = fixture(false, true, function(values)
        values.specificPlayers[1] = player
        values.localClient.ready = function(slot, player)
            readyCalls = readyCalls + 1
            eq(slot, 1, "exact player route keeps slot")
            eq(player, values.specificPlayers[1], "exact player route keeps identity")
            return { ok = true }
        end
    end)
    created.owner.install(); f.events.OnMiniScoreboardUpdate.fire(); f.events.OnTick.fire()
    eq(readyCalls, 1, "exact player readiness does not require an online ID")
    eq(onlineIdCalls, 0, "readiness never calls getOnlineID")
end

do
    local player, readyCalls = {}, 0
    local created, f = fixture(false, true, function(values)
        values.specificPlayers[2] = player
        values.localClient.ready = function()
            readyCalls = readyCalls + 1
            error("ready failed")
        end
    end)
    yes(created.owner.install().ok, "failed readiness fixture installs")
    eq(readyCalls, 0, "installation does not attempt readiness")
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(readyCalls, 1, "failed eligible exact pair is attempted once")
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    f.events.OnCreatePlayer.fire(2, player)
    eq(readyCalls, 1, "failed readiness attempt is not retried by later gates")
    yes(created.owner.status().failure ~= nil, "failed readiness retains a failure")
    eq(created.owner.status().failure.code, "owner_ready_invalid", "failed readiness remains bounded")
end

do
    local created, f = fixture(false, false)
    local player = {}
    yes(created.owner.install().ok, "SP installs")
    eq(f.events.OnGameStart.adds(), 1, "SP owns one game-start callback")
    eq(f.events.OnCreatePlayer.adds(), 1, "SP owns one create-player callback")
    eq(f.events.OnMiniScoreboardUpdate.adds(), 0, "SP event set has no post-ack callback")
    eq(f.events.OnDisconnect.adds(), 0, "SP event set has no disconnect callback")
    f.events.OnCreatePlayer.fire(1, player)
    eq(f.factoryCalls(), 0, "SP player before startup retains without factory")
    f.events.OnGameStart.fire()
    eq(f.factoryCalls(), 1, "SP startup factory once")
    eq(f.calls[#f.calls - 2][1], "client_reset_slot", "SP drain resets exact slot")
    eq(f.calls[#f.calls - 1][1], "ready", "SP drain readies exact player")
    eq(f.calls[#f.calls][1], "client_accept", "SP drain accepts direct snapshot")
    eq(f.calls[#f.calls - 1][2], player, "SP preserves retained player identity")
    f.events.OnCreatePlayer.fire(3, player)
    eq(f.calls[#f.calls - 2][1], "client_reset_slot", "SP post-start resets slot")
    eq(f.calls[#f.calls - 1][1], "ready", "SP post-start direct ready")
end

do
    local created, f = fixture(true, true)
    no(created.ok, "both modes fail closed")
    eq(created.code, "mode_invalid", "both-mode code")
    eq(#f.calls, 2, "mode checks called once each")
end

do
    local _, f = fixture(false, true)
    f.globals.isServer = function() error("authoritative mode must not recheck server") end
    f.globals.isClient = function() error("authoritative mode must not recheck client") end
    local created = Build42Lifecycle.create({ modules = f.modules, globals = f.globals, mode = "client" })
    yes(created.ok, "authoritative client mode bypasses process mode recheck")
    local invalid = Build42Lifecycle.create({ modules = f.modules, globals = f.globals, mode = "unresolved" })
    no(invalid.ok, "unresolved is not a concrete authoritative mode")
    eq(invalid.code, "mode_invalid", "invalid authoritative mode is bounded")
end

do
    local created, f = fixture(true, false)
    f.modules.Build42RuntimeFactory.create = function() return { ok = false, code = "factory_down", detail = "offline" } end
    yes(created.owner.install().ok, "captured factory installs callbacks")
    f.events.OnServerStarted.fire(); f.events.OnServerStarted.fire()
    eq(f.factoryCalls(), 1, "replacement factory is ignored after callable capture")
    eq(created.owner.status().failure, nil, "captured factory succeeds")
end

do
    local created, f = fixture(true, false, function(values)
        values.modules.Build42RuntimeFactory.create = function()
            return { ok = true, runtime = { services = { xpSource = values.source, ownerSession = values.session } } }
        end
    end)
    yes(created.owner.install().ok, "malformed-runtime hooks install")
    f.events.OnServerStarted.fire()
    eq(created.owner.status().failure.code, "runtime_factory_invalid", "missing runtime catalog is rejected")
    created, f = fixture(true, false, function(values)
        values.modules.Build42RuntimeFactory.create = function() return "bad" end
    end)
    yes(created.owner.install().ok, "malformed-factory hooks install")
    f.events.OnServerStarted.fire()
    eq(created.owner.status().failure.code, "runtime_factory_invalid", "malformed factory result is retained")
end

do
    local created, f = fixture(false, true)
    f.events.OnMiniScoreboardUpdate.Add = function() error("ambiguous") end
    no(created.owner.install().ok, "registration throw fails")
    no(created.owner.install().ok, "registration throw is not retried")
    eq(f.events.OnServerCommand.adds(), 0, "registration stops after ambiguous add")
end

do
    local readyCalls = 0
    local created, f = fixture(false, true, function(values)
        values.localClient.ready = function()
            readyCalls = readyCalls + 1
            return { ok = true }
        end
    end)
    f.events.OnServerCommand.Add = function() error("partial add") end
    no(created.owner.install().ok, "partial event registration fails")
    no(created.owner.install().ok, "partial event registration is never retried")
    eq(f.events.OnCreatePlayer.adds(), 0, "partial client install never owns create-player")
    eq(f.events.OnMiniScoreboardUpdate.adds(), 1, "first partial hook remains singular")
    eq(f.events.OnServerCommand.adds(), 0, "throwing partial hook is not counted")
    eq(#f.specificPlayerCalls, 0, "partial client installation never starts readiness")
    f.events.OnCreatePlayer.fire(0, {})
    f.events.OnMiniScoreboardUpdate.fire()
    eq(readyCalls, 0, "callback registered before a later Add failure remains inert")
end

do
    local created, f = fixture(true, false)
    yes(created.owner.install().ok, "dual server installs")
    f.events.OnServerStarted.fire()
    eq(f.serverCreates(), 1, "owner server created once")
    eq(f.advancementServerCreates(), 1, "advancement server created once")
    eq(f.calls[4][1], "install_source", "source precedes both server endpoints")
    eq(f.calls[5][1], "create_server", "owner endpoint created first")
    eq(f.calls[6][1], "create_adv_server", "advancement endpoint created second")
    eq(f.calls[5][2].ownerSession, f.session, "owner endpoint gets exact session")
    eq(f.calls[6][2].advancementSession, f.advancementSession, "advancement endpoint gets exact session")
    eq(f.calls[6][2].snapshotValidator, f.validator, "advancement endpoint gets captured validator")
    local player, args = {}, {}
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "advancementRequest", player, args)
    eq(f.calls[#f.calls][1], "adv_server_handle", "advancement command exact-dispatched")
    eq(f.calls[#f.calls][4], player, "server preserves callback player identity")
    eq(f.calls[#f.calls][5], args, "server preserves callback args identity")
    local before = #f.calls
    f.events.OnClientCommand.fire("Other", "advancementRequest", player, args)
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "unknown", player, args)
    eq(#f.calls, before, "foreign and unknown server commands ignored")
    eq(created.owner.requestAdvancement(0, "Strength").code, "advancement_unavailable", "server request unavailable")
    eq(created.owner.advancementStatus(0).code, "advancement_unavailable", "server status unavailable")
end

do
    local created, f = fixture(true, false, function(values)
        values.advancementServer.handle = function() return { ok = false, code = "invalid_request", detail = "request" } end
    end)
    created.owner.install(); f.events.OnServerStarted.fire()
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "advancementRequest", {}, {})
    eq(created.owner.status().failure, nil, "valid untrusted request rejection does not poison server")

    created, f = fixture(true, false, function(values)
        values.serverTransport.handle = function()
            return { ok = false, code = "invalid_request", detail = "request", committed = false }
        end
    end)
    created.owner.install(); f.events.OnServerStarted.fire()
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "ownerReady", {}, {})
    eq(created.owner.status().failure.code, "invalid_request", "owner committed rejection is retained")

    created, f = fixture(true, false, function(values)
        values.advancementServer.handle = function()
            return { ok = false, code = "invalid_request", detail = "request", committed = false }
        end
    end)
    created.owner.install(); f.events.OnServerStarted.fire()
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "advancementRequest", {}, {})
    eq(created.owner.status().failure.code, "invalid_request", "advancement committed rejection is retained")
end

do
    local malformed = {
        function() return { ok = true } end,
        function() return { ok = true, handled = false } end,
        function() return { ok = true, handled = true, private = true } end,
        function() return setmetatable({ ok = true, handled = true }, {}) end,
    }
    for index = 1, #malformed do
        for endpoint = 1, 2 do
            local created, f = fixture(true, false, function(values)
                if endpoint == 1 then values.serverTransport.handle = malformed[index]
                else values.advancementServer.handle = malformed[index] end
            end)
            created.owner.install(); f.events.OnServerStarted.fire()
            local command = endpoint == 1 and "ownerReady" or "advancementRequest"
            f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", command, {}, {})
            local expected = endpoint == 1 and "owner_server_handle_invalid" or "advancement_server_handle_invalid"
            eq(created.owner.status().failure.code, expected, "server endpoint exact handled shape " .. endpoint .. ":" .. index)
        end
    end
end

do
    local created, f = fixture(false, true)
    yes(created.ok, "multiplayer dual clients create")
    eq(f.clientCreates(), 1, "one owner client")
    eq(f.advancementClientCreates(), 1, "one advancement client")
    eq(f.calls[4][2].ownerClient, f.localClient, "advancement client receives exact owner client")
    created.owner.install()
    eq(created.owner.requestAdvancement(0, "Strength").code, "player_not_ready", "client request requires retained player")
    local players = { {}, {}, {}, {} }
    for slot = 0, 3 do
        acknowledge(f, slot, players[slot + 1])
        local requested = created.owner.requestAdvancement(slot, "Strength")
        yes(requested.ok, "client slot request " .. slot)
        eq(f.calls[#f.calls][2], slot, "request slot " .. slot)
        eq(f.calls[#f.calls][3], players[slot + 1], "request player identity " .. slot)
    end
    local replacement = {}
    acknowledge(f, 2, replacement)
    created.owner.requestAdvancement(2, "Fitness")
    eq(f.calls[#f.calls][3], replacement, "replacement player becomes exact request identity")
    local before = #f.calls
    f.events.OnServerCommand.fire("Other", "advancementResult", {})
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "unknown", {})
    eq(#f.calls, before, "foreign and unknown client commands ignored")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "advancementResult", {})
    eq(f.calls[#f.calls][1], "adv_handle", "advancement response exact-dispatched")
end

do
    local ownerResetCalls, advancementResetCalls = 0, 0
    local created, f = fixture(false, true, function(values)
        values.localClient.reset = function() ownerResetCalls = ownerResetCalls + 1; error("owner reset") end
        values.advancementClient.reset = function() advancementResetCalls = advancementResetCalls + 1; return { ok = true } end
    end)
    created.owner.install(); acknowledge(f, 1, {})
    f.events.OnDisconnect.fire()
    eq(ownerResetCalls, 1, "disconnect attempts owner reset")
    eq(advancementResetCalls, 1, "disconnect attempts advancement reset after owner failure")
    eq(created.owner.status().failure.code, "owner_reset_invalid", "first disconnect failure retained")
    eq(created.owner.requestAdvancement(1, "Strength").code, "player_not_ready", "disconnect clears retained players")
end

do
    local player, readyCalls = {}, 0
    local created, f = fixture(false, true, function(values)
        values.localClient.ready = function()
            readyCalls = readyCalls + 1
            return { ok = true }
        end
    end)
    created.owner.install()
    acknowledge(f, 0, player)
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(readyCalls, 1, "duplicate exact acknowledged pair is readied once")
    f.events.OnDisconnect.fire()
    f.events.OnMiniScoreboardUpdate.fire()
    f.events.OnTick.fire()
    eq(readyCalls, 2, "disconnect reset permits reconnect of the same player object")
end

do
    local ownerResetCalls, advancementResetCalls = 0, 0
    local created, f = fixture(false, true, function(values)
        values.localClient.reset = function() ownerResetCalls = ownerResetCalls + 1; return { ok = true } end
        values.advancementClient.reset = function() advancementResetCalls = advancementResetCalls + 1; return { ok = true } end
    end)
    created.owner.install(); acknowledge(f, 0, {})
    f.globals.Events = {}
    f.events.OnDisconnect.fire()
    eq(ownerResetCalls, 1, "ownership loss still resets owner client")
    eq(advancementResetCalls, 1, "ownership loss still resets advancement client")
    eq(created.owner.status().failure.code, "event_ownership_lost", "ownership loss remains retained after cleanup")
    eq(created.owner.requestAdvancement(0, "Strength").code, "player_not_ready", "ownership-loss disconnect clears players")
end

do
    local ownerShapes = {
        function() return { ok = true } end,
        function() return { ok = true, handled = false, accepted = true } end,
        function() return { ok = true, handled = true, accepted = true, localSlot = 0, private = true } end,
        function() return setmetatable({ ok = true, handled = true, accepted = true, localSlot = 0 }, {}) end,
    }
    for index = 1, #ownerShapes do
        local created, f = fixture(false, true, function(values) values.localClient.handle = ownerShapes[index] end)
        created.owner.install()
        f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "ownerSnapshot", {})
        eq(created.owner.status().failure.code, "owner_client_handle_invalid", "owner response exact handled shape " .. index)
    end
    local created, f = fixture(false, true, function(values)
        values.localClient.handle = function()
            return { ok = true, handled = true, accepted = false, code = "stale_snapshot", localSlot = 0 }
        end
    end)
    created.owner.install(); f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "ownerSnapshot", {})
    eq(created.owner.status().failure, nil, "exact owner handled rejection is valid")
end

do
    local validResult = {
        ok = true, applied = false, requestId = "mp:2", perkId = "Fitness",
        code = "insufficient_ap", detail = "ap",
    }
    local advancementShapes = {
        function() return { ok = true } end,
        function() return { ok = true, handled = false, result = validResult } end,
        function() return { ok = true, handled = true, localSlot = 0, result = validResult, private = true } end,
        function() return setmetatable({ ok = true, handled = true, localSlot = 0, result = validResult }, {}) end,
    }
    for index = 1, #advancementShapes do
        local created, f = fixture(false, true, function(values) values.advancementClient.handle = advancementShapes[index] end)
        created.owner.install()
        f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "advancementResult", {})
        eq(created.owner.status().failure.code, "advancement_client_handle_invalid", "advancement response exact handled shape " .. index)
    end
end

do
    local statusSource = {
        ok = true, pending = false,
        result = { ok = true, applied = false, requestId = "mp:9", perkId = "Strength", code = "insufficient_ap", detail = "ap" },
    }
    local created, f = fixture(false, true, function(values)
        values.advancementClient.status = function() return statusSource end
        values.advancementClient.request = function() return { ok = false, code = "invalid_perk", detail = "perkId" } end
    end)
    local rejectedRequest = created.owner.requestAdvancement(0, "Strength")
    eq(rejectedRequest.code, "player_not_ready", "unready precedes transport request")
    created.owner.install(); acknowledge(f, 0, {})
    rejectedRequest = created.owner.requestAdvancement(0, "Strength")
    eq(rejectedRequest.code, "invalid_perk", "valid client request rejection is returned")
    eq(created.owner.status().failure, nil, "valid client request rejection does not poison lifecycle")
    local view = created.owner.advancementStatus(0)
    eq(view.result.code, "insufficient_ap", "client terminal status delegated")
    no(view.result == statusSource.result, "client terminal result detached")
    eq(view.result.snapshot, nil, "client status cannot expose snapshot")
    view.result.code = "mutated"
    eq(created.owner.advancementStatus(0).result.code, "insufficient_ap", "client status detachment is stable")
end

do
    local outcomes = {
        { ok = false, code = "request_pending", detail = "localSlot" },
        { ok = false, code = "send_failed", detail = "sendClientCommand", committed = false },
    }
    local index = 0
    local created, f = fixture(false, true, function(values)
        values.advancementClient.request = function()
            index = index + 1
            return outcomes[index]
        end
    end)
    created.owner.install(); acknowledge(f, 0, {})
    eq(created.owner.requestAdvancement(0, "Strength").code, "request_pending", "pending client request returned")
    local sendFailure = created.owner.requestAdvancement(0, "Strength")
    eq(sendFailure.code, "send_failed", "client send failure returned")
    no(sendFailure.committed, "client send failure commitment preserved")
    eq(created.owner.status().failure, nil, "valid pending/send failures do not poison lifecycle")
end

do
    local created = fixture(false, true, function(values)
        values.advancementClient.status = function()
            return { ok = true, pending = false, result = {
                ok = true, requestId = "mp:1", perkId = "Strength", private = "leak",
            } }
        end
    end)
    eq(created.owner.advancementStatus(0).code, "advancement_status_invalid", "malformed client status is bounded")
    eq(created.owner.status().failure.code, "advancement_status_invalid", "malformed trusted client status poisons lifecycle")
end

do
    local player, acceptedSnapshot = {}, nil
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function() return { ok = true, present = true, snapshot = { ready = true, revision = 7 } } end
        values.localClient.acceptLocal = function(slot, snapshot)
            acceptedSnapshot = snapshot
            return { ok = true, accepted = true }
        end
    end)
    eq(created.owner.requestAdvancement(0, "Strength").code, "player_not_ready", "SP request before startup is bounded")
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, player)
    local result = created.owner.requestAdvancement(0, "Strength")
    yes(result.ok, "SP applied request succeeds")
    yes(result.applied, "SP applied result")
    eq(result.apCost, 1, "SP AP cost retained")
    eq(result.snapshot, nil, "SP result omits snapshot")
    eq(acceptedSnapshot.revision, 8, "SP accepts exact session snapshot")
    local sessionCall = f.calls[#f.calls]
    eq(sessionCall[1], "session_request", "SP calls composed advancement session")
    eq(sessionCall[2], player, "SP session receives retained player")
    eq(sessionCall[3].expectedRevision, 7, "SP revision comes from owner view")
    local firstId = result.requestId
    local second = created.owner.requestAdvancement(0, "Strength")
    no(second.requestId == firstId, "SP request IDs are monotone")
    local status = created.owner.advancementStatus(0)
    no(status.pending, "SP status is never pending")
    eq(status.result.requestId, second.requestId, "SP status retains last terminal result")
    no(status.result == second, "SP status result is detached")
    exactKeys(result, {
        ok = true, applied = true, requestId = true, perkId = true, apCost = true,
        mastered = true, snapshotAccepted = true,
    }, 7, "SP applied summary")
end

do
    local acceptCalls = 0
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function() return { ok = true, present = true, snapshot = { ready = true, revision = 2 } } end
        values.localClient.acceptLocal = function() acceptCalls = acceptCalls + 1; return { ok = true, accepted = true } end
        values.advancementSession.request = function(_, request)
            return { ok = true, applied = false, requestId = request.requestId, perkId = request.perkId, code = "insufficient_ap", detail = "ap" }
        end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    acceptCalls = 0
    local result = created.owner.requestAdvancement(0, "Strength")
    no(result.applied, "ordinary SP rejection is terminal")
    eq(acceptCalls, 0, "ordinary rejection does not enter owner inbox")
    eq(created.owner.status().failure, nil, "ordinary rejection does not poison lifecycle")
    exactKeys(result, { ok = true, applied = true, requestId = true, perkId = true, code = true, detail = true }, 6, "ordinary rejection summary")
end

do
    local staleSnapshot = { ready = true, revision = 9 }
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function() return { ok = true, present = true, snapshot = { ready = true, revision = 3 } } end
        values.localClient.acceptLocal = function(_, snapshot)
            if snapshot == staleSnapshot then return { ok = true, accepted = false, code = "stale_snapshot" } end
            return { ok = true, accepted = true }
        end
        values.advancementSession.request = function(_, request)
            return { ok = true, applied = false, requestId = request.requestId, perkId = request.perkId,
                code = "stale_revision", detail = "revision", snapshot = staleSnapshot }
        end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local result = created.owner.requestAdvancement(0, "Strength")
    no(result.snapshotAccepted, "ahead owner view may reject stale session snapshot")
    eq(result.snapshotCode, "stale_snapshot", "ahead result reports stale acceptance")
    eq(result.snapshot, nil, "stale summary omits snapshot")
    eq(created.owner.status().failure, nil, "valid stale result does not poison lifecycle")
end

do
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function() return { ok = true, present = true, snapshot = { ready = true, revision = 4 } } end
        values.advancementSession.request = function() return { ok = false, code = "persist_failed", detail = "save", committed = true } end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local result = created.owner.requestAdvancement(0, "Strength")
    no(result.ok, "committed SP failure remains failure")
    yes(result.committed, "committed SP failure preserved")
    eq(result.snapshot, nil, "committed failure omits snapshot")
    eq(created.owner.status().failure, nil, "valid committed terminal failure is not malformed")
end

do
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function() return { ok = true, present = true, snapshot = { ready = true, revision = 5 } } end
        values.advancementSession.request = function() return { ok = true, applied = true, private = {} } end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local malformed = created.owner.requestAdvancement(0, "Strength")
    eq(malformed.code, "session_request_invalid", "malformed SP session is bounded")
    eq(created.owner.status().failure.code, "sp_advancement_invalid", "malformed SP session poisons lifecycle")
end


do
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function() return { ok = true, present = true, snapshot = { ready = true, revision = 6 } } end
        values.advancementSession.request = function() error("session boom") end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local result = created.owner.requestAdvancement(0, "Strength")
    eq(result.code, "session_request_threw", "thrown SP session is bounded")
    yes(result.committed, "thrown SP session is conservatively committed")
    eq(created.owner.status().failure.code, "sp_advancement_invalid", "thrown SP session poisons lifecycle")
end

do
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function() return { ok = true, present = true, snapshot = { ready = true, revision = 8 } } end
        values.localClient.acceptLocal = function(_, snapshot)
            if rawget(snapshot, "revision") == 9 then return { ok = false, code = "snapshot_invalid", detail = "snapshot" } end
            return { ok = true, accepted = true }
        end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local result = created.owner.requestAdvancement(0, "Strength")
    eq(result.code, "snapshot_rejected", "SP snapshot acceptance failure is terminal")
    yes(result.committed, "applied result remains committed after acceptance failure")
    eq(result.snapshot, nil, "snapshot acceptance failure omits snapshot")
    eq(created.owner.status().failure.code, "snapshot_invalid", "snapshot acceptance failure poisons lifecycle")
end

do
    local readyCalls, sessionCalls = 0, 0
    local first, replacement, afterFailure = {}, {}, {}
    local created, f = fixture(false, false, function(values)
        values.modules.Build42RuntimeFactory.create = function() error("factory failed") end
        values.session.ready = function() readyCalls = readyCalls + 1; return { ok = true, snapshot = {} } end
        values.advancementSession.request = function() sessionCalls = sessionCalls + 1; return { ok = false } end
    end)
    created.owner.install()
    f.events.OnCreatePlayer.fire(0, first)
    f.events.OnCreatePlayer.fire(0, replacement)
    f.events.OnGameStart.fire()
    f.events.OnCreatePlayer.fire(0, afterFailure)
    f.events.OnGameStart.fire()
    eq(readyCalls, 0, "terminal SP startup failure clears queued replacement player")
    eq(sessionCalls, 0, "terminal SP startup failure never reaches advancement session")
    eq(created.owner.requestAdvancement(0, "Strength").code, "player_not_ready", "failed SP startup retains no usable player")
    eq(created.owner.status().failure.code, "runtime_factory_invalid", "SP startup failure remains terminal")
end

do
    local created, f = fixture(true, false)
    f.modules.Build42RuntimeFactory.create = function() error("mutated runtime factory") end
    f.modules.Build42OwnerTransport.createServer = function() error("mutated owner factory") end
    f.modules.Build42AdvancementTransport.createServer = function() error("mutated advancement factory") end
    created.owner.install(); f.events.OnServerStarted.fire()
    yes(created.owner.status().started, "server uses construction-captured factories")
    eq(f.serverCreates(), 1, "captured owner server factory runs")
    eq(f.advancementServerCreates(), 1, "captured advancement server factory runs")
end

do
    local created, f = fixture(false, true)
    created.owner.install(); acknowledge(f, 0, {})
    f.localClient.handle = function() error("mutated owner handle") end
    f.localClient.reset = function() error("mutated owner reset") end
    f.advancementClient.request = function() error("mutated request") end
    f.advancementClient.status = function() error("mutated status") end
    f.advancementClient.handle = function() error("mutated handle") end
    f.advancementClient.reset = function() error("mutated reset") end
    yes(created.owner.requestAdvancement(0, "Strength").ok, "captured advancement request runs")
    no(created.owner.advancementStatus(0).pending, "captured advancement status runs")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "ownerSnapshot", {})
    eq(f.calls[#f.calls][1], "client_handle", "captured owner response handler runs")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "advancementResult", {})
    eq(f.calls[#f.calls][1], "adv_handle", "captured advancement response handler runs")
    f.events.OnDisconnect.fire()
    eq(f.calls[#f.calls - 2][1], "client_reset", "captured owner reset runs")
    eq(f.calls[#f.calls - 1][1], "adv_reset", "captured advancement reset runs")
    eq(f.calls[#f.calls][1], "admin_reset", "captured admin reset runs")
    eq(created.owner.status().failure, nil, "captured client endpoint callables remain valid")
end

do
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function() return { ok = true, present = true, snapshot = { ready = true, revision = 10 } } end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    f.advancementSession.request = function() error("mutated SP request") end
    local result = created.owner.requestAdvancement(0, "Strength")
    yes(result.ok, "SP uses startup-captured advancement request")
    eq(f.calls[#f.calls - 1][1], "session_request", "captured SP session request executed")
end

do
    local created, f = fixture(false, true)
    local notices = {}
    yes(created.owner.setClientStateListener(function(slot, kind)
        notices[#notices + 1] = { slot, kind }
    end).ok, "client listener installs")
    yes(created.owner.install().ok, "client refresh hooks install")
    local player = {}
    acknowledge(f, 2, player)
    local before = #f.calls
    for index = 1, 200 do
        created.owner.clientState(2)
        created.owner.advancementStatus(2)
        f.events.OnServerCommand.fire("Other", "ignored", {})
    end
    eq(#f.calls, before, "views and unrelated callbacks do not refresh")
    yes(created.owner.refreshOwner(2).ok, "multiplayer refresh delegates")
    eq(f.calls[#f.calls][1], "client_refresh", "multiplayer refresh uses owner client")
    eq(f.calls[#f.calls][2], 2, "multiplayer refresh preserves slot")
    eq(f.calls[#f.calls][3], player, "multiplayer refresh preserves player identity")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "ownerSnapshot", {})
    eq(#notices, 1, "accepted owner response emits one notice")
    eq(notices[#notices][1], 0, "accepted owner response supplies transport slot")
    eq(notices[#notices][2], "owner_snapshot", "accepted owner response notifies once")
    yes(created.owner.requestAdvancement(2, "Strength").ok, "requested AP route coexists with refresh")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "advancementResult", {})
    eq(#notices, 2, "terminal advancement response emits one notice")
    eq(notices[#notices][2], "advancement_terminal", "terminal advancement response notifies once")
    local replacementNotices = 0
    yes(created.owner.setClientStateListener(function()
        replacementNotices = replacementNotices + 1
    end).ok, "client listener replaces prior sink")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "ownerSnapshot", {})
    eq(#notices, 2, "replaced listener does not retain prior sink")
    eq(replacementNotices, 1, "replacement listener receives owner notice")
    yes(created.owner.setClientStateListener(nil).ok, "client listener clears")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "advancementResult", {})
    eq(replacementNotices, 1, "cleared listener receives no terminal notice")
    no(created.owner.setClientStateListener({}).ok, "nonfunction listener is rejected")
end

do
    local created, f = fixture(false, false)
    local notices = 0
    yes(created.owner.setClientStateListener(function()
        notices = notices + 1
        error("listener boom")
    end).ok, "throwing listener installs")
    yes(created.owner.install().ok, "SP refresh hooks install")
    local player = {}
    f.events.OnGameStart.fire()
    f.events.OnCreatePlayer.fire(1, player)
    eq(notices, 1, "SP ready notifies accepted owner snapshot")
    local before = #f.calls
    yes(created.owner.refreshOwner(1).ok, "SP refresh succeeds")
    eq(f.calls[before + 1][1], "snapshot", "SP refresh calls session snapshot once")
    eq(f.calls[before + 1][2], player, "SP refresh keeps exact ready player")
    eq(f.calls[before + 2][1], "client_accept", "SP refresh uses existing local inbox")
    eq(notices, 2, "listener throw is contained without retry")
    eq(created.owner.status().failure, nil, "listener throw does not retain lifecycle failure")
    no(created.owner.refreshOwner(4).ok, "invalid refresh slot is bounded")
end

do
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function()
            return { ok = true, present = true, snapshot = { ready = true, revision = 7 } }
        end
    end)
    local terminalNotices = {}
    created.owner.setClientStateListener(function(slot, kind)
        terminalNotices[#terminalNotices + 1] = { slot, kind }
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local result = created.owner.requestAdvancement(0, "Strength")
    yes(result.ok and result.applied, "SP terminal request succeeds")
    eq(terminalNotices[#terminalNotices][1], 0, "SP terminal listener keeps slot")
    eq(terminalNotices[#terminalNotices][2], "advancement_terminal", "SP terminal request notifies after storage")
end

do
    local created, f = fixture(false, true, function(values)
        values.localClient.refresh = function()
            return { ok = false, code = "not_bound", detail = "player route" }
        end
    end)
    created.owner.install(); acknowledge(f, 0, {})
    local unbound = created.owner.refreshOwner(0)
    eq(unbound.code, "not_bound", "valid unbound refresh is returned")
    eq(created.owner.status().failure, nil, "valid unbound refresh does not poison lifecycle")
end

do
    local created, f = fixture(true, false)
    local capturedUsernameLookup = f.globals.getPlayerFromUsername
    yes(created.owner.install().ok, "admin server installs existing events")
    f.globals.getPlayerFromUsername = function() error("replacement username lookup") end
    f.events.OnServerStarted.fire()
    eq(f.adminBoundaryCreates(), 1, "one admin boundary after startup")
    eq(f.adminServerCreates(), 1, "one admin server after boundary")
    eq(f.adminClientCreates(), 0, "server creates no admin client")
    eq(f.calls[7][1], "create_admin_boundary", "admin boundary follows existing server endpoints")
    eq(f.calls[8][1], "create_admin_server", "admin server follows boundary")
    local boundary = f.calls[7][2]
    eq(boundary.Capability, f.globals.Capability, "boundary gets captured capability")
    eq(boundary.getPlayerByOnlineID, f.globals.getPlayerByOnlineID, "boundary gets captured lookup")
    eq(boundary.getPlayerFromUsername, capturedUsernameLookup,
        "boundary gets captured username lookup")
    local server = f.calls[8][2]
    eq(server.adminBoundary, f.adminBoundary, "admin server gets exact boundary")
    eq(server.adminSession, f.adminSession, "admin server gets composed admin session")
    eq(server.ownerPublisher, f.serverTransport, "admin server gets exact owner publisher")
    eq(server.sendServerCommand, f.globals.sendServerCommand, "admin server gets captured sender")
    local actor, args = {}, {}
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "adminRequest", actor, args)
    eq(f.calls[#f.calls][1], "admin_server_handle", "admin command exact-dispatched")
    eq(f.calls[#f.calls][4], actor, "admin dispatch preserves callback actor")
    eq(f.calls[#f.calls][5], args, "admin dispatch preserves callback args")
    local before = #f.calls
    f.events.OnClientCommand.fire("Other", "adminRequest", actor, args)
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "other", actor, args)
    eq(#f.calls, before, "foreign and unknown admin traffic ignored")
    eq(created.owner.requestAdmin(0, {}).code, "admin_unavailable", "server admin request unavailable")
    eq(created.owner.adminStatus(0).code, "admin_unavailable", "server admin status unavailable")
end

do
    local created, f = fixture(true, false, function(values)
        values.adminServer.handle = function()
            return { ok = false, code = "invalid_request", detail = "request", committed = false }
        end
    end)
    created.owner.install(); f.events.OnServerStarted.fire()
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "adminRequest", {}, {})
    eq(created.owner.status().failure, nil, "ordinary admin request rejection is contained")

    created, f = fixture(true, false, function(values)
        values.adminServer.handle = function() return { ok = true, handled = true, private = true } end
    end)
    created.owner.install(); f.events.OnServerStarted.fire()
    f.events.OnClientCommand.fire("SurvivorLevelingAdvancement", "adminRequest", {}, {})
    eq(created.owner.status().failure.code, "admin_server_handle_invalid", "malformed admin endpoint retained")
end

do
    local audit, writerCalls = nil, {}
    local created, f = fixture(true, false, function(values)
        values.modules.Build42AdminTransport.createServer = function(argument)
            audit = argument.audit
            return { ok = true, server = values.adminServer }
        end
        values.globals.writeLog = function(name, line) writerCalls[#writerCalls + 1] = { name, line } end
    end)
    created.owner.install(); f.events.OnServerStarted.fire()
    local actor = { getUsername = function() return "Jos" .. string.char(195) .. string.char(169) end }
    local target = { onlineId = 77, username = "T" .. string.char(195) .. string.char(169) .. "st" }
    yes(audit.record(actor, target, "awardSurvivorXp", "committed").ok, "audit accepts exact committed call")
    eq(#writerCalls, 1, "audit writes once")
    eq(writerCalls[1][1], "admin", "audit uses admin logger")
    eq(writerCalls[1][2], "SLA admin actor=" .. actor:getUsername() .. " operation=awardSurvivorXp target="
        .. target.username .. " onlineId=77", "audit line is exact and bounded")
    yes(audit.record(actor, target, "clearAdvancementSlots", "committed").ok,
        "audit accepts clear slots mutation")
    eq(writerCalls[2][2], "SLA admin actor=" .. actor:getUsername()
        .. " operation=clearAdvancementSlots target=" .. target.username .. " onlineId=77",
        "clear slots audit line is exact")
    no(audit.record({ getUsername = function() return "bad\nname" end }, target, "awardSurvivorXp", "committed").ok,
        "audit rejects actor C0")
    no(audit.record({ getUsername = function() return "bad" .. string.char(127) end }, target, "awardSurvivorXp", "committed").ok,
        "audit rejects actor DEL")
    no(audit.record(actor, { onlineId = 77, username = "bad\nname" }, "awardSurvivorXp", "committed").ok,
        "audit rejects target C0")
    no(audit.record(actor, { onlineId = 77, username = "bad" .. string.char(127) }, "awardSurvivorXp", "committed").ok,
        "audit rejects target DEL")
    no(audit.record(actor, target, "inspect", "committed").ok, "audit rejects nonmutation")
    no(audit.record(actor, target, "awardSurvivorXp", "other").ok, "audit rejects noncommitted outcome")
    no(audit.record(actor, target, "awardSurvivorXp", "committed", { amount = 125, summary = {} }).ok,
        "audit rejects payload argument")
    eq(#writerCalls, 2, "rejected audit calls do not log or leak payload")
    local failedAudit = nil
    created, f = fixture(true, false, function(values)
        values.modules.Build42AdminTransport.createServer = function(argument)
            failedAudit = argument.audit
            return { ok = true, server = values.adminServer }
        end
        values.globals.writeLog = function() error("writer boom") end
    end)
    created.owner.install(); f.events.OnServerStarted.fire()
    no(failedAudit.record(actor, target, "awardSurvivorLevels", "committed").ok, "captured audit writer failure is bounded")
end

do
    local created, f = fixture(false, true)
    eq(f.adminClientCreates(), 1, "multiplayer creates one admin client")
    yes(created.owner.install().ok, "admin client installs existing events")
    local players = { {}, {}, {}, {} }
    for slot = 0, 3 do
        acknowledge(f, slot, players[slot + 1])
        local request = { operation = "inspect", target = { username = "Target" } }
        local result = created.owner.requestAdmin(slot, request)
        yes(result.ok, "admin request delegates slot " .. slot)
        eq(f.calls[#f.calls][1], "admin_request", "admin request invoked once " .. slot)
        eq(f.calls[#f.calls][2], slot, "admin request keeps slot " .. slot)
        eq(f.calls[#f.calls][3], players[slot + 1], "admin request keeps actor identity " .. slot)
        eq(f.calls[#f.calls][4], request, "admin request preserves username-only logical shape " .. slot)
    end
    local before = #f.calls
    f.events.OnServerCommand.fire("Other", "adminResult", {})
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "other", {})
    eq(#f.calls, before, "foreign admin results ignored")
    local notices = {}
    created.owner.setClientStateListener(function(slot, kind) notices[#notices + 1] = { slot, kind } end)
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "adminResult", {})
    eq(f.calls[#f.calls][1], "admin_handle", "admin result exact-dispatched")
    eq(notices[#notices][1], 0, "admin terminal keeps transport slot")
    eq(notices[#notices][2], "admin_terminal", "admin terminal notifies listener")
end

do
    local statusSource = {
        ok = true, pending = false, result = {
            ok = true, requestId = "admin:3", operation = "awardSurvivorXp", target = { onlineId = 8, username = "Target" },
            outcome = "rejected", code = "stale_revision", detail = "revision",
            summary = { accountingMode = "Tracked", revision = 9, level = 5, xpIntoLevel = 2, xpForNextLevel = 100, spent = 2, availableAp = 3 },
        },
    }
    local created, f = fixture(false, true, function(values)
        values.adminClient.status = function() return statusSource end
        values.adminClient.request = function() return { ok = false, code = "invalid_request", detail = "request" } end
    end)
    created.owner.install(); acknowledge(f, 0, {})
    eq(created.owner.requestAdmin(0, {}).code, "invalid_request", "valid admin client rejection is returned")
    eq(created.owner.status().failure, nil, "valid admin rejection does not poison lifecycle")
    local view = created.owner.adminStatus(0)
    eq(view.result.code, "stale_revision", "admin status delegates terminal")
    no(view.result == statusSource.result, "admin terminal status is detached")
    view.result.target.username = "mutated"
    eq(created.owner.adminStatus(0).result.target.username, "Target", "admin status detachment is stable")
end

do
    local username = "T" .. string.char(195) .. string.char(169) .. "st"
    local statusSource = {
        ok = true, pending = true, requestId = "admin:inspect", operation = "inspect",
        target = { username = username },
    }
    local created, f = fixture(false, true, function(values)
        values.adminClient.status = function() return statusSource end
    end)
    created.owner.install(); acknowledge(f, 0, {})
    local pending = created.owner.adminStatus(0)
    exactKeys(pending, {
        ok = true, pending = true, requestId = true, operation = true, target = true,
    }, 5, "username-only inspect pending status")
    exactKeys(pending.target, { username = true }, 1, "username-only pending target")
    eq(pending.target.username, username, "pending UTF-8 username preserved")
    no(pending.target == statusSource.target, "pending inspect target detached")

    statusSource = {
        ok = true, pending = false, result = {
            ok = true, requestId = "admin:inspect", operation = "inspect",
            target = { onlineId = 44, username = username }, outcome = "inspected",
            summary = { accountingMode = "Tracked", revision = 1, level = 1,
                xpIntoLevel = 0, xpForNextLevel = 100, spent = 0, availableAp = 1 },
        },
    }
    local inspected = created.owner.adminStatus(0)
    eq(inspected.result.target.onlineId, 44, "inspect success preserves canonical online ID")
    eq(inspected.result.target.username, username, "inspect success preserves canonical username")

    statusSource = {
        ok = true, pending = false, result = {
            ok = false, requestId = "admin:inspect", operation = "inspect",
            target = { username = username }, code = "request_denied",
            detail = "unavailable", committed = false,
        },
    }
    local denied = created.owner.adminStatus(0)
    exactKeys(denied.result.target, { username = true }, 1, "inspect failure username target")
    no(denied.result.committed, "inspect failure remains uncommitted")

    statusSource.result.committed = true
    eq(created.owner.adminStatus(0).code, "admin_status_invalid",
        "committed inspect failure is rejected")
    statusSource.result.committed = false
    statusSource.result.target.onlineId = 44
    eq(created.owner.adminStatus(0).code, "admin_status_invalid",
        "pair-shaped inspect failure is rejected")

    statusSource = {
        ok = true, pending = false, result = {
            ok = false, requestId = "admin:mutation", operation = "awardSurvivorXp",
            target = { onlineId = 44, username = username }, code = "publication_failed",
            detail = "publication", committed = true,
        },
    }
    local committedMutation = created.owner.adminStatus(0)
    yes(committedMutation.result.committed,
        "committed mutation failure remains valid")

    statusSource = {
        ok = true, pending = false, result = {
            ok = true, requestId = "admin:clear", operation = "clearAdvancementSlots",
            target = { onlineId = 44, username = username }, outcome = "applied",
            levelsGained = 0, apGained = 0,
            summary = { accountingMode = "Tracked", revision = 2, level = 1,
                xpIntoLevel = 0, xpForNextLevel = 100, spent = 0, availableAp = 1 },
        },
    }
    local clearTerminal = created.owner.adminStatus(0)
    eq(clearTerminal.result.operation, "clearAdvancementSlots", "MP clear terminal accepted")
    eq(clearTerminal.result.levelsGained, 0, "MP clear terminal preserves zero gains")
    statusSource.result.levelsGained, statusSource.result.apGained = 1, 1
    eq(created.owner.adminStatus(0).code, "admin_status_invalid",
        "MP clear terminal rejects nonzero gains")
end

do
    local resetOwner, resetAdvancement, resetAdmin = 0, 0, 0
    local created, f = fixture(false, true, function(values)
        values.localClient.reset = function() resetOwner = resetOwner + 1; error("owner reset") end
        values.advancementClient.reset = function() resetAdvancement = resetAdvancement + 1; return { ok = true } end
        values.adminClient.reset = function() resetAdmin = resetAdmin + 1; return { ok = true } end
    end)
    created.owner.install(); acknowledge(f, 1, {})
    f.events.OnDisconnect.fire()
    eq(resetOwner, 1, "disconnect attempts owner reset before failures")
    eq(resetAdvancement, 1, "disconnect continues advancement reset")
    eq(resetAdmin, 1, "disconnect continues admin reset")
    eq(created.owner.requestAdmin(1, {}).code, "player_not_ready", "disconnect clears admin player route")

    created, f = fixture(false, false)
    eq(created.owner.requestAdmin(0, {}).code, "player_not_ready", "SP admin requires retained player")
    no(created.owner.adminStatus(0).pending, "SP admin status is synchronously nonpending")
    eq(f.adminClientCreates(), 0, "SP creates no admin client")
end

do
    local created = fixture(false, false, function(values)
        values.globals.isDebugEnabled = nil
    end)
    no(created.ok, "SP construction requires debug capability")
    eq(created.code, "invalid_dependencies", "missing SP debug capability is bounded")

    created = fixture(true, false, function(values) values.globals.isDebugEnabled = nil end)
    yes(created.ok, "server construction does not require debug capability")
    created = fixture(false, true, function(values) values.globals.isDebugEnabled = nil end)
    yes(created.ok, "multiplayer construction does not require debug capability")
end

do
    local player = {}
    local created, f = fixture(false, false, function(values)
        values.localClient.get = function()
            return { ok = true, present = true, snapshot = { ready = true, revision = 1 } }
        end
    end)
    eq(f.debugCalls(), 0, "SP construction does not call debug capability")
    created.owner.install()
    f.events.OnGameStart.fire()
    f.events.OnCreatePlayer.fire(0, player)
    eq(f.debugCalls(), 0, "SP startup and readiness do not call debug capability")
    created.owner.refreshOwner(0)
    created.owner.requestAdvancement(0, "Strength")
    created.owner.advancementStatus(0)
    eq(f.debugCalls(), 0, "SP refresh and advancement do not call debug capability")
end

do
    local inspectCalls = 0
    local falseDebugCalls = 0
    local created, f = fixture(false, false, function(values)
        values.globals.isDebugEnabled = function() falseDebugCalls = falseDebugCalls + 1; return false end
        values.adminSession.inspect = function() inspectCalls = inspectCalls + 1; return { ok = true } end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local unavailable = created.owner.requestAdmin(0, { operation = "inspect" })
    eq(unavailable.code, "admin_unavailable", "debug false disables SP admin request")
    eq(created.owner.status().failure, nil, "debug false does not retain lifecycle failure")
    unavailable = created.owner.adminStatus(0)
    eq(unavailable.code, "admin_unavailable", "debug false hides SP admin status")
    eq(falseDebugCalls, 2, "debug false is checked exactly once per request and status")
    eq(inspectCalls, 0, "debug false calls no admin session")

    local debugCalls = 0
    created, f = fixture(false, false, function(values)
        values.globals.isDebugEnabled = function()
            debugCalls = debugCalls + 1
            error("debug boom")
        end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    eq(created.owner.requestAdmin(0, { operation = "inspect" }).code,
        "debug_capability_invalid", "throwing debug request is bounded")
    eq(debugCalls, 1, "request checks throwing debug exactly once")
    eq(created.owner.status().failure.code, "debug_capability_invalid", "throwing debug failure retained")
    eq(created.owner.adminStatus(0).code, "debug_capability_invalid", "throwing debug status is bounded")
    eq(debugCalls, 2, "status checks throwing debug exactly once")

    debugCalls = 0
    created, f = fixture(false, false, function(values)
        values.globals.isDebugEnabled = function() debugCalls = debugCalls + 1; return "true" end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    eq(created.owner.requestAdmin(0, { operation = "inspect" }).code,
        "debug_capability_invalid", "nonboolean debug request is bounded")
    eq(debugCalls, 1, "nonboolean debug checked exactly once")

    local capturedCalls, replacementCalls = 0, 0
    created, f = fixture(false, false, function(values)
        values.globals.isDebugEnabled = function() capturedCalls = capturedCalls + 1; return true end
    end)
    f.globals.isDebugEnabled = function() replacementCalls = replacementCalls + 1; return false end
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    yes(created.owner.requestAdmin(0, { operation = "inspect" }).ok,
        "SP admin uses construction-captured debug capability")
    eq(capturedCalls, 1, "captured debug capability called once")
    eq(replacementCalls, 0, "replacement debug capability unused")
end

do
    local created, f = fixture(false, false, function(values)
        values.adminSession.inspect = function()
            return { ok = true, summary = {
                accountingMode = "Tracked", revision = 0, level = 0, xpIntoLevel = 0,
                xpForNextLevel = 100, spent = 0, availableAp = 0,
            }, private = true }
        end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local malformed = created.owner.requestAdmin(0, { operation = "inspect" })
    no(malformed.ok, "malformed SP inspect result fails closed")
    no(malformed.committed, "malformed SP inspect cannot be committed")
    eq(malformed.code, "session_result_invalid", "malformed SP inspect is bounded")
    eq(created.owner.status().failure.code, "sp_admin_session_invalid", "malformed SP inspect retained")

    created, f = fixture(false, false, function(values)
        values.adminSession.request = function() error("admin request boom") end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local thrown = created.owner.requestAdmin(0, {
        operation = "awardSurvivorXp", expectedRevision = 0, amount = 1,
    })
    no(thrown.ok, "throwing SP mutation fails closed")
    yes(thrown.committed, "throwing SP mutation conservatively reports committed")
    eq(thrown.code, "session_call_threw", "throwing SP mutation is bounded")
end

do
    local sessionCalls = 0
    local created, f = fixture(false, false, function(values)
        values.adminSession.inspect = function() sessionCalls = sessionCalls + 1; return { ok = true } end
        values.adminSession.request = function() sessionCalls = sessionCalls + 1; return { ok = true } end
    end)
    created.owner.install(); f.events.OnGameStart.fire()
    eq(created.owner.requestAdmin(4, { operation = "inspect" }).code, "invalid_slot", "SP admin rejects invalid slot")
    eq(created.owner.requestAdmin(0, { operation = "inspect" }).code, "player_not_ready", "SP admin rejects unready player")
    local player = {}
    f.events.OnCreatePlayer.fire(0, player)
    local invalidRequests = {
        {},
        { operation = "unknown" },
        { operation = "inspect", target = {} },
        { operation = "inspect", expectedRevision = 0 },
        { operation = "awardSurvivorXp", expectedRevision = 0 },
        { operation = "awardSurvivorXp", expectedRevision = -1, amount = 1 },
        { operation = "awardSurvivorXp", expectedRevision = 0, amount = 0 },
        { operation = "awardSurvivorXp", expectedRevision = 0, amount = math.huge },
        { operation = "awardSurvivorXp", expectedRevision = 0, amount = 1, requestId = "fake" },
        { operation = "awardSurvivorLevels", expectedRevision = 0, count = 0 },
        { operation = "awardSurvivorLevels", expectedRevision = 0, count = 1.5 },
        { operation = "awardSurvivorLevels", expectedRevision = 0, count = 9007199254740992 },
        { operation = "awardSurvivorLevels", expectedRevision = 0, count = 1, onlineId = 3 },
        { operation = "clearAdvancementSlots" },
        { operation = "clearAdvancementSlots", expectedRevision = -1 },
        { operation = "clearAdvancementSlots", expectedRevision = 0, count = 1 },
        { operation = "advancePerkNormally", expectedRevision = 0 },
        { operation = "resetAccounting", expectedRevision = 0 },
        { operation = "setAccounting", expectedRevision = 0 },
        setmetatable({ operation = "inspect" }, {}),
    }
    eq(created.owner.requestAdmin(0, nil).code, "invalid_request", "SP admin rejects nil request")
    for index = 1, #invalidRequests do
        eq(created.owner.requestAdmin(0, invalidRequests[index]).code,
            "invalid_request", "SP admin rejects hostile request " .. index)
    end
    eq(sessionCalls, 0, "invalid SP admin paths call no admin session")
end

do
    local player = {}
    local inspectCalls, snapshotCalls, sendCalls, logCalls = 0, 0, 0, 0
    local notices = {}
    local sessionSummary = {
        accountingMode = "Tracked", revision = 3, level = 2, xpIntoLevel = 25,
        xpForNextLevel = 100, spent = 1, availableAp = 1,
    }
    local created, f = fixture(false, false, function(values)
        values.globals.sendClientCommand = function() sendCalls = sendCalls + 1 end
        values.globals.writeLog = function() logCalls = logCalls + 1 end
        values.adminSession.inspect = function(target)
            inspectCalls = inspectCalls + 1
            eq(target, player, "SP inspect receives exact retained player")
            return { ok = true, summary = sessionSummary }
        end
        values.session.snapshot = function() snapshotCalls = snapshotCalls + 1; return { ok = true, snapshot = {} } end
    end)
    created.owner.setClientStateListener(function(slot, kind) notices[#notices + 1] = { slot, kind } end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(2, player)
    f.adminSession.inspect = function() error("mutated admin inspect") end
    local terminal = created.owner.requestAdmin(2, { operation = "inspect" })
    yes(terminal.ok, "SP inspect succeeds")
    eq(terminal.operation, "inspect", "SP inspect terminal operation")
    eq(terminal.outcome, "inspected", "SP inspect terminal outcome")
    exactKeys(terminal, { ok = true, operation = true, outcome = true, summary = true }, 4, "SP inspect terminal")
    eq(inspectCalls, 1, "SP inspect session called once")
    eq(snapshotCalls, 0, "SP inspect does not refresh owner snapshot")
    eq(sendCalls, 0, "SP inspect sends no command")
    eq(logCalls, 0, "SP inspect writes no audit log")
    eq(f.adminClientCreates(), 0, "SP inspect creates no admin client")
    eq(f.adminBoundaryCreates(), 0, "SP inspect creates no admin boundary")
    eq(terminal.requestId, nil, "SP inspect has no request ID")
    eq(terminal.target, nil, "SP inspect has no synthetic target")
    local status = created.owner.adminStatus(2)
    no(status.pending, "SP inspect status is nonpending")
    exactKeys(status, { ok = true, pending = true, result = true }, 3, "SP inspect status")
    no(status.result == terminal, "SP inspect status terminal detached")
    no(status.result.summary == terminal.summary, "SP inspect status summary detached")
    terminal.summary.level = 99
    eq(created.owner.adminStatus(2).result.summary.level, 2, "stored SP inspect terminal remains detached")
    eq(notices[#notices][1], 2, "SP inspect terminal notice preserves slot")
    eq(notices[#notices][2], "admin_terminal", "SP inspect terminal notice kind")
end

do
    local player, acceptedSnapshot = {}, nil
    local requestCalls, snapshotCalls, acceptCalls = 0, 0, 0
    local notices = {}
    local created, f = fixture(false, false, function(values)
        values.adminSession.request = function(target, request)
            requestCalls = requestCalls + 1
            eq(target, player, "SP clear receives exact retained player")
            exactKeys(request, { kind = true, expectedRevision = true }, 2,
                "converted clear request")
            eq(request.kind, "clearAdvancementSlots", "converted clear kind")
            eq(request.expectedRevision, 9, "converted clear revision")
            return {
                ok = true, applied = true, kind = request.kind,
                levelsGained = 0, apGained = 0,
                summary = { accountingMode = "Tracked", revision = 10, level = 8,
                    xpIntoLevel = 20, xpForNextLevel = 200, spent = 2, availableAp = 6 },
            }
        end
        values.session.snapshot = function(target)
            snapshotCalls = snapshotCalls + 1
            eq(target, player, "post-clear snapshot receives exact player")
            return { ok = true, snapshot = { marker = "clear" } }
        end
        values.localClient.acceptLocal = function(slot, snapshot)
            if snapshot.marker == "clear" then
                acceptCalls = acceptCalls + 1
                eq(slot, 3, "post-clear acceptance preserves slot")
                acceptedSnapshot = snapshot
            end
            return { ok = true, accepted = true }
        end
    end)
    created.owner.setClientStateListener(function(slot, kind)
        notices[#notices + 1] = { slot, kind }
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(3, player)
    local terminal = created.owner.requestAdmin(3, {
        operation = "clearAdvancementSlots", expectedRevision = 9,
    })
    yes(terminal.ok, "SP clear mutation succeeds")
    eq(terminal.operation, "clearAdvancementSlots", "SP clear terminal operation")
    eq(terminal.outcome, "applied", "SP clear terminal applied")
    eq(terminal.levelsGained, 0, "SP clear reports zero level gain")
    eq(terminal.apGained, 0, "SP clear reports zero AP gain")
    eq(requestCalls, 1, "SP clear session called once")
    eq(snapshotCalls, 1, "SP clear projects owner snapshot once")
    eq(acceptCalls, 1, "SP clear accepts owner snapshot once")
    eq(acceptedSnapshot.marker, "clear", "SP clear accepts exact projected snapshot")
    eq(notices[#notices - 1][2], "owner_snapshot",
        "SP clear owner snapshot notice precedes terminal")
    eq(notices[#notices][2], "admin_terminal", "SP clear emits terminal notice")
end

do
    local player, acceptedSnapshot = {}, nil
    local requestCalls, snapshotCalls, acceptCalls = 0, 0, 0
    local notices = {}
    local created, f = fixture(false, false, function(values)
        values.adminSession.request = function(target, request)
            requestCalls = requestCalls + 1
            eq(target, player, "SP XP request receives exact player")
            exactKeys(request, { kind = true, expectedRevision = true, amount = true }, 3, "converted XP request")
            eq(request.kind, "awardSurvivorXp", "converted XP kind")
            eq(request.expectedRevision, 7, "converted XP revision")
            eq(request.amount, 125.5, "converted XP amount")
            return {
                ok = true, applied = true, kind = request.kind, amount = request.amount,
                levelsGained = 2, apGained = 2,
                summary = { accountingMode = "Tracked", revision = 8, level = 4,
                    xpIntoLevel = 5, xpForNextLevel = 100, spent = 1, availableAp = 3 },
            }
        end
        values.session.snapshot = function(target)
            snapshotCalls = snapshotCalls + 1
            eq(target, player, "post-admin snapshot receives exact player")
            return { ok = true, snapshot = { marker = "admin" } }
        end
        values.localClient.acceptLocal = function(slot, snapshot)
            if snapshot.marker == "admin" then
                acceptCalls = acceptCalls + 1
                eq(slot, 1, "post-admin acceptance preserves slot")
                acceptedSnapshot = snapshot
            end
            return { ok = true, accepted = true }
        end
    end)
    created.owner.setClientStateListener(function(slot, kind) notices[#notices + 1] = { slot, kind } end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(1, player)
    local terminal = created.owner.requestAdmin(1, {
        operation = "awardSurvivorXp", expectedRevision = 7, amount = 125.5,
    })
    yes(terminal.ok, "SP XP mutation succeeds")
    eq(terminal.outcome, "applied", "SP XP terminal applied")
    eq(terminal.levelsGained, 2, "SP XP levels gained")
    eq(terminal.apGained, 2, "SP XP AP gained")
    exactKeys(terminal, {
        ok = true, operation = true, outcome = true, levelsGained = true,
        apGained = true, summary = true,
    }, 6, "SP XP terminal")
    eq(requestCalls, 1, "SP XP session called once")
    eq(snapshotCalls, 1, "SP XP projects owner snapshot once")
    eq(acceptCalls, 1, "SP XP accepts owner snapshot once")
    eq(acceptedSnapshot.marker, "admin", "SP XP accepts exact projected snapshot")
    eq(notices[#notices - 1][2], "owner_snapshot", "SP XP owner snapshot notice precedes terminal")
    eq(notices[#notices][2], "admin_terminal", "SP XP emits terminal notice")
end

do
    local player = {}
    local snapshotCalls = 0
    local created, f = fixture(false, false, function(values)
        values.adminSession.request = function(target, request)
            eq(target, player, "SP level request receives exact player")
            exactKeys(request, { kind = true, expectedRevision = true, count = true }, 3, "converted level request")
            return {
                ok = true, applied = true, kind = request.kind, count = request.count,
                levelsGained = request.count, apGained = request.count,
                summary = { accountingMode = "Free", revision = 10, level = 8,
                    xpIntoLevel = 20, xpForNextLevel = 200, spent = 0, availableAp = 8 },
            }
        end
        values.session.snapshot = function() snapshotCalls = snapshotCalls + 1; return { ok = true, snapshot = {} } end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(3, player)
    local terminal = created.owner.requestAdmin(3, {
        operation = "awardSurvivorLevels", expectedRevision = 9, count = 3,
    })
    yes(terminal.ok, "SP level mutation succeeds")
    eq(terminal.operation, "awardSurvivorLevels", "SP level terminal operation")
    eq(terminal.levelsGained, 3, "SP level gains preserved")
    eq(snapshotCalls, 1, "SP level mutation refreshes once")
end

do
    local snapshotCalls = 0
    local failNext = false
    local created, f = fixture(false, false, function(values)
        values.adminSession.request = function(_, request)
            if failNext then
                return { ok = false, code = "store_save_failed", detail = "store.save failed", committed = false }
            end
            return {
                ok = true, applied = false, kind = request.kind,
                code = "stale_revision", detail = "revision",
                summary = { accountingMode = "Tracked", revision = 5, level = 2,
                    xpIntoLevel = 1, xpForNextLevel = 100, spent = 1, availableAp = 1 },
            }
        end
        values.session.snapshot = function() snapshotCalls = snapshotCalls + 1; return { ok = true, snapshot = {} } end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local stale = created.owner.requestAdmin(0, {
        operation = "awardSurvivorXp", expectedRevision = 4, amount = 1,
    })
    yes(stale.ok, "SP stale revision is handled")
    eq(stale.outcome, "rejected", "SP stale terminal rejected")
    eq(stale.code, "stale_revision", "SP stale code preserved")
    eq(snapshotCalls, 0, "SP stale mutation does not refresh owner")

    failNext = true
    local failed = created.owner.requestAdmin(0, {
        operation = "awardSurvivorLevels", expectedRevision = 5, count = 1,
    })
    no(failed.ok, "SP precommit failure returned")
    no(failed.committed, "SP precommit failure preserves committed false")
    eq(failed.code, "store_save_failed", "SP precommit code preserved")
    eq(snapshotCalls, 0, "SP precommit failure does not refresh owner")
    eq(created.owner.status().failure, nil, "valid SP session rejection does not poison lifecycle")
end

do
    local function invariantSummary(revision, level)
        return {
            accountingMode = "Tracked", revision = revision, level = level,
            xpIntoLevel = 0, xpForNextLevel = 100, spent = 0, availableAp = level,
        }
    end
    local cases = {
        {
            label = "zero level gains",
            request = { operation = "awardSurvivorLevels", expectedRevision = 4, count = 2 },
            result = { ok = true, applied = true, kind = "awardSurvivorLevels", count = 2,
                levelsGained = 0, apGained = 0, summary = invariantSummary(5, 6) },
        },
        {
            label = "wrong level gains",
            request = { operation = "awardSurvivorLevels", expectedRevision = 4, count = 2 },
            result = { ok = true, applied = true, kind = "awardSurvivorLevels", count = 2,
                levelsGained = 1, apGained = 1, summary = invariantSummary(5, 6) },
        },
        {
            label = "unchanged applied revision",
            request = { operation = "awardSurvivorXp", expectedRevision = 4, amount = 10 },
            result = { ok = true, applied = true, kind = "awardSurvivorXp", amount = 10,
                levelsGained = 1, apGained = 1, summary = invariantSummary(4, 5) },
        },
        {
            label = "wrong applied revision",
            request = { operation = "awardSurvivorXp", expectedRevision = 4, amount = 10 },
            result = { ok = true, applied = true, kind = "awardSurvivorXp", amount = 10,
                levelsGained = 1, apGained = 1, summary = invariantSummary(6, 5) },
        },
        {
            label = "unchanged stale revision",
            request = { operation = "awardSurvivorXp", expectedRevision = 4, amount = 10 },
            result = { ok = true, applied = false, kind = "awardSurvivorXp",
                code = "stale_revision", detail = "revision", summary = invariantSummary(4, 5) },
        },
        {
            label = "gains exceed resulting level",
            request = { operation = "awardSurvivorXp", expectedRevision = 4, amount = 10 },
            result = { ok = true, applied = true, kind = "awardSurvivorXp", amount = 10,
                levelsGained = 1, apGained = 1, summary = invariantSummary(5, 0) },
        },
        {
            label = "applied maximum revision",
            request = {
                operation = "awardSurvivorXp", expectedRevision = 9007199254740991, amount = 10,
            },
            result = { ok = true, applied = true, kind = "awardSurvivorXp", amount = 10,
                levelsGained = 1, apGained = 1,
                summary = invariantSummary(9007199254740991, 5) },
        },
    }
    for index = 1, #cases do
        local item = cases[index]
        local snapshotCalls = 0
        local created, f = fixture(false, false, function(values)
            values.adminSession.request = function() return item.result end
            values.session.snapshot = function()
                snapshotCalls = snapshotCalls + 1
                return { ok = true, snapshot = {} }
            end
        end)
        created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
        local failed = created.owner.requestAdmin(0, item.request)
        no(failed.ok, item.label .. " fails closed")
        yes(failed.committed, item.label .. " conservatively reports committed")
        eq(failed.code, "session_result_invalid", item.label .. " is bounded")
        eq(snapshotCalls, 0, item.label .. " cannot refresh owner state")
    end
end

do
    local created, f = fixture(false, false, function(values)
        values.session.snapshot = function() return { ok = false, code = "project_failed", detail = "snapshot" } end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    local failed = created.owner.requestAdmin(0, {
        operation = "awardSurvivorLevels", expectedRevision = 0, count = 1,
    })
    no(failed.ok, "SP postcommit projection failure returned")
    yes(failed.committed, "SP projection failure preserves committed truth")
    eq(failed.code, "owner_snapshot_failed", "SP projection failure is bounded")
    eq(created.owner.status().failure.code, "project_failed", "SP projection failure retained")

    local acceptCalls = 0
    created, f = fixture(false, false, function(values)
        values.session.snapshot = function() return { ok = true, snapshot = { marker = "admin" } } end
        values.localClient.acceptLocal = function(_, snapshot)
            if snapshot.marker == "admin" then
                acceptCalls = acceptCalls + 1
                return { ok = true, accepted = false, code = "stale_snapshot" }
            end
            return { ok = true, accepted = true }
        end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, {})
    failed = created.owner.requestAdmin(0, {
        operation = "awardSurvivorXp", expectedRevision = 0, amount = 1,
    })
    no(failed.ok, "SP postcommit acceptance failure returned")
    yes(failed.committed, "SP acceptance failure preserves committed truth")
    eq(acceptCalls, 1, "SP failed acceptance is attempted once")
end

do
    local firstPlayer, secondPlayer = {}, {}
    local inspectIndex = 0
    local created, f = fixture(false, false, function(values)
        values.adminSession.inspect = function()
            inspectIndex = inspectIndex + 1
            return { ok = true, summary = {
                accountingMode = "Tracked", revision = inspectIndex, level = inspectIndex,
                xpIntoLevel = 0, xpForNextLevel = 100, spent = 0, availableAp = inspectIndex,
            } }
        end
    end)
    created.owner.install(); f.events.OnGameStart.fire(); f.events.OnCreatePlayer.fire(0, firstPlayer)
    local first = created.owner.requestAdmin(0, { operation = "inspect" })
    local second = created.owner.requestAdmin(0, { operation = "inspect" })
    eq(created.owner.adminStatus(0).result.summary.revision, 2, "SP stores only newest terminal per slot")
    first.summary.revision, second.summary.revision = 99, 99
    eq(created.owner.adminStatus(0).result.summary.revision, 2, "SP stored terminal detached from returns")
    f.events.OnCreatePlayer.fire(0, secondPlayer)
    local cleared = created.owner.adminStatus(0)
    no(cleared.pending, "SP re-ready status remains nonpending")
    eq(cleared.result, nil, "SP re-ready clears prior character terminal")
end

do
    local advancementResets, adminResets, readyCalls = 0, 0, 0
    local created, f = fixture(false, true, function(values)
        values.advancementClient.resetSlot = function() advancementResets = advancementResets + 1; error("advancement reset") end
        values.adminClient.resetSlot = function() adminResets = adminResets + 1; return { ok = true } end
        values.localClient.ready = function() readyCalls = readyCalls + 1; return { ok = true } end
    end)
    created.owner.install(); acknowledge(f, 2, {})
    eq(advancementResets, 1, "failed advancement reset is attempted once")
    eq(adminResets, 1, "admin reset still follows failed advancement reset")
    eq(readyCalls, 0, "failed request reset blocks owner ready")
    eq(created.owner.status().failure.code, "advancement_slot_reset_invalid", "first slot reset failure retained")
    f.events.OnMiniScoreboardUpdate.fire()
    eq(advancementResets, 1, "same observed player does not retry failed advancement reset")
    eq(adminResets, 1, "same observed player does not repeat admin reset after failure")
    eq(readyCalls, 0, "same failed observation does not retry owner readiness")

    created, f = fixture(false, true, function(values)
        values.adminClient.request = function()
            return { ok = false, code = "send_failed", detail = "sendClientCommand", committed = true }
        end
    end)
    created.owner.install(); acknowledge(f, 0, {})
    eq(created.owner.requestAdmin(0, {}).code, "admin_request_invalid", "committed client request is malformed")
    eq(created.owner.status().failure.code, "admin_request_invalid", "committed client request is retained")
end

local bootstrapEvidence = rawget(_G, "__C10T_BOOTSTRAP_EVIDENCE")
if bootstrapEvidence ~= nil then
    eq(bootstrapEvidence.phase, 18, "bootstrap harness completes every phase")
    yes(bootstrapEvidence.checks >= 75, "bootstrap harness performs exact boundary checks")
    local malformedInstall = rawget(_G, "C10TBootstrapMalformed")
    local malformedOwner = rawget(_G, "C10TBootstrapMalformedOwner")
    local extraOwner = rawget(_G, "C10TBootstrapExtraOwner")
    local indexedOwner = rawget(_G, "C10TBootstrapIndexOwner")
    eq(type(malformedInstall), "table", "bootstrap malformed install returns a result")
    eq(type(malformedOwner), "table", "bootstrap malformed owner returns a result")
    eq(type(extraOwner), "table", "bootstrap extra owner returns a result")
    eq(type(indexedOwner), "table", "bootstrap indexed owner returns a result")
    eq(malformedInstall.code, "lifecycle_install_invalid", "bootstrap malformed install is bounded")
    eq(malformedOwner.code, "lifecycle_create_invalid", "bootstrap malformed owner is bounded")
    eq(extraOwner.code, "lifecycle_sentinel_collision", "bootstrap extra owner field is collision")
    eq(indexedOwner.code, "lifecycle_sentinel_collision", "bootstrap indexed owner is collision")
end

return assertions
