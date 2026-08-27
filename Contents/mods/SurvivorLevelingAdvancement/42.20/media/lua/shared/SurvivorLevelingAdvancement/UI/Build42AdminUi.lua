local Build42AdminUi = {}

local MAX_SAFE_INTEGER = 9007199254740991
local PANEL_WIDTH = 400
local PANEL_HEIGHT = 318
local PANEL_MARGIN = 16
local PANEL_GAP = 20

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

local function callable(value)
    return type(value) == "function"
end

local function method(value, name)
    if type(value) ~= "table" then return nil end
    local candidate = rawget(value, name)
    return callable(candidate) and candidate or nil
end

local function protectedMember(value, name)
    if value == nil then return nil end
    local called, candidate = pcall(function() return value[name] end)
    return called and candidate or nil
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

local function validOwner(owner)
    local fields = {
        install = true,
        status = true,
        clientState = true,
        refreshOwner = true,
        setClientStateListener = true,
        requestAdvancement = true,
        advancementStatus = true,
        requestAdmin = true,
        adminStatus = true,
    }
    if not exactPlainTable(owner, fields) then return false end
    for key in pairs(fields) do
        if not callable(rawget(owner, key)) then return false end
    end
    return true
end

local function validSlot(value)
    return nonnegativeInteger(value) and value <= 3
end

local function boundedUsername(value)
    if type(value) ~= "string" or #value == 0 or #value > 64 then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then return false end
    end
    return true
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

local function validTarget(value)
    return exactPlainTable(value, { onlineId = true, username = true })
        and nonnegativeInteger(rawget(value, "onlineId"))
        and boundedUsername(rawget(value, "username"))
end

local function copyTarget(value)
    return { onlineId = rawget(value, "onlineId"), username = rawget(value, "username") }
end

local function validSummary(value)
    if not exactPlainTable(value, {
        accountingMode = true,
        revision = true,
        level = true,
        xpIntoLevel = true,
        xpForNextLevel = true,
        spent = true,
        availableAp = true,
    }) then return false end
    return (rawget(value, "accountingMode") == "Tracked"
            or rawget(value, "accountingMode") == "Free")
        and nonnegativeInteger(rawget(value, "revision"))
        and nonnegativeInteger(rawget(value, "level"))
        and finite(rawget(value, "xpIntoLevel"))
        and rawget(value, "xpIntoLevel") >= 0
        and finite(rawget(value, "xpForNextLevel"))
        and rawget(value, "xpForNextLevel") > 0
        and rawget(value, "xpIntoLevel") < rawget(value, "xpForNextLevel")
        and nonnegativeInteger(rawget(value, "spent"))
        and nonnegativeInteger(rawget(value, "availableAp"))
        and rawget(value, "spent") <= rawget(value, "level")
        and rawget(value, "availableAp") == rawget(value, "level") - rawget(value, "spent")
end

local function copySummary(value)
    return {
        accountingMode = rawget(value, "accountingMode"),
        revision = rawget(value, "revision"),
        level = rawget(value, "level"),
        xpIntoLevel = rawget(value, "xpIntoLevel"),
        xpForNextLevel = rawget(value, "xpForNextLevel"),
        spent = rawget(value, "spent"),
        availableAp = rawget(value, "availableAp"),
    }
end

local function parsePositiveNumber(value)
    if type(value) ~= "string" or #value == 0 or #value > 64 then return nil end
    local parsed = tonumber(value)
    if not finite(parsed) or parsed <= 0 then return nil end
    return parsed
end

local function parsePositiveInteger(value)
    local parsed = parsePositiveNumber(value)
    return positiveInteger(parsed) and parsed or nil
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

