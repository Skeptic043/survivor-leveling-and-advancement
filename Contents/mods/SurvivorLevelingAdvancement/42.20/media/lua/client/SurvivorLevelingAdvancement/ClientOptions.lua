local ClientOptions = {}

function ClientOptions.ensure()
    require "PZAPI/ModOptions"
    require "OptionScreens/MainOptions"
    if type(PZAPI) ~= "table" or type(PZAPI.ModOptions) ~= "table" then return {} end
    local api = PZAPI.ModOptions
    local options = api:getOptions("SurvivorLevelingAdvancement")
    if options == nil then
        options = api:create("SurvivorLevelingAdvancement", "IGUI_SLA_ModOptions_Title")
    end
    local function checkbox(id, name, tooltip)
        local called, option = pcall(function()
            return options:getOption(id) or options:addTickBox(id, name, false, tooltip)
        end)
        if called and type(option) == "table" and type(option.getValue) == "function" then
            return option
        end
        return nil
    end
    local result = {}
    result.watch = checkbox("ShowWatchProgress", "IGUI_SLA_WatchOption", "IGUI_SLA_WatchOption_Tooltip")
    result.highContrast = checkbox("HighContrastMarkers", "IGUI_SLA_HighContrastOption",
        "IGUI_SLA_HighContrastOption_Tooltip")
    local instance = type(MainOptions) == "table" and rawget(MainOptions, "instance") or nil
    if type(instance) == "table" then
        local tabs = rawget(instance, "tabs")
        if type(tabs) == "table" and type(tabs.getView) == "function"
            and type(instance.addModOptionsPanel) == "function" then
            local viewed, page = pcall(tabs.getView, tabs, getText("UI_mainscreen_mods"))
            if viewed and page == nil then pcall(instance.addModOptionsPanel, instance) end
        end
    end
    return result
end

return ClientOptions
