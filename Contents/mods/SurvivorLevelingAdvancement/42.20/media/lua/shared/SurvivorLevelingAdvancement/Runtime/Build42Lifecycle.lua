local Build42Lifecycle = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function bounded(result, code, detail)
    if type(result) == "table" and result.ok == false
        and type(result.code) == "string" and result.code ~= "" and #result.code <= 64
        and (function(value)
            for index = 1, #value do
                local byte = string.byte(value, index)
                if not ((byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90)
                    or (byte >= 97 and byte <= 122) or byte == 95 or byte == 46 or byte == 58 or byte == 45) then
                    return false
                end
            end
            return true
        end)(result.code)
        and type(result.detail) == "string" and result.detail ~= "" and #result.detail <= 160
        and result.detail:find("[%c]") == nil then
        return failure(result.code, result.detail)
    end
    return failure(code, detail)
end

local function callable(value)
    return type(value) == "function"
end

local function validSlot(value)
    return type(value) == "number" and value == math.floor(value) and value >= 0 and value <= 3
end

local function exactTable(value, fields)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do if type(key) ~= "string" or not fields[key] then return false end end
    for key in pairs(fields) do if rawget(value, key) == nil then return false end end
    return true
end

local function eventSet(events, names)
    if type(events) ~= "table" then return nil end
    local captured = {}
    for index = 1, #names do
        local name = names[index]
        local event = events[name]
        if type(event) ~= "table" or not callable(event.Add) then return nil end
        captured[name] = event
    end
    return captured
end

