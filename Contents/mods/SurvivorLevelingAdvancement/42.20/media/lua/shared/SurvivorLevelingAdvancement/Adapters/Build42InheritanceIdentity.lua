local Build42InheritanceIdentity = {}

local MAX_SAFE_INTEGER = 9007199254740991
local MAX_ONLINE_ID = 32767
local MAX_USERNAME_BYTES = 64
local MAX_CACHE_BASES = 8192

local function plainOrUserdata(value)
    return (type(value) == "table" and getmetatable(value) == nil) or type(value) == "userdata"
end

local function safeInteger(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
        and value >= 0 and value <= MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function safeProfile(value)
    return safeInteger(value) and value <= 3
end

local function safeOnlineId(value)
    return safeInteger(value) and value <= MAX_ONLINE_ID
end

local function safeUsername(value)
    if type(value) ~= "string" or value == "" or #value > MAX_USERNAME_BYTES then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then return false end
    end
    return true
end

local function property(object, name)
    if not plainOrUserdata(object) then return false, nil end
    return pcall(function() return object[name] end)
end

local function method(object, name)
    local got, fn = property(object, name)
    if not got or type(fn) ~= "function" then return false, nil end
    return pcall(fn, object)
end

local function failure(code)
    return { ok = false, code = code }
end

function Build42InheritanceIdentity.create(dependencies)
    if type(dependencies) ~= "table" or getmetatable(dependencies) ~= nil
        or type(rawget(dependencies, "isServer")) ~= "function"
        or type(rawget(dependencies, "isClient")) ~= "function"
        or type(rawget(dependencies, "getPlayerByOnlineID")) ~= "function" then
        return failure("invalid_capabilities")
    end
    local isServer, isClient = rawget(dependencies, "isServer"), rawget(dependencies, "isClient")
    local getPlayerByOnlineID = rawget(dependencies, "getPlayerByOnlineID")
    local cache, cacheCount = {}, 0
    local adapter = {}

    local function mode()
        local serverCalled, server = pcall(isServer)
        local clientCalled, client = pcall(isClient)
        if not serverCalled or not clientCalled
            or type(server) ~= "boolean" or type(client) ~= "boolean"
            or (server and client) then return nil end
        if server then return "server" end
        if client then return nil end
        return "sp"
    end

    function adapter.resolve(player)
        local processMode = mode()
        if processMode == nil then return failure("invalid_mode") end
        if not plainOrUserdata(player) then return failure("invalid_player") end
        if processMode == "sp" then
            local got, profileIndex = method(player, "getPlayerNum")
            if not got or not safeProfile(profileIndex) then return failure("invalid_profile") end
            return { ok = true, owner = { kind = "sp", profileIndex = profileIndex } }
        end

        local onlineCalled, onlineId = method(player, "getOnlineID")
        if not onlineCalled or not safeOnlineId(onlineId) then return failure("invalid_online_id") end
        local liveCalled, livePlayer = pcall(getPlayerByOnlineID, onlineId)
        if not liveCalled then return failure("player_lookup_failed") end
        if livePlayer ~= player then return failure("player_not_live") end
        local profileIndex = onlineId % 4
        local indexCalled, assignedIndex = method(player, "getPlayerNum")
        if not indexCalled or assignedIndex ~= profileIndex then return failure("profile_mismatch") end
        local base = onlineId - profileIndex
        local primaryCalled, primary = pcall(getPlayerByOnlineID, base)
        if not primaryCalled then return failure("primary_lookup_failed") end

        if primary ~= nil then
            if not plainOrUserdata(primary) then return failure("invalid_primary") end
            local primaryIdCalled, primaryId = method(primary, "getOnlineID")
            local primaryIndexCalled, primaryIndex = method(primary, "getPlayerNum")
            local usernameCalled, username = method(primary, "getUsername")
            if not primaryIdCalled or primaryId ~= base
                or not primaryIndexCalled or primaryIndex ~= 0
                or not usernameCalled or not safeUsername(username) then
                return failure("invalid_primary")
            end
            if profileIndex == 0 and primary ~= player then return failure("invalid_primary") end
            local binding = cache[base]
            if binding == nil then
                if cacheCount >= MAX_CACHE_BASES then return failure("cache_full") end
                cacheCount = cacheCount + 1
            end
            if binding == nil or binding.primary ~= primary
                or binding.primaryLoginUsername ~= username then
                binding = {
                    primary = primary,
                    primaryLoginUsername = username,
                    players = { [0] = primary },
                }
            else
                binding.primaryLoginUsername = username
                binding.players[0] = primary
            end
            binding.players[profileIndex] = player
            cache[base] = binding
            return {
                ok = true,
                owner = {
                    kind = "mp", primaryLoginUsername = username, profileIndex = profileIndex,
                },
            }
        end

        local binding = cache[base]
        if profileIndex == 0 or binding == nil or binding.players[profileIndex] ~= player then
            return failure("primary_unavailable")
        end
        return {
            ok = true,
            owner = {
                kind = "mp",
                primaryLoginUsername = binding.primaryLoginUsername,
                profileIndex = profileIndex,
            },
        }
    end

    return { ok = true, adapter = adapter }
end

return Build42InheritanceIdentity
