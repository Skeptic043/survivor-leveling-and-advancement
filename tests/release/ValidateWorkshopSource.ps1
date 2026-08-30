$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Assertions = 0

function Assert-ReleaseCondition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:Assertions += 1
    if (-not $Condition) {
        throw "Workshop release validation failed: $Message"
    }
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$workshopPath = Join-Path $projectRoot 'workshop.txt'
$previewPath = Join-Path $projectRoot 'preview.png'
$modRoot = Join-Path $projectRoot 'Contents\mods\SurvivorLevelingAdvancement\42.20'
$modInfoPath = Join-Path $modRoot 'mod.info'
$posterPath = Join-Path $modRoot 'poster.png'
$runtimeLicensePath = Join-Path $modRoot 'LICENSE'
$sourceLicensePath = Join-Path $projectRoot 'LICENSE'
$descriptionPath = Join-Path $projectRoot 'assets\workshop\WORKSHOP_DESCRIPTION.md'
$screenshotsPath = Join-Path $projectRoot 'assets\workshop\screenshots'

foreach ($requiredPath in @(
    $workshopPath,
    $previewPath,
    $modInfoPath,
    $posterPath,
    $runtimeLicensePath,
    $sourceLicensePath,
    $descriptionPath,
    $screenshotsPath
)) {
    Assert-ReleaseCondition (Test-Path -LiteralPath $requiredPath) "missing $requiredPath"
}

$workshopLines = @(Get-Content -LiteralPath $workshopPath)
Assert-ReleaseCondition ($workshopLines[0] -eq 'version=1') 'workshop version'
Assert-ReleaseCondition ($workshopLines -contains 'id=3792412209') 'Workshop item ID'
Assert-ReleaseCondition ($workshopLines -contains 'title=Survivor Leveling & Advancement [B42]') 'workshop title'
Assert-ReleaseCondition ($workshopLines -contains 'tags=Build 42;Balance;Interface;Multiplayer;Skills') 'workshop tags'
Assert-ReleaseCondition ($workshopLines -contains 'visibility=friendsOnly') 'initial friends-only visibility'
Assert-ReleaseCondition (@($workshopLines -match '^description=').Count -ge 30) 'substantial Workshop description'

$descriptionLines = @(Get-Content -LiteralPath $descriptionPath)
$descriptionText = Get-Content -Raw -LiteralPath $descriptionPath
$workshopText = Get-Content -Raw -LiteralPath $workshopPath
$linkedMods = [ordered]@{
    'RPG Skills Systems B42 / RPGMenu' = '3666281346'
    'Beyond Ten - Level 15 Skills' = '3765241705'
    'Seesaw Game' = '3515515643'
    'Detailed Skill Tooltips' = '3572846242'
    'Toughness Skill' = '3545533939'
    'Show Skill XP Gain B42.20' = '3776490883'
}
foreach ($entry in $linkedMods.GetEnumerator()) {
    $url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($entry.Value)"
    Assert-ReleaseCondition ($descriptionText.Contains("[$($entry.Key)]($url)")) "Markdown link for $($entry.Key)"
    Assert-ReleaseCondition ($workshopText.Contains("[url=$url]$($entry.Key)[/url]")) "Workshop link for $($entry.Key)"
}
Assert-ReleaseCondition ($descriptionText.Contains('[Ko-fi](https://ko-fi.com/skeptic043)')) 'Markdown Ko-fi link'
Assert-ReleaseCondition ($workshopText.Contains('[url=https://ko-fi.com/skeptic043]Ko-fi[/url]')) 'Workshop Ko-fi link'
Assert-ReleaseCondition ($descriptionText.Contains('Optional support: [Ko-fi](https://ko-fi.com/skeptic043). All donations are strictly optional and no mod features are locked behind a paywall.')) 'Markdown support copy'
Assert-ReleaseCondition ($workshopText.Contains('description=Optional support: [url=https://ko-fi.com/skeptic043]Ko-fi[/url]. All donations are strictly optional and no mod features are locked behind a paywall.')) 'Workshop support copy'
$aiUseDisclosure = "AI was used to write all of the code in this project. The original concept, design direction, testing, debugging, and release decisions are my own. I spent many hours personally testing SLA and working through issues to make sure it behaves as intended. I'm grateful that AI tools helped me turn the idea into something I can share with the community. If you prefer not to use mods developed with AI assistance, I understand and respect that choice."
$workshopAIUseDisclosure = "description=$aiUseDisclosure"
Assert-ReleaseCondition (@($descriptionLines -ceq '## AI Use').Count -eq 1) 'exact Markdown AI Use heading'
Assert-ReleaseCondition (@($workshopLines -ceq 'description=[h2]AI Use[/h2]').Count -eq 1) 'exact Workshop AI Use heading'
Assert-ReleaseCondition (@($descriptionLines -ceq $aiUseDisclosure).Count -eq 1) 'exact Markdown AI use disclosure'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopAIUseDisclosure).Count -eq 1) 'exact one-line Workshop AI use disclosure'
$markdownCurrentLimitsIndex = [Array]::IndexOf($descriptionLines, '## Current limits')
$markdownAIUseIndex = [Array]::IndexOf($descriptionLines, '## AI Use')
$markdownSupportIndex = [Array]::IndexOf($descriptionLines, '## Support')
$markdownModInfoIndex = [Array]::IndexOf($descriptionLines, '## Mod information')
$workshopCurrentLimitsIndex = [Array]::IndexOf($workshopLines, 'description=[h2]Current limits[/h2]')
$workshopAIUseIndex = [Array]::IndexOf($workshopLines, 'description=[h2]AI Use[/h2]')
$workshopSupportIndex = [Array]::IndexOf($workshopLines, 'description=[h2]Support[/h2]')
$workshopModInfoIndex = [Array]::IndexOf($workshopLines, 'description=[h2]Mod information[/h2]')
Assert-ReleaseCondition ($markdownCurrentLimitsIndex -ge 0 -and $markdownCurrentLimitsIndex -lt $markdownAIUseIndex -and $markdownAIUseIndex -lt $markdownSupportIndex) 'Markdown AI Use section after current limits and before support'
Assert-ReleaseCondition ($workshopCurrentLimitsIndex -ge 0 -and $workshopCurrentLimitsIndex -lt $workshopAIUseIndex -and $workshopAIUseIndex -lt $workshopSupportIndex) 'Workshop AI Use section after current limits and before support'
Assert-ReleaseCondition ($markdownSupportIndex -ge 0 -and $markdownSupportIndex -lt $markdownModInfoIndex) 'Markdown support section before mod information'
Assert-ReleaseCondition ($workshopSupportIndex -ge 0 -and $workshopSupportIndex -lt $workshopModInfoIndex) 'Workshop support section before mod information'
Assert-ReleaseCondition ($descriptionText.Contains('- Target version: Project Zomboid Build 42.20')) 'Markdown target version'
Assert-ReleaseCondition ($workshopLines -contains 'description=Target version: Project Zomboid Build 42.20') 'Workshop target version'
Assert-ReleaseCondition (-not $descriptionText.Contains('content track')) 'Markdown omits content-track wording'
Assert-ReleaseCondition (-not $workshopText.Contains('content track')) 'Workshop omits content-track wording'
Assert-ReleaseCondition (-not $descriptionText.Contains('Mod ID:')) 'Markdown leaves generated Mod ID to PZ'
Assert-ReleaseCondition (-not $descriptionText.Contains('Workshop ID:')) 'Markdown leaves generated Workshop ID to PZ'
Assert-ReleaseCondition (-not $workshopText.Contains('description=Mod ID:')) 'Workshop leaves generated Mod ID to PZ'
Assert-ReleaseCondition (-not $workshopText.Contains('description=Workshop ID:')) 'Workshop leaves generated Workshop ID to PZ'
Assert-ReleaseCondition (-not $descriptionText.Contains('—')) 'Markdown compatibility labels use colons'
Assert-ReleaseCondition (-not $workshopText.Contains('—')) 'Workshop compatibility labels use colons'

