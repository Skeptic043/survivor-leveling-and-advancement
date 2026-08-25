[pscustomobject]@{
    Label = 'C10-E ServiceComposition'
    Spec = 'tests/runtime/ServiceCompositionSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'WorldSettings'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/WorldSettings.lua' }
        [pscustomobject]@{ Global = 'EventDerivedXpSource'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/XP/EventDerivedXpSource.lua' }
        [pscustomobject]@{ Global = 'ServiceComposition'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/ServiceComposition.lua' }
    )
}
