[pscustomobject]@{
    Label = 'C58 Client Options Bootstrap'
    Spec = 'tests/ui/ClientOptionsBootstrapHarness.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'ClientOptions'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/ClientOptions.lua' }
        [pscustomobject]@{ Global = 'C58OptionsInit'; Path = 'tests/ui/ClientOptionsBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C58SkillsFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/SkillsUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C58OptionsAfter0'; Path = 'tests/ui/ClientOptionsBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C58WatchSecond'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/WatchUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C58OptionsAfter1'; Path = 'tests/ui/ClientOptionsBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C58WatchFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/WatchUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C58OptionsAfter2'; Path = 'tests/ui/ClientOptionsBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C58SkillsSecond'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/SkillsUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C58OptionsAfter3'; Path = 'tests/ui/ClientOptionsBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C58SkillsContrastFailure'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/SkillsUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C58OptionsAfter4'; Path = 'tests/ui/ClientOptionsBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C58WatchContrastFailure'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/WatchUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C58OptionsAfter5'; Path = 'tests/ui/ClientOptionsBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C58SkillsOptionsFailure'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/SkillsUiBootstrap.lua' }
    )
}
