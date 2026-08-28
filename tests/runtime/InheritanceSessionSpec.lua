local Session = InheritanceSession
local assertions = 0
local function eq(a, b, m) assertions = assertions + 1; if a ~= b then error(m .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function yes(v, m) eq(v, true, m) end

local function player(index)
    local modData = {}
    return {
        playerIndex = index or 0,
        getPlayerNum = function(self) return self.playerIndex end,
        getModData = function() return modData end,
    }, modData
end

local function fixture(configure)
    local root = nil
    local settings = { enabled = true, retainedRatio = 0.5 }
    local authority = true
    local identityCalls, settingCalls, stateLoads, stateSaves = 0, 0, 0, 0
    local characterStore = CharacterInheritanceStore.create().store
    local stateStore = PlayerStateStore.create(StateCodec).store
    local stateLoad, stateSave = stateStore.load, stateStore.save
    stateStore.load = function(...) stateLoads = stateLoads + 1; return stateLoad(...) end
    stateStore.save = function(...) stateSaves = stateSaves + 1; return stateSave(...) end
    local recordStore = InheritanceRecordStore.create({
        readRoot = function() return root end,
        writeRoot = function(value) root = value; return true end,
    }).store
    local dependencies = {
        authority = { describe = function() return { ok = true, authoritative = authority } end },
        playerIdentity = { isPlayer = function() return true end },
        characterStore = characterStore,
        stateStore = stateStore,
        recordStore = recordStore,
        identity = { resolve = function(actual)
            identityCalls = identityCalls + 1
            return { ok = true, owner = { kind = "sp", profileIndex = actual.playerIndex } }
        end },
        inheritanceSettings = { resolve = function()
            settingCalls = settingCalls + 1
            return { ok = true, settings = {
                enabled = settings.enabled, retainedRatio = settings.retainedRatio,
            } }
        end },
        StateCodec = { fresh = StateCodec.fresh },
        InheritancePolicy = { plan = InheritancePolicy.plan },
    }
    local values = {
        dependencies = dependencies,
        settings = settings,
        characterStore = characterStore,
        stateStore = stateStore,
        recordStore = recordStore,
        root = function() return root end,
        setRoot = function(value) root = value end,
        setAuthority = function(value) authority = value end,
        identityCalls = function() return identityCalls end,
        settingCalls = function() return settingCalls end,
        stateLoads = function() return stateLoads end,
        stateSaves = function() return stateSaves end,
    }
    if configure then configure(dependencies, values) end
    local created = Session.create(dependencies)
    yes(created.ok, "session creates")
    values.session = created.session
    return values
end

eq(Session.create(nil).code, "invalid_dependencies", "nil dependencies rejected")

do
    local f = fixture()
    local p = player(0)
    local existing = StateCodec.fresh()
    existing.survivor.level = 7
    yes(f.stateStore.save(p, existing).ok, "existing codec state seeded")
    local result = f.session.initialize(p)
    eq(result.outcome, "existing", "codec state is existing")
    eq(f.stateStore.load(p).state.survivor.level, 7, "existing codec state is not rewritten")
    yes(f.characterStore.inspect(p).metadata.initialized, "legacy codec gains initialized marker")
    eq(f.identityCalls(), 0, "existing state never resolves inheritance identity")
end

do
    local f = fixture()
    local p = player(0)
    yes(f.characterStore.markInitialized(p).ok, "initialized marker seeded")
    eq(f.session.initialize(p).outcome, "existing", "marker-only incarnation is existing")
    eq(f.identityCalls(), 0, "marker-only incarnation never consumes")
end

do
    local f = fixture()
    local p = player(0)
    yes(f.recordStore.put({ kind = "sp", profileIndex = 0 }, 12).ok, "pending seeded")
    local result = f.session.initialize(p)
    eq(result.outcome, "fresh", "unmarked old character initializes fresh")
    eq(result.consumed, false, "unmarked old character does not consume")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).found, true, "unmarked path preserves pending")
    yes(f.characterStore.inspect(p).metadata.initialized, "unmarked old character becomes initialized")
