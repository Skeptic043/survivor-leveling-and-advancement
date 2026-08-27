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
    IGUI_SLA_Admin_Button = "Admin",
    IGUI_SLA_Admin_Menu = "Survivor progression",
    IGUI_SLA_Admin_Title = "Survivor progression",
    IGUI_SLA_Admin_Target = "Target: %1",
    IGUI_SLA_Admin_Level = "Survivor Level: %1",
    IGUI_SLA_Admin_Xp = "Survivor XP: %1 / %2",
    IGUI_SLA_Admin_Ap = "Available AP: %1",
    IGUI_SLA_Admin_XpInput = "XP to award",
    IGUI_SLA_Admin_AwardXp = "Award XP",
    IGUI_SLA_Admin_LevelsInput = "Levels to award",
    IGUI_SLA_Admin_AwardLevels = "Award Levels",
    IGUI_SLA_Admin_ClearSlots = "Clear Advancement Slots",
    IGUI_SLA_Admin_Refresh = "Refresh",
    IGUI_SLA_Admin_Waiting = "Waiting for Survivor data.",
    IGUI_SLA_Admin_Inspected = "Survivor data refreshed.",
    IGUI_SLA_Admin_Applied = "Survivor progression updated.",
    IGUI_SLA_Admin_Stale = "Survivor data changed. Refresh and try again.",
    IGUI_SLA_Admin_Failure = "The request failed. Refresh and try again.",
    IGUI_SLA_Admin_CommittedFailure = "The change may have applied. Refresh before trying again.",
    IGUI_SLA_Admin_InvalidXp = "Enter a positive XP amount.",
    IGUI_SLA_Admin_InvalidLevels = "Enter a positive whole level count.",
    IGUI_SLA_Admin_PendingOther = "Another admin request is pending.",
}

local function getText(key, ...)
    local value = translations[key]
    if value == nil then return key end
    local arguments = { ... }
    for index = 1, #arguments do
        value = string.gsub(value, "%%" .. tostring(index), tostring(arguments[index]))
    end
    return value
end

local function summary(revision, level, spent, xp, accountingMode)
    return {
        accountingMode = accountingMode or "Tracked",
        revision = revision,
        level = level,
        xpIntoLevel = xp or 25,
        xpForNextLevel = 100,
        spent = spent,
        availableAp = level - spent,
    }
end

