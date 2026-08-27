[pscustomobject]@{
    Label = 'C13-G Build 42 single-player admin'
    Spec = 'tests/runtime/Build42LifecycleSpec.lua'
    Sources = @(
        [pscustomobject]@{
            Global = 'Build42Lifecycle'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/Build42Lifecycle.lua'
        }
    )
}
