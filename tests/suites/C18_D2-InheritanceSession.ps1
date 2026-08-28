[pscustomobject]@{
    Label = 'C18-D2 InheritanceSession'
    Spec = 'tests/runtime/InheritanceSessionSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'InheritanceSession'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/InheritanceSession.lua' },
        [pscustomobject]@{ Global = 'CharacterInheritanceStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/CharacterInheritanceStore.lua' },
        [pscustomobject]@{ Global = 'InheritanceRecordStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/InheritanceRecordStore.lua' },
        [pscustomobject]@{ Global = 'PlayerStateStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/PlayerStateStore.lua' },
        [pscustomobject]@{ Global = 'StateCodec'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/StateCodec.lua' },
        [pscustomobject]@{ Global = 'InheritancePolicy'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/InheritancePolicy.lua' }
        [pscustomobject]@{ Global = 'Build42InheritanceIdentity'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Adapters/Build42InheritanceIdentity.lua' }
    )
}
