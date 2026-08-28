local assertionCount = 0

local function assertEqual(actual, expected, message)
    assertionCount = assertionCount + 1
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertTrue(value, message)
    assertEqual(value, true, message)
end

local function assertFalse(value, message)
    assertEqual(value, false, message)
end

local function assertSame(actual, expected, message)
    assertEqual(actual, expected, message)
end

local function sequenceEquals(actual, expected, message)
    assertEqual(#actual, #expected, (message or "sequence") .. " length")
    for index = 1, #expected do
        assertEqual(actual[index], expected[index], (message or "sequence") .. " item " .. tostring(index))
    end
end

local function makeDependencies(overrides)
    local calls = {}
    local arguments = {}
    local store = {
        load = function() return { ok = true, state = {} } end,
        save = function() return { ok = true } end,
    }
    local characterInheritanceStore = {
        inspect = function() return { ok = true } end,
        tokenNewCharacter = function() return { ok = true } end,
        markInitialized = function() return { ok = true } end,
        markDeathRecorded = function() return { ok = true } end,
    }
    local inheritanceRecordStore = {
        peek = function() return { ok = true, found = false } end,
        put = function() return { ok = true, stored = true } end,
        consume = function() return { ok = true, consumed = false } end,
    }
    local inheritanceSession = {
        tokenNewCharacter = function() return { ok = true } end,
        initialize = function() return { ok = true } end,
        recordDeath = function() return { ok = true } end,
    }
    local apService = {
        spend = function() return { ok = true } end,
        recover = function() return { ok = true } end,
        recoverLoadedState = function() return { ok = true } end,
    }
    local accountingMode = {
        synchronizeLoaded = function() return { ok = true } end,
    }
    local ownerSnapshot = {
        project = function() return { ok = true, snapshot = {} } end,
    }
    local ownerSession = {
        ready = function() return { ok = true } end,
        snapshot = function() return { ok = true } end,
        isReady = function() return false end,
        clearPlayer = function() return { ok = true } end,
    }
    local advancementSession = { request = function() return { ok = true } end }
    local adminSession = { inspect = function() return { ok = true } end, request = function() return { ok = true } end }
    local processorCalls = {}
    local processor = {
        process = function(player, award, settings)
            processorCalls[#processorCalls + 1] = {
                player = player,
                award = award,
                settings = settings,
            }
            return { ok = true, survivorXp = 7 }
        end,
    }
    local source = {
        marker = "source",
        install = function() return { ok = true } end,
        initializePlayer = function() return { ok = true } end,
        rebasePlayerPerk = function() return { ok = true } end,
        status = function() return { ok = true } end,
    }
    local settings = {
        normalization = 25,
        survivorMultiplier = 1.5,
        postMax = { enabled = false },
    }
    local settingsCalls = {}
    local worldSettings = {
        ok = true,
        accountingSettings = {
            resolve = function()
                return { ok = true, settings = { mode = "Tracked" } }
            end,
        },
        awardSettings = {
            resolve = function(player, perkId)
                settingsCalls[#settingsCalls + 1] = { player = player, perkId = perkId }
                return { ok = true, settings = settings }
            end,
        },
        allotmentSettings = {
            resolve = function()
                return { ok = true, settings = { mode = "Free" } }
            end,
        },
        inheritanceSettings = {
            resolve = function()
                return { ok = true, settings = { enabled = false, retainedRatio = 0.5 } }
            end,
        },
    }

    local dependencies = {
        StateCodec = {
            decode = function() return { ok = true } end,
            encode = function() return { ok = true } end,
            fresh = function() return {} end,
        },
        InheritancePolicy = { plan = function() return { ok = true } end },
        LevelGainCompletion = {
            create = function(levelsGained, apGained)
                return { ok = true, completion = {
                    protocolVersion = 1, kind = "survivor_level_gain",
                    levelsGained = levelsGained, apGained = apGained,
                } }
            end,
            validate = function(value) return { ok = true, completion = value } end,
        },
        PlayerStateStore = {
            create = function(codec)
                calls[#calls + 1] = "store"
                arguments.store = codec
                return { ok = true, store = store }
            end,
        },
        CharacterInheritanceStore = {
            create = function(argument)
                calls[#calls + 1] = "character"
                arguments.character = argument
                return { ok = true, store = characterInheritanceStore }
            end,
        },
        InheritanceRecordStore = {
            create = function(argument)
                calls[#calls + 1] = "record"
                arguments.record = argument
                return { ok = true, store = inheritanceRecordStore }
            end,
        },
        InheritanceSession = {
            create = function(argument)
                calls[#calls + 1] = "inheritance"
                arguments.inheritance = argument
                return { ok = true, session = inheritanceSession }
            end,
        },
        NaturalLedger = {
            baseline = function() end,
            inspect = function() end,
            reconcileExternal = function() end,
            appendTarget = function() end,
            master = function() end,
            applySupported = function() end,
        },
        SurvivorEconomy = {
            availableAp = function() end,
            nextLevelCost = function() end,
            computeAward = function() end,
            applyXp = function() end,
        },
        Allotment = { evaluate = function() end },
        PostMax = { apply = function() end },
        MutationScope = {
            begin = function() end,
            isActive = function() return false end,
            finish = function() end,
        },
        ActualObservation = {
            get = function() end,
            set = function() end,
            clearPlayer = function() end,
        },
        AccountingMode = {
            create = function(argument)
                calls[#calls + 1] = "accounting"
                arguments.accounting = argument
                return { ok = true, service = accountingMode }
            end,
        },
        ApTransaction = {
            create = function(argument)
                calls[#calls + 1] = "ap"
                arguments.ap = argument
                return { ok = true, service = apService }
            end,
        },
        SupportedAwardProcessor = {
            create = function(argument)
                calls[#calls + 1] = "processor"
                arguments.processor = argument
                return { ok = true, service = processor }
            end,
        },
        WorldSettings = {
            create = function(argument)
                calls[#calls + 1] = "settings"
                arguments.settings = argument
                return worldSettings
            end,
        },
        OwnerSnapshot = {
            create = function(argument)
                calls[#calls + 1] = "snapshot"
                arguments.snapshot = argument
                return { ok = true, projector = ownerSnapshot }
            end,
        },
        EventDerivedXpSource = {
            create = function(argument)
                calls[#calls + 1] = "source"
                arguments.source = argument
                return source, nil
            end,
        },
        OwnerSession = {
            create = function(argument)
                calls[#calls + 1] = "session"
                arguments.session = argument
                return { ok = true, session = ownerSession }
            end,
        },
        AdvancementSession = {
            create = function(argument)
                calls[#calls + 1] = "advancement"
                arguments.advancement = argument
                return { ok = true, session = advancementSession }
            end,
        },
        AdminSession = {
            create = function(argument)
                calls[#calls + 1] = "admin"
                arguments.admin = argument
                return { ok = true, session = adminSession }
            end,
        },
        catalog = {
            allPerks = function() return {} end,
            resolver = {
                resolve = function() return { ok = false, code = "unused" } end,
                loadOptions = {},
            },
            perkIdentity = {
                resolve = function() return { ok = false, code = "unused" } end,
            },
            positionReader = {
                read = function() return { ok = false, code = "unused" } end,
            },
        },
        worldSettingsProvider = {
            read = function() return {} end,
        },
        normalizationByPerk = {
            Cooking = 1200,
            ["mod.perk-A"] = 375.5,
        },
        sandboxMultiplier = { resolve = function() end },
        positionArithmetic = { add = function() end },
        environment = { globals = {} },
        authority = { describe = function() end },
        playerIdentity = { isPlayer = function() end },
        inheritanceWorldStore = { readRoot = function() end, writeRoot = function() end },
        inheritanceIdentity = { resolve = function() end },
        levelGainSink = function() return { ok = true } end,
    }

    if overrides ~= nil then
        overrides(dependencies, {
            calls = calls,
            arguments = arguments,
            store = store,
            characterInheritanceStore = characterInheritanceStore,
            inheritanceRecordStore = inheritanceRecordStore,
            inheritanceSession = inheritanceSession,
            ownerSnapshot = ownerSnapshot,
            ownerSession = ownerSession,
            advancementSession = advancementSession,
            adminSession = adminSession,
            apService = apService,
            accountingMode = accountingMode,
            processor = processor,
            processorCalls = processorCalls,
            source = source,
            worldSettings = worldSettings,
            settings = settings,
            settingsCalls = settingsCalls,
        })
    end

    return dependencies, {
        calls = calls,
        arguments = arguments,
        store = store,
        characterInheritanceStore = characterInheritanceStore,
        inheritanceRecordStore = inheritanceRecordStore,
        inheritanceSession = inheritanceSession,
        ownerSnapshot = ownerSnapshot,
        ownerSession = ownerSession,
        advancementSession = advancementSession,
        adminSession = adminSession,
        apService = apService,
        accountingMode = accountingMode,
        processor = processor,
        processorCalls = processorCalls,
        source = source,
        worldSettings = worldSettings,
        settings = settings,
        settingsCalls = settingsCalls,
    }
end

do
    local dependencies, fixture = makeDependencies()
    local result = ServiceComposition.create(dependencies)

    assertTrue(result.ok, "composition succeeds")
    sequenceEquals(fixture.calls, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session", "advancement", "admin" }, "factory order")
    assertSame(fixture.arguments.store, dependencies.StateCodec, "codec identity")
    assertSame(fixture.arguments.settings.provider, dependencies.worldSettingsProvider, "provider identity")
    assertSame(fixture.arguments.record, dependencies.inheritanceWorldStore, "inheritance world capability identity")
    assertSame(fixture.arguments.inheritance.characterStore, fixture.characterInheritanceStore, "character inheritance store identity")
    assertSame(fixture.arguments.inheritance.recordStore, fixture.inheritanceRecordStore, "pending inheritance store identity")
    assertSame(fixture.arguments.inheritance.identity, dependencies.inheritanceIdentity, "inheritance identity adapter identity")
    assertSame(fixture.arguments.inheritance.inheritanceSettings, fixture.worldSettings.inheritanceSettings, "inheritance settings identity")
    assertSame(fixture.arguments.inheritance.StateCodec, dependencies.StateCodec, "inheritance codec identity")
    assertSame(fixture.arguments.inheritance.InheritancePolicy, dependencies.InheritancePolicy, "inheritance policy identity")
    assertFalse(fixture.arguments.settings.normalizationByPerk == dependencies.normalizationByPerk, "normalization detached")
    assertEqual(fixture.arguments.settings.normalizationByPerk.Cooking, 1200, "normalization retained")
    assertSame(fixture.arguments.accounting.store, fixture.store, "accounting store identity")
    assertSame(fixture.arguments.accounting.ActualObservation, dependencies.ActualObservation, "accounting observation identity")
    assertSame(fixture.arguments.snapshot.catalog, dependencies.catalog, "snapshot catalog identity")
    assertSame(fixture.arguments.snapshot.SurvivorEconomy, dependencies.SurvivorEconomy, "snapshot economy identity")
    assertSame(fixture.arguments.ap.store, fixture.store, "AP store identity")
    assertSame(fixture.arguments.processor.store, fixture.store, "processor store identity")
    assertSame(fixture.arguments.ap.resolver, dependencies.catalog.resolver, "AP resolver identity")
    assertEqual(fixture.arguments.ap.loadOptions, nil, "AP receives no redundant load options")
    assertSame(fixture.arguments.processor.resolver, dependencies.catalog.resolver, "processor resolver identity")
    assertSame(fixture.arguments.ap.MutationScope, dependencies.MutationScope, "AP mutation scope identity")
    assertSame(fixture.arguments.processor.MutationScope, dependencies.MutationScope, "processor mutation scope identity")
    assertSame(fixture.arguments.source.mutationScope, dependencies.MutationScope, "source mutation scope identity")
    assertSame(fixture.arguments.ap.ActualObservation, dependencies.ActualObservation, "AP observation identity")
    assertSame(fixture.arguments.ap.AccountingMode, fixture.accountingMode, "AP accounting-mode identity")
    assertSame(fixture.arguments.processor.ActualObservation, dependencies.ActualObservation, "processor observation identity")
    assertSame(fixture.arguments.processor.AccountingMode, fixture.accountingMode, "processor accounting-mode identity")
    assertSame(fixture.arguments.processor.recoveryService, fixture.apService, "recovery identity")
    assertSame(fixture.arguments.source.perkIdentity, dependencies.catalog.perkIdentity, "perk identity")
    assertSame(fixture.arguments.source.positionReader, dependencies.catalog.positionReader, "position reader identity")
    assertSame(fixture.arguments.source.awardHandler, result.services.awardHandler, "handler identity")
    assertSame(fixture.arguments.session.store, fixture.store, "session store identity")
    assertSame(fixture.arguments.session.recoveryService, fixture.apService, "session recovery identity")
    assertSame(fixture.arguments.session.accountingMode, fixture.accountingMode, "session accounting-mode identity")
    assertSame(fixture.arguments.session.accountingSettings, fixture.worldSettings.accountingSettings, "session accounting-settings identity")
    assertSame(fixture.arguments.session.catalog, dependencies.catalog, "session catalog identity")
    assertSame(fixture.arguments.session.xpSource, fixture.source, "session XP source identity")
    assertSame(fixture.arguments.session.ownerSnapshot, fixture.ownerSnapshot, "session snapshot identity")
    assertSame(fixture.arguments.session.inheritanceSession, fixture.inheritanceSession, "owner inheritance-session identity")
    assertSame(fixture.arguments.advancement.apTransaction, fixture.apService, "advancement AP identity")
    assertSame(fixture.arguments.advancement.allotmentSettings, fixture.worldSettings.allotmentSettings, "advancement settings identity")
    assertSame(fixture.arguments.advancement.ownerSession, fixture.ownerSession, "advancement owner identity")
    assertSame(fixture.arguments.admin.store, fixture.store, "admin store identity")
    assertSame(fixture.arguments.admin.catalog, dependencies.catalog, "admin catalog identity")
    assertSame(fixture.arguments.admin.ownerSession, fixture.ownerSession, "admin owner identity")
    assertSame(fixture.arguments.admin.SurvivorEconomy, dependencies.SurvivorEconomy, "admin economy identity")
    assertSame(fixture.arguments.admin.NaturalLedger, dependencies.NaturalLedger, "admin ledger identity")
    assertSame(fixture.arguments.admin.ActualObservation, dependencies.ActualObservation, "admin observation identity")
    local adminDependencyCount = 0
    for key in pairs(fixture.arguments.admin) do
        adminDependencyCount = adminDependencyCount + 1
        assertTrue(
            key == "store" or key == "catalog" or key == "ownerSession" or key == "SurvivorEconomy"
                or key == "NaturalLedger" or key == "ActualObservation",
            "admin dependency allowlist"
        )
    end
    assertEqual(adminDependencyCount, 6, "admin receives six dependencies only")
    assertSame(result.services.store, fixture.store, "result store")
    assertSame(result.services.worldSettings, fixture.worldSettings, "result settings")
    assertSame(result.services.accountingMode, fixture.accountingMode, "result accounting mode")
    assertSame(result.services.ownerSnapshot, fixture.ownerSnapshot, "result snapshot")
    assertSame(result.services.apTransaction, fixture.apService, "result AP")
    assertSame(result.services.awardProcessor, fixture.processor, "result processor")
    assertSame(result.services.xpSource, fixture.source, "result source")
    assertSame(result.services.ownerSession, fixture.ownerSession, "result owner session")
    assertSame(result.services.inheritanceSession, fixture.inheritanceSession, "result inheritance session")
    assertSame(result.services.advancementSession, fixture.advancementSession, "result advancement session")
    assertSame(result.services.adminSession, fixture.adminSession, "result admin session")

    local expectedKeys = {
        store = true,
        worldSettings = true,
        accountingMode = true,
        ownerSnapshot = true,
        apTransaction = true,
        awardProcessor = true,
        awardHandler = true,
        xpSource = true,
        ownerSession = true,
        inheritanceSession = true,
        advancementSession = true,
        adminSession = true,
    }
    local serviceCount = 0
    for key in pairs(result.services) do
        serviceCount = serviceCount + 1
        assertTrue(expectedKeys[key] == true, "unexpected result service " .. tostring(key))
    end
    assertEqual(serviceCount, 12, "twelve services only")
    assertEqual(result.services.dependencies, nil, "dependencies not exposed")
    assertEqual(result.services.modules, nil, "modules not exposed")
    assertEqual(result.services.OwnerSnapshot, nil, "snapshot factory not exposed")

    dependencies.normalizationByPerk.Cooking = 2
    assertEqual(fixture.arguments.settings.normalizationByPerk.Cooking, 1200, "later normalization mutation isolated")
end

do
    local sinkCalls = {}
    local currentResult = nil
    local dependencies, fixture = makeDependencies(function(values, returned)
        values.levelGainSink = function(player, completion)
            sinkCalls[#sinkCalls + 1] = { player = player, completion = completion }
            return { ok = true }
        end
        returned.processor.process = function(player, award, settings)
            returned.processorCalls[#returned.processorCalls + 1] = {
                player = player, award = award, settings = settings,
            }
            return currentResult
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertTrue(result.ok, "level completion composition succeeds")
    local player = {}
    local award = { perkId = "Cooking" }

    currentResult = { ok = true, levelsGained = 1, apGained = 1, stateWritten = true }
    local handled = result.services.awardHandler.process(player, award)
    assertSame(handled, currentResult, "ordinary one-level result preserved")
    assertEqual(#sinkCalls, 1, "ordinary one-level gain emits once")
    assertSame(sinkCalls[1].player, player, "ordinary gain exact player")
    assertEqual(sinkCalls[1].completion.levelsGained, 1, "ordinary one-level count")
    assertEqual(sinkCalls[1].completion.apGained, 1, "ordinary one-level AP")

    currentResult = { ok = true, levelsGained = 4, apGained = 4, stateWritten = true }
    handled = result.services.awardHandler.process(player, award)
    assertSame(handled, currentResult, "ordinary multi-level result preserved")
    assertEqual(#sinkCalls, 2, "ordinary multi-level gain emits one additional completion")
    assertEqual(sinkCalls[2].completion.levelsGained, 4, "ordinary multi-level count stays aggregated")

    currentResult = { ok = true, levelsGained = 0, apGained = 0, stateWritten = true }
    result.services.awardHandler.process(player, award)
    assertEqual(#sinkCalls, 2, "ordinary zero-level award stays silent")

    dependencies, fixture = makeDependencies(function(values, returned)
        values.levelGainSink = function() error("feedback route") end
        returned.processor.process = function()
            return { ok = true, levelsGained = 2, apGained = 2, stateWritten = true }
        end
    end)
    result = ServiceComposition.create(dependencies)
    handled = result.services.awardHandler.process(player, award)
    assertTrue(handled.ok, "completion sink failure does not invalidate saved award")
    assertEqual(handled.levelsGained, 2, "sink failure preserves committed gains")
end

do
    local dependencies, fixture = makeDependencies()
    local player = {}
    local award = { perkId = "Cooking" }
    local result = ServiceComposition.create(dependencies)
    local handled = result.services.awardHandler.process(player, award)

    assertTrue(handled.ok, "award handled")
    assertEqual(handled.survivorXp, 7, "processor result returned")
    assertEqual(#fixture.settingsCalls, 1, "settings resolved once")
    assertEqual(#fixture.processorCalls, 1, "processor invoked once")
    assertSame(fixture.settingsCalls[1].player, player, "settings player")
    assertEqual(fixture.settingsCalls[1].perkId, "Cooking", "settings perk")
    assertSame(fixture.processorCalls[1].player, player, "processor player")
    assertSame(fixture.processorCalls[1].award, award, "processor award")
    assertSame(fixture.processorCalls[1].settings, fixture.settings, "resolved settings identity")
end

do
    local dependencies, fixture = makeDependencies(function(_, values)
        values.worldSettings.awardSettings.resolve = function()
            values.settingsCalls[#values.settingsCalls + 1] = {}
            return { ok = false, code = "settings_unavailable", detail = "provider failed" }
        end
    end)
    local result = ServiceComposition.create(dependencies)
    local handled = result.services.awardHandler.process({}, { perkId = "Cooking" })

    assertFalse(handled.ok, "settings failure returned")
    assertEqual(handled.code, "settings_unavailable", "settings code stable")
    assertEqual(handled.detail, "provider failed", "settings detail stable")
    assertEqual(#fixture.settingsCalls, 1, "settings failure not retried")
    assertEqual(#fixture.processorCalls, 0, "processor skipped after settings failure")
end

do
    local dependencies, fixture = makeDependencies(function(_, values)
        values.worldSettings.awardSettings.resolve = function()
            values.settingsCalls[#values.settingsCalls + 1] = {}
            error("provider boom")
        end
    end)
    local result = ServiceComposition.create(dependencies)
    local handled = result.services.awardHandler.process({}, { perkId = "Cooking" })

    assertFalse(handled.ok, "settings throw contained")
    assertEqual(handled.code, "settings_threw", "settings throw stable")
    assertEqual(#fixture.settingsCalls, 1, "throw not retried")
    assertEqual(#fixture.processorCalls, 0, "processor skipped after throw")
end

do
    local dependencies, fixture = makeDependencies(function(_, values)
        values.processor.process = function()
            values.processorCalls[#values.processorCalls + 1] = {}
            error("processor boom")
        end
    end)
    local result = ServiceComposition.create(dependencies)
    local handled = result.services.awardHandler.process({}, { perkId = "Cooking" })

    assertFalse(handled.ok, "processor throw contained")
    assertEqual(handled.code, "processor_threw", "processor throw stable")
    assertEqual(#fixture.settingsCalls, 1, "settings called once before processor throw")
    assertEqual(#fixture.processorCalls, 1, "processor throw not retried")
end

do
    local dependencies, fixture = makeDependencies()
    local result = ServiceComposition.create(dependencies)
    local handled = result.services.awardHandler.process({}, nil)

    assertFalse(handled.ok, "missing award rejected")
    assertEqual(handled.code, "invalid_award", "missing award code")
    assertEqual(#fixture.settingsCalls, 0, "invalid award does not resolve settings")
    assertEqual(#fixture.processorCalls, 0, "invalid award does not invoke processor")
end

local function assertPreflightFailure(mutator, expectedDetail)
    local dependencies, fixture = makeDependencies()
    mutator(dependencies)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, "preflight rejects dependency")
    assertEqual(result.code, "invalid_dependencies", "preflight code")
    assertEqual(result.detail, expectedDetail, "preflight detail")
    assertEqual(#fixture.calls, 0, "preflight runs no factory")
end

assertPreflightFailure(function(dependencies) dependencies.StateCodec = nil end, "StateCodec capabilities are required")
assertPreflightFailure(function(dependencies) dependencies.PlayerStateStore.create = nil end, "PlayerStateStore.create is required")
assertPreflightFailure(function(dependencies) dependencies.CharacterInheritanceStore.create = nil end, "CharacterInheritanceStore.create is required")
assertPreflightFailure(function(dependencies) dependencies.InheritanceRecordStore.create = nil end, "InheritanceRecordStore.create is required")
assertPreflightFailure(function(dependencies) dependencies.InheritanceSession.create = nil end, "InheritanceSession.create is required")
assertPreflightFailure(function(dependencies) dependencies.InheritancePolicy.plan = nil end, "InheritancePolicy capabilities are required")
assertPreflightFailure(function(dependencies) dependencies.AccountingMode.create = nil end, "AccountingMode.create is required")
assertPreflightFailure(function(dependencies) dependencies.OwnerSnapshot.create = nil end, "OwnerSnapshot.create is required")
assertPreflightFailure(function(dependencies) dependencies.OwnerSession.create = nil end, "OwnerSession.create is required")
assertPreflightFailure(function(dependencies) dependencies.AdvancementSession.create = nil end, "AdvancementSession.create is required")
assertPreflightFailure(function(dependencies) dependencies.AdminSession.create = nil end, "AdminSession.create is required")
assertPreflightFailure(function(dependencies) dependencies.SurvivorEconomy.nextLevelCost = nil end, "SurvivorEconomy capabilities are required")
assertPreflightFailure(function(dependencies) dependencies.catalog.allPerks = nil end, "catalog capabilities are required")
assertPreflightFailure(function(dependencies) dependencies.catalog.resolver.resolve = nil end, "catalog capabilities are required")
assertPreflightFailure(function(dependencies) dependencies.worldSettingsProvider.read = nil end, "worldSettingsProvider.read is required")
assertPreflightFailure(function(dependencies) dependencies.inheritanceWorldStore.readRoot = nil end, "inheritanceWorldStore capabilities are required")
assertPreflightFailure(function(dependencies) dependencies.inheritanceIdentity.resolve = nil end, "inheritanceIdentity.resolve is required")
assertPreflightFailure(function(dependencies) dependencies.normalizationByPerk.Cooking = 0 end, "normalizationByPerk is malformed")
assertPreflightFailure(function(dependencies) dependencies.normalizationByPerk["bad id"] = 4 end, "normalizationByPerk is malformed")
assertPreflightFailure(function(dependencies) setmetatable(dependencies.normalizationByPerk, {}) end, "normalizationByPerk is malformed")
assertPreflightFailure(function(dependencies) dependencies.environment = nil end, "environment.globals is required")

local function assertFactoryStops(factoryName, replacement, expectedCalls, expectedCode)
    local labels = {
        PlayerStateStore = "store",
        WorldSettings = "settings",
        CharacterInheritanceStore = "character",
        InheritanceRecordStore = "record",
        InheritanceSession = "inheritance",
        AccountingMode = "accounting",
        OwnerSnapshot = "snapshot",
        ApTransaction = "ap",
        SupportedAwardProcessor = "processor",
        EventDerivedXpSource = "source",
        OwnerSession = "session",
        AdvancementSession = "advancement",
        AdminSession = "admin",
    }
    local dependencies, fixture = makeDependencies(function(values, returned)
        values[factoryName].create = function(argument)
            returned.calls[#returned.calls + 1] = labels[factoryName]
            return replacement(argument)
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, factoryName .. " failure returned")
    assertEqual(result.code, expectedCode, factoryName .. " failure code")
    sequenceEquals(fixture.calls, expectedCalls, factoryName .. " stops later factories")
end

assertFactoryStops("PlayerStateStore", function() return { ok = true, store = {} } end, { "store" }, "invalid_factory_result")
assertFactoryStops("WorldSettings", function() return { ok = true, awardSettings = {} } end, { "store", "settings" }, "invalid_factory_result")
assertFactoryStops("CharacterInheritanceStore", function() return { ok = true, store = {} } end, { "store", "settings", "character" }, "invalid_factory_result")
assertFactoryStops("InheritanceRecordStore", function() return { ok = true, store = {} } end, { "store", "settings", "character", "record" }, "invalid_factory_result")
assertFactoryStops("InheritanceSession", function() return { ok = true, session = {} } end, { "store", "settings", "character", "record", "inheritance" }, "invalid_factory_result")
assertFactoryStops("AccountingMode", function() return { ok = true, service = {} } end, { "store", "settings", "character", "record", "inheritance", "accounting" }, "invalid_factory_result")
assertFactoryStops("OwnerSnapshot", function() return nil end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot" }, "invalid_factory_result")
assertFactoryStops("OwnerSnapshot", function() return { ok = true, projector = {} } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot" }, "invalid_factory_result")
assertFactoryStops("ApTransaction", function() return { ok = false, code = "ap_unavailable", detail = "nope" } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap" }, "ap_unavailable")
assertFactoryStops("ApTransaction", function()
    return { ok = true, service = { spend = function() end, recover = function() end } }
end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap" }, "invalid_factory_result")
assertFactoryStops("SupportedAwardProcessor", function() return { ok = true, service = {} } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor" }, "invalid_factory_result")
assertFactoryStops("EventDerivedXpSource", function() return nil, { ok = false, code = "source_unavailable", detail = "nope" } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source" }, "source_unavailable")
assertFactoryStops("OwnerSession", function() return { ok = true, session = {} } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session" }, "invalid_factory_result")
assertFactoryStops("OwnerSession", function() return { ok = false, code = "session_unavailable", detail = "catalog rejected" } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session" }, "session_unavailable")
assertFactoryStops("OwnerSession", function() error("session boom") end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session" }, "factory_threw")
assertFactoryStops("AdvancementSession", function() return { ok = true, session = {} } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session", "advancement" }, "invalid_factory_result")
assertFactoryStops("AdvancementSession", function() return { ok = false, code = "advancement_unavailable", detail = "owner rejected" } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session", "advancement" }, "advancement_unavailable")
assertFactoryStops("AdvancementSession", function() error("advancement boom") end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session", "advancement" }, "factory_threw")
assertFactoryStops("AdminSession", function() return { ok = true, session = {} } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session", "advancement", "admin" }, "invalid_factory_result")
assertFactoryStops("AdminSession", function() return { ok = true, session = { inspect = function() end, request = function() end }, private = {} } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session", "advancement", "admin" }, "invalid_factory_result")
assertFactoryStops("AdminSession", function() return { ok = true, session = { inspect = function() end, request = function() end, private = {} } } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session", "advancement", "admin" }, "invalid_factory_result")
assertFactoryStops("AdminSession", function() return { ok = false, code = "admin_unavailable", detail = "owner rejected" } end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session", "advancement", "admin" }, "admin_unavailable")
assertFactoryStops("AdminSession", function() error("admin boom") end, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot", "ap", "processor", "source", "session", "advancement", "admin" }, "factory_threw")

do
    local dependencies, fixture = makeDependencies(function(values, returned)
        values.OwnerSnapshot.create = function()
            returned.calls[#returned.calls + 1] = "snapshot"
            return { ok = false, code = "snapshot_unavailable", detail = "catalog rejected" }
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, "snapshot explicit failure returned")
    assertEqual(result.code, "snapshot_unavailable", "snapshot explicit failure code")
    assertEqual(result.detail, "catalog rejected", "snapshot explicit failure detail")
    sequenceEquals(fixture.calls, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot" }, "snapshot explicit failure stops graph")
end

do
    local dependencies, fixture = makeDependencies(function(values, returned)
        values.OwnerSnapshot.create = function()
            returned.calls[#returned.calls + 1] = "snapshot"
            return { ok = false, code = "snapshot_unavailable" }
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, "snapshot malformed failure returned")
    assertEqual(result.code, "snapshot_unavailable", "snapshot malformed failure keeps explicit code")
    assertEqual(result.detail, "OwnerSnapshot.create failed", "snapshot malformed failure gets stable detail")
    sequenceEquals(fixture.calls, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot" }, "snapshot malformed failure stops graph")
end

do
    local dependencies, fixture = makeDependencies(function(values, returned)
        values.OwnerSnapshot.create = function()
            returned.calls[#returned.calls + 1] = "snapshot"
            error("snapshot boom")
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, "snapshot throw contained")
    assertEqual(result.code, "factory_threw", "snapshot throw code")
    assertEqual(result.detail, "OwnerSnapshot.create threw", "snapshot throw detail")
    sequenceEquals(fixture.calls, { "store", "settings", "character", "record", "inheritance", "accounting", "snapshot" }, "snapshot throw stops graph")
end

do
    local dependencies, fixture = makeDependencies(function(values, returned)
        values.WorldSettings.create = function()
            returned.calls[#returned.calls + 1] = "settings"
            error("factory boom")
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, "factory throw contained")
    assertEqual(result.code, "factory_threw", "factory throw code")
    sequenceEquals(fixture.calls, { "store", "settings" }, "factory throw stops later work")
end

do
    local registrations = 0
    local installs = 0
    local loads = 0
    local saves = 0
    local synchronizations = 0
    local projections = 0
    local recoveries = 0
    local loadedRecoveries = 0
    local playerInitializations = 0
    local sessionReadiness = 0
    local sessionSnapshots = 0
    local sessionQueries = 0
    local sessionClears = 0
    local advancementRequests = 0
    local commands = 0
    local dependencies, fixture = makeDependencies(function(values, returned)
        values.environment.register = function()
            registrations = registrations + 1
        end
        values.environment.globals.sendClientCommand = function()
            commands = commands + 1
        end
        values.environment.globals.sendServerCommand = function()
            commands = commands + 1
        end
        returned.store.load = function()
            loads = loads + 1
            return { ok = true, state = {} }
        end
        returned.store.save = function()
            saves = saves + 1
            return { ok = true }
        end
        returned.accountingMode.synchronizeLoaded = function()
            synchronizations = synchronizations + 1
            return { ok = true }
        end
        returned.ownerSnapshot.project = function()
            projections = projections + 1
            return { ok = true, snapshot = {} }
        end
        returned.apService.recover = function()
            recoveries = recoveries + 1
            return { ok = true }
        end
        returned.apService.recoverLoadedState = function()
            loadedRecoveries = loadedRecoveries + 1
            return { ok = true }
        end
        returned.source.install = function()
            installs = installs + 1
            return { ok = true }
        end
        returned.source.initializePlayer = function()
            playerInitializations = playerInitializations + 1
            return { ok = true }
        end
        returned.ownerSession.ready = function()
            sessionReadiness = sessionReadiness + 1
            return { ok = true }
        end
        returned.ownerSession.snapshot = function()
            sessionSnapshots = sessionSnapshots + 1
            return { ok = true }
        end
        returned.ownerSession.isReady = function()
            sessionQueries = sessionQueries + 1
            return false
        end
        returned.ownerSession.clearPlayer = function()
            sessionClears = sessionClears + 1
            return { ok = true }
        end
        returned.advancementSession.request = function()
            advancementRequests = advancementRequests + 1
            return { ok = true }
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertTrue(result.ok, "source graph created")
    assertSame(result.services.xpSource, fixture.source, "created source exposed")
    assertEqual(registrations, 0, "composition registers no event")
    assertEqual(installs, 0, "composition does not install source")
    assertEqual(loads, 0, "composition does not load state")
    assertEqual(saves, 0, "composition does not save state")
    assertEqual(synchronizations, 0, "composition does not synchronize accounting mode")
    assertEqual(projections, 0, "composition does not project a snapshot")
    assertEqual(recoveries, 0, "composition does not recover state")
    assertEqual(loadedRecoveries, 0, "composition does not recover loaded state")
    assertEqual(playerInitializations, 0, "composition does not initialize a player")
    assertEqual(sessionReadiness, 0, "composition does not ready a player")
    assertEqual(sessionSnapshots, 0, "composition does not snapshot a player")
    assertEqual(sessionQueries, 0, "composition does not query a player")
    assertEqual(sessionClears, 0, "composition does not clear a player")
    assertEqual(advancementRequests, 0, "composition does not request advancement")
    assertEqual(commands, 0, "composition sends no commands")
end

do
    local dependencies = makeDependencies()
    local result = ServiceComposition.create(dependencies)
    result.services.awardProcessor.process = function()
        return { ok = false, code = "", detail = "" }
    end
    local handled = result.services.awardHandler.process({}, { perkId = "Cooking" })
    assertFalse(handled.ok, "malformed processor failure rejected")
    assertEqual(handled.code, "invalid_processor_result", "malformed processor failure code")
    assertTrue(type(handled.detail) == "string" and handled.detail ~= "", "malformed processor failure detail")
end

do
    local dependencies = makeDependencies(function(values)
        values.AdvancementSession.create = function()
            return setmetatable({ ok = true, session = { request = function() end } }, {})
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, "advancement metatable result rejected")
    assertEqual(result.code, "invalid_factory_result", "advancement metatable result code")
end

do
    local dependencies = makeDependencies(function(values)
        values.AdvancementSession.create = function()
            return { ok = true, session = { request = function() end }, private = {} }
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, "advancement extra result rejected")
    assertEqual(result.code, "invalid_factory_result", "advancement extra result code")
end

do
    local dependencies = makeDependencies(function(values)
        values.AdvancementSession.create = function()
            return { ok = true, session = { request = function() end, private = {} } }
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, "advancement private service rejected")
    assertEqual(result.code, "invalid_factory_result", "advancement private service code")
end

do
    local dependencies = makeDependencies(function(values)
        values.AdvancementSession = setmetatable({}, { __index = function() error("hostile") end })
    end)
    local result = ServiceComposition.create(dependencies)
    assertFalse(result.ok, "hostile advancement lookup contained")
    assertEqual(result.code, "invalid_dependencies", "hostile advancement lookup code")
end

do
    local providerReads = 0
    local processorSettings = nil
    local dependencies, fixture = makeDependencies(function(values, returned)
        values.WorldSettings = {
            create = function(argument)
                returned.calls[#returned.calls + 1] = "settings"
                returned.arguments.settings = argument
                return WorldSettings.create(argument)
            end,
        }
        values.worldSettingsProvider = {
            read = function()
                providerReads = providerReads + 1
                return {
                    survivorMultiplier = 2,
                    fitnessStrengthNormalization = 91,
                    automaticCurveNormalization = true,
                    allotmentMode = "Free",
                    globalLimit = 0,
                    perSkillDefault = 0,
                    perSkillOverrides = {},
                }
            end,
        }
        values.normalizationByPerk = { Cooking = 347.5 }
        returned.processor.process = function(_, _, settings)
            processorSettings = settings
            returned.processorCalls[#returned.processorCalls + 1] = {}
            return { ok = true, survivorXp = 3 }
        end
    end)
    local result = ServiceComposition.create(dependencies)
    assertTrue(result.ok, "real WorldSettings composes")
    dependencies.normalizationByPerk.Cooking = 1
    local handled = result.services.awardHandler.process({}, { perkId = "Cooking" })
    assertTrue(handled.ok, "real settings award succeeds")
    assertEqual(providerReads, 1, "real settings provider read once")
    assertEqual(#fixture.processorCalls, 1, "processor boundary once with real settings")
    assertEqual(processorSettings.normalization, 347.5, "normalization delegated to WorldSettings")
    assertEqual(processorSettings.survivorMultiplier, 2, "multiplier delegated to WorldSettings")
    assertFalse(processorSettings.postMax.enabled, "post-max setting delegated to WorldSettings")
end

do
    local addXp = function() end
    local addXpNoMultiplier = function() end
    local eventRegistrations = 0
    local addXpEvent = {
        Add = function()
            eventRegistrations = eventRegistrations + 1
        end,
    }
    local dependencies, fixture = makeDependencies(function(values, returned)
        values.environment.globals.addXp = addXp
        values.environment.globals.addXpNoMultiplier = addXpNoMultiplier
        values.environment.globals.Events = { AddXP = addXpEvent }
        values.EventDerivedXpSource = {
            create = function(argument)
                returned.calls[#returned.calls + 1] = "source"
                returned.arguments.source = argument
                return EventDerivedXpSource.create(argument)
            end,
        }
    end)
    local result = ServiceComposition.create(dependencies)
    assertTrue(result.ok, "real event-derived source composes")
    assertSame(fixture.arguments.source.mutationScope, dependencies.MutationScope, "real source receives lowercase mutationScope")
    assertEqual(fixture.arguments.source.MutationScope, nil, "real source receives no wrong-case scope")
    assertEqual(eventRegistrations, 0, "real source construction registers no AddXP observer")
    assertSame(dependencies.environment.globals.addXp, addXp, "real source construction leaves addXp unchanged")
    assertSame(dependencies.environment.globals.addXpNoMultiplier, addXpNoMultiplier, "real source construction leaves addXpNoMultiplier unchanged")
    local status = result.services.xpSource.status()
    assertFalse(status.installed, "real source remains uninstalled")
end

return assertionCount
