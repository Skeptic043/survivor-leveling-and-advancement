[pscustomobject]@{
    Label = 'C20-B Watch UI Bootstrap'
    Spec = 'tests/ui/WatchUiBootstrapHarness.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'C20BWatchHarnessInit'; Path = 'tests/ui/WatchUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C20BWatchBootstrapFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/WatchUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C20BWatchHarnessAfterFirst'; Path = 'tests/ui/WatchUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C20BWatchBootstrapReload'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/WatchUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C20BWatchHarnessAfterReload'; Path = 'tests/ui/WatchUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C20BWatchCollision'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/WatchUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C20BWatchHarnessAfterCollision'; Path = 'tests/ui/WatchUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C20BWatchOptionThrow'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/WatchUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'C20BWatchHarnessAfterThrow'; Path = 'tests/ui/WatchUiBootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C20BWatchOptionMissing'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/WatchUiBootstrap.lua' }
        [pscustomobject]@{ Global = 'WatchUiBootstrapHarness'; Path = 'tests/ui/WatchUiBootstrapHarness.lua' }
    )
}
