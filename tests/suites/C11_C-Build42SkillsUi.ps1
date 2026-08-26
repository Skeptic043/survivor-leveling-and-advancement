[pscustomobject]@{
    Label = 'C11-C Build42 Skills UI'
    Spec = 'tests/ui/Build42SkillsUiSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'Build42SkillsUi'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/UI/Build42SkillsUi.lua' }
        [pscustomobject]@{ Global = 'C11CHarnessInit'; Path = 'tests/ui/SkillsUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C11CBootstrapFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/SkillsUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C11CHarnessAfterFirst'; Path = 'tests/ui/SkillsUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C11CBootstrapReload'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/SkillsUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C11CHarnessAfterReload'; Path = 'tests/ui/SkillsUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C11CBootstrapCollision'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/SkillsUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C11CHarnessAfterCollision'; Path = 'tests/ui/SkillsUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C11CBootstrapThrow'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/SkillsUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C11CHarnessAfterThrow'; Path = 'tests/ui/SkillsUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C11CBootstrapCreateThrow'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/SkillsUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'SkillsUiBootstrapHarness'; Path = 'tests/ui/SkillsUiBootstrapHarness.lua' }
    )
}
