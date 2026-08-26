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
        [pscustomobject]@{ Global = 'C10TBootstrapHarness'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapFirst'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapReload'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCollisionSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapCollision'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapThrowSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapThrow'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformed'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedOwnerSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapMalformedOwner'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapExtraOwnerSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapExtraOwner'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapIndexOwnerSetup'; Path = 'tests/runtime/Build42BootstrapHarness.lua' }
        [pscustomobject]@{ Global = 'C10TBootstrapIndexOwner'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Bootstrap.lua' }
    )
}