$modInfoLines = @(Get-Content -LiteralPath $modInfoPath)
Assert-ReleaseCondition ($modInfoLines -contains 'id=SurvivorLevelingAdvancement') 'mod ID'
Assert-ReleaseCondition ($modInfoLines -contains 'poster=poster.png') 'poster declaration'
Assert-ReleaseCondition ($modInfoLines -contains 'incompatible=RpgSkillsSystemsB42,VanillaMenu') 'native incompatibility declaration'

Add-Type -AssemblyName System.Drawing

function Assert-PngDimensions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [int]$Width,
        [Parameter(Mandatory = $true)]
        [int]$Height,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $image = [System.Drawing.Image]::FromFile($Path)
    try {
        Assert-ReleaseCondition ($image.Width -eq $Width) "$Label width"
        Assert-ReleaseCondition ($image.Height -eq $Height) "$Label height"
        Assert-ReleaseCondition ($image.RawFormat.Guid -eq [System.Drawing.Imaging.ImageFormat]::Png.Guid) "$Label PNG format"
    }
    finally {
        $image.Dispose()
    }
}

Assert-PngDimensions $previewPath 256 256 'preview'
Assert-PngDimensions $posterPath 512 512 'poster'
Assert-ReleaseCondition ((Get-Item -LiteralPath $previewPath).Length -le 1MB) 'preview is at most 1 MB'

$screenshots = @(Get-ChildItem -LiteralPath $screenshotsPath -File -Filter '*.png' | Sort-Object Name)
Assert-ReleaseCondition ($screenshots.Count -eq 3) 'exactly three Workshop screenshots'
foreach ($screenshot in $screenshots) {
    $image = [System.Drawing.Image]::FromFile($screenshot.FullName)
    try {
        Assert-ReleaseCondition ($image.Width -ge 400) "$($screenshot.Name) useful width"
        Assert-ReleaseCondition ($image.Height -ge 400) "$($screenshot.Name) useful height"
    }
    finally {
        $image.Dispose()
    }
}

$sourceLicenseHash = (Get-FileHash -LiteralPath $sourceLicensePath -Algorithm SHA256).Hash
$runtimeLicenseHash = (Get-FileHash -LiteralPath $runtimeLicensePath -Algorithm SHA256).Hash
Assert-ReleaseCondition ($sourceLicenseHash -eq $runtimeLicenseHash) 'runtime license matches repository license'

$publicText = [string]::Join("`n", @(
    Get-Content -LiteralPath $workshopPath
    Get-Content -LiteralPath $descriptionPath
    Get-Content -LiteralPath $modInfoPath
))
foreach ($privatePattern in @('C:\\Users\\', 's8a_x', '\.codex')) {
    Assert-ReleaseCondition (-not ($publicText -match $privatePattern)) "public text excludes $privatePattern"
}

Write-Host "Workshop release-source validation passed ($($script:Assertions) assertions)."
