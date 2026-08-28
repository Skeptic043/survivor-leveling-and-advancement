local key = "__SLA_Build42WatchUi_42_20_v4"
local evidence = rawget(_G, "__C20B_WATCH_BOOTSTRAP")

local function check(condition, message)
    if not condition then error(message, 2) end
    evidence.checks = evidence.checks + 1
end

if evidence == nil then
    evidence = { checks = 0, phase = 1, creates = 0, adds = 0, moduleCreates = 0,
        installs = 0, optionPageAdds = 0, postUiAdds = 0, postUiPrerenders = 0,
        postUiRenders = 0, textureDraws = {}, requires = {} }
    rawset(_G, "__C20B_WATCH_BOOTSTRAP", evidence)
    evidence.option = { value = false, getValue = function(self) return self.value end }
    evidence.options = {
        getOption = function(_, id) evidence.optionId = id; return nil end,
        addTickBox = function(_, id, name, value, tooltip)
            evidence.adds = evidence.adds + 1
            evidence.optionArgs = { id, name, value, tooltip }
            return evidence.option
        end,
    }
    PZAPI = { ModOptions = {
        getOptions = function(_, id) evidence.groupLookup = id; return nil end,
        create = function(_, id, name)
            evidence.creates = evidence.creates + 1
            evidence.groupArgs = { id, name }
            return evidence.options
        end,
    } }
    evidence.owner = { refreshOwner = function() end, clientState = function() end }
    evidence.integration = {
        install = function() evidence.installs = evidence.installs + 1; return { ok = true } end,
        status = function() return { ok = true } end,
    }
    evidence.module = { create = function(dependencies)
        evidence.moduleCreates = evidence.moduleCreates + 1
        evidence.dependencies = dependencies
        return { ok = true, integration = evidence.integration }
    end }
    require = function(path)
        evidence.requires[path] = (evidence.requires[path] or 0) + 1
        if path == "SurvivorLevelingAdvancement/Bootstrap" then return evidence.owner end
        if path == "SurvivorLevelingAdvancement/UI/Build42WatchUi" then return evidence.module end
        return true
    end
    ISUIElement = { new = function(_, x, y, width, height)
        local element = { x = x, y = y, width = width, height = height }
        function element:initialise() end
        function element:instantiate() self.javaObject = {} end
        function element:setX(value) self.x = value end
        function element:setY(value) self.y = value end
        function element:setWidth(value) self.width = value end
        function element:setHeight(value) self.height = value end
        function element:drawTexture(texture, x, y)
            evidence.textureDraws[#evidence.textureDraws + 1] = {
                texture = texture.name, x = self.x + x, y = self.y + y,
            }
        end
        return element
    end }
    UIManager = { getClock = function() return evidence.clock end }
    Events = { OnPostUIDraw = { Add = function(callback)
        evidence.postUiAdds = evidence.postUiAdds + 1
        evidence.postUiCallback = callback
    end } }
    local tabs = setmetatable({}, { __index = {
        getView = function() return evidence.optionsPage end,
    } })
    local mainOptionsInstance = setmetatable({ tabs = tabs }, { __index = {
        addModOptionsPanel = function()
            evidence.optionPageAdds = evidence.optionPageAdds + 1
            evidence.optionsPage = {}
        end,
    } })
    MainOptions = { instance = mainOptionsInstance }
    getGameTime = function() return { getMinutesStamp = function() return 12 end } end
    getSpecificPlayer = function(slot) return { slot = slot } end
    getText = function(key) return key end
    getCore = function() return { getOptionClockSize = function() return evidence.clockSize or 1 end } end
    getTexture = function(path)
        local slash = string.find(path, "DateDivide", 1, true) ~= nil
        local dot = string.find(path, "Dot", 1, true) ~= nil
        local medium = string.find(path, "Medium", 1, true) ~= nil
        return {
            name = path,
            getWidth = function()
                if medium then return slash and 5 or dot and 2 or 9 end
                return slash and 3 or dot and 1 or 4
            end,
            getHeight = function()
                if medium then return dot and 2 or 17 end
                return dot and 1 or 7
            end,
        }
    end
    rawset(_G, key, nil)
