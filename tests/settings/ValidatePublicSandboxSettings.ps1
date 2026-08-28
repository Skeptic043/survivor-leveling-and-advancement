Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mod = Join-Path $root 'Contents/mods/SurvivorLevelingAdvancement/42.20'
$optionsPath = Join-Path $mod 'media/sandbox-options.txt'
$infoPath = Join-Path $mod 'mod.info'
$jsonPath = Join-Path $mod 'media/lua/shared/Translate/EN/Sandbox.json'
$uiPath = Join-Path $mod 'media/lua/shared/Translate/EN/IG_UI.json'
$obsoleteUiPath = Join-Path $mod 'media/lua/shared/Translate/EN/IG_UI_EN.txt'

$assertions = 0
function Assert($condition, [string]$message) {
    $script:assertions++
    if (-not $condition) { throw "ASSERTION FAILED: $message" }
}

function Field([string]$body, [string]$name) {
    $m = [regex]::Match($body, "(?m)^\s*$([regex]::Escape($name))\s*=\s*(\{[^}]*\}|[^,\r\n]+)")
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value.Trim()
}

$ids = @('Fitness','Strength','Sprinting','Lightfoot','Nimble','Sneak','Axe','Blunt','SmallBlunt','LongBlade','SmallBlade','Spear','Maintenance','Farming','Husbandry','Woodwork','Carving','Cooking','Electricity','Doctor','FlintKnapping','Masonry','Mechanics','Blacksmith','Pottery','Tailoring','MetalWelding','Aiming','Reloading','Fishing','PlantScavenging','Tracking','Trapping','Butchering','Glassmaking')
$text = Get-Content -Raw $optionsPath
Assert ($text -match '(?m)^VERSION\s*=\s*1,\s*$') 'VERSION must be 1'
$blocks = @([regex]::Matches($text, '(?ms)^option\s+([^\s{]+)\s*\{(.*?)^\}'))
Assert ($blocks.Count -eq 43) 'exactly eight main and 35 per-skill options are required'

$main = @{
    'SurvivorXpMultiplier' = @('double','0','100','1','SLA')
    'FitnessStrengthContributionPercent' = @('double','0','100','6.7230769','SLA')
    'AutomaticCurveNormalization' = @('boolean','','','true','SLA')
    'EnableSurvivorLevelInheritance' = @('boolean','','','false','SLA')
    'SurvivorLevelRetainedPercent' = @('double','0','100','50','SLA')
    'AllotmentMode' = @('enum','','','1','SLA')
    'GlobalAdvancementLimit' = @('integer','0','100','3','SLA')
    'PerSkillDefaultLimit' = @('integer','0','10','1','SLA')
}
$seen = @()
foreach ($b in $blocks) {
    $name = $b.Groups[1].Value
    $body = $b.Groups[2].Value
    if ($name -match '^SurvivorLevelingAdvancement\.(SurvivorXpMultiplier|FitnessStrengthContributionPercent|AutomaticCurveNormalization|EnableSurvivorLevelInheritance|SurvivorLevelRetainedPercent|AllotmentMode|GlobalAdvancementLimit|PerSkillDefaultLimit)$') {
        $key = $Matches[1]; $seen += $key; $expected = $main[$key]
        Assert ((Field $body 'type') -eq $expected[0]) "$key type"
        if ($expected[1]) { Assert ((Field $body 'min') -eq $expected[1] -and (Field $body 'max') -eq $expected[2]) "$key range" }
        Assert ((Field $body 'default') -eq $expected[3]) "$key default"
        Assert ((Field $body 'page') -eq $expected[4]) "$key page"
        Assert (Field $body 'translation') "$key translation"
        if ($key -eq 'AllotmentMode') { Assert ((Field $body 'numValues') -eq '3' -and (Field $body 'valueTranslation')) 'allotment enum encoding' }
    }
}
Assert ((@($seen | Sort-Object -Unique) -join ',') -eq (($main.Keys | Sort-Object) -join ',')) 'exact eight main settings'

