local GlobalXpSource = {}

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

local function pack(...)
    return { n = select("#", ...), ... }
end

local function callSafely(callable, ...)
    return pack(pcall(callable, ...))
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
        or type(dependencies.authority.isAuthoritative) ~= "function" then
        return nil, result(false, "invalid_dependencies", "authority")
    end
    if type(dependencies.perkIdentity) ~= "table"
        or type(dependencies.perkIdentity.resolve) ~= "function" then
        return nil, result(false, "invalid_dependencies", "perkIdentity")
    end
    if type(dependencies.positionReader) ~= "table"
        or type(dependencies.positionReader.read) ~= "function" then
        return nil, result(false, "invalid_dependencies", "positionReader")
    end
    if type(dependencies.awardHandler) ~= "table"
        or type(dependencies.awardHandler.process) ~= "function" then
        return nil, result(false, "invalid_dependencies", "awardHandler")
    end
    return {
        globals = dependencies.environment.globals,
        isAuthoritative = dependencies.authority.isAuthoritative,
        resolvePerk = dependencies.perkIdentity.resolve,
        readPosition = dependencies.positionReader.read,
        processAward = dependencies.awardHandler.process,
    }, nil
end

function GlobalXpSource.create(dependencies)
    local validated, failure = validateDependencies(dependencies)
    if not validated then
        return nil, failure
    end

    local globals = validated.globals
    local isAuthoritative = validated.isAuthoritative
    local resolvePerk = validated.resolvePerk
    local readPosition = validated.readPosition
    local processAward = validated.processAward
    local transactions = {}
    local installed = false
    local captureEnabled = false
    local observerState = "not_attempted"
    local registrationEvent = nil
    local ambiguousEvents = setmetatable({}, { __mode = "k" })
    local priorAddXp = nil
    local priorAddXpNoMultiplier = nil
    local wrappedAddXp = nil
    local wrappedAddXpNoMultiplier = nil
    local ownershipReason = nil
    local lastCode = "created"
    local instance = {}

    local function setLast(code)
        lastCode = code
    end

    local function authoritativeNow()
        local called = callSafely(isAuthoritative)
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
        local called = callSafely(resolvePerk, perk)
        if not called[1] then
            return nil, "identity_threw"
        end
        local answer = called[2]
        if type(answer) ~= "table" or answer.ok ~= true
            or type(answer.perkId) ~= "string"
            or not answer.perkId:match("^[%w%._:%-]+$") then
            return nil, "identity_failed"
        end
        return answer.perkId, nil
    end

    local function read(player, perkId, phase)
        local called = callSafely(readPosition, player, perkId)
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

    local function observe(owner, perk, appliedDelta)
        if not captureEnabled then
            return
        end
        local transaction = transactions[#transactions]
        if not transaction then
            return
        end
        if owner ~= transaction.player or perk ~= transaction.perk then
            transaction.invalidCode = "mismatched_event"
            return
        end
        transaction.eventCount = transaction.eventCount + 1
        if transaction.eventCount > 1 then
            transaction.invalidCode = "multiple_events"
            return
        end
        if not isFinite(appliedDelta) then
            transaction.invalidCode = "invalid_applied_delta"
            return
        end
        transaction.appliedDelta = appliedDelta
    end

    local function handleAward(transaction)
        if transaction.invalidCode then
            setLast(transaction.invalidCode)
            return
        end
        if transaction.eventCount == 0 then
            setLast("missing_event")
            return
        end
        if transaction.eventCount ~= 1 then
            setLast("multiple_events")
            return
        end
        local after, readFailure = read(transaction.player, transaction.perkId, "after")
        if not after then
            setLast(readFailure)
            return
        end
        local award = {
            perkId = transaction.perkId,
            baseAward = transaction.baseAward,
            appliedDelta = transaction.appliedDelta,
            actualPositionBefore = transaction.before,
            actualPositionAfter = after,
        }
        local handled = callSafely(processAward, transaction.player, award)
        if not handled[1] then
            setLast("handler_threw")
            return
        end
        local answer = handled[2]
        if type(answer) ~= "table" or answer.ok ~= true then
            setLast("handler_failed")
            return
        end
        setLast("award_processed")
    end

    local function callPrior(prior, ...)
        local args = pack(...)
        local transaction = nil

        if captureEnabled then
            local baseAward = args[3]
            if not isFinite(baseAward) then
                setLast("invalid_base_award")
            else
                local perkId, identityFailure = resolve(args[2])
                if not perkId then
                    setLast(identityFailure)
                else
                    local before, readFailure = read(args[1], perkId, "before")
                    if before then
                        transaction = {
                            player = args[1],
                            perk = args[2],
                            perkId = perkId,
                            baseAward = baseAward,
                            before = before,
                            eventCount = 0,
                        }
                        transactions[#transactions + 1] = transaction
                    else
                        setLast(readFailure)
                    end
                end
            end
        end

        local called = pack(pcall(prior, unpack(args, 1, args.n)))

        if transaction then
            transactions[#transactions] = nil
            if called[1] and captureEnabled then
                handleAward(transaction)
            else
                if not called[1] then
                    setLast("prior_threw")
                end
            end
        end

        if not called[1] then
            error(called[2], 0)
        end
        return unpack(called, 2, called.n)
    end

    local function ownershipDetail()
        if not installed then
            return false, false, false
        end
        local ownsAddXp = globals.addXp == wrappedAddXp
        local ownsNoMultiplier = globals.addXpNoMultiplier == wrappedAddXpNoMultiplier
        local ownsEvent = type(globals.Events) == "table"
            and globals.Events.AddXP == registrationEvent
        return ownsAddXp, ownsNoMultiplier, ownsEvent
    end

    function instance.verifyOwnership()
        if not installed then
            setLast("not_installed")
            return result(false, "not_installed", nil)
        end
        if ownershipReason then
            setLast("ownership_lost")
            return result(false, "ownership_lost", ownershipReason)
        end

        local ownsAddXp, ownsNoMultiplier, ownsEvent = ownershipDetail()
        if not ownsAddXp then
            ownershipReason = "addXp"
        elseif not ownsNoMultiplier then
            ownershipReason = "addXpNoMultiplier"
        elseif not ownsEvent then
            ownershipReason = "Events.AddXP"
        end
        if ownershipReason then
            captureEnabled = false
            setLast("ownership_lost")
            return result(false, "ownership_lost", ownershipReason)
        end

        setLast("ownership_verified")
        return result(true, "ownership_verified", nil)
    end

    function instance.install()
        if ownershipReason then
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
        if installed then
            local verified = instance.verifyOwnership()
            if not verified.ok then
                return verified
            end
            setLast("already_installed")
            return result(true, "already_installed", nil)
        end

        local candidateAddXp = globals.addXp
        local candidateNoMultiplier = globals.addXpNoMultiplier
        local events = globals.Events
        local event = type(events) == "table" and events.AddXP or nil
        if type(candidateAddXp) ~= "function" then
            setLast("missing_addXp")
            return result(false, "missing_seam", "addXp")
        end
        if type(candidateNoMultiplier) ~= "function" then
            setLast("missing_addXpNoMultiplier")
            return result(false, "missing_seam", "addXpNoMultiplier")
        end
        if type(event) ~= "table" or type(event.Add) ~= "function" then
            setLast("missing_Events_AddXP_Add")
            return result(false, "missing_seam", "Events.AddXP.Add")
        end
        if ambiguousEvents[event] then
            setLast("observer_registration_ambiguous")
            return result(false, "observer_registration_ambiguous", nil)
        end

        local registered = callSafely(event.Add, observe)
        if not registered[1] then
            ambiguousEvents[event] = true
            observerState = "ambiguous"
            captureEnabled = false
            setLast("observer_registration_ambiguous")
            return result(false, "observer_registration_ambiguous", nil)
        end

        priorAddXp = candidateAddXp
        priorAddXpNoMultiplier = candidateNoMultiplier
        wrappedAddXp = function(...)
            return callPrior(priorAddXp, ...)
        end
        wrappedAddXpNoMultiplier = function(...)
            return callPrior(priorAddXpNoMultiplier, ...)
        end
        registrationEvent = event
        observerState = "registered"
        globals.addXp = wrappedAddXp
        globals.addXpNoMultiplier = wrappedAddXpNoMultiplier
        installed = true
        captureEnabled = true
        setLast("installed")
        return result(true, "installed", nil)
    end

    function instance.status()
        local ownsAddXp, ownsNoMultiplier, ownsEvent = ownershipDetail()
        return {
            installed = installed,
            captureEnabled = captureEnabled,
            observerRegistration = observerState,
            ownsAddXp = ownsAddXp,
            ownsAddXpNoMultiplier = ownsNoMultiplier,
            ownsEvent = ownsEvent,
            lastCode = lastCode,
            ownershipReason = ownershipReason,
        }
    end

    return instance, nil
end

return GlobalXpSource
