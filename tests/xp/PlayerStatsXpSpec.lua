local assertions = 0
local function expect(value, label)
    assertions = assertions + 1
    if not value then error(label, 0) end
end
local function equal(value, wanted, label)
    expect(value == wanted, label .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end
local function ok(value, label)
    expect(value and value.ok, label .. ': ' .. tostring(value and value.code))
    return value
end

local function fixture(multiplier, checked, options)
    options = options or {}
    local h = { awards = {}, settings = { accountingMode = 'Tracked', normalization = options.normalization or 1, survivorMultiplier = 1 }, reports = {}, nativeCalls = 0 }
    local player = { position = 0, level = 0, data = {} }
    local steps = {75,150,300,750,1500,3000,4500,6000,7500,9000}
    local thresholds = {[0] = 0}
    for level = 1,10 do thresholds[level] = thresholds[level-1] + steps[level] end
    if options.nearCap then
        player.position, player.level = thresholds[10]-1, 9
    end
    local perk = { id = options.perkId or 'Farming' }
    function perk:getId() return self.id end
    function perk:getType() return self end
    function perk:getXpForLevel(level) return steps[level] or -1 end
    function perk:getTotalXpForLevel(level) return thresholds[level] or -1 end
    function player:getModData() return self.data end
    function player:getPerkLevel() return self.level end
    function player:getUsername() return 'test' end
    local callbacks = {}
    local event = { Add = function(fn) callbacks[#callbacks+1] = fn end,
        Remove = function(fn) for i=#callbacks,1,-1 do if callbacks[i]==fn then table.remove(callbacks,i) end end end }
    function h.emit(target, targetPerk, amount)
        if targetPerk.id ~= perk.id then
            target.otherPosition=(target.otherPosition or 0)+amount
            for _, callback in ipairs(callbacks) do callback(target,targetPerk,amount) end
            return
        end
        local before = target.position
        target.position = math.max(0, math.min(thresholds[10], before + amount))
        if target == player then
            target.level = 0
            while target.level < 10 and target.position >= thresholds[target.level+1] do target.level = target.level+1 end
        end
        for _, callback in ipairs(callbacks) do callback(target, targetPerk, target.position-before) end
    end
    local xp = { getXP = function() return player.position end,
        setXPToLevel = function(_, _, level) player.position = thresholds[level] end }
    function xp:AddXP(targetPerk, amount, first, multipliers, third, fourth)
        equal(targetPerk, perk, 'native perk')
        expect(first == false and third == false and fourth == false, 'native flags unchanged')
        h.nativeCalls = h.nativeCalls+1
        if h.nested then local nested=h.nested; h.nested=nil; nested() end
        if h.throwNative then error(h.throwNative, 0) end
        -- Verified native gate and cap behavior, not a loaded engine simulation.
        if amount >= 0 and player.position >= thresholds[10] then return end
        h.emit(player, perk, multipliers and amount*0.25*multiplier or amount)
    end
    function player:getXp() return xp end
    function player:LevelPerk() self.level = self.level+1 end
    local built = ok(VanillaAdapter.build(perk), 'adapter')
    local described = ok(VanillaAdapter.describe(built.handle), 'description')
    local resolver = { loadOptions = { loadedPerks = { [perk.id] = {
        adapterId=described.adapterId, adapterVersion=described.adapterVersion,
        curveFingerprint=described.curveFingerprint, effectiveMaximum=10 } } } }
    function resolver.resolve(id) return {ok=id==perk.id, adapter=VanillaAdapter, handle=built.handle} end
    local store = ok(PlayerStateStore.create(StateCodec), 'store').store
    local initial = StateCodec.fresh()
    initial.survivor.level = 20
    ok(store.save(player, initial), 'seed')
    local mode = ok(AccountingMode.create({store=store, ActualObservation=ActualObservation}), 'mode').service
    local purchases = ok(ApTransaction.create({store=store,resolver=resolver,NaturalLedger=NaturalLedger,
        SurvivorEconomy=SurvivorEconomy,Allotment=Allotment,MutationScope=MutationScope,
        ActualObservation=ActualObservation,AccountingMode=mode}), 'purchases').service
    local processor = ok(SupportedAwardProcessor.create({store=store,resolver=resolver,NaturalLedger=NaturalLedger,
        SurvivorEconomy=SurvivorEconomy,MutationScope=MutationScope,ActualObservation=ActualObservation,
        recoveryService=purchases,AccountingMode=mode}), 'processor').service
    function h.load() return ok(store.load(player,resolver.loadOptions), 'load').state end
    function h.buy()
        ok(purchases.spend(player,{requestId='purchase',perkId=perk.id,expectedRevision=h.load().revision},
            {mode='Global',globalLimit=3}), 'purchase')
    end
    if options.buy then h.buy() end
    local globals = {Events={AddXP=event}, addXp=function(target,p,amount) h.emit(target,p,amount) end,
        addXpNoMultiplier=function(target,p,amount) h.emit(target,p,amount) end}
    local source = EventDerivedXpSource.create({environment={globals=globals},
        authority={describe=function() return {ok=true,authoritative=not options.multiplayer} end},
        playerIdentity={isPlayer=function(target) return type(target)=='table' and target.position~=nil end},
        perkIdentity={resolve=function(p) return {ok=true,perkId=p.id} end},
        positionReader={read=function(target,id) return {ok=true,position=id==perk.id and target.position or (target.otherPosition or 0)} end},
        positionArithmetic={add=function(before,amount) return {ok=true,positionAfter=before+amount,moved=amount~=0} end},
        sandboxMultiplier={resolve=function() return {ok=true,multiplier=multiplier} end},
        mutationScope=MutationScope,
        awardHandler={process=function(target, award)
            h.awards[#h.awards+1]=award
            if target~=player or award.perkId~=perk.id then return {ok=true} end
            local result=processor.process(target,award,h.settings)
            ok(result,'process accepted event')
            return result
        end}})
    expect(source~=nil,'source')
    ok(source.install(),'install source')
    if not options.multiplayer then ok(source.initializePlayer(player,{perk}),'initialize') end
    local stats = {onOptionMouseDown=function() end,setVisible=function() end}
    NativePlayerStatsAddXP(stats,function() return options.multiplayer==true end,function(command) h.command=command end)
    local native=stats.onAddXP
    stats.onAddXP=function(...)
        native(...)
        return 'native-result',nil,7
    end
    stats.instance={char=player,loadPerks=function() h.loads=(h.loads or 0)+1 end}
    local owner={requestAdmin=function() error('XP must not request accounting clear',0) end,
        adminStatus=function() return {ok=true} end,setAdminResultListener=function() return {ok=true} end,
        invokeWithRoute=function(...) h.scopes=(h.scopes or 0)+1; return source.invokeWithRoute(...) end}
    h.integration=ok(Build42AdminSkillUi.create({PlayerStats=stats,owner=owner,
        getSpecificPlayer=function(slot) return slot==0 and player or nil end,
        isClient=function() return options.multiplayer==true end,report=function(code) h.reports[#h.reports+1]=code end}), 'UI').integration
    ok(h.integration.install(),'install UI')
    function h.grant(amount, useMultipliers)
        if useMultipliers==nil then useMultipliers=checked end
        return stats:onAddXP(nil,perk,amount,false,useMultipliers)
    end
    h.player,h.perk,h.source,h.stats,h.globals,h.maximum=player,perk,source,stats,globals,thresholds[10]
    return h
end

for _, id in ipairs({'Farming','Glassmaking','Fitness','Strength'}) do
    for _, multiplier in ipairs({0.5,1,2,4}) do
        for _, checked in ipairs({false,true}) do
            local h=fixture(multiplier,checked,{perkId=id,buy=true})
            local first,second,third=h.grant(5)
            local applied=checked and 5*0.25*multiplier or 5
            equal(h.awards[1].survivorCreditBase,checked and 1.25 or 5,'checkbox provenance '..id..' '..multiplier..' '..tostring(checked))
            equal(h.player.position,75+applied,'native skill XP unchanged')
            equal(h.load().perks[id].naturalPosition,applied,'blue catch-up uses applied XP')
            equal(h.load().survivor.xpIntoLevel,checked and 1.25 or 5,'composed Survivor credit')
            equal(#h.load().perks[id].activeTargets,1,'XP grant preserves unfinished accounting')
            equal(h.load().survivor.spent,1,'XP grant never refunds AP')
            expect(first=='native-result' and second==nil and third==7,'all prior returns preserved')
            ok(h.integration.install(),'repeat UI install')
            h.grant(5)
            equal(h.nativeCalls,2,'idempotent wrapping')
        end
    end
end

for _, checked in ipairs({false,true}) do
    local h=fixture(4,checked,{nearCap=true})
    h.grant(5)
    equal(h.player.position,h.maximum,'native cap clipping')
    equal(h.awards[1].appliedDelta,1,'only clipped XP is applied')
    equal(h.awards[1].survivorCreditBase,checked and 0.25 or 1,'only clipped event credited')
    h.grant(5)
    equal(#h.awards,1,'no award beyond native cap')
end

do
    local h=fixture(4,false,{buy=true})
    h.grant(0)
    h.grant('')
    h.grant(nil)
    equal(#h.awards,0,'zero and empty inputs fabricate no award')
    h.grant(-5)
    equal(h.player.position,70,'native negative XP remains native')
    equal(h.load().survivor.xpIntoLevel,0,'negative XP gives no Survivor credit')
    local succeeded=pcall(h.grant,'invalid')
    expect(not succeeded,'native invalid amount error propagates')
    h.throwNative={native='error'}
    local called,err=pcall(h.grant,5)
    expect(not called and err==h.throwNative,'native error object preserved')
    h.throwNative=nil
    local count=#h.awards
    h.globals.addXp(h.player,h.perk,4)
    equal(h.awards[count+1].survivorCreditBase,1,'error cleanup restores ordinary route')
end

do
    local h=fixture(4,false)
    local other={position=0}
    local otherPerk={id='Other'}
    ok(h.source.initializePlayer(other,{h.perk}),'other player ready')
    ok(h.source.initializePlayer(h.player,{h.perk,otherPerk}),'other perk ready')
    h.nested=function()
        h.grant(5,true)
        h.emit(other,h.perk,4)
        h.emit(h.player,otherPerk,4)
        h.globals.addXp(h.player,h.perk,4)
        h.globals.addXpNoMultiplier(h.player,h.perk,4)
    end
    h.grant(5,false)
    equal(h.awards[1].survivorCreditBase,1.25,'nested checked overrides outer unchecked')
    equal(h.awards[2].survivorCreditBase,1,'scope excludes other player')
    equal(h.awards[3].survivorCreditBase,1,'scope excludes other perk')
    equal(h.awards[4].survivorCreditBase,1,'nested global checked overrides outer route')
    equal(h.awards[5].survivorCreditBase,4,'nested global unchecked route')
    equal(h.awards[6].survivorCreditBase,5,'outer unchecked restored after nesting')
end

for _, normalization in ipairs({0,0.067230769,1.5}) do
    local h=fixture(4,false,{normalization=normalization,buy=true})
    h.grant(5)
    equal(h.load().survivor.xpIntoLevel,5*normalization,'contribution and normalization preserved')
    equal(h.load().perks.Farming.naturalPosition,5,'disabled contribution still catches up')
end

do
    local h=fixture(4,false)
    h.globals.addXp=function() end
    h.grant(5)
    equal(h.nativeCalls,1,'source hook loss preserves exactly one native call')
    equal(#h.awards,0,'lost source ownership disables credit')
    expect(not h.source.verifyOwnership().ok,'source hook loss reported')
end

do
    local h=fixture(4,false)
    local old=h.stats.onAddXP
    h.stats.onAddXP=function(...) return old(...) end
    h.grant(5)
    equal(h.nativeCalls,1,'UI hook replacement preserves prior once')
    equal(h.scopes,nil,'lost UI ownership disables scoped capability')
    expect(not h.integration.install().ok,'lost UI hook cannot reinstall')
    equal(h.reports[1],'player_stats_hook_ownership_lost','hook loss reported')
end

do
    local h=fixture(4,false,{multiplayer=true})
    local first,second,third=h.grant(5)
    equal(h.nativeCalls,1,'MP retains native call')
    equal(h.scopes,nil,'MP does not use SP provenance')
    expect(h.command and h.command:find('-false',1,true),'MP retains native server command')
    expect(first=='native-result' and second==nil and third==7,'MP preserves returns')
end

return assertions
