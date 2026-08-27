local SupportedAwardProcessor = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isInteger(value)
    return isFinite(value) and value == math.floor(value)
end

local function isSafeId(value)
    return type(value) == "string" and value:match("^[%w%._:%-]+$") ~= nil
end

local function hasMethods(value, names)
    if type(value) ~= "table" then return false end
    for index = 1, #names do
        if type(value[names[index]]) ~= "function" then return false end
    end
    return true
end

local function detailOf(result)
    if type(result) ~= "table" then return "not_result" end
    local code = result.code and tostring(result.code) or "failed"
    local detail = result.detail and tostring(result.detail) or "no_detail"
    return code .. ":" .. detail
end

local function callResult(method, label, ...)
    local ok, result = pcall(method, ...)
    if not ok then return failure(label .. "_error", "dependency_threw") end
    if type(result) ~= "table" then return failure(label .. "_invalid", "not_result") end
    return result
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

local function validateAward(award)
    if type(award) ~= "table" then return failure("invalid_award", "award_not_table") end
    local allowed = {
        perkId = true,
        survivorCreditBase = true,
        appliedDelta = true,
        actualPositionBefore = true,
        actualPositionAfter = true,
        effectiveDelta = true,
    }
    for key in pairs(award) do
        if not allowed[key] then
            return failure("invalid_award", "unexpected_field:" .. tostring(key))
        end
    end
    if not isSafeId(award.perkId) then return failure("invalid_award", "perkId") end
    if not isFinite(award.survivorCreditBase) or award.survivorCreditBase < 0 then
        return failure("invalid_award", "survivorCreditBase")
    end
    if not isFinite(award.appliedDelta) then return failure("invalid_award", "appliedDelta") end
    if not isFinite(award.actualPositionBefore) or award.actualPositionBefore < 0 then
        return failure("invalid_award", "actualPositionBefore")
    end
    if not isFinite(award.actualPositionAfter) or award.actualPositionAfter < 0 then
        return failure("invalid_award", "actualPositionAfter")
    end
    if award.effectiveDelta ~= nil
        and (not isFinite(award.effectiveDelta) or award.effectiveDelta < 0) then
        return failure("invalid_award", "effectiveDelta")
    end
    if award.survivorCreditBase > 0 and award.appliedDelta < 0 then
        return failure("invalid_award", "positive_base_negative_movement")
    end
    return { ok = true }
end

local function validateSettings(settings)
    if type(settings) ~= "table" then return failure("invalid_settings", "settings_not_table") end
    for key in pairs(settings) do
        if key ~= "accountingMode" and key ~= "normalization" and key ~= "survivorMultiplier" and key ~= "postMax" then
            return failure("invalid_settings", "unexpected_field:" .. tostring(key))
        end
    end
    if settings.accountingMode ~= "Tracked" and settings.accountingMode ~= "Free" then
        return failure("invalid_settings", "accountingMode")
    end
    if not isFinite(settings.normalization) or settings.normalization < 0 then
        return failure("invalid_settings", "normalization")
    end
    if not isFinite(settings.survivorMultiplier) or settings.survivorMultiplier < 0 then
        return failure("invalid_settings", "survivorMultiplier")
    end
    local postMax = settings.postMax
    if type(postMax) ~= "table" or type(postMax.enabled) ~= "boolean" then
        return failure("invalid_settings", "postMax_enabled")
    end
    if postMax.enabled and (
        not isFinite(postMax.fullRateAllowance)
        or postMax.fullRateAllowance < 0
        or not isFinite(postMax.diminishedRate)
        or postMax.diminishedRate < 0
        or postMax.diminishedRate > 1
    ) then
        return failure("invalid_settings", "postMax_values")
    end
    return { ok = true }
end