end

do
    local f = fixture()
    local p = player(0)
    yes(f.session.tokenNewCharacter(p).ok, "new character token issued")
    yes(f.recordStore.put({ kind = "sp", profileIndex = 0 }, 10).ok, "disabled pending seeded")
    f.settings.enabled = false
    local result = f.session.initialize(p)
    eq(result.outcome, "fresh", "disabled inheritance initializes fresh")
    eq(result.consumed, false, "disabled inheritance does not consume")
    eq(f.identityCalls(), 0, "disabled inheritance does not resolve identity")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).found, true, "disabled inheritance preserves pending")
end

do
    local f = fixture()
    local p = player(0)
    yes(f.session.tokenNewCharacter(p).ok, "no-pending token issued")
    local result = f.session.initialize(p)
    eq(result.outcome, "fresh", "no pending initializes fresh")
    eq(result.consumed, false, "no pending does not consume")
end

do
    local f = fixture()
    local p = player(0)
    f.settings.retainedRatio = 0.5
    yes(f.session.tokenNewCharacter(p).ok, "current-percentage token issued")
    yes(f.recordStore.put({ kind = "sp", profileIndex = 0 }, 10).ok, "current-percentage pending seeded")
    f.settings.retainedRatio = 0.8
    eq(f.session.initialize(p).survivorLevel, 8, "percentage at consume time controls inheritance")
end

do
    local f = fixture()
    local issuedPlayer, issuedData = player(0)
    local copiedPlayer, copiedData = player(0)
    yes(f.session.tokenNewCharacter(issuedPlayer).ok, "wrong-object token issued")
    for key, value in pairs(issuedData) do copiedData[key] = value end
    yes(f.recordStore.put({ kind = "sp", profileIndex = 0 }, 11).ok, "wrong-object pending seeded")
    local result = f.session.initialize(copiedPlayer)
    eq(result.outcome, "fresh", "wrong object with copied token initializes fresh")
    eq(result.consumed, false, "wrong object cannot consume")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).found, true, "wrong-object pending survives")
end

local ratios = {
    { ratio = 0, level = 9, expected = 0 },
    { ratio = 0.5, level = 9, expected = 4 },
    { ratio = 0.8, level = 9, expected = 7 },
    { ratio = 1, level = 9, expected = 9 },
}
for index = 1, #ratios do
    local item = ratios[index]
    local f = fixture()
    local p = player(0)
    f.settings.retainedRatio = item.ratio
    yes(f.session.tokenNewCharacter(p).ok, "ratio token issued")
    yes(f.recordStore.put({ kind = "sp", profileIndex = 0 }, item.level).ok, "ratio pending seeded")
    local result = f.session.initialize(p)
    eq(result.outcome, "inherit", "ratio path inherits")
    eq(result.survivorLevel, item.expected, "ratio level floored")
    eq(result.consumed, true, "ratio path consumes exact pending")
    local state = f.stateStore.load(p).state
    eq(state.survivor.level, item.expected, "inherited level saved")
    eq(state.survivor.xpIntoLevel, 0, "fresh inherited XP")
    eq(state.survivor.spent, 0, "fresh inherited AP")
    eq(state.revision, 0, "fresh inherited revision")
    eq(state.accountingMode, "Tracked", "fresh inherited accounting mode")
    eq(state.inFlightAdvancement, nil, "fresh inheritance has no in-flight request")
    local perkCount = 0; for _ in pairs(state.perks) do perkCount = perkCount + 1 end
    local orphanCount = 0; for _ in pairs(state.orphanedPerks) do orphanCount = orphanCount + 1 end
    eq(perkCount, 0, "fresh inheritance has no active perks")
    eq(orphanCount, 0, "fresh inheritance has no orphaned perks")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).found, false, "pending consumed once")
    eq(f.session.initialize(p).outcome, "existing", "same-process replay is existing")
end

