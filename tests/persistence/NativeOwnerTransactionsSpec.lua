local assertions = 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, message)
end

local function environment()
    local roots, failureMode, generated, replacement = {}, nil, 0, nil
    local stateCodec = { encode = StateCodec.encode }
    local env = { roots = roots, codec = stateCodec }
    stateCodec.decode = function(value, options)
        if env.onDecode then return env.onDecode(value, options) end
        return StateCodec.decode(value, options)
    end
    local built = ServerPlayerRecordStore.create({
        codec = stateCodec,
        identity = { resolve = function(player)
            return { ok = true, owner = { kind = "mp",
                primaryLoginUsername = player.name, profileIndex = player.index or 0 } }
        end },
        legacyStateStore = { load = function() return { ok = false } end },
        legacyCharacterStore = { inspect = function() return { ok = false } end },
        getOrCreate = function(key)
            if failureMode == "fail_read" then error("read failure") end
            roots[key] = roots[key] or {}
            return roots[key]
        end,
        add = function(key, value)
            if failureMode == "reject" then return false end
            if failureMode == "reject_then_read_fail" then
                failureMode = "fail_read"
                return false
            end
            if failureMode == "throw" then error("write failure") end
            if failureMode == "new_bucket" then
                value.players.Alpha = replacement
                return false
            end
            if failureMode == "new_record" then
                value.players.Alpha[0] = replacement
                return false
            end
            if failureMode == "new_root" then
                roots[key] = replacement
                return false
            end
            roots[key] = value
        end,
        generateIncarnationId = function()
            generated = generated + 1
            return env.forcedId or "id:" .. generated
        end,
    })
    check(built.ok, "create")
    env.store = built
    env.player = { name = "Alpha", getModData = function() return {} end }
    function env.fail(value, newValue)
        failureMode, replacement = value, newValue
    end
    function env.root() return roots.SLA_ServerPlayers_v1 end
    local first = StateCodec.fresh()
    first.survivor.level = 3
    check(built.stateStore.save(env.player, first).ok, "initial save")
    check(built.characterStore.markInitialized(env.player).ok, "initialize")
    return env
end

for _, kind in ipairs({"reject", "throw", "reject_then_read_fail"}) do
    local env = environment()
    local before = env.root().players.Alpha
    local changed = StateCodec.fresh()
    changed.survivor.level = 5
    env.fail(kind)
    check(not env.store.stateStore.save(env.player, changed).ok, "reject " .. kind)
    check(env.root().players.Alpha == before, "exact owner table restored " .. kind)
    check(before[0].state.survivor.level == 3, "prior state unchanged " .. kind)
    env.fail(nil)
    check(env.store.stateStore.load(env.player).state.survivor.level == 3, "reload old state " .. kind)
end
for _, kind in ipairs({"new_bucket", "new_record", "new_root"}) do
    local env = environment()
    local other = environment()
    local newer = other.root().players.Alpha[0]
    newer.persistenceRevision = 900
    local replacement = kind == "new_bucket" and {[0] = newer} or (kind == "new_record" and newer or other.root())
    env.fail(kind, replacement)
    check(not env.store.stateStore.save(env.player, StateCodec.fresh()).ok, "reentrant rejected " .. kind)
    if kind == "new_bucket" then check(env.root().players.Alpha == replacement, "new bucket preserved")
    elseif kind == "new_record" then check(env.root().players.Alpha[0] == replacement, "new record preserved")
    else check(env.root() == replacement, "new root preserved") end
end
for _, field in ipairs({"schemaVersion", "incarnationId", "persistenceRevision", "state", "record", "worldId", "players", "extra_profile", "extra_record_field", "extra_root_field"}) do
    local env = environment()
    local original = env.root().players.Alpha
    local changed = false
    env.onDecode = function(value, options)
        local decoded = StateCodec.decode(value, options)
        if not changed then
            changed = true
            if field == "extra_profile" then original[4] = {}
            elseif field == "extra_record_field" then original[0].unexpected = true
            elseif field == "extra_root_field" then env.root().unexpected = true
            elseif field == "record" then original[0] = {}
            elseif field == "players" then env.root().players = {}
            elseif field == "worldId" then env.root().worldId = "world:replacement"
            elseif field == "state" then original[0].state = StateCodec.fresh()
            elseif field == "incarnationId" then original[0].incarnationId = "inc:replacement"
            else original[0][field] = 999 end
        end
        return decoded
    end
    local saved = env.store.stateStore.save(env.player, StateCodec.fresh())
    check(not saved.ok and saved.code == "global_compare_failed", "prepublication compare " .. field)
