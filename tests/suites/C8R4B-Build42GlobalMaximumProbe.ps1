$root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$sourcePath = Join-Path $root "Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Adapters/Build42GlobalMaximumProbe.lua"
$sourceText = [IO.File]::ReadAllText($sourcePath)
$forbidden = "Events\.|addXp|addXpNoMultiplier|OnTick|ModData|sendClientCommand|sendServerCommand|ISUI|print\s*\(|TODO|journal|retry|recipe|exercise"
if ($sourceText -match $forbidden) {
    throw "C8R4B probe contains an out-of-scope mechanism"
}

[pscustomobject]@{
    Label = "C8R4B Build42GlobalMaximumProbe"
    Spec = "tests/adapters/Build42GlobalMaximumProbeSpec.lua"
    Sources = @(
        [pscustomobject]@{
            Global = "Build42GlobalMaximumProbe"
            Path = "Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Adapters/Build42GlobalMaximumProbe.lua"
        }
    )
}