do
    local f = fixture()
    local p, modData = player(0)
    yes(f.session.tokenNewCharacter(p).ok, "stale token initially issued")
    yes(f.recordStore.put({ kind = "sp", profileIndex = 0 }, 20).ok, "stale-token pending seeded")
    local restartedCharacterStore = CharacterInheritanceStore.create().store
    local restarted = fixture(function(dependencies)
        dependencies.characterStore = restartedCharacterStore
        dependencies.recordStore = f.recordStore
        dependencies.stateStore = f.stateStore
    end)
    local result = restarted.session.initialize(p)
    eq(result.outcome, "fresh", "restart-reloaded token initializes fresh")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).found, true, "stale token cannot consume")
    local copiedPlayer, copiedData = player(0)
    for key, value in pairs(modData) do copiedData[key] = value end
    eq(restartedCharacterStore.inspect(copiedPlayer).metadata.tokenValid, false, "copied metadata has no proof")
end

do
    local pending = { schemaVersion = 1, deadSurvivorLevel = 10 }
    local consumes = 0
    local f = fixture(function(dependencies, values)
        dependencies.recordStore = {
            peek = function() return { ok = true, found = true, record = {
                schemaVersion = pending.schemaVersion, deadSurvivorLevel = pending.deadSurvivorLevel,
            } } end,
            consume = function()
                consumes = consumes + 1
                pending = { schemaVersion = 1, deadSurvivorLevel = 20 }
                return { ok = true, consumed = false }
            end,
            put = function() return { ok = true, stored = true } end,
        }
        dependencies.stateStore.save = function() return { ok = false, code = "disk_failed", detail = "save" } end
    end)
    local p = player(0)
    yes(f.session.tokenNewCharacter(p).ok, "compare-mismatch token issued")
    local failed = f.session.initialize(p)
    eq(failed.ok, false, "fresh save failure reported")
    eq(failed.committed, true, "compare mismatch terminalization committed")
    eq(consumes, 1, "compare attempted once")
    eq(pending.deadSurvivorLevel, 20, "newer pending remains untouched")
    eq(f.session.initialize(p).outcome, "existing", "immediate replay cannot consume newer death")
    eq(consumes, 1, "immediate replay performs no compare")
    local restartedStore = CharacterInheritanceStore.create().store
    local restarted = fixture(function(dependencies)
        dependencies.characterStore = restartedStore
        dependencies.recordStore = {
            peek = function() error("restart must not peek") end,
            consume = function() error("restart must not consume") end,
            put = function() return { ok = true, stored = true } end,
        }
        dependencies.stateStore = f.stateStore
    end)
    eq(restarted.session.initialize(p).outcome, "existing", "restart after mismatch remains terminalized")
end

local function assertPostConsumeTerminal(freshReplacement, saveReplacement, expectedCode, label)
    local p = player(0)
    local consumes = 0
    local f = fixture(function(dependencies)
        dependencies.characterStore.tokenNewCharacter(p)
        local originalConsume = dependencies.recordStore.consume
        dependencies.recordStore.put({ kind = "sp", profileIndex = 0 }, 10)
        dependencies.recordStore.consume = function(...)
            consumes = consumes + 1
            return originalConsume(...)
        end
        if freshReplacement ~= nil then dependencies.StateCodec.fresh = freshReplacement end
        if saveReplacement ~= nil then dependencies.stateStore.save = saveReplacement end
    end)
    local failed = f.session.initialize(p)
    eq(failed.code, expectedCode, label .. " returns bounded failure")
    eq(failed.committed, true, label .. " reports committed consume")
    eq(consumes, 1, label .. " consumes original pending once")
    yes(f.recordStore.put({ kind = "sp", profileIndex = 0 }, 20).ok, label .. " seeds newer death")
    eq(f.session.initialize(p).outcome, "existing", label .. " immediate replay is terminalized")
    eq(consumes, 1, label .. " immediate replay cannot consume newer death")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).record.deadSurvivorLevel, 20,
        label .. " newer pending survives immediate replay")
    local restarted = fixture(function(dependencies)
        dependencies.characterStore = CharacterInheritanceStore.create().store
        dependencies.recordStore = f.recordStore
        dependencies.stateStore = f.stateStore
    end)
    eq(restarted.session.initialize(p).outcome, "existing", label .. " restart-style replay is terminalized")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).record.deadSurvivorLevel, 20,
        label .. " newer pending survives restart-style replay")
