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
$readmePath = Join-Path $projectRoot 'README.md'
$changelogPath = Join-Path $projectRoot 'CHANGELOG.md'
$workshopPath = Join-Path $projectRoot 'workshop.txt'
$previewPath = Join-Path $projectRoot 'preview.png'
$fullNamePosterPath = Join-Path $projectRoot 'assets\workshop\poster-full-name.png'
$modRoot = Join-Path $projectRoot 'Contents\mods\SurvivorLevelingAdvancement\42.20'
$modInfoPath = Join-Path $modRoot 'mod.info'
$posterPath = Join-Path $modRoot 'poster.png'
$iconPath = Join-Path $modRoot 'icon.png'
$runtimeLicensePath = Join-Path $modRoot 'LICENSE'
$sourceLicensePath = Join-Path $projectRoot 'LICENSE'
$descriptionPath = Join-Path $projectRoot 'assets\workshop\WORKSHOP_DESCRIPTION.md'
$steamChangeNotesPath = Join-Path $projectRoot 'assets\workshop\STEAM_CHANGE_NOTES.md'
$screenshotsPath = Join-Path $projectRoot 'assets\workshop\screenshots'

foreach ($requiredPath in @(
    $readmePath,
    $changelogPath,
    $workshopPath,
    $previewPath,
    $fullNamePosterPath,
    $modInfoPath,
    $posterPath,
    $iconPath,
    $runtimeLicensePath,
    $sourceLicensePath,
    $descriptionPath,
    $steamChangeNotesPath,
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
$readmeLines = @(Get-Content -LiteralPath $readmePath)
$readmeText = Get-Content -Raw -LiteralPath $readmePath
$changelogLines = @(Get-Content -LiteralPath $changelogPath)
$steamChangeNoteLines = @(Get-Content -LiteralPath $steamChangeNotesPath)

function Get-MarkdownSectionBody {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [string]$Heading
    )

    $startIndex = [Array]::IndexOf($Lines, $Heading)
    if ($startIndex -lt 0) {
        return @()
    }

    $endIndex = $Lines.Count
    for ($index = $startIndex + 1; $index -lt $Lines.Count; $index += 1) {
        if ($Lines[$index] -match '^## ') {
            $endIndex = $index
            break
        }
    }

    return @($Lines | Select-Object -Skip ($startIndex + 1) -First ($endIndex - $startIndex - 1))
}

Assert-ReleaseCondition (@($changelogLines -ceq '## 1.0.0 - 2026-08-30').Count -eq 1) 'exact released 1.0.0 changelog heading'
Assert-ReleaseCondition (@($changelogLines -ceq '## 1.0.0 - Unreleased').Count -eq 0) 'changelog omits stale 1.0.0 Unreleased heading'
Assert-ReleaseCondition (@($changelogLines -ceq '## 1.1.0 - 2026-09-01').Count -eq 1) 'exact released 1.1.0 changelog heading'
Assert-ReleaseCondition (@($changelogLines -ceq '## Unreleased').Count -eq 0) 'changelog omits stale Unreleased heading'
Assert-ReleaseCondition (@($steamChangeNoteLines -ceq '## 1.1.0').Count -eq 1) 'exact released Steam 1.1.0 heading'
Assert-ReleaseCondition (@($steamChangeNoteLines -ceq '## Next update').Count -eq 0) 'Steam notes omit stale Next update heading'
$authoringReminder = 'Add any further player-visible changes here before the next upload.'
Assert-ReleaseCondition (@($steamChangeNoteLines -ceq $authoringReminder).Count -eq 0) 'Steam notes omit the release-authoring reminder'
Assert-ReleaseCondition (@($steamChangeNoteLines -ceq '## 1.0.0').Count -eq 1) 'exact one Steam 1.0.0 heading'
$release110ChangelogBody = @(Get-MarkdownSectionBody -Lines $changelogLines -Heading '## 1.1.0 - 2026-09-01')
$release110SteamBody = @(Get-MarkdownSectionBody -Lines $steamChangeNoteLines -Heading '## 1.1.0')
$releasedSteamBody = @(Get-MarkdownSectionBody -Lines $steamChangeNoteLines -Heading '## 1.0.0')
$release110ChangelogContent = @($release110ChangelogBody | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$release110SteamContent = @($release110SteamBody | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$releasedSteamContent = @($releasedSteamBody | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$expectedNextUpdateBullets = @(
    '- Fixed the digital-watch Survivor XP percentage remaining visible over the full-screen world map.'
    '- Added sandbox toggles for Survivor XP generation from each vanilla skill and one universal toggle for compatible custom skills.'
    '- Replaced the SLA-only Workshop browse thumbnail with the full-name artwork.'
    '- Clarified the dedicated-server shutdown and save-loss warning.'
)
$release110ChangelogBullets = @($release110ChangelogBody | Where-Object { $_.StartsWith('- ', [StringComparison]::Ordinal) })
$release110SteamBullets = @($release110SteamBody | Where-Object { $_.StartsWith('- ', [StringComparison]::Ordinal) })
Assert-ReleaseCondition ($release110ChangelogContent.Count -gt 0) 'non-empty changelog 1.1.0 section'
Assert-ReleaseCondition ($release110SteamContent.Count -gt 0) 'non-empty Steam 1.1.0 section'
Assert-ReleaseCondition ([string]::Join("`n", $release110ChangelogBullets) -ceq [string]::Join("`n", $expectedNextUpdateBullets)) 'exact changelog 1.1.0 update bullets'
Assert-ReleaseCondition ([string]::Join("`n", $release110SteamBullets) -ceq [string]::Join("`n", $expectedNextUpdateBullets)) 'exact matching Steam 1.1.0 update bullets'
Assert-ReleaseCondition ([string]::Join("`n", $release110ChangelogBullets) -ceq [string]::Join("`n", $release110SteamBullets)) 'exact ordered equality between changelog and Steam 1.1.0 bullets'
$changelogWithoutWatchMapNote = @($release110ChangelogBullets | Where-Object { $_ -cne $expectedNextUpdateBullets[0] })
$steamWithoutContributionNote = @($release110SteamBullets | Where-Object { $_ -cne $expectedNextUpdateBullets[1] })
Assert-ReleaseCondition (-not ([string]::Join("`n", $changelogWithoutWatchMapNote) -ceq [string]::Join("`n", $expectedNextUpdateBullets))) 'missing watch-map changelog note fixture fails exact bullets'
Assert-ReleaseCondition (-not ([string]::Join("`n", $steamWithoutContributionNote) -ceq [string]::Join("`n", $expectedNextUpdateBullets))) 'missing contribution Steam note fixture fails exact bullets'

$developerFacingHousekeepingPatterns = @(
    '(?i)\bsemicolons?\b|;'
    '(?i)\bpunctuation\b'
    '(?i)\bformatting\b'
    '(?i)\brefactor(?:ed|ing|s)?\b'
    '(?i)\btest suite\b'
    '(?i)\bvalidator\b'
    '(?i)\bCI\b'
)

function Test-NoDeveloperFacingReleaseHousekeeping {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Bullets
    )

    $bulletText = [string]::Join("`n", $Bullets)
    return @($developerFacingHousekeepingPatterns | Where-Object { $bulletText -match $_ }).Count -eq 0
}

Assert-ReleaseCondition (Test-NoDeveloperFacingReleaseHousekeeping -Bullets $release110ChangelogBullets) 'current changelog 1.1.0 bullets omit developer-facing housekeeping'
Assert-ReleaseCondition (Test-NoDeveloperFacingReleaseHousekeeping -Bullets $release110SteamBullets) 'current Steam 1.1.0 bullets omit developer-facing housekeeping'
$developerFacingHousekeepingFixtures = @(
    '- Removed semicolons from public copy.'
    '- Updated punctuation in public copy.'
    '- Adjusted formatting in public copy.'
    '- Refactored the release workflow.'
    '- Expanded the test suite.'
    '- Updated the release validator.'
    '- Adjusted CI checks.'
)
foreach ($fixture in $developerFacingHousekeepingFixtures) {
    Assert-ReleaseCondition (-not (Test-NoDeveloperFacingReleaseHousekeeping -Bullets @($fixture))) "developer-facing housekeeping fixture is rejected: $fixture"
}

function Test-NoStaleReleaseAuthoring {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Changelog,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$SteamNotes
    )

    return @($Changelog -ceq '## Unreleased').Count -eq 0 `
        -and @($SteamNotes -ceq '## Next update').Count -eq 0 `
        -and @($SteamNotes -ceq $authoringReminder).Count -eq 0
}

Assert-ReleaseCondition (Test-NoStaleReleaseAuthoring -Changelog $changelogLines -SteamNotes $steamChangeNoteLines) 'release cut contains no stale authoring markers'
$staleChangelogHeadingFixture = @($changelogLines + '## Unreleased')
$staleSteamHeadingFixture = @($steamChangeNoteLines + '## Next update')
$staleSteamReminderFixture = @($steamChangeNoteLines + $authoringReminder)
Assert-ReleaseCondition (-not (Test-NoStaleReleaseAuthoring -Changelog $staleChangelogHeadingFixture -SteamNotes $steamChangeNoteLines)) 'stale Unreleased heading fixture fails'
Assert-ReleaseCondition (-not (Test-NoStaleReleaseAuthoring -Changelog $changelogLines -SteamNotes $staleSteamHeadingFixture)) 'stale Next update heading fixture fails'
Assert-ReleaseCondition (-not (Test-NoStaleReleaseAuthoring -Changelog $changelogLines -SteamNotes $staleSteamReminderFixture)) 'stale authoring reminder fixture fails'
Assert-ReleaseCondition ($releasedSteamContent.Count -gt 0) 'non-empty Steam 1.0.0 section'
$openingSummaryCopy = 'Level your skills through normal play while also progressing your Survivor Level and earning Advancement Points to boost selected skills while keeping natural progression important.'
$howItWorksCopy = @(
    'SLA gives each character a Survivor Level separate from their normal skills. By default, XP earned in supported trainable skills also earns Survivor XP, with each Survivor Level granting one Advancement Point, or AP. AP can then be spent directly in the vanilla skills panel to raise the level of a selected skill.'
    "Advancing a skill with AP occupies the required number of Advancement Slots. To earn a slot back, you must naturally earn the XP that the AP allowed you to bypass. That XP still applies toward the skill's next level, allowing AP to boost your progress without replacing natural skill progression."
    "The final advancement to a skill's effective maximum, normally level 9 to level 10, is considered mastering the skill. Mastery costs 2 AP and requires 2 free Advancement Slots, then clears any active Advancement Slots on that skill. If the Global or Per Skill slot limit is set to 1, mastery only requires 1 free slot while retaining the 2 AP cost. Free mode requires no Advancement Slots while still retaining the 2 AP cost."
)
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
$levelInheritanceCopy = "Survivor Level inheritance is configured through sandbox settings and allows the host to set a percentage of a deceased character's Survivor Level that passes to that player's next eligible survivor. This allows you to continue playing in a world you've invested significant progress in, while still retaining some of the downside of becoming Zomboid chow."
$orderedContentContract = @(
    [pscustomobject]@{ Markdown = '## Features'; Workshop = 'description=[h2]Features[/h2]' }
    [pscustomobject]@{ Markdown = '## How it works'; Workshop = 'description=[h2]How it works[/h2]' }
    [pscustomobject]@{ Markdown = $howItWorksCopy[0]; Workshop = "description=$($howItWorksCopy[0])" }
    [pscustomobject]@{ Markdown = $howItWorksCopy[1]; Workshop = "description=$($howItWorksCopy[1])" }
    [pscustomobject]@{ Markdown = $howItWorksCopy[2]; Workshop = "description=$($howItWorksCopy[2])" }
    [pscustomobject]@{ Markdown = '## Advancement modes'; Workshop = 'description=[h2]Advancement modes[/h2]' }
    [pscustomobject]@{ Markdown = '## Optional level inheritance'; Workshop = 'description=[h2]Optional level inheritance[/h2]' }
    [pscustomobject]@{ Markdown = '## Adding or removing SLA'; Workshop = 'description=[h2]Adding or removing SLA[/h2]' }
    [pscustomobject]@{ Markdown = '## Dedicated servers and hosting'; Workshop = 'description=[h2]Dedicated servers and hosting[/h2]' }
    [pscustomobject]@{ Markdown = '## Compatibility'; Workshop = 'description=[h2]Compatibility[/h2]' }
    [pscustomobject]@{ Markdown = '## Current limits'; Workshop = 'description=[h2]Current limits[/h2]' }
)

function Test-ExactOrderedReleaseCopy {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedLines
    )

    $previousIndex = -1
    foreach ($expectedLine in $ExpectedLines) {
        $currentIndex = [Array]::IndexOf($Lines, $expectedLine)
        if ($currentIndex -le $previousIndex -or [Array]::LastIndexOf($Lines, $expectedLine) -ne $currentIndex) {
            return $false
        }

        $previousIndex = $currentIndex
    }

    return $true
}

$orderedMarkdownLines = @($orderedContentContract | ForEach-Object { $_.Markdown })
$orderedWorkshopLines = @($orderedContentContract | ForEach-Object { $_.Workshop })
Assert-ReleaseCondition (Test-ExactOrderedReleaseCopy -Lines $descriptionLines -ExpectedLines $orderedMarkdownLines) 'exact ordered Markdown release-copy contract'
Assert-ReleaseCondition (Test-ExactOrderedReleaseCopy -Lines $workshopLines -ExpectedLines $orderedWorkshopLines) 'exact ordered Workshop release-copy contract'
$reorderedWorkshopFixture = [string[]]$workshopLines.Clone()
$firstWorkshopParagraphIndex = [Array]::IndexOf($reorderedWorkshopFixture, $orderedContentContract[2].Workshop)
$secondWorkshopParagraphIndex = [Array]::IndexOf($reorderedWorkshopFixture, $orderedContentContract[3].Workshop)
$reorderedWorkshopFixture[$firstWorkshopParagraphIndex] = $orderedContentContract[3].Workshop
$reorderedWorkshopFixture[$secondWorkshopParagraphIndex] = $orderedContentContract[2].Workshop
Assert-ReleaseCondition (-not (Test-ExactOrderedReleaseCopy -Lines $reorderedWorkshopFixture -ExpectedLines $orderedWorkshopLines)) 'reordered Workshop How-it-works paragraph fixture fails'
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
$readmeContributionDisclosure = '- Let hosts enable or disable Survivor XP generation for individual vanilla skills and all compatible custom skills.'
$markdownContributionDisclosure = '- Individually enable or disable Survivor XP generation for each vanilla skill, plus one universal toggle for compatible custom skills'
$workshopContributionDisclosure = 'description=[*]Individually enable or disable Survivor XP generation for each vanilla skill, plus one universal toggle for compatible custom skills'
Assert-ReleaseCondition (@($readmeLines -ceq $readmeContributionDisclosure).Count -eq 1) 'exact README per-skill contribution disclosure'
Assert-ReleaseCondition (@($descriptionLines -ceq $markdownContributionDisclosure).Count -eq 1) 'exact Markdown per-skill contribution disclosure'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopContributionDisclosure).Count -eq 1) 'exact Workshop per-skill contribution disclosure'
$readmeWithoutContributionDisclosure = @($readmeLines | Where-Object { $_ -cne $readmeContributionDisclosure })
$markdownWithoutContributionDisclosure = @($descriptionLines | Where-Object { $_ -cne $markdownContributionDisclosure })
$workshopWithoutContributionDisclosure = @($workshopLines | Where-Object { $_ -cne $workshopContributionDisclosure })
Assert-ReleaseCondition (-not (@($readmeWithoutContributionDisclosure -ceq $readmeContributionDisclosure).Count -eq 1)) 'missing README contribution disclosure fixture fails'
Assert-ReleaseCondition (-not (@($markdownWithoutContributionDisclosure -ceq $markdownContributionDisclosure).Count -eq 1)) 'missing Markdown contribution disclosure fixture fails'
Assert-ReleaseCondition (-not (@($workshopWithoutContributionDisclosure -ceq $workshopContributionDisclosure).Count -eq 1)) 'missing Workshop contribution disclosure fixture fails'
$markdownWithMutatedContributionDisclosure = @(
    $descriptionLines | ForEach-Object {
        if ($_ -ceq $markdownContributionDisclosure) {
            $_.Replace('Individually enable or disable', 'Enable or disable')
        } else {
            $_
        }
    }
)
Assert-ReleaseCondition (-not (@($markdownWithMutatedContributionDisclosure -ceq $markdownContributionDisclosure).Count -eq 1)) 'mutated Markdown contribution disclosure fixture fails'
Assert-ReleaseCondition (@($descriptionLines -ceq $openingSummaryCopy).Count -eq 1) 'exact Markdown opening summary'
Assert-ReleaseCondition (@($workshopLines -ceq "description=$openingSummaryCopy").Count -eq 1) 'exact Workshop opening summary'
foreach ($paragraph in $howItWorksCopy) {
    Assert-ReleaseCondition (@($descriptionLines -ceq $paragraph).Count -eq 1) "exact Markdown How-it-works paragraph: $paragraph"
    Assert-ReleaseCondition (@($workshopLines -ceq "description=$paragraph").Count -eq 1) "exact Workshop How-it-works paragraph: $paragraph"
}
$markdownWithoutHowItWorksParagraph = @($descriptionLines | Where-Object { $_ -cne $howItWorksCopy[1] })
$workshopWithMutatedHowItWorksParagraph = @(
    $workshopLines | ForEach-Object {
        if ($_ -ceq "description=$($howItWorksCopy[0])") {
            $_.Replace('By default', 'Typically')
        } else {
            $_
        }
    }
)
Assert-ReleaseCondition (-not (@($markdownWithoutHowItWorksParagraph -ceq $howItWorksCopy[1]).Count -eq 1)) 'missing Markdown How-it-works paragraph fixture fails'
Assert-ReleaseCondition (-not (@($workshopWithMutatedHowItWorksParagraph -ceq "description=$($howItWorksCopy[0])").Count -eq 1)) 'mutated Workshop How-it-works paragraph fixture fails'
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
Assert-ReleaseCondition (@($descriptionLines -ceq '## Optional level inheritance').Count -eq 1) 'exact Markdown Optional level inheritance heading'
Assert-ReleaseCondition (@($workshopLines -ceq 'description=[h2]Optional level inheritance[/h2]').Count -eq 1) 'exact Workshop Optional level inheritance heading'
Assert-ReleaseCondition (@($descriptionLines -ceq $levelInheritanceCopy).Count -eq 1) 'exact Markdown Optional level inheritance copy'
Assert-ReleaseCondition (@($workshopLines -ceq "description=$levelInheritanceCopy").Count -eq 1) 'exact Workshop Optional level inheritance copy'
$markdownFeaturesIndex = [Array]::IndexOf($descriptionLines, '## Features')
$markdownHowItWorksIndex = [Array]::IndexOf($descriptionLines, '## How it works')
$workshopFeaturesIndex = [Array]::IndexOf($workshopLines, 'description=[h2]Features[/h2]')
$workshopHowItWorksIndex = [Array]::IndexOf($workshopLines, 'description=[h2]How it works[/h2]')
Assert-ReleaseCondition ($markdownFeaturesIndex -ge 0 -and $markdownFeaturesIndex -lt $markdownHowItWorksIndex) 'Markdown Features section before How it works'
Assert-ReleaseCondition ($workshopFeaturesIndex -ge 0 -and $workshopFeaturesIndex -lt $workshopHowItWorksIndex) 'Workshop Features section before How it works'
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
$markdownHookConflictCopy = '- **Potential hook conflicts:** Mods that replace skill-XP award functions or `Events.AddXP`, the vanilla Skills panel, online-player context menus, or digital-watch rendering may conflict with the related SLA feature. If SLA detects a required hook was replaced, it disables that capability rather than risking incorrect behavior.'
$workshopHookConflictCopy = 'description=[*][b]Potential hook conflicts:[/b] Mods that replace skill-XP award functions or Events.AddXP, the vanilla Skills panel, online-player context menus, or digital-watch rendering may conflict with the related SLA feature. If SLA detects a required hook was replaced, it disables that capability rather than risking incorrect behavior.'
$markdownCustomProgressionCopy = '- **Custom progression boundary:** Compatible trainable skills with a usable XP curve and supported XP events are expected to work. Mods that directly set skill XP or levels, replace caps or curves incompatibly, or bypass supported XP events may not grant Survivor XP.'
$workshopCustomProgressionCopy = 'description=[*][b]Custom progression boundary:[/b] Compatible trainable skills with a usable XP curve and supported XP events are expected to work. Mods that directly set skill XP or levels, replace caps or curves incompatibly, or bypass supported XP events may not grant Survivor XP.'
$markdownCurrentlyUnsupportedCopy = '- **Currently unsupported: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) and [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. These mods directly replace progression rules that SLA relies on.'
$workshopCurrentlyUnsupportedCopy = 'description=[*][b]Currently unsupported: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705]Beyond Ten - Level 15 Skills[/url] and [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643]Seesaw Game[/url][/b]. These mods directly replace progression rules that SLA relies on.'
$markdownTestedTogetherCopy = "- **Tested together: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939), and [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. This combination worked without issue in testing, but compatibility with every interface or custom-skill mod cannot be guaranteed."
$workshopTestedTogetherCopy = "description=[*][b]Tested together: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242]Detailed Skill Tooltips[/url], [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939]Toughness Skill[/url], and [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883]Show Skill XP Gain B42.20[/url][/b]. This combination worked without issue in testing, but compatibility with every interface or custom-skill mod cannot be guaranteed."
Assert-ReleaseCondition (@($descriptionLines -ceq $markdownCurrentlyUnsupportedCopy).Count -eq 1) 'exact Markdown currently-unsupported compatibility entry'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopCurrentlyUnsupportedCopy).Count -eq 1) 'exact Workshop currently-unsupported compatibility entry'
Assert-ReleaseCondition (@($descriptionLines -ceq $markdownTestedTogetherCopy).Count -eq 1) 'exact Markdown tested-together compatibility entry'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopTestedTogetherCopy).Count -eq 1) 'exact Workshop tested-together compatibility entry'
Assert-ReleaseCondition (@($descriptionLines -ceq $markdownHookConflictCopy).Count -eq 1) 'exact Markdown potential-hook-conflicts boundary'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopHookConflictCopy).Count -eq 1) 'exact Workshop potential-hook-conflicts boundary'
Assert-ReleaseCondition (@($descriptionLines -ceq $markdownCustomProgressionCopy).Count -eq 1) 'exact Markdown custom-progression boundary'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopCustomProgressionCopy).Count -eq 1) 'exact Workshop custom-progression boundary'
$markdownTestedTogetherIndex = [Array]::IndexOf($descriptionLines, $markdownTestedTogetherCopy)
$markdownHookConflictIndex = [Array]::IndexOf($descriptionLines, $markdownHookConflictCopy)
$markdownCustomProgressionIndex = [Array]::IndexOf($descriptionLines, $markdownCustomProgressionCopy)
$workshopTestedTogetherIndex = [Array]::IndexOf($workshopLines, $workshopTestedTogetherCopy)
$workshopHookConflictIndex = [Array]::IndexOf($workshopLines, $workshopHookConflictCopy)
$workshopCustomProgressionIndex = [Array]::IndexOf($workshopLines, $workshopCustomProgressionCopy)
Assert-ReleaseCondition ($markdownTestedTogetherIndex -ge 0 -and $markdownTestedTogetherIndex -lt $markdownHookConflictIndex -and $markdownHookConflictIndex -lt $markdownCustomProgressionIndex) 'Markdown Tested together before generalized compatibility boundaries'
Assert-ReleaseCondition ($workshopTestedTogetherIndex -ge 0 -and $workshopTestedTogetherIndex -lt $workshopHookConflictIndex -and $workshopHookConflictIndex -lt $workshopCustomProgressionIndex) 'Workshop Tested together before generalized compatibility boundaries'
Assert-ReleaseCondition ($descriptionText.Contains('[Ko-fi](https://ko-fi.com/skeptic043)')) 'Markdown Ko-fi link'
Assert-ReleaseCondition ($workshopText.Contains('[url=https://ko-fi.com/skeptic043]Ko-fi[/url]')) 'Workshop Ko-fi link'
Assert-ReleaseCondition ($descriptionText.Contains('Optional support: [Ko-fi](https://ko-fi.com/skeptic043). All donations are strictly optional and no mod features are locked behind a paywall.')) 'Markdown support copy'
Assert-ReleaseCondition ($workshopText.Contains('description=Optional support: [url=https://ko-fi.com/skeptic043]Ko-fi[/url]. All donations are strictly optional and no mod features are locked behind a paywall.')) 'Workshop support copy'
$administrationCopy = 'Authorized administrators can open "Admin Panel > Mini Scoreboard" or "Admin Panel > Users List", right-click an online player, and choose "Survivor progression". Administrators can inspect progression, award positive Survivor XP or whole Survivor Levels, clear active Advancement Slots (without refunding AP or changing skill XP), and refresh the target state. An administrator can manage their own SLA progression from the "Admin" button in the Skills panel. Administration is limited to online players.'
$workshopAdministrationLine = "description=$administrationCopy"
$dedicatedSaveLimitCopy = 'Dedicated servers should set the native SaveWorldEveryMinutes option to a nonzero value. Closing the server by any method other than the quit command can potentially lose SLA progression written after the last successful server save. A shorter save interval means less progression possibly lost in the event of a server failure.'
$markdownDedicatedSaveLimitLine = 'Dedicated servers should set the native `SaveWorldEveryMinutes` option to a nonzero value. Closing the server by any method other than the `quit` command can potentially lose SLA progression written after the last successful server save. A shorter save interval means less progression possibly lost in the event of a server failure.'
$workshopDedicatedSaveLimitLine = "description=$dedicatedSaveLimitCopy"
$backupRecommendationCopy = 'As with any mod-list change, I strongly recommend backing up any ongoing world you care about.'
$staleWatchSettingsCopy = "Optional sandbox settings also provide Survivor Level inheritance and a small digital watch integration."
Assert-ReleaseCondition (@($descriptionLines -ceq '## Dedicated servers and hosting').Count -eq 1) 'exact Markdown Dedicated servers and hosting heading'
Assert-ReleaseCondition (@($workshopLines -ceq 'description=[h2]Dedicated servers and hosting[/h2]').Count -eq 1) 'exact Workshop Dedicated servers and hosting heading'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopAdministrationLine).Count -eq 1) 'exact Workshop online-player administration copy for Mini Scoreboard and Users List'
Assert-ReleaseCondition (@($descriptionLines -ceq $administrationCopy).Count -eq 1) 'exact Markdown online-player administration copy for Mini Scoreboard and Users List'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopDedicatedSaveLimitLine).Count -eq 1) 'exact Workshop dedicated SaveWorldEveryMinutes limitation copy'
Assert-ReleaseCondition (@($descriptionLines -ceq $markdownDedicatedSaveLimitLine).Count -eq 1) 'exact Markdown dedicated SaveWorldEveryMinutes limitation copy'
Assert-ReleaseCondition (@($descriptionLines -ceq $backupRecommendationCopy).Count -eq 1) 'exact Markdown revised backup recommendation'
Assert-ReleaseCondition (@($workshopLines -ceq "description=$backupRecommendationCopy").Count -eq 1) 'exact Workshop revised backup recommendation'
$markdownDedicatedHeadingIndex = [Array]::IndexOf($descriptionLines, '## Dedicated servers and hosting')
$markdownAdministrationIndex = [Array]::IndexOf($descriptionLines, $administrationCopy)
$markdownDedicatedSaveIndex = [Array]::IndexOf($descriptionLines, $markdownDedicatedSaveLimitLine)
$workshopDedicatedHeadingIndex = [Array]::IndexOf($workshopLines, 'description=[h2]Dedicated servers and hosting[/h2]')
$workshopAdministrationIndex = [Array]::IndexOf($workshopLines, $workshopAdministrationLine)
$workshopDedicatedSaveIndex = [Array]::IndexOf($workshopLines, $workshopDedicatedSaveLimitLine)
Assert-ReleaseCondition ($markdownDedicatedHeadingIndex -ge 0 -and $markdownDedicatedHeadingIndex -lt $markdownAdministrationIndex -and $markdownAdministrationIndex -lt $markdownDedicatedSaveIndex) 'Markdown dedicated-server copy in non-list section order'
Assert-ReleaseCondition ($workshopDedicatedHeadingIndex -ge 0 -and $workshopDedicatedHeadingIndex -lt $workshopAdministrationIndex -and $workshopAdministrationIndex -lt $workshopDedicatedSaveIndex) 'Workshop dedicated-server copy in non-list section order'
Assert-ReleaseCondition (-not $descriptionText.Contains($staleWatchSettingsCopy)) 'Markdown omits stale combined sandbox-settings watch copy'
Assert-ReleaseCondition (-not $workshopText.Contains("description=$staleWatchSettingsCopy")) 'Workshop omits stale combined sandbox-settings watch copy'
Assert-ReleaseCondition (-not $readmeText.Contains(';')) 'README prose omits semicolons'
Assert-ReleaseCondition (-not $descriptionText.Contains(';')) 'Markdown Workshop description prose omits semicolons'
$workshopDescriptionLines = @($workshopLines | Where-Object { $_.StartsWith('description=', [StringComparison]::Ordinal) })
Assert-ReleaseCondition (@($workshopDescriptionLines -match ';').Count -eq 0) 'Workshop description lines omit semicolons'

