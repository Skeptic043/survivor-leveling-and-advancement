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
    local callbacks, adds = {}, 0
    return {
        Add = function(callback) adds = adds + 1; callbacks[#callbacks + 1] = callback end,
        fire = function(...) for index = 1, #callbacks do callbacks[index](...) end end,
        adds = function() return adds end,
    }
end

local function fixture(server, client, configure)
    local calls = {}
    local events = { OnServerStarted = event(), OnClientCommand = event(), OnCreatePlayer = event(), OnServerCommand = event(), OnDisconnect = event(), OnGameStart = event() }
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
    local source = { install = function() calls[#calls + 1] = { "install_source" }; return { ok = true } end }
    local runtime = { catalog = {}, services = { xpSource = source, ownerSession = session, advancementSession = advancementSession } }
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
    local factoryCalls, clientCreates, serverCreates, advancementClientCreates, advancementServerCreates = 0, 0, 0, 0, 0
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
        ClientOwnerState = { create = function() end, validate = validator },
    }
    local globals = {
        Events = events,
        isServer = function() calls[#calls + 1] = { "isServer" }; return server end,
        isClient = function() calls[#calls + 1] = { "isClient" }; return client end,
        sendClientCommand = function() end,
        sendServerCommand = function() end,
    }
    if configure ~= nil then configure({ modules = modules, globals = globals, localClient = localClient, session = session, advancementSession = advancementSession, source = source, serverTransport = serverTransport, advancementClient = advancementClient, advancementServer = advancementServer }) end
    local created = Build42Lifecycle.create({ modules = modules, globals = globals })
    return created, { calls = calls, events = events, modules = modules, globals = globals, session = session, source = source, runtime = runtime, localClient = localClient, serverTransport = serverTransport,
        advancementSession = advancementSession, advancementClient = advancementClient, advancementServer = advancementServer,
        factoryCalls = function() return factoryCalls end, clientCreates = function() return clientCreates end, serverCreates = function() return serverCreates end,
        advancementClientCreates = function() return advancementClientCreates end, advancementServerCreates = function() return advancementServerCreates end, validator = validator }
end

do
    local created, f = fixture(true, false)
    yes(created.ok, "server creates")
    exactKeys(created.owner, {
        install = true, status = true, clientState = true,
        refreshOwner = true, setClientStateListener = true,
        requestAdvancement = true, advancementStatus = true,
    }, 7, "exact owner API")
    eq(f.clientCreates(), 0, "server creates no client transport")
    eq(f.factoryCalls(), 0, "server construction is inert")
    eq(f.events.OnServerStarted.adds(), 0, "server construction registers no event")
    yes(created.owner.install().ok, "server installs")
    yes(created.owner.install().ok, "server install idempotent")
    eq(f.events.OnServerStarted.adds(), 1, "one server start callback")
    eq(f.events.OnClientCommand.adds(), 1, "one client-command callback")
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
    f.events.OnCreatePlayer.fire(0, {})
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
    f.events.OnCreatePlayer.fire(2, { player = true })
    eq(f.calls[#f.calls][1], "client_ready", "client player uses supplied player")
    f.events.OnServerCommand.fire("SurvivorLevelingAdvancement", "ownerSnapshot", { ok = true })
    eq(f.calls[#f.calls][1], "client_handle", "client response delegated")
    f.events.OnDisconnect.fire()
    eq(f.calls[#f.calls - 1][1], "client_reset", "disconnect resets owner client")
    eq(f.calls[#f.calls][1], "adv_reset", "disconnect resets advancement client")
    local view, count = created.owner.clientState(0), 0
    for key in pairs(view) do count = count + 1; yes(key == "ok" or key == "present", "client state allowlist") end
    eq(count, 2, "client state delegates only its public view")
end

do
    local created, f = fixture(false, false)
    local player = {}
    yes(created.owner.install().ok, "SP installs")
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
    f.events.OnCreatePlayer.Add = function() error("ambiguous") end
    no(created.owner.install().ok, "registration throw fails")
    no(created.owner.install().ok, "registration throw is not retried")
    eq(f.events.OnServerCommand.adds(), 0, "registration stops after ambiguous add")
end

do
    local created, f = fixture(false, true)
    f.events.OnServerCommand.Add = function() error("partial add") end
    no(created.owner.install().ok, "partial event registration fails")
    no(created.owner.install().ok, "partial event registration is never retried")
    eq(f.events.OnCreatePlayer.adds(), 1, "first partial hook remains singular")
    eq(f.events.OnServerCommand.adds(), 0, "throwing partial hook is not counted")
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
        f.events.OnCreatePlayer.fire(slot, players[slot + 1])
        local requested = created.owner.requestAdvancement(slot, "Strength")
        yes(requested.ok, "client slot request " .. slot)
        eq(f.calls[#f.calls][2], slot, "request slot " .. slot)
        eq(f.calls[#f.calls][3], players[slot + 1], "request player identity " .. slot)
    end
    local replacement = {}
    f.events.OnCreatePlayer.fire(2, replacement)
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
    created.owner.install(); f.events.OnCreatePlayer.fire(1, {})
    f.events.OnDisconnect.fire()
    eq(ownerResetCalls, 1, "disconnect attempts owner reset")
    eq(advancementResetCalls, 1, "disconnect attempts advancement reset after owner failure")
    eq(created.owner.status().failure.code, "owner_reset_invalid", "first disconnect failure retained")
    eq(created.owner.requestAdvancement(1, "Strength").code, "player_not_ready", "disconnect clears retained players")
end

do
    local ownerResetCalls, advancementResetCalls = 0, 0
    local created, f = fixture(false, true, function(values)
        values.localClient.reset = function() ownerResetCalls = ownerResetCalls + 1; return { ok = true } end
        values.advancementClient.reset = function() advancementResetCalls = advancementResetCalls + 1; return { ok = true } end
    end)
    created.owner.install(); f.events.OnCreatePlayer.fire(0, {})
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
    created.owner.install(); f.events.OnCreatePlayer.fire(0, {})
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
    created.owner.install(); f.events.OnCreatePlayer.fire(0, {})
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
    created.owner.install(); f.events.OnCreatePlayer.fire(0, {})
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
    eq(f.calls[#f.calls - 1][1], "client_reset", "captured owner reset runs")
    eq(f.calls[#f.calls][1], "adv_reset", "captured advancement reset runs")
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
    f.events.OnCreatePlayer.fire(2, player)
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
    created.owner.install(); f.events.OnCreatePlayer.fire(0, {})
    local unbound = created.owner.refreshOwner(0)
    eq(unbound.code, "not_bound", "valid unbound refresh is returned")
    eq(created.owner.status().failure, nil, "valid unbound refresh does not poison lifecycle")
end

local bootstrapEvidence = rawget(_G, "__C10T_BOOTSTRAP_EVIDENCE")
if bootstrapEvidence ~= nil then
    eq(bootstrapEvidence.phase, 7, "bootstrap harness completes every phase")
    yes(bootstrapEvidence.checks >= 25, "bootstrap harness performs exact boundary checks")
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
