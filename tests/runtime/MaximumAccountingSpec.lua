local assertions = 0
local function expect(value, label)
    assertions = assertions + 1
    if not value then error(label, 0) end
end
local function ok(value, label)
    expect(value and value.ok, label .. ": " .. tostring(value and value.code) .. ":" .. tostring(value and value.detail))
    return value
end

local function fixture(server, maximum, modeName)
    local steps = maximum == 10 and {75,150,300,750,1500,3000,4500,6000,7500,9000}
        or {10,20,30,40,20}
    local thresholds = {[0]=0}
    for level=1,maximum do thresholds[level]=thresholds[level-1]+steps[level] end
    local baseline = maximum-4
    local perk = {}
    function perk:getXpForLevel(level) return steps[level] or -1 end
    function perk:getTotalXpForLevel(level) return thresholds[level] or -1 end
    local player = {level=baseline, position=thresholds[baseline], data={}}
    function player:getPerkLevel(_) return self.level end
    function player:getModData() return self.data end
    local xp = {}
    function xp:getXP(_) return player.position end
    function xp:setXPToLevel(_, level) player.position=thresholds[level] end
    function player:getXp() return xp end
    function player:LevelPerk(_) self.level=self.level+1 end
    local built = ok(VanillaAdapter.build(perk), "adapter build")
    local described = ok(VanillaAdapter.describe(built.handle), "adapter description")
    local resolver = {loadOptions={loadedPerks={Axe={adapterId=described.adapterId,
        adapterVersion=described.adapterVersion, curveFingerprint=described.curveFingerprint,
        effectiveMaximum=maximum}}}}
    function resolver.resolve(id)
        expect(id=="Axe", "selected perk")
        return {ok=true, adapter=VanillaAdapter, handle=built.handle}
    end
    local localStore = ok(PlayerStateStore.create(StateCodec), "local store").store
    local store = localStore
    if server then
        local root = {}
        local id=0
        store=ok(ServerPlayerRecordStore.create({codec=StateCodec,
            identity={resolve=function() return {ok=true,owner={kind="mp",primaryLoginUsername="test",profileIndex=0}} end},
            legacyStateStore=localStore,
            legacyCharacterStore={inspect=function() return {ok=false} end},
            getOrCreate=function() return root end,
            add=function(_, value) root=value end,
            generateIncarnationId=function() id=id+1; return "test:"..id end,
        }), "server store").stateStore
    end
    local initial=StateCodec.fresh()
    initial.survivor.level=20
    initial.survivor.xpIntoLevel=12.5
    ok(store.save(player,initial), "seed")
    local mode=ok(AccountingMode.create({store=store, ActualObservation=ActualObservation}), "mode").service
    local purchases=ok(ApTransaction.create({store=store, resolver=resolver, NaturalLedger=NaturalLedger,
        SurvivorEconomy=SurvivorEconomy, Allotment=Allotment, MutationScope=MutationScope,
        ActualObservation=ActualObservation, AccountingMode=mode}), "purchases").service
    local processor=ok(SupportedAwardProcessor.create({store=store, resolver=resolver,
        NaturalLedger=NaturalLedger, SurvivorEconomy=SurvivorEconomy, MutationScope=MutationScope,
        ActualObservation=ActualObservation, recoveryService=purchases, AccountingMode=mode}), "processor").service
    local config=modeName=="Global" and {mode="Global",globalLimit=3}
        or {mode="PerSkill",perSkillDefault=3}
    for level=baseline+1,maximum-1 do
        local current=ok(store.load(player,resolver.loadOptions), "before spend").state
        ok(purchases.spend(player,{requestId="max-"..level,perkId="Axe",expectedRevision=current.revision},config), "buy "..level)
        expect(player.level==level, "bought level")
    end
    local function load() return ok(store.load(player,resolver.loadOptions), "load").state end
    return {player=player,store=store,load=load,mode=mode,processor=processor,
        resolver=resolver,thresholds=thresholds,maximum=maximum}
end

for _, server in ipairs({false,true}) do
    for _, modeName in ipairs({"Global","PerSkill"}) do
        for _, free in ipairs({false,true}) do
            for _, maximum in ipairs({5,10}) do
                local env=fixture(server,maximum,modeName)
                local old=env.load()
                expect(#old.perks.Axe.activeTargets==3, "three purchases occupy three slots")
                if free then ok(env.mode.synchronizeLoaded(env.player,old,"Free"), "Free transition") end
                local before=env.player.position
                local maximumPosition=env.thresholds[maximum]
                local earned=maximumPosition-before
                env.player.position=maximumPosition
                env.player.level=maximum
                local result=ok(env.processor.process(env.player,{perkId="Axe",survivorCreditBase=earned,
                    appliedDelta=earned,actualPositionBefore=before,actualPositionAfter=maximumPosition},
                    {accountingMode=free and "Free" or "Tracked",normalization=1,survivorMultiplier=1}), "natural maximum")
                local state=env.load()
                expect(#state.perks.Axe.activeTargets==0, "all max accounting released")
                expect(state.perks.Axe.naturalPosition==maximumPosition and state.perks.Axe.observedPosition==maximumPosition, "clear anchors maximum")
                expect(state.survivor.spent==3, "no AP refund or extra spending")
                expect(result.survivorXp==earned, "only accepted crossing XP credited")
                expect(#result.clearedTargetIds==3, "crossing reports every cleared target")
                expect(env.player.level==maximum and env.player.position==maximumPosition, "clear does not touch engine progression")
                expect(state.perks.Axe.postMaxFullRateUsed==0, "legacy counter preserved")
            end
        end
    end
end

return assertions
