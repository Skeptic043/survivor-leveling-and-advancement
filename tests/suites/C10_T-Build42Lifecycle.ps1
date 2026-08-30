$lifecyclePath = Join-Path $PSScriptRoot '..\..\Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\Runtime\Build42Lifecycle.lua'
$lifecycleSource = [System.IO.File]::ReadAllText($lifecyclePath)
$bootstrapPath = Join-Path $PSScriptRoot '..\..\Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\Bootstrap.lua'
$bootstrapSource = [System.IO.File]::ReadAllText($bootstrapPath)

$clearPendingDefinition = '(?ms)^\s*local function clearPendingNewPlayers\(\)\s*\r?\n\s*for index = 1, #pendingNewPlayers do pendingNewPlayers\[index\] = nil end\s*\r?\n\s*pendingNewPlayers = \{\}\s*\r?\n\s*end\s*$'
if (-not [regex]::IsMatch($bootstrapSource, $clearPendingDefinition)) {
    throw 'C18-D2 guard: Bootstrap must nil every pending-new reference and replace the private table'
}
if ([regex]::Matches($bootstrapSource, 'clearPendingNewPlayers\(\)').Count -ne 7) {
    throw 'C18-D2 guard: Bootstrap pending-new clear definition/call count changed'
}
$clearPendingLocalDefinition = '(?ms)^\s*local function clearPendingLocalPlayers\(\)\s*\r?\n\s*for slot = 0, 3 do pendingLocalPlayers\[slot\] = nil end\s*\r?\n\s*pendingLocalPlayers = \{\}\s*\r?\n\s*end\s*$'
if (-not [regex]::IsMatch($bootstrapSource, $clearPendingLocalDefinition)) {
    throw 'C18-H guard: Bootstrap must nil every pending-local reference and replace the private table'
}
if ([regex]::Matches($bootstrapSource, 'clearPendingLocalPlayers\(\)').Count -ne 7) {
    throw 'C18-H guard: Bootstrap pending-local clear definition/call count changed'
}
$terminalClearPatterns = @(
    '(?ms)local function loseResolverOwnership\(detail\)\s*\r?\n\s*clearPendingNewPlayers\(\)\s*\r?\n\s*clearPendingLocalPlayers\(\)',
    '(?ms)for slot = 0, 3 do localPlayers\[slot\] = pendingLocalPlayers\[slot\] end\s*\r?\n\s*end\s*\r?\n\s*local clientStateListener = deferredClientStateListener\s*\r?\n\s*clearPendingNewPlayers\(\)\s*\r?\n\s*clearPendingLocalPlayers\(\)\s*\r?\n\s*clearDeferredClientStateListener\(\)\s*\r?\n\s*local called, created = pcall\(createLifecycle,',
    '(?ms)if mode == nil then\s*\r?\n\s*resolutionAttempted = true\s*\r?\n\s*clearPendingNewPlayers\(\)\s*\r?\n\s*clearPendingLocalPlayers\(\)\s*\r?\n\s*clearDeferredClientStateListener\(\)\s*\r?\n\s*return\s*\r?\n\s*end',
    '(?ms)else\s*\r?\n\s*resolutionAttempted = true\s*\r?\n\s*clearPendingNewPlayers\(\)\s*\r?\n\s*clearPendingLocalPlayers\(\)\s*\r?\n\s*clearDeferredClientStateListener\(\)\s*\r?\n\s*retain\("mode_invalid", "OnGameStart cannot resolve server mode"\)',
    '(?ms)if resolverInstallAttempted and not resolverInstalled then\s*\r?\n\s*resolutionAttempted = true\s*\r?\n\s*clearPendingNewPlayers\(\)\s*\r?\n\s*clearPendingLocalPlayers\(\)',
    '(?ms)local mode = checkMode\(\)\s*\r?\n\s*if mode == nil then\s*\r?\n\s*resolutionAttempted = true\s*\r?\n\s*clearPendingNewPlayers\(\)\s*\r?\n\s*clearPendingLocalPlayers\(\)\s*\r?\n\s*clearDeferredClientStateListener\(\)'
)
foreach ($terminalClearPattern in $terminalClearPatterns) {
    if (-not [regex]::IsMatch($bootstrapSource, $terminalClearPattern)) {
        throw 'C18-D2 guard: Bootstrap terminal pending-new clear path changed'
    }
}

$listenerHandoffPattern = '(?ms)local clientStateListener = deferredClientStateListener\s*\r?\n\s*clearPendingNewPlayers\(\)\s*\r?\n\s*clearPendingLocalPlayers\(\)\s*\r?\n\s*clearDeferredClientStateListener\(\).*?pcall\(\s*\r?\n\s*rawget\(candidateOwner, "setClientStateListener"\),\s*\r?\n\s*clientStateListener\s*\r?\n\s*\)'
if (-not [regex]::IsMatch($bootstrapSource, $listenerHandoffPattern)) {
    throw 'C18-F correction guard: unresolved listener must be cleared locally and handed to the concrete owner once'
}

