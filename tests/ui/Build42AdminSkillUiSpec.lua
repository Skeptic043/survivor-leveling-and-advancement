local assertions = 0
local function expect(value, message)
    assertions = assertions + 1
    if not value then error(message, 0) end
end
local function equal(actual, expected, message)
    expect(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function environment(multiplayer, localSlot)
    local env = { calls = 0, requests = {}, reports = {}, revision = 4, slot = localSlot or 0 }
    local perk = { getId = function() return "Fitness" end }
    local player = { position = 150 }
    local xp = { getXP = function() return player.position end }
    function player:getXp() return xp end
    function player:getUsername() return "Target" end
    function player:getOnlineID() return 17 end
    local actor = multiplayer and {} or player
    local stats = {}
    function stats.onOptionMouseDown(view, button, extra)
        env.calls = env.calls + 1
        env.lastExtra = extra
        if env.nested and not env.inside then
            env.inside = true
            stats.onOptionMouseDown(view, button)
            env.inside = nil
        end
        if env.otherNested and not env.inside then
            env.inside = true
            local selected = view.selectedPerk
            view.selectedPerk = { perk = { getId = function() return "Strength" end } }
            stats.onOptionMouseDown(view, button)
            view.selectedPerk = selected
            env.inside = nil
        end
        if env.throws then error("native failure") end
        if button.internal == "LEVELPERK" then player.position = math.min(300, player.position + 100)
        elseif button.internal == "LOWERPERK" then player.position = math.max(0, player.position - 100) end
        return "prior-return", nil, 7
    end
    function stats.setVisible(view, visible) view.visible = visible; return "visible" end
    local view = setmetatable({ char = player, admin = actor, selectedPerk = { perk = perk },
        xpListBox = { selected = 3 }, visible = true },
        { __index = stats })
    function view:isVisible() return self.visible end
    local owner = {}
    function owner.setAdminResultListener(listener) env.listener = listener; return { ok = true } end
    function owner.requestAdmin(slot, request)
        equal(slot, env.slot, "exact local slot")
        env.requests[#env.requests + 1] = request
        if env.failSend then return { ok = false, code = "send_failed" } end
        if multiplayer then
            env.nextId = (env.nextId or 0) + 1
            local id = "request-" .. env.nextId
            env.status = { ok = true, pending = true }
            if env.immediate then
                env.status = { ok = true, pending = false, result = {
                    ok = true, outcome = request.operation == "inspect" and "inspected" or "applied",
                    requestId = id, target = { username = "Target", onlineId = 17 },
                    summary = { revision = env.revision },
                } }
                env.listener(slot, "admin_terminal", env.status.result)
                if env.reentrant then env.status = { ok = true, pending = true } end
            end
            return { ok = true, requestId = id }
        end
        if request.operation == "inspect" then
            env.listener(slot, "admin_terminal")
            return { ok = true, outcome = "inspected", summary = { revision = env.revision } }
        end
        return { ok = true, outcome = "applied", summary = { revision = env.revision + 1 } }
    end
    function owner.adminStatus() return env.status or { ok = true, pending = false } end
    env.deps = { PlayerStats = stats, owner = owner, isClient = function() return multiplayer end,
        getSpecificPlayer = function(slot) return slot == env.slot and actor or nil end,
        report = function(code) env.reports[#env.reports + 1] = code end }
    local created = Build42AdminSkillUi.create(env.deps)
    expect(created.ok, "create wrapper")
    env.integration = created.integration
    expect(env.integration.install().ok, "install wrapper")
    env.stats, env.view, env.perk, env.player, env.actor = stats, view, perk, player, actor
    function env.click(operation)
        return stats.onOptionMouseDown(view, { internal = operation }, "argument")
    end
    function env.deliver(id, outcome, changes)
        local result = { ok = true, requestId = id, outcome = outcome,
            summary = { revision = env.revision }, target = { username = "Target", onlineId = 17 } }
        for key, value in pairs(changes or {}) do result[key] = value end
        env.status = { ok = true, pending = false, result = result }
        env.listener(env.slot, "admin_terminal", result)
    end
    return env
end

for _, direction in ipairs({ "LEVELPERK", "LOWERPERK" }) do
    local env = environment(false, 2)
    local first, second, third = env.click(direction)
    equal(first, "prior-return", "prior first result")
    equal(second, nil, "prior nil result")
    equal(third, 7, "prior last result")
    equal(env.calls, 1, "native handler runs once")
    equal(env.lastExtra, "argument", "native extra argument preserved")
    equal(#env.requests, 2, "inspect plus selected clear")
    equal(env.requests[2].perkId, "Fitness", "clear selects exact perk")
    equal(env.requests[2].expectedRevision, 4, "clear uses prepared revision")
    equal(env.player.position, direction == "LEVELPERK" and 250 or 50, "native XP preserved")
    equal(#env.reports, 0, "successful SP operation has no error")
    expect(env.integration.install().ok, "repeat install is idempotent")
    env.click(direction)
    equal(env.calls, 2, "repeat install does not double-chain")
end

do
    local env = environment(false)
    env.player.position = 0
    env.click("LOWERPERK")
    equal(#env.requests, 1, "unchanged limit does not clear")
    env.click("ADDXP")
    equal(#env.requests, 1, "raw Add XP has no clear")
    env.player.position = 70
    equal(#env.requests, 1, "ordinary gameplay has no clear")
    env.nested = true
    env.click("LEVELPERK")
    equal(env.calls, 4, "nested prior behavior is preserved")
    equal(#env.requests, 3, "same-perk nesting clears only once")
end

do
    local env = environment(false)
    env.throws = true
    local ok = pcall(env.click, "LEVELPERK")
    expect(not ok, "original SP throw propagates")
    equal(#env.requests, 1, "throw never dispatches clear")
    env.throws = false
    env.click("LOWERPERK")
    equal(#env.requests, 3, "throw releases pending and scope")
end

do
    local env = environment(true, 1)
    env.click("LOWERPERK")
    equal(env.calls, 0, "MP waits for authoritative inspection")
    env.click("LEVELPERK")
    equal(#env.requests, 1, "duplicate pending action is frozen")
    env.deliver("foreign", "inspected")
    equal(env.calls, 0, "foreign response cannot trigger native")
    env.deliver("request-1", "inspected")
    equal(env.calls, 1, "matching response executes captured native once")
    equal(env.requests[2].perkId, "Fitness", "MP clear carries selected perk")
    equal(env.requests[2].target.onlineId, 17, "MP clear retains authoritative identity")
    equal(env.requests[2].expectedRevision, 4, "MP clear preserves prepared revision")
    env.deliver("request-2", "rejected", { code = "stale_revision" })
    equal(env.reports[#env.reports], "stale_revision", "late clear conflict is reported")
    env.click("LEVELPERK")
    equal(#env.requests, 3, "rejection releases pending")
end

for _, change in ipairs({ "perk", "target", "hidden", "reset", "ownership", "denied" }) do
    local env = environment(true)
    env.click("LOWERPERK")
    if change == "perk" then env.view.selectedPerk = { perk = {} }
    elseif change == "target" then env.view.char = {}
    elseif change == "hidden" then env.view:setVisible(false)
    elseif change == "reset" then env.listener(0, "reset")
    elseif change == "ownership" then env.stats.onOptionMouseDown = function() end end
    env.deliver("request-1", "inspected", change == "denied" and { ok = false, code = "request_denied" } or nil)
    equal(env.calls, change == "denied" and 1 or 0, "cancelled preparation cannot invoke native: " .. change)
    equal(#env.requests, 1, "cancelled preparation cannot clear: " .. change)
end

do
    local env = environment(true)
    env.click("LOWERPERK")
    env.view.selectedPerk = nil
    env.deliver("request-1", "inspected")
    equal(env.calls, 1, "transient native prerender selection is restored for matched inspection")
    equal(#env.requests, 2, "transient selection still clears the captured skill")
end

do
    local env = environment(true)
    env.click("LOWERPERK")
    env.view.selectedPerk = nil
    env.view.xpListBox.selected = 4
    env.deliver("request-1", "inspected")
    equal(env.calls, 0, "changed native row cannot run delayed handler")
    equal(#env.requests, 1, "changed native row cannot clear another skill")
end

for _, failureCode in ipairs({ "request_denied", "response_timeout" }) do
    local env = environment(true)
    env.nested = true
    env.click("LOWERPERK")
    env.deliver("request-1", "inspected", { ok = false, code = failureCode, committed = false })
    equal(env.calls, 2, "fallback preserves nested native call once: " .. failureCode)
    equal(#env.requests, 1, "fallback nesting cannot schedule another inspection: " .. failureCode)
    env.deliver("request-2", "inspected")
    equal(env.calls, 2, "unexpected later response cannot replay fallback native call: " .. failureCode)
end

do
    local env = environment(true)
    env.immediate = true
    env.click("LOWERPERK")
    equal(env.calls, 1, "synchronous delivery executes native once")
    env.click("LEVELPERK")
    equal(env.calls, 2, "synchronous clear result releases pending")
end

do
    local env = environment(false)
    env.deps.PlayerStats = {}
    equal(Build42AdminSkillUi.create(env.deps).ok, false, "missing native methods fail closed")
    local old = env.stats.onOptionMouseDown
    env.stats.onOptionMouseDown = function(...) return old(...) end
    env.click("LOWERPERK")
    equal(#env.requests, 0, "later wrapper disables SLA reset")
    equal(env.calls, 1, "later wrapper preserves prior native behavior")
    expect(not env.integration.status().installed, "ownership loss is reported")
end
do
    local env = environment(false)
    env.otherNested = true
    env.click("LEVELPERK")
    equal(env.calls, 2, "different-perk nested native behavior is preserved")
    equal(#env.requests, 2, "different-perk nesting does not add an unsafe clear")
    equal(env.reports[1], "nested_skill_edit_not_cleared", "nested fallback is explicit")
end

do
    local env = environment(true)
    env.immediate, env.reentrant = true, true
    env.click("LOWERPERK")
    equal(env.calls, 1, "captured terminal survives status replacement by another listener")
    env.click("LEVELPERK")
    equal(env.calls, 2, "captured clear terminal releases action despite replaced status")
end

do
    local env = environment(true)
    env.click("LOWERPERK")
    env.throws = true
    env.deliver("request-1", "inspected")
    equal(#env.requests, 1, "MP native throw cancels clear")
    env.throws = false
    env.click("LEVELPERK")
    equal(#env.requests, 2, "MP native throw releases pending")
end
return assertions
