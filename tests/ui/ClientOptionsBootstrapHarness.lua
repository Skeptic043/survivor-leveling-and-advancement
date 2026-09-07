local evidence = rawget(_G, "__C58_OPTIONS_HARNESS")
local function check(value, message)
    if not value then error(message, 2) end
    evidence.checks = evidence.checks + 1
end

if evidence == nil then
    evidence = { checks = 0, phase = 0 }
    rawset(_G, "__C58_OPTIONS_HARNESS", evidence)
    evidence.reset = function(storedWatch, contrastFailure)
        rawset(_G, "__SLA_Build42SkillsUi_42_20_v2", nil)
        rawset(_G, "__SLA_Build42WatchUi_42_20_v4", nil)
        evidence.creates, evidence.adds, evidence.pages = 0, {}, 0
        evidence.contrastFailure = contrastFailure
        evidence.optionReads = 0
        local function option(value)
            return { value = value, getValue = function(self)
                evidence.optionReads = evidence.optionReads + 1
                return self.value
            end }
        end
        evidence.options = { values = {} }
        if storedWatch then evidence.options.values.ShowWatchProgress = option(true) end
        function evidence.options:getOption(id)
            if id == "HighContrastMarkers" and evidence.contrastFailure then error("contrast unavailable") end
            return self.values[id]
        end
        function evidence.options:addTickBox(id, name, value, tooltip)
            check(self.values[id] == nil, "native option identity is registered only once")
            check(value == false, "new client checkboxes default off")
            check(string.find(name, "IGUI_SLA_", 1, true) == 1
                and string.find(tooltip, "IGUI_SLA_", 1, true) == 1, "option copy uses translation keys")
            evidence.adds[#evidence.adds + 1] = id
            self.values[id] = option(value)
            return self.values[id]
        end
        evidence.existingGroup = storedWatch and evidence.options or nil
        PZAPI = { ModOptions = {
            getOptions = function(_, id)
                check(id == "SurvivorLevelingAdvancement", "existing option group identity is preserved")
                return evidence.existingGroup
            end,
            create = function(_, id)
                evidence.creates = evidence.creates + 1
                evidence.existingGroup = evidence.options
                return evidence.options
            end,
        } }
        local page
        MainOptions = { instance = {
            tabs = { getView = function() return page end },
            addModOptionsPanel = function() evidence.pages = evidence.pages + 1; page = {} end,
        } }
    end
    local integration = { install = function() return { ok = true } end,
        status = function() return { ok = true, installed = true } end }
    evidence.integration = integration
    local function module(name)
        return { create = function(dependencies)
            evidence[name] = dependencies
            return { ok = true, integration = integration, model = {}, provider = {} }
        end }
    end
    local modules = {
        ["SurvivorLevelingAdvancement/UI/Build42SkillsUi"] = module("skills"),
        ["SurvivorLevelingAdvancement/UI/Build42WatchUi"] = module("watch"),
        ["SurvivorLevelingAdvancement/UI/Build42AdminUi"] = module("admin"),
        ["SurvivorLevelingAdvancement/UI/SkillsViewModel"] = module("model"),
        ["SurvivorLevelingAdvancement/Adapters/Build42WorldSettingsProvider"] = module("provider"),
    }
    require = function(path)
        if path == "SurvivorLevelingAdvancement/ClientOptions" then return ClientOptions end
        return modules[path] or {}
    end
    ISCharacterInfo, ISSkillProgressBar, ISButton, ISPanel, ISToolTip = {}, {}, {}, {}, {}
    ISMiniScoreboardUI, ISUsersList, ISCollapsableWindowJoypad, ISTextEntryBox = {}, {}, {}, {}
    Capability = { CanSeePlayersStats = {} }
    UIFont, Joypad = { Small = {} }, { AButton = {} }
    getText = function(key) return key end
    getTextManager = function() return { getFontHeight = function() return 12 end } end
    evidence.reset(true, false)
elseif evidence.phase == 1 then
    check(C58SkillsFirst == evidence.integration, "Skills first loads with shared options")
    check(evidence.skills.highContrastEnabled() == false, "Skills receives default-off contrast option")
    check(evidence.skills.ISToolTip == ISToolTip and evidence.skills.fontHeight() == 12,
        "native tooltip and current font height are injected")
    evidence.watchIdentity = evidence.options.values.ShowWatchProgress
elseif evidence.phase == 2 then
    check(C58WatchSecond == evidence.integration, "Watch loads after Skills")
    check(evidence.watch.optionEnabled() == true, "Skills-first order preserves stored watch true")
    check(evidence.options.values.ShowWatchProgress == evidence.watchIdentity,
        "Watch reuses existing option object")
    check(evidence.creates == 0 and #evidence.adds == 1 and evidence.pages == 1,
        "Skills-first order adds only missing checkbox and one Mods page")
    evidence.reset(true, false)
elseif evidence.phase == 3 then
    check(C58WatchFirst == evidence.integration, "Watch-first order loads")
    check(evidence.watch.optionEnabled() == true, "Watch-first keeps stored true")
    evidence.watchIdentity = evidence.options.values.ShowWatchProgress
elseif evidence.phase == 4 then
    check(C58SkillsSecond == evidence.integration, "Skills loads after Watch")
    check(evidence.options.values.ShowWatchProgress == evidence.watchIdentity,
        "Skills leaves watch option identity untouched")
    check(evidence.creates == 0 and #evidence.adds == 1 and evidence.pages == 1,
        "Watch-first order adds only missing checkbox and one Mods page")
    evidence.options.values.HighContrastMarkers.value = true
    check(evidence.skills.highContrastEnabled() == true, "applied option changes are visible without restart")
    check(evidence.watch.optionEnabled() == true, "contrast change preserves watch setting")
    ClientOptions.ensure()
    check(#evidence.adds == 1 and evidence.pages == 1, "repeated registration is idempotent")
    evidence.reset(true, true)
elseif evidence.phase == 5 then
    check(C58SkillsContrastFailure == evidence.integration, "contrast registration failure leaves Skills available")
    check(evidence.skills.highContrastEnabled() == false, "contrast registration failure defaults off")
elseif evidence.phase == 6 then
    check(C58WatchContrastFailure == evidence.integration and evidence.watch.optionEnabled() == true,
        "contrast registration failure leaves stored watch working")
    evidence.reset(true, false)
    PZAPI.ModOptions.getOptions = function() error("optional settings unavailable") end
elseif evidence.phase == 7 then
    check(C58SkillsOptionsFailure == evidence.integration, "whole option API failure leaves Skills available")
    check(evidence.skills.highContrastEnabled() == false, "whole option API failure defaults off")
    evidence.reset(false, false)
    local options = ClientOptions.ensure()
    check(options.watch:getValue() == false and options.highContrast:getValue() == false,
        "new client receives both defaults off")
    check(evidence.creates == 1 and evidence.pages == 1 and #evidence.adds == 2,
        "new client creates one group and two options")
    check(evidence.adds[1] == "ShowWatchProgress" and evidence.adds[2] == "HighContrastMarkers",
        "contrast is adjacent to watch in deterministic order")
    ClientOptions.ensure()
    check(evidence.creates == 1 and evidence.pages == 1 and #evidence.adds == 2,
        "fresh registration repeats without duplication")
end
evidence.phase = evidence.phase + 1
return evidence.checks
