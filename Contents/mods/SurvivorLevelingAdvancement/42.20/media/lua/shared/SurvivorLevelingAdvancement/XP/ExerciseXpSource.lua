local ExerciseXpSource = {}

local FLOAT_MAX = 3.4028234663852886e38

local DEFINITIONS = {
    squats = { stiffness = "legs", xpMod = 1 },
    pushups = { stiffness = "arms,chest", xpMod = 1 },
    situp = { stiffness = "abs", xpMod = 1 },
    burpees = { stiffness = "legs,arms,chest", xpMod = 0.8 },
    barbellcurl = { stiffness = "arms,chest", xpMod = 1.2 },
    dumbbellpress = { stiffness = "arms", xpMod = 1.8 },
    bicepscurl = { stiffness = "arms", xpMod = 1.8 },
}

local STIFFNESS_BASES = {
    legs = { strength = 0, fitness = 4 },
    ["arms,chest"] = { strength = 6, fitness = 0 },
    abs = { strength = 0, fitness = 2 },
    ["legs,arms,chest"] = { strength = 6, fitness = 4 },
    arms = { strength = 4, fitness = 0 },
}

local unpackValues = unpack or table.unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function isPosition(value)
    return isFinite(value) and value >= 0
end

local function isIntegerLevel(value)
    return isFinite(value) and value >= 0 and value == math.floor(value)
end

local function requireTable(value, name)
    if type(value) ~= "table" then
        error("ExerciseXpSource.create: " .. name .. " must be a table", 3)
    end
    return value
end

local function requireFunction(value, name)
    if type(value) ~= "function" then
        error("ExerciseXpSource.create: " .. name .. " must be a function", 3)
    end
    return value
end

local function result(ok, code, detail)
    return { ok = ok, code = code, detail = detail }
end

local function callMethod(owner, methodName, ...)
    if owner == nil then
        return false, nil
    end

    local method = owner[methodName]
    if type(method) ~= "function" then
        return false, nil
    end

    local called = pack(pcall(method, owner, ...))
    if not called[1] then
        return false, nil
    end
    return true, called[2]
end

local function matchesDefinition(definition, exerciseType, expected)
    return type(definition) == "table"
        and definition.type == exerciseType
        and definition.stiffness == expected.stiffness
        and isFinite(definition.xpMod)
        and definition.xpMod == expected.xpMod
end

local function roundFloat(rounder, value)
    local rounded = pack(pcall(rounder, value, -FLOAT_MAX, FLOAT_MAX))
    if not rounded[1] or not isFinite(rounded[2]) then
        return nil
    end
    return rounded[2]
end

local function multiplyFloat(rounder, left, right)
    local roundedLeft = roundFloat(rounder, left)
    local roundedRight = roundFloat(rounder, right)
    if roundedLeft == nil or roundedRight == nil then
        return nil
    end
    return roundFloat(rounder, roundedLeft * roundedRight)
end

local function exerciseBase(rounder, stiffnessBase, level, xpMod)
    local levelFactor = 1
    if level > 5 then
        levelFactor = 1 + math.floor((level - 5) / 10)
    end

    local scaled = multiplyFloat(rounder, stiffnessBase, levelFactor)
    if scaled == nil then
        return nil
    end
    return multiplyFloat(rounder, scaled, xpMod)
end

local function routeBase(value, serverRoute)
    if not serverRoute then
        return value
    end
    if value < 0 then
        return math.ceil(value)
    end
    return math.floor(value)
end

