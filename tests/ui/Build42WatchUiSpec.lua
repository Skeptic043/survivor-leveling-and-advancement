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
        enabled = false, stamp = 0, millis = 0, players = {}, refreshes = {}, states = {}, stateReads = 0,
        geometry = {}, draws = {}, panels = 0, playerReads = {}, mapVisible = false,
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
            h.stateReads = h.stateReads + 1
            if h.stateThrow then error("state") end
            return h.states[slot]
        end,
    }
    h.dependencies = {
        owner = h.owner,
        optionEnabled = function() if h.optionThrow then error("option") end; return h.enabled end,
        isWorldMapVisible = function()
            if h.mapThrow then error("map") end
            if h.mapMalformed then return "visible" end
            return h.mapVisible
        end,
        getClock = function() if h.clockThrow then error("clock") end; return h.clock end,
        minuteStamp = function() if h.timeThrow then error("time") end; return h.stamp end,
        clockMillis = function() if h.millisThrow then error("millis") end; return h.millis end,
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
missing = harness()
missing.dependencies.isWorldMapVisible = nil
equal(Watch.create(missing.dependencies).code, "invalid_dependencies", "missing map capability fails")
missing = harness()
missing.dependencies.clockMillis = nil
equal(Watch.create(missing.dependencies).code, "invalid_dependencies", "missing real clock capability fails")

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

local mapH = harness()
mapH.enabled = true
mapH.players[0] = { dead = false }
mapH.states[0] = snapshot(25, 100)
mapH.mapVisible = true
local geometryBeforeMap = #mapH.geometry
mapH.callbacks.prerender()
mapH.callbacks.render()
equal(mapH.created.integration.status().displaying, false, "visible world map hides percentage")
equal(#mapH.refreshes, 0, "visible world map prevents owner refresh")
equal(#mapH.playerReads, 0, "visible world map prevents player reads")
expect(#mapH.geometry == geometryBeforeMap + 1 and mapH.geometry[#mapH.geometry].width == 0,
    "visible world map hides without clock geometry")
equal(#mapH.draws, 0, "visible world map prevents drawing")
mapH.mapVisible = false
mapH.callbacks.prerender()
mapH.callbacks.render()
equal(#mapH.refreshes, 1, "closing world map resumes due owner refresh")
equal(#mapH.draws, 1, "closing world map resumes drawing without a new event")

mapH.mapThrow = true
mapH.callbacks.prerender()
equal(mapH.created.integration.status().displaying, false, "throwing world map visibility fails closed")
mapH.mapThrow = false
mapH.mapMalformed = true
mapH.callbacks.prerender()
equal(mapH.created.integration.status().displaying, false, "non-boolean world map visibility fails closed")
mapH.mapMalformed = false
mapH.callbacks.prerender()
mapH.mapVisible = true
mapH.callbacks.render()
equal(mapH.created.integration.status().displaying, false, "world map opening between callbacks prevents drawing")

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
h.millis = 1000
h.callbacks.prerender()
h.draws = {}
h.callbacks.render()
equal(h.draws[1][1], 100, "percentage clamps above one")
h.states[0] = snapshot(-5, 100)
h.millis = 2000
h.callbacks.prerender()
h.draws = {}
h.callbacks.render()
equal(h.draws[1][1], 0, "percentage clamps below zero")
h.states[0] = snapshot(5, 0)
h.millis = 3000
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "invalid cost hides percentage")
h.states[0] = snapshot(5, 100, false)
h.millis = 4000
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "unready snapshot hides percentage")
h.states[0] = { ok = true, present = false }
h.millis = 5000
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "absent snapshot hides percentage")

h.states[0] = snapshot(20, 100)
h.clock.visible = false
h.callbacks.prerender()
equal(h.created.integration.status().displaying, false, "hidden digital clock hides percentage")
h.clock.visible = true

local function failureCase(field, stamp)
    h[field] = true; h.stamp = stamp; h.millis = h.millis + 1000; h.callbacks.prerender()
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
h.millis = h.millis + 1000

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

local cost = harness()
cost.enabled = true
cost.players[0] = { dead = false }
cost.states[0] = snapshot(25, 100)
cost.callbacks.prerender()
cost.states[0] = snapshot(75, 100)
for frame = 1, 240 do
    cost.millis = frame * 4
    cost.callbacks.prerender()
    cost.callbacks.render()
end
equal(cost.stateReads, 1, "240 visible frames below one second reuse one snapshot read")
equal(cost.draws[#cost.draws][1], 25, "percentage stays cached before the interval")
equal(#cost.refreshes, 1, "display frames do not add owner refreshes")
cost.millis = 1000
cost.callbacks.prerender()
cost.callbacks.render()
equal(cost.stateReads, 2, "next real second reads one new snapshot")
equal(cost.draws[#cost.draws][1], 75, "next interval displays new percentage")

cost.mapVisible = true
for frame = 1, 120 do cost.millis = 1000 + frame * 16; cost.callbacks.prerender() end
equal(cost.stateReads, 2, "map-hidden frames read no snapshots")
cost.mapVisible = false
cost.callbacks.prerender()
equal(cost.stateReads, 3, "closing map reads once when the interval has elapsed")
cost.enabled = false
for frame = 1, 120 do cost.millis = 3000 + frame * 16; cost.callbacks.prerender() end
equal(cost.stateReads, 3, "disabled frames read no snapshots")
cost.enabled = true
cost.callbacks.prerender()
equal(cost.stateReads, 4, "reenabling reads once after the interval")
cost.clock.visible = false
for frame = 1, 120 do cost.millis = 5000 + frame * 16; cost.callbacks.prerender() end
equal(cost.stateReads, 4, "hidden digital clock reads no snapshots")
cost.clock.visible = true
cost.callbacks.prerender()
equal(cost.stateReads, 5, "visible clock resumes the snapshot interval")

cost.players[0] = { dead = false }
cost.states[0] = snapshot(10, 100)
cost.millis = cost.millis + 1
cost.callbacks.prerender()
equal(cost.created.integration.status().displaying, false, "new character cannot display old percentage")
equal(cost.stateReads, 5, "owner change cannot bypass snapshot read throttle")
cost.millis = cost.millis + 1000
cost.callbacks.prerender()
cost.callbacks.render()
equal(cost.draws[#cost.draws][1], 10, "replacement receives its own percentage next interval")
cost.players[0].dead = true
cost.callbacks.prerender()
equal(cost.created.integration.status().displaying, false, "death hides immediately before owner refresh cadence")
cost.players[0] = nil
cost.callbacks.prerender()
equal(cost.created.integration.status().localSlot, nil, "disconnect immediately drops cached owner")
cost.players[0] = { dead = false }
cost.states[0] = snapshot(60, 100)
cost.callbacks.prerender()
equal(cost.created.integration.status().displaying, false, "reconnect cannot inherit dead character percentage")
cost.millis = cost.millis + 1000
cost.callbacks.prerender()
cost.callbacks.render()
equal(cost.draws[#cost.draws][1], 60, "reconnected character receives current percentage")

local readsBeforeFailure = cost.stateReads
cost.stateThrow = true
cost.millis = cost.millis + 1000
cost.callbacks.prerender()
equal(cost.created.integration.status().displaying, false, "snapshot read failure discards cached percentage")
for frame = 1, 240 do cost.millis = cost.millis + 4; cost.callbacks.prerender() end
equal(cost.stateReads, readsBeforeFailure + 1, "throwing snapshot reads retry at most once per second")
cost.stateThrow = false
cost.millis = cost.millis + 40
cost.callbacks.prerender()
equal(cost.stateReads, readsBeforeFailure + 2, "snapshot failure recovers at the next interval")
local recoveredReads = cost.stateReads
for frame = 1, 60 do
    cost.enabled = false; cost.callbacks.prerender()
    cost.enabled = true; cost.callbacks.prerender()
end
equal(cost.stateReads, recoveredReads, "option transitions do not reset the read throttle")

cost.millis = cost.millis - 5000
cost.callbacks.prerender()
equal(cost.created.integration.status().displaying, false, "clock rollback clears cached percentage")
for frame = 1, 100 do cost.callbacks.prerender() end
equal(cost.stateReads, recoveredReads, "clock rollback does not retry expensive reads each frame")
cost.millis = cost.millis + 1000
cost.callbacks.prerender()
equal(cost.stateReads, recoveredReads + 1, "rebased clock resumes after one second")
local readsBeforeClockFailure = cost.stateReads
for _, invalidClock in ipairs({ 0 / 0, math.huge, -math.huge, false }) do
    cost.millis = invalidClock
    for frame = 1, 30 do cost.callbacks.prerender() end
    equal(cost.created.integration.status().displaying, false, "invalid real clock hides percentage")
end
cost.millisThrow = true
for frame = 1, 100 do cost.callbacks.prerender() end
equal(cost.stateReads, readsBeforeClockFailure, "invalid or throwing real clock never reads snapshots")
cost.millisThrow = false
cost.millis = 100000
cost.callbacks.prerender()
equal(cost.stateReads, readsBeforeClockFailure + 1, "valid real clock resumes safely")
cost.states[0] = { ok = true, present = false }
cost.millis = cost.millis + 1000
cost.callbacks.prerender()
equal(cost.created.integration.status().displaying, false, "reset owner snapshot clears displayed percentage next interval")
local absentReads = cost.stateReads
for frame = 1, 120 do cost.callbacks.prerender() end
equal(cost.stateReads, absentReads, "absent snapshot does not cause per-frame reads")

return checks