end

assertPostConsumeTerminal(function()
    local state = StateCodec.fresh()
    state.extra = true
    return state
end, nil, "fresh_state_invalid", "post-consume fresh failure")

assertPostConsumeTerminal(function()
    error("fresh boom")
end, nil, "fresh_state_invalid", "post-consume fresh throw")

assertPostConsumeTerminal(function()
    return "not a state"
end, nil, "fresh_state_invalid", "post-consume non-table fresh result")

assertPostConsumeTerminal(nil, function()
    return { ok = false, code = "disk_failed", detail = "save" }
end, "state_save_failed", "post-consume save failure")

assertPostConsumeTerminal(nil, function()
    error("save boom")
end, "state_save_threw", "post-consume save throw")

assertPostConsumeTerminal(nil, function()
    return { ok = true, extra = true }
end, "state_save_invalid", "post-consume malformed save success")

do
    local f = fixture()
    local p = player(1)
    eq(f.session.recordDeath(p).code, "character_uninitialized", "uninitialized death rejected")
    yes(f.session.tokenNewCharacter(p).ok, "token-only death fixture")
    eq(f.session.recordDeath(p).code, "character_uninitialized", "token-only death rejected")
end

do
    local f = fixture()
    local p = player(1)
    yes(f.session.initialize(p).ok, "death character initialized")
    local state = f.stateStore.load(p).state
    state.survivor.level = 6
    yes(f.stateStore.save(p, state).ok, "death level saved")
    local recorded = f.session.recordDeath(p)
    yes(recorded.ok and recorded.recorded, "ordinary death recorded")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 1 }).record.deadSurvivorLevel, 6, "SP profile split retained")
    local repeatDeath = f.session.recordDeath(p)
    yes(repeatDeath.ok and repeatDeath.alreadyRecorded, "repeat death is successful no-op")
end

do
    local f = fixture()
    local p = player(0)
    yes(f.session.initialize(p).ok, "zero-level death initialized")
    yes(f.session.recordDeath(p).recorded, "zero level death is valid")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).record.deadSurvivorLevel, 0, "zero level stored")
end

do
    local byId = {}
    local identity = Build42InheritanceIdentity.create({
        isServer = function() return true end,
        isClient = function() return false end,
        getPlayerByOnlineID = function(id) return byId[id] end,
    }).adapter
    local f = fixture(function(dependencies) dependencies.identity = identity end)
    local primary = player(0)
    primary.playerIndex = 0
    primary.getOnlineID = function() return 200 end
    primary.getUsername = function() return "primary-login" end
    local secondary = player(1)
    secondary.playerIndex = 1
    secondary.getOnlineID = function() return 201 end
    secondary.getUsername = function() error("secondary label must be ignored") end
    byId[200] = primary
    byId[201] = secondary
    yes(f.session.initialize(primary).ok, "MP primary initialized")
    yes(f.session.initialize(secondary).ok, "MP secondary initialized")
    local primaryState, secondaryState = f.stateStore.load(primary).state, f.stateStore.load(secondary).state
    primaryState.survivor.level, secondaryState.survivor.level = 3, 7
    yes(f.stateStore.save(primary, primaryState).ok, "MP primary level saved")
    yes(f.stateStore.save(secondary, secondaryState).ok, "MP secondary level saved")
    yes(f.session.recordDeath(primary).recorded, "MP primary death recorded")
    yes(f.session.recordDeath(secondary).recorded, "MP secondary death recorded")
    eq(f.recordStore.peek({ kind = "mp", primaryLoginUsername = "primary-login", profileIndex = 0 }).record.deadSurvivorLevel,
        3, "MP primary slot is separate")
    eq(f.recordStore.peek({ kind = "mp", primaryLoginUsername = "primary-login", profileIndex = 1 }).record.deadSurvivorLevel,
        7, "MP secondary slot uses primary login and authoritative profile")

    local replacement = player(0)
    replacement.playerIndex = 0
    replacement.getOnlineID = function() return 200 end
    replacement.getUsername = function() return "primary-login" end
    byId[200] = replacement
    yes(f.session.initialize(replacement).ok, "replacement MP primary initialized")
    local replacementState = f.stateStore.load(replacement).state
    replacementState.survivor.level = 9
    yes(f.stateStore.save(replacement, replacementState).ok, "replacement MP primary level saved")
    yes(f.session.recordDeath(replacement).recorded, "later MP primary death recorded")
    eq(f.recordStore.peek({ kind = "mp", primaryLoginUsername = "primary-login", profileIndex = 0 }).record.deadSurvivorLevel,
        9, "later eligible death overwrites newest owner record")
    eq(f.recordStore.peek({ kind = "mp", primaryLoginUsername = "primary-login", profileIndex = 1 }).record.deadSurvivorLevel,
        7, "MP overwrite preserves sibling profile")
