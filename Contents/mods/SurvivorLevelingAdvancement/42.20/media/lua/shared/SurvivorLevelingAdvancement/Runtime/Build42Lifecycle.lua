local Build42Lifecycle = {}

local MODULE = "SurvivorLevelingAdvancement"
local MAX_SAFE_INTEGER = 9007199254740991
local nextLocalRequest = 0

local function failure(code, detail, committed)
    local result = { ok = false, code = code, detail = detail }
    if committed ~= nil then result.committed = committed end
    return result
end

local function callable(value) return type(value) == "function" end

local function safeInteger(value)
    return type(value) == "number" and value == value and value >= 0
        and value <= MAX_SAFE_INTEGER and value == math.floor(value)
end

local function safeText(value, maximum, identifier)
    if type(value) ~= "string" or #value == 0 or #value > maximum then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if identifier then
            local allowed = (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90)
                or (byte >= 97 and byte <= 122) or byte == 95 or byte == 46
                or byte == 58 or byte == 45
            if not allowed then return false end
        elseif byte < 32 or byte > 126 then
            return false
        end
    end
    return true
end

local function safeId(value, maximum) return safeText(value, maximum, true) end

local function safeUsername(value)
    if type(value) ~= "string" or #value == 0 or #value > 64 then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then return false end
    end
    return true
end

local function exactTable(value, fields)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do if type(key) ~= "string" or not fields[key] then return false end end
    for key in pairs(fields) do if rawget(value, key) == nil then return false end end
    return true
end

local function bounded(result, code, detail)
    if type(result) == "table" and rawget(result, "ok") == false
        and safeId(rawget(result, "code"), 64)
        and safeText(rawget(result, "detail"), 160, false) then
        local committed = rawget(result, "committed")
        if committed == nil or type(committed) == "boolean" then
            return failure(rawget(result, "code"), rawget(result, "detail"), committed)
        end
    end
    return failure(code, detail)
end

local function validSlot(value) return safeInteger(value) and value <= 3 end

local function pendingNewList(value)
    if value == nil then return {} end
    if type(value) ~= "table" or getmetatable(value) ~= nil or #value > 4 then return nil end
    local copy, seen = {}, {}
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > #value or key ~= math.floor(key) then return nil end
    end
    for index = 1, #value do
        local player = rawget(value, index)
        if player == nil or seen[player] then return nil end
        seen[player], copy[index] = true, player
    end
    return copy
end

local function pendingLocalMap(value)
    if value == nil then return {} end
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    local copy, count = {}, 0
    for slot, player in pairs(value) do
        if not validSlot(slot) or player == nil then return nil end
        count = count + 1
        if count > 4 then return nil end
        copy[slot] = player
    end
    return copy
end

local function eventSet(events, names, removable)
    if type(events) ~= "table" then return nil end
    local captured = {}
    for index = 1, #names do
        local name = names[index]
        local event = rawget(events, name)
        if type(event) ~= "table" or not callable(rawget(event, "Add"))
            or (removable ~= nil and removable[name] and not callable(rawget(event, "Remove"))) then return nil end
        captured[name] = event
    end
    return captured
end

local function service(result, field, methods)
    if not exactTable(result, { ok = true, [field] = true }) or rawget(result, "ok") ~= true then return nil end
    local value = rawget(result, field)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    local captured = { value = value }
    for index = 1, #methods do
        local name = methods[index]
        if not callable(rawget(value, name)) then return nil end
        captured[name] = rawget(value, name)
    end
    return captured
end

local function acceptance(result)
    if exactTable(result, { ok = true, accepted = true })
        and rawget(result, "ok") == true and rawget(result, "accepted") == true then return true end
    if exactTable(result, { ok = true, accepted = true, code = true })
        and rawget(result, "ok") == true and rawget(result, "accepted") == false
        and rawget(result, "code") == "stale_snapshot" then return false, "stale_snapshot" end
    return nil
end

