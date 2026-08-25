local assertions = 0

local function assertTrue(value, message)
    assertions = assertions + 1
    if value ~= true then
        error(message or "expected true")
    end
end

local function assertFalse(value, message)
    assertions = assertions + 1
    if value ~= false then
        error(message or "expected false")
    end
end

local function assertEqual(expected, actual, message)
    assertions = assertions + 1
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertNil(value, message)
    assertions = assertions + 1
    if value ~= nil then
        error(message or "expected nil")
    end
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local function award(perk, amount)
    return {
        getPerk = function(self)
            return perk
        end,
        getAmount = function(self)
            return amount
        end,
    }
end

local function recipe(awards)
    return {
        getXPAwardCount = function(self)
            return #awards
        end,
        getXPAward = function(self, index)
            return awards[index + 1]
        end,
    }
end

local function action(kind, player, recipeValue)
    local value = {
        character = player,
        priorCalls = 0,
    }
    local logic = {
        getRecipe = function(self)
            return recipeValue
        end,
    }
    if kind == "handcraft" then
        value.logic = logic
    else
        value.buildPanelLogic = logic
    end
    return value
end

local function newFixture(authoritative)
    local fixture = {
        authorityCalls = 0,
        addCalls = 0,
        observers = {},
        handled = {},
        readCalls = {},
        positions = {},
        priorArgs = {},
        claims = {},
        releases = {},
    }

    local function positionTable(player)
        local current = fixture.positions[player]
        if current == nil then
            current = {}
            fixture.positions[player] = current
        end
        return current
    end

    function fixture.setPosition(player, perkId, value)
        positionTable(player)[perkId] = value
    end

    function fixture.emit(player, perk, delta)
        local positions = positionTable(player)
        positions[perk.id] = (positions[perk.id] or 0) + delta
        for index = 1, #fixture.observers do
            fixture.observers[index](player, perk, delta)
        end
    end

    fixture.handcraftPrior = function(...)
        local args = pack(...)
        local receiver = args[1]
        receiver.priorCalls = receiver.priorCalls + 1
        fixture.priorArgs[#fixture.priorArgs + 1] = args
        if receiver.priorBehavior ~= nil then
            return receiver.priorBehavior(...)
        end
        return "handcraft", nil, "done"
    end

    fixture.buildPrior = function(...)
        local args = pack(...)
        local receiver = args[1]
        receiver.priorCalls = receiver.priorCalls + 1
        fixture.priorArgs[#fixture.priorArgs + 1] = args
        if receiver.priorBehavior ~= nil then
            return receiver.priorBehavior(...)
        end
        return "build", nil, "done"
    end

    fixture.event = {
        Add = function(callback)
            fixture.addCalls = fixture.addCalls + 1
            fixture.observers[#fixture.observers + 1] = callback
            if fixture.throwOnAdd then
                error("add failed")
            end
        end,
    }
    fixture.globals = {
        ISHandcraftAction = { performRecipe = fixture.handcraftPrior },
        ISBuildIsoEntity = { create = fixture.buildPrior },
        Events = { AddXP = fixture.event },
    }
    fixture.dependencies = {
        environment = { globals = fixture.globals },
        authority = {
            isAuthoritative = function()
                fixture.authorityCalls = fixture.authorityCalls + 1
                return { ok = true, authoritative = authoritative ~= false }
            end,
        },
        perkIdentity = {
            resolve = function(perk)
                if fixture.resolveFailure or type(perk) ~= "table" or type(perk.id) ~= "string" then
                    return { ok = false }
                end
                return { ok = true, perkId = perk.id }
            end,
        },
        positionReader = {
            read = function(player, perkId)
                local key = tostring(player) .. ":" .. perkId
                fixture.readCalls[key] = (fixture.readCalls[key] or 0) + 1
                if fixture.failReadAt ~= nil and fixture.readCalls[key] == fixture.failReadAt then
                    return { ok = false }
                end
                return { ok = true, position = positionTable(player)[perkId] or 0 }
            end,
        },
        awardHandler = {
            process = function(player, envelope)
                fixture.handled[#fixture.handled + 1] = { player = player, envelope = envelope }
                if fixture.handlerBehavior ~= nil then
                    return fixture.handlerBehavior(player, envelope)
                end
                if fixture.handlerThrows then
                    error("handler failed")
                end
                if fixture.handlerFails then
                    return { ok = false, code = "private_detail" }
                end
                return { ok = true }
            end,
        },
        exactXpClaims = {
            claim = function(token, player, perk, amount)
                fixture.claims[#fixture.claims + 1] = {
                    token = token, player = player, perk = perk, amount = amount,
                }
                if fixture.claimThrows then
                    error("claim failed")
                elseif fixture.claimFalse then
                    return false
                elseif fixture.claimFails then
                    return { ok = false }
                end
                return { ok = true }
            end,
            release = function(token)
                fixture.releases[#fixture.releases + 1] = token
                if fixture.releaseThrows then
                    error("release failed")
                elseif fixture.releaseFails then
                    return { ok = false }
                end
                return { ok = true }
            end,
        },
    }
    fixture.source = RecipeXpSource.create(fixture.dependencies)
    return fixture
end

do
    local source = RecipeXpSource.create(nil)
    local installed = source.install()
    assertFalse(installed.ok, "nil dependencies fail")
    assertEqual("invalid_dependencies", installed.code)
    assertEqual("invalid_dependencies", source.status().lastCode)

    local fixture = newFixture(true)
    fixture.dependencies.perkIdentity.resolve = nil
    source = RecipeXpSource.create(fixture.dependencies)
    installed = source.install()
    assertFalse(installed.ok, "partial dependencies fail")
    assertEqual(0, fixture.authorityCalls, "dependency failure precedes authority")
end

do
    local fixture = newFixture(true)
    fixture.dependencies.authority.isAuthoritative = function()
        fixture.authorityCalls = fixture.authorityCalls + 1
        error("authority unavailable")
    end
    local source = RecipeXpSource.create(fixture.dependencies)
    local installed = source.install()
    assertFalse(installed.ok)
    assertEqual("authority_failed", installed.code)
    assertEqual(0, fixture.addCalls)
    fixture.dependencies.authority.isAuthoritative = function()
        fixture.authorityCalls = fixture.authorityCalls + 1
        return { ok = true, authoritative = true }
    end
    local retried = source.install()
    assertTrue(retried.ok, "a later finite install gate retries authority")
    assertEqual("installed", retried.code)
    assertEqual(2, fixture.authorityCalls)
    assertEqual(1, fixture.addCalls)
end

do
    local fixture = newFixture(false)
    local handcraftPrior = fixture.globals.ISHandcraftAction.performRecipe
    local buildPrior = fixture.globals.ISBuildIsoEntity.create
    local installed = fixture.source.install()
    assertTrue(installed.ok)
    assertEqual("non_authoritative", installed.code)
    assertEqual(1, fixture.authorityCalls)
    assertEqual(0, fixture.addCalls)
    assertEqual(handcraftPrior, fixture.globals.ISHandcraftAction.performRecipe)
    assertEqual(buildPrior, fixture.globals.ISBuildIsoEntity.create)
    assertFalse(fixture.source.status().captureEnabled)
    assertEqual("non_authoritative", fixture.source.status().ownershipReason)
    assertEqual("non_authoritative", fixture.source.install().code)
    assertEqual(1, fixture.authorityCalls, "authority is checked once")
    assertTrue(fixture.source.verifyOwnership().ok)
end

do
    local fixture = newFixture(true)
    fixture.globals.ISHandcraftAction = nil
    local installed = fixture.source.install()
    assertFalse(installed.ok)
    assertEqual("handcraft_unavailable", installed.code)
    assertEqual(0, fixture.addCalls)
end

do
    local fixture = newFixture(true)
    fixture.globals.ISBuildIsoEntity.create = false
    local installed = fixture.source.install()
    assertFalse(installed.ok)
    assertEqual("build_unavailable", installed.code)
    assertEqual(0, fixture.addCalls)
end

do
    local fixture = newFixture(true)
    fixture.globals.Events.AddXP.Add = nil
    local installed = fixture.source.install()
    assertFalse(installed.ok)
    assertEqual("event_unavailable", installed.code)
    assertEqual(fixture.handcraftPrior, fixture.globals.ISHandcraftAction.performRecipe)
    assertEqual(fixture.buildPrior, fixture.globals.ISBuildIsoEntity.create)
end

do
    local fixture = newFixture(true)
    fixture.throwOnAdd = true
    local first = fixture.source.install()
    assertFalse(first.ok)
    assertEqual("event_registration_ambiguous", first.code)
    assertEqual(1, fixture.addCalls)
    assertEqual(fixture.handcraftPrior, fixture.globals.ISHandcraftAction.performRecipe)
    assertTrue(fixture.source.status().registrationAmbiguous)
    local second = fixture.source.install()
    assertFalse(second.ok)
    assertEqual(1, fixture.addCalls, "ambiguous event is not retried")

    fixture.throwOnAdd = false
    local replacement = {
        Add = function(callback)
            fixture.addCalls = fixture.addCalls + 1
            fixture.observers[#fixture.observers + 1] = callback
        end,
    }
    fixture.globals.Events.AddXP = replacement
    local third = fixture.source.install()
    assertTrue(third.ok, "replacement event can be attempted")
    assertEqual("installed", third.code)
    assertEqual(2, fixture.addCalls)
    assertFalse(fixture.source.status().registrationAmbiguous)
end

do
    local fixture = newFixture(true)
    local installed = fixture.source.install()
    assertTrue(installed.ok)
    local handWrapper = fixture.globals.ISHandcraftAction.performRecipe
    local buildWrapper = fixture.globals.ISBuildIsoEntity.create
    assertTrue(handWrapper ~= fixture.handcraftPrior)
    assertTrue(buildWrapper ~= fixture.buildPrior)
    local again = fixture.source.install()
    assertTrue(again.ok)
    assertEqual("already_installed", again.code)
    assertEqual(1, fixture.addCalls)
    assertEqual(handWrapper, fixture.globals.ISHandcraftAction.performRecipe)
    assertEqual(buildWrapper, fixture.globals.ISBuildIsoEntity.create)
end

do
    local fixture = newFixture(true)
    local player = {}
    local carpentry = { id = "Carpentry" }
    local cooking = { id = "Cooking" }
    fixture.setPosition(player, "Carpentry", 10)
    fixture.setPosition(player, "Cooking", 20)
    fixture.source.install()
    local value = action("handcraft", player, recipe({
        award(carpentry, 2.5),
        award(carpentry, 3.5),
        award(cooking, -1),
    }))
    value.priorBehavior = function(self, first, second, third)
        assertEqual("alpha", first)
        assertNil(second)
        assertEqual("omega", third)
        fixture.emit(player, carpentry, 5)
        fixture.emit(player, carpentry, 7)
        fixture.emit(player, cooking, -0.5)
        return 41, nil, 43
    end
    local returned = pack(fixture.globals.ISHandcraftAction.performRecipe(value, "alpha", nil, "omega"))
    assertEqual(3, returned.n, "return arity preserved")
    assertEqual(41, returned[1])
    assertNil(returned[2])
    assertEqual(43, returned[3])
    assertEqual(1, value.priorCalls)
    assertEqual(4, fixture.priorArgs[1].n, "argument arity preserved")
    assertEqual(value, fixture.priorArgs[1][1])
    assertEqual("alpha", fixture.priorArgs[1][2])
    assertNil(fixture.priorArgs[1][3])
    assertEqual("omega", fixture.priorArgs[1][4])
    assertEqual(2, #fixture.handled, "repeated perk aggregates")
    local first = fixture.handled[1]
    assertEqual(player, first.player)
    assertEqual("Carpentry", first.envelope.perkId)
    assertEqual(6, first.envelope.baseAward, "metadata base stays isolated")
    assertEqual(12, first.envelope.appliedDelta, "event delta stays isolated")
    assertEqual(10, first.envelope.actualPositionBefore)
    assertEqual(22, first.envelope.actualPositionAfter)
    local second = fixture.handled[2]
    assertEqual("Cooking", second.envelope.perkId)
    assertEqual(-1, second.envelope.baseAward)
    assertEqual(-0.5, second.envelope.appliedDelta)
    assertEqual(20, second.envelope.actualPositionBefore)
    assertEqual(19.5, second.envelope.actualPositionAfter)
    assertEqual(2, fixture.readCalls[tostring(player) .. ":Carpentry"])
    assertEqual(2, fixture.readCalls[tostring(player) .. ":Cooking"])
    assertEqual("capture_ok", fixture.source.status().lastCode)
end

do
    local fixture = newFixture(true)
    local player = {}
    local perk = { id = "Cooking" }
    fixture.setPosition(player, perk.id, 3)
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(perk, 0) }))
    value.priorBehavior = function(self)
        fixture.emit(player, perk, 0)
    end
    fixture.globals.ISHandcraftAction.performRecipe(value)
    assertEqual(1, #fixture.handled)
    assertEqual(0, fixture.handled[1].envelope.baseAward)
    assertEqual(0, fixture.handled[1].envelope.appliedDelta)
    assertEqual(3, fixture.handled[1].envelope.actualPositionBefore)
    assertEqual(3, fixture.handled[1].envelope.actualPositionAfter)
end

do
    local fixture = newFixture(true)
    local player = {}
    local metal = { id = "MetalWelding" }
    fixture.setPosition(player, metal.id, 4)
    fixture.source.install()
    local value = action("build", player, recipe({ award(metal, 8) }))
    value.logic = { getRecipe = function() error("wrong field") end }
    value.priorBehavior = function(self)
        fixture.emit(player, metal, 2)
        return nil, "built"
    end
    local returned = pack(fixture.globals.ISBuildIsoEntity.create(value))
    assertEqual(2, returned.n)
    assertNil(returned[1])
    assertEqual("built", returned[2])
    assertEqual(1, #fixture.handled)
    assertEqual(8, fixture.handled[1].envelope.baseAward)
    assertEqual(2, fixture.handled[1].envelope.appliedDelta)
    assertEqual(4, fixture.handled[1].envelope.actualPositionBefore)
    assertEqual(6, fixture.handled[1].envelope.actualPositionAfter)
end

do
    local fixture = newFixture(true)
    fixture.source.install()
    local player = {}
    local value = action("handcraft", player, recipe({}))
    local returned = pack(fixture.globals.ISHandcraftAction.performRecipe(value))
    assertEqual(3, returned.n)
    assertEqual("handcraft", returned[1])
    assertNil(returned[2])
    assertEqual("done", returned[3])
    assertEqual(0, #fixture.handled)
    assertEqual("capture_ok", fixture.source.status().lastCode)
end

local function assertUnsupportedMutation(mutate)
    local fixture = newFixture(true)
    local player = {}
    local perk = { id = "Cooking" }
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(perk, 1) }))
    mutate(value)
    local originalLogic = value.logic
    local returned = fixture.globals.ISHandcraftAction.performRecipe(value)
    assertEqual("handcraft", returned)
    assertEqual(1, value.priorCalls)
    assertEqual(0, #fixture.handled)
    assertEqual(originalLogic, value.logic, "receiver remains unchanged")
    assertEqual("action_unsupported", fixture.source.status().lastCode)
end

local function invalidPerkIdCase(perkId)
    local fixture = newFixture(true)
    local player = {}
    local perk = { id = "source" }
    fixture.dependencies.perkIdentity.resolve = function()
        return { ok = true, perkId = perkId }
    end
    fixture.source = RecipeXpSource.create(fixture.dependencies)
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(perk, 1) }))
    fixture.globals.ISHandcraftAction.performRecipe(value)
    assertEqual(0, #fixture.handled)
    assertEqual("action_unsupported", fixture.source.status().lastCode)
end

invalidPerkIdCase("")
invalidPerkIdCase("Cooking Skill")
invalidPerkIdCase("mod/Skill")

assertUnsupportedMutation(function(value) value.logic = nil end)
assertUnsupportedMutation(function(value) value.logic.getRecipe = nil end)
assertUnsupportedMutation(function(value) value.logic.getRecipe = function() return nil end end)
assertUnsupportedMutation(function(value)
    value.logic.getRecipe = function()
        return { getXPAwardCount = function() return 1.5 end }
    end
end)
assertUnsupportedMutation(function(value)
    value.logic.getRecipe = function()
        return { getXPAwardCount = function() return 1 end, getXPAward = function() return nil end }
    end
end)
assertUnsupportedMutation(function(value)
    value.logic.getRecipe = function()
        return {
            getXPAwardCount = function() return 1 end,
            getXPAward = function() return { getPerk = function() return {} end } end,
        }
    end
end)
assertUnsupportedMutation(function(value)
    value.logic.getRecipe = function()
        return {
            getXPAwardCount = function() return 1 end,
            getXPAward = function() return award({ id = "Cooking" }, 0 / 0) end,
        }
    end
end)

local function ambiguityCase(events, expectedCode)
    local fixture = newFixture(true)
    local player = {}
    local first = { id = "First" }
    local second = { id = "Second" }
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(first, 2), award(second, 3) }))
    value.priorBehavior = function(self)
        for index = 1, #events do
            local event = events[index]
            local owner = event.owner == "other" and {} or player
            local perk = event.perk == "first" and first or event.perk == "second" and second or {}
            fixture.emit(owner, perk, event.delta)
        end
    end
    fixture.globals.ISHandcraftAction.performRecipe(value)
    assertEqual(0, #fixture.handled)
    assertEqual(expectedCode or "event_pair_ambiguous", fixture.source.status().lastCode)
end

ambiguityCase({ { perk = "first", delta = 1 } })
ambiguityCase({ { perk = "second", delta = 1 }, { perk = "first", delta = 1 } })
ambiguityCase({ { perk = "first", delta = 1 }, { perk = "other", delta = 1 } })
ambiguityCase({ { owner = "other", perk = "first", delta = 1 }, { perk = "second", delta = 1 } })
ambiguityCase({ { perk = "first", delta = 1 }, { perk = "second", delta = 1 }, { perk = "second", delta = 1 } })
ambiguityCase({ { perk = "first", delta = 0 / 0 }, { perk = "second", delta = 1 } })
ambiguityCase({ { perk = "first", delta = math.huge }, { perk = "second", delta = 1 } })

do
    local fixture = newFixture(true)
    local player = {}
    local perk = { id = "Cooking" }
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(perk, 1) }))
    value.priorBehavior = function(self)
        fixture.emit(player, perk, 1)
        error("prior exact failure")
    end
    local ok, thrown = pcall(fixture.globals.ISHandcraftAction.performRecipe, value)
    assertFalse(ok)
    assertEqual("prior exact failure", thrown)
    assertEqual(0, #fixture.handled)
    assertEqual(1, #fixture.releases, "prior error releases transaction token")
    assertEqual("prior_failed", fixture.source.status().lastCode)
end

do
    local fixture = newFixture(true)
    local player = {}
    local outerPerk = { id = "Carpentry" }
    local innerPerk = { id = "MetalWelding" }
    fixture.source.install()
    local inner = action("build", player, recipe({ award(innerPerk, 4) }))
    inner.priorBehavior = function(self)
        fixture.emit(player, innerPerk, 1.5)
        return "inner"
    end
    local outer = action("handcraft", player, recipe({ award(outerPerk, 7) }))
    outer.priorBehavior = function(self)
        assertEqual("inner", fixture.globals.ISBuildIsoEntity.create(inner))
        fixture.emit(player, outerPerk, 2.5)
        return "outer"
    end
    assertEqual("outer", fixture.globals.ISHandcraftAction.performRecipe(outer))
    assertEqual(2, #fixture.handled)
    assertEqual("MetalWelding", fixture.handled[1].envelope.perkId)
    assertEqual(1.5, fixture.handled[1].envelope.appliedDelta)
    assertEqual("Carpentry", fixture.handled[2].envelope.perkId)
    assertEqual(2.5, fixture.handled[2].envelope.appliedDelta)
    assertEqual(2, #fixture.claims, "nested events both claimed")
    assertTrue(fixture.claims[1].token ~= fixture.claims[2].token,
        "nested actions use distinct claim tokens")
    assertEqual(fixture.claims[1].token, fixture.releases[1], "inner token released first")
    assertEqual(fixture.claims[2].token, fixture.releases[2], "outer token released second")
end

do
    local fixture = newFixture(true)
    local player = {}
    local outerPerk = { id = "Carpentry" }
    local innerPerk = { id = "Cooking" }
    fixture.source.install()

    fixture.handlerBehavior = function(handlerPlayer, envelope)
        if envelope.perkId == innerPerk.id then
            fixture.emit(handlerPlayer, outerPerk, 50)
        end
        return { ok = true }
    end

    local inner = action("build", player, recipe({ award(innerPerk, 3) }))
    inner.priorBehavior = function(self)
        fixture.emit(player, innerPerk, 1)
    end
    local outer = action("handcraft", player, recipe({ award(outerPerk, 4) }))
    outer.priorBehavior = function(self)
        fixture.globals.ISBuildIsoEntity.create(inner)
        fixture.emit(player, outerPerk, 2)
    end

    fixture.globals.ISHandcraftAction.performRecipe(outer)
    assertEqual(2, #fixture.handled, "handler event does not corrupt outer pairing")
    assertEqual("Cooking", fixture.handled[1].envelope.perkId)
    assertEqual(1, fixture.handled[1].envelope.appliedDelta)
    assertEqual("Carpentry", fixture.handled[2].envelope.perkId)
    assertEqual(2, fixture.handled[2].envelope.appliedDelta, "handler event is ignored by outer capture")
    assertEqual(52, fixture.handled[2].envelope.actualPositionAfter)
end

do
    local fixture = newFixture(true)
    local player = {}
    local firstPerk = { id = "Cooking" }
    local nestedPerk = { id = "MetalWelding" }
    fixture.source.install()

    local nested = action("build", player, recipe({ award(nestedPerk, 6) }))
    nested.priorBehavior = function(self)
        fixture.emit(player, nestedPerk, 2)
    end
    fixture.handlerBehavior = function(handlerPlayer, envelope)
        if envelope.perkId == firstPerk.id then
            fixture.globals.ISBuildIsoEntity.create(nested)
        end
        return { ok = true }
    end

    local first = action("handcraft", player, recipe({ award(firstPerk, 5) }))
    first.priorBehavior = function(self)
        fixture.emit(player, firstPerk, 1)
    end
    fixture.globals.ISHandcraftAction.performRecipe(first)
    assertEqual(2, #fixture.handled, "nested recipe in handler remains capturable")
    assertEqual("Cooking", fixture.handled[1].envelope.perkId)
    assertEqual("MetalWelding", fixture.handled[2].envelope.perkId)
    assertEqual(2, fixture.handled[2].envelope.appliedDelta)
end

do
    local fixture = newFixture(true)
    local player = {}
    local perk = { id = "Cooking" }
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(perk, 1) }))
    value.priorBehavior = function(self)
        fixture.emit(player, perk, 1)
        return "vanilla"
    end
    fixture.handlerFails = true
    assertEqual("vanilla", fixture.globals.ISHandcraftAction.performRecipe(value))
    assertEqual("handler_failed", fixture.source.status().lastCode)
    fixture.handlerFails = false
    fixture.handlerThrows = true
    assertEqual("vanilla", fixture.globals.ISHandcraftAction.performRecipe(value))
    assertEqual("handler_failed", fixture.source.status().lastCode)
    assertEqual(2, #fixture.handled)
end

do
    local fixture = newFixture(true)
    local player = {}
    local perk = { id = "Cooking" }
    fixture.setPosition(player, perk.id, 5)
    fixture.failReadAt = 2
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(perk, 1) }))
    value.priorBehavior = function(self)
        fixture.emit(player, perk, 1)
        return "unchanged"
    end
    assertEqual("unchanged", fixture.globals.ISHandcraftAction.performRecipe(value))
    assertEqual(0, #fixture.handled)
    assertEqual("position_after_failed", fixture.source.status().lastCode)
end

do
    local fixture = newFixture(true)
    fixture.resolveFailure = true
    local player = {}
    local perk = { id = "Cooking" }
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(perk, 1) }))
    fixture.globals.ISHandcraftAction.performRecipe(value)
    assertEqual(0, #fixture.handled)
    assertEqual("action_unsupported", fixture.source.status().lastCode)
end

local function ownershipFixture()
    local fixture = newFixture(true)
    fixture.source.install()
    return fixture
end

do
    local fixture = ownershipFixture()
    local later = function() return "later" end
    fixture.globals.ISHandcraftAction.performRecipe = later
    local verified = fixture.source.verifyOwnership()
    assertFalse(verified.ok)
    assertEqual("ownership_lost", verified.code)
    assertEqual("handcraft_method_replaced", verified.detail)
    assertFalse(fixture.source.status().captureEnabled)
    assertEqual(later, fixture.globals.ISHandcraftAction.performRecipe)
    assertEqual("ownership_lost", fixture.source.install().code)
    assertEqual(later, fixture.globals.ISHandcraftAction.performRecipe)
end

do
    local fixture = ownershipFixture()
    fixture.globals.ISHandcraftAction = { performRecipe = fixture.globals.ISHandcraftAction.performRecipe }
    assertEqual("handcraft_table_replaced", fixture.source.verifyOwnership().detail)
end

do
    local fixture = ownershipFixture()
    fixture.globals.ISBuildIsoEntity.create = function() end
    assertEqual("build_method_replaced", fixture.source.verifyOwnership().detail)
end

do
    local fixture = ownershipFixture()
    fixture.globals.ISBuildIsoEntity = { create = fixture.globals.ISBuildIsoEntity.create }
    assertEqual("build_table_replaced", fixture.source.verifyOwnership().detail)
end

do
    local fixture = ownershipFixture()
    fixture.globals.Events.AddXP = { Add = function() end }
    local verified = fixture.source.verifyOwnership()
    assertEqual("event_replaced", verified.detail)
    assertFalse(fixture.source.status().eventOwned)
    fixture.globals.Events.AddXP = fixture.event
    assertEqual("ownership_lost", fixture.source.verifyOwnership().code, "disable is sticky")
end

do
    local fixture = ownershipFixture()
    local verified = fixture.source.verifyOwnership()
    assertTrue(verified.ok)
    assertEqual("ownership_ok", verified.code)
    local status = fixture.source.status()
    assertTrue(status.installed)
    assertTrue(status.captureEnabled)
    assertTrue(status.observerRegistered)
    assertTrue(status.handcraftOwned)
    assertTrue(status.buildOwned)
    assertTrue(status.eventOwned)
    assertEqual("owned", status.ownershipReason)
    assertNil(status.observer, "status excludes callable")
    assertNil(status.player, "status excludes player")
    assertNil(status.awards, "status excludes awards")
end

do
    local fixture = newFixture(true)
    local player = {}
    local perk = { id = "Cooking", marker = "perk" }
    local metadata = award(perk, 2)
    local recipeValue = recipe({ metadata })
    local value = action("handcraft", player, recipeValue)
    local originalLogic = value.logic
    local originalGetRecipe = value.logic.getRecipe
    local originalGetAward = recipeValue.getXPAward
    local originalGetPerk = metadata.getPerk
    fixture.source.install()
    value.priorBehavior = function(self)
        fixture.emit(player, perk, 1)
    end
    fixture.globals.ISHandcraftAction.performRecipe(value)
    assertEqual(originalLogic, value.logic)
    assertEqual(originalGetRecipe, value.logic.getRecipe)
    assertEqual(originalGetAward, recipeValue.getXPAward)
    assertEqual(originalGetPerk, metadata.getPerk)
    assertEqual("perk", perk.marker)
    assertEqual(2, metadata:getAmount())
end

do
    local fixture = newFixture(true)
    local player = {}
    local perk = { id = "Cooking" }
    fixture.setPosition(player, perk.id, 4)
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(perk, 2), award(perk, 2) }))
    value.priorBehavior = function(self)
        fixture.emit(player, perk, 2)
        fixture.emit(player, perk, 2)
        return "one", nil, "three"
    end
    local returned = pack(fixture.globals.ISHandcraftAction.performRecipe(value))
    assertEqual(3, returned.n, "successful claims preserve return arity")
    assertEqual(2, #fixture.claims, "repeated same-tuple events are distinct claims")
    assertEqual(fixture.claims[1].token, fixture.claims[2].token, "action claims share token")
    assertEqual(1, #fixture.releases, "successful action releases once")
    assertEqual(fixture.claims[1].token, fixture.releases[1], "released token is exact")
    assertEqual(1, #fixture.handled, "successful claims retain aggregate envelope")
    assertEqual(4, fixture.handled[1].envelope.baseAward, "aggregate base unchanged")
    assertEqual(4, fixture.handled[1].envelope.appliedDelta, "aggregate delta unchanged")
end

do
    local variants = {
        { field = "claimFalse", code = "claim_failed" },
        { field = "claimFails", code = "claim_failed" },
        { field = "claimThrows", code = "claim_threw" },
    }
    for index = 1, #variants do
        local fixture = newFixture(true)
        fixture[variants[index].field] = true
        local player = {}
        local perk = { id = "Cooking" }
        fixture.source.install()
        local value = action("build", player, recipe({ award(perk, 1) }))
        value.priorBehavior = function(self)
            fixture.emit(player, perk, 1)
            return "vanilla"
        end
        assertEqual("vanilla", fixture.globals.ISBuildIsoEntity.create(value),
            "claim failure preserves return " .. index)
        assertEqual(0, #fixture.handled, "claim failure suppresses envelope " .. index)
        assertEqual(1, #fixture.releases, "claim failure releases " .. index)
        assertEqual(variants[index].code, fixture.source.status().lastCode, "claim status " .. index)
    end
end

do
    local fixture = newFixture(true)
    local errorToken = "claim release prior failure"
    local player = {}
    local perk = { id = "Cooking" }
    fixture.source.install()
    local value = action("handcraft", player, recipe({ award(perk, 1) }))
    value.priorBehavior = function(self)
        fixture.emit(player, perk, 1)
        error(errorToken)
    end
    local ok, thrown = pcall(fixture.globals.ISHandcraftAction.performRecipe, value)
    assertFalse(ok, "prior error preserved")
    assertTrue(string.find(tostring(thrown), errorToken, 1, true) ~= nil, "prior error preserved exactly")
    assertEqual(1, #fixture.releases, "prior error releases")
    assertEqual(0, #fixture.handled, "prior error suppresses envelope")
end

do
    local variants = { "releaseFails", "releaseThrows" }
    for index = 1, #variants do
        local fixture = newFixture(true)
        fixture[variants[index]] = true
        local player = {}
        local perk = { id = "Cooking" }
        fixture.source.install()
        local value = action("handcraft", player, recipe({ award(perk, 1) }))
        value.priorBehavior = function(self)
            fixture.emit(player, perk, 1)
            return "vanilla"
        end
        assertEqual("vanilla", fixture.globals.ISHandcraftAction.performRecipe(value))
        assertEqual(1, #fixture.handled, "release failure retains envelope " .. index)
        assertEqual("claim_release_failed", fixture.source.status().lastCode)
    end
end

return assertions
