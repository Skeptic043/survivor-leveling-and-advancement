[pscustomobject]@{
    Label = 'C4 Supported Award Processor'
    Spec = 'tests/xp/SupportedAwardProcessorSpec.lua'
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
            Global = 'SupportedAwardProcessor'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/XP/SupportedAwardProcessor.lua'
        }
    )
}
