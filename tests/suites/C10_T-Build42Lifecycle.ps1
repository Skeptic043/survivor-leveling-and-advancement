$lifecyclePath = Join-Path $PSScriptRoot '..\..\Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\Runtime\Build42Lifecycle.lua'
$lifecycleSource = [System.IO.File]::ReadAllText($lifecyclePath)

$cleanupPattern = '(?ms)^\s*local function startupFailure\(result, code, detail\)\s*\r?\n\s*if mode == "single_player" then\s*\r?\n\s*for slot = 0, 3 do pendingPlayers\[slot\] = nil end\s*\r?\n\s*end\s*\r?\n\s*return retain\(result, code, detail\)\s*\r?\n\s*end\s*$'
if (-not [regex]::IsMatch($lifecycleSource, $cleanupPattern)) {
    throw 'C10-X guard: startupFailure must clear all four pending-player slots before retaining failure'
}

$createPlayerPattern = '(?ms)^\s*callbacks\.OnCreatePlayer = function\(localSlot, player\)\s*\r?\n\s*if not installed or not ownEvents\(\) or not validSlot\(localSlot\) or player == nil then return end\s*\r?\n\s*if started then readySingle\(localSlot, player\)\s*\r?\n\s*elseif not startupAttempted then pendingPlayers\[localSlot\] = player end\s*\r?\n\s*end\s*\r?\n\s*callbacks\.OnTick = function\(\).*?^\s*end\s*\r?\n\s*callbacks\.OnMiniScoreboardUpdate = function\(\)\s*\r?\n\s*if not installed or not ownEvents\(\) then return end\s*\r?\n\s*inspectLocalPlayers\(\)\s*\r?\n\s*end\s*\r?\n\s*callbacks\.OnServerCommand'
if (-not [regex]::IsMatch($lifecycleSource, $createPlayerPattern)) {
    throw 'C10-X guard: OnCreatePlayer, one-shot tick, and finite post-ack callbacks must retain their exact boundaries'
}

$clientEventsPattern = 'mode == "client" and \{ "OnMiniScoreboardUpdate", "OnTick", "OnServerCommand", "OnDisconnect" \}'
if (-not [regex]::IsMatch($lifecycleSource, $clientEventsPattern)) {
    throw 'C15-F guard: multiplayer must own the exact four-event set in order'
}

$postAckMentions = [regex]::Matches($lifecycleSource, 'OnMiniScoreboardUpdate')
if ($postAckMentions.Count -ne 2) {
    throw 'C15-B guard: post-ack event must have one captured identity and one callback'
}

if ([regex]::IsMatch($lifecycleSource, 'EveryTenMinutes|EveryOneMinute|getOnlinePlayers|scoreboard')) {
    throw 'C15-F guard: readiness must not add polling, online-player enumeration, or scoreboard-row dependencies'
}

$oneShotTickPattern = '(?ms)^\s*callbacks\.OnTick = function\(\)\s*\r?\n\s*if not tickRegistered then return end\s*\r?\n\s*tickRegistered = false\s*\r?\n\s*local called = pcall\(events\.OnTick\.Remove, callbacks\.OnTick\)'
if ((-not [regex]::IsMatch($lifecycleSource, $oneShotTickPattern)) -or ([regex]::Matches($lifecycleSource, 'events\.OnTick\.Add').Count -ne 1) -or ([regex]::Matches($lifecycleSource, 'events\.OnTick\.Remove').Count -ne 2)) {
    throw 'C15-F guard: readiness must own only one removable one-shot tick path'
}

if ([regex]::IsMatch($lifecycleSource, 'getOnlineID')) {
    throw 'C15-D guard: multiplayer readiness must not retain an online-ID dependency'
}

$localScanCalls = [regex]::Matches($lifecycleSource, 'inspectLocalPlayers\(\)')
if ($localScanCalls.Count -ne 2) {
    throw 'C15-D guard: local-player scan must exist only as its definition and post-acceptance call'
}

$pendingWrites = [regex]::Matches($lifecycleSource, 'pendingPlayers\[[^\]\r\n]+\]\s*=')
$clearWrites = [regex]::Matches($lifecycleSource, 'pendingPlayers\[slot\]\s*=\s*nil')
$enqueueWrites = [regex]::Matches($lifecycleSource, 'pendingPlayers\[localSlot\]\s*=\s*player')
if ($pendingWrites.Count -ne 3 -or $clearWrites.Count -ne 2 -or $enqueueWrites.Count -ne 1) {
    throw 'C10-X guard: unexpected pendingPlayers write path'
}

[pscustomobject]@{
    Label = 'C10-T Build42Lifecycle'
    Spec = 'tests/runtime/Build42LifecycleSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'Build42Lifecycle'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/Build42Lifecycle.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapHarnessSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapFirstCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapReloadFalse'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapReloadFalseCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapReloadClient'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapReloadClientCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapSpFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapSpFirstCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapSpReload'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapSpReloadCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCreateFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCreateFirstCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapOwnershipFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapOwnershipFirstCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapBothTrue'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapBothTrueCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapThrowMode'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapThrowModeCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedMode'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedModeCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCollision'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCollisionCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapThrow'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapThrowCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformed'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCandidateFailure'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCandidateFailureCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedOwner'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedOwnerCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapExtraOwner'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapExtraOwnerCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapIndexOwner'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapIndexOwnerCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
    )
}
