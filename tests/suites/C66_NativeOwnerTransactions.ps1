[pscustomobject]@{
    Label = 'C66 Native Owner Transactions'
    Spec = 'tests/persistence/NativeOwnerTransactionsSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'ServerPlayerRecordStore'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/Persistence/ServerPlayerRecordStore.lua' },
        [pscustomobject]@{ Global = 'StateCodec'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/shared/SurvivorLevelingAdvancement/State/StateCodec.lua' }
    )
}
