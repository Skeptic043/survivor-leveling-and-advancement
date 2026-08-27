local assertionCount = 0

local function expect(value, message)
    assertionCount = assertionCount + 1
    if not value then
        error(message or "expectation failed", 2)
    end
end

local function expectEqual(actual, expected, message)
    assertionCount = assertionCount + 1
    if actual ~= expected then
        error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)), 2)
    end
end

local function rawSettings()
    return {
        survivorMultiplier = 1.5,
        fitnessStrengthNormalization = 16,
        automaticCurveNormalization = true,
        allotmentMode = "Global",
        globalLimit = 3,
        perSkillDefault = 1,
        perSkillOverrides = { Carving = 0, Sprinting = 2 },
    }
end

local current = rawSettings()
local reads = 0
local resolver = WorldSettings.create({
    provider = {
        read = function()
            reads = reads + 1
            return current
        end,
    },
    normalizationByPerk = {
        Carving = 2,
        Sprinting = 3,
        Fitness = 4,
        Strength = 5,
        Modded_Skill = 7,
    },
})
expect(resolver.ok)

local opaquePlayer = setmetatable({}, {
    __index = function()
        error("player must remain opaque")
    end,
})

local accounting = resolver.accountingSettings.resolve(opaquePlayer)
expect(accounting.ok)
expectEqual(accounting.settings.mode, "Tracked")
expectEqual(reads, 1)
accounting.settings.mode = "Free"
expectEqual(resolver.accountingSettings.resolve(opaquePlayer).settings.mode, "Tracked")
expectEqual(reads, 2)

local award = resolver.awardSettings.resolve(opaquePlayer, "Carving")
expect(award.ok)
expectEqual(award.settings.normalization, 2)
expectEqual(award.settings.survivorMultiplier, 1.5)
expectEqual(award.settings.postMax.enabled, false)
expectEqual(award.settings.accountingMode, "Tracked")
expectEqual(reads, 3)
award.settings.normalization = 99
award.settings.survivorMultiplier = 99
award.settings.postMax.enabled = true
local readsBefore = reads
award = resolver.awardSettings.resolve(opaquePlayer, "Carving")
expectEqual(reads, readsBefore + 1)
expectEqual(award.settings.normalization, 2)
expectEqual(award.settings.survivorMultiplier, 1.5)
expectEqual(award.settings.postMax.enabled, false)

award = resolver.awardSettings.resolve(opaquePlayer, "Fitness")
expect(award.ok)
expectEqual(award.settings.normalization, 16)
current.automaticCurveNormalization = false
award = resolver.awardSettings.resolve(opaquePlayer, "Strength")
expect(award.ok)
expectEqual(award.settings.normalization, 16)
award = resolver.awardSettings.resolve(opaquePlayer, "Carving")
expect(award.ok)
expectEqual(award.settings.normalization, 1)
award = resolver.awardSettings.resolve(opaquePlayer, "Modded_Skill")
expect(award.ok)
expectEqual(award.settings.normalization, 1)
current.automaticCurveNormalization = true
award = resolver.awardSettings.resolve(opaquePlayer, "42:mod.skill-name")
expectEqual(award.ok, false)
expectEqual(award.code, "unknown_perk")

current.survivorMultiplier = 0
award = resolver.awardSettings.resolve(opaquePlayer, "Carving")
expect(award.ok)
expectEqual(award.settings.survivorMultiplier, 0)

current.allotmentMode = "Global"
accounting = resolver.accountingSettings.resolve(opaquePlayer)
expect(accounting.ok)
expectEqual(accounting.settings.mode, "Tracked")
local allotment = resolver.allotmentSettings.resolve(opaquePlayer, "Carving")
expect(allotment.ok)
expectEqual(allotment.settings.mode, "Global")
expectEqual(allotment.settings.globalLimit, 3)
expectEqual(allotment.settings.perSkillDefault, nil)

current.allotmentMode = "PerSkill"
accounting = resolver.accountingSettings.resolve(opaquePlayer)
expect(accounting.ok)
expectEqual(accounting.settings.mode, "Tracked")
allotment = resolver.allotmentSettings.resolve(opaquePlayer, "Carving")
expect(allotment.ok)
expectEqual(allotment.settings.mode, "PerSkill")
expectEqual(allotment.settings.perSkillDefault, 1)
expectEqual(allotment.settings.perSkillOverrides.Carving, 0)
allotment.settings.perSkillOverrides.Carving = 9
allotment = resolver.allotmentSettings.resolve(opaquePlayer, "Carving")
expectEqual(allotment.settings.perSkillOverrides.Carving, 0)

current.allotmentMode = "Free"
accounting = resolver.accountingSettings.resolve(opaquePlayer)
expect(accounting.ok)
expectEqual(accounting.settings.mode, "Free")
allotment = resolver.allotmentSettings.resolve(opaquePlayer, "Carving")
expect(allotment.ok)
expectEqual(allotment.settings.mode, "Free")
expectEqual(allotment.settings.globalLimit, nil)
expectEqual(allotment.settings.perSkillDefault, nil)
expectEqual(allotment.settings.perSkillOverrides, nil)
expectEqual(resolver.awardSettings.resolve(opaquePlayer, "Carving").settings.accountingMode, "Free")

