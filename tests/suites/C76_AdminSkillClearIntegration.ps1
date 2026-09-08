[pscustomobject]@{
    Label = 'C76 Selected skill clear integration'
    Spec = 'tests/runtime/AdminSkillClearIntegrationSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'NaturalLedger'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/NaturalLedger.lua' }
        [pscustomobject]@{ Global = 'SurvivorEconomy'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/SurvivorEconomy.lua' }
        [pscustomobject]@{ Global = 'StateCodec'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/StateCodec.lua' }
        [pscustomobject]@{ Global = 'ActualObservation'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/ActualObservation.lua' }
        [pscustomobject]@{ Global = 'AdminSession'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/AdminSession.lua' }
    )
}
