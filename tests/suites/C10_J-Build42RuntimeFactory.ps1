[pscustomobject]@{
    Label = 'C10-J Build42RuntimeFactory'
    Spec = 'tests/runtime/Build42RuntimeFactorySpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'ActualWorldSettingsProvider'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Adapters/Build42WorldSettingsProvider.lua' }
        [pscustomobject]@{ Global = 'ActualWorldSettings'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/WorldSettings.lua' }
        [pscustomobject]@{ Global = 'Build42RuntimeFactory'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/Build42RuntimeFactory.lua' })
}
