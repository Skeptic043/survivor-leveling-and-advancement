[pscustomobject]@{
    Label = 'C86 Localized Client Options'
    Spec = 'tests/ui/LocalizedClientOptionsSpec.lua'
    Sources = @(
        [pscustomobject]@{ Global = 'LocaleText'; Path = 'tests/.build/locale-ui-fixture.lua' }
        [pscustomobject]@{ Global = 'VanillaModOptions'; Path = 'tests/.build/vanilla-mod-options.lua' }
        [pscustomobject]@{ Global = 'ClientOptions'; Path = 'Contents/mods/SurvivorLevelingAdvancement/42.20/media/lua/client/SurvivorLevelingAdvancement/ClientOptions.lua' }
    )
}
