local InheritanceSession = {}

local MAX_SAFE_INTEGER = 9007199254740991
local STATE_SCHEMA_VERSION = 3
local COMPLETED_DEATH_REPLACEMENT = "completed_death_replacement"

local function failure(code, detail, committed)
    local result = { ok = false, code = code, detail = detail }
    if committed ~= nil then result.committed = committed end
    return result
end

local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function exact(value, fields)
    if not plain(value) then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "string" or not fields[key] then return false end
        count = count + 1
    end
    local required = 0
    for key in pairs(fields) do
        required = required + 1
        if rawget(value, key) == nil then return false end
    end
    return count == required
end

local function safeInteger(value)
    return type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value >= 0 and value <= MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function emptyMap(value)
    if not plain(value) then return false end
    for _ in pairs(value) do return false end
    return true
end

local function boundedFailure(operation, kind, result, committed)
    local code = operation .. "_" .. kind
    local detail = operation
    if kind == "failed" and type(result) == "table" then
        local upstream = rawget(result, "code")
        if type(upstream) == "string" and #upstream > 0 and #upstream <= 64
            and upstream:match("^[%w%._:%-]+$") then detail = upstream end
    end
    return failure(code, detail, committed)
end

local function invoke(operation, callable, ...)
    local called, result = pcall(callable, ...)
    if not called then return nil, boundedFailure(operation, "threw") end
    if type(result) ~= "table" or rawget(result, "ok") ~= true then
        return nil, boundedFailure(operation, "failed", result)
    end
    return result, nil
end

local function validateMetadata(result)
    if not exact(result, { ok = true, metadata = true }) or rawget(result, "ok") ~= true then return nil end
    local metadata = rawget(result, "metadata")
    if not exact(metadata, {
        tokenPresent = true, tokenValid = true, initialized = true,
        deathRecorded = true, codecPresent = true,
    }) then return nil end
    for _, key in ipairs({ "tokenPresent", "tokenValid", "initialized", "deathRecorded", "codecPresent" }) do
        if type(rawget(metadata, key)) ~= "boolean" then return nil end
    end
    if metadata.tokenValid and not metadata.tokenPresent then return nil end
    return metadata
end

local function validateSettings(result)
    if not exact(result, { ok = true, settings = true }) or rawget(result, "ok") ~= true then return nil end
    local settings = rawget(result, "settings")
    if not exact(settings, { enabled = true, retainedRatio = true })
        or type(settings.enabled) ~= "boolean"
        or type(settings.retainedRatio) ~= "number" or settings.retainedRatio ~= settings.retainedRatio
        or settings.retainedRatio == math.huge or settings.retainedRatio == -math.huge
        or settings.retainedRatio < 0 or settings.retainedRatio > 1 then return nil end
    return settings
end

local function validateOwner(result)
    if type(result) ~= "table" or getmetatable(result) ~= nil or rawget(result, "ok") ~= true
        or type(rawget(result, "owner")) ~= "table" then return nil end
    local owner = rawget(result, "owner")
    if rawget(owner, "kind") == "sp"
        and exact(owner, { kind = true, profileIndex = true })
        and safeInteger(rawget(owner, "profileIndex")) and owner.profileIndex <= 3 then
        return { kind = "sp", profileIndex = owner.profileIndex }
    end
    if rawget(owner, "kind") ~= "mp"
        or not exact(owner, { kind = true, primaryLoginUsername = true, profileIndex = true })
        or not safeInteger(rawget(owner, "profileIndex")) or owner.profileIndex > 3 then return nil end
    local username = rawget(owner, "primaryLoginUsername")
    if type(username) ~= "string" or #username == 0 or #username > 64 then return nil end
    for index = 1, #username do
        local byte = string.byte(username, index)
        if byte < 32 or byte == 127 then return nil end
    end
    return { kind = "mp", primaryLoginUsername = username, profileIndex = owner.profileIndex }
end

