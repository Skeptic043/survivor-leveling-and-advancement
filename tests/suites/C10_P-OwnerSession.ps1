[pscustomobject]@{
    Label = 'C10-P OwnerSession'
    Spec = 'tests/runtime/OwnerSessionSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'NaturalLedger'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/NaturalLedger.lua' }
        [pscustomobject]@{ Global = 'OwnerSession'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/OwnerSession.lua' }
    )
}
