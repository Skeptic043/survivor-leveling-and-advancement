[pscustomobject]@{
    Label = 'C78 Admin skill UI Bootstrap'
    Spec = 'tests/ui/AdminSkillUiBootstrapHarness.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'C78AdminSkillHarnessInit'; Path = 'tests/ui/AdminSkillUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C78AdminSkillBootstrapFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/AdminSkillUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C78AdminSkillHarnessFirst'; Path = 'tests/ui/AdminSkillUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C78AdminSkillBootstrapReload'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/AdminSkillUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C78AdminSkillHarnessReload'; Path = 'tests/ui/AdminSkillUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C78AdminSkillBootstrapCollision'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/AdminSkillUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'AdminSkillUiBootstrapHarness'; Path = 'tests/ui/AdminSkillUiBootstrapHarness.lua' }
    )
}