function ExerciseXpSource.create(dependencies)
    dependencies = requireTable(dependencies, "dependencies")
    local environment = requireTable(dependencies.environment, "environment")
    local globals = requireTable(environment.globals, "environment.globals")
    local authority = requireTable(dependencies.authority, "authority")
    local describeAuthority = requireFunction(authority.describe, "authority.describe")
    local perkIdentity = requireTable(dependencies.perkIdentity, "perkIdentity")
    local resolvePerk = requireFunction(perkIdentity.resolve, "perkIdentity.resolve")
    local positionReader = requireTable(dependencies.positionReader, "positionReader")
    local readPosition = requireFunction(positionReader.read, "positionReader.read")
    local awardHandler = requireTable(dependencies.awardHandler, "awardHandler")
    local processAward = requireFunction(awardHandler.process, "awardHandler.process")

    local state = {
        authorityKnown = false,
        authoritative = false,
        serverRoute = false,
        installed = false,
        captureEnabled = false,
        actionTable = nil,
        priorMethod = nil,
        wrapper = nil,
        eventObject = nil,
        observer = nil,
        observerRegistered = false,
        ambiguousEvents = setmetatable({}, { __mode = "k" }),
        stack = {},
        lastCode = "not-installed",
        ownershipReason = nil,
    }

    local instance = {}

    local function setLast(code)
        state.lastCode = code
    end

    local function resolve(perk)
        local resolved = pack(pcall(resolvePerk, perk))
        if not resolved[1] or type(resolved[2]) ~= "table" then
            return nil
        end
        local value = resolved[2]
        if value.ok ~= true or type(value.perkId) ~= "string" or value.perkId == "" then
            return nil
        end
        return value.perkId
    end

    local function read(player, perkId)
        local readResult = pack(pcall(readPosition, player, perkId))
        if not readResult[1] or type(readResult[2]) ~= "table" then
            return nil
        end
        local value = readResult[2]
        if value.ok ~= true or not isPosition(value.position) then
            return nil
        end
        return value.position
    end

    local function buildTransaction(receiver)
        if type(receiver) ~= "table" then
            return nil, "receiver-invalid"
        end

        local player = receiver.character
        local fitness = receiver.fitness
        local exerciseType = receiver.exeDataType
        local exerciseData = receiver.exeData
        if player == nil or fitness == nil or type(exerciseType) ~= "string" then
            return nil, "action-capability-missing"
        end

        local expected = DEFINITIONS[exerciseType]
        if expected == nil then
            return nil, "definition-unsupported"
        end

        local gotFitness, playerFitness = callMethod(player, "getFitness")
        local gotParent, fitnessParent = callMethod(fitness, "getParent")
        local gotCurrent, currentExercise = callMethod(fitness, "getCurrentExe")
        if not gotFitness or playerFitness ~= fitness
            or not gotParent or fitnessParent ~= player
            or not gotCurrent or currentExercise == nil then
            return nil, "identity-invalid"
        end

        local exerciseTypes = globals.FitnessExercises
        exerciseTypes = type(exerciseTypes) == "table" and exerciseTypes.exercisesType or nil
        local hostedDefinition = type(exerciseTypes) == "table" and exerciseTypes[exerciseType] or nil
        if not matchesDefinition(hostedDefinition, exerciseType, expected)
            or not matchesDefinition(exerciseData, exerciseType, expected) then
            return nil, "definition-mismatch"
        end

        local perks = globals.Perks
        local strengthPerk = type(perks) == "table" and perks.Strength or nil
        local fitnessPerk = type(perks) == "table" and perks.Fitness or nil
        if strengthPerk == nil or fitnessPerk == nil or strengthPerk == fitnessPerk then
            return nil, "perks-invalid"
        end

        local gotStrengthLevel, strengthLevel = callMethod(player, "getPerkLevel", strengthPerk)
        local gotFitnessLevel, fitnessLevel = callMethod(player, "getPerkLevel", fitnessPerk)
        if not gotStrengthLevel or not gotFitnessLevel
            or not isIntegerLevel(strengthLevel) or not isIntegerLevel(fitnessLevel) then
            return nil, "level-invalid"
        end

        local pzMath = globals.PZMath
        local rounder = pzMath ~= nil and pzMath.clampFloat or nil
        if type(rounder) ~= "function" then
            return nil, "rounder-missing"
        end

        local bases = STIFFNESS_BASES[expected.stiffness]
        local strengthBase = exerciseBase(rounder, bases.strength, strengthLevel, expected.xpMod)
        local fitnessBase = exerciseBase(rounder, bases.fitness, fitnessLevel, expected.xpMod)
        if strengthBase == nil or fitnessBase == nil then
            return nil, "rounding-failed"
        end
        strengthBase = routeBase(strengthBase, state.serverRoute)
        fitnessBase = routeBase(fitnessBase, state.serverRoute)

        local strengthId = resolve(strengthPerk)
        local fitnessId = resolve(fitnessPerk)
        if strengthId == nil or fitnessId == nil or strengthId == fitnessId then
            return nil, "perk-identity-failed"
        end

        local strengthBefore = read(player, strengthId)
        local fitnessBefore = read(player, fitnessId)
        if strengthBefore == nil or fitnessBefore == nil then
            return nil, "position-before-failed"
        end

        return {
            kind = "transaction",
            player = player,
            invalid = false,
            sawFitness = false,
            awards = {
                {
                    perk = strengthPerk,
                    perkId = strengthId,
                    baseAward = strengthBase,
                    before = strengthBefore,
                    eventSeen = false,
                    appliedDelta = nil,
                },
                {
                    perk = fitnessPerk,
                    perkId = fitnessId,
                    baseAward = fitnessBase,
                    before = fitnessBefore,
                    eventSeen = false,
                    appliedDelta = nil,
                },
            },
        }
    end

    local function observe(owner, perk, appliedDelta)
        local top = state.stack[#state.stack]
        if top == nil or top.kind ~= "transaction" or top.invalid then
            return
        end

        local strength = top.awards[1]
        local fitness = top.awards[2]
        local expectedIndex = nil
        if perk == strength.perk then
            expectedIndex = 1
        elseif perk == fitness.perk then
            expectedIndex = 2
        else
            return
        end

        if owner ~= top.player then
            top.invalid = true
            return
        end
        if not isFinite(appliedDelta) then
            top.invalid = true
            return
        end

        local award = top.awards[expectedIndex]
        if award.eventSeen or (expectedIndex == 1 and top.sawFitness) then
            top.invalid = true
            return
        end

        award.eventSeen = true
        award.appliedDelta = appliedDelta
        if expectedIndex == 2 then
            top.sawFitness = true
        end
    end

    state.observer = observe

    local function processOne(transaction, award, after)
        local envelope = {
            perkId = award.perkId,
            baseAward = award.baseAward,
            appliedDelta = award.appliedDelta,
            actualPositionBefore = award.before,
            actualPositionAfter = after,
        }

        local sentinel = { kind = "ignore" }
        state.stack[#state.stack + 1] = sentinel
        local handled = pack(pcall(processAward, transaction.player, envelope))
        state.stack[#state.stack] = nil

        if not handled[1] then
            return "handler-threw"
        elseif type(handled[2]) ~= "table" or handled[2].ok ~= true then
            return "handler-failed"
        end
        return "award-processed"
    end

    local function completeTransaction(transaction)
        if transaction.invalid then
            setLast("repeat-ambiguous")
            return
        end

        local paired = false
        local finalReadFailed = false
        local prepared = {}
        for index = 1, 2 do
            local award = transaction.awards[index]
            if award.eventSeen then
                paired = true
                local after = read(transaction.player, award.perkId)
                if after == nil then
                    finalReadFailed = true
                else
                    prepared[#prepared + 1] = { award = award, after = after }
                end
            end
        end
        if not paired then
            setLast("repeat-no-pairs")
            return
        end

        local handlerThrew = false
        local handlerFailed = false
        for index = 1, #prepared do
            local handled = processOne(transaction, prepared[index].award, prepared[index].after)
            if handled == "handler-threw" then
                handlerThrew = true
            elseif handled == "handler-failed" then
                handlerFailed = true
            end
        end

        if handlerThrew then
            setLast("handler-threw")
        elseif handlerFailed then
            setLast("handler-failed")
        elseif finalReadFailed then
            setLast("position-after-failed")
        elseif #prepared > 0 then
            setLast("award-processed")
        end
    end

    local function wrapper(...)
        local arguments = pack(...)
        local prior = state.priorMethod
        if not state.captureEnabled then
            return prior(unpackValues(arguments, 1, arguments.n))
        end

        local built = pack(pcall(buildTransaction, arguments[1]))
        local transaction = nil
        if built[1] then
            transaction = built[2]
            if transaction == nil then
                setLast(built[3] or "capture-unavailable")
            end
        else
            setLast("capture-failed")
        end

        if transaction == nil then
            if #state.stack > 0 then
                local sentinel = { kind = "ignore" }
                state.stack[#state.stack + 1] = sentinel
                local priorResult = pack(pcall(prior, unpackValues(arguments, 1, arguments.n)))
                state.stack[#state.stack] = nil
                if not priorResult[1] then
                    error(priorResult[2], 0)
                end
                return unpackValues(priorResult, 2, priorResult.n)
            end
            return prior(unpackValues(arguments, 1, arguments.n))
        end

        state.stack[#state.stack + 1] = transaction
        local priorResult = pack(pcall(prior, unpackValues(arguments, 1, arguments.n)))
        state.stack[#state.stack] = nil

        if not priorResult[1] then
            setLast("prior-threw")
            error(priorResult[2], 0)
        end

        completeTransaction(transaction)
        return unpackValues(priorResult, 2, priorResult.n)
    end

    state.wrapper = wrapper

    local function describe()
        if state.authorityKnown then
            return true
        end

        local described = pack(pcall(describeAuthority))
        if not described[1] then
            setLast("authority-threw")
            return false
        end

        local descriptor = described[2]
        if type(descriptor) ~= "table" or descriptor.ok ~= true
            or type(descriptor.authoritative) ~= "boolean"
            or type(descriptor.serverRoute) ~= "boolean" then
            setLast("authority-invalid")
            return false
        end

        state.authorityKnown = true
        state.authoritative = descriptor.authoritative
        state.serverRoute = descriptor.serverRoute
        return true
    end

    local function disable(reason)
        state.captureEnabled = false
        state.ownershipReason = reason
        setLast(reason)
        return result(false, reason, "exercise capture ownership was lost")
    end

    local function ownershipResult()
        if globals.ISFitnessAction ~= state.actionTable then
            return disable("action-table-replaced")
        end
        if state.actionTable.exeLooped ~= state.wrapper then
            return disable("method-replaced")
        end
        local events = globals.Events
        if type(events) ~= "table" or events.AddXP ~= state.eventObject then
            return disable("event-replaced")
        end
        return nil
    end

    function instance.install()
        if not describe() then
            return result(false, state.lastCode, "authority descriptor is unavailable")
        end
        if not state.authoritative then
            state.captureEnabled = false
            setLast("non-authoritative")
            return result(true, "non-authoritative", "exercise capture is inert")
        end

        if state.installed then
            local lost = ownershipResult()
            if lost ~= nil then
                return lost
            end
            if not state.captureEnabled then
                return result(false, state.lastCode, "exercise capture is disabled")
            end
            setLast("already-installed")
            return result(true, "already-installed", "exercise capture is already installed")
        end

        local actionTable = globals.ISFitnessAction
        local events = globals.Events
        local eventObject = type(events) == "table" and events.AddXP or nil
        local eventAdd = type(eventObject) == "table" and eventObject.Add or nil
        if type(actionTable) ~= "table" or type(actionTable.exeLooped) ~= "function" then
            setLast("method-unavailable")
            return result(false, "method-unavailable", "ISFitnessAction.exeLooped is unavailable")
        end
        if type(eventAdd) ~= "function" then
            setLast("event-unavailable")
            return result(false, "event-unavailable", "Events.AddXP.Add is unavailable")
        end

        if state.ambiguousEvents[eventObject] then
            setLast("event-registration-ambiguous")
            return result(false, "event-registration-ambiguous", "observer registration is ambiguous")
        end

        if not state.observerRegistered or state.eventObject ~= eventObject then
            local registered = pack(pcall(eventAdd, state.observer))
            if not registered[1] then
                state.ambiguousEvents[eventObject] = true
                state.observerRegistered = false
                state.eventObject = nil
                setLast("event-registration-ambiguous")
                return result(false, "event-registration-ambiguous", "observer registration threw")
            end
            state.observerRegistered = true
            state.eventObject = eventObject
        end

        state.actionTable = actionTable
        state.priorMethod = actionTable.exeLooped
        local replaced = pack(pcall(function()
            actionTable.exeLooped = state.wrapper
        end))
        if not replaced[1] or actionTable.exeLooped ~= state.wrapper then
            state.actionTable = nil
            state.priorMethod = nil
            setLast("method-replacement-failed")
            return result(false, "method-replacement-failed", "ISFitnessAction.exeLooped could not be replaced")
        end

        state.installed = true
        state.captureEnabled = true
        state.ownershipReason = nil
        setLast("installed")
        return result(true, "installed", "exercise capture installed")
    end

    function instance.verifyOwnership()
        if state.authorityKnown and not state.authoritative then
            return result(true, "non-authoritative", "exercise capture is inert")
        end
        if not state.installed then
            setLast("not-installed")
            return result(false, "not-installed", "exercise capture is not installed")
        end
        if not state.captureEnabled then
            return result(false, state.ownershipReason or "capture-disabled", "exercise capture is disabled")
        end

        local lost = ownershipResult()
        if lost ~= nil then
            return lost
        end
        setLast("ownership-verified")
        return result(true, "ownership-verified", "exercise capture ownership is intact")
    end

    function instance.status()
        local actionTableOwned = state.installed and globals.ISFitnessAction == state.actionTable
        local wrapperOwned = actionTableOwned and state.actionTable.exeLooped == state.wrapper
        local events = globals.Events
        local eventOwned = state.installed and type(events) == "table" and events.AddXP == state.eventObject

        return {
            installed = state.installed,
            captureEnabled = state.captureEnabled,
            authorityKnown = state.authorityKnown,
            authoritative = state.authorityKnown and state.authoritative or false,
            serverRoute = state.authorityKnown and state.serverRoute or false,
            observerRegistered = state.observerRegistered,
            actionTableOwned = actionTableOwned,
            wrapperOwned = wrapperOwned,
            eventOwned = eventOwned,
            ownershipReason = state.ownershipReason,
            lastCode = state.lastCode,
        }
    end

    return instance
end

return ExerciseXpSource
