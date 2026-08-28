local Identity = Build42InheritanceIdentity
local assertions = 0

local function yes(value, message) assertions = assertions + 1; if not value then error(message, 2) end end
local function no(value, message) assertions = assertions + 1; if value then error(message, 2) end end
local function eq(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local usernameReads, steamReads = 0, 0
local function player(id, index, username)
    return {
        playerIndex = index,
        serverPlayerIndex = -1,
        getPlayerNum = function() return index end,
        getOnlineID = function() return id end,
        getUsername = function() usernameReads = usernameReads + 1; return username end,
        getSteamID = function() steamReads = steamReads + 1; return 76561198000000000 end,
    }
end

local server, client = false, false
local byId = {}
local lookupIds = {}
local created = Identity.create({
    isServer = function() return server end,
    isClient = function() return client end,
    getPlayerByOnlineID = function(id)
        lookupIds[#lookupIds + 1] = id
        return byId[id]
    end,
})
yes(created.ok, "valid identity capabilities create")
local adapter = created.adapter

local sp0 = player(0, 0, "must-not-read")
local sp1 = player(0, 1, "must-not-read")
sp0.playerIndex = nil
sp1.playerIndex = nil
local resolved = adapter.resolve(sp0)
yes(resolved.ok, "SP zero resolves")
eq(resolved.owner.kind, "sp", "SP kind")
eq(resolved.owner.profileIndex, 0, "SP zero index")
eq(adapter.resolve(sp1).owner.profileIndex, 1, "SP one index")
eq(usernameReads, 0, "SP never reads username")
local rawOnlySp = player(0, 0, "must-not-read")
rawOnlySp.getPlayerNum = nil
eq(adapter.resolve(rawOnlySp).code, "invalid_profile", "SP raw field cannot replace the live method")

server = true
local primaryA = player(100, 0, "primary-A")
local secondaryA = player(101, 1, "editable-secondary-label")
secondaryA.getUsername = function() error("secondary username must be ignored") end
byId[100] = primaryA
byId[101] = secondaryA
resolved = adapter.resolve(primaryA)
yes(resolved.ok, "MP primary resolves")
eq(resolved.owner.primaryLoginUsername, "primary-A", "MP primary login username")
eq(resolved.owner.profileIndex, 0, "MP primary profile")
resolved = adapter.resolve(secondaryA)
yes(resolved.ok, "MP secondary resolves through primary")
eq(resolved.owner.primaryLoginUsername, "primary-A", "secondary uses primary login")
eq(resolved.owner.profileIndex, 1, "secondary profile remainder")
resolved.owner.primaryLoginUsername = "mutated"
eq(adapter.resolve(secondaryA).owner.primaryLoginUsername, "primary-A", "owner result is detached")

byId[100] = nil
resolved = adapter.resolve(secondaryA)
yes(resolved.ok, "already-connected secondary uses prior direct cache")
eq(resolved.owner.primaryLoginUsername, "primary-A", "cached account remains exact")
local impostorSecondary = player(101, 1, "ignored")
eq(adapter.resolve(impostorSecondary).code, "player_not_live", "full-ID lookup rejects different secondary object")

local primaryB = player(100, 0, "primary-B")
local secondaryB = player(101, 1, "ignored-B")
secondaryB.getUsername = function() error("secondary username must remain ignored") end
byId[100] = primaryB
byId[101] = nil
local lookupsBeforeMissing = #lookupIds
eq(adapter.resolve(secondaryB).code, "player_not_live", "missing full-ID entry rejects new secondary")
eq(#lookupIds, lookupsBeforeMissing + 1, "missing full-ID entry stops before base lookup")
eq(lookupIds[#lookupIds], 101, "missing full-ID lookup uses candidate online ID")
byId[101] = secondaryB
local lookupsBeforeStale = #lookupIds
eq(adapter.resolve(secondaryA).code, "player_not_live", "stale secondary is rejected under reused base")
eq(#lookupIds, lookupsBeforeStale + 1, "different full-ID object stops before base lookup")
byId[100] = nil
byId[101] = secondaryA
eq(adapter.resolve(secondaryA).owner.primaryLoginUsername, "primary-A",
    "rejected stale resolver cannot replace prior cache binding")
byId[100] = primaryB
byId[101] = secondaryB
resolved = adapter.resolve(secondaryB)
yes(resolved.ok, "present primary revalidates reused group")
eq(resolved.owner.primaryLoginUsername, "primary-B", "present primary replaces cache binding")
byId[100] = nil
eq(adapter.resolve(secondaryB).owner.primaryLoginUsername, "primary-B", "replacement cache serves exact secondary")
byId[101] = secondaryA
eq(adapter.resolve(secondaryA).code, "primary_unavailable", "replacement cache rejects exact old secondary")

local primaryUsername = "stable-login"
local stablePrimary = player(120, 0, "unused")
stablePrimary.getUsername = function() usernameReads = usernameReads + 1; return primaryUsername end
local stableSecondaryOne = player(121, 1, "ignored-one")
local stableSecondaryTwo = player(122, 2, "ignored-two")
byId[120] = stablePrimary
byId[121] = stableSecondaryOne
byId[122] = stableSecondaryTwo
yes(adapter.resolve(stableSecondaryOne).ok, "first secondary binds to stable primary")
yes(adapter.resolve(stableSecondaryTwo).ok, "second secondary binds to stable primary")
primaryUsername = "renamed-login"
resolved = adapter.resolve(stableSecondaryOne)
yes(resolved.ok, "same primary rebinds after login username change")
eq(resolved.owner.primaryLoginUsername, "renamed-login", "renamed binding returns new login username")
byId[120] = nil
eq(adapter.resolve(stableSecondaryOne).owner.primaryLoginUsername, "renamed-login",
    "currently resolved secondary survives renamed binding")
eq(adapter.resolve(stableSecondaryTwo).code, "primary_unavailable",
    "renamed binding rejects another old cached secondary")

local capacityById = {}
local capacityAdapter = Identity.create({
    isServer = function() return true end,
    isClient = function() return false end,
    getPlayerByOnlineID = function(id) return capacityById[id] end,
}).adapter
local capacityOkay, lastCapacityOwner = true, nil
for connectionIndex = 0, 64 do
    local base = connectionIndex * 4
    local primary = player(base, 0, "capacity-" .. tostring(connectionIndex))
    capacityById[base] = primary
    local result = capacityAdapter.resolve(primary)
    if not result.ok then capacityOkay = false end
    lastCapacityOwner = result.owner
end
yes(capacityOkay, "all first 65 valid connection bases resolve")
eq(lastCapacityOwner.primaryLoginUsername, "capacity-64", "base beyond prior 64-entry cap resolves")

local maximumPrimary = player(32764, 0, "maximum-base")
local maximumSecondary = player(32767, 3, "ignored-maximum")
capacityById[32764] = maximumPrimary
capacityById[32767] = maximumSecondary
resolved = capacityAdapter.resolve(maximumSecondary)
yes(resolved.ok, "maximum Java-short online ID resolves")
eq(resolved.owner.primaryLoginUsername, "maximum-base", "maximum ID uses matching primary base")
eq(resolved.owner.profileIndex, 3, "maximum ID preserves profile remainder")
eq(capacityAdapter.resolve(player(32768, 0, "too-large")).code, "invalid_online_id",
    "online ID beyond Java-short range fails closed")

client = true
eq(adapter.resolve(sp0).code, "invalid_mode", "both-true mode fails closed")
server = false
eq(adapter.resolve(sp0).code, "invalid_mode", "client mode fails closed")
client = false
server = true

local invalidPlayers = {
    player(-1, 0, "x"), player(1.5, 1, "x"), player(0 / 0, 0, "x"),
}
for index = 1, #invalidPlayers do
    eq(adapter.resolve(invalidPlayers[index]).code, "invalid_online_id", "invalid online ID rejected")
end
local mismatch = player(102, 1, "x")
mismatch.getPlayerNum = function() return 1 end
byId[102] = mismatch
eq(adapter.resolve(mismatch).code, "profile_mismatch", "assigned index mismatch rejected")
local missingMethod = { playerIndex = 0, getPlayerNum = function() return 0 end }
eq(adapter.resolve(missingMethod).code, "invalid_online_id", "missing online ID capability rejected")
eq(adapter.resolve(setmetatable(player(104, 0, "x"), {})).code, "invalid_player", "player metatable rejected")

local badPrimaryCases = {
    player(109, 0, "wrong-id"),
    player(108, 1, "wrong-index"),
    player(108, 0, ""),
    player(108, 0, "bad\nname"),
    player(108, 0, string.rep("x", 65)),
    setmetatable(player(108, 0, "meta"), {}),
}
local target = player(109, 1, "ignored")
byId[109] = target
for index = 1, #badPrimaryCases do
    byId[108] = badPrimaryCases[index]
    eq(adapter.resolve(target).code, "invalid_primary", "invalid primary fails closed")
end
byId[108] = player(108, 0, "valid")
local wrongPrimaryObject = player(108, 0, "other")
eq(adapter.resolve(wrongPrimaryObject).code, "player_not_live", "profile zero must be exact looked-up live player")

local throwingLookup = Identity.create({
    isServer = function() return true end,
    isClient = function() return false end,
    getPlayerByOnlineID = function() error("lookup") end,
}).adapter
eq(throwingLookup.resolve(player(112, 0, "lookup")).code, "player_lookup_failed",
    "throwing full-ID lookup fails closed")
local baseLookupPlayer = player(113, 1, "ignored")
local baseLookupAdapter = Identity.create({
    isServer = function() return true end,
    isClient = function() return false end,
    getPlayerByOnlineID = function(id)
        if id == 113 then return baseLookupPlayer end
        error("base lookup")
    end,
}).adapter
eq(baseLookupAdapter.resolve(baseLookupPlayer).code, "primary_lookup_failed",
    "throwing separate base lookup still fails closed")
local malformedMode = Identity.create({
    isServer = function() return "true" end,
    isClient = function() return false end,
    getPlayerByOnlineID = function() end,
}).adapter
eq(malformedMode.resolve(sp0).code, "invalid_mode", "malformed mode capability fails closed")

eq(Identity.create(nil).code, "invalid_capabilities", "nil capabilities rejected")
eq(Identity.create({}).code, "invalid_capabilities", "missing capabilities rejected")
eq(Identity.create(setmetatable({
    isServer = function() return false end,
    isClient = function() return false end,
    getPlayerByOnlineID = function() end,
}, {})).code, "invalid_capabilities", "dependency metatable rejected")

eq(steamReads, 0, "identity adapter has no Steam dependency")

return assertions
