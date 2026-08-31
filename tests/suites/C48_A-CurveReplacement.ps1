[pscustomobject]@{
    Label = 'C48-A Same-ID curve replacement'
    Spec = 'tests/regression/CurveReplacementSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'StateCodec'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/StateCodec.lua' },
        [pscustomobject]@{ Global = 'PlayerStateStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/PlayerStateStore.lua' },
        [pscustomobject]@{ Global = 'ServerPlayerRecordStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/ServerPlayerRecordStore.lua' },
        [pscustomobject]@{ Global = 'NaturalLedger'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/NaturalLedger.lua' },
        [pscustomobject]@{ Global = 'SurvivorEconomy'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/SurvivorEconomy.lua' },
        [pscustomobject]@{ Global = 'Allotment'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/Allotment.lua' },
        [pscustomobject]@{ Global = 'PostMax'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/PostMax.lua' },
        [pscustomobject]@{ Global = 'MutationScope'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/MutationScope.lua' },
        [pscustomobject]@{ Global = 'ActualObservation'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/ActualObservation.lua' },
        [pscustomobject]@{ Global = 'ApTransaction'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Advancement/ApTransaction.lua' },
        [pscustomobject]@{ Global = 'SupportedAwardProcessor'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/XP/SupportedAwardProcessor.lua' }
    )
}
