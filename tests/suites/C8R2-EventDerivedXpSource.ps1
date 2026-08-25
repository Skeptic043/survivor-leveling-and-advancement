$root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$sourcePath = Join-Path $root "Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/XP/EventDerivedXpSource.lua"
$sourceText = [IO.File]::ReadAllText($sourcePath)
$forbidden = "InferredXpSource|ExactXpClaims|exactXpClaims|isEnabled|baseAward|rawBase|print\s*\(|ModData|sendClientCommand|sendServerCommand|ISUI|\bprevious\b|(?:positionAfter|after)\s*-\s*eventAmount|batch\.appliedDelta"
if ($sourceText -match $forbidden) {
    throw "C8R2 source contains a forbidden legacy or out-of-scope mechanism"
}
if ($sourceText -notmatch "survivorCreditBase") {
    throw "C8R2 source is missing survivorCreditBase envelopes"
}

[pscustomobject]@{
    Label = "C8R2 EventDerivedXpSource"
    Spec = "tests/xp/EventDerivedXpSourceSpec.lua"
    Sources = @(
        [pscustomobject]@{
            Global = "EventDerivedXpSource"
            Path = "Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/XP/EventDerivedXpSource.lua"
        }
        [pscustomobject]@{
            Global = "ReloadedEventDerivedXpSource"
            Path = "Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/XP/EventDerivedXpSource.lua"
        }
    )
}
