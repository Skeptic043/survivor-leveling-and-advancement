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
    IGUI_SLA_Admin_ProfilePrimary = "Primary profile",
    IGUI_SLA_Admin_ProfileCoop = "Co-op profile %1",
    IGUI_SLA_Admin_ProfileSelected = "Profile: %1",
    IGUI_SLA_Admin_SelectProfile = "Offline character profiles",
    IGUI_SLA_Admin_ProfileDead = "Read-only: this character is dead.",
    IGUI_SLA_Admin_ProfileUninitialized = "Read-only: Survivor progression is not initialized.",
    IGUI_SLA_Admin_QueueClear = "Queue Clear Advancements",
    IGUI_SLA_Admin_CancelPending = "Cancel Pending",
    IGUI_SLA_Admin_Acknowledge = "Acknowledge",
    IGUI_SLA_Admin_MailboxPending = "Pending clear",
    IGUI_SLA_Admin_MailboxApplied = "Applied clear",
    IGUI_SLA_Admin_MailboxFailed = "Failed clear",
    IGUI_SLA_Admin_MailboxCancelled = "Cancelled clear",
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

local function summary(revision, level, spent, xp, accountingMode, xpForNextLevel)
    return {
        accountingMode = accountingMode or "Tracked",
        revision = revision,
        level = level,
        xpIntoLevel = xp or 25,
        xpForNextLevel = xpForNextLevel or 100,
        spent = spent,
        availableAp = level - spent,
    }
end

local function offlineSummary(username, profileIndex, incarnationId, revision)
    local result = summary(revision, 5, 2)
    result.username = username
    result.profileIndex = profileIndex
    result.incarnationId = incarnationId
    result.initialized = true
    result.dead = false
    return result
end

