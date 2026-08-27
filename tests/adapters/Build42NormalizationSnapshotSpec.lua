local assertions = 0

local function check(condition, message)
    assertions = assertions + 1
    if not condition then
        error(message or "assertion failed")
    end
end

local function close(actual, expected, tolerance)
    return actual >= expected - tolerance and actual <= expected + tolerance
end

local function requirements(total, levels)
    local result = {}
    local value = total / levels
    for index = 1, levels do
        result[index] = value
    end
    return result
end

local function makeCatalog(entries)
    local perks = {}
    local identities = {}
    local resolutions = {}
    for index, entry in ipairs(entries) do
        local perk = entry.perk or { ordinal = index }
        if entry.custom ~= nil and perk.isCustom == nil then
            perk.isCustom = function(self)
                return entry.custom
            end
        end
        perks[index] = perk
        identities[perk] = entry.id
        resolutions[entry.id] = entry.resolution or {
            ok = true,
            adapter = {
                describe = function(handle)
                    return { ok = true, perLevelRequirements = handle.requirements }
                end,
            },
            handle = { requirements = entry.requirements },
        }
    end

    return {
        allPerks = function()
            return { ok = true, perks = perks }
        end,
        perkIdentity = {
            resolve = function(perk)
                return { ok = true, perkId = identities[perk] }
            end,
        },
        resolver = {
            resolve = function(perkId)
                return resolutions[perkId] or { ok = false, code = "UNKNOWN" }
            end,
        },
    }
end

local function build(entries, economy)
    return Build42NormalizationSnapshot.build({
        catalog = makeCatalog(entries),
        SurvivorEconomy = economy or SurvivorEconomy,
    })
end

local builtIn = build({ { id = "Woodwork", custom = false, requirements = requirements(32775, 10) } })
check(builtIn.ok == true, "built-in curve succeeds")
check(builtIn.normalizationByPerk.Woodwork == 1.0, "built-in curve stays ordinary")
check(builtIn.automaticCount == 0 and builtIn.fallbackCount == 1, "built-in counts")

local customHigh = build({ { id = "mod:custom-high", custom = true, requirements = requirements(325000, 10) } })
check(customHigh.ok == true, "high total curve succeeds")
check(close(customHigh.normalizationByPerk["mod:custom-high"], 0.067230769, 0.000000001), "high total curve normalization")

local extended = build({ { id = "mod:extended.skill", custom = true, requirements = requirements(21850, 15) } })
check(extended.ok == true, "extended curve succeeds")
check(close(extended.normalizationByPerk["mod:extended.skill"], 1.5, 0.000000001), "extended curve only uses first ten requirements")

local fallback = build({
    { id = "missing", custom = true },
    { id = "short", custom = true, requirements = requirements(100, 9) },
    { id = "nan", custom = true, requirements = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 0 / 0 } },
    { id = "zero", custom = true, requirements = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 0 } },
})
check(fallback.ok == true, "unusable curves are per-skill fallbacks")
check(fallback.fallbackCount == 4 and fallback.automaticCount == 0, "unusable curve counts")
for _, id in ipairs({ "missing", "short", "nan", "zero" }) do
    check(fallback.normalizationByPerk[id] == 1.0, "unusable curve fallback for " .. id)
end

local mixed = build({
    { id = "automatic", custom = true, requirements = requirements(21850, 10) },
    { id = "fallback", custom = true, requirements = requirements(100, 9) },
})
check(mixed.automaticCount == 1 and mixed.fallbackCount == 1, "mixed snapshot counts classify every entry")
check(mixed.normalizationByPerk.automatic == 1.0 and mixed.normalizationByPerk.fallback == 1.0, "mixed snapshot map matches counts")

local economyRejected = build({ { id = "economy-rejected", custom = true, requirements = requirements(20, 10) } }, {
    normalizationFromCoreCurve = function()
        return { ok = false, code = "REJECTED" }
    end,
})
check(economyRejected.ok == true and economyRejected.normalizationByPerk["economy-rejected"] == 1.0, "economy rejection falls back")

local opaque = build({ { id = "mod.author:skill-name_42.20", custom = true, requirements = requirements(21850, 10) } })
check(opaque.ok == true, "opaque id build succeeds")
check(opaque.normalizationByPerk["mod.author:skill-name_42.20"] == 1.0, "opaque id stays exact map key")

local duplicate = build({
    { id = "duplicate", custom = true, requirements = requirements(21850, 10) },
    { id = "duplicate", custom = true, requirements = requirements(21850, 10) },
})
check(duplicate.ok == false and duplicate.code == "PERK_ID_DUPLICATE", "duplicate id rejects complete snapshot")
check(duplicate.normalizationByPerk == nil, "duplicate has no partial map")

