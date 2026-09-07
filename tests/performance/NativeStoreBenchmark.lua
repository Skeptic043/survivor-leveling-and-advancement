local function state(skills)
    local result = StateCodec.fresh()
    for index = 1, skills do
        result.perks["Skill" .. index] = { adapterId = "vanilla", adapterVersion = 1,
            curveFingerprint = "curve:1", effectiveMaximum = 10,
            naturalPosition = 123, highWaterPosition = 123, observedPosition = 123,
            activeTargets = {}, postMaxFullRateUsed = 0 }
    end
    return result
end
for _, skills in ipairs({ 2, 10, 32 }) do
    for _, population in ipairs({ 1, 100, 1000 }) do
        local root = { schemaVersion = 3, worldId = "world:test", players = {} }
        for index = 1, population do
            root.players["user" .. index] = { [0] = { schemaVersion = 2,
                initialized = true, deathRecorded = false, incarnationId = "inc:" .. index,
                persistenceRevision = 1, state = state(skills) } }
        end
        local built = ServerPlayerRecordStore.create({ codec = StateCodec,
            identity = { resolve = function(player)
                return { ok = true, owner = { kind = "mp",
                    primaryLoginUsername = player.name, profileIndex = 0 } }
            end },
            legacyStateStore = { load = function() return { ok = false } end },
            legacyCharacterStore = { inspect = function() return { ok = false } end },
            getOrCreate = function() return root end,
            add = function(_, value) root = value end,
            generateIncarnationId = function() return "unused:uuid" end,
        })
        assert(built.ok)
        local player = { name = "user1", getModData = function() return {} end }
        local samples = {}
        for index = 1, 250 do
            local started = benchClock()
            local loaded = built.stateStore.load(player)
            assert(loaded.ok, loaded.code)
            local saved = built.stateStore.save(player, loaded.state)
            assert(saved.ok, saved.code)
            if index > 50 then samples[#samples + 1] = benchClock() - started end
        end
        table.sort(samples)
        print("profiles=" .. population .. " skills=" .. skills
            .. " load+save wall_ms median=" .. samples[100]
            .. " p95=" .. samples[190] .. " max=" .. samples[200])
    end
end
return 1
