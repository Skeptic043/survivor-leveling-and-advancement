local assertions = 0
local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 0) end
end
local function yes(value, message) equal(value, true, message) end

local function fixture()
    local player = { position = 200 }
    local nativePerk = {}
    local state = {
        schemaVersion = 3, accountingMode = "Tracked", revision = 3,
        survivor = { level = 4, xpIntoLevel = 25, spent = 2 },
        perks = {
            Fitness = { adapterId = "test", adapterVersion = 1, curveFingerprint = "fitness",
                effectiveMaximum = 10, naturalPosition = 100, highWaterPosition = 100,
                observedPosition = 200, postMaxFullRateUsed = 7,
                activeTargets = { { targetId = "paid", targetLevel = 2, targetPosition = 200 } } },
            Strength = { adapterId = "test", adapterVersion = 1, curveFingerprint = "strength",
                effectiveMaximum = 10, naturalPosition = 20, highWaterPosition = 20,
                observedPosition = 50, postMaxFullRateUsed = 0,
                activeTargets = { { targetId = "other", targetLevel = 1, targetPosition = 50 } } },
        },
        orphanedPerks = {},
    }
    local env = { state = state, player = player }
    local cursor = 200
    local source = { rebasePlayerPerk = function(actualPlayer, perk)
        equal(actualPlayer, player, "native cursor player")
        equal(perk, nativePerk, "native cursor perk")
        cursor = player.position
        return { ok = true, detail = { perkId = "Fitness", position = cursor } }
    end }
    local store = {}
    function store.load()
        local result = StateCodec.decode(StateCodec.encode(env.state).state)
        yes(result.ok, "load validates stored schema")
        return result
    end
    function store.save(_, candidate)
        local encoded = StateCodec.encode(candidate)
        yes(encoded.ok, "save encodes candidate")
        env.state = StateCodec.decode(encoded.state).state
        return { ok = true }
    end
    local created = AdminSession.create({
        store = store,
        catalog = {
            resolver = { loadOptions = { loadedPerks = { Fitness = true, Strength = true } } },
            positionReader = { read = function() return { ok = true, position = player.position } end },
            perkFor = function() return { ok = true, perk = nativePerk } end,
        },
        ownerSession = { isReady = function() return true end },
        SurvivorEconomy = SurvivorEconomy, NaturalLedger = NaturalLedger,
        ActualObservation = ActualObservation, xpSource = source,
    })
    yes(created.ok, "admin session creates")
    env.session = created.session
    function env.clear(revision)
        return env.session.request(player, { kind = "clearAdvancementSlots",
            perkId = "Fitness", expectedRevision = revision or 3 })
    end
    function env.xp(delta)
        player.position = player.position + delta
        local before = env.state.perks.Fitness
        local result = NaturalLedger.applySupported(before, delta, player.position)
        yes(result.ok, "native XP transition remains valid")
        before.naturalPosition, before.highWaterPosition = result.state.naturalPosition, result.state.highWaterPosition
        before.activeTargets, before.observedPosition = result.state.activeTargets, player.position
        return result
    end
    function env.reload()
        env.state = StateCodec.decode(StateCodec.encode(env.state).state).state
        ActualObservation.clearPlayer(player)
        local saved = env.state.perks.Fitness
        ActualObservation.set(player, "Fitness", saved.observedPosition)
        cursor = saved.observedPosition
    end
    function env.cursor() return cursor end
    return env
end

for _, delta in ipairs({ -100, 100 }) do
    local before = fixture()
    yes(before.clear().ok, "clear before native command succeeds")
    before.xp(delta)
    local after = fixture()
    after.xp(delta)
    yes(after.clear().ok, "clear after native command succeeds")
    equal(before.state.perks.Fitness.naturalPosition, after.state.perks.Fitness.naturalPosition,
        "clear commutes with native signed XP")
    equal(before.state.perks.Fitness.observedPosition, after.state.perks.Fitness.observedPosition,
        "durable cursor commutes with native signed XP")
    equal(#before.state.perks.Fitness.activeTargets, 0, "edited skill has no blue targets")
    equal(before.state.perks.Strength.activeTargets[1].targetId, "other", "unrelated blue target survives")
    equal(before.state.survivor.spent, 2, "clear never refunds AP")
    equal(before.state.survivor.xpIntoLevel, 25, "clear generates no Survivor XP")
    equal(after.cursor(), after.player.position, "clear aligns native event cursor")
    equal(ActualObservation.get(after.player, "Fitness").position, after.player.position,
        "clear aligns runtime observation")
    after.reload()
    local nextAward = after.xp(1)
    equal(nextAward.effect.eligibleApplied, 1, "next gameplay XP after reload is eligible")
    equal(#after.state.perks.Fitness.activeTargets, 0, "reload and gameplay cannot resurrect cleared targets")
end

do
    local env = fixture()
    env.xp(-100)
    env.state.revision = 4
    env.state.perks.Fitness.activeTargets = {
        { targetId = "new-ap", targetLevel = 2, targetPosition = 200 },
    }
    local result = env.clear(3)
    equal(result.applied, false, "late clear rejects an intervening AP revision")
    equal(result.code, "stale_revision", "late clear reports revision conflict")
    equal(env.state.perks.Fitness.activeTargets[1].targetId, "new-ap", "late clear preserves new AP target")
end
return assertions
