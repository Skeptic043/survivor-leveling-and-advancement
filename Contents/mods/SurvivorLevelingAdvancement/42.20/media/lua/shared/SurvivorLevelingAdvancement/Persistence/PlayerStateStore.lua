local PlayerStateStore = {}

local NAMESPACE = "SurvivorLevelingAdvancement"

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function call(method, ...)
    local ok, result = pcall(method, ...)
    if not ok then return nil, result end
    return result
end

function PlayerStateStore.create(codec)
    if type(codec) ~= "table" or type(codec.decode) ~= "function" or type(codec.encode) ~= "function" then
        return failure("invalid_codec", "decode_and_encode_required")
    end

    local store = {}

    function store.load(player, options)
        if player == nil or type(player.getModData) ~= "function" then
            return failure("missing_player_mod_data", "getModData_required")
        end
        local modData, modDataError = call(player.getModData, player)
        if type(modData) ~= "table" then
            return failure("player_mod_data_unavailable", tostring(modDataError or "not_table"))
        end
        local decoded, decodeError = call(codec.decode, modData[NAMESPACE], options)
        if type(decoded) ~= "table" then
            return failure("codec_decode_failed", tostring(decodeError or "not_result"))
        end
        return decoded
    end

    function store.save(player, state)
        local encoded, encodeError = call(codec.encode, state)
        if type(encoded) ~= "table" then
            return failure("codec_encode_failed", tostring(encodeError or "not_result"))
        end
        if not encoded.ok then return encoded end
        if type(encoded.state) ~= "table" then return failure("codec_encode_failed", "missing_state") end
        if player == nil or type(player.getModData) ~= "function" then
            return failure("missing_player_mod_data", "getModData_required")
        end
        local modData, modDataError = call(player.getModData, player)
        if type(modData) ~= "table" then
            return failure("player_mod_data_unavailable", tostring(modDataError or "not_table"))
        end
        modData[NAMESPACE] = encoded.state
        return { ok = true }
    end

    return { ok = true, store = store }
end

return PlayerStateStore