local empty = build({ { id = "", requirements = requirements(21850, 10) } })
check(empty.ok == false and empty.code == "PERK_ID_INVALID", "empty id rejects complete snapshot")

local unsafe = build({ { id = "unsafe id", requirements = requirements(21850, 10) } })
check(unsafe.ok == false and unsafe.code == "PERK_ID_INVALID", "unsafe id rejects complete snapshot")

local catalog = makeCatalog({ { id = "detached", requirements = requirements(21850, 10) } })
local dependencies = { catalog = catalog, SurvivorEconomy = SurvivorEconomy }
local first = Build42NormalizationSnapshot.build(dependencies)
local second = Build42NormalizationSnapshot.build(dependencies)
first.normalizationByPerk.detached = 99
check(second.normalizationByPerk.detached == 1.0, "repeated builds return detached maps")
check(first.normalizationByPerk ~= second.normalizationByPerk, "maps are distinct allocations")

local throwingCatalog = makeCatalog({ { id = "first", requirements = requirements(21850, 10) } })
throwingCatalog.perkIdentity.resolve = function()
    error("identity failure")
end
local identityFailure = Build42NormalizationSnapshot.build({ catalog = throwingCatalog, SurvivorEconomy = SurvivorEconomy })
check(identityFailure.ok == false and identityFailure.code == "PERK_IDENTITY_FAILED", "identity failure rejects snapshot")
check(identityFailure.normalizationByPerk == nil, "identity failure has no partial map")

local unresolvedCatalog = makeCatalog({ { id = "missing-resolution", requirements = requirements(21850, 10) } })
unresolvedCatalog.resolver.resolve = function()
    return { ok = false, code = "MISSING" }
end
local unresolved = Build42NormalizationSnapshot.build({ catalog = unresolvedCatalog, SurvivorEconomy = SurvivorEconomy })
check(unresolved.ok == false and unresolved.code == "PERK_RESOLUTION_FAILED", "resolver failure rejects snapshot")

local brokenDescriptionCatalog = makeCatalog({ { id = "bad-description", requirements = requirements(21850, 10) } })
brokenDescriptionCatalog.resolver.resolve = function()
    return {
        ok = true,
        adapter = { describe = function() return { ok = false, code = "BAD" } end },
        handle = {},
    }
end
local brokenDescription = Build42NormalizationSnapshot.build({ catalog = brokenDescriptionCatalog, SurvivorEconomy = SurvivorEconomy })
check(brokenDescription.ok == false and brokenDescription.code == "PERK_DESCRIPTION_FAILED", "description failure rejects snapshot")

local badEnumerationCatalog = makeCatalog({})
badEnumerationCatalog.allPerks = function()
    return { ok = true, perks = { [2] = {} } }
end
local badEnumeration = Build42NormalizationSnapshot.build({ catalog = badEnumerationCatalog, SurvivorEconomy = SurvivorEconomy })
check(badEnumeration.ok == false and badEnumeration.code == "CATALOG_ENUMERATION_INVALID", "bad enumeration rejects snapshot")

local thrownEconomy = build({ { id = "economy-throws", custom = true, requirements = requirements(21850, 10) } }, {
    normalizationFromCoreCurve = function()
        error("economy failure")
    end,
})
check(thrownEconomy.ok == true and thrownEconomy.normalizationByPerk["economy-throws"] == 1.0, "thrown economy falls back")

local markerPerk = {}
markerPerk.isCustom = function(self)
    return self == markerPerk
end
local markerReceiver = build({ { id = "receiver", perk = markerPerk, requirements = requirements(325000, 10) } })
check(markerReceiver.ok == true, "custom marker receives the exact perk")
check(close(markerReceiver.normalizationByPerk.receiver, 0.067230769, 0.000000001), "exact marker receiver enables automatic normalization")

local markerFallback = build({
    { id = "missing-marker", requirements = requirements(325000, 10) },
    { id = "throwing-marker", perk = { isCustom = function() error("marker failure") end }, requirements = requirements(325000, 10) },
    { id = "nonboolean-marker", perk = { isCustom = function() return "true" end }, requirements = requirements(325000, 10) },
})
check(markerFallback.ok == true, "invalid custom markers do not fail the snapshot")
check(markerFallback.automaticCount == 0 and markerFallback.fallbackCount == 3, "invalid markers fall back")
for _, id in ipairs({ "missing-marker", "throwing-marker", "nonboolean-marker" }) do
    check(markerFallback.normalizationByPerk[id] == 1.0, "invalid marker fallback for " .. id)
end

local invalidDependencies = Build42NormalizationSnapshot.build({})
check(invalidDependencies.ok == false and invalidDependencies.code == "INVALID_DEPENDENCIES", "invalid dependencies reject")

return assertions
