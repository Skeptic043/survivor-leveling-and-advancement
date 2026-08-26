local AdminSession = {}

local MAX_SAFE_INTEGER = 9007199254740991

local function failure(code, detail)
    return { ok = false, code = code, detail = detail, committed = false }
end

local function finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function safeInteger(value)
    return finite(value)
        and value >= 0
        and value <= MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function positiveSafeInteger(value)
    return safeInteger(value) and value > 0
end

local function exactPlainTable(value, allowed, required)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do
        if allowed[key] ~= true then return false end
    end
    for index = 1, #required do
        if rawget(value, required[index]) == nil then return false end
    end
    return true
end

local function cloneValue(value, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "string" then
        return value
    end
    if valueType == "number" then
        if not finite(value) then return nil, "non_finite_number" end
        return value
    end
    if valueType ~= "table" or getmetatable(value) ~= nil then
        return nil, "unsupported_value"
    end
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

local function protectedCall(method, ...)
    local called, result = pcall(method, ...)
    if not called then return nil, "threw" end
    return result, nil
end

local function validateStateShape(state)
    if type(state) ~= "table" or getmetatable(state) ~= nil then
        return failure("invalid_state", "loaded state must be a plain table")
    end
    if state.accountingMode ~= "Tracked" and state.accountingMode ~= "Free" then
        return failure("invalid_state", "accountingMode is invalid")
    end
    if not safeInteger(state.revision) then
        return failure("invalid_state", "revision must be a nonnegative safe integer")
    end
    local survivor = state.survivor
    if not exactPlainTable(
        survivor,
        { level = true, xpIntoLevel = true, spent = true },
        { "level", "xpIntoLevel", "spent" }
    ) then
        return failure("invalid_state", "survivor state is malformed")
    end
    if not safeInteger(survivor.level)
        or not finite(survivor.xpIntoLevel)
        or survivor.xpIntoLevel < 0
        or not safeInteger(survivor.spent)
        or survivor.spent > survivor.level then
        return failure("invalid_state", "survivor values are impossible")
    end
    return { ok = true }
end

local function validateRequest(request)
    if type(request) ~= "table" or getmetatable(request) ~= nil then
        return failure("invalid_request", "request must be a plain table")
    end
    local kind = rawget(request, "kind")
    if kind == "awardSurvivorXp" then
        if not exactPlainTable(
            request,
            { kind = true, expectedRevision = true, amount = true },
            { "kind", "expectedRevision", "amount" }
        ) then
            return failure("invalid_request", "XP request fields are invalid")
        end
        if not safeInteger(request.expectedRevision) then
            return failure("invalid_request", "expectedRevision must be a nonnegative safe integer")
        end
        if not finite(request.amount) or request.amount <= 0 then
            return failure("invalid_request", "amount must be finite and positive")
        end
        return { ok = true, kind = kind }
    end
    if kind == "awardSurvivorLevels" then
        if not exactPlainTable(
            request,
            { kind = true, expectedRevision = true, count = true },
            { "kind", "expectedRevision", "count" }
        ) then
            return failure("invalid_request", "level request fields are invalid")
        end
        if not safeInteger(request.expectedRevision) then
            return failure("invalid_request", "expectedRevision must be a nonnegative safe integer")
        end
        if not positiveSafeInteger(request.count) then
            return failure("invalid_request", "count must be a positive safe integer")
        end
        return { ok = true, kind = kind }
    end
    return failure("invalid_request", "kind is invalid")
end

local function validateEconomyResult(result, allowed, required)
    return exactPlainTable(result, allowed, required) and result.ok == true
end

function AdminSession.create(dependencies)
    if not exactPlainTable(
        dependencies,
        { store = true, catalog = true, ownerSession = true, SurvivorEconomy = true },
        { "store", "catalog", "ownerSession", "SurvivorEconomy" }
    ) then
        return failure("invalid_dependencies", "dependencies must be an exact plain table")
    end

    local store = dependencies.store
    if type(store) ~= "table"
        or getmetatable(store) ~= nil
        or type(store.load) ~= "function"
        or type(store.save) ~= "function" then
        return failure("invalid_dependencies", "store.load and store.save are required")
    end
    local catalog = dependencies.catalog
    if type(catalog) ~= "table"
        or getmetatable(catalog) ~= nil
        or type(catalog.resolver) ~= "table"
        or getmetatable(catalog.resolver) ~= nil
        or type(catalog.resolver.loadOptions) ~= "table"
        or getmetatable(catalog.resolver.loadOptions) ~= nil then
        return failure("invalid_dependencies", "catalog.resolver.loadOptions is required")
    end
    local ownerSession = dependencies.ownerSession
    if type(ownerSession) ~= "table"
        or getmetatable(ownerSession) ~= nil
        or type(ownerSession.isReady) ~= "function" then
        return failure("invalid_dependencies", "ownerSession.isReady is required")
    end
    local economy = dependencies.SurvivorEconomy
    if type(economy) ~= "table"
        or getmetatable(economy) ~= nil
        or type(economy.nextLevelCost) ~= "function"
        or type(economy.availableAp) ~= "function"
        or type(economy.applyXp) ~= "function" then
        return failure("invalid_dependencies", "SurvivorEconomy capabilities are required")
    end

    local load = store.load
    local save = store.save
    local loadOptions = catalog.resolver.loadOptions
    local isReady = ownerSession.isReady
    local nextLevelCost = economy.nextLevelCost
    local availableAp = economy.availableAp
    local applyXp = economy.applyXp
    local session = {}

    local function requireReady(target)
        if target == nil then return failure("invalid_target", "target is required") end
        local ready, callError = protectedCall(isReady, target)
        if callError then return failure("readiness_threw", "ownerSession.isReady threw") end
        if type(ready) ~= "boolean" then
            return failure("readiness_invalid", "ownerSession.isReady returned a malformed result")
        end
        if not ready then return failure("not_ready", "target is not ready") end
        return { ok = true }
    end

    local function loadState(target)
        local loaded, callError = protectedCall(load, target, loadOptions)
        if callError then return failure("store_load_threw", "store.load threw") end
        if type(loaded) ~= "table" or getmetatable(loaded) ~= nil then
            return failure("store_load_invalid", "store.load returned a malformed result")
        end
        if loaded.ok ~= true then
            return failure("store_load_failed", "store.load failed")
        end
        if not exactPlainTable(loaded, { ok = true, state = true }, { "ok", "state" })
            or type(loaded.state) ~= "table" then
            return failure("store_load_invalid", "store.load returned a malformed result")
        end
        local valid = validateStateShape(loaded.state)
        if not valid.ok then return valid end
        return { ok = true, state = loaded.state }
    end

    local function summaryFor(state)
        local cost, costError = protectedCall(nextLevelCost, state.survivor.level)
        if costError then return failure("economy_cost_threw", "SurvivorEconomy.nextLevelCost threw") end
        if not validateEconomyResult(cost, { ok = true, cost = true }, { "ok", "cost" })
            or not finite(cost.cost)
            or cost.cost <= 0
            or state.survivor.xpIntoLevel >= cost.cost then
            return failure("invalid_state", "Survivor level cost is invalid")
        end

        local available, availableError = protectedCall(availableAp, state.survivor)
        if availableError then return failure("economy_ap_threw", "SurvivorEconomy.availableAp threw") end
        if not validateEconomyResult(
            available,
            { ok = true, availableAp = true },
            { "ok", "availableAp" }
        ) or not safeInteger(available.availableAp) then
            return failure("invalid_state", "Survivor available AP is invalid")
        end

        return {
            ok = true,
            summary = {
                accountingMode = state.accountingMode,
                revision = state.revision,
                level = state.survivor.level,
                xpIntoLevel = state.survivor.xpIntoLevel,
                xpForNextLevel = cost.cost,
                spent = state.survivor.spent,
                availableAp = available.availableAp,
            },
        }
    end

    local function saveState(target, state)
        local saved, callError = protectedCall(save, target, state)
        if callError then return failure("store_save_threw", "store.save threw") end
        if type(saved) ~= "table" or getmetatable(saved) ~= nil then
            return failure("store_save_invalid", "store.save returned a malformed result")
        end
        if saved.ok ~= true then return failure("store_save_failed", "store.save failed") end
        if not exactPlainTable(saved, { ok = true }, { "ok" }) then
            return failure("store_save_invalid", "store.save returned a malformed result")
        end
        return { ok = true }
    end

    function session.inspect(target)
        local ready = requireReady(target)
        if not ready.ok then return ready end
        local loaded = loadState(target)
        if not loaded.ok then return loaded end
        local summarized = summaryFor(loaded.state)
        if not summarized.ok then return summarized end
        return { ok = true, summary = summarized.summary }
    end

    function session.request(target, request)
        local requestValid = validateRequest(request)
        if not requestValid.ok then return requestValid end
        local ready = requireReady(target)
        if not ready.ok then return ready end
        local loaded = loadState(target)
        if not loaded.ok then return loaded end
        local current = summaryFor(loaded.state)
        if not current.ok then return current end

        if request.expectedRevision ~= loaded.state.revision then
            return {
                ok = true,
                applied = false,
                kind = request.kind,
                code = "stale_revision",
                detail = "expected revision does not match current revision",
                summary = current.summary,
            }
        end
        if loaded.state.revision == MAX_SAFE_INTEGER then
            return failure("revision_overflow", "revision cannot be incremented safely")
        end

        local candidate, cloneError = cloneValue(loaded.state)
        if not candidate then return failure("invalid_state", "loaded state cannot be detached: " .. cloneError) end
        local levelsGained
        local apGained

        if request.kind == "awardSurvivorXp" then
            local applied, callError = protectedCall(applyXp, candidate.survivor, request.amount)
            if callError then return failure("economy_apply_threw", "SurvivorEconomy.applyXp threw") end
            if not validateEconomyResult(
                applied,
                { ok = true, state = true, effects = true },
                { "ok", "state", "effects" }
            ) or not exactPlainTable(
                applied.state,
                { level = true, xpIntoLevel = true, spent = true },
                { "level", "xpIntoLevel", "spent" }
            ) or not exactPlainTable(
                applied.effects,
                { levelsGained = true, apGained = true },
                { "levelsGained", "apGained" }
            ) then
                return failure("economy_apply_invalid", "SurvivorEconomy.applyXp returned a malformed result")
            end
            local nextSurvivor = applied.state
            levelsGained = applied.effects.levelsGained
            apGained = applied.effects.apGained
            if not safeInteger(nextSurvivor.level)
                or not finite(nextSurvivor.xpIntoLevel)
                or nextSurvivor.xpIntoLevel < 0
                or nextSurvivor.spent ~= loaded.state.survivor.spent
                or nextSurvivor.level < loaded.state.survivor.level
                or not safeInteger(levelsGained)
                or not safeInteger(apGained)
                or levelsGained ~= nextSurvivor.level - loaded.state.survivor.level
                or apGained ~= levelsGained then
                return failure("economy_apply_invalid", "SurvivorEconomy.applyXp returned impossible progression")
            end
            candidate.survivor = {
                level = nextSurvivor.level,
                xpIntoLevel = nextSurvivor.xpIntoLevel,
                spent = nextSurvivor.spent,
            }
        else
            if request.count > MAX_SAFE_INTEGER - candidate.survivor.level then
                return failure("level_overflow", "Survivor level cannot be incremented safely")
            end
            candidate.survivor.level = candidate.survivor.level + request.count
            levelsGained = request.count
            apGained = request.count
        end

        candidate.revision = candidate.revision + 1
        local summarized = summaryFor(candidate)
        if not summarized.ok then return summarized end
        local saved = saveState(target, candidate)
        if not saved.ok then return saved end

        if request.kind == "awardSurvivorXp" then
            return {
                ok = true,
                applied = true,
                kind = request.kind,
                amount = request.amount,
                levelsGained = levelsGained,
                apGained = apGained,
                summary = summarized.summary,
            }
        end
        return {
            ok = true,
            applied = true,
            kind = request.kind,
            count = request.count,
            levelsGained = levelsGained,
            apGained = apGained,
            summary = summarized.summary,
        }
    end

    return { ok = true, session = session }
end

return AdminSession