function Build42Lifecycle.create(dependencies)
    if type(dependencies) ~= "table" or type(dependencies.modules) ~= "table" or type(dependencies.globals) ~= "table" then
        return failure("invalid_dependencies", "modules and globals are required")
    end
    local modules, globals = dependencies.modules, dependencies.globals
    if type(modules.Build42RuntimeFactory) ~= "table" or not callable(modules.Build42RuntimeFactory.create)
        or type(modules.Build42OwnerTransport) ~= "table" or not callable(modules.Build42OwnerTransport.createServer)
        or not callable(modules.Build42OwnerTransport.createClient)
        or type(modules.ClientOwnerState) ~= "table" or not callable(modules.ClientOwnerState.create)
        or not callable(modules.ClientOwnerState.validate) then
        return failure("invalid_dependencies", "lifecycle module capabilities are required")
    end
    local snapshotValidator = { validate = modules.ClientOwnerState.validate }
    if not callable(globals.isServer) or not callable(globals.isClient)
        or not callable(globals.sendClientCommand) or not callable(globals.sendServerCommand) then
        return failure("invalid_dependencies", "lifecycle global capabilities are required")
    end

    local serverCalled, server = pcall(globals.isServer)
    local clientCalled, client = pcall(globals.isClient)
    if not serverCalled or not clientCalled or type(server) ~= "boolean" or type(client) ~= "boolean" then
        return failure("mode_invalid", "isServer and isClient must return booleans")
    end
    local mode
    if server and client then return failure("mode_invalid", "server and client cannot both be true") end
    if server then mode = "server" elseif client then mode = "client" else mode = "single_player" end

    local clientTransport = nil
    local clientGet = nil
    if mode ~= "server" then
        local called, created = pcall(modules.Build42OwnerTransport.createClient, {
            ClientOwnerState = modules.ClientOwnerState,
            sendClientCommand = globals.sendClientCommand,
        })
        if not called or type(created) ~= "table" or created.ok ~= true or type(created.client) ~= "table"
            or not callable(created.client.ready) or not callable(created.client.handle) or not callable(created.client.reset)
            or not callable(created.client.resetSlot) or not callable(created.client.acceptLocal) or not callable(created.client.get) then
            return bounded(created, "client_transport_invalid", "Build42OwnerTransport.createClient")
        end
        clientTransport = created.client
        clientGet = clientTransport.get
    end

    local names = mode == "server" and { "OnServerStarted", "OnClientCommand" }
        or mode == "client" and { "OnCreatePlayer", "OnServerCommand", "OnDisconnect" }
        or { "OnGameStart", "OnCreatePlayer" }
    local events = eventSet(globals.Events, names)
    if events == nil then return failure("invalid_dependencies", "required lifecycle events are required") end

    local installed, installAttempted, startupAttempted, started = false, false, false, false
    local retainedFailure, runtime, serverTransport = nil, nil, nil
    local pending = {}
    local owner = {}
    local readySingle

    local function retain(result, code, detail)
        retainedFailure = bounded(result, code, detail)
        return retainedFailure
    end

    local function ownEvents()
        if type(globals.Events) ~= "table" then
            retain(nil, "event_ownership_lost", "Events")
            return false
        end
        for index = 1, #names do
            local name = names[index]
            if type(globals.Events[name]) ~= "table" or globals.Events[name] ~= events[name] then
                retain(nil, "event_ownership_lost", name)
                return false
            end
        end
        return true
    end

    local function startup()
        if startupAttempted then return retainedFailure or { ok = started } end
        startupAttempted = true
        local called, created = pcall(modules.Build42RuntimeFactory.create, { modules = modules, globals = globals })
        if not called or type(created) ~= "table" or created.ok ~= true or type(created.runtime) ~= "table"
            or type(created.runtime.catalog) ~= "table"
            or type(created.runtime.services) ~= "table" then
            return retain(created, "runtime_factory_invalid", "Build42RuntimeFactory.create")
        end
        local services = created.runtime.services
        if type(services.xpSource) ~= "table" or not callable(services.xpSource.install)
            or type(services.ownerSession) ~= "table" or not callable(services.ownerSession.ready)
            or not callable(services.ownerSession.snapshot) or not callable(services.ownerSession.isReady)
            or not callable(services.ownerSession.clearPlayer) then
            return retain(nil, "runtime_factory_invalid", "runtime service surface")
        end
        runtime = created.runtime
        local sourceCalled, sourceResult = pcall(services.xpSource.install)
        if not sourceCalled or type(sourceResult) ~= "table" or sourceResult.ok ~= true then
            return retain(sourceResult, "xp_source_install_invalid", "xpSource.install")
        end
        if mode == "server" then
            local transportCalled, transportCreated = pcall(modules.Build42OwnerTransport.createServer, {
                ownerSession = services.ownerSession,
                snapshotValidator = snapshotValidator,
                sendServerCommand = globals.sendServerCommand,
            })
            if not transportCalled or type(transportCreated) ~= "table" or transportCreated.ok ~= true
                or type(transportCreated.server) ~= "table" or not callable(transportCreated.server.handle)
                or not callable(transportCreated.server.clearPlayer) then
                return retain(transportCreated, "server_transport_invalid", "Build42OwnerTransport.createServer")
            end
            serverTransport = transportCreated.server
        end
        started = true
        retainedFailure = nil
        if mode == "single_player" then
            local function drain(slot)
                local player = pending[slot]
                pending[slot] = nil
                if player ~= nil then readySingle(slot, player) end
            end
            drain(0); drain(1); drain(2); drain(3)
        end
        return { ok = true }
    end

    readySingle = function(localSlot, player)
        local resetCalled, reset = pcall(clientTransport.resetSlot, localSlot)
        if not resetCalled or type(reset) ~= "table" or reset.ok ~= true then return retain(reset, "client_reset_invalid", "client.resetSlot") end
        local called, result = pcall(runtime.services.ownerSession.ready, player)
        if not called or type(result) ~= "table" or result.ok ~= true or type(result.snapshot) ~= "table" then
            return retain(result, "session_ready_invalid", "ownerSession.ready")
        end
        local acceptCalled, accepted = pcall(clientTransport.acceptLocal, localSlot, result.snapshot)
        if not acceptCalled or type(accepted) ~= "table" or accepted.ok ~= true then return retain(accepted, "client_accept_invalid", "client.acceptLocal") end
        return { ok = true }
    end

    local function transportCall(callable, failureCode, detail, ...)
        local called, result = pcall(callable, ...)
        if not called or type(result) ~= "table" or type(result.ok) ~= "boolean" or result.ok ~= true then
            return retain(result, failureCode, detail)
        end
        return result
    end

    local callbacks = {}
    callbacks.OnServerStarted = function() if ownEvents() then startup() end end
    callbacks.OnGameStart = function() if ownEvents() then startup() end end
    callbacks.OnClientCommand = function(module, command, player, args)
        if ownEvents() and serverTransport ~= nil then
            transportCall(serverTransport.handle, "server_handle_invalid", "server.handle", module, command, player, args)
        end
    end
    callbacks.OnCreatePlayer = function(localSlot, player)
        if not ownEvents() or not validSlot(localSlot) or player == nil then return end
        if mode == "client" then
            transportCall(clientTransport.ready, "client_ready_invalid", "client.ready", localSlot, player)
        elseif started then
            readySingle(localSlot, player)
        else
            pending[localSlot] = player
        end
    end
    callbacks.OnServerCommand = function(module, command, args)
        if ownEvents() then transportCall(clientTransport.handle, "client_handle_invalid", "client.handle", module, command, args) end
    end
    callbacks.OnDisconnect = function()
        if ownEvents() then
            transportCall(clientTransport.reset, "client_reset_invalid", "client.reset")
        end
    end

    function owner.install()
        if installAttempted then
            if not ownEvents() then return retainedFailure end
            return installed and { ok = true } or retainedFailure or failure("install_failed", "event registration")
        end
        installAttempted = true
        for index = 1, #names do
            local name = names[index]
            local called = pcall(events[name].Add, callbacks[name])
            if not called then return retain(nil, "event_register_threw", name) end
        end
        installed = true
        return { ok = true }
    end

    function owner.status()
        local result = { ok = true, mode = mode, installed = installed, started = started, ready = started }
        if retainedFailure ~= nil then result.failure = { code = retainedFailure.code, detail = retainedFailure.detail } end
        return result
    end

    function owner.clientState(localSlot)
        if mode == "server" then return failure("client_state_unavailable", "server mode") end
        local called, result = pcall(clientGet, localSlot)
        if not called then return failure("client_state_threw", "client.get") end
        if exactTable(result, { ok = true, present = true }) and result.ok == true and result.present == false then
            return { ok = true, present = false }
        end
        if exactTable(result, { ok = true, present = true, snapshot = true })
            and result.ok == true and result.present == true and type(result.snapshot) == "table" then
            local validatedCalled, validated = pcall(snapshotValidator.validate, result.snapshot)
            if not validatedCalled or not exactTable(validated, { ok = true, snapshot = true })
                or validated.ok ~= true or type(validated.snapshot) ~= "table" then
                return failure("client_state_invalid", "client snapshot")
            end
            return { ok = true, present = true, snapshot = validated.snapshot }
        end
        if exactTable(result, { ok = true, code = true, detail = true }) and result.ok == false then
            local retained = bounded(result, "client_state_invalid", "client.get")
            return retained
        end
        return failure("client_state_invalid", "client.get")
    end

    return { ok = true, owner = owner }
end

return Build42Lifecycle
