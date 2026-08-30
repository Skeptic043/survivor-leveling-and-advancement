local EventDerivedXpSource = {}

local RELOAD_SENTINEL_KEY = "__SLA_EventDerivedXpSource_42_20_v1_7F2C9D4A"
local RELOAD_SENTINEL_SIGNATURE = "sla.event-derived-xp-source/42.20/v1/7f2c9d4a"
local MAX_HANDLER_DIAGNOSTIC_CODE_LENGTH = 64
local MAX_HANDLER_DIAGNOSTIC_DETAIL_LENGTH = 160
local GENERIC_HANDLER_DIAGNOSTIC = "unavailable"
local ambiguousEvents = setmetatable({}, { __mode = "k" })

local function result(ok, code, detail)
    return { ok = ok, code = code, detail = detail }
end

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isPosition(value)
    return isFinite(value) and value >= 0
end

local function isSafePerkId(value)
    return type(value) == "string" and value:match("^[%w%._:%-]+$") ~= nil
end

local function isSafeHandlerDiagnosticCode(value)
    return type(value) == "string"
        and #value > 0
        and #value <= MAX_HANDLER_DIAGNOSTIC_CODE_LENGTH
        and value:match("^[%w%._:%-]+$") ~= nil
end

local function isSafeHandlerDiagnosticDetail(value)
    return type(value) == "string"
        and #value > 0
        and #value <= MAX_HANDLER_DIAGNOSTIC_DETAIL_LENGTH
        and value:find("[%c]") == nil
end

local function safeHandlerDiagnosticCode(value)
    if isSafeHandlerDiagnosticCode(value) then
        return value
    end
    return GENERIC_HANDLER_DIAGNOSTIC
end

local function safeHandlerDiagnosticDetail(value)
    if isSafeHandlerDiagnosticDetail(value) then
        return value
    end
    return GENERIC_HANDLER_DIAGNOSTIC
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local function callSafely(callable, ...)
    return pack(pcall(callable, ...))
end

local function isEmpty(map)
    for _ in pairs(map) do
        return false
    end
    return true
end

local function ownerFromReloadSentinel(sentinel)
    if type(sentinel) == "table"
        and sentinel.signature == RELOAD_SENTINEL_SIGNATURE
        and type(sentinel.owner) == "table"
        and type(sentinel.owner.install) == "function"
        and type(sentinel.owner.verifyOwnership) == "function" then
        return sentinel.owner
    end
    return nil
end

local function validateDependencies(dependencies)
    if type(dependencies) ~= "table" then
        return nil, result(false, "invalid_dependencies", "dependencies")
    end
    if type(dependencies.environment) ~= "table"
        or type(dependencies.environment.globals) ~= "table" then
        return nil, result(false, "invalid_dependencies", "environment.globals")
    end
    if type(dependencies.authority) ~= "table"
        or type(dependencies.authority.describe) ~= "function" then
        return nil, result(false, "invalid_dependencies", "authority.describe")
    end
    if type(dependencies.playerIdentity) ~= "table"
        or type(dependencies.playerIdentity.isPlayer) ~= "function" then
        return nil, result(false, "invalid_dependencies", "playerIdentity.isPlayer")
    end
    if type(dependencies.perkIdentity) ~= "table"
        or type(dependencies.perkIdentity.resolve) ~= "function" then
        return nil, result(false, "invalid_dependencies", "perkIdentity.resolve")
    end
    if type(dependencies.positionReader) ~= "table"
        or type(dependencies.positionReader.read) ~= "function" then
        return nil, result(false, "invalid_dependencies", "positionReader.read")
    end
    if type(dependencies.positionArithmetic) ~= "table"
        or type(dependencies.positionArithmetic.add) ~= "function" then
        return nil, result(false, "invalid_dependencies", "positionArithmetic.add")
    end
    if type(dependencies.sandboxMultiplier) ~= "table"
        or type(dependencies.sandboxMultiplier.resolve) ~= "function" then
        return nil, result(false, "invalid_dependencies", "sandboxMultiplier.resolve")
    end
    if type(dependencies.mutationScope) ~= "table"
        or type(dependencies.mutationScope.isActive) ~= "function" then
        return nil, result(false, "invalid_dependencies", "mutationScope.isActive")
    end
    if type(dependencies.awardHandler) ~= "table"
        or type(dependencies.awardHandler.process) ~= "function" then
        return nil, result(false, "invalid_dependencies", "awardHandler.process")
    end
    return {
        globals = dependencies.environment.globals,
        describeAuthority = dependencies.authority.describe,
        isPlayer = dependencies.playerIdentity.isPlayer,
        resolvePerk = dependencies.perkIdentity.resolve,
        readPosition = dependencies.positionReader.read,
        addPosition = dependencies.positionArithmetic.add,
        resolveSandboxMultiplier = dependencies.sandboxMultiplier.resolve,
        isMutationActive = dependencies.mutationScope.isActive,
        processAward = dependencies.awardHandler.process,
    }, nil
