[pscustomobject]@{
    Label = 'C46-C Free accounting integration'
    Spec = 'tests/runtime/FreeAccountingIntegrationSpec.lua'
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
            Global = 'PostMax'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/PostMax.lua'
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
            Global = 'AccountingMode'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/AccountingMode.lua'
        }
        [pscustomobject]@{
            Global = 'ApTransaction'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Advancement/ApTransaction.lua'
        }
        [pscustomobject]@{
            Global = 'SupportedAwardProcessor'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/XP/SupportedAwardProcessor.lua'
        }
        [pscustomobject]@{
            Global = 'OwnerSession'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/OwnerSession.lua'
        }
    )
}
