local MutationScope = {}

local activeByPlayer = {}
local recordByHandle = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function isSafeId(value)
    return type(value) == "string" and value:match("^[%w%._:%-]+$") ~= nil
end

function MutationScope.begin(player, perkId)
    if player == nil then return failure("invalid_scope", "player_required") end
    if not isSafeId(perkId) then return failure("invalid_scope", "perkId_required") end
    local scopes = activeByPlayer[player]
    if scopes ~= nil and scopes[perkId] ~= nil then return failure("scope_active", "player_perk") end
    if scopes == nil then
        scopes = {}
        activeByPlayer[player] = scopes
    end
    local handle = {}
    local record = { player = player, perkId = perkId, handle = handle }
    scopes[perkId] = record
    recordByHandle[handle] = record
    return { ok = true, handle = handle }
end

function MutationScope.isActive(player, perkId)
    if player == nil or not isSafeId(perkId) then return false end
    local scopes = activeByPlayer[player]
    return scopes ~= nil and scopes[perkId] ~= nil
end

function MutationScope.finish(handle)
    local record = recordByHandle[handle]
    if record == nil then return failure("invalid_scope_handle", "stale_or_foreign") end
    local scopes = activeByPlayer[record.player]
    if scopes == nil or scopes[record.perkId] ~= record then
        return failure("invalid_scope_handle", "stale_or_foreign")
    end
    scopes[record.perkId] = nil
    local hasRemaining = false
    for _ in pairs(scopes) do
        hasRemaining = true
        break
    end
    if not hasRemaining then activeByPlayer[record.player] = nil end
    recordByHandle[handle] = nil
    return { ok = true }
end

return MutationScope
