local ServerPlayerRecordStore = {}

local NAMESPACE = "SLA_ServerPlayers_v1"
local LEGACY_STATE_NAMESPACE = "SurvivorLevelingAdvancement"
local ROOT_SCHEMA = 1
local RECORD_SCHEMA = 1
local COMPLETED_DEATH_REPLACEMENT = "completed_death_replacement"

local function failure(code, detail)
    return { ok = false, code = code, detail = detail or code }
end

local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function empty(value)
    if not plain(value) then return false end
    for _ in pairs(value) do return false end
    return true
end

local function safeProfile(value)
    return type(value) == "number" and value == math.floor(value)
        and value >= 0 and value <= 3
end

local function safeUsername(value)
    if type(value) ~= "string" or value == "" or #value > 64 then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then return false end
    end
    return true
end

local function exact(value, fields, count)
    if not plain(value) then return false end
    local found = 0
    for key in pairs(value) do
        if type(key) ~= "string" or not fields[key] then return false end
        found = found + 1
    end
    return found == count
end

local function validRecordShape(record)
    return exact(record, {
        schemaVersion = true,
        state = true,
        initialized = true,
        deathRecorded = true,
    }, 4)
        and rawget(record, "schemaVersion") == RECORD_SCHEMA
        and plain(rawget(record, "state"))
        and type(rawget(record, "initialized")) == "boolean"
        and type(rawget(record, "deathRecorded")) == "boolean"
        and (not rawget(record, "deathRecorded") or rawget(record, "initialized"))
end

local function copyRoot(raw)
    if empty(raw) then
        return { schemaVersion = ROOT_SCHEMA, players = {} }, true
    end
    if not plain(raw) then return nil, false, "invalid_root" end
    local schema = rawget(raw, "schemaVersion")
    if type(schema) == "number" and schema > ROOT_SCHEMA then
        return nil, false, "newer_root"
    end
    if not exact(raw, { schemaVersion = true, players = true }, 2)
        or schema ~= ROOT_SCHEMA or not plain(rawget(raw, "players")) then
        return nil, false, "invalid_root"
    end
    local copiedPlayers = {}
    for username, profiles in pairs(raw.players) do
        if not safeUsername(username) or not plain(profiles) then
            return nil, false, "invalid_root"
        end
        local copiedProfiles = {}
        for profileIndex, record in pairs(profiles) do
            if not safeProfile(profileIndex) then return nil, false, "invalid_root" end
            if plain(record) and type(rawget(record, "schemaVersion")) == "number"
                and rawget(record, "schemaVersion") > RECORD_SCHEMA then
                return nil, false, "newer_record"
            end
            if not validRecordShape(record) then return nil, false, "invalid_record" end
            copiedProfiles[profileIndex] = {
                schemaVersion = RECORD_SCHEMA,
                state = record.state,
                initialized = record.initialized,
                deathRecorded = record.deathRecorded,
            }
        end
        copiedPlayers[username] = copiedProfiles
    end
    return { schemaVersion = ROOT_SCHEMA, players = copiedPlayers }, false, nil
end

local function copyOwner(result)
    if not exact(result, { ok = true, owner = true }, 2) or rawget(result, "ok") ~= true then
        return nil
    end
    local owner = rawget(result, "owner")
    if not exact(owner, {
        kind = true,
        primaryLoginUsername = true,
        profileIndex = true,
    }, 3) or rawget(owner, "kind") ~= "mp"
        or not safeUsername(rawget(owner, "primaryLoginUsername"))
        or not safeProfile(rawget(owner, "profileIndex")) then
        return nil
    end
    return {
        primaryLoginUsername = owner.primaryLoginUsername,
        profileIndex = owner.profileIndex,
    }
end

local function metadata(result)
    if not exact(result, { ok = true, metadata = true }, 2) or rawget(result, "ok") ~= true then
        return nil
    end
    local value = rawget(result, "metadata")
    if not exact(value, {
        tokenPresent = true,
        tokenValid = true,
        initialized = true,
        deathRecorded = true,
        codecPresent = true,
    }, 5) then return nil end
    for _, key in ipairs({
        "tokenPresent", "tokenValid", "initialized", "deathRecorded", "codecPresent",
    }) do
        if type(rawget(value, key)) ~= "boolean" then return nil end
    end
    return value
