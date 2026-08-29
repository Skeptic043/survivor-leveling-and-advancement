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

local function nonnegativeInteger(value)
    return type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value >= 0 and value == math.floor(value)
end

local function finiteNonnegative(value)
    return type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value >= 0
end

local function exactPlain(value, fields)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not fields[key] then return false end
    end
    for key in pairs(fields) do
        if rawget(value, key) == nil then return false end
    end
    return true
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

local function cloneValue(value, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "number" or valueType == "string" then
        return value
    end
    if valueType ~= "table" then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local copiedKey = cloneValue(key, seen)
        local copiedChild = cloneValue(child, seen)
        if copiedKey == nil or copiedChild == nil then seen[value] = nil; return nil end
        copy[copiedKey] = copiedChild
    end
    seen[value] = nil
    return copy
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function ledgerFromPerk(record)
    return {
        naturalPosition = record.naturalPosition,
        highWaterPosition = record.highWaterPosition,
        activeTargets = record.activeTargets,
    }
end

local function recordAtPosition(record, ledger, position)
    local copy = cloneValue(record)
    if copy == nil then return nil end
    if ledger ~= nil then
        copy.naturalPosition = ledger.naturalPosition
        copy.highWaterPosition = ledger.highWaterPosition
        copy.activeTargets = ledger.activeTargets
    end
    copy.observedPosition = position
    return copy
end

local function successful(result)
    return type(result) == "table" and rawget(result, "ok") == true
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

local function resolveAccountingMode(accountingSettings, player)
    local resolved, settingsFailure, settingsResult = call(accountingSettings.resolve, player)
    if resolved == nil then
        return nil, dependencyFailure("accounting_settings", settingsFailure, settingsResult)
    end
    if not exactPlain(resolved, { ok = true, settings = true }) or rawget(resolved, "ok") ~= true then
        return nil, failure("accounting_settings_invalid", "accountingSettings.resolve")
    end
    local settings = resolved.settings
    if not exactPlain(settings, { mode = true }) then
        return nil, failure("accounting_settings_invalid", "accountingSettings.resolve")
    end
    if settings.mode ~= "Tracked" and settings.mode ~= "Free" then
        return nil, failure("accounting_settings_invalid", "accountingSettings.resolve")
    end
    return settings.mode, nil
end

local function synchronizeAccountingMode(accountingMode, player, state, desiredMode)
    local synchronized, synchronizeFailure, synchronizeResult = call(
        accountingMode.synchronizeLoaded,
        player,
        state,
        desiredMode
    )
    if synchronized == nil then
        return nil, dependencyFailure("accounting_mode", synchronizeFailure, synchronizeResult)
    end
    if not exactPlain(synchronized, {
            ok = true,
            state = true,
            transitioned = true,
            fromMode = true,
            toMode = true,
        })
        or rawget(synchronized, "ok") ~= true
        or type(synchronized.state) ~= "table"
        or type(synchronized.transitioned) ~= "boolean"
        or (synchronized.fromMode ~= "Tracked" and synchronized.fromMode ~= "Free")
        or synchronized.toMode ~= desiredMode
        or synchronized.state.accountingMode ~= desiredMode
        or state.accountingMode ~= synchronized.fromMode
        or not nonnegativeInteger(state.revision)
        or (synchronized.transitioned and (
            synchronized.fromMode == desiredMode
            or state.revision >= MAX_SAFE_INTEGER
            or synchronized.state == state
            or synchronized.state.revision ~= state.revision + 1
        ))
        or (not synchronized.transitioned and (
            synchronized.fromMode ~= desiredMode
            or synchronized.state ~= state
        )) then
        return nil, failure("accounting_mode_invalid", "accountingMode.synchronizeLoaded")
    end
    local survivor = synchronized.state.survivor
    if not nonnegativeInteger(synchronized.state.revision)
        or type(survivor) ~= "table"
        or not nonnegativeInteger(survivor.level)
        or not finiteNonnegative(survivor.xpIntoLevel)
        or not nonnegativeInteger(survivor.spent)
        or (desiredMode == "Tracked" and type(synchronized.state.perks) ~= "table") then
        return nil, failure("accounting_mode_invalid", "accountingMode.synchronizeLoaded")
    end
    return synchronized.state, nil
end

function OwnerSession.create(dependencies)
    if type(dependencies) ~= "table" then return failure("invalid_dependencies", "dependencies must be a table") end

    local store = dependencies.store
    if type(store) ~= "table" or type(store.load) ~= "function" then
        return failure("invalid_dependencies", "store.load is required")
    end
    if type(store.save) ~= "function" then
        return failure("invalid_dependencies", "store.save is required")
    end
    local recoveryService = dependencies.recoveryService
    if type(recoveryService) ~= "table" or type(recoveryService.recoverLoadedState) ~= "function" then
        return failure("invalid_dependencies", "recoveryService.recoverLoadedState is required")
    end
    local accountingMode = dependencies.accountingMode
    if type(accountingMode) ~= "table" or type(accountingMode.synchronizeLoaded) ~= "function" then
        return failure("invalid_dependencies", "accountingMode.synchronizeLoaded is required")
    end
    local accountingSettings = dependencies.accountingSettings
    if type(accountingSettings) ~= "table" or type(accountingSettings.resolve) ~= "function" then
        return failure("invalid_dependencies", "accountingSettings.resolve is required")
    end
    local catalog = dependencies.catalog
    if type(catalog) ~= "table" or type(catalog.allPerks) ~= "function"
        or type(catalog.resolver) ~= "table" or type(catalog.resolver.loadOptions) ~= "table"
        or type(catalog.positionReader) ~= "table" or type(catalog.positionReader.read) ~= "function" then
        return failure("invalid_dependencies", "catalog capabilities are required")
    end
    local NaturalLedger = dependencies.NaturalLedger
    if type(NaturalLedger) ~= "table" or type(NaturalLedger.reconcileExternal) ~= "function" then
        return failure("invalid_dependencies", "NaturalLedger.reconcileExternal is required")
    end
    local ActualObservation = dependencies.ActualObservation
    if type(ActualObservation) ~= "table" or type(ActualObservation.set) ~= "function" then
        return failure("invalid_dependencies", "ActualObservation.set is required")
    end
    local xpSource = dependencies.xpSource
    if type(xpSource) ~= "table" or type(xpSource.initializePlayer) ~= "function" then
        return failure("invalid_dependencies", "xpSource.initializePlayer is required")
    end
    local ownerSnapshot = dependencies.ownerSnapshot
    if type(ownerSnapshot) ~= "table" or type(ownerSnapshot.project) ~= "function" then
        return failure("invalid_dependencies", "ownerSnapshot.project is required")
    end
    local inheritanceSession = dependencies.inheritanceSession
    if type(inheritanceSession) ~= "table" or type(inheritanceSession.initialize) ~= "function" then
        return failure("invalid_dependencies", "inheritanceSession.initialize is required")
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

    local function reconcileReadiness(player, state)
        if state.accountingMode ~= "Tracked" then return state, nil end

        local candidate = state
        local changed = false
        local seeds = {}
        local perkIds = sortedKeys(state.perks)
        for index = 1, #perkIds do
            local perkId = perkIds[index]
            local record = state.perks[perkId]
            local readCalled, readResult = pcall(catalog.positionReader.read, player, perkId)
            if readCalled and successful(readResult) and finiteNonnegative(rawget(readResult, "position"))
                and type(record) == "table"
                and (record.observedPosition == nil or finiteNonnegative(record.observedPosition)) then
                local position = readResult.position
                local nextRecord
                if record.observedPosition == nil then
                    nextRecord = recordAtPosition(record, nil, position)
                elseif record.observedPosition ~= position then
                    local reconciledCalled, reconciled = pcall(
                        NaturalLedger.reconcileExternal,
                        ledgerFromPerk(record),
                        position - record.observedPosition,
                        position
                    )
                    if reconciledCalled and successful(reconciled) and type(reconciled.state) == "table" then
                        nextRecord = recordAtPosition(record, reconciled.state, position)
                    end
                end

                if nextRecord ~= nil then
                    if not changed then
                        candidate = cloneValue(state)
                        if candidate == nil then return nil, failure("readiness_reconciliation_invalid", "state clone") end
                        changed = true
                    end
                    candidate.perks[perkId] = nextRecord
                end
                if nextRecord ~= nil or record.observedPosition == position then
                    seeds[#seeds + 1] = { perkId = perkId, position = position }
                end
            end
        end

        if changed then
            local saved, saveFailure, saveResult = call(store.save, player, candidate)
            if saved == nil then
                return nil, dependencyFailure("readiness_reconciliation_save", saveFailure, saveResult)
            end
        end
        for index = 1, #seeds do
            local seed = seeds[index]
            local observed, observationFailure, observationResult = call(
                ActualObservation.set,
                player,
                seed.perkId,
                seed.position
            )
            if observed == nil then
                return nil, dependencyFailure("readiness_observation", observationFailure, observationResult)
            end
        end
        return candidate, nil
    end

    function session.ready(player)
        if player == nil then return failure("invalid_player", "player is required") end
        local priorEntry = entryFor(player)

        local inherited, inheritanceFailure, inheritanceResult = call(inheritanceSession.initialize, player)
        if inherited == nil then
            return dependencyFailure("inheritance_initialize", inheritanceFailure, inheritanceResult)
        end
        if not exactPlain(inherited, {
                ok = true, outcome = true, survivorLevel = true, consumed = true,
            }) or rawget(inherited, "ok") ~= true
            or (inherited.outcome ~= "existing" and inherited.outcome ~= "fresh"
                and inherited.outcome ~= "inherit")
            or not nonnegativeInteger(inherited.survivorLevel)
            or type(inherited.consumed) ~= "boolean" then
            return failure("inheritance_initialize_invalid", "inheritanceSession.initialize")
        end

        local loaded, loadFailure, loadResult = call(store.load, player, loadOptions)
        if loaded == nil then return dependencyFailure("store_load", loadFailure, loadResult) end
        if type(loaded.state) ~= "table" then return failure("store_load_invalid", "store.load") end

        local recovered, recoveryFailure, recoveryResult = call(recoveryService.recoverLoadedState, player, loaded.state)
        if recovered == nil then return dependencyFailure("recovery", recoveryFailure, recoveryResult) end
        if type(recovered.state) ~= "table" or type(recovered.recovered) ~= "boolean" then
            return failure("recovery_invalid", "recoveryService.recoverLoadedState")
        end

        local desiredMode, settingsFailure = resolveAccountingMode(accountingSettings, player)
        if desiredMode == nil then return settingsFailure end
        local synchronizedState, synchronizationFailure = synchronizeAccountingMode(
            accountingMode,
            player,
            recovered.state,
            desiredMode
        )
        if synchronizedState == nil then return synchronizationFailure end

        local catalogResult, catalogFailure, failedCatalogResult = call(catalog.allPerks)
        if catalogResult == nil then return dependencyFailure("catalog", catalogFailure, failedCatalogResult) end
        if not denseArray(catalogResult.perks) then return failure("catalog_invalid", "catalog.allPerks") end

        local reconciledState, reconciliationFailure = reconcileReadiness(player, synchronizedState)
        if reconciledState == nil then return reconciliationFailure end
        synchronizedState = reconciledState

        local initialized, initializationFailure, initializationResult = call(xpSource.initializePlayer, player, catalogResult.perks)
        if initialized == nil then return dependencyFailure("xp_initialize", initializationFailure, initializationResult) end
        local initializedCount, skippedCount = initializedCounts(initialized)
        if initializedCount == nil or initializedCount + skippedCount ~= #catalogResult.perks then
            return failure("xp_initialize_invalid", "xpSource.initializePlayer")
        end

        local sequence = nextSequence(priorEntry)
        if sequence == nil then return failure("sequence_invalid", "session sequence") end
        local snapshot, snapshotFailure = project(synchronizedState, sequence)
        if snapshot == nil then return snapshotFailure end

        entries[player] = { ready = true, sequence = sequence }
        local result = {
            ok = true,
            snapshot = snapshot,
            recovered = recovered.recovered,
            initialized = initializedCount,
            skipped = skippedCount,
        }
        if priorEntry == nil and inherited.outcome == "inherit" and inherited.consumed
            and inherited.survivorLevel > 0 then
            result.completion = {
                protocolVersion = 1,
                kind = "survivor_level_gain",
                levelsGained = inherited.survivorLevel,
                apGained = inherited.survivorLevel,
            }
        end
        return result
    end

    function session.snapshot(player)
        if player == nil then return failure("invalid_player", "player is required") end
        local entry = entryFor(player)
        if entry == nil or not entry.ready then return failure("not_ready", "ready has not succeeded") end

        local loaded, loadFailure, loadResult = call(store.load, player, loadOptions)
        if loaded == nil then return dependencyFailure("store_load", loadFailure, loadResult) end
        if type(loaded.state) ~= "table" then return failure("store_load_invalid", "store.load") end

        local desiredMode, settingsFailure = resolveAccountingMode(accountingSettings, player)
        if desiredMode == nil then return settingsFailure end
        local synchronizedState, synchronizationFailure = synchronizeAccountingMode(
            accountingMode,
            player,
            loaded.state,
            desiredMode
        )
        if synchronizedState == nil then return synchronizationFailure end

        local sequence = nextSequence(entry)
        if sequence == nil then return failure("sequence_invalid", "session sequence") end
        local snapshot, snapshotFailure = project(synchronizedState, sequence)
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
