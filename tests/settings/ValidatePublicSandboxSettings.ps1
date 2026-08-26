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
Assert ($blocks.Count -eq 41) 'exactly six main and 35 per-skill options are required'

$main = @{
    'SurvivorXpMultiplier' = @('double','0','10','1','SLA')
    'FitnessStrengthContribution' = @('double','0.001','1','0.067230769','SLA')
    'AutomaticCurveNormalization' = @('boolean','','','true','SLA')
    'AllotmentMode' = @('enum','','','1','SLA')
    'GlobalAdvancementLimit' = @('integer','0','100','3','SLA')
    'PerSkillDefaultLimit' = @('integer','0','10','1','SLA')
}
$seen = @()
foreach ($b in $blocks) {
    $name = $b.Groups[1].Value
    $body = $b.Groups[2].Value
    if ($name -match '^SurvivorLevelingAdvancement\.(SurvivorXpMultiplier|FitnessStrengthContribution|AutomaticCurveNormalization|AllotmentMode|GlobalAdvancementLimit|PerSkillDefaultLimit)$') {
        $key = $Matches[1]; $seen += $key; $expected = $main[$key]
        Assert ((Field $body 'type') -eq $expected[0]) "$key type"
        if ($expected[1]) { Assert ((Field $body 'min') -eq $expected[1] -and (Field $body 'max') -eq $expected[2]) "$key range" }
        Assert ((Field $body 'default') -eq $expected[3]) "$key default"
        Assert ((Field $body 'page') -eq $expected[4]) "$key page"
        Assert (Field $body 'translation') "$key translation"
        if ($key -eq 'AllotmentMode') { Assert ((Field $body 'numValues') -eq '3' -and (Field $body 'valueTranslation')) 'allotment enum encoding' }
    }
}
Assert ((@($seen | Sort-Object -Unique) -join ',') -eq (($main.Keys | Sort-Object) -join ',')) 'exact six main settings'

$actualIds = @($blocks | ForEach-Object { if ($_.Groups[1].Value -match '^SurvivorLevelingAdvancement\.PerSkillLimit_(.+)$') { $Matches[1] } })
Assert (($actualIds -join ',') -eq ($ids -join ',')) 'ordered vanilla override IDs'
foreach ($b in $blocks | Where-Object { $_.Groups[1].Value -match 'PerSkillLimit_' }) {
    $body = $b.Groups[2].Value
    Assert ((Field $body 'type') -eq 'enum' -and (Field $body 'numValues') -eq '12' -and (Field $body 'default') -eq '1') 'per-skill enum shape'
    Assert ((Field $body 'page') -eq 'SLA' -and (Field $body 'valueTranslation') -eq 'SLA_PerSkillLimit') 'per-skill page/value translation'
    Assert ((Field $body 'valueTranslation') -eq 'SLA_PerSkillLimit') 'per-skill enum value translation'
}
Assert ((@($blocks | ForEach-Object { Field $_.Groups[2].Value 'page' } | Where-Object { $_ -eq 'SLA' }).Count -eq 41)) 'all settings use the one SLA page'
Assert ($text -notmatch '(?m)^\s*page\s*=\s*SLA_PerSkill\s*,\s*$') 'no second sandbox page remains'

$info = @{}
foreach ($line in Get-Content $infoPath) { if ($line -match '^([^=]+)=(.*)$') { $info[$Matches[1]] = $Matches[2] } }
Assert (($info.Keys | Sort-Object) -join ',' -eq 'description,id,name') 'metadata has no extra fields'
Assert ($info.name -eq 'Survivor Leveling & Advancement' -and $info.id -eq 'SurvivorLevelingAdvancement') 'metadata name and id'
Assert (-not $info.ContainsKey('versionMin') -and -not $info.ContainsKey('versionMax')) 'metadata does not enforce patch bounds'
Assert ($info.description -eq 'Earn Survivor Levels through skill XP and spend Advancement Points to raise trainable skills.') 'metadata behavior description'

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
Assert ($translations.Sandbox_SLA_tooltip -eq 'Control Survivor XP pacing and how many skill advancements may be active at once.') 'main page tooltip wording'
Assert ($translations.Sandbox_SLA_SurvivorXpMultiplier_tooltip -eq 'Multiplies Survivor XP gained from trainable skill XP. This does not change skill XP.') 'XP multiplier tooltip wording'
Assert ($translations.Sandbox_SLA_FitnessStrengthContribution_tooltip -eq 'Scales Survivor XP from Fitness and Strength before the Survivor XP multiplier. The default is about 6.7%%.') 'Fitness and Strength tooltip wording and escaping'
Assert ((@([regex]::Matches($jsonText, '%')).Count -eq 2)) 'only the escaped Fitness and Strength literal percent is present'
Assert ($translations.Sandbox_SLA_AutomaticCurveNormalization_tooltip -eq 'Balances Survivor XP from compatible custom skills using their published XP curve. Skills without a usable curve use normal contribution.') 'custom skill normalization tooltip wording'
Assert ($translations.Sandbox_SLA_AllotmentMode_tooltip -eq 'Choose whether active advancements share one global limit, use limits per skill, or have no limit.') 'allotment tooltip wording'
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

$forbidden = 'inherit|post.?maximum|digital.?watch|admin|runtime|poll|network|ui|poster|icon|workshop|client'
Assert (-not ($text -match "(?i)$forbidden")) 'sandbox file contains no deferred settings or claims'
Assert (-not ($info.Values -join ' ' -match "(?i)$forbidden")) 'metadata contains no deferred claims'

$requiredUi = [ordered]@{
    'IGUI_SLA_StatusAP' = 'AP: %1 unspent'
    'IGUI_SLA_StatusActive' = 'Active advancements: %1 / %2'
    'IGUI_SLA_Advance' = 'Advance to level %1 for %2 AP.'
    'IGUI_SLA_PerSkillActive' = 'Active advancements: %1 / %2.'
    'IGUI_SLA_Targets' = 'Blue boxes are active AP advancements.'
    'IGUI_SLA_HighWater' = 'The blue marker shows natural XP progress.'
    'IGUI_SLA_Recovery' = 'Red shows natural XP recovery still needed.'
    'IGUI_SLA_Reason_Pending' = 'An advancement request is pending.'
    'IGUI_SLA_Reason_MaximumMismatch' = "This skill's progression curve changed."
    'IGUI_SLA_Reason_AtMaximum' = 'This skill is already at its maximum.'
    'IGUI_SLA_Reason_RedRecovery' = 'Recover natural XP before advancing again.'
    'IGUI_SLA_Reason_InsufficientAp' = 'You need more AP.'
    'IGUI_SLA_Reason_AllotmentDisabled' = 'Advancement spending is disabled for this skill.'
    'IGUI_SLA_Reason_AllotmentCapacity' = 'This skill has reached its advancement limit.'
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
