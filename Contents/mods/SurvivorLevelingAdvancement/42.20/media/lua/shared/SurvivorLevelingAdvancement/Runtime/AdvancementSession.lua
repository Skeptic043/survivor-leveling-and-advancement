local MAX_SAFE_INTEGER = 9007199254740991

local function exactPlain(value, allowed)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    for key in pairs(allowed) do
        if rawget(value, key) == nil then return false end
    end
    return true
end

local function safeInteger(value, minimum)
    return type(value) == "number" and value == value and value >= minimum and value <= MAX_SAFE_INTEGER and value == math.floor(value)
end

local function safeId(value, maximum)
    if type(value) ~= "string" or #value == 0 or #value > maximum then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        local valid = (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
            or byte == 45 or byte == 46 or byte == 58 or byte == 95
        if not valid then return false end
    end
    return true
end

local function safeDetail(value)
    if type(value) ~= "string" or #value == 0 or #value > 120 then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte > 126 then return false end
    end
    return true
end

local function boundedDependencyDetail(result)
    if type(result) == "table" and safeId(rawget(result, "code"), 64) and safeDetail(rawget(result, "detail")) then
        local detail = rawget(result, "code") .. ":" .. rawget(result, "detail")
        if #detail <= 160 then return detail end
    end
    return "unavailable"
end

local function failure(code, detail, committed)
    local result = { ok = false, code = code, detail = detail }
    if committed ~= nil then result.committed = committed end
    return result
end

local function snapshotFrom(result)
    if not exactPlain(result, { ok = true, snapshot = true }) or rawget(result, "ok") ~= true then return nil, false end
    local snapshot = rawget(result, "snapshot")
    if type(snapshot) ~= "table" or getmetatable(snapshot) ~= nil then return nil, false end
    return snapshot, true
end

local function settingsFrom(result)
    if not exactPlain(result, { ok = true, settings = true }) or rawget(result, "ok") ~= true then return nil, false end
    local settings = rawget(result, "settings")
    if type(settings) ~= "table" or getmetatable(settings) ~= nil then return nil, false end
    return settings, true
end

local function apFailure(result)
    if not exactPlain(result, { ok = true, code = true, detail = true }) or rawget(result, "ok") ~= false then return nil, false end
    local code = rawget(result, "code")
    local detail = rawget(result, "detail")
    if not safeId(code, 64) or not safeDetail(detail) then return nil, false end
    return { code = code, detail = detail }, true
end