local function detachSummary(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil
        or type(rawget(value, "ok")) ~= "boolean"
        or not safeId(rawget(value, "requestId"), 64)
        or not safeId(rawget(value, "perkId"), 128) then return nil end
    local fields
    if rawget(value, "ok") == true and rawget(value, "applied") == true then
        fields = { ok = true, applied = true, requestId = true, perkId = true,
            apCost = true, mastered = true, snapshotAccepted = true }
        if rawget(value, "snapshotCode") ~= nil then fields.snapshotCode = true end
    elseif rawget(value, "ok") == true and rawget(value, "applied") == false then
        fields = { ok = true, applied = true, requestId = true, perkId = true, code = true, detail = true }
        if rawget(value, "snapshotAccepted") ~= nil then fields.snapshotAccepted = true end
        if rawget(value, "snapshotCode") ~= nil then fields.snapshotCode = true end
    elseif rawget(value, "ok") == false and rawget(value, "applied") == nil then
        fields = { ok = true, requestId = true, perkId = true, code = true, detail = true, committed = true }
    elseif rawget(value, "ok") == false and type(rawget(value, "applied")) == "boolean" then
        fields = { ok = true, applied = true, requestId = true, perkId = true,
            code = true, detail = true, committed = true }
        if rawget(value, "applied") == true then fields.apCost, fields.mastered = true, true
        else fields.upstreamCode, fields.upstreamDetail = true, true end
    end
    if fields == nil or not exactTable(value, fields) then return nil end
    local copy = {}
    for key, item in pairs(value) do
        if type(key) ~= "string" or not fields[key]
            or (type(item) ~= "boolean" and type(item) ~= "number" and type(item) ~= "string") then return nil end
        copy[key] = item
    end
    if rawget(value, "applied") ~= nil and type(rawget(value, "applied")) ~= "boolean" then return nil end
    if rawget(value, "apCost") ~= nil and rawget(value, "apCost") ~= 1 and rawget(value, "apCost") ~= 2 then return nil end
    if rawget(value, "mastered") ~= nil and type(rawget(value, "mastered")) ~= "boolean" then return nil end
    if rawget(value, "apCost") ~= nil
        and rawget(value, "mastered") ~= (rawget(value, "apCost") == 2) then return nil end
    if rawget(value, "snapshotAccepted") ~= nil and type(rawget(value, "snapshotAccepted")) ~= "boolean" then return nil end
    if rawget(value, "committed") ~= nil and type(rawget(value, "committed")) ~= "boolean" then return nil end
    if rawget(value, "code") ~= nil and not safeId(rawget(value, "code"), 64) then return nil end
    if rawget(value, "detail") ~= nil and not safeText(rawget(value, "detail"), 160, false) then return nil end
    if rawget(value, "snapshotCode") ~= nil and rawget(value, "snapshotCode") ~= "stale_snapshot" then return nil end
    if rawget(value, "snapshotCode") ~= nil and rawget(value, "snapshotAccepted") ~= false then return nil end
    if rawget(value, "upstreamCode") ~= nil and not safeId(rawget(value, "upstreamCode"), 64) then return nil end
    if rawget(value, "upstreamDetail") ~= nil and not safeText(rawget(value, "upstreamDetail"), 160, false) then return nil end
    return copy
end

local function detachStatus(value)
    if exactTable(value, { ok = true, pending = true })
        and rawget(value, "ok") == true and rawget(value, "pending") == false then
        return { ok = true, pending = false }
    end
    if exactTable(value, { ok = true, pending = true, requestId = true, perkId = true })
        and rawget(value, "ok") == true and rawget(value, "pending") == true
        and safeId(rawget(value, "requestId"), 64) and safeId(rawget(value, "perkId"), 128) then
        return { ok = true, pending = true, requestId = rawget(value, "requestId"), perkId = rawget(value, "perkId") }
    end
    if exactTable(value, { ok = true, pending = true, result = true })
        and rawget(value, "ok") == true and rawget(value, "pending") == false then
        local result = detachSummary(rawget(value, "result"))
        if result ~= nil then return { ok = true, pending = false, result = result } end
    end
    return nil
end

local function detachAdminSummary(value)
    local fields = {
        accountingMode = true,
        revision = true,
        level = true,
        xpIntoLevel = true,
        xpForNextLevel = true,
        spent = true,
        availableAp = true,
    }
    if not exactTable(value, fields) then return nil end
    local accountingMode = rawget(value, "accountingMode")
    local revision, level = rawget(value, "revision"), rawget(value, "level")
    local xpIntoLevel, xpForNextLevel = rawget(value, "xpIntoLevel"), rawget(value, "xpForNextLevel")
    local spent, availableAp = rawget(value, "spent"), rawget(value, "availableAp")
    if (accountingMode ~= "Tracked" and accountingMode ~= "Free")
        or not safeInteger(revision) or not safeInteger(level)
        or type(xpIntoLevel) ~= "number" or xpIntoLevel ~= xpIntoLevel
        or xpIntoLevel < 0 or xpIntoLevel == math.huge
        or type(xpForNextLevel) ~= "number" or xpForNextLevel ~= xpForNextLevel
        or xpForNextLevel <= 0 or xpForNextLevel == math.huge or xpIntoLevel >= xpForNextLevel
        or not safeInteger(spent) or spent > level
        or not safeInteger(availableAp) or availableAp ~= level - spent then
        return nil
    end
    return {
        accountingMode = accountingMode,
        revision = revision,
        level = level,
        xpIntoLevel = xpIntoLevel,
        xpForNextLevel = xpForNextLevel,
        spent = spent,
        availableAp = availableAp,
    }
end

local function detachAdminTarget(value)
    if not exactTable(value, { onlineId = true, username = true })
        or not safeInteger(rawget(value, "onlineId")) or not safeUsername(rawget(value, "username")) then
        return nil
    end
    return { onlineId = rawget(value, "onlineId"), username = rawget(value, "username") }
end

local function detachAdminUsernameTarget(value)
    if not exactTable(value, { username = true })
        or not safeUsername(rawget(value, "username")) then
        return nil
    end
    return { username = rawget(value, "username") }
end

local function detachAdminTerminal(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil
        or type(rawget(value, "ok")) ~= "boolean"
        or not safeId(rawget(value, "requestId"), 64) then
        return nil
    end
    local operation = rawget(value, "operation")
    if operation ~= "inspect" and operation ~= "awardSurvivorXp"
        and operation ~= "awardSurvivorLevels" and operation ~= "clearAdvancementSlots" then
        return nil
    end
    local target
    if operation == "inspect" and rawget(value, "ok") == false then
        target = detachAdminUsernameTarget(rawget(value, "target"))
    else
        target = detachAdminTarget(rawget(value, "target"))
    end
    if target == nil then return nil end
    local result = {
        ok = rawget(value, "ok"), requestId = rawget(value, "requestId"),
        operation = operation, target = target,
    }
    if result.ok then
        local outcome = rawget(value, "outcome")
        local fields = { ok = true, requestId = true, operation = true, target = true, outcome = true, summary = true }
        if operation == "inspect" then
            if outcome ~= "inspected" then return nil end
        elseif outcome == "applied" then
            fields.levelsGained, fields.apGained = true, true
        elseif outcome == "rejected" then
            fields.code, fields.detail = true, true
        else
            return nil
        end
        local summary = detachAdminSummary(rawget(value, "summary"))
        if not exactTable(value, fields) or summary == nil then return nil end
        if outcome == "applied" then
            if not safeInteger(rawget(value, "levelsGained"))
                or rawget(value, "apGained") ~= rawget(value, "levelsGained")
                or (operation == "clearAdvancementSlots"
                    and rawget(value, "levelsGained") ~= 0) then return nil end
            result.levelsGained, result.apGained = rawget(value, "levelsGained"), rawget(value, "apGained")
        elseif outcome == "rejected" then
            if rawget(value, "code") ~= "stale_revision" or not safeText(rawget(value, "detail"), 160, false) then return nil end
            result.code, result.detail = rawget(value, "code"), rawget(value, "detail")
        end
        result.outcome, result.summary = outcome, summary
    else
        if not exactTable(value, { ok = true, requestId = true, operation = true, target = true, code = true, detail = true, committed = true })
            or not safeId(rawget(value, "code"), 64) or not safeText(rawget(value, "detail"), 160, false)
            or type(rawget(value, "committed")) ~= "boolean" then return nil end
        if operation == "inspect" and rawget(value, "committed") ~= false then return nil end
        result.code, result.detail, result.committed = rawget(value, "code"), rawget(value, "detail"), rawget(value, "committed")
    end
    return result
end

local function detachAdminStatus(value)
    if exactTable(value, { ok = true, pending = true })
        and rawget(value, "ok") == true and rawget(value, "pending") == false then
        return { ok = true, pending = false }
    end
    if exactTable(value, { ok = true, pending = true, requestId = true, operation = true, target = true })
        and rawget(value, "ok") == true and rawget(value, "pending") == true
        and safeId(rawget(value, "requestId"), 64) then
        local operation = rawget(value, "operation")
        local target
        if operation == "inspect" then
            target = detachAdminUsernameTarget(rawget(value, "target"))
        else
            target = detachAdminTarget(rawget(value, "target"))
        end
        if target ~= nil and (operation == "inspect" or operation == "awardSurvivorXp"
            or operation == "awardSurvivorLevels" or operation == "clearAdvancementSlots") then
            return { ok = true, pending = true, requestId = rawget(value, "requestId"), operation = operation, target = target }
        end
    end
    if exactTable(value, { ok = true, pending = true, result = true })
        and rawget(value, "ok") == true and rawget(value, "pending") == false then
        local terminal = detachAdminTerminal(rawget(value, "result"))
        if terminal ~= nil then return { ok = true, pending = false, result = terminal } end
    end
    return nil
end

local function localAdminRequest(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    local operation = rawget(value, "operation")
    if operation == "inspect" then
        if exactTable(value, { operation = true }) then
            return { operation = operation }
        end
        return nil
    end
    local expectedRevision = rawget(value, "expectedRevision")
    if not safeInteger(expectedRevision) then return nil end
    if operation == "awardSurvivorXp" then
        local amount = rawget(value, "amount")
        if exactTable(value, { operation = true, expectedRevision = true, amount = true })
            and type(amount) == "number" and amount == amount
            and amount ~= math.huge and amount ~= -math.huge and amount > 0 then
            return { kind = operation, expectedRevision = expectedRevision, amount = amount }
        end
        return nil
    end
    if operation == "awardSurvivorLevels" then
        local count = rawget(value, "count")
        if exactTable(value, { operation = true, expectedRevision = true, count = true })
            and safeInteger(count) and count > 0 then
            return { kind = operation, expectedRevision = expectedRevision, count = count }
        end
    end
    if operation == "clearAdvancementSlots"
        and exactTable(value, { operation = true, expectedRevision = true }) then
        return { kind = operation, expectedRevision = expectedRevision }
    end
    return nil
end

local function detachLocalAdminTerminal(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil
        or type(rawget(value, "ok")) ~= "boolean" then return nil end
    local operation = rawget(value, "operation")
    if operation ~= "inspect" and operation ~= "awardSurvivorXp"
        and operation ~= "awardSurvivorLevels"
        and operation ~= "clearAdvancementSlots" then return nil end
    local terminal = { ok = rawget(value, "ok"), operation = operation }
    if terminal.ok then
        local outcome = rawget(value, "outcome")
        local fields = { ok = true, operation = true, outcome = true, summary = true }
        if outcome == "applied" then
            fields.levelsGained, fields.apGained = true, true
        elseif outcome == "rejected" then
            fields.code, fields.detail = true, true
        elseif outcome ~= "inspected" or operation ~= "inspect" then
            return nil
        end
        local summary = detachAdminSummary(rawget(value, "summary"))
        if not exactTable(value, fields) or summary == nil then return nil end
        if outcome == "applied" then
            local levelsGained, apGained = rawget(value, "levelsGained"), rawget(value, "apGained")
            if not safeInteger(levelsGained) or apGained ~= levelsGained
                or (operation == "clearAdvancementSlots" and levelsGained ~= 0) then return nil end
            terminal.levelsGained, terminal.apGained = levelsGained, apGained
        elseif outcome == "rejected" then
            if rawget(value, "code") ~= "stale_revision"
                or not safeText(rawget(value, "detail"), 160, false) then return nil end
            terminal.code, terminal.detail = rawget(value, "code"), rawget(value, "detail")
        end
        terminal.outcome, terminal.summary = outcome, summary
        return terminal
    end
    if not exactTable(value, {
        ok = true, operation = true, code = true, detail = true, committed = true,
    }) or not safeId(rawget(value, "code"), 64)
        or not safeText(rawget(value, "detail"), 160, false)
        or type(rawget(value, "committed")) ~= "boolean" then return nil end
    terminal.code, terminal.detail = rawget(value, "code"), rawget(value, "detail")
    terminal.committed = rawget(value, "committed")
    return terminal
end

local function localAdminSessionTerminal(operation, request, value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    if rawget(value, "ok") == false then
        if exactTable(value, { ok = true, code = true, detail = true, committed = true })
            and safeId(rawget(value, "code"), 64)
            and safeText(rawget(value, "detail"), 160, false)
            and rawget(value, "committed") == false then
            return {
                ok = false, operation = operation, code = rawget(value, "code"),
                detail = rawget(value, "detail"), committed = false,
            }
        end
        return nil
    end
    if operation == "inspect" then
        local summary = detachAdminSummary(rawget(value, "summary"))
        if exactTable(value, { ok = true, summary = true })
            and rawget(value, "ok") == true and summary ~= nil then
            return { ok = true, operation = operation, outcome = "inspected", summary = summary }
        end
        return nil
    end
    local kind = rawget(request, "kind")
    if exactTable(value, {
        ok = true, applied = true, kind = true, code = true, detail = true, summary = true,
    }) and rawget(value, "ok") == true and rawget(value, "applied") == false
        and rawget(value, "kind") == kind and rawget(value, "code") == "stale_revision"
        and safeText(rawget(value, "detail"), 160, false) then
        local summary = detachAdminSummary(rawget(value, "summary"))
        if summary ~= nil and summary.revision ~= rawget(request, "expectedRevision") then
            return {
                ok = true, operation = operation, outcome = "rejected",
                code = "stale_revision", detail = rawget(value, "detail"), summary = summary,
            }
        end
        return nil
    end
    local fields = {
        ok = true, applied = true, kind = true, levelsGained = true,
        apGained = true, summary = true,
    }
    local operand
    if kind == "awardSurvivorXp" then fields.amount, operand = true, "amount"
    elseif kind == "awardSurvivorLevels" then fields.count, operand = true, "count"
    elseif kind ~= "clearAdvancementSlots" then return nil end
    local summary = detachAdminSummary(rawget(value, "summary"))
    local levelsGained, apGained = rawget(value, "levelsGained"), rawget(value, "apGained")
    if not exactTable(value, fields) or rawget(value, "ok") ~= true
        or rawget(value, "applied") ~= true or rawget(value, "kind") ~= kind
        or (operand ~= nil and rawget(value, operand) ~= rawget(request, operand)) or summary == nil
        or rawget(request, "expectedRevision") >= MAX_SAFE_INTEGER
        or summary.revision ~= rawget(request, "expectedRevision") + 1
        or not safeInteger(levelsGained) or apGained ~= levelsGained
        or levelsGained > summary.level
        or (kind == "awardSurvivorLevels" and levelsGained ~= rawget(request, "count"))
        or (kind == "clearAdvancementSlots" and levelsGained ~= 0) then return nil end
    return {
        ok = true, operation = operation, outcome = "applied",
        levelsGained = levelsGained, apGained = apGained, summary = summary,
    }
end

local function ownerHandled(value)
    local acceptedFields = { ok = true, handled = true, accepted = true, localSlot = true }
    if type(value) == "table" and rawget(value, "completion") ~= nil then
        acceptedFields.completion = true
    end
    if exactTable(value, acceptedFields) then
        return rawget(value, "ok") == true and rawget(value, "handled") == true
            and rawget(value, "accepted") == true and validSlot(rawget(value, "localSlot")),
            rawget(value, "localSlot"), true, rawget(value, "completion")
    end
    if exactTable(value, { ok = true, handled = true, accepted = true, code = true, localSlot = true }) then
        return rawget(value, "ok") == true and rawget(value, "handled") == true
            and rawget(value, "accepted") == false and safeId(rawget(value, "code"), 64)
            and validSlot(rawget(value, "localSlot")), rawget(value, "localSlot"), false
    end
    return false
end

local function advancementHandled(value)
    if not exactTable(value, { ok = true, handled = true, localSlot = true, result = true }) then return false end
    return rawget(value, "ok") == true and rawget(value, "handled") == true
        and validSlot(rawget(value, "localSlot"))
        and rawget(value, "ok") == true and rawget(value, "handled") == true
        and detachSummary(rawget(value, "result")) ~= nil, rawget(value, "localSlot")
end

local function adminHandled(value)
    if not exactTable(value, { ok = true, handled = true, localSlot = true, result = true }) then return false end
    if rawget(value, "ok") ~= true or rawget(value, "handled") ~= true or not validSlot(rawget(value, "localSlot")) then return false end
    return detachAdminTerminal(rawget(value, "result")) ~= nil, rawget(value, "localSlot")
end

local function applied(result, requestId, perkId)
    return exactTable(result, {
        ok = true, applied = true, requestId = true, perkId = true,
        apCost = true, mastered = true, snapshot = true,
    }) and rawget(result, "ok") == true and rawget(result, "applied") == true
        and rawget(result, "requestId") == requestId and rawget(result, "perkId") == perkId
        and (rawget(result, "apCost") == 1 or rawget(result, "apCost") == 2)
        and rawget(result, "mastered") == (rawget(result, "apCost") == 2)
        and type(rawget(result, "snapshot")) == "table"
end

local function rejected(result, requestId, perkId)
    if type(result) ~= "table" or getmetatable(result) ~= nil then return false end
    local fields = { ok = true, applied = true, requestId = true, perkId = true, code = true, detail = true }
    local snapshot = rawget(result, "snapshot")
    if snapshot ~= nil then fields.snapshot = true end
    return exactTable(result, fields) and rawget(result, "ok") == true
        and rawget(result, "applied") == false and rawget(result, "requestId") == requestId
        and rawget(result, "perkId") == perkId and safeId(rawget(result, "code"), 64)
        and safeText(rawget(result, "detail"), 160, false)
        and (snapshot == nil or (rawget(result, "code") == "stale_revision" and type(snapshot) == "table"))
end

function Build42Lifecycle.create(dependencies)
    if type(dependencies) ~= "table" or type(rawget(dependencies, "modules")) ~= "table"
        or type(rawget(dependencies, "globals")) ~= "table" then
        return failure("invalid_dependencies", "modules and globals are required")
    end
    local modules, globals = rawget(dependencies, "modules"), rawget(dependencies, "globals")
    local pendingNewPlayers = pendingNewList(rawget(dependencies, "pendingNewPlayers"))
    if pendingNewPlayers == nil then return failure("invalid_dependencies", "pendingNewPlayers") end
    local pendingPlayers = pendingLocalMap(rawget(dependencies, "pendingLocalPlayers"))
    if pendingPlayers == nil then return failure("invalid_dependencies", "pendingLocalPlayers") end
    local authoritativeMode = rawget(dependencies, "mode")
    if authoritativeMode ~= nil and authoritativeMode ~= "server"
        and authoritativeMode ~= "client" and authoritativeMode ~= "single_player" then
        return failure("mode_invalid", "authoritative mode is invalid")
    end
    local runtimeFactory, ownerFactory = rawget(modules, "Build42RuntimeFactory"), rawget(modules, "Build42OwnerTransport")
    local advancementFactory, clientState = rawget(modules, "Build42AdvancementTransport"), rawget(modules, "ClientOwnerState")
    local adminFactory, adminBoundaryFactory = rawget(modules, "Build42AdminTransport"), rawget(modules, "Build42AdminBoundary")
    local completionFactory = rawget(modules, "LevelGainCompletion")
    local feedbackFactory = rawget(modules, "Build42LevelFeedback")
    if type(runtimeFactory) ~= "table" or not callable(rawget(runtimeFactory, "create"))
        or type(ownerFactory) ~= "table" or not callable(rawget(ownerFactory, "createServer"))
        or not callable(rawget(ownerFactory, "createClient"))
        or type(advancementFactory) ~= "table" or not callable(rawget(advancementFactory, "createServer"))
        or not callable(rawget(advancementFactory, "createClient"))
        or type(adminFactory) ~= "table" or not callable(rawget(adminFactory, "createServer"))
        or not callable(rawget(adminFactory, "createClient"))
        or type(adminBoundaryFactory) ~= "table" or not callable(rawget(adminBoundaryFactory, "create"))
        or type(completionFactory) ~= "table"
        or not callable(rawget(completionFactory, "create"))
        or not callable(rawget(completionFactory, "validate"))
        or type(feedbackFactory) ~= "table" or not callable(rawget(feedbackFactory, "create"))
        or type(clientState) ~= "table" or not callable(rawget(clientState, "create"))
        or not callable(rawget(clientState, "validate")) then
        return failure("invalid_dependencies", "lifecycle module capabilities are required")
    end
    local createRuntime = rawget(runtimeFactory, "create")
    local createOwnerServer, createOwnerClient = rawget(ownerFactory, "createServer"), rawget(ownerFactory, "createClient")
    local createAdvServer, createAdvClient = rawget(advancementFactory, "createServer"), rawget(advancementFactory, "createClient")
    local createAdminServer, createAdminClient = rawget(adminFactory, "createServer"), rawget(adminFactory, "createClient")
    local createAdminBoundary = rawget(adminBoundaryFactory, "create")
    local createCompletion, validateCompletion = rawget(completionFactory, "create"), rawget(completionFactory, "validate")
    local createFeedback = rawget(feedbackFactory, "create")
    local validateSnapshot = rawget(clientState, "validate")
    local Capability = rawget(globals, "Capability")
    local getPlayerByOnlineID = rawget(globals, "getPlayerByOnlineID")
    local getPlayerFromUsername = rawget(globals, "getPlayerFromUsername")
    local writeLog = rawget(globals, "writeLog")
    local isServer, isClient = rawget(globals, "isServer"), rawget(globals, "isClient")
    local getSpecificPlayer = rawget(globals, "getSpecificPlayer")
    local mode = authoritativeMode
    if mode == nil then
        if not callable(isServer) or not callable(isClient) then return failure("invalid_dependencies", "mode globals are required") end
        local serverCalled, serverMode = pcall(isServer)
        local clientCalled, clientMode = pcall(isClient)
        if not serverCalled or not clientCalled or type(serverMode) ~= "boolean" or type(clientMode) ~= "boolean" then
            return failure("mode_invalid", "isServer and isClient must return booleans")
        end
        if serverMode and clientMode then return failure("mode_invalid", "server and client cannot both be true") end
        mode = serverMode and "server" or clientMode and "client" or "single_player"
    end
    local isDebugEnabled = rawget(globals, "isDebugEnabled")
    if mode == "single_player" and not callable(isDebugEnabled) then
        return failure("invalid_dependencies", "single-player debug capability is required")
    end
    if mode ~= "single_player" and #pendingNewPlayers > 0 then
        return failure("invalid_dependencies", "pendingNewPlayers require single-player mode")
    end
    if mode ~= "single_player" then
        for slot = 0, 3 do
            if pendingPlayers[slot] ~= nil then
                return failure("invalid_dependencies", "pendingLocalPlayers require single-player mode")
            end
        end
    end
    local levelFeedback = nil
    if mode ~= "server" then
        local feedbackCalled, feedbackCreated = pcall(createFeedback, {
            HaloTextHelper = rawget(globals, "HaloTextHelper"),
            getText = rawget(globals, "getText"),
        })
        local feedbackEndpoint = feedbackCalled
            and service(feedbackCreated, "presenter", { "show" }) or nil
        if feedbackEndpoint == nil then
            return bounded(feedbackCreated, "level_feedback_invalid", "Build42LevelFeedback.create")
        end
        levelFeedback = feedbackEndpoint.value
    end
    local sendCommand = mode == "server" and rawget(globals, "sendServerCommand") or rawget(globals, "sendClientCommand")
    if not callable(sendCommand) then return failure("invalid_dependencies", "mode command sender is required") end
    if mode == "client" and not callable(getSpecificPlayer) then
        return failure("invalid_dependencies", "getSpecificPlayer is required")
    end

    local ownerClient, advancementClient, adminClient
    if mode ~= "server" then
        local called, created = pcall(createOwnerClient, {
            ClientOwnerState = clientState,
            completionValidator = completionFactory,
            sendClientCommand = sendCommand,
        })
        ownerClient = called and service(created, "client", { "ready", "refresh", "handle", "reset", "resetSlot", "acceptLocal", "get", "status" }) or nil
        if ownerClient == nil then return bounded(created, "owner_client_invalid", "Build42OwnerTransport.createClient") end
        if mode == "client" then
            called, created = pcall(createAdvClient, { ownerClient = ownerClient.value, sendClientCommand = sendCommand })
            advancementClient = called and service(created, "client", { "request", "handle", "status", "resetSlot", "reset" }) or nil
            if advancementClient == nil then return bounded(created, "advancement_client_invalid", "Build42AdvancementTransport.createClient") end
            called, created = pcall(createAdminClient, { sendClientCommand = sendCommand })
            adminClient = called and service(created, "client", { "request", "handle", "status", "resetSlot", "reset" }) or nil
            if adminClient == nil then return bounded(created, "admin_client_invalid", "Build42AdminTransport.createClient") end
        end
    end

    local eventNames = mode == "server" and { "OnServerStarted", "OnClientCommand", "OnNewGame", "OnCharacterDeath" }
        or mode == "client" and { "OnMiniScoreboardUpdate", "OnTick", "OnServerCommand", "OnDisconnect" }
        or { "OnGameStart", "OnCreatePlayer", "OnNewGame", "OnCharacterDeath" }
    local events = eventSet(rawget(globals, "Events"), eventNames,
        mode == "client" and { OnTick = true } or nil)
    if events == nil then return failure("invalid_dependencies", "required lifecycle events are required") end

    local installed, installAttempted, startupAttempted, started = false, false, false, false
    local retainedFailure, ownerServerHandle, advancementServerHandle, adminServerHandle
    local ownerPublisher
    local ownerSessionReady, ownerSessionSnapshot, advancementRequest
    local xpSourceVerifyOwnership, xpSourceOwnershipFailure
    local tokenNewCharacter, recordDeath
    local adminSessionInspect, adminSessionRequest
    local readyPlayers, observedPlayers, observedSlots = {}, {}, {}
    local deferredPlayers, deferredSlots = {}, {}
    local tickRegistered, tickAddAttempted = false, false
    local singlePlayerResults, singlePlayerAdminResults = {}, {}
    local owner, readySingle = {}, nil
    local clientStateListener = nil
    local callbacks = {}
    local pendingReferencesClosed = false

    local function clearPendingPlayerReferences()
        for index = 1, #pendingNewPlayers do pendingNewPlayers[index] = nil end
        pendingNewPlayers = {}
        for slot = 0, 3 do pendingPlayers[slot] = nil end
        pendingReferencesClosed = true
    end

    local function bufferNewPlayer(player)
        if player == nil then return failure("invalid_new_player", "OnNewGame") end
        for index = 1, #pendingNewPlayers do
            if pendingNewPlayers[index] == player then return { ok = true } end
        end
        if #pendingNewPlayers >= 4 then return failure("new_player_buffer_full", "OnNewGame") end
        pendingNewPlayers[#pendingNewPlayers + 1] = player
        return { ok = true }
    end

    local function retain(result, code, detail)
        retainedFailure = bounded(result, code, detail)
        return retainedFailure
    end

    local function detachCompletion(value)
        if value == nil then return nil end
        local called, result = pcall(validateCompletion, value)
        if not called or not exactTable(result, { ok = true, completion = true })
            or rawget(result, "ok") ~= true
            or type(rawget(result, "completion")) ~= "table" then return nil end
        return rawget(result, "completion")
    end

    local function notifyClientState(localSlot, kind, completion, exactPlayer)
        if clientStateListener ~= nil then pcall(clientStateListener, localSlot, kind) end
        local checked = detachCompletion(completion)
        if checked == nil or levelFeedback == nil then return end
        local player = exactPlayer
        if player == nil and mode == "client" then
            local called, resolved = pcall(getSpecificPlayer, localSlot)
            if called then player = resolved end
        end
        if player ~= nil then pcall(rawget(levelFeedback, "show"), player, checked) end
    end

    local function levelGainSink(player, completion)
        local checked = detachCompletion(completion)
        if checked == nil or player == nil then return { ok = true, published = false } end
        if mode == "server" then
            if ownerPublisher ~= nil then pcall(rawget(ownerPublisher, "publish"), player, checked) end
            return { ok = true, published = ownerPublisher ~= nil }
        end
        if mode ~= "single_player" or ownerSessionSnapshot == nil then
            return { ok = true, published = false }
        end
        local localSlot = nil
        for slot = 0, 3 do
            if readyPlayers[slot] == player then localSlot = slot; break end
        end
        if localSlot == nil then return { ok = true, published = false } end
        local snapshotCalled, snapshotResult = pcall(ownerSessionSnapshot, player)
        if not snapshotCalled or type(snapshotResult) ~= "table"
            or rawget(snapshotResult, "ok") ~= true
            or type(rawget(snapshotResult, "snapshot")) ~= "table" then
            return { ok = true, published = false }
        end
        local acceptedCalled, accepted = pcall(
            ownerClient.acceptLocal,
            localSlot,
            rawget(snapshotResult, "snapshot")
        )
        if acceptedCalled and acceptance(accepted) == true then
            notifyClientState(localSlot, "owner_snapshot", checked, player)
            return { ok = true, published = true }
        end
        return { ok = true, published = false }
    end

    local function startupFailure(result, code, detail)
        clearPendingPlayerReferences()
        return retain(result, code, detail)
    end

    local function ownEvents()
        local current = rawget(globals, "Events")
        if type(current) ~= "table" then
            if not started then clearPendingPlayerReferences() end
            retain(nil, "event_ownership_lost", "Events")
            return false
        end
        for index = 1, #eventNames do
            local name = eventNames[index]
            if rawget(current, name) ~= events[name] then
                if not started then clearPendingPlayerReferences() end
                retain(nil, "event_ownership_lost", name)
                return false
            end
        end
        return true
    end

    local function verifyXpSourceOwnership()
        if xpSourceOwnershipFailure ~= nil then
            return xpSourceOwnershipFailure
        end
        if xpSourceVerifyOwnership == nil then
            return { ok = true }
        end
        local called, verified = pcall(xpSourceVerifyOwnership)
        if not called or type(verified) ~= "table" or rawget(verified, "ok") ~= true then
            xpSourceOwnershipFailure = retain(
                verified,
                "xp_source_ownership_invalid",
                "xpSource.verifyOwnership"
            )
            return xpSourceOwnershipFailure
        end
        return { ok = true }
    end

    local function trusted(callableValue, code, detail, ...)
        local called, result = pcall(callableValue, ...)
        if not called or type(result) ~= "table" or rawget(result, "ok") ~= true then
            return nil, retain(result, code, detail)
        end
        return result
    end

    local function auditSink()
        if not callable(writeLog) then return nil end
        local audit = {}
        function audit.record(actor, targetRef, operation, outcome, ...)
            local usernameCalled, username = pcall(function()
                if actor == nil then return nil end
                local method = actor.getUsername
                if not callable(method) then return nil end
                return method(actor)
            end)
            local target = detachAdminTarget(targetRef)
            if select("#", ...) ~= 0 or not usernameCalled or not safeUsername(username) or target == nil
                or (operation ~= "awardSurvivorXp" and operation ~= "awardSurvivorLevels"
                    and operation ~= "clearAdvancementSlots")
                or outcome ~= "committed" then
                return failure("audit_invalid", "record")
            end
            local line = "SLA admin actor=" .. username .. " operation=" .. operation
                .. " target=" .. target.username .. " onlineId=" .. tostring(target.onlineId)
            local called = pcall(writeLog, "admin", line)
            if not called then return failure("audit_failed", "writeLog") end
            return { ok = true }
        end
        return audit
    end

    local function startup()
        if startupAttempted then return retainedFailure or { ok = started } end
        startupAttempted = true
        local called, created = pcall(createRuntime, {
            modules = modules,
            globals = globals,
            levelGainSink = levelGainSink,
        })
        if not called or type(created) ~= "table" or rawget(created, "ok") ~= true
            or type(rawget(created, "runtime")) ~= "table"
            or type(rawget(rawget(created, "runtime"), "catalog")) ~= "table"
            or type(rawget(rawget(created, "runtime"), "services")) ~= "table" then
            return startupFailure(created, "runtime_factory_invalid", "Build42RuntimeFactory.create")
        end
        local services = rawget(rawget(created, "runtime"), "services")
        local xpSource, ownerSession = rawget(services, "xpSource"), rawget(services, "ownerSession")
        local inheritanceSession = rawget(services, "inheritanceSession")
        local advancementSession, adminSession = rawget(services, "advancementSession"), rawget(services, "adminSession")
        if type(xpSource) ~= "table" or not callable(rawget(xpSource, "install"))
            or type(ownerSession) ~= "table" or not callable(rawget(ownerSession, "ready"))
            or not callable(rawget(ownerSession, "snapshot")) or not callable(rawget(ownerSession, "isReady"))
            or not callable(rawget(ownerSession, "clearPlayer"))
            or type(inheritanceSession) ~= "table"
            or not callable(rawget(inheritanceSession, "tokenNewCharacter"))
            or not callable(rawget(inheritanceSession, "recordDeath"))
            or type(advancementSession) ~= "table" or not callable(rawget(advancementSession, "request"))
            or type(adminSession) ~= "table" or not callable(rawget(adminSession, "inspect"))
            or not callable(rawget(adminSession, "request")) then
            return startupFailure(nil, "runtime_factory_invalid", "runtime service surface")
        end
        local sourceCalled, sourceResult = pcall(rawget(xpSource, "install"))
        if not sourceCalled or type(sourceResult) ~= "table" or rawget(sourceResult, "ok") ~= true then
            return startupFailure(sourceResult, "xp_source_install_invalid", "xpSource.install")
        end
        local sourceVerifier = rawget(xpSource, "verifyOwnership")
        if callable(sourceVerifier) then xpSourceVerifyOwnership = sourceVerifier end
        if mode == "server" then
            local ownerCalled, ownerCreated = pcall(createOwnerServer, {
                ownerSession = ownerSession, snapshotValidator = { validate = validateSnapshot },
                completionValidator = completionFactory, sendServerCommand = sendCommand,
            })
            local ownerEndpoint = ownerCalled and service(ownerCreated, "server", { "handle", "clearPlayer", "publish" }) or nil
            if ownerEndpoint == nil then return startupFailure(ownerCreated, "owner_server_invalid", "Build42OwnerTransport.createServer") end
            local advCalled, advCreated = pcall(createAdvServer, {
                advancementSession = advancementSession, snapshotValidator = validateSnapshot, sendServerCommand = sendCommand,
            })
            local advEndpoint = advCalled and service(advCreated, "server", { "handle" }) or nil
            if advEndpoint == nil then return startupFailure(advCreated, "advancement_server_invalid", "Build42AdvancementTransport.createServer") end
            local boundaryCalled, boundaryCreated = pcall(createAdminBoundary, {
                Capability = Capability,
                getPlayerByOnlineID = getPlayerByOnlineID,
                getPlayerFromUsername = getPlayerFromUsername,
            })
            local boundaryEndpoint = boundaryCalled and service(boundaryCreated, "boundary", { "authorizeAndResolve" }) or nil
            if boundaryEndpoint == nil then return startupFailure(boundaryCreated, "admin_boundary_invalid", "Build42AdminBoundary.create") end
            local audit = auditSink()
            if audit == nil then return startupFailure(nil, "admin_audit_invalid", "writeLog") end
            local adminCalled, adminCreated = pcall(createAdminServer, {
                adminBoundary = boundaryEndpoint.value,
                adminSession = adminSession,
                ownerPublisher = ownerEndpoint.value,
                completionFactory = completionFactory,
                audit = audit,
                sendServerCommand = sendCommand,
            })
            local adminEndpoint = adminCalled and service(adminCreated, "server", { "handle" }) or nil
            if adminEndpoint == nil then return startupFailure(adminCreated, "admin_server_invalid", "Build42AdminTransport.createServer") end
            ownerPublisher = ownerEndpoint.value
            ownerServerHandle, advancementServerHandle, adminServerHandle = ownerEndpoint.handle, advEndpoint.handle, adminEndpoint.handle
        end
        ownerSessionReady = rawget(ownerSession, "ready")
        ownerSessionSnapshot = rawget(ownerSession, "snapshot")
        tokenNewCharacter = rawget(inheritanceSession, "tokenNewCharacter")
        recordDeath = rawget(inheritanceSession, "recordDeath")
        advancementRequest = rawget(advancementSession, "request")
        adminSessionInspect = rawget(adminSession, "inspect")
        adminSessionRequest = rawget(adminSession, "request")
        local newPlayers = pendingNewPlayers
        local newPlayerCount = #newPlayers
        pendingNewPlayers = {}
        for index = 1, newPlayerCount do
            local tokened = trusted(tokenNewCharacter, "new_character_token_invalid", "inheritanceSession.tokenNewCharacter", newPlayers[index])
            newPlayers[index] = nil
            if tokened == nil then
                for remaining = index + 1, newPlayerCount do newPlayers[remaining] = nil end
                return startupFailure(retainedFailure, retainedFailure.code, retainedFailure.detail)
            end
        end
        started, retainedFailure = true, nil
        if mode == "single_player" then
            for slot = 0, 3 do
                local player = pendingPlayers[slot]
                pendingPlayers[slot] = nil
                if player ~= nil then readySingle(slot, player) end
            end
        end
        return { ok = true }
    end

    readySingle = function(localSlot, player)
        readyPlayers[localSlot], singlePlayerResults[localSlot], singlePlayerAdminResults[localSlot] = nil, nil, nil
        if trusted(ownerClient.resetSlot, "owner_slot_reset_invalid", "ownerClient.resetSlot", localSlot) == nil then return retainedFailure end
        local ready = trusted(ownerSessionReady, "session_ready_invalid", "ownerSession.ready", player)
        if ready == nil or type(rawget(ready, "snapshot")) ~= "table" then
            return ready == nil and retainedFailure or retain(ready, "session_ready_invalid", "ownerSession.ready")
        end
        local accepted = trusted(ownerClient.acceptLocal, "owner_accept_invalid", "ownerClient.acceptLocal", localSlot, rawget(ready, "snapshot"))
        if accepted == nil or acceptance(accepted) ~= true then
            return accepted == nil and retainedFailure or retain(accepted, "owner_accept_invalid", "ownerClient.acceptLocal")
        end
        readyPlayers[localSlot] = player
        notifyClientState(localSlot, "owner_snapshot", rawget(ready, "completion"), player)
        return { ok = true }
    end

    local function readyMultiplayer(localSlot, player)
        readyPlayers[localSlot] = nil
        local firstFailure = nil
        if trusted(advancementClient.resetSlot, "advancement_slot_reset_invalid", "advancementClient.resetSlot", localSlot) == nil then
            firstFailure = retainedFailure
        end
        if trusted(adminClient.resetSlot, "admin_slot_reset_invalid", "adminClient.resetSlot", localSlot) == nil and firstFailure == nil then
            firstFailure = retainedFailure
        end
        if firstFailure ~= nil then
            retainedFailure = firstFailure
            return firstFailure
        end
        if trusted(ownerClient.ready, "owner_ready_invalid", "ownerClient.ready", localSlot, player) == nil then return retainedFailure end
        readyPlayers[localSlot] = player
        return { ok = true }
    end

    local function clearMultiplayerSlot(localSlot)
        readyPlayers[localSlot] = nil
        local firstFailure = nil
        if trusted(ownerClient.resetSlot, "owner_slot_reset_invalid", "ownerClient.resetSlot", localSlot) == nil then
            firstFailure = retainedFailure
        end
        if trusted(advancementClient.resetSlot, "advancement_slot_reset_invalid", "advancementClient.resetSlot", localSlot) == nil and firstFailure == nil then
            firstFailure = retainedFailure
        end
        if trusted(adminClient.resetSlot, "admin_slot_reset_invalid", "adminClient.resetSlot", localSlot) == nil and firstFailure == nil then
            firstFailure = retainedFailure
        end
        if firstFailure ~= nil then retainedFailure = firstFailure; return firstFailure end
        return { ok = true }
    end

    local function scheduleDeferredSlot(localSlot, player)
        deferredSlots[localSlot], deferredPlayers[localSlot] = true, player
        if tickRegistered or tickAddAttempted then return end
        tickAddAttempted = true
        local called = pcall(events.OnTick.Add, callbacks.OnTick)
        if not called then
            for slot = 0, 3 do deferredSlots[slot], deferredPlayers[slot] = nil, nil end
            retain(nil, "event_register_threw", "OnTick")
            return
        end
        tickRegistered = true
    end

    local function inspectLocalPlayers()
        local firstFailure = nil
        for slot = 0, 3 do
            local called, player = pcall(getSpecificPlayer, slot)
            if not called then
                firstFailure = firstFailure or failure("player_resolver_threw", "getSpecificPlayer")
            elseif not observedSlots[slot] or observedPlayers[slot] ~= player then
                local wasObserved = observedSlots[slot] == true
                observedSlots[slot], observedPlayers[slot] = true, player
                if player ~= nil or wasObserved then scheduleDeferredSlot(slot, player) end
            end
        end
        if firstFailure ~= nil then retainedFailure = firstFailure end
    end

    local function serverDispatch(endpoint, code, detail, allowCommittedFalse, module, command, player, args)
        local called, result = pcall(endpoint, module, command, player, args)
        if called and exactTable(result, { ok = true, handled = true })
            and rawget(result, "ok") == true and rawget(result, "handled") == true then
            return
        end
        if called and type(result) == "table" and rawget(result, "ok") == false then
            local resultCode = rawget(result, "code")
            local fields = { ok = true, code = true, detail = true }
            if allowCommittedFalse and rawget(result, "committed") ~= nil then fields.committed = true end
            local contained = (resultCode == "invalid_request" or resultCode == "protocol_mismatch")
                and exactTable(result, fields)
                and safeText(rawget(result, "detail"), 160, false)
                and (not allowCommittedFalse or rawget(result, "committed") == nil or rawget(result, "committed") == false)
            if contained then return end
        end
        retain(result, code, detail)
    end

    local function clientView(localSlot)
        if mode == "server" then return failure("client_state_unavailable", "server mode") end
        local called, result = pcall(ownerClient.get, localSlot)
        if not called then return failure("client_state_threw", "ownerClient.get") end
        if exactTable(result, { ok = true, present = true }) and rawget(result, "ok") == true
            and rawget(result, "present") == false then return { ok = true, present = false } end
        if exactTable(result, { ok = true, present = true, snapshot = true })
            and rawget(result, "ok") == true and rawget(result, "present") == true
            and type(rawget(result, "snapshot")) == "table" then
            local calledValidate, validated = pcall(validateSnapshot, rawget(result, "snapshot"))
            if calledValidate and exactTable(validated, { ok = true, snapshot = true })
                and rawget(validated, "ok") == true and type(rawget(validated, "snapshot")) == "table" then
                return { ok = true, present = true, snapshot = rawget(validated, "snapshot") }
            end
            return failure("client_state_invalid", "client snapshot")
        end
        return bounded(result, "client_state_invalid", "ownerClient.get")
    end

    local function acceptResult(localSlot, result, wasApplied)
        local called, accepted = pcall(ownerClient.acceptLocal, localSlot, rawget(result, "snapshot"))
        local didAccept, acceptCode
        if called then didAccept, acceptCode = acceptance(accepted) end
        if didAccept == nil then
            retain(accepted, "sp_snapshot_accept_invalid", "ownerClient.acceptLocal")
            local summary = {
                ok = false, applied = wasApplied, requestId = rawget(result, "requestId"),
                perkId = rawget(result, "perkId"), code = "snapshot_rejected",
                detail = "ownerClient.acceptLocal", committed = wasApplied,
            }
            if wasApplied then summary.apCost, summary.mastered = rawget(result, "apCost"), rawget(result, "mastered")
            else summary.upstreamCode, summary.upstreamDetail = rawget(result, "code"), rawget(result, "detail") end
            return summary
        end
        local summary = {
            ok = true, applied = wasApplied, requestId = rawget(result, "requestId"),
            perkId = rawget(result, "perkId"), snapshotAccepted = didAccept,
        }
        if wasApplied then summary.apCost, summary.mastered = rawget(result, "apCost"), rawget(result, "mastered")
        else summary.code, summary.detail = rawget(result, "code"), rawget(result, "detail") end
        if acceptCode ~= nil then summary.snapshotCode = acceptCode end
        return summary
    end

    local function requestSingle(localSlot, perkId)
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        if not safeId(perkId, 128) then return failure("invalid_perk", "perkId") end
        local player = readyPlayers[localSlot]
        if not started or player == nil then return failure("player_not_ready", "localSlot") end
        local view, snapshot = clientView(localSlot), nil
        snapshot = rawget(view, "snapshot")
        if rawget(view, "ok") ~= true or rawget(view, "present") ~= true or type(snapshot) ~= "table"
            or rawget(snapshot, "ready") ~= true or not safeInteger(rawget(snapshot, "revision")) then
            return failure("owner_state_not_ready", "localSlot")
        end
        if nextLocalRequest >= MAX_SAFE_INTEGER then return failure("request_id_exhausted", "counter") end
        nextLocalRequest = nextLocalRequest + 1
        local requestId = "advancement-local:" .. tostring(nextLocalRequest)
        local request = { requestId = requestId, perkId = perkId, expectedRevision = rawget(snapshot, "revision") }
        local called, result = pcall(advancementRequest, player, request)
        local summary
        if called and applied(result, requestId, perkId) then
            summary = acceptResult(localSlot, result, true)
        elseif called and rejected(result, requestId, perkId) then
            summary = rawget(result, "snapshot") ~= nil and acceptResult(localSlot, result, false) or {
                ok = true, applied = false, requestId = requestId, perkId = perkId,
                code = rawget(result, "code"), detail = rawget(result, "detail"),
            }
        elseif called and exactTable(result, { ok = true, code = true, detail = true, committed = true })
            and rawget(result, "ok") == false and safeId(rawget(result, "code"), 64)
            and safeText(rawget(result, "detail"), 160, false) and type(rawget(result, "committed")) == "boolean" then
            summary = failure(rawget(result, "code"), rawget(result, "detail"), rawget(result, "committed"))
            summary.requestId, summary.perkId = requestId, perkId
        else
            local committed = true
            retain(result, "sp_advancement_invalid", "advancementSession.request")
            summary = failure(called and "session_request_invalid" or "session_request_threw", "advancementSession.request", committed)
            summary.requestId, summary.perkId = requestId, perkId
        end
        singlePlayerResults[localSlot] = summary
        notifyClientState(localSlot, "advancement_terminal")
        return detachSummary(summary)
    end

    local function debugAvailable()
        local called, enabled = pcall(isDebugEnabled)
        if not called or type(enabled) ~= "boolean" then
            return nil, retain(nil, "debug_capability_invalid", "isDebugEnabled")
        end
        return enabled
    end

    local function storeLocalAdminTerminal(localSlot, terminal)
        local stored = detachLocalAdminTerminal(terminal)
        if stored == nil then return nil end
        singlePlayerAdminResults[localSlot] = stored
        notifyClientState(localSlot, "admin_terminal")
        return detachLocalAdminTerminal(stored)
    end

    local function postAdminMutation(localSlot, player, operation, sessionResult)
        local called, snapshotResult = pcall(ownerSessionSnapshot, player)
        if not called or not exactTable(snapshotResult, { ok = true, snapshot = true })
            or rawget(snapshotResult, "ok") ~= true
            or type(rawget(snapshotResult, "snapshot")) ~= "table" then
            retain(snapshotResult, "sp_admin_snapshot_invalid", "ownerSession.snapshot")
            return failure("owner_snapshot_failed", "ownerSession.snapshot", true)
        end
        local acceptedCalled, accepted = pcall(
            ownerClient.acceptLocal,
            localSlot,
            rawget(snapshotResult, "snapshot")
        )
        local didAccept = acceptedCalled and acceptance(accepted) or nil
        if didAccept ~= true then
            retain(accepted, "sp_admin_snapshot_accept_invalid", "ownerClient.acceptLocal")
            return failure("owner_snapshot_failed", "ownerClient.acceptLocal", true)
        end
        local completion = nil
        if type(sessionResult) == "table" and rawget(sessionResult, "levelsGained") ~= nil
            and rawget(sessionResult, "levelsGained") > 0 then
            local completionCalled, completionResult = pcall(
                createCompletion,
                rawget(sessionResult, "levelsGained"),
                rawget(sessionResult, "apGained")
            )
            if completionCalled and type(completionResult) == "table"
                and rawget(completionResult, "ok") == true then
                completion = rawget(completionResult, "completion")
            end
        end
        notifyClientState(localSlot, "owner_snapshot", completion, player)
        return { ok = true, operation = operation }
    end

    local function requestSingleAdmin(localSlot, request)
        local debug = debugAvailable()
        if debug == nil then return retainedFailure end
        if not debug then return failure("admin_unavailable", "debug mode") end
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        local player = readyPlayers[localSlot]
        if not started or player == nil then return failure("player_not_ready", "localSlot") end
        local converted = localAdminRequest(request)
        if converted == nil then return failure("invalid_request", "request") end
        local operation = rawget(request, "operation")
        local callableValue = operation == "inspect" and adminSessionInspect or adminSessionRequest
        local called, sessionResult
        if operation == "inspect" then called, sessionResult = pcall(callableValue, player)
        else called, sessionResult = pcall(callableValue, player, converted) end
        local terminal = called and localAdminSessionTerminal(operation, converted, sessionResult) or nil
        if terminal == nil then
            local committed = operation ~= "inspect"
            retain(sessionResult, "sp_admin_session_invalid", operation == "inspect" and "adminSession.inspect" or "adminSession.request")
            terminal = failure(
                called and "session_result_invalid" or "session_call_threw",
                operation == "inspect" and "adminSession.inspect" or "adminSession.request",
                committed
            )
            terminal.operation = operation
        elseif terminal.ok and terminal.outcome == "applied" then
            local refreshed = postAdminMutation(localSlot, player, operation, sessionResult)
            if not refreshed.ok then
                refreshed.operation = operation
                terminal = refreshed
            end
        end
        return storeLocalAdminTerminal(localSlot, terminal)
    end

    callbacks.OnServerStarted = function() if installed and ownEvents() then startup() end end
    callbacks.OnGameStart = function() if installed and ownEvents() then startup() end end
    callbacks.OnClientCommand = function(module, command, player, args)
        if not installed or not ownEvents() or not started or module ~= MODULE then return end
        if command == "ownerReady" or command == "ownerRefresh" then
            serverDispatch(ownerServerHandle, "owner_server_handle_invalid", "ownerServer.handle", false, module, command, player, args)
        elseif command == "advancementRequest" then
            serverDispatch(advancementServerHandle, "advancement_server_handle_invalid", "advancementServer.handle", false, module, command, player, args)
        elseif command == "adminRequest" then
            serverDispatch(adminServerHandle, "admin_server_handle_invalid", "adminServer.handle", true, module, command, player, args)
        end
    end
    callbacks.OnCreatePlayer = function(localSlot, player)
        if not installed or not ownEvents() or not validSlot(localSlot) or player == nil then return end
        if started then readySingle(localSlot, player)
        elseif not startupAttempted and not pendingReferencesClosed then pendingPlayers[localSlot] = player end
    end
    callbacks.OnNewGame = function(player)
        if not installed or not ownEvents() then return end
        if started then
            trusted(tokenNewCharacter, "new_character_token_invalid", "inheritanceSession.tokenNewCharacter", player)
        elseif not startupAttempted and not pendingReferencesClosed then
            local buffered = bufferNewPlayer(player)
            if not buffered.ok then retain(buffered, buffered.code, buffered.detail) end
        end
    end
    callbacks.OnCharacterDeath = function(player)
        if not installed or not ownEvents() or not started then return end
        trusted(recordDeath, "inheritance_death_invalid", "inheritanceSession.recordDeath", player)
    end
    callbacks.OnTick = function()
        if not tickRegistered then return end
        tickRegistered = false
        local called = pcall(events.OnTick.Remove, callbacks.OnTick)
        if not called then
            for slot = 0, 3 do deferredSlots[slot], deferredPlayers[slot] = nil, nil end
            retain(nil, "event_remove_threw", "OnTick")
            return
        end
        tickAddAttempted = false
        local batchSlots, batchPlayers = deferredSlots, deferredPlayers
        deferredSlots, deferredPlayers = {}, {}
        if not installed or not ownEvents() then return end
        local firstFailure = nil
        for slot = 0, 3 do
            if batchSlots[slot] then
                local player = batchPlayers[slot]
                local changed = player ~= nil and readyMultiplayer(slot, player)
                    or clearMultiplayerSlot(slot)
                if type(changed) ~= "table" or rawget(changed, "ok") ~= true then
                    firstFailure = firstFailure or bounded(changed, "player_adoption_failed", "getSpecificPlayer")
                end
            end
        end
        if firstFailure ~= nil then retainedFailure = firstFailure end
    end
    callbacks.OnMiniScoreboardUpdate = function()
        if not installed or not ownEvents() then return end
        inspectLocalPlayers()
    end
    callbacks.OnServerCommand = function(module, command, args)
        if not installed or not ownEvents() or module ~= MODULE then return end
        if command == "ownerSnapshot" then
            local called, result = pcall(ownerClient.handle, module, command, args)
            local handled, localSlot, accepted, completion = false, nil, nil, nil
            if called then handled, localSlot, accepted, completion = ownerHandled(result) end
            if not handled then
                retain(result, "owner_client_handle_invalid", "ownerClient.handle")
            elseif accepted then
                notifyClientState(localSlot, "owner_snapshot", completion)
            end
        elseif command == "advancementResult" then
            local called, result = pcall(advancementClient.handle, module, command, args)
            local handled, localSlot = false, nil
            if called then handled, localSlot = advancementHandled(result) end
            if not handled then
                retain(result, "advancement_client_handle_invalid", "advancementClient.handle")
            else
                notifyClientState(localSlot, "advancement_terminal")
            end
        elseif command == "adminResult" then
            local called, result = pcall(adminClient.handle, module, command, args)
            local handled, localSlot = false, nil
            if called then handled, localSlot = adminHandled(result) end
            if not handled then
                retain(result, "admin_client_handle_invalid", "adminClient.handle")
            else
                notifyClientState(localSlot, "admin_terminal")
            end
        end
    end
    callbacks.OnDisconnect = function()
        if not installed then return end
        local ownsEvents = ownEvents()
        local firstFailure = not ownsEvents and retainedFailure or nil
        if tickRegistered then
            tickRegistered = false
            local removed = pcall(events.OnTick.Remove, callbacks.OnTick)
            if removed then tickAddAttempted = false
            else firstFailure = firstFailure or failure("event_remove_threw", "OnTick") end
        end
        for slot = 0, 3 do deferredSlots[slot], deferredPlayers[slot] = nil, nil end
        for slot = 0, 3 do
            readyPlayers[slot], observedPlayers[slot], observedSlots[slot] = nil, nil, nil
        end
        local called, result = pcall(ownerClient.reset)
        if not called or type(result) ~= "table" or rawget(result, "ok") ~= true then
            firstFailure = firstFailure or bounded(result, "owner_reset_invalid", "ownerClient.reset")
        end
        called, result = pcall(advancementClient.reset)
        if not called or type(result) ~= "table" or rawget(result, "ok") ~= true then
            firstFailure = firstFailure or bounded(result, "advancement_reset_invalid", "advancementClient.reset")
        end
        called, result = pcall(adminClient.reset)
        if not called or type(result) ~= "table" or rawget(result, "ok") ~= true then
            firstFailure = firstFailure or bounded(result, "admin_reset_invalid", "adminClient.reset")
        end
        if firstFailure ~= nil then retain(firstFailure, firstFailure.code, firstFailure.detail) end
    end

    function owner.install()
        if installAttempted then
            if not ownEvents() then return retainedFailure end
            if installed and xpSourceVerifyOwnership ~= nil then
                local verified = verifyXpSourceOwnership()
                if not verified.ok then return verified end
            end
            return installed and { ok = true } or retainedFailure or failure("install_failed", "event registration")
        end
        installAttempted = true
        for index = 1, #eventNames do
            local name = eventNames[index]
            if name ~= "OnTick" and not pcall(rawget(events[name], "Add"), callbacks[name]) then
                clearPendingPlayerReferences()
                return retain(nil, "event_register_threw", name)
            end
        end
        installed = true
        return { ok = true }
    end

    function owner.status()
        local result = { ok = true, mode = mode, installed = installed, started = started, ready = started }
        if retainedFailure ~= nil then result.failure = { code = retainedFailure.code, detail = retainedFailure.detail } end
        return result
    end

    function owner.clientState(localSlot) return clientView(localSlot) end

    function owner.setClientStateListener(listener)
        if listener ~= nil and not callable(listener) then return failure("invalid_listener", "listener") end
        clientStateListener = listener
        return { ok = true }
    end

    function owner.refreshOwner(localSlot)
        if mode == "server" then return failure("owner_refresh_unavailable", "server mode") end
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        local player = readyPlayers[localSlot]
        if player == nil then return failure("player_not_ready", "localSlot") end

        if mode == "client" then
            local called, result = pcall(ownerClient.refresh, localSlot, player)
            if called and exactTable(result, { ok = true }) and rawget(result, "ok") == true then return { ok = true } end
            if called and exactTable(result, { ok = true, code = true, detail = true })
                and rawget(result, "ok") == false and safeId(rawget(result, "code"), 64)
                and safeText(rawget(result, "detail"), 160, false) then
                return failure(rawget(result, "code"), rawget(result, "detail"))
            end
            return retain(result, "owner_refresh_invalid", "ownerClient.refresh")
        end

        local snapshotResult = trusted(ownerSessionSnapshot, "session_snapshot_invalid", "ownerSession.snapshot", player)
        if snapshotResult == nil or type(rawget(snapshotResult, "snapshot")) ~= "table" then
            return snapshotResult == nil and retainedFailure or retain(snapshotResult, "session_snapshot_invalid", "ownerSession.snapshot")
        end
        local accepted = trusted(ownerClient.acceptLocal, "owner_accept_invalid", "ownerClient.acceptLocal", localSlot, rawget(snapshotResult, "snapshot"))
        if accepted == nil then return retainedFailure end
        if acceptance(accepted) == nil then return retain(accepted, "owner_accept_invalid", "ownerClient.acceptLocal") end
        if acceptance(accepted) then notifyClientState(localSlot, "owner_snapshot") end
        return { ok = true }
    end

    function owner.requestAdvancement(localSlot, perkId)
        if mode == "server" then return failure("advancement_unavailable", "server mode") end
        if mode == "single_player" then return requestSingle(localSlot, perkId) end
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        local player = readyPlayers[localSlot]
        if player == nil then return failure("player_not_ready", "localSlot") end
        local called, result = pcall(advancementClient.request, localSlot, player, perkId)
        if not called or type(result) ~= "table" or type(rawget(result, "ok")) ~= "boolean" then
            return retain(result, "advancement_request_invalid", "advancementClient.request")
        end
        if exactTable(result, { ok = true, requestId = true }) and rawget(result, "ok") == true
            and safeId(rawget(result, "requestId"), 64) then return { ok = true, requestId = rawget(result, "requestId") } end
        local failureFields = { ok = true, code = true, detail = true }
        if rawget(result, "committed") ~= nil then failureFields.committed = true end
        if exactTable(result, failureFields) and rawget(result, "ok") == false
            and safeId(rawget(result, "code"), 64)
            and safeText(rawget(result, "detail"), 160, false)
            and (rawget(result, "committed") == nil or type(rawget(result, "committed")) == "boolean") then
            return failure(rawget(result, "code"), rawget(result, "detail"), rawget(result, "committed"))
        end
        return retain(result, "advancement_request_invalid", "advancementClient.request")
    end

    function owner.advancementStatus(localSlot)
        if mode == "server" then return failure("advancement_unavailable", "server mode") end
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        if mode == "single_player" then
            local result = detachSummary(singlePlayerResults[localSlot])
            return result == nil and { ok = true, pending = false } or { ok = true, pending = false, result = result }
        end
        local called, result = pcall(advancementClient.status, localSlot)
        local detached = called and detachStatus(result) or nil
        if detached == nil then return retain(result, "advancement_status_invalid", "advancementClient.status") end
        return detached
    end

    function owner.requestAdmin(localSlot, request)
        if mode == "server" then return failure("admin_unavailable", "server mode") end
        if mode == "single_player" then return requestSingleAdmin(localSlot, request) end
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        local player = readyPlayers[localSlot]
        if player == nil then return failure("player_not_ready", "localSlot") end
        local called, result = pcall(adminClient.request, localSlot, player, request)
        if not called or type(result) ~= "table" or type(rawget(result, "ok")) ~= "boolean" then
            return retain(result, "admin_request_invalid", "adminClient.request")
        end
        if exactTable(result, { ok = true, requestId = true }) and rawget(result, "ok") == true
            and safeId(rawget(result, "requestId"), 64) then
            return { ok = true, requestId = rawget(result, "requestId") }
        end
        if rawget(result, "committed") == true then
            retain(nil, "admin_request_invalid", "adminClient.request")
            return failure("admin_request_invalid", "adminClient.request")
        end
        local fields = { ok = true, code = true, detail = true }
        if rawget(result, "committed") ~= nil then fields.committed = true end
        if exactTable(result, fields) and rawget(result, "ok") == false
            and safeId(rawget(result, "code"), 64) and safeText(rawget(result, "detail"), 160, false)
            and (rawget(result, "committed") == nil or rawget(result, "committed") == false) then
            return failure(rawget(result, "code"), rawget(result, "detail"), rawget(result, "committed"))
        end
        return retain(result, "admin_request_invalid", "adminClient.request")
    end

    function owner.adminStatus(localSlot)
        if mode == "server" then return failure("admin_unavailable", "server mode") end
        if mode == "single_player" then
            local debug = debugAvailable()
            if debug == nil then return retainedFailure end
            if not debug then return failure("admin_unavailable", "debug mode") end
            if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
            local result = detachLocalAdminTerminal(singlePlayerAdminResults[localSlot])
            if result == nil then return { ok = true, pending = false } end
            return { ok = true, pending = false, result = result }
        end
        if not validSlot(localSlot) then return failure("invalid_slot", "localSlot") end
        local called, result = pcall(adminClient.status, localSlot)
        local detached = called and detachAdminStatus(result) or nil
        if detached == nil then return retain(result, "admin_status_invalid", "adminClient.status") end
        return detached
    end

    return { ok = true, owner = owner }
end

return Build42Lifecycle
