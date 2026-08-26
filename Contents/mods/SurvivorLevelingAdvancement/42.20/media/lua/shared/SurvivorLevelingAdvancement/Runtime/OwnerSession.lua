local OwnerSession = {}
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_DIAGNOSTIC_CODE_LENGTH = 64
local MAX_DIAGNOSTIC_DETAIL_LENGTH = 95

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function positiveInteger(value)
    return type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value > 0 and value == math.floor(value)
end

local function denseArray(value)
    if type(value) ~= "table" then return false end
    local length = #value
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) or key > length then
            return false
        end
    end
    return true
end

local function successful(result)
    return type(result) == "table" and result.ok == true
end

local function safeDiagnosticCode(value)
    if type(value) == "string" and #value > 0 and #value <= MAX_DIAGNOSTIC_CODE_LENGTH
        and value:match("^[%w%._:%-]+$") ~= nil then
        return value
    end
    return "unavailable"
end

local function safeDiagnosticDetail(value)
    if type(value) == "string" and #value > 0 and #value <= MAX_DIAGNOSTIC_DETAIL_LENGTH
        and value:find("[%c]") == nil then
        return value
    end
    return "unavailable"
end

local function dependencyDetail(result)
    if type(result) ~= "table" then
        return "unavailable:unavailable"
    end
    return safeDiagnosticCode(rawget(result, "code")) .. ":"
        .. safeDiagnosticDetail(rawget(result, "detail"))
end

local function call(callable, ...)
    local called, result = pcall(callable, ...)
    if not called then return nil, "threw" end
    if not successful(result) then return nil, "failed", result end
    return result, nil
end

local function initializedCounts(result)
    local detail = result.detail
    if type(detail) ~= "table" then return nil end
    local initialized, skipped = detail.initialized, detail.skipped
    if type(initialized) ~= "number" or initialized ~= initialized or initialized == math.huge or initialized == -math.huge
        or initialized ~= math.floor(initialized) or initialized < 0
        or type(skipped) ~= "number" or skipped ~= skipped or skipped == math.huge or skipped == -math.huge
        or skipped ~= math.floor(skipped) or skipped < 0 then
        return nil
    end
    return initialized, skipped
end

local function dependencyFailure(operation, kind, result)
    if kind == "failed" then
        return failure(operation .. "_failed", dependencyDetail(result))
    end
    return failure(operation .. "_threw", "dependency threw")
end

