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
$iconPath = Join-Path $modRoot 'icon.png'
$runtimeLicensePath = Join-Path $modRoot 'LICENSE'
$sourceLicensePath = Join-Path $projectRoot 'LICENSE'
$descriptionPath = Join-Path $projectRoot 'assets\workshop\WORKSHOP_DESCRIPTION.md'
$screenshotsPath = Join-Path $projectRoot 'assets\workshop\screenshots'

foreach ($requiredPath in @(
    $workshopPath,
    $previewPath,
    $modInfoPath,
    $posterPath,
    $iconPath,
    $runtimeLicensePath,
    $sourceLicensePath,
    $descriptionPath,
    $screenshotsPath
)) {
    Assert-ReleaseCondition (Test-Path -LiteralPath $requiredPath) "missing $requiredPath"
}

$workshopLines = @(Get-Content -LiteralPath $workshopPath)
Assert-ReleaseCondition ($workshopLines[0] -eq 'version=1') 'workshop version'
$workshopItemIdLines = @($workshopLines -match '^id=')
Assert-ReleaseCondition ($workshopItemIdLines.Count -eq 1) 'exactly one Workshop item ID declaration'
Assert-ReleaseCondition ($workshopItemIdLines[0] -ceq 'id=3792412209') 'exact Workshop item ID'
Assert-ReleaseCondition ($workshopLines -contains 'title=Survivor Leveling & Advancement [B42]') 'workshop title'
Assert-ReleaseCondition ($workshopLines -contains 'tags=Build 42;Balance;Interface;Multiplayer;Skills') 'workshop tags'
$visibilityLines = @($workshopLines -match '^visibility=')
Assert-ReleaseCondition ($visibilityLines.Count -eq 1) 'exactly one Workshop visibility declaration'
Assert-ReleaseCondition ($visibilityLines[0] -ceq 'visibility=public') 'public Workshop visibility (stale unlisted is rejected)'
Assert-ReleaseCondition (@($workshopLines -match '^description=').Count -ge 30) 'substantial Workshop description'

