[pscustomobject]@{
    Label = 'C10-F Build42NormalizationSnapshot'
    Spec = 'tests/adapters/Build42NormalizationSnapshotSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'SurvivorEconomy'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/SurvivorEconomy.lua' }
        [pscustomobject]@{ Global = 'Build42NormalizationSnapshot'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Adapters/Build42NormalizationSnapshot.lua' }
    )
}