function Build42AdminUi.create(dependencies)
    local dependencyFields = {
        owner = true,
        ISMiniScoreboardUI = true,
        ISCollapsableWindowJoypad = true,
        ISTextEntryBox = true,
        ISButton = true,
        canSeePlayersStats = true,
        getPlayerContextMenu = true,
        getSpecificPlayer = true,
        isServer = true,
        isClient = true,
        isDebugEnabled = true,
        getText = true,
        viewport = true,
        smallFont = true,
    }
    if not exactPlainTable(dependencies, dependencyFields) then
        return failure("invalid_dependencies", "dependencies")
    end

    local owner = rawget(dependencies, "owner")
    local scoreboardClass = rawget(dependencies, "ISMiniScoreboardUI")
    local windowClass = rawget(dependencies, "ISCollapsableWindowJoypad")
    local entryClass = rawget(dependencies, "ISTextEntryBox")
    local buttonClass = rawget(dependencies, "ISButton")
    local seePlayerStats = rawget(dependencies, "canSeePlayersStats")
    local getPlayerContextMenu = rawget(dependencies, "getPlayerContextMenu")
    local getSpecificPlayer = rawget(dependencies, "getSpecificPlayer")
    local isServer = rawget(dependencies, "isServer")
    local isClient = rawget(dependencies, "isClient")
    local isDebugEnabled = rawget(dependencies, "isDebugEnabled")
    local getText = rawget(dependencies, "getText")
    local viewport = rawget(dependencies, "viewport")
    local smallFont = rawget(dependencies, "smallFont")

    local priorScoreboardMenu = method(scoreboardClass, "doPlayerListContextMenu")
    local windowNew = method(windowClass, "new")
    local windowCreateChildren = method(windowClass, "createChildren")
    local priorWindowPrerender = method(windowClass, "prerender")
    local windowInstantiate = protectedMember(windowClass, "instantiate")
    local entryNew = method(entryClass, "new")
    local buttonNew = method(buttonClass, "new")
    local requestAdmin = validOwner(owner) and rawget(owner, "requestAdmin") or nil
    local adminStatus = validOwner(owner) and rawget(owner, "adminStatus") or nil
    if type(scoreboardClass) ~= "table" or type(windowClass) ~= "table"
        or type(entryClass) ~= "table" or type(buttonClass) ~= "table"
        or not priorScoreboardMenu or not windowNew or not windowCreateChildren
        or not priorWindowPrerender or not callable(windowInstantiate) or not entryNew or not buttonNew
        or not requestAdmin or not adminStatus or seePlayerStats == nil
        or not callable(getPlayerContextMenu) or not callable(getSpecificPlayer) or not callable(isServer)
        or not callable(isClient) or not callable(isDebugEnabled)
        or not callable(getText) or not callable(viewport) or smallFont == nil then
        return failure("invalid_dependencies", "callables")
    end

    local serverCalled, serverValue = pcall(isServer)
    local clientCalled, clientValue = pcall(isClient)
    if not serverCalled or not clientCalled or type(serverValue) ~= "boolean"
        or type(clientValue) ~= "boolean" or (serverValue and clientValue) then
        return failure("invalid_process_mode", "process mode")
    end
    if serverValue then return failure("invalid_process_mode", "server") end
    local mode = clientValue and "multiplayer" or "singleplayer"

    local installed = false
    local installAttempted = false
    local retainedFailure = nil
    local wrapper = nil
    local panels = {}

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

    local function debugAvailable(slot)
        if mode ~= "singleplayer" or not validSlot(slot) then return false end
        local called, value = pcall(isDebugEnabled)
        if not called or type(value) ~= "boolean" then
            retain("debug_capability_failed", "isDebugEnabled")
            return false
        end
        return value
    end

    local function actorCanInspect(admin)
        local getRole = protectedMember(admin, "getRole")
        if not callable(getRole) then return false end
        local roleCalled, role = pcall(getRole, admin)
        if not roleCalled or role == nil then return false end
        local hasCapability = protectedMember(role, "hasCapability")
        if not callable(hasCapability) then return false end
        local called, allowed = pcall(hasCapability, role, seePlayerStats)
        return called and allowed == true
    end

    local function localAdminUsername(slot)
        if mode ~= "multiplayer" or not validSlot(slot) then return nil end
        local playerCalled, player = pcall(getSpecificPlayer, slot)
        if not playerCalled or player == nil or not actorCanInspect(player) then return nil end
        local getUsername = protectedMember(player, "getUsername")
        if not callable(getUsername) then return nil end
        local usernameCalled, username = pcall(getUsername, player)
        return usernameCalled and boundedUsername(username) and username or nil
    end

    local function launcherAvailable(slot)
        if mode == "multiplayer" then return localAdminUsername(slot) ~= nil end
        return debugAvailable(slot)
    end

    local function targetMatches(left, right)
        return validTarget(left) and validTarget(right)
            and rawget(left, "onlineId") == rawget(right, "onlineId")
            and rawget(left, "username") == rawget(right, "username")
    end

    local function statusRoute(value)
        if not exactPlainTable(value, {
            ok = true, pending = true, requestId = true, operation = true, target = true,
        }) or rawget(value, "ok") ~= true or rawget(value, "pending") ~= true
            or not safeId(rawget(value, "requestId"), 64) then return nil end
        local operation = rawget(value, "operation")
        local target = rawget(value, "target")
        if operation ~= "inspect" or type(target) ~= "table" or getmetatable(target) ~= nil
            or not exactPlainTable(target, { username = true })
            or not boundedUsername(rawget(target, "username")) then return nil end
        return { operation = operation, username = rawget(target, "username") }
    end

    local function terminalFromStatus(value)
        if not exactPlainTable(value, { ok = true, pending = true, result = true })
            or rawget(value, "ok") ~= true or rawget(value, "pending") ~= false then return nil end
        local result = rawget(value, "result")
        return type(result) == "table" and getmetatable(result) == nil and result or nil
    end

    local function validClearGains(result, operation, outcome)
        return operation ~= "clearAdvancementSlots" or outcome ~= "applied"
            or (rawget(result, "levelsGained") == 0
                and rawget(result, "apGained") == 0)
    end

    local function validStatusTerminal(result)
        if type(result) ~= "table" or getmetatable(result) ~= nil then return false end
        local operation = rawget(result, "operation")
        if operation ~= "inspect" and operation ~= "awardSurvivorXp"
            and operation ~= "awardSurvivorLevels"
            and operation ~= "clearAdvancementSlots" then return false end
        local succeeded = rawget(result, "ok")
        if type(succeeded) ~= "boolean" then return false end
        if rawget(result, "protocolVersion") ~= nil then return false end
        if mode == "multiplayer" then
            if not safeId(rawget(result, "requestId"), 64) then return false end
            local target = rawget(result, "target")
            if operation == "inspect" and not succeeded then
                if not exactPlainTable(target, { username = true })
                    or not boundedUsername(rawget(target, "username")) then return false end
            elseif not validTarget(target) then
                return false
            end
        elseif rawget(result, "requestId") ~= nil or rawget(result, "target") ~= nil then
            return false
        end
        if not succeeded then return type(rawget(result, "committed")) == "boolean" end
        if not validSummary(rawget(result, "summary")) then return false end
        local outcome = rawget(result, "outcome")
        if operation == "inspect" then return outcome == "inspected" end
        return (outcome == "applied" and validClearGains(result, operation, outcome))
            or (outcome == "rejected" and rawget(result, "code") == "stale_revision")
    end

    local function validNonpendingStatus(value)
        if exactPlainTable(value, { ok = true, pending = true }) then
            return rawget(value, "ok") == true and rawget(value, "pending") == false
        end
        if exactPlainTable(value, { ok = true, pending = true, result = true }) then
            return rawget(value, "ok") == true and rawget(value, "pending") == false
                and validStatusTerminal(rawget(value, "result"))
        end
        return false
    end

    local function validPendingStatus(value)
        if not exactPlainTable(value, {
            ok = true, pending = true, requestId = true, operation = true, target = true,
        }) or rawget(value, "ok") ~= true or rawget(value, "pending") ~= true
            or not safeId(rawget(value, "requestId"), 64) then return false end
        local operation = rawget(value, "operation")
        local target = rawget(value, "target")
        if operation == "inspect" then
            return exactPlainTable(target, { username = true })
                and boundedUsername(rawget(target, "username"))
        end
        return (operation == "awardSurvivorXp" or operation == "awardSurvivorLevels"
                or operation == "clearAdvancementSlots")
            and validTarget(target)
    end

    local function pendingMatches(state, value)
        if not validPendingStatus(value)
            or rawget(value, "requestId") ~= state.pendingRequestId
            or rawget(value, "operation") ~= state.pendingOperation then return false end
        local target = rawget(value, "target")
        if state.pendingOperation == "inspect" then
            return exactPlainTable(target, { username = true })
                and rawget(target, "username") == state.selectedUsername
        end
        return mode == "multiplayer" and targetMatches(target, state.target)
    end

    local function makeControl(classTable, constructor, ...)
        local called, control = pcall(constructor, classTable, ...)
        if not called or type(control) ~= "table" then return nil end
        local initialise = control.initialise
        if not callable(initialise) or not pcall(initialise, control) then return nil end
        return control
    end

    local function addChild(parent, child)
        local add = type(parent) == "table" and parent.addChild or nil
        return callable(add) and pcall(add, parent, child)
    end

    local function setEnabled(control, enabled)
        local setter = type(control) == "table" and control.setEnable or nil
        return callable(setter) and pcall(setter, control, enabled)
    end

    local function setEditable(control, enabled)
        local setter = type(control) == "table" and control.setEditable or nil
        if not callable(setter) then return true end
        return pcall(setter, control, enabled)
    end

    local function setVisible(control, visible)
        local setter = type(control) == "table" and control.setVisible or nil
        return callable(setter) and pcall(setter, control, visible)
    end

    local function updateControls(state)
        local access = launcherAvailable(state.slot)
        state.access = access
        local mutationEnabled = access and not state.waiting and state.summary ~= nil
        local refreshEnabled = access and not state.waiting
        local clearVisible = state.summary ~= nil
            and state.summary.accountingMode == "Tracked"
        setEnabled(state.awardXpButton, mutationEnabled)
        setEnabled(state.awardLevelsButton, mutationEnabled)
        setVisible(state.clearSlotsButton, clearVisible)
        setEnabled(state.clearSlotsButton, mutationEnabled and clearVisible)
        setEnabled(state.refreshButton, refreshEnabled)
        setEditable(state.xpEntry, mutationEnabled)
        setEditable(state.levelsEntry, mutationEnabled)
    end

    local function requestShape(state, operation, operandName, operand)
        local request = { operation = operation }
        if operation == "inspect" then
            if mode == "multiplayer" then
                local username = state.target and state.target.username or state.selectedUsername
                request.target = { username = username }
            end
        else
            if mode == "multiplayer" then request.target = copyTarget(state.target) end
            request.expectedRevision = state.summary.revision
            if operandName ~= nil then request[operandName] = operand end
        end
        return request
    end

    local function acceptTerminal(state, result, expectedOperation)
        if type(result) ~= "table" or getmetatable(result) ~= nil then return false end
        if type(rawget(result, "ok")) ~= "boolean" then return false end
        local operation = rawget(result, "operation")
        if operation ~= expectedOperation then return false end
        if mode == "multiplayer" then
            if rawget(result, "protocolVersion") ~= nil
                or rawget(result, "requestId") ~= state.pendingRequestId
                or not safeId(rawget(result, "requestId"), 64) then return false end
            local target = rawget(result, "target")
            if expectedOperation == "inspect" then
                if rawget(result, "ok") == true then
                    if not validTarget(target) or target.username ~= state.selectedUsername then return false end
                elseif not exactPlainTable(target, { username = true })
                    or not boundedUsername(rawget(target, "username"))
                    or rawget(target, "username") ~= state.selectedUsername then
                    return false
                end
            elseif not targetMatches(target, state.target) then
                return false
            end
        elseif rawget(result, "protocolVersion") ~= nil
            or rawget(result, "requestId") ~= nil or rawget(result, "target") ~= nil then
            return false
        end

        if rawget(result, "ok") == true then
            local summary = rawget(result, "summary")
            if not validSummary(summary) then return false end
            local outcome = rawget(result, "outcome")
            if outcome == nil then
                if expectedOperation == "inspect" then outcome = "inspected"
                elseif rawget(result, "applied") == true then outcome = "applied"
                elseif rawget(result, "applied") == false and rawget(result, "code") == "stale_revision" then
                    outcome = "rejected"
                end
            end
            if outcome ~= "inspected" and outcome ~= "applied"
                and not (outcome == "rejected" and rawget(result, "code") == "stale_revision") then
                return false
            end
            if not validClearGains(result, expectedOperation, outcome) then return false end
            state.summary = copySummary(summary)
            if mode == "multiplayer" and expectedOperation == "inspect" then
                state.target = copyTarget(rawget(result, "target"))
            end
            if outcome == "inspected" then
                state.message = localized("IGUI_SLA_Admin_Inspected")
            elseif outcome == "applied" then
                state.message = localized("IGUI_SLA_Admin_Applied")
            else
                state.message = localized("IGUI_SLA_Admin_Stale")
            end
            state.waiting = false
            state.pendingRequestId = nil
            state.pendingOperation = nil
            return state.message ~= nil
        end

        if type(rawget(result, "committed")) ~= "boolean" then return false end
        state.message = localized(rawget(result, "committed")
            and "IGUI_SLA_Admin_CommittedFailure" or "IGUI_SLA_Admin_Failure")
        state.waiting = false
        state.pendingRequestId = nil
        state.pendingOperation = nil
        return state.message ~= nil
    end

    local function acceptedPending(result)
        return exactPlainTable(result, { ok = true, requestId = true })
            and rawget(result, "ok") == true
            and safeId(rawget(result, "requestId"), 64)
    end

    local function beginRequest(state, operation, operandName, operand)
        if state.waiting or not state.access then return false end
        if operation ~= "inspect" and state.summary == nil then return false end
        local request = requestShape(state, operation, operandName, operand)
        local called, result = pcall(requestAdmin, state.slot, request)
        if not called or type(result) ~= "table" or getmetatable(result) ~= nil then
            state.message = localized("IGUI_SLA_Admin_Failure")
            updateControls(state)
            return false
        end
        if acceptedPending(result) then
            state.waiting = true
            state.pendingOperation = operation
            state.pendingRequestId = rawget(result, "requestId")
            state.message = localized("IGUI_SLA_Admin_Waiting")
            updateControls(state)
            return true
        end
        if acceptTerminal(state, result, operation) then
            updateControls(state)
            return true
        end
        state.message = localized("IGUI_SLA_Admin_Failure")
        updateControls(state)
        return false
    end

    local function readEntry(entry)
        local getValue = type(entry) == "table" and entry.getText or nil
        if not callable(getValue) then return nil end
        local called, value = pcall(getValue, entry)
        return called and value or nil
    end

    local function onPanelButton(state, button)
        if type(state) ~= "table" or panels[state.slot] ~= state.window
            or type(button) ~= "table" then return end
        updateControls(state)
        if not state.access or state.waiting then return end
        local action = rawget(button, "internal")
        if action == "REFRESH" then
            beginRequest(state, "inspect")
            return
        end
        if state.summary == nil then return end
        if action == "XP" then
            local amount = parsePositiveNumber(readEntry(state.xpEntry))
            if amount == nil then
                state.message = localized("IGUI_SLA_Admin_InvalidXp")
                return
            end
            beginRequest(state, "awardSurvivorXp", "amount", amount)
        elseif action == "LEVELS" then
            local count = parsePositiveInteger(readEntry(state.levelsEntry))
            if count == nil then
                state.message = localized("IGUI_SLA_Admin_InvalidLevels")
                return
            end
            beginRequest(state, "awardSurvivorLevels", "count", count)
        elseif action == "CLEAR" and state.summary.accountingMode == "Tracked" then
            beginRequest(state, "clearAdvancementSlots")
        end
    end

    local function drawPanel(state)
        local window = state.window
        local draw = type(window) == "table" and window.drawText or nil
        if not callable(draw) then return end
        local function drawLine(text, x, y)
            if text ~= nil then pcall(draw, window, text, x, y, 1, 1, 1, 1, smallFont) end
        end
        if mode == "multiplayer" then
            local username = state.target and state.target.username or state.selectedUsername
            drawLine(localized("IGUI_SLA_Admin_Target", username), 16, 34)
        end
        local summary = state.summary
        if summary ~= nil then
            drawLine(localized("IGUI_SLA_Admin_Level", summary.level), 16, 58)
            local current = formatSurvivorXp(summary.xpIntoLevel)
            local required = formatSurvivorXp(summary.xpForNextLevel)
            if current ~= nil and required ~= nil then
                drawLine(localized("IGUI_SLA_Admin_Xp", current, required), 16, 78)
            end
            drawLine(localized("IGUI_SLA_Admin_Ap", summary.availableAp), 16, 98)
        end
        drawLine(state.message, 16, 122)
        drawLine(localized("IGUI_SLA_Admin_XpInput"), 16, 151)
        drawLine(localized("IGUI_SLA_Admin_LevelsInput"), 16, 211)
    end

    local function closePanel(state)
        if panels[state.slot] ~= state.window then return end
        panels[state.slot] = nil
        state.closed = true
        local remove = state.window.removeFromUIManager
        if callable(remove) then pcall(remove, state.window) end
    end

    local function makeButton(state, x, y, width, title, action)
        local button = makeControl(buttonClass, buttonNew, x, y, width, 24, title, state, onPanelButton)
        if button == nil then return nil end
        rawset(button, "internal", action)
        return button
    end

    local function buildChildren(state)
        windowCreateChildren(state.window)
        local grid = state.grid
        if type(grid) ~= "table" then return false end
        local xpEntry = makeControl(entryClass, entryNew, "", grid.left, 170, grid.width, 24)
        local levelsEntry = makeControl(entryClass, entryNew, "", grid.left, 230, grid.width, 24)
        local awardXp = makeButton(state, grid.right, 170, grid.width,
            localized("IGUI_SLA_Admin_AwardXp"), "XP")
        local awardLevels = makeButton(state, grid.right, 230, grid.width,
            localized("IGUI_SLA_Admin_AwardLevels"), "LEVELS")
        local clearSlots = makeButton(state, grid.left, 274, grid.width,
            localized("IGUI_SLA_Admin_ClearSlots"), "CLEAR")
        local refresh = makeButton(state, grid.right, 274, grid.width,
            localized("IGUI_SLA_Admin_Refresh"), "REFRESH")
        if xpEntry == nil or levelsEntry == nil or awardXp == nil
            or awardLevels == nil or clearSlots == nil or refresh == nil
            or not callable(clearSlots.setVisible) then return false end
        state.xpEntry = xpEntry
        state.levelsEntry = levelsEntry
        state.awardXpButton = awardXp
        state.awardLevelsButton = awardLevels
        state.clearSlotsButton = clearSlots
        state.refreshButton = refresh
        return addChild(state.window, xpEntry) and addChild(state.window, awardXp)
            and addChild(state.window, levelsEntry) and addChild(state.window, awardLevels)
            and addChild(state.window, clearSlots)
            and addChild(state.window, refresh)
    end

    local function poll(state)
        updateControls(state)
        if not state.waiting or not state.access then return end
        local called, value = pcall(adminStatus, state.slot)
        if not called then
            state.waiting = false
            state.pendingRequestId = nil
            state.pendingOperation = nil
            state.message = localized("IGUI_SLA_Admin_Failure")
            updateControls(state)
            return
        end
        if type(value) == "table" and rawget(value, "pending") == true then
            if pendingMatches(state, value) then return end
            state.waiting = false
            state.pendingRequestId = nil
            state.pendingOperation = nil
            state.message = localized("IGUI_SLA_Admin_Failure")
            updateControls(state)
            return
        end
        local terminal = terminalFromStatus(value)
        if terminal == nil or not acceptTerminal(state, terminal, state.pendingOperation) then
            state.waiting = false
            state.pendingRequestId = nil
            state.pendingOperation = nil
            state.message = localized("IGUI_SLA_Admin_Failure")
        end
        updateControls(state)
    end

    local function createPanel(slot, username)
        local viewportCalled, viewportLeft, viewportTop, viewportWidth, viewportHeight = pcall(viewport, slot)
        if not viewportCalled or not finite(viewportLeft) or not finite(viewportTop)
            or not finite(viewportWidth) or not finite(viewportHeight)
            or viewportWidth <= 0 or viewportHeight <= 0 then
            return nil, failure("viewport_failed", "viewport")
        end
        local width = math.min(PANEL_WIDTH, viewportWidth)
        local height = math.min(PANEL_HEIGHT, viewportHeight)
        local x = viewportLeft + math.max(0, math.min(viewportWidth - width,
            math.floor((viewportWidth - width) / 2)))
        local y = viewportTop + math.max(0, math.min(viewportHeight - height,
            math.floor((viewportHeight - height) / 2)))
        local called, window = pcall(windowNew, windowClass, x, y, width, height)
        if not called or type(window) ~= "table" then return nil, failure("window_create_failed", "window") end

        local state = {
            slot = slot,
            selectedUsername = username,
            target = nil,
            summary = nil,
            waiting = false,
            pendingOperation = nil,
            pendingRequestId = nil,
            access = launcherAvailable(slot),
            message = localized("IGUI_SLA_Admin_Waiting"),
            window = window,
            grid = {
                left = PANEL_MARGIN,
                width = (width - PANEL_MARGIN * 2 - PANEL_GAP) / 2,
                right = PANEL_MARGIN + (width - PANEL_MARGIN * 2 - PANEL_GAP) / 2 + PANEL_GAP,
            },
            closed = false,
        }
        if state.message == nil or state.grid.width <= 0 then
            return nil, failure("translation_failed", "admin copy")
        end
        window.createChildren = function()
            if not buildChildren(state) then error("admin child construction") end
        end
        window.prerender = function(self, ...)
            local ok, a, b, c = pcall(priorWindowPrerender, self, ...)
            if not ok then error(a, 0) end
            if not state.closed then
                poll(state)
                drawPanel(state)
            end
            return a, b, c
        end
        window.close = function() closePanel(state) end
        local setTitle = window.setTitle
        local title = localized("IGUI_SLA_Admin_Title")
        if not callable(setTitle) or title == nil or not pcall(setTitle, window, title) then
            return nil, failure("window_create_failed", "title")
        end
        rawset(window, "resizable", false)
        local initialise = window.initialise
        local addToManager = window.addToUIManager
        local setVisible = window.setVisible
        local removeFromManager = window.removeFromUIManager
        local function cleanup()
            if callable(setVisible) then pcall(setVisible, window, false) end
            if callable(removeFromManager) then pcall(removeFromManager, window) end
        end
        if not callable(initialise) or not callable(addToManager) or not callable(setVisible)
            or not callable(removeFromManager) or not pcall(initialise, window)
            or not pcall(windowInstantiate, window) or not pcall(addToManager, window)
            or not pcall(setVisible, window, true) then
            cleanup()
            return nil, failure("window_create_failed", "lifecycle")
        end
        panels[slot] = window
        updateControls(state)
        return state, nil
    end

    local function attachOrInspect(state)
        local statusCalled, current = pcall(adminStatus, state.slot)
        if not statusCalled or type(current) ~= "table" or getmetatable(current) ~= nil then
            state.message = localized("IGUI_SLA_Admin_Failure")
            updateControls(state)
            return false
        end
        if rawget(current, "pending") == true then
            if not validPendingStatus(current) then
                state.message = localized("IGUI_SLA_Admin_Failure")
                updateControls(state)
                return false
            end
            local route = statusRoute(current)
            if route ~= nil and route.username == state.selectedUsername then
                state.waiting = true
                state.pendingOperation = "inspect"
                state.pendingRequestId = rawget(current, "requestId")
                updateControls(state)
                return true
            end
            state.message = localized("IGUI_SLA_Admin_PendingOther")
            updateControls(state)
            return false
        end
        if not validNonpendingStatus(current) then
            state.message = localized("IGUI_SLA_Admin_Failure")
            updateControls(state)
            return false
        end
        return beginRequest(state, "inspect")
    end

    local function open(slot, username)
        if not validSlot(slot) then return failure("invalid_slot", "localSlot") end
        if mode == "singleplayer" then
            if username ~= nil then return failure("invalid_target", "single player") end
            if not debugAvailable(slot) then return failure("debug_unavailable", "debug") end
        elseif username == nil then
            username = localAdminUsername(slot)
            if username == nil then return failure("admin_unavailable", "local player") end
        elseif not boundedUsername(username) then
            return failure("invalid_target", "username")
        end

        local existing = panels[slot]
        if type(existing) == "table" then
            local state = rawget(existing, "__slaAdminState")
            if type(state) == "table" and not state.closed
                and (mode == "singleplayer" or state.selectedUsername == username) then
                local bring = existing.bringToTop
                if callable(bring) then pcall(bring, existing) end
                if not state.waiting then attachOrInspect(state) end
                return { ok = true }
            end
            if type(state) == "table" then closePanel(state) end
        end

        local state, createFailure = createPanel(slot, username)
        if state == nil then return createFailure end
        rawset(state.window, "__slaAdminState", state)
        attachOrInspect(state)
        return { ok = true }
    end

    local function appendScoreboardAction(scoreboard, player)
        if mode ~= "multiplayer" or type(scoreboard) ~= "table" or type(player) ~= "table"
            or not actorCanInspect(rawget(scoreboard, "admin")) then return end
        local admin = rawget(scoreboard, "admin")
        local getPlayerNum = protectedMember(admin, "getPlayerNum")
        if not callable(getPlayerNum) then return end
        local slotCalled, slot = pcall(getPlayerNum, admin)
        local username = rawget(player, "username")
        if not slotCalled or not validSlot(slot) or not boundedUsername(username) then return end
        local menuCalled, menu = pcall(getPlayerContextMenu, slot)
        local addOption = type(menu) == "table" and menu.addOption or nil
        local title = localized("IGUI_SLA_Admin_Menu")
        if not menuCalled or not callable(addOption) or title == nil then return end
        local controller = { slot = slot, username = username }
        controller.activate = function(target)
            open(target.slot, target.username)
        end
        pcall(addOption, menu, title, controller, controller.activate)
    end

    wrapper = function(scoreboard, player, x, y, ...)
        local ok, a, b, c = pcall(priorScoreboardMenu, scoreboard, player, x, y, ...)
        if not ok then error(a, 0) end
        local appended = pcall(appendScoreboardAction, scoreboard, player)
        if not appended then retain("scoreboard_append_failed", "context menu") end
        return a, b, c
    end

    local function ownsHook()
        return mode == "singleplayer" or rawget(scoreboardClass, "doPlayerListContextMenu") == wrapper
    end

    local integration = {}

    function integration.install()
        if installAttempted then
            if installed and ownsHook() then return { ok = true } end
            return retain("hook_ownership_lost", "scoreboard wrapper")
        end
        installAttempted = true
        if mode == "multiplayer" then
            rawset(scoreboardClass, "doPlayerListContextMenu", wrapper)
            if not ownsHook() then return retain("hook_install_failed", "scoreboard wrapper") end
        end
        installed = true
        return { ok = true }
    end

    function integration.status()
        local result = { ok = true, installed = installed and ownsHook(), mode = mode }
        if retainedFailure ~= nil then
            result.failure = { code = retainedFailure.code, detail = retainedFailure.detail }
        elseif installed and not ownsHook() then
            result.failure = { code = "hook_ownership_lost", detail = "scoreboard wrapper" }
        end
        return result
    end

    function integration.isAvailable(slot)
        return launcherAvailable(slot)
    end

    function integration.open(slot, username)
        return open(slot, username)
    end

    return { ok = true, integration = integration }
end

return Build42AdminUi
