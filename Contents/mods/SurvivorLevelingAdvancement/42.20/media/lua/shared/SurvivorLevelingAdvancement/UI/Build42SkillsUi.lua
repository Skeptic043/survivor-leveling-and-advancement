local Build42SkillsUi = {}

local MAX_SAFE_INTEGER = 9007199254740991
local REFRESH_MILLIS = 1000
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
    local fields = { ok = true, pending = true }
    if rawget(value, "result") ~= nil then fields.result = true end
    return exactPlainTable(value, fields)
        and (rawget(value, "result") == nil or type(rawget(value, "result")) == "table"), false
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
    }
    if not exactPlainTable(settings, fields)
        or not finite(rawget(settings, "survivorMultiplier"))
        or rawget(settings, "survivorMultiplier") < 0
        or not finite(rawget(settings, "fitnessStrengthNormalization"))
        or rawget(settings, "fitnessStrengthNormalization") <= 0
        or type(rawget(settings, "automaticCurveNormalization")) ~= "boolean"
        or not nonnegativeInteger(rawget(settings, "globalLimit"))
        or not nonnegativeInteger(rawget(settings, "perSkillDefault")) then return nil end
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
        owner = true,
        viewModel = true,
        settingsProvider = true,
        progressionAdapter = true,
        clockMillis = true,
        getText = true,
        measureText = true,
        smallFont = true,
    }
    if not exactPlainTable(dependencies, dependencyFields) then
        return failure("invalid_dependencies", "dependencies")
    end

    local characterInfo = rawget(dependencies, "ISCharacterInfo")
    local progressBar = rawget(dependencies, "ISSkillProgressBar")
    local buttonClass = rawget(dependencies, "ISButton")
    local owner = rawget(dependencies, "owner")
    local viewModel = rawget(dependencies, "viewModel")
    local settingsProvider = rawget(dependencies, "settingsProvider")
    local progression = rawget(dependencies, "progressionAdapter")
    local clockMillis = rawget(dependencies, "clockMillis")
    local getText = rawget(dependencies, "getText")
    local measureText = rawget(dependencies, "measureText")
    local smallFont = rawget(dependencies, "smallFont")

    local priorPrerender = method(characterInfo, "prerender")
    local priorRender = method(characterInfo, "render")
    local priorRenderPerkRect = method(progressBar, "renderPerkRect")
    local priorUpdateTooltip = method(progressBar, "updateTooltip")
    local priorActivate = method(progressBar, "activate")
    local buttonNew = method(buttonClass, "new")
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

    if type(characterInfo) ~= "table" or type(progressBar) ~= "table" or type(buttonClass) ~= "table"
        or not priorPrerender or not priorRender or not priorRenderPerkRect
        or not priorUpdateTooltip or not priorActivate or not buttonNew
        or not clientState or not refreshOwner or not setClientStateListener
        or not requestAdvancement or not advancementStatus
        or not callable(buildView) or not callable(readSettings)
        or not callable(buildProgression) or not callable(describeProgression)
        or not callable(inspectProgression) or not callable(clockMillis)
        or not callable(getText) or not callable(measureText) or smallFont == nil then
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
            slot = slot,
            dirty = true,
            observed = false,
            barsReady = false,
            disabled = false,
            cache = nil,
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
            inset = nil,
            statusLeftText = nil,
            statusRightText = nil,
            statusLeft = nil,
            statusRight = nil,
            statusY = nil,
        }
        views[target] = state
        return state
    end

    local function removeButtonCallback(barState)
        local button = barState and barState.button or nil
        if type(button) == "table" then
            rawset(button, "onclick", nil)
            rawset(button, "target", nil)
        end
    end

    local restoreLayout

    local function disableView(state)
        if state == nil then return end
        if restoreLayout ~= nil then
            for view, candidate in pairs(views) do
                if candidate == state then
                    pcall(restoreLayout, view, state)
                    break
                end
            end
        end
        state.disabled = true
        state.cache = nil
        state.statusLeftText = nil
        state.statusRightText = nil
        state.statusLeft = nil
        state.statusRight = nil
        for bar in pairs(state.bars) do
            local barState = bars[bar]
            if barState and barState.button and callable(barState.button.setEnable) then
                pcall(barState.button.setEnable, barState.button, false)
            end
        end
    end

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
            if type(target) == "table" and callable(target.activate) then target:activate() end
        end)
        if not buttonCalled or type(button) ~= "table"
            or not callable(button.initialise) or not callable(button.setEnable)
            or not callable(button.setTooltip) or not callable(button.getWidth) then
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

    local function buttonTooltipFor(row)
        local lines = {}
        local reason = rawget(row, "reasonCode")
        if reason ~= nil then
            local key = REASON_KEYS[reason]
            local value = key and localized(key) or nil
            if value == nil then return nil end
            lines[#lines + 1] = value
        elseif rawget(row, "nextTargetLevel") ~= nil and rawget(row, "apCost") ~= nil then
            local value = localized("IGUI_SLA_Advance", rawget(row, "nextTargetLevel"), rawget(row, "apCost"))
            if value == nil then return nil end
            lines[#lines + 1] = value
        end
        if rawget(row, "activeCount") ~= nil and rawget(row, "limit") ~= nil then
            local value = localized("IGUI_SLA_PerSkillActive", rawget(row, "activeCount"), rawget(row, "limit"))
            if value == nil then return nil end
            lines[#lines + 1] = value
        end
        return table.concat(lines, " <LINE> ")
    end

    local function headerTexts(cache)
        local left = localized("IGUI_SLA_StatusAP", cache.survivor.availableAp)
        if left == nil then return nil, nil end
        if cache.allotment.mode ~= "Global" then return left, nil end
        local right = localized("IGUI_SLA_StatusActive", cache.allotment.activeCount, cache.allotment.limit)
        if right == nil then return nil, nil end
        return left, right
    end

    local function setButton(barState, enabled, tooltip)
        if barState.button == nil then return false end
        if not pcall(barState.button.setEnable, barState.button, enabled) then return false end
        if not pcall(barState.button.setTooltip, barState.button, tooltip) then return false end
        return true
    end

    local function applyCache(state)
        local cache = state.cache
        local left, right = nil, nil
        if cache then left, right = headerTexts(cache) end
        state.statusLeftText = left
        state.statusRightText = right
        if cache and left == nil then disableView(state); return false end
        for index = 1, #state.order do
            local barState = bars[state.order[index]]
            if barState and barState.supported then
                local row = cache and cache.rows[barState.perkId] or nil
                local tracked = cache ~= nil and cache.allotment.mode ~= "Free"
                local overlay = row ~= nil and (not tracked or validOverlay(barState, row))
                barState.row = row
                barState.tracked = tracked
                barState.overlayValid = overlay
                local tooltip = row and buttonTooltipFor(row) or nil
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
        local statusValid, pending = statusCalled and validAdvancementStatus(statusResult) or false, nil
        if statusValid then local _, value = validAdvancementStatus(statusResult); pending = value end
        local allotment = settingsCalled and projectAllotment(settingsResult) or nil
        if not stateValid or snapshot == nil or not statusValid or allotment == nil then
            state.cache = nil
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
            applyCache(state)
            return false
        end
        state.cache = rawget(built, "view")
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
            if view ~= nil and state.slot == slot and state.cache ~= nil then
                state.cache.pending = true
                applyCache(state)
            end
        end
    end

    local function request(barState)
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
        local inset = buttonY + buttonHeight
        if not finite(inset) or inset <= 0 then return false end
        local parent = rawget(view, "parent")
        if type(parent) ~= "table" then return false end
        local currentY = readNumber(view, "getY")
        local currentHeight = readNumber(view, "getHeight")
        if currentY == nil or currentHeight == nil or currentHeight < inset then return false end

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
        state.inset = inset
        local appliedY = state.baseY + inset
        if not writeNumber(view, "setY", appliedY) then return false end
        state.appliedY = appliedY
        local appliedHeight = state.vanillaHeight - inset
        if appliedHeight < 0 or not propagate(view, appliedHeight, "height") then return false end
        state.appliedHeight = appliedHeight
        return true
    end

    local function finishHeader(view, state)
        local height = readNumber(view, "getHeight")
        if height == nil or state.inset == nil or height < state.inset then return false end
        state.vanillaHeight = height
        local appliedHeight = height - state.inset
        if not propagate(view, appliedHeight, "height") then return false end
        state.appliedHeight = appliedHeight
        return true
    end

    restoreLayout = function(view, state)
        local restored = true
        if state.baseY ~= nil and not writeNumber(view, "setY", state.baseY) then restored = false end
        if state.vanillaHeight ~= nil and not propagate(view, state.vanillaHeight, "height") then
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
        if state.statusLeftText ~= nil then
            local contentLeft, y = firstButtonGeometry(view)
            local leftCalled, leftWidth = pcall(measureText, state.statusLeftText)
            if contentLeft == nil or not leftCalled or not finite(leftWidth) or leftWidth < 0 then return false end
            local headerRight = contentLeft + leftWidth
            if state.statusRightText ~= nil then
                local gapCalled, gapWidth = pcall(measureText, "  ")
                local rightCalled, rightWidth = pcall(measureText, state.statusRightText)
                if not gapCalled or not finite(gapWidth) or gapWidth < 0
                    or not rightCalled or not finite(rightWidth) or rightWidth < 0 then return false end
                headerRight = headerRight + gapWidth + rightWidth
            end
            requiredRight = math.max(requiredRight, headerRight)
            state.contentLeft = contentLeft
            state.statusLeft = contentLeft
            state.statusRight = state.statusRightText ~= nil and requiredRight or nil
            state.statusY = y
        else
            state.statusLeft, state.statusRight, state.statusY = nil, nil, nil
        end
        local desiredWidth = requiredRight + gutter
        if not propagate(view, desiredWidth, "width") then return false end
        state.appliedWidth = desiredWidth
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
        if state.statusLeftText ~= nil and state.statusLeft ~= nil then
            local parent = rawget(view, "parent")
            local viewX = readNumber(view, "getX")
            local drawLeft = type(parent) == "table" and parent.drawText or nil
            local drawRight = type(parent) == "table" and parent.drawTextRight or nil
            local y = state.baseY + state.statusY
            local leftOk = viewX ~= nil and callable(drawLeft)
                and pcall(drawLeft, parent, state.statusLeftText, viewX + state.statusLeft,
                    y, 1, 1, 1, 1, smallFont)
            local rightOk = state.statusRightText == nil or (viewX ~= nil and callable(drawRight)
                and pcall(drawRight, parent, state.statusRightText, viewX + state.statusRight,
                    y, 1, 1, 1, 1, smallFont))
            if not leftOk or not rightOk then
                disableView(state)
            end
        end
    end

    local function onOverlay(bar)
        local barState = bars[bar]
        if barState == nil or not barState.supported or not barState.overlayValid
            or not barState.tracked or barState.row == nil then return end
        local drawBorder = bar.drawRectBorder
        local drawRect = bar.drawRect
        if not callable(drawBorder) or not callable(drawRect) then return end
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
        if natural == nil then return end
        local highX = curvePosition(barState, high)
        if highX ~= nil then
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

    wrappers.prerender = function(view, ...)
        local state = viewFor(view)
        if state ~= nil and not state.disabled then
            local prepared, result = pcall(prepareHeader, view, state)
            if not prepared or not result then disableView(state) end
        end
        local ok, a, b, c = pcall(priorPrerender, view, ...)
        local addonOk = pcall(onPrerender, view)
        if not addonOk then disableView(views[view]) end
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.render = function(view, ...)
        local state = viewFor(view)
        if state ~= nil and not state.disabled then
            local headerCalled, headerPrepared = pcall(prepareHeader, view, state)
            local geometryCalled, geometryPrepared = pcall(prepareGeometry, view, state)
            if not headerCalled or not headerPrepared or not geometryCalled or not geometryPrepared then
                disableView(state)
            end
        end
        local ok, a, b, c = pcall(priorRender, view, ...)
        local addonOk = pcall(onRender, view)
        if not addonOk then disableView(views[view]) end
        if not ok then error(a, 0) end
        return a, b, c
    end
    wrappers.renderPerkRect = function(bar, ...)
        local ok, a, b, c = pcall(priorRenderPerkRect, bar, ...)
        local addonOk = pcall(onOverlay, bar)
        if not addonOk and bars[bar] ~= nil then
            bars[bar].overlayValid = false
            local state = bars[bar].state
            if state ~= nil then applyCache(state) end
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
        local barState = bars[bar]
        if barState ~= nil then pcall(request, barState) end
        if not ok then error(a, 0) end
        return a, b, c
    end

    local function ownsHooks()
        return rawget(characterInfo, "prerender") == wrappers.prerender
            and rawget(characterInfo, "render") == wrappers.render
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
        local listenerCalled, listenerResult = pcall(setClientStateListener, markSlotDirty)
        if not listenerCalled or not exactSuccess(listenerResult) then
            return retain("listener_install_failed", "owner.setClientStateListener")
        end
        rawset(characterInfo, "prerender", wrappers.prerender)
        rawset(characterInfo, "render", wrappers.render)
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
