local ServerPlayerRecordStore = {}

local NAMESPACE = "SLA_ServerPlayers_v1"
local LEGACY_STATE_NAMESPACE = "SurvivorLevelingAdvancement"
local ROOT_SCHEMA = 3
local RECORD_SCHEMA = 2
local MAX_SAFE_INTEGER = 9007199254740991
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
    return type(value) == "number" and value == math.floor(value) and value >= 0 and value <= 3
end

local function safeRevision(value)
    return type(value) == "number" and value == math.floor(value)
        and value >= 0 and value <= MAX_SAFE_INTEGER
end

local function safeUsername(value)
    if type(value) ~= "string" or value == "" or #value > 64 then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then return false end
    end
    return true
end

local function safeOpaqueId(value)
    return type(value) == "string" and value ~= "" and #value <= 64
        and string.match(value, "^[%w%._:%-]+$") ~= nil
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

local function copyMailbox(value, enclosingIncarnationId)
    if value == nil then return nil, true end
    if not plain(value) then return nil, false end
    local status = rawget(value, "status")
    if status == "pending" then
        if not exact(value, {
            kind = true, status = true, incarnationId = true,
            stateRevision = true, queuedPersistenceRevision = true,
        }, 5) or rawget(value, "kind") ~= "clearAdvancementSlots"
            or not safeOpaqueId(rawget(value, "incarnationId"))
            or not safeRevision(rawget(value, "stateRevision"))
            or not safeRevision(rawget(value, "queuedPersistenceRevision")) then
            return nil, false
        end
        if enclosingIncarnationId ~= nil and value.incarnationId ~= enclosingIncarnationId then
            return nil, false
        end
        return {
            kind = "clearAdvancementSlots", status = "pending",
            incarnationId = value.incarnationId, stateRevision = value.stateRevision,
            queuedPersistenceRevision = value.queuedPersistenceRevision,
        }, true
    end
    if status == "applied" or status == "failed" or status == "cancelled" then
        if not exact(value, {
            kind = true, status = true, incarnationId = true, code = true,
        }, 4) or rawget(value, "kind") ~= "clearAdvancementSlots"
            or not safeOpaqueId(rawget(value, "incarnationId"))
            or not safeOpaqueId(rawget(value, "code")) then
            return nil, false
        end
        if enclosingIncarnationId ~= nil and value.incarnationId ~= enclosingIncarnationId then
            return nil, false
        end
        return {
            kind = "clearAdvancementSlots", status = status,
            incarnationId = value.incarnationId, code = value.code,
        }, true
    end
    return nil, false
end

local function validLegacyRecord(record)
    return exact(record, {
        schemaVersion = true, state = true, initialized = true, deathRecorded = true,
    }, 4) and rawget(record, "schemaVersion") == 1
        and plain(rawget(record, "state"))
        and type(rawget(record, "initialized")) == "boolean"
        and type(rawget(record, "deathRecorded")) == "boolean"
        and (not record.deathRecorded or record.initialized)
end

local function validRecord(record)
    local mailbox, validMailbox = copyMailbox(
        plain(record) and rawget(record, "mailbox"),
        plain(record) and rawget(record, "incarnationId")
    )
    if not validMailbox then return false end
    return exact(record, {
        schemaVersion = true, state = true, initialized = true, deathRecorded = true,
        incarnationId = true, persistenceRevision = true, mailbox = true,
    }, mailbox == nil and 6 or 7)
        and rawget(record, "schemaVersion") == RECORD_SCHEMA
        and plain(rawget(record, "state"))
        and type(rawget(record, "initialized")) == "boolean"
        and type(rawget(record, "deathRecorded")) == "boolean"
        and safeOpaqueId(rawget(record, "incarnationId"))
        and safeRevision(rawget(record, "persistenceRevision"))
        and (not record.deathRecorded or record.initialized)
end

local function generatedId(generator, username, profileIndex, reason, previous)
    local called, value = pcall(generator, {
        username = username, profileIndex = profileIndex, reason = reason,
        previousIncarnationId = previous,
    })
    if not called or not safeOpaqueId(value) or value == previous then return nil end
    return value
end

