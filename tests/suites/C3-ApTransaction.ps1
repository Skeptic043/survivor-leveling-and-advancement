[pscustomobject]@{
    Label = 'C3 AP transaction'
    Spec = 'tests/advancement/ApTransactionSpec.lua'
    Sources = @(
        [pscustomobject]@{
            Global = 'NaturalLedger'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/NaturalLedger.lua'
        }
        [pscustomobject]@{
            Global = 'SurvivorEconomy'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/SurvivorEconomy.lua'
        }
        [pscustomobject]@{
            Global = 'Allotment'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/Allotment.lua'
        }
        [pscustomobject]@{
            Global = 'MutationScope'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/MutationScope.lua'
        }
        [pscustomobject]@{
            Global = 'ActualObservation'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/ActualObservation.lua'
        }
        [pscustomobject]@{
            Global = 'ApTransaction'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Advancement/ApTransaction.lua'
        }
    )
}
