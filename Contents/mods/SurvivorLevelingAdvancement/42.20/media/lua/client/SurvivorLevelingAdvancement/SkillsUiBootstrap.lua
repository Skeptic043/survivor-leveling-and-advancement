require "XpSystem/ISUI/ISCharacterInfo"
require "XpSystem/ISUI/ISSkillProgressBar"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/AdminPanel/ISMiniScoreboardUI"
require "ISUI/ISContextMenu"

local SENTINEL_KEY = "__SLA_Build42SkillsUi_42_20_v1"
local SENTINEL_SIGNATURE = "sla.build42-skills-ui/42.20/v1"

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function exactPlainTable(value, fields)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not fields[key] then return false end
    end
    for key in pairs(fields) do
        if rawget(value, key) == nil then return false end
    end
    return true
end

local function validIntegration(value)
    return exactPlainTable(value, { install = true, status = true })
        and type(rawget(value, "install")) == "function"
        and type(rawget(value, "status")) == "function"
end

local function validSentinel(value)
    return exactPlainTable(value, { signature = true, integration = true })
        and rawget(value, "signature") == SENTINEL_SIGNATURE
        and validIntegration(rawget(value, "integration"))
end

local function install(integration)
    local called, result = pcall(rawget(integration, "install"))
    if not called then return failure("skills_ui_install_threw", "integration.install") end
    if not exactPlainTable(result, { ok = true }) or rawget(result, "ok") ~= true then
        return failure("skills_ui_install_invalid", "integration.install")
    end
    return { ok = true }
end

local existing = rawget(_G, SENTINEL_KEY)
if existing ~= nil then
    if not validSentinel(existing) then
        return failure("skills_ui_sentinel_collision", "existing sentinel is malformed")
    end
    local installed = install(existing.integration)
    if not installed.ok then return installed end
    return existing.integration
end

local lifecycle = require "SurvivorLevelingAdvancement/Bootstrap"
local Build42SkillsUi = require "SurvivorLevelingAdvancement/UI/Build42SkillsUi"
local Build42AdminUi = require "SurvivorLevelingAdvancement/UI/Build42AdminUi"
local SkillsViewModel = require "SurvivorLevelingAdvancement/UI/SkillsViewModel"
local Build42WorldSettingsProvider = require "SurvivorLevelingAdvancement/Adapters/Build42WorldSettingsProvider"
local ClientOwnerState = require "SurvivorLevelingAdvancement/Runtime/ClientOwnerState"
local Allotment = require "SurvivorLevelingAdvancement/Core/Allotment"
local VanillaProgressionAdapter = require "SurvivorLevelingAdvancement/Adapters/VanillaProgressionAdapter"

local adminCalled, adminCreated = pcall(Build42AdminUi.create, {
    owner = lifecycle,
    ISMiniScoreboardUI = ISMiniScoreboardUI,
    ISCollapsableWindowJoypad = ISCollapsableWindowJoypad,
    ISTextEntryBox = ISTextEntryBox,
    ISButton = ISButton,
    canSeePlayersStats = Capability.CanSeePlayersStats,
    getPlayerContextMenu = function(playerNum) return getPlayerContextMenu(playerNum) end,
    isServer = function() return isServer() end,
    isClient = function() return isClient() end,
    isDebugEnabled = function() return isDebugEnabled() end,
    getText = function(key, ...) return getText(key, ...) end,
    viewport = function(playerNum)
        return getPlayerScreenLeft(playerNum), getPlayerScreenTop(playerNum),
            getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    end,
    smallFont = UIFont.Small,
})
if not adminCalled or type(adminCreated) ~= "table" or rawget(adminCreated, "ok") ~= true
    or type(rawget(adminCreated, "integration")) ~= "table" then
    return failure("admin_ui_create_failed", "Build42AdminUi.create")
end

local providerCalled, providerResult = pcall(Build42WorldSettingsProvider.create, {
    readSandboxVars = function() return SandboxVars end,
})
if not providerCalled or type(providerResult) ~= "table" or rawget(providerResult, "ok") ~= true
    or type(rawget(providerResult, "provider")) ~= "table" then
    return failure("settings_provider_create_failed", "Build42WorldSettingsProvider.create")
end

local modelCalled, modelResult = pcall(SkillsViewModel.create, {
    ClientOwnerState = ClientOwnerState,
    Allotment = Allotment,
})
if not modelCalled or type(modelResult) ~= "table" or rawget(modelResult, "ok") ~= true
    or type(rawget(modelResult, "model")) ~= "table" then
    return failure("skills_view_model_create_failed", "SkillsViewModel.create")
end

local createCalled, created = pcall(Build42SkillsUi.create, {
    ISCharacterInfo = ISCharacterInfo,
    ISSkillProgressBar = ISSkillProgressBar,
    ISButton = ISButton,
    owner = lifecycle,
    viewModel = modelResult.model,
    settingsProvider = providerResult.provider,
    progressionAdapter = VanillaProgressionAdapter,
    clockMillis = function() return getTimestampMs() end,
    getText = function(key, ...) return getText(key, ...) end,
    measureText = function(text) return getTextManager():MeasureStringX(UIFont.Small, text) end,
    smallFont = UIFont.Small,
    adminLauncher = adminCreated.integration,
})
if not createCalled or type(created) ~= "table" or rawget(created, "ok") ~= true
    or not validIntegration(rawget(created, "integration")) then
    return failure("skills_ui_create_failed", "Build42SkillsUi.create")
end

local sentinel = { signature = SENTINEL_SIGNATURE, integration = created.integration }
if not validSentinel(sentinel) then return failure("skills_ui_create_failed", "integration surface") end
rawset(_G, SENTINEL_KEY, sentinel)
local installed = install(created.integration)
if not installed.ok then return installed end
return created.integration
