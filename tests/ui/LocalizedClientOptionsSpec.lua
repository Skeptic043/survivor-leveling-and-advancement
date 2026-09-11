local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
    if not condition then error(message) end
end
require = function() end
MainOptions = nil
for locale, text in pairs(LocaleText) do
    PZAPI.ModOptions.Data, PZAPI.ModOptions.Dict = {}, {}
    getText = function(key) return text[key] or key end
    local options = ClientOptions.ensure()
    check(options.watch ~= nil and options.highContrast ~= nil, locale .. " registers both options")
    local group = PZAPI.ModOptions:getOptions("SurvivorLevelingAdvancement")
    -- MainOptions resolves these stored keys when constructing the Mods panel.
    local watch = group:getOption("ShowWatchProgress")
    local contrast = group:getOption("HighContrastMarkers")
    check(getText(watch.name) == text.IGUI_SLA_WatchOption, locale .. " localized watch label")
    check(getText(watch.tooltip) == text.IGUI_SLA_WatchOption_Tooltip, locale .. " localized watch tooltip")
    check(getText(contrast.name) == text.IGUI_SLA_HighContrastOption, locale .. " localized contrast label")
    check(getText(contrast.tooltip) == text.IGUI_SLA_HighContrastOption_Tooltip, locale .. " localized contrast tooltip")
    check(getText(group.name) == "Survivor Leveling & Advancement", locale .. " retains brand")
    if locale ~= "EN" then
        check(getText(watch.name) ~= LocaleText.EN.IGUI_SLA_WatchOption, locale .. " is visibly localized")
    end
end
return assertions