$playerCapturePattern = '(?ms)callbacks\.OnCreatePlayer = function\(localSlot, player\)\s*\r?\n\s*if resolverInstalled and not resolutionAttempted.*?pendingLocalPlayers\[localSlot\] = player\s*\r?\n\s*end\s*\r?\n\s*resolveFrom\("OnCreatePlayer"\)'
$playerHandoffPattern = '(?ms)pendingLocalPlayers = localPlayers,\s*\r?\n\s*\}\).*?if localPlayers ~= nil then\s*\r?\n\s*for slot = 0, 3 do localPlayers\[slot\] = nil end'
$hasPlayerCapture = [regex]::IsMatch($bootstrapSource, $playerCapturePattern)
$hasPlayerHandoff = [regex]::IsMatch($bootstrapSource, $playerHandoffPattern)
if (-not $hasPlayerCapture -or -not $hasPlayerHandoff) {
    throw 'C18-H guard: unresolved exact local players must be handed to SP lifecycle and cleared'
}

$cleanupDefinition = '(?ms)^\s*local function clearPendingPlayerReferences\(\)\s*\r?\n\s*for index = 1, #pendingNewPlayers do pendingNewPlayers\[index\] = nil end\s*\r?\n\s*pendingNewPlayers = \{\}\s*\r?\n\s*for slot = 0, 3 do pendingPlayers\[slot\] = nil end\s*\r?\n\s*pendingReferencesClosed = true\s*\r?\n\s*end\s*$'
$cleanupPattern = '(?ms)^\s*local function startupFailure\(result, code, detail\)\s*\r?\n\s*clearPendingPlayerReferences\(\)\s*\r?\n\s*return retain\(result, code, detail\)\s*\r?\n\s*end\s*$'
$installCleanupPattern = '(?ms)if name ~= "OnTick" and not pcall\(rawget\(events\[name\], "Add"\), callbacks\[name\]\) then\s*\r?\n\s*clearPendingPlayerReferences\(\)\s*\r?\n\s*return retain\(nil, "event_register_threw", name\)'
$hasCleanupDefinition = [regex]::IsMatch($lifecycleSource, $cleanupDefinition)
$hasCleanupPattern = [regex]::IsMatch($lifecycleSource, $cleanupPattern)
$hasInstallCleanup = [regex]::IsMatch($lifecycleSource, $installCleanupPattern)
$cleanupCallCount = [regex]::Matches($lifecycleSource, 'clearPendingPlayerReferences\(\)').Count
if (-not $hasCleanupDefinition -or -not $hasCleanupPattern -or -not $hasInstallCleanup -or $cleanupCallCount -ne 5) {
    throw 'C18-Q guard: terminal install, startup, and ownership-loss paths must clear both pending-player collections'
}

$createPlayerPattern = '(?ms)^\s*callbacks\.OnCreatePlayer = function\(localSlot, player\)\s*\r?\n\s*if not installed or not ownEvents\(\) or not validSlot\(localSlot\) or player == nil then return end\s*\r?\n\s*if started then readySingle\(localSlot, player\)\s*\r?\n\s*elseif not startupAttempted and not pendingReferencesClosed then pendingPlayers\[localSlot\] = player end\s*\r?\n\s*end\s*\r?\n\s*callbacks\.OnNewGame = function\(player\).*?^\s*end\s*\r?\n\s*callbacks\.OnCharacterDeath = function\(player\).*?^\s*end\s*\r?\n\s*callbacks\.OnTick = function\(\).*?^\s*end\s*\r?\n\s*callbacks\.OnMiniScoreboardUpdate = function\(\)\s*\r?\n\s*if not installed or not ownEvents\(\) then return end\s*\r?\n\s*inspectLocalPlayers\(\)\s*\r?\n\s*end\s*\r?\n\s*callbacks\.OnServerCommand'
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

if ([regex]::IsMatch($lifecycleSource, 'EveryTenMinutes|EveryOneMinute|scoreboard')) {
    throw 'C15-F guard: readiness must not add polling or scoreboard-row dependencies'
}
if ([regex]::Matches($lifecycleSource, 'getOnlinePlayers').Count -ne 4) {
    throw 'C43 guard: online-player enumeration must exist only as the captured admin-boundary dependency'
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
        [pscustomobject]@{ Global = 'C18D2BootstrapPartialGameStart'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C18D2BootstrapPartialGameStartCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C18D2BootstrapPartialCreatePlayer'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C18D2BootstrapPartialCreatePlayerCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C18D2BootstrapPartialNewGame'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C18D2BootstrapPartialNewGameCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C18D2BootstrapFinalCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C18D2BootstrapBufferedModeFailure'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C18D2BootstrapBufferedModeFailureCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C18D2BootstrapCorrectedFinalCheck'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
    )
}
