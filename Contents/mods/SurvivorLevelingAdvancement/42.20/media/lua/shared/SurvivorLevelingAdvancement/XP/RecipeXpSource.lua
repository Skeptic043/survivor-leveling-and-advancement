local RecipeXpSource = {}

local unpackValues = unpack

local function pack(...)
    return { n = select("#", ...), ... }
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

local function callableMember(object, name)
    if object == nil then
        return nil
    end

    local ok, member = pcall(function()
        return object[name]
    end)
    if not ok or type(member) ~= "function" then
        return nil
    end
    return member
end

local function readMember(object, name)
    if object == nil then
        return false, nil
    end
    return pcall(function()
        return object[name]
    end)
end

local function callMethod(object, name, ...)
    local method = callableMember(object, name)
    if method == nil then
        return false, nil
    end
    return pcall(method, object, ...)
end

local function result(ok, code, detail)
    return {
        ok = ok,
        code = code,
        detail = detail,
    }
end

function RecipeXpSource.create(dependencies)
    local state = {
        dependencies = dependencies,
        stack = {},
        ambiguousEvents = setmetatable({}, { __mode = "k" }),
        authorityChecked = false,
        authoritative = false,
        inert = false,
        installed = false,
        captureEnabled = false,
        observerRegistered = false,
        registrationAmbiguous = false,
        handcraftOwned = false,
        buildOwned = false,
        eventOwned = false,
        ownershipLost = false,
        ownershipReason = "not_installed",
        lastCode = "not_installed",
    }

    local instance = {}
    local observer
    local handcraftWrapper
    local buildWrapper

    local function setLast(code)
        state.lastCode = code
    end

    local function validateDependencies()
        local dependenciesValue = state.dependencies
        if type(dependenciesValue) ~= "table" then
            return false
        end
        if type(dependenciesValue.environment) ~= "table"
            or type(dependenciesValue.environment.globals) ~= "table" then
            return false
        end
        if type(dependenciesValue.authority) ~= "table"
            or type(dependenciesValue.authority.isAuthoritative) ~= "function" then
            return false
        end
        if type(dependenciesValue.perkIdentity) ~= "table"
            or type(dependenciesValue.perkIdentity.resolve) ~= "function" then
            return false
        end
        if type(dependenciesValue.positionReader) ~= "table"
            or type(dependenciesValue.positionReader.read) ~= "function" then
            return false
        end
        if type(dependenciesValue.awardHandler) ~= "table"
            or type(dependenciesValue.awardHandler.process) ~= "function" then
            return false
        end
        if type(dependenciesValue.exactXpClaims) ~= "table"
            or type(dependenciesValue.exactXpClaims.claim) ~= "function"
            or type(dependenciesValue.exactXpClaims.release) ~= "function" then
            return false
        end
        return true
    end

    local function resolvePerk(perk)
        local ok, resolved = pcall(state.dependencies.perkIdentity.resolve, perk)
        if not ok or type(resolved) ~= "table" or resolved.ok ~= true
            or type(resolved.perkId) ~= "string"
            or string.match(resolved.perkId, "^[%w%._:%-]+$") == nil then
            return false, nil
        end
        return true, resolved.perkId
    end

    local function readPosition(player, perkId)
        local ok, readResult = pcall(state.dependencies.positionReader.read, player, perkId)
        if not ok or type(readResult) ~= "table" or readResult.ok ~= true
            or not isPosition(readResult.position) then
            return false, nil
        end
        return true, readResult.position
    end

    local function makeTransaction(kind, receiver)
        local transaction = {
            valid = false,
            invalidEvent = false,
            player = nil,
            expected = {},
            unique = {},
            eventCount = 0,
        }

        local logicField = kind == "handcraft" and "logic" or "buildPanelLogic"
        local playerOk, player = readMember(receiver, "character")
        local logicOk, logic = readMember(receiver, logicField)
        if not playerOk or player == nil or not logicOk or logic == nil then
            return transaction
        end

        local recipeOk, recipe = callMethod(logic, "getRecipe")
        if not recipeOk or recipe == nil then
            return transaction
        end

        local countOk, count = callMethod(recipe, "getXPAwardCount")
        if not countOk or not isFinite(count) or count < 0 or count % 1 ~= 0 then
            return transaction
        end

        local uniqueByPerk = {}
        for index = 0, count - 1 do
            local awardOk, award = callMethod(recipe, "getXPAward", index)
            if not awardOk or award == nil then
                return transaction
            end

            local perkOk, perk = callMethod(award, "getPerk")
            local amountOk, amount = callMethod(award, "getAmount")
            if not perkOk or perk == nil or not amountOk or not isFinite(amount) then
                return transaction
            end

            local aggregate = uniqueByPerk[perk]
            if aggregate == nil then
                local resolvedOk, perkId = resolvePerk(perk)
                if not resolvedOk then
                    return transaction
                end
                local positionOk, before = readPosition(player, perkId)
                if not positionOk then
                    return transaction
                end
                aggregate = {
                    perk = perk,
                    perkId = perkId,
                    baseAward = 0,
                    appliedDelta = 0,
                    actualPositionBefore = before,
                }
                uniqueByPerk[perk] = aggregate
                transaction.unique[#transaction.unique + 1] = aggregate
            end

            aggregate.baseAward = aggregate.baseAward + amount
            if not isFinite(aggregate.baseAward) then
                return transaction
            end
            transaction.expected[#transaction.expected + 1] = {
                perk = perk,
                aggregate = aggregate,
            }
        end

        transaction.player = player
        transaction.valid = true
        return transaction
    end

    local function observe(owner, perk, appliedDelta)
        if not state.captureEnabled then
            return
        end

        local transaction = state.stack[#state.stack]
        if transaction == nil or transaction.ignoreEvents
            or not transaction.valid or transaction.invalidEvent then
            return
        end

        local nextIndex = transaction.eventCount + 1
        local expected = transaction.expected[nextIndex]
        if expected == nil or owner ~= transaction.player or perk ~= expected.perk
            or not isFinite(appliedDelta) then
            transaction.invalidEvent = true
            return
        end

        local newApplied = expected.aggregate.appliedDelta + appliedDelta
        if not isFinite(newApplied) then
            transaction.invalidEvent = true
            return
        end
        local claimed, claimResult = pcall(
            state.dependencies.exactXpClaims.claim,
            transaction,
            owner,
            perk,
            appliedDelta
        )
        if not claimed then
            transaction.invalidEvent = true
            transaction.claimCode = "claim_threw"
            return
        end
        if type(claimResult) ~= "table" or claimResult.ok ~= true then
            transaction.invalidEvent = true
            transaction.claimCode = "claim_failed"
            return
        end
        expected.aggregate.appliedDelta = newApplied
        transaction.eventCount = nextIndex
    end

    observer = function(owner, perk, appliedDelta)
        observe(owner, perk, appliedDelta)
    end

    local function finishTransaction(transaction)
        if not transaction.valid then
            setLast("action_unsupported")
            return
        end
        if transaction.invalidEvent or transaction.eventCount ~= #transaction.expected then
            setLast(transaction.claimCode or "event_pair_ambiguous")
            return
        end

        local envelopes = {}
        for index = 1, #transaction.unique do
            local aggregate = transaction.unique[index]
            local positionOk, after = readPosition(transaction.player, aggregate.perkId)
            if not positionOk then
                setLast("position_after_failed")
                return
            end
            envelopes[index] = {
                perkId = aggregate.perkId,
                baseAward = aggregate.baseAward,
                appliedDelta = aggregate.appliedDelta,
                actualPositionBefore = aggregate.actualPositionBefore,
                actualPositionAfter = after,
            }
        end

        local handlerFailed = false
        state.stack[#state.stack + 1] = { ignoreEvents = true }
        for index = 1, #envelopes do
            local ok, handlerResult = pcall(
                state.dependencies.awardHandler.process,
                transaction.player,
                envelopes[index]
            )
            if not ok or type(handlerResult) ~= "table" or handlerResult.ok ~= true then
                handlerFailed = true
            end
        end
        state.stack[#state.stack] = nil
        setLast(handlerFailed and "handler_failed" or "capture_ok")
    end

    local function invokeAction(kind, prior, ...)
        if not state.captureEnabled then
            return prior(...)
        end

        local receiver = select(1, ...)
        local prepared, transaction = pcall(makeTransaction, kind, receiver)
        if not prepared then
            transaction = {
                valid = false,
                invalidEvent = false,
                expected = {},
                unique = {},
                eventCount = 0,
            }
        end

        state.stack[#state.stack + 1] = transaction
        local priorResult = pack(pcall(prior, ...))
        state.stack[#state.stack] = nil
        local released, releaseResult = pcall(state.dependencies.exactXpClaims.release, transaction)
        local releaseFailed = not released
            or type(releaseResult) ~= "table" or releaseResult.ok ~= true

        if not priorResult[1] then
            setLast(releaseFailed and "claim_release_failed" or "prior_failed")
            error(priorResult[2], 0)
        end

        local finished = pcall(finishTransaction, transaction)
        if not finished then
            setLast("capture_failed")
        end
        if releaseFailed then
            setLast("claim_release_failed")
        end
        return unpackValues(priorResult, 2, priorResult.n)
    end

    handcraftWrapper = function(...)
        return invokeAction("handcraft", state.handcraftPrior, ...)
    end

    buildWrapper = function(...)
        return invokeAction("build", state.buildPrior, ...)
    end

    local function disableOwnership(reason)
        state.captureEnabled = false
        state.ownershipLost = true
        state.handcraftOwned = false
        state.buildOwned = false
        state.eventOwned = false
        state.ownershipReason = reason
        setLast("ownership_lost")
        return result(false, "ownership_lost", reason)
    end

    local function inspectOwnership()
        if not state.installed then
            return result(false, "not_installed", "not_installed")
        end
        if state.ownershipLost then
            return result(false, "ownership_lost", state.ownershipReason)
        end

        local globals = state.dependencies.environment.globals
        local handcraft = globals.ISHandcraftAction
        if handcraft ~= state.handcraftTable then
            return disableOwnership("handcraft_table_replaced")
        end
        if handcraft.performRecipe ~= handcraftWrapper then
            return disableOwnership("handcraft_method_replaced")
        end

        local build = globals.ISBuildIsoEntity
        if build ~= state.buildTable then
            return disableOwnership("build_table_replaced")
        end
        if build.create ~= buildWrapper then
            return disableOwnership("build_method_replaced")
        end

        local event = globals.Events and globals.Events.AddXP or nil
        if event ~= state.event then
            return disableOwnership("event_replaced")
        end

        state.handcraftOwned = true
        state.buildOwned = true
        state.eventOwned = true
        state.ownershipReason = "owned"
        setLast("ownership_ok")
        return result(true, "ownership_ok", "owned")
    end

    function instance.install()
        if not validateDependencies() then
            setLast("invalid_dependencies")
            return result(false, "invalid_dependencies", "required_dependency_missing")
        end
        if state.ownershipLost then
            return result(false, "ownership_lost", state.ownershipReason)
        end
        if state.inert then
            return result(true, "non_authoritative", "inert")
        end
        if state.installed then
            local owned = inspectOwnership()
            if not owned.ok then
                return owned
            end
            setLast("already_installed")
            return result(true, "already_installed", "owned")
        end

        if not state.authorityChecked then
            local called, authorityResult = pcall(state.dependencies.authority.isAuthoritative)
            if not called or type(authorityResult) ~= "table" or authorityResult.ok ~= true
                or type(authorityResult.authoritative) ~= "boolean" then
                setLast("authority_failed")
                return result(false, "authority_failed", "authority_unavailable")
            end
            state.authorityChecked = true
            state.authoritative = authorityResult.authoritative
            if not state.authoritative then
                state.inert = true
                state.ownershipReason = "non_authoritative"
                setLast("non_authoritative")
                return result(true, "non_authoritative", "inert")
            end
        elseif not state.authoritative then
            return result(false, "authority_failed", "authority_unavailable")
        end

        local globals = state.dependencies.environment.globals
        local handcraft = globals.ISHandcraftAction
        local build = globals.ISBuildIsoEntity
        local events = globals.Events
        local event = events and events.AddXP or nil
        local handcraftPrior = callableMember(handcraft, "performRecipe")
        local buildPrior = callableMember(build, "create")
        local addObserver = callableMember(event, "Add")

        if handcraftPrior == nil then
            setLast("handcraft_unavailable")
            return result(false, "handcraft_unavailable", "performRecipe_missing")
        end
        if buildPrior == nil then
            setLast("build_unavailable")
            return result(false, "build_unavailable", "create_missing")
        end
        if addObserver == nil then
            setLast("event_unavailable")
            return result(false, "event_unavailable", "AddXP_Add_missing")
        end
        if state.ambiguousEvents[event] then
            state.registrationAmbiguous = true
            setLast("event_registration_ambiguous")
            return result(false, "event_registration_ambiguous", "same_event_not_retried")
        end

        local registered = pcall(addObserver, observer)
        if not registered then
            state.ambiguousEvents[event] = true
            state.registrationAmbiguous = true
            setLast("event_registration_ambiguous")
            return result(false, "event_registration_ambiguous", "registration_threw")
        end

        state.handcraftPrior = handcraftPrior
        state.buildPrior = buildPrior
        state.handcraftTable = handcraft
        state.buildTable = build
        state.event = event
        handcraft.performRecipe = handcraftWrapper
        build.create = buildWrapper
        state.installed = true
        state.captureEnabled = true
        state.observerRegistered = true
        state.registrationAmbiguous = false
        state.handcraftOwned = true
        state.buildOwned = true
        state.eventOwned = true
        state.ownershipReason = "owned"
        setLast("installed")
        return result(true, "installed", "owned")
    end

    function instance.verifyOwnership()
        if state.inert then
            setLast("non_authoritative")
            return result(true, "non_authoritative", "inert")
        end
        return inspectOwnership()
    end

    function instance.status()
        return {
            installed = state.installed,
            captureEnabled = state.captureEnabled,
            observerRegistered = state.observerRegistered,
            registrationAmbiguous = state.registrationAmbiguous,
            handcraftOwned = state.handcraftOwned,
            buildOwned = state.buildOwned,
            eventOwned = state.eventOwned,
            ownershipReason = state.ownershipReason,
            lastCode = state.lastCode,
        }
    end

    return instance
end

return RecipeXpSource
