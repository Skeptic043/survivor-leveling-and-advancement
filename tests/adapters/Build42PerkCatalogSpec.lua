local Catalog = Build42PerkCatalog
local assertions = 0

local function assertTrue(value, message)
    assertions = assertions + 1
    if not value then error(message or "expected truthy value") end
end

local function assertEqual(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error(message or "values differ") end
end

local function assertFailure(result, code)
    assertEqual(result.ok, false, "expected failure")
    assertEqual(result.code, code, "unexpected failure code")
    assertTrue(type(result.detail) == "string" and result.detail ~= "", "failure needs detail")
end

local none = {}
local function perk(id, parent)
    local value = { id = id, parent = parent }
    function value:getId() return self.id end
    function value:getParent() return self.parent end
    return value
end

local function registry(values)
    local value = { values = values }
    function value:size() return #self.values end
    function value:get(index) return self.values[index + 1] end
    return value
end

local adapter = { built = 0 }
function adapter:build(value)
    self.built = self.built + 1
    if value.rejectBuild then return { ok = false, code = "unsupported", detail = "unsupported" } end
    return { ok = true, handle = { source = value, serial = self.built } }
end
function adapter:describe(handle)
    local source = handle.source
    if source.badDescription then return { ok = true, adapterId = "bad" } end
    return {
        ok = true, adapterId = "sla.vanilla", adapterVersion = 1,
        curveFingerprint = "curve." .. source.id, effectiveMaximum = 3,
        cumulativeThresholds = { [0] = 0, [1] = 10, [2] = 30, [3] = 60 },
        perLevelRequirements = { [1] = 10, [2] = 20, [3] = 30 },
    }
end
function adapter:inspect(handle, player)
    if player == "bad" then return { ok = true, actualPosition = math.huge } end
    if player == "throw" then error("inspect failure") end
    return { ok = true, actualPosition = player.position }
end

assertFailure(Catalog.create(), "invalid-dependencies")
assertFailure(Catalog.create({}), "missing-dependency")
assertFailure(Catalog.create({ nonePerk = none }), "missing-capability")

local category = perk("Category", none)
local fitness = perk("Fitness", {})
local modded = perk("mod.skill-12", {})
local invalidId = perk("bad id", {})
local rejected = perk("Reject", {})
rejected.rejectBuild = true
local malformed = perk("Malformed", {})
malformed.badDescription = true
local result = Catalog.create({ perkRegistry = registry({ category, fitness, modded, invalidId, rejected, malformed }), nonePerk = none, progressionAdapter = adapter })
assertTrue(result.ok, "dependencies should build")
local catalog = result.catalog
assertEqual(catalog.status().initialized, false, "catalog starts uninitialized")
assertFailure(catalog.resolver.resolve("Fitness"), "not-initialized")
local refreshed = catalog.refresh()
assertTrue(refreshed.ok, "refresh should publish valid skills")
assertEqual(refreshed.acceptedCount, 2, "children should be accepted")
assertEqual(refreshed.skippedCount, 4, "category and unsupported entries should skip")
assertEqual(catalog.status().acceptedCount, 2, "status should remain bounded")
local mutableStatus = catalog.status()
mutableStatus.acceptedCount = 99
assertEqual(catalog.status().acceptedCount, 2, "status result must be detached")
assertEqual(catalog.perkIdentity.resolve(fitness).perkId, "Fitness", "passive child should resolve")
assertEqual(catalog.perkIdentity.resolve(modded).perkId, "mod.skill-12", "modded compatible child should resolve")
assertFailure(catalog.perkIdentity.resolve({}), "unknown-perk")
local fitnessResolved = catalog.resolver.resolve("Fitness")
assertTrue(fitnessResolved.ok, "resolver should find exact ID")
assertFailure(catalog.resolver.resolve("Unknown"), "unknown-perk")
assertEqual(fitnessResolved.handle.source, fitness, "resolver returns the adapter handle")
assertEqual(catalog.perkFor("Fitness").perk, fitness, "perkFor returns the published object")
assertTrue(catalog.perkFor("Fitness").perk ~= fitnessResolved.handle, "perkFor must not return the adapter handle")
local all = catalog.allPerks()
assertEqual(#all.perks, 2, "allPerks should be dense")
assertEqual(all.perks[1], fitness, "allPerks returns exact published objects")
assertTrue(all.perks[1] ~= fitnessResolved.handle, "allPerks must not return adapter handles")
all.perks[1] = nil
assertEqual(#catalog.allPerks().perks, 2, "allPerks must detach its array")
assertEqual(catalog.positionReader.read({ position = 17 }, "Fitness").position, 17, "position reader returns exact coordinate")
assertFailure(catalog.positionReader.read("bad", "Fitness"), "invalid-position")
assertFailure(catalog.positionReader.read("throw", "Fitness"), "capability-error")
assertFailure(catalog.positionReader.read({ position = 0 }, "Unknown"), "unknown-perk")

local stableOptions = catalog.resolver.loadOptions
local initialMap = stableOptions.loadedPerks
local initialRecord = initialMap.Fitness
initialRecord.adapterId = "mutated"
assertEqual(catalog.resolver.resolve("Fitness").adapter, adapter, "load options mutation cannot affect resolver")
assertTrue(catalog.refresh().ok, "second refresh should replace snapshot")
assertEqual(catalog.resolver.loadOptions, stableOptions, "load options identity is stable")
assertTrue(stableOptions.loadedPerks ~= initialMap, "loaded map is replaced atomically")
assertEqual(stableOptions.loadedPerks.Fitness.adapterId, "sla.vanilla", "new compatibility records are detached")
assertEqual(stableOptions.loadedPerks.Fitness.adapterVersion, 1, "compatibility record has adapter version")
assertEqual(stableOptions.loadedPerks.Fitness.curveFingerprint, "curve.Fitness", "compatibility record has fingerprint")
assertEqual(stableOptions.loadedPerks.Fitness.effectiveMaximum, 3, "compatibility record has discovered maximum")

local duplicate = Catalog.create({ perkRegistry = registry({ fitness, fitness }), nonePerk = none, progressionAdapter = adapter }).catalog
assertFailure(duplicate.refresh(), "ambiguous-perk")
assertEqual(duplicate.status().initialized, false, "failed first refresh must not publish")
local changingRegistry = registry({ fitness })
local preserving = Catalog.create({ perkRegistry = changingRegistry, nonePerk = none, progressionAdapter = adapter }).catalog
assertTrue(preserving.refresh().ok, "initial snapshot should publish")
local publishedHandle = preserving.perkFor("Fitness").perk
changingRegistry.values = { fitness, fitness }
assertFailure(preserving.refresh(), "ambiguous-perk")
assertEqual(preserving.perkFor("Fitness").perk, publishedHandle, "failed refresh preserves snapshot")
assertEqual(preserving.resolver.loadOptions.loadedPerks.Fitness.adapterId, "sla.vanilla", "failed refresh preserves load map")

local badSize = registry({ fitness })
function badSize:size() return -1 end
assertFailure(Catalog.create({ perkRegistry = badSize, nonePerk = none, progressionAdapter = adapter }).catalog.refresh(), "invalid-registry-size")
local throwingSize = registry({ fitness })
function throwingSize:size() error("size failure") end
assertFailure(Catalog.create({ perkRegistry = throwingSize, nonePerk = none, progressionAdapter = adapter }).catalog.refresh(), "capability-error")
local throwingGet = registry({ fitness })
function throwingGet:get(index) error("get failure") end
assertFailure(Catalog.create({ perkRegistry = throwingGet, nonePerk = none, progressionAdapter = adapter }).catalog.refresh(), "capability-error")

local zeroBased = registry({ fitness, modded })
local zeroIndices = {}
function zeroBased:get(index)
    zeroIndices[#zeroIndices + 1] = index
    return self.values[index + 1]
end
local zeroCatalog = Catalog.create({ perkRegistry = zeroBased, nonePerk = none, progressionAdapter = adapter }).catalog
assertTrue(zeroCatalog.refresh().ok, "zero-based registry should refresh")
assertEqual(zeroIndices[1], 0, "first registry access must be zero")
assertEqual(zeroIndices[2], 1, "second registry access must be one")

local duplicateId = perk("Fitness", {})
local duplicateIdCatalog = Catalog.create({ perkRegistry = registry({ fitness, duplicateId }), nonePerk = none, progressionAdapter = adapter }).catalog
assertFailure(duplicateIdCatalog.refresh(), "ambiguous-perk")
local throwingId = perk("ThrowingId", {})
function throwingId:getId() error("ID failure") end
local throwingParent = perk("ThrowingParent", {})
function throwingParent:getParent() error("parent failure") end
local malformedCatalog = Catalog.create({ perkRegistry = registry({ throwingId, throwingParent, fitness }), nonePerk = none, progressionAdapter = adapter }).catalog
local malformedRefresh = malformedCatalog.refresh()
assertTrue(malformedRefresh.ok, "malformed entries should not block valid entries")
assertEqual(malformedRefresh.acceptedCount, 1, "valid entry should survive malformed neighbors")
assertEqual(malformedRefresh.skippedCount, 2, "throwing ID and parent should skip independently")

local throwingAdapter = {}
function throwingAdapter:build(value) error("build failure") end
function throwingAdapter:describe(handle) error("describe failure") end
function throwingAdapter:inspect(handle, player) return { ok = true, actualPosition = 0 } end
local throwingBuildCatalog = Catalog.create({ perkRegistry = registry({ fitness }), nonePerk = none, progressionAdapter = throwingAdapter }).catalog
local throwingBuildRefresh = throwingBuildCatalog.refresh()
assertTrue(throwingBuildRefresh.ok, "throwing build should be skipped")
assertEqual(throwingBuildRefresh.skippedCount, 1, "throwing build should count once")
local describeThrowAdapter = {}
function describeThrowAdapter:build(value) return { ok = true, handle = value } end
function describeThrowAdapter:describe(handle) error("describe failure") end
function describeThrowAdapter:inspect(handle, player) return { ok = true, actualPosition = 0 } end
local throwingDescribeCatalog = Catalog.create({ perkRegistry = registry({ fitness }), nonePerk = none, progressionAdapter = describeThrowAdapter }).catalog
local throwingDescribeRefresh = throwingDescribeCatalog.refresh()
assertTrue(throwingDescribeRefresh.ok, "throwing describe should be skipped")
assertEqual(throwingDescribeRefresh.skippedCount, 1, "throwing describe should count once")

return assertions
