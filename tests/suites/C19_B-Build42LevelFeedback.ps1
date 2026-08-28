$translationPath = Join-Path $PSScriptRoot '..\..\Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\Translate\EN\IG_UI.json'
$translations = Get-Content -Raw -LiteralPath $translationPath | ConvertFrom-Json
if ($translations.IGUI_SLA_LevelGain_Singular -ne 'Survivor Level +%1' -or
    $translations.IGUI_SLA_LevelGain_Plural -ne 'Survivor Levels +%1' -or
    $translations.IGUI_SLA_LevelGain_AP -ne 'AP +%1') {
    throw 'C19-B guard: localized level/AP notification copy changed'
}
$sourcePath = Join-Path $PSScriptRoot '..\..\Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\Adapters\Build42LevelFeedback.lua'
$source = [IO.File]::ReadAllText($sourcePath)
if ($source -match '(?i)\bplaySound\b|\baddSound\b|OnTick|EveryOneMinute|EveryTenMinutes') {
    throw 'C19-B guard: level feedback must remain causally event-driven and avoid generic sound APIs'
}
if ($source -notmatch 'player\.playGainExperienceLevelSound' -or
    $source -notmatch 'pcall\(playLevelSound,\s*player\)') {
    throw 'C24 guard: level feedback must use the exact target player native level-gain sound'
}

[pscustomobject]@{
    Label = 'C19-B Build 42 level feedback'
    Spec = 'tests/adapters/Build42LevelFeedbackSpec.lua'
    Sources = @(
        [pscustomobject]@{
            Global = 'Build42LevelFeedback'
            Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Adapters/Build42LevelFeedback.lua'
        }
    )
}
