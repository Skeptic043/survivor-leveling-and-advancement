local Store = CharacterInheritanceStore
local assertions = 0
local function eq(a, b, m) assertions = assertions + 1; if a ~= b then error(m .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function yes(v, m) eq(v, true, m) end

local function player(modData)
    return { getModData = function() return modData end }
end

local modData = {}
local firstPlayer = player(modData)
local first = Store.create().store
local inspected = first.inspect(firstPlayer)
yes(inspected.ok, "absent metadata inspects")
eq(inspected.metadata.tokenPresent, false, "absent token")
eq(inspected.metadata.tokenValid, false, "absent proof")
eq(inspected.metadata.initialized, false, "absent initialized")
eq(inspected.metadata.deathRecorded, false, "absent death")
eq(inspected.metadata.codecPresent, false, "absent codec")

yes(first.tokenNewCharacter(firstPlayer).ok, "token writes")
yes(first.tokenNewCharacter(firstPlayer).ok, "same-object token replay is idempotent")
inspected = first.inspect(firstPlayer)
yes(inspected.metadata.tokenPresent, "token shape persists")
yes(inspected.metadata.tokenValid, "current-store exact-object proof validates")
local namespace, root
for key, value in pairs(modData) do namespace, root = key, value end
eq(namespace, "SLA_CharacterInheritance_v1", "exact private namespace")
local rootKeys = 0
for key in pairs(root) do
    rootKeys = rootKeys + 1
    yes(key == "schemaVersion" or key == "newCharacterToken" or key == "initialized"
        or key == "deathRecorded", "metadata key allowlist")
end
eq(rootKeys, 4, "metadata exact shape")
eq(root.schemaVersion, 1, "metadata version")
eq(root.username, nil, "metadata stores no username")
eq(root.onlineId, nil, "metadata stores no online ID")
eq(root.owner, nil, "metadata stores no owner")

local copiedData = { [namespace] = root }
local copiedPlayer = player(copiedData)
local copied = first.inspect(copiedPlayer)
yes(copied.ok, "copied token shape inspects")
yes(copied.metadata.tokenPresent, "copied token remains structurally present")
eq(copied.metadata.tokenValid, false, "copied token has no exact-object proof")
local restarted = Store.create().store
eq(restarted.inspect(firstPlayer).metadata.tokenValid, false, "new store instance invalidates persisted token")

modData.SurvivorLevelingAdvancement = { schemaVersion = 2 }
yes(first.inspect(firstPlayer).metadata.codecPresent, "codec presence detected before decode")
yes(first.markInitialized(firstPlayer).ok, "token transitions to initialized")
inspected = first.inspect(firstPlayer)
eq(inspected.metadata.tokenPresent, false, "initialized clears token")
eq(inspected.metadata.tokenValid, false, "initialized clears issuance proof")
yes(inspected.metadata.initialized, "initialized marker persists")
yes(first.markDeathRecorded(firstPlayer).ok, "death marker writes")
yes(first.inspect(firstPlayer).metadata.deathRecorded, "death marker reads")

local malformedValues = {
    { schemaVersion = 2, newCharacterToken = false, initialized = false, deathRecorded = false },
    { schemaVersion = 1, newCharacterToken = true, initialized = true, deathRecorded = false },
    { schemaVersion = 1, newCharacterToken = false, initialized = false, deathRecorded = true },
    { schemaVersion = 1, newCharacterToken = false, initialized = false, deathRecorded = false, extra = true },
    setmetatable({ schemaVersion = 1, newCharacterToken = false, initialized = false, deathRecorded = false }, {}),
}
for index = 1, #malformedValues do
    local hostileData = { [namespace] = malformedValues[index] }
    local hostilePlayer = player(hostileData)
    eq(first.inspect(hostilePlayer).code, "metadata_invalid", "malformed metadata rejected")
    eq(first.tokenNewCharacter(hostilePlayer).code, "metadata_invalid", "malformed metadata not rewritten")
    eq(hostileData[namespace], malformedValues[index], "malformed metadata identity preserved")
end
eq(first.inspect({}).code, "metadata_unavailable", "missing player capability bounded")
eq(first.inspect({ getModData = function() error("boom") end }).code, "metadata_unavailable", "throwing player capability bounded")

return assertions
