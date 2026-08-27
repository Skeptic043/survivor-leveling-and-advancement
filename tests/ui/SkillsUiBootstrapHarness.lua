local key = "__SLA_Build42SkillsUi_42_20_v1"
local signature = "sla.build42-skills-ui/42.20/v1"
local evidence = rawget(_G, "__C11C_BOOTSTRAP_EVIDENCE")

local function check(condition, message)
    if not condition then error(message, 2) end
    evidence.checks = evidence.checks + 1
end

if evidence == nil then
    evidence = { checks = 0, requires = {}, creates = 0, installs = 0, adminCreates = 0, phase = 1 }
    rawset(_G, "__C11C_BOOTSTRAP_EVIDENCE", evidence)
    evidence.characterInfo = {}
    evidence.progressBar = {}
    evidence.button = {}
    evidence.entry = {}
    evidence.window = {}
    evidence.scoreboard = {}
    evidence.capability = { CanSeePlayersStats = {} }
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
        requestAdmin = function() return { ok = false, code = "unavailable", detail = "unavailable" } end,
        adminStatus = function() return { ok = true, pending = false } end,
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
    evidence.adminIntegration = {
        install = function() return { ok = true } end,
        status = function() return { ok = true, installed = true } end,
        isAvailable = function() return false end,
        open = function() return { ok = false, code = "unavailable", detail = "unavailable" } end,
    }
    evidence.adminUi = {
        create = function(dependencies)
            evidence.adminCreates = evidence.adminCreates + 1
            evidence.adminDependencies = dependencies
            return { ok = true, integration = evidence.adminIntegration }
        end,
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
        if path == "SurvivorLevelingAdvancement/UI/Build42AdminUi" then return evidence.adminUi end
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
    ISTextEntryBox = evidence.entry
    ISCollapsableWindowJoypad = evidence.window
    ISMiniScoreboardUI = evidence.scoreboard
    Capability = evidence.capability
    UIFont = { Small = evidence.smallFont }
    SandboxVars = evidence.sandboxVars
    getTimestampMs = function() return 4321 end
    getPlayerContextMenu = function(slot) return { slot = slot } end
    isServer = function() return false end
    isClient = function() return false end
    isDebugEnabled = function() return true end
    getPlayerScreenLeft = function(slot) evidence.viewportSlot = slot; return 100 end
    getPlayerScreenTop = function(slot) evidence.viewportSlot = slot; return 50 end
    getPlayerScreenWidth = function(slot) evidence.viewportSlot = slot; return 800 end
    getPlayerScreenHeight = function(slot) evidence.viewportSlot = slot; return 500 end
    getText = function(name) return name end
    getTextManager = function()
        return { MeasureStringX = function(_, _, text) return #text end }
    end
    rawset(_G, key, nil)
elseif evidence.phase == 1 then
    check(evidence.creates == 1 and evidence.adminCreates == 1
        and evidence.installs == 1, "first load creates both integrations and installs composite once")
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
    check(evidence.dependencies.adminLauncher == evidence.adminIntegration,
        "Skills integration receives exact admin launcher")
    check(evidence.adminDependencies.owner == evidence.owner
        and evidence.adminDependencies.ISMiniScoreboardUI == evidence.scoreboard
        and evidence.adminDependencies.ISCollapsableWindowJoypad == evidence.window
        and evidence.adminDependencies.ISTextEntryBox == evidence.entry
        and evidence.adminDependencies.ISButton == evidence.button,
        "admin adapter receives exact owner and UI classes")
    check(evidence.adminDependencies.canSeePlayersStats == evidence.capability.CanSeePlayersStats
        and evidence.adminDependencies.getPlayerContextMenu(2).slot == 2
        and evidence.adminDependencies.isServer() == false
        and evidence.adminDependencies.isClient() == false
        and evidence.adminDependencies.isDebugEnabled() == true,
        "admin adapter receives exact global capabilities")
    local viewportLeft, viewportTop, viewportWidth, viewportHeight = evidence.adminDependencies.viewport(2)
    check(viewportLeft == 100 and viewportTop == 50
        and viewportWidth == 800 and viewportHeight == 500 and evidence.viewportSlot == 2,
        "admin adapter receives exact slot-local viewport capability")
    check(evidence.modelDependencies.ClientOwnerState == evidence.clientOwnerState
        and evidence.modelDependencies.Allotment == evidence.allotment, "view-model dependencies")
    check(evidence.providerDependencies.readSandboxVars() == evidence.sandboxVars,
        "settings provider reads the live global cell")
    check(rawget(evidence.dependencies, "Events") == nil
        and rawget(evidence.dependencies, "players") == nil, "no event or player surface")
    evidence.phase = 2
elseif evidence.phase == 2 then
    check(evidence.creates == 1 and evidence.adminCreates == 1
        and evidence.installs == 2, "reload reuses composite integration")
    local modulePaths = {
        "SurvivorLevelingAdvancement/Bootstrap",
        "SurvivorLevelingAdvancement/UI/Build42SkillsUi",
        "SurvivorLevelingAdvancement/UI/Build42AdminUi",
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
