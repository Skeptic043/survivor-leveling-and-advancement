[pscustomobject]@{
    Label = 'C90 Player Stats XP'
    Spec = 'tests/xp/PlayerStatsXpSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'NativePlayerStatsAddXP'; Path = 'tests/.build/vanilla-player-stats-add-xp.lua' }
        [pscustomobject]@{ Global = 'StateCodec'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/StateCodec.lua' }
        [pscustomobject]@{ Global = 'NaturalLedger'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/NaturalLedger.lua' }
        [pscustomobject]@{ Global = 'SurvivorEconomy'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/SurvivorEconomy.lua' }
        [pscustomobject]@{ Global = 'Allotment'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/Allotment.lua' }
        [pscustomobject]@{ Global = 'MutationScope'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/MutationScope.lua' }
        [pscustomobject]@{ Global = 'ActualObservation'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/ActualObservation.lua' }
        [pscustomobject]@{ Global = 'PlayerStateStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/PlayerStateStore.lua' }
        [pscustomobject]@{ Global = 'AccountingMode'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/AccountingMode.lua' }
        [pscustomobject]@{ Global = 'VanillaAdapter'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Adapters/VanillaProgressionAdapter.lua' }
        [pscustomobject]@{ Global = 'ApTransaction'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Advancement/ApTransaction.lua' }
        [pscustomobject]@{ Global = 'SupportedAwardProcessor'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/XP/SupportedAwardProcessor.lua' }
        [pscustomobject]@{ Global = 'EventDerivedXpSource'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/XP/EventDerivedXpSource.lua' }
        [pscustomobject]@{ Global = 'Build42AdminSkillUi'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/UI/Build42AdminSkillUi.lua' }
    )
}
