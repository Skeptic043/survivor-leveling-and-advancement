local Build42AdminSkillUi = {}

local function failure(code)
    return { ok = false, code = code }
end

local function member(value, key)
    local ok, result = pcall(function() return value[key] end)
    return ok and result or nil
end

local function call(value, key, ...)
    local method = member(value, key)
    if type(method) ~= "function" then return nil end
    local ok, result = pcall(method, value, ...)
    return ok and result or nil
end

local function finite(value)
    return type(value) == "number" and value == value and value >= 0
        and value ~= math.huge
end

local function codeOf(value, fallback)
    return type(value) == "table" and type(value.code) == "string" and value.code or fallback
end

local function pack(...)
    return { n = select("#", ...), ... }
end

function Build42AdminSkillUi.create(deps)
    if type(deps) ~= "table" or type(deps.PlayerStats) ~= "table"
        or type(deps.owner) ~= "table" or type(deps.owner.requestAdmin) ~= "function"
        or type(deps.owner.adminStatus) ~= "function"
        or type(deps.owner.invokeWithRoute) ~= "function"
        or type(deps.owner.setAdminResultListener) ~= "function"
        or type(deps.getSpecificPlayer) ~= "function" or type(deps.isClient) ~= "function"
        or type(deps.report) ~= "function" then return failure("invalid_dependencies") end
    local stats, owner = deps.PlayerStats, deps.owner
    local prior = rawget(stats, "onOptionMouseDown")
    local priorVisible = rawget(stats, "setVisible")
    local priorAddXP = rawget(stats, "onAddXP")
    if type(prior) ~= "function" or type(priorVisible) ~= "function" or type(priorAddXP) ~= "function" then
        return failure("missing_player_stats_hook")
    end
    local pending, running = {}, {}
    local installed, disabled = false, false
    local hook, visibilityHook, addXpHook, listener

    local function report(code)
        pcall(deps.report, code)
    end

    local function owns()
        if not installed or disabled then return false end
        if rawget(stats, "onOptionMouseDown") ~= hook or rawget(stats, "setVisible") ~= visibilityHook
            or rawget(stats, "onAddXP") ~= addXpHook then
            disabled = true
            pending = {}
            report("player_stats_hook_ownership_lost")
            return false
        end
        return true
    end

    local function slotFor(player)
        for slot = 0, 3 do
            local ok, current = pcall(deps.getSpecificPlayer, slot)
            if ok and current ~= nil and current == player then return slot end
        end
        return nil
    end

    local function position(action)
        local xp = call(action.player, "getXp")
        return xp and call(xp, "getXP", action.perk) or nil
    end

    local function stableAction(action)
        return owns() and action.view.char == action.player
            and action.button.internal == action.operation
            and call(action.view, "isVisible") == true
            and slotFor(action.actor) == action.slot
            and (not action.multiplayer or
                (call(action.player, "getOnlineID") == action.onlineId
                     and call(action.player, "getUsername") == action.username))
    end

    local function selectedFor(action)
        local selected = action.view.selectedPerk
        if type(selected) == "table" and selected.perk == action.perk then return selected end
        local list = action.view.xpListBox
        if selected == nil and action.selectionIndex ~= nil and type(list) == "table"
            and list.selected == action.selectionIndex
            and type(action.selection) == "table" and action.selection.perk == action.perk then
            return action.selection
        end
        return nil
    end

    local function callNative(action, selection)
        local current = action.view.selectedPerk
        if current == nil then action.view.selectedPerk = selection end
        local result = pack(pcall(prior, action.view, action.button,
            unpack(action.arguments, 1, action.arguments.n)))
        if current == nil then action.view.selectedPerk = nil end
        return result
    end

    local function callScopedNative(action, selection)
        local map = running[action.player]
        if map == nil then map = {}; running[action.player] = map end
        map[action.perk] = true
        local result = callNative(action, selection)
        map[action.perk] = nil
        local occupied = false
        for _ in pairs(map) do occupied = true; break end
        if not occupied then running[action.player] = nil end
        return result
    end

    local function fallback(action)
        if not stableAction(action) then
            pending[action.slot] = nil
            report("player_stats_action_changed")
            return
        end
        local selection = selectedFor(action)
        if selection == nil then
            pending[action.slot] = nil
            report("player_stats_action_changed")
            return
        end
        pending[action.slot] = nil
        local result = callScopedNative(action, selection)
        if not result[1] then
            report("native_level_edit_threw")
            if not action.multiplayer then error(result[2], 0) end
            return
        end
        return unpack(result, 2, result.n)
    end

    local function finish(action, terminal)
        if pending[action.slot] ~= action then return end
        pending[action.slot] = nil
        if not terminal or terminal.ok ~= true or terminal.outcome ~= "applied" then
            report(terminal and terminal.code or "skill_clear_failed")
        end
    end

    local function invoke(action, summary, target)
        if not stableAction(action) then
            pending[action.slot] = nil
            report("player_stats_action_changed")
            return
        end
        local selection = selectedFor(action)
        if selection == nil then
            pending[action.slot] = nil
            report("player_stats_action_changed")
            return
        end
        local before = position(action)
        if not finite(before) then pending[action.slot] = nil; report("skill_position_unavailable"); return end
        action.phase = "native"
        local result = callScopedNative(action, selection)
        if not result[1] then
            pending[action.slot] = nil
            report("native_level_edit_threw")
            if not action.multiplayer then error(result[2], 0) end
            return
        end
        local after = position(action)
        if not finite(after) or before == after then
            pending[action.slot] = nil
            return unpack(result, 2, result.n)
        end
        local request = { operation = "clearAdvancementSlots", perkId = action.perkId,
            expectedRevision = summary.revision }
        if action.multiplayer then request.target = target end
        action.phase = "clear"
        action.requestId, action.terminal = nil, nil
        local sent, cleared = pcall(owner.requestAdmin, action.slot, request)
        if not sent or type(cleared) ~= "table" or not cleared.ok then
            pending[action.slot] = nil
            report(codeOf(cleared, "skill_clear_request_failed"))
        elseif action.multiplayer then
            action.requestId = cleared.requestId
            listener(action.slot, "admin_terminal")
        else
            finish(action, cleared)
        end
        return unpack(result, 2, result.n)
    end

    listener = function(slot, kind, received)
        local action = pending[slot]
        if action == nil or not action.multiplayer then return end
        if kind == "reset" then pending[slot] = nil; return end
        if not owns() then return end
        if received ~= nil then action.terminal = received end
        if action.requestId == nil then return end
        local terminal = action.terminal
        if terminal == nil then
            local ok, status = pcall(owner.adminStatus, slot)
            if not ok or type(status) ~= "table" or status.ok ~= true or status.pending then return end
            terminal = status.result
        end
        if type(terminal) ~= "table" or terminal.requestId ~= action.requestId then return end
        if action.phase == "inspect" then
            local target = terminal.target
            if terminal.ok == false then return fallback(action) end
            if terminal.ok ~= true or terminal.outcome ~= "inspected"
                or type(terminal.summary) ~= "table" or not finite(terminal.summary.revision)
                or type(target) ~= "table" or target.onlineId ~= action.onlineId
                or target.username ~= action.username then
                pending[slot] = nil
                report(terminal.code or "skill_inspection_failed")
                return
            end
            invoke(action, terminal.summary, target)
        elseif action.phase == "clear" then
            finish(action, terminal)
        end
    end

    hook = function(view, button, ...)
        local operation = type(button) == "table" and button.internal or nil
        if operation ~= "LEVELPERK" and operation ~= "LOWERPERK" then
            return prior(view, button, ...)
        end
        if not owns() then return prior(view, button, ...) end
        local player = view.char
        local perk = type(view.selectedPerk) == "table" and view.selectedPerk.perk or nil
        if player == nil or perk == nil then return prior(view, button, ...) end
        local map = running[player]
        if map and map[perk] then return prior(view, button, ...) end
        local clientOk, multiplayer = pcall(deps.isClient)
        if not clientOk or type(multiplayer) ~= "boolean" then
            report("client_mode_unavailable")
            return prior(view, button, ...)
        end
        local actor = multiplayer and view.admin or player
        local slot = slotFor(actor)
        if slot == nil then
            report("player_stats_local_owner_unavailable")
            return prior(view, button, ...)
        end
        if pending[slot] ~= nil then
            if pending[slot].phase == "native" then
                report("nested_skill_edit_not_cleared")
                return prior(view, button, ...)
            end
            return
        end
        local id = call(perk, "getId")
        if type(id) ~= "string" or #id > 128 or not string.match(id, "^[%w%._:%-]+$") then
            report("skill_identity_unavailable")
            return prior(view, button, ...)
        end
        local action = { view = view, button = button, player = player, actor = actor,
            slot = slot, perk = perk, perkId = id, operation = operation, multiplayer = multiplayer,
            arguments = pack(...), phase = "inspect", selection = view.selectedPerk,
            selectionIndex = type(view.xpListBox) == "table" and view.xpListBox.selected or nil }
        local request = { operation = "inspect" }
        if multiplayer then
            action.username, action.onlineId = call(player, "getUsername"), call(player, "getOnlineID")
            if type(action.username) ~= "string" or not finite(action.onlineId) then
                report("player_stats_target_unavailable")
                return
            end
            request.target = { username = action.username }
        end
        pending[slot] = action
        local ok, inspected = pcall(owner.requestAdmin, slot, request)
        if not ok or type(inspected) ~= "table" or not inspected.ok then
            pending[slot] = nil
            report(codeOf(inspected, "skill_inspection_failed"))
            return fallback(action)
        end
        if multiplayer then
            action.requestId = inspected.requestId
            listener(slot, "admin_terminal")
            return
        end
        if inspected.outcome ~= "inspected" or type(inspected.summary) ~= "table"
            or not finite(inspected.summary.revision) then
            pending[slot] = nil
            report("skill_inspection_failed")
            return
        end
        return invoke(action, inspected.summary)
    end

    visibilityHook = function(view, visible, ...)
        if visible == false then
            for slot = 0, 3 do
                if pending[slot] and pending[slot].view == view then pending[slot] = nil end
            end
        end
        return priorVisible(view, visible, ...)
    end

    addXpHook = function(view, button, perk, amount, addGlobalXP, useMultipliers, ...)
        local clientOk, multiplayer = pcall(deps.isClient)
        if not owns() or not clientOk or multiplayer ~= false or type(useMultipliers) ~= "boolean" then
            return priorAddXP(view, button, perk, amount, addGlobalXP, useMultipliers, ...)
        end
        local current = rawget(stats, "instance")
        local player = current and member(current, "char")
        local selectedPerk = call(perk, "getType")
        if player == nil or selectedPerk == nil then
            return priorAddXP(view, button, perk, amount, addGlobalXP, useMultipliers, ...)
        end
        return owner.invokeWithRoute(player, selectedPerk, useMultipliers, priorAddXP,
            view, button, perk, amount, addGlobalXP, useMultipliers, ...)
    end

    local integration = {}
    function integration.install()
        if disabled then return failure("player_stats_hook_ownership_lost") end
        if installed then return owns() and { ok = true } or failure("player_stats_hook_ownership_lost") end
        if rawget(stats, "onOptionMouseDown") ~= prior or rawget(stats, "setVisible") ~= priorVisible
            or rawget(stats, "onAddXP") ~= priorAddXP then
            disabled = true
            return failure("player_stats_hook_ownership_lost")
        end
        local ok, bound = pcall(owner.setAdminResultListener, listener)
        if not ok or type(bound) ~= "table" or not bound.ok then return failure("listener_install_failed") end
        rawset(stats, "onOptionMouseDown", hook)
        rawset(stats, "setVisible", visibilityHook)
        rawset(stats, "onAddXP", addXpHook)
        installed = true
        return { ok = true }
    end
    function integration.status()
        return { ok = true, installed = owns() }
    end
    return { ok = true, integration = integration }
end

return Build42AdminSkillUi
