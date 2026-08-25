[pscustomobject]@{
    Label = 'C2 SurvivorEconomy'
    Spec = 'tests/core/SurvivorEconomySpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'SurvivorEconomy'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/SurvivorEconomy.lua' }
        [pscustomobject]@{ Global = 'Allotment'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/Allotment.lua' }
        [pscustomobject]@{ Global = 'PostMax'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/PostMax.lua' }
    )
}