end

do
    local oldPlayer = player(0)
    local newerPlayer = player(0)
    local putAttempts = 0
    local touches = 0
    local f = fixture(function(dependencies)
        local underlyingCharacter = dependencies.characterStore
        local underlyingState = dependencies.stateStore
        local underlyingRecord = dependencies.recordStore
        local underlyingIdentity = dependencies.identity
        local underlyingSettings = dependencies.inheritanceSettings
        local underlyingPlayerIdentity = dependencies.playerIdentity
        local underlyingAuthority = dependencies.authority
        dependencies.characterStore = {
            inspect = function(...)
                touches = touches + 1
                return underlyingCharacter.inspect(...)
            end,
            tokenNewCharacter = underlyingCharacter.tokenNewCharacter,
            markInitialized = underlyingCharacter.markInitialized,
            markDeathRecorded = function(actual, ...)
                touches = touches + 1
                if actual == oldPlayer then
                    return { ok = false, code = "marker_failed", detail = "write" }
                end
                return underlyingCharacter.markDeathRecorded(actual, ...)
            end,
        }
        dependencies.stateStore = {
            load = function(...)
                touches = touches + 1
                return underlyingState.load(...)
            end,
            save = underlyingState.save,
        }
        dependencies.recordStore = {
            peek = underlyingRecord.peek,
            consume = underlyingRecord.consume,
            put = function(...)
                touches = touches + 1
                putAttempts = putAttempts + 1
                if putAttempts == 1 then
                    return { ok = false, code = "write_failed", detail = "put" }
                end
                return underlyingRecord.put(...)
            end,
        }
        dependencies.identity = { resolve = function(...)
            touches = touches + 1
            return underlyingIdentity.resolve(...)
        end }
        dependencies.inheritanceSettings = { resolve = function(...)
            touches = touches + 1
            return underlyingSettings.resolve(...)
        end }
        dependencies.playerIdentity = { isPlayer = function(...)
            touches = touches + 1
            return underlyingPlayerIdentity.isPlayer(...)
        end }
        dependencies.authority = { describe = function(...)
            touches = touches + 1
            return underlyingAuthority.describe(...)
        end }
    end)
    yes(f.session.initialize(oldPlayer).ok, "marker-failure old death initialized")
    yes(f.session.initialize(newerPlayer).ok, "marker-failure newer death initialized")
    local oldState = f.stateStore.load(oldPlayer).state
    oldState.survivor.level = 5
    yes(f.stateStore.save(oldPlayer, oldState).ok, "marker-failure old level saved")
    local newerState = f.stateStore.load(newerPlayer).state
    newerState.survivor.level = 9
    yes(f.stateStore.save(newerPlayer, newerState).ok, "marker-failure newer level saved")

    local putFailed = f.session.recordDeath(oldPlayer)
    eq(putFailed.code, "pending_put_failed", "failed pending put is reported")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).found, false,
        "failed pending put stores no record")

    local markerFailed = f.session.recordDeath(oldPlayer)
    eq(markerFailed.ok, false, "retry reaches post-put marker failure")
    eq(markerFailed.committed, true, "post-put marker failure reports committed pending write")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).record.deadSurvivorLevel, 5,
        "marker failure preserves committed pending record")
    yes(f.session.recordDeath(newerPlayer).recorded, "different character records newer death")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).record.deadSurvivorLevel, 9,
        "different character overwrites with newer level")

    local touchesBeforeReplay = touches
    local replay = f.session.recordDeath(oldPlayer)
    yes(replay.ok and replay.alreadyRecorded, "guarded old replay is successful no-op")
    eq(touches, touchesBeforeReplay, "guarded replay touches no inheritance dependency")
    eq(f.recordStore.peek({ kind = "sp", profileIndex = 0 }).record.deadSurvivorLevel, 9,
        "guarded old replay leaves newer record untouched")
