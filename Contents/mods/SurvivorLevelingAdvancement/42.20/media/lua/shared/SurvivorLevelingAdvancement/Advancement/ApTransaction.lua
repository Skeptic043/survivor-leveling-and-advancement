local ApTransaction = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isNonnegativeInteger(value)
    return isFinite(value) and value >= 0 and value == math.floor(value)
end

local function isPositiveInteger(value)
    return isFinite(value) and value > 0 and value == math.floor(value)
end

local function isSafeId(value)
    return type(value) == "string" and value:match("^[%w%._:%-]+$") ~= nil
end

local function cloneValue(value, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "string" or valueType == "number" then
        if valueType == "number" and not isFinite(value) then
            return nil, "non_finite_number"
        end
        return value
    end
    if valueType ~= "table" then return nil, "unsupported_type" end
    seen = seen or {}
    if seen[value] then return nil, "cycle" end
    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local copiedKey, keyError = cloneValue(key, seen)
        if keyError then seen[value] = nil; return nil, keyError end
        local copiedChild, childError = cloneValue(child, seen)
        if childError then seen[value] = nil; return nil, childError end
        copy[copiedKey] = copiedChild
    end
    seen[value] = nil
    return copy
end

local function detailOf(result)
    if type(result) ~= "table" then return "not_result" end
    local code = result.code and tostring(result.code) or "failed"
    local detail = result.detail and tostring(result.detail) or "no_detail"
    return code .. ":" .. detail
end

local function hasMethods(value, names)
    if type(value) ~= "table" then return false end
    for index = 1, #names do
        if type(value[names[index]]) ~= "function" then return false end
    end
    return true
end

local function callResult(method, label, ...)
    local ok, result = pcall(method, ...)
    if not ok then return failure(label .. "_error", tostring(result)) end
    if type(result) ~= "table" then return failure(label .. "_invalid", "not_result") end
    return result
end

local function resolveAdapter(resolver, perkId)
    local ok, result = pcall(resolver.resolve, perkId)
    if not ok then return failure("resolver_failed", tostring(result)) end
    if type(result) ~= "table" then return failure("resolver_failed", "not_result") end
    if result.ok ~= true then return failure("resolver_failed", detailOf(result)) end

    local adapter = result.adapter
    local handle = result.handle
    if not hasMethods(adapter, { "describe", "inspect", "ensureTarget" }) or type(handle) ~= "table" then
        return failure("resolver_failed", "adapter_and_handle_required")
    end
    return { ok = true, adapter = adapter, handle = handle }
end

local function describeAdapter(adapter, handle)
    local result = callResult(adapter.describe, "adapter_describe", handle)
    if not result.ok then return failure("adapter_description_failed", detailOf(result)) end
    if not isSafeId(result.adapterId)
        or not isNonnegativeInteger(result.adapterVersion)
        or not isSafeId(result.curveFingerprint)
        or not isPositiveInteger(result.effectiveMaximum) then
        return failure("adapter_description_failed", "identity_invalid")
    end
    return {
        ok = true,
        identity = {
            adapterId = result.adapterId,
            adapterVersion = result.adapterVersion,
            curveFingerprint = result.curveFingerprint,
            effectiveMaximum = result.effectiveMaximum,
        },
    }
end

local function inspectAdapter(adapter, handle, player, identity)
    local result = callResult(adapter.inspect, "adapter_inspect", handle, player)
    if not result.ok then return failure("adapter_inspection_failed", detailOf(result)) end
    if not isNonnegativeInteger(result.storedLevel)
        or not isFinite(result.actualPosition)
        or result.actualPosition < 0
        or not isPositiveInteger(result.effectiveMaximum)
        or type(result.levelAligned) ~= "boolean" then
        return failure("adapter_inspection_failed", "mapping_invalid")
    end
    if result.effectiveMaximum ~= identity.effectiveMaximum
        or (result.adapterId ~= nil and result.adapterId ~= identity.adapterId)
        or (result.adapterVersion ~= nil and result.adapterVersion ~= identity.adapterVersion)
        or (result.curveFingerprint ~= nil and result.curveFingerprint ~= identity.curveFingerprint) then
        return failure("adapter_identity_mismatch", "inspection_identity_changed")
    end
    if result.storedLevel > identity.effectiveMaximum then
        return failure("adapter_inspection_failed", "level_above_maximum")
    end
    if result.storedLevel < identity.effectiveMaximum then
        if result.nextTargetLevel ~= result.storedLevel + 1
            or not isFinite(result.nextTargetPosition)
            or result.nextTargetPosition < 0 then
            return failure("adapter_inspection_failed", "next_target_invalid")
        end
    elseif result.nextTargetLevel ~= nil or result.nextTargetPosition ~= nil then
        return failure("adapter_inspection_failed", "maximum_target_present")
    end
    return { ok = true, inspection = result }
end

local function sameIdentity(record, identity)
    return type(record) == "table"
        and record.adapterId == identity.adapterId
        and record.adapterVersion == identity.adapterVersion
        and record.curveFingerprint == identity.curveFingerprint
        and record.effectiveMaximum == identity.effectiveMaximum
end

local function advancementCost(targetLevel, effectiveMaximum)
    return targetLevel == effectiveMaximum and 2 or 1
end

local function durableTargetId(requestId, preRevision)
    return requestId .. ":revision:" .. tostring(preRevision)
end

local function hasLegacyCompletedTarget(record, reservation)
    if type(record) ~= "table" or type(record.activeTargets) ~= "table" then return false end
    for index = 1, #record.activeTargets do
        local target = record.activeTargets[index]
        if type(target) == "table"
            and target.targetId == reservation.requestId
            and target.targetLevel == reservation.targetLevel
            and target.targetPosition == reservation.targetPosition then
            return true
        end
    end
    return false
end

local function ledgerFromPerk(record)
    return {
        naturalPosition = record.naturalPosition,
        highWaterPosition = record.highWaterPosition,
        activeTargets = record.activeTargets,
    }
end

local function durableRecordBoundary(record)
    if record.observedPosition ~= nil then return record.observedPosition end
    local boundary = record.naturalPosition
    if type(record.activeTargets) == "table" and #record.activeTargets > 0 then
        boundary = record.activeTargets[#record.activeTargets].targetPosition
    end
    return boundary
end

local function applyLedger(record, ledger)
    local copy, copyError = cloneValue(record)
    if not copy then return nil, copyError end
    copy.naturalPosition = ledger.naturalPosition
    copy.highWaterPosition = ledger.highWaterPosition
    copy.activeTargets = ledger.activeTargets
    return copy
end

local function perkFromBaseline(identity, ledger)
    return {
        adapterId = identity.adapterId,
        adapterVersion = identity.adapterVersion,
        curveFingerprint = identity.curveFingerprint,
        effectiveMaximum = identity.effectiveMaximum,
        naturalPosition = ledger.naturalPosition,
        highWaterPosition = ledger.highWaterPosition,
        activeTargets = ledger.activeTargets,
        postMaxFullRateUsed = 0,
    }
end

local function setPreservedFreeBoundary(state, perkId, identity, position)
    local record = state.perks[perkId]
    if record == nil or not sameIdentity(record, identity) then return { ok = true } end
    local nextRecord, recordError = cloneValue(record)
    if not nextRecord then return failure("invalid_state", recordError) end
    nextRecord.observedPosition = position
    state.perks[perkId] = nextRecord
    return { ok = true }
end

local function validateRequest(request)
    if type(request) ~= "table" then return failure("invalid_request", "request_not_table") end
    for key in pairs(request) do
        if key ~= "perkId" and key ~= "requestId" and key ~= "expectedRevision" then
            return failure("invalid_request", "unexpected_field:" .. tostring(key))
        end
    end
    if not isSafeId(request.perkId) then return failure("invalid_request", "perkId") end
    if not isSafeId(request.requestId) then return failure("invalid_request", "requestId") end
    if not isNonnegativeInteger(request.expectedRevision) then
        return failure("invalid_request", "expectedRevision")
    end
    return { ok = true }
end

local function validateReservation(record)
    if type(record) ~= "table"
        or not isSafeId(record.requestId)
        or not isSafeId(record.perkId)
        or not isNonnegativeInteger(record.preRevision)
        or not isNonnegativeInteger(record.preSpent)
        or not isNonnegativeInteger(record.preLevel)
        or not isFinite(record.prePosition)
        or record.prePosition < 0
        or not isPositiveInteger(record.targetLevel)
        or not isFinite(record.targetPosition)
        or record.targetPosition < 0
        or not isSafeId(record.adapterId)
        or not isNonnegativeInteger(record.adapterVersion)
        or not isSafeId(record.curveFingerprint)
        or not isPositiveInteger(record.effectiveMaximum) then
        return failure("recovery_quarantined", "reservation_invalid")
    end
    if record.targetLevel ~= record.preLevel + 1
        or record.targetLevel > record.effectiveMaximum
        or record.targetPosition <= record.prePosition then
        return failure("recovery_quarantined", "reservation_coordinates_invalid")
    end
    return { ok = true }
end

local function loadState(store, player, options)
    local loaded = callResult(store.load, "store_load", player, options)
    if not loaded.ok or type(loaded.state) ~= "table" then
        return failure("store_load_failed", detailOf(loaded))
    end
    return { ok = true, state = loaded.state }
end

local function saveState(store, player, state, code)
    local saved = callResult(store.save, "store_save", player, state)
    if not saved.ok then return failure(code, detailOf(saved)) end
    return { ok = true }
end

local function synchronizeAccountingMode(deps, player, state, desiredMode)
    local synchronized = callResult(
        deps.AccountingMode.synchronizeLoaded,
        "accounting_mode",
        player,
        state,
        desiredMode
    )
    if synchronized.ok ~= true then
        return failure("accounting_mode_failed", detailOf(synchronized))
    end
    if type(synchronized.state) ~= "table"
        or type(synchronized.transitioned) ~= "boolean"
        or (synchronized.fromMode ~= "Tracked" and synchronized.fromMode ~= "Free")
        or synchronized.toMode ~= desiredMode
        or synchronized.state.accountingMode ~= desiredMode
        or (synchronized.transitioned and synchronized.fromMode == desiredMode)
        or (not synchronized.transitioned and (synchronized.fromMode ~= desiredMode or synchronized.state ~= state)) then
        return failure("accounting_mode_failed", "result_invalid")
    end
    return synchronized
end

local function activeByPerk(state)
    local active = {}
    for perkId, record in pairs(state.perks) do
        if type(record) ~= "table" or type(record.activeTargets) ~= "table" then
            return nil, failure("invalid_state", "active_targets_invalid")
        end
        active[perkId] = #record.activeTargets
    end
    return active, nil
end

local function setObservation(observation, player, perkId, position)
    local result = callResult(observation.set, "observation_set", player, perkId, position)
    if not result.ok then return failure("observation_failed", detailOf(result)) end
    return { ok = true }
end

local function synchronizeObservation(deps, player, perkId, state, record, actualPosition)
    local observed = callResult(deps.ActualObservation.get, "observation_get", player, perkId)
    if not observed.ok then return failure("observation_failed", detailOf(observed)) end
    if observed.present ~= true then
        if record == nil then
            local setResult = setObservation(deps.ActualObservation, player, perkId, actualPosition)
            if not setResult.ok then return setResult end
            return { ok = true, state = state, record = record }
        end
        observed = { ok = true, present = true, position = durableRecordBoundary(record) }
    end
    if not isFinite(observed.position) or observed.position < 0 then
        return failure("observation_failed", "stored_position_invalid")
    end

    local delta = actualPosition - observed.position
    if delta == 0 or record == nil then
        local setResult = setObservation(deps.ActualObservation, player, perkId, actualPosition)
        if not setResult.ok then return setResult end
        return { ok = true, state = state, record = record }
    end

    local reconciled = deps.NaturalLedger.reconcileExternal(ledgerFromPerk(record), delta, actualPosition)
    if type(reconciled) ~= "table" or not reconciled.ok then
        return failure("perk_quarantined", "reconciliation_" .. detailOf(reconciled))
    end
    local nextRecord, recordError = applyLedger(record, reconciled.state)
    if not nextRecord then return failure("perk_quarantined", "record_" .. recordError) end
    nextRecord.observedPosition = actualPosition
    local nextState, stateError = cloneValue(state)
    if not nextState then return failure("invalid_state", stateError) end
    nextState.perks[perkId] = nextRecord
    local saved = saveState(deps.store, player, nextState, "reconciliation_save_failed")
    if not saved.ok then return saved end
    local setResult = setObservation(deps.ActualObservation, player, perkId, actualPosition)
    if not setResult.ok then return setResult end
    return { ok = true, state = nextState, record = nextRecord, reconciled = true }
end

local function beginScope(deps, player, perkId)
    local begun = callResult(deps.MutationScope.begin, "scope_begin", player, perkId)
    if not begun.ok or begun.handle == nil then
        return failure("scope_begin_failed", detailOf(begun))
    end
    return { ok = true, handle = begun.handle }
end

local function finishScope(deps, scopeHandle)
    local finished = callResult(deps.MutationScope.finish, "scope_finish", scopeHandle)
    if not finished.ok then return failure("scope_finish_failed", detailOf(finished)) end
    return { ok = true }
end

local function performEnsureInScope(
    deps,
    player,
    perkId,
    adapter,
    handle,
    identity,
    targetLevel,
    targetPosition,
    scopeHandle,
    updateObservation
)
    local ensured = callResult(adapter.ensureTarget, "adapter_ensure", handle, player, targetLevel, targetPosition)
    local finished = finishScope(deps, scopeHandle)
    local post = inspectAdapter(adapter, handle, player, identity)
    if post.ok and updateObservation then
        local observed = setObservation(deps.ActualObservation, player, perkId, post.inspection.actualPosition)
        if not observed.ok then return observed end
    end
    if not ensured.ok then return failure("engine_mutation_failed", detailOf(ensured)) end
    if not finished.ok then return failure("scope_finish_failed", detailOf(finished)) end
    if not post.ok then return failure("post_inspection_failed", detailOf(post)) end
    if post.inspection.storedLevel ~= targetLevel or post.inspection.actualPosition ~= targetPosition then
        return failure("post_inspection_failed", "target_not_exact")
    end
    if type(ensured.xpWriteInvoked) ~= "boolean" or type(ensured.levelWriteInvoked) ~= "boolean" then
        return failure("engine_mutation_failed", "write_effects_missing")
    end
    return {
        ok = true,
        xpWriteInvoked = ensured.xpWriteInvoked,
        levelWriteInvoked = ensured.levelWriteInvoked,
    }
end

local function performEnsureWithNewScope(
    deps,
    player,
    perkId,
    adapter,
    handle,
    identity,
    targetLevel,
    targetPosition,
    updateObservation
)
    local begun = beginScope(deps, player, perkId)
    if not begun.ok then return begun end
    return performEnsureInScope(
        deps,
        player,
        perkId,
        adapter,
        handle,
        identity,
        targetLevel,
        targetPosition,
        begun.handle,
        updateObservation
    )
end

local function recoverLoaded(deps, player, state)
    local reservation = state.inFlightAdvancement
    if reservation == nil then
        return { ok = true, state = state, recovered = false }
    end
    local reservationValid = validateReservation(reservation)
    if not reservationValid.ok then return reservationValid end
    local apCost = advancementCost(reservation.targetLevel, reservation.effectiveMaximum)
    if (state.revision ~= reservation.preRevision and state.revision ~= reservation.preRevision + 1)
        or (state.survivor.spent ~= reservation.preSpent and state.survivor.spent ~= reservation.preSpent + apCost)
        or reservation.preSpent + apCost > state.survivor.level then
        return failure("recovery_quarantined", "reservation_state_inconsistent")
    end

    local resolved = resolveAdapter(deps.resolver, reservation.perkId)
    if not resolved.ok then return failure("recovery_quarantined", detailOf(resolved)) end
    local described = describeAdapter(resolved.adapter, resolved.handle)
    if not described.ok then return failure("recovery_quarantined", detailOf(described)) end
    local identity = described.identity
    if identity.adapterId ~= reservation.adapterId
        or identity.adapterVersion ~= reservation.adapterVersion
        or identity.curveFingerprint ~= reservation.curveFingerprint
        or identity.effectiveMaximum ~= reservation.effectiveMaximum then
        return failure("recovery_quarantined", "adapter_identity_mismatch")
    end

    local free = state.accountingMode == "Free"
    local record
    local mastered = reservation.targetLevel == reservation.effectiveMaximum
    local ledgerResult
    local addedTarget = false
    if not free then
        record = state.perks[reservation.perkId]
        if record ~= nil and not sameIdentity(record, identity) then
            return failure("recovery_quarantined", "perk_identity_mismatch")
        end
        if record == nil then
            local baseline = deps.NaturalLedger.baseline(reservation.prePosition)
            if type(baseline) ~= "table" or not baseline.ok then
                return failure("recovery_quarantined", "baseline_" .. detailOf(baseline))
            end
            record = perkFromBaseline(identity, baseline.state)
        end

        if mastered then
            local ledgerInspection = deps.NaturalLedger.inspect(ledgerFromPerk(record))
            if type(ledgerInspection) ~= "table" or not ledgerInspection.ok then
                return failure("recovery_quarantined", "ledger_" .. detailOf(ledgerInspection))
            end
            if ledgerInspection.red then
                return failure("recovery_quarantined", "natural_recovery_required")
            end
            ledgerResult = deps.NaturalLedger.master(ledgerFromPerk(record), reservation.targetPosition)
        else
            local targetId = durableTargetId(reservation.requestId, reservation.preRevision)
            if hasLegacyCompletedTarget(record, reservation) then
                targetId = reservation.requestId
            end
            ledgerResult = deps.NaturalLedger.appendTarget(ledgerFromPerk(record), {
                targetId = targetId,
                targetLevel = reservation.targetLevel,
                targetPosition = reservation.targetPosition,
            }, reservation.effectiveMaximum)
        end
        if type(ledgerResult) ~= "table" or not ledgerResult.ok then
            return failure("recovery_quarantined", "target_" .. detailOf(ledgerResult))
        end
        addedTarget = not mastered and ledgerResult.added or false
    end

    local inspected = inspectAdapter(resolved.adapter, resolved.handle, player, identity)
    if not inspected.ok then return failure("recovery_quarantined", detailOf(inspected)) end
    local actual = inspected.inspection
    local atPre = actual.storedLevel == reservation.preLevel and actual.actualPosition == reservation.prePosition
    local xpOnly = actual.storedLevel == reservation.preLevel and actual.actualPosition == reservation.targetPosition
    local complete = actual.storedLevel == reservation.targetLevel and actual.actualPosition == reservation.targetPosition
    if not atPre and not xpOnly and not complete then
        return failure("recovery_quarantined", "observed_state_inconsistent")
    end

    local ensured = performEnsureWithNewScope(
        deps,
        player,
        reservation.perkId,
        resolved.adapter,
        resolved.handle,
        identity,
        reservation.targetLevel,
        reservation.targetPosition,
        not free
    )
    if not ensured.ok then return failure("recovery_quarantined", detailOf(ensured)) end

    local committed, stateError = cloneValue(state)
    if not committed then return failure("recovery_quarantined", "state_" .. stateError) end
    if free then
        local bounded = setPreservedFreeBoundary(
            committed,
            reservation.perkId,
            identity,
            reservation.targetPosition
        )
        if not bounded.ok then return failure("recovery_quarantined", detailOf(bounded)) end
    else
        local committedRecord, recordError = applyLedger(record, ledgerResult.state)
        if not committedRecord then return failure("recovery_quarantined", "record_" .. recordError) end
        committedRecord.observedPosition = reservation.targetPosition
        committed.perks[reservation.perkId] = committedRecord
    end
    committed.survivor.spent = reservation.preSpent + apCost
    committed.revision = reservation.preRevision + 1
    committed.inFlightAdvancement = nil
    local saved = saveState(deps.store, player, committed, "recovery_commit_failed")
    if not saved.ok then return failure("recovery_quarantined", detailOf(saved)) end

    return {
        ok = true,
        state = committed,
        recovered = true,
        requestId = reservation.requestId,
        perkId = reservation.perkId,
        revision = committed.revision,
        spent = committed.survivor.spent,
        availableAp = committed.survivor.level - committed.survivor.spent,
        apCost = apCost,
        mastered = mastered,
        addedTarget = addedTarget,
        clearedTargetIds = not free and mastered and ledgerResult.effect.clearedTargetIds or {},
        xpWriteInvoked = ensured.xpWriteInvoked,
        levelWriteInvoked = ensured.levelWriteInvoked,
    }
end

local function publicRecovery(result)
    if not result.ok then return result end
    if not result.recovered then return { ok = true, recovered = false } end
    return {
        ok = true,
        requestId = result.requestId,
        perkId = result.perkId,
        revision = result.revision,
        spent = result.spent,
        availableAp = result.availableAp,
        apCost = result.apCost,
        mastered = result.mastered,
        addedTarget = result.addedTarget,
        clearedTargetIds = result.clearedTargetIds,
        xpWriteInvoked = result.xpWriteInvoked,
        levelWriteInvoked = result.levelWriteInvoked,
        recovered = true,
    }
end

function ApTransaction.create(dependencies)
    if type(dependencies) ~= "table" then
        return failure("invalid_dependencies", "dependencies_required")
    end
    local store = dependencies.store or dependencies.PlayerStateStore
    local required = {
        { dependencies.NaturalLedger, { "baseline", "inspect", "reconcileExternal", "appendTarget", "master" }, "NaturalLedger" },
        { dependencies.SurvivorEconomy, { "availableAp" }, "SurvivorEconomy" },
        { dependencies.Allotment, { "evaluate" }, "Allotment" },
        { dependencies.MutationScope, { "begin", "finish" }, "MutationScope" },
        { store, { "load", "save" }, "PlayerStateStore" },
        { dependencies.ActualObservation, { "get", "set", "clearPlayer" }, "ActualObservation" },
        { dependencies.AccountingMode, { "synchronizeLoaded" }, "AccountingMode" },
    }
    for index = 1, #required do
        if not hasMethods(required[index][1], required[index][2]) then
            return failure("invalid_dependencies", required[index][3] .. "_invalid")
        end
    end
    if type(dependencies.resolver) ~= "table" or type(dependencies.resolver.resolve) ~= "function" then
        return failure("invalid_dependencies", "resolver_invalid")
    end
    if dependencies.resolver.loadOptions ~= nil and type(dependencies.resolver.loadOptions) ~= "table" then
        return failure("invalid_dependencies", "resolver_load_options_invalid")
    end

    local deps = {
        NaturalLedger = dependencies.NaturalLedger,
        SurvivorEconomy = dependencies.SurvivorEconomy,
        Allotment = dependencies.Allotment,
        MutationScope = dependencies.MutationScope,
        store = store,
        ActualObservation = dependencies.ActualObservation,
        AccountingMode = dependencies.AccountingMode,
        resolver = dependencies.resolver,
        loadOptions = dependencies.resolver.loadOptions,
    }
    local service = {}

    function service.recoverLoadedState(player, state)
        if type(state) ~= "table" then
            return failure("store_load_failed", "state_not_table")
        end
        return recoverLoaded(deps, player, state)
    end

    function service.recover(player)
        local loaded = loadState(deps.store, player, deps.loadOptions)
        if not loaded.ok then return loaded end
        return publicRecovery(service.recoverLoadedState(player, loaded.state))
    end

    function service.spend(player, request, allotmentConfig)
        if type(allotmentConfig) ~= "table"
            or (allotmentConfig.mode ~= "Global"
                and allotmentConfig.mode ~= "PerSkill"
                and allotmentConfig.mode ~= "Free") then
            return failure("allotment_invalid", "mode_invalid")
        end
        local loaded = loadState(deps.store, player, deps.loadOptions)
        if not loaded.ok then return loaded end
        local recovered = service.recoverLoadedState(player, loaded.state)
        if not recovered.ok then return recovered end
        local state = recovered.state

        local desiredMode = allotmentConfig.mode == "Free" and "Free" or "Tracked"
        local synchronized = synchronizeAccountingMode(deps, player, state, desiredMode)
        if not synchronized.ok then return synchronized end
        state = synchronized.state
        if synchronized.transitioned and synchronized.fromMode == "Free" then
            local reloaded = loadState(deps.store, player, deps.loadOptions)
            if not reloaded.ok then return reloaded end
            if reloaded.state.accountingMode ~= "Tracked"
                or reloaded.state.revision ~= state.revision then
                return failure("accounting_mode_failed", "tracked_reload_invalid")
            end
            state = reloaded.state
        end

        local requestValid = validateRequest(request)
        if not requestValid.ok then return requestValid end
        if (synchronized.transitioned == true or state.accountingMode == "Free")
            and request.expectedRevision ~= state.revision then
            return failure("stale_revision", "expected_revision_mismatch")
        end
        local resolved = resolveAdapter(deps.resolver, request.perkId)
        if not resolved.ok then return resolved end
        local described = describeAdapter(resolved.adapter, resolved.handle)
        if not described.ok then return described end
        local identity = described.identity
        local inspected = inspectAdapter(resolved.adapter, resolved.handle, player, identity)
        if not inspected.ok then return inspected end
        local actual = inspected.inspection

        if state.accountingMode == "Free" then
            local available = deps.SurvivorEconomy.availableAp(state.survivor)
            if type(available) ~= "table" or not available.ok then
                return failure("invalid_state", "survivor_" .. detailOf(available))
            end
            if available.availableAp < 1 then return failure("no_ap", "no_available_ap") end
            if not actual.levelAligned then return failure("misaligned_progression", actual.alignment or "unaligned") end
            if actual.storedLevel >= identity.effectiveMaximum then return failure("at_maximum", "effective_maximum") end
            local apCost = advancementCost(actual.nextTargetLevel, identity.effectiveMaximum)
            if available.availableAp < apCost then return failure("no_ap", "insufficient_ap_for_advancement") end
            local reservationState, stateError = cloneValue(state)
            if not reservationState then return failure("invalid_state", stateError) end
            local bounded = setPreservedFreeBoundary(
                reservationState,
                request.perkId,
                identity,
                actual.actualPosition
            )
            if not bounded.ok then return bounded end
            reservationState.inFlightAdvancement = {
                requestId = request.requestId,
                perkId = request.perkId,
                preRevision = state.revision,
                preSpent = state.survivor.spent,
                preLevel = actual.storedLevel,
                prePosition = actual.actualPosition,
                targetLevel = actual.nextTargetLevel,
                targetPosition = actual.nextTargetPosition,
                adapterId = identity.adapterId,
                adapterVersion = identity.adapterVersion,
                curveFingerprint = identity.curveFingerprint,
                effectiveMaximum = identity.effectiveMaximum,
            }
            local begun = beginScope(deps, player, request.perkId)
            if not begun.ok then return begun end
            local reserved = saveState(deps.store, player, reservationState, "reservation_save_failed")
            if not reserved.ok then
                local finished = finishScope(deps, begun.handle)
                if not finished.ok then return finished end
                return reserved
            end
            local ensured = performEnsureInScope(
                deps,
                player,
                request.perkId,
                resolved.adapter,
                resolved.handle,
                identity,
                actual.nextTargetLevel,
                actual.nextTargetPosition,
                begun.handle,
                false
            )
            if not ensured.ok then return ensured end

            local committed, commitError = cloneValue(reservationState)
            if not committed then return failure("commit_save_failed", commitError) end
            bounded = setPreservedFreeBoundary(
                committed,
                request.perkId,
                identity,
                actual.nextTargetPosition
            )
            if not bounded.ok then return failure("commit_save_failed", detailOf(bounded)) end
            committed.survivor.spent = state.survivor.spent + apCost
            committed.revision = state.revision + 1
            committed.inFlightAdvancement = nil
            local saved = saveState(deps.store, player, committed, "commit_save_failed")
            if not saved.ok then return saved end
            return {
                ok = true,
                requestId = request.requestId,
                perkId = request.perkId,
                revision = committed.revision,
                spent = committed.survivor.spent,
                availableAp = committed.survivor.level - committed.survivor.spent,
                apCost = apCost,
                mastered = apCost == 2,
                addedTarget = false,
                clearedTargetIds = {},
                xpWriteInvoked = ensured.xpWriteInvoked,
                levelWriteInvoked = ensured.levelWriteInvoked,
                recovered = recovered.recovered,
            }
        end

        local record = state.perks[request.perkId]
        if record ~= nil and not sameIdentity(record, identity) then
            return failure("perk_quarantined", "adapter_identity_mismatch")
        end
        local synchronized = synchronizeObservation(
            deps,
            player,
            request.perkId,
            state,
            record,
            actual.actualPosition
        )
        if not synchronized.ok then return synchronized end
        state = synchronized.state
        record = synchronized.record

        if request.expectedRevision ~= state.revision then
            return failure("stale_revision", "expected_revision_mismatch")
        end
        local available = deps.SurvivorEconomy.availableAp(state.survivor)
        if type(available) ~= "table" or not available.ok then
            return failure("invalid_state", "survivor_" .. detailOf(available))
        end
        if available.availableAp < 1 then return failure("no_ap", "no_available_ap") end
        if not actual.levelAligned then return failure("misaligned_progression", actual.alignment or "unaligned") end
        if actual.storedLevel >= identity.effectiveMaximum then return failure("at_maximum", "effective_maximum") end
        local apCost = advancementCost(actual.nextTargetLevel, identity.effectiveMaximum)
        local mastered = apCost == 2
        if available.availableAp < apCost then return failure("no_ap", "insufficient_ap_for_advancement") end

        if record == nil then
            local baseline = deps.NaturalLedger.baseline(actual.actualPosition)
            if type(baseline) ~= "table" or not baseline.ok then
                return failure("perk_quarantined", "baseline_" .. detailOf(baseline))
            end
            record = perkFromBaseline(identity, baseline.state)
        end
        local ledgerInspection = deps.NaturalLedger.inspect(ledgerFromPerk(record))
        if type(ledgerInspection) ~= "table" or not ledgerInspection.ok then
            return failure("perk_quarantined", "ledger_" .. detailOf(ledgerInspection))
        end
        if ledgerInspection.red then return failure("red_recovery", "natural_recovery_required") end

        local ledgerResult
        if mastered then
            ledgerResult = deps.NaturalLedger.master(ledgerFromPerk(record), actual.nextTargetPosition)
        else
            ledgerResult = deps.NaturalLedger.appendTarget(ledgerFromPerk(record), {
                targetId = durableTargetId(request.requestId, state.revision),
                targetLevel = actual.nextTargetLevel,
                targetPosition = actual.nextTargetPosition,
            }, identity.effectiveMaximum)
        end
        if type(ledgerResult) ~= "table" or not ledgerResult.ok then
            return failure("target_rejected", detailOf(ledgerResult))
        end
        local addedTarget = not mastered and ledgerResult.added or false
        local active, activeError = activeByPerk(state)
        if activeError then return activeError end
        local allotment = deps.Allotment.evaluate(
            allotmentConfig,
            request.perkId,
            active,
            addedTarget,
            mastered and 2 or nil
        )
        if type(allotment) ~= "table" or not allotment.ok then
            return failure("allotment_invalid", detailOf(allotment))
        end
        if not allotment.allowed then return failure("allotment_rejected", "capacity_reached") end
        if mastered and not allotment.spendingEnabled then return failure("allotment_rejected", "spending_disabled") end

        local reservationState, stateError = cloneValue(state)
        if not reservationState then return failure("invalid_state", stateError) end
        reservationState.perks[request.perkId] = record
        reservationState.inFlightAdvancement = {
            requestId = request.requestId,
            perkId = request.perkId,
            preRevision = state.revision,
            preSpent = state.survivor.spent,
            preLevel = actual.storedLevel,
            prePosition = actual.actualPosition,
            targetLevel = actual.nextTargetLevel,
            targetPosition = actual.nextTargetPosition,
            adapterId = identity.adapterId,
            adapterVersion = identity.adapterVersion,
            curveFingerprint = identity.curveFingerprint,
            effectiveMaximum = identity.effectiveMaximum,
        }
        local begun = beginScope(deps, player, request.perkId)
        if not begun.ok then return begun end
        local reserved = saveState(deps.store, player, reservationState, "reservation_save_failed")
        if not reserved.ok then
            local finished = finishScope(deps, begun.handle)
            if not finished.ok then return finished end
            return reserved
        end

        local ensured = performEnsureInScope(
            deps,
            player,
            request.perkId,
            resolved.adapter,
            resolved.handle,
            identity,
            actual.nextTargetLevel,
            actual.nextTargetPosition,
            begun.handle,
            true
        )
        if not ensured.ok then return ensured end

        local committed, commitError = cloneValue(reservationState)
        if not committed then return failure("commit_save_failed", commitError) end
        local committedRecord, recordError = applyLedger(record, ledgerResult.state)
        if not committedRecord then return failure("commit_save_failed", recordError) end
        committedRecord.observedPosition = actual.nextTargetPosition
        committed.perks[request.perkId] = committedRecord
        committed.survivor.spent = state.survivor.spent + apCost
        committed.revision = state.revision + 1
        committed.inFlightAdvancement = nil
        local saved = saveState(deps.store, player, committed, "commit_save_failed")
        if not saved.ok then return saved end

        return {
            ok = true,
            requestId = request.requestId,
            perkId = request.perkId,
            revision = committed.revision,
            spent = committed.survivor.spent,
            availableAp = committed.survivor.level - committed.survivor.spent,
            apCost = apCost,
            mastered = mastered,
            addedTarget = addedTarget,
            clearedTargetIds = mastered and ledgerResult.effect.clearedTargetIds or {},
            xpWriteInvoked = ensured.xpWriteInvoked,
            levelWriteInvoked = ensured.levelWriteInvoked,
            recovered = recovered.recovered,
        }
    end

    return { ok = true, service = service }
end

return ApTransaction