local function copyRoot(raw, generator)
    if empty(raw) then
        local worldId = generatedId(generator, nil, nil, "world_identity", nil)
        if worldId == nil then return nil, false, "world_identity_generation_failed" end
        return { schemaVersion = ROOT_SCHEMA, worldId = worldId, players = {} }, true
    end
    if not plain(raw) then return nil, false, "invalid_root" end
    local schema = rawget(raw, "schemaVersion")
    if type(schema) == "number" and schema > ROOT_SCHEMA then
        return nil, false, "newer_root"
    end
    local expected = schema == ROOT_SCHEMA
        and { schemaVersion = true, worldId = true, players = true }
        or { schemaVersion = true, players = true }
    local expectedCount = schema == ROOT_SCHEMA and 3 or 2
    if not exact(raw, expected, expectedCount)
        or (schema ~= 1 and schema ~= 2 and schema ~= ROOT_SCHEMA)
        or not plain(rawget(raw, "players"))
        or (schema == ROOT_SCHEMA and not safeOpaqueId(rawget(raw, "worldId"))) then
        return nil, false, "invalid_root"
    end
    local migratedRecords = schema == 1
    local migrated = schema ~= ROOT_SCHEMA
    local worldId = rawget(raw, "worldId")
    if worldId == nil then
        worldId = generatedId(generator, nil, nil, "world_identity", nil)
        if worldId == nil then return nil, false, "world_identity_generation_failed" end
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
            if migratedRecords then
                if not validLegacyRecord(record) then return nil, false, "invalid_record" end
                local incarnationId = generatedId(generator, username, profileIndex, "migration", nil)
                if incarnationId == nil then return nil, false, "incarnation_generation_failed" end
                copiedProfiles[profileIndex] = {
                    schemaVersion = RECORD_SCHEMA, state = record.state,
                    initialized = record.initialized, deathRecorded = record.deathRecorded,
                    incarnationId = incarnationId,
                    persistenceRevision = safeRevision(rawget(record.state, "revision"))
                        and rawget(record.state, "revision") or 0,
                }
            else
                if not validRecord(record) then return nil, false, "invalid_record" end
                local mailbox = copyMailbox(record.mailbox, record.incarnationId)
                copiedProfiles[profileIndex] = {
                    schemaVersion = RECORD_SCHEMA, state = record.state,
                    initialized = record.initialized, deathRecorded = record.deathRecorded,
                    incarnationId = record.incarnationId,
                    persistenceRevision = record.persistenceRevision,
                    mailbox = mailbox,
                }
            end
        end
        copiedPlayers[username] = copiedProfiles
    end
    return { schemaVersion = ROOT_SCHEMA, worldId = worldId, players = copiedPlayers }, migrated
end

local function copyOwner(result)
    if not exact(result, { ok = true, owner = true }, 2) or rawget(result, "ok") ~= true then
        return nil
    end
    local owner = rawget(result, "owner")
    if not exact(owner, { kind = true, primaryLoginUsername = true, profileIndex = true }, 3)
        or rawget(owner, "kind") ~= "mp"
        or not safeUsername(rawget(owner, "primaryLoginUsername"))
        or not safeProfile(rawget(owner, "profileIndex")) then return nil end
    return { primaryLoginUsername = owner.primaryLoginUsername, profileIndex = owner.profileIndex }
end

local function metadata(result)
    if not exact(result, { ok = true, metadata = true }, 2) or rawget(result, "ok") ~= true then
        return nil
    end
    local value = rawget(result, "metadata")
    if not exact(value, {
        tokenPresent = true, tokenValid = true, initialized = true,
        deathRecorded = true, codecPresent = true,
    }, 5) then return nil end
    for _, key in ipairs({
        "tokenPresent", "tokenValid", "initialized", "deathRecorded", "codecPresent",
    }) do if type(rawget(value, key)) ~= "boolean" then return nil end end
    return value
end

