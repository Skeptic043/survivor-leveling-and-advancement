local Build42WatchUi = {}

local REFRESH_MINUTES = 10

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function callable(value)
    return type(value) == "function"
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeCall(fn, ...)
    local called, result = pcall(fn, ...)
    if not called then return nil end
    return result
end

local function validPanel(value)
    return type(value) == "table"
        and callable(rawget(value, "setGeometry"))
        and callable(rawget(value, "drawPercentage"))
end

function Build42WatchUi.create(dependencies)
    if type(dependencies) ~= "table" then return failure("invalid_dependencies", "dependencies") end
    local required = {
        "optionEnabled", "isWorldMapVisible", "getClock", "minuteStamp", "getPlayer", "isDead", "createPanel",
    }
    for index = 1, #required do
        if not callable(rawget(dependencies, required[index])) then
            return failure("invalid_dependencies", required[index])
        end
    end
    local owner = rawget(dependencies, "owner")
    if type(owner) ~= "table" or not callable(rawget(owner, "refreshOwner"))
        or not callable(rawget(owner, "clientState")) then
        return failure("invalid_dependencies", "owner")
    end

    local panel = nil
    local installed = false
    local display = false
    local ownerSlot = nil
    local percentValue = nil
    local nextMinute = nil

    local function resolveOwner()
        local playerCalled, player = pcall(dependencies.getPlayer, 0)
        if not playerCalled then return nil end
        if player == nil then return false end
        local deadCalled, dead = pcall(dependencies.isDead, player)
        if not deadCalled or type(dead) ~= "boolean" then return nil end
        if dead then return false end
        return { slot = 0 }
    end

    local function hide()
        display = false
        percentValue = nil
        if panel ~= nil then safeCall(panel.setGeometry, 0, 0, 0, 0) end
    end

    local function clockGeometry(clock)
        local x = safeCall(function() return clock:getX() end)
        local y = safeCall(function() return clock:getY() end)
        local width = safeCall(function() return clock:getWidth() end)
        local height = safeCall(function() return clock:getHeight() end)
        if not finite(x) or not finite(y) or not finite(width) or not finite(height)
            or width < 3 or height < 3 then return nil end
        return x, y, width, height
    end

    local function readRatio(slot)
        local state = safeCall(owner.clientState, slot)
        if type(state) ~= "table" or rawget(state, "ok") ~= true
            or rawget(state, "present") ~= true then return nil end
        local snapshot = rawget(state, "snapshot")
        if type(snapshot) ~= "table" or rawget(snapshot, "ready") ~= true then return nil end
        local survivor = rawget(snapshot, "survivor")
        if type(survivor) ~= "table" then return nil end
        local xp, cost = rawget(survivor, "xpIntoLevel"), rawget(survivor, "xpForNextLevel")
        if not finite(xp) or not finite(cost) or cost <= 0 then return nil end
        local value = xp / cost
        if value < 0 then value = 0 elseif value > 1 then value = 1 end
        return value
    end

    local function due(stamp)
        return nextMinute == nil or stamp < nextMinute - REFRESH_MINUTES or stamp >= nextMinute
    end

    local function prerender()
        if safeCall(dependencies.optionEnabled) ~= true then
            ownerSlot, nextMinute = nil, nil
            hide()
            return
        end
        local mapVisible = safeCall(dependencies.isWorldMapVisible)
        if type(mapVisible) ~= "boolean" or mapVisible then
            hide()
            return
        end
        local clock = safeCall(dependencies.getClock)
        local dateVisible = clock ~= nil and safeCall(function() return clock:isDateVisible() end) == true
        if not dateVisible then
            ownerSlot, nextMinute = nil, nil
            hide()
            return
        end
        local stamp = safeCall(dependencies.minuteStamp)
        if not finite(stamp) then
            ownerSlot, nextMinute = nil, nil
            hide()
            return
        end
        if due(stamp) then
            nextMinute = stamp + REFRESH_MINUTES
            local resolved = resolveOwner()
            if resolved == nil or resolved == false then
                ownerSlot = nil
                hide()
                return
            end
            ownerSlot = resolved.slot
            safeCall(owner.refreshOwner, ownerSlot)
        end
        if ownerSlot == nil then hide(); return end
        local currentRatio = readRatio(ownerSlot)
        if currentRatio == nil then hide(); return end
        local x, y, width, height = clockGeometry(clock)
        if x == nil then hide(); return end
        local geometryCalled = pcall(panel.setGeometry, x, y, width, height)
        if not geometryCalled then hide(); return end
        percentValue = math.floor(currentRatio * 100)
        display = true
    end

    local function panelFailure()
        display, percentValue = false, nil
        if panel ~= nil then pcall(panel.setGeometry, 0, 0, 0, 0) end
    end

    local function render()
        if not display or panel == nil or percentValue == nil then return end
        local mapVisible = safeCall(dependencies.isWorldMapVisible)
        if type(mapVisible) ~= "boolean" or mapVisible then hide(); return end
        local widthCalled, width = pcall(panel.width)
        local heightCalled, height = pcall(panel.height)
        if not widthCalled or not heightCalled
            or not finite(width) or not finite(height)
            or width < 3 or height < 3 then panelFailure(); return end
        if not pcall(panel.drawPercentage, percentValue) then panelFailure(); return end
    end

    local callbacks = { prerender = prerender, render = render }
    local integration = {}

    function integration.install()
        if installed then return { ok = true } end
        local created = safeCall(dependencies.createPanel, callbacks)
        if not validPanel(created) or not callable(rawget(created, "width"))
            or not callable(rawget(created, "height")) then
            return failure("watch_panel_failed", "createPanel")
        end
        panel = created
        if not pcall(panel.setGeometry, 0, 0, 0, 0) then
            panel = nil
            return failure("watch_panel_failed", "initial geometry")
        end
        installed = true
        return { ok = true }
    end

    function integration.status()
        return { ok = true, installed = installed, displaying = display, localSlot = ownerSlot }
    end

    return { ok = true, integration = integration, callbacks = callbacks }
end

return Build42WatchUi
