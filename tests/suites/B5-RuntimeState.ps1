[pscustomobject]@{
    Label = 'B5 RuntimeState'
    Spec = 'tests/state/RuntimeStateSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'StateCodec'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/StateCodec.lua' },
        [pscustomobject]@{ Global = 'PlayerStateStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/PlayerStateStore.lua' },
        [pscustomobject]@{ Global = 'MutationScope'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/MutationScope.lua' }
    )
}
