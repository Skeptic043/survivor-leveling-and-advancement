[pscustomobject]@{
    Label = 'C13-F Build 42 admin lifecycle'
    Spec = 'tests/runtime/Build42LifecycleSpec.lua'
    Sources = @(
        [pscustomobject]@{
            Global = 'Build42Lifecycle'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/Build42Lifecycle.lua'
        }
    )
}
