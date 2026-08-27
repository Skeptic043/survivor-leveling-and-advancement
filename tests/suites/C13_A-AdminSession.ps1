[pscustomobject]@{
    Label = 'C13-A AdminSession'
    Spec = 'tests/runtime/AdminSessionSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'NaturalLedger'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/NaturalLedger.lua' }
        [pscustomobject]@{ Global = 'SurvivorEconomy'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/SurvivorEconomy.lua' }
        [pscustomobject]@{ Global = 'AdminSession'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/AdminSession.lua' }
    )
}
