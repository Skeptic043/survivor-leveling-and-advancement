local Build42SkillsUi = {}

local MAX_SAFE_INTEGER = 9007199254740991
local REFRESH_MILLIS = 1000
local STATUS_LEFT_MARGIN = 4
local ADMIN_OUTBOARD_GAP = 4
local TARGET_R, TARGET_G, TARGET_B = 0.35, 0.72, 1.00
local POSITION_R, POSITION_G, POSITION_B = 0.12, 0.32, 0.65
local RECOVERY_R, RECOVERY_G, RECOVERY_B = 0.95, 0.25, 0.25
local RECOVERY_POSITION_R, RECOVERY_POSITION_G, RECOVERY_POSITION_B = 0.45, 0.08, 0.08

local REASON_KEYS = {
    pending = "IGUI_SLA_Reason_Pending",
    maximum_mismatch = "IGUI_SLA_Reason_MaximumMismatch",
    at_maximum = "IGUI_SLA_Reason_AtMaximum",
    red_recovery = "IGUI_SLA_Reason_RedRecovery",
    insufficient_ap = "IGUI_SLA_Reason_InsufficientAp",
    allotment_disabled = "IGUI_SLA_Reason_AllotmentDisabled",
    allotment_capacity = "IGUI_SLA_Reason_AllotmentCapacity",
}

local ADVANCEMENT_RESULT_KEYS = {
    no_ap = "IGUI_SLA_Reason_InsufficientAp",
    at_maximum = "IGUI_SLA_Reason_AtMaximum",
    red_recovery = "IGUI_SLA_Reason_RedRecovery",
    stale_revision = "IGUI_SLA_Advancement_Stale",
}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function nonnegativeInteger(value)
    return finite(value) and value >= 0 and value <= MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function positiveInteger(value)
    return nonnegativeInteger(value) and value > 0
end

local function safeId(value, maximum)
    if type(value) ~= "string" or #value == 0 or #value > maximum then return false end
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

local function safeText(value, maximum)
    if type(value) ~= "string" or #value == 0 or #value > maximum then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte > 126 then return false end
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

local function callable(value)
    return type(value) == "function"
end

local function method(value, name)
    if type(value) ~= "table" then return nil end
    local candidate = rawget(value, name)
    return callable(candidate) and candidate or nil
end

local function validSlot(value)
    return nonnegativeInteger(value) and value <= 3
end

local function weakKeys()
    return setmetatable({}, { __mode = "k" })
end

local function copyArray(source, maximum)
    if type(source) ~= "table" or getmetatable(source) ~= nil then return nil end
    local result = {}
    for level = 0, maximum do
        local value = rawget(source, level)
        if not finite(value) or value < 0 then return nil end
        if level > 0 and value <= result[level - 1] then return nil end
        result[level] = value
    end
    for key in pairs(source) do
        if type(key) ~= "number" or key < 0 or key > maximum
            or key ~= math.floor(key) then return nil end
    end
    return result
end

local function validOwner(owner)
    if not exactPlainTable(owner, {
        install = true,
        status = true,
        clientState = true,
        refreshOwner = true,
        setClientStateListener = true,
        requestAdvancement = true,
        advancementStatus = true,
        requestAdmin = true,
        adminStatus = true,
    }) then return false end
    for key in pairs(owner) do
        if not callable(rawget(owner, key)) then return false end
    end
    return true
end

local function exactSuccess(value, payload)
    local fields = { ok = true }
    if payload ~= nil then fields[payload] = true end
    return exactPlainTable(value, fields) and rawget(value, "ok") == true
end

local function validClientState(value)
    if exactPlainTable(value, { ok = true, present = true })
        and rawget(value, "ok") == true and rawget(value, "present") == false then
        return true, nil
    end
    if exactPlainTable(value, { ok = true, present = true, snapshot = true })
        and rawget(value, "ok") == true and rawget(value, "present") == true
        and type(rawget(value, "snapshot")) == "table"
        and getmetatable(rawget(value, "snapshot")) == nil then
        return true, rawget(value, "snapshot")
    end
    return false, nil
end