local function makeEnvironment(processMode)
    local evidence = {
        mode = processMode,
        serverReads = 0,
        clientReads = 0,
        debugReads = 0,
        debug = true,
        canSee = true,
        priorMenus = 0,
        vanillaContextGets = 0,
        existingMenuGets = 0,
        capabilityReads = 0,
        requests = {},
        statusReads = 0,
        status = { ok = true, pending = false },
        windows = {},
        windowChildren = 0,
        viewportWidth = 300,
        viewportHeight = 240,
        viewportLeft = 400,
        viewportTop = 100,
        viewportSlot = nil,
        requestSequence = 0,
    }

    local Scoreboard = {}
    local Window = {}
    local Entry = {}
    local Button = {}
    local Capability = { CanSeePlayersStats = {} }

    local function makeMenu()
        local menu = { options = {} }
        function menu:addOption(title, target, onSelect)
            local option = { title = title, target = target, onSelect = onSelect }
            function option:click() self.onSelect(self.target) end
            self.options[#self.options + 1] = option
            return option
        end
        return menu
    end

    function Scoreboard.doPlayerListContextMenu(self, player, x, y)
        evidence.priorMenus = evidence.priorMenus + 1
        evidence.vanillaContextGets = evidence.vanillaContextGets + 1
        evidence.menu = makeMenu()
        if evidence.priorThrows then error("vanilla menu boom") end
        return "vanilla", x, y
    end

    function Window.createChildren(self)
        evidence.windowChildren = evidence.windowChildren + 1
        if evidence.childConstructionThrows then error("child construction boom") end
        self.baseCloseControls = (self.baseCloseControls or 0) + 1
        self:addChild({ baseCloseControl = true })
    end

    function Window.prerender(self)
        self.priorPrerenders = self.priorPrerenders + 1
        if self.prerenderThrows then error("vanilla window boom") end
    end

    function Window.instantiate(self)
        self.phaseOrder[#self.phaseOrder + 1] = "instantiate"
        self.instantiates = (self.instantiates or 0) + 1
        if evidence.instantiateThrows then error("instantiate boom") end
        self:createChildren()
        self.instantiated = true
    end

    function Window.new(_, x, y, width, height)
        local window = {
            x = x,
            y = y,
            width = width,
            height = height,
            children = {},
            draws = {},
            priorPrerenders = 0,
            visible = false,
            removed = false,
            phaseOrder = {},
        }
        function window:setTitle(value) self.title = value end
        function window:initialise()
            self.phaseOrder[#self.phaseOrder + 1] = "initialise"
            self.initialised = true
        end
        function window:addToUIManager()
            self.phaseOrder[#self.phaseOrder + 1] = "manager"
            self.added = true
            if not self.instantiated then error("window was not instantiated") end
        end
        function window:setVisible(value)
            self.phaseOrder[#self.phaseOrder + 1] = value and "visible" or "hidden"
            self.visible = value
        end
        function window:removeFromUIManager() self.removed = true end
        function window:bringToTop() self.broughtToTop = (self.broughtToTop or 0) + 1 end
        function window:addChild(child)
            self.children[#self.children + 1] = child
            child.parent = self
        end
        function window:drawText(text, drawX, drawY)
            self.draws[#self.draws + 1] = { text = text, x = drawX, y = drawY }
        end
        evidence.windows[#evidence.windows + 1] = window
        return window
    end

    function Entry.new(_, title, x, y, width, height)
        local entry = {
            text = title,
            x = x,
            y = y,
            width = width,
            height = height,
            editable = true,
        }
        function entry:initialise() self.initialised = true end
        function entry:getText() return self.text end
        function entry:setText(value) self.text = value end
        function entry:setEditable(value) self.editable = value end
        return entry
    end

    function Button.new(_, x, y, width, height, title, target, onclick)
        local button = {
            x = x,
            y = y,
            width = width,
            height = height,
            title = title,
            target = target,
            onclick = onclick,
            enabled = true,
            visible = true,
        }
        function button:initialise() self.initialised = true end
        function button:setEnable(value) self.enabled = value end
        function button:setVisible(value) self.visible = value end
        function button:click()
            if self.enabled and self.onclick ~= nil then self.onclick(self.target, self) end
        end
        return button
    end

    local owner = {
        install = function() return { ok = true } end,
        status = function() return { ok = true } end,
        clientState = function() return { ok = true, present = false } end,
        refreshOwner = function() return { ok = true } end,
        setClientStateListener = function() return { ok = true } end,
        requestAdvancement = function() return { ok = false, code = "unavailable", detail = "unavailable" } end,
        advancementStatus = function() return { ok = true, pending = false } end,
        requestAdmin = function(slot, request)
            evidence.requests[#evidence.requests + 1] = { slot = slot, request = request }
            if evidence.requestHandler ~= nil then return evidence.requestHandler(slot, request) end
            evidence.requestSequence = evidence.requestSequence + 1
            return { ok = true, requestId = "request-" .. tostring(evidence.requestSequence) }
        end,
        adminStatus = function(slot)
            evidence.statusReads = evidence.statusReads + 1
            evidence.lastStatusSlot = slot
            if evidence.statusThrows then error("status boom") end
            return evidence.status
        end,
    }

    local dependencies = {
        owner = owner,
        ISMiniScoreboardUI = Scoreboard,
        ISCollapsableWindowJoypad = Window,
        ISTextEntryBox = Entry,
        ISButton = Button,
        canSeePlayersStats = Capability.CanSeePlayersStats,
        getPlayerContextMenu = function(slot)
            evidence.existingMenuGets = evidence.existingMenuGets + 1
            evidence.lastMenuSlot = slot
            return evidence.menu
        end,
        isServer = function()
            evidence.serverReads = evidence.serverReads + 1
            return false
        end,
        isClient = function()
            evidence.clientReads = evidence.clientReads + 1
            return processMode == "multiplayer"
        end,
        isDebugEnabled = function()
            evidence.debugReads = evidence.debugReads + 1
            if evidence.debugThrows then error("debug boom") end
            return evidence.debug
        end,
        getText = getText,
        viewport = function(slot)
            evidence.viewportSlot = slot
            return evidence.viewportLeft, evidence.viewportTop,
                evidence.viewportWidth, evidence.viewportHeight
        end,
        smallFont = "small-font",
    }

    local created = Build42AdminUi.create(dependencies)
    expect(created.ok, processMode .. " integration creates")
    evidence.integration = created.integration
    evidence.dependencies = dependencies
    evidence.owner = owner
    evidence.Scoreboard = Scoreboard
    evidence.Capability = Capability

    function evidence:scoreboard(username, slot)
        local roleBacking = {
            hasCapability = function(_, value)
                evidence.capabilityReads = evidence.capabilityReads + 1
                evidence.lastCapability = value
                return evidence.canSee
            end,
        }
        local role = setmetatable({}, {
            __index = function(_, key)
                evidence.roleProxyReads = (evidence.roleProxyReads or 0) + 1
                return roleBacking[key]
            end,
        })
        local adminBacking = {
            getRole = function() return role end,
            getPlayerNum = function() return slot or 0 end,
        }
        local admin = setmetatable({}, {
            __index = function(_, key)
                evidence.adminProxyReads = (evidence.adminProxyReads or 0) + 1
                return adminBacking[key]
            end,
        })
        evidence.lastAdminProxy = admin
        evidence.lastRoleProxy = role
        return { admin = admin }, { username = username }
    end

    function evidence:openFromScoreboard(username, slot)
        local scoreboard, player = self:scoreboard(username, slot)
        local a, b, c = self.Scoreboard.doPlayerListContextMenu(scoreboard, player, 11, 22)
        local option = self.menu.options[#self.menu.options]
        option:click()
        return option, a, b, c
    end

    return evidence
end

local function findButton(state, internal)
    if internal == "XP" then return state.awardXpButton end
    if internal == "LEVELS" then return state.awardLevelsButton end
    if internal == "CLEAR" then return state.clearSlotsButton end
    return state.refreshButton
end

local function containsDraw(window, text)
    for index = 1, #window.draws do
        if string.find(window.draws[index].text, text, 1, true) ~= nil then return true end
    end
    return false
end

expect(type(Build42AdminUi) == "table", "module loads")
expect(type(Build42AdminUi.create) == "function", "module exposes create")

local malformed = Build42AdminUi.create({})
equal(malformed.ok, false, "malformed construction fails")
equal(malformed.code, "invalid_dependencies", "malformed construction code")

local mp = makeEnvironment("multiplayer")
mp.viewportWidth = 500
mp.viewportHeight = 400
equal(mp.serverReads, 1, "server mode read once")
equal(mp.clientReads, 1, "client mode read once")
equal(mp.priorMenus, 0, "construction does not patch or invoke scoreboard")
equal(#mp.requests, 0, "construction sends no request")
equal(mp.statusReads, 0, "construction reads no admin status")
equal(#mp.windows, 0, "construction creates no UI")
expect(exact(mp.integration, {
    install = true, status = true, isAvailable = true, open = true,
}), "integration surface exact")
local initialStatus = mp.integration.status()
expect(initialStatus.ok and not initialStatus.installed and initialStatus.mode == "multiplayer",
    "creation status is inert and mode-bounded")
expect(mp.integration.install().ok, "MP installs")
expect(mp.integration.install().ok, "MP reload install idempotent")
equal(mp.priorMenus, 0, "installation invokes no vanilla menu")

local hiddenScoreboard, hiddenPlayer = mp:scoreboard("Hidden", 1)
expect(rawget(mp.lastAdminProxy, "getRole") == nil
    and rawget(mp.lastRoleProxy, "hasCapability") == nil,
    "Java-proxy regression fakes expose no raw methods")
mp.canSee = false
mp.Scoreboard.doPlayerListContextMenu(hiddenScoreboard, hiddenPlayer, 1, 2)
equal(mp.priorMenus, 1, "hidden action still chains vanilla once")
equal(#mp.menu.options, 0, "missing live capability hides action")
equal(mp.existingMenuGets, 0, "hidden action never retrieves context again")
mp.canSee = true

mp.owner.requestAdmin = function() error("late owner mutation") end
local option, a, b, c = mp:openFromScoreboard("Alpha", 2)
equal(a, "vanilla", "scoreboard wrapper preserves first return")
equal(b, 11, "scoreboard wrapper preserves second return")
equal(c, 22, "scoreboard wrapper preserves third return")
equal(mp.priorMenus, 2, "visible action chains captured vanilla exactly once")
equal(mp.vanillaContextGets, 2, "vanilla owns one context construction per invocation")
equal(mp.existingMenuGets, 1, "adapter retrieves existing context exactly once")
equal(mp.lastMenuSlot, 2, "existing context getter uses exact local slot")
expect(mp.lastCapability == mp.Capability.CanSeePlayersStats, "visibility uses exact capability")
expect(mp.adminProxyReads > 0 and mp.roleProxyReads > 0,
    "admin and role methods are read through protected proxy access")
equal(option.title, "Survivor progression", "scoreboard action localized")
equal(#mp.requests, 1, "opening sends one inspection")
equal(mp.requests[1].slot, 2, "inspection preserves local slot")
expect(exact(mp.requests[1].request, { operation = true, target = true }),
    "MP inspection logical request exact")
expect(exact(mp.requests[1].request.target, { username = true })
    and mp.requests[1].request.target.username == "Alpha", "inspection sends username only")
equal(#mp.windows, 1, "one panel created")
local window = mp.windows[1]
local state = rawget(window, "__slaAdminState")
expect(state ~= nil, "panel owns bounded controller state")
equal(mp.viewportSlot, 2, "viewport capability preserves exact local slot")
equal(window.x, 470, "panel centers inside nonzero split-screen X origin")
equal(window.y, 141, "panel centers inside nonzero split-screen Y origin")
equal(window.width, 360, "panel uses compact width inside local viewport")
equal(window.height, 318, "panel uses compact height inside local viewport")
equal(window.instantiates, 1, "window instantiates exactly once before UI-manager add")
equal(table.concat(window.phaseOrder, ","), "initialise,instantiate,manager,visible",
    "window lifecycle orders child construction before manager add and visibility")
equal(mp.windowChildren, 1, "window child phase runs exactly once")
equal(window.baseCloseControls, 1, "base close controls are created exactly once")
equal(#window.children, 7, "base close control and six SLA controls are created once")
expect(state.xpEntry.initialised and state.levelsEntry.initialised
    and state.awardXpButton.initialised and state.awardLevelsButton.initialised
    and state.clearSlotsButton.initialised and state.refreshButton.initialised,
    "all SLA entries and buttons initialise exactly once")
expect(not state.awardXpButton.enabled and not state.awardLevelsButton.enabled,
    "mutations disable while inspection waits")
expect(not state.clearSlotsButton.visible and not state.clearSlotsButton.enabled,
    "clear action stays hidden before a tracked summary exists")
option:click()
equal(#mp.windows, 1, "reopening exact route does not stack")
equal(#mp.requests, 1, "reopening exact route sends no duplicate")
equal(window.broughtToTop, 1, "reopening raises existing panel")

mp.status = {
    ok = true,
    pending = true,
    requestId = "request-1",
    operation = "inspect",
    target = { username = "Alpha" },
}
window:prerender()
equal(window.priorPrerenders, 1, "panel cadence chains vanilla once")
equal(mp.lastStatusSlot, 2, "pending cadence reads exact slot")
equal(#mp.requests, 1, "pending cadence sends no traffic")

local canonical = { onlineId = 77, username = "Alpha" }
mp.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-1",
        operation = "inspect",
        target = canonical,
        ok = true,
        outcome = "inspected",
        summary = summary(7, 5, 2),
    },
}
window:prerender()
equal(state.target.onlineId, 77, "successful inspect retains canonical online ID")
equal(state.target.username, "Alpha", "successful inspect retains canonical username")
expect(state.target ~= canonical, "canonical target retained detached")
expect(state.summary ~= mp.status.result.summary, "displayed summary retained detached from envelope")
expect(state.awardXpButton.enabled and state.awardLevelsButton.enabled,
    "valid terminal enables mutation controls")
expect(state.clearSlotsButton.visible and state.clearSlotsButton.enabled,
    "tracked summary shows and enables the clear action")
expect(containsDraw(window, "Survivor Level: 5"), "panel draws Survivor Level")
expect(containsDraw(window, "Survivor XP: 25 / 100"), "panel draws exact XP progress")
expect(containsDraw(window, "Available AP: 3"), "panel draws available AP")
expect(containsDraw(window, "Target: Alpha"), "MP panel draws canonical target username")

state.xpEntry:setText("12.5")
state.awardXpButton:click()
equal(#mp.requests, 2, "valid XP activates once")
local xpRequest = mp.requests[2].request
expect(exact(xpRequest, {
    operation = true, target = true, expectedRevision = true, amount = true,
}), "XP mutation shape exact")
equal(xpRequest.operation, "awardSurvivorXp", "XP operation exact")
equal(xpRequest.amount, 12.5, "finite positive XP preserved")
equal(xpRequest.expectedRevision, 7, "XP uses displayed revision")
expect(exact(xpRequest.target, { onlineId = true, username = true })
    and xpRequest.target.onlineId == 77 and xpRequest.target.username == "Alpha",
    "XP uses retained canonical pair")
state.awardXpButton:click()
equal(#mp.requests, 2, "disabled second XP click cannot duplicate")

mp.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-2",
        operation = "awardSurvivorXp",
        target = { onlineId = 77, username = "Alpha" },
        ok = true,
        outcome = "applied",
        levelsGained = 1,
        apGained = 1,
        summary = summary(8, 6, 2, 10),
    },
}
window:prerender()
equal(state.summary.revision, 8, "applied terminal replaces complete summary")
equal(state.target.onlineId, 77, "applied terminal keeps canonical target")
equal(state.message, "Survivor progression updated.", "applied copy bounded")

state.levelsEntry:setText("2")
state.awardLevelsButton:click()
equal(#mp.requests, 3, "valid level award activates once")
local levelRequest = mp.requests[3].request
expect(exact(levelRequest, {
    operation = true, target = true, expectedRevision = true, count = true,
}), "level mutation shape exact")
equal(levelRequest.count, 2, "positive safe integer count preserved")
equal(levelRequest.expectedRevision, 8, "levels use displayed revision")
mp.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-3",
        operation = "awardSurvivorLevels",
        target = { onlineId = 77, username = "Alpha" },
        ok = true,
        outcome = "rejected",
        code = "stale_revision",
        detail = "secret backend stale detail",
        summary = summary(9, 7, 2, 12),
    },
}
window:prerender()
equal(state.summary.revision, 9, "stale terminal replaces complete summary")
equal(state.message, "Survivor data changed. Refresh and try again.", "stale gives short retry copy")
equal(#mp.requests, 3, "stale terminal never resubmits")

state.xpEntry:setText("1")
state.awardXpButton:click()
mp.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-4",
        operation = "awardSurvivorXp",
        target = { onlineId = 77, username = "Alpha" },
        ok = false,
        code = "publish_failed",
        detail = "secret raw backend detail",
        committed = true,
    },
}
window:prerender()
equal(state.message, "The change may have applied. Refresh before trying again.",
    "committed ambiguity explicitly directs refresh")
equal(string.find(state.message, "secret", 1, true), nil, "failure copy omits backend detail")

state.clearSlotsButton:click()
equal(#mp.requests, 5, "tracked clear activates once")
local clearRequest = mp.requests[5].request
expect(exact(clearRequest, {
    operation = true, target = true, expectedRevision = true,
}), "clear mutation shape has no operand")
equal(clearRequest.operation, "clearAdvancementSlots", "clear operation exact")
equal(clearRequest.expectedRevision, 9, "clear uses displayed current revision")
expect(exact(clearRequest.target, { onlineId = true, username = true })
    and clearRequest.target.onlineId == 77 and clearRequest.target.username == "Alpha",
    "clear uses retained canonical pair")
expect(not state.clearSlotsButton.enabled and not state.awardXpButton.enabled
    and not state.awardLevelsButton.enabled and not state.xpEntry.editable
    and not state.levelsEntry.editable,
    "pending clear disables every panel mutation")
state.clearSlotsButton:click()
state.awardXpButton:click()
equal(#mp.requests, 5, "pending clear suppresses duplicate and other mutations")
mp.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-5",
        operation = "clearAdvancementSlots",
        target = { onlineId = 77, username = "Alpha" },
        ok = true,
        outcome = "applied",
        levelsGained = 0,
        apGained = 0,
        summary = summary(10, 7, 2, 12),
    },
}
window:prerender()
equal(state.summary.revision, 10, "applied clear replaces the complete summary")
equal(state.message, "Survivor progression updated.", "applied clear uses bounded copy")
expect(state.clearSlotsButton.visible and state.clearSlotsButton.enabled,
    "tracked clear re-enables after its terminal")

state.clearSlotsButton:click()
equal(#mp.requests, 6, "second tracked clear sends once")
mp.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-6",
        operation = "clearAdvancementSlots",
        target = { onlineId = 77, username = "Alpha" },
        ok = true,
        outcome = "rejected",
        code = "stale_revision",
        detail = "secret stale clear detail",
        summary = summary(11, 7, 2, 12),
    },
}
window:prerender()
equal(state.summary.revision, 11, "stale clear replaces the complete summary")
equal(state.message, "Survivor data changed. Refresh and try again.",
    "stale clear keeps the existing refresh instruction")
equal(#mp.requests, 6, "stale clear never retries")

local requestsBeforeInvalid = #mp.requests
local invalidXp = { "", "0", "-1", "1e309" }
for index = 1, #invalidXp do
    state.xpEntry:setText(invalidXp[index])
    state.awardXpButton:click()
end
equal(#mp.requests, requestsBeforeInvalid, "invalid XP boundaries send nothing")
local invalidLevels = { "0", "-1", "1.5", "9007199254740992" }
for index = 1, #invalidLevels do
    state.levelsEntry:setText(invalidLevels[index])
    state.awardLevelsButton:click()
end
equal(#mp.requests, requestsBeforeInvalid, "invalid level boundaries send nothing")
equal(string.find(state.message or "", ";", 1, true), nil, "validation copy has no semicolon")

state.refreshButton:click()
equal(#mp.requests, requestsBeforeInvalid + 1, "refresh sends one inspection")
local refreshRequest = mp.requests[#mp.requests].request
expect(exact(refreshRequest, { operation = true, target = true })
    and exact(refreshRequest.target, { username = true }), "refresh returns to username-only inspect")
equal(refreshRequest.target.username, "Alpha", "refresh preserves canonical username")

local attach = makeEnvironment("multiplayer")
expect(attach.integration.install().ok, "attachment environment installs")
attach.status = {
    ok = true, pending = true, requestId = "existing", operation = "inspect",
    target = { username = "Beta" },
}
attach:openFromScoreboard("Beta", 1)
equal(#attach.requests, 0, "same exact pending inspect route attaches without request")
local attachState = rawget(attach.windows[1], "__slaAdminState")
expect(attachState.waiting, "same exact route remains waiting")
equal(attachState.pendingRequestId, "existing", "attachment retains exact pending request ID")
attach.status = {
    ok = true, pending = true, requestId = "other", operation = "inspect",
    target = { username = "SomeoneElse" },
}
attach:openFromScoreboard("Busy", 1)
equal(#attach.requests, 0, "different exact pending route sends no request")
local busyState = rawget(attach.windows[2], "__slaAdminState")
equal(busyState.message, "Another admin request is pending.",
    "different exact pending route shows bounded busy copy")
attach.status = {
    ok = true, pending = true, requestId = "existing", operation = "inspect",
    target = { username = "Gamma" }, extra = true,
}
attach:openFromScoreboard("Gamma", 1)
equal(#attach.requests, 0, "extra pending shape is rejected without duplicate")
local rejectedState = rawget(attach.windows[3], "__slaAdminState")
expect(not rejectedState.waiting, "extra pending shape cannot attach")
equal(rejectedState.message, "The request failed. Refresh and try again.",
    "malformed pending shape uses bounded failure copy")
attach.status = {
    ok = true, pending = true, requestId = "existing", operation = "inspect",
    target = { username = "Delta" },
    route = { operation = "inspect", target = { username = "Delta" } },
}
attach:openFromScoreboard("Delta", 1)
equal(#attach.requests, 0, "nested route shape is rejected without compatibility branch")
equal(rawget(attach.windows[4], "__slaAdminState").message,
    "The request failed. Refresh and try again.", "nested pending shape fails closed")
equal(#attach.windows, 4, "target switching replaces rather than mutates prior target panel")
expect(attach.windows[1].removed and attach.windows[2].removed and attach.windows[3].removed,
    "target switching removes earlier slot windows")

local statusThrow = makeEnvironment("multiplayer")
expect(statusThrow.integration.install().ok, "status-throw environment installs")
statusThrow.statusThrows = true
statusThrow:openFromScoreboard("NoSend", 0)
equal(#statusThrow.requests, 0, "throwing opening status sends no inspection")
equal(rawget(statusThrow.windows[1], "__slaAdminState").message,
    "The request failed. Refresh and try again.", "throwing status fails closed visibly")

local malformedStatus = makeEnvironment("multiplayer")
expect(malformedStatus.integration.install().ok, "malformed-status environment installs")
malformedStatus.status = { ok = true, pending = false, extra = true }
malformedStatus:openFromScoreboard("NoSend", 0)
equal(#malformedStatus.requests, 0, "malformed opening status sends no inspection")
equal(rawget(malformedStatus.windows[1], "__slaAdminState").message,
    "The request failed. Refresh and try again.", "malformed status fails closed visibly")

local malformedTerminalStatus = makeEnvironment("multiplayer")
expect(malformedTerminalStatus.integration.install().ok,
    "malformed-terminal-status environment installs")
malformedTerminalStatus.status = { ok = true, pending = false, result = {} }
malformedTerminalStatus:openFromScoreboard("NoSend", 0)
equal(#malformedTerminalStatus.requests, 0,
    "malformed retained terminal status sends no inspection")
equal(rawget(malformedTerminalStatus.windows[1], "__slaAdminState").message,
    "The request failed. Refresh and try again.", "malformed retained terminal fails closed visibly")

local malformedClearGainCases = {
    { label = "missing clear gains" },
    { label = "nonzero clear gains", levelsGained = 1, apGained = 0 },
}
for index = 1, #malformedClearGainCases do
    local gainCase = malformedClearGainCases[index]
    local retainedClear = makeEnvironment("multiplayer")
    expect(retainedClear.integration.install().ok,
        gainCase.label .. " retained-status environment installs")
    local result = {
        requestId = "old-clear",
        operation = "clearAdvancementSlots",
        target = { onlineId = 14, username = "ClearTarget" },
        ok = true,
        outcome = "applied",
        summary = summary(4, 5, 2),
    }
    if gainCase.levelsGained ~= nil then result.levelsGained = gainCase.levelsGained end
    if gainCase.apGained ~= nil then result.apGained = gainCase.apGained end
    retainedClear.status = { ok = true, pending = false, result = result }
    retainedClear:openFromScoreboard("ClearTarget", 0)
    equal(#retainedClear.requests, 0,
        gainCase.label .. " retained terminal starts no inspection")
    equal(rawget(retainedClear.windows[1], "__slaAdminState").message,
        "The request failed. Refresh and try again.",
        gainCase.label .. " retained terminal fails closed")
end

local transportEnvelopeStatus = makeEnvironment("multiplayer")
expect(transportEnvelopeStatus.integration.install().ok,
    "transport-envelope-status environment installs")
transportEnvelopeStatus.status = {
    ok = true,
    pending = false,
    result = {
        protocolVersion = 1,
        requestId = "old",
        operation = "inspect",
        target = { onlineId = 4, username = "NoSend" },
        ok = true,
        outcome = "inspected",
        summary = summary(1, 2, 0),
    },
}
transportEnvelopeStatus:openFromScoreboard("NoSend", 0)
equal(#transportEnvelopeStatus.requests, 0,
    "transport protocol field is rejected from lifecycle status")
equal(rawget(transportEnvelopeStatus.windows[1], "__slaAdminState").message,
    "The request failed. Refresh and try again.", "transport envelope fails UI status closed")

local priorTerminal = makeEnvironment("multiplayer")
expect(priorTerminal.integration.install().ok, "prior-terminal environment installs")
priorTerminal:openFromScoreboard("Prior", 0)
local priorWindow = priorTerminal.windows[1]
priorTerminal.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-1",
        operation = "inspect",
        target = { onlineId = 5, username = "Prior" },
        ok = true,
        outcome = "inspected",
        summary = summary(1, 2, 0),
    },
}
priorWindow:prerender()
expect(rawget(priorWindow, "__slaAdminState").summary ~= nil,
    "exact protocol-free lifecycle terminal is accepted")
priorWindow:close()
expect(priorWindow.removed, "prior terminal panel closes cleanly")
local reopened = priorTerminal.integration.open(0, "Prior")
expect(reopened.ok, "panel reopens after retained lifecycle terminal")
equal(#priorTerminal.requests, 2, "reopen after prior terminal starts one new inspection")
expect(exact(priorTerminal.requests[2].request, { operation = true, target = true })
    and exact(priorTerminal.requests[2].request.target, { username = true }),
    "reopen inspection remains username-only")
equal(priorTerminal.requests[2].request.target.username, "Prior",
    "reopen inspection preserves selected username")

local replacedRoute = makeEnvironment("multiplayer")
expect(replacedRoute.integration.install().ok, "replaced-route environment installs")
replacedRoute:openFromScoreboard("Same", 0)
local replacedWindow = replacedRoute.windows[1]
local replacedState = rawget(replacedWindow, "__slaAdminState")
equal(replacedState.pendingRequestId, "request-1", "accepted request ID retained")
replacedRoute.status = {
    ok = true, pending = true, requestId = "replacement", operation = "inspect",
    target = { username = "Same" },
}
replacedWindow:prerender()
expect(not replacedState.waiting and replacedState.pendingRequestId == nil,
    "same-target replacement request ID fails correlation closed")
equal(replacedState.message, "The request failed. Refresh and try again.",
    "replaced route shows bounded failure")

local wrongTerminalId = makeEnvironment("multiplayer")
expect(wrongTerminalId.integration.install().ok, "wrong-terminal-ID environment installs")
wrongTerminalId:openFromScoreboard("Terminal", 0)
local wrongTerminalWindow = wrongTerminalId.windows[1]
local wrongTerminalState = rawget(wrongTerminalWindow, "__slaAdminState")
wrongTerminalId.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "replacement",
        operation = "inspect",
        target = { onlineId = 8, username = "Terminal" },
        ok = true,
        outcome = "inspected",
        summary = summary(1, 2, 0),
    },
}
wrongTerminalWindow:prerender()
expect(wrongTerminalState.summary == nil and not wrongTerminalState.waiting,
    "terminal with replaced request ID fails correlation closed")
equal(wrongTerminalState.message, "The request failed. Refresh and try again.",
    "wrong terminal request ID uses bounded failure")

local missingOperation = makeEnvironment("multiplayer")
expect(missingOperation.integration.install().ok, "missing-operation environment installs")
missingOperation:openFromScoreboard("Missing", 0)
local missingWindow = missingOperation.windows[1]
local missingState = rawget(missingWindow, "__slaAdminState")
missingOperation.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-1",
        target = { onlineId = 9, username = "Missing" },
        ok = true,
        outcome = "inspected",
        summary = summary(1, 2, 0),
    },
}
missingWindow:prerender()
expect(missingState.summary == nil and not missingState.waiting,
    "terminal missing exact operation fails closed")
equal(missingState.message, "The request failed. Refresh and try again.",
    "missing operation uses bounded failure")

local badSelector = makeEnvironment("multiplayer")
expect(badSelector.integration.install().ok, "bad-selector environment installs")
badSelector:openFromScoreboard("Selector", 0)
local badSelectorWindow = badSelector.windows[1]
local badSelectorState = rawget(badSelectorWindow, "__slaAdminState")
badSelector.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-1",
        operation = "inspect",
        target = { username = "Selector", extra = true },
        ok = false,
        code = "denied",
        detail = "secret selector detail",
        committed = false,
    },
}
badSelectorWindow:prerender()
expect(not badSelectorState.waiting and badSelectorState.pendingRequestId == nil,
    "inspect failure with extra selector field fails closed")
equal(badSelectorState.message, "The request failed. Refresh and try again.",
    "malformed failure selector exposes no backend detail")

local wrongRoute = makeEnvironment("multiplayer")
expect(wrongRoute.integration.install().ok, "wrong-route environment installs")
wrongRoute:openFromScoreboard("Route", 0)
local wrongWindow = wrongRoute.windows[1]
local wrongState = rawget(wrongWindow, "__slaAdminState")
wrongRoute.status = {
    ok = true, pending = true, requestId = "request-1", operation = "inspect",
    target = { username = "Other" },
}
wrongWindow:prerender()
expect(not wrongState.waiting, "mismatched pending route fails closed")
equal(wrongState.message, "The request failed. Refresh and try again.",
    "mismatched pending route uses bounded failure copy")

local freeMode = makeEnvironment("multiplayer")
expect(freeMode.integration.install().ok, "Free-mode environment installs")
freeMode:openFromScoreboard("FreeTarget", 0)
local freeWindow = freeMode.windows[1]
local freeState = rawget(freeWindow, "__slaAdminState")
freeMode.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-1",
        operation = "inspect",
        target = { onlineId = 12, username = "FreeTarget" },
        ok = true,
        outcome = "inspected",
        summary = summary(2, 3, 1, 25, "Free"),
    },
}
freeWindow:prerender()
expect(not freeState.clearSlotsButton.visible and not freeState.clearSlotsButton.enabled,
    "Free summary hides and disables the clear action")
freeState.clearSlotsButton:click()
equal(#freeMode.requests, 1, "hidden Free clear action sends nothing")

local lost = makeEnvironment("multiplayer")
expect(lost.integration.install().ok, "ownership environment installs")
lost.Scoreboard.doPlayerListContextMenu = function() end
local lostResult = lost.integration.install()
equal(lostResult.ok, false, "lost scoreboard hook fails closed")
equal(lostResult.code, "hook_ownership_lost", "lost scoreboard ownership code")

local childFailure = makeEnvironment("multiplayer")
childFailure.childConstructionThrows = true
local childFailureResult = childFailure.integration.open(0, "Cleanup")
equal(childFailureResult.ok, false, "child-construction failure is bounded")
equal(childFailureResult.code, "window_create_failed", "child-construction failure code")
equal(#childFailure.windows, 1, "failed child phase creates only one candidate window")
expect(childFailure.windows[1].removed and not childFailure.windows[1].visible,
    "failed child phase performs bounded window cleanup")
equal(#childFailure.requests, 0, "failed child phase sends no inspection")

local throwing = makeEnvironment("multiplayer")
expect(throwing.integration.install().ok, "throwing vanilla environment installs")
throwing.priorThrows = true
local throwingScoreboard, throwingPlayer = throwing:scoreboard("Throw", 0)
local wrapperOk = pcall(function()
    throwing.Scoreboard.doPlayerListContextMenu(throwingScoreboard, throwingPlayer, 0, 0)
end)
expect(not wrapperOk, "vanilla scoreboard failure propagates")
equal(throwing.priorMenus, 1, "throwing vanilla scoreboard is called exactly once")
equal(throwing.existingMenuGets, 0, "throwing vanilla scoreboard appends nothing")

local sp = makeEnvironment("singleplayer")
sp.viewportWidth = 1920
sp.viewportHeight = 1080
sp.requestHandler = function(_, request)
    if request.operation == "inspect" then
        return { ok = true, operation = "inspect", outcome = "inspected", summary = summary(3, 4, 1) }
    end
    return {
        ok = true,
        operation = request.operation,
        outcome = "applied",
        summary = summary(request.expectedRevision + 1, 5, 1),
    }
end
expect(sp.integration.install().ok, "SP installs without scoreboard hook")
expect(sp.integration.isAvailable(3), "SP launcher visible with live debug")
equal(sp.debugReads, 1, "SP launcher rechecks live debug")
local opened = sp.integration.open(3)
expect(exact(opened, { ok = true }), "SP panel opens exactly")
equal(#sp.requests, 1, "SP opening inspects once")
equal(sp.requests[1].slot, 3, "SP inspection preserves slot")
expect(exact(sp.requests[1].request, { operation = true }), "SP inspection is targetless")
local spWindow = sp.windows[1]
local spState = rawget(spWindow, "__slaAdminState")
expect(spState.summary ~= nil and spState.target == nil, "SP retains summary without synthetic target")
spWindow:prerender()
equal(containsDraw(spWindow, "Target:"), false, "SP panel omits target identity")
spState.xpEntry:setText("2.25")
spState.awardXpButton:click()
equal(#sp.requests, 2, "SP XP request applies synchronously")
expect(exact(sp.requests[2].request, {
    operation = true, expectedRevision = true, amount = true,
}), "SP XP request remains targetless")
spState.levelsEntry:setText("2")
spState.awardLevelsButton:click()
expect(exact(sp.requests[3].request, {
    operation = true, expectedRevision = true, count = true,
}), "SP level request remains targetless")
sp.integration.open(3)
equal(#sp.windows, 1, "SP reopening does not stack")
equal(#sp.requests, 4, "SP reopening a terminal panel starts one fresh inspection")
spWindow:close()
expect(spWindow.removed, "close removes the panel from UI manager")
sp.integration.open(3)
equal(#sp.windows, 2, "reopen after close creates one replacement")
equal(#sp.requests, 5, "reopen after close begins one fresh inspection")
local reopenedState = rawget(sp.windows[2], "__slaAdminState")
sp.debug = false
sp.windows[2]:prerender()
expect(not reopenedState.awardXpButton.enabled and not reopenedState.awardLevelsButton.enabled,
    "live debug loss disables SP mutations immediately")
expect(not sp.integration.isAvailable(3), "SP launcher disappears after debug loss")
local unavailable = sp.integration.open(3)
equal(unavailable.ok, false, "SP open fails while debug unavailable")
equal(unavailable.code, "debug_unavailable", "SP debug loss failure code")
equal(#sp.requests, 5, "SP debug loss sends no request")

local malformedImmediateCases = {
    {
        label = "missing ok",
        result = { operation = "inspect", committed = true },
    },
    {
        label = "nonboolean ok",
        result = { operation = "inspect", ok = "yes", committed = true },
    },
}
for index = 1, #malformedImmediateCases do
    local immediateCase = malformedImmediateCases[index]
    local immediate = makeEnvironment("singleplayer")
    immediate.requestHandler = function() return immediateCase.result end
    expect(immediate.integration.install().ok,
        immediateCase.label .. " immediate environment installs")
    local immediateOpen = immediate.integration.open(0)
    expect(immediateOpen.ok, immediateCase.label .. " panel opens with bounded failure")
    equal(#immediate.requests, 1, immediateCase.label .. " immediate request occurs once")
    local immediateState = rawget(immediate.windows[1], "__slaAdminState")
    expect(immediateState.summary == nil and immediateState.target == nil,
        immediateCase.label .. " adopts no summary or target")
    equal(immediateState.message, "The request failed. Refresh and try again.",
        immediateCase.label .. " uses generic UI failure")
end

local malformedSummary = makeEnvironment("singleplayer")
malformedSummary.requestHandler = function()
    local invalid = summary(1, 2, 0)
    invalid.accountingMode = "PerSkill"
    return { ok = true, operation = "inspect", outcome = "inspected", summary = invalid }
end
expect(malformedSummary.integration.install().ok, "malformed-summary environment installs")
expect(malformedSummary.integration.open(0).ok, "malformed-summary panel opens")
local malformedSummaryState = rawget(malformedSummary.windows[1], "__slaAdminState")
expect(malformedSummaryState.summary == nil and not malformedSummaryState.clearSlotsButton.visible,
    "malformed accounting mode adopts no summary and exposes no clear action")
equal(malformedSummaryState.message, "The request failed. Refresh and try again.",
    "malformed summary fails closed with bounded copy")

for index = 1, #malformedClearGainCases do
    local gainCase = malformedClearGainCases[index]
    local immediateClear = makeEnvironment("singleplayer")
    immediateClear.requestHandler = function(_, request)
        if request.operation == "inspect" then
            return {
                ok = true,
                operation = "inspect",
                outcome = "inspected",
                summary = summary(6, 5, 2),
            }
        end
        local result = {
            ok = true,
            operation = "clearAdvancementSlots",
            outcome = "applied",
            summary = summary(7, 5, 2),
        }
        if gainCase.levelsGained ~= nil then result.levelsGained = gainCase.levelsGained end
        if gainCase.apGained ~= nil then result.apGained = gainCase.apGained end
        return result
    end
    expect(immediateClear.integration.install().ok,
        gainCase.label .. " immediate environment installs")
    expect(immediateClear.integration.open(0).ok,
        gainCase.label .. " immediate panel opens")
    local immediateState = rawget(immediateClear.windows[1], "__slaAdminState")
    immediateState.clearSlotsButton:click()
    equal(#immediateClear.requests, 2, gainCase.label .. " clear requests once")
    equal(immediateState.summary.revision, 6,
        gainCase.label .. " adopts no malformed replacement summary")
    equal(immediateState.message, "The request failed. Refresh and try again.",
        gainCase.label .. " active terminal fails closed")
end

return assertions
