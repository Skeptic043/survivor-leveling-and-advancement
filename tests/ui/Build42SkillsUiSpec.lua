local assertions = 0

local function expect(condition, message)
    assertions = assertions + 1
    if not condition then error(message, 2) end
end

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function exact(value, fields)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do if not fields[key] then return false end end
    for key in pairs(fields) do if rawget(value, key) == nil then return false end end
    return true
end

local function rootScreenX(element)
    local current = element
    while type(current) == "table" and rawget(current, "parent") ~= nil do
        current = rawget(current, "parent")
    end
    return type(current) == "table" and rawget(current, "x") or nil
end

local translations = {
    IGUI_SLA_StatusLevel = "Survivor Level: %1",
    IGUI_SLA_StatusAP = "AP: %1",
    IGUI_SLA_StatusActive = "Advancement Slots: %1/%2",
    IGUI_SLA_StatusSurvivorXp = "Survivor XP: %1 / %2",
    IGUI_SLA_Advance = "Advance to level %1 for %2 AP.",
    IGUI_SLA_Master = "Master skill for %1 AP.",
    IGUI_SLA_PerSkillActive = "Advancement Slots: %1/%2.",
    IGUI_SLA_TargetXpLeft = "%1 natural skill XP left",
    IGUI_SLA_TargetCatchUp = "Catch up to free this advancement slot.",
    IGUI_SLA_RecoveryXpLeft = "%1 lost skill XP left",
    IGUI_SLA_RecoveryNoSurvivorXp = "No Survivor XP during recovery.",
    IGUI_SLA_Reason_Pending = "An advancement request is pending.",
    IGUI_SLA_Reason_MaximumMismatch = "This skill's progression curve changed.",
    IGUI_SLA_Reason_AtMaximum = "This skill is already at its maximum.",
    IGUI_SLA_Reason_RedRecovery = "Recover natural XP before advancing again.",
    IGUI_SLA_Reason_InsufficientAp = "Not enough AP.",
    IGUI_SLA_Reason_AllotmentDisabled = "Advancement spending is disabled for this skill.",
    IGUI_SLA_Reason_AllotmentCapacity = "Advancement slot unavailable.",
    IGUI_SLA_Advancement_Stale = "Survivor data changed. Refresh and try again.",
    IGUI_SLA_Advancement_SendFailed = "The advancement request could not be sent. Try again.",
    IGUI_SLA_Advancement_Committed = "The advancement may have applied. Refresh before trying again.",
    IGUI_SLA_Advancement_Failed = "The advancement failed. Refresh and try again.",
    IGUI_SLA_Admin_Button = "Admin",
}

local function formatText(key, ...)
    local value = translations[key]
    if value == nil then return key end
    local arguments = { ... }
    for index = 1, #arguments do
        value = string.gsub(value, "%%" .. tostring(index), tostring(arguments[index]))
    end
    return value
end

local function snapshot()
    return {
        protocolVersion = 1,
        ready = true,
        sequence = 1,
        revision = 2,
        survivor = {
            level = 5,
            xpIntoLevel = 10,
            xpForNextLevel = 100,
            spent = 2,
            availableAp = 3,
        },
        perks = {},
    }
end

local function settings(mode, fitnessStrengthNormalization)
    return {
        survivorMultiplier = 1,
        fitnessStrengthNormalization = fitnessStrengthNormalization == nil
            and 0.067 or fitnessStrengthNormalization,
        automaticCurveNormalization = true,
        customSkillSurvivorXpEnabled = true,
        perSkillSurvivorXpEnabled = { Axe = true },
        allotmentMode = mode or "Global",
        globalLimit = 6,
        perSkillDefault = 2,
        perSkillOverrides = { Axe = 4 },
        inheritanceEnabled = true,
        retainedRatio = 0.5,
    }
end

