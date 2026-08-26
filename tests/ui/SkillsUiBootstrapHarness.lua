local key = "__SLA_Build42SkillsUi_42_20_v1"
local signature = "sla.build42-skills-ui/42.20/v1"
local evidence = rawget(_G, "__C11C_BOOTSTRAP_EVIDENCE")

local function check(condition, message)
    if not condition then error(message, 2) end
    evidence.checks = evidence.checks + 1
end

if evidence == nil then
    evidence = { checks = 0, requires = {}, creates = 0, installs = 0, phase = 1 }
    rawset(_G, "__C11C_BOOTSTRAP_EVIDENCE", evidence)
    evidence.characterInfo = {}
    evidence.progressBar = {}
    evidence.button = {}
    evidence.smallFont = {}
    evidence.sandboxVars = { SurvivorLevelingAdvancement = {} }
    evidence.owner = {
        install = function() return { ok = true } end,
        status = function() return { ok = true } end,
        clientState = function() return { ok = true, present = false } end,
        refreshOwner = function() return { ok = false, code = "refresh_pending", detail = "pending" } end,
        setClientStateListener = function() return { ok = true } end,
        requestAdvancement = function() return { ok = false, code = "blocked", detail = "blocked" } end,
        advancementStatus = function() return { ok = true, pending = false } end,
    }
    evidence.clientOwnerState = {}
    evidence.allotment = {}
    evidence.progression = {}
    evidence.model = { build = function() return { ok = false } end }
    evidence.provider = { read = function() return nil end }
    evidence.integration = {
        install = function() evidence.installs = evidence.installs + 1; return { ok = true } end,
        status = function() return { ok = true, installed = true } end,
    }
    evidence.skillsUi = {
        create = function(dependencies)
            evidence.creates = evidence.creates + 1
            evidence.dependencies = dependencies
            return { ok = true, integration = evidence.integration }
        end,
    }
    evidence.skillsViewModel = {
        create = function(dependencies)
            evidence.modelDependencies = dependencies
            return { ok = true, model = evidence.model }
        end,
    }
    evidence.settingsFactory = {
        create = function(dependencies)
            evidence.providerDependencies = dependencies
            return { ok = true, provider = evidence.provider }
        end,
    }
    require = function(path)
        evidence.requires[path] = (evidence.requires[path] or 0) + 1
        if path == "SurvivorLevelingAdvancement/Bootstrap" then return evidence.owner end
        if path == "SurvivorLevelingAdvancement/UI/Build42SkillsUi" then return evidence.skillsUi end
        if path == "SurvivorLevelingAdvancement/UI/SkillsViewModel" then return evidence.skillsViewModel end
        if path == "SurvivorLevelingAdvancement/Adapters/Build42WorldSettingsProvider" then return evidence.settingsFactory end
        if path == "SurvivorLevelingAdvancement/Runtime/ClientOwnerState" then return evidence.clientOwnerState end
        if path == "SurvivorLevelingAdvancement/Core/Allotment" then return evidence.allotment end
        if path == "SurvivorLevelingAdvancement/Adapters/VanillaProgressionAdapter" then return evidence.progression end
        return true
    end
    ISCharacterInfo = evidence.characterInfo
    ISSkillProgressBar = evidence.progressBar
    ISButton = evidence.button
    UIFont = { Small = evidence.smallFont }
    SandboxVars = evidence.sandboxVars
    getTimestampMs = function() return 4321 end
    getText = function(name) return name end
    getTextManager = function()
        return { MeasureStringX = function(_, _, text) return #text end }
    end
    rawset(_G, key, nil)
elseif evidence.phase == 1 then
    check(evidence.creates == 1 and evidence.installs == 1, "first load creates and installs once")
    check(rawget(_G, key).signature == signature
        and rawget(_G, key).integration == evidence.integration, "exact sentinel payload")
    check(evidence.dependencies.ISCharacterInfo == evidence.characterInfo
        and evidence.dependencies.ISSkillProgressBar == evidence.progressBar
        and evidence.dependencies.ISButton == evidence.button, "exact vanilla classes")
    check(evidence.dependencies.owner == evidence.owner
        and evidence.dependencies.viewModel == evidence.model
        and evidence.dependencies.settingsProvider == evidence.provider
        and evidence.dependencies.progressionAdapter == evidence.progression, "exact service identities")
    check(evidence.dependencies.smallFont == evidence.smallFont
        and evidence.dependencies.clockMillis() == 4321
        and evidence.dependencies.getText("copy") == "copy"
        and evidence.dependencies.measureText("abcd") == 4, "exact UI capabilities")
    check(evidence.modelDependencies.ClientOwnerState == evidence.clientOwnerState
        and evidence.modelDependencies.Allotment == evidence.allotment, "view-model dependencies")
    check(evidence.providerDependencies.readSandboxVars() == evidence.sandboxVars,
        "settings provider reads the live global cell")
    check(rawget(evidence.dependencies, "Events") == nil
        and rawget(evidence.dependencies, "players") == nil, "no event or player surface")
    evidence.phase = 2
elseif evidence.phase == 2 then
    check(evidence.creates == 1 and evidence.installs == 2, "reload reuses integration")
    local modulePaths = {
        "SurvivorLevelingAdvancement/Bootstrap",
        "SurvivorLevelingAdvancement/UI/Build42SkillsUi",
        "SurvivorLevelingAdvancement/UI/SkillsViewModel",
        "SurvivorLevelingAdvancement/Adapters/Build42WorldSettingsProvider",
        "SurvivorLevelingAdvancement/Runtime/ClientOwnerState",
        "SurvivorLevelingAdvancement/Core/Allotment",
        "SurvivorLevelingAdvancement/Adapters/VanillaProgressionAdapter",
    }
    for index = 1, #modulePaths do
        check(evidence.requires[modulePaths[index]] == 1, "module required once " .. index)
    end
    rawset(_G, key, { signature = signature, integration = { install = function() return { ok = true } end } })
    evidence.phase = 3
elseif evidence.phase == 3 then
    check(rawget(_G, "C11CBootstrapCollision").code == "skills_ui_sentinel_collision",
        "malformed sentinel collision")
    rawset(_G, key, { signature = signature, integration = {
        install = function() error("install boom") end,
        status = function() return { ok = true } end,
    } })
    evidence.phase = 4
elseif evidence.phase == 4 then
    check(rawget(_G, "C11CBootstrapThrow").code == "skills_ui_install_threw",
        "reload install throw is bounded")
    rawset(_G, key, nil)
    evidence.skillsUi.create = function() error("create boom") end
    evidence.phase = 5
elseif evidence.phase == 5 then
    check(rawget(_G, "C11CBootstrapCreateThrow").code == "skills_ui_create_failed",
        "adapter create throw is bounded")
end

return evidence.checks
