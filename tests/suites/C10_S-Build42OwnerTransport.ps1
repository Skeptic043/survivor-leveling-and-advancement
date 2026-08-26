[pscustomobject]@{
    Label = 'C10-S Build42OwnerTransport'
    Spec = 'tests/runtime/Build42OwnerTransportSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'Build42OwnerTransport'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/Build42OwnerTransport.lua' },
        [pscustomobject]@{ Global = 'ClientOwnerState'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/ClientOwnerState.lua' }
    )
}
