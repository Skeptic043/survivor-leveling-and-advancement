$lifecyclePath = Join-Path $PSScriptRoot '..\..\Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\Runtime\Build42Lifecycle.lua'
$lifecycleSource = [System.IO.File]::ReadAllText($lifecyclePath)

$cleanupPattern = '(?ms)^\s*local function startupFailure\(result, code, detail\)\s*\r?\n\s*if mode == "single_player" then\s*\r?\n\s*for slot = 0, 3 do pendingPlayers\[slot\] = nil end\s*\r?\n\s*end\s*\r?\n\s*return retain\(result, code, detail\)\s*\r?\n\s*end\s*$'
if (-not [regex]::IsMatch($lifecycleSource, $cleanupPattern)) {
    throw 'C10-X guard: startupFailure must clear all four pending-player slots before retaining failure'
}

$createPlayerPattern = '(?ms)^\s*callbacks\.OnCreatePlayer = function\(localSlot, player\).*?^\s*elseif started then readySingle\(localSlot, player\)\s*\r?\n\s*elseif not startupAttempted then pendingPlayers\[localSlot\] = player end\s*\r?\n\s*end\s*\r?\n\s*callbacks\.OnServerCommand'
if (-not [regex]::IsMatch($lifecycleSource, $createPlayerPattern)) {
    throw 'C10-X guard: OnCreatePlayer may enqueue only before a startup attempt'
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