end

local initializationFailures = {
    { "authority throw", "authority_threw", function(d) d.authority.describe = function() error("boom") end end },
    { "authority malformed", "authority_invalid", function(d) d.authority.describe = function() return { ok = true, authoritative = "yes" } end end },
    { "metadata throw", "metadata_inspect_threw", function(d) d.characterStore.inspect = function() error("boom") end end },
    { "metadata malformed", "metadata_inspect_invalid", function(d) d.characterStore.inspect = function() return { ok = true, metadata = {} } end end },
    { "settings throw", "inheritance_settings_threw", function(d) d.inheritanceSettings.resolve = function() error("boom") end end },
    { "settings failure", "inheritance_settings_failed", function(d) d.inheritanceSettings.resolve = function() return { ok = false, code = "down", detail = "settings" } end end },
    { "settings malformed", "inheritance_settings_invalid", function(d) d.inheritanceSettings.resolve = function() return { ok = true, settings = { enabled = true, retainedRatio = "half" } } end end },
    { "identity throw", "identity_threw", function(d) d.identity.resolve = function() error("boom") end end },
    { "identity malformed", "identity_invalid", function(d) d.identity.resolve = function() return { ok = true, owner = { kind = "sp", profileIndex = 9 } } end end },
    { "peek throw", "pending_peek_threw", function(d) d.recordStore.peek = function() error("boom") end end },
    { "peek malformed", "pending_peek_invalid", function(d) d.recordStore.peek = function() return { ok = true, found = true } end end },
    { "policy throw", "policy_threw", function(d) d.InheritancePolicy.plan = function() error("boom") end end },
    { "policy malformed", "policy_invalid", function(d) d.InheritancePolicy.plan = function() return { ok = true, outcome = "inherit", consumePending = true, survivorLevel = math.huge } end end },
    { "consume throw", "pending_consume_threw", function(d) d.recordStore.consume = function() error("boom") end end },
    { "consume malformed", "pending_consume_invalid", function(d) d.recordStore.consume = function() return { ok = true, consumed = true } end end },
}
for index = 1, #initializationFailures do
    local item = initializationFailures[index]
    local p = player(0)
    local f = fixture(function(dependencies)
        dependencies.characterStore.tokenNewCharacter(p)
        dependencies.recordStore.put({ kind = "sp", profileIndex = 0 }, 10)
        item[3](dependencies)
    end)
    eq(f.session.initialize(p).code, item[2], item[1] .. " is bounded")
end

do
    local p = player(0)
    local f = fixture(function(dependencies, values)
        dependencies.characterStore.tokenNewCharacter(p)
        values.settings.enabled = false
        dependencies.StateCodec.fresh = function()
            return setmetatable({
                survivor = { level = 0, xpIntoLevel = 0, spent = 0 }, revision = 0,
                accountingMode = "Tracked", perks = {}, orphanedPerks = {},
            }, {})
        end
    end)
    eq(f.session.initialize(p).code, "fresh_state_invalid", "metatable fresh state is bounded")
end