local function resolveAdapter(resolver, perkId)
    local resolved = callResult(resolver.resolve, "resolver", perkId)
    if not resolved.ok then return failure("resolver_failed", detailOf(resolved)) end
    if not hasMethods(resolved.adapter, { "describe", "inspect" }) or type(resolved.handle) ~= "table" then
        return failure("resolver_failed", "adapter_and_handle_required")
    end
    return { ok = true, adapter = resolved.adapter, handle = resolved.handle }
end

local function describeAdapter(adapter, handle)
    local described = callResult(adapter.describe, "adapter_describe", handle)
    if not described.ok then return failure("adapter_description_failed", detailOf(described)) end
    if not isSafeId(described.adapterId)
        or not isInteger(described.adapterVersion)
        or described.adapterVersion < 0
        or not isSafeId(described.curveFingerprint)
        or not isInteger(described.effectiveMaximum)
        or described.effectiveMaximum <= 0 then
        return failure("adapter_description_failed", "identity_invalid")
    end
    if type(described.cumulativeThresholds) ~= "table" then
        return failure("adapter_description_failed", "cumulative_thresholds_required")
    end
    local maximumPosition = described.cumulativeThresholds[described.effectiveMaximum]
    if not isFinite(maximumPosition) or maximumPosition <= 0 then
        return failure("adapter_description_failed", "maximum_position_invalid")
    end
    return {
        ok = true,
        identity = {
            adapterId = described.adapterId,
            adapterVersion = described.adapterVersion,
            curveFingerprint = described.curveFingerprint,
            effectiveMaximum = described.effectiveMaximum,
        },
        maximumPosition = maximumPosition,
    }
end

local function inspectAdapter(adapter, handle, player, identity)
    local inspected = callResult(adapter.inspect, "adapter_inspect", handle, player)
    if not inspected.ok then return failure("adapter_inspection_failed", detailOf(inspected)) end
    if not isInteger(inspected.storedLevel)
        or inspected.storedLevel < 0
        or not isFinite(inspected.actualPosition)
        or inspected.actualPosition < 0
        or not isInteger(inspected.effectiveMaximum)
        or inspected.effectiveMaximum <= 0
        or type(inspected.levelAligned) ~= "boolean" then
        return failure("adapter_inspection_failed", "mapping_invalid")
    end
    if inspected.storedLevel > identity.effectiveMaximum
        or inspected.effectiveMaximum ~= identity.effectiveMaximum
        or (inspected.adapterId ~= nil and inspected.adapterId ~= identity.adapterId)
        or (inspected.adapterVersion ~= nil and inspected.adapterVersion ~= identity.adapterVersion)
        or (inspected.curveFingerprint ~= nil and inspected.curveFingerprint ~= identity.curveFingerprint) then
        return failure("adapter_identity_mismatch", "inspection_identity_changed")
    end
    return { ok = true, inspection = inspected }
end

local function sameIdentity(record, identity)
    return type(record) == "table"
        and record.adapterId == identity.adapterId
        and record.adapterVersion == identity.adapterVersion
        and record.curveFingerprint == identity.curveFingerprint
        and record.effectiveMaximum == identity.effectiveMaximum
end

local function ledgerFromPerk(record)
    return {
        naturalPosition = record.naturalPosition,
        highWaterPosition = record.highWaterPosition,
        activeTargets = record.activeTargets,
    }
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

local function loadState(store, player, options)
    local loaded = callResult(store.load, "store_load", player, options)
    if not loaded.ok or type(loaded.state) ~= "table" then
        return failure("store_load_failed", detailOf(loaded))
    end
    local state = loaded.state
    if type(state.perks) ~= "table" or type(state.survivor) ~= "table" or not isInteger(state.revision) or state.revision < 0 then
        return failure("store_load_failed", "state_shape_invalid")
    end
    return { ok = true, state = state }
end

local function saveState(store, player, state)
    local saved = callResult(store.save, "store_save", player, state)
    if not saved.ok then return failure("award_save_failed", detailOf(saved)) end
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