$actualIds = @($blocks | ForEach-Object { if ($_.Groups[1].Value -match '^SurvivorLevelingAdvancement\.PerSkillLimit_(.+)$') { $Matches[1] } })
Assert (($actualIds -join ',') -eq ($ids -join ',')) 'ordered vanilla override IDs'
foreach ($b in $blocks | Where-Object { $_.Groups[1].Value -match 'PerSkillLimit_' }) {
    $body = $b.Groups[2].Value
    Assert ((Field $body 'type') -eq 'enum' -and (Field $body 'numValues') -eq '12' -and (Field $body 'default') -eq '1') 'per-skill enum shape'
    Assert ((Field $body 'page') -eq 'SLA' -and (Field $body 'valueTranslation') -eq 'SLA_PerSkillLimit') 'per-skill page/value translation'
    Assert ((Field $body 'valueTranslation') -eq 'SLA_PerSkillLimit') 'per-skill enum value translation'
}
Assert ((@($blocks | ForEach-Object { Field $_.Groups[2].Value 'page' } | Where-Object { $_ -eq 'SLA' }).Count -eq 43)) 'all settings use the one SLA page'
Assert ($text -notmatch '(?m)^\s*page\s*=\s*SLA_PerSkill\s*,\s*$') 'no second sandbox page remains'

$info = @{}
foreach ($line in Get-Content $infoPath) { if ($line -match '^([^=]+)=(.*)$') { $info[$Matches[1]] = $Matches[2] } }
Assert (($info.Keys | Sort-Object) -join ',' -eq 'description,id,incompatible,name') 'metadata has only the approved fields'
Assert ($info.name -eq 'Survivor Leveling & Advancement' -and $info.id -eq 'SurvivorLevelingAdvancement') 'metadata name and id'
Assert (-not $info.ContainsKey('versionMin') -and -not $info.ContainsKey('versionMax')) 'metadata does not enforce patch bounds'
Assert ($info.description -eq 'Earn Survivor Levels through skill XP and spend Advancement Points to raise trainable skills.') 'metadata behavior description'
Assert ($info.incompatible -eq 'RpgSkillsSystemsB42,VanillaMenu') 'metadata blocks both conflicting RPG Skills Systems mod IDs'

