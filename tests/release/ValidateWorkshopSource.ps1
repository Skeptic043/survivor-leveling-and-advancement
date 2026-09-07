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
$githubReleaseNotesPath = Join-Path $projectRoot 'assets\release\GITHUB_RELEASE_NOTES.md'
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
    $githubReleaseNotesPath,
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
$githubReleaseNoteLines = @(Get-Content -LiteralPath $githubReleaseNotesPath)
$githubReleaseNoteText = Get-Content -Raw -LiteralPath $githubReleaseNotesPath

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

function Get-MarkdownDocumentBody {
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

    return @($Lines | Select-Object -Skip ($startIndex + 1))
}

function Test-NoDateShapedText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $dateShapedTextPattern = '(?<!\d)(?:19|20)\d{2}[-/]\d{2}[-/]\d{2}(?!\d)'
    return -not ([string]::Join("`n", $Lines) -match $dateShapedTextPattern)
}

Assert-ReleaseCondition (@($changelogLines -ceq '## 1.0.0 - 2026-08-30').Count -eq 1) 'exact released 1.0.0 changelog heading'
Assert-ReleaseCondition (@($changelogLines -ceq '## 1.0.0 - Unreleased').Count -eq 0) 'changelog omits stale 1.0.0 Unreleased heading'
Assert-ReleaseCondition (@($changelogLines -ceq '## 1.1.0 - 2026-09-01').Count -eq 1) 'exact released 1.1.0 changelog heading'
Assert-ReleaseCondition (@($changelogLines -ceq '## 1.1.1 - 2026-09-06').Count -eq 1) 'exact released 1.1.1 changelog heading'
Assert-ReleaseCondition (@($changelogLines -match '^## 1\.1\.1').Count -eq 1) 'exactly one changelog 1.1.1 heading'
Assert-ReleaseCondition (@($changelogLines -ceq '## Unreleased').Count -eq 0) 'changelog omits stale Unreleased heading'
Assert-ReleaseCondition (@($steamChangeNoteLines -ceq '## 1.1.1').Count -eq 1) 'exact released Steam 1.1.1 heading'
Assert-ReleaseCondition (@($steamChangeNoteLines -match '^## 1\.1\.1').Count -eq 1) 'exactly one Steam 1.1.1 heading'
Assert-ReleaseCondition (@($steamChangeNoteLines -ceq '## 1.1.0').Count -eq 1) 'exact released Steam 1.1.0 heading'
Assert-ReleaseCondition (@($steamChangeNoteLines -ceq '## Next update').Count -eq 0) 'Steam notes omit stale Next update heading'
$authoringReminder = 'Add any further player-visible changes here before the next upload.'
Assert-ReleaseCondition (@($steamChangeNoteLines -ceq $authoringReminder).Count -eq 0) 'Steam notes omit the release-authoring reminder'
Assert-ReleaseCondition (@($steamChangeNoteLines -ceq '## 1.0.0').Count -eq 1) 'exact one Steam 1.0.0 heading'
$release110ChangelogBody = @(Get-MarkdownSectionBody -Lines $changelogLines -Heading '## 1.1.0 - 2026-09-01')
$release110SteamBody = @(Get-MarkdownSectionBody -Lines $steamChangeNoteLines -Heading '## 1.1.0')
$release100ChangelogBody = @(Get-MarkdownSectionBody -Lines $changelogLines -Heading '## 1.0.0 - 2026-08-30')
$releasedSteamBody = @(Get-MarkdownSectionBody -Lines $steamChangeNoteLines -Heading '## 1.0.0')
$release111ChangelogBody = @(Get-MarkdownSectionBody -Lines $changelogLines -Heading '## 1.1.1 - 2026-09-06')
$release111SteamBody = @(Get-MarkdownSectionBody -Lines $steamChangeNoteLines -Heading '## 1.1.1')
$release111GithubBody = @(Get-MarkdownDocumentBody -Lines $githubReleaseNoteLines -Heading '# Survivor Leveling & Advancement v1.1.1')
$release110ChangelogContent = @($release110ChangelogBody | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$release110SteamContent = @($release110SteamBody | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$releasedSteamContent = @($releasedSteamBody | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$expectedNextUpdateBullets = @(
    '- Fixed the digital-watch Survivor XP percentage remaining visible over the full-screen world map.'
    '- Added sandbox toggles for Survivor XP generation from each vanilla skill and one universal toggle for compatible custom skills.'
    '- Replaced the SLA-only Workshop browse thumbnail with the full-name artwork.'
    '- Clarified the dedicated-server shutdown and save-loss warning.'
)
$expectedRelease100ChangelogBullets = @(
    '- Earn independently paced Survivor XP from accepted trainable-skill XP.'
    '- Gain one Advancement Point for each Survivor Level and spend it directly from the vanilla Skills panel.'
    '- Choose Global, Per Skill, or Free advancement accounting through sandbox settings.'
    '- Track AP-created advancement separately from natural skill progress, including visible catch-up and recovery states.'
    '- Support compatible custom trainable skills through automatic curve normalization.'
    '- Provide server-authoritative multiplayer progression, remote administration, and optional one-use Survivor Level inheritance.'
    '- Show optional Player 1 Survivor XP progress inside the digital watch.'
    '- Preserve accepted skill levels when SLA is disabled and reconcile supported skill changes when it is re-enabled.'
)
$expectedRelease100SteamContent = @($expectedRelease100ChangelogBullets)
$expectedRelease111Bullets = @(
    '- Added administration for existing offline player profiles.'
    '- Reduced server processing for SLA progress updates in worlds with many stored characters.'
    '- Dead-character SLA profiles are now removed after their replacement character is created instead of being kept as unused history.'
    '- Advancement tooltips now show the number of free slots required.'
    '- Hover over Advancement Slots for a short explanation of how to free them.'
    '- Added an optional high-contrast setting for advancement and recovery markers.'
    '- Controller users can now see the XP needed to free advancement slots.'
    '- Fixed the digital watch''s Survivor XP percentage updating every frame instead of once per second.'
)
$release110ChangelogBullets = @($release110ChangelogBody | Where-Object { $_.StartsWith('- ', [StringComparison]::Ordinal) })
$release110SteamBullets = @($release110SteamBody | Where-Object { $_.StartsWith('- ', [StringComparison]::Ordinal) })
$release100ChangelogBullets = @($release100ChangelogBody | Where-Object { $_.StartsWith('- ', [StringComparison]::Ordinal) })
$release111ChangelogBullets = @($release111ChangelogBody | Where-Object { $_.StartsWith('- ', [StringComparison]::Ordinal) })
$release111SteamBullets = @($release111SteamBody | Where-Object { $_.StartsWith('- ', [StringComparison]::Ordinal) })
$release111GithubBullets = @($githubReleaseNoteLines | Where-Object { $_.StartsWith('- ', [StringComparison]::Ordinal) })
Assert-ReleaseCondition ($release110ChangelogContent.Count -gt 0) 'non-empty changelog 1.1.0 section'
Assert-ReleaseCondition ($release110SteamContent.Count -gt 0) 'non-empty Steam 1.1.0 section'
Assert-ReleaseCondition ([string]::Join("`n", $release110ChangelogBullets) -ceq [string]::Join("`n", $expectedNextUpdateBullets)) 'exact changelog 1.1.0 update bullets'
Assert-ReleaseCondition ([string]::Join("`n", $release110SteamBullets) -ceq [string]::Join("`n", $expectedNextUpdateBullets)) 'exact matching Steam 1.1.0 update bullets'
Assert-ReleaseCondition ([string]::Join("`n", $release110ChangelogBullets) -ceq [string]::Join("`n", $release110SteamBullets)) 'exact ordered equality between changelog and Steam 1.1.0 bullets'
Assert-ReleaseCondition ([string]::Join("`n", $release100ChangelogBullets) -ceq [string]::Join("`n", $expectedRelease100ChangelogBullets)) 'released changelog 1.0.0 bullets remain unchanged'
Assert-ReleaseCondition ([string]::Join("`n", $releasedSteamContent) -ceq [string]::Join("`n", $expectedRelease100SteamContent)) 'released Steam 1.0.0 content remains unchanged'
Assert-ReleaseCondition ([string]::Join("`n", $release111ChangelogBullets) -ceq [string]::Join("`n", $expectedRelease111Bullets)) 'exact changelog 1.1.1 release bullets'
Assert-ReleaseCondition ([string]::Join("`n", $release111SteamBullets) -ceq [string]::Join("`n", $expectedRelease111Bullets)) 'exact Steam 1.1.1 release bullets'
Assert-ReleaseCondition ([string]::Join("`n", $release111GithubBullets) -ceq [string]::Join("`n", $expectedRelease111Bullets)) 'exact GitHub 1.1.1 release bullets'
Assert-ReleaseCondition ([string]::Join("`n", $release111ChangelogBullets) -ceq [string]::Join("`n", $release111SteamBullets)) 'exact ordered equality between changelog and Steam 1.1.1 bullets'
Assert-ReleaseCondition ([string]::Join("`n", $release111SteamBullets) -ceq [string]::Join("`n", $release111GithubBullets)) 'exact ordered equality between Steam and GitHub 1.1.1 bullets'
$extraRelease111BulletFixture = @($release111ChangelogBullets + '- Unexpected extra v1.2 change-note bullet.')
Assert-ReleaseCondition (-not ([string]::Join("`n", $extraRelease111BulletFixture) -ceq [string]::Join("`n", $expectedRelease111Bullets))) 'extra v1.2 change-note bullet fixture fails exact contract'
Assert-ReleaseCondition (@($githubReleaseNoteLines -ceq '# Survivor Leveling & Advancement v1.1.1').Count -eq 1) 'exact GitHub v1.1.1 release title'
Assert-ReleaseCondition (@($githubReleaseNoteLines -ceq 'Draft release notes').Count -eq 0) 'GitHub notes omit stale draft label'
Assert-ReleaseCondition (-not $githubReleaseNoteText.Contains('Version 1.1.1 is not yet released and is awaiting live acceptance.')) 'GitHub notes omit stale unreleased blurb'
Assert-ReleaseCondition (Test-NoDateShapedText -Lines $release111ChangelogBody) 'changelog v1.1.1 body keeps the release date in its heading'
Assert-ReleaseCondition (Test-NoDateShapedText -Lines $release111SteamBody) 'Steam v1.1.1 body omits invented release date'
Assert-ReleaseCondition (Test-NoDateShapedText -Lines $release111GithubBody) 'GitHub v1.1.1 body omits invented release date'
$datedChangelogBodyFixture = @($release111ChangelogBody + 'Planned release date: 2026-09-02')
$datedSteamBodyFixture = @($release111SteamBody + 'Planned release date: 2026-09-02')
Assert-ReleaseCondition (-not (Test-NoDateShapedText -Lines $datedChangelogBodyFixture)) 'invented date in changelog v1.1.1 body fixture fails'
Assert-ReleaseCondition (-not (Test-NoDateShapedText -Lines $datedSteamBodyFixture)) 'invented date in Steam v1.1.1 body fixture fails'
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
$howItWorksCopy = "SLA gives each character a Survivor Level separate from their normal skills. By default, XP earned in supported trainable skills also earns Survivor XP, with each Survivor Level granting one Advancement Point, or AP. AP can then be spent directly in the vanilla skills panel to raise the level of a selected skill. Advancing a skill with AP occupies the required number of Advancement Slots. To earn a slot back, you must naturally earn the XP that the AP allowed you to bypass. That XP still applies toward the skill's next level, allowing AP to boost your progress without replacing natural skill progression. The final advancement to a skill's effective maximum, normally level 9 to level 10, is considered mastering the skill. Mastery costs 2 AP and requires 2 free Advancement Slots, then clears any active Advancement Slots on that skill. If the Global or Per Skill slot limit is set to 1, mastery only requires 1 free slot while retaining the 2 AP cost. Free mode requires no Advancement Slots while still retaining the 2 AP cost."
$advancementModeCopy = @(
    '**Global:** Shares one configurable pool of Advancement Slots across every skill, with a default limit of 3 active slots in total.'
    '**Per Skill:** Gives each skill its own configurable slot limit, using a default for compatible custom skills and optional overrides for vanilla skills.'
    '**Free:** Removes Advancement Slot limits and catch-up or recovery restrictions.'
)
$staleFreeModeCopy = 'Free mode does not track catch-up or recovery.'
$modeRecoveryCopy = 'In Global and Per Skill modes, losing levels or XP (Fitness/Strength) puts that skill into a recovery state that grants no Survivor XP until the lost progress is recovered.'
$modeAccountingNote = 'Changing modes does not reset tracked progress. Natural skill XP earned while Free is selected still counts toward any preserved catch-up or recovery, and switching back to Global or Per Skill restores only what remains.'
$combinedModeAccountingCopy = "$modeRecoveryCopy **Note:** $modeAccountingNote"
$levelInheritanceCopy = "Survivor Level inheritance is configured through sandbox settings. The host can set a percentage of a deceased character's Survivor Level to pass to that player's next eligible survivor. This lets a player retain some long-term progress while death still carries a cost."
$addingRemovingCopy = 'SLA can be added to or removed from existing saves. Existing skills are preserved, and past progression does not grant retroactive Survivor Levels. Disabling SLA hides its interface but leaves AP-granted skill levels in place. Re-enabling it restores SLA state and reconciles supported progression earned while it was absent. As with any mod-list change, I strongly recommend backing up any ongoing world you care about.'
function Get-NormalizedReleaseCopy {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Markdown', 'Workshop')]
        [string]$Format
    )

    $content = foreach ($line in $Lines) {
        if ($Format -eq 'Workshop') {
            if (-not $line.StartsWith('description=', [StringComparison]::Ordinal)) {
                continue
            }
            $value = $line.Substring('description='.Length)
            $value = $value -replace '\[url=([^\]]+)\](.*?)\[/url\]', '$2 <$1>'
            $value = $value -replace '\[/?(?:h[1-6]|b|list)\]|\[\*\]', ''
        } else {
            $value = $line -replace '^#{1,6}\s+', '' -replace '^\s*-\s+', ''
            $value = $value -replace '\[([^\]]+)\]\(([^)]+)\)', '$1 <$2>'
            $value = $value.Replace('**', '').Replace('`', '')
            if ($line.StartsWith('# ', [StringComparison]::Ordinal)) {
                $value = $value -replace ' \[B42\]$', ''
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $value.Trim()
        }
    }
    return ([string]::Join(' ', @($content)) -replace '\s+', ' ').Trim()
}

$normalizedMarkdown = Get-NormalizedReleaseCopy -Lines $descriptionLines -Format Markdown
$normalizedWorkshop = Get-NormalizedReleaseCopy -Lines $workshopLines -Format Workshop
Assert-ReleaseCondition ($normalizedMarkdown -ceq $normalizedWorkshop) 'Markdown and Workshop description content and links agree'
$changedWorkshopCopyFixture = @($workshopLines + 'description=Unmatched Workshop content.')
Assert-ReleaseCondition ($normalizedMarkdown -cne (Get-NormalizedReleaseCopy -Lines $changedWorkshopCopyFixture -Format Workshop)) 'unmatched Workshop content fixture fails agreement'

$semanticRequirements = [ordered]@{
    'one AP per Survivor Level' = 'each Survivor Level giving you one Advancement Point'
    'default three-slot allowance' = 'By default, you can have three advancement slots occupied at once'
    'catch-up XP also advances the next level' = 'XP you skipped, with that XP also counting toward your next skill level'
    'mastery requires two AP and two slots' = 'Mastery costs 2 AP and requires 2 free Advancement Slots'
    'one-slot mastery exception retains two AP cost' = 'slot limit is set to 1, mastery only requires 1 free slot while retaining the 2 AP cost'
    'Free-mode mastery retains two AP cost' = 'Free mode requires no Advancement Slots while still retaining the 2 AP cost'
    'inheritance stays in the same world' = 'carries over to your next character in the same world'
    'inheritance example math' = 'Survivor Level 20 with inheritance set to 50% gives your next character Survivor Level 10 and 10 AP'
    'inheritance does not copy skills' = 'Your old skill levels are not copied'
    'inheritance defaults off' = 'Inheritance is optional and disabled by default'
    'per-skill contribution settings' = 'Fitness, Strength, individual vanilla skills, and compatible custom skills contribute'
}
foreach ($requirement in $semanticRequirements.GetEnumerator()) {
    Assert-ReleaseCondition ($normalizedMarkdown.Contains($requirement.Value)) "Workshop gameplay semantics: $($requirement.Key)"
}
foreach ($modeCopy in $advancementModeCopy) {
    Assert-ReleaseCondition (@($descriptionLines -ceq "- $modeCopy").Count -eq 1) "Markdown advancement mode semantics: $modeCopy"
}
Assert-ReleaseCondition (-not $normalizedMarkdown.Contains($staleFreeModeCopy)) 'Workshop omits stale Free-mode accounting copy'
Assert-ReleaseCondition ($descriptionText.Contains($combinedModeAccountingCopy)) 'Workshop preserves recovery and mode-switch accounting boundary'
Assert-ReleaseCondition ($descriptionText.Contains($addingRemovingCopy)) 'Workshop preserves existing-save and removing-mod boundary'

$featureCopy = @(
    'Earn independent Survivor XP and Survivor Levels from supported trainable skill XP'
    'Gain one AP per Survivor Level and spend AP to advance skills directly'
    'Choose Global, Per Skill, or Free advancement modes'
    'Keep AP advancement separate from natural progress through visible catch-up and recovery'
    'Configure the Survivor XP multiplier, Fitness and Strength contribution, each vanilla skill toggle, and the compatible-custom-skill toggle'
    'Normalize progression curves for compatible custom skills'
    'Use server-authoritative multiplayer progression and administer existing online or offline profiles'
    "Optionally inherit part of a dead character's Survivor Level"
    'Use the vanilla Skills panel with controller and split-screen support'
    'Optionally show Player 1 Survivor XP on the digital watch through Mod Options'
)


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
Assert-ReleaseCondition (@($descriptionLines -ceq '- [Ko-fi](https://ko-fi.com/skeptic043) donations are optional, and no mod features are locked behind a paywall.').Count -eq 1) 'Markdown support list copy'
Assert-ReleaseCondition (@($workshopLines -ceq 'description=[*][url=https://ko-fi.com/skeptic043]Ko-fi[/url] donations are optional, and no mod features are locked behind a paywall.').Count -eq 1) 'Workshop support list copy'
$administrationCopy = 'Admins can manage existing online and offline SLA profiles. Positive Survivor XP and whole Survivor Levels apply immediately to offline profiles. Clear Advancements queues the action for offline profiles, remaining visible and cancellable, applying when that character reconnects. Clear Advancements does not refund AP or change vanilla skill XP.'
$workshopAdministrationLine = "description=$administrationCopy"
$dedicatedSaveLimitCopy = "SLA uses Project Zomboid's normal saves. On hosted and dedicated servers, enable SaveWorldEveryMinutes and shut down the server normally."
$markdownDedicatedSaveLimitLine = $dedicatedSaveLimitCopy
$readmeDedicatedSaveLimitLine = "SLA uses Project Zomboid's normal saves. For hosted and dedicated servers, set ``SaveWorldEveryMinutes`` above ``0`` to enable periodic world saves and shut down the server normally. A crash, forced shutdown, or power failure can lose SLA changes made since the last successful world save."
$workshopDedicatedSaveLimitLine = "description=$dedicatedSaveLimitCopy"
$staleWatchSettingsCopy = "Optional sandbox settings also provide Survivor Level inheritance and a small digital watch integration."
Assert-ReleaseCondition (@($descriptionLines -ceq '## Dedicated servers and hosting').Count -eq 1) 'exact Markdown Dedicated servers and hosting heading'
Assert-ReleaseCondition (@($workshopLines -ceq 'description=[h2]Dedicated servers and hosting[/h2]').Count -eq 1) 'exact Workshop Dedicated servers and hosting heading'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopAdministrationLine).Count -eq 1) 'exact Workshop online and offline administration copy'
Assert-ReleaseCondition (@($descriptionLines -ceq $administrationCopy).Count -eq 1) 'exact Markdown online and offline administration copy'
Assert-ReleaseCondition (@($workshopLines -ceq $workshopDedicatedSaveLimitLine).Count -eq 1) 'exact Workshop native saving copy'
Assert-ReleaseCondition (@($descriptionLines -ceq $markdownDedicatedSaveLimitLine).Count -eq 1) 'exact Markdown native saving copy'
Assert-ReleaseCondition (@($readmeLines -ceq $administrationCopy).Count -eq 1) 'exact README online and offline administration copy'
Assert-ReleaseCondition (@($readmeLines -ceq $readmeDedicatedSaveLimitLine).Count -eq 1) 'exact README native saving and recent-loss limitation copy'
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
Assert-ReleaseCondition (-not ((Get-Content -Raw -LiteralPath $changelogPath).Contains(';'))) 'CHANGELOG prose omits semicolons'
Assert-ReleaseCondition (-not $descriptionText.Contains(';')) 'Markdown Workshop description prose omits semicolons'
Assert-ReleaseCondition (-not ((Get-Content -Raw -LiteralPath $steamChangeNotesPath).Contains(';'))) 'Steam change notes omit semicolons'
Assert-ReleaseCondition (-not $githubReleaseNoteText.Contains(';')) 'GitHub release notes omit semicolons'
$workshopDescriptionLines = @($workshopLines | Where-Object { $_.StartsWith('description=', [StringComparison]::Ordinal) })
Assert-ReleaseCondition (@($workshopDescriptionLines -match ';').Count -eq 0) 'Workshop description lines omit semicolons'
Assert-ReleaseCondition (@($readmeLines -ceq '## Status').Count -eq 0) 'README omits Status section'
Assert-ReleaseCondition (@($readmeLines -ceq '## Design goals').Count -eq 0) 'README omits Design goals section'
Assert-ReleaseCondition (-not ($readmeText -match '(?i)\brelease candidate\b|\bawaiting live acceptance\b')) 'README omits release-state checkpoint prose'
foreach ($readmeHeading in @(
    '## How it works',
    '## Advancement modes',
    '## Features and configuration',
    '## Multiplayer administration and saving',
    '## Adding or removing SLA',
    '## Optional level inheritance',
    '## Installation',
    '## Compatibility and limits',
    '## Technical context',
    '## Project links',
    '## AI Use',
    '## License',
    '## Support'
)) {
    Assert-ReleaseCondition (@($readmeLines -ceq $readmeHeading).Count -eq 1) "README durable content backbone includes $readmeHeading"
}
Assert-ReleaseCondition ($readmeText.Contains('Internal mod ID: `SurvivorLevelingAdvancement`')) 'README internal mod ID'
Assert-ReleaseCondition ($readmeText.Contains('Target version: Project Zomboid Build 42.20')) 'README Build 42.20 target'
Assert-ReleaseCondition ($readmeText.Contains('Currently developed and tested on: Project Zomboid 42.20.4')) 'README tested patch'
Assert-ReleaseCondition ($readmeText.Contains('[Subscribe through the Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3792412209)')) 'README supported Workshop installation'
Assert-ReleaseCondition ($readmeText.Contains('[Report a bug or issue](https://github.com/Skeptic043/survivor-leveling-and-advancement/issues/new/choose)')) 'README issue link'
Assert-ReleaseCondition ($readmeText.Contains('[Changelog](CHANGELOG.md)')) 'README changelog link'
Assert-ReleaseCondition (-not ($readmeText -match '\b1\.[12]\.0\b')) 'README omits release-state version numbers'
Assert-ReleaseCondition (@($readmeLines -ceq $howItWorksCopy).Count -eq 1) 'README retains complete How-it-works backbone'
Assert-ReleaseCondition (@($readmeLines -ceq $combinedModeAccountingCopy.Replace('(Fitness/Strength)', 'in Fitness or Strength')).Count -eq 1) 'README retains cohesive advancement-mode accounting backbone'
Assert-ReleaseCondition (@($readmeLines -ceq $addingRemovingCopy).Count -eq 1) 'README retains complete adding-or-removing backbone'
Assert-ReleaseCondition (@($readmeLines -ceq $levelInheritanceCopy).Count -eq 1) 'README retains cohesive optional-inheritance backbone'
foreach ($feature in $featureCopy) {
    Assert-ReleaseCondition (@($readmeLines -ceq "- $feature.").Count -eq 1) "README retains feature: $feature"
}
$prohibitedSaveClaims = @('zero-loss', 'zero loss', 'final-window', 'final window', 'atomic save', 'guaranteed recovery')
$saveBoundaryText = [string]::Join("`n", @($readmeText, $descriptionText, $workshopText))
foreach ($claim in $prohibitedSaveClaims) {
    Assert-ReleaseCondition ($saveBoundaryText.IndexOf($claim, [StringComparison]::OrdinalIgnoreCase) -lt 0) "public save copy omits prohibited claim: $claim"
}

function Get-MarkdownProseParagraphs {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $paragraphs = @()
    $currentLines = @()
    foreach ($line in $Lines) {
        $isBoundary = [string]::IsNullOrWhiteSpace($line) -or
            $line -match '^#{1,6}\s+' -or
            $line -match '^\s*(?:[-*+] |\d+\. )'
        if ($isBoundary) {
            if ($currentLines.Count -gt 0) {
                $paragraphs += [string]::Join(' ', $currentLines)
                $currentLines = @()
            }
        } else {
            $currentLines += $line.Trim()
        }
    }
    if ($currentLines.Count -gt 0) {
        $paragraphs += [string]::Join(' ', $currentLines)
    }

    return @($paragraphs)
}

function Test-MarkdownParagraphStyle {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$AllowedShortParagraphs
    )

    foreach ($paragraph in @(Get-MarkdownProseParagraphs -Lines $Lines)) {
        if (@($AllowedShortParagraphs -ceq $paragraph).Count -gt 0) {
            continue
        }
        if ([regex]::Matches($paragraph, '[.!?](?=\s|$)').Count -lt 3) {
            return $false
        }
    }
    return $true
}