local function validIdArray(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    local length = #value
    for key, item in pairs(value) do
        if not safeInteger(key, 1) or key > length or not safeId(item, 128) then return false end
    end
    for index = 1, length do if rawget(value, index) == nil then return false end end
    return true
end

local function apSuccess(result, request)
    if not exactPlain(result, {
        ok = true, requestId = true, perkId = true, revision = true, spent = true, availableAp = true,
        apCost = true, mastered = true, addedTarget = true, clearedTargetIds = true, xpWriteInvoked = true,
        levelWriteInvoked = true, recovered = true,
    }) or rawget(result, "ok") ~= true then return nil, false end
    if rawget(result, "requestId") ~= rawget(request, "requestId") or rawget(result, "perkId") ~= rawget(request, "perkId")
        or not safeInteger(rawget(result, "revision"), 0) or not safeInteger(rawget(result, "spent"), 0)
        or not safeInteger(rawget(result, "availableAp"), 0) or (rawget(result, "apCost") ~= 1 and rawget(result, "apCost") ~= 2)
        or type(rawget(result, "mastered")) ~= "boolean" or type(rawget(result, "addedTarget")) ~= "boolean"
        or not validIdArray(rawget(result, "clearedTargetIds")) or type(rawget(result, "xpWriteInvoked")) ~= "boolean"
        or type(rawget(result, "levelWriteInvoked")) ~= "boolean" or type(rawget(result, "recovered")) ~= "boolean" then return nil, false end
    if rawget(result, "mastered") ~= (rawget(result, "apCost") == 2)
        or (rawget(result, "mastered") and rawget(result, "addedTarget"))
        or (not rawget(result, "mastered") and #rawget(result, "clearedTargetIds") ~= 0) then return nil, false end
    return { apCost = rawget(result, "apCost"), mastered = rawget(result, "mastered") }, true
end

local function validRequest(request)
    if not exactPlain(request, { perkId = true, requestId = true, expectedRevision = true }) then return false end
    return safeId(rawget(request, "perkId"), 128) and safeId(rawget(request, "requestId"), 64)
        and safeInteger(rawget(request, "expectedRevision"), 0)
end

local function create(dependencies)
    if not exactPlain(dependencies, { apTransaction = true, allotmentSettings = true, ownerSession = true }) then
        return failure("construction_invalid", "dependencies")
    end
    local apTransaction = rawget(dependencies, "apTransaction")
    local allotmentSettings = rawget(dependencies, "allotmentSettings")
    local ownerSession = rawget(dependencies, "ownerSession")
    if type(apTransaction) ~= "table" or getmetatable(apTransaction) ~= nil
        or type(allotmentSettings) ~= "table" or getmetatable(allotmentSettings) ~= nil
        or type(ownerSession) ~= "table" or getmetatable(ownerSession) ~= nil then
        return failure("construction_invalid", "dependencies")
    end
    local spend = rawget(apTransaction, "spend")
    local resolve = rawget(allotmentSettings, "resolve")
    local isReady = rawget(ownerSession, "isReady")
    local snapshot = rawget(ownerSession, "snapshot")
    if type(spend) ~= "function" or type(resolve) ~= "function" or type(isReady) ~= "function" or type(snapshot) ~= "function" then
        return failure("construction_invalid", "dependencies")
    end

    local session = {}
    function session.request(player, request)
        if not validRequest(request) then return failure("invalid_request", "request", false) end

        local readyCalled, ready = pcall(isReady, player)
        if not readyCalled or type(ready) ~= "boolean" then return failure("readiness_failed", "unavailable", false) end
        if ready ~= true then return failure("not_ready", "owner session not ready", false) end

        local settingsCalled, settingsResult = pcall(resolve, player, rawget(request, "perkId"))
        if not settingsCalled then return failure("settings_failed", "unavailable", false) end
        local settings, settingsValid = settingsFrom(settingsResult)
        if not settingsValid then return failure("settings_failed", boundedDependencyDetail(settingsResult), false) end

        local spendCalled, spendResult = pcall(spend, player, request, settings)
        if not spendCalled then return failure("ap_failed", "unavailable", false) end
        local rejected, rejectedValid = apFailure(spendResult)
        if rejectedValid then
            local result = {
                ok = true,
                applied = false,
                requestId = rawget(request, "requestId"),
                perkId = rawget(request, "perkId"),
                code = rejected.code,
                detail = rejected.detail,
            }
            if rejected.code == "stale_revision" then
                local projectionCalled, projectionResult = pcall(snapshot, player)
                if projectionCalled then
                    local staleSnapshot, staleValid = snapshotFrom(projectionResult)
                    if staleValid then result.snapshot = staleSnapshot end
                end
            end
            return result
        end
        local applied, appliedValid = apSuccess(spendResult, request)
        if not appliedValid then return failure("ap_failed", boundedDependencyDetail(spendResult), false) end

        local projectionCalled, projectionResult = pcall(snapshot, player)
        if not projectionCalled then return failure("post_commit_snapshot_failed", "unavailable", true) end
        local projected, projectionValid = snapshotFrom(projectionResult)
        if not projectionValid then return failure("post_commit_snapshot_failed", boundedDependencyDetail(projectionResult), true) end
        return {
            ok = true,
            applied = true,
            requestId = rawget(request, "requestId"),
            perkId = rawget(request, "perkId"),
            apCost = applied.apCost,
            mastered = applied.mastered,
            snapshot = projected,
        }
    end
    return { ok = true, session = session }
end

return { create = create }
