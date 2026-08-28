local CharacterInheritanceStore = {}

local NAMESPACE = "SLA_CharacterInheritance_v1"
local CODEC_NAMESPACE = "SurvivorLevelingAdvancement"
local SCHEMA_VERSION = 1

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function exactRoot(value)
    if not plain(value) then return nil end
    local allowed = {
        schemaVersion = true,
        newCharacterToken = true,
        initialized = true,
        deathRecorded = true,
    }
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then return nil end
        count = count + 1
    end
    if count ~= 4 or rawget(value, "schemaVersion") ~= SCHEMA_VERSION
        or type(rawget(value, "newCharacterToken")) ~= "boolean"
        or type(rawget(value, "initialized")) ~= "boolean"
        or type(rawget(value, "deathRecorded")) ~= "boolean"
        or (rawget(value, "initialized") and rawget(value, "newCharacterToken"))
        or (rawget(value, "deathRecorded") and not rawget(value, "initialized")) then
        return nil
    end
    return {
        schemaVersion = SCHEMA_VERSION,
        newCharacterToken = rawget(value, "newCharacterToken"),
        initialized = rawget(value, "initialized"),
        deathRecorded = rawget(value, "deathRecorded"),
    }
end

local function emptyRoot()
    return {
        schemaVersion = SCHEMA_VERSION,
        newCharacterToken = false,
        initialized = false,
        deathRecorded = false,
    }
end

local function playerModData(player)
    if player == nil then return nil, "player_required" end
    local methodCalled, method = pcall(function() return player.getModData end)
    if not methodCalled or type(method) ~= "function" then return nil, "getModData_required" end
    local called, modData = pcall(method, player)
    if not called or type(modData) ~= "table" then return nil, "mod_data_unavailable" end
    return modData, nil
end

function CharacterInheritanceStore.create()
    local issued = setmetatable({}, { __mode = "k" })
    local store = {}

    local function read(player)
        local modData, detail = playerModData(player)
        if modData == nil then return nil, nil, failure("metadata_unavailable", detail) end
        local raw = rawget(modData, NAMESPACE)
        if raw == nil then return modData, emptyRoot(), nil end
        local root = exactRoot(raw)
        if root == nil then return nil, nil, failure("metadata_invalid", "inheritance namespace") end
        return modData, root, nil
    end

    local function write(modData, root)
        local called = pcall(rawset, modData, NAMESPACE, root)
        if not called then return failure("metadata_write_failed", "inheritance namespace") end
        return { ok = true }
    end

    function store.inspect(player)
        local modData, root, err = read(player)
        if err ~= nil then return err end
        return {
            ok = true,
            metadata = {
                tokenPresent = root.newCharacterToken,
                tokenValid = root.newCharacterToken and issued[player] == true,
                initialized = root.initialized,
                deathRecorded = root.deathRecorded,
                codecPresent = rawget(modData, CODEC_NAMESPACE) ~= nil,
            },
        }
    end

    function store.tokenNewCharacter(player)
        local modData, root, err = read(player)
        if err ~= nil then return err end
        if root.initialized or root.deathRecorded then
            return failure("metadata_state_invalid", "character already initialized")
        end
        if root.newCharacterToken and issued[player] == true then return { ok = true } end
        local saved = write(modData, {
            schemaVersion = SCHEMA_VERSION,
            newCharacterToken = true,
            initialized = false,
            deathRecorded = false,
        })
        if not saved.ok then return saved end
        issued[player] = true
        return { ok = true }
    end

    function store.markInitialized(player)
        issued[player] = nil
        local modData, root, err = read(player)
        if err ~= nil then return err end
        return write(modData, {
            schemaVersion = SCHEMA_VERSION,
            newCharacterToken = false,
            initialized = true,
            deathRecorded = root.deathRecorded,
        })
    end

    function store.markDeathRecorded(player)
        local modData, root, err = read(player)
        if err ~= nil then return err end
        if not root.initialized or root.newCharacterToken then
            return failure("metadata_state_invalid", "character is not initialized")
        end
        return write(modData, {
            schemaVersion = SCHEMA_VERSION,
            newCharacterToken = false,
            initialized = true,
            deathRecorded = true,
        })
    end

    return { ok = true, store = store }
end

return CharacterInheritanceStore