$jsonText = Get-Content -Raw $jsonPath
$keys = [regex]::Matches($jsonText, '(?m)"((?:[^"\\]|\\.)*)"\s*:') | ForEach-Object { $_.Groups[1].Value }
Assert (@($keys | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'translation JSON has no duplicate keys'
$translations = $jsonText | ConvertFrom-Json
foreach ($b in $blocks) {
    foreach ($field in @('translation')) {
        $key = Field ($b.Groups[2].Value) $field
        Assert ($key -and $translations.("Sandbox_" + $key)) "automatic translation mapping $key"
    }
}
Assert ($translations.Sandbox_SLA) 'single page translation coverage'
Assert ($translations.PSObject.Properties.Name -notcontains 'Sandbox_SLA_PerSkill') 'second-page translation is absent'
Assert ($translations.PSObject.Properties.Name -notcontains 'Sandbox_SLA_PerSkill_tooltip') 'second-page tooltip translation is absent'
Assert ($translations.Sandbox_SLA_PerSkillLimit_option1 -and $translations.Sandbox_SLA_PerSkillLimit_option12) 'shared enum translation coverage'
Assert ($translations.Sandbox_SLA_tooltip -eq 'Control Survivor XP pacing, skill advancement limits, and optional Survivor Level inheritance.') 'main page tooltip wording'
Assert ($translations.Sandbox_SLA_SurvivorXpMultiplier_tooltip -eq 'Multiplies Survivor XP gained from trainable skill XP. This does not change skill XP.') 'XP multiplier tooltip wording'
Assert ($translations.Sandbox_SLA_FitnessStrengthContributionPercent -eq 'Fitness & Strength Survivor XP contribution percentage') 'Fitness and Strength percentage label'
Assert ($translations.Sandbox_SLA_FitnessStrengthContributionPercent_tooltip -eq 'Sets Survivor XP from Fitness and Strength as a percentage of ordinary skill contribution before the Survivor XP multiplier. 6.7 means 6.7%%.') 'Fitness and Strength percentage tooltip wording and escaping'
Assert ($translations.PSObject.Properties.Name -notcontains 'Sandbox_SLA_FitnessStrengthContribution') 'stale raw Fitness and Strength option translation is absent'
Assert ((@([regex]::Matches($jsonText, '%')).Count -eq 2)) 'only the escaped Fitness and Strength literal percent is present'
Assert ($translations.Sandbox_SLA_AutomaticCurveNormalization_tooltip -eq 'Balances Survivor XP from compatible custom skills using their published XP curve. Skills without a usable curve use normal contribution.') 'custom skill normalization tooltip wording'
Assert ($translations.Sandbox_SLA_EnableSurvivorLevelInheritance -eq 'Enable Survivor Level Inheritance') 'inheritance enabled label'
Assert ($translations.Sandbox_SLA_EnableSurvivorLevelInheritance_tooltip -eq "Allows an eligible new character to inherit part of the previous character's Survivor Level for the same player profile.") 'inheritance enabled tooltip'
Assert ($translations.Sandbox_SLA_SurvivorLevelRetainedPercent -eq 'Percentage of Survivor Level Retained') 'inheritance percentage label'
Assert ($translations.Sandbox_SLA_SurvivorLevelRetainedPercent_tooltip -eq "Percentage of the previous character's Survivor Level inherited by an eligible new character.") 'inheritance percentage tooltip'
Assert ($translations.Sandbox_SLA_AllotmentMode_tooltip -eq 'Global shares Advancement Slots across skills. Per Skill limits Advancement Slots by skill. Free removes Advancement Slots and accounting for natural or lost skill XP.') 'allotment tooltip wording'
Assert ($translations.Sandbox_SLA_GlobalAdvancementLimit_tooltip -eq 'Maximum active advancements across all skills. Used only in Global mode.') 'global limit tooltip wording'
Assert ($translations.Sandbox_SLA_PerSkillDefaultLimit_tooltip -eq 'Default maximum active advancements per skill. Custom skills use this value. Vanilla skills can override it below.') 'default limit tooltip wording'
$sandboxTooltips = @($translations.PSObject.Properties | Where-Object Name -like '*_tooltip')
Assert (@($sandboxTooltips | Where-Object { $_.Value -match ';' }).Count -eq 0) 'sandbox tooltips contain no semicolons'
$labels = @{'Sprinting'='Running';'Lightfoot'='Lightfooted';'Sneak'='Sneaking';'Farming'='Agriculture';'Husbandry'='Animal Care';'Woodwork'='Carpentry';'Doctor'='First Aid';'FlintKnapping'='Knapping';'Blacksmith'='Blacksmithing';'MetalWelding'='Welding';'PlantScavenging'='Foraging';'Electricity'='Electrical'}
foreach ($id in $ids) {
    $key = "SLA_PerSkill_$id"
    Assert ($translations.("Sandbox_" + $key)) "skill translation $id"
    if ($labels.ContainsKey($id)) { Assert ($translations.("Sandbox_" + $key) -eq $labels[$id]) "vanilla English label $id" }
}

$forbidden = 'post.?maximum|digital.?watch|admin|runtime|poll|network|ui|poster|icon|workshop|client'
Assert (-not ($text -match "(?i)$forbidden")) 'sandbox file contains no deferred settings or claims'
Assert (-not ($info.Values -join ' ' -match "(?i)$forbidden")) 'metadata contains no deferred claims'

$requiredUi = [ordered]@{
    'IGUI_SLA_StatusAP' = 'AP: %1'
    'IGUI_SLA_StatusActive' = 'Advancement Slots: %1/%2'
    'IGUI_SLA_StatusSurvivorXp' = 'Survivor XP: %1 / %2'
    'IGUI_SLA_Advance' = 'Advance to level %1 for %2 AP.'
    'IGUI_SLA_Master' = 'Master skill for %1 AP.'
    'IGUI_SLA_PerSkillActive' = 'Advancement Slots: %1/%2.'
    'IGUI_SLA_TargetXpLeft' = '%1 natural skill XP left'
    'IGUI_SLA_TargetCatchUp' = 'Catch up to free this advancement slot.'
    'IGUI_SLA_RecoveryXpLeft' = '%1 lost skill XP left'
    'IGUI_SLA_RecoveryNoSurvivorXp' = 'No Survivor XP during recovery.'
    'IGUI_SLA_Reason_Pending' = 'An advancement request is pending.'
    'IGUI_SLA_Reason_MaximumMismatch' = "This skill's progression curve changed."
    'IGUI_SLA_Reason_AtMaximum' = 'This skill is already at its maximum.'
    'IGUI_SLA_Reason_RedRecovery' = 'Recover natural XP before advancing again.'
    'IGUI_SLA_Reason_InsufficientAp' = 'Not enough AP.'
    'IGUI_SLA_Reason_AllotmentDisabled' = 'Advancement spending is disabled for this skill.'
    'IGUI_SLA_Reason_AllotmentCapacity' = 'Advancement slot unavailable.'
    'IGUI_SLA_Admin_Button' = 'Admin'
    'IGUI_SLA_Admin_Menu' = 'Survivor progression'
    'IGUI_SLA_Admin_Title' = 'Survivor progression'
    'IGUI_SLA_Admin_Target' = 'Target: %1'
    'IGUI_SLA_Admin_Level' = 'Survivor Level: %1'
    'IGUI_SLA_Admin_Xp' = 'Survivor XP: %1 / %2'
    'IGUI_SLA_Admin_Ap' = 'Available AP: %1'
    'IGUI_SLA_Admin_XpInput' = 'XP to award'
    'IGUI_SLA_Admin_AwardXp' = 'Award XP'
    'IGUI_SLA_Admin_LevelsInput' = 'Levels to award'
    'IGUI_SLA_Admin_AwardLevels' = 'Award Levels'
    'IGUI_SLA_Admin_ClearSlots' = 'Clear Advancements'
    'IGUI_SLA_Admin_Refresh' = 'Refresh'
    'IGUI_SLA_Admin_Waiting' = 'Waiting for Survivor data.'
    'IGUI_SLA_Admin_Inspected' = 'Survivor data refreshed.'
    'IGUI_SLA_Admin_Applied' = 'Survivor progression updated.'
    'IGUI_SLA_Admin_Stale' = 'Survivor data changed. Refresh and try again.'
    'IGUI_SLA_Admin_Failure' = 'The request failed. Refresh and try again.'
    'IGUI_SLA_Admin_CommittedFailure' = 'The change may have applied. Refresh before trying again.'
    'IGUI_SLA_Admin_InvalidXp' = 'Enter a positive XP amount.'
    'IGUI_SLA_Admin_InvalidLevels' = 'Enter a positive whole level count.'
    'IGUI_SLA_Admin_PendingOther' = 'Another admin request is pending.'
    'IGUI_SLA_LevelGain_Singular' = 'Survivor Level +%1'
    'IGUI_SLA_LevelGain_Plural' = 'Survivor Levels +%1'
    'IGUI_SLA_LevelGain_AP' = 'AP +%1'
    'IGUI_SLA_ModOptions_Title' = 'Survivor Leveling & Advancement'
    'IGUI_SLA_WatchOption' = 'Show XP %% to next level on digital watch'
    'IGUI_SLA_WatchOption_Tooltip' = "Show XP progress to the next Survivor Level as a small percentage in the bottom-right of the digital watch. This only shows Player 1's XP %%."
}
Assert (Test-Path -LiteralPath $uiPath -PathType Leaf) 'Build 42 English UI JSON exists'
Assert (-not (Test-Path -LiteralPath $obsoleteUiPath)) 'obsolete English UI text file is absent'
$uiText = Get-Content -Raw -LiteralPath $uiPath
$uiKeys = @([regex]::Matches($uiText, '(?m)"((?:[^"\\]|\\.)*)"\s*:') | ForEach-Object { $_.Groups[1].Value })
Assert (@($uiKeys | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'SLA UI JSON has no duplicate keys'
$uiTranslations = $uiText | ConvertFrom-Json
$actualUiKeys = @($uiTranslations.PSObject.Properties.Name)
Assert ($actualUiKeys.Count -eq $requiredUi.Count) 'exact SLA UI translation count'
Assert (($actualUiKeys -join ',') -eq (@($requiredUi.Keys) -join ',')) 'exact ordered SLA UI translation keys'
foreach ($key in $requiredUi.Keys) {
    $value = $uiTranslations.$key
    Assert ($value -eq $requiredUi[$key]) "exact SLA UI wording $key"
    Assert ($value -notmatch ';') "SLA UI copy has no semicolon $key"
}
Write-Output "Public sandbox settings: $assertions assertions passed."