$descriptionLines = @(Get-Content -LiteralPath $descriptionPath)
$descriptionText = Get-Content -Raw -LiteralPath $descriptionPath
$workshopText = Get-Content -Raw -LiteralPath $workshopPath
$howItWorksCopy = "SLA gives each character a Survivor Level separate from normal skills. Supported trainable skill XP also earns Survivor XP, with each Survivor Level granting one Advancement Point, or AP. AP can then be spent in the vanilla skills panel to raise the level of a selected skill, spending the required AP and occupying the required number of Advancement Slots. In order to earn a slot back, you must naturally earn the XP in the skill the AP was spent to bypass, while that same XP still applies toward your next level. The final advancement to a skill's effective maximum, normally level 9 to level 10, requires 2 AP to 'master' the skill along with 2 free Advancement Slots, and clears any active Advancement Slots on the skill. If you have Global or Per Skill Advancement Slot limits set to 1, then mastery only requires 1 free Advancement Slot while retaining the 2 AP cost. Free mode requires no Advancement Slots while retaining the 2 AP cost."
$staleHowItWorksCopy = "Trainable skill XP also earns you Survivor XP, with each Survivor Level granting one Advancement Point, or AP. AP can then be spent in the vanilla Skills panel to raise the level of a selected skill, spending the required AP and occupying the required number of Advancement Slots. By default, you are limited to 3 Advancement Slots across all skills. In order to earn a slot back, you must naturally earn the XP in the skill the AP was spent to bypass, while that same XP still applies toward your next level."
$advancementModeCopy = @(
    '**Global:** Shares one configurable pool of Advancement Slots across every skill, with a default limit of 3 active slots in total.'
    '**Per Skill:** Gives each skill its own configurable slot limit, using a default for compatible custom skills and optional overrides for vanilla skills.'
    '**Free:** Removes Advancement Slot limits and catch-up or recovery restrictions.'
)
$workshopAdvancementModeCopy = @(
    'description=[*][b]Global:[/b] Shares one configurable pool of Advancement Slots across every skill, with a default limit of 3 active slots in total.'
    'description=[*][b]Per Skill:[/b] Gives each skill its own configurable slot limit, using a default for compatible custom skills and optional overrides for vanilla skills.'
    'description=[*][b]Free:[/b] Removes Advancement Slot limits and catch-up or recovery restrictions.'
)
$staleFreeModeCopy = 'Free mode does not track catch-up or recovery.'
$modeRecoveryCopy = 'In Global and Per Skill modes, losing levels or XP (Fitness/Strength) puts that skill into a recovery state that grants no Survivor XP until the lost progress is recovered.'
$modeAccountingNote = 'Changing modes does not reset tracked progress. Natural skill XP earned while Free is selected still counts toward any preserved catch-up or recovery, and switching back to Global or Per Skill restores only what remains.'
$levelInheritanceCopy = "Survivor Level inheritance is configured through sandbox settings and allows the host to set a percentage of a deceased character's Survivor Level that passes to that player's next eligible survivor. This allows you to continue playing in a world you've invested significant progress, while still retaining some of the downside of becoming Zomboid chow."
$featureCopy = @(
    'Integrated directly into the vanilla skills panel'
    'A separately configurable Survivor XP multiplier that does not change skill XP'
    'Configurable Fitness and Strength contribution to Survivor XP'
    'Automatic curve normalization for compatible custom skills'
    'Server-authoritative multiplayer progression'
    'Online-player administration for inspecting progression, awarding XP or levels, and clearing advancements'
    'Full controller support for spending AP'
    'Split-screen compatible'
    'Optional Survivor Level inheritance after death'
    'Optional Player 1 Survivor XP percentage inside the digital watch, enabled through Mod Options in the settings menu'
)
Assert-ReleaseCondition (@($descriptionLines -ceq $howItWorksCopy).Count -eq 1) 'exact Markdown separate Survivor Level and lower-case skills-panel opening'
Assert-ReleaseCondition (@($workshopLines -ceq "description=$howItWorksCopy").Count -eq 1) 'exact Workshop separate Survivor Level and lower-case skills-panel opening'
Assert-ReleaseCondition (-not $descriptionText.Contains($staleHowItWorksCopy)) 'Markdown omits replaced capitalized Skills-panel opening'
Assert-ReleaseCondition (-not $workshopText.Contains("description=$staleHowItWorksCopy")) 'Workshop omits replaced capitalized Skills-panel opening'
Assert-ReleaseCondition (@($descriptionLines -ceq '## Advancement modes').Count -eq 1) 'exact Markdown Advancement modes heading'
Assert-ReleaseCondition (@($workshopLines -ceq 'description=[h2]Advancement modes[/h2]').Count -eq 1) 'exact Workshop Advancement modes heading'
foreach ($modeCopy in $advancementModeCopy) {
    Assert-ReleaseCondition (@($descriptionLines -ceq "- $modeCopy").Count -eq 1) "exact Markdown advancement mode copy: $modeCopy"
}
foreach ($modeCopy in $workshopAdvancementModeCopy) {
    Assert-ReleaseCondition (@($workshopLines -ceq $modeCopy).Count -eq 1) "exact Workshop advancement mode copy: $modeCopy"
}
Assert-ReleaseCondition (-not $descriptionText.Contains($staleFreeModeCopy)) 'Markdown omits stale Free-mode accounting copy'
Assert-ReleaseCondition (-not $workshopText.Contains($staleFreeModeCopy)) 'Workshop omits stale Free-mode accounting copy'
Assert-ReleaseCondition (@($descriptionLines -ceq $modeRecoveryCopy).Count -eq 1) 'exact Markdown Global and Per Skill recovery copy'
Assert-ReleaseCondition (@($workshopLines -ceq "description=$modeRecoveryCopy").Count -eq 1) 'exact Workshop Global and Per Skill recovery copy'
Assert-ReleaseCondition (@($descriptionLines -ceq "**Note:** $modeAccountingNote").Count -eq 1) 'exact Markdown preserved mode-accounting note'
Assert-ReleaseCondition (@($workshopLines -ceq "description=[b]Note:[/b] $modeAccountingNote").Count -eq 1) 'exact Workshop preserved mode-accounting note'
Assert-ReleaseCondition (@($descriptionLines -ceq '## Level Inheritance').Count -eq 1) 'exact Markdown Level Inheritance heading'
Assert-ReleaseCondition (@($workshopLines -ceq 'description=[h2]Level Inheritance[/h2]').Count -eq 1) 'exact Workshop Level Inheritance heading'
Assert-ReleaseCondition (@($descriptionLines -ceq $levelInheritanceCopy).Count -eq 1) 'exact Markdown Level Inheritance copy'
Assert-ReleaseCondition (@($workshopLines -ceq "description=$levelInheritanceCopy").Count -eq 1) 'exact Workshop Level Inheritance copy'
foreach ($feature in $featureCopy) {
    Assert-ReleaseCondition (@($descriptionLines -ceq "- $feature").Count -eq 1) "exact Markdown feature copy: $feature"
    Assert-ReleaseCondition (@($workshopLines -ceq "description=[*]$feature").Count -eq 1) "exact Workshop feature copy: $feature"
}
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
$markdownHookConflictCopy = "- **Potential hook conflicts:** Mods that replace the game's skill-XP award functions or ``Events.AddXP`` handling, vanilla Skills panel/progress-bar methods, online-player context menus, or digital-watch rendering may conflict with the corresponding SLA feature. SLA disables an affected capability when it detects that a required hook has been replaced rather than continuing with potentially incorrect behavior."
$workshopHookConflictCopy = "description=[*][b]Potential hook conflicts:[/b] Mods that replace the game's skill-XP award functions or Events.AddXP handling, vanilla Skills panel/progress-bar methods, online-player context menus, or digital-watch rendering may conflict with the corresponding SLA feature. SLA disables an affected capability when it detects that a required hook has been replaced rather than continuing with potentially incorrect behavior."
$markdownCustomProgressionCopy = '- **Custom progression boundary:** Compatible trainable skills that publish a usable XP curve and award XP through supported game events are expected to work. Mods that directly set skill XP or levels, replace skill caps or curves without compatible data, or otherwise bypass supported XP events may not grant Survivor XP or may be unsupported.'
$workshopCustomProgressionCopy = 'description=[*][b]Custom progression boundary:[/b] Compatible trainable skills that publish a usable XP curve and award XP through supported game events are expected to work. Mods that directly set skill XP or levels, replace skill caps or curves without compatible data, or otherwise bypass supported XP events may not grant Survivor XP or may be unsupported.'
Assert-ReleaseCondition (@($descriptionLines -ceq $markdownHookConflictCopy).Count -eq 1) 'exact Markdown potential-hook-conflicts boundary'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopHookConflictCopy).Count -eq 1) 'exact Workshop potential-hook-conflicts boundary'
Assert-ReleaseCondition (@($descriptionLines -ceq $markdownCustomProgressionCopy).Count -eq 1) 'exact Markdown custom-progression boundary'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopCustomProgressionCopy).Count -eq 1) 'exact Workshop custom-progression boundary'
Assert-ReleaseCondition ($descriptionText.Contains('[Ko-fi](https://ko-fi.com/skeptic043)')) 'Markdown Ko-fi link'
Assert-ReleaseCondition ($workshopText.Contains('[url=https://ko-fi.com/skeptic043]Ko-fi[/url]')) 'Workshop Ko-fi link'
Assert-ReleaseCondition ($descriptionText.Contains('Optional support: [Ko-fi](https://ko-fi.com/skeptic043). All donations are strictly optional and no mod features are locked behind a paywall.')) 'Markdown support copy'
Assert-ReleaseCondition ($workshopText.Contains('description=Optional support: [url=https://ko-fi.com/skeptic043]Ko-fi[/url]. All donations are strictly optional and no mod features are locked behind a paywall.')) 'Workshop support copy'
$administrationCopy = 'Authorized administrators can open "Admin Panel > Mini Scoreboard" or "Admin Panel > Users List", right-click an online player, and choose "Survivor progression". Administrators can inspect progression, award positive Survivor XP or whole Survivor Levels, clear active Advancement Slots (without refunding AP or changing skill XP), and refresh the target state. An administrator can manage their own SLA progression from the "Admin" button in the Skills panel. Administration is limited to online players.'
$workshopAdministrationLine = "description=$administrationCopy"
$workshopDedicatedSaveLimitLine = 'description=[*]Dedicated servers should set the native SaveWorldEveryMinutes option to a nonzero value. Abrupt termination can lose SLA progression written after the last successful server save; a shorter interval reduces that window.'
$backupRecommendationCopy = 'Regardless of design, I strongly recommend backing up your save before changing the mod list of an ongoing world you care about.'
$staleWatchSettingsCopy = "Optional sandbox settings also provide Survivor Level inheritance and a small digital watch integration."
Assert-ReleaseCondition (@($workshopLines -ceq $workshopAdministrationLine).Count -eq 1) 'exact Workshop online-player administration copy for Mini Scoreboard and Users List'
Assert-ReleaseCondition (@($descriptionLines -ceq $administrationCopy).Count -eq 1) 'exact Markdown online-player administration copy for Mini Scoreboard and Users List'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopDedicatedSaveLimitLine).Count -eq 1) 'exact Workshop dedicated SaveWorldEveryMinutes limitation copy'
Assert-ReleaseCondition (@($descriptionLines -ceq $backupRecommendationCopy).Count -eq 1) 'exact Markdown strengthened backup recommendation'
Assert-ReleaseCondition (@($workshopLines -ceq "description=$backupRecommendationCopy").Count -eq 1) 'exact Workshop strengthened backup recommendation'
Assert-ReleaseCondition (-not $descriptionText.Contains($staleWatchSettingsCopy)) 'Markdown omits stale combined sandbox-settings watch copy'
Assert-ReleaseCondition (-not $workshopText.Contains("description=$staleWatchSettingsCopy")) 'Workshop omits stale combined sandbox-settings watch copy'
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
Assert-ReleaseCondition (@($descriptionLines -ceq '- Developed and tested on: Project Zomboid 42.20.4').Count -eq 1) 'exact Markdown developed-and-tested version'
Assert-ReleaseCondition (@($workshopLines -ceq 'description=Developed and tested on: Project Zomboid 42.20.4').Count -eq 1) 'exact Workshop developed-and-tested version'
Assert-ReleaseCondition (@($descriptionLines -ceq '- Required dependencies: None').Count -eq 1) 'exact Markdown dependency declaration'
Assert-ReleaseCondition (@($workshopLines -ceq 'description=Required dependencies: None').Count -eq 1) 'exact Workshop dependency declaration'
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
Assert-ReleaseCondition (@($modInfoLines -ceq 'icon=icon.png').Count -eq 1) 'exact icon=icon.png declaration'
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
Assert-PngDimensions $iconPath 64 64 'icon'
Assert-ReleaseCondition ((Get-Item -LiteralPath $previewPath).Length -le 1MB) 'preview is at most 1 MB'

$screenshots = @(Get-ChildItem -LiteralPath $screenshotsPath -File | Sort-Object Name)
$expectedScreenshotNames = @(
    '01-skills-overview.png'
    '02-advancement-tooltip.png'
    '03-sandbox-settings.png'
    '04-admin-panel.png'
)
Assert-ReleaseCondition ($screenshots.Count -eq 4) 'exactly four Workshop screenshots'
Assert-ReleaseCondition ([string]::Join("`n", @($screenshots.Name)) -ceq [string]::Join("`n", $expectedScreenshotNames)) 'exact Workshop screenshot filenames'
foreach ($screenshot in @($screenshots | Where-Object { $_.Name -ne '04-admin-panel.png' })) {
    $image = [System.Drawing.Image]::FromFile($screenshot.FullName)
    try {
        Assert-ReleaseCondition ($image.Width -ge 400) "$($screenshot.Name) useful width"
        Assert-ReleaseCondition ($image.Height -ge 400) "$($screenshot.Name) useful height"
    }
    finally {
        $image.Dispose()
    }
}
Assert-PngDimensions (Join-Path $screenshotsPath '04-admin-panel.png') 902 320 'admin screenshot'

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
