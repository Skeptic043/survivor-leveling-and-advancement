[pscustomobject]@{
    Label = 'C10-T Build42Lifecycle'
    Spec = 'tests/runtime/Build42LifecycleSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'Build42Lifecycle'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/Build42Lifecycle.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapHarness'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapReload'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCollisionSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCollision'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapThrowSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapThrow'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformed'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedOwnerSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedOwner'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapExtraOwnerSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapExtraOwner'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapIndexOwnerSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapIndexOwner'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
    )
}