elseif evidence.phase == 1 then
    check(evidence.creates == 1 and evidence.adds == 1 and evidence.moduleCreates == 1, "first load creates option and module once")
    check(evidence.installs == 1, "first load installs once")
    check(evidence.optionPageAdds == 1, "save-loaded mod adds the absent vanilla Mods page once")
    check(evidence.groupArgs[1] == "SurvivorLevelingAdvancement"
        and evidence.groupArgs[2] == "IGUI_SLA_ModOptions_Title", "localized option group")
    check(evidence.optionArgs[1] == "ShowWatchProgress" and evidence.optionArgs[3] == false, "watch option defaults off")
    check(evidence.optionArgs[2] == "IGUI_SLA_WatchOption"
        and evidence.optionArgs[4] == "IGUI_SLA_WatchOption_Tooltip", "localized option copy")
    check(evidence.dependencies.owner == evidence.owner, "exact lifecycle owner injected")
    check(evidence.dependencies.optionEnabled() == false
        and evidence.dependencies.minuteStamp() == 12, "option and engine minute capabilities")
    check(evidence.dependencies.getPlayer(0).slot == 0, "player one lookup capability")
    local panel = evidence.dependencies.createPanel({
        prerender = function() evidence.postUiPrerenders = evidence.postUiPrerenders + 1 end,
        render = function() evidence.postUiRenders = evidence.postUiRenders + 1 end,
    })
    check(type(panel) == "table" and evidence.postUiAdds == 1, "post-UI drawing seam registered")
    panel.setGeometry(100, 10, 91, 37)
    panel.drawPercentage(54)
    check(#evidence.textureDraws == 7,
        "small percentage uses two digits plus slash and doubled native percent dots")
    check(evidence.textureDraws[1].texture == "media/ui/ClockAssets/ClockDigitsSmall5.png"
        and evidence.textureDraws[1].x == 168 and evidence.textureDraws[1].y == 37
        and evidence.textureDraws[2].x == 173,
        "small percentage preserves native number spacing while shifting the group left")
    check(evidence.textureDraws[3].texture == "media/ui/ClockAssets/DateDivideSmall.png"
        and evidence.textureDraws[3].x == 181
        and evidence.textureDraws[4].x == 178 and evidence.textureDraws[5].x == 179
        and evidence.textureDraws[6].x == 185 and evidence.textureDraws[7].x == 186,
        "small percent visibly spans nine pixels and retains a four-pixel right margin")
    evidence.clockSize = 2
    evidence.textureDraws = {}
    panel.setGeometry(100, 10, 156, 62)
    panel.drawPercentage(54)
    check(#evidence.textureDraws == 5
        and evidence.textureDraws[1].texture == "media/ui/ClockAssets/ClockDigitsMedium5.png"
        and evidence.textureDraws[1].x == 222 and evidence.textureDraws[1].y == 52
        and evidence.textureDraws[2].x == 232
        and evidence.textureDraws[3].texture == "media/ui/ClockAssets/DateDivideMedium.png"
        and evidence.textureDraws[3].x == 245
        and evidence.textureDraws[4].x == 242 and evidence.textureDraws[5].x == 250,
        "large percentage preserves number spacing with a ten-pixel sign and four-pixel margin")
    evidence.postUiCallback()
    check(evidence.postUiPrerenders == 1 and evidence.postUiRenders == 1,
        "post-UI callback updates then draws")
    check(rawget(evidence.dependencies, "Events") == nil and rawget(evidence.dependencies, "ModData") == nil,
        "no event or persistence surface")
    evidence.phase = 2
elseif evidence.phase == 2 then
    check(evidence.creates == 1 and evidence.adds == 1 and evidence.moduleCreates == 1, "reload reuses sentinel")
    check(evidence.installs == 2, "reload calls idempotent integration install")
    rawset(_G, key, { signature = "wrong", integration = evidence.integration })
    evidence.phase = 3
elseif evidence.phase == 3 then
    check(rawget(_G, "C20BWatchCollision").code == "watch_ui_sentinel_collision", "sentinel collision fails closed")
    rawset(_G, key, nil)
    PZAPI.ModOptions.getOptions = function() error("option lookup") end
    evidence.phase = 4
elseif evidence.phase == 4 then
    check(rawget(_G, "C20BWatchOptionThrow").code == "watch_option_failed", "throwing option lookup fails closed")
    rawset(_G, key, nil)
    PZAPI.ModOptions.getOptions = nil
    evidence.phase = 5
elseif evidence.phase == 5 then
    check(rawget(_G, "C20BWatchOptionMissing").code == "watch_option_failed", "missing option lookup fails closed")
end

return evidence.checks