current = rawSettings()
current.automaticCurveNormalization = true
current.perSkillOverrides.Carpentry = 4
award = resolver.awardSettings.resolve(opaquePlayer, "Carving")
expectEqual(award.settings.normalization, 2)

local normalized = { Carving = 9, Fitness = 1, Strength = 1 }
local detached = WorldSettings.create({
    provider = { read = function() return rawSettings() end },
    normalizationByPerk = normalized,
})
expect(detached.ok)
normalized.Carving = 99
expectEqual(detached.awardSettings.resolve(nil, "Carving").settings.normalization, 9)

local function expectClosed(raw)
    current = raw
    local awardFailure = resolver.awardSettings.resolve(nil, "Carving")
    local allotmentFailure = resolver.allotmentSettings.resolve(nil, "Carving")
    expectEqual(awardFailure.ok, false)
    expectEqual(awardFailure.code, "invalid_settings")
    expect(type(awardFailure.detail) == "string")
    expectEqual(allotmentFailure.ok, false)
    expectEqual(allotmentFailure.code, "invalid_settings")
    expect(type(allotmentFailure.detail) == "string")
end

local malformed = rawSettings()
malformed.extra = true
expectClosed(malformed)
malformed = rawSettings()
malformed.survivorMultiplier = -1
expectClosed(malformed)
malformed = rawSettings()
malformed.survivorMultiplier = 0 / 0
expectClosed(malformed)
malformed = rawSettings()
malformed.fitnessStrengthNormalization = math.huge
expectClosed(malformed)
malformed = rawSettings()
malformed.fitnessStrengthNormalization = -0.1
expectClosed(malformed)
malformed = rawSettings()
malformed.automaticCurveNormalization = "true"
expectClosed(malformed)
malformed = rawSettings()
malformed.allotmentMode = "Category"
expectClosed(malformed)
malformed = rawSettings()
malformed.globalLimit = 1.2
expectClosed(malformed)
malformed = rawSettings()
malformed.globalLimit = nil
expectClosed(malformed)
malformed = rawSettings()
malformed.perSkillOverrides.Bad = -1
expectClosed(malformed)
malformed = rawSettings()
malformed.perSkillOverrides.Carving = malformed.perSkillOverrides
expectClosed(malformed)
malformed = rawSettings()
malformed.self = malformed
expectClosed(malformed)

local unknown = resolver.awardSettings.resolve(nil, "UnknownSkill")
expectEqual(unknown.ok, false)
expectEqual(unknown.code, "unknown_perk")
expectEqual(unknown.detail, "perkId is not published")
local unsafe = resolver.awardSettings.resolve(nil, "bad perk")
expectEqual(unsafe.ok, false)
expectEqual(unsafe.code, "invalid_perk_id")
expectEqual(unsafe.detail, "perkId is unsafe")
expectEqual(resolver.allotmentSettings.resolve(nil, "UnknownSkill").code, "unknown_perk")

local throwing = WorldSettings.create({
    provider = { read = function() error("provider failure") end },
    normalizationByPerk = { Carving = 1 },
})
expect(throwing.ok)
local providerFailure = throwing.awardSettings.resolve(nil, "Carving")
expectEqual(providerFailure.ok, false)
expectEqual(providerFailure.code, "provider_failure")
expectEqual(providerFailure.detail, "provider.read failed")
expectEqual(throwing.allotmentSettings.resolve(nil, "Carving").code, "provider_failure")
local invalidNormalization = WorldSettings.create({ provider = { read = function() return rawSettings() end }, normalizationByPerk = { ["bad perk"] = 1 } })
expectEqual(invalidNormalization.ok, false)
expectEqual(invalidNormalization.code, "invalid_normalization")
expectEqual(invalidNormalization.detail, "normalizationByPerk must be a safe finite map")
local zeroCatalogNormalization = WorldSettings.create({ provider = { read = function() return rawSettings() end }, normalizationByPerk = { Carving = 0 } })
expectEqual(zeroCatalogNormalization.ok, false)
expectEqual(zeroCatalogNormalization.code, "invalid_normalization")
local invalidDependencies = WorldSettings.create(nil)
expectEqual(invalidDependencies.ok, false)
expectEqual(invalidDependencies.code, "invalid_dependencies")
local invalidProvider = WorldSettings.create({ normalizationByPerk = {} })
expectEqual(invalidProvider.ok, false)
expectEqual(invalidProvider.code, "invalid_provider")

local punctuated = WorldSettings.create({
    provider = { read = function() return rawSettings() end },
    normalizationByPerk = { ["42:mod.skill-name"] = 8 },
})
expect(punctuated.ok)
expectEqual(punctuated.awardSettings.resolve(nil, "42:mod.skill-name").settings.normalization, 8)

current = rawSettings()
current.fitnessStrengthNormalization = 0
award = resolver.awardSettings.resolve(opaquePlayer, "Fitness")
expect(award.ok)
expectEqual(award.settings.normalization, 0)
expectEqual(resolver.awardSettings.resolve(opaquePlayer, "Strength").settings.normalization, 0)

return assertionCount
