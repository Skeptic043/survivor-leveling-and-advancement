local InferredXpSource = {}

local FLUSH_INTERVAL_MS = 1000

local function isFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isSafePerkId(value)
    return type(value) == "string" and value ~= ""
end

local function weakKeys()
    return setmetatable({}, { __mode = "k" })
end

local function isEmpty(value)
    for _ in pairs(value) do
        return false
    end
    return true
end

local function requireTable(value, name)
    if type(value) ~= "table" then
        error(name .. " is required")
    end
    return value
end

local function requireFunction(value, name)
    if type(value) ~= "function" then
        error(name .. " is required")
    end
    return value
end

function InferredXpSource.create(dependencies)
    dependencies = requireTable(dependencies, "dependencies")
    local environment = requireTable(dependencies.environment, "environment")
    local globals = requireTable(environment.globals, "environment.globals")
    local authority = requireTable(dependencies.authority, "authority")
    local clock = requireTable(dependencies.clock, "clock")
    local claims = requireTable(dependencies.exactXpClaims, "exactXpClaims")
    local perkIdentity = requireTable(dependencies.perkIdentity, "perkIdentity")
    local positionReader = requireTable(dependencies.positionReader, "positionReader")
    local positionArithmetic = requireTable(dependencies.positionArithmetic, "positionArithmetic")
    local enabledSetting = requireTable(dependencies.enabledSetting, "enabledSetting")
    local multiplierResolver = requireTable(dependencies.sandboxMultiplier, "sandboxMultiplier")
    local awardHandler = requireTable(dependencies.awardHandler, "awardHandler")

    requireFunction(authority.describe, "authority.describe")
    requireFunction(clock.now, "clock.now")
    requireFunction(claims.consume, "exactXpClaims.consume")
    requireFunction(perkIdentity.resolve, "perkIdentity.resolve")
    requireFunction(positionReader.read, "positionReader.read")
    requireFunction(positionArithmetic.previous, "positionArithmetic.previous")
    requireFunction(enabledSetting.read, "enabledSetting.read")
    requireFunction(multiplierResolver.resolve, "sandboxMultiplier.resolve")
    requireFunction(awardHandler.process, "awardHandler.process")

    local state = {
        authorityResolved = false,
        authoritative = false,
        installed = false,
        enabled = false,
        captureEnabled = false,
        eventsOwned = false,
        ownershipLost = false,
        ownershipReason = nil,
        lastCode = "created",
        addXpEvent = nil,
        onTickEvent = nil,
        registeredAddXpEvent = nil,
        registeredOnTickEvent = nil,
        pendingCount = 0,
    }
    local ambiguousAddXp = weakKeys()
    local ambiguousOnTick = weakKeys()
    local pendingByPlayer = weakKeys()
    local ignoredByPlayer = weakKeys()

    local source = {}
    local addXpObserver
    local onTickObserver

    local function result(ok, code, extra)
        local value = extra or {}
        value.ok = ok
        value.code = code
        return value
    end

    local function pendingFor(player, create)
        local pending = pendingByPlayer[player]
        if pending == nil and create then
            pending = weakKeys()
            pendingByPlayer[player] = pending
        end
        return pending
    end

    local function removeBatch(batch)
        local pending = pendingFor(batch.player, false)
        if pending == nil or pending[batch.perk] ~= batch then
            return false
        end
        pending[batch.perk] = nil
        if isEmpty(pending) then
            pendingByPlayer[batch.player] = nil
        end
        state.pendingCount = state.pendingCount - 1
        return true
    end

    local function pushIgnore(player, perk)
        local ignored = ignoredByPlayer[player]
        if ignored == nil then
            ignored = weakKeys()
            ignoredByPlayer[player] = ignored
        end
        ignored[perk] = (ignored[perk] or 0) + 1
    end

    local function popIgnore(player, perk)
        local ignored = ignoredByPlayer[player]
        if ignored == nil then
            return
        end
        local depth = ignored[perk]
        if depth == nil or depth <= 1 then
            ignored[perk] = nil
        else
            ignored[perk] = depth - 1
        end
        if isEmpty(ignored) then
            ignoredByPlayer[player] = nil
        end
    end

    local function isIgnored(player, perk)
        local ignored = ignoredByPlayer[player]
        return ignored ~= nil and ignored[perk] ~= nil
    end

    local function flushBatch(batch)
        if not removeBatch(batch) then
            return result(true, "nothing-pending", { flushed = 0, dropped = 0 })
        end
        if not state.captureEnabled then
            state.lastCode = "capture-disabled"
            return result(false, "capture-disabled", { flushed = 0, dropped = 1 })
        end

        local appliedDelta = batch.latestPosition - batch.firstPosition
        if not isFinite(batch.summedBase) or batch.summedBase <= 0
            or not isFinite(appliedDelta) or appliedDelta <= 0 then
            state.lastCode = "invalid-batch"
            return result(false, "invalid-batch", { flushed = 0, dropped = 1 })
        end

        local award = {
            perkId = batch.perkId,
            baseAward = batch.summedBase,
            appliedDelta = appliedDelta,
            actualPositionBefore = batch.firstPosition,
            actualPositionAfter = batch.latestPosition,
        }
        pushIgnore(batch.player, batch.perk)
        local called, handled = pcall(awardHandler.process, batch.player, award)
        popIgnore(batch.player, batch.perk)
        if not called then
            state.lastCode = "handler-threw"
            return result(false, "handler-threw", { flushed = 0, dropped = 1 })
        end
        if type(handled) ~= "table" or handled.ok ~= true then
            state.lastCode = "handler-failed"
            return result(false, "handler-failed", { flushed = 0, dropped = 1 })
        end
        state.lastCode = "batch-flushed"
        return result(true, "batch-flushed", { flushed = 1, dropped = 0 })
    end

    local function collectBatches(player, perkId)
        local batches = {}
        if player ~= nil then
            local pending = pendingFor(player, false)
            if pending ~= nil then
                for _, batch in pairs(pending) do
                    if perkId == nil or batch.perkId == perkId then
                        batches[#batches + 1] = batch
                    end
                end
            end
        else
            for _, pending in pairs(pendingByPlayer) do
                for _, batch in pairs(pending) do
                    batches[#batches + 1] = batch
                end
            end
        end
        table.sort(batches, function(left, right)
            if left.perkId == right.perkId then
                return left.startTime < right.startTime
            end
            return left.perkId < right.perkId
        end)
        return batches
    end

    local function flushBatches(batches)
        local flushed = 0
        local dropped = 0
        local firstFailure = nil
        for index = 1, #batches do
            local outcome = flushBatch(batches[index])
            flushed = flushed + outcome.flushed
            dropped = dropped + outcome.dropped
            if not outcome.ok and firstFailure == nil then
                firstFailure = outcome.code
            end
        end
        if firstFailure ~= nil then
            state.lastCode = firstFailure
            return result(false, firstFailure, { flushed = flushed, dropped = dropped })
        end
        if flushed == 0 then
            state.lastCode = "nothing-pending"
            return result(true, "nothing-pending", { flushed = 0, dropped = 0 })
        end
        return result(true, "batches-flushed", { flushed = flushed, dropped = 0 })
    end

    local function flushExactPlayerPerk(player, perk)
        local pending = pendingFor(player, false)
        if pending == nil then
            return result(true, "nothing-pending", { flushed = 0, dropped = 0 })
        end
        local batch = pending[perk]
        if batch == nil then
            return result(true, "nothing-pending", { flushed = 0, dropped = 0 })
        end
        return flushBatch(batch)
    end

    local function readEnabled()
        local called, value = pcall(enabledSetting.read)
        if not called or type(value) ~= "table" or value.ok ~= true or type(value.enabled) ~= "boolean" then
            state.enabled = false
            state.lastCode = called and "setting-failed" or "setting-threw"
            return nil
        end
        state.enabled = value.enabled
        return value.enabled
    end

    local function readNow()
        local called, value = pcall(clock.now)
        if not called or not isFinite(value) or value < 0 then
            local batches = collectBatches(nil, nil)
            for index = 1, #batches do
                removeBatch(batches[index])
            end
            state.lastCode = called and "clock-failed" or "clock-threw"
            return nil
        end
        return value
    end

    local function resolvePerk(perk)
        local called, value = pcall(perkIdentity.resolve, perk)
        if not called or type(value) ~= "table" or value.ok ~= true or not isSafePerkId(value.perkId) then
            state.lastCode = called and "perk-identity-failed" or "perk-identity-threw"
            return nil
        end
        return value.perkId
    end

    local function readPosition(player, perkId)
        local called, value = pcall(positionReader.read, player, perkId)
        if not called or type(value) ~= "table" or value.ok ~= true
            or not isFinite(value.position) or value.position < 0 then
            state.lastCode = called and "position-failed" or "position-threw"
            return nil
        end
        return value.position
    end

    local function previousPosition(positionAfter, eventAmount)
        local called, value = pcall(positionArithmetic.previous, positionAfter, eventAmount)
        if not called or type(value) ~= "table" or value.ok ~= true
            or not isFinite(value.positionBefore) or value.positionBefore < 0 then
            state.lastCode = called and "position-arithmetic-failed" or "position-arithmetic-threw"
            return nil
        end
        return value.positionBefore
    end

    local function resolveMultiplier(player, perkId)
        local called, value = pcall(multiplierResolver.resolve, player, perkId)
        if not called or type(value) ~= "table" or value.ok ~= true
            or not isFinite(value.multiplier) or value.multiplier <= 0 then
            state.lastCode = called and "multiplier-failed" or "multiplier-threw"
            return nil
        end
        return value.multiplier
    end

    local function findOtherPerkBatch(player, perk, perkId)
        local pending = pendingFor(player, false)
        if pending == nil then
            return nil
        end
        for otherPerk, batch in pairs(pending) do
            if otherPerk ~= perk and batch.perkId == perkId then
                return batch
            end
        end
        return nil
    end

    local function startBatch(player, perk, perkId, firstPosition, latestPosition, base, multiplier, now)
        local pending = pendingFor(player, true)
        pending[perk] = {
            player = player,
            perk = perk,
            perkId = perkId,
            firstPosition = firstPosition,
            latestPosition = latestPosition,
            summedBase = base,
            multiplier = multiplier,
            startTime = now,
        }
        state.pendingCount = state.pendingCount + 1
        state.lastCode = "batch-started"
    end

    local function handleAddXp(player, perk, amount)
        if not state.captureEnabled then
            return
        end
        if not isFinite(amount) or amount <= 0 then
            state.lastCode = "event-ignored"
            return
        end

        local consumed, claimResult = pcall(claims.consume, player, perk, amount)
        if not consumed or type(claimResult) ~= "table" or claimResult.ok ~= true
            or type(claimResult.claimed) ~= "boolean" then
            state.lastCode = consumed and "claim-failed" or "claim-threw"
            return
        end
        if claimResult.claimed then
            local flushed = flushExactPlayerPerk(player, perk)
            if flushed.ok then
                state.lastCode = "exact-claimed"
            end
            return
        end
        if player == nil or perk == nil then
            state.lastCode = "invalid-event-identity"
            return
        end
        if isIgnored(player, perk) then
            state.lastCode = "handler-event-ignored"
            return
        end

        local enabled = readEnabled()
        if enabled ~= true then
            if enabled == false then
                state.lastCode = "inference-disabled"
            end
            return
        end
        local perkId = resolvePerk(perk)
        if perkId == nil then
            return
        end
        local position = readPosition(player, perkId)
        if position == nil then
            return
        end
        local multiplier = resolveMultiplier(player, perkId)
        if multiplier == nil then
            return
        end
        local inferredBase = amount / multiplier
        local firstPosition = previousPosition(position, amount)
        if firstPosition == nil then
            return
        end
        local movement = position - firstPosition
        if not isFinite(inferredBase) or inferredBase <= 0
            or not isFinite(firstPosition) or firstPosition < 0
            or not isFinite(movement) or movement <= 0 then
            state.lastCode = "invalid-boundary"
            return
        end
        local now = readNow()
        if now == nil then
            return
        end

        local otherBatch = findOtherPerkBatch(player, perk, perkId)
        if otherBatch ~= nil then
            flushBatch(otherBatch)
        end
        local pending = pendingFor(player, false)
        local batch = pending ~= nil and pending[perk] or nil
        if batch ~= nil then
            local age = now - batch.startTime
            local baseSum = batch.summedBase + inferredBase
            local contiguous = firstPosition == batch.latestPosition
            if age < 0 or age >= FLUSH_INTERVAL_MS or batch.multiplier ~= multiplier
                or not contiguous or not isFinite(baseSum) then
                flushBatch(batch)
                batch = nil
            else
                batch.latestPosition = position
                batch.summedBase = baseSum
                state.lastCode = "batch-extended"
            end
        end
        if batch == nil then
            startBatch(player, perk, perkId, firstPosition, position, inferredBase, multiplier, now)
        end
    end

    local function handleTick()
        if not state.captureEnabled or state.pendingCount == 0 then
            return
        end
        local now = readNow()
        if now == nil then
            return
        end
        local due = {}
        for _, pending in pairs(pendingByPlayer) do
            for _, batch in pairs(pending) do
                if now - batch.startTime >= FLUSH_INTERVAL_MS then
                    due[#due + 1] = batch
                end
            end
        end
        for index = 1, #due do
            flushBatch(due[index])
        end
    end

    addXpObserver = function(player, perk, amount)
        handleAddXp(player, perk, amount)
    end
    onTickObserver = function()
        handleTick()
    end

    local function describeAuthority()
        local called, descriptor = pcall(authority.describe)
        if not called then
            state.lastCode = "authority-threw"
            return result(false, "authority-threw")
        end
        if type(descriptor) ~= "table" or descriptor.ok ~= true
            or type(descriptor.authoritative) ~= "boolean" then
            state.lastCode = "authority-failed"
            return result(false, "authority-failed")
        end
        state.authorityResolved = true
        state.authoritative = descriptor.authoritative
        if not descriptor.authoritative then
            state.lastCode = "non-authoritative"
            return result(true, "non-authoritative")
        end
        return result(true, "authoritative")
    end

    local function currentEvents()
        local events = globals.Events
        if type(events) ~= "table" then
            return nil, nil, nil, nil, "events-unavailable"
        end
        local addXpEvent = events.AddXP
        local onTickEvent = events.OnTick
        if type(addXpEvent) ~= "table" or type(addXpEvent.Add) ~= "function" then
            return nil, nil, nil, nil, "addxp-event-unavailable"
        end
        if type(onTickEvent) ~= "table" or type(onTickEvent.Add) ~= "function" then
            return nil, nil, nil, nil, "ontick-event-unavailable"
        end
        return addXpEvent, addXpEvent.Add, onTickEvent, onTickEvent.Add, nil
    end

    function source.install()
        if state.ownershipLost then
            state.lastCode = state.ownershipReason or "ownership-lost"
            return result(false, state.lastCode)
        end
        if not state.authorityResolved then
            local described = describeAuthority()
            if not described.ok or not state.authoritative then
                return described
            end
        elseif not state.authoritative then
            state.lastCode = "non-authoritative"
            return result(true, "non-authoritative")
        end
        if state.installed then
            local verified = source.verifyOwnership()
            if not verified.ok then
                return verified
            end
            state.lastCode = "already-installed"
            return result(true, "already-installed")
        end

        local addXpEvent, addXpAdd, onTickEvent, onTickAdd, unavailable = currentEvents()
        if unavailable ~= nil then
            state.lastCode = unavailable
            return result(false, unavailable)
        end
        if state.registeredAddXpEvent ~= addXpEvent then
            if ambiguousAddXp[addXpEvent] then
                state.lastCode = "addxp-registration-ambiguous"
                return result(false, "addxp-registration-ambiguous")
            end
            local registered = pcall(addXpAdd, addXpObserver)
            if not registered then
                ambiguousAddXp[addXpEvent] = true
                state.lastCode = "addxp-registration-threw"
                return result(false, "addxp-registration-threw")
            end
            state.registeredAddXpEvent = addXpEvent
        end
        if state.registeredOnTickEvent ~= onTickEvent then
            if ambiguousOnTick[onTickEvent] then
                state.lastCode = "ontick-registration-ambiguous"
                return result(false, "ontick-registration-ambiguous")
            end
            local registered = pcall(onTickAdd, onTickObserver)
            if not registered then
                ambiguousOnTick[onTickEvent] = true
                state.lastCode = "ontick-registration-threw"
                return result(false, "ontick-registration-threw")
            end
            state.registeredOnTickEvent = onTickEvent
        end

        state.addXpEvent = addXpEvent
        state.onTickEvent = onTickEvent
        state.installed = true
        state.captureEnabled = true
        state.eventsOwned = true
        state.lastCode = "installed"
        return result(true, "installed")
    end

    function source.verifyOwnership()
        if not state.authorityResolved then
            state.lastCode = "not-installed"
            return result(false, "not-installed")
        end
        if not state.authoritative then
            state.lastCode = "non-authoritative"
            return result(true, "non-authoritative")
        end
        if not state.installed then
            state.lastCode = "not-installed"
            return result(false, "not-installed")
        end
        local events = globals.Events
        local reason = nil
        if type(events) ~= "table" or events.AddXP ~= state.addXpEvent then
            reason = "addxp-event-replaced"
        elseif events.OnTick ~= state.onTickEvent then
            reason = "ontick-event-replaced"
        end
        if reason ~= nil then
            state.captureEnabled = false
            state.eventsOwned = false
            state.ownershipLost = true
            state.ownershipReason = reason
            local batches = collectBatches(nil, nil)
            for index = 1, #batches do
                removeBatch(batches[index])
            end
            state.lastCode = reason
            return result(false, reason)
        end
        state.lastCode = "ownership-verified"
        return result(true, "ownership-verified")
    end

    function source.flushPlayerPerk(player, perkId)
        if player == nil then
            return result(false, "invalid-player", { flushed = 0, dropped = 0 })
        end
        if not isSafePerkId(perkId) then
            return result(false, "invalid-perk-id", { flushed = 0, dropped = 0 })
        end
        return flushBatches(collectBatches(player, perkId))
    end

    function source.flushPlayer(player)
        if player == nil then
            return result(false, "invalid-player", { flushed = 0, dropped = 0 })
        end
        return flushBatches(collectBatches(player, nil))
    end

    function source.flushAll()
        return flushBatches(collectBatches(nil, nil))
    end

    function source.status()
        return {
            authoritative = state.authoritative,
            installed = state.installed,
            enabled = state.enabled,
            captureEnabled = state.captureEnabled,
            eventsOwned = state.eventsOwned,
            pendingBatches = state.pendingCount,
            lastCode = state.lastCode,
            ownershipReason = state.ownershipReason,
        }
    end

    return source
end

return InferredXpSource