function InheritanceSession.create(dependencies)
    if not plain(dependencies) then return failure("invalid_dependencies", "dependencies") end
    local required = {
        { "authority", "describe" }, { "playerIdentity", "isPlayer" },
        { "characterStore", "inspect" }, { "characterStore", "tokenNewCharacter" },
        { "characterStore", "markInitialized" }, { "characterStore", "markDeathRecorded" },
        { "stateStore", "load" }, { "stateStore", "save" },
        { "recordStore", "peek" }, { "recordStore", "consume" }, { "recordStore", "put" },
        { "identity", "resolve" }, { "inheritanceSettings", "resolve" },
        { "StateCodec", "fresh" }, { "InheritancePolicy", "plan" },
    }
    for index = 1, #required do
        local owner, name = rawget(dependencies, required[index][1]), required[index][2]
        if type(owner) ~= "table" or type(rawget(owner, name)) ~= "function" then
            return failure("invalid_dependencies", required[index][1] .. "." .. name)
        end
    end

    local authority = rawget(dependencies, "authority")
    local playerIdentity = rawget(dependencies, "playerIdentity")
    local characterStore = rawget(dependencies, "characterStore")
    local stateStore = rawget(dependencies, "stateStore")
    local recordStore = rawget(dependencies, "recordStore")
    local identity = rawget(dependencies, "identity")
    local inheritanceSettings = rawget(dependencies, "inheritanceSettings")
    local StateCodec = rawget(dependencies, "StateCodec")
    local InheritancePolicy = rawget(dependencies, "InheritancePolicy")
    local authorityDescribe = rawget(authority, "describe")
    local isPlayer = rawget(playerIdentity, "isPlayer")
    local inspectMetadata = rawget(characterStore, "inspect")
    local writeToken = rawget(characterStore, "tokenNewCharacter")
    local writeInitialized = rawget(characterStore, "markInitialized")
    local writeDeathRecorded = rawget(characterStore, "markDeathRecorded")
    local loadState, saveState = rawget(stateStore, "load"), rawget(stateStore, "save")
    local peekPending = rawget(recordStore, "peek")
    local consumePending, putPending = rawget(recordStore, "consume"), rawget(recordStore, "put")
    local resolveIdentity = rawget(identity, "resolve")
    local resolveSettings = rawget(inheritanceSettings, "resolve")
    local freshState, planInheritance = rawget(StateCodec, "fresh"), rawget(InheritancePolicy, "plan")
    local session = {}
    local recordedDeaths = setmetatable({}, { __mode = "k" })

    local function requireAuthority()
        local result, err = invoke("authority", authorityDescribe)
        if result == nil then return err end
        if not exact(result, { ok = true, authoritative = true })
            or type(rawget(result, "authoritative")) ~= "boolean" then
            return failure("authority_invalid", "authority.describe")
        end
        if not result.authoritative then return failure("not_authoritative", "inheritance mutation") end
        return nil
    end

    local function inspect(player)
        local result, err = invoke("metadata_inspect", inspectMetadata, player)
        if result == nil then return nil, err end
        local metadata = validateMetadata(result)
        if metadata == nil then return nil, failure("metadata_inspect_invalid", "characterStore.inspect") end
        return metadata, nil
    end

    local function markInitialized(player, committed, intent)
        local result, err = invoke("metadata_initialize", writeInitialized, player, intent)
        if result == nil then
            if committed ~= nil then err.committed = committed end
            return err
        end
        if not exact(result, { ok = true }) then return failure("metadata_initialize_invalid", "characterStore.markInitialized", committed) end
        return nil
    end

    local function fresh(level)
        local called, state = pcall(freshState)
        local survivor = called and plain(state) and rawget(state, "survivor") or nil
        if not exact(state, {
                schemaVersion = true, accountingMode = true, revision = true,
                survivor = true, perks = true, orphanedPerks = true,
            }) or rawget(state, "schemaVersion") ~= STATE_SCHEMA_VERSION
            or not exact(survivor, { level = true, xpIntoLevel = true, spent = true })
            or rawget(survivor, "level") ~= 0
            or not safeInteger(level) then return nil, failure("fresh_state_invalid", "StateCodec.fresh") end
        rawset(survivor, "level", level)
        if rawget(survivor, "xpIntoLevel") ~= 0 or rawget(survivor, "spent") ~= 0
            or rawget(state, "revision") ~= 0 or rawget(state, "accountingMode") ~= "Tracked"
            or not emptyMap(rawget(state, "perks")) or not emptyMap(rawget(state, "orphanedPerks"))
            or rawget(state, "inFlightAdvancement") ~= nil then
            return nil, failure("fresh_state_invalid", "StateCodec.fresh")
        end
        return state, nil
    end

    local function saveFreshAndMark(player, level, outcome, consumed, replacing)
        local state, stateFailure = fresh(level)
        if state == nil then return stateFailure end
        local intent = replacing and COMPLETED_DEATH_REPLACEMENT or nil
        local saved, saveFailure = invoke("state_save", saveState, player, state, intent)
        if saved == nil then
            if consumed then saveFailure.committed = true end
            return saveFailure
        end
        if not exact(saved, { ok = true }) then return failure("state_save_invalid", "stateStore.save", consumed or nil) end
        local markerFailure = markInitialized(player, true)
        if markerFailure ~= nil then return markerFailure end
        return { ok = true, outcome = outcome, survivorLevel = level, consumed = consumed == true }
    end

    local function terminalizeAndSave(player, level, outcome, consumed, replacing)
        local intent = replacing and COMPLETED_DEATH_REPLACEMENT or nil
        local markerFailure = markInitialized(player, true, intent)
        if markerFailure ~= nil then return markerFailure end
        local state, stateFailure = fresh(level)
        if state == nil then stateFailure.committed = true; return stateFailure end
        local saved, saveFailure = invoke("state_save", saveState, player, state)
        if saved == nil then saveFailure.committed = true; return saveFailure end
        if not exact(saved, { ok = true }) then
            return failure("state_save_invalid", "stateStore.save", true)
        end
        return { ok = true, outcome = outcome, survivorLevel = level, consumed = consumed == true }
    end

    function session.tokenNewCharacter(player)
        local authorityFailure = requireAuthority()
        if authorityFailure ~= nil then return authorityFailure end
        local result, err = invoke("metadata_token", writeToken, player)
        if result == nil then return err end
        if not exact(result, { ok = true }) then return failure("metadata_token_invalid", "characterStore.tokenNewCharacter") end
        return { ok = true }
    end

    function session.initialize(player)
        local authorityFailure = requireAuthority()
        if authorityFailure ~= nil then return authorityFailure end
        local metadata, metadataFailure = inspect(player)
        if metadata == nil then return metadataFailure end
        if not metadata.tokenValid and (metadata.codecPresent or metadata.initialized) then
            if not metadata.initialized then
                local markerFailure = markInitialized(player)
                if markerFailure ~= nil then return markerFailure end
            end
            return { ok = true, outcome = "existing", survivorLevel = 0, consumed = false }
        end
        if not metadata.tokenValid then
            return saveFreshAndMark(player, 0, "fresh", false)
        end

        local settingsResult, settingsFailure = invoke("inheritance_settings", resolveSettings, player)
        if settingsResult == nil then return settingsFailure end
        local settings = validateSettings(settingsResult)
        if settings == nil then return failure("inheritance_settings_invalid", "inheritanceSettings.resolve") end
        if not settings.enabled then return saveFreshAndMark(player, 0, "fresh", false, true) end

        local identityResult, identityFailure = invoke("identity", resolveIdentity, player)
        if identityResult == nil then return identityFailure end
        local owner = validateOwner(identityResult)
        if owner == nil then return failure("identity_invalid", "identity.resolve") end
        local peeked, peekFailure = invoke("pending_peek", peekPending, owner)
        if peeked == nil then return peekFailure end
        if exact(peeked, { ok = true, found = true }) and peeked.found == false then
            return saveFreshAndMark(player, 0, "fresh", false, true)
        end
        if not exact(peeked, { ok = true, found = true, record = true }) or peeked.found ~= true
            or type(peeked.record) ~= "table" then
            return failure("pending_peek_invalid", "recordStore.peek")
        end
        local planned, policyFailure = invoke("policy", planInheritance, {
            initializationStatus = "genuine_new",
            enabled = true,
            retainedRatio = settings.retainedRatio,
            pendingDeadLevel = rawget(peeked.record, "deadSurvivorLevel"),
            tokenStatus = "valid",
        })
        if planned == nil then return policyFailure end
        if not exact(planned, {
            ok = true, outcome = true, consumePending = true, survivorLevel = true,
        }) or planned.outcome ~= "inherit" or planned.consumePending ~= true
            or not safeInteger(planned.survivorLevel) then
            return failure("policy_invalid", "InheritancePolicy.plan")
        end
        local consumedResult, consumeFailure = invoke(
            "pending_consume", consumePending, owner, peeked.record
        )
        if consumedResult == nil then return consumeFailure end
        if exact(consumedResult, { ok = true, consumed = true }) and consumedResult.consumed == false then
            return terminalizeAndSave(player, 0, "fresh", false, true)
        end
        if not exact(consumedResult, { ok = true, consumed = true, record = true })
            or consumedResult.consumed ~= true then
            return failure("pending_consume_invalid", "recordStore.consume")
        end
        return terminalizeAndSave(player, planned.survivorLevel, "inherit", true, true)
    end

    function session.recordDeath(player)
        if player ~= nil and recordedDeaths[player] then
            return { ok = true, recorded = false, alreadyRecorded = true }
        end
        local identityCalled, playerAccepted = pcall(isPlayer, player)
        if not identityCalled then return failure("player_identity_threw", "playerIdentity.isPlayer") end
        if type(playerAccepted) ~= "boolean" then return failure("player_identity_invalid", "playerIdentity.isPlayer") end
        if not playerAccepted then return { ok = true, recorded = false, ignored = true } end
        local authorityFailure = requireAuthority()
        if authorityFailure ~= nil then return authorityFailure end
        local metadata, metadataFailure = inspect(player)
        if metadata == nil then return metadataFailure end
        if not metadata.initialized or metadata.tokenPresent then
            return failure("character_uninitialized", "initialized metadata required")
        end
        if metadata.deathRecorded then return { ok = true, recorded = false, alreadyRecorded = true } end
        local settingsResult, settingsFailure = invoke("inheritance_settings", resolveSettings, player)
        if settingsResult == nil then return settingsFailure end
        local settings = validateSettings(settingsResult)
        if settings == nil then return failure("inheritance_settings_invalid", "inheritanceSettings.resolve") end
        if not settings.enabled then
            local marked, markerFailure = invoke(
                "metadata_death", writeDeathRecorded, player
            )
            if marked == nil then return markerFailure end
            if not exact(marked, { ok = true }) then
                return failure("metadata_death_invalid", "characterStore.markDeathRecorded")
            end
            recordedDeaths[player] = true
            return { ok = true, recorded = false, disabled = true }
        end
        local loaded, loadFailure = invoke("state_load", loadState, player)
        if loaded == nil then return loadFailure end
        local state = rawget(loaded, "state")
        local survivor = type(state) == "table" and rawget(state, "survivor") or nil
        local level = type(survivor) == "table" and rawget(survivor, "level") or nil
        if not safeInteger(level) then return failure("state_load_invalid", "stateStore.load") end
        local identityResult, ownerFailure = invoke("identity", resolveIdentity, player)
        if identityResult == nil then return ownerFailure end
        local owner = validateOwner(identityResult)
        if owner == nil then return failure("identity_invalid", "identity.resolve") end
        local put, putFailure = invoke("pending_put", putPending, owner, level)
        if put == nil then return putFailure end
        if not exact(put, { ok = true, stored = true }) or put.stored ~= true then
            return failure("pending_put_invalid", "recordStore.put")
        end
        recordedDeaths[player] = true
        local marked, markerFailure = invoke(
            "metadata_death", writeDeathRecorded, player
        )
        if marked == nil then markerFailure.committed = true; return markerFailure end
        if not exact(marked, { ok = true }) then return failure("metadata_death_invalid", "characterStore.markDeathRecorded", true) end
        return { ok = true, recorded = true, survivorLevel = level }
    end

    return { ok = true, session = session }
end

return InheritanceSession