do
    local p = player(0)
    local f = fixture(function(dependencies, values)
        dependencies.characterStore.tokenNewCharacter(p)
        values.settings.enabled = false
        dependencies.StateCodec.fresh = function()
            local state = StateCodec.fresh()
            state.extra = true
            return state
        end
    end)
    eq(f.session.initialize(p).code, "fresh_state_invalid", "extra fresh root field is rejected")
end

do
    local p = player(0)
    local f = fixture(function(dependencies, values)
        dependencies.characterStore.tokenNewCharacter(p)
        values.settings.enabled = false
        dependencies.StateCodec.fresh = function()
            local state = StateCodec.fresh()
            state.survivor.extra = true
            return state
        end
    end)
    eq(f.session.initialize(p).code, "fresh_state_invalid", "extra fresh survivor field is rejected")
end

do
    local p = player(0)
    local f = fixture(function(dependencies, values)
        dependencies.characterStore.tokenNewCharacter(p)
        values.settings.enabled = false
        dependencies.StateCodec.fresh = function()
            local state = StateCodec.fresh()
            state.survivor.level = 1
            return state
        end
    end)
    eq(f.session.initialize(p).code, "fresh_state_invalid",
        "plain exact-shape nonzero fresh Survivor level is rejected before mutation")
end

do
    local p = player(0)
    local f = fixture(function(dependencies, values)
        dependencies.characterStore.tokenNewCharacter(p)
        values.settings.enabled = false
        dependencies.stateStore.save = function() return { ok = true, extra = true } end
    end)
    eq(f.session.initialize(p).code, "state_save_invalid", "malformed state save is bounded")
end

do
    local p = player(0)
    local f = fixture(function(dependencies, values)
        dependencies.characterStore.tokenNewCharacter(p)
        values.settings.enabled = false
        dependencies.characterStore.markInitialized = function() return { ok = false, code = "down", detail = "marker" } end
    end)
    local result = f.session.initialize(p)
    eq(result.code, "metadata_initialize_failed", "initialization marker failure is bounded")
    eq(result.committed, true, "initialization marker failure follows committed fresh state")
end

do
    local f = fixture(function(dependencies)
        dependencies.characterStore.tokenNewCharacter = function() return { ok = true, extra = true } end
    end)
    eq(f.session.tokenNewCharacter(player(0)).code, "metadata_token_invalid", "malformed token write is bounded")
end

local deathFailures = {
    { "player type throw", "player_identity_threw", function(d) d.playerIdentity.isPlayer = function() error("boom") end end },
    { "player type malformed", "player_identity_invalid", function(d) d.playerIdentity.isPlayer = function() return "yes" end end },
    { "death settings malformed", "inheritance_settings_invalid", function(d) d.inheritanceSettings.resolve = function() return { ok = true, settings = { enabled = true, retainedRatio = -1 } } end end },
    { "death state malformed", "state_load_invalid", function(d) d.stateStore.load = function() return { ok = true, state = { survivor = { level = math.huge } } } end end },
    { "death identity malformed", "identity_invalid", function(d) d.identity.resolve = function() return { ok = true, owner = { kind = "mp", primaryLoginUsername = "", profileIndex = 0 } } end end },
    { "death put throw", "pending_put_threw", function(d) d.recordStore.put = function() error("boom") end end },
    { "death put malformed", "pending_put_invalid", function(d) d.recordStore.put = function() return { ok = true, stored = false } end end },
    { "death marker throw", "metadata_death_threw", function(d) d.characterStore.markDeathRecorded = function() error("boom") end end },
    { "death marker malformed", "metadata_death_invalid", function(d) d.characterStore.markDeathRecorded = function() return { ok = true, extra = true } end end },
}
for index = 1, #deathFailures do
    local item = deathFailures[index]
    local p = player(0)
    local f = fixture(function(dependencies)
        dependencies.characterStore.markInitialized(p)
        dependencies.stateStore.save(p, StateCodec.fresh())
        item[3](dependencies)
    end)
    local result = f.session.recordDeath(p)
    eq(result.code, item[2], item[1] .. " is bounded")
    if item[2] == "metadata_death_threw" or item[2] == "metadata_death_invalid" then
        eq(result.committed, true, item[1] .. " reports committed pending write")
    end
