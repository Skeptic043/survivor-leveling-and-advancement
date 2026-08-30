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
local function empty(value)
    for _ in pairs(value) do return false end
    return true
end

local function makePlayer(username, profileIndex, modData)
    return {
        ownerUsername = username,
        ownerProfile = profileIndex,
        modData = modData or {},
        getModData = function(self) return self.modData end,
    }
end

local function makeEnvironment(initialRoots)
    local roots = initialRoots or {}
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

local function engineRoundTrip(value, seen)
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end
    if valueType ~= "table" then return nil end
    seen = seen or {}
    if seen[value] ~= nil then error("engine Global ModData tables must be acyclic") end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local copied = engineRoundTrip(child, seen)
            if copied ~= nil then copy[key] = copied end
        end
    end
    seen[value] = nil
    return copy
end

local function accountedState()
    local value = state(6, 4)
    value.survivor.xpIntoLevel = 321
    value.survivor.spent = 2
    value.perks.Reloading = {
        adapterId = "sla.vanilla",
        adapterVersion = 1,
        curveFingerprint = "reloading-curve",
        effectiveMaximum = 10,
        naturalPosition = 75,
        highWaterPosition = 75,
        activeTargets = {
            { targetId = "paid-reloading-2", targetLevel = 2, targetPosition = 150 },
        },
        postMaxFullRateUsed = 0,
    }
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