function Get-WorkshopDescriptionPayload {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Separator
    )

    $descriptionValues = @(
        $Lines |
            Where-Object { $_.StartsWith('description=', [StringComparison]::Ordinal) } |
            ForEach-Object { $_.Substring('description='.Length) }
    )
    return [string]::Join($Separator, $descriptionValues)
}

function Test-WorkshopDescriptionWithinLimit {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [int]$MaximumLength
    )

    $payload = Get-WorkshopDescriptionPayload -Lines $Lines -Separator "`r`n"
    return $payload.Length -le $MaximumLength
}

$workshopDescriptionLimit = 7800
$workshopDescriptionPayloadLF = Get-WorkshopDescriptionPayload -Lines $workshopLines -Separator "`n"
$workshopDescriptionPayloadCRLF = Get-WorkshopDescriptionPayload -Lines $workshopLines -Separator "`r`n"
Assert-ReleaseCondition (Test-WorkshopDescriptionWithinLimit -Lines $workshopLines -MaximumLength $workshopDescriptionLimit) "Workshop description conservative CRLF payload exceeds $workshopDescriptionLimit characters"
$overLimitWorkshopFixture = @("description=$('x' * ($workshopDescriptionLimit + 1))")
Assert-ReleaseCondition (-not (Test-WorkshopDescriptionWithinLimit -Lines $overLimitWorkshopFixture -MaximumLength $workshopDescriptionLimit)) 'over-limit Workshop description fixture fails'

$aiUseDisclosure = 'AI was used to write all of the code in this project. The original concept, design direction, testing, debugging, and release decisions are my own. I spent many hours personally testing SLA and working through issues to make sure it behaves as intended. If you prefer not to use mods developed with AI assistance, I understand and respect that choice.'
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

Assert-PngDimensions $previewPath 512 512 'preview'
Assert-PngDimensions $posterPath 512 512 'poster'
Assert-PngDimensions $iconPath 64 64 'icon'
$previewHash = (Get-FileHash -LiteralPath $previewPath -Algorithm SHA256).Hash
$fullNamePosterHash = (Get-FileHash -LiteralPath $fullNamePosterPath -Algorithm SHA256).Hash
Assert-ReleaseCondition ($previewHash -eq $fullNamePosterHash) 'preview is byte-identical to full-name Workshop artwork'
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

Write-Host "Workshop description payload length: LF=$($workshopDescriptionPayloadLF.Length), CRLF=$($workshopDescriptionPayloadCRLF.Length), limit=$workshopDescriptionLimit."
Write-Host "Workshop release-source validation passed ($($script:Assertions) assertions)."
