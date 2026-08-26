Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mod = Join-Path $root 'Contents/mods/SurvivorLevelingAdvancement/42.20'
$optionsPath = Join-Path $mod 'media/sandbox-options.txt'
$infoPath = Join-Path $mod 'mod.info'
$jsonPath = Join-Path $mod 'media/lua/shared/Translate/EN/Sandbox.json'
$uiPath = Join-Path $mod 'media/lua/shared/Translate/EN/IG_UI_EN.txt'

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

$uiText = Get-Content -Raw -LiteralPath $uiPath
$uiMatches = @([regex]::Matches($uiText, '(?m)^\s*(IGUI_SLA_[A-Za-z0-9_]+)\s*=\s*"((?:[^"\\]|\\.)*)",\s*$'))
$uiKeys = @($uiMatches | ForEach-Object { $_.Groups[1].Value })
$requiredUiKeys = @(
    'IGUI_SLA_StatusAP',
    'IGUI_SLA_StatusActive',
    'IGUI_SLA_Advance',
    'IGUI_SLA_PerSkillActive',
    'IGUI_SLA_Targets',
    'IGUI_SLA_HighWater',
    'IGUI_SLA_Recovery',
    'IGUI_SLA_Reason_Pending',
    'IGUI_SLA_Reason_MaximumMismatch',
    'IGUI_SLA_Reason_AtMaximum',
    'IGUI_SLA_Reason_RedRecovery',
    'IGUI_SLA_Reason_InsufficientAp',
    'IGUI_SLA_Reason_AllotmentDisabled',
    'IGUI_SLA_Reason_AllotmentCapacity'
)
Assert ($uiText -match '(?m)^IG_UI_EN\s*=\s*\{\s*$') 'English UI translation table header'
Assert ($uiText -match '(?m)^\}\s*$') 'English UI translation table footer'
Assert ($uiMatches.Count -eq $requiredUiKeys.Count) 'exact new SLA UI translation count'
Assert (($uiKeys -join ',') -eq ($requiredUiKeys -join ',')) 'exact ordered SLA UI translation keys'
Assert (@($uiKeys | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'SLA UI translations have no duplicate keys'
foreach ($match in $uiMatches) {
    $value = $match.Groups[2].Value
    Assert (-not [string]::IsNullOrWhiteSpace($value)) "SLA UI translation has copy $($match.Groups[1].Value)"
    Assert ($value -notmatch ';') "SLA UI tooltip copy has no semicolon $($match.Groups[1].Value)"
}
Assert (($uiMatches | Where-Object { $_.Groups[1].Value -eq 'IGUI_SLA_StatusAP' }).Groups[2].Value -eq 'AP: %1 unspent') 'AP status wording'
Assert (($uiMatches | Where-Object { $_.Groups[1].Value -eq 'IGUI_SLA_StatusActive' }).Groups[2].Value -eq 'Active advancements: %1 / %2') 'active status wording'
Write-Output "Public sandbox settings: $assertions assertions passed."
