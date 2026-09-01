require "PZAPI/ModOptions"
require "OptionScreens/MainOptions"
require "ISUI/ISUIElement"

local SENTINEL_KEY = "__SLA_Build42WatchUi_42_20_v4"
local SENTINEL_SIGNATURE = "sla.build42-watch-ui/42.20/v4"
local OPTION_GROUP = "SurvivorLevelingAdvancement"
local OPTION_ID = "ShowWatchProgress"

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function validIntegration(value)
    return type(value) == "table" and type(rawget(value, "install")) == "function"
        and type(rawget(value, "status")) == "function"
end

local function install(integration)
    local called, result = pcall(rawget(integration, "install"))
    if not called or type(result) ~= "table" or rawget(result, "ok") ~= true then
        return failure("watch_ui_install_failed", "integration.install")
    end
    return { ok = true }
end

local existing = rawget(_G, SENTINEL_KEY)
if existing ~= nil then
    if type(existing) ~= "table" or rawget(existing, "signature") ~= SENTINEL_SIGNATURE
        or not validIntegration(rawget(existing, "integration")) then
        return failure("watch_ui_sentinel_collision", "existing sentinel")
    end
    local installed = install(existing.integration)
    if not installed.ok then return installed end
    return existing.integration
end

if type(PZAPI) ~= "table" or type(PZAPI.ModOptions) ~= "table"
    or type(PZAPI.ModOptions.getOptions) ~= "function" then
    return failure("watch_option_failed", "ModOptions.getOptions")
end
local optionsCalled, options = pcall(PZAPI.ModOptions.getOptions, PZAPI.ModOptions, OPTION_GROUP)
if not optionsCalled then return failure("watch_option_failed", "ModOptions.getOptions") end
if options == nil then
    if type(PZAPI.ModOptions.create) ~= "function" then
        return failure("watch_option_failed", "ModOptions.create")
    end
    local createCalled
    createCalled, options = pcall(PZAPI.ModOptions.create, PZAPI.ModOptions, OPTION_GROUP, "IGUI_SLA_ModOptions_Title")
    if not createCalled then return failure("watch_option_failed", "ModOptions.create") end
end
if type(options) ~= "table" or type(options.getOption) ~= "function"
    or type(options.addTickBox) ~= "function" then
    return failure("watch_option_failed", "options")
end
local getCalled, option = pcall(options.getOption, options, OPTION_ID)
if not getCalled then return failure("watch_option_failed", "options.getOption") end
if option == nil then
    local addCalled
    addCalled, option = pcall(options.addTickBox, options, OPTION_ID,
        "IGUI_SLA_WatchOption", false, "IGUI_SLA_WatchOption_Tooltip")
    if not addCalled then return failure("watch_option_failed", "options.addTickBox") end
end
if type(option) ~= "table" or type(option.getValue) ~= "function" then
    return failure("watch_option_failed", "option")
end

local function ensureModOptionsPage()
    local instance = type(MainOptions) == "table" and rawget(MainOptions, "instance") or nil
    if type(instance) ~= "table" then return end
    local tabs = rawget(instance, "tabs")
    local getView = type(tabs) == "table" and tabs.getView or nil
    local addPanel = instance.addModOptionsPanel
    if type(getView) ~= "function" or type(addPanel) ~= "function" then return end
    local title = getText("UI_mainscreen_mods")
    local viewed, existingPage = pcall(getView, tabs, title)
    if viewed and existingPage == nil then pcall(addPanel, instance) end
end

ensureModOptionsPage()

local lifecycle = require "SurvivorLevelingAdvancement/Bootstrap"
local Build42WatchUi = require "SurvivorLevelingAdvancement/UI/Build42WatchUi"

local function isWorldMapVisible()
    local instance = rawget(_G, "ISWorldMap_instance")
    if instance == nil then return false end
    return instance:isVisible()
end

