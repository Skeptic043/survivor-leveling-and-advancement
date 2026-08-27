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

local translations = {
    IGUI_SLA_StatusAP = "AP: %1",
    IGUI_SLA_StatusActive = "Advancement Slots: %1/%2",
    IGUI_SLA_StatusSurvivorXp = "Survivor XP: %1 / %2",
    IGUI_SLA_Advance = "Advance to level %1 for %2 AP.",
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
    IGUI_SLA_Reason_AllotmentCapacity = "This skill has reached its advancement limit.",
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

local function settings(mode)
    return {
        survivorMultiplier = 1,
        fitnessStrengthNormalization = 0.067,
        automaticCurveNormalization = true,
        allotmentMode = mode or "Global",
        globalLimit = 6,
        perSkillDefault = 2,
        perSkillOverrides = { Axe = 4 },
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
        priorActivate = 0,
        priorMouseUp = 0,
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
        adminInstalls = 0,
        adminStatusReads = 0,
        adminAvailabilityReads = 0,
        adminOpens = {},
        adminAvailable = true,
        adminInstalled = false,
        listenerSets = 0,
        listener = nil,
        prerenderGeometry = {},
        mode = options.mode or "Global",
        pending = { false, false, false, false },
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
        drawOrder = {},
        buildArguments = {},
    }

    local CharacterInfo = {}
    local ProgressBar = {}
    local Button = {}

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
        if self.throwRender then error("vanilla render") end
        if self.pendingBars ~= nil then
            self.progressBars = self.pendingBars
            self.pendingBars = nil
        end
        if self.buttonList[1] ~= nil then self.buttonList[1]:setY(10) end
        self:setWidthAndParentWidth(math.max(self:getWidth(), self.vanillaWidth))
        self:setHeightAndParentHeight(self.vanillaHeight)
        self.scrollHeight = self.vanillaScrollHeight
    end

    function ProgressBar.renderPerkRect(self)
        evidence.priorOverlay = evidence.priorOverlay + 1
        evidence.drawOrder[#evidence.drawOrder + 1] = "gold"
    end

    function ProgressBar.updateTooltip(self)
        evidence.priorTooltip = evidence.priorTooltip + 1
        self.message = "Vanilla tooltip"
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
        function button:setBorderRGBA(r, g, b, a) self.border = { r, g, b, a } end
        function button:getWidth() return self.width end
        function button:getHeight() return self.height end
        function button:setX(value) self.x = value end
        function button:setY(value) self.y = value end
        function button:click()
            if self.enabled and self.onclick ~= nil then self.onclick(self.target, self) end
        end
        return button
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
            local value = settings(evidence.mode)
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
            local result = {
                sequence = 1,
                revision = 2,
                survivor = {
                    level = 5,
                    xpIntoLevel = 10,
                    xpForNextLevel = 100,
                    spent = 2,
                    availableAp = 3,
                },
                allotment = allotment,
                pending = input.pending,
                rows = rows,
            }
            if evidence.privateModelField then result.private = true end
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
    function parent:setWidth(value) self.width = value end
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
    function parent:drawText(text, drawX, drawY, r, g, b, a, font)
        if self.throwDraw then error("parent draw boom") end
        self.statusDraws[#self.statusDraws + 1] = {
            kind = "left",
            text = text,
            x = drawX,
            y = drawY,
            screenX = self.x + drawX - self.xScroll,
            screenY = self.y + drawY - self.yScroll,
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
    function view:setYScroll(value) self.yScroll = value end
    function view:getScrollHeight() return self.scrollHeight end
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
    end
    setmetatable(view, { __index = environment.CharacterInfo })
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
equal(SkillsUiBootstrapHarness, 24, "bootstrap harness checks")
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

expect(exact(environment.integration.status(), { ok = true, installed = true })
    and environment.integration.status().installed == false, "creation is inert")
equal(environment.listenerSets, 0, "creation installs no listener")
equal(environment.buttonCreates, 0, "creation creates no UI")
equal(environment.settingsReads, 0, "creation reads no settings")
equal(environment.adminRequests, 0, "creation does not call admin request")
equal(environment.adminStatusReads, 0, "creation does not read admin status")
equal(total(environment.stateReads), 0, "creation reads no state")
equal(total(environment.refresh), 0, "creation sends no refresh")
local installed = environment.integration.install()
expect(exact(installed, { ok = true }) and installed.ok, "install succeeds exactly")
equal(environment.listenerSets, 1, "one lifecycle listener")
expect(environment.integration.install().ok, "repeat install idempotent")
equal(environment.listenerSets, 1, "repeat install does not replace listener")
expect(exact(environment.integration.status(), { ok = true, installed = true }), "status surface exact")
local installedMouseUp = environment.ProgressBar.onMouseUp

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
equal(environment.prerenderGeometry[1].height, 270, "header viewport is reserved before vanilla stencil")
equal(view.y, 58, "view moves by the exact two-row native header inset")
equal(environment.refresh[1], 1, "first visible prerender requests refresh")
equal(total(environment.stateReads), 0, "first prerender reads no owner state")
equal(total(environment.statusReads), 0, "first prerender reads no advancement status")
equal(environment.settingsReads, 0, "first prerender reads no settings")
equal(environment.modelBuilds, 0, "first prerender builds no model")

view:render()
equal(environment.priorRender, 1, "first render chains vanilla once")
equal(view.height, 270, "viewport loses exactly one native header inset")
equal(view.parent.height, 328, "containing panel grows by exactly one native row")
equal(view.outer.height, 348, "outer window grows by exactly one native row")
equal(view.scrollHeight, 500, "vanilla scroll height remains unchanged")
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
axe:activate()
equal(environment.requests[1], 1, "controller activation same frame coalesces")
equal(environment.priorActivate, 2, "mouse and controller each retain vanilla activate seam")
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
environment.requestReject = true
axeButton:click()
equal(environment.requests[1], 2, "ordinary rejection is delivered once")
expect(axeButton.enabled, "ordinary rejection does not poison control")
equal(string.find(axeButton.tooltip or "", "secret", 1, true), nil, "backend detail never leaks")

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
equal(#view.statusDraws, statusDrawsBeforeScroll + 3,
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
equal(lastDrawText(view.statusDraws, "AP: 3").x, 4,
    "repeated renders keep the first left label at the fixed window margin")
equal(lastDrawText(view.statusDraws, "Survivor XP: 10 / 100").x, 4,
    "repeated renders keep the second left label at the fixed window margin")
equal(view.width - (axe.x + axe.width), 100, "expanded bar preserves measured vanilla right gutter")
equal(view.parent.width, view.x + view.width, "view width propagates absolutely to parent")
equal(view.outer.width, view.parent.x + view.parent.width, "width propagates through every ancestor")
expect(#view.statusDraws > 0, "status draws on first category row")
equal(lastDrawText(view.statusDraws, "AP: 3").y, 18,
    "first status row uses fixed parent-local coordinates")
local globalLeft = lastDrawText(view.statusDraws, "AP: 3")
local globalRight = lastDraw(view.statusDraws, "right")
local survivorXp = lastDrawText(view.statusDraws, "Survivor XP: 10 / 100")
equal(globalLeft.text, "AP: 3", "Global status binds compact AP left")
equal(globalLeft.x, 4, "Global AP binds four logical pixels from containing window left edge")
equal(globalRight.text, "Advancement Slots: 2/6", "Global status binds slots right")
equal(globalRight.x, view.parent.width - 4,
    "Global slots bind four logical pixels from containing window right edge")
expect(survivorXp ~= nil, "second row binds exact cached Survivor XP")
equal(survivorXp.x, 4, "Survivor XP binds four logical pixels from containing window left edge")
equal(survivorXp.y, 38, "Survivor XP uses the second native-height row")

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
local narrowStatus = lastDraw(narrowView.statusDraws, "right")
local requiredWindowWidth = 4 + (#"AP: 3" * 10) + (#"  " * 10)
    + (#"Advancement Slots: 2/6" * 10) + 4
equal(narrowStatus.x, narrowView.parent.width - 4,
    "Global labels retain the four-pixel containing-window right margin")
equal(narrowView.width, requiredWindowWidth,
    "Global width uses the collision-safe header minimum with symmetric outer margins")
expect(narrowView.width > 200 and narrowView.parent.width > 220,
    "narrow view and containing window widen for measured copy")

local originalSecondRowCopy = translations.IGUI_SLA_StatusSurvivorXp
translations.IGUI_SLA_StatusSurvivorXp = string.rep("W", 500) .. " %1 / %2"
local wideSecondRowEnvironment = makeEnvironment()
expect(wideSecondRowEnvironment.integration.install().ok, "wide second-row integration installs")
local wideSecondRowBar = makeBar(wideSecondRowEnvironment, "Axe")
local wideSecondRowView = makeView(wideSecondRowEnvironment, 0, { wideSecondRowBar })
wideSecondRowView:prerender()
wideSecondRowView:render()
local wideSecondRowText = formatText("IGUI_SLA_StatusSurvivorXp", 10, 100)
equal(wideSecondRowView.width, 4 + #wideSecondRowText + 4,
    "wider second row remains the collision-safe header minimum in Global mode")
translations.IGUI_SLA_StatusSurvivorXp = originalSecondRowCopy

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
equal(tornParent.height, 336, "torn-off parent receives one-row-expanded absolute height")
equal(tornOuter.height, 360, "torn-off outer window receives full expanded ancestor height")
equal(lastDrawText(tornParent.statusDraws, "AP: 3").y, 26,
    "torn-off first status row uses the new parent-local position")
equal(lastDrawText(tornParent.statusDraws, "Survivor XP: 10 / 100").y, 46,
    "torn-off second status row follows one native row below")
view.parent = dockedParent
view:setY(8)
view:render()
equal(view.y, 58, "reattached view reapplies the two-row header inset")
equal(dockedParent.height, 328, "reattached panel restores one-row-expanded height")
equal(dockedOuter.height, 348, "reattached outer window restores one-row-expanded height")

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
    expect(lastDrawText(modeView.statusDraws, "AP: 3") ~= nil,
        modes[index] .. " first row includes AP")
    expect(lastDrawText(modeView.statusDraws, "Survivor XP: 10 / 100") ~= nil,
        modes[index] .. " second row includes exact Survivor XP")
    equal(lastDraw(modeView.statusDraws, "right"), nil, modes[index] .. " header makes no right draw")
    equal(modeView.width, 420, modes[index] .. " width uses max control edge plus captured gutter")
end

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
vanillaThrowView.throwRender = true
local renderOk = pcall(function() vanillaThrowView:render() end)
expect(not renderOk, "vanilla render throw propagates")
equal(vanillaThrowEnvironment.priorRender, 1, "throwing vanilla render called once")

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
equal(#adminView.parent.children, 1, "one second-row admin button is created")
local adminButton = adminView.parent.children[1]
equal(adminButton.title, "Admin", "admin launcher uses localized compact label")
expect(adminButton.visible and adminButton.enabled, "debug launcher is visible and enabled")
local adminRight = lastDraw(adminView.statusDraws, "right")
local adminXp = lastDrawText(adminView.statusDraws, "Survivor XP: 10 / 100")
expect(adminRight ~= nil and adminRight.x == adminView.parent.width - 4,
    "first-row Global label keeps its containing-window right margin")
expect(adminXp ~= nil and adminXp.x == 4 and adminButton.x > adminXp.x,
    "second-row Survivor XP and Admin keep separate left and right alignment")
equal(adminButton.x, adminView.parent.width - 4 - adminButton.width,
    "Admin binds four logical pixels from containing window right edge")
equal(adminButton.y, 38, "Admin uses the second native-height row")
local stableAdminX = adminButton.x
adminView:render()
equal(adminButton.x, stableAdminX, "repeated render keeps Admin right-margin placement stable")
local visibleApX = lastDrawText(adminView.statusDraws, "AP: 3").x
local visibleXpX = adminXp.x
adminButton:click()
equal(#adminEnvironment.adminOpens, 1, "admin launcher activates once")
equal(adminEnvironment.adminOpens[1], 2, "admin launcher activation preserves exact slot")
adminEnvironment.adminAvailable = false
adminView:prerender()
adminView:render()
expect(not adminButton.visible and not adminButton.enabled,
    "launcher disappears and disables on the next visible prerender")
equal(lastDrawText(adminView.statusDraws, "AP: 3").x, visibleApX,
    "first-row label does not move when Admin disappears")
equal(lastDrawText(adminView.statusDraws, "Survivor XP: 10 / 100").x, visibleXpX,
    "second-row label does not move when Admin disappears")
adminButton:click()
equal(#adminEnvironment.adminOpens, 1, "hidden launcher cannot activate")
equal(adminEnvironment.adminRequests, 0, "Skills launcher never calls lifecycle admin request")
equal(adminEnvironment.adminStatusReads, 0, "Skills launcher never reads lifecycle admin status")
adminEnvironment.adminInstalled = false
local lostAdminHook = adminEnvironment.integration.install()
equal(lostAdminHook.ok, false, "lost admin hook ownership fails composite closed")
equal(lostAdminHook.code, "hook_ownership_lost", "lost admin ownership code")

local offsetAdminEnvironment = makeEnvironment({ adminLauncher = true })
expect(offsetAdminEnvironment.integration.install().ok, "offset Admin integration installs")
local offsetAdminBar = makeBar(offsetAdminEnvironment, "Axe")
local offsetAdminView = makeView(offsetAdminEnvironment, 1, { offsetAdminBar })
offsetAdminView.x = 23
offsetAdminView:prerender()
offsetAdminView:render()
local offsetAdminButton = offsetAdminView.parent.children[1]
local offsetGlobalRight = lastDraw(offsetAdminView.statusDraws, "right")
equal(offsetGlobalRight.x, offsetAdminView.parent.width - 4,
    "offset Global label uses the containing-window right margin")
equal(offsetAdminButton.x, offsetAdminView.parent.width - 4 - offsetAdminButton.width,
    "offset Admin uses the containing-window right margin")
equal(offsetAdminView.parent.width, offsetAdminView.x + offsetAdminView.width,
    "offset Skills view width propagates through its containing parent")
equal(offsetAdminView.outer.width, offsetAdminView.parent.x + offsetAdminView.parent.width,
    "offset containing-parent width propagates through its ancestor")
local stableOffsetParentWidth = offsetAdminView.parent.width
local stableOffsetButtonX = offsetAdminButton.x
offsetAdminView:render()
equal(offsetAdminView.parent.width, stableOffsetParentWidth,
    "offset repeated render keeps propagated containing width stable")
equal(offsetAdminButton.x, stableOffsetButtonX,
    "offset repeated render keeps Admin right-margin placement stable")
equal(lastDraw(offsetAdminView.statusDraws, "right").x, offsetAdminView.parent.width - 4,
    "offset repeated render keeps Global right-margin placement stable")

equal(environment.adminRequests, 0, "Skills UI never calls admin request")
equal(environment.adminStatusReads, 0, "Skills UI never reads admin status")

return assertions