do
    local before = makeEnvironment()
    local beforePlayer = makePlayer("RestartAccount", 0)
    local beforeStore = before.createStore()
    yes(beforeStore.ok, "pre-restart store creates")
    yes(beforeStore.characterStore.tokenNewCharacter(beforePlayer).ok,
        "pre-restart new character proof")
    yes(beforeStore.stateStore.save(beforePlayer, accountedState()).ok,
        "pre-restart accounted state saves")
    yes(beforeStore.characterStore.markInitialized(beforePlayer).ok,
        "pre-restart record initializes")

    local persisted = engineRoundTrip(before.roots)
    local persistedRoot = persisted.SLA_ServerPlayers_v1
    yes(persistedRoot ~= before.roots.SLA_ServerPlayers_v1,
        "engine save boundary detaches Global root identity")
    yes(persistedRoot.players.RestartAccount[0].state
        ~= before.roots.SLA_ServerPlayers_v1.players.RestartAccount[0].state,
        "engine save boundary detaches nested codec state identity")

    beforeStore, beforePlayer, before = nil, nil, nil
    local loadedRoots = engineRoundTrip(persisted)
    local after = makeEnvironment(loadedRoots)
    local afterStore = after.createStore()
    yes(afterStore.ok, "post-OnInitGlobalModData store creates over loaded tables")
    local afterPlayer = makePlayer("RestartAccount", 0, {
        SurvivorLevelingAdvancement = state(99, 99),
    })

    local restartTransient = makePlayer("RestartAccount", 0)
    yes(afterStore.characterStore.tokenNewCharacter(restartTransient).ok,
        "dedicated transient CreatePlayer OnNewGame is observed after process restart")
    local pendingRoot
    local pending = InheritanceRecordStore.create({
        readRoot = function() return pendingRoot end,
        writeRoot = function(value) pendingRoot = value; return true end,
    }).store
    local afterSession = InheritanceSession.create({
        authority = { describe = function() return { ok = true, authoritative = true } end },
        playerIdentity = { isPlayer = function() return true end },
        characterStore = afterStore.characterStore,
        stateStore = afterStore.stateStore,
        recordStore = pending,
        identity = after.identity,
        inheritanceSettings = { resolve = function()
            return { ok = true, settings = { enabled = false, retainedRatio = 0.5 } }
        end },
        StateCodec = StateCodec,
        InheritancePolicy = InheritancePolicy,
    }).session
    local initialized = afterSession.initialize(afterPlayer)
    yes(initialized.ok, "post-restart existing incarnation initializes")
    eq(initialized.outcome, "existing", "restart does not reclassify existing player as fresh")
    no(afterStore.characterStore.inspect(afterPlayer).metadata.tokenPresent,
        "non-dead canonical record does not authorize restart replacement")

    afterPlayer.modData = { SurvivorLevelingAdvancement = state(88, 88) }
    local loaded = afterStore.stateStore.load(afterPlayer)
    yes(loaded.ok, "post-restart canonical state loads")
    eq(loaded.state.survivor.level, 6, "Survivor level survives full restart")
    eq(loaded.state.survivor.xpIntoLevel, 321, "Survivor XP survives full restart")
    eq(loaded.state.survivor.spent, 2, "spent AP survives full restart")
    eq(loaded.state.revision, 4, "transaction revision survives full restart")
    eq(loaded.state.accountingMode, "Tracked", "accounting mode survives full restart")
    local ledger = loaded.state.perks.Reloading
    eq(#ledger.activeTargets, 1, "paid advancement target survives full restart")
    eq(ledger.activeTargets[1].targetLevel, 2, "paid target level survives full restart")
    eq(ledger.activeTargets[1].targetPosition, 150,
        "paid target position survives full restart")

    local inspectionEnvironment = makeEnvironment(engineRoundTrip(persisted))
    local inspectionStore = inspectionEnvironment.createStore()
    local inspectionTransient = makePlayer("RestartAccount", 0)
    local inspectionPlayer = makePlayer("RestartAccount", 0)
    yes(inspectionStore.characterStore.tokenNewCharacter(inspectionTransient).ok,
        "separate restarted runtime observes transient server event")
    local beforeInspectionSave = inspectionStore.stateStore.load(inspectionPlayer)
    yes(beforeInspectionSave.ok, "restart token does not block canonical load")
    yes(inspectionStore.stateStore.save(inspectionPlayer, beforeInspectionSave.state).ok,
        "save before readiness remains canonical")
    local firstInspection = inspectionStore.characterStore.inspect(inspectionPlayer)
    yes(firstInspection.ok, "separate restarted metadata inspects")
    no(firstInspection.metadata.tokenPresent,
        "transient server event does not attach proof to the later live object")
    no(firstInspection.metadata.tokenValid,
        "live canonical incarnation rejects restart CreatePlayer as replacement proof")
    yes(firstInspection.metadata.initialized,
        "spurious token cannot clear canonical initialization before inspection")
    no(firstInspection.metadata.deathRecorded,
        "spurious token cannot manufacture completed-incarnation metadata")
    no(inspectionStore.characterStore.inspect(inspectionPlayer).metadata.tokenPresent,
        "non-dead record remains unauthorized on repeat inspection")
end

do
    local newer = { SLA_ServerPlayers_v1 = { schemaVersion = 999, players = {} } }
    local persistedNewer = engineRoundTrip(newer)
    local newerStore = makeEnvironment(persistedNewer).createStore()
    no(newerStore.stateStore.load(makePlayer("Newer", 0)).ok,
        "serialized unknown-newer Global root fails closed")
    eq(persistedNewer.SLA_ServerPlayers_v1.schemaVersion, 999,
        "unknown-newer Global root remains untouched")

    local malformed = { SLA_ServerPlayers_v1 = { schemaVersion = 1, players = "bad" } }
    local persistedMalformed = engineRoundTrip(malformed)
    local malformedStore = makeEnvironment(persistedMalformed).createStore()
    no(malformedStore.stateStore.load(makePlayer("Malformed", 0)).ok,
        "serialized malformed Global root fails closed")
    eq(persistedMalformed.SLA_ServerPlayers_v1.players, "bad",
        "malformed Global root remains untouched")
end

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
yes(serverCharacter.tokenNewCharacter(player).ok, "transient creation seam accepts player")
yes(serverState.load(player).ok, "state load resolves")
yes(serverState.save(player, awarded).ok, "state save resolves")
yes(env.identityCalls() >= beforeResolve + 3,
    "every record-reading or record-writing operation re-resolves exact player")
yes(serverCharacter.markInitialized(player).ok, "resolved proof cleared after initialization")

yes(serverCharacter.markDeathRecorded(player).ok,
    "completed incarnation authorizes the later live replacement")
local playerMetadata = serverCharacter.inspect(player)
no(playerMetadata.metadata.tokenValid, "completed dead object cannot replace itself")
local replacementObject = makePlayer("Account", 0)
yes(serverCharacter.inspect(replacementObject).metadata.tokenValid,
    "distinct live object can claim persisted completed-incarnation authority")
local reloadedStore = env.createStore()
yes(reloadedStore.characterStore.inspect(replacementObject).metadata.tokenValid,
    "persisted completed-incarnation authority survives runtime recreation")

local preassignmentPlayer = { modData = {}, getModData = function(self) return self.modData end }
yes(serverCharacter.tokenNewCharacter(preassignmentPlayer).ok,
    "authoritative creation seam can issue proof before durable identity assignment")
preassignmentPlayer.ownerUsername = "AssignedLater"
preassignmentPlayer.ownerProfile = 1
no(serverCharacter.inspect(preassignmentPlayer).metadata.tokenValid,
    "transient creation object is not treated as the later live replacement")

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
local inheritanceSourceState = accountedState()
inheritanceSourceState.survivor.level = 10
yes(inheritanceState.save(inheritancePlayer, inheritanceSourceState).ok,
    "inheritance source state with paid accounting")
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
local inheritanceTransient = makePlayer("Inheritance", 0)
yes(inheritanceSession.tokenNewCharacter(inheritanceTransient).ok,
    "replacement OnNewGame transient is accepted")
local replacement = makePlayer("Inheritance", 0)
local inherited = inheritanceSession.initialize(replacement)
yes(inherited.ok and inherited.consumed, "replacement consumes pending inheritance once")
eq(inherited.outcome, "inherit", "replacement inheritance outcome")
eq(inherited.survivorLevel, 5, "replacement inherited floored level")
local inheritedState = inheritanceState.load(replacement).state
eq(inheritedState.survivor.level, 5,
    "completed-incarnation authority replaces previous canonical incarnation")
eq(inheritedState.survivor.xpIntoLevel, 0, "inheritance transfers no Survivor XP")
eq(inheritedState.survivor.spent, 0, "inheritance grants fresh AP")
yes(empty(inheritedState.perks), "inheritance transfers no paid or recovery accounting")
local reconnect = makePlayer("Inheritance", 0)
local reconnectResult = inheritanceSession.initialize(reconnect)
eq(reconnectResult.outcome, "existing", "reconnect without proof retains incarnation")
eq(inheritanceState.load(reconnect).state.survivor.level, 5, "reconnect retains inherited state")

local orderedPrimary = makePlayer("OrderedProfiles", 0)
local orderedSecondary = makePlayer("OrderedProfiles", 1)
yes(inheritanceState.save(orderedPrimary, state(12, 0)).ok,
    "ordered primary source state")
yes(inheritanceCharacter.markInitialized(orderedPrimary).ok,
    "ordered primary source initialized")
yes(inheritanceState.save(orderedSecondary, state(8, 0)).ok,
    "ordered secondary source state")
yes(inheritanceCharacter.markInitialized(orderedSecondary).ok,
    "ordered secondary source initialized")
yes(inheritanceSession.recordDeath(orderedSecondary).recorded,
    "secondary profile death records first")
yes(inheritanceSession.recordDeath(orderedPrimary).recorded,
    "primary profile death records second")
yes(inheritanceSession.tokenNewCharacter(makePlayer("OrderedProfiles", 0)).ok,
    "primary transient creation event accepted")
yes(inheritanceSession.tokenNewCharacter(makePlayer("OrderedProfiles", 1)).ok,
    "secondary transient creation event accepted")
local orderedPrimaryReplacement = makePlayer("OrderedProfiles", 0)
local orderedSecondaryReplacement = makePlayer("OrderedProfiles", 1)
eq(inheritanceSession.initialize(orderedPrimaryReplacement).survivorLevel, 6,
    "primary replacement inherits only its profile level")
eq(inheritanceSession.initialize(orderedSecondaryReplacement).survivorLevel, 4,
    "secondary replacement inherits only its profile level")
eq(inheritanceState.load(orderedPrimaryReplacement).state.survivor.level, 6,
    "primary replacement state remains owner-isolated")
eq(inheritanceState.load(orderedSecondaryReplacement).state.survivor.level, 4,
    "secondary replacement state remains owner-isolated")
yes(inheritanceSession.recordDeath(orderedPrimary).alreadyRecorded,
    "stale primary death callback cannot alter replacement")
yes(inheritanceSession.recordDeath(orderedSecondary).alreadyRecorded,
    "stale secondary death callback cannot alter replacement")
eq(inheritanceState.load(orderedPrimaryReplacement).state.survivor.level, 6,
    "stale callback leaves primary replacement unchanged")
eq(inheritanceState.load(orderedSecondaryReplacement).state.survivor.level, 4,
    "stale callback leaves secondary replacement unchanged")

local disabledPlayer = makePlayer("DisabledInheritance", 0)
yes(inheritanceCharacter.tokenNewCharacter(disabledPlayer).ok,
    "disabled-inheritance source proof")
local disabledSourceState = accountedState()
disabledSourceState.survivor.level = 9
yes(inheritanceState.save(disabledPlayer, disabledSourceState).ok,
    "disabled-inheritance source state with paid accounting")
yes(inheritanceCharacter.markInitialized(disabledPlayer).ok,
    "disabled-inheritance source initialized")
local disabledSettingsAvailable = true
local disabledSession = InheritanceSession.create({
    authority = { describe = function() return { ok = true, authoritative = true } end },
    playerIdentity = { isPlayer = function() return true end },
    characterStore = inheritanceCharacter,
    stateStore = inheritanceState,
    recordStore = recordStore,
    identity = env.identity,
    inheritanceSettings = { resolve = function()
        if not disabledSettingsAvailable then
            return { ok = false, code = "settings_unavailable", detail = "retry" }
        end
        return { ok = true, settings = { enabled = false, retainedRatio = 0.5 } }
    end },
    StateCodec = StateCodec,
    InheritancePolicy = InheritancePolicy,
}).session
local disabledDeath = disabledSession.recordDeath(disabledPlayer)
yes(disabledDeath.ok and disabledDeath.disabled and not disabledDeath.recorded,
    "disabled inheritance still completes death metadata")
yes(inheritanceCharacter.inspect(disabledPlayer).metadata.deathRecorded,
    "disabled inheritance records the completed incarnation")
local disabledRepeatedDeath = disabledSession.recordDeath(disabledPlayer)
yes(disabledRepeatedDeath.ok and disabledRepeatedDeath.alreadyRecorded,
    "disabled-inheritance repeat death remains at-most-once")
no(recordStore.peek({
    kind = "mp", primaryLoginUsername = "DisabledInheritance", profileIndex = 0,
}).found, "disabled inheritance creates no pending Survivor Level")
local disabledReplacement = makePlayer("DisabledInheritance", 0)
local disabledTransient = makePlayer("DisabledInheritance", 0)
yes(disabledSession.tokenNewCharacter(disabledTransient).ok,
    "disabled-inheritance transient OnNewGame is accepted")
yes(inheritanceCharacter.inspect(disabledReplacement).metadata.tokenValid,
    "distinct live disabled-inheritance replacement is authorized")
disabledSettingsAvailable = false
eq(disabledSession.initialize(disabledReplacement).code, "inheritance_settings_failed",
    "replacement initialization can fail after completed-death inspection")
local unrelatedState = inheritanceState.load(disabledReplacement).state
yes(inheritanceState.save(disabledReplacement, unrelatedState).ok,
    "unrelated state save remains an ordinary canonical save")
local retryMetadata = inheritanceCharacter.inspect(disabledReplacement).metadata
yes(retryMetadata.deathRecorded and retryMetadata.tokenValid,
    "unrelated save preserves completed-death replacement authority")
eq(inheritanceState.load(disabledReplacement).state.survivor.level, 9,
    "unrelated save cannot silently commit replacement state")
disabledSettingsAvailable = true
local disabledFresh = disabledSession.initialize(disabledReplacement)
yes(disabledFresh.ok and disabledFresh.outcome == "fresh" and not disabledFresh.consumed,
    "disabled-inheritance replacement initializes fresh")
local disabledFreshState = inheritanceState.load(disabledReplacement).state
eq(disabledFreshState.survivor.level, 0,
    "disabled-inheritance replacement does not retain dead survivor level")
eq(disabledFreshState.survivor.xpIntoLevel, 0,
    "disabled-inheritance replacement does not retain Survivor XP")
eq(disabledFreshState.survivor.spent, 0,
    "disabled-inheritance replacement does not retain spent AP")
yes(empty(disabledFreshState.perks),
    "disabled-inheritance replacement has no paid or recovery accounting")
no(inheritanceCharacter.inspect(disabledReplacement).metadata.deathRecorded,
    "fresh disabled-inheritance incarnation clears completed-death metadata")

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
local mismatchTransient = makePlayer("Mismatch", 0)
yes(mismatchSession.tokenNewCharacter(mismatchTransient).ok,
    "compare-mismatch transient OnNewGame is accepted")
local mismatchReplacement = makePlayer("Mismatch", 0)
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

local function verifyTerminalizedRetry(username, failureKind, expectedCode)
    local source = makePlayer(username, 0)
    yes(inheritanceState.save(source, state(8, 0)).ok,
        failureKind .. " terminalization source state")
    yes(inheritanceCharacter.markInitialized(source).ok,
        failureKind .. " terminalization source initialized")
    yes(inheritanceSession.recordDeath(source).recorded,
        failureKind .. " terminalization source death recorded")
    local terminalRecordStore = {
        peek = recordStore.peek,
        put = recordStore.put,
        consume = function(owner, expected)
            local replaced = recordStore.put(owner, 12)
            if not replaced.ok then return replaced end
            return recordStore.consume(owner, expected)
        end,
    }
    local saveFailurePending = failureKind == "save"
    local terminalStateStore = {
        load = inheritanceState.load,
        save = function(playerToSave, candidate, intent)
            if saveFailurePending then
                saveFailurePending = false
                return { ok = false, code = "disk_failed", detail = "retry" }
            end
            return inheritanceState.save(playerToSave, candidate, intent)
        end,
    }
    local terminalCodec = StateCodec
    if failureKind == "fresh" then
        terminalCodec = { fresh = function() error("fresh unavailable") end }
    end
    local terminalSession = InheritanceSession.create({
        authority = { describe = function() return { ok = true, authoritative = true } end },
        playerIdentity = { isPlayer = function() return true end },
        characterStore = inheritanceCharacter,
        stateStore = terminalStateStore,
        recordStore = terminalRecordStore,
        identity = env.identity,
        inheritanceSettings = { resolve = function()
            return { ok = true, settings = { enabled = true, retainedRatio = 0.5 } }
        end },
        StateCodec = terminalCodec,
        InheritancePolicy = InheritancePolicy,
    }).session
    yes(terminalSession.tokenNewCharacter(makePlayer(username, 0)).ok,
        failureKind .. " terminalization transient event accepted")
    local replacementPlayer = makePlayer(username, 0)
    local failed = terminalSession.initialize(replacementPlayer)
    eq(failed.code, expectedCode,
        failureKind .. " after compare mismatch reports bounded failure")
    yes(failed.committed,
        failureKind .. " after compare mismatch reports committed terminalization")
    local terminalMetadata = inheritanceCharacter.inspect(replacementPlayer).metadata
    yes(terminalMetadata.initialized and not terminalMetadata.deathRecorded
        and not terminalMetadata.tokenValid,
        failureKind .. " failure leaves replacement durably terminalized")
    eq(terminalSession.initialize(replacementPlayer).outcome, "existing",
        failureKind .. " immediate retry cannot consume newer pending death")
    local owner = {
        kind = "mp", primaryLoginUsername = username, profileIndex = 0,
    }
    eq(recordStore.peek(owner).record.deadSurvivorLevel, 12,
        failureKind .. " immediate retry preserves newer pending level")
    local restartedStore = env.createStore()
    local restartedSession = InheritanceSession.create({
        authority = { describe = function() return { ok = true, authoritative = true } end },
        playerIdentity = { isPlayer = function() return true end },
        characterStore = restartedStore.characterStore,
        stateStore = restartedStore.stateStore,
        recordStore = recordStore,
        identity = env.identity,
        inheritanceSettings = { resolve = function()
            return { ok = true, settings = { enabled = true, retainedRatio = 0.5 } }
        end },
        StateCodec = StateCodec,
        InheritancePolicy = InheritancePolicy,
    }).session
    eq(restartedSession.initialize(makePlayer(username, 0)).outcome, "existing",
        failureKind .. " restart retry remains terminalized")
    eq(recordStore.peek(owner).record.deadSurvivorLevel, 12,
        failureKind .. " restart retry preserves newer pending level")
end

verifyTerminalizedRetry("TerminalFreshFailure", "fresh", "fresh_state_invalid")
verifyTerminalizedRetry("TerminalSaveFailure", "save", "state_save_failed")

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