local function createPanel(callbacks)
    if type(Events) ~= "table" or type(Events.OnPostUIDraw) ~= "table"
        or type(Events.OnPostUIDraw.Add) ~= "function" then return nil end
    local x, y, width, height = 0, 0, 0, 0
    local element = ISUIElement:new(0, 0, 0, 0)
    element:initialise()
    element:instantiate()
    local textureSets = {}
    local function texturesFor(size)
        local existing = textureSets[size]
        if existing ~= nil then return existing end
        local digits = {}
        for digit = 0, 9 do
            digits[digit] = getTexture("media/ui/ClockAssets/ClockDigits" .. size
                .. tostring(digit) .. ".png")
        end
        local value = {
            digits = digits,
            slash = getTexture("media/ui/ClockAssets/DateDivide" .. size .. ".png"),
            dot = getTexture("media/ui/ClockAssets/ClockDigits" .. size .. "Dot.png"),
        }
        textureSets[size] = value
        return value
    end
    local draw = function()
        callbacks.prerender()
        callbacks.render()
    end
    Events.OnPostUIDraw.Add(draw)
    return {
        setGeometry = function(gx, gy, w, h)
            x, y, width, height = gx, gy, w, h
            element:setX(gx)
            element:setY(gy)
            element:setWidth(w)
            element:setHeight(h)
        end,
        width = function() return width end,
        height = function() return height end,
        drawPercentage = function(value)
            local size = getCore():getOptionClockSize() == 2 and "Medium" or "Small"
            local set = texturesFor(size)
            local text = tostring(value)
            local first = set.digits[tonumber(string.sub(text, 1, 1))]
            local digitWidth = first:getWidth()
            local digitHeight = first:getHeight()
            local dotWidth = set.dot:getWidth()
            local spacing = 1
            local signWidth = size == "Small" and 9 or 10
            local rightInset = 4
            local contentWidth = (#text * digitWidth) + ((#text - 1) * spacing)
                + spacing + signWidth
            local drawX = width - contentWidth - rightInset
            local drawY = math.max(0, height - digitHeight - 3)
            local r, g, b = 100 / 255, 200 / 255, 210 / 255
            for index = 1, #text do
                local digit = tonumber(string.sub(text, index, index))
                element:drawTexture(set.digits[digit], drawX, drawY, 1, r, g, b)
                drawX = drawX + digitWidth + spacing
            end
            local percentX = drawX
            local slashX = percentX + 3
            element:drawTexture(set.slash, slashX, drawY, 1, r, g, b)
            element:drawTexture(set.dot, percentX, drawY, 1, r, g, b)
            if size == "Small" then
                element:drawTexture(set.dot, percentX + 1, drawY, 1, r, g, b)
            end
            local bottomDotWidth = size == "Small" and 2 or dotWidth
            local bottomDotX = percentX + signWidth - bottomDotWidth
            local bottomDotY = drawY + digitHeight - dotWidth
            element:drawTexture(set.dot, bottomDotX, bottomDotY, 1, r, g, b)
            if size == "Small" then
                element:drawTexture(set.dot, bottomDotX + 1, bottomDotY, 1, r, g, b)
            end
        end,
    }
end

local createdCalled, created = pcall(Build42WatchUi.create, {
    owner = lifecycle,
    optionEnabled = function() return option:getValue() == true end,
    isWorldMapVisible = isWorldMapVisible,
    getClock = function() return UIManager.getClock() end,
    minuteStamp = function() return getGameTime():getMinutesStamp() end,
    getPlayer = function(slot) return getSpecificPlayer(slot) end,
    isDead = function(player) return player:isDead() end,
    createPanel = createPanel,
})
if not createdCalled or type(created) ~= "table" or rawget(created, "ok") ~= true
    or not validIntegration(rawget(created, "integration")) then
    return failure("watch_ui_create_failed", "Build42WatchUi.create")
end

local sentinel = { signature = SENTINEL_SIGNATURE, integration = created.integration }
rawset(_G, SENTINEL_KEY, sentinel)
local installed = install(created.integration)
if not installed.ok then return installed end
return created.integration