$changelogBlurb = 'All notable public changes will be documented here.'
$steamNotesBlurb = 'Copy the relevant version''s text into Project Zomboid''s Workshop change-note field for every upload. Keep it aligned with `CHANGELOG.md` and the corresponding GitHub Release.'
$steamInitialReleaseBlurb = 'Initial public release of Survivor Leveling & Advancement for Project Zomboid Build 42.20.'
Assert-ReleaseCondition (Test-MarkdownParagraphStyle -Lines $readmeLines -AllowedShortParagraphs @()) 'README has no one- or two-sentence prose paragraphs'
Assert-ReleaseCondition (Test-MarkdownParagraphStyle -Lines $changelogLines -AllowedShortParagraphs @($changelogBlurb)) 'CHANGELOG has no one- or two-sentence prose paragraphs beyond its headline blurb'
Assert-ReleaseCondition (Test-MarkdownParagraphStyle -Lines $steamChangeNoteLines -AllowedShortParagraphs @($steamNotesBlurb, $steamInitialReleaseBlurb)) 'Steam notes have no one- or two-sentence prose paragraphs beyond headline blurbs'
Assert-ReleaseCondition (Test-MarkdownParagraphStyle -Lines $githubReleaseNoteLines -AllowedShortParagraphs @()) 'GitHub release notes have no one- or two-sentence prose paragraphs'

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
    return [Text.Encoding]::UTF8.GetByteCount($payload) -le $MaximumLength
}

$workshopDescriptionLimit = 7800
$workshopDescriptionPayloadLF = Get-WorkshopDescriptionPayload -Lines $workshopLines -Separator "`n"
$workshopDescriptionPayloadCRLF = Get-WorkshopDescriptionPayload -Lines $workshopLines -Separator "`r`n"
$workshopDescriptionPayloadLFBytes = [Text.Encoding]::UTF8.GetByteCount($workshopDescriptionPayloadLF)
$workshopDescriptionPayloadCRLFBytes = [Text.Encoding]::UTF8.GetByteCount($workshopDescriptionPayloadCRLF)
Assert-ReleaseCondition (Test-WorkshopDescriptionWithinLimit -Lines $workshopLines -MaximumLength $workshopDescriptionLimit) "Workshop description conservative CRLF payload exceeds $workshopDescriptionLimit bytes"
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

Write-Host "Workshop description payload bytes: LF=$workshopDescriptionPayloadLFBytes, CRLF=$workshopDescriptionPayloadCRLFBytes, limit=$workshopDescriptionLimit."
Write-Host "Workshop release-source validation passed ($($script:Assertions) assertions)."
