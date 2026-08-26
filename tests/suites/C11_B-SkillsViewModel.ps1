[pscustomobject]@{
    Label = 'C11-B Skills view model'
    Spec = 'tests/ui/SkillsViewModelSpec.lua'
    Sources = @(
        [pscustomobject]@{
            Global = 'ClientOwnerState'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/ClientOwnerState.lua'
        }
        [pscustomobject]@{
            Global = 'Allotment'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/Allotment.lua'
        }
        [pscustomobject]@{
            Global = 'SkillsViewModel'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/UI/SkillsViewModel.lua'
        }
    )
}