function OwnerSession.create(dependencies)
    if type(dependencies) ~= "table" then return failure("invalid_dependencies", "dependencies must be a table") end

    local store = dependencies.store
    if type(store) ~= "table" or type(store.load) ~= "function" then
        return failure("invalid_dependencies", "store.load is required")
    end
    local recoveryService = dependencies.recoveryService
    if type(recoveryService) ~= "table" or type(recoveryService.recoverLoadedState) ~= "function" then
        return failure("invalid_dependencies", "recoveryService.recoverLoadedState is required")
    end
    local catalog = dependencies.catalog
    if type(catalog) ~= "table" or type(catalog.allPerks) ~= "function"
        or type(catalog.resolver) ~= "table" or type(catalog.resolver.loadOptions) ~= "table" then
        return failure("invalid_dependencies", "catalog capabilities are required")
    end
    local xpSource = dependencies.xpSource
    if type(xpSource) ~= "table" or type(xpSource.initializePlayer) ~= "function" then
        return failure("invalid_dependencies", "xpSource.initializePlayer is required")
    end
    local ownerSnapshot = dependencies.ownerSnapshot
    if type(ownerSnapshot) ~= "table" or type(ownerSnapshot.project) ~= "function" then
        return failure("invalid_dependencies", "ownerSnapshot.project is required")
    end

    local entries = setmetatable({}, { __mode = "k" })
    local loadOptions = catalog.resolver.loadOptions
    local session = {}

    local function entryFor(player)
        return entries[player]
    end

    local function nextSequence(entry)
        if entry == nil then return 1 end
        if type(entry) ~= "table" or not positiveInteger(entry.sequence)
            or entry.sequence >= MAX_SAFE_INTEGER then return nil end
        local sequence = entry.sequence + 1
        if not positiveInteger(sequence) or sequence <= entry.sequence then return nil end
        return sequence
    end

    local function project(state, sequence)
        local projected, projectFailure, projectResult = call(ownerSnapshot.project, state, sequence, true)
        if projected == nil then return nil, dependencyFailure("snapshot", projectFailure, projectResult) end
        if type(projected.snapshot) ~= "table" or projected.snapshot.protocolVersion ~= 1
            or projected.snapshot.ready ~= true or projected.snapshot.sequence ~= sequence then
            return nil, failure("snapshot_invalid", "ownerSnapshot.project")
        end
        return projected.snapshot
    end

    function session.ready(player)
        if player == nil then return failure("invalid_player", "player is required") end

        local loaded, loadFailure, loadResult = call(store.load, player, loadOptions)
        if loaded == nil then return dependencyFailure("store_load", loadFailure, loadResult) end
        if type(loaded.state) ~= "table" then return failure("store_load_invalid", "store.load") end

        local recovered, recoveryFailure, recoveryResult = call(recoveryService.recoverLoadedState, player, loaded.state)
        if recovered == nil then return dependencyFailure("recovery", recoveryFailure, recoveryResult) end
        if type(recovered.state) ~= "table" or type(recovered.recovered) ~= "boolean" then
            return failure("recovery_invalid", "recoveryService.recoverLoadedState")
        end

        local catalogResult, catalogFailure, failedCatalogResult = call(catalog.allPerks)
        if catalogResult == nil then return dependencyFailure("catalog", catalogFailure, failedCatalogResult) end
        if not denseArray(catalogResult.perks) then return failure("catalog_invalid", "catalog.allPerks") end

        local initialized, initializationFailure, initializationResult = call(xpSource.initializePlayer, player, catalogResult.perks)
        if initialized == nil then return dependencyFailure("xp_initialize", initializationFailure, initializationResult) end
        local initializedCount, skippedCount = initializedCounts(initialized)
        if initializedCount == nil or initializedCount + skippedCount ~= #catalogResult.perks then
            return failure("xp_initialize_invalid", "xpSource.initializePlayer")
        end

        local sequence = nextSequence(entryFor(player))
        if sequence == nil then return failure("sequence_invalid", "session sequence") end
        local snapshot, snapshotFailure = project(recovered.state, sequence)
        if snapshot == nil then return snapshotFailure end

        entries[player] = { ready = true, sequence = sequence }
        return {
            ok = true,
            snapshot = snapshot,
            recovered = recovered.recovered,
            initialized = initializedCount,
            skipped = skippedCount,
        }
    end

    function session.snapshot(player)
        if player == nil then return failure("invalid_player", "player is required") end
        local entry = entryFor(player)
        if entry == nil or not entry.ready then return failure("not_ready", "ready has not succeeded") end

        local loaded, loadFailure, loadResult = call(store.load, player, loadOptions)
        if loaded == nil then return dependencyFailure("store_load", loadFailure, loadResult) end
        if type(loaded.state) ~= "table" then return failure("store_load_invalid", "store.load") end

        local sequence = nextSequence(entry)
        if sequence == nil then return failure("sequence_invalid", "session sequence") end
        local snapshot, snapshotFailure = project(loaded.state, sequence)
        if snapshot == nil then return snapshotFailure end

        entry.sequence = sequence
        return { ok = true, snapshot = snapshot }
    end

    function session.isReady(player)
        local entry = player ~= nil and entryFor(player) or nil
        return entry ~= nil and entry.ready == true
    end

    function session.clearPlayer(player)
        if player ~= nil then entries[player] = nil end
        return { ok = true }
    end

    return { ok = true, session = session }
end

return OwnerSession
