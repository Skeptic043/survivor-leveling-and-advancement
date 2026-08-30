local assertions = 0
local function eq(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end
local function yes(value, message) eq(value, true, message) end
local function no(value, message) eq(value, false, message) end

local function makePlayer(username, profileIndex, modData)
    return {
        ownerUsername = username,
        ownerProfile = profileIndex,
        modData = modData or {},
        getModData = function(self) return self.modData end,
    }
end

local function makeEnvironment()
    local roots = {}
    local identityCalls = 0
    local identity = {
        resolve = function(player)
            identityCalls = identityCalls + 1
            if type(player) ~= "table" then return { ok = false, code = "invalid_player" } end
            return {
                ok = true,
                owner = {
                    kind = "mp",
                    primaryLoginUsername = player.ownerUsername,
                    profileIndex = player.ownerProfile,
                },
            }
        end,
    }
    local legacyState = PlayerStateStore.create(StateCodec).store
    local legacyCharacter = CharacterInheritanceStore.create().store
    local function createStore()
        return ServerPlayerRecordStore.create({
            codec = StateCodec,
            identity = identity,
            legacyStateStore = legacyState,
            legacyCharacterStore = legacyCharacter,
            getOrCreate = function(name)
                if roots[name] == nil then roots[name] = {} end
                return roots[name]
            end,
            add = function(name, value) roots[name] = value end,
        })
    end
    return {
        roots = roots,
        identity = identity,
        legacyState = legacyState,
        legacyCharacter = legacyCharacter,
        createStore = createStore,
        identityCalls = function() return identityCalls end,
    }
end

local function state(level, revision)
    local value = StateCodec.fresh()
    value.survivor.level = level or 0
    value.revision = revision or 0
    return value
end

local env = makeEnvironment()
local player = makePlayer("Account", 0)
yes(env.legacyState.save(player, state(4, 2)).ok, "legacy state seeded")
yes(env.legacyCharacter.markInitialized(player).ok, "legacy metadata seeded")
local created = env.createStore()
yes(created.ok, "server store construction")
local serverState, serverCharacter = created.stateStore, created.characterStore

local imported = serverState.load(player)
yes(imported.ok, "legacy state imports")
eq(imported.state.survivor.level, 4, "legacy Survivor level retained")
eq(imported.state.revision, 2, "legacy revision retained")
player.modData = {}
local afterWholeTableReplacement = serverState.load(player)
yes(afterWholeTableReplacement.ok, "canonical state survives whole player ModData replacement")
eq(afterWholeTableReplacement.state.survivor.level, 4, "stale replacement cannot reset level")

local forged = state(99, 99)
player.modData.SurvivorLevelingAdvancement = forged
local canonicalWins = serverState.load(player)
eq(canonicalWins.state.survivor.level, 4, "canonical record wins over forged legacy state")
eq(canonicalWins.state.revision, 2, "canonical revision wins over forged legacy state")

local awarded = canonicalWins.state
awarded.survivor.level = 7
awarded.revision = 3
local legacyBeforeCanonicalSave = player.modData.SurvivorLevelingAdvancement
yes(serverState.save(player, awarded).ok, "canonical award saves")
eq(player.modData.SurvivorLevelingAdvancement, legacyBeforeCanonicalSave,
    "canonical save never mirrors into player ModData")
player.modData = {}
eq(serverState.load(player).state.survivor.level, 7, "award survives later player ModData wipe")
local restarted = env.createStore()
yes(restarted.ok, "server store recreates over same Global root")
eq(restarted.stateStore.load(player).state.survivor.level, 7, "restart/reconnect retains canonical state")

local profileOne = makePlayer("Account", 1)
local otherAccount = makePlayer("Other", 0)
yes(serverState.save(profileOne, state(2, 1)).ok, "secondary profile saves")
yes(serverState.save(otherAccount, state(9, 1)).ok, "separate account saves")
eq(serverState.load(player).state.survivor.level, 7, "primary account/profile remains isolated")
eq(serverState.load(profileOne).state.survivor.level, 2, "secondary profile remains isolated")
eq(serverState.load(otherAccount).state.survivor.level, 9, "separate account remains isolated")

local root
for _, candidate in pairs(env.roots) do
    if type(candidate) == "table" and candidate.players ~= nil then root = candidate end
end
yes(root ~= nil, "versioned server root persisted")
eq(root.schemaVersion, 1, "server root schema")
local canonicalRecord = root.players.Account[0]
local originalRecord = canonicalRecord
canonicalRecord.state.schemaVersion = 999
local invalidCanonical = serverState.load(player)
no(invalidCanonical.ok, "unknown-newer canonical state rejected")
eq(invalidCanonical.code, "canonical_state_invalid", "unknown-newer canonical code")
eq(root.players.Account[0], originalRecord, "invalid canonical record identity preserved")
eq(root.players.Account[0].state.schemaVersion, 999, "invalid canonical bytes not rewritten")
player.modData.SurvivorLevelingAdvancement = state(88, 1)
no(serverState.load(player).ok, "invalid canonical never falls back to legacy")
yes(serverCharacter.tokenNewCharacter(player).ok, "proof may be issued over invalid canonical")
no(serverState.save(player, state(1, 0)).ok,
    "genuine-new proof cannot overwrite invalid or unknown-newer canonical state")
eq(root.players.Account[0].state.schemaVersion, 999,
    "proof leaves invalid canonical state untouched")
root.players.Account[0].state = StateCodec.encode(awarded).state

local beforeResolve = env.identityCalls()
yes(serverCharacter.inspect(player).ok, "metadata inspect resolves")
yes(serverCharacter.tokenNewCharacter(player).ok, "token issuance resolves")
yes(serverState.load(player).ok, "state load resolves")
yes(serverState.save(player, awarded).ok, "state save resolves")
yes(env.identityCalls() >= beforeResolve + 3,
    "every record-reading or record-writing operation re-resolves exact player")
yes(serverCharacter.markInitialized(player).ok, "resolved proof cleared after initialization")

local wrongObject = makePlayer("Account", 0)
yes(serverCharacter.tokenNewCharacter(wrongObject).ok, "wrong object receives its own proof")
local playerMetadata = serverCharacter.inspect(player)
no(playerMetadata.metadata.tokenValid, "wrong-object proof cannot authorize player")
yes(serverCharacter.inspect(wrongObject).metadata.tokenValid, "proof remains exact-object")
local reloadedStore = env.createStore()
no(reloadedStore.characterStore.inspect(wrongObject).metadata.tokenValid,
    "runtime recreation invalidates proof")

local preassignmentPlayer = { modData = {}, getModData = function(self) return self.modData end }
yes(serverCharacter.tokenNewCharacter(preassignmentPlayer).ok,
    "authoritative creation seam can issue proof before durable identity assignment")
preassignmentPlayer.ownerUsername = "AssignedLater"
preassignmentPlayer.ownerProfile = 1
yes(serverCharacter.inspect(preassignmentPlayer).metadata.tokenValid,
    "later exact-object identity resolution retains pre-assignment proof")

local adminPlayer = makePlayer("AdminTarget", 0)
local adminCreated = env.createStore()
local adminState, adminCharacter = adminCreated.stateStore, adminCreated.characterStore
yes(adminCharacter.tokenNewCharacter(adminPlayer).ok, "admin target proof")
yes(adminState.save(adminPlayer, state(0, 0)).ok, "admin target state initialized")
yes(adminCharacter.markInitialized(adminPlayer).ok, "admin target metadata initialized")
local adminSessionResult = AdminSession.create({
    store = adminState,
    catalog = {
        resolver = { loadOptions = { loadedPerks = {} } },
        positionReader = { read = function() return { ok = true, position = 0 } end },
    },
    ownerSession = { isReady = function() return true end },
    SurvivorEconomy = SurvivorEconomy,
    NaturalLedger = { baseline = function(position)
        return { naturalPosition = position, highWaterPosition = position, activeTargets = {} }
    end },
    ActualObservation = { clearPlayer = function() return { ok = true } end },
})
yes(adminSessionResult.ok, "real AdminSession composes with server store")
local adminSession = adminSessionResult.session
local inspectedBefore = adminSession.inspect(adminPlayer)
yes(inspectedBefore.ok, "real AdminSession inspects canonical record")
local adminAward = adminSession.request(adminPlayer, {
    kind = "awardSurvivorLevels",
    expectedRevision = inspectedBefore.summary.revision,
    count = 3,
})
yes(adminAward.ok and adminAward.applied, "real AdminSession commits level award")
eq(adminAward.summary.level, 3, "admin award summary level")
eq(adminAward.summary.availableAp, 3, "admin award summary AP")
adminPlayer.modData = {}
local refreshedAdmin = adminSession.inspect(adminPlayer)
eq(refreshedAdmin.summary.level, 3, "admin refresh survives whole ModData replacement")
eq(refreshedAdmin.summary.availableAp, 3, "admin refresh retains awarded AP")

local inheritancePlayer = makePlayer("Inheritance", 0)
local inheritanceCreated = env.createStore()
local inheritanceState = inheritanceCreated.stateStore
local inheritanceCharacter = inheritanceCreated.characterStore
yes(inheritanceCharacter.tokenNewCharacter(inheritancePlayer).ok, "inheritance initial proof")
yes(inheritanceState.save(inheritancePlayer, state(10, 0)).ok, "inheritance source state")
yes(inheritanceCharacter.markInitialized(inheritancePlayer).ok, "inheritance source initialized")
local pendingRoot
local recordStore = InheritanceRecordStore.create({
    readRoot = function() return pendingRoot end,
    writeRoot = function(value) pendingRoot = value; return true end,
}).store
local inheritanceSessionResult = InheritanceSession.create({
    authority = { describe = function() return { ok = true, authoritative = true } end },
    playerIdentity = { isPlayer = function() return true end },
    characterStore = inheritanceCharacter,
    stateStore = inheritanceState,
    recordStore = recordStore,
    identity = env.identity,
    inheritanceSettings = { resolve = function()
        return { ok = true, settings = { enabled = true, retainedRatio = 0.5 } }
    end },
    StateCodec = StateCodec,
    InheritancePolicy = InheritancePolicy,
})
yes(inheritanceSessionResult.ok, "real inheritance session composes with server record")
local inheritanceSession = inheritanceSessionResult.session
local death = inheritanceSession.recordDeath(inheritancePlayer)
yes(death.ok and death.recorded, "death captures canonical Survivor level")
eq(death.survivorLevel, 10, "death captured level")
local repeatedDeath = inheritanceSession.recordDeath(inheritancePlayer)
yes(repeatedDeath.ok and repeatedDeath.alreadyRecorded, "repeat death remains at-most-once")
local replacement = makePlayer("Inheritance", 0)
yes(inheritanceSession.tokenNewCharacter(replacement).ok, "replacement exact-object proof issued")
local inherited = inheritanceSession.initialize(replacement)
yes(inherited.ok and inherited.consumed, "replacement consumes pending inheritance once")
eq(inherited.outcome, "inherit", "replacement inheritance outcome")
eq(inherited.survivorLevel, 5, "replacement inherited floored level")
eq(inheritanceState.load(replacement).state.survivor.level, 5,
    "genuine-new proof replaces previous canonical incarnation")
local reconnect = makePlayer("Inheritance", 0)
local reconnectResult = inheritanceSession.initialize(reconnect)
eq(reconnectResult.outcome, "existing", "reconnect without proof retains incarnation")
eq(inheritanceState.load(reconnect).state.survivor.level, 5, "reconnect retains inherited state")

local mismatchSource = makePlayer("Mismatch", 0)
yes(inheritanceCharacter.tokenNewCharacter(mismatchSource).ok, "compare-mismatch source proof")
yes(inheritanceState.save(mismatchSource, state(8, 0)).ok, "compare-mismatch source state")
yes(inheritanceCharacter.markInitialized(mismatchSource).ok, "compare-mismatch source initialized")
yes(inheritanceSession.recordDeath(mismatchSource).recorded, "compare-mismatch pending record captured")
local mismatchRecordStore = {
    peek = recordStore.peek,
    put = recordStore.put,
    consume = function(owner, expected)
        local replaced = recordStore.put(owner, 12)
        if not replaced.ok then return replaced end
        return recordStore.consume(owner, expected)
    end,
}
local mismatchSession = InheritanceSession.create({
    authority = { describe = function() return { ok = true, authoritative = true } end },
    playerIdentity = { isPlayer = function() return true end },
    characterStore = inheritanceCharacter,
    stateStore = inheritanceState,
    recordStore = mismatchRecordStore,
    identity = env.identity,
    inheritanceSettings = { resolve = function()
        return { ok = true, settings = { enabled = true, retainedRatio = 0.5 } }
    end },
    StateCodec = StateCodec,
    InheritancePolicy = InheritancePolicy,
}).session
local mismatchReplacement = makePlayer("Mismatch", 0)
yes(mismatchSession.tokenNewCharacter(mismatchReplacement).ok, "compare-mismatch replacement proof")
local mismatchResult = mismatchSession.initialize(mismatchReplacement)
yes(mismatchResult.ok and not mismatchResult.consumed, "compare mismatch terminalizes fresh")
eq(mismatchResult.outcome, "fresh", "compare mismatch outcome")
eq(inheritanceState.load(mismatchReplacement).state.survivor.level, 0,
    "compare mismatch replaces prior incarnation with fresh state")
local newerPending = recordStore.peek({
    kind = "mp", primaryLoginUsername = "Mismatch", profileIndex = 0,
})
yes(newerPending.ok and newerPending.found, "compare mismatch preserves newer pending record")
eq(newerPending.record.deadSurvivorLevel, 12, "compare mismatch preserves newer pending level")

local spState = PlayerStateStore.create(StateCodec).store
local localA = makePlayer("Local", 0)
local localB = makePlayer("Local", 0)
yes(spState.save(localA, state(1, 0)).ok, "first local character saves")
yes(spState.save(localB, state(6, 0)).ok, "second local character saves")
eq(spState.load(localA).state.survivor.level, 1,
    "separately saved local character A retains character-owned state")
eq(spState.load(localB).state.survivor.level, 6,
    "separately saved local character B retains character-owned state")

local extraCapability = env.createStore
local transmitRejected = ServerPlayerRecordStore.create({
    codec = StateCodec,
    identity = env.identity,
    legacyStateStore = env.legacyState,
    legacyCharacterStore = env.legacyCharacter,
    getOrCreate = function() return {} end,
    add = function() end,
    transmit = extraCapability,
})
no(transmitRejected.ok, "Global transmit capability is not accepted")

return assertions
