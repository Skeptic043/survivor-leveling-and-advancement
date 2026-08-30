$sourcePath = Join-Path $PSScriptRoot '..\..\Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\Persistence\ServerPlayerRecordStore.lua'
$source = [IO.File]::ReadAllText($sourcePath)
if ([regex]::IsMatch($source, '(?i)\btransmit\b|OnReceiveGlobalModData')) {
    throw 'C43 guard: canonical server records must not transmit or accept a client Global ModData writer'
}
$transportRoot = Join-Path $PSScriptRoot '..\..\Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\Runtime'
foreach ($name in @('Build42OwnerTransport.lua', 'Build42AdvancementTransport.lua', 'Build42AdminTransport.lua')) {
    $transport = [IO.File]::ReadAllText((Join-Path $transportRoot $name))
    if ($transport.Contains('SLA_ServerPlayers_v1')) {
        throw "C43 guard: $name must not expose the canonical Global record root"
    }
}

[pscustomobject]@{
    Label = 'C43 ServerPlayerRecordStore'
    Spec = 'tests/persistence/ServerPlayerRecordStoreSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'ServerPlayerRecordStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/ServerPlayerRecordStore.lua' },
        [pscustomobject]@{ Global = 'PlayerStateStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/PlayerStateStore.lua' },
        [pscustomobject]@{ Global = 'CharacterInheritanceStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/CharacterInheritanceStore.lua' },
        [pscustomobject]@{ Global = 'InheritanceRecordStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/InheritanceRecordStore.lua' },
        [pscustomobject]@{ Global = 'InheritanceSession'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/InheritanceSession.lua' },
        [pscustomobject]@{ Global = 'AdminSession'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Runtime/AdminSession.lua' },
        [pscustomobject]@{ Global = 'StateCodec'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/StateCodec.lua' },
        [pscustomobject]@{ Global = 'InheritancePolicy'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/InheritancePolicy.lua' },
        [pscustomobject]@{ Global = 'SurvivorEconomy'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Core/SurvivorEconomy.lua' }
    )
}
