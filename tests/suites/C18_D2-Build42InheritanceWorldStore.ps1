[pscustomobject]@{
    Label = 'C18-D2 Build42InheritanceWorldStore'
    Spec = 'tests/adapters/Build42InheritanceWorldStoreSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'Build42InheritanceWorldStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Adapters/Build42InheritanceWorldStore.lua' },
        [pscustomobject]@{ Global = 'InheritanceRecordStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/InheritanceRecordStore.lua' }
    )
}