end

function ServerPlayerRecordStore.create(dependencies)
    if not exact(dependencies, {
        codec = true,
        identity = true,
        legacyStateStore = true,
        legacyCharacterStore = true,
        getOrCreate = true,
        add = true,
    }, 6) then return failure("invalid_dependencies", "exact dependencies required") end
    local codec = rawget(dependencies, "codec")
    local identity = rawget(dependencies, "identity")
    local legacyStateStore = rawget(dependencies, "legacyStateStore")
    local legacyCharacterStore = rawget(dependencies, "legacyCharacterStore")
    local getOrCreate, add = rawget(dependencies, "getOrCreate"), rawget(dependencies, "add")
    if not plain(codec) or type(rawget(codec, "decode")) ~= "function"
        or type(rawget(codec, "encode")) ~= "function"
        or not plain(identity) or type(rawget(identity, "resolve")) ~= "function"
        or not plain(legacyStateStore) or type(rawget(legacyStateStore, "load")) ~= "function"
        or not plain(legacyCharacterStore) or type(rawget(legacyCharacterStore, "inspect")) ~= "function"
        or type(getOrCreate) ~= "function" or type(add) ~= "function" then
        return failure("invalid_dependencies", "store capabilities required")
    end
    local decode, encode = rawget(codec, "decode"), rawget(codec, "encode")
    local resolveIdentity = rawget(identity, "resolve")
    local loadLegacy = rawget(legacyStateStore, "load")
    local inspectLegacy = rawget(legacyCharacterStore, "inspect")
    local completedPlayers = setmetatable({}, { __mode = "k" })

    local function resolve(player)
        local called, result = pcall(resolveIdentity, player)
        if not called then return nil, failure("identity_threw", "identity.resolve") end
        local owner = copyOwner(result)
        if owner == nil then return nil, failure("identity_invalid", "identity.resolve") end
        return owner, nil
    end

    local function readRoot()
        local called, raw = pcall(getOrCreate, NAMESPACE)
        if not called or raw == nil then return nil, failure("global_read_failed", NAMESPACE) end
        local root, absent, code = copyRoot(raw)
        if root == nil then return nil, failure(code, NAMESPACE) end
        return root, nil, absent
    end

    local function writeRoot(root)
        local called, accepted = pcall(add, NAMESPACE, root)
        if not called or accepted == false then return failure("global_write_failed", NAMESPACE) end
        return { ok = true }
    end

    local function locate(root, owner, create)
        local profiles = root.players[owner.primaryLoginUsername]
        if profiles == nil and create then
            profiles = {}
            root.players[owner.primaryLoginUsername] = profiles
        end
        return profiles, owner.profileIndex
    end

    local function decodeRecord(record, options)
        local called, result = pcall(decode, record.state, options)
        if not called or type(result) ~= "table" or rawget(result, "ok") ~= true
            or type(rawget(result, "state")) ~= "table" then
            return nil, failure("canonical_state_invalid", "codec.decode")
        end
        return result.state, nil
    end

    local function legacyPresent(player)
        if player == nil then return nil end
        local methodCalled, method = pcall(function() return player.getModData end)
        if not methodCalled or type(method) ~= "function" then return nil end
        local dataCalled, data = pcall(method, player)
        if not dataCalled or type(data) ~= "table" then return nil end
        return rawget(data, LEGACY_STATE_NAMESPACE) ~= nil
    end

    local function adoptLegacy(player, owner, root, options)
        if not legacyPresent(player) then return nil, nil end
        local called, loaded = pcall(loadLegacy, player, options)
        if not called or type(loaded) ~= "table" or rawget(loaded, "ok") ~= true
            or type(rawget(loaded, "state")) ~= "table" then
            return nil, failure("legacy_state_invalid", "legacyStateStore.load")
        end
        local encodedCalled, encoded = pcall(encode, loaded.state)
        if not encodedCalled or type(encoded) ~= "table" or rawget(encoded, "ok") ~= true
            or type(rawget(encoded, "state")) ~= "table" then
            return nil, failure("legacy_state_invalid", "codec.encode")
        end
        local initialized, deathRecorded = true, false
        local metadataCalled, inspected = pcall(inspectLegacy, player)
        local legacyMetadata = metadataCalled and metadata(inspected) or nil
        if legacyMetadata ~= nil and legacyMetadata.initialized then
            deathRecorded = legacyMetadata.deathRecorded
        end
        local profiles, profileIndex = locate(root, owner, true)
        profiles[profileIndex] = {
            schemaVersion = RECORD_SCHEMA,
            state = encoded.state,
            initialized = initialized,
            deathRecorded = deathRecorded,
        }
        local written = writeRoot(root)
        if not written.ok then return nil, written end
        return encoded.state, nil
    end

    local stateStore = {}

    function stateStore.load(player, options)
        local owner, ownerFailure = resolve(player)
        if owner == nil then return ownerFailure end
        local root, rootFailure = readRoot()
        if root == nil then return rootFailure end
        local profiles, profileIndex = locate(root, owner, false)
        local record = profiles and profiles[profileIndex] or nil
        if record ~= nil then
            local state, stateFailure = decodeRecord(record, options)
            if state == nil then return stateFailure end
            return { ok = true, state = state }
        end
        local adopted, adoptionFailure = adoptLegacy(player, owner, root, options)
        if adoptionFailure ~= nil then return adoptionFailure end
        if adopted ~= nil then
            local state, stateFailure = decodeRecord({ state = adopted }, options)
            if state == nil then return stateFailure end
            return { ok = true, state = state }
        end
        local called, decoded = pcall(decode, nil, options)
        if not called or type(decoded) ~= "table" or rawget(decoded, "ok") ~= true
            or type(rawget(decoded, "state")) ~= "table" then
            return failure("codec_decode_failed", "fresh state")
        end
        return { ok = true, state = decoded.state }
    end

    function stateStore.save(player, state, intent)
        if intent ~= nil and intent ~= COMPLETED_DEATH_REPLACEMENT then
            return failure("invalid_save_intent", "stateStore.save")
        end
        local owner, ownerFailure = resolve(player)
        if owner == nil then return ownerFailure end
        local called, encoded = pcall(encode, state)
        if not called or type(encoded) ~= "table" or rawget(encoded, "ok") ~= true
            or type(rawget(encoded, "state")) ~= "table" then
            return failure("codec_encode_failed", "codec.encode")
        end
        local root, rootFailure = readRoot()
        if root == nil then return rootFailure end
        local profiles, profileIndex = locate(root, owner, false)
        local current = profiles and profiles[profileIndex] or nil
        if current ~= nil then
            local _, stateFailure = decodeRecord(current)
            if stateFailure ~= nil then return stateFailure end
        end
        local legacyReplacing = false
        if current == nil and intent == COMPLETED_DEATH_REPLACEMENT
            and completedPlayers[player] ~= true and legacyPresent(player) then
            local called, inspected = pcall(inspectLegacy, player)
            local legacyMetadata = called and metadata(inspected) or nil
            legacyReplacing = legacyMetadata ~= nil and legacyMetadata.initialized
                and legacyMetadata.deathRecorded
        end
        local replacing = intent == COMPLETED_DEATH_REPLACEMENT
            and completedPlayers[player] ~= true
            and ((current ~= nil and current.deathRecorded) or legacyReplacing)
        if intent == COMPLETED_DEATH_REPLACEMENT and not replacing then
            return failure("replacement_not_authorized", "completed death required")
        end
        profiles, profileIndex = locate(root, owner, true)
        profiles[profileIndex] = {
            schemaVersion = RECORD_SCHEMA,
            state = encoded.state,
            initialized = replacing or (current ~= nil and current.initialized) or false,
            deathRecorded = current ~= nil and not replacing and current.deathRecorded or false,
        }
        local written = writeRoot(root)
        if not written.ok then return written end
        return { ok = true }
    end

    local characterStore = {}

    function characterStore.inspect(player)
        local owner, ownerFailure = resolve(player)
        if owner == nil then return ownerFailure end
        local root, rootFailure = readRoot()
        if root == nil then return rootFailure end
        local profiles, profileIndex = locate(root, owner, false)
        local record = profiles and profiles[profileIndex] or nil
        if record ~= nil then
            local _, stateFailure = decodeRecord(record)
            if stateFailure ~= nil then return stateFailure end
            -- Dedicated OnNewGame receives a transient pre-DB player, not the later live object.
            local tokenValid = record.deathRecorded and completedPlayers[player] ~= true
            return {
                ok = true,
                metadata = {
                    tokenPresent = tokenValid,
                    tokenValid = tokenValid,
                    initialized = record.initialized,
                    deathRecorded = record.deathRecorded,
                    codecPresent = true,
                },
            }
        end
        local codecPresent = legacyPresent(player) == true
        local initialized, deathRecorded = false, false
        if codecPresent then
            local called, inspected = pcall(inspectLegacy, player)
            local legacyMetadata = called and metadata(inspected) or nil
            initialized = true
            deathRecorded = legacyMetadata ~= nil
                and legacyMetadata.initialized and legacyMetadata.deathRecorded or false
        end
        local tokenValid = deathRecorded and completedPlayers[player] ~= true
        return {
            ok = true,
            metadata = {
                tokenPresent = tokenValid,
                tokenValid = tokenValid,
                initialized = initialized,
                deathRecorded = deathRecorded,
                codecPresent = codecPresent,
            },
        }
    end

    function characterStore.tokenNewCharacter(player)
        if type(player) ~= "table" and type(player) ~= "userdata" then
            return failure("invalid_player", "player object required")
        end
        return { ok = true }
    end

    local function updateMetadata(player, initialized, deathRecorded)
        local owner, ownerFailure = resolve(player)
        if owner == nil then return ownerFailure end
        local root, rootFailure = readRoot()
        if root == nil then return rootFailure end
        local profiles, profileIndex = locate(root, owner, false)
        local record = profiles and profiles[profileIndex] or nil
        if record == nil then return failure("canonical_record_missing", "player record") end
        local _, stateFailure = decodeRecord(record)
        if stateFailure ~= nil then return stateFailure end
        record.initialized = initialized
        record.deathRecorded = deathRecorded
        local written = writeRoot(root)
        if not written.ok then return written end
        return { ok = true }
    end

    function characterStore.markInitialized(player, intent)
        if intent ~= nil then
            if intent ~= COMPLETED_DEATH_REPLACEMENT then
                return failure("invalid_initialize_intent", "characterStore.markInitialized")
            end
            local inspected = characterStore.inspect(player)
            if not inspected.ok then return inspected end
            if not inspected.metadata.tokenValid then
                return failure("replacement_not_authorized", "completed death required")
            end
            local updated = updateMetadata(player, true, false)
            if not updated.ok and updated.code == "canonical_record_missing" then
                local adopted = stateStore.load(player)
                if not adopted.ok then return adopted end
                updated = updateMetadata(player, true, false)
            end
            if updated.ok then completedPlayers[player] = nil end
            return updated
        end
        local updated = updateMetadata(player, true, false)
        if updated.ok then completedPlayers[player] = nil end
        return updated
    end

    function characterStore.markDeathRecorded(player)
        local owner, ownerFailure = resolve(player)
        if owner == nil then return ownerFailure end
        local root, rootFailure = readRoot()
        if root == nil then return rootFailure end
        local profiles, profileIndex = locate(root, owner, false)
        local record = profiles and profiles[profileIndex] or nil
        if record == nil or not record.initialized then
            return failure("metadata_state_invalid", "character is not initialized")
        end
        local _, stateFailure = decodeRecord(record)
        if stateFailure ~= nil then return stateFailure end
        record.deathRecorded = true
        local written = writeRoot(root)
        if not written.ok then return written end
        completedPlayers[player] = true
        return { ok = true }
    end

    return { ok = true, stateStore = stateStore, characterStore = characterStore }
end

return ServerPlayerRecordStore