local function makeEnvironment(options)
    options = options or {}
    local evidence = {
        now = 0,
        priorPrerender = 0,
        priorRender = 0,
        priorOverlay = 0,
        priorTooltip = 0,
        priorRemoveTooltip = 0,
        priorActivate = 0,
        priorJoypadDown = 0,
        priorJoypadUp = 0,
        priorJoypadDownDirection = 0,
        priorJoypadLeft = 0,
        priorJoypadRight = 0,
        priorJoypadGain = 0,
        priorJoypadLose = 0,
        priorMouseUp = 0,
        priorMouseWheel = 0,
        wheelDeltas = {},
        refresh = { 0, 0, 0, 0 },
        stateReads = { 0, 0, 0, 0 },
        statusReads = { 0, 0, 0, 0 },
        settingsReads = 0,
        modelBuilds = 0,
        requests = { 0, 0, 0, 0 },
        adminRequests = 0,
        launcherStatusReads = 0,
        progressionBuilds = 0,
        progressionDescribes = 0,
        progressionInspects = 0,
        buttonCreates = 0,
        panelCreates = 0,
        adminInstalls = 0,
        adminStatusReads = 0,
        adminAvailabilityReads = 0,
        adminOpens = {},
        adminAvailable = true,
        adminInstalled = false,
        listenerSets = 0,
        listener = nil,
        prerenderGeometry = {},
        joypadHighlights = {},
        mode = options.mode or "Global",
        fitnessStrengthNormalization = options.fitnessStrengthNormalization,
        contributionSettingsMutation = options.contributionSettingsMutation,
        pending = { false, false, false, false },
        terminalResults = {},
        reason = options.reason,
        malformedSettings = false,
        modelFailure = false,
        incompleteEnabled = false,
        enabledAtMaximum = false,
        enabledMissingCost = false,
        enabledCurrentTarget = false,
        enabledAboveMaximum = false,
        enabledZeroCost = false,
        asynchronous = options.asynchronous ~= false,
        xpIntoLevel = options.xpIntoLevel,
        xpForNextLevel = options.xpForNextLevel,
        drawOrder = {},
        buildArguments = {},
        vanillaRootXs = {},
        progressRootXs = {},
        adminRootXs = {},
        survivorLevel = options.survivorLevel,
        spentAp = options.spentAp,
        availableAp = options.availableAp,
        omitSurvivorLevel = false,
        malformedSurvivorLevel = false,
    }

    local CharacterInfo = {}
    local ProgressBar = {}
    local Button = {}
    local Panel = {}

    function CharacterInfo.prerender(self)
        evidence.priorPrerender = evidence.priorPrerender + 1
        if self.throwPrerender then error("vanilla prerender") end
        evidence.prerenderGeometry[#evidence.prerenderGeometry + 1] = {
            y = self:getY(),
            height = self:getHeight(),
        }
    end

    function CharacterInfo.render(self)
        evidence.priorRender = evidence.priorRender + 1
        evidence.vanillaRootXs[#evidence.vanillaRootXs + 1] = rootScreenX(self)
        if self.throwRender then error("vanilla render") end
        if self.pendingBars ~= nil then
            self.progressBars = self.pendingBars
            self.pendingBars = nil
        end
        if self.buttonList[1] ~= nil then self.buttonList[1]:setY(10) end
        self:setWidthAndParentWidth(math.max(self:getWidth(), self.vanillaWidth))
        self:setHeightAndParentHeight(self.vanillaHeight)
        self:setScrollHeight(self.vanillaScrollHeight)
        if self.joyfocus and self.joypadIndex and self.progressBars[self.joypadIndex] then
            evidence.joypadHighlights[#evidence.joypadHighlights + 1] = {
                index = self.joypadIndex,
                yScroll = self:getYScroll(),
                barY = self.progressBars[self.joypadIndex]:getY(),
                height = self:getHeight(),
                scrollHeight = self:getScrollHeight(),
            }
        end
    end

    function CharacterInfo.onJoypadDown(self, button)
        evidence.priorJoypadDown = evidence.priorJoypadDown + 1
        if button == "A" and self.joypadIndex and self.progressBars[self.joypadIndex] then
            self.progressBars[self.joypadIndex]:activate()
        end
    end

    function CharacterInfo.onJoypadDirUp(self)
        evidence.priorJoypadUp = evidence.priorJoypadUp + 1
        if not self.joypadIndex or self.joypadIndex == 1 then
            self.joypadIndex = #self.progressBars
        else
            self.joypadIndex = self.joypadIndex - 1
        end
    end

    function CharacterInfo.onJoypadDirDown(self)
        evidence.priorJoypadDownDirection = evidence.priorJoypadDownDirection + 1
        if not self.joypadIndex or self.joypadIndex == #self.progressBars then
            self.joypadIndex = 1
        else
            self.joypadIndex = self.joypadIndex + 1
        end
    end

    function CharacterInfo.onJoypadDirLeft() evidence.priorJoypadLeft = evidence.priorJoypadLeft + 1 end
    function CharacterInfo.onJoypadDirRight() evidence.priorJoypadRight = evidence.priorJoypadRight + 1 end
    function CharacterInfo.onGainJoypadFocus(self)
        evidence.priorJoypadGain = evidence.priorJoypadGain + 1
        self.joypadIndex = nil
    end
    function CharacterInfo.onLoseJoypadFocus() evidence.priorJoypadLose = evidence.priorJoypadLose + 1 end
    function CharacterInfo.onMouseWheel(self, delta)
        evidence.priorMouseWheel = evidence.priorMouseWheel + 1
        evidence.wheelDeltas[#evidence.wheelDeltas + 1] = delta
        self:setYScroll(self:getYScroll() - delta * 30)
        return true
    end
    function ProgressBar.renderPerkRect(self)
        evidence.priorOverlay = evidence.priorOverlay + 1
        evidence.progressRootXs[#evidence.progressRootXs + 1] = rootScreenX(self)
        evidence.drawOrder[#evidence.drawOrder + 1] = "gold"
        self.level = self.perk.level
    end

    function ProgressBar.updateTooltip(self)
        evidence.priorTooltip = evidence.priorTooltip + 1
        self.message = "Vanilla tooltip"
    end

    function ProgressBar.removeTooltip(self)
        evidence.priorRemoveTooltip = evidence.priorRemoveTooltip + 1
        if evidence.removeTooltipThrows then error("remove tooltip boom") end
        self.message = nil
    end

    function ProgressBar.activate(self)
        evidence.priorActivate = evidence.priorActivate + 1
    end

    function ProgressBar.onMouseUp(self)
        evidence.priorMouseUp = evidence.priorMouseUp + 1
    end

    function Button.new(_, x, y, width, height, title, target, onclick)
        evidence.buttonCreates = evidence.buttonCreates + 1
        local button = {
            x = x,
            y = y,
            width = math.max(width, 20),
            height = height,
            title = title,
            target = target,
            onclick = onclick,
            enabled = true,
            visible = true,
            tooltip = nil,
        }
        function button:initialise() self.initialised = true end
        function button:setEnable(value) self.enabled = value end
        function button:setVisible(value) self.visible = value end
        function button:setTooltip(value) self.tooltip = value end
        function button:isMouseOver()
            evidence.buttonHoverReads = (evidence.buttonHoverReads or 0) + 1
            return self.mouseOver == true
        end
        function button:setBorderRGBA(r, g, b, a) self.border = { r, g, b, a } end
        function button:getWidth() return self.width end
        function button:getHeight() return self.height end
        function button:setX(value) self.x = value end
        function button:setY(value) self.y = value end
        function button:click()
            if self.enabled and self.onclick ~= nil then self.onclick(self.target, self) end
        end
        function button:render()
            if self.title == "Admin" then
                evidence.adminRootXs[#evidence.adminRootXs + 1] = rootScreenX(self)
            end
        end
        return setmetatable(button, { __index = {
            setJoypadFocused = function(self, value) self.joypadFocused = value end,
            forceClick = function(self) self:click() end,
        } })
    end

    function Panel.new(_, x, y, width, height)
        evidence.panelCreates = evidence.panelCreates + 1
        local panel = {
            x = x, y = y, width = width, height = height, visible = true,
        }
        function panel:initialise()
            self.initialised = true
            self.javaObject = {
                setConsumeMouseEvents = function(_, value)
                    self.javaConsumeMouseEvents = value
                end,
            }
        end
        function panel:noBackground() self.background = false end
        function panel:setWantMouseEvents(value)
            self.javaObject:setConsumeMouseEvents(value)
        end
        function panel:setVisible(value) self.visible = value end
        function panel:getWidth() return self.width end
        function panel:getHeight() return self.height end
        function panel:setX(value) self.x = value end
        function panel:setY(value) self.y = value end
        function panel:setWidth(value) self.width = value end
        function panel:setHeight(value) self.height = value end
        return panel
    end

    local owner = {
        install = function() return { ok = true } end,
        status = function() return { ok = true } end,
        clientState = function(slot)
            evidence.stateReads[slot + 1] = evidence.stateReads[slot + 1] + 1
            if evidence.stateMalformed then return { ok = true, present = false, extra = true } end
            return { ok = true, present = true, snapshot = snapshot() }
        end,
        refreshOwner = function(slot)
            evidence.refresh[slot + 1] = evidence.refresh[slot + 1] + 1
            if evidence.refreshThrows then error("refresh boom") end
            if evidence.refreshPending then
                return { ok = false, code = "refresh_pending", detail = "coalesced" }
            end
            return { ok = true }
        end,
        setClientStateListener = function(listener)
            evidence.listenerSets = evidence.listenerSets + 1
            if evidence.listenerFailure then return { ok = false, code = "bad", detail = "bad" } end
            evidence.listener = listener
            return { ok = true }
        end,
        requestAdvancement = function(slot, perkId)
            evidence.requests[slot + 1] = evidence.requests[slot + 1] + 1
            evidence.lastRequest = { slot = slot, perkId = perkId }
            if evidence.requestReject then
                return { ok = false, code = "no_ap", detail = "secret backend detail" }
            end
            if evidence.asynchronous then return { ok = true, requestId = "ui-request" } end
            return {
                ok = true,
                applied = true,
                requestId = "sp-request",
                perkId = perkId,
                apCost = 1,
                mastered = false,
                snapshotAccepted = true,
            }
        end,
        advancementStatus = function(slot)
            evidence.statusReads[slot + 1] = evidence.statusReads[slot + 1] + 1
            if evidence.statusMalformed then return { ok = true, pending = "no" } end
            if evidence.pending[slot + 1] then
                return { ok = true, pending = true, requestId = "pending-id", perkId = "Axe" }
            end
            if evidence.terminalResults[slot + 1] ~= nil then
                return { ok = true, pending = false, result = evidence.terminalResults[slot + 1] }
            end
            return { ok = true, pending = false }
        end,
        requestAdmin = function()
            evidence.adminRequests = evidence.adminRequests + 1
            error("Skills UI must not request admin")
        end,
        adminStatus = function()
            evidence.adminStatusReads = evidence.adminStatusReads + 1
            error("Skills UI must not read admin status")
        end,
    }

    local provider = {
        read = function()
            evidence.settingsReads = evidence.settingsReads + 1
            if evidence.settingsThrows then error("settings boom") end
            if evidence.malformedSettings then return nil end
            local value = settings(evidence.mode, evidence.fitnessStrengthNormalization)
            if evidence.contributionSettingsMutation == "custom" then
                value.customSkillSurvivorXpEnabled = "true"
            elseif evidence.contributionSettingsMutation == "map" then
                value.perSkillSurvivorXpEnabled = { ["bad perk"] = true }
            elseif evidence.contributionSettingsMutation == "value" then
                value.perSkillSurvivorXpEnabled.Axe = 1
            end
            evidence.lastRawSettings = value
            return value
        end,
    }

    local model = {
        build = function(input)
            evidence.modelBuilds = evidence.modelBuilds + 1
            evidence.buildArguments[#evidence.buildArguments + 1] = input
            if evidence.modelThrows then error("model boom") end
            if evidence.modelFailure then return { ok = false, code = "bad", detail = "secret" } end
            local rows = {}
            for index = 1, #input.rows do
                local source = input.rows[index]
                local reason = evidence.reason
                if input.pending then reason = "pending" end
                local row = {
                    currentLevel = source.currentLevel,
                    effectiveMaximum = source.effectiveMaximum,
                    nextTargetLevel = source.currentLevel + 1,
                    apCost = source.currentLevel + 1 == source.effectiveMaximum and 2 or 1,
                    enabled = reason == nil,
                }
                if input.allotment.mode ~= "Free" then
                    row.activeTargets = evidence.activeTargets or {
                        { targetLevel = 2, targetPosition = 200 },
                        { targetLevel = 4, targetPosition = 400 },
                    }
                    row.naturalPosition = evidence.naturalPosition == nil and 100 or evidence.naturalPosition
                    row.highWaterPosition = evidence.highWaterPosition == nil and 150 or evidence.highWaterPosition
                end
                if reason ~= nil then row.reasonCode = reason end
                if input.allotment.mode == "PerSkill" then
                    row.activeCount = 1
                    row.limit = input.allotment.perSkillOverrides[source.perkId]
                        or input.allotment.perSkillDefault
                end
                if evidence.modelMaximumOffset then
                    row.effectiveMaximum = row.effectiveMaximum + evidence.modelMaximumOffset
                    row.enabled = false
                    row.reasonCode = "maximum_mismatch"
                end
                if evidence.incompleteEnabled then
                    row.nextTargetLevel = nil
                    row.apCost = nil
                    row.enabled = true
                    row.reasonCode = nil
                end
                if evidence.enabledAtMaximum then
                    row.currentLevel = row.effectiveMaximum
                    row.nextTargetLevel = nil
                    row.apCost = nil
                    row.enabled = true
                    row.reasonCode = nil
                end
                if evidence.enabledMissingCost then
                    row.apCost = nil
                    row.enabled = true
                    row.reasonCode = nil
                end
                if evidence.enabledCurrentTarget then
                    row.nextTargetLevel = row.currentLevel
                    row.enabled = true
                    row.reasonCode = nil
                end
                if evidence.enabledAboveMaximum then
                    row.nextTargetLevel = row.effectiveMaximum + 1
                    row.enabled = true
                    row.reasonCode = nil
                end
                if evidence.enabledZeroCost then
                    row.apCost = 0
                    row.enabled = true
                    row.reasonCode = nil
                end
                rows[source.perkId] = row
            end
            local allotment = { mode = input.allotment.mode }
            if input.allotment.mode == "Global" then
                allotment.activeCount = 2
                allotment.limit = input.allotment.globalLimit
            end
            local survivorLevel = evidence.survivorLevel or 5
            local spentAp = evidence.spentAp or 2
            local result = {
                sequence = 1,
                revision = 2,
                survivor = {
                    level = survivorLevel,
                    xpIntoLevel = evidence.xpIntoLevel or 10,
                    xpForNextLevel = evidence.xpForNextLevel or 100,
                    spent = spentAp,
                    availableAp = evidence.availableAp or survivorLevel - spentAp,
                },
                allotment = allotment,
                pending = input.pending,
                rows = rows,
            }
            if evidence.omitSurvivorLevel then result.survivor.level = nil end
            if evidence.malformedSurvivorLevel then result.survivor.level = "five" end
            if evidence.privateModelField then result.private = true end
            evidence.lastModelView = result
            return { ok = true, view = result }
        end,
    }

    local progression = {
        build = function(perk)
            evidence.progressionBuilds = evidence.progressionBuilds + 1
            evidence.buildPerk = perk
            if perk.unsupported then return { ok = false, code = "unsupported", detail = "unsupported" } end
            return { ok = true, handle = { perk = perk } }
        end,
        describe = function(handle)
            evidence.progressionDescribes = evidence.progressionDescribes + 1
            evidence.describeHandle = handle
            local maximum = handle.perk.maximum or 10
            local thresholds = { [0] = 0 }
            for level = 1, maximum do thresholds[level] = level * 100 end
            if handle.perk.badCurve then thresholds[2] = thresholds[1] end
            return {
                ok = true,
                effectiveMaximum = maximum,
                cumulativeThresholds = thresholds,
            }
        end,
        inspect = function(handle, player)
            evidence.progressionInspects = evidence.progressionInspects + 1
            evidence.inspectHandle = handle
            evidence.inspectPlayer = player
            return {
                ok = true,
                storedLevel = handle.perk.level or 1,
                effectiveMaximum = handle.perk.maximum or 10,
            }
        end,
    }

    local dependencies = {
        ISCharacterInfo = CharacterInfo,
        ISSkillProgressBar = ProgressBar,
        ISButton = Button,
        ISPanel = Panel,
        owner = owner,
        viewModel = model,
        settingsProvider = provider,
        progressionAdapter = progression,
        clockMillis = function()
            if evidence.clockThrows then error("clock boom") end
            return evidence.now
        end,
        getText = formatText,
        measureText = function(text) return #text * (evidence.measureScale or 1) end,
        smallFont = "small-font",
        joypadAButton = "A",
    }
    if options.adminLauncher then
        dependencies.adminLauncher = {
            install = function()
                evidence.adminInstalls = evidence.adminInstalls + 1
                evidence.adminInstalled = true
                return { ok = true }
            end,
            status = function()
                evidence.launcherStatusReads = evidence.launcherStatusReads + 1
                return { ok = true, installed = evidence.adminInstalled }
            end,
            isAvailable = function(slot)
                evidence.adminAvailabilityReads = evidence.adminAvailabilityReads + 1
                evidence.lastAdminAvailabilitySlot = slot
                return evidence.adminAvailable
            end,
            open = function(slot)
                evidence.adminOpens[#evidence.adminOpens + 1] = slot
                return { ok = true }
            end,
        }
        evidence.adminLauncher = dependencies.adminLauncher
    end
    local created = Build42SkillsUi.create(dependencies)
    expect(created.ok, "integration creates")
    evidence.integration = created.integration
    evidence.CharacterInfo = CharacterInfo
    evidence.ProgressBar = ProgressBar
    evidence.Button = Button
    evidence.Panel = Panel
    evidence.owner = owner
    evidence.dependencies = dependencies
    return evidence
end

local function makeParent(width, height, ancestor, x, y)
    local parent = {
        x = x or 0,
        y = y or 0,
        width = width or 450,
        height = height or 308,
        parent = ancestor,
        statusDraws = {},
        xScroll = 0,
        yScroll = 0,
        children = {},
    }
    function parent:getX() return self.x end
    function parent:getY() return self.y end
    function parent:getWidth() return self.width end
    function parent:getHeight() return self.height end
    function parent:setX(value)
        if self.keepOnScreen then
            value = math.max(0, math.min(value, self.screenWidth - self.width))
        end
        self.x = value
    end
    function parent:setWidth(value)
        if self.throwSetWidth then
            local child = self.children[1]
            local childVisible, childEnabled = nil, nil
            if type(child) == "table" then
                childVisible = child.visible
                childEnabled = child.enabled
            end
            self.throwSetWidthObservation = {
                visible = childVisible,
                enabled = childEnabled,
            }
            error("parent setWidth")
        end
        self.width = value
        if self.keepOnScreen then
            self.x = math.max(0, math.min(self.x, self.screenWidth - self.width))
        end
    end
    function parent:setHeight(value) self.height = value end
    function parent:addChild(child)
        self.children[#self.children + 1] = child
        child.parent = self
    end
    function parent:removeChild(child)
        for index = #self.children, 1, -1 do
            if self.children[index] == child then table.remove(self.children, index) end
        end
    end
    function parent:canRouteMouseTo(child)
        return child.parent == self and child.visible ~= false and child.enabled ~= false
            and child.x >= 0 and child.y >= 0
            and child.x + child.width <= self.width
            and child.y + child.height <= self.height
    end
    function parent:drawText(text, drawX, drawY, r, g, b, a, font)
        if self.throwDraw then error("parent draw boom") end
        self.statusDraws[#self.statusDraws + 1] = {
            kind = "left",
            text = text,
            x = drawX,
            y = drawY,
            screenX = self.x + drawX - self.xScroll,
            screenY = self.y + drawY - self.yScroll,
            rootX = rootScreenX(self),
            font = font,
        }
    end
    function parent:drawTextRight(text, drawX, drawY, r, g, b, a, font)
        if self.throwDraw then error("parent draw boom") end
        self.statusDraws[#self.statusDraws + 1] = {
            kind = "right",
            text = text,
            x = drawX,
            y = drawY,
            screenX = self.x + drawX - self.xScroll,
            screenY = self.y + drawY - self.yScroll,
            rootX = rootScreenX(self),
            font = font,
        }
    end
    return parent
end

local function makeBar(environment, id, options)
    options = options or {}
    local perk = {
        id = id,
        maximum = options.maximum or 10,
        level = options.level or 1,
        unsupported = options.unsupported,
        badCurve = options.badCurve,
    }
    function perk:getId() return self.id end
    local bar = {
        perk = perk,
        char = options.player or { name = "player-" .. id },
        x = options.x or 100,
        y = options.y or 40,
        width = options.width or 200,
        height = options.height or 20,
        level = perk.level,
        mouseX = options.mouseX or -1,
        children = {},
        draws = {},
    }
    function bar:getX() return self.x end
    function bar:getY() return self.y end
    function bar:getWidth() return self.width end
    function bar:getHeight() return self.height end
    function bar:getMouseX() return self.mouseX end
    function bar:setWidth(value) self.width = value end
    function bar:addChild(child) self.children[#self.children + 1] = child end
    function bar:drawRectBorder(x, y, width, height, alpha, r, g, b)
        self.draws[#self.draws + 1] = { kind = "border", x = x, y = y, width = width, height = height,
            alpha = alpha, r = r, g = g, b = b }
        environment.drawOrder[#environment.drawOrder + 1] = "overlay-border"
    end
    function bar:drawRect(x, y, width, height, alpha, r, g, b)
        self.draws[#self.draws + 1] = { kind = "rect", x = x, y = y, width = width, height = height,
            alpha = alpha, r = r, g = g, b = b }
        environment.drawOrder[#environment.drawOrder + 1] = "overlay-rect"
    end
    setmetatable(bar, { __index = environment.ProgressBar })
    return bar
end

local function makeView(environment, slot, bars, delayed)
    local category = { name = "Long category" }
    function category:getName() return self.name end
    local categoryButton = { x = 10, y = 10, width = 20 }
    function categoryButton:getRight() return self.x + self.width end
    function categoryButton:getY() return self.y end
    function categoryButton:getHeight() return 20 end
    function categoryButton:setY(value) self.y = value end
    local outer = makeParent(450, 328, nil, 0, 0)
    local parent = makeParent(450, 308, outer, 0, 20)
    local view = {
        playerNum = slot,
        progressBars = delayed and {} or bars,
        pendingBars = delayed and bars or nil,
        parent = parent,
        outer = outer,
        x = 0,
        y = 8,
        width = 400,
        height = 300,
        vanillaWidth = 400,
        vanillaHeight = 300,
        vanillaScrollHeight = 500,
        scrollHeight = 500,
        yScroll = 0,
        visible = true,
        visibleTransitions = 0,
        sorted = { category },
        buttonList = { categoryButton },
        statusDraws = parent.statusDraws,
    }
    function view:getX() return self.x end
    function view:getY() return self.y end
    function view:getWidth() return self.width end
    function view:getHeight() return self.height end
    function view:setY(value) self.y = value end
    function view:setWidth(value) self.width = value end
    function view:setHeight(value) self.height = value end
    function view:getYScroll() return self.yScroll end
    function view:setYScroll(value)
        if environment.realisticScrollClamp then
            local maximum = math.max(0, self.scrollHeight - self.height)
            value = math.max(-maximum, math.min(0, value))
        end
        self.yScroll = value
    end
    function view:getScrollHeight() return self.scrollHeight end
    function view:setScrollHeight(value)
        self.scrollHeight = value
        if environment.vanillaRenderClampsScroll then self.yScroll = 0 end
    end
    function view:isVisible() return self.visible ~= false end
    function view:setVisible(value)
        self.visibleTransitions = self.visibleTransitions + 1
        self.visible = value
        if self.throwSetVisible then error("vanilla setVisible") end
    end
    function view:setWidthAndParentWidth(value)
        self:setWidth(value)
        local child, current = self, self.parent
        while current ~= nil do
            current:setWidth(child:getX() + child:getWidth())
            child, current = current, current.parent
        end
    end
    function view:setHeightAndParentHeight(value)
        self:setHeight(value)
        local child, current = self, self.parent
        while current ~= nil do
            current:setHeight(child:getY() + child:getHeight())
            child, current = current, current.parent
        end
        if environment.vanillaRenderClampsScroll then self.yScroll = 0 end
    end
    setmetatable(view, { __index = environment.CharacterInfo })
    for index = 1, #bars do bars[index].parent = view end
    return view
end

local function total(list)
    local result = 0
    for index = 1, #list do result = result + list[index] end
    return result
end

local function lastDraw(list, kind)
    for index = #list, 1, -1 do
        if list[index].kind == kind then return list[index] end
    end
    return nil
end

local function lastDrawText(list, text)
    for index = #list, 1, -1 do
        if list[index].text == text then return list[index] end
    end
    return nil
end

expect(type(Build42SkillsUi) == "table", "module loads")
expect(type(Build42SkillsUi.create) == "function", "module exposes create")
equal(SkillsUiBootstrapHarness, 25, "bootstrap harness checks")
expect(C11CBootstrapFirst == rawget(_G, "__C11C_BOOTSTRAP_EVIDENCE").integration,
    "bootstrap returns integration")
expect(C11CBootstrapReload == C11CBootstrapFirst, "reload returns exact integration")

local malformed = Build42SkillsUi.create({})
equal(malformed.ok, false, "malformed dependencies fail")
equal(malformed.code, "invalid_dependencies", "malformed dependency code")

local environment = makeEnvironment()
expect(exact(environment.owner, {
    install = true,
    status = true,
    clientState = true,
    refreshOwner = true,
    setClientStateListener = true,
    requestAdvancement = true,
    advancementStatus = true,
    requestAdmin = true,
    adminStatus = true,
}), "exact nine-method owner is accepted")

local function copyOwner(owner)
    local copy = {}
    for key, value in pairs(owner) do copy[key] = value end
    return copy
end

local function createWithOwner(owner)
    local dependencies = {}
    for key, value in pairs(environment.dependencies) do dependencies[key] = value end
    dependencies.owner = owner
    return Build42SkillsUi.create(dependencies)
end

local ownerMissingAdmin = copyOwner(environment.owner)
ownerMissingAdmin.requestAdmin = nil
local missingAdmin = createWithOwner(ownerMissingAdmin)
equal(missingAdmin.ok, false, "owner missing admin request fails closed")
equal(missingAdmin.code, "invalid_dependencies", "missing admin request failure code")

local ownerNoncallableAdmin = copyOwner(environment.owner)
ownerNoncallableAdmin.adminStatus = true
local noncallableAdmin = createWithOwner(ownerNoncallableAdmin)
equal(noncallableAdmin.ok, false, "owner noncallable admin status fails closed")
equal(noncallableAdmin.code, "invalid_dependencies", "noncallable admin status failure code")

local ownerWithExtraMember = copyOwner(environment.owner)
ownerWithExtraMember.unexpected = function() end
local extraOwnerMember = createWithOwner(ownerWithExtraMember)
equal(extraOwnerMember.ok, false, "owner extra member fails closed")
equal(extraOwnerMember.code, "invalid_dependencies", "extra owner member failure code")

local missingRemovalDependencies = {}
for key, value in pairs(environment.dependencies) do missingRemovalDependencies[key] = value end
local missingRemovalProgressBar = {}
for key, value in pairs(environment.ProgressBar) do missingRemovalProgressBar[key] = value end
missingRemovalProgressBar.removeTooltip = nil
missingRemovalDependencies.ISSkillProgressBar = missingRemovalProgressBar
local missingRemoval = Build42SkillsUi.create(missingRemovalDependencies)
equal(missingRemoval.ok, false, "missing vanilla tooltip removal fails closed")
equal(missingRemoval.code, "invalid_dependencies", "missing vanilla tooltip removal failure code")

expect(exact(environment.integration.status(), { ok = true, installed = true })
    and environment.integration.status().installed == false, "creation is inert")
equal(environment.listenerSets, 0, "creation installs no listener")
equal(environment.buttonCreates, 0, "creation creates no UI")
equal(environment.settingsReads, 0, "creation reads no settings")
equal(environment.adminRequests, 0, "creation does not call admin request")
equal(environment.adminStatusReads, 0, "creation does not read admin status")
equal(total(environment.stateReads), 0, "creation reads no state")
equal(total(environment.refresh), 0, "creation sends no refresh")
local vanillaRemoveTooltip = environment.ProgressBar.removeTooltip
local installed = environment.integration.install()
expect(exact(installed, { ok = true }) and installed.ok, "install succeeds exactly")
equal(environment.listenerSets, 1, "one lifecycle listener")
expect(environment.integration.install().ok, "repeat install idempotent")
equal(environment.listenerSets, 1, "repeat install does not replace listener")
expect(exact(environment.integration.status(), { ok = true, installed = true }), "status surface exact")
local installedMouseUp = environment.ProgressBar.onMouseUp
local installedRemoveTooltip = environment.ProgressBar.removeTooltip
expect(installedRemoveTooltip == vanillaRemoveTooltip,
    "vanilla tooltip-removal ownership remains unpatched")

local player = { identity = "exact-player" }
local axe = makeBar(environment, "Axe", { player = player })
local view = makeView(environment, 0, { axe }, true)
local dockedParent = view.parent
local dockedOuter = view.outer
expect(type(view.parent.drawText) == "function", "containing parent exposes ordinary left text drawing")
expect(type(view.parent.drawTextRight) == "function", "containing parent exposes ordinary right text drawing")
equal(view.parent.drawTextRightStatic, nil, "live-faithful parent exposes no static text helper")
view:prerender()
equal(environment.priorPrerender, 1, "first prerender chains vanilla once")
equal(environment.prerenderGeometry[1].y, 58, "two-row header inset is applied before vanilla prerender")
equal(environment.prerenderGeometry[1].height, 250, "the full fixed-header offset is reserved before vanilla stencil")
equal(view.y, 58, "view moves by the exact two-row native header inset")
equal(environment.refresh[1], 1, "first visible prerender requests refresh")
equal(total(environment.stateReads), 0, "first prerender reads no owner state")
equal(total(environment.statusReads), 0, "first prerender reads no advancement status")
equal(environment.settingsReads, 0, "first prerender reads no settings")
equal(environment.modelBuilds, 0, "first prerender builds no model")

view:render()
equal(environment.priorRender, 1, "first render chains vanilla once")
equal(view.height, 250, "viewport loses the same offset by which it was moved")
equal(view.parent.height, 308, "fixed header preserves the containing panel bottom edge")
equal(view.outer.height, 328, "fixed header preserves the outer window bottom edge")
equal(view.scrollHeight, 500, "fixed header does not add phantom skill content")
equal(#view.progressBars, 1, "vanilla creates one bar")
equal(environment.buttonCreates, 1, "reconciliation creates one button")
equal(axe.children[1].enabled, false, "new button stays disabled before the first model build")
equal(environment.progressionBuilds, 1, "bar progression builds once")
equal(environment.progressionDescribes, 1, "bar progression describes once")
equal(environment.progressionInspects, 1, "bar progression inspects once")
expect(environment.buildPerk == axe.perk, "progression build receives exact perk")
expect(environment.inspectPlayer == player, "progression inspect receives exact player")
expect(environment.describeHandle == environment.inspectHandle, "describe and inspect share exact handle")
equal(total(environment.stateReads), 0, "post-render reads no state")
equal(environment.settingsReads, 0, "post-render reads no settings")

environment.now = 10
view:prerender()
equal(environment.priorPrerender, 2, "second prerender chains once")
equal(environment.stateReads[1], 1, "dirty rebuild reads owner once")
equal(environment.statusReads[1], 1, "dirty rebuild reads status once")
equal(environment.settingsReads, 1, "dirty rebuild reads settings once")
equal(environment.modelBuilds, 1, "dirty rebuild builds model once")
local firstInput = environment.buildArguments[1]
expect(exact(firstInput, { snapshot = true, allotment = true, pending = true, rows = true }),
    "model input exact")
expect(exact(firstInput.allotment, { mode = true, globalLimit = true }), "Global projection exact")
equal(firstInput.allotment.globalLimit, 6, "Global limit projected")
expect(environment.lastRawSettings.inheritanceEnabled == true
    and environment.lastRawSettings.retainedRatio == 0.5,
    "live inheritance settings shape is accepted without entering the allotment projection")
expect(environment.lastRawSettings.customSkillSurvivorXpEnabled == true
    and environment.lastRawSettings.perSkillSurvivorXpEnabled.Axe == true,
    "expanded contribution settings shape is accepted")
equal(firstInput.allotment.customSkillSurvivorXpEnabled, nil,
    "custom contribution setting does not enter the allotment projection")
equal(firstInput.allotment.perSkillSurvivorXpEnabled, nil,
    "per-skill contribution settings do not enter the allotment projection")
expect(firstInput.rows[1].perkId == "Axe" and firstInput.rows[1].currentLevel == 1
    and firstInput.rows[1].effectiveMaximum == 10, "resolved row projected")
local axeButton = axe.children[1]
expect(axeButton.enabled, "eligible button enabled")
equal(axeButton.title, "+", "native button copy")
equal(axeButton.x, 200, "button begins exactly at the vanilla bar edge")
equal(axe.width, 200 + axeButton.width, "bar expands by exactly the observed button width")
expect(axeButton.border[1] == 0.12 and axeButton.border[2] == 0.32
    and axeButton.border[3] == 0.65 and axeButton.border[4] == 0.75,
    "button retains its exact subtle blue border")
expect(string.find(axeButton.tooltip, "Advance to level 2 for 1 AP.", 1, true) ~= nil,
    "button tooltip explains cost")
equal(string.find(axeButton.tooltip, ";", 1, true), nil, "button tooltip has no semicolon")

for frame = 1, 60 do
    environment.now = 10 + frame
    view:prerender()
end
equal(environment.refresh[1], 1, "sixty frames inside one second send nothing")
equal(environment.stateReads[1], 1, "sixty frames inside one second read nothing")
equal(environment.settingsReads, 1, "sixty frames read no settings")
environment.now = 1000
view:prerender()
equal(environment.refresh[1], 2, "one-second expiry refreshes once")
equal(environment.stateReads[1], 2, "expiry performs one dirty rebuild")
environment.now = 1001
view:prerender()
equal(environment.stateReads[1], 2, "next prerender rebuilds once")
environment.now = 1100
view:prerender()
equal(environment.refresh[1], 2, "reopen inside one second reuses refresh cache")
equal(environment.stateReads[1], 2, "reopen inside one second reuses presentation cache")

local hiddenCounts = { environment.refresh[1], environment.stateReads[1], environment.settingsReads }
environment.now = 5000
equal(environment.refresh[1], hiddenCounts[1], "hidden view performs no refresh without prerender")
equal(environment.stateReads[1], hiddenCounts[2], "hidden view performs no state read")
equal(environment.settingsReads, hiddenCounts[3], "hidden view performs no settings read")

environment.now = 500
view:prerender()
equal(environment.refresh[1], 2, "backward clock sends nothing")
environment.now = 1499
view:prerender()
equal(environment.refresh[1], 2, "backward clock waits a fresh second")
environment.now = 1500
view:prerender()
equal(environment.refresh[1], 3, "fresh second after backward jump refreshes")

local reopenedEnvironment = makeEnvironment()
expect(reopenedEnvironment.integration.install().ok, "reopened integration installs")
local reopenedBar = makeBar(reopenedEnvironment, "Axe")
local reopened = makeView(reopenedEnvironment, 0, { reopenedBar }, false)
reopened:prerender()
equal(reopenedEnvironment.stateReads[1], 1, "reopened existing bars rebuild immediately")
equal(reopenedEnvironment.refresh[1], 1, "reopened view also advances refresh cadence")

local fractionalEnvironment = makeEnvironment({
    xpIntoLevel = 105.40056410233345,
    xpForNextLevel = 1200,
})
expect(fractionalEnvironment.integration.install().ok, "fractional XP integration installs")
local fractionalBar = makeBar(fractionalEnvironment, "Axe")
local fractionalView = makeView(fractionalEnvironment, 0, { fractionalBar }, false)
fractionalView:prerender()
fractionalView:render()
expect(lastDrawText(fractionalView.statusDraws, "Survivor XP: 105.4 / 1200") ~= nil,
    "Survivor XP display rounds fractional values to one decimal place")
equal(fractionalEnvironment.lastModelView.survivor.xpIntoLevel, 105.40056410233345,
    "Survivor XP cache retains exact current value")
equal(fractionalEnvironment.lastModelView.survivor.xpForNextLevel, 1200,
    "Survivor XP cache retains exact required value")

local survivorXpDisplayCases = {
    { current = 10, required = 100, display = "Survivor XP: 10 / 100" },
    { current = 10.04, required = 100, display = "Survivor XP: 10 / 100" },
    { current = 10.05, required = 100, display = "Survivor XP: 10.1 / 100" },
    {
        current = 9007199254740990,
        required = 9007199254740991,
        large = true,
    },
}
for index = 1, #survivorXpDisplayCases do
    local displayCase = survivorXpDisplayCases[index]
    local displayEnvironment = makeEnvironment({
        xpIntoLevel = displayCase.current,
        xpForNextLevel = displayCase.required,
    })
    expect(displayEnvironment.integration.install().ok,
        "Survivor XP display case installs " .. tostring(index))
    local displayBar = makeBar(displayEnvironment, "Axe")
    local displayView = makeView(displayEnvironment, 0, { displayBar }, false)
    displayView:prerender()
    displayView:render()
    if displayCase.large then
        local largeText = nil
        for drawIndex = #displayView.statusDraws, 1, -1 do
            local text = displayView.statusDraws[drawIndex].text
            if string.find(text, "Survivor XP: ", 1, true) == 1 then
                largeText = text
                break
            end
        end
        expect(largeText ~= nil and string.find(largeText, ".", 1, true) == nil,
            "safe large Survivor XP has no decimal suffix: " .. tostring(largeText))
    else
        expect(lastDrawText(displayView.statusDraws, displayCase.display) ~= nil,
            "Survivor XP display case uses the compact shared presentation " .. tostring(index))
    end
    equal(displayEnvironment.lastModelView.survivor.xpIntoLevel, displayCase.current,
        "Survivor XP display leaves the exact current snapshot unchanged " .. tostring(index))
    equal(displayEnvironment.lastModelView.survivor.xpForNextLevel, displayCase.required,
        "Survivor XP display leaves the exact required snapshot unchanged " .. tostring(index))
end

local slotBar = makeBar(environment, "Cooking", { x = 120 })
local slotView = makeView(environment, 1, { slotBar }, false)
slotView:setY(12)
environment.now = 1600
slotView:prerender()
equal(environment.stateReads[2], 1, "slot one rebuild isolated")
equal(environment.stateReads[1], 3, "slot zero read count unchanged")
equal(slotView.y, 62, "slot one keeps its independent two-row header base")
for slot = 2, 3 do
    local isolatedBar = makeBar(environment, "Slot" .. tostring(slot), { x = 120 + slot })
    local isolatedView = makeView(environment, slot, { isolatedBar }, false)
    isolatedView:setY(8 + slot)
    isolatedView:prerender()
    equal(environment.stateReads[slot + 1], 1, "slot rebuild isolated " .. tostring(slot))
    equal(environment.refresh[slot + 1], 1, "slot refresh isolated " .. tostring(slot))
    expect(isolatedBar.children[1].enabled, "slot button isolated " .. tostring(slot))
    equal(isolatedView.y, 58 + slot, "slot header geometry isolated " .. tostring(slot))
end
environment.listener(0, "owner_snapshot")
environment.now = 1601
view:prerender()
equal(environment.stateReads[1], 4, "matching listener dirties slot zero")
equal(environment.stateReads[2], 1, "listener does not dirty slot one")

axeButton:click()
equal(environment.requests[1], 1, "mouse plus sends one request")
equal(environment.lastRequest.slot, 0, "request uses view slot")
equal(environment.lastRequest.perkId, "Axe", "request uses resolved perk ID")
equal(axeButton.enabled, false, "successful request disables button before return")
axeButton:click()
equal(environment.requests[1], 1, "disabled mouse plus cannot duplicate a pending request")
axe:activate()
equal(environment.requests[1], 1, "activating the skill row does not spend AP")
equal(environment.priorActivate, 1, "skill-row activation retains vanilla seam once")
expect(slotBar.children[1].enabled, "other slot button remains enabled")
expect(environment.ProgressBar.onMouseUp == installedMouseUp, "vanilla mouse seam remains unpatched")
local requestsBeforeOutside = environment.requests[1]
axe:onMouseUp(1, 1)
equal(environment.priorMouseUp, 1, "click outside plus retains vanilla behavior")
equal(environment.requests[1], requestsBeforeOutside, "click outside plus sends no advancement")

environment.listener(0, "advancement_result")
environment.pending[1] = false
environment.now = 1602
view:prerender()
expect(axeButton.enabled, "terminal listener rebuild re-enables eligible row")
view.joypadIndex = 1
view:onJoypadDirRight()
expect(axeButton.joypadFocused, "right selects the exact plus button")
equal(environment.priorJoypadRight, 0, "handled plus focus does not escape the Skills panel")
view:onJoypadDown("A")
equal(environment.requests[1], 2, "controller A activates the focused plus once")
equal(environment.priorJoypadDown, 0, "focused plus consumes controller A")
expect(not axeButton.enabled, "controller request disables the focused plus")
view:onJoypadDown("A")
equal(environment.requests[1], 2, "disabled controller plus cannot duplicate a pending request")
environment.listener(0, "advancement_result")
environment.pending[1] = false
environment.now = 1603
view:prerender()
view:onJoypadDirLeft()
expect(not axeButton.joypadFocused, "left returns focus from plus to the skill row")
environment.requestReject = true
axeButton:click()
equal(environment.requests[1], 3, "ordinary rejection is delivered once")
expect(axeButton.enabled, "ordinary rejection does not poison control")
equal(string.find(axeButton.tooltip or "", "secret", 1, true), nil, "backend detail never leaks")

do
    local scrollEnvironment = makeEnvironment({})
    expect(scrollEnvironment.integration.install().ok, "deep-row scroll integration installs")
    local shallowBar = makeBar(scrollEnvironment, "Axe", { y = 40 })
    local deepBar = makeBar(scrollEnvironment, "Trapping", { y = 490 })
    local scrollView = makeView(scrollEnvironment, 0, { shallowBar, deepBar })
    scrollView:prerender()
    scrollView:render()
    equal(scrollView.scrollHeight, 550, "scroll range includes forty pixels below the final skill")
    scrollView.joypadIndex = 1
    scrollView.joyfocus = true
    scrollView:onJoypadDirDown()
    equal(scrollView.joypadIndex, 2, "controller selects the deep final skill")
    equal(scrollView.yScroll, -300, "controller selection uses the actual shortened viewport")
    scrollEnvironment.vanillaRenderClampsScroll = true
    scrollEnvironment.realisticScrollClamp = true
    local originalHeightSetter = rawget(scrollView, "setHeightAndParentHeight")
    local originalScrollSetter = rawget(scrollView, "setScrollHeight")
    scrollView:render()
    equal(scrollView.yScroll, -300, "controller scroll survives vanilla render clamping")
    local highlight = scrollEnvironment.joypadHighlights[#scrollEnvironment.joypadHighlights]
    equal(highlight.index, 2, "vanilla highlight follows the selected deep skill")
    equal(highlight.barY, 490, "vanilla highlight uses the selected skill row")
    equal(highlight.yScroll, -300, "vanilla highlight is drawn with the preserved controller scroll")
    equal(highlight.height, 250, "vanilla highlight uses the shortened Skills viewport")
    equal(highlight.scrollHeight, 550, "vanilla highlight uses the extended final-row scroll range")
    equal(rawget(scrollView, "setHeightAndParentHeight"), originalHeightSetter,
        "controller render restores the exact instance height setter")
    equal(rawget(scrollView, "setScrollHeight"), originalScrollSetter,
        "controller render restores the exact instance scroll-height setter")
    scrollView:setYScroll(-90)
    scrollView:render()
    equal(scrollView.yScroll, -90, "mouse-wheel scroll survives vanilla render clamping")
end

do
    local tooltipEnvironment = makeEnvironment({})
    expect(tooltipEnvironment.integration.install().ok, "tooltip refresh integration installs")
    local tooltipBar = makeBar(tooltipEnvironment, "Axe")
    local tooltipView = makeView(tooltipEnvironment, 0, { tooltipBar })
    tooltipView:prerender()
    tooltipView:render()
    expect(string.find(tooltipBar.children[1].tooltip or "", "level 2", 1, true) ~= nil,
        "initial plus tooltip uses the current target")
    tooltipBar.perk.level = 2
    tooltipBar:renderPerkRect()
    tooltipView:prerender()
    expect(string.find(tooltipBar.children[1].tooltip or "", "level 3", 1, true) ~= nil,
        "plus tooltip refreshes to the next level after advancement")

    local masteryEnvironment = makeEnvironment({})
    expect(masteryEnvironment.integration.install().ok, "mastery tooltip integration installs")
    local masteryBar = makeBar(masteryEnvironment, "Axe", { level = 9 })
    local masteryView = makeView(masteryEnvironment, 0, { masteryBar })
    masteryView:prerender()
    masteryView:render()
    equal(masteryBar.children[1].tooltip, "Master skill for 2 AP.",
        "final two-point advancement uses mastery copy")
end

axe:renderPerkRect()
equal(environment.drawOrder[1], "gold", "vanilla gold renders before overlays")
equal(#axe.draws, 5, "two targets, accounting marker, recovery span, and recovery marker draw")
equal(axe.draws[1].kind, "border", "first overlay is target outline")
equal(axe.draws[1].x, 20, "level two outline boundary")
equal(axe.draws[2].x, 60, "level four outline boundary")
equal(axe.draws[3].x, 29, "fractional high-water marker")
equal(axe.draws[4].x, 20, "red recovery starts at natural position")
equal(axe.draws[4].width, 10, "red recovery ends at high-water")
equal(axe.draws[5].x, 19, "recovery current-position line tracks natural position")
expect(axe.draws[1].alpha == 0.95 and axe.draws[1].width == 20 and axe.draws[1].height == 20,
    "target border alpha and geometry remain unchanged")
expect(axe.draws[3].alpha == 0.85 and axe.draws[3].width == 2 and axe.draws[3].height == 20,
    "accounting-position line alpha and thickness remain unchanged")
expect(axe.draws[4].alpha == 0.75 and axe.draws[4].height == 2,
    "recovery span alpha and thickness remain unchanged")
expect(axe.draws[5].alpha == 0.90 and axe.draws[5].width == 2 and axe.draws[5].height == 20,
    "recovery-position line alpha and thickness remain unchanged")
expect(axe.draws[1].r == 0.35 and axe.draws[1].g == 0.72 and axe.draws[1].b == 1.00,
    "target border uses exact brighter blue")
expect(axe.draws[3].r == 0.12 and axe.draws[3].g == 0.32 and axe.draws[3].b == 0.65,
    "accounting-position line uses exact darker blue")
expect(axe.draws[4].r == 0.95 and axe.draws[4].g == 0.25 and axe.draws[4].b == 0.25,
    "recovery span uses exact brighter red")
expect(axe.draws[5].r == 0.45 and axe.draws[5].g == 0.08 and axe.draws[5].b == 0.08,
    "recovery-position line uses exact darker red")

axe.mouseX = 20
axe:updateTooltip()
equal(environment.priorTooltip, 1, "vanilla tooltip runs once")
expect(string.find(axe.message, "Vanilla tooltip", 1, true) == 1, "vanilla tooltip retained")
expect(string.find(axe.message, "50 lost skill XP left", 1, true) ~= nil, "recovery amount uses high-water minus natural XP")
expect(string.find(axe.message, "No Survivor XP during recovery.", 1, true) ~= nil, "recovery consequence appended")
equal(string.find(axe.message, "natural skill XP left", 1, true), nil, "red recovery wins blue overlap")
equal(string.find(axe.message, ";", 1, true), nil, "row tooltip has no semicolon")

axe.mouseX = 30
axe:updateTooltip()
expect(string.find(axe.message, "50 lost skill XP left", 1, true) ~= nil,
    "final red outer edge belongs to recovery region")
axe.mouseX = 35
axe:updateTooltip()
expect(string.find(axe.message, "100 natural skill XP left", 1, true) ~= nil,
    "first target uses its target-specific remaining XP")
expect(string.find(axe.message, "Catch up to free this advancement slot.", 1, true) ~= nil,
    "target consequence appended")
equal(string.find(axe.message, "Advance to level", 1, true), nil,
    "skill tooltip never receives button action copy")
equal(string.find(axe.message, "Not enough AP", 1, true), nil,
    "skill tooltip never receives button reason copy")
equal(string.find(axe.message, "lost skill XP left", 1, true), nil,
    "blue-only region omits recovery copy")
axe.mouseX = 45
axe:updateTooltip()
equal(axe.message, "Vanilla tooltip", "gap outside exact overlay regions appends no SLA line")
axe.mouseX = 60
axe:updateTooltip()
expect(string.find(axe.message, "300 natural skill XP left", 1, true) ~= nil,
    "second target uses its own remaining XP")
axe.mouseX = 80
axe:updateTooltip()
expect(string.find(axe.message, "300 natural skill XP left", 1, true) ~= nil,
    "final blue outer edge belongs to last visible target")

local boundaryEnvironment = makeEnvironment()
boundaryEnvironment.activeTargets = {
    { targetLevel = 2, targetPosition = 200 },
    { targetLevel = 3, targetPosition = 300 },
}
boundaryEnvironment.naturalPosition = 100
boundaryEnvironment.highWaterPosition = 100
expect(boundaryEnvironment.integration.install().ok, "boundary integration installs")
local boundaryBar = makeBar(boundaryEnvironment, "Axe")
local boundaryView = makeView(boundaryEnvironment, 0, { boundaryBar })
boundaryView:prerender()
boundaryBar.mouseX = 20
boundaryBar:updateTooltip()
expect(string.find(boundaryBar.message, "100 natural skill XP left", 1, true) ~= nil,
    "target left edge is inclusive")
boundaryBar.mouseX = 39.999
boundaryBar:updateTooltip()
expect(string.find(boundaryBar.message, "100 natural skill XP left", 1, true) ~= nil,
    "target interior remains owned by first region")
boundaryBar.mouseX = 40
boundaryBar:updateTooltip()
expect(string.find(boundaryBar.message, "200 natural skill XP left", 1, true) ~= nil,
    "adjacent exact boundary belongs only to next target")
equal(string.find(boundaryBar.message, "100 natural skill XP left", 1, true), nil,
    "adjacent exact boundary excludes previous target")
boundaryBar.mouseX = 60
boundaryBar:updateTooltip()
expect(string.find(boundaryBar.message, "200 natural skill XP left", 1, true) ~= nil,
    "last adjacent target owns its final outer edge")
boundaryBar.mouseX = 60.001
boundaryBar:updateTooltip()
equal(boundaryBar.message, "Vanilla tooltip", "position beyond final outer edge is outside")

local paidUpEnvironment = makeEnvironment()
paidUpEnvironment.activeTargets = {}
paidUpEnvironment.naturalPosition = 150
paidUpEnvironment.highWaterPosition = 150
expect(paidUpEnvironment.integration.install().ok, "paid-up integration installs")
local paidUpBar = makeBar(paidUpEnvironment, "Axe", { mouseX = 25 })
local paidUpView = makeView(paidUpEnvironment, 0, { paidUpBar })
paidUpView:prerender()
paidUpBar:renderPerkRect()
equal(#paidUpBar.draws, 0, "paid-up tracked record draws no SLA overlay")
paidUpBar:updateTooltip()
equal(paidUpBar.message, "Vanilla tooltip", "paid-up tracked record keeps vanilla-only tooltip")

local redOnlyEnvironment = makeEnvironment()
redOnlyEnvironment.activeTargets = {}
redOnlyEnvironment.naturalPosition = 100
redOnlyEnvironment.highWaterPosition = 150
expect(redOnlyEnvironment.integration.install().ok, "red-only recovery integration installs")
local redOnlyBar = makeBar(redOnlyEnvironment, "Axe", { mouseX = 20 })
local redOnlyView = makeView(redOnlyEnvironment, 0, { redOnlyBar })
redOnlyView:prerender()
redOnlyBar:renderPerkRect()
equal(#redOnlyBar.draws, 2, "red-only recovery draws span and position without blue overlays")
expect(redOnlyBar.draws[1].r == 0.95 and redOnlyBar.draws[1].g == 0.25
    and redOnlyBar.draws[1].b == 0.25 and redOnlyBar.draws[1].width == 10,
    "red-only recovery retains the red span")
expect(redOnlyBar.draws[2].r == 0.45 and redOnlyBar.draws[2].g == 0.08
    and redOnlyBar.draws[2].b == 0.08 and redOnlyBar.draws[2].x == 19,
    "red-only recovery retains the red position marker")
redOnlyBar:updateTooltip()
expect(string.find(redOnlyBar.message, "50 lost skill XP left", 1, true) ~= nil,
    "red-only recovery retains its recovery tooltip")

local cleanupEnvironment = makeEnvironment()
expect(cleanupEnvironment.integration.install().ok, "tooltip cleanup integration installs")
local cleanupBar = makeBar(cleanupEnvironment, "Axe")
local cleanupView = makeView(cleanupEnvironment, 0, { cleanupBar })
cleanupView:prerender()
local cleanupButton = cleanupBar.children[1]
local cleanupTooltip = cleanupButton.tooltip
cleanupBar.message = "Vanilla level ten tooltip"
cleanupButton.mouseOver = true
cleanupBar:renderPerkRect()
equal(cleanupEnvironment.priorRemoveTooltip, 1,
    "exact hovered SLA button removes the stale vanilla tooltip once")
equal(cleanupBar.message, nil, "hovered SLA button clears only the parent bar tooltip")
cleanupBar:renderPerkRect()
equal(cleanupEnvironment.priorRemoveTooltip, 1,
    "hovered SLA button does not repeat removal after the stale tooltip is cleared")
equal(cleanupButton.tooltip, cleanupTooltip, "tooltip cleanup preserves the button tooltip")
cleanupButton:click()
equal(cleanupEnvironment.requests[1], 1, "tooltip cleanup preserves button activation")

local disabledCleanupEnvironment = makeEnvironment({ reason = "insufficient_ap" })
expect(disabledCleanupEnvironment.integration.install().ok, "disabled tooltip cleanup integration installs")
local disabledCleanupBar = makeBar(disabledCleanupEnvironment, "Axe")
local disabledCleanupView = makeView(disabledCleanupEnvironment, 0, { disabledCleanupBar })
disabledCleanupView:prerender()
local disabledCleanupButton = disabledCleanupBar.children[1]
expect(not disabledCleanupButton.enabled, "disabled tooltip cleanup button stays disabled")
disabledCleanupBar.message = "Vanilla level ten tooltip"
disabledCleanupButton.mouseOver = true
disabledCleanupBar:renderPerkRect()
equal(disabledCleanupEnvironment.priorRemoveTooltip, 1,
    "disabled hovered SLA button removes the stale vanilla tooltip once")
equal(disabledCleanupBar.message, nil, "disabled hovered SLA button clears the parent bar tooltip")

local freeCleanupEnvironment = makeEnvironment({ mode = "Free" })
expect(freeCleanupEnvironment.integration.install().ok, "Free tooltip cleanup integration installs")
local freeCleanupBar = makeBar(freeCleanupEnvironment, "Axe")
local freeCleanupView = makeView(freeCleanupEnvironment, 0, { freeCleanupBar })
freeCleanupView:prerender()
freeCleanupBar.message = "Vanilla level ten tooltip"
freeCleanupBar.children[1].mouseOver = true
freeCleanupBar:renderPerkRect()
equal(freeCleanupEnvironment.priorRemoveTooltip, 1,
    "Free mode hovered SLA button removes the stale vanilla tooltip once")
equal(freeCleanupBar.message, nil, "Free mode cleanup does not need an SLA overlay")

local noCleanupEnvironment = makeEnvironment()
expect(noCleanupEnvironment.integration.install().ok, "non-hover tooltip cleanup integration installs")
local noCleanupBar = makeBar(noCleanupEnvironment, "Axe", { mouseX = 35 })
local noCleanupView = makeView(noCleanupEnvironment, 0, { noCleanupBar })
noCleanupView:prerender()
local unrelatedChild = { isMouseOver = function() return true end }
noCleanupBar.children[#noCleanupBar.children + 1] = unrelatedChild
noCleanupBar.message = "Vanilla level ten tooltip"
noCleanupBar:renderPerkRect()
equal(noCleanupEnvironment.priorRemoveTooltip, 0,
    "only the exact SLA button hover removes a tooltip")
equal(noCleanupBar.message, "Vanilla level ten tooltip",
    "non-hovered SLA button retains the vanilla tooltip")
noCleanupBar:updateTooltip()
expect(string.find(noCleanupBar.message, "Vanilla tooltip", 1, true) == 1,
    "non-hover cleanup keeps vanilla cell tooltip composition")
expect(string.find(noCleanupBar.message, "100 natural skill XP left", 1, true) ~= nil,
    "non-hover cleanup keeps SLA cell tooltip composition")

local missingHoverEnvironment = makeEnvironment()
expect(missingHoverEnvironment.integration.install().ok, "missing-hover cleanup integration installs")
local missingHoverBar = makeBar(missingHoverEnvironment, "Axe")
local missingHoverView = makeView(missingHoverEnvironment, 0, { missingHoverBar })
missingHoverView:prerender()
local missingHoverButton = missingHoverBar.children[1]
missingHoverButton.isMouseOver = nil
missingHoverBar.message = "Vanilla level ten tooltip"
expect(pcall(function() missingHoverBar:renderPerkRect() end),
    "missing button hover capability is contained")
expect(not missingHoverButton.enabled, "missing button hover capability disables SLA view")
equal(missingHoverEnvironment.priorRemoveTooltip, 0,
    "missing button hover capability cannot remove a tooltip")
missingHoverBar.message = "Vanilla tooltip after failure"
missingHoverBar:renderPerkRect()
equal(missingHoverEnvironment.priorRemoveTooltip, 0,
    "missing button hover capability does not retry tooltip mutation")
equal(missingHoverBar.message, "Vanilla tooltip after failure",
    "disabled failure boundary preserves later vanilla tooltip state")

local throwingHoverEnvironment = makeEnvironment()
expect(throwingHoverEnvironment.integration.install().ok, "throwing-hover cleanup integration installs")
local throwingHoverBar = makeBar(throwingHoverEnvironment, "Axe")
local throwingHoverView = makeView(throwingHoverEnvironment, 0, { throwingHoverBar })
throwingHoverView:prerender()
local throwingHoverButton = throwingHoverBar.children[1]
throwingHoverButton.isMouseOver = function() error("hover boom") end
expect(pcall(function() throwingHoverBar:renderPerkRect() end),
    "throwing button hover capability is contained")
expect(not throwingHoverButton.enabled, "throwing button hover capability disables SLA view")
equal(throwingHoverEnvironment.priorRemoveTooltip, 0,
    "throwing button hover capability cannot remove a tooltip")

local throwingRemovalEnvironment = makeEnvironment()
expect(throwingRemovalEnvironment.integration.install().ok, "throwing-removal cleanup integration installs")
local throwingRemovalBar = makeBar(throwingRemovalEnvironment, "Axe")
local throwingRemovalView = makeView(throwingRemovalEnvironment, 0, { throwingRemovalBar })
throwingRemovalView:prerender()
local throwingRemovalButton = throwingRemovalBar.children[1]
throwingRemovalButton.mouseOver = true
throwingRemovalEnvironment.removeTooltipThrows = true
throwingRemovalBar.message = "Vanilla level ten tooltip"
expect(pcall(function() throwingRemovalBar:renderPerkRect() end),
    "throwing tooltip removal capability is contained")
expect(not throwingRemovalButton.enabled, "throwing tooltip removal capability disables SLA view")
equal(throwingRemovalEnvironment.priorRemoveTooltip, 1,
    "throwing tooltip removal capability is called once")
throwingRemovalBar.message = "Vanilla tooltip after removal failure"
throwingRemovalBar:renderPerkRect()
equal(throwingRemovalEnvironment.priorRemoveTooltip, 1,
    "throwing tooltip removal capability does not retry mutation")
equal(throwingRemovalBar.message, "Vanilla tooltip after removal failure",
    "disabled removal failure boundary preserves later vanilla tooltip state")

local formatCases = {
    { targetPosition = 100, expected = "0 natural skill XP left", label = "zero" },
    { targetPosition = 100.125, expected = "0.13 natural skill XP left", label = "ordinary decimal" },
    { targetPosition = 100.005, expected = "<0.01 natural skill XP left", label = "positive below hundredth" },
    { targetPosition = 100.3000000000007, expected = "0.3 natural skill XP left", label = "subtraction noise" },
}
for index = 1, #formatCases do
    local formatCase = formatCases[index]
    local formatEnvironment = makeEnvironment()
    formatEnvironment.activeTargets = {
        { targetLevel = 2, targetPosition = formatCase.targetPosition },
    }
    formatEnvironment.naturalPosition = 100
    formatEnvironment.highWaterPosition = 100
    expect(formatEnvironment.integration.install().ok, formatCase.label .. " formatter integration installs")
    local formatBar = makeBar(formatEnvironment, "Axe", { mouseX = 25 })
    local formatView = makeView(formatEnvironment, 0, { formatBar })
    formatView:prerender()
    formatBar:updateTooltip()
    expect(string.find(formatBar.message, formatCase.expected, 1, true) ~= nil,
        formatCase.label .. " remaining XP format")
    equal(string.find(formatBar.message, "e+", 1, true), nil,
        formatCase.label .. " format avoids scientific notation")
end

local buttonsBeforeRepeatedRender = environment.buttonCreates
view:render()
local stableViewWidth = view.width
local stableParentWidth = view.parent.width
local stableOuterWidth = view.outer.width
local stableBarWidth = axe.width
local stableViewY = view.y
local stableViewHeight = view.height
local stableParentHeight = view.parent.height
local stableOuterHeight = view.outer.height
local stableStatusY = view.statusDraws[#view.statusDraws].screenY
local rowScreenY = view.parent.y + view.y + view:getYScroll() + axe.y
view:setYScroll(-60)
local statusDrawsBeforeScroll = #view.statusDraws
view:render()
equal(#view.statusDraws, statusDrawsBeforeScroll + 4,
    "ordinary containing parent receives both fixed status rows")
equal(view.statusDraws[#view.statusDraws].screenY, stableStatusY,
    "status screen position stays fixed while skill rows scroll")
equal(view.parent.y + view.y + view:getYScroll() + axe.y, rowScreenY - 60,
    "vanilla rows retain scrolling below the fixed status")
local readsBeforeStable = {
    environment.refresh[1], environment.stateReads[1], environment.settingsReads,
}
for repeatRender = 1, 60 do view:render() end
equal(view.width, stableViewWidth, "view width never grows cumulatively")
equal(view.parent.width, stableParentWidth, "parent width never grows cumulatively")
equal(view.outer.width, stableOuterWidth, "complete ancestor width never grows cumulatively")
equal(axe.width, stableBarWidth, "bar width never grows cumulatively")
equal(view.y, stableViewY, "view header inset never grows cumulatively")
equal(view.height, stableViewHeight, "viewport height never shrinks cumulatively")
equal(view.parent.height, stableParentHeight, "parent height never grows cumulatively")
equal(view.outer.height, stableOuterHeight, "outer height never grows cumulatively")
equal(environment.refresh[1], readsBeforeStable[1], "render stability sends no refresh")
equal(environment.stateReads[1], readsBeforeStable[2], "render stability reads no owner state")
equal(environment.settingsReads, readsBeforeStable[3], "render stability reads no settings")
equal(environment.buttonCreates, buttonsBeforeRepeatedRender, "repeated renders create no duplicate buttons")
equal(lastDrawText(view.statusDraws, "Survivor Level: 5").x, 4,
    "repeated renders keep the first left label at the fixed window margin")
equal(lastDrawText(view.statusDraws, "Survivor XP: 10 / 100").x, 4,
    "repeated renders keep the second left label at the fixed window margin")
equal(view.width - (axe.x + axe.width), 100, "expanded bar preserves measured vanilla right gutter")
equal(view.parent.width, view.x + view.width, "view width propagates absolutely to parent")
equal(view.outer.width, view.parent.x + view.parent.width, "width propagates through every ancestor")
expect(#view.statusDraws > 0, "status draws on first category row")
equal(lastDrawText(view.statusDraws, "Survivor Level: 5").y, 18,
    "first status row uses fixed parent-local coordinates")
do
    local survivorLevel = lastDrawText(view.statusDraws, "Survivor Level: 5")
    local availableAp = lastDrawText(view.statusDraws, "AP: 3")
    local advancementSlots = lastDrawText(view.statusDraws, "Advancement Slots: 2/6")
    local survivorXp = lastDrawText(view.statusDraws, "Survivor XP: 10 / 100")
    equal(survivorLevel.text, "Survivor Level: 5", "ready snapshot binds exact Survivor Level")
    equal(survivorLevel.x, 4, "Survivor Level binds four logical pixels from the left edge")
    equal(availableAp.kind, "right", "AP binds to the first-row right edge")
    equal(availableAp.x, view.parent.width - 4,
        "AP binds four logical pixels from the containing-window right edge")
    equal(advancementSlots.kind, "right", "Global slots bind to the second-row right edge")
    equal(advancementSlots.x, view.parent.width - 4,
        "Global slots bind four logical pixels from the containing-window right edge")
    expect(survivorXp ~= nil, "second row binds exact cached Survivor XP")
    expect(survivorLevel ~= nil and survivorXp ~= nil and advancementSlots ~= nil
        and availableAp ~= nil,
        "expanded provider settings preserve Level, XP, Slots, and AP header model")
    equal(survivorXp.kind, "left", "Survivor XP binds to the second-row left edge")
    equal(survivorXp.x, 4,
        "Survivor XP binds four logical pixels from the left edge")
    equal(survivorXp.y, 38, "Survivor XP uses the second native-height row")
end

do
local narrowEnvironment = makeEnvironment()
narrowEnvironment.measureScale = 10
expect(narrowEnvironment.integration.install().ok, "narrow-view integration installs")
local narrowBar = makeBar(narrowEnvironment, "Axe", { x = 50, width = 100, height = 10 })
local narrowView = makeView(narrowEnvironment, 0, { narrowBar })
narrowView.width = 200
narrowView.vanillaWidth = 200
narrowView.parent.width = 220
narrowView:prerender()
narrowView:render()
    local narrowAp = lastDrawText(narrowView.statusDraws, "AP: 3")
    local requiredFirstRow = 4 + (#"Survivor Level: 5" * 10) + (#"  " * 10)
        + (#"AP: 3" * 10) + 4
    local requiredSecondRow = 4 + (#"Advancement Slots: 2/6" * 10) + (#"  " * 10)
        + (#"Survivor XP: 10 / 100" * 10) + 4
    local requiredWindowWidth = math.max(requiredFirstRow, requiredSecondRow)
    equal(narrowAp.x, narrowView.parent.width - 4,
        "Global right labels retain the four-pixel containing-window margin")
    equal(narrowView.width, requiredWindowWidth,
        "both Global rows use the collision-safe measured minimum")
    expect(narrowView.width > 200 and narrowView.parent.width > 220,
        "narrow view and containing window widen for measured copy")
    local narrowLevel = lastDrawText(narrowView.statusDraws, "Survivor Level: 5")
    local narrowXp = lastDrawText(narrowView.statusDraws, "Survivor XP: 10 / 100")
    local narrowSlots = lastDrawText(narrowView.statusDraws, "Advancement Slots: 2/6")
    expect(narrowLevel.x + #narrowLevel.text * 10 + #"  " * 10
        <= narrowAp.x - #narrowAp.text * 10, "minimum-width first row does not overlap")
    expect(narrowXp.x + #narrowXp.text * 10 + #"  " * 10
        <= narrowSlots.x - #narrowSlots.text * 10, "minimum-width second row does not overlap")

local originalSecondRowCopy = translations.IGUI_SLA_StatusSurvivorXp
translations.IGUI_SLA_StatusSurvivorXp = string.rep("W", 500) .. " %1 / %2"
local wideSecondRowEnvironment = makeEnvironment()
expect(wideSecondRowEnvironment.integration.install().ok, "wide second-row integration installs")
local wideSecondRowBar = makeBar(wideSecondRowEnvironment, "Axe")
local wideSecondRowView = makeView(wideSecondRowEnvironment, 0, { wideSecondRowBar })
wideSecondRowView:prerender()
wideSecondRowView:render()
local wideSecondRowText = formatText("IGUI_SLA_StatusSurvivorXp", 10, 100)
    equal(wideSecondRowView.width,
        4 + #"Advancement Slots: 2/6" + #"  " + #wideSecondRowText + 4,
        "wider left-aligned XP remains collision-safe beside Global slots")
translations.IGUI_SLA_StatusSurvivorXp = originalSecondRowCopy

local largeHeaderEnvironment = makeEnvironment({
    survivorLevel = 123456,
    spentAp = 111111,
    availableAp = 12345,
    xpIntoLevel = 987654.3,
    xpForNextLevel = 999999,
})
largeHeaderEnvironment.measureScale = 4
expect(largeHeaderEnvironment.integration.install().ok, "large header integration installs")
local largeHeaderBar = makeBar(largeHeaderEnvironment, "Axe", { x = 50, width = 100 })
local largeHeaderView = makeView(largeHeaderEnvironment, 0, { largeHeaderBar })
largeHeaderView.width = 200
largeHeaderView.vanillaWidth = 200
largeHeaderView:prerender()
largeHeaderView:render()
local largeLevel = lastDrawText(largeHeaderView.statusDraws, "Survivor Level: 123456")
local largeAp = lastDrawText(largeHeaderView.statusDraws, "AP: 12345")
local largeSlots = lastDrawText(largeHeaderView.statusDraws, "Advancement Slots: 2/6")
local largeXp = lastDrawText(largeHeaderView.statusDraws, "Survivor XP: 987654.3 / 999999")
expect(largeLevel ~= nil and largeAp ~= nil and largeSlots ~= nil and largeXp ~= nil,
    "large representative values render on their exact rows")
expect(largeLevel.x + #largeLevel.text * 4 + #"  " * 4 <= largeAp.x - #largeAp.text * 4,
    "large first-row values do not overlap")
expect(largeXp.x + #largeXp.text * 4 + #"  " * 4 <= largeSlots.x - #largeSlots.text * 4,
    "large second-row values do not overlap")

for _, malformedLevelCase in ipairs({ "missing", "malformed" }) do
    local malformedLevelEnvironment = makeEnvironment()
    malformedLevelEnvironment.omitSurvivorLevel = malformedLevelCase == "missing"
    malformedLevelEnvironment.malformedSurvivorLevel = malformedLevelCase == "malformed"
    expect(malformedLevelEnvironment.integration.install().ok,
        malformedLevelCase .. " Survivor Level integration installs")
    local malformedLevelBar = makeBar(malformedLevelEnvironment, "Axe")
    local malformedLevelView = makeView(malformedLevelEnvironment, 0, { malformedLevelBar })
    malformedLevelView:prerender()
    equal(#malformedLevelView.statusDraws, 0,
        malformedLevelCase .. " Survivor Level renders no partial header")
    expect(not malformedLevelBar.children[1].enabled,
        malformedLevelCase .. " Survivor Level fails presentation closed")
end
end

local resolutionEnvironment = makeEnvironment()
expect(resolutionEnvironment.integration.install().ok, "resolution integration installs")
local resolutionBar = makeBar(resolutionEnvironment, "Axe")
local resolutionView = makeView(resolutionEnvironment, 0, { resolutionBar })
resolutionView:prerender()
resolutionView:render()
resolutionView:setWidth(460)
resolutionView:render()
equal(resolutionView.width, 480, "resolution rebuild rebases from the new vanilla view width")
equal(resolutionView.width - (resolutionBar.x + resolutionBar.width), 160,
    "resolution rebuild preserves its newly measured vanilla gutter")
equal(resolutionView.parent.width, 480, "resolution width propagates to parent")
equal(resolutionView.outer.width, 480, "resolution width propagates to outer ancestor")
resolutionView:render()
equal(resolutionView.width, 480, "resolution rebase remains non-cumulative")

local oldButton = axeButton
local buttonsBeforeReplacement = environment.buttonCreates
local replacement = makeBar(environment, "Axe", { player = player })
view.progressBars = { replacement }
view:render()
equal(environment.buttonCreates, buttonsBeforeReplacement + 1, "replacement creates one new button")
equal(oldButton.onclick, nil, "replaced bar callback removed")
local requestsBeforeStale = environment.requests[1]
axe:activate()
equal(environment.requests[1], requestsBeforeStale, "stale bar no longer requests")
view.progressBars = {}
view:render()
equal(replacement.children[1].onclick, nil, "collapse removes stale callback")
local expanded = makeBar(environment, "Axe")
view.progressBars = { expanded }
view:render()
equal(#expanded.children, 1, "expanded bar gets one button")

local tornOuter = makeParent(300, 0, nil, 0, 0)
local tornParent = makeParent(300, 0, tornOuter, 0, 24)
view.parent = tornParent
view:setY(16)
view:render()
expect(tornParent.width > 300, "torn-off parent identity widens independently")
equal(view.width, stableViewWidth, "torn-off reconciliation remains non-cumulative")
equal(view.y, 66, "torn-off view rebases two header rows from its new vanilla position")
equal(tornParent.height, 316, "torn-off parent preserves its rebased bottom edge")
equal(tornOuter.height, 340, "torn-off outer window preserves its rebased bottom edge")
equal(lastDrawText(tornParent.statusDraws, "Survivor Level: 5").y, 26,
    "torn-off first status row uses the new parent-local position")
equal(lastDrawText(tornParent.statusDraws, "Survivor XP: 10 / 100").y, 46,
    "torn-off second status row follows one native row below")
view.parent = dockedParent
view:setY(8)
view:render()
equal(view.y, 58, "reattached view reapplies the two-row header inset")
equal(dockedParent.height, 308, "reattached panel restores its original bottom edge")
equal(dockedOuter.height, 328, "reattached outer window restores its original bottom edge")

local unsupported = makeBar(environment, "Unsupported", { unsupported = true })
view.progressBars = { unsupported }
view:render()
equal(#unsupported.children, 0, "unsupported row remains vanilla-only")
unsupported:renderPerkRect()
equal(#unsupported.draws, 0, "unsupported row draws no SLA overlay")

local badCurve = makeBar(environment, "BadCurve", { badCurve = true })
view.progressBars = { badCurve }
view:render()
equal(#badCurve.children, 0, "malformed curve remains vanilla-only")

local hostilePerk = makeBar(environment, "Hostile")
hostilePerk.perk = setmetatable({}, { __index = function() error("lookup boom") end })
view.progressBars = { hostilePerk }
local hostileOk = pcall(function() view:render() end)
expect(hostileOk, "throwing Java-like perk lookup is contained")
equal(#hostilePerk.children, 0, "throwing perk lookup stays vanilla-only")

local aboveTenEnvironment = makeEnvironment()
aboveTenEnvironment.activeTargets = {
    { targetLevel = 10, targetPosition = 1000 },
    { targetLevel = 11, targetPosition = 1100 },
}
expect(aboveTenEnvironment.integration.install().ok, "above-ten integration installs")
local aboveTen = makeBar(aboveTenEnvironment, "LongCurve", { maximum = 12 })
local aboveTenView = makeView(aboveTenEnvironment, 0, { aboveTen })
aboveTenView:prerender()
aboveTen:renderPerkRect()
equal(#aboveTen.draws, 4, "level eleven is not fabricated beyond ten cells")
equal(aboveTen.draws[1].x, 180, "level ten uses last vanilla cell")

local invalidOverlayEnvironment = makeEnvironment()
invalidOverlayEnvironment.highWaterPosition = 5000
expect(invalidOverlayEnvironment.integration.install().ok, "invalid overlay integration installs")
local invalidOverlayBar = makeBar(invalidOverlayEnvironment, "Axe")
local invalidOverlayView = makeView(invalidOverlayEnvironment, 0, { invalidOverlayBar })
invalidOverlayView:prerender()
equal(invalidOverlayBar.children[1].enabled, false, "out-of-curve positions disable SLA control")
invalidOverlayBar:renderPerkRect()
equal(#invalidOverlayBar.draws, 0, "out-of-curve positions suppress overlays")

local enabledRowCases = {
    { field = "incompleteEnabled", label = "enabled row missing target and cost" },
    { field = "enabledMissingCost", label = "enabled row missing AP cost" },
    { field = "enabledCurrentTarget", label = "enabled row target not above current" },
    { field = "enabledAboveMaximum", label = "enabled row target above maximum" },
    { field = "enabledZeroCost", label = "enabled row with nonpositive AP cost" },
    { field = "enabledAtMaximum", label = "enabled row at effective maximum" },
}
for index = 1, #enabledRowCases do
    local rowCase = enabledRowCases[index]
    local rowEnvironment = makeEnvironment()
    rowEnvironment[rowCase.field] = true
    expect(rowEnvironment.integration.install().ok, rowCase.label .. " integration installs")
    local rowBar = makeBar(rowEnvironment, "Axe")
    local rowView = makeView(rowEnvironment, 0, { rowBar })
    rowView:prerender()
    equal(rowEnvironment.modelBuilds, 1, rowCase.label .. " reaches model boundary")
    expect(not rowBar.children[1].enabled, rowCase.label .. " fails closed")
    rowBar.children[1]:click()
    equal(rowEnvironment.requests[1], 0, rowCase.label .. " cannot request advancement")
end

local modes = { "PerSkill", "Free" }
for index = 1, #modes do
    local modeEnvironment = makeEnvironment({ mode = modes[index] })
    expect(modeEnvironment.integration.install().ok, modes[index] .. " integration installs")
    local modeBar = makeBar(modeEnvironment, "Axe")
    local modeView = makeView(modeEnvironment, 0, { modeBar })
    modeView:prerender()
    local allotment = modeEnvironment.buildArguments[1].allotment
    if modes[index] == "PerSkill" then
        expect(exact(allotment, { mode = true, perSkillDefault = true, perSkillOverrides = true }),
            "Per Skill projection exact")
        equal(allotment.perSkillOverrides.Axe, 4, "Per Skill override projected")
        expect(allotment.perSkillOverrides ~= modeEnvironment.lastRawSettings.perSkillOverrides,
            "Per Skill override projection detaches")
        allotment.perSkillOverrides.Axe = 9
        equal(modeEnvironment.lastRawSettings.perSkillOverrides.Axe, 4,
            "model input mutation cannot alter provider result")
        expect(string.find(modeBar.children[1].tooltip, "Advancement Slots: 1/4.", 1, true) ~= nil,
            "Per Skill count is in row tooltip")
        modeBar.mouseX = 35
        modeBar:updateTooltip()
        equal(string.find(modeBar.message, "Advancement Slots", 1, true), nil,
            "Per Skill slot count never enters skill tooltip")
    else
        expect(exact(allotment, { mode = true }), "Free projection exact")
        equal(string.find(modeBar.children[1].tooltip, "Advancement Slots", 1, true), nil,
            "Free tooltip omits limits")
        modeBar:renderPerkRect()
        equal(#modeBar.draws, 0, "Free draws no accounting overlay")
        modeBar.mouseX = 25
        modeBar:updateTooltip()
        equal(modeBar.message, "Vanilla tooltip", "Free skill tooltip appends no accounting copy")
    end
    modeView:render()
    expect(lastDrawText(modeView.statusDraws, "Survivor Level: 5") ~= nil,
        modes[index] .. " first row includes Survivor Level")
    expect(lastDrawText(modeView.statusDraws, "AP: 3") ~= nil,
        modes[index] .. " first row includes AP")
    expect(lastDrawText(modeView.statusDraws, "Survivor XP: 10 / 100") ~= nil,
        modes[index] .. " second row includes exact Survivor XP")
    equal(lastDrawText(modeView.statusDraws, "Advancement Slots: 2/6"), nil,
        modes[index] .. " header omits a nonexistent global slot total")
    equal(lastDrawText(modeView.statusDraws, "AP: 3").kind, "right",
        modes[index] .. " AP stays right aligned")
    equal(lastDrawText(modeView.statusDraws, "Survivor XP: 10 / 100").kind, "left",
        modes[index] .. " Survivor XP stays left aligned")
    equal(modeView.width, 420, modes[index] .. " width uses max control edge plus captured gutter")
end

local zeroNormalizationEnvironment = makeEnvironment({ fitnessStrengthNormalization = 0 })
expect(zeroNormalizationEnvironment.integration.install().ok,
    "zero-normalization integration installs")
local zeroNormalizationBar = makeBar(zeroNormalizationEnvironment, "Axe")
local zeroNormalizationView = makeView(zeroNormalizationEnvironment, 0, { zeroNormalizationBar })
zeroNormalizationView:prerender()
equal(zeroNormalizationEnvironment.settingsReads, 1,
    "zero normalization is read once")
equal(zeroNormalizationEnvironment.modelBuilds, 1,
    "zero normalization reaches the Skills model")
expect(zeroNormalizationBar.children[1].enabled,
    "zero normalization preserves valid Skills controls")

local negativeNormalizationEnvironment = makeEnvironment({ fitnessStrengthNormalization = -0.01 })
expect(negativeNormalizationEnvironment.integration.install().ok,
    "negative-normalization integration installs")
local negativeNormalizationBar = makeBar(negativeNormalizationEnvironment, "Axe")
local negativeNormalizationView = makeView(negativeNormalizationEnvironment, 0, { negativeNormalizationBar })
negativeNormalizationView:prerender()
equal(negativeNormalizationEnvironment.modelBuilds, 0,
    "negative normalization fails before the Skills model")
expect(not negativeNormalizationBar.children[1].enabled,
    "negative normalization disables SLA presentation")

local reasons = {
    "pending",
    "maximum_mismatch",
    "at_maximum",
    "red_recovery",
    "insufficient_ap",
    "allotment_disabled",
    "allotment_capacity",
}
for index = 1, #reasons do
    local reasonEnvironment = makeEnvironment({ reason = reasons[index] })
    expect(reasonEnvironment.integration.install().ok, "reason integration installs " .. reasons[index])
    local reasonBar = makeBar(reasonEnvironment, "Axe")
    local reasonView = makeView(reasonEnvironment, 0, { reasonBar })
    reasonView:prerender()
    local tooltip = reasonBar.children[1].tooltip
    expect(type(tooltip) == "string" and #tooltip > 0, "reason tooltip exists " .. reasons[index])
    equal(string.find(tooltip, ";", 1, true), nil, "reason tooltip has no semicolon " .. reasons[index])
    equal(string.find(tooltip, "secret", 1, true), nil, "reason tooltip omits detail " .. reasons[index])
    expect(not reasonBar.children[1].enabled, "reason disables button " .. reasons[index])
    if reasons[index] == "insufficient_ap" then
        equal(tooltip, "Not enough AP.", "disabled plus owns exact insufficient-AP copy")
        reasonBar.mouseX = 35
        reasonBar:updateTooltip()
        equal(string.find(reasonBar.message, "Not enough AP.", 1, true), nil,
            "vanilla skill tooltip omits insufficient-AP copy")
    end
end

do
    local terminalCases = {
        {
            name = "no AP",
            result = { ok = true, applied = false, requestId = "result-1", perkId = "Axe",
                code = "no_ap", detail = "secret terminal detail" },
            copy = "Not enough AP.",
        },
        {
            name = "effective maximum",
            result = { ok = true, applied = false, requestId = "result-2", perkId = "Axe",
                code = "at_maximum", detail = "secret terminal detail" },
            copy = "This skill is already at its maximum.",
        },
        {
            name = "red recovery",
            result = { ok = true, applied = false, requestId = "result-3", perkId = "Axe",
                code = "red_recovery", detail = "secret terminal detail" },
            copy = "Recover natural XP before advancing again.",
        },
        {
            name = "stale revision",
            result = { ok = true, applied = false, requestId = "result-4", perkId = "Axe",
                code = "stale_revision", detail = "secret terminal detail" },
            copy = "Survivor data changed. Refresh and try again.",
        },
        {
            name = "uncommitted send failure",
            result = { ok = false, requestId = "result-5", perkId = "Axe",
                code = "send_failed", detail = "secret terminal detail", committed = false },
            copy = "The advancement request could not be sent. Try again.",
        },
        {
            name = "generic rejection",
            result = { ok = true, applied = false, requestId = "result-6", perkId = "Axe",
                code = "future_backend_code", detail = "secret terminal detail" },
            copy = "The advancement failed. Refresh and try again.",
        },
        {
            name = "committed snapshot rejection",
            result = { ok = false, applied = true, requestId = "result-7", perkId = "Axe",
                code = "snapshot_rejected", detail = "secret terminal detail", committed = true,
                apCost = 1, mastered = false },
            copy = "The advancement may have applied. Refresh before trying again.",
        },
        {
            name = "uncommitted upstream snapshot failure",
            result = { ok = false, applied = false, requestId = "result-7b", perkId = "Axe",
                code = "snapshot_rejected", detail = "secret terminal detail", committed = false,
                upstreamCode = "stale_revision", upstreamDetail = "secret upstream detail" },
            copy = "The advancement failed. Refresh and try again.",
        },
        {
            name = "committed precedence",
            result = { ok = false, requestId = "result-8", perkId = "Axe",
                code = "no_ap", detail = "secret terminal detail", committed = true },
            copy = "The advancement may have applied. Refresh before trying again.",
            forbidden = "Not enough AP.",
        },
    }
    for index = 1, #terminalCases do
        local terminalCase = terminalCases[index]
        local terminalEnvironment = makeEnvironment()
        terminalEnvironment.terminalResults[1] = terminalCase.result
        expect(terminalEnvironment.integration.install().ok,
            "terminal result integration installs " .. terminalCase.name)
        local terminalBar = makeBar(terminalEnvironment, "Axe")
        local terminalView = makeView(terminalEnvironment, 0, { terminalBar })
        terminalView:prerender()
        local tooltip = terminalBar.children[1].tooltip or ""
        expect(string.find(tooltip, terminalCase.copy, 1, true) ~= nil,
            "matching perk gets terminal copy " .. terminalCase.name)
        equal(string.find(tooltip, "secret terminal detail", 1, true), nil,
            "terminal detail never leaks " .. terminalCase.name)
        equal(string.find(tooltip, "secret upstream detail", 1, true), nil,
            "terminal upstream detail never leaks " .. terminalCase.name)
        equal(string.find(tooltip, "future_backend_code", 1, true), nil,
            "terminal code never leaks " .. terminalCase.name)
        equal(string.find(tooltip, ";", 1, true), nil,
            "terminal tooltip has no semicolon " .. terminalCase.name)
        if terminalCase.forbidden ~= nil then
            equal(string.find(tooltip, terminalCase.forbidden, 1, true), nil,
                "committed copy takes precedence over code-specific copy")
        end
    end

    local appliedEnvironment = makeEnvironment()
    appliedEnvironment.terminalResults[1] = {
        ok = true,
        applied = true,
        requestId = "result-applied",
        perkId = "Axe",
        apCost = 1,
        mastered = false,
        snapshotAccepted = true,
    }
    expect(appliedEnvironment.integration.install().ok, "applied terminal integration installs")
    local appliedBar = makeBar(appliedEnvironment, "Axe")
    local appliedView = makeView(appliedEnvironment, 0, { appliedBar })
    appliedView:prerender()
    equal(appliedBar.children[1].tooltip, "Advance to level 2 for 1 AP.",
        "successful applied terminal adds no failure copy")

    local appliedStaleEnvironment = makeEnvironment()
    appliedStaleEnvironment.terminalResults[1] = {
        ok = true,
        applied = true,
        requestId = "result-applied-stale",
        perkId = "Axe",
        apCost = 2,
        mastered = true,
        snapshotAccepted = false,
        snapshotCode = "stale_snapshot",
    }
    expect(appliedStaleEnvironment.integration.install().ok,
        "applied stale-snapshot terminal integration installs")
    local appliedStaleBar = makeBar(appliedStaleEnvironment, "Axe")
    local appliedStaleView = makeView(appliedStaleEnvironment, 0, { appliedStaleBar })
    appliedStaleView:prerender()
    equal(appliedStaleBar.children[1].tooltip, "Advance to level 2 for 1 AP.",
        "applied terminal with stale snapshot acceptance remains silent")

    local staleSnapshotEnvironment = makeEnvironment()
    staleSnapshotEnvironment.terminalResults[1] = {
        ok = true,
        applied = false,
        requestId = "result-stale-snapshot",
        perkId = "Axe",
        code = "stale_revision",
        detail = "secret terminal detail",
        snapshotAccepted = false,
        snapshotCode = "stale_snapshot",
    }
    expect(staleSnapshotEnvironment.integration.install().ok,
        "stale-rejection snapshot terminal integration installs")
    local staleSnapshotBar = makeBar(staleSnapshotEnvironment, "Axe")
    local staleSnapshotView = makeView(staleSnapshotEnvironment, 0, { staleSnapshotBar })
    staleSnapshotView:prerender()
    expect(string.find(staleSnapshotBar.children[1].tooltip or "",
        "Survivor data changed. Refresh and try again.", 1, true) ~= nil,
        "stale rejection with detached snapshot fields gets stale copy")

    local malformedTerminals = {
        {
            name = "missing request ID",
            result = { ok = true, applied = false, perkId = "Axe",
                code = "no_ap", detail = "secret terminal detail" },
        },
        {
            name = "missing detail",
            result = { ok = true, applied = false, requestId = "malformed-2", perkId = "Axe",
                code = "no_ap" },
        },
        {
            name = "extra upstream detail",
            result = { ok = false, requestId = "malformed-3", perkId = "Axe",
                code = "send_failed", detail = "secret terminal detail", committed = false,
                upstreamDetail = "secret upstream detail" },
        },
        {
            name = "contradictory applied committed",
            result = { ok = true, applied = true, requestId = "malformed-4", perkId = "Axe",
                apCost = 1, mastered = false, snapshotAccepted = true, committed = true },
        },
        {
            name = "contradictory accepted snapshot code",
            result = { ok = true, applied = true, requestId = "malformed-5", perkId = "Axe",
                apCost = 1, mastered = false, snapshotAccepted = true,
                snapshotCode = "stale_snapshot" },
        },
        {
            name = "contradictory applied mastery",
            result = { ok = true, applied = true, requestId = "malformed-6", perkId = "Axe",
                apCost = 2, mastered = false, snapshotAccepted = true },
        },
        {
            name = "contradictory snapshot failure mastery",
            result = { ok = false, applied = true, requestId = "malformed-7", perkId = "Axe",
                code = "snapshot_rejected", detail = "secret terminal detail", committed = true,
                apCost = 1, mastered = true },
        },
        {
            name = "snapshot fields on non-stale rejection",
            result = { ok = true, applied = false, requestId = "malformed-8", perkId = "Axe",
                code = "no_ap", detail = "secret terminal detail", snapshotAccepted = false,
                snapshotCode = "stale_snapshot" },
        },
        {
            name = "unrecognized snapshot code",
            result = { ok = true, applied = true, requestId = "malformed-9", perkId = "Axe",
                apCost = 1, mastered = false, snapshotAccepted = false,
                snapshotCode = "snapshot_failed" },
        },
        {
            name = "nonprintable detail",
            result = { ok = true, applied = false, requestId = "malformed-10", perkId = "Axe",
                code = "no_ap", detail = "line one\nline two" },
        },
        {
            name = "overlong detail",
            result = { ok = true, applied = false, requestId = "malformed-11", perkId = "Axe",
                code = "no_ap", detail = string.rep("x", 161) },
        },
        {
            name = "unsafe upstream code",
            result = { ok = false, applied = false, requestId = "malformed-12", perkId = "Axe",
                code = "snapshot_rejected", detail = "secret terminal detail", committed = false,
                upstreamCode = "not safe", upstreamDetail = "secret upstream detail" },
        },
    }
    for index = 1, #malformedTerminals do
        local malformedCase = malformedTerminals[index]
        local malformedEnvironment = makeEnvironment()
        malformedEnvironment.terminalResults[1] = malformedCase.result
        expect(malformedEnvironment.integration.install().ok,
            "malformed terminal integration installs " .. malformedCase.name)
        local malformedBar = makeBar(malformedEnvironment, "Axe")
        local malformedView = makeView(malformedEnvironment, 0, { malformedBar })
        malformedView:prerender()
        equal(malformedEnvironment.statusReads[1], 1,
            "malformed terminal status is consumed once " .. malformedCase.name)
        equal(malformedEnvironment.modelBuilds, 0,
            "malformed terminal fails before model build " .. malformedCase.name)
        expect(not malformedBar.children[1].enabled,
            "malformed terminal disables SLA presentation " .. malformedCase.name)
        equal(malformedBar.children[1].tooltip, nil,
            "malformed terminal renders no copy " .. malformedCase.name)
    end

    local isolationEnvironment = makeEnvironment()
    isolationEnvironment.terminalResults[1] = {
        ok = true,
        applied = false,
        requestId = "result-isolation",
        perkId = "Axe",
        code = "stale_revision",
        detail = "secret terminal detail",
    }
    expect(isolationEnvironment.integration.install().ok, "terminal isolation integration installs")
    local matchingBar = makeBar(isolationEnvironment, "Axe")
    local otherPerkBar = makeBar(isolationEnvironment, "Cooking")
    local matchingView = makeView(isolationEnvironment, 0, { matchingBar, otherPerkBar })
    matchingView:prerender()
    expect(string.find(matchingBar.children[1].tooltip or "",
        "Survivor data changed. Refresh and try again.", 1, true) ~= nil,
        "matching perk receives retained terminal")
    equal(string.find(otherPerkBar.children[1].tooltip or "",
        "Survivor data changed. Refresh and try again.", 1, true), nil,
        "other perk receives no retained terminal")
    local otherSlotBar = makeBar(isolationEnvironment, "Axe")
    local otherSlotView = makeView(isolationEnvironment, 1, { otherSlotBar })
    otherSlotView:prerender()
    equal(string.find(otherSlotBar.children[1].tooltip or "",
        "Survivor data changed. Refresh and try again.", 1, true), nil,
        "other local slot receives no retained terminal")

    local listenerEnvironment = makeEnvironment()
    expect(listenerEnvironment.integration.install().ok, "terminal listener integration installs")
    local listenerBar = makeBar(listenerEnvironment, "Axe")
    local listenerView = makeView(listenerEnvironment, 0, { listenerBar })
    listenerView:prerender()
    local readsBeforeListener = listenerEnvironment.statusReads[1]
    listenerEnvironment.terminalResults[1] = {
        ok = true,
        applied = false,
        requestId = "result-listener",
        perkId = "Axe",
        code = "stale_revision",
        detail = "secret terminal detail",
    }
    listenerEnvironment.listener(0, "advancement_result")
    equal(listenerEnvironment.statusReads[1], readsBeforeListener,
        "lifecycle callback performs no advancement-status read")
    listenerEnvironment.now = 1
    listenerView:prerender()
    equal(listenerEnvironment.statusReads[1], readsBeforeListener + 1,
        "next visible prerender consumes lifecycle dirty status")
    expect(string.find(listenerBar.children[1].tooltip or "",
        "Survivor data changed. Refresh and try again.", 1, true) ~= nil,
        "lifecycle dirty rebuild updates terminal tooltip")

    local cadenceEnvironment = makeEnvironment()
    expect(cadenceEnvironment.integration.install().ok, "terminal cadence integration installs")
    local cadenceBar = makeBar(cadenceEnvironment, "Axe")
    local cadenceView = makeView(cadenceEnvironment, 0, { cadenceBar })
    cadenceView:prerender()
    local cadenceReads = cadenceEnvironment.statusReads[1]
    cadenceEnvironment.terminalResults[1] = {
        ok = false,
        requestId = "result-cadence",
        perkId = "Axe",
        code = "send_failed",
        detail = "secret terminal detail",
        committed = false,
    }
    cadenceEnvironment.now = 999
    cadenceView:prerender()
    equal(cadenceEnvironment.statusReads[1], cadenceReads,
        "retained send failure waits for ordinary refresh deadline")
    cadenceEnvironment.now = 1000
    cadenceView:prerender()
    equal(cadenceEnvironment.statusReads[1], cadenceReads + 1,
        "ordinary one-second refresh consumes retained send failure")
    expect(string.find(cadenceBar.children[1].tooltip or "",
        "The advancement request could not be sent. Try again.", 1, true) ~= nil,
        "retained send failure appears without a completion callback")

    local retryEnvironment = makeEnvironment()
    retryEnvironment.terminalResults[1] = {
        ok = true,
        applied = false,
        requestId = "result-before-retry",
        perkId = "Axe",
        code = "stale_revision",
        detail = "secret terminal detail",
    }
    expect(retryEnvironment.integration.install().ok, "terminal retry integration installs")
    local retryBar = makeBar(retryEnvironment, "Axe")
    local retryView = makeView(retryEnvironment, 0, { retryBar })
    retryView:prerender()
    local retryButton = retryBar.children[1]
    expect(string.find(retryButton.tooltip or "",
        "Survivor data changed. Refresh and try again.", 1, true) ~= nil,
        "old terminal is visible before accepted retry")
    local retryStatusReads = retryEnvironment.statusReads[1]
    retryButton:click()
    equal(retryEnvironment.requests[1], 1, "accepted retry sends once")
    expect(not retryButton.enabled, "accepted retry immediately disables the button")
    equal(retryEnvironment.statusReads[1], retryStatusReads,
        "accepted retry clears presentation without another status read")
    equal(string.find(retryButton.tooltip or "",
        "Survivor data changed. Refresh and try again.", 1, true), nil,
        "accepted retry synchronously clears the old terminal")
    retryButton:click()
    equal(retryEnvironment.requests[1], 1,
        "new pending state still deduplicates activation after clearing old terminal")
end

for _, mutation in ipairs({ "custom", "map", "value" }) do
    local contributionFailureEnvironment = makeEnvironment({
        contributionSettingsMutation = mutation,
    })
    expect(contributionFailureEnvironment.integration.install().ok,
        "malformed contribution settings integration installs: " .. mutation)
    local contributionFailureBar = makeBar(contributionFailureEnvironment, "Axe")
    local contributionFailureView = makeView(
        contributionFailureEnvironment, 0, { contributionFailureBar }, false)
    contributionFailureView:prerender()
    contributionFailureView:render()
    equal(contributionFailureEnvironment.modelBuilds, 0,
        "malformed contribution settings fail before model build: " .. mutation)
    expect(not contributionFailureBar.children[1].enabled,
        "malformed contribution settings disable SLA presentation: " .. mutation)
    equal(#contributionFailureView.statusDraws, 0,
        "malformed contribution settings suppress the SLA header: " .. mutation)
end

local failureEnvironment = makeEnvironment()
expect(failureEnvironment.integration.install().ok, "failure integration installs")
local failureBar = makeBar(failureEnvironment, "Axe")
local failureView = makeView(failureEnvironment, 0, { failureBar })
failureEnvironment.malformedSettings = true
failureView:prerender()
equal(failureEnvironment.settingsReads, 1, "malformed settings read once")
expect(not failureBar.children[1].enabled, "malformed settings disables SLA presentation")
for frame = 1, 20 do failureEnvironment.now = frame; failureView:prerender() end
equal(failureEnvironment.settingsReads, 1, "malformed settings cannot retry every frame")
failureEnvironment.malformedSettings = false
failureEnvironment.listener(0, "owner_snapshot")
failureEnvironment.now = 30
failureView:prerender()
equal(failureEnvironment.settingsReads, 2, "legitimate dirty mark permits retry")
expect(failureBar.children[1].enabled, "valid retry restores presentation")

failureEnvironment.privateModelField = true
failureEnvironment.listener(0, "owner_snapshot")
failureEnvironment.now = 31
failureView:prerender()
expect(not failureBar.children[1].enabled, "private model result fails closed")
failureEnvironment.privateModelField = false
for frame = 32, 40 do failureEnvironment.now = frame; failureView:prerender() end
equal(failureEnvironment.modelBuilds, 2, "malformed model result is consumed")

local pendingEnvironment = makeEnvironment()
pendingEnvironment.refreshPending = true
expect(pendingEnvironment.integration.install().ok, "pending refresh integration installs")
local pendingBar = makeBar(pendingEnvironment, "Axe")
local pendingView = makeView(pendingEnvironment, 0, { pendingBar }, true)
pendingView:prerender()
for frame = 1, 30 do pendingEnvironment.now = frame; pendingView:prerender() end
equal(pendingEnvironment.refresh[1], 1, "pending refresh coalesces within deadline")

local clockEnvironment = makeEnvironment()
expect(clockEnvironment.integration.install().ok, "clock integration installs")
local clockBar = makeBar(clockEnvironment, "Axe")
local clockView = makeView(clockEnvironment, 0, { clockBar })
clockEnvironment.clockThrows = true
local beforePrior = clockEnvironment.priorPrerender
local readsBeforeClockFailure = {
    clockEnvironment.refresh[1], clockEnvironment.stateReads[1], clockEnvironment.settingsReads,
}
local clockOk = pcall(function() clockView:prerender() end)
expect(clockOk, "clock failure is contained")
equal(clockEnvironment.priorPrerender, beforePrior + 1, "wrapper failure never repeats vanilla")
equal(clockView.y, 8, "permanent disable restores captured vanilla Y")
equal(clockView.height, 300, "permanent disable restores captured vanilla height")
equal(clockView.parent.height, 308, "permanent disable restores parent height")
equal(clockView.outer.height, 328, "permanent disable restores outer height")
equal(clockEnvironment.refresh[1], readsBeforeClockFailure[1], "disable path sends no refresh")
equal(clockEnvironment.stateReads[1], readsBeforeClockFailure[2], "disable path reads no owner state")
equal(clockEnvironment.settingsReads, readsBeforeClockFailure[3], "disable path reads no settings")

local drawFailureEnvironment = makeEnvironment()
expect(drawFailureEnvironment.integration.install().ok, "parent draw failure integration installs")
local drawFailureBar = makeBar(drawFailureEnvironment, "Axe")
local drawFailureView = makeView(drawFailureEnvironment, 0, { drawFailureBar })
drawFailureView:prerender()
drawFailureView.parent.throwDraw = true
local drawFailureOk = pcall(function() drawFailureView:render() end)
expect(drawFailureOk, "throwing ordinary parent draw is contained")
equal(drawFailureEnvironment.priorRender, 1, "throwing parent draw retains one vanilla render")
equal(#drawFailureView.statusDraws, 0, "throwing parent records no status draw")
expect(not drawFailureBar.children[1].enabled, "throwing parent disables only SLA control")
equal(drawFailureView.y, 8, "throwing parent restores vanilla Y")
equal(drawFailureView.height, 300, "throwing parent restores vanilla height")
equal(drawFailureView.width, 400, "throwing parent restores vanilla width")
equal(drawFailureBar.width, 200, "throwing parent restores vanilla bar width")
drawFailureView:render()
equal(drawFailureEnvironment.priorRender, 2, "disabled SLA view keeps later vanilla rendering")
equal(#drawFailureView.statusDraws, 0, "disabled SLA view does not retry parent drawing")

local ownershipEnvironment = makeEnvironment()
expect(ownershipEnvironment.integration.install().ok, "ownership integration installs")
ownershipEnvironment.CharacterInfo.render = function() end
local ownership = ownershipEnvironment.integration.install()
equal(ownership.ok, false, "lost wrapper ownership fails closed")
equal(ownership.code, "hook_ownership_lost", "lost ownership code")
equal(ownershipEnvironment.listenerSets, 1, "lost ownership does not replace listener")

local vanillaThrowEnvironment = makeEnvironment()
expect(vanillaThrowEnvironment.integration.install().ok, "vanilla throw integration installs")
local vanillaThrowView = makeView(vanillaThrowEnvironment, 0, {})
local vanillaThrowHeightSetter = rawget(vanillaThrowView, "setHeightAndParentHeight")
local vanillaThrowScrollSetter = rawget(vanillaThrowView, "setScrollHeight")
vanillaThrowView.throwRender = true
local renderOk = pcall(function() vanillaThrowView:render() end)
expect(not renderOk, "vanilla render throw propagates")
equal(vanillaThrowEnvironment.priorRender, 1, "throwing vanilla render called once")
equal(rawget(vanillaThrowView, "setHeightAndParentHeight"), vanillaThrowHeightSetter,
    "throwing vanilla render restores the exact instance height setter")
equal(rawget(vanillaThrowView, "setScrollHeight"), vanillaThrowScrollSetter,
    "throwing vanilla render restores the exact instance scroll-height setter")

local invalidLauncherDependencies = {}
for key, value in pairs(environment.dependencies) do invalidLauncherDependencies[key] = value end
invalidLauncherDependencies.adminLauncher = {
    install = function() return { ok = true } end,
    status = function() return { ok = true, installed = true } end,
    isAvailable = function() return true end,
}
local invalidLauncher = Build42SkillsUi.create(invalidLauncherDependencies)
equal(invalidLauncher.ok, false, "incomplete admin launcher fails closed")
equal(invalidLauncher.code, "invalid_dependencies", "incomplete admin launcher failure code")

local adminEnvironment = makeEnvironment({ adminLauncher = true })
equal(adminEnvironment.adminInstalls, 0, "admin launcher creation is inert")
expect(adminEnvironment.integration.install().ok, "composite Skills and admin integration installs")
equal(adminEnvironment.adminInstalls, 1, "composite install delegates to admin exactly once")
expect(adminEnvironment.integration.install().ok, "composite reload install is idempotent")
equal(adminEnvironment.adminInstalls, 1, "composite reload does not reinstall admin")
local adminBar = makeBar(adminEnvironment, "Axe")
local adminView = makeView(adminEnvironment, 2, { adminBar })
adminView:prerender()
adminView:render()
equal(adminEnvironment.lastAdminAvailabilitySlot, 2, "launcher visibility preserves exact Skills slot")
equal(#adminView.parent.children, 2, "one outboard Admin and one wheel surface are created")
local adminButton = adminView.parent.children[1]
local adminWheelSurface = adminView.parent.children[2]
equal(adminButton.title, "Admin", "admin launcher uses localized compact label")
expect(adminButton.visible and adminButton.enabled,
    "prerender-finalized debug launcher is visible and enabled before child rendering")
local adminAp = lastDrawText(adminView.statusDraws, "AP: 3")
local adminXp = lastDrawText(adminView.statusDraws, "Survivor XP: 10 / 100")
local adminSlots = lastDrawText(adminView.statusDraws, "Advancement Slots: 2/6")
expect(adminAp ~= nil and adminAp.x == adminView.x + adminView.width - 4,
    "first-row AP stays bound to the Skills panel right edge")
expect(adminXp ~= nil and adminXp.x == 4,
    "second-row Survivor XP stays bound to the Skills panel left edge")
expect(adminSlots ~= nil and adminSlots.x == adminView.x + adminView.width - 4,
    "second-row Advancement Slots stay bound to the Skills panel right edge")
equal(adminButton.x, adminView.x + adminView.width + 4,
    "Admin begins four logical pixels outside the Skills panel right edge")
expect(adminButton.x > adminAp.x and adminButton.x + adminButton.width <= adminView.parent.width,
    "expanded parent keeps the outboard Admin unclipped and clear of header copy")
expect(adminView.parent.width <= adminView.outer.width,
    "outboard Admin remains inside the propagated window hierarchy")
expect(adminView.parent:canRouteMouseTo(adminButton),
    "expanded parent routes mouse input to the visible outboard Admin")
equal(adminButton.y, 18, "Admin uses the first native-height row")
expect(adminWheelSurface.visible and adminWheelSurface.javaConsumeMouseEvents == false,
    "transparent outboard gutter forwards wheel without consuming other mouse events")
equal(rawget(adminWheelSurface, "setConsumeMouseEvents"), nil,
    "production-shaped wheel surface omits the nonexistent Lua consume-events seam")
equal(adminWheelSurface.x, adminView.x + adminView.width,
    "wheel surface begins at the exact Skills right edge")
equal(adminWheelSurface.y, adminButton.y + adminButton.height,
    "wheel surface begins immediately below Admin")
equal(adminWheelSurface.width,
    adminButton.x + adminButton.width + 4 - adminWheelSurface.x,
    "wheel surface covers only the leased outboard strip")
equal(adminWheelSurface.height, adminView.parent.height - adminWheelSurface.y,
    "wheel surface ends at the containing panel bottom")
adminView:onMouseWheel(1)
equal(adminEnvironment.wheelDeltas[#adminEnvironment.wheelDeltas], 1,
    "wheel inside Skills uses the captured active scroll path")
expect(adminWheelSurface:onMouseWheel(-2), "outboard gutter consumes a forwarded wheel event")
equal(adminEnvironment.wheelDeltas[#adminEnvironment.wheelDeltas], -2,
    "outboard gutter forwards the exact wheel delta")
expect(adminButton:onMouseWheel(3), "Admin button forwards wheel to Skills")
equal(adminEnvironment.wheelDeltas[#adminEnvironment.wheelDeltas], 3,
    "Admin button forwards the exact wheel delta")
local stableAdminX = adminButton.x
adminView:render()
equal(adminButton.x, stableAdminX, "repeated render keeps Admin right-margin placement stable")
local visibleTransitionsBeforeTabs = adminView.visibleTransitions
local buttonCreatesBeforeTabs = adminEnvironment.buttonCreates
adminView:setVisible(false)
expect(not adminButton.visible and not adminButton.enabled,
    "Admin hides at the exact Skills visibility transition")
expect(not adminWheelSurface.visible, "outboard wheel surface hides with Skills")
local wheelReadsWhileHidden = adminEnvironment.priorMouseWheel
expect(not adminWheelSurface:onMouseWheel(1), "hidden outboard gutter does not consume wheel")
expect(not adminButton:onMouseWheel(1), "hidden Admin does not consume wheel")
equal(adminEnvironment.priorMouseWheel, wheelReadsWhileHidden,
    "hidden outboard controls restore world-wheel routing")
equal(adminView.parent.width, adminView.x + adminView.width,
    "hiding Skills immediately releases the shared tab-panel width")
equal(adminView.outer.width, adminView.parent.x + adminView.parent.width,
    "hiding Skills immediately releases the containing-window width")
expect(not adminView.parent:canRouteMouseTo(adminButton),
    "hidden Admin is excluded from parent mouse routing")
equal(#adminView.parent.children, 2, "leaving Skills creates no additional outboard controls")
adminButton:click()
equal(#adminEnvironment.adminOpens, 0, "stale hidden Admin click cannot open the panel")
adminView:setVisible(true)
expect(adminButton.visible and adminButton.enabled,
    "Admin returns at the exact Skills visibility transition")
equal(adminView.parent.width, adminButton.x + adminButton.width + 4,
    "showing Skills immediately reacquires only the outboard width")
for _, tabName in ipairs({ "Info", "Health", "Protection", "Temperature", "Custom" }) do
    adminView:setVisible(false)
    expect(not adminButton.visible and not adminButton.enabled,
        "Admin hides while " .. tabName .. " is the active non-Skills tab")
    adminButton:click()
    adminView:setVisible(true)
    expect(adminButton.visible and adminButton.enabled,
        "Admin returns from " .. tabName .. " without changing authorization")
end
equal(adminView.visibleTransitions, visibleTransitionsBeforeTabs + 12,
    "owned visibility wrapper chains every vanilla tab transition exactly once")
equal(adminEnvironment.buttonCreates, buttonCreatesBeforeTabs,
    "tab transitions create no duplicate UI controls")
equal(#adminEnvironment.adminOpens, 0, "tab switching opens no admin panel")
local visibleApX = lastDrawText(adminView.statusDraws, "AP: 3").x
local visibleXpX = adminXp.x
adminButton:click()
equal(#adminEnvironment.adminOpens, 1, "admin launcher activates once")
equal(adminEnvironment.adminOpens[1], 2, "admin launcher activation preserves exact slot")
adminEnvironment.adminAvailable = false
adminView:setVisible(false)
adminView:setVisible(true)
expect(not adminButton.visible and not adminButton.enabled,
    "launcher disappears and disables on an authorized visibility transition")
equal(adminView.parent.width, adminView.x + adminView.width,
    "authorization loss immediately releases the outboard parent width")
equal(adminView.outer.width, adminView.parent.x + adminView.parent.width,
    "authorization loss immediately releases the outboard ancestor width")
adminView:render()
equal(lastDrawText(adminView.statusDraws, "AP: 3").x, visibleApX,
    "first-row label does not move when Admin disappears")
equal(lastDrawText(adminView.statusDraws, "Survivor XP: 10 / 100").x, visibleXpX,
    "second-row label does not move when Admin disappears")
equal(adminView.parent.width, adminView.x + adminView.width,
    "unavailable Admin leaves no unused outboard width after layout")
adminButton:click()
equal(#adminEnvironment.adminOpens, 1, "hidden launcher cannot activate")
equal(adminEnvironment.adminRequests, 0, "Skills launcher never calls lifecycle admin request")
equal(adminEnvironment.adminStatusReads, 0, "Skills launcher never reads lifecycle admin status")
adminEnvironment.adminAvailable = true
adminView:setVisible(false)
adminView:setVisible(true)
equal(adminView.parent.width, adminButton.x + adminButton.width + 4,
    "authorization transition immediately restores the outboard mouse-routing bounds")
expect(adminView.parent:canRouteMouseTo(adminButton),
    "newly authorized Admin is mouse reachable before the next render")
adminEnvironment.adminInstalled = false
local lostAdminHook = adminEnvironment.integration.install()
equal(lostAdminHook.ok, false, "lost admin hook ownership fails composite closed")
equal(lostAdminHook.code, "hook_ownership_lost", "lost admin ownership code")

local throwingVisibilityEnvironment = makeEnvironment({ adminLauncher = true })
expect(throwingVisibilityEnvironment.integration.install().ok,
    "throwing visibility integration installs")
local throwingVisibilityBar = makeBar(throwingVisibilityEnvironment, "Axe")
local throwingVisibilityView = makeView(throwingVisibilityEnvironment, 0, { throwingVisibilityBar })
local vanillaSetVisible = rawget(throwingVisibilityView, "setVisible")
throwingVisibilityView:prerender()
throwingVisibilityView:render()
local throwingVisibilityButton = throwingVisibilityView.parent.children[1]
local ownedSetVisible = rawget(throwingVisibilityView, "setVisible")
expect(ownedSetVisible ~= vanillaSetVisible, "Skills UI owns the exact per-view visibility seam")
throwingVisibilityView.throwSetVisible = true
local visibilityCalled, visibilityError = pcall(function() throwingVisibilityView:setVisible(false) end)
expect(not visibilityCalled and visibilityError == "vanilla setVisible",
    "throwing vanilla visibility transition propagates unchanged")
expect(not throwingVisibilityButton.visible and not throwingVisibilityButton.enabled,
    "throwing visibility transition hides and disables Admin before propagation")
equal(rawget(throwingVisibilityView, "setVisible"), vanillaSetVisible,
    "throwing visibility transition restores the exact prior seam")
equal(throwingVisibilityView.y, 8, "throwing visibility transition restores vanilla header geometry")
equal(throwingVisibilityView.parent.width,
    throwingVisibilityView.x + throwingVisibilityView.width,
    "disabled view releases the outboard parent width")
equal(throwingVisibilityView.outer.width,
    throwingVisibilityView.parent.x + throwingVisibilityView.parent.width,
    "disabled view releases the outboard ancestor width")
throwingVisibilityButton:click()
equal(#throwingVisibilityEnvironment.adminOpens, 0,
    "throwing visibility transition leaves no stale Admin activation")

local lostVisibilityEnvironment = makeEnvironment({ adminLauncher = true })
expect(lostVisibilityEnvironment.integration.install().ok, "lost visibility integration installs")
local lostVisibilityBar = makeBar(lostVisibilityEnvironment, "Axe")
local lostVisibilityView = makeView(lostVisibilityEnvironment, 0, { lostVisibilityBar })
local lostVanillaSetVisible = rawget(lostVisibilityView, "setVisible")
lostVisibilityView:prerender()
lostVisibilityView:render()
local lostVisibilityButton = lostVisibilityView.parent.children[1]
lostVisibilityView:prerender()
expect(lostVisibilityButton.visible and lostVisibilityButton.enabled,
    "owned visibility launcher is live before ownership changes")
rawset(lostVisibilityView, "setVisible", lostVanillaSetVisible)
lostVisibilityView:render()
expect(lostVisibilityButton.visible and lostVisibilityButton.enabled,
    "render consumes prerender-decided visibility without mid-frame ownership cleanup")
lostVisibilityView:prerender()
expect(not lostVisibilityButton.visible and not lostVisibilityButton.enabled,
    "next prerender fails lost visibility-wrapper ownership closed before child rendering")
lostVisibilityButton:click()
equal(#lostVisibilityEnvironment.adminOpens, 0,
    "lost visibility-wrapper ownership leaves no stale Admin activation")

do
    local reparentEnvironment = makeEnvironment({ adminLauncher = true })
    expect(reparentEnvironment.integration.install().ok, "reparented Admin integration installs")
    local reparentBar = makeBar(reparentEnvironment, "Axe")
    local reparentView = makeView(reparentEnvironment, 0, { reparentBar })
    reparentView:prerender()
    reparentView:render()
    reparentView:prerender()
    local oldParent = reparentView.parent
    local oldButton = oldParent.children[1]
    local oldWheelSurface = oldParent.children[2]
    local newOuter = makeParent(450, 328, nil, 0, 0)
    local newParent = makeParent(450, 308, newOuter, 0, 20)
    reparentView.parent = newParent
    reparentView:setY(8)
    reparentView:render()
    reparentView:prerender()
    equal(#oldParent.children, 0, "parent replacement removes the old outboard Admin child")
    equal(oldParent.width, reparentView.x + reparentView.width,
        "next prerender restores the old shared parent's width before child rendering")
    equal(oldParent.parent.width, oldParent.x + oldParent.width,
        "next prerender restores the old ancestor's width before child rendering")
    expect(not oldButton.visible and oldButton.onclick == nil and oldButton.target == nil,
        "removed outboard Admin is hidden and has no stale callback")
    expect(not oldWheelSurface.visible and oldWheelSurface.onMouseWheel == nil,
        "removed outboard wheel surface is hidden and has no stale callback")
    equal(#newParent.children, 2,
        "parent replacement creates one Admin and one wheel surface on the live parent")
    expect(newParent:canRouteMouseTo(newParent.children[1]),
        "replacement parent routes mouse input only to the live Admin")
end

do
    local edgeEnvironment = makeEnvironment({ adminLauncher = true })
    expect(edgeEnvironment.integration.install().ok, "right-edge Admin integration installs")
    local edgeBar = makeBar(edgeEnvironment, "Axe")
    local edgeView = makeView(edgeEnvironment, 0, { edgeBar })
    edgeView.outer.keepOnScreen = true
    edgeView.outer.screenWidth = 1000
    edgeView.outer.x = 580
    edgeView:prerender()
    local edgeButton = edgeView.parent.children[1]
    equal(edgeView.outer.width, 448,
        "first prerender leases the exact outboard width before child rendering")
    equal(edgeView.outer.x, 552,
        "first prerender applies vanilla keep-on-screen before child rendering")
    expect(edgeButton.visible and edgeButton.enabled,
        "right-edge Admin becomes visible only after prerender reserves its geometry")
    edgeBar:renderPerkRect()
    edgeView:render()
    edgeButton:render()
    equal(edgeEnvironment.progressRootXs[#edgeEnvironment.progressRootXs], 552,
        "Java-child-shaped progress rendering retains the leased root X")
    equal(edgeEnvironment.vanillaRootXs[#edgeEnvironment.vanillaRootXs], 552,
        "vanilla ISCharacterInfo rendering retains the same leased root X")
    for index = #edgeView.statusDraws - 3, #edgeView.statusDraws do
        equal(edgeView.statusDraws[index].rootX, 552,
            "SLA header rendering retains the same leased root X")
    end
    equal(edgeEnvironment.adminRootXs[#edgeEnvironment.adminRootXs], 552,
        "Admin child rendering retains the same leased root X")
    edgeView:prerender()
    edgeEnvironment.adminAvailable = false
    edgeBar:renderPerkRect()
    edgeView:render()
    edgeButton:render()
    equal(edgeEnvironment.progressRootXs[#edgeEnvironment.progressRootXs], 552,
        "post-prerender availability change cannot move the child-render root X")
    equal(edgeEnvironment.vanillaRootXs[#edgeEnvironment.vanillaRootXs], 552,
        "render does not release Admin geometry after availability changes")
    for index = #edgeView.statusDraws - 3, #edgeView.statusDraws do
        equal(edgeView.statusDraws[index].rootX, 552,
            "availability transition leaves the current SLA header cycle at one root X")
    end
    equal(edgeEnvironment.adminRootXs[#edgeEnvironment.adminRootXs], 552,
        "availability transition leaves current-cycle Admin rendering at one root X")
    expect(edgeButton.visible and edgeButton.enabled,
        "current frame consumes the Admin state accepted during prerender")
    edgeView:prerender()
    equal(edgeView.outer.width, 420,
        "next prerender releases unavailable Admin geometry before child rendering")
    equal(edgeView.outer.x, 580,
        "next prerender restores unavailable Admin root X before child rendering")
    expect(not edgeButton.visible and not edgeButton.enabled,
        "next prerender hides unavailable Admin before geometry restoration")
    edgeBar:renderPerkRect()
    equal(edgeEnvironment.progressRootXs[#edgeEnvironment.progressRootXs], 580,
        "first child render after availability release uses the restored root X")
    edgeEnvironment.adminAvailable = true
    edgeView:setVisible(false)
    equal(edgeView.parent.width, 420,
        "right-edge hide restores the shared tab-panel base width")
    equal(edgeView.outer.width, 420,
        "right-edge hide restores the top-level base width")
    equal(edgeView.outer.x, 580,
        "right-edge hide restores the lease-owned keep-on-screen shift")
    edgeView:setVisible(true)
    equal(edgeView.outer.width, 448,
        "right-edge show reacquires the outboard width")
    equal(edgeView.outer.x, 552,
        "right-edge show deterministically reapplies vanilla keep-on-screen")
    edgeView.outer:setWidth(500)
    equal(edgeView.outer.x, 500,
        "production-shaped external resize applies its own keep-on-screen shift")
    edgeView:setVisible(false)
    equal(edgeView.parent.width, 420,
        "external top-level resize does not prevent child lease release")
    equal(edgeView.outer.width, 500,
        "lease release preserves a legitimate external top-level resize")
    equal(edgeView.outer.x, 500,
        "lease release preserves the external resize's keep-on-screen position")
    expect(not edgeView.parent:canRouteMouseTo(edgeButton),
        "right-edge hidden Admin cannot intercept mouse input")
    edgeView:setVisible(true)
    edgeView.parent:setWidth(470)
    edgeView:setVisible(false)
    equal(edgeView.parent.width, 470,
        "lease release preserves a legitimate external shared-parent resize")
    equal(edgeView.outer.width, 500,
        "external shared-parent resize retains its already sufficient ancestor")
end

do
    local widthTransitionEnvironment = makeEnvironment({ adminLauncher = true })
    widthTransitionEnvironment.measureScale = 6
    expect(widthTransitionEnvironment.integration.install().ok,
        "width-transition Admin integration installs")
    local widthTransitionBar = makeBar(widthTransitionEnvironment, "Axe")
    local widthTransitionView = makeView(
        widthTransitionEnvironment, 0, { widthTransitionBar })
    widthTransitionView.outer.keepOnScreen = true
    widthTransitionView.outer.screenWidth = 1000
    widthTransitionView.outer.x = 580
    widthTransitionView:prerender()
    local widthTransitionButton = widthTransitionView.parent.children[1]
    equal(widthTransitionView.outer.width, 448,
        "narrow snapshot begins with the normal leased width")
    equal(widthTransitionView.outer.x, 552,
        "narrow snapshot begins at the normal keep-on-screen root X")
    widthTransitionBar:renderPerkRect()
    widthTransitionView:render()
    widthTransitionButton:render()
    widthTransitionEnvironment.survivorLevel = 9007199254740991
    widthTransitionEnvironment.availableAp = 9007199254740989
    widthTransitionEnvironment.xpIntoLevel = 9007199254740990
    widthTransitionEnvironment.xpForNextLevel = 9007199254740991
    widthTransitionEnvironment.now = 1000
    widthTransitionView:prerender()
    local expandedRootX = widthTransitionView.outer.x
    expect(widthTransitionView.outer.width > 448 and expandedRootX < 552,
        "larger snapshot values widen and shift the right-edge window during prerender")
    widthTransitionBar:renderPerkRect()
    widthTransitionView:render()
    widthTransitionButton:render()
    equal(widthTransitionEnvironment.progressRootXs[
        #widthTransitionEnvironment.progressRootXs], expandedRootX,
        "width-expanding snapshot reserves root X before progress child rendering")
    equal(widthTransitionEnvironment.vanillaRootXs[
        #widthTransitionEnvironment.vanillaRootXs], expandedRootX,
        "width-expanding snapshot keeps vanilla rendering at the prerender root X")
    for index = #widthTransitionView.statusDraws - 3,
        #widthTransitionView.statusDraws do
        equal(widthTransitionView.statusDraws[index].rootX, expandedRootX,
            "width-expanding snapshot keeps SLA header rendering at the prerender root X")
    end
    equal(widthTransitionEnvironment.adminRootXs[
        #widthTransitionEnvironment.adminRootXs], expandedRootX,
        "width-expanding snapshot keeps Admin rendering at the prerender root X")
end

do
    local tabWidthEnvironment = makeEnvironment({ adminLauncher = true })
    expect(tabWidthEnvironment.integration.install().ok,
        "tab-width Admin integration installs")
    local tabWidthBar = makeBar(tabWidthEnvironment, "Axe")
    local tabWidthView = makeView(tabWidthEnvironment, 0, { tabWidthBar })
    tabWidthView:prerender()
    tabWidthView:render()
    tabWidthView:prerender()
    equal(tabWidthView.width, 420, "narrow-tab transition keeps vanilla Skills minimum")
    equal(tabWidthView.parent.width, 448,
        "narrow-tab transition adds only the exact Admin lease")
    tabWidthView:setVisible(false)
    equal(tabWidthView.parent.width, 420,
        "leaving narrow Skills releases only SLA-owned width")
    tabWidthView:setWidth(520)
    tabWidthView.parent:setWidth(520)
    tabWidthView.outer:setWidth(520)
    tabWidthView:setVisible(true)
    tabWidthView:prerender()
    tabWidthView:render()
    tabWidthView:prerender()
    equal(tabWidthView.width, 540,
        "Temperature-sized external width remains legitimate beneath the SLA plus gutter")
    equal(tabWidthView.parent.width, 568,
        "wider vanilla geometry receives one exact outboard lease")
    tabWidthView:setVisible(false)
    equal(tabWidthView.parent.width, 520,
        "leaving wider Skills preserves the legitimate external width")
    tabWidthView:setVisible(true)
    tabWidthView:prerender()
    equal(tabWidthView.parent.width, 568,
        "returning from wider tab does not accumulate SLA width")
end

do
    local releaseFailureEnvironment = makeEnvironment({ adminLauncher = true })
    expect(releaseFailureEnvironment.integration.install().ok,
        "release-failure Admin integration installs")
    local releaseFailureBar = makeBar(releaseFailureEnvironment, "Axe")
    local releaseFailureView = makeView(
        releaseFailureEnvironment, 0, { releaseFailureBar })
    releaseFailureView:prerender()
    releaseFailureView:render()
    releaseFailureView:prerender()
    local releaseFailureButton = releaseFailureView.parent.children[1]
    expect(releaseFailureButton.visible and releaseFailureButton.enabled,
        "release-failure fixture begins with a live leased Admin")
    releaseFailureView.parent.throwSetWidth = true
    releaseFailureView:setVisible(false)
    local cleanupObservation = releaseFailureView.parent.throwSetWidthObservation
    expect(type(cleanupObservation) == "table"
        and cleanupObservation.visible == false and cleanupObservation.enabled == false,
        "Admin is hidden and disabled before a failing geometry-restoration write")
    expect(not releaseFailureButton.visible and not releaseFailureButton.enabled
        and releaseFailureButton.onclick == nil and releaseFailureButton.target == nil,
        "release failure leaves no clickable Admin control")
    releaseFailureButton:click()
    equal(#releaseFailureEnvironment.adminOpens, 0,
        "release failure cannot activate a stale Admin callback")
end

local offsetAdminEnvironment = makeEnvironment({ adminLauncher = true })
expect(offsetAdminEnvironment.integration.install().ok, "offset Admin integration installs")
local offsetAdminBar = makeBar(offsetAdminEnvironment, "Axe")
local offsetAdminView = makeView(offsetAdminEnvironment, 1, { offsetAdminBar })
offsetAdminView.x = 23
offsetAdminView:prerender()
offsetAdminView:render()
offsetAdminView:prerender()
local offsetAdminButton = offsetAdminView.parent.children[1]
local offsetAp = lastDrawText(offsetAdminView.statusDraws, "AP: 3")
equal(offsetAp.x, offsetAdminView.x + offsetAdminView.width - 4,
    "offset AP uses the live Skills-panel right margin")
equal(offsetAdminButton.x, offsetAdminView.x + offsetAdminView.width + 4,
    "offset Admin tracks immediately outside the live Skills-panel edge")
equal(offsetAdminView.parent.width, offsetAdminButton.x + offsetAdminButton.width + 4,
    "offset Admin expands its containing parent enough to remain mouse reachable")
equal(offsetAdminView.outer.width, offsetAdminView.parent.x + offsetAdminView.parent.width,
    "offset containing-parent width propagates through its ancestor")
local stableOffsetParentWidth = offsetAdminView.parent.width
local stableOffsetButtonX = offsetAdminButton.x
offsetAdminView:render()
equal(offsetAdminView.parent.width, stableOffsetParentWidth,
    "offset repeated render keeps propagated containing width stable")
equal(offsetAdminButton.x, stableOffsetButtonX,
    "offset repeated render keeps Admin right-margin placement stable")
equal(lastDrawText(offsetAdminView.statusDraws, "AP: 3").x,
    offsetAdminView.x + offsetAdminView.width - 4,
    "offset repeated render keeps AP on the Skills-panel right margin")
offsetAdminView.x = 37
offsetAdminView:setWidth(460)
offsetAdminView:render()
equal(offsetAdminButton.x, offsetAdminView.x + offsetAdminView.width + 4,
    "Admin tracks a live Skills-panel move and resize")
equal(offsetAdminView.parent.width, offsetAdminButton.x + offsetAdminButton.width + 4,
    "moved Admin remains inside the expanded mouse-routing parent")

equal(environment.adminRequests, 0, "Skills UI never calls admin request")
equal(environment.adminStatusReads, 0, "Skills UI never reads admin status")

return assertions
