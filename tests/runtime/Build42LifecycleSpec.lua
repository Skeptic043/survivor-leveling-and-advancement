local assertions = 0
local function eq(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end
local function yes(value, message) eq(value, true, message) end
local function no(value, message) eq(value, false, message) end

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
        ready = function(player) calls[#calls + 1] = { "ready", player }; return { ok = true, snapshot = { marker = player } } end,
        snapshot = function() return { ok = true, snapshot = {} } end,
        isReady = function() return true end,
        clearPlayer = function() return { ok = true } end,
    }
    local source = { install = function() calls[#calls + 1] = { "install_source" }; return { ok = true } end }
    local runtime = { catalog = {}, services = { xpSource = source, ownerSession = session } }
    local localClient = {
        ready = function(slot, player) calls[#calls + 1] = { "client_ready", slot, player }; return { ok = true } end,
        handle = function(module, command, args) calls[#calls + 1] = { "client_handle", module, command, args }; return { ok = true } end,
        reset = function() calls[#calls + 1] = { "client_reset" }; return { ok = true } end,
        resetSlot = function(slot) calls[#calls + 1] = { "client_reset_slot", slot }; return { ok = true } end,
        acceptLocal = function(slot, snapshot) calls[#calls + 1] = { "client_accept", slot, snapshot }; return { ok = true, accepted = true } end,
        get = function() return { ok = true, present = false } end,
    }
    local serverTransport = {
        handle = function(module, command, player, args) calls[#calls + 1] = { "server_handle", module, command, player, args }; return { ok = true } end,
        clearPlayer = function() return { ok = true } end,
    }
    local factoryCalls, clientCreates, serverCreates = 0, 0, 0
    local validator = function(snapshot) return { ok = true, snapshot = { marker = snapshot.marker } } end
    local modules = {
        Build42RuntimeFactory = { create = function(argument) factoryCalls = factoryCalls + 1; calls[#calls + 1] = { "factory", argument }; return { ok = true, runtime = runtime } end },
        Build42OwnerTransport = {
            createClient = function(argument) clientCreates = clientCreates + 1; calls[#calls + 1] = { "create_client", argument }; return { ok = true, client = localClient } end,
            createServer = function(argument) serverCreates = serverCreates + 1; calls[#calls + 1] = { "create_server", argument }; return { ok = true, server = serverTransport } end,
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
    if configure ~= nil then configure({ modules = modules, globals = globals, localClient = localClient, session = session, source = source, serverTransport = serverTransport }) end
    local created = Build42Lifecycle.create({ modules = modules, globals = globals })
    return created, { calls = calls, events = events, modules = modules, globals = globals, session = session, source = source, runtime = runtime, localClient = localClient, serverTransport = serverTransport,
        factoryCalls = function() return factoryCalls end, clientCreates = function() return clientCreates end, serverCreates = function() return serverCreates end, validator = validator }
end

do
    local created, f = fixture(true, false)
    yes(created.ok, "server creates")
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
    local created, f = fixture(true, false)
    yes(created.owner.install().ok, "server callback-failure hooks install")
    f.events.OnServerStarted.fire()
    f.serverTransport.handle = function() error("handle boom") end
    f.events.OnClientCommand.fire("other", "ignored", {}, {})
    eq(created.owner.status().failure.code, "server_handle_invalid", "server command throw retained")
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
    local created, f = fixture(true, false)
    local attempts = 0
    f.modules.Build42RuntimeFactory.create = function() attempts = attempts + 1; error("factory boom") end
    yes(created.owner.install().ok, "factory-failure hooks install")
    f.events.OnServerStarted.fire(); f.events.OnServerStarted.fire()
    eq(attempts, 1, "throwing factory is attempted once")
    eq(created.owner.status().failure.code, "runtime_factory_invalid", "factory throw retained")
end

do
    local created, f = fixture(true, false)
    local attempts = 0
    f.modules.Build42RuntimeFactory.create = function()
        attempts = attempts + 1
        return { ok = true, runtime = { catalog = {}, services = { xpSource = f.source, ownerSession = f.session } } }
    end
    f.source.install = function() error("install boom") end
    yes(created.owner.install().ok, "source-failure hooks install")
    f.events.OnServerStarted.fire(); f.events.OnServerStarted.fire()
    eq(attempts, 1, "source failure does not rebuild runtime")
    eq(created.owner.status().failure.code, "xp_source_install_invalid", "source throw retained")
end

do
    local created, f = fixture(true, false)
    f.modules.Build42OwnerTransport.createServer = function() error("transport boom") end
    yes(created.owner.install().ok, "server-transport hooks install")
    f.events.OnServerStarted.fire()
    eq(created.owner.status().failure.code, "server_transport_invalid", "server transport throw retained")
end

do
    local created, f = fixture(false, true)
    yes(created.owner.install().ok, "callback client installs")
    f.localClient.ready = function() error("ready boom") end
    f.events.OnCreatePlayer.fire(0, {})
    eq(created.owner.status().failure.code, "client_ready_invalid", "client ready throw retained")
    f.localClient.handle = function() return "bad" end
    f.events.OnServerCommand.fire("other", "ignored", {})
    eq(created.owner.status().failure.code, "client_handle_invalid", "client handle malformed retained")
    f.localClient.reset = function() error("disconnect boom") end
    f.events.OnDisconnect.fire()
    eq(created.owner.status().failure.code, "client_reset_invalid", "disconnect throw retained")
    local before = #f.calls
    f.events.OnCreatePlayer.fire(4, {})
    eq(#f.calls, before, "invalid slot is ignored before transport")
end

do
    local created, f = fixture(false, false)
    yes(created.owner.install().ok, "SP failure hooks install")
    f.events.OnGameStart.fire()
    f.localClient.resetSlot = function() error("reset boom") end
    f.events.OnCreatePlayer.fire(0, {})
    eq(created.owner.status().failure.code, "client_reset_invalid", "SP reset throw retained")
    f.localClient.resetSlot = function() return { ok = true } end
    f.session.ready = function() return "bad" end
    f.events.OnCreatePlayer.fire(1, {})
    eq(created.owner.status().failure.code, "session_ready_invalid", "SP ready malformed retained")
    f.session.ready = function() return { ok = true, snapshot = {} } end
    f.localClient.acceptLocal = function() error("accept boom") end
    f.events.OnCreatePlayer.fire(2, {})
    eq(created.owner.status().failure.code, "client_accept_invalid", "SP accept throw retained")
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
    eq(f.calls[#f.calls][1], "client_reset", "disconnect resets client transport")
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
    yes(created.owner.install().ok, "failing server installs callbacks")
    f.events.OnServerStarted.fire(); f.events.OnServerStarted.fire()
    eq(f.factoryCalls(), 0, "replacement factory is called through frozen module table only once attempt")
    eq(created.owner.status().failure.code, "factory_down", "factory failure retained")
end

do
    local created, f = fixture(true, false)
    f.modules.Build42RuntimeFactory.create = function()
        return { ok = true, runtime = { services = { xpSource = f.source, ownerSession = f.session } } }
    end
    yes(created.owner.install().ok, "malformed-runtime hooks install")
    f.events.OnServerStarted.fire()
    eq(created.owner.status().failure.code, "runtime_factory_invalid", "missing runtime catalog is rejected")
    created, f = fixture(true, false)
    f.modules.Build42RuntimeFactory.create = function() return "bad" end
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
