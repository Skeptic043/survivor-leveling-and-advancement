local SkillsViewModel = {}

local MAX_SAFE_INTEGER = 9007199254740991

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function nonnegativeInteger(value)
    return finite(value) and value >= 0 and value <= MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function positiveInteger(value)
    return nonnegativeInteger(value) and value > 0
end

local function safeId(value)
    if type(value) ~= "string" or #value == 0 or #value > 128 then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        local allowed = (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or byte == 95 or byte == 46 or byte == 58 or byte == 45
        if not allowed then return false end
    end
    return true
end

local function exactPlainTable(value, fields)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not fields[key] then return false end
    end
    for key in pairs(fields) do
        if rawget(value, key) == nil then return false end
    end
    return true
end

local function denseLength(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or not positiveInteger(key) then return nil end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if count ~= maximum then return nil end
    for index = 1, maximum do
        if rawget(value, index) == nil then return nil end
    end
    return maximum
end

local function copyMap(source)
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

local function copyConfiguration(config)
    if config.mode == "Global" then
        return { mode = config.mode, globalLimit = config.globalLimit }
    end
    if config.mode == "Free" then return { mode = config.mode } end
    return {
        mode = config.mode,
        perSkillDefault = config.perSkillDefault,
        perSkillOverrides = copyMap(config.perSkillOverrides),
    }
end

local function validateConfiguration(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    local mode = rawget(value, "mode")
    if mode == "Global" then
        if not exactPlainTable(value, { mode = true, globalLimit = true })
            or not nonnegativeInteger(rawget(value, "globalLimit")) then return nil end
        return { mode = mode, globalLimit = rawget(value, "globalLimit") }
    end
    if mode == "Free" then
        if not exactPlainTable(value, { mode = true }) then return nil end
        return { mode = mode }
    end
    if mode ~= "PerSkill"
        or not exactPlainTable(value, {
            mode = true,
            perSkillDefault = true,
            perSkillOverrides = true,
        })
        or not nonnegativeInteger(rawget(value, "perSkillDefault")) then return nil end
    local overrides = rawget(value, "perSkillOverrides")
    if type(overrides) ~= "table" or getmetatable(overrides) ~= nil then return nil end
    local detached = {}
    for perkId, limit in pairs(overrides) do
        if not safeId(perkId) or not nonnegativeInteger(limit) then return nil end
        detached[perkId] = limit
    end
    return {
        mode = mode,
        perSkillDefault = rawget(value, "perSkillDefault"),
        perSkillOverrides = detached,
    }
end

local function validateRows(value)
    local length = denseLength(value)
    if length == nil then return nil end
    local rows, seen = {}, {}
    for index = 1, length do
        local row = rawget(value, index)
        if not exactPlainTable(row, {
            perkId = true,
            currentLevel = true,
            effectiveMaximum = true,
        }) then return nil end
        local perkId = rawget(row, "perkId")
        local currentLevel = rawget(row, "currentLevel")
        local effectiveMaximum = rawget(row, "effectiveMaximum")
        if not safeId(perkId) or seen[perkId]
            or not nonnegativeInteger(currentLevel)
            or not positiveInteger(effectiveMaximum)
            or currentLevel > effectiveMaximum then return nil end
        seen[perkId] = true
        rows[index] = {
            perkId = perkId,
            currentLevel = currentLevel,
            effectiveMaximum = effectiveMaximum,
        }
    end
    return rows
end

local function validatedSnapshot(validate, snapshot)
    local called, result = pcall(validate, snapshot)
    if not called
        or not exactPlainTable(result, { ok = true, snapshot = true })
        or rawget(result, "ok") ~= true
        or type(rawget(result, "snapshot")) ~= "table"
        or getmetatable(rawget(result, "snapshot")) ~= nil then
        return nil
    end
    return rawget(result, "snapshot")
end

local function validOwnerSnapshot(snapshot, mode)
    if not exactPlainTable(snapshot, {
        protocolVersion = true,
        ready = true,
        sequence = true,
        revision = true,
        survivor = true,
        perks = true,
    })
        or rawget(snapshot, "protocolVersion") ~= 1
        or type(rawget(snapshot, "ready")) ~= "boolean"
        or not positiveInteger(rawget(snapshot, "sequence"))
        or not nonnegativeInteger(rawget(snapshot, "revision")) then return false end
    local survivor = rawget(snapshot, "survivor")
    if not exactPlainTable(survivor, {
        level = true,
        xpIntoLevel = true,
        xpForNextLevel = true,
        spent = true,
        availableAp = true,
    })
        or not nonnegativeInteger(rawget(survivor, "level"))
        or not finite(rawget(survivor, "xpIntoLevel"))
        or rawget(survivor, "xpIntoLevel") < 0
        or not positiveInteger(rawget(survivor, "xpForNextLevel"))
        or rawget(survivor, "xpIntoLevel") >= rawget(survivor, "xpForNextLevel")
        or not nonnegativeInteger(rawget(survivor, "spent"))
        or not nonnegativeInteger(rawget(survivor, "availableAp"))
        or rawget(survivor, "spent") > rawget(survivor, "level")
        or rawget(survivor, "availableAp") ~= rawget(survivor, "level") - rawget(survivor, "spent") then
        return false
    end
    local perks = rawget(snapshot, "perks")
    if type(perks) ~= "table" or getmetatable(perks) ~= nil then return false end
    if mode == "Free" then return true end
    for perkId, record in pairs(perks) do
        if not safeId(perkId)
            or not exactPlainTable(record, {
                effectiveMaximum = true,
                naturalPosition = true,
                highWaterPosition = true,
                activeTargets = true,
            })
            or not positiveInteger(rawget(record, "effectiveMaximum"))
            or not finite(rawget(record, "naturalPosition"))
            or rawget(record, "naturalPosition") < 0
            or not finite(rawget(record, "highWaterPosition"))
            or rawget(record, "highWaterPosition") < rawget(record, "naturalPosition") then return false end
        local targets = rawget(record, "activeTargets")
        local length = denseLength(targets)
        if length == nil then return false end
        local previousLevel, previousPosition = 0, rawget(record, "highWaterPosition")
        for index = 1, length do
            local target = rawget(targets, index)
            if not exactPlainTable(target, { targetLevel = true, targetPosition = true })
                or not positiveInteger(rawget(target, "targetLevel"))
                or rawget(target, "targetLevel") > rawget(record, "effectiveMaximum")
                or rawget(target, "targetLevel") <= previousLevel
                or not finite(rawget(target, "targetPosition"))
                or rawget(target, "targetPosition") <= previousPosition then return false end
            previousLevel = rawget(target, "targetLevel")
            previousPosition = rawget(target, "targetPosition")
        end
    end
    return true
end

local function activeCounts(snapshot)
    local perks = rawget(snapshot, "perks")
    if type(perks) ~= "table" or getmetatable(perks) ~= nil then return nil end
    local counts, total = {}, 0
    for perkId, record in pairs(perks) do
        if not safeId(perkId) or type(record) ~= "table" or getmetatable(record) ~= nil then return nil end
        local targets = rawget(record, "activeTargets")
        local count = denseLength(targets)
        if count == nil then return nil end
        counts[perkId] = count
        total = total + count
        if not nonnegativeInteger(total) then return nil end
    end
    return counts, total
end

local function activeTargets(record)
    if record == nil then return {}, false end
    if type(record) ~= "table" or getmetatable(record) ~= nil then return nil end
    local targets = rawget(record, "activeTargets")
    local length = denseLength(targets)
    if length == nil then return nil end
    local detached = {}
    for index = 1, length do
        local target = rawget(targets, index)
        if not exactPlainTable(target, { targetLevel = true, targetPosition = true })
            or not positiveInteger(rawget(target, "targetLevel"))
            or not finite(rawget(target, "targetPosition"))
            or rawget(target, "targetPosition") < 0 then return nil end
        detached[index] = {
            targetLevel = rawget(target, "targetLevel"),
            targetPosition = rawget(target, "targetPosition"),
        }
    end
    return detached, true
end

local function containsLevel(targets, targetLevel)
    for index = 1, #targets do
        if targets[index].targetLevel == targetLevel then return true end
    end
    return false
end

local function expectedLimit(config, perkId)
    if config.mode == "Global" then return config.globalLimit end
    if config.mode ~= "PerSkill" then return nil end
    local override = config.perSkillOverrides[perkId]
    return override == nil and config.perSkillDefault or override
end

local function validateAllotmentResult(result, config, perkId, addsTarget, activeByPerk, globalActive)
    local limited = config.mode ~= "Free"
    local fields = {
        ok = true,
        allowed = true,
        spendingEnabled = true,
        mode = true,
        bypassed = true,
        activeCount = true,
    }
    if limited then fields.limit = true end
    if not exactPlainTable(result, fields)
        or rawget(result, "ok") ~= true
        or type(rawget(result, "allowed")) ~= "boolean"
        or type(rawget(result, "spendingEnabled")) ~= "boolean"
        or rawget(result, "mode") ~= config.mode
        or type(rawget(result, "bypassed")) ~= "boolean"
        or rawget(result, "bypassed") ~= not addsTarget
        or not nonnegativeInteger(rawget(result, "activeCount")) then return nil end
    local expectedActive = config.mode == "Global" and addsTarget
        and globalActive or (activeByPerk[perkId] or 0)
    if rawget(result, "activeCount") ~= expectedActive then return nil end
    if limited then
        local limit = expectedLimit(config, perkId)
        if not nonnegativeInteger(rawget(result, "limit"))
            or rawget(result, "limit") ~= limit
            or rawget(result, "spendingEnabled") ~= (limit > 0) then return nil end
    elseif rawget(result, "allowed") ~= true or rawget(result, "spendingEnabled") ~= true then
        return nil
    end
    if not addsTarget and rawget(result, "allowed") ~= true then return nil end
    return result
end

local function evaluateAllotment(evaluate, config, perkId, addsTarget, activeByPerk, globalActive)
    local called, result = pcall(
        evaluate,
        copyConfiguration(config),
        perkId,
        copyMap(activeByPerk),
        addsTarget
    )
    if not called then return nil end
    return validateAllotmentResult(result, config, perkId, addsTarget, activeByPerk, globalActive)
end

local function disabledReason(pending, mismatch, atMaximum, red, availableAp, apCost, allotment, mastery, addsTarget)
    if pending then return "pending" end
    if mismatch then return "maximum_mismatch" end
    if atMaximum then return "at_maximum" end
    if red then return "red_recovery" end
    if availableAp < apCost then return "insufficient_ap" end
    if mastery and not allotment.spendingEnabled then return "allotment_disabled" end
    if addsTarget and not allotment.allowed then
        return allotment.spendingEnabled and "allotment_capacity" or "allotment_disabled"
    end
    return nil
end

local function freeDisabledReason(pending, atMaximum, availableAp, apCost)
    if pending then return "pending" end
    if atMaximum then return "at_maximum" end
    if availableAp < apCost then return "insufficient_ap" end
    return nil
end

local function snapshotHeader(snapshot)
    local survivor = rawget(snapshot, "survivor")
    if type(survivor) ~= "table" or getmetatable(survivor) ~= nil
        or not positiveInteger(rawget(snapshot, "sequence"))
        or not nonnegativeInteger(rawget(snapshot, "revision")) then return nil end
    return {
        sequence = rawget(snapshot, "sequence"),
        revision = rawget(snapshot, "revision"),
        survivor = {
            level = rawget(survivor, "level"),
            xpIntoLevel = rawget(survivor, "xpIntoLevel"),
            xpForNextLevel = rawget(survivor, "xpForNextLevel"),
            spent = rawget(survivor, "spent"),
            availableAp = rawget(survivor, "availableAp"),
        },
    }
end

function SkillsViewModel.create(dependencies)
    if not exactPlainTable(dependencies, { ClientOwnerState = true, Allotment = true }) then
        return failure("invalid_dependencies", "dependencies")
    end
    local clientOwnerState = rawget(dependencies, "ClientOwnerState")
    local allotment = rawget(dependencies, "Allotment")
    local validate = type(clientOwnerState) == "table" and rawget(clientOwnerState, "validate") or nil
    local evaluate = type(allotment) == "table" and rawget(allotment, "evaluate") or nil
    if type(validate) ~= "function" or type(evaluate) ~= "function" then
        return failure("invalid_dependencies", "callables")
    end

    local model = {}

    function model.build(input)
        if not exactPlainTable(input, {
            snapshot = true,
            allotment = true,
            pending = true,
            rows = true,
        }) or type(rawget(input, "pending")) ~= "boolean" then
            return failure("invalid_input", "fields")
        end
        local snapshot = validatedSnapshot(validate, rawget(input, "snapshot"))
        if snapshot == nil then
            return failure("invalid_snapshot", "ClientOwnerState.validate")
        end
        local config = validateConfiguration(rawget(input, "allotment"))
        if config == nil then return failure("invalid_allotment", "configuration") end
        if not validOwnerSnapshot(snapshot, config.mode) then
            return failure("invalid_snapshot", "ClientOwnerState.validate")
        end
        if rawget(snapshot, "ready") ~= true then
            return failure("invalid_snapshot", "not_ready")
        end
        local rows = validateRows(rawget(input, "rows"))
        if rows == nil then return failure("invalid_rows", "rows") end
        local header = snapshotHeader(snapshot)
        if header == nil then return failure("invalid_snapshot", "header") end

        if config.mode == "Free" then
            local viewRows = {}
            for index = 1, #rows do
                local source = rows[index]
                local atMaximum = source.currentLevel == source.effectiveMaximum
                local nextTargetLevel = not atMaximum and source.currentLevel + 1 or nil
                local apCost = nextTargetLevel ~= nil
                    and (nextTargetLevel == source.effectiveMaximum and 2 or 1) or nil
                local reason = freeDisabledReason(
                    rawget(input, "pending"),
                    atMaximum,
                    header.survivor.availableAp,
                    apCost or 0
                )
                local row = {
                    currentLevel = source.currentLevel,
                    effectiveMaximum = source.effectiveMaximum,
                    enabled = reason == nil,
                }
                if nextTargetLevel ~= nil then
                    row.nextTargetLevel = nextTargetLevel
                    row.apCost = apCost
                end
                if reason ~= nil then row.reasonCode = reason end
                viewRows[source.perkId] = row
            end
            return {
                ok = true,
                view = {
                    sequence = header.sequence,
                    revision = header.revision,
                    survivor = header.survivor,
                    allotment = { mode = "Free" },
                    pending = rawget(input, "pending"),
                    rows = viewRows,
                },
            }
        end

        local counts, globalActive = activeCounts(snapshot)
        if counts == nil then return failure("invalid_snapshot", "perks") end

        local viewRows = {}
        for index = 1, #rows do
            local source = rows[index]
            local record = rawget(snapshot.perks, source.perkId)
            local targets, published = activeTargets(record)
            if targets == nil then return failure("invalid_snapshot", "targets") end
            local atMaximum = source.currentLevel == source.effectiveMaximum
            local nextTargetLevel = not atMaximum and source.currentLevel + 1 or nil
            local mastery = nextTargetLevel ~= nil and nextTargetLevel == source.effectiveMaximum
            local reboost = nextTargetLevel ~= nil and containsLevel(targets, nextTargetLevel)
            local addsTarget = nextTargetLevel ~= nil and not mastery and not reboost
            local evaluated = evaluateAllotment(
                evaluate,
                config,
                source.perkId,
                addsTarget,
                counts,
                globalActive
            )
            if evaluated == nil then return failure("invalid_allotment", "Allotment.evaluate") end

            local mismatch = published and rawget(record, "effectiveMaximum") ~= source.effectiveMaximum
            local red = published and rawget(record, "naturalPosition") < rawget(record, "highWaterPosition")
            local apCost = nextTargetLevel ~= nil and (mastery and 2 or 1) or nil
            local reason = disabledReason(
                rawget(input, "pending"),
                mismatch,
                atMaximum,
                red,
                header.survivor.availableAp,
                apCost or 0,
                evaluated,
                mastery,
                addsTarget
            )
            local row = {
                currentLevel = source.currentLevel,
                effectiveMaximum = source.effectiveMaximum,
                enabled = reason == nil,
                activeTargets = targets,
            }
            if nextTargetLevel ~= nil then
                row.nextTargetLevel = nextTargetLevel
                row.apCost = apCost
            end
            if reason ~= nil then row.reasonCode = reason end
            if config.mode == "PerSkill" then
                row.activeCount = evaluated.activeCount
                row.limit = evaluated.limit
            end
            if published then
                row.naturalPosition = rawget(record, "naturalPosition")
                row.highWaterPosition = rawget(record, "highWaterPosition")
            end
            viewRows[source.perkId] = row
        end

        local allotmentView = { mode = config.mode }
        if config.mode == "Global" then
            allotmentView.activeCount = globalActive
            allotmentView.limit = config.globalLimit
        end
        return {
            ok = true,
            view = {
                sequence = header.sequence,
                revision = header.revision,
                survivor = header.survivor,
                allotment = allotmentView,
                pending = rawget(input, "pending"),
                rows = viewRows,
            },
        }
    end

    return { ok = true, model = model }
end

return SkillsViewModel
