local Watch = Build42WatchUi
local checks = 0

local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local function equal(actual, expected, message)
    expect(actual == expected, message .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
end

local function snapshot(xp, cost, ready)
    return { ok = true, present = true, snapshot = {
        ready = ready ~= false,
        survivor = { xpIntoLevel = xp, xpForNextLevel = cost },
    } }
end

local function harness()
    local h = {
        enabled = false, stamp = 0, players = {}, refreshes = {}, states = {},
        geometry = {}, draws = {}, panels = 0, playerReads = {},
    }
    h.clock = { x = 100, y = 10, width = 91, height = 37, visible = true }
    function h.clock:getX() return self.x end
    function h.clock:getY() return self.y end
    function h.clock:getWidth() return self.width end
    function h.clock:getHeight() return self.height end
    function h.clock:isDateVisible() return self.visible end
    h.owner = {
        refreshOwner = function(slot)
            h.refreshes[#h.refreshes + 1] = slot
            if h.refreshThrow then error("refresh") end
            return { ok = true }
        end,
        clientState = function(slot)
            if h.stateThrow then error("state") end
            return h.states[slot]
        end,
    }
    h.dependencies = {
        owner = h.owner,
        optionEnabled = function() if h.optionThrow then error("option") end; return h.enabled end,
        getClock = function() if h.clockThrow then error("clock") end; return h.clock end,
        minuteStamp = function() if h.timeThrow then error("time") end; return h.stamp end,
        getPlayer = function(slot)
            h.playerReads[#h.playerReads + 1] = slot
            if h.playerThrow then error("player") end
            return h.players[slot]
        end,
        isDead = function(value) if h.deadThrow then error("dead") end; return value.dead end,
        createPanel = function(callbacks)
            h.panels = h.panels + 1
            h.callbacks = callbacks
            local width, height = 0, 0
            return {
                setGeometry = function(x, y, w, panelHeight)
                    if h.geometryThrow then error("geometry") end
                    width, height = w, panelHeight
                    h.geometry[#h.geometry + 1] = { x = x, y = y, width = w, height = panelHeight }
                end,
                width = function() if h.widthThrow then error("width") end; return width end,
                height = function() if h.heightThrow then error("height") end; return height end,
                drawPercentage = function(...)
                    if h.drawPercentageThrow then error("drawPercentage") end
                    h.draws[#h.draws + 1] = { ... }
                end,
            }
        end,
    }
    h.created = Watch.create(h.dependencies)
    expect(h.created.ok, "watch creates")
    expect(h.created.integration.install().ok, "watch installs")
    return h
end

equal(Watch.create(nil).code, "invalid_dependencies", "nil dependencies fail")
local missing = harness()
missing.dependencies.getClock = nil
equal(Watch.create(missing.dependencies).code, "invalid_dependencies", "missing capability fails")

local h = harness()
h.callbacks.prerender()
equal(#h.refreshes, 0, "default off sends nothing")
equal(#h.playerReads, 0, "default off reads no player")
equal(h.created.integration.status().displaying, false, "default off hidden")
expect(h.created.integration.install().ok, "repeat install succeeds")
equal(h.panels, 1, "repeat install reuses post-UI drawer")

h.enabled = true
h.players[0] = { dead = false }
h.players[1] = { dead = false }
h.states[0] = snapshot(25, 100)
h.states[1] = snapshot(75, 100)
h.callbacks.prerender()
equal(h.playerReads[1], 0, "watch reads only player one")
equal(#h.playerReads, 1, "watch never scans later split-screen slots")
equal(h.refreshes[1], 0, "player one owner refreshes")
equal(h.created.integration.status().localSlot, 0, "status exposes player one slot")
local g = h.geometry[#h.geometry]
equal(g.x, 100, "percentage follows clock x")
equal(g.y, 10, "percentage stays inside clock")
equal(g.width, 91, "percentage follows clock width")
equal(g.height, 37, "percentage follows clock height")
h.callbacks.render()
equal(#h.draws, 1, "visible percentage draws one clock-texture value")
equal(h.draws[1][1], 25, "clock textures use player one percentage")

h.stamp = 9
h.callbacks.prerender()
equal(#h.refreshes, 1, "owner refresh coalesces before ten minutes")
h.stamp = 10
h.callbacks.prerender()
equal(#h.refreshes, 2, "player one refreshes at cadence")

h.players[0].dead = true
h.stamp = 20
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "dead player one hides percentage")
h.players[0] = nil
h.stamp = 30
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "absent player one hides percentage")
h.players[0] = { dead = false }
h.states[0] = snapshot(150, 100)
h.stamp = 40
h.callbacks.prerender()
h.draws = {}
h.callbacks.render()
equal(h.draws[1][1], 100, "percentage clamps above one")
h.states[0] = snapshot(-5, 100)
h.callbacks.prerender()
h.draws = {}
h.callbacks.render()
equal(h.draws[1][1], 0, "percentage clamps below zero")
h.states[0] = snapshot(5, 0)
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "invalid cost hides percentage")
h.states[0] = snapshot(5, 100, false)
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "unready snapshot hides percentage")
h.states[0] = { ok = true, present = false }
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "absent snapshot hides percentage")

h.states[0] = snapshot(20, 100)
h.clock.visible = false
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "hidden digital clock hides percentage")
h.clock.visible = true

local function failureCase(field, stamp)
    h[field] = true; h.stamp = stamp; h.callbacks.prerender()
    equal(h.created.integration.status().displaying, false, field .. " fails closed")
    h[field] = false
end
failureCase("optionThrow", 50)
failureCase("clockThrow", 51)
failureCase("timeThrow", 52)
failureCase("playerThrow", 60)
failureCase("deadThrow", 70)
h.stateThrow = true; h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "state throw fails closed")
h.stateThrow = false

h.enabled = false; h.callbacks.prerender(); h.enabled = true
h.geometryThrow = true; h.stamp = 80; h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "throwing geometry never becomes visible")
h.geometryThrow = false; h.stamp = 90; h.callbacks.prerender()
expect(h.created.integration.status().displaying, "display recovers after geometry seam")
h.widthThrow = true; h.callbacks.render()
equal(h.created.integration.status().displaying, false, "throwing width closes display")
h.widthThrow = false; h.callbacks.prerender(); h.heightThrow = true; h.callbacks.render()
equal(h.created.integration.status().displaying, false, "throwing height closes display")
h.heightThrow = false; h.callbacks.prerender(); h.drawPercentageThrow = true; h.callbacks.render()
equal(h.created.integration.status().displaying, false, "throwing post-UI clock textures close display")

local badPanel = harness()
badPanel.dependencies.createPanel = function() return {} end
local badCreated = Watch.create(badPanel.dependencies)
expect(badCreated.ok, "bad panel defers to install")
equal(badCreated.integration.install().code, "watch_panel_failed", "malformed panel rejected")

return checks