function ServerPlayerRecordStore.create(dependencies)
    if not plain(dependencies) then return failure("invalid_dependencies", "exact dependencies required") end
    local dependencyCount = 0
    for key in pairs(dependencies) do
        if key ~= "codec" and key ~= "identity" and key ~= "legacyStateStore"
            and key ~= "legacyCharacterStore" and key ~= "getOrCreate" and key ~= "add"
            and key ~= "generateIncarnationId" then
            return failure("invalid_dependencies", "exact dependencies required")
        end
        dependencyCount = dependencyCount + 1
    end
    if dependencyCount ~= 6 and dependencyCount ~= 7 then
        return failure("invalid_dependencies", "exact dependencies required")
    end
    local codec, identity = dependencies.codec, dependencies.identity
    local legacyStateStore, legacyCharacterStore = dependencies.legacyStateStore,
        dependencies.legacyCharacterStore
    local getOrCreate, add = dependencies.getOrCreate, dependencies.add
    local generateIncarnationId = dependencies.generateIncarnationId
    if generateIncarnationId == nil then
        local fallbackCounter = 0
        generateIncarnationId = function(context)
            local previous = type(context) == "table" and context.previousIncarnationId or nil
            repeat
                fallbackCounter = fallbackCounter + 1
                local candidate = "sla:" .. tostring(fallbackCounter)
                if candidate ~= previous then return candidate end
            until fallbackCounter >= MAX_SAFE_INTEGER
            return nil
        end
    end
    if not plain(codec) or type(rawget(codec, "decode")) ~= "function"
        or type(rawget(codec, "encode")) ~= "function"
        or not plain(identity) or type(rawget(identity, "resolve")) ~= "function"
        or not plain(legacyStateStore) or type(rawget(legacyStateStore, "load")) ~= "function"
        or not plain(legacyCharacterStore) or type(rawget(legacyCharacterStore, "inspect")) ~= "function"
        or type(getOrCreate) ~= "function" or type(add) ~= "function"
        or type(generateIncarnationId) ~= "function" then
        return failure("invalid_dependencies", "store capabilities required")
    end
    local sourceGenerator = generateIncarnationId
    local generationGuard = {}
    generateIncarnationId = function(context)
        local called, value = pcall(sourceGenerator, context)
        local previous = plain(context) and rawget(context, "previousIncarnationId") or nil
        if not called or not safeOpaqueId(value) or value == previous or generationGuard[value] then
            return nil
        end
        generationGuard[value] = true
        return value
    end
    local decode, encode = codec.decode, codec.encode
    local resolveIdentity, loadLegacy, inspectLegacy = identity.resolve,
        legacyStateStore.load, legacyCharacterStore.inspect
    local completedPlayers = {}
    local completedByOwner = {}
    local completedOwnerByPlayer = {}

    local function clearCompleted(owner, player)
        local username = owner.primaryLoginUsername
        local bucket = completedByOwner[username]
        if bucket ~= nil then
            local completed = bucket[owner.profileIndex]
            if completed ~= nil then
                completedPlayers[completed] = nil
                completedOwnerByPlayer[completed] = nil
            end
            bucket[owner.profileIndex] = nil
            if empty(bucket) then completedByOwner[username] = nil end
        end
        if player ~= nil then
            completedPlayers[player] = nil
            completedOwnerByPlayer[player] = nil
        end
    end

    local function recordCompleted(owner, player)
        local username = owner.primaryLoginUsername
        local bucket = completedByOwner[username]
        if bucket == nil then
            bucket = {}
            completedByOwner[username] = bucket
        end
        local prior = bucket[owner.profileIndex]
        if prior ~= nil and prior ~= player then
            completedPlayers[prior] = nil
            completedOwnerByPlayer[prior] = nil
        end
        bucket[owner.profileIndex] = player
        completedPlayers[player] = true
        completedOwnerByPlayer[player] = {
            primaryLoginUsername = owner.primaryLoginUsername,
            profileIndex = owner.profileIndex,
        }
    end

    local function resolve(player)
        local called, result = pcall(resolveIdentity, player)
        if not called then return nil, failure("identity_threw", "identity.resolve") end
        local owner = copyOwner(result)
        if owner == nil then return nil, failure("identity_invalid", "identity.resolve") end
        return owner, nil
    end

    local function accountStamp(profiles)
        local result = {}
        for index = 0, 3 do
            local record = profiles and profiles[index]
            if record ~= nil then result[index] = { source = record,
                schemaVersion = record.schemaVersion, state = record.state,
                incarnationId = record.incarnationId, persistenceRevision = record.persistenceRevision,
                initialized = record.initialized, deathRecorded = record.deathRecorded,
                mailbox = record.mailbox } end
        end
        return result
    end

    local function accountMatches(profiles, stamps)
        if profiles ~= nil then
            if not plain(profiles) then return false end
            for index in pairs(profiles) do if not safeProfile(index) then return false end end
        end
        for index = 0, 3 do
            local record, stamp = profiles and profiles[index], stamps[index]
            if stamp == nil then
                if record ~= nil then return false end
            elseif record ~= stamp.source or not validRecord(record)
                or record.schemaVersion ~= stamp.schemaVersion
                or record.state ~= stamp.state or record.incarnationId ~= stamp.incarnationId
                or record.persistenceRevision ~= stamp.persistenceRevision
                or record.initialized ~= stamp.initialized or record.deathRecorded ~= stamp.deathRecorded
                or record.mailbox ~= stamp.mailbox then return false end
        end
        return true
    end

    local function writeRoot(root, scope)
        local target, previous = root, nil
        if scope ~= nil then
            local readCalled, current = pcall(getOrCreate, NAMESPACE)
            if not readCalled or current ~= scope.root or current.players ~= scope.players
                or current.players[scope.username] ~= scope.previous
                or not exact(current, { schemaVersion = true, worldId = true, players = true }, 3)
                or not plain(current.players) or current.schemaVersion ~= ROOT_SCHEMA or current.worldId ~= scope.worldId
                or not accountMatches(scope.previous, scope.stamps) then
                return failure("global_compare_failed", NAMESPACE)
            end
            target, previous = current, current.players[scope.username]
            target.players[scope.username] = root.players[scope.username]
        end
        local published = scope and accountStamp(target.players[scope.username])
        local called, accepted = pcall(add, NAMESPACE, target)
        if not called or accepted == false then
            if scope ~= nil then
                local readCalled, current = pcall(getOrCreate, NAMESPACE)
                if (not readCalled or current == target) and target.players == scope.players
                    and target.players[scope.username] == root.players[scope.username]
                    and accountMatches(target.players[scope.username], published) then
                    target.players[scope.username] = previous
                end
            end
            return failure("global_write_failed", NAMESPACE)
        end
        return { ok = true }
    end

    local function readOwner(raw, username)
        if not exact(raw, { schemaVersion = true, worldId = true, players = true }, 3)
            or raw.schemaVersion ~= ROOT_SCHEMA or not plain(raw.players)
            or not safeOpaqueId(raw.worldId) then return nil, failure("invalid_root", NAMESPACE) end
        local profiles = raw.players[username]
        local selected = profiles == nil and {} or { [username] = profiles }
        local copied, _, code = copyRoot({ schemaVersion = ROOT_SCHEMA,
            worldId = raw.worldId, players = selected }, function() return nil end)
        if copied == nil then return nil, failure(code, NAMESPACE) end
        generationGuard = { [raw.worldId] = true }
        for _, record in pairs(copied.players[username] or {}) do
            generationGuard[record.incarnationId] = true
        end
        local scope = { root = raw, players = raw.players,
            username = username, previous = profiles, worldId = raw.worldId,
            stamps = accountStamp(profiles) }
        return copied, nil, scope
    end

    local function readRoot(owner)
        local called, raw = pcall(getOrCreate, NAMESPACE)
        if not called or raw == nil then return nil, failure("global_read_failed", NAMESPACE) end
        if owner ~= nil and plain(raw) and raw.schemaVersion == ROOT_SCHEMA then
            if not exact(raw, { schemaVersion = true, worldId = true, players = true }, 3)
                or not plain(raw.players) or not safeOpaqueId(raw.worldId) then
                return nil, failure("invalid_root", NAMESPACE)
            end
            local username = type(owner) == "table" and owner.primaryLoginUsername or owner
            return readOwner(raw, username)
        end
        if not empty(raw) then
            if not plain(raw) then return nil, failure("invalid_root", NAMESPACE) end
            local schema = rawget(raw, "schemaVersion")
            if type(schema) == "number" and schema > ROOT_SCHEMA then
                return nil, failure("newer_root", NAMESPACE)
            end
            if (schema ~= 1 and schema ~= 2)
                or not exact(raw, { schemaVersion = true, players = true }, 2)
                or not plain(raw.players) then return nil, failure("invalid_root", NAMESPACE) end
        end
        generationGuard = {}
        if plain(raw) then
            local rawWorldId = rawget(raw, "worldId")
            if safeOpaqueId(rawWorldId) then generationGuard[rawWorldId] = true end
            local rawPlayers = rawget(raw, "players")
            if plain(rawPlayers) then
                for _, profiles in pairs(rawPlayers) do
                    if plain(profiles) then
                        for _, record in pairs(profiles) do
                            local incarnationId = plain(record) and rawget(record, "incarnationId") or nil
                            if safeOpaqueId(incarnationId) then generationGuard[incarnationId] = true end
                        end
                    end
                end
            end
        end
        local root, migrated, code = copyRoot(raw, generateIncarnationId)
        if root == nil then return nil, failure(code, NAMESPACE) end
        if migrated then
            local written = writeRoot(root)
            if not written.ok then return nil, written end
        end
        local username = type(owner) == "table" and owner.primaryLoginUsername or owner
        return readOwner(root, username)
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

    local function adoptLegacy(player, owner, root, scope, options)
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
        local incarnationId = generatedId(
            generateIncarnationId, owner.primaryLoginUsername, profileIndex, "legacy_adoption", nil
        )
        if incarnationId == nil then return nil, failure("incarnation_generation_failed", "legacy adoption") end
        profiles[profileIndex] = {
            schemaVersion = RECORD_SCHEMA, state = encoded.state,
            initialized = initialized, deathRecorded = deathRecorded,
            incarnationId = incarnationId,
            persistenceRevision = safeRevision(rawget(loaded.state, "revision"))
                and rawget(loaded.state, "revision") or 0,
        }
        local written = writeRoot(root, scope)
        if not written.ok then return nil, written end
        return encoded.state, nil
    end

    local stateStore = {}

    function stateStore.load(player, options)
        local owner, ownerFailure = resolve(player)
        if owner == nil then return ownerFailure end
        local root, rootFailure, scope = readRoot(owner)
        if root == nil then return rootFailure end
        local profiles, profileIndex = locate(root, owner, false)
        local record = profiles and profiles[profileIndex] or nil
        if record ~= nil then
            local state, stateFailure = decodeRecord(record, options)
            if state == nil then return stateFailure end
            return { ok = true, state = state }
        end
        local adopted, adoptionFailure = adoptLegacy(player, owner, root, scope, options)
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
        local root, rootFailure, scope = readRoot(owner)
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
            local inspectedCalled, inspected = pcall(inspectLegacy, player)
            local legacyMetadata = inspectedCalled and metadata(inspected) or nil
            legacyReplacing = legacyMetadata ~= nil and legacyMetadata.initialized
                and legacyMetadata.deathRecorded
        end
        local replacing = intent == COMPLETED_DEATH_REPLACEMENT
            and completedPlayers[player] ~= true
            and ((current ~= nil and current.deathRecorded) or legacyReplacing)
        if intent == COMPLETED_DEATH_REPLACEMENT and not replacing then
            return failure("replacement_not_authorized", "completed death required")
        end
        local incarnationId = current and current.incarnationId or nil
        if replacing or incarnationId == nil then
            incarnationId = generatedId(
                generateIncarnationId, owner.primaryLoginUsername, owner.profileIndex,
                replacing and "completed_death_replacement" or "fresh_record",
                current and current.incarnationId or nil
            )
            if incarnationId == nil then return failure("incarnation_generation_failed", "stateStore.save") end
        end
        local persistenceRevision = current and current.persistenceRevision or 0
        if persistenceRevision == MAX_SAFE_INTEGER then
            return failure("persistence_revision_overflow", "stateStore.save")
        end
        local nextMailbox = current and current.mailbox or nil
        if replacing then nextMailbox = nil end
        profiles, profileIndex = locate(root, owner, true)
        profiles[profileIndex] = {
            schemaVersion = RECORD_SCHEMA, state = encoded.state,
            initialized = replacing or (current ~= nil and current.initialized) or false,
            deathRecorded = current ~= nil and not replacing and current.deathRecorded or false,
            incarnationId = incarnationId, persistenceRevision = persistenceRevision + 1,
            mailbox = nextMailbox,
        }
        local written = writeRoot(root, scope)
        if not written.ok then return written end
        if replacing then clearCompleted(owner, player) end
        return { ok = true }
    end

    function stateStore.clearPlayer(player)
        if player == nil then return failure("invalid_player", "player object required") end
        local owner = completedOwnerByPlayer[player]
        if owner == nil then owner = resolve(player) end
        if owner ~= nil then
            local bucket = completedByOwner[owner.primaryLoginUsername]
            if bucket ~= nil and bucket[owner.profileIndex] == player then
                clearCompleted(owner, player)
            else
                completedPlayers[player] = nil
                completedOwnerByPlayer[player] = nil
            end
        else
            completedPlayers[player] = nil
            completedOwnerByPlayer[player] = nil
        end
        return { ok = true }
    end

    local characterStore = {}

    function characterStore.inspect(player)
        local owner, ownerFailure = resolve(player)
        if owner == nil then return ownerFailure end
        local root, rootFailure = readRoot(owner)
        if root == nil then return rootFailure end
        local profiles, profileIndex = locate(root, owner, false)
        local record = profiles and profiles[profileIndex] or nil
        if record ~= nil then
            local _, stateFailure = decodeRecord(record)
            if stateFailure ~= nil then return stateFailure end
            local tokenValid = record.deathRecorded and completedPlayers[player] ~= true
            return { ok = true, metadata = {
                tokenPresent = tokenValid, tokenValid = tokenValid,
                initialized = record.initialized, deathRecorded = record.deathRecorded,
                codecPresent = true,
            } }
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
        return { ok = true, metadata = {
            tokenPresent = tokenValid, tokenValid = tokenValid,
            initialized = initialized, deathRecorded = deathRecorded,
            codecPresent = codecPresent,
        } }
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
        local root, rootFailure, scope = readRoot(owner)
        if root == nil then return rootFailure end
        local profiles, profileIndex = locate(root, owner, false)
        local record = profiles and profiles[profileIndex] or nil
        if record == nil then return failure("canonical_record_missing", "player record") end
        local _, stateFailure = decodeRecord(record)
        if stateFailure ~= nil then return stateFailure end
        if record.persistenceRevision == MAX_SAFE_INTEGER then
            return failure("persistence_revision_overflow", "metadata")
        end
        record.initialized, record.deathRecorded = initialized, deathRecorded
        record.persistenceRevision = record.persistenceRevision + 1
        local written = writeRoot(root, scope)
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
            if updated.ok then
                local owner = resolve(player)
                if owner ~= nil then clearCompleted(owner, player) end
            end
            return updated
        end
        local updated = updateMetadata(player, true, false)
        if updated.ok then completedPlayers[player] = nil end
        return updated
    end

    function characterStore.markDeathRecorded(player)
        local owner, ownerFailure = resolve(player)
        if owner == nil then return ownerFailure end
        local root, rootFailure, scope = readRoot(owner)
        if root == nil then return rootFailure end
        local profiles, profileIndex = locate(root, owner, false)
        local record = profiles and profiles[profileIndex] or nil
        if record == nil or not record.initialized then
            return failure("metadata_state_invalid", "character is not initialized")
        end
        local _, stateFailure = decodeRecord(record)
        if stateFailure ~= nil then return stateFailure end
        if record.persistenceRevision == MAX_SAFE_INTEGER then
            return failure("persistence_revision_overflow", "death")
        end
        record.deathRecorded = true
        if record.mailbox ~= nil and record.mailbox.status == "pending" then
            record.mailbox = {
                kind = "clearAdvancementSlots", status = "cancelled",
                incarnationId = record.incarnationId, code = "profile_died",
            }
        end
        record.persistenceRevision = record.persistenceRevision + 1
        local written = writeRoot(root, scope)
        if not written.ok then return written end
        recordCompleted(owner, player)
        return { ok = true }
    end

    function characterStore.clearPlayer(player)
        return stateStore.clearPlayer(player)
    end

    local offlineStore = {}

    local function copyOfflineRecord(username, profileIndex, record, options)
        local state, stateFailure = decodeRecord(record, options)
        if state == nil then return nil, stateFailure end
        local mailbox = copyMailbox(record.mailbox, record.incarnationId)
        return {
            username = username, profileIndex = profileIndex,
            incarnationId = record.incarnationId,
            persistenceRevision = record.persistenceRevision,
            initialized = record.initialized, deathRecorded = record.deathRecorded,
            state = state, mailbox = mailbox,
        }, nil
    end

    function offlineStore.enumerate(username, options)
        if not safeUsername(username) then return failure("invalid_username", "username") end
        local root, rootFailure = readRoot(username)
        if root == nil then return rootFailure end
        local result, profiles = {}, root.players[username]
        if profiles ~= nil then
            for profileIndex = 0, 3 do
                local record = profiles[profileIndex]
                if record ~= nil then
                    local copied, copiedFailure = copyOfflineRecord(username, profileIndex, record, options)
                    if copied == nil then return copiedFailure end
                    result[#result + 1] = copied
                end
            end
        end
        return { ok = true, profiles = result }
    end

    local function validSelector(selector)
        return exact(selector, {
            username = true, profileIndex = true, incarnationId = true,
        }, 3) and safeUsername(selector.username) and safeProfile(selector.profileIndex)
            and safeOpaqueId(selector.incarnationId)
    end

    function offlineStore.inspect(selector, options)
        if not validSelector(selector) then return failure("invalid_selector", "offline profile") end
        local root, rootFailure, scope = readRoot(selector.username)
        if root == nil then return rootFailure end
        local profiles = root.players[selector.username]
        local record = profiles and profiles[selector.profileIndex] or nil
        if record == nil then return failure("profile_missing", "offline profile") end
        if record.incarnationId ~= selector.incarnationId then
            return failure("incarnation_mismatch", "offline profile")
        end
        local copied, copiedFailure = copyOfflineRecord(
            selector.username, selector.profileIndex, record, options
        )
        if copied == nil then return copiedFailure end
        return { ok = true, record = copied }
    end

    function offlineStore.replace(selector, expectedRevision, state, mailbox)
        if not validSelector(selector) then return failure("invalid_selector", "offline profile") end
        if not safeRevision(expectedRevision) then return failure("invalid_revision", "offline profile") end
        local copiedMailbox, mailboxValid = copyMailbox(mailbox, selector.incarnationId)
        if not mailboxValid then return failure("invalid_mailbox", "offline profile") end
        local encodedCalled, encoded = pcall(encode, state)
        if not encodedCalled or type(encoded) ~= "table" or rawget(encoded, "ok") ~= true
            or type(rawget(encoded, "state")) ~= "table" then
            return failure("codec_encode_failed", "offline profile")
        end
        local root, rootFailure, scope = readRoot(selector.username)
        if root == nil then return rootFailure end
        local profiles = root.players[selector.username]
        local record = profiles and profiles[selector.profileIndex] or nil
        if record == nil then return failure("profile_missing", "offline profile") end
        if record.incarnationId ~= selector.incarnationId then
            return failure("incarnation_mismatch", "offline profile")
        end
        if copiedMailbox ~= nil and copiedMailbox.incarnationId ~= record.incarnationId then
            return failure("invalid_mailbox", "offline profile")
        end
        if record.persistenceRevision ~= expectedRevision then
            local latest, latestFailure = copyOfflineRecord(
                selector.username, selector.profileIndex, record
            )
            if latest == nil then return latestFailure end
            return { ok = true, saved = false, code = "stale_revision", record = latest }
        end
        if expectedRevision == MAX_SAFE_INTEGER then
            return failure("persistence_revision_overflow", "offline profile")
        end
        record.state, record.mailbox = encoded.state, copiedMailbox
        record.persistenceRevision = expectedRevision + 1
        local written = writeRoot(root, scope)
        if not written.ok then return written end
        local saved, savedFailure = copyOfflineRecord(selector.username, selector.profileIndex, record)
        if saved == nil then return savedFailure end
        return { ok = true, saved = true, record = saved }
    end

    function offlineStore.resolvePlayer(player)
        local owner, ownerFailure = resolve(player)
        if owner == nil then return ownerFailure end
        return { ok = true, profile = {
            username = owner.primaryLoginUsername, profileIndex = owner.profileIndex,
        } }
    end


    return {
        ok = true, stateStore = stateStore,
        characterStore = characterStore, offlineStore = offlineStore,
    }
end

return ServerPlayerRecordStore