local function makeEnvironment(processMode)
    local nativeElement = VanillaUiLifecycle({ new = function(luaElement)
        local javaElement = { luaElement = luaElement, children = {} }
        for _, name in ipairs({ "setX", "setY", "setHeight", "setWidth", "setAnchorLeft",
            "setAnchorRight", "setAnchorTop", "setAnchorBottom", "setWantKeyEvents",
            "setConsumeMouseEvents", "setWantExtraMouseEvents", "setForceCursorVisible" }) do
            javaElement[name] = function() end
        end
        function javaElement:AddChild(child) self.children[#self.children + 1] = child end
        return javaElement
    end })
    function nativeElement:derive() return setmetatable({}, { __index = self }) end
    local nativeJoypad, nativeBounds = VanillaPanelJoypad(nativeElement, { AButton = "A", BButton = "B", XButton = "X" })
    math.clamp = math.clamp or function(value, low, high) return math.max(low, math.min(high, value)) end
    local function geometry(control)
        nativeElement.initialise(control)
        control.instantiate = nativeElement.instantiate
        control.createChildren = function() end
        control.getParent = nativeElement.getParent
        control.addChild = nativeElement.addChild
        function control:isReallyVisible() return self.visible ~= false and self.removed ~= true end
        function control:setJoypadFocused(value) self.joypadFocused = value end
        function control:getX() return self.x end
        function control:getY() return self.y end
        function control:getWidth() return self.width end
        function control:getHeight() return self.height end
        function control:getAbsoluteBounds() return nativeBounds:new(self.x, self.y, self.width, self.height) end
        function control:toDebugString() return "test control" end
        function control:setX(value) self.x = value end
        function control:setY(value) self.y = value end
        function control:setWidth(value) self.width = value end
        function control:setHeight(value) self.height = value end
        return control
    end
    local evidence = {
        mode = processMode,
        serverReads = 0,
        clientReads = 0,
        debugReads = 0,
        debug = true,
        canSee = true,
        priorMenus = 0,
        priorUsersMenus = 0,
        vanillaContextGets = 0,
        vanillaUsersContextGets = 0,
        existingMenuGets = 0,
        capabilityReads = 0,
        specificPlayerReads = 0,
        specificPlayerSlots = {},
        localPlayers = {},
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
        joypads = {},
        focusChanges = {},
    }

    local Scoreboard = {}
    local UsersList = {}
    local Window = {}
    Window.onGainJoypadFocus = nativeElement.onGainJoypadFocus
    Window.onLoseJoypadFocus = nativeElement.onLoseJoypadFocus
    Window.onJoypadDown = nativeJoypad.onJoypadDown
    local Entry = {}
    local Button = {}
    local Capability = { CanSeePlayersStats = {} }

    local function localPlayer(slot, username)
        local role = {
            hasCapability = function(_, value)
                evidence.capabilityReads = evidence.capabilityReads + 1
                evidence.lastCapability = value
                return evidence.canSee
            end,
        }
        return {
            getRole = function() return role end,
            getUsername = function() return username end,
        }
    end

    for slot = 0, 3 do
        evidence.localPlayers[slot] = localPlayer(slot, "Local" .. tostring(slot))
    end

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

    function UsersList.doContextMenu(self, item, x, y)
        evidence.priorUsersMenus = evidence.priorUsersMenus + 1
        evidence.vanillaUsersContextGets = evidence.vanillaUsersContextGets + 1
        evidence.menu = makeMenu()
        if evidence.priorUsersThrows then error("vanilla users menu boom") end
        return "users", x, y
    end

    function Window.createChildren(self)
        evidence.windowChildren = evidence.windowChildren + 1
        if evidence.childConstructionThrows then error("child construction boom") end
        self.baseCloseControls = (self.baseCloseControls or 0) + 1
        self:addChild(geometry({ baseCloseControl = true }))
    end

    function Window.prerender(self)
        self.priorPrerenders = self.priorPrerenders + 1
        if self.prerenderThrows then error("vanilla window boom") end
        local state = rawget(self, "__slaAdminState")
        if state and state.pane then state.pane:prerender() end
    end

    function Window.instantiate(self)
        self.phaseOrder[#self.phaseOrder + 1] = "instantiate"
        self.instantiates = (self.instantiates or 0) + 1
        if evidence.instantiateThrows then error("instantiate boom") end
        nativeElement.instantiate(self)
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
        function window:drawText(text, drawX, drawY)
            self.draws[#self.draws + 1] = { text = text, x = drawX, y = drawY }
        end
        geometry(window)
        window.instantiate = Window.instantiate
        window.joypadButtonsY, window.joypadButtons, window.allJoypadButtons = {}, {}, {}
        window.joypadIndex, window.joypadIndexY = 0, 0
        setmetatable(window, { __index = nativeJoypad })
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
        function entry:setVisible(value) self.visible = value end
        function entry:focus() self.focused = true; return "focused" end
        return geometry(entry)
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
        function button:setTitle(value) self.title = value end
        function button:click()
            if self.enabled and self.onclick ~= nil then self.onclick(self.target, self) end
        end
        button.isButton = true
        button.forceClick = button.click
        return geometry(button)
    end

    local owner = {
        install = function() return { ok = true } end,
        status = function() return { ok = true } end,
        clientState = function() return { ok = true, present = false } end,
        refreshOwner = function() return { ok = true } end,
        setAdminResultListener = function() return { ok = true } end,
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
        ISUsersList = UsersList,
        ISCollapsableWindowJoypad = Window,
        ISTextEntryBox = Entry,
        ISButton = Button,
        ISPanel = { new = function(_, x, y, width, height)
            local panel = geometry({ x = x, y = y, width = width, height = height, children = {}, scroll = 0 })
            function panel:initialise() end
            function panel:setScrollChildren(value) self.scrollChildren = value end
            function panel:addScrollBars() self.scrollBars = true end
            function panel:setScrollHeight(value) self.scrollHeight = value end
            function panel:getYScroll() return self.scroll end
            function panel:setYScroll(value) self.scroll = math.max(-math.max(0, (self.scrollHeight or 0) - self.height), math.min(0, value)) end
            function panel:setStencilRect() end
            function panel:clearStencilRect() end
            function panel:repaintStencilRect() self.repainted = true end
            function panel:drawText(text, x, y) self.parent:drawText(text, x, y + self.y + self.scroll) end
            return panel
        end },
        canSeePlayersStats = Capability.CanSeePlayersStats,
        getPlayerContextMenu = function(slot)
            evidence.existingMenuGets = evidence.existingMenuGets + 1
            evidence.lastMenuSlot = slot
            return evidence.menu
        end,
        getSpecificPlayer = function(slot)
            evidence.specificPlayerReads = evidence.specificPlayerReads + 1
            evidence.specificPlayerSlots[#evidence.specificPlayerSlots + 1] = slot
            if evidence.getSpecificThrows then error("specific player boom") end
            return evidence.localPlayers[slot]
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
        measureText = function(text)
            evidence.measureCalls = (evidence.measureCalls or 0) + 1
            return #text * (evidence.charWidth or 5)
        end,
        fontHeight = function() return evidence.fontHeight or 12 end,
        viewport = function(slot)
            evidence.viewportSlot = slot
            return evidence.viewportLeft, evidence.viewportTop,
                evidence.viewportWidth, evidence.viewportHeight
        end,
        smallFont = "small-font",
        joypadBButton = "B",
        getJoypadData = function(slot) return evidence.joypads[slot] end,
        setJoypadFocus = function(slot, control)
            evidence.focusChanges[#evidence.focusChanges + 1] = { slot = slot, control = control }
            local data = evidence.joypads[slot]
            if data then data.focus = control end
        end,
    }

    local created = Build42AdminUi.create(dependencies)
    expect(created.ok, processMode .. " integration creates")
    evidence.integration = created.integration
    evidence.dependencies = dependencies
    evidence.owner = owner
    evidence.Scoreboard = Scoreboard
    evidence.UsersList = UsersList
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
        local option = self.menu.options[1]
        option:click()
        return option, a, b, c
    end

    function evidence:usersList(username, slot, online)
        local role = setmetatable({}, { __index = function(_, key)
            if key == "hasCapability" then
                return function(_, value)
                    evidence.capabilityReads = evidence.capabilityReads + 1
                    evidence.lastCapability = value
                    return evidence.canSee
                end
            end
        end })
        local actor = setmetatable({}, { __index = function(_, key)
            if key == "getRole" then return function() return role end end
            if key == "getPlayerNum" then return function() return slot or 0 end end
        end })
        local item = setmetatable({}, { __index = function(_, key)
            if key == "isOnline" then return function() return online ~= false end end
            if key == "getUsername" then return function() return username end end
        end })
        return { player = actor }, item
    end

    function evidence:openFromUsersList(username, slot)
        local usersList, item = self:usersList(username, slot, true)
        local a, b, c = self.UsersList.doContextMenu(usersList, item, 33, 44)
        local option = self.menu.options[1]
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
    local rendered = {}
    for index = 1, #window.draws do
        if string.find(window.draws[index].text, text, 1, true) ~= nil then return true end
        rendered[#rendered + 1] = window.draws[index].text
    end
    return string.find(table.concat(rendered):gsub("%s", ""), text:gsub("%s", ""), 1, true) ~= nil
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

expect(mp.integration.isAvailable(2), "MP launcher is available for the exact authorized local slot")
equal(mp.specificPlayerSlots[#mp.specificPlayerSlots], 2,
    "MP availability resolves only the requested local slot")

local selfAdmin = makeEnvironment("multiplayer")
expect(selfAdmin.integration.install().ok, "self-admin environment installs")
expect(selfAdmin.integration.isAvailable(2), "self-admin local slot is available")
local selfOpened = selfAdmin.integration.open(2)
expect(exact(selfOpened, { ok = true }), "self-admin opens without an explicit username")
equal(#selfAdmin.requests, 1, "self-admin opening issues one inspection")
equal(selfAdmin.requests[1].slot, 2, "self-admin inspection keeps the exact local slot")
expect(exact(selfAdmin.requests[1].request, { operation = true, target = true })
    and exact(selfAdmin.requests[1].request.target, { username = true })
    and selfAdmin.requests[1].request.target.username == "Local2",
    "self-admin inspection derives only the exact local username")
local selfWindow = selfAdmin.windows[1]
local selfState = rawget(selfWindow, "__slaAdminState")
equal(selfState.selectedUsername, "Local2", "self-admin panel retains the bounded local username")
selfAdmin.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-1",
        operation = "inspect",
        target = { onlineId = 42, username = "Local2" },
        ok = true,
        outcome = "inspected",
        summary = summary(1, 2, 0),
    },
}
selfWindow:prerender()
expect(selfState.awardXpButton.enabled and selfState.awardLevelsButton.enabled
    and selfState.clearSlotsButton.enabled and selfState.refreshButton.enabled
    and selfState.xpEntry.editable and selfState.levelsEntry.editable,
    "completed self-admin inspection enables every applicable control")
selfAdmin.canSee = false
expect(not selfAdmin.integration.isAvailable(2), "role loss hides the MP launcher on the next availability read")
selfWindow:prerender()
expect(not selfState.awardXpButton.enabled and not selfState.awardLevelsButton.enabled
    and not selfState.clearSlotsButton.enabled and not selfState.refreshButton.enabled
    and not selfState.xpEntry.editable and not selfState.levelsEntry.editable,
    "role loss disables every applicable control on an already-open MP panel")
equal(#selfAdmin.requests, 1, "role loss sends no request")

local explicitRemote = makeEnvironment("multiplayer")
expect(explicitRemote.integration.open(1, "RemoteTarget").ok,
    "explicit MP remote target still opens")
equal(#explicitRemote.requests, 1, "explicit MP remote target inspects once")
expect(exact(explicitRemote.requests[1].request.target, { username = true })
    and explicitRemote.requests[1].request.target.username == "RemoteTarget",
    "explicit MP target never becomes the local self target")

local usersMenu = makeEnvironment("multiplayer")
expect(usersMenu.integration.install().ok, "Users List environment installs")
expect(usersMenu.integration.install().ok, "Users List repeated install is idempotent")
local hiddenUsers, hiddenUsersItem = usersMenu:usersList("HiddenUser", 3, true)
usersMenu.canSee = false
usersMenu.UsersList.doContextMenu(hiddenUsers, hiddenUsersItem, 1, 2)
equal(usersMenu.priorUsersMenus, 1, "unauthorized Users List still chains vanilla once")
equal(#usersMenu.menu.options, 0, "unauthorized Users List omits SLA action")
equal(usersMenu.existingMenuGets, 0, "unauthorized Users List retrieves no context")
usersMenu.canSee = true
local offlineUsers, offlineItem = usersMenu:usersList("OfflineUser", 3, false)
usersMenu.UsersList.doContextMenu(offlineUsers, offlineItem, 1, 2)
equal(usersMenu.priorUsersMenus, 2, "offline Users List still chains vanilla once")
equal(#usersMenu.menu.options, 1, "offline Users List exposes SLA profile administration")
equal(usersMenu.existingMenuGets, 1, "offline Users List retrieves the existing context once")
local offlineAdmin = makeEnvironment("multiplayer")
expect(offlineAdmin.integration.install().ok, "offline profile-selection environment installs")
local offlineAdminList, offlineAdminItem = offlineAdmin:usersList("OfflineUser", 3, false)
offlineAdmin.UsersList.doContextMenu(offlineAdminList, offlineAdminItem, 1, 2)
local offlineOption = offlineAdmin.menu.options[1]
offlineOption:click()
equal(#offlineAdmin.requests, 1, "offline Users List action enumerates profiles once")
expect(exact(offlineAdmin.requests[1].request, { operation = true, target = true })
    and offlineAdmin.requests[1].request.operation == "enumerateOfflineProfiles"
    and offlineAdmin.requests[1].request.target.username == "OfflineUser",
    "offline launcher sends bounded username enumeration")
local offlineWindow = offlineAdmin.windows[1]
local offlineState = rawget(offlineWindow, "__slaAdminState")
offlineAdmin.status = {
    ok = true,
    pending = false,
    result = {
        requestId = "request-1",
        operation = "enumerateOfflineProfiles",
        target = { username = "OfflineUser" },
        ok = true,
        outcome = "enumerated",
        profiles = {
            offlineSummary("OfflineUser", 0, "offline-primary", 4),
            offlineSummary("OfflineUser", 2, "offline-coop", 7),
        },
    },
}
offlineWindow:prerender()
equal(#offlineState.profileChoices, 2, "multiple offline profiles require an explicit choice")
equal(offlineState.awardXpButton.title, "Primary profile", "primary profile choice is visible")
equal(offlineState.awardLevelsButton.title, "Co-op profile 3", "co-op profile choice is visible")
expect(not offlineState.xpEntry.visible and not offlineState.levelsEntry.visible,
    "mutation entries hide until an offline profile is selected")
offlineState.awardLevelsButton:click()
equal(offlineState.target.profileIndex, 2, "explicit co-op selection retains the exact profile index")
equal(offlineState.target.incarnationId, "offline-coop",
    "explicit co-op selection retains the exact incarnation")
equal(offlineState.summary.revision, 7, "explicit selection displays its persistence revision")
expect(offlineState.xpEntry.visible and offlineState.levelsEntry.visible,
    "mutation entries return after explicit profile selection")
equal(offlineState.clearSlotsButton.title, "Queue Clear Advancements",
    "selected offline profile exposes the durable queue action")
offlineState.summary.dead = true
offlineState.summary.accountingMode = "Free"
offlineState.summary.mailbox = {
    kind = "clearAdvancementSlots", status = "pending",
    incarnationId = "offline-coop", stateRevision = 7,
    queuedPersistenceRevision = 6,
}
offlineWindow:prerender()
expect(not offlineState.awardXpButton.enabled and not offlineState.awardLevelsButton.enabled
    and not offlineState.clearSlotsButton.visible and not offlineState.clearSlotsButton.enabled,
    "Free read-only profile cannot access pending cancellation or progression mutations")
offlineState.clearSlotsButton:click()
equal(#offlineAdmin.requests, 1, "hidden Free pending action dispatches nothing")
expect(containsDraw(offlineWindow, "Read-only: this character is dead."),
    "dead offline profile visibly explains its read-only state")
offlineState.summary.mailbox = {
    kind = "clearAdvancementSlots", status = "cancelled",
    incarnationId = "offline-coop", code = "profile_died",
}
offlineWindow:prerender()
expect(offlineState.clearSlotsButton.visible and offlineState.clearSlotsButton.enabled
    and offlineState.clearSlotsButton.title == "Acknowledge",
    "Free dead profile exposes only terminal acknowledgement")
offlineState.summary.dead = false
offlineState.summary.initialized = false
offlineWindow:prerender()
expect(containsDraw(offlineWindow, "Read-only: Survivor progression is not initialized."),
    "uninitialized offline profile visibly explains its read-only state")
expect(offlineState.clearSlotsButton.visible and offlineState.clearSlotsButton.enabled
    and not offlineState.awardXpButton.enabled and not offlineState.awardLevelsButton.enabled,
    "Free uninitialized profile keeps terminal acknowledgement but no mutation access")
offlineState.clearSlotsButton:click()
equal(#offlineAdmin.requests, 2, "Free terminal acknowledgement dispatches exactly once")
local freeAcknowledgement = offlineAdmin.requests[2].request
expect(exact(freeAcknowledgement, {
    operation = true, target = true, expectedRevision = true,
}), "Free terminal acknowledgement request shape exact")
equal(freeAcknowledgement.operation, "acknowledgeMailbox",
    "Free terminal mailbox dispatches acknowledgement")
equal(freeAcknowledgement.expectedRevision, 7,
    "Free terminal acknowledgement uses displayed persistence revision")
equal(freeAcknowledgement.target.profileIndex, 2,
    "Free terminal acknowledgement preserves selected profile")
equal(freeAcknowledgement.target.incarnationId, "offline-coop",
    "Free terminal acknowledgement preserves exact incarnation")
local malformedUsers, _ = usersMenu:usersList("Malformed", 3, true)
local malformedItem = setmetatable({}, { __index = {
    isOnline = function() return true end,
} })
usersMenu.UsersList.doContextMenu(malformedUsers, malformedItem, 1, 2)
equal(usersMenu.priorUsersMenus, 3, "malformed Users List target still chains vanilla once")
equal(#usersMenu.menu.options, 0, "malformed Users List target adds no SLA action")
local usersOption, usersA, usersB, usersC = usersMenu:openFromUsersList("OnlineUser", 3)
equal(usersA, "users", "Users List wrapper preserves first return")
equal(usersB, 33, "Users List wrapper preserves second return")
equal(usersC, 44, "Users List wrapper preserves third return")
equal(usersMenu.priorUsersMenus, 4, "Users List chains captured vanilla exactly once")
equal(usersMenu.vanillaUsersContextGets, 4, "Users List owns one context construction per invocation")
equal(usersMenu.existingMenuGets, 2, "Users List retrieves the existing context exactly once per valid row")
equal(usersMenu.lastMenuSlot, 3, "Users List existing context uses exact local slot")
equal(usersOption.title, "Survivor progression", "Users List action uses existing localization")
equal(#usersMenu.menu.options, 2, "online Users List row exposes online and offline-profile actions")
equal(usersMenu.menu.options[2].title, "Offline character profiles",
    "online account row labels the separate offline-profile launcher")
equal(#usersMenu.requests, 1, "Users List action sends one inspection")
equal(usersMenu.requests[1].slot, 3, "Users List inspection preserves exact local slot")
expect(exact(usersMenu.requests[1].request.target, { username = true })
    and usersMenu.requests[1].request.target.username == "OnlineUser",
    "Users List inspection sends only bounded online username")

local mixedLauncher = makeEnvironment("multiplayer")
expect(mixedLauncher.integration.install().ok, "mixed-account launcher environment installs")
local mixedList, mixedItem = mixedLauncher:usersList("MixedAccount", 1, true)
mixedLauncher.UsersList.doContextMenu(mixedList, mixedItem, 1, 2)
equal(#mixedLauncher.menu.options, 2,
    "online account row retains online action and adds offline profiles")
mixedLauncher.menu.options[2]:click()
equal(#mixedLauncher.requests, 1, "offline sibling launcher sends one request")
equal(mixedLauncher.requests[1].request.operation, "enumerateOfflineProfiles",
    "offline sibling launcher enumerates profiles even from an online account row")
equal(mixedLauncher.requests[1].request.target.username, "MixedAccount",
    "offline sibling launcher preserves exact account username")

local throwingUsers = makeEnvironment("multiplayer")
expect(throwingUsers.integration.install().ok, "throwing Users List environment installs")
throwingUsers.priorUsersThrows = true
local throwingUsersList, throwingUsersItem = throwingUsers:usersList("ThrowUser", 0, true)
local throwingUsersOk = pcall(function()
    throwingUsers.UsersList.doContextMenu(throwingUsersList, throwingUsersItem, 0, 0)
end)
expect(not throwingUsersOk, "vanilla Users List failure propagates")
equal(throwingUsers.priorUsersMenus, 1, "throwing vanilla Users List is called exactly once")
equal(throwingUsers.existingMenuGets, 0, "throwing vanilla Users List appends nothing")

local noLocalRole = makeEnvironment("multiplayer")
noLocalRole.localPlayers[0] = { getUsername = function() return "Local0" end }
expect(not noLocalRole.integration.isAvailable(0), "missing local role fails closed")
local missingRoleOpen = noLocalRole.integration.open(0)
equal(missingRoleOpen.ok, false, "missing local role cannot open self-admin")
equal(#noLocalRole.requests, 0, "missing local role sends no inspection")

local throwingCapability = makeEnvironment("multiplayer")
throwingCapability.localPlayers[1] = {
    getRole = function()
        return { hasCapability = function() error("capability boom") end }
    end,
    getUsername = function() return "Local1" end,
}
expect(not throwingCapability.integration.isAvailable(1), "throwing local capability fails closed")
local throwingCapabilityOpen = throwingCapability.integration.open(1)
equal(throwingCapabilityOpen.ok, false, "throwing local capability cannot open self-admin")
equal(#throwingCapability.requests, 0, "throwing local capability sends no inspection")

local malformedIdentity = makeEnvironment("multiplayer")
malformedIdentity.localPlayers[3] = {
    getRole = function()
        return { hasCapability = function() return true end }
    end,
    getUsername = function() return "" end,
}
expect(not malformedIdentity.integration.isAvailable(3), "username-less local identity fails closed")
local malformedIdentityOpen = malformedIdentity.integration.open(3)
equal(malformedIdentityOpen.ok, false, "username-less local identity cannot open")
equal(#malformedIdentity.requests, 0, "username-less local identity sends no inspection")

local throwingLocal = makeEnvironment("multiplayer")
throwingLocal.getSpecificThrows = true
expect(not throwingLocal.integration.isAvailable(1), "throwing local-player lookup fails closed")
local throwingLocalOpen = throwingLocal.integration.open(1)
equal(throwingLocalOpen.ok, false, "throwing local-player lookup cannot open")
equal(#throwingLocal.requests, 0, "throwing local-player lookup sends no inspection")

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
expect(window.x >= mp.viewportLeft and window.x + window.width <= mp.viewportLeft + mp.viewportWidth,
    "content-sized panel stays inside nonzero split-screen X bounds")
expect(window.y >= mp.viewportTop and window.y + window.height <= mp.viewportTop + mp.viewportHeight,
    "content-sized panel stays inside nonzero split-screen Y bounds")
expect(window.width < 400 and window.width <= mp.viewportWidth, "short copy produces a compact measured window")
expect(window.height <= mp.viewportHeight, "content-sized panel respects local viewport height")
equal(window.instantiates, 1, "window instantiates exactly once before UI-manager add")
equal(table.concat(window.phaseOrder, ","), "initialise,instantiate,manager,visible",
    "window lifecycle orders child construction before manager add and visibility")
equal(mp.windowChildren, 1, "window child phase runs exactly once")
equal(window.baseCloseControls, 1, "base close controls are created exactly once")
equal(#window.childrenInOrder, 2, "base close control and content pane are created once")
equal(#state.pane.childrenInOrder, 6, "six SLA controls belong to the scrollable content pane")
equal(window.javaObject.children[2], state.pane.javaObject,
    "native window retains the same content pane Java object used for drawing and controls")
equal(#window.javaObject.children[2].children, 6,
    "all six controls are attached to the native content pane in the window tree")
for index, child in ipairs(state.pane.childrenInOrder) do
    equal(window.javaObject.children[2].children[index], child.javaObject,
        "native window tree reaches live control " .. tostring(index))
end
expect(state.xpEntry.initialised and state.levelsEntry.initialised
    and state.awardXpButton.initialised and state.awardLevelsButton.initialised
    and state.clearSlotsButton.initialised and state.refreshButton.initialised,
    "all SLA entries and buttons initialise exactly once")
equal(state.xpEntry.x, 16, "XP entry aligns to the left panel margin")
equal(state.levelsEntry.x, 16, "levels entry aligns to the left panel margin")
equal(state.awardXpButton.x, state.refreshButton.x, "XP award aligns to the right grid column")
equal(state.awardLevelsButton.x, state.refreshButton.x, "levels award aligns to the right grid column")
equal(state.clearSlotsButton.x, 16, "clear button stays inside the left panel margin")
equal(state.clearSlotsButton.width, state.xpEntry.width, "clear button uses the shared grid width")
equal(state.refreshButton.x, state.awardXpButton.x, "refresh button starts at the right grid column")
equal(state.refreshButton.width, state.clearSlotsButton.width, "refresh button matches the shared grid width")
equal(state.xpEntry.width, state.awardXpButton.width,
    "first award row uses equal grid columns")
equal(state.levelsEntry.width, state.awardLevelsButton.width,
    "second award row uses equal grid columns")
equal(state.awardXpButton.x - (state.xpEntry.x + state.xpEntry.width), 20,
    "first award row keeps the shared grid gap")
equal(state.awardLevelsButton.x - (state.levelsEntry.x + state.levelsEntry.width), 20,
    "second award row keeps the shared grid gap")
equal(state.refreshButton.x - (state.clearSlotsButton.x + state.clearSlotsButton.width), 20,
    "bottom buttons keep a twenty-pixel visible gap")
equal(state.refreshButton.x + state.refreshButton.width, window.width - 32,
    "refresh button stays inside the right panel margin")
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
for repeatRender = 1, 20 do window:prerender() end
equal(state.clearSlotsButton.x, 16, "repeated panel renders keep clear button position")
equal(state.refreshButton.x, state.awardXpButton.x, "repeated panel renders keep refresh aligned")
equal(state.clearSlotsButton.width, state.refreshButton.width,
    "repeated panel renders keep bottom button widths equal")
equal(state.refreshButton.x - (state.clearSlotsButton.x + state.clearSlotsButton.width), 20,
    "repeated panel renders keep the bottom button gap")
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

state.summary = summary(7, 5, 2, 25.44, "Tracked", 100.04)
window:prerender()
expect(containsDraw(window, "Survivor XP: 25.4 / 100"),
    "panel rounds ordinary fractional Survivor XP to one decimal place")
equal(state.summary.xpIntoLevel, 25.44,
    "panel presentation leaves the exact current summary value unchanged")
equal(state.summary.xpForNextLevel, 100.04,
    "panel presentation leaves the exact required summary value unchanged")
state.summary = summary(7, 5, 2, 25.05, "Tracked", 100.05)
window:prerender()
expect(containsDraw(window, "Survivor XP: 25.1 / 100.1"),
    "panel rounds Survivor XP half-up at one decimal place")
state.summary = summary(7, 5, 2, 9007199254740990, "Tracked", 9007199254740991)
window:prerender()
local largeXpText = nil
for drawIndex = #window.draws, 1, -1 do
    local text = window.draws[drawIndex].text
    if string.find(text, "Survivor XP: ", 1, true) == 1 then
        largeXpText = text
        break
    end
end
expect(largeXpText ~= nil and string.find(largeXpText, ".", 1, true) == nil,
    "panel presents safe large Survivor XP without a decimal suffix")
state.summary = summary(7, 5, 2)

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

local lostUsers = makeEnvironment("multiplayer")
expect(lostUsers.integration.install().ok, "Users List ownership environment installs")
lostUsers.UsersList.doContextMenu = function() end
local lostUsersResult = lostUsers.integration.install()
equal(lostUsersResult.ok, false, "lost Users List hook fails closed")
equal(lostUsersResult.code, "hook_ownership_lost", "lost Users List ownership code")

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

local layout = makeEnvironment("singleplayer")
layout.viewportWidth, layout.viewportHeight = 1000, 900
layout.requestHandler = function()
    return { ok = true, operation = "inspect", outcome = "inspected", summary = summary(3, 5, 0) }
end
expect(layout.integration.install().ok and layout.integration.open(0).ok, "layout regression panel opens")
local layoutWindow = layout.windows[1]
local layoutState = rawget(layoutWindow, "__slaAdminState")
layoutWindow:prerender()
local shortWidth, shortHeight = layoutWindow.width, layoutWindow.height
layoutState.message = "Borrado de avances pendiente. Se aplicará cuando este perfil vuelva a conectarse."
layoutWindow:prerender()
expect(layoutWindow.width > shortWidth, "long translated status widens the outer window")
expect(layoutWindow.width <= layout.viewportWidth, "natural width respects viewport cap")
local naturalWidth = layoutWindow.width
local measuredCalls = layout.measureCalls
for frame = 1, 25 do layoutWindow:prerender() end
equal(layout.measureCalls, measuredCalls + 25, "unchanged frames only measure the font sentinel, without repeating layout")
layout.viewportWidth = 260
layout.viewportHeight = 190
layoutWindow:prerender()
equal(layoutWindow.width, 260, "outer width clamps to a narrow viewport")
expect(layoutState.pane.scrollHeight > layoutState.pane.height, "long content remains scrollable below viewport")
equal(layoutWindow.height, 190, "outer height clamps to viewport")
expect(layoutWindow.x >= layout.viewportLeft and layoutWindow.x + layoutWindow.width <= layout.viewportLeft + 260,
    "resizing preserves split-screen horizontal bounds")
local rebuilt = {}
for index = 1, #layoutState.drawLines do
    local line = layoutState.drawLines[index]
    expect(layout.dependencies.measureText(line.text) <= layoutWindow.width - 48, "wrapped text fits its measured box")
    if index > 1 then expect(line.y > layoutState.drawLines[index - 1].y, "wrapped lines do not overlap") end
    rebuilt[#rebuilt + 1] = line.text
end
expect(string.find(table.concat(rebuilt):gsub(" ", ""), layoutState.message:gsub(" ", ""), 1, true) ~= nil,
    "wrapping preserves the complete translated message")
expect(layoutState.awardXpButton.y >= layoutState.xpEntry.y + layoutState.xpEntry.height,
    "narrow viewport stacks an action below its entry")
expect(layoutState.levelsEntry.y > layoutState.awardXpButton.y + layoutState.awardXpButton.height,
    "later controls follow the measured preceding row")
layoutState.pane:onMouseWheel(1)
expect(layoutState.pane:getYScroll() < 0, "mouse wheel reaches overflow content")
layoutState.pane:setYScroll(0)
equal(layoutState.levelsEntry:focus(), "focused", "entry focus preserves native return")
expect(layoutState.levelsEntry.focused and layoutState.pane:getYScroll() < 0, "keyboard focus scrolls the entry into view")
layoutWindow.joyfocus, layoutWindow.joypadIndexY, layoutWindow.joypadIndex = {}, 3, 2
layoutState.pane:setYScroll(0)
layoutWindow:ensureVisible()
expect(layoutState.refreshButton.y + layoutState.refreshButton.height <= -layoutState.pane:getYScroll() + layoutState.pane.height,
    "controller selection scrolls the focused action into view")
equal(layoutState.refreshButton.internal, "REFRESH", "scrolling preserves action identity")
local oldContentHeight = layoutState.pane.scrollHeight
layout.fontHeight, layout.charWidth = 26, 9
layoutWindow:prerender()
expect(layoutState.pane.scrollHeight > oldContentHeight, "larger font reflows and grows content height")
expect(layoutState.refreshButton.height >= 36, "button height follows the larger font")
equal(layoutWindow.titleFontHgt, 26, "title bar height follows the actual Small font")
layoutState.pane:render()
expect(layoutState.pane.repainted, "nested content stencil repaints its parent mask after clearing")
layoutState.message = "玩家檔案重新整理後再次連線並清除所有已占用的晉升欄位玩家檔案重新整理後再次連線"
layoutWindow:prerender()
local cjk = {}
for _, line in ipairs(layoutState.drawLines) do
    expect(layout.dependencies.measureText(line.text) <= layoutWindow.width - 48, "no-space CJK stays within the measured box")
    cjk[#cjk + 1] = line.text
end
expect(string.find(table.concat(cjk), layoutState.message, 1, true) ~= nil, "CJK wrapping preserves full Unicode text")
layoutState.message = "ExtremelyLongUnbrokenPlayerUsernameABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
layoutWindow:prerender()
local username = {}
for _, line in ipairs(layoutState.drawLines) do
    expect(layout.dependencies.measureText(line.text) <= layoutWindow.width - 48, "long username stays within the measured box")
    username[#username + 1] = line.text
end
expect(string.find(table.concat(username), layoutState.message, 1, true) ~= nil, "username wrapping preserves every character without injected hyphens")
layout.viewportWidth, layout.viewportHeight = 1000, 900
layoutState.message = "Ready"
layout.fontHeight, layout.charWidth = 12, 5
layoutWindow.joyfocus = nil
layoutWindow:prerender()
expect(layoutWindow.width < naturalWidth, "outer width shrinks when long content is replaced")
expect(layoutWindow.height < 900 and layoutState.pane.scrollHeight <= layoutState.pane.height,
    "outer height fits content when the viewport has room")
layout.viewportWidth, layout.viewportHeight = 70, 70
layoutWindow:prerender()
expect(layoutState.closed and layoutWindow.removed, "viewport smaller than supported chrome closes existing UI cleanly")
local tiny = makeEnvironment("singleplayer")
tiny.viewportWidth, tiny.viewportHeight = 70, 70
expect(tiny.integration.install().ok, "tiny viewport environment installs")
local tinyOpen = tiny.integration.open(0)
expect(not tinyOpen.ok and tinyOpen.code == "viewport_failed" and #tiny.windows == 0,
    "viewport below 120 by 100 fails before making a blank overflowing window")

do
    local env = makeEnvironment("singleplayer")
    env.viewportWidth, env.viewportHeight = 1000, 900
    env.requestHandler = function()
        return { ok = true, operation = "inspect", outcome = "inspected", summary = summary(3, 5, 0) }
    end
    local previous = { isReallyVisible = function() return true end }
    local otherFocus = {}
    local otherPlayer = { isActive = true, focus = otherFocus }
    env.joypads[0] = otherPlayer
    env.joypads[2] = { isActive = true, focus = previous }
    expect(env.integration.install().ok and env.integration.open(2).ok, "active controller admin opens")
    local window, data = env.windows[1], env.joypads[2]
    local state = rawget(window, "__slaAdminState")
    equal(data.focus, window, "opening transfers controller focus to admin")
    equal(state.previousFocus, previous, "opening retains previous focus")
    equal(env.focusChanges[1].slot, 2, "focus transfer addresses exact local player")
    equal(otherPlayer.focus, otherFocus, "other local player remains untouched")
    window:onGainJoypadFocus(data)
    equal(window:getJoypadFocus(), state.xpEntry, "native initial focus selects first visible input")
    expect(state.xpEntry.joypadFocused, "initial input is highlighted")
    window:onJoypadDirRight(data)
    equal(window:getJoypadFocus(), state.awardXpButton, "native Right selects the action beside input")
    window:onJoypadDirDown(data)
    equal(window:getJoypadFocus(), state.awardLevelsButton, "native Down selects corresponding next-row action")
    window:onJoypadDirLeft(data)
    equal(window:getJoypadFocus(), state.levelsEntry, "native Left reaches levels input")
    state.levelsEntry.Type = "ISTextEntryBox"
    local keyboard = {}
    state.levelsEntry.onJoypadDown = function(_, button, joypadData)
        equal(button, "A", "native panel delegates A to text entry")
        keyboard.prevFocus = joypadData.focus
        joypadData.focus = keyboard
    end
    window:onJoypadDown("A", data)
    equal(data.focus, keyboard, "native text-entry delegation permits keyboard focus")
    window:onLoseJoypadFocus(data)
    expect(not state.levelsEntry.joypadFocused, "losing window focus clears control highlight")
    data.focus = keyboard.prevFocus
    window:onGainJoypadFocus(data)
    equal(window:getJoypadFocus(), state.levelsEntry, "return from keyboard preserves input selection")
    env.integration.open(2)
    equal(state.previousFocus, previous, "reopen while focused does not overwrite return target with itself")
    window:onJoypadDown("B", data)
    expect(window.removed and state.closed, "B closes admin")
    equal(data.focus, previous, "B restores previous visible focus")
    expect(env.integration.open(2).ok, "admin opens again after close")
    window = env.windows[2]
    window:close()
    equal(data.focus, previous, "mouse close also restores controller focus")
    expect(env.integration.open(2).ok, "admin opens before foreign focus test")
    window = env.windows[3]
    local foreign = {}
    data.focus = foreign
    window:close()
    equal(data.focus, foreign, "closing unfocused admin does not steal another window's focus")
    data.focus = { isReallyVisible = function() return false end }
    expect(env.integration.open(2).ok, "admin opens from subsequently unavailable return surface")
    env.windows[4]:close()
    equal(data.focus, nil, "invisible previous focus is not restored")
    data.isActive = false
    local changes = #env.focusChanges
    expect(env.integration.open(2).ok, "mouse-only admin still opens")
    equal(#env.focusChanges, changes, "inactive controller does not receive focus")
end

return assertions