end
-- Outputs and inputs remain detached, and writes never replace unrelated account buckets.
do
    local env = environment()
    local beta = {name = "Beta", getModData = env.player.getModData}
    check(env.store.stateStore.save(beta, StateCodec.fresh()).ok, "second account")
    local untouched = env.root().players.Beta
    local input = StateCodec.fresh()
    input.survivor.level = 4
    check(env.store.stateStore.save(env.player, input).ok, "save detached")
    input.survivor.level = 99
    check(env.root().players.Alpha[0].state.survivor.level == 4, "input detached")
    local output = env.store.stateStore.load(env.player).state
    output.survivor.level = 77
    check(env.root().players.Alpha[0].state.survivor.level == 4, "output detached")
    check(env.root().players.Beta == untouched, "unrelated bucket preserved")
    for _, field in ipairs({"schemaVersion", "state"}) do
        local prior = env.root().players.Alpha[0][field]
        env.root().players.Alpha[0][field] = field == "state" and {schemaVersion = 999} or 999
        check(not env.store.stateStore.load(env.player).ok, "newer selected record rejected " .. field)
        env.root().players.Alpha[0][field] = prior
    end
end
-- Identity remains account/profile/world scoped. Global uniqueness is intentionally not scanned.
do
    local env = environment()
    local alphaId = env.root().players.Alpha[0].incarnationId
    env.forcedId = alphaId
    local beta = {name = "Beta", getModData = env.player.getModData}
    check(env.store.stateStore.save(beta, StateCodec.fresh()).ok, "other account ID does not require population scan")
    check(env.root().players.Alpha[0].state.survivor.level == 3, "Alpha remains separate")
    check(env.store.stateStore.load(beta).state.survivor.level == 0, "Beta remains separate")
    check(env.store.autosaveStore == nil, "custom snapshot store surface removed")
end
do
    local env = environment()
    local beta = {name = "Beta", getModData = env.player.getModData}
    check(env.store.stateStore.save(beta, StateCodec.fresh()).ok, "unrelated account ready")
    local original = env.root().players.Alpha
    local changed = false
    env.onDecode = function(value, options)
        if not changed then
            changed = true
            env.root().players.Beta[0].persistenceRevision = 800
        end
        return StateCodec.decode(value, options)
    end
    env.fail("reject")
    check(not env.store.stateStore.save(env.player, StateCodec.fresh()).ok, "own transaction rejected")
    check(env.root().players.Alpha == original, "own table restored")
    check(env.root().players.Beta[0].persistenceRevision == 800, "unrelated account change survives rollback")
end
do
    local env = environment()
    for index = 1, 1000 do
        env.root().players["Offline" .. index] = {[0] = {schemaVersion = 2, state = StateCodec.fresh(), initialized = true, deathRecorded = false, incarnationId = "offline:" .. index, persistenceRevision = 1}}
    end
    local originalPairs, populationVisits = pairs, 0
    pairs = function(value)
        if value == env.root().players then populationVisits = populationVisits+1 end
        return originalPairs(value)
    end
    local loaded = env.store.stateStore.load(env.player)
    local saved = env.store.stateStore.save(env.player, loaded.state)
    pairs = originalPairs
    check(loaded.ok and saved.ok, "populated world selected owner succeeds")
    check(populationVisits == 0, "ordinary access never enumerates the population")
    check(env.root().players.Offline1000[0].persistenceRevision == 1, "unrelated records untouched")
end
for _, schema in ipairs({0, 2, 999, "invalid"}) do
    local env = environment()
    env.root().schemaVersion = schema
    local originalPairs, populationVisits = pairs, 0
    pairs = function(value)
        if value == env.root().players then populationVisits = populationVisits+1 end
        return originalPairs(value)
    end
    local result = env.store.stateStore.load(env.player)
    pairs = originalPairs
    check(not result.ok, "malformed or unsupported root rejected " .. tostring(schema))
    check(populationVisits == 0, "invalid root rejected before population scan " .. tostring(schema))
end
for _, schema in ipairs({0, 1, 2}) do
    local root = schema == 0 and {} or {schemaVersion = schema, players = {}}
    local writes, generated = 0, 0
    local built = ServerPlayerRecordStore.create({codec = StateCodec, identity = {resolve = function() return {ok = true, owner = {kind = "mp", primaryLoginUsername = "Fresh", profileIndex = 0}} end}, legacyStateStore = {load = function() return {ok = false} end}, legacyCharacterStore = {inspect = function() return {ok = false} end}, getOrCreate = function() return root end, add = function(_, value)writes = writes+1
    if writes == 2 then return false end
    root = value end, generateIncarnationId = function()generated = generated+1
    return "fresh:" .. generated end})
    local player = {getModData = function() return {} end}
    local result = built.stateStore.save(player, StateCodec.fresh())
    check(not result.ok, "second publication rejects after schema " .. schema)
    check(root.schemaVersion == 3, "native migration retained after rejected state write " .. schema)
    check(root.players.Fresh == nil, "rejected new state absent from published root " .. schema)
    check(writes == 2, "migration then scoped state publication " .. schema)
end
return assertions