end

function EventDerivedXpSource.create(dependencies)
    local validated, failure = validateDependencies(dependencies)
    if not validated then
        return nil, failure
    end

    local globals = validated.globals
    local initialEvents = globals.Events
    local initialAddXpEvent = type(initialEvents) == "table" and initialEvents.AddXP or nil
    local globalsSentinel = globals[RELOAD_SENTINEL_KEY]
    local eventSentinel = type(initialAddXpEvent) == "table"
        and initialAddXpEvent[RELOAD_SENTINEL_KEY] or nil
    local globalsOwner = ownerFromReloadSentinel(globalsSentinel)
    local eventOwner = ownerFromReloadSentinel(eventSentinel)
    if globalsOwner and eventOwner
        and (globalsOwner ~= eventOwner or globalsSentinel ~= eventSentinel) then
        return nil, result(false, "reload_registry_conflict", nil)
    end
    local existingOwner = globalsOwner or eventOwner
    if existingOwner then
        return existingOwner, nil
    end
    if globalsSentinel ~= nil or eventSentinel ~= nil then
        return nil, result(false, "reload_registry_collision", nil)
    end

    local cursors = setmetatable({}, { __mode = "k" })
    local handleIds = setmetatable({}, { __mode = "k" })
    local handlerScopes = setmetatable({}, { __mode = "k" })
    local routeFrames = {}
    local installed = false
    local capturing = false
    local observerState = "not_attempted"
    local cleanupState = "not_attempted"
    local cleanupAttempted = false
    local registrationAddXpEvent = nil
    local registrationRemove = nil
    local anchorAddXpEvent = type(initialAddXpEvent) == "table" and initialAddXpEvent or nil
    local priorAddXp = nil
    local priorAddXpNoMultiplier = nil
    local wrappedAddXp = nil
    local wrappedAddXpNoMultiplier = nil
    local ownershipReason = nil
    local lastCode = "created"
    local lastFailure = nil
    local instance = {}
    -- Dual anchors let a fresh source chunk find the owner after one anchor is lost.
    local reloadSentinel = {
        signature = RELOAD_SENTINEL_SIGNATURE,
        owner = instance,
    }
    globals[RELOAD_SENTINEL_KEY] = reloadSentinel
    if anchorAddXpEvent then
        anchorAddXpEvent[RELOAD_SENTINEL_KEY] = reloadSentinel
    end

    local function setLast(code)
        lastCode = code
    end

    local function setHandlerFailure(code, handlerAnswer)
        local handlerCode = nil
        local handlerDetail = nil
        if type(handlerAnswer) == "table" then
            handlerCode = rawget(handlerAnswer, "code")
            handlerDetail = rawget(handlerAnswer, "detail")
        end
        lastFailure = {
            code = code,
            detail = {
                code = safeHandlerDiagnosticCode(handlerCode),
                detail = safeHandlerDiagnosticDetail(handlerDetail),
            },
        }
    end

    local function mapFor(root, player, create)
        local map = root[player]
        if not map and create then
            map = {}
            root[player] = map
        end
        return map
    end

    local function playerIsEligible(player)
        local called = callSafely(validated.isPlayer, player)
        if not called[1] then
            return false, "player_identity_threw"
        end
        if type(called[2]) ~= "boolean" then
            return false, "player_identity_failed"
        end
        if not called[2] then
            return false, "non_player_owner"
        end
        return true, nil
    end

    local function authoritativeNow()
        local called = callSafely(validated.describeAuthority)
        if not called[1] then
            return false, "authority_threw"
        end
        local answer = called[2]
        if type(answer) ~= "table" or answer.ok ~= true
            or type(answer.authoritative) ~= "boolean" then
            return false, "authority_failed"
        end
        if not answer.authoritative then
            return false, "non_authoritative"
        end
        return true, nil
    end

    local function resolve(perk)
        local called = callSafely(validated.resolvePerk, perk)
        if not called[1] then
            return nil, "identity_threw"
        end
        local answer = called[2]
        if type(answer) ~= "table" or answer.ok ~= true
            or not isSafePerkId(answer.perkId) then
            return nil, "identity_failed"
        end
        return answer.perkId, nil
    end

    local function read(player, perkId, phase)
        local called = callSafely(validated.readPosition, player, perkId)
        if not called[1] then
            return nil, phase .. "_position_threw"
        end
        local answer = called[2]
        if type(answer) ~= "table" or answer.ok ~= true
            or not isPosition(answer.position) then
            return nil, phase .. "_position_failed"
        end
        return answer.position, nil
    end

    local function sandboxDivisor(player, perkId)
        local called = callSafely(validated.resolveSandboxMultiplier, player, perkId)
        if not called[1] then
            return nil, "sandbox_multiplier_threw"
        end
        local answer = called[2]
        local divisor = answer
        if type(answer) == "table" and answer.ok == true then
            divisor = answer.multiplier
            if divisor == nil then
                divisor = answer.divisor
            end
        end
        if not isFinite(divisor) or divisor <= 0 then
            return nil, "sandbox_multiplier_failed"
        end
        return divisor, nil
    end

    local function mutationIsActive(player, perkId)
        local scopeMap = handlerScopes[player]
        local handlerActive = scopeMap and (scopeMap[perkId] or 0) > 0 or false
        local called = callSafely(validated.isMutationActive, player, perkId)
        if not called[1] then
            return nil, "mutation_scope_threw"
        end
        if type(called[2]) ~= "boolean" then
            return nil, "mutation_scope_failed"
        end
        return handlerActive or called[2], nil
    end

    local function pushHandlerScope(player, perkId)
        local scopeMap = mapFor(handlerScopes, player, true)
        scopeMap[perkId] = (scopeMap[perkId] or 0) + 1
    end

    local function popHandlerScope(player, perkId)
        local scopeMap = handlerScopes[player]
        if not scopeMap then
            return
        end
        local depth = (scopeMap[perkId] or 1) - 1
        if depth > 0 then
            scopeMap[perkId] = depth
        else
            scopeMap[perkId] = nil
        end
        if isEmpty(scopeMap) then
            handlerScopes[player] = nil
        end
    end

    local function deliver(player, envelope)
        local appliedDelta = envelope.actualPositionAfter - envelope.actualPositionBefore
        local positiveCredit = isFinite(envelope.survivorCreditBase)
            and envelope.survivorCreditBase > 0
        local validMovement = isFinite(appliedDelta) and appliedDelta ~= 0
            and ((positiveCredit and appliedDelta > 0)
                or (envelope.survivorCreditBase == 0 and appliedDelta < 0))
        if not validMovement then
            setLast("invalid_event_movement")
            return result(false, "invalid_event_movement", nil)
        end
        local award = {
            perkId = envelope.perkId,
            survivorCreditBase = envelope.survivorCreditBase,
            appliedDelta = appliedDelta,
            actualPositionBefore = envelope.actualPositionBefore,
            actualPositionAfter = envelope.actualPositionAfter,
        }
        pushHandlerScope(player, envelope.perkId)
        local called = callSafely(validated.processAward, player, award)
        popHandlerScope(player, envelope.perkId)
        if not called[1] then
            setLast("handler_threw")
            setHandlerFailure("handler_threw", nil)
            return result(false, "handler_threw", nil)
        end
        if type(called[2]) ~= "table" or called[2].ok ~= true then
            setLast("handler_failed")
            setHandlerFailure("handler_failed", called[2])
            return result(false, "handler_failed", nil)
        end
        setLast("award_processed")
        lastFailure = nil
        return result(true, "award_processed", nil)
    end

    local function rebase(player, perkId, perk, position)
        local playerCursors = mapFor(cursors, player, true)
        local oldCursor = playerCursors[perkId]
        local playerHandleIds = mapFor(handleIds, player, true)
        if oldCursor and playerHandleIds[oldCursor.perk] == perkId then
            playerHandleIds[oldCursor.perk] = nil
        end
        playerCursors[perkId] = { perk = perk, position = position }
        playerHandleIds[perk] = perkId
    end

    local function clearCursor(player, perkId)
        local playerCursors = cursors[player]
        if not playerCursors then
            return
        end
        local cursor = playerCursors[perkId]
        local playerHandleIds = handleIds[player]
        if cursor and playerHandleIds and playerHandleIds[cursor.perk] == perkId then
            playerHandleIds[cursor.perk] = nil
            if isEmpty(playerHandleIds) then
                handleIds[player] = nil
            end
        end
        playerCursors[perkId] = nil
        if isEmpty(playerCursors) then
            cursors[player] = nil
        end
    end

    local function refreshCursor(player, perkId, perk, phase)
        local position, readFailure = read(player, perkId, phase)
        if not position then
            clearCursor(player, perkId)
            return nil, readFailure
        end
        rebase(player, perkId, perk, position)
        return position, nil
    end

    local function routeFor(player, perk)
        for index = #routeFrames, 1, -1 do
            local frame = routeFrames[index]
            if frame.player == player and frame.perk == perk then
                return frame.route
            end
        end
        return "sandbox"
    end

    local function handlePositive(player, perk, perkId, before, after, eventAmount)
        local route = routeFor(player, perk)
        local divisor = 1
        local divisorFailure = nil
        if route ~= "no_multiplier" then
            divisor, divisorFailure = sandboxDivisor(player, perkId)
        end
        if not divisor then
            setLast(divisorFailure)
            return
        end

        local credit = eventAmount / divisor
        if not isFinite(credit) or credit <= 0 then
            setLast("invalid_survivor_credit")
            return
        end
        deliver(player, {
            perkId = perkId,
            actualPositionBefore = before,
            actualPositionAfter = after,
            survivorCreditBase = credit,
        })
    end

    local function handleNegative(player, perkId, before, after)
        deliver(player, {
            perkId = perkId,
            actualPositionBefore = before,
            actualPositionAfter = after,
            survivorCreditBase = 0,
        })
    end

    local function observe(owner, perk, eventAmount)
        if not capturing then
            return
        end

        local eligible, playerFailure = playerIsEligible(owner)
        if not eligible then
            setLast(playerFailure)
            return
        end

        local playerHandleIds = handleIds[owner]
        local cachedPerkId = playerHandleIds and playerHandleIds[perk] or nil
        local perkId, identityFailure = resolve(perk)
        if not perkId then
            if cachedPerkId then
                local _, boundaryFailure = refreshCursor(
                    owner, cachedPerkId, perk, "identity_boundary"
                )
                setLast(boundaryFailure or (identityFailure .. "_rebased"))
            else
                setLast(identityFailure)
            end
            return
        end

        local after, readFailure = read(owner, perkId, "after")
        if not after then
            local _, boundaryFailure = refreshCursor(
                owner, perkId, perk, "failure_boundary"
            )
            setLast(boundaryFailure or (readFailure .. "_rebased"))
            return
        end

        local priorPerkId = playerHandleIds and playerHandleIds[perk] or nil
        if priorPerkId and priorPerkId ~= perkId then
            clearCursor(owner, priorPerkId)
            local _, boundaryFailure = refreshCursor(
                owner, perkId, perk, "id_boundary"
            )
            setLast(boundaryFailure or "id_discontinuity_rebased")
            return
        end

        local playerCursors = cursors[owner]
        local cursor = playerCursors and playerCursors[perkId] or nil
        local function stopAtBoundary(code)
            local _, boundaryFailure = refreshCursor(
                owner, perkId, perk, "failure_boundary"
            )
            setLast(boundaryFailure or code)
        end

        local internal, scopeFailure = mutationIsActive(owner, perkId)
        if internal == nil then
            stopAtBoundary(scopeFailure)
            return
        end
        if internal then
            stopAtBoundary("internal_mutation_rebased")
            return
        end

        if not cursor or cursor.perk ~= perk then
            stopAtBoundary(cursor and "handle_discontinuity_rebased" or "missing_cursor_rebased")
            return
        end

        if not isFinite(eventAmount) then
            stopAtBoundary("invalid_event_amount_rebased")
            return
        end

        local added = callSafely(validated.addPosition, cursor.position, eventAmount)
        if not added[1] then
            stopAtBoundary("position_add_threw")
            return
        end
        local transition = added[2]
        if type(transition) ~= "table" or transition.ok ~= true
            or not isPosition(transition.positionAfter)
            or type(transition.moved) ~= "boolean" then
            stopAtBoundary("position_add_failed")
            return
        end
        if transition.positionAfter ~= after then
            stopAtBoundary("position_discontinuity_rebased")
            return
        end

        local before = cursor.position
        rebase(owner, perkId, perk, after)
        if not transition.moved or eventAmount == 0 then
            setLast("zero_movement_rebased")
            return
        end
        if eventAmount > 0 then
            handlePositive(owner, perk, perkId, before, after, eventAmount)
        else
            handleNegative(owner, perkId, before, after)
        end
    end

    local function callPrior(prior, route, ...)
        local args = pack(...)
        routeFrames[#routeFrames + 1] = {
            player = args[1],
            perk = args[2],
            route = route,
        }
        local called = pack(pcall(prior, unpack(args, 1, args.n)))
        routeFrames[#routeFrames] = nil
        if not called[1] then
            setLast("prior_threw")
            error(called[2], 0)
        end

        return unpack(called, 2, called.n)
    end

    local function ownershipDetail()
        if not installed then
            return false, false, false, false, false
        end
        local events = globals.Events
        return globals[RELOAD_SENTINEL_KEY] == reloadSentinel,
            type(events) == "table" and type(events.AddXP) == "table"
                and events.AddXP[RELOAD_SENTINEL_KEY] == reloadSentinel,
            globals.addXp == wrappedAddXp,
            globals.addXpNoMultiplier == wrappedAddXpNoMultiplier,
            type(events) == "table" and events.AddXP == registrationAddXpEvent
    end

    local function cleanupOwnedSeams()
        if cleanupAttempted or not installed then
            return
        end
        cleanupAttempted = true

        if globals.addXp == wrappedAddXp then
            globals.addXp = priorAddXp
        end
        if globals.addXpNoMultiplier == wrappedAddXpNoMultiplier then
            globals.addXpNoMultiplier = priorAddXpNoMultiplier
        end

        if registrationRemove == nil then
            cleanupState = "observer_remove_unavailable"
            return
        end
        local removed = callSafely(registrationRemove, observe)
        if not removed[1] then
            cleanupState = "observer_remove_ambiguous"
            return
        end
        observerState = "removed"
        cleanupState = "observer_removed"
    end

    local function loseOwnership(reason)
        if ownershipReason == nil then
            ownershipReason = reason
            capturing = false
            cleanupOwnedSeams()
        end
        setLast("ownership_lost")
        return result(false, "ownership_lost", ownershipReason)
    end

    function instance.verifyOwnership()
        if not installed then
            setLast("not_installed")
            return result(false, "not_installed", nil)
        end
        if ownershipReason then
            return loseOwnership(ownershipReason)
        end

        local ownsGlobalsSentinel, ownsEventSentinel, ownsAddXp, ownsNoMultiplier,
            ownsAddXpEvent = ownershipDetail()
        local lostReason = nil
        if not ownsGlobalsSentinel then
            lostReason = "reloadRegistry.globals"
        elseif not ownsEventSentinel then
            lostReason = "reloadRegistry.Events.AddXP"
        elseif not ownsAddXp then
            lostReason = "addXp"
        elseif not ownsNoMultiplier then
            lostReason = "addXpNoMultiplier"
        elseif not ownsAddXpEvent then
            lostReason = "Events.AddXP"
        end
        if lostReason then
            return loseOwnership(lostReason)
        end

        setLast("ownership_verified")
        return result(true, "ownership_verified", nil)
    end

    local function prepareInstallAnchor()
        if globals[RELOAD_SENTINEL_KEY] ~= reloadSentinel then
            return false, "reloadRegistry.globals"
        end
        local events = globals.Events
        local addXpEvent = type(events) == "table" and events.AddXP or nil
        if anchorAddXpEvent then
            if addXpEvent ~= anchorAddXpEvent then
                return false, "Events.AddXP"
            end
            if anchorAddXpEvent[RELOAD_SENTINEL_KEY] ~= reloadSentinel then
                return false, "reloadRegistry.Events.AddXP"
            end
        elseif type(addXpEvent) == "table" then
            local currentSentinel = addXpEvent[RELOAD_SENTINEL_KEY]
            if currentSentinel ~= nil and currentSentinel ~= reloadSentinel then
                return false, "reloadRegistry.Events.AddXP"
            end
            addXpEvent[RELOAD_SENTINEL_KEY] = reloadSentinel
            anchorAddXpEvent = addXpEvent
        end
        return true, nil
    end

    function instance.install()
        if ownershipReason then
            setLast("ownership_lost")
            return result(false, "ownership_lost", ownershipReason)
        end

        if installed then
            local verified = instance.verifyOwnership()
            if not verified.ok then
                return verified
            end
            setLast("already_installed")
            return result(true, "already_installed", nil)
        end

        local ownsAnchors, anchorFailure = prepareInstallAnchor()
        if not ownsAnchors then
            ownershipReason = anchorFailure
            setLast("ownership_lost")
            return result(false, "ownership_lost", ownershipReason)
        end

        local canInstall, authorityCode = authoritativeNow()
        if not canInstall then
            if authorityCode == "non_authoritative" then
                setLast("inert_non_authoritative")
                return result(true, "inert_non_authoritative", nil)
            end
            setLast(authorityCode)
            return result(false, authorityCode, nil)
        end

        local candidateAddXp = globals.addXp
        local candidateNoMultiplier = globals.addXpNoMultiplier
        local events = globals.Events
        local addXpEvent = type(events) == "table" and events.AddXP or nil
        if type(candidateAddXp) ~= "function" then
            setLast("missing_addXp")
            return result(false, "missing_seam", "addXp")
        end
        if type(candidateNoMultiplier) ~= "function" then
            setLast("missing_addXpNoMultiplier")
            return result(false, "missing_seam", "addXpNoMultiplier")
        end
        if type(addXpEvent) ~= "table" or type(addXpEvent.Add) ~= "function" then
            setLast("missing_Events_AddXP_Add")
            return result(false, "missing_seam", "Events.AddXP.Add")
        end
        if ambiguousEvents[addXpEvent] then
            setLast("observer_registration_ambiguous")
            return result(false, "observer_registration_ambiguous", nil)
        end

        local addRegistered = callSafely(addXpEvent.Add, observe)
        if not addRegistered[1] then
            ambiguousEvents[addXpEvent] = true
            observerState = "ambiguous"
            capturing = false
            setLast("observer_registration_ambiguous")
            return result(false, "observer_registration_ambiguous", "Events.AddXP")
        end
        priorAddXp = candidateAddXp
        priorAddXpNoMultiplier = candidateNoMultiplier
        wrappedAddXp = function(...)
            return callPrior(priorAddXp, "sandbox", ...)
        end
        wrappedAddXpNoMultiplier = function(...)
            return callPrior(priorAddXpNoMultiplier, "no_multiplier", ...)
        end
        registrationAddXpEvent = addXpEvent
        registrationRemove = type(addXpEvent.Remove) == "function" and addXpEvent.Remove or nil
        observerState = "registered"
        globals.addXp = wrappedAddXp
        globals.addXpNoMultiplier = wrappedAddXpNoMultiplier
        installed = true
        capturing = true
        setLast("installed")
        return result(true, "installed", nil)
    end

    function instance.initializePlayer(player, perks)
        if installed then
            local verified = instance.verifyOwnership()
            if not verified.ok then
                return verified
            end
        end
        local eligible, playerFailure = playerIsEligible(player)
        if not eligible then
            setLast(playerFailure)
            return result(false, playerFailure, nil)
        end
        if type(perks) ~= "table" then
            setLast("invalid_perks")
            return result(false, "invalid_perks", nil)
        end

        local count = 0
        local highestIndex = 0
        for key in pairs(perks) do
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
                setLast("invalid_perks")
                return result(false, "invalid_perks", nil)
            end
            count = count + 1
            if key > highestIndex then
                highestIndex = key
            end
        end
        if count ~= highestIndex then
            setLast("invalid_perks")
            return result(false, "invalid_perks", nil)
        end

        cursors[player] = nil
        handleIds[player] = nil
        local initialized = 0
        local skipped = 0
        for index = 1, highestIndex do
            local perk = perks[index]
            local perkId = resolve(perk)
            if not perkId then
                skipped = skipped + 1
            else
                local position = read(player, perkId, "initial")
                if not position then
                    skipped = skipped + 1
                else
                    rebase(player, perkId, perk, position)
                    initialized = initialized + 1
                end
            end
        end
        setLast("player_initialized")
        return result(true, "player_initialized", {
            initialized = initialized,
            skipped = skipped,
        })
    end

    function instance.rebasePlayerPerk(player, perk)
        local eligible, playerFailure = playerIsEligible(player)
        if not eligible then
            setLast(playerFailure)
            return result(false, playerFailure, nil)
        end
        local perkId, identityFailure = resolve(perk)
        if not perkId then
            setLast(identityFailure)
            return result(false, identityFailure, nil)
        end

        local position, readFailure = refreshCursor(
            player, perkId, perk, "rebase"
        )
        if not position then
            setLast(readFailure)
            return result(false, readFailure, nil)
        end
        setLast("player_perk_rebased")
        return result(true, "player_perk_rebased", {
            perkId = perkId,
            position = position,
        })
    end

    function instance.flushPlayerPerk(player, perkId)
        setLast("no_pending_award")
        return result(true, "no_pending_award", {
            flushed = 0,
            failed = 0,
        })
    end

    function instance.flushPlayer(player)
        setLast("no_pending_award")
        return result(true, "no_pending_award", {
            flushed = 0,
            failed = 0,
        })
    end

    function instance.flushAll()
        setLast("no_pending_award")
        return result(true, "no_pending_award", {
            flushed = 0,
            failed = 0,
        })
    end

    function instance.status()
        local ownsGlobalsSentinel, ownsEventSentinel, ownsAddXp, ownsNoMultiplier,
            ownsAddXpEvent = ownershipDetail()
        local cursorCount = 0
        for _, playerCursors in pairs(cursors) do
            for _ in pairs(playerCursors) do
                cursorCount = cursorCount + 1
            end
        end
        return {
            installed = installed,
            capturing = capturing,
            observerRegistration = observerState,
            ownershipCleanup = cleanupState,
            ownsGlobalsReloadSentinel = ownsGlobalsSentinel,
            ownsEventReloadSentinel = ownsEventSentinel,
            ownsAddXp = ownsAddXp,
            ownsAddXpNoMultiplier = ownsNoMultiplier,
            ownsAddXpEvent = ownsAddXpEvent,
            cursorCount = cursorCount,
            lastCode = lastCode,
            lastFailure = lastFailure and {
                code = lastFailure.code,
                detail = {
                    code = lastFailure.detail.code,
                    detail = lastFailure.detail.detail,
                },
            } or nil,
            ownershipReason = ownershipReason,
        }
    end

    return instance, nil
end

return EventDerivedXpSource