local function classifyAdvancementResult(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil
        or not safeId(rawget(value, "requestId"), 64)
        or not safeId(rawget(value, "perkId"), 128) then return false, nil end

    local appliedFields = {
        ok = true, applied = true, requestId = true, perkId = true,
        apCost = true, mastered = true, snapshotAccepted = true,
    }
    local appliedWithSnapshotCode = {
        ok = true, applied = true, requestId = true, perkId = true,
        apCost = true, mastered = true, snapshotAccepted = true, snapshotCode = true,
    }
    local applied = exactPlainTable(value, appliedFields)
        or exactPlainTable(value, appliedWithSnapshotCode)
    if applied then
        local snapshotAccepted = rawget(value, "snapshotAccepted")
        local snapshotCode = rawget(value, "snapshotCode")
        local snapshotShape = type(snapshotAccepted) == "boolean"
            and (snapshotCode == nil
                or snapshotAccepted == false and snapshotCode == "stale_snapshot")
        local apCost = rawget(value, "apCost")
        if rawget(value, "ok") ~= true or rawget(value, "applied") ~= true
            or (apCost ~= 1 and apCost ~= 2)
            or rawget(value, "mastered") ~= (apCost == 2) or not snapshotShape then
            return false, nil
        end
        return true, nil
    end

    local rejectionFields = {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true,
    }
    local rejectionWithSnapshot = {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true, snapshotAccepted = true,
    }
    local rejectionWithSnapshotCode = {
        ok = true, applied = true, requestId = true, perkId = true,
        code = true, detail = true, snapshotAccepted = true, snapshotCode = true,
    }
    local rejection = exactPlainTable(value, rejectionFields)
        or exactPlainTable(value, rejectionWithSnapshot)
        or exactPlainTable(value, rejectionWithSnapshotCode)
    if rejection then
        local code = rawget(value, "code")
        local snapshotAccepted = rawget(value, "snapshotAccepted")
        local snapshotCode = rawget(value, "snapshotCode")
        local snapshotShape = snapshotAccepted == nil and snapshotCode == nil
            or code == "stale_revision" and snapshotAccepted == true and snapshotCode == nil
            or code == "stale_revision" and snapshotAccepted == false
                and (snapshotCode == nil or snapshotCode == "stale_snapshot")
        if rawget(value, "ok") ~= true or rawget(value, "applied") ~= false
            or not safeId(code, 64) or not safeText(rawget(value, "detail"), 160)
            or not snapshotShape then return false, nil end
        return true, {
            perkId = rawget(value, "perkId"),
            key = ADVANCEMENT_RESULT_KEYS[code] or "IGUI_SLA_Advancement_Failed",
        }
    end

    if exactPlainTable(value, {
        ok = true, requestId = true, perkId = true, code = true,
        detail = true, committed = true,
    }) then
        local code = rawget(value, "code")
        local committed = rawget(value, "committed")
        if rawget(value, "ok") ~= false or not safeId(code, 64)
            or not safeText(rawget(value, "detail"), 160)
            or type(committed) ~= "boolean" then return false, nil end
        local key = committed and "IGUI_SLA_Advancement_Committed"
            or code == "send_failed" and "IGUI_SLA_Advancement_SendFailed"
            or ADVANCEMENT_RESULT_KEYS[code] or "IGUI_SLA_Advancement_Failed"
        return true, { perkId = rawget(value, "perkId"), key = key }
    end

    local appliedSnapshotFailure = exactPlainTable(value, {
        ok = true, applied = true, requestId = true, perkId = true, code = true,
        detail = true, committed = true, apCost = true, mastered = true,
    })
    local rejectedSnapshotFailure = exactPlainTable(value, {
        ok = true, applied = true, requestId = true, perkId = true, code = true,
        detail = true, committed = true, upstreamCode = true, upstreamDetail = true,
    })
    if not appliedSnapshotFailure and not rejectedSnapshotFailure then return false, nil end
    local code = rawget(value, "code")
    if rawget(value, "ok") ~= false or not safeId(code, 64)
        or not safeText(rawget(value, "detail"), 160)
        or type(rawget(value, "applied")) ~= "boolean" then return false, nil end
    if appliedSnapshotFailure then
        local apCost = rawget(value, "apCost")
        if rawget(value, "applied") ~= true or rawget(value, "committed") ~= true
            or (apCost ~= 1 and apCost ~= 2)
            or rawget(value, "mastered") ~= (apCost == 2) then return false, nil end
        return true, {
            perkId = rawget(value, "perkId"),
            key = "IGUI_SLA_Advancement_Committed",
        }
    end
    if rawget(value, "applied") ~= false or rawget(value, "committed") ~= false
        or not safeId(rawget(value, "upstreamCode"), 64)
        or not safeText(rawget(value, "upstreamDetail"), 160) then return false, nil end
    local key = code == "send_failed" and "IGUI_SLA_Advancement_SendFailed"
        or ADVANCEMENT_RESULT_KEYS[code] or "IGUI_SLA_Advancement_Failed"
    return true, { perkId = rawget(value, "perkId"), key = key }
end

local function validAdvancementStatus(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil
        or rawget(value, "ok") ~= true or type(rawget(value, "pending")) ~= "boolean" then
        return false, nil
    end
    if rawget(value, "pending") then
        return exactPlainTable(value, {
            ok = true, pending = true, requestId = true, perkId = true,
        }) and safeId(rawget(value, "requestId"), 64)
            and safeId(rawget(value, "perkId"), 128), true
    end
    if exactPlainTable(value, { ok = true, pending = true }) then return true, false, nil end
    if not exactPlainTable(value, { ok = true, pending = true, result = true }) then
        return false, nil
    end
    local valid, presentation = classifyAdvancementResult(rawget(value, "result"))
    return valid, false, presentation
end

local function validAcceptedRequest(value, perkId)
    if exactPlainTable(value, { ok = true, requestId = true })
        and rawget(value, "ok") == true and safeId(rawget(value, "requestId"), 64) then
        return true
    end
    if type(value) ~= "table" or getmetatable(value) ~= nil
        or rawget(value, "ok") ~= true or type(rawget(value, "applied")) ~= "boolean"
        or not safeId(rawget(value, "requestId"), 64)
        or rawget(value, "perkId") ~= perkId then return false end
    local allowed = {
        ok = true, applied = true, requestId = true, perkId = true,
        apCost = true, mastered = true, snapshotAccepted = true,
        snapshotCode = true, code = true, detail = true,
    }
    for key, item in pairs(value) do
        if type(key) ~= "string" or not allowed[key]
            or (type(item) ~= "boolean" and type(item) ~= "number" and type(item) ~= "string") then
            return false
        end
    end
    if rawget(value, "applied") then
        return (rawget(value, "apCost") == 1 or rawget(value, "apCost") == 2)
            and type(rawget(value, "mastered")) == "boolean"
            and type(rawget(value, "snapshotAccepted")) == "boolean"
    end
    return safeId(rawget(value, "code"), 64)
        and type(rawget(value, "detail")) == "string"
end

local function projectAllotment(settings)
    if type(settings) ~= "table" or getmetatable(settings) ~= nil then return nil end
    local fields = {
        survivorMultiplier = true,
        fitnessStrengthNormalization = true,
        automaticCurveNormalization = true,
        allotmentMode = true,
        globalLimit = true,
        perSkillDefault = true,
        perSkillOverrides = true,
        inheritanceEnabled = true,
        retainedRatio = true,
    }
    if not exactPlainTable(settings, fields)
        or not finite(rawget(settings, "survivorMultiplier"))
        or rawget(settings, "survivorMultiplier") < 0
        or not finite(rawget(settings, "fitnessStrengthNormalization"))
        or rawget(settings, "fitnessStrengthNormalization") < 0
        or type(rawget(settings, "automaticCurveNormalization")) ~= "boolean"
        or not nonnegativeInteger(rawget(settings, "globalLimit"))
        or not nonnegativeInteger(rawget(settings, "perSkillDefault"))
        or type(rawget(settings, "inheritanceEnabled")) ~= "boolean"
        or not finite(rawget(settings, "retainedRatio"))
        or rawget(settings, "retainedRatio") < 0
        or rawget(settings, "retainedRatio") > 1 then return nil end
    local mode = rawget(settings, "allotmentMode")
    if mode == "Global" then
        return { mode = mode, globalLimit = rawget(settings, "globalLimit") }
    end
    if mode == "Free" then return { mode = mode } end
    if mode ~= "PerSkill" then return nil end
    local overrides = rawget(settings, "perSkillOverrides")
    if type(overrides) ~= "table" or getmetatable(overrides) ~= nil then return nil end
    local detached = {}
    for perkId, limit in pairs(overrides) do
        if not safeId(perkId, 128) or not nonnegativeInteger(limit) then return nil end
        detached[perkId] = limit
    end
    return {
        mode = mode,
        perSkillDefault = rawget(settings, "perSkillDefault"),
        perSkillOverrides = detached,
    }
end

local function validModelView(value)
    if not exactPlainTable(value, {
        sequence = true,
        revision = true,
        survivor = true,
        allotment = true,
        pending = true,
        rows = true,
    }) or not positiveInteger(rawget(value, "sequence"))
        or not nonnegativeInteger(rawget(value, "revision"))
        or type(rawget(value, "pending")) ~= "boolean"
        or type(rawget(value, "survivor")) ~= "table"
        or type(rawget(value, "allotment")) ~= "table"
        or type(rawget(value, "rows")) ~= "table"
        or getmetatable(rawget(value, "survivor")) ~= nil
        or getmetatable(rawget(value, "allotment")) ~= nil
        or getmetatable(rawget(value, "rows")) ~= nil then return false end
    local survivor = rawget(value, "survivor")
    if not exactPlainTable(survivor, {
        level = true, xpIntoLevel = true, xpForNextLevel = true,
        spent = true, availableAp = true,
    }) or not nonnegativeInteger(rawget(survivor, "level"))
        or not finite(rawget(survivor, "xpIntoLevel")) or rawget(survivor, "xpIntoLevel") < 0
        or not positiveInteger(rawget(survivor, "xpForNextLevel"))
        or rawget(survivor, "xpIntoLevel") >= rawget(survivor, "xpForNextLevel")
        or not nonnegativeInteger(rawget(survivor, "spent"))
        or not nonnegativeInteger(rawget(survivor, "availableAp"))
        or rawget(survivor, "spent") > rawget(survivor, "level")
        or rawget(survivor, "availableAp") ~= rawget(survivor, "level") - rawget(survivor, "spent") then
        return false
    end
    local allotment = rawget(value, "allotment")
    local mode = rawget(allotment, "mode")
    if mode == "Global" then
        if not exactPlainTable(allotment, { mode = true, activeCount = true, limit = true })
            or not nonnegativeInteger(rawget(allotment, "activeCount"))
            or not nonnegativeInteger(rawget(allotment, "limit")) then return false end
    elseif mode == "PerSkill" or mode == "Free" then
        if not exactPlainTable(allotment, { mode = true }) then return false end
    else
        return false
    end
    for perkId, row in pairs(rawget(value, "rows")) do
        local allowed = {
            currentLevel = true, effectiveMaximum = true, nextTargetLevel = true,
            apCost = true, enabled = true, reasonCode = true, activeCount = true,
            limit = true, activeTargets = true, naturalPosition = true,
            highWaterPosition = true,
        }
        if not safeId(perkId, 128) or type(row) ~= "table" or getmetatable(row) ~= nil
            or type(rawget(row, "enabled")) ~= "boolean"
            or not nonnegativeInteger(rawget(row, "currentLevel"))
            or not positiveInteger(rawget(row, "effectiveMaximum"))
            or rawget(row, "currentLevel") > rawget(row, "effectiveMaximum") then return false end
        for key in pairs(row) do
            if type(key) ~= "string" or not allowed[key] then return false end
        end
        if (rawget(row, "nextTargetLevel") == nil) ~= (rawget(row, "apCost") == nil) then return false end
        if rawget(row, "nextTargetLevel") ~= nil then
            if not positiveInteger(rawget(row, "nextTargetLevel"))
                or rawget(row, "nextTargetLevel") ~= rawget(row, "currentLevel") + 1
                or rawget(row, "nextTargetLevel") > rawget(row, "effectiveMaximum")
                or (rawget(row, "apCost") ~= 1 and rawget(row, "apCost") ~= 2) then return false end
            if rawget(row, "apCost") ~= (rawget(row, "nextTargetLevel") == rawget(row, "effectiveMaximum") and 2 or 1) then
                return false
            end
        end
        if (rawget(row, "activeCount") == nil) ~= (rawget(row, "limit") == nil)
            or (rawget(row, "activeCount") ~= nil
                and (not nonnegativeInteger(rawget(row, "activeCount"))
                    or not nonnegativeInteger(rawget(row, "limit")))) then return false end
        if (mode == "PerSkill") ~= (rawget(row, "activeCount") ~= nil) then return false end
        if mode == "Free" then
            if rawget(row, "activeTargets") ~= nil
                or rawget(row, "naturalPosition") ~= nil
                or rawget(row, "highWaterPosition") ~= nil then return false end
        else
            local targets = rawget(row, "activeTargets")
            if type(targets) ~= "table" or getmetatable(targets) ~= nil then return false end
            local count, previousLevel, previousPosition = 0, 0, -1
            for key, target in pairs(targets) do
                if type(key) ~= "number" or not positiveInteger(key)
                    or not exactPlainTable(target, { targetLevel = true, targetPosition = true })
                    or not positiveInteger(rawget(target, "targetLevel"))
                    or rawget(target, "targetLevel") > rawget(row, "effectiveMaximum")
                    or not finite(rawget(target, "targetPosition"))
                    or rawget(target, "targetPosition") < 0 then return false end
                count = count + 1
            end
            for index = 1, count do
                local target = rawget(targets, index)
                if target == nil or rawget(target, "targetLevel") <= previousLevel
                    or rawget(target, "targetPosition") <= previousPosition then return false end
                previousLevel = rawget(target, "targetLevel")
                previousPosition = rawget(target, "targetPosition")
            end
            if (rawget(row, "naturalPosition") == nil) ~= (rawget(row, "highWaterPosition") == nil)
                or (rawget(row, "naturalPosition") ~= nil
                    and (not finite(rawget(row, "naturalPosition"))
                        or not finite(rawget(row, "highWaterPosition"))
                        or rawget(row, "naturalPosition") < 0
                        or rawget(row, "highWaterPosition") < rawget(row, "naturalPosition"))) then return false end
            if count > 0 and rawget(row, "naturalPosition") == nil then return false end
        end
        if rawget(row, "reasonCode") ~= nil and REASON_KEYS[rawget(row, "reasonCode")] == nil then return false end
        if mode == "Free" and rawget(row, "reasonCode") ~= nil
            and rawget(row, "reasonCode") ~= "pending"
            and rawget(row, "reasonCode") ~= "at_maximum"
            and rawget(row, "reasonCode") ~= "insufficient_ap" then return false end
        if rawget(row, "enabled") and rawget(row, "reasonCode") ~= nil then return false end
        if not rawget(row, "enabled") and rawget(row, "reasonCode") == nil then return false end
        if rawget(row, "enabled") and (rawget(row, "currentLevel") >= rawget(row, "effectiveMaximum")
            or rawget(row, "nextTargetLevel") == nil
            or not positiveInteger(rawget(row, "apCost"))) then return false end
    end
    return true
end

function Build42SkillsUi.create(dependencies)
    local dependencyFields = {
        ISCharacterInfo = true,
        ISSkillProgressBar = true,
        ISButton = true,
        ISPanel = true,
        owner = true,
        viewModel = true,
        settingsProvider = true,
        progressionAdapter = true,
        clockMillis = true,
        getText = true,
        measureText = true,
        smallFont = true,
        joypadAButton = true,
    }
    local launcherDependencyFields = {}
    for key in pairs(dependencyFields) do launcherDependencyFields[key] = true end
    launcherDependencyFields.adminLauncher = true
    local hasAdminLauncher = type(dependencies) == "table"
        and rawget(dependencies, "adminLauncher") ~= nil
    if not exactPlainTable(dependencies,
        hasAdminLauncher and launcherDependencyFields or dependencyFields) then
        return failure("invalid_dependencies", "dependencies")
    end

    local characterInfo = rawget(dependencies, "ISCharacterInfo")
    local progressBar = rawget(dependencies, "ISSkillProgressBar")
    local buttonClass = rawget(dependencies, "ISButton")
    local panelClass = rawget(dependencies, "ISPanel")
    local owner = rawget(dependencies, "owner")
    local viewModel = rawget(dependencies, "viewModel")
    local settingsProvider = rawget(dependencies, "settingsProvider")
    local progression = rawget(dependencies, "progressionAdapter")
    local clockMillis = rawget(dependencies, "clockMillis")
    local getText = rawget(dependencies, "getText")
    local measureText = rawget(dependencies, "measureText")
    local smallFont = rawget(dependencies, "smallFont")
    local joypadAButton = rawget(dependencies, "joypadAButton")
    local adminLauncher = rawget(dependencies, "adminLauncher")

    local priorPrerender = method(characterInfo, "prerender")
    local priorRender = method(characterInfo, "render")
    local priorRenderPerkRect = method(progressBar, "renderPerkRect")
    local priorUpdateTooltip = method(progressBar, "updateTooltip")
    local priorRemoveTooltip = method(progressBar, "removeTooltip")
    local priorActivate = method(progressBar, "activate")
    local priorOnJoypadDown = method(characterInfo, "onJoypadDown")
    local priorOnJoypadDirUp = method(characterInfo, "onJoypadDirUp")
    local priorOnJoypadDirDown = method(characterInfo, "onJoypadDirDown")
    local priorOnJoypadDirLeft = method(characterInfo, "onJoypadDirLeft")
    local priorOnJoypadDirRight = method(characterInfo, "onJoypadDirRight")
    local priorOnGainJoypadFocus = method(characterInfo, "onGainJoypadFocus")
    local priorOnLoseJoypadFocus = method(characterInfo, "onLoseJoypadFocus")
    local priorOnMouseWheel = method(characterInfo, "onMouseWheel")
    local buttonNew = method(buttonClass, "new")
    local panelNew = method(panelClass, "new")
    local clientState = validOwner(owner) and rawget(owner, "clientState") or nil
    local refreshOwner = validOwner(owner) and rawget(owner, "refreshOwner") or nil
    local setClientStateListener = validOwner(owner) and rawget(owner, "setClientStateListener") or nil
    local requestAdvancement = validOwner(owner) and rawget(owner, "requestAdvancement") or nil
    local advancementStatus = validOwner(owner) and rawget(owner, "advancementStatus") or nil
    local buildView = type(viewModel) == "table" and rawget(viewModel, "build") or nil
    local readSettings = type(settingsProvider) == "table" and rawget(settingsProvider, "read") or nil
    local buildProgression = type(progression) == "table" and rawget(progression, "build") or nil
    local describeProgression = type(progression) == "table" and rawget(progression, "describe") or nil
    local inspectProgression = type(progression) == "table" and rawget(progression, "inspect") or nil
    local adminInstall = type(adminLauncher) == "table" and rawget(adminLauncher, "install") or nil
    local adminStatus = type(adminLauncher) == "table" and rawget(adminLauncher, "status") or nil
    local adminAvailable = type(adminLauncher) == "table" and rawget(adminLauncher, "isAvailable") or nil
    local adminOpen = type(adminLauncher) == "table" and rawget(adminLauncher, "open") or nil

    local validAdminLauncher = adminLauncher == nil or (exactPlainTable(adminLauncher, {
        install = true, status = true, isAvailable = true, open = true,
    }) and callable(adminInstall) and callable(adminStatus)
        and callable(adminAvailable) and callable(adminOpen))

    if type(characterInfo) ~= "table" or type(progressBar) ~= "table"
        or type(buttonClass) ~= "table" or type(panelClass) ~= "table"
        or not priorPrerender or not priorRender or not priorRenderPerkRect
        or not priorUpdateTooltip or not priorRemoveTooltip or not priorActivate
        or not priorOnMouseWheel or not buttonNew or not panelNew
        or not priorOnJoypadDown or not priorOnJoypadDirUp or not priorOnJoypadDirDown
        or not priorOnJoypadDirLeft or not priorOnJoypadDirRight
        or not priorOnGainJoypadFocus or not priorOnLoseJoypadFocus
        or not clientState or not refreshOwner or not setClientStateListener
        or not requestAdvancement or not advancementStatus
        or not callable(buildView) or not callable(readSettings)
        or not callable(buildProgression) or not callable(describeProgression)
        or not callable(inspectProgression) or not callable(clockMillis)
        or not callable(getText) or not callable(measureText) or smallFont == nil
        or joypadAButton == nil
        or not validAdminLauncher then
        return failure("invalid_dependencies", "callables")
    end

    local views = weakKeys()
    local bars = weakKeys()
    local installed = false
    local installAttempted = false
    local retainedFailure = nil
    local wrappers = {}

    local function retain(code, detail)
        if retainedFailure == nil then retainedFailure = failure(code, detail) end
        return retainedFailure
    end

    local function localized(key, ...)
        local called, value = pcall(getText, key, ...)
        if not called or type(value) ~= "string" or #value == 0
            or string.find(value, ";", 1, true) ~= nil then return nil end
        return value
    end

    local function isVisible(view)
        local called, reader = pcall(function() return view and view.isVisible end)
        if not called or not callable(reader) then return false end
        local visibleCalled, visible = pcall(reader, view)
        return visibleCalled and visible == true
    end

    local function readNumber(target, name)
        local fn = type(target) == "table" and target[name] or nil
        if not callable(fn) then return nil end
        local called, value = pcall(fn, target)
        if not called or not finite(value) then return nil end
        return value
    end

    local function writeNumber(target, name, value)
        local fn = type(target) == "table" and target[name] or nil
        if not callable(fn) or not finite(value) then return false end
        return pcall(fn, target, value)
    end

    local function viewFor(target)
        local state = views[target]
        if state ~= nil then return state end
        local slot = type(target) == "table" and rawget(target, "playerNum") or nil
        if not validSlot(slot) then return nil end
        state = {
            view = target,
            slot = slot,
            dirty = true,
            observed = false,
            barsReady = false,
            disabled = false,
            cache = nil,
            terminalPresentation = nil,
            nextRefresh = nil,
            lastClock = nil,
            bars = weakKeys(),
            order = {},
            baseWidth = nil,
            appliedWidth = nil,
            contentLeft = nil,
            outerGutter = nil,
            layoutParent = nil,
            baseY = nil,
            appliedY = nil,
            vanillaHeight = nil,
            appliedHeight = nil,
            viewportInset = nil,
            statusFirstLeftText = nil,
            statusFirstRightText = nil,
            statusSecondLeftText = nil,
            statusSecondRightText = nil,
            statusLeft = nil,
            statusRight = nil,
            statusFirstY = nil,
            statusSecondY = nil,
            adminVisible = false,
            adminButton = nil,
            adminButtonParent = nil,
            adminWheelSurface = nil,
            adminWheelReady = false,
            adminOutboardRight = nil,
            adminGeometryLease = nil,
            adminGeometryPrimed = false,
            joypadButton = nil,
            vanillaScrollHeight = nil,
            appliedScrollHeight = nil,
        }
        views[target] = state
        return state
    end

    local function clearJoypadButton(state)
        local button = state and state.joypadButton or nil
        if type(button) == "table" and callable(button.setJoypadFocused) then
            pcall(button.setJoypadFocused, button, false)
        end
        if state ~= nil then state.joypadButton = nil end
    end

    local function removeButtonCallback(barState)
        local button = barState and barState.button or nil
        if type(button) == "table" then
            if barState.state and barState.state.joypadButton == button then
                clearJoypadButton(barState.state)
            end
            rawset(button, "onclick", nil)
            rawset(button, "target", nil)
        end
    end

    local restoreLayout
    local restoreAdminVisibility
    local acquireAdminGeometry
    local rebaseAdminGeometry
    local releaseAdminGeometry

    local function disableView(state)
        if state == nil then return end
        state.disabled = true
        state.cache = nil
        state.statusFirstLeftText = nil
        state.statusFirstRightText = nil
        state.statusSecondLeftText = nil
        state.statusSecondRightText = nil
        state.statusLeft = nil
        state.statusRight = nil
        state.adminVisible = false
        state.adminWheelReady = false
        state.adminGeometryPrimed = false
        clearJoypadButton(state)
        if type(state.adminButton) == "table" then
            local setVisible = state.adminButton.setVisible
            local setEnable = state.adminButton.setEnable
            if callable(setVisible) then pcall(setVisible, state.adminButton, false) end
            if callable(setEnable) then pcall(setEnable, state.adminButton, false) end
            rawset(state.adminButton, "onclick", nil)
            rawset(state.adminButton, "target", nil)
            rawset(state.adminButton, "onMouseWheel", nil)
        end
        if type(state.adminWheelSurface) == "table" then
            local setVisible = state.adminWheelSurface.setVisible
            if callable(setVisible) then pcall(setVisible, state.adminWheelSurface, false) end
            rawset(state.adminWheelSurface, "onMouseWheel", nil)
        end
        if releaseAdminGeometry ~= nil then pcall(releaseAdminGeometry, state) end
        if restoreAdminVisibility ~= nil then pcall(restoreAdminVisibility, state) end
        if restoreLayout ~= nil then
            for view, candidate in pairs(views) do
                if candidate == state then
                    pcall(restoreLayout, view, state)
                    break
                end
            end
        end
        for bar in pairs(state.bars) do
            local barState = bars[bar]
            if barState and barState.button and callable(barState.button.setEnable) then
                pcall(barState.button.setEnable, barState.button, false)
            end
        end
    end

    local request

    local function resolveBar(bar, state)
        local perk = type(bar) == "table" and rawget(bar, "perk") or nil
        local player = type(bar) == "table" and rawget(bar, "char") or nil
        local lookupCalled, getId = pcall(function() return perk and perk.getId or nil end)
        if perk == nil or player == nil or not lookupCalled or not callable(getId) then
            return { supported = false }
        end
        local idCalled, perkId = pcall(getId, perk)
        if not idCalled or not safeId(perkId, 128) then return { supported = false } end

        local builtCalled, built = pcall(buildProgression, perk)
        if not builtCalled or not exactSuccess(built, "handle") then return { supported = false, perkId = perkId } end
        local handle = rawget(built, "handle")
        local describedCalled, described = pcall(describeProgression, handle)
        local inspectedCalled, inspected = pcall(inspectProgression, handle, player)
        if not describedCalled or type(described) ~= "table" or rawget(described, "ok") ~= true
            or not inspectedCalled or type(inspected) ~= "table" or rawget(inspected, "ok") ~= true then
            return { supported = false, perkId = perkId }
        end
        local maximum = rawget(described, "effectiveMaximum")
        local currentLevel = rawget(inspected, "storedLevel")
        if not positiveInteger(maximum) or not nonnegativeInteger(currentLevel)
            or currentLevel > maximum or rawget(inspected, "effectiveMaximum") ~= maximum then
            return { supported = false, perkId = perkId }
        end
        local thresholds = copyArray(rawget(described, "cumulativeThresholds"), maximum)
        local baseWidth = readNumber(bar, "getWidth")
        local height = readNumber(bar, "getHeight")
        if thresholds == nil or baseWidth == nil or baseWidth <= 0
            or height == nil or height <= 0 then return { supported = false, perkId = perkId } end

        local barState = {
            supported = true,
            perkId = perkId,
            currentLevel = currentLevel,
            effectiveMaximum = maximum,
            thresholds = thresholds,
            baseWidth = baseWidth,
            height = height,
            bar = bar,
            appliedWidth = nil,
            button = nil,
            state = state,
            row = nil,
            overlayValid = false,
        }
        local buttonCalled, button = pcall(buttonNew, buttonClass, baseWidth, 0, height, height, "+", bar, function(target)
            local targetState = type(target) == "table" and bars[target] or nil
            if targetState ~= nil and callable(request) then request(targetState) end
        end)
        if not buttonCalled or type(button) ~= "table"
            or not callable(button.initialise) or not callable(button.setEnable)
            or not callable(button.setTooltip) or not callable(button.getWidth)
            or not callable(button.forceClick) or not callable(button.setJoypadFocused) then
            return { supported = false, perkId = perkId }
        end
        if not pcall(button.initialise, button)
            or not pcall(button.setEnable, button, false)
            or not callable(bar.addChild) or not pcall(bar.addChild, bar, button) then
            removeButtonCallback({ button = button })
            return { supported = false, perkId = perkId }
        end
        if callable(button.setBorderRGBA) then
            pcall(button.setBorderRGBA, button, POSITION_R, POSITION_G, POSITION_B, 0.75)
        end
        barState.button = button
        return barState
    end

    local function reconcile(view, state)
        local collection = type(view) == "table" and rawget(view, "progressBars") or nil
        if type(collection) ~= "table" then return false end
        local current = weakKeys()
        local order = {}
        local changed = false
        for index, bar in ipairs(collection) do
            if type(bar) == "table" then
                current[bar] = true
                order[#order + 1] = bar
                if state.bars[bar] == nil then
                    local barState = resolveBar(bar, state)
                    state.bars[bar] = true
                    bars[bar] = barState
                    changed = true
                end
            end
        end
        for bar in pairs(state.bars) do
            if current[bar] == nil then
                removeButtonCallback(bars[bar])
                bars[bar] = nil
                state.bars[bar] = nil
                changed = true
            end
        end
        state.order = order
        state.barsReady = #order > 0
        state.observed = true
        if changed then state.dirty = true end
        return true
    end

    local function currentRows(state)
        local rows = {}
        for index = 1, #state.order do
            local barState = bars[state.order[index]]
            if barState and barState.supported then
                rows[#rows + 1] = {
                    perkId = barState.perkId,
                    currentLevel = barState.currentLevel,
                    effectiveMaximum = barState.effectiveMaximum,
                }
            end
        end
        return rows
    end

    local function curvePosition(barState, position)
        if not finite(position) or position < 0 then return nil end
        local visibleMaximum = math.min(barState.effectiveMaximum, 10)
        if position > barState.thresholds[visibleMaximum] then return nil end
        local baseWidth = barState.baseWidth
        local stride = baseWidth / 10
        local cell = barState.height
        if not finite(stride) or stride <= 0 or not finite(cell) or cell <= 0 or stride < cell then return nil end
        if position == 0 then return 0 end
        for level = 1, visibleMaximum do
            local low, high = barState.thresholds[level - 1], barState.thresholds[level]
            if position <= high then
                return (level - 1) * stride + ((position - low) / (high - low)) * cell
            end
        end
        return nil
    end

    local function validOverlay(barState, row)
        if row == nil or rawget(row, "effectiveMaximum") ~= barState.effectiveMaximum then return false end
        local targets = rawget(row, "activeTargets")
        if type(targets) ~= "table" or getmetatable(targets) ~= nil then return false end
        for index, target in ipairs(targets) do
            if not exactPlainTable(target, { targetLevel = true, targetPosition = true })
                or not positiveInteger(rawget(target, "targetLevel"))
                or rawget(target, "targetLevel") > barState.effectiveMaximum
                or not finite(rawget(target, "targetPosition"))
                or rawget(target, "targetPosition") < 0 then return false end
            if index > 1
                and (rawget(target, "targetLevel") <= rawget(targets[index - 1], "targetLevel")
                    or rawget(target, "targetPosition") <= rawget(targets[index - 1], "targetPosition")) then
                return false
            end
        end
        local natural, high = rawget(row, "naturalPosition"), rawget(row, "highWaterPosition")
        if (natural == nil) ~= (high == nil) then return false end
        if #targets > 0 and natural == nil then return false end
        if natural ~= nil and (not finite(natural) or not finite(high) or natural < 0 or high < natural
            or high > barState.thresholds[barState.effectiveMaximum]) then return false end
        return true
    end

    local function formatRemaining(value)
        if not finite(value) or value < 0 then return nil end
        if value == 0 then return "0" end
        if value < 0.01 then return "<0.01" end
        local rounded = value
        if value <= MAX_SAFE_INTEGER / 100 then
            rounded = math.floor(value * 100 + 0.5) / 100
        end
        local called, formatted = pcall(string.format, "%.2f", rounded)
        if not called or type(formatted) ~= "string" then return nil end
        if string.sub(formatted, -3) == ".00" then
            formatted = string.sub(formatted, 1, -4)
        elseif string.sub(formatted, -1) == "0" then
            formatted = string.sub(formatted, 1, -2)
        end
        return formatted
    end

    local function formatSurvivorXp(value)
        if not finite(value) or value < 0 then return nil end
        local rounded = value
        if value <= MAX_SAFE_INTEGER / 10 then
            rounded = math.floor(value * 10 + 0.5) / 10
        end
        local called, formatted = pcall(string.format,
            rounded == math.floor(rounded) and "%.0f" or "%.1f", rounded)
        return called and type(formatted) == "string" and formatted or nil
    end

    local function containsHorizontal(value, left, right, finalRegion)
        return finite(value) and finite(left) and finite(right) and right >= left
            and value >= left and (value < right or (finalRegion and value == right))
    end

    local function hoverTooltip(barState, mouseX)
        if not barState.tracked or not barState.overlayValid or not finite(mouseX) then return nil end
        local row = barState.row
        local natural = rawget(row, "naturalPosition")
        local high = rawget(row, "highWaterPosition")
        if natural ~= nil and natural < high then
            local left = curvePosition(barState, natural)
            local right = curvePosition(barState, high)
            if left ~= nil and right ~= nil and containsHorizontal(mouseX, left, right, true) then
                local amount = formatRemaining(math.max(0, high - natural))
                local first = amount and localized("IGUI_SLA_RecoveryXpLeft", amount) or nil
                local second = localized("IGUI_SLA_RecoveryNoSurvivorXp")
                if first == nil or second == nil then return nil end
                return first .. " <LINE> " .. second
            end
        end

        local targets = rawget(row, "activeTargets")
        local visibleCount = 0
        for index = 1, #targets do
            if rawget(targets[index], "targetLevel") <= 10 then visibleCount = index end
        end
        local stride = barState.baseWidth / 10
        for index = 1, visibleCount do
            local target = targets[index]
            local left = (rawget(target, "targetLevel") - 1) * stride
            local right = left + barState.height
            if containsHorizontal(mouseX, left, right, index == visibleCount) then
                local amount = formatRemaining(math.max(0, rawget(target, "targetPosition") - natural))
                local first = amount and localized("IGUI_SLA_TargetXpLeft", amount) or nil
                local second = localized("IGUI_SLA_TargetCatchUp")
                if first == nil or second == nil then return nil end
                return first .. " <LINE> " .. second
            end
        end
        return nil
    end

    local function buttonTooltipFor(row, terminalKey)
        local lines = {}
        local reason = rawget(row, "reasonCode")
        if reason ~= nil then
            local key = REASON_KEYS[reason]
            local value = key and localized(key) or nil
            if value == nil then return nil end
            lines[#lines + 1] = value
        elseif rawget(row, "nextTargetLevel") ~= nil and rawget(row, "apCost") ~= nil then
            local key = rawget(row, "nextTargetLevel") == rawget(row, "effectiveMaximum")
                and rawget(row, "apCost") == 2 and "IGUI_SLA_Master" or "IGUI_SLA_Advance"
            local value
            if key == "IGUI_SLA_Master" then
                value = localized(key, rawget(row, "apCost"))
            else
                value = localized(key, rawget(row, "nextTargetLevel"), rawget(row, "apCost"))
            end
            if value == nil then return nil end
            lines[#lines + 1] = value
        end
        if rawget(row, "activeCount") ~= nil and rawget(row, "limit") ~= nil then
            local value = localized("IGUI_SLA_PerSkillActive", rawget(row, "activeCount"), rawget(row, "limit"))
            if value == nil then return nil end
            lines[#lines + 1] = value
        end
        if terminalKey ~= nil then
            local value = localized(terminalKey)
            if value == nil then return nil end
            local duplicate = false
            for index = 1, #lines do
                if lines[index] == value then
                    duplicate = true
                    break
                end
            end
            if not duplicate then lines[#lines + 1] = value end
        end
        return table.concat(lines, " <LINE> ")
    end

    local function headerTexts(cache)
        local firstLeft = localized("IGUI_SLA_StatusLevel", cache.survivor.level)
        local firstRight = localized("IGUI_SLA_StatusAP", cache.survivor.availableAp)
        local current = formatSurvivorXp(cache.survivor.xpIntoLevel)
        local required = formatSurvivorXp(cache.survivor.xpForNextLevel)
        local secondLeft = current ~= nil and required ~= nil
            and localized("IGUI_SLA_StatusSurvivorXp", current, required) or nil
        if firstLeft == nil or firstRight == nil or secondLeft == nil then
            return nil, nil, nil, nil
        end
        if cache.allotment.mode ~= "Global" then
            return firstLeft, firstRight, secondLeft, nil
        end
        local secondRight = localized(
            "IGUI_SLA_StatusActive", cache.allotment.activeCount, cache.allotment.limit)
        if secondRight == nil then return nil, nil, nil, nil end
        return firstLeft, firstRight, secondLeft, secondRight
    end

    local function forwardAdminWheel(state, delta)
        if state == nil or state.disabled or state.adminVisible ~= true
            or not isVisible(state.view) or not finite(delta) then return false end
        local called, consumed = pcall(priorOnMouseWheel, state.view, delta)
        return called and consumed == true
    end

    local function applyAdminButtonVisibility(state, visible)
        local button = state.adminButton
        local buttonOk = true
        if type(button) == "table" then
            local setVisible = button.setVisible
            local setEnable = button.setEnable
            local visibilityOk = callable(setVisible) and pcall(setVisible, button, visible)
            local enableOk = callable(setEnable) and pcall(setEnable, button, visible)
            buttonOk = visibilityOk and enableOk
        end
        local surface = state.adminWheelSurface
        local surfaceOk = true
        if type(surface) == "table" then
            local setVisible = surface.setVisible
            surfaceOk = callable(setVisible)
                and pcall(setVisible, surface, visible and state.adminWheelReady == true)
        end
        return buttonOk and surfaceOk
    end

    local function setAdminButtonState(state, visible, expandImmediately)
        state.adminVisible = visible
        if not visible then
            state.adminGeometryPrimed = false
            state.adminWheelReady = false
            local hidden = applyAdminButtonVisibility(state, false)
            local released = releaseAdminGeometry == nil or releaseAdminGeometry(state)
            return hidden and released
        elseif expandImmediately == true and acquireAdminGeometry ~= nil
            and type(state.adminButtonParent) == "table"
            and finite(state.adminOutboardRight) then
            if not acquireAdminGeometry(state) then return false end
            state.adminGeometryPrimed = false
        end
        return applyAdminButtonVisibility(state, visible)
    end

    local function updateAdminAvailability(view, state, expandImmediately)
        if adminLauncher == nil or state.adminVisibilityFailed or not isVisible(view) then
            return setAdminButtonState(state, false, false)
        end
        local called, available = pcall(adminAvailable, state.slot)
        return setAdminButtonState(state, called and available == true, expandImmediately)
    end

    local function installAdminVisibility(view, state)
        if adminLauncher == nil then return true end
        if state.adminVisibilityFailed then
            setAdminButtonState(state, false)
            return false
        end
        if state.adminVisibilityWrapper ~= nil then
            local called, current = pcall(function() return view.setVisible end)
            if called and current == state.adminVisibilityWrapper then return true end
            state.adminVisibilityFailed = true
            setAdminButtonState(state, false)
            return false
        end
        local priorRaw = rawget(view, "setVisible")
        local called, prior = pcall(function() return view.setVisible end)
        if not called or not callable(prior) then
            state.adminVisibilityFailed = true
            setAdminButtonState(state, false)
            return false
        end
        local wrapper
        wrapper = function(target, ...)
            local ok, a, b, c = pcall(prior, target, ...)
            if not ok then
                setAdminButtonState(state, false)
                disableView(state)
                error(a, 0)
            end
            local updated, applied = pcall(updateAdminAvailability, view, state, true)
            if not updated or not applied then disableView(state) end
            return a, b, c
        end
        local wrote = pcall(rawset, view, "setVisible", wrapper)
        if not wrote then
            state.adminVisibilityFailed = true
            setAdminButtonState(state, false)
            return false
        end
        local installed, current = pcall(function() return view.setVisible end)
        if not installed or current ~= wrapper then
            state.adminVisibilityFailed = true
            setAdminButtonState(state, false)
            return false
        end
        state.adminVisibilityPrior = priorRaw
        state.adminVisibilityWrapper = wrapper
        local updated, applied = pcall(updateAdminAvailability, view, state, true)
        if not updated or not applied then
            setAdminButtonState(state, false)
            return false
        end
        return true
    end

    restoreAdminVisibility = function(state)
        if state == nil or state.adminVisibilityWrapper == nil then return true end
        local view = state.view
        if type(view) ~= "table" or rawget(view, "setVisible") ~= state.adminVisibilityWrapper then
            state.adminVisibilityFailed = true
            setAdminButtonState(state, false)
            return false
        end
        local restored = pcall(rawset, view, "setVisible", state.adminVisibilityPrior)
        if not restored or rawget(view, "setVisible") ~= state.adminVisibilityPrior then
            state.adminVisibilityFailed = true
            setAdminButtonState(state, false)
            return false
        end
        state.adminVisibilityWrapper = nil
        state.adminVisibilityPrior = nil
        return true
    end

    local function activateAdmin(state)
        if state == nil or state.disabled then return end
        if not isVisible(state.view) then
            setAdminButtonState(state, false)
            return
        end
        local called, available = pcall(adminAvailable, state.slot)
        if not called or available ~= true then
            setAdminButtonState(state, false)
            return
        end
        pcall(adminOpen, state.slot)
    end

    local function removeAdminButton(state)
        local button = state.adminButton
        local wheelSurface = state.adminWheelSurface
        local parent = state.adminButtonParent
        local hidden = applyAdminButtonVisibility(state, false)
        if type(button) == "table" then
            rawset(button, "onclick", nil)
            rawset(button, "target", nil)
            rawset(button, "onMouseWheel", nil)
        end
        if type(wheelSurface) == "table" then
            rawset(wheelSurface, "onMouseWheel", nil)
        end
        local released = true
        if releaseAdminGeometry ~= nil then
            local called, result = pcall(releaseAdminGeometry, state)
            released = called and result == true
        end
        if type(button) == "table" then
            local removeChild = type(parent) == "table" and parent.removeChild or nil
            if callable(removeChild) then pcall(removeChild, parent, button) end
        end
        if type(wheelSurface) == "table" then
            local removeChild = type(parent) == "table" and parent.removeChild or nil
            if callable(removeChild) then pcall(removeChild, parent, wheelSurface) end
        end
        state.adminButton = nil
        state.adminButtonParent = nil
        state.adminWheelSurface = nil
        state.adminWheelReady = false
        state.adminOutboardRight = nil
        state.adminGeometryPrimed = false
        return hidden and released
    end

    local function ensureAdminButton(view, state)
        if adminLauncher == nil then return true end
        local parent = rawget(view, "parent")
        if type(parent) ~= "table" then return false end
        if state.adminButton ~= nil and state.adminButtonParent ~= parent then
            if not removeAdminButton(state) then return false end
        end
        if state.adminButton == nil then
            local title = localized("IGUI_SLA_Admin_Button")
            if title == nil then return false end
            local called, button = pcall(buttonNew, buttonClass, 0, 0, 1, 20,
                title, state, activateAdmin)
            if not called or type(button) ~= "table" then return false end
            local initialise = button.initialise
            local addChild = parent.addChild
            if not callable(initialise) or not callable(addChild)
                or not pcall(initialise, button) or not pcall(addChild, parent, button) then
                return false
            end
            state.adminButton = button
            state.adminButtonParent = parent
            rawset(button, "onMouseWheel", function(_, delta)
                return forwardAdminWheel(state, delta)
            end)
            local panelCalled, wheelSurface = pcall(panelNew, panelClass, 0, 0, 1, 1)
            if not panelCalled or type(wheelSurface) ~= "table" then
                removeAdminButton(state)
                return false
            end
            local initialisePanel = wheelSurface.initialise
            local noBackground = wheelSurface.noBackground
            local setWantMouseEvents = wheelSurface.setWantMouseEvents
            if not callable(initialisePanel) or not callable(noBackground)
                or not callable(setWantMouseEvents)
                or not pcall(initialisePanel, wheelSurface)
                or not pcall(noBackground, wheelSurface)
                or not pcall(setWantMouseEvents, wheelSurface, false)
                or not pcall(addChild, parent, wheelSurface) then
                removeAdminButton(state)
                return false
            end
            rawset(wheelSurface, "onMouseWheel", function(_, delta)
                return forwardAdminWheel(state, delta)
            end)
            state.adminWheelSurface = wheelSurface
            state.adminWheelReady = false
        end
        return setAdminButtonState(state, state.adminVisible)
    end

    local function setButton(barState, enabled, tooltip)
        if barState.button == nil then return false end
        if not pcall(barState.button.setEnable, barState.button, enabled) then return false end
        if not pcall(barState.button.setTooltip, barState.button, tooltip) then return false end
        return true
    end

    local function applyCache(state)
        local cache = state.cache
        local firstLeft, firstRight, secondLeft, secondRight = nil, nil, nil, nil
        if cache then firstLeft, firstRight, secondLeft, secondRight = headerTexts(cache) end
        state.statusFirstLeftText = firstLeft
        state.statusFirstRightText = firstRight
        state.statusSecondLeftText = secondLeft
        state.statusSecondRightText = secondRight
        if cache and (firstLeft == nil or firstRight == nil or secondLeft == nil) then
            disableView(state)
            return false
        end
        for index = 1, #state.order do
            local barState = bars[state.order[index]]
            if barState and barState.supported then
                local row = cache and cache.rows[barState.perkId] or nil
                local tracked = cache ~= nil and cache.allotment.mode ~= "Free"
                local overlay = row ~= nil and (not tracked or validOverlay(barState, row))
                barState.row = row
                barState.tracked = tracked
                barState.overlayValid = overlay
                local terminal = state.terminalPresentation
                local terminalKey = terminal ~= nil and terminal.perkId == barState.perkId
                    and terminal.key or nil
                local tooltip = row and buttonTooltipFor(row, terminalKey) or nil
                if row and tooltip == nil then disableView(state); return false end
                local enabled = row ~= nil and row.enabled == true and overlay
                    and cache.pending ~= true
                if not setButton(barState, enabled, tooltip) then disableView(state); return false end
            end
        end
        return true
    end

    local function rebuild(state)
        state.dirty = false
        local stateCalled, stateResult = pcall(clientState, state.slot)
        local statusCalled, statusResult = pcall(advancementStatus, state.slot)
        local settingsCalled, settingsResult = pcall(readSettings)
        local stateValid, snapshot = stateCalled and validClientState(stateResult) or false, nil
        if stateValid then local _, detached = validClientState(stateResult); snapshot = detached end
        local statusValid, pending, terminalPresentation = false, nil, nil
        if statusCalled then
            statusValid, pending, terminalPresentation = validAdvancementStatus(statusResult)
        end
        local allotment = settingsCalled and projectAllotment(settingsResult) or nil
        if not stateValid or snapshot == nil or not statusValid or allotment == nil then
            state.cache = nil
            state.terminalPresentation = nil
            applyCache(state)
            return false
        end
        local called, built = pcall(buildView, {
            snapshot = snapshot,
            allotment = allotment,
            pending = pending,
            rows = currentRows(state),
        })
        if not called or not exactSuccess(built, "view") or not validModelView(rawget(built, "view")) then
            state.cache = nil
            state.terminalPresentation = nil
            applyCache(state)
            return false
        end
        state.cache = rawget(built, "view")
        state.terminalPresentation = terminalPresentation
        state.disabled = false
        return applyCache(state)
    end

    local function markSlotDirty(slot)
        if not validSlot(slot) then return end
        for view, state in pairs(views) do
            if view ~= nil and state.slot == slot then state.dirty = true end
        end
    end

    local function markSlotPending(slot)
        for view, state in pairs(views) do
            if view ~= nil and state.slot == slot then
                state.terminalPresentation = nil
                if state.cache ~= nil then
                    state.cache.pending = true
                    applyCache(state)
                end
            end
        end
    end

    request = function(barState)
        local state = barState.state
        local row = state and state.cache and state.cache.rows[barState.perkId] or nil
        if state == nil or row == nil or not row.enabled or state.cache.pending
            or not barState.overlayValid then return false end
        local called, result = pcall(requestAdvancement, state.slot, barState.perkId)
        if not called or not validAcceptedRequest(result, barState.perkId) then return false end
        markSlotPending(state.slot)
        state.dirty = true
        return true
    end

    local function propagate(view, value, axis)
        local sizeName = axis == "width" and "setWidth" or "setHeight"
        local readSize = axis == "width" and "getWidth" or "getHeight"
        local readPosition = axis == "width" and "getX" or "getY"
        if not writeNumber(view, sizeName, value) then return false end
        local child = view
        local parent = rawget(view, "parent")
        while parent ~= nil do
            if type(parent) ~= "table" then return false end
            local position = readNumber(child, readPosition)
            local size = readNumber(child, readSize)
            if position == nil or size == nil
                or not writeNumber(parent, sizeName, position + size) then return false end
            child = parent
            parent = rawget(parent, "parent")
        end
        return true
    end

    releaseAdminGeometry = function(state)
        local lease = state and state.adminGeometryLease or nil
        if lease == nil then return true end
        state.adminGeometryLease = nil
        if type(lease) ~= "table" or getmetatable(lease) ~= nil then return false end
        local child = nil
        for index = 1, #lease do
            local entry = rawget(lease, index)
            local node = type(entry) == "table" and rawget(entry, "node") or nil
            local currentWidth = readNumber(node, "getWidth")
            local currentX = readNumber(node, "getX")
            if currentWidth == nil or currentX == nil then return false end
            if rawget(entry, "changed") == true
                and currentWidth == rawget(entry, "appliedWidth") then
                local targetWidth = rawget(entry, "baseWidth")
                if child ~= nil then
                    local childX = readNumber(child, "getX")
                    local childWidth = readNumber(child, "getWidth")
                    if childX == nil or childWidth == nil then return false end
                    targetWidth = math.max(targetWidth, childX + childWidth)
                end
                local restoreX = currentX == rawget(entry, "appliedX")
                    and targetWidth == rawget(entry, "baseWidth")
                if targetWidth ~= currentWidth
                    and not writeNumber(node, "setWidth", targetWidth) then return false end
                if restoreX and currentX ~= rawget(entry, "baseX")
                    and not writeNumber(node, "setX", rawget(entry, "baseX")) then return false end
            end
            child = node
        end
        return true
    end

    acquireAdminGeometry = function(state)
        if state == nil or state.adminVisible ~= true
            or type(state.adminButtonParent) ~= "table"
            or not finite(state.adminOutboardRight) then return true end
        local lease = state.adminGeometryLease
        if lease ~= nil then
            local node = state.adminButtonParent
            for index = 1, #lease do
                local entry = rawget(lease, index)
                if type(entry) ~= "table" or rawget(entry, "node") ~= node then
                    if not releaseAdminGeometry(state) then return false end
                    lease = nil
                    break
                end
                node = type(node) == "table" and rawget(node, "parent") or nil
            end
            if lease ~= nil and node ~= nil then
                if not releaseAdminGeometry(state) then return false end
                lease = nil
            end
        end
        if lease == nil then
            lease = {}
            state.adminGeometryLease = lease
        end
        local node = state.adminButtonParent
        local requiredWidth = state.adminOutboardRight
        local index = 1
        while node ~= nil do
            if type(node) ~= "table" then return false end
            local entry = rawget(lease, index)
            local baseWidth = entry ~= nil and rawget(entry, "baseWidth")
                or readNumber(node, "getWidth")
            local baseX = entry ~= nil and rawget(entry, "baseX") or readNumber(node, "getX")
            if baseWidth == nil or baseX == nil then return false end
            local desiredWidth = math.max(baseWidth, requiredWidth)
            local changed = desiredWidth > baseWidth
            local currentWidth = readNumber(node, "getWidth")
            if currentWidth == nil then return false end
            if currentWidth ~= desiredWidth
                and not writeNumber(node, "setWidth", desiredWidth) then return false end
            local appliedWidth = readNumber(node, "getWidth")
            local appliedX = readNumber(node, "getX")
            if appliedWidth == nil or appliedX == nil then return false end
            if entry == nil then
                entry = { node = node }
                lease[index] = entry
            end
            entry.baseWidth = baseWidth
            entry.baseX = baseX
            entry.appliedWidth = appliedWidth
            entry.appliedX = appliedX
            entry.changed = changed
            local parent = rawget(node, "parent")
            if parent ~= nil then
                local nodeX = readNumber(node, "getX")
                if nodeX == nil then return false end
                requiredWidth = nodeX + appliedWidth
            end
            node = parent
            index = index + 1
        end
        return true
    end

    rebaseAdminGeometry = function(state)
        local lease = state and state.adminGeometryLease or nil
        if lease == nil then return true end
        for index = 1, #lease do
            local entry = rawget(lease, index)
            local node = type(entry) == "table" and rawget(entry, "node") or nil
            local currentWidth = readNumber(node, "getWidth")
            local currentX = readNumber(node, "getX")
            if currentWidth == nil or currentX == nil then return false end
            if currentWidth ~= rawget(entry, "appliedWidth") then
                entry.baseWidth = currentWidth
                entry.appliedWidth = currentWidth
                entry.changed = false
            end
            if currentX ~= rawget(entry, "appliedX") then
                entry.baseX = currentX
                entry.appliedX = currentX
            end
        end
        return true
    end

    local function primeAdminGeometry(state)
        if state == nil or state.adminVisible ~= true
            or state.adminGeometryPrimed ~= true
            or state.adminGeometryLease ~= nil then return true end
        if type(state.adminButtonParent) ~= "table"
            or not finite(state.adminOutboardRight)
            or not acquireAdminGeometry(state) then return false end
        state.adminGeometryPrimed = false
        return applyAdminButtonVisibility(state, true)
    end

    local function reapplyAdminGeometry(state)
        local lease = state and state.adminGeometryLease or nil
        if lease == nil or state.adminVisible ~= true
            or not finite(state.adminOutboardRight) then return true end
        local requiredWidth = state.adminOutboardRight
        for index = 1, #lease do
            local entry = rawget(lease, index)
            local node = type(entry) == "table" and rawget(entry, "node") or nil
            local baseWidth = type(entry) == "table" and rawget(entry, "baseWidth") or nil
            local baseX = type(entry) == "table" and rawget(entry, "baseX") or nil
            if not finite(baseWidth) or not finite(baseX) then return false end
            local desiredWidth = math.max(baseWidth, requiredWidth)
            local currentWidth = readNumber(node, "getWidth")
            if currentWidth == nil then return false end
            if currentWidth ~= desiredWidth
                and not writeNumber(node, "setWidth", desiredWidth) then return false end
            local appliedWidth = readNumber(node, "getWidth")
            local appliedX = readNumber(node, "getX")
            if appliedWidth == nil or appliedX == nil then return false end
            entry.appliedWidth = appliedWidth
            entry.appliedX = appliedX
            entry.changed = desiredWidth > baseWidth
            local parent = rawget(node, "parent")
            if parent ~= nil then
                local nodeX = readNumber(node, "getX")
                if nodeX == nil then return false end
                requiredWidth = nodeX + appliedWidth
            end
        end
        return true
    end

    local function prepareGeometry(view, state)
        local currentWidth = readNumber(view, "getWidth")
        if currentWidth == nil then return false end
        if state.appliedWidth ~= nil and currentWidth ~= state.appliedWidth then
            state.baseWidth = currentWidth
        end
        if state.baseWidth ~= nil and not propagate(view, state.baseWidth, "width") then return false end
        for index = 1, #state.order do
            local barState = bars[state.order[index]]
            if barState and barState.supported then
                if not writeNumber(state.order[index], "setWidth", barState.baseWidth) then return false end
            end
        end
        return true
    end

    local function firstButtonGeometry(view)
        local buttons = type(view) == "table" and rawget(view, "buttonList") or nil
        local firstButton = type(buttons) == "table" and rawget(buttons, 1) or nil
        local left = firstButton and readNumber(firstButton, "getRight") or nil
        local y = firstButton and readNumber(firstButton, "getY") or nil
        local height = firstButton and readNumber(firstButton, "getHeight") or nil
        if left == nil or y == nil or height == nil or height <= 0 then return nil, nil, nil end
        return left, y, height
    end

    local function prepareHeader(view, state)
        local _, buttonY, buttonHeight = firstButtonGeometry(view)
        if buttonY == nil or buttonHeight == nil then return false end
        local viewportInset = buttonY + buttonHeight
        local headerInset = viewportInset + buttonHeight
        if not finite(viewportInset) or viewportInset <= 0
            or not finite(headerInset) or headerInset <= viewportInset then return false end
        local parent = rawget(view, "parent")
        if type(parent) ~= "table" then return false end
        local currentY = readNumber(view, "getY")
        local currentHeight = readNumber(view, "getHeight")
        if currentY == nil or currentHeight == nil or currentHeight < headerInset then return false end

        if state.layoutParent ~= parent then
            if state.appliedY ~= nil and currentY == state.appliedY then currentY = state.baseY end
            if state.appliedHeight ~= nil and currentHeight == state.appliedHeight then
                currentHeight = state.vanillaHeight
            end
            state.layoutParent = parent
            state.baseY = currentY
            state.vanillaHeight = currentHeight
        else
            if state.appliedY == nil or currentY ~= state.appliedY then state.baseY = currentY end
            if state.appliedHeight == nil or currentHeight ~= state.appliedHeight then
                state.vanillaHeight = currentHeight
            end
        end
        state.viewportInset = headerInset
        local appliedY = state.baseY + headerInset
        if not writeNumber(view, "setY", appliedY) then return false end
        state.appliedY = appliedY
        local appliedHeight = state.vanillaHeight - headerInset
        if appliedHeight < 0 or not propagate(view, appliedHeight, "height") then return false end
        state.appliedHeight = appliedHeight
        return true
    end

    local function finishHeader(view, state)
        local height = readNumber(view, "getHeight")
        if height == nil or state.viewportInset == nil or height < state.viewportInset then return false end
        state.vanillaHeight = height
        local appliedHeight = height - state.viewportInset
        if not propagate(view, appliedHeight, "height") then return false end
        state.appliedHeight = appliedHeight
        local scrollHeight = readNumber(view, "getScrollHeight")
        if scrollHeight == nil then return false end
        if state.appliedScrollHeight ~= nil and scrollHeight == state.appliedScrollHeight then
            scrollHeight = state.vanillaScrollHeight
        end
        state.vanillaScrollHeight = scrollHeight
        local appliedScrollHeight = scrollHeight
        local collection = rawget(view, "progressBars")
        local last = type(collection) == "table" and rawget(collection, #collection) or nil
        if type(last) == "table" then
            local lastY = readNumber(last, "getY")
            local lastHeight = readNumber(last, "getHeight")
            if lastY ~= nil and lastHeight ~= nil then
                appliedScrollHeight = math.max(appliedScrollHeight, lastY + lastHeight + 40)
            end
        end
        if not writeNumber(view, "setScrollHeight", appliedScrollHeight) then return false end
        state.appliedScrollHeight = appliedScrollHeight
        return true
    end

    restoreLayout = function(view, state)
        local restored = true
        if state.baseY ~= nil and not writeNumber(view, "setY", state.baseY) then restored = false end
        if state.vanillaHeight ~= nil and not propagate(view, state.vanillaHeight, "height") then
            restored = false
        end
        if state.vanillaScrollHeight ~= nil
            and not writeNumber(view, "setScrollHeight", state.vanillaScrollHeight) then
            restored = false
        end
        if state.baseWidth ~= nil and not propagate(view, state.baseWidth, "width") then restored = false end
        for index = 1, #state.order do
            local barState = bars[state.order[index]]
            if barState and barState.supported
                and not writeNumber(state.order[index], "setWidth", barState.baseWidth) then restored = false end
        end
        state.appliedY = nil
        state.appliedHeight = nil
        state.appliedWidth = nil
        return restored
    end

    local function applyGeometry(view, state)
        local currentWidth = readNumber(view, "getWidth")
        if currentWidth == nil then return false end
        state.baseWidth = currentWidth
        local baseRight, controlRight = 0, 0
        for index = 1, #state.order do
            local bar = state.order[index]
            local barState = bars[bar]
            if barState and barState.supported then
                local x = readNumber(bar, "getX")
                local buttonWidth = readNumber(barState.button, "getWidth")
                if x == nil or buttonWidth == nil or buttonWidth <= 0 then return false end
                local expanded = barState.baseWidth + buttonWidth
                if not writeNumber(barState.button, "setX", barState.baseWidth)
                    or not writeNumber(barState.button, "setY", 0)
                    or not writeNumber(bar, "setWidth", expanded) then return false end
                barState.appliedWidth = expanded
                baseRight = math.max(baseRight, x + barState.baseWidth)
                controlRight = math.max(controlRight, x + expanded)
            end
        end
        if baseRight == 0 then return true end
        local gutter = state.baseWidth - baseRight
        if not finite(gutter) or gutter < 0 then return false end
        state.outerGutter = gutter
        local requiredRight = controlRight
        if state.statusFirstLeftText ~= nil and state.statusFirstRightText ~= nil
            and state.statusSecondLeftText ~= nil then
            local contentLeft, y, rowHeight = firstButtonGeometry(view)
            local gapCalled, gapWidth = pcall(measureText, "  ")
            local firstLeftCalled, firstLeftWidth = pcall(measureText, state.statusFirstLeftText)
            local firstRightCalled, firstRightWidth = pcall(measureText, state.statusFirstRightText)
            if contentLeft == nil or y == nil or rowHeight == nil
                or not firstLeftCalled or not finite(firstLeftWidth) or firstLeftWidth < 0
                or not firstRightCalled or not finite(firstRightWidth) or firstRightWidth < 0
                or not gapCalled or not finite(gapWidth) or gapWidth < 0 then return false end
            local viewX = readNumber(view, "getX")
            if viewX == nil then return false end
            local firstRowWidth = STATUS_LEFT_MARGIN + firstLeftWidth + gapWidth
                + firstRightWidth + STATUS_LEFT_MARGIN
            local secondLeftCalled, secondLeftWidth = pcall(
                measureText, state.statusSecondLeftText)
            if not secondLeftCalled or not finite(secondLeftWidth)
                or secondLeftWidth < 0 then return false end
            local secondRowWidth = STATUS_LEFT_MARGIN + secondLeftWidth + STATUS_LEFT_MARGIN
            if state.statusSecondRightText ~= nil then
                local secondRightCalled, secondRightWidth = pcall(
                    measureText, state.statusSecondRightText)
                if not secondRightCalled or not finite(secondRightWidth)
                    or secondRightWidth < 0 then return false end
                secondRowWidth = STATUS_LEFT_MARGIN + secondLeftWidth + gapWidth
                    + secondRightWidth + STATUS_LEFT_MARGIN
            end
            local headerWidth = math.max(firstRowWidth, secondRowWidth)
            state.contentLeft = contentLeft
            state.statusLeft = STATUS_LEFT_MARGIN
            state.statusFirstY = y
            state.statusSecondY = y + rowHeight
            local windowWidth = viewX + requiredRight + gutter
            windowWidth = math.max(windowWidth, headerWidth)
            requiredRight = windowWidth - viewX - gutter
            state.statusRight = requiredRight + gutter - STATUS_LEFT_MARGIN
            local desiredWidth = requiredRight + gutter
            if not propagate(view, desiredWidth, "width") then return false end
            state.appliedWidth = desiredWidth
            if adminLauncher ~= nil then
                local parent = rawget(view, "parent")
                if state.adminButton ~= nil and state.adminButtonParent == parent then
                    local buttonWidth = readNumber(state.adminButton, "getWidth")
                    local buttonHeight = readNumber(state.adminButton, "getHeight")
                    if buttonWidth == nil or buttonWidth <= 0
                        or buttonHeight == nil or buttonHeight <= 0 then return false end
                    local buttonX = viewX + desiredWidth + ADMIN_OUTBOARD_GAP
                    local buttonY = state.baseY + state.statusFirstY
                    if not writeNumber(state.adminButton, "setX", buttonX)
                        or not writeNumber(state.adminButton, "setY", buttonY) then return false end
                    state.adminOutboardRight = buttonX + buttonWidth + STATUS_LEFT_MARGIN
                    local wheelSurface = state.adminWheelSurface
                    local parentHeight = readNumber(parent, "getHeight")
                    local surfaceX = viewX + desiredWidth
                    local surfaceY = buttonY + buttonHeight
                    local surfaceWidth = state.adminOutboardRight - surfaceX
                    local surfaceHeight = parentHeight ~= nil and parentHeight - surfaceY or nil
                    if type(wheelSurface) ~= "table" or parentHeight == nil
                        or surfaceWidth <= 0 or surfaceHeight == nil or surfaceHeight <= 0
                        or not writeNumber(wheelSurface, "setX", surfaceX)
                        or not writeNumber(wheelSurface, "setY", surfaceY)
                        or not writeNumber(wheelSurface, "setWidth", surfaceWidth)
                        or not writeNumber(wheelSurface, "setHeight", surfaceHeight) then return false end
                    state.adminWheelReady = true
                    if state.adminVisible then
                        if state.adminGeometryLease ~= nil then
                            if not reapplyAdminGeometry(state)
                                or not applyAdminButtonVisibility(state, true) then return false end
                            state.adminGeometryPrimed = false
                        else
                            state.adminGeometryPrimed = true
                            if not applyAdminButtonVisibility(state, false) then return false end
                        end
                    elseif not state.adminVisible then
                        state.adminGeometryPrimed = false
                    end
                end
            end
        else
            state.statusLeft, state.statusRight = nil, nil
            state.statusFirstY, state.statusSecondY = nil, nil
            local desiredWidth = requiredRight + gutter
            if not propagate(view, desiredWidth, "width") then return false end
            state.appliedWidth = desiredWidth
        end
        return true
    end

    local function refresh(state, now)
        if state.lastClock ~= nil and now < state.lastClock then
            state.lastClock = now
            state.nextRefresh = now + REFRESH_MILLIS
            return
        end
        state.lastClock = now
        if state.nextRefresh ~= nil and now < state.nextRefresh then return end
        state.nextRefresh = now + REFRESH_MILLIS
        pcall(refreshOwner, state.slot)
        state.dirty = true
    end

    local function onPrerender(view)
        local state = viewFor(view)
        if state == nil or state.disabled then return end
        if not state.observed and type(rawget(view, "progressBars")) == "table"
            and #rawget(view, "progressBars") > 0 then
            if not reconcile(view, state) then disableView(state); return end
        end
        local called, now = pcall(clockMillis)
        if not called or not finite(now) or now < 0 then disableView(state); return end
        refresh(state, now)
        if state.dirty and state.barsReady then rebuild(state) end
    end

    local function onRender(view)
        local state = viewFor(view)
        if state == nil or state.disabled then return end
        if not finishHeader(view, state) or not reconcile(view, state) or not applyGeometry(view, state) then
            disableView(state)
            return
        end
        if state.statusFirstLeftText ~= nil and state.statusFirstRightText ~= nil
            and state.statusSecondLeftText ~= nil
            and state.statusLeft ~= nil then
            local parent = rawget(view, "parent")
            local viewX = readNumber(view, "getX")
            local drawLeft = type(parent) == "table" and parent.drawText or nil
            local drawRight = type(parent) == "table" and parent.drawTextRight or nil
            local firstY = state.baseY + state.statusFirstY
            local secondY = state.baseY + state.statusSecondY
            local leftOk = viewX ~= nil and callable(drawLeft)
                and pcall(drawLeft, parent, state.statusFirstLeftText, state.statusLeft,
                    firstY, 1, 1, 1, 1, smallFont)
            local firstRightOk = viewX ~= nil and callable(drawRight)
                and pcall(drawRight, parent, state.statusFirstRightText, viewX + state.statusRight,
                    firstY, 1, 1, 1, 1, smallFont)
            local secondLeftOk = viewX ~= nil and callable(drawLeft)
                and pcall(drawLeft, parent, state.statusSecondLeftText,
                    state.statusLeft, secondY, 1, 1, 1, 1, smallFont)
            local secondRightOk = state.statusSecondRightText == nil or (viewX ~= nil
                and callable(drawRight) and pcall(drawRight, parent, state.statusSecondRightText,
                    viewX + state.statusRight, secondY, 1, 1, 1, 1, smallFont))
            if not leftOk or not firstRightOk or not secondLeftOk or not secondRightOk then
                disableView(state)
            end
        end
    end

    local function onOverlay(bar)
        local barState = bars[bar]
        if barState == nil or not barState.supported then return true end
        local state = barState.state
        if state == nil or state.disabled then return true end
        local button = barState.button
        local isMouseOver = type(button) == "table" and button.isMouseOver or nil
        if not callable(isMouseOver) then return false end
        local hoveredCalled, hovered = pcall(isMouseOver, button)
        if not hoveredCalled or type(hovered) ~= "boolean" then return false end
        local vanillaTooltip = rawget(bar, "message")
        if hovered and type(vanillaTooltip) == "string" and vanillaTooltip ~= ""
            and not pcall(priorRemoveTooltip, bar) then return false end
        if not barState.overlayValid or not barState.tracked or barState.row == nil then return true end
        local drawBorder = bar.drawRectBorder
        local drawRect = bar.drawRect
        if not callable(drawBorder) or not callable(drawRect) then return true end
        local stride = barState.baseWidth / 10
        local cell = barState.height
        for _, target in ipairs(barState.row.activeTargets) do
            local level = target.targetLevel
            if level <= 10 then
                pcall(drawBorder, bar, (level - 1) * stride, 0, cell, cell,
                    0.95, TARGET_R, TARGET_G, TARGET_B)
            end
        end
        local natural, high = barState.row.naturalPosition, barState.row.highWaterPosition
        if natural == nil then return true end
        local highX = curvePosition(barState, high)
        if #barState.row.activeTargets > 0 and highX ~= nil then
            pcall(drawRect, bar, highX - 1, 0, 2, cell, 0.85,
                POSITION_R, POSITION_G, POSITION_B)
        end
        if natural < high then
            local naturalX = curvePosition(barState, natural)
            if naturalX ~= nil and highX ~= nil and highX > naturalX then
                pcall(drawRect, bar, naturalX, cell - 3, highX - naturalX, 2,
                    0.75, RECOVERY_R, RECOVERY_G, RECOVERY_B)
                pcall(drawRect, bar, naturalX - 1, 0, 2, cell, 0.90,
                    RECOVERY_POSITION_R, RECOVERY_POSITION_G, RECOVERY_POSITION_B)
            end
        end
        return true
    end

    local function onTooltip(bar)
        local barState = bars[bar]
        if barState == nil or barState.row == nil or not barState.tracked then return end
        local mouseX = readNumber(bar, "getMouseX")
        local addition = mouseX ~= nil and hoverTooltip(barState, mouseX) or nil
        if addition == nil or addition == "" then return end
        local vanilla = rawget(bar, "message")
        if type(vanilla) == "string" and vanilla ~= "" then
            rawset(bar, "message", vanilla .. " <LINE><LINE> " .. addition)
        end
    end

    local function focusCurrentButton(view, state)
        clearJoypadButton(state)
        local index = type(view) == "table" and rawget(view, "joypadIndex") or nil
        local progressBars = type(view) == "table" and rawget(view, "progressBars") or nil
        local bar = type(index) == "number" and type(progressBars) == "table"
            and rawget(progressBars, index) or nil
        local barState = type(bar) == "table" and bars[bar] or nil
        local button = barState and barState.button or nil
        if type(button) ~= "table" or not callable(button.setJoypadFocused) then return false end
        local called = pcall(button.setJoypadFocused, button, true)
        if not called then return false end
        state.joypadButton = button
        return true
    end

    local function forceSelectedVisible(view)
        local index = type(view) == "table" and rawget(view, "joypadIndex") or nil
        local collection = type(view) == "table" and rawget(view, "progressBars") or nil
        local child = type(index) == "number" and type(collection) == "table"
            and rawget(collection, index) or nil
        if type(child) ~= "table" then return true end
        local scroll = readNumber(view, "getYScroll")
        local height = readNumber(view, "getHeight")
        local y = readNumber(child, "getY")
        local childHeight = readNumber(child, "getHeight")
        if scroll == nil or height == nil or y == nil or childHeight == nil then return false end
        local visibleTop = 0 - scroll
        if y - 40 < visibleTop then
            return writeNumber(view, "setYScroll", 0 - y + 40)
        end
        if y + childHeight + 40 > visibleTop + height then
            return writeNumber(view, "setYScroll", 0 - (y + childHeight + 40 - height))
        end
        return true
    end

    local function moveJoypadSelection(view, prior, ...)
        local state = viewFor(view)
        local keepButtonFocus = state ~= nil and state.joypadButton ~= nil
        if keepButtonFocus then clearJoypadButton(state) end
        local ok, a, b, c = pcall(prior, view, ...)
        if ok and not forceSelectedVisible(view) and state ~= nil then disableView(state) end
        if ok and keepButtonFocus and not focusCurrentButton(view, state) then clearJoypadButton(state) end
        if not ok then error(a, 0) end
        return a, b, c
    end

    local function preserveScrollInsideVanillaRender(view, scroll, appliedHeight, appliedScrollHeight)
        local heightCalled, heightSetter = pcall(function()
            return view.setHeightAndParentHeight
        end)
        local scrollCalled, scrollSetter = pcall(function()
            return view.setScrollHeight
        end)
        if not heightCalled or not scrollCalled
            or not callable(heightSetter) or not callable(scrollSetter) then
            return nil
        end

        local rawHeightSetter = rawget(view, "setHeightAndParentHeight")
        local rawScrollSetter = rawget(view, "setScrollHeight")
        local vanillaHeight = nil
        local vanillaScrollHeight = nil
        rawset(view, "setHeightAndParentHeight", function(target, value, ...)
            local a, b, c = heightSetter(target, value, ...)
            vanillaHeight = value
            if appliedHeight ~= nil and not propagate(target, appliedHeight, "height") then
                error("SLA could not preserve the shortened viewport during vanilla layout", 0)
            end
            if not writeNumber(target, "setYScroll", scroll) then
                error("SLA could not preserve scroll after vanilla height layout", 0)
            end
            return a, b, c
        end)
        rawset(view, "setScrollHeight", function(target, value, ...)
            local a, b, c = scrollSetter(target, value, ...)
            vanillaScrollHeight = value
            if appliedScrollHeight ~= nil then
                scrollSetter(target, appliedScrollHeight)
            end
            if not writeNumber(target, "setYScroll", scroll) then
                error("SLA could not preserve scroll after vanilla scroll layout", 0)
            end
            return a, b, c
        end)
        return function()
            rawset(view, "setHeightAndParentHeight", rawHeightSetter)
            rawset(view, "setScrollHeight", rawScrollSetter)
            if vanillaHeight ~= nil then heightSetter(view, vanillaHeight) end
            if vanillaScrollHeight ~= nil then scrollSetter(view, vanillaScrollHeight) end
        end
    end

    wrappers.prerender = function(view, ...)
        local state = viewFor(view)
        if state ~= nil and not state.disabled then
            local visibilityReady = installAdminVisibility(view, state)
            local availabilityReady = visibilityReady
                and updateAdminAvailability(view, state, false)
            local ownershipReady = availabilityReady and ensureAdminButton(view, state)
            local geometryRebased = ownershipReady and rebaseAdminGeometry(state)
            local prepared, result = pcall(prepareHeader, view, state)
            local primed, primeResult = pcall(primeAdminGeometry, state)
            if not visibilityReady or not availabilityReady or not ownershipReady or not geometryRebased
                or not prepared or not result or not primed or not primeResult then
                disableView(state)
            end
        end
        local ok, a, b, c = pcall(priorPrerender, view, ...)
        local addonOk = pcall(onPrerender, view)
        if not addonOk then disableView(views[view]) end
        state = views[view]
        if addonOk and state ~= nil and not state.disabled then
            local finalized, finalResult = pcall(function()
                return prepareGeometry(view, state)
                    and applyGeometry(view, state)
                    and primeAdminGeometry(state)
            end)
            if not finalized or not finalResult then disableView(state) end
        end
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.render = function(view, ...)
        local state = viewFor(view)
        local preservedScroll = nil
        local restoreRenderSetters = nil
        if state ~= nil and not state.disabled then
            if not rebaseAdminGeometry(state) then
                disableView(state)
            else
                preservedScroll = readNumber(view, "getYScroll")
                local headerCalled, headerPrepared = pcall(prepareHeader, view, state)
                local geometryCalled, geometryPrepared = pcall(prepareGeometry, view, state)
                if not headerCalled or not headerPrepared
                    or not geometryCalled or not geometryPrepared then disableView(state) end
                if preservedScroll ~= nil and not state.disabled then
                    restoreRenderSetters = preserveScrollInsideVanillaRender(view, preservedScroll,
                        state.appliedHeight, state.appliedScrollHeight)
                    if restoreRenderSetters == nil then disableView(state) end
                end
            end
        end
        local ok, a, b, c = pcall(priorRender, view, ...)
        if restoreRenderSetters ~= nil and not pcall(restoreRenderSetters) then
            disableView(views[view])
        end
        local addonOk = pcall(onRender, view)
        if not addonOk then disableView(views[view]) end
        state = views[view]
        if addonOk and preservedScroll ~= nil and state ~= nil and not state.disabled
            and not writeNumber(view, "setYScroll", preservedScroll) then
            disableView(state)
        end
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.renderPerkRect = function(bar, ...)
        local ok, a, b, c = pcall(priorRenderPerkRect, bar, ...)
        local barState = bars[bar]
        if ok and barState ~= nil and barState.supported then
            local currentLevel = rawget(bar, "level")
            if nonnegativeInteger(currentLevel) and currentLevel <= barState.effectiveMaximum
                and currentLevel ~= barState.currentLevel then
                barState.currentLevel = currentLevel
                if barState.state ~= nil then
                    barState.state.dirty = true
                end
                pcall(priorRemoveTooltip, bar)
            end
        end
        local addonCalled, addonResult = pcall(onOverlay, bar)
        if (not addonCalled or addonResult ~= true) and bars[bar] ~= nil then
            bars[bar].overlayValid = false
            local state = bars[bar].state
            if state ~= nil then disableView(state) end
        end
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.updateTooltip = function(bar, ...)
        local ok, a, b, c = pcall(priorUpdateTooltip, bar, ...)
        local addonOk = pcall(onTooltip, bar)
        if not addonOk and bars[bar] ~= nil then
            bars[bar].row = nil
            setButton(bars[bar], false, nil)
        end
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.activate = function(bar, ...)
        local ok, a, b, c = pcall(priorActivate, bar, ...)
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.onJoypadDown = function(view, button, ...)
        local state = viewFor(view)
        if state ~= nil and state.joypadButton ~= nil and button == joypadAButton then
            local forceClick = state.joypadButton.forceClick
            if not callable(forceClick) or not pcall(forceClick, state.joypadButton) then disableView(state) end
            return
        end
        local ok, a, b, c = pcall(priorOnJoypadDown, view, button, ...)
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.onJoypadDirUp = function(view, ...)
        return moveJoypadSelection(view, priorOnJoypadDirUp, ...)
    end
    wrappers.onJoypadDirDown = function(view, ...)
        return moveJoypadSelection(view, priorOnJoypadDirDown, ...)
    end
    wrappers.onJoypadDirLeft = function(view, ...)
        local state = viewFor(view)
        if state ~= nil and state.joypadButton ~= nil then clearJoypadButton(state); return end
        local ok, a, b, c = pcall(priorOnJoypadDirLeft, view, ...)
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.onJoypadDirRight = function(view, ...)
        local state = viewFor(view)
        if state ~= nil and focusCurrentButton(view, state) then return end
        local ok, a, b, c = pcall(priorOnJoypadDirRight, view, ...)
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.onGainJoypadFocus = function(view, ...)
        local state = viewFor(view)
        if state ~= nil then clearJoypadButton(state) end
        local ok, a, b, c = pcall(priorOnGainJoypadFocus, view, ...)
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.onLoseJoypadFocus = function(view, ...)
        local state = viewFor(view)
        if state ~= nil then clearJoypadButton(state) end
        local ok, a, b, c = pcall(priorOnLoseJoypadFocus, view, ...)
        if not ok then error(a, 0) end
        return a, b, c
    end

    local function ownsAdminIntegration()
        if adminLauncher == nil then return true end
        local called, value = pcall(adminStatus)
        return called and type(value) == "table" and getmetatable(value) == nil
            and rawget(value, "ok") == true and rawget(value, "installed") == true
    end

    local function ownsHooks()
        return ownsAdminIntegration()
            and rawget(characterInfo, "prerender") == wrappers.prerender
            and rawget(characterInfo, "render") == wrappers.render
            and rawget(characterInfo, "onJoypadDown") == wrappers.onJoypadDown
            and rawget(characterInfo, "onJoypadDirUp") == wrappers.onJoypadDirUp
            and rawget(characterInfo, "onJoypadDirDown") == wrappers.onJoypadDirDown
            and rawget(characterInfo, "onJoypadDirLeft") == wrappers.onJoypadDirLeft
            and rawget(characterInfo, "onJoypadDirRight") == wrappers.onJoypadDirRight
            and rawget(characterInfo, "onGainJoypadFocus") == wrappers.onGainJoypadFocus
            and rawget(characterInfo, "onLoseJoypadFocus") == wrappers.onLoseJoypadFocus
            and rawget(progressBar, "renderPerkRect") == wrappers.renderPerkRect
            and rawget(progressBar, "updateTooltip") == wrappers.updateTooltip
            and rawget(progressBar, "activate") == wrappers.activate
    end

    local integration = {}

    function integration.install()
        if installAttempted then
            if installed and ownsHooks() then return { ok = true } end
            return retain("hook_ownership_lost", "Skills UI wrappers")
        end
        installAttempted = true
        if adminLauncher ~= nil then
            local adminCalled, adminResult = pcall(adminInstall)
            if not adminCalled or not exactSuccess(adminResult) then
                return retain("admin_launcher_install_failed", "adminLauncher.install")
            end
        end
        local listenerCalled, listenerResult = pcall(setClientStateListener, markSlotDirty)
        if not listenerCalled or not exactSuccess(listenerResult) then
            return retain("listener_install_failed", "owner.setClientStateListener")
        end
        rawset(characterInfo, "prerender", wrappers.prerender)
        rawset(characterInfo, "render", wrappers.render)
        rawset(characterInfo, "onJoypadDown", wrappers.onJoypadDown)
        rawset(characterInfo, "onJoypadDirUp", wrappers.onJoypadDirUp)
        rawset(characterInfo, "onJoypadDirDown", wrappers.onJoypadDirDown)
        rawset(characterInfo, "onJoypadDirLeft", wrappers.onJoypadDirLeft)
        rawset(characterInfo, "onJoypadDirRight", wrappers.onJoypadDirRight)
        rawset(characterInfo, "onGainJoypadFocus", wrappers.onGainJoypadFocus)
        rawset(characterInfo, "onLoseJoypadFocus", wrappers.onLoseJoypadFocus)
        rawset(progressBar, "renderPerkRect", wrappers.renderPerkRect)
        rawset(progressBar, "updateTooltip", wrappers.updateTooltip)
        rawset(progressBar, "activate", wrappers.activate)
        if not ownsHooks() then return retain("hook_install_failed", "Skills UI wrappers") end
        installed = true
        return { ok = true }
    end

    function integration.status()
        local result = { ok = true, installed = installed and ownsHooks() }
        if retainedFailure ~= nil then
            result.failure = { code = retainedFailure.code, detail = retainedFailure.detail }
        elseif installed and not ownsHooks() then
            result.failure = { code = "hook_ownership_lost", detail = "Skills UI wrappers" }
        end
        return result
    end

    return { ok = true, integration = integration }
end

return Build42SkillsUi