local function getObservation(observation, player, perkId)
    local observed = callResult(observation.get, "observation_get", player, perkId)
    if not observed.ok then return failure("observation_failed", detailOf(observed)) end
    if type(observed.present) ~= "boolean" then
        return failure("observation_failed", "present_boolean_required")
    end
    if observed.present and (not isFinite(observed.position) or observed.position < 0) then
        return failure("observation_failed", "position_invalid")
    end
    return observed
end

local function setObservation(observation, player, perkId, position)
    local observed = callResult(observation.set, "observation_set", player, perkId, position)
    if not observed.ok then return failure("observation_failed", detailOf(observed)) end
    return { ok = true }
end

local function appendCleared(destination, source)
    if type(source) ~= "table" then return false end
    for index = 1, #source do
        destination[#destination + 1] = source[index]
    end
    return true
end

local function zeroAward()
    return { eligibleBase = 0, normalizedBase = 0, survivorXp = 0 }
end

local function computeAward(deps, survivorCreditBase, settings, ratio, multiplier)
    if ratio == 0 or survivorCreditBase <= 0 then return { ok = true, award = zeroAward() } end
    if settings.normalization == 0 then return { ok = true, award = zeroAward() } end
    local computed = deps.SurvivorEconomy.computeAward(
        survivorCreditBase,
        settings.normalization,
        multiplier,
        ratio
    )
    if type(computed) ~= "table" or not computed.ok then
        return failure("award_math_failed", detailOf(computed))
    end
    return { ok = true, award = computed }
end

local function processOrdinary(deps, record, award, settings)
    if award.actualPositionAfter - award.actualPositionBefore ~= award.appliedDelta then
        return failure("invalid_award", "applied_delta_position_mismatch")
    end
    local transitioned = deps.NaturalLedger.applySupported(
        ledgerFromPerk(record),
        award.appliedDelta,
        award.actualPositionAfter
    )
    if type(transitioned) ~= "table" or not transitioned.ok then
        return failure("perk_quarantined", "supported_transition_" .. detailOf(transitioned))
    end
    local nextRecord, recordError = applyLedger(record, transitioned.state)
    if not nextRecord then return failure("perk_quarantined", "record_" .. recordError) end
    local ratio = 0
    if award.survivorCreditBase > 0 then ratio = transitioned.effect.eligibleRatio end
    local natural = computeAward(deps, award.survivorCreditBase, settings, ratio, settings.survivorMultiplier)
    if not natural.ok then return natural end
    return {
        ok = true,
        record = nextRecord,
        naturalAward = natural.award,
        postMaxAward = zeroAward(),
        postMaxXp = 0,
        recoveryApplied = transitioned.effect.recoveryApplied,
        clearedTargetIds = transitioned.effect.clearedTargetIds,
        changed = award.appliedDelta ~= 0,
    }
end

local function processAtMaximum(deps, record, award, settings, maximumPosition)
    if award.actualPositionAfter ~= maximumPosition then
        return failure("invalid_award", "maximum_award_position_changed")
    end
    local inspected = deps.NaturalLedger.inspect(ledgerFromPerk(record))
    if type(inspected) ~= "table" or not inspected.ok then
        return failure("perk_quarantined", "ledger_inspection_" .. detailOf(inspected))
    end

    local nextRecord = record
    local naturalRatio = 0
    local postMaxRatio = 0
    local recoveryApplied = 0
    local clearedTargetIds = {}
    local changed = false
    if not inspected.red and inspected.activeCount == 0 then
        postMaxRatio = 1
    else
        if award.effectiveDelta == nil then
            return failure("invalid_award", "effectiveDelta_required")
        end
        if record.naturalPosition > maximumPosition or record.highWaterPosition > maximumPosition then
            return failure("perk_quarantined", "ledger_above_maximum")
        end
        if award.effectiveDelta > 0 then
            local movement = math.min(award.effectiveDelta, maximumPosition - record.naturalPosition)
            local transitionPosition = award.actualPositionAfter
            if inspected.activeCount == 0 then
                transitionPosition = record.naturalPosition + movement
            end
            local transitioned = deps.NaturalLedger.applySupported(
                ledgerFromPerk(record),
                movement,
                transitionPosition
            )
            if type(transitioned) ~= "table" or not transitioned.ok then
                return failure("perk_quarantined", "maximum_transition_" .. detailOf(transitioned))
            end
            local recordError
            nextRecord, recordError = applyLedger(record, transitioned.state)
            if not nextRecord then return failure("perk_quarantined", "record_" .. recordError) end
            recoveryApplied = transitioned.effect.recoveryApplied
            naturalRatio = transitioned.effect.eligibleApplied / award.effectiveDelta
            postMaxRatio = (award.effectiveDelta - movement) / award.effectiveDelta
            clearedTargetIds = transitioned.effect.clearedTargetIds
            changed = movement ~= 0
        end
    end

    local natural = computeAward(deps, award.survivorCreditBase, settings, naturalRatio, settings.survivorMultiplier)
    if not natural.ok then return natural end
    local postMax = computeAward(deps, award.survivorCreditBase, settings, postMaxRatio, 1)
    if not postMax.ok then return postMax end

    local postMaxApplied = { state = { fullRateUsed = nextRecord.postMaxFullRateUsed }, effect = { survivorXp = 0 } }
    if postMax.award.normalizedBase > 0 then
        postMaxApplied = deps.PostMax.apply(
            { fullRateUsed = nextRecord.postMaxFullRateUsed },
            postMax.award.normalizedBase,
            settings.survivorMultiplier,
            settings.postMax
        )
        if type(postMaxApplied) ~= "table" or not postMaxApplied.ok then
            return failure("postmax_failed", detailOf(postMaxApplied))
        end
        if postMaxApplied.state.fullRateUsed ~= nextRecord.postMaxFullRateUsed then
            local copy, copyError = cloneValue(nextRecord)
            if not copy then return failure("perk_quarantined", "record_" .. copyError) end
            nextRecord = copy
            nextRecord.postMaxFullRateUsed = postMaxApplied.state.fullRateUsed
            changed = true
        end
    end

    return {
        ok = true,
        record = nextRecord,
        naturalAward = natural.award,
        postMaxAward = postMax.award,
        postMaxXp = postMaxApplied.effect.survivorXp,
        recoveryApplied = recoveryApplied,
        clearedTargetIds = clearedTargetIds,
        changed = changed,
    }
end

function SupportedAwardProcessor.create(dependencies)
    if type(dependencies) ~= "table" then
        return failure("invalid_dependencies", "dependencies_required")
    end
    local store = dependencies.store or dependencies.PlayerStateStore
    local required = {
        { dependencies.NaturalLedger, { "baseline", "inspect", "applySupported", "reconcileExternal" }, "NaturalLedger" },
        { dependencies.SurvivorEconomy, { "computeAward", "applyXp" }, "SurvivorEconomy" },
        { dependencies.PostMax, { "apply" }, "PostMax" },
        { dependencies.MutationScope, { "isActive" }, "MutationScope" },
        { store, { "load", "save" }, "PlayerStateStore" },
        { dependencies.ActualObservation, { "get", "set" }, "ActualObservation" },
        { dependencies.recoveryService, { "recoverLoadedState" }, "recoveryService" },
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
        PostMax = dependencies.PostMax,
        MutationScope = dependencies.MutationScope,
        store = store,
        ActualObservation = dependencies.ActualObservation,
        resolver = dependencies.resolver,
        loadOptions = dependencies.resolver.loadOptions,
        recoveryService = dependencies.recoveryService,
        AccountingMode = dependencies.AccountingMode,
    }
    local service = {}

    function service.process(player, award, settings)
        local perkId = type(award) == "table" and award.perkId or nil
        local scopeOk, activeOrError = pcall(deps.MutationScope.isActive, player, perkId)
        if not scopeOk then return failure("scope_check_failed", "dependency_threw") end
        if activeOrError == true then
            return { ok = true, ignoredInternal = true, stateWritten = false }
        end
        if activeOrError ~= false then return failure("scope_check_failed", "boolean_required") end
        if player == nil then return failure("invalid_player", "player_required") end

        local awardValid = validateAward(award)
        if not awardValid.ok then return awardValid end
        local settingsValid = validateSettings(settings)
        if not settingsValid.ok then return settingsValid end

        local loaded = loadState(deps.store, player, deps.loadOptions)
        if not loaded.ok then return loaded end
        local recovered = callResult(
            deps.recoveryService.recoverLoadedState,
            "recovery",
            player,
            loaded.state
        )
        if not recovered.ok then
            return failure("recovery_failed", detailOf(recovered))
        end
        local state = recovered.state
        if type(state) ~= "table"
            or type(state.perks) ~= "table"
            or type(state.survivor) ~= "table"
            or not isInteger(state.revision)
            or state.revision < 0 then
            return failure("recovery_failed", "state_shape_invalid")
        end
        local synchronized = synchronizeAccountingMode(deps, player, state, settings.accountingMode)
        if not synchronized.ok then return synchronized end
        state = synchronized.state
        if type(state.perks) ~= "table"
            or type(state.survivor) ~= "table"
            or not isInteger(state.revision)
            or state.revision < 0 then
            return failure("accounting_mode_failed", "state_shape_invalid")
        end
        local originalRevision = state.revision
        local alreadyWritten = recovered.recovered == true or synchronized.transitioned == true

        if state.accountingMode == "Free" then
            if award.actualPositionAfter - award.actualPositionBefore ~= award.appliedDelta then
                return failure("invalid_award", "applied_delta_position_mismatch")
            end
            local computed = { ok = true, award = zeroAward() }
            if award.appliedDelta > 0 and award.survivorCreditBase > 0 then
                computed = computeAward(deps, award.survivorCreditBase, settings, 1, settings.survivorMultiplier)
            end
            if not computed.ok then return computed end
            local survivorXp = computed.award.survivorXp
            local applied = deps.SurvivorEconomy.applyXp(state.survivor, survivorXp)
            if type(applied) ~= "table" or not applied.ok then
                return failure("survivor_transition_failed", detailOf(applied))
            end
            local stateChanged = applied.state.level ~= state.survivor.level
                or applied.state.xpIntoLevel ~= state.survivor.xpIntoLevel
                or applied.state.spent ~= state.survivor.spent
            state.survivor = applied.state
            if state.revision ~= originalRevision then
                return failure("invalid_state", "revision_changed_during_award")
            end
            if stateChanged then
                local saved = saveState(deps.store, player, state)
                if not saved.ok then return saved end
            end
            return {
                ok = true,
                survivorXp = survivorXp,
                levelsGained = applied.effects.levelsGained,
                apGained = applied.effects.apGained,
                recoveryApplied = 0,
                naturalEligibleBase = computed.award.eligibleBase,
                postMaxBase = 0,
                postMaxXp = 0,
                clearedTargetIds = {},
                stateWritten = alreadyWritten or stateChanged,
            }
        end

        local resolved = resolveAdapter(deps.resolver, award.perkId)
        if not resolved.ok then return resolved end
        local described = describeAdapter(resolved.adapter, resolved.handle)
        if not described.ok then return described end
        local identity = described.identity
        local maximumPosition = described.maximumPosition
        local inspected = inspectAdapter(resolved.adapter, resolved.handle, player, identity)
        if not inspected.ok then return inspected end
        if inspected.inspection.actualPosition ~= award.actualPositionAfter then
            return failure("adapter_inspection_failed", "actual_position_mismatch")
        end
        if award.actualPositionBefore > maximumPosition or award.actualPositionAfter > maximumPosition then
            return failure("adapter_inspection_failed", "position_above_maximum")
        end

        local record = state.perks[award.perkId]
        if record ~= nil and not sameIdentity(record, identity) then
            return failure("perk_quarantined", "adapter_identity_mismatch")
        end

        local observed = getObservation(deps.ActualObservation, player, award.perkId)
        if not observed.ok then return observed end
        local stateChanged = false
        local clearedTargetIds = {}
        if record ~= nil and observed.present and observed.position ~= award.actualPositionBefore then
            local reconciled = deps.NaturalLedger.reconcileExternal(
                ledgerFromPerk(record),
                award.actualPositionBefore - observed.position,
                award.actualPositionBefore
            )
            if type(reconciled) ~= "table" or not reconciled.ok then
                return failure("perk_quarantined", "reconciliation_" .. detailOf(reconciled))
            end
            local recordError
            record, recordError = applyLedger(record, reconciled.state)
            if not record then return failure("perk_quarantined", "record_" .. recordError) end
            appendCleared(clearedTargetIds, reconciled.effect.clearedTargetIds)
            state.perks[award.perkId] = record
            stateChanged = true
        end

        if record == nil then
            local baseline = deps.NaturalLedger.baseline(award.actualPositionBefore)
            if type(baseline) ~= "table" or not baseline.ok then
                return failure("perk_quarantined", "baseline_" .. detailOf(baseline))
            end
            record = perkFromBaseline(identity, baseline.state)
            state.perks[award.perkId] = record
            stateChanged = true
        end

        local accounting
        if award.actualPositionBefore == maximumPosition
            and award.actualPositionAfter == maximumPosition then
            if inspected.inspection.storedLevel ~= identity.effectiveMaximum then
                return failure("adapter_inspection_failed", "maximum_level_not_reached")
            end
            accounting = processAtMaximum(deps, record, award, settings, maximumPosition)
        else
            accounting = processOrdinary(deps, record, award, settings)
        end
        if not accounting.ok then return accounting end
        appendCleared(clearedTargetIds, accounting.clearedTargetIds)
        state.perks[award.perkId] = accounting.record
        stateChanged = stateChanged or accounting.changed

        local survivorXp = accounting.naturalAward.survivorXp + accounting.postMaxXp
        if not isFinite(survivorXp) or survivorXp < 0 then
            return failure("award_math_failed", "survivor_xp_invalid")
        end
        local applied = deps.SurvivorEconomy.applyXp(state.survivor, survivorXp)
        if type(applied) ~= "table" or not applied.ok then
            return failure("survivor_transition_failed", detailOf(applied))
        end
        if applied.state.level ~= state.survivor.level
            or applied.state.xpIntoLevel ~= state.survivor.xpIntoLevel
            or applied.state.spent ~= state.survivor.spent then
            stateChanged = true
        end
        state.survivor = applied.state
        if state.revision ~= originalRevision then
            return failure("invalid_state", "revision_changed_during_award")
        end

        if stateChanged then
            local saved = saveState(deps.store, player, state)
            if not saved.ok then return saved end
        end
        local observationSet = setObservation(
            deps.ActualObservation,
            player,
            award.perkId,
            award.actualPositionAfter
        )
        if not observationSet.ok then return observationSet end

        return {
            ok = true,
            survivorXp = survivorXp,
            levelsGained = applied.effects.levelsGained,
            apGained = applied.effects.apGained,
            recoveryApplied = accounting.recoveryApplied,
            naturalEligibleBase = accounting.naturalAward.eligibleBase,
            postMaxBase = accounting.postMaxAward.eligibleBase,
            postMaxXp = accounting.postMaxXp,
            clearedTargetIds = clearedTargetIds,
            stateWritten = alreadyWritten or stateChanged,
        }
    end

    return { ok = true, service = service }
end

return SupportedAwardProcessor