end


do
    local hostileCalls = 0
    local function hostile() hostileCalls = hostileCalls + 1; error("post-construction substitution") end
    local f = fixture()
    local p = player(0)
    local originalPeek = f.recordStore.peek
    yes(f.session.tokenNewCharacter(p).ok, "mutation fixture token issued")
    yes(f.recordStore.put({ kind = "sp", profileIndex = 0 }, 10).ok, "mutation fixture pending seeded")
    local d = f.dependencies
    d.authority.describe = hostile
    d.playerIdentity.isPlayer = hostile
    d.characterStore.inspect = hostile
    d.characterStore.tokenNewCharacter = hostile
    d.characterStore.markInitialized = hostile
    d.characterStore.markDeathRecorded = hostile
    d.stateStore.load = hostile
    d.stateStore.save = hostile
    d.recordStore.peek = hostile
    d.recordStore.consume = hostile
    d.recordStore.put = hostile
    d.identity.resolve = hostile
    d.inheritanceSettings.resolve = hostile
    d.StateCodec.fresh = hostile
    d.InheritancePolicy.plan = hostile
    yes(f.session.tokenNewCharacter(p).ok, "captured token callable ignores substitution")
    local initialized = f.session.initialize(p)
    eq(initialized.outcome, "inherit", "captured initialization graph ignores substitution")
    eq(initialized.survivorLevel, 5, "captured policy retains original behavior")
    yes(f.session.recordDeath(p).recorded, "captured death graph ignores substitution")
    eq(originalPeek({ kind = "sp", profileIndex = 0 }).record.deadSurvivorLevel, 5,
        "captured pending writer records inherited level")
    eq(hostileCalls, 0, "no post-construction callable substitution is invoked")
end

do
    local touches = 0
    local f = fixture(function(dependencies)
        dependencies.playerIdentity = { isPlayer = function() return false end }
        local original = dependencies.characterStore.inspect
        dependencies.characterStore.inspect = function(...) touches = touches + 1; return original(...) end
        dependencies.inheritanceSettings.resolve = function() touches = touches + 1; return { ok = false } end
        dependencies.identity.resolve = function() touches = touches + 1; return { ok = false } end
        dependencies.stateStore.load = function() touches = touches + 1; return { ok = false } end
        dependencies.recordStore.put = function() touches = touches + 1; return { ok = false } end
    end)
    local result = f.session.recordDeath({})
    yes(result.ok and result.ignored, "non-player death is ignored")
    eq(touches, 0, "non-player death touches no hostile persistence capability")
end

do
    local persistenceTouches = 0
    local f = fixture(function(dependencies, values)
        values.setAuthority(false)
        local function hostile() persistenceTouches = persistenceTouches + 1; error("client persistence touch") end
        dependencies.characterStore.inspect = hostile
        dependencies.characterStore.tokenNewCharacter = hostile
        dependencies.characterStore.markInitialized = hostile
        dependencies.characterStore.markDeathRecorded = hostile
        dependencies.inheritanceSettings.resolve = hostile
        dependencies.identity.resolve = hostile
        dependencies.stateStore.load = hostile
        dependencies.stateStore.save = hostile
        dependencies.recordStore.peek = hostile
        dependencies.recordStore.consume = hostile
        dependencies.recordStore.put = hostile
        dependencies.StateCodec.fresh = hostile
        dependencies.InheritancePolicy.plan = hostile
    end)
    local p = player(0)
    eq(f.session.tokenNewCharacter(p).code, "not_authoritative", "client token rejected")
    eq(f.session.initialize(p).code, "not_authoritative", "client initialize rejected")
    eq(f.session.recordDeath(p).code, "not_authoritative", "client death rejected after player gate")
    eq(persistenceTouches, 0, "client rejection precedes every persistence and inheritance capability")
end

return assertions
