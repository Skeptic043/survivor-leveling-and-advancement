local assertionCount = 0

local function assertTrue(value, message)
    assertionCount = assertionCount + 1
    if value ~= true then
        error(message or "expected true")
    end
end

local function assertFalse(value, message)
    assertionCount = assertionCount + 1
    if value ~= false then
        error(message or "expected false")
    end
end

local function assertEqual(expected, actual, message)
    assertionCount = assertionCount + 1
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertExactKeys(value, expected, message)
    local count = 0
    for key in pairs(value) do
        count = count + 1
        assertTrue(expected[key] == true, (message or "table") .. " has unexpected key " .. tostring(key))
    end
    local expectedCount = 0
    for key in pairs(expected) do
        expectedCount = expectedCount + 1
        assertTrue(value[key] ~= nil, (message or "table") .. " lacks key " .. tostring(key))
    end
    assertEqual(expectedCount, count, (message or "table") .. " key count")
end

local function makeRole(capabilities, position)
    local role = {
        capabilityCalls = 0,
        positionCalls = 0,
    }

    function role:hasCapability(capability)
        self.capabilityCalls = self.capabilityCalls + 1
        self.lastCapability = capability
        return capabilities[capability] == true
    end

    function role:getPosition()
        self.positionCalls = self.positionCalls + 1
        return position
    end

    return role
end

local function makeActor(role)
    local actor = {
        roleCalls = 0,
    }

    function actor:getRole()
        self.roleCalls = self.roleCalls + 1
        return role
    end

    return actor
end

local function makeTarget(onlineId, username, role)
    local target = {
        onlineIdCalls = 0,
        usernameCalls = 0,
        roleCalls = 0,
    }

    function target:getOnlineID()
        self.onlineIdCalls = self.onlineIdCalls + 1
        return onlineId
    end

    function target:getUsername()
        self.usernameCalls = self.usernameCalls + 1
        return username
    end

    function target:getRole()
        self.roleCalls = self.roleCalls + 1
        return role
    end

    return target
end

local SEE = {}
local MODIFY = {}
local Capability = {
    CanSeePlayersStats = SEE,
    CanModifyPlayerStatsInThePlayerStatsUI = MODIFY,
}

local function makeBoundary(target)
    local fixture = {
        lookupCalls = 0,
        lookupIds = {},
        target = target,
    }

    local function lookup(onlineId)
        fixture.lookupCalls = fixture.lookupCalls + 1
        fixture.lookupIds[fixture.lookupCalls] = onlineId
        return fixture.target
    end

    local created = Build42AdminBoundary.create({
        Capability = Capability,
        getPlayerByOnlineID = lookup,
    })
    if not created.ok then
        error("valid boundary construction failed")
    end
    fixture.boundary = created.boundary
    return fixture
end

local function assertFailure(result, code, message)
    assertExactKeys(result, { ok = true, code = true }, message)
    assertFalse(result.ok, (message or "failure") .. " ok")
    assertEqual(code, result.code, (message or "failure") .. " code")
end

local function assertSuccess(result, target, onlineId, username, message)
    assertExactKeys(result, { ok = true, target = true, targetRef = true }, message)
    assertTrue(result.ok, (message or "success") .. " ok")
    assertEqual(target, result.target, (message or "success") .. " target")
    assertExactKeys(result.targetRef, { onlineId = true, username = true }, (message or "success") .. " targetRef")
    assertEqual(onlineId, result.targetRef.onlineId, (message or "success") .. " onlineId")
    assertEqual(username, result.targetRef.username, (message or "success") .. " username")
end

assertEqual("table", type(Build42AdminBoundary), "module type")
assertEqual("function", type(Build42AdminBoundary.create), "constructor type")
assertExactKeys(Build42AdminBoundary, { create = true }, "module public surface")

local function assertConstructionFailure(dependencies, detail, message)
    local callOk, result = pcall(Build42AdminBoundary.create, dependencies)
    assertTrue(callOk, (message or "construction failure") .. " does not throw")
    assertExactKeys(result, { ok = true, code = true, detail = true }, message)
    assertFalse(result.ok, (message or "construction failure") .. " ok")
    assertEqual("invalid_dependencies", result.code, (message or "construction failure") .. " code")
    assertEqual(detail, result.detail, (message or "construction failure") .. " detail")
end

assertConstructionFailure(nil, "dependencies must be an exact plain table", "nil dependencies")

local constructorCases = {
    {
        dependencies = {},
        detail = "dependencies must be an exact plain table",
        label = "empty dependencies",
    },
    {
        dependencies = { Capability = Capability },
        detail = "dependencies must be an exact plain table",
        label = "missing lookup",
    },
    {
        dependencies = { getPlayerByOnlineID = function() end },
        detail = "dependencies must be an exact plain table",
        label = "missing Capability",
    },
    {
        dependencies = {
            Capability = Capability,
            getPlayerByOnlineID = function() end,
            extra = true,
        },
        detail = "dependencies must be an exact plain table",
        label = "extra dependency",
    },
    {
        dependencies = {
            Capability = {},
            getPlayerByOnlineID = function() end,
        },
        detail = "Capability.CanSeePlayersStats is required",
        label = "missing inspect capability",
    },
    {
        dependencies = {
            Capability = { CanSeePlayersStats = SEE },
            getPlayerByOnlineID = function() end,
        },
        detail = "Capability.CanModifyPlayerStatsInThePlayerStatsUI is required",
        label = "missing mutation capability",
    },
    {
        dependencies = {
            Capability = Capability,
            getPlayerByOnlineID = true,
        },
        detail = "getPlayerByOnlineID must be a function",
        label = "malformed lookup",
    },
    {
        dependencies = {
            Capability = setmetatable({}, {
                __index = function()
                    error("hostile Capability")
                end,
            }),
            getPlayerByOnlineID = function() end,
        },
        detail = "Capability.CanSeePlayersStats is required",
        label = "hostile Capability",
    },
}
for index = 1, #constructorCases do
    local item = constructorCases[index]
    assertConstructionFailure(item.dependencies, item.detail, item.label)
end

local hostileDependencyIndexCalls = 0
local hostileDependencies = setmetatable(
    {
        Capability = { CanSeePlayersStats = SEE },
        getPlayerByOnlineID = function() end,
    },
    {
        __index = function()
            hostileDependencyIndexCalls = hostileDependencyIndexCalls + 1
            error("hostile dependencies")
        end,
    }
)
assertConstructionFailure(
    hostileDependencies,
    "dependencies must be an exact plain table",
    "metatable dependencies"
)
assertEqual(0, hostileDependencyIndexCalls, "hostile dependency metatable not invoked")

local exactConstruction = Build42AdminBoundary.create({
    Capability = Capability,
    getPlayerByOnlineID = function() return nil end,
})
assertExactKeys(exactConstruction, { ok = true, boundary = true }, "construction success")
assertTrue(exactConstruction.ok, "construction success ok")
assertEqual("table", type(exactConstruction.boundary), "construction boundary type")
assertExactKeys(
    exactConstruction.boundary,
    { authorizeAndResolve = true },
    "constructed boundary public surface"
)

local operations = {
    { name = "inspect", capability = SEE, mutation = false },
    { name = "awardSurvivorXp", capability = MODIFY, mutation = true },
    { name = "awardSurvivorLevels", capability = MODIFY, mutation = true },
    { name = "advancePerkNormally", capability = MODIFY, mutation = true },
    { name = "resetAccounting", capability = MODIFY, mutation = true },
    { name = "setAccounting", capability = MODIFY, mutation = true },
}

local publicSurfaceFixture = makeBoundary(makeTarget(42, "Target", makeRole({}, 1)))
assertExactKeys(
    publicSurfaceFixture.boundary,
    { authorizeAndResolve = true },
    "instance public surface"
)

for index = 1, #operations do
    local operation = operations[index]
    local actorRole = makeRole({ [SEE] = true, [MODIFY] = true }, 10)
    local targetRole = makeRole({}, 5)
    local actor = makeActor(actorRole)
    local target = makeTarget(42, "Exact User", targetRole)
    local fixture = makeBoundary(target)
    local result = fixture.boundary.authorizeAndResolve(
        actor,
        operation.name,
        { onlineId = 42, username = "Exact User" }
    )

    assertSuccess(result, target, 42, "Exact User", operation.name)
    assertEqual(1, actor.roleCalls, operation.name .. " actor role calls")
    assertEqual(1, actorRole.capabilityCalls, operation.name .. " capability calls")
    assertEqual(operation.capability, actorRole.lastCapability, operation.name .. " capability")
    assertEqual(1, fixture.lookupCalls, operation.name .. " lookup calls")
    assertEqual(42, fixture.lookupIds[1], operation.name .. " lookup id")
    assertEqual(1, target.onlineIdCalls, operation.name .. " online id calls")
    assertEqual(1, target.usernameCalls, operation.name .. " username calls")
    if operation.mutation then
        assertEqual(1, target.roleCalls, operation.name .. " target role calls")
        assertEqual(1, actorRole.positionCalls, operation.name .. " actor position calls")
        assertEqual(1, targetRole.positionCalls, operation.name .. " target position calls")
    else
        assertEqual(0, target.roleCalls, operation.name .. " target role calls")
        assertEqual(0, actorRole.positionCalls, operation.name .. " actor position calls")
        assertEqual(0, targetRole.positionCalls, operation.name .. " target position calls")
    end
end

local seeOnlyRole = makeRole({ [SEE] = true }, 10)
local seeOnlyActor = makeActor(seeOnlyRole)
local seeOnlyFixture = makeBoundary(makeTarget(8, "Target", makeRole({}, 1)))
local seeOnlyResult = seeOnlyFixture.boundary.authorizeAndResolve(
    seeOnlyActor,
    "awardSurvivorXp",
    { onlineId = 8, username = "Target" }
)
assertFailure(seeOnlyResult, "unauthorized", "inspect capability cannot mutate")
assertEqual(MODIFY, seeOnlyRole.lastCapability, "mutation denial checks mutation capability")
assertEqual(0, seeOnlyFixture.lookupCalls, "mutation denial precedes lookup")

local modifyOnlyRole = makeRole({ [MODIFY] = true }, 10)
local modifyOnlyActor = makeActor(modifyOnlyRole)
local modifyOnlyFixture = makeBoundary(makeTarget(8, "Target", makeRole({}, 1)))
local modifyOnlyResult = modifyOnlyFixture.boundary.authorizeAndResolve(
    modifyOnlyActor,
    "inspect",
    { onlineId = 8, username = "Target" }
)
assertFailure(modifyOnlyResult, "unauthorized", "mutation capability cannot inspect")
assertEqual(SEE, modifyOnlyRole.lastCapability, "inspect denial checks inspect capability")
assertEqual(0, modifyOnlyFixture.lookupCalls, "inspect denial precedes lookup")

local invalidOperations = {
    "Inspect",
    "awardXP",
    "",
    false,
    1,
    {},
    0 / 0,
}
for index = 1, #invalidOperations do
    local actor = makeActor(makeRole({ [SEE] = true, [MODIFY] = true }, 10))
    local fixture = makeBoundary(makeTarget(8, "Target", makeRole({}, 1)))
    local result = fixture.boundary.authorizeAndResolve(
        actor,
        invalidOperations[index],
        { onlineId = 8, username = "Target" }
    )
    assertFailure(result, "invalid_request", "invalid operation " .. tostring(index))
    assertEqual(0, actor.roleCalls, "invalid operation avoids actor role " .. tostring(index))
    assertEqual(0, fixture.lookupCalls, "invalid operation avoids lookup " .. tostring(index))
end

local selectorWithMetatable = setmetatable({ onlineId = 8, username = "Target" }, {})
local nilSelectorActor = makeActor(makeRole({ [SEE] = true }, 10))
local nilSelectorFixture = makeBoundary(makeTarget(8, "Target", makeRole({}, 1)))
local nilSelectorResult = nilSelectorFixture.boundary.authorizeAndResolve(nilSelectorActor, "inspect", nil)
assertFailure(nilSelectorResult, "invalid_request", "nil selector")
assertEqual(0, nilSelectorActor.roleCalls, "nil selector avoids actor role")
assertEqual(0, nilSelectorFixture.lookupCalls, "nil selector avoids lookup")

local hostileSelectors = {
    {},
    { onlineId = 8 },
    { username = "Target" },
    { onlineId = 8, username = "Target", actor = {} },
    { onlineId = -1, username = "Target" },
    { onlineId = 1.5, username = "Target" },
    { onlineId = 9007199254740992, username = "Target" },
    { onlineId = 0 / 0, username = "Target" },
    { onlineId = math.huge, username = "Target" },
    { onlineId = "8", username = "Target" },
    { onlineId = 8, username = "" },
    { onlineId = 8, username = string.rep("x", 65) },
    { onlineId = 8, username = "bad\nname" },
    { onlineId = 8, username = "bad" .. string.char(127) .. "name" },
    { onlineId = 8, username = 9 },
    selectorWithMetatable,
}
for index = 1, #hostileSelectors do
    local actor = makeActor(makeRole({ [SEE] = true }, 10))
    local fixture = makeBoundary(makeTarget(8, "Target", makeRole({}, 1)))
    local result = fixture.boundary.authorizeAndResolve(actor, "inspect", hostileSelectors[index])
    assertFailure(result, "invalid_request", "hostile selector " .. tostring(index))
    assertEqual(0, actor.roleCalls, "hostile selector avoids actor role " .. tostring(index))
    assertEqual(0, fixture.lookupCalls, "hostile selector avoids lookup " .. tostring(index))
end

local namedAdminRole = makeRole({}, 99)
local namedAdmin = makeActor(namedAdminRole)
function namedAdmin:getAccessLevel()
    error("access level must not be read")
end
namedAdmin.username = "Admin"
local namedAdminFixture = makeBoundary(makeTarget(8, "Target", makeRole({}, 1)))
local namedAdminResult = namedAdminFixture.boundary.authorizeAndResolve(
    namedAdmin,
    "inspect",
    { onlineId = 8, username = "Target" }
)
assertFailure(namedAdminResult, "unauthorized", "named admin without capability")
assertEqual(1, namedAdminRole.capabilityCalls, "named admin capability checked")
assertEqual(SEE, namedAdminRole.lastCapability, "named admin inspect capability")
assertEqual(0, namedAdminFixture.lookupCalls, "named admin denied before lookup")

local malformedActors = {
    false,
    {},
    { getRole = function() error("role failure") end },
    { getRole = function() return nil end },
    { getRole = function() return {} end },
    { getRole = function() return { hasCapability = function() error("capability failure") end } end },
    { getRole = function() return { hasCapability = function() return false end } end },
    { getRole = function() return { hasCapability = function() return "true" end } end },
}
for index = 1, #malformedActors do
    local fixture = makeBoundary(makeTarget(8, "Target", makeRole({}, 1)))
    local result = fixture.boundary.authorizeAndResolve(
        malformedActors[index],
        "inspect",
        { onlineId = 8, username = "Target" }
    )
    assertFailure(result, "unauthorized", "malformed actor " .. tostring(index))
    assertEqual(0, fixture.lookupCalls, "malformed actor denied before lookup " .. tostring(index))
end

local targetCases = {
    { target = nil, code = "target_unavailable" },
    { target = {}, code = "target_mismatch" },
    {
        target = {
            getOnlineID = function() error("online ID failure") end,
            getUsername = function() return "Target" end,
        },
        code = "target_mismatch",
    },
    { target = makeTarget(9, "Target", makeRole({}, 1)), code = "target_mismatch" },
    { target = makeTarget(8, "Other", makeRole({}, 1)), code = "target_mismatch" },
    {
        target = {
            getOnlineID = function() return 8 end,
            getUsername = function() error("username failure") end,
        },
        code = "target_mismatch",
    },
}
for index = 1, #targetCases do
    local actor = makeActor(makeRole({ [SEE] = true }, 10))
    local fixture = makeBoundary(targetCases[index].target)
    local result = fixture.boundary.authorizeAndResolve(
        actor,
        "inspect",
        { onlineId = 8, username = "Target" }
    )
    assertFailure(result, targetCases[index].code, "target case " .. tostring(index))
    assertEqual(1, fixture.lookupCalls, "target case resolves once " .. tostring(index))
end

local throwingFixture = {
    lookupCalls = 0,
}
local throwingConstruction = Build42AdminBoundary.create({
    Capability = Capability,
    getPlayerByOnlineID = function()
        throwingFixture.lookupCalls = throwingFixture.lookupCalls + 1
        error("lookup failure")
    end,
})
assertTrue(throwingConstruction.ok, "throwing lookup construction")
local throwingBoundary = throwingConstruction.boundary
local throwingResult = throwingBoundary.authorizeAndResolve(
    makeActor(makeRole({ [SEE] = true }, 10)),
    "inspect",
    { onlineId = 8, username = "Target" }
)
assertFailure(throwingResult, "target_unavailable", "throwing lookup")
assertEqual(1, throwingFixture.lookupCalls, "throwing lookup called once")

local disconnectedTarget = makeTarget(8, "Target", makeRole({}, 1))
function disconnectedTarget:getOnlineID()
    self.onlineIdCalls = self.onlineIdCalls + 1
    return -1
end
local disconnectedFixture = makeBoundary(disconnectedTarget)
local disconnectedResult = disconnectedFixture.boundary.authorizeAndResolve(
    makeActor(makeRole({ [SEE] = true }, 10)),
    "inspect",
    { onlineId = 8, username = "Target" }
)
assertFailure(disconnectedResult, "target_mismatch", "disconnected target")
assertEqual(1, disconnectedFixture.lookupCalls, "disconnected target lookup once")

local replacement = makeTarget(8, "Replacement", makeRole({}, 1))
local replacementFixture = makeBoundary(replacement)
local replacementResult = replacementFixture.boundary.authorizeAndResolve(
    makeActor(makeRole({ [SEE] = true }, 10)),
    "inspect",
    { onlineId = 8, username = "Original" }
)
assertFailure(replacementResult, "target_mismatch", "replacement target")
assertEqual(1, replacementFixture.lookupCalls, "replacement target lookup once")

local hierarchyCases = {
    { actorPosition = 5, targetPosition = 4, succeeds = true, label = "lower target" },
    { actorPosition = 5, targetPosition = 5, succeeds = true, label = "equal target" },
    { actorPosition = 5, targetPosition = 6, succeeds = false, label = "higher target" },
}
for index = 1, #hierarchyCases do
    local item = hierarchyCases[index]
    local actorRole = makeRole({ [MODIFY] = true }, item.actorPosition)
    local targetRole = makeRole({}, item.targetPosition)
    local target = makeTarget(8, "Target", targetRole)
    local fixture = makeBoundary(target)
    local result = fixture.boundary.authorizeAndResolve(
        makeActor(actorRole),
        "setAccounting",
        { onlineId = 8, username = "Target" }
    )
    if item.succeeds then
        assertSuccess(result, target, 8, "Target", item.label)
    else
        assertFailure(result, "unauthorized", item.label)
    end
    assertEqual(1, fixture.lookupCalls, item.label .. " lookup once")
    assertEqual(1, actorRole.positionCalls, item.label .. " actor position once")
    assertEqual(1, targetRole.positionCalls, item.label .. " target position once")
end

local malformedHierarchyCases = {
    {
        actorRole = { hasCapability = function() return true end },
        targetRole = makeRole({}, 1),
    },
    {
        actorRole = {
            hasCapability = function() return true end,
            getPosition = function() error("actor position failure") end,
        },
        targetRole = makeRole({}, 1),
    },
    {
        actorRole = makeRole({ [MODIFY] = true }, "10"),
        targetRole = makeRole({}, 1),
    },
    {
        actorRole = makeRole({ [MODIFY] = true }, 10),
        targetRole = nil,
    },
    {
        actorRole = makeRole({ [MODIFY] = true }, 10),
        targetRole = { getPosition = function() return 0 / 0 end },
    },
    {
        actorRole = makeRole({ [MODIFY] = true }, 10),
        targetRole = { getPosition = function() error("target position failure") end },
    },
}
for index = 1, #malformedHierarchyCases do
    local item = malformedHierarchyCases[index]
    local target = makeTarget(8, "Target", item.targetRole)
    local fixture = makeBoundary(target)
    local result = fixture.boundary.authorizeAndResolve(
        makeActor(item.actorRole),
        "setAccounting",
        { onlineId = 8, username = "Target" }
    )
    assertFailure(result, "unauthorized", "malformed hierarchy " .. tostring(index))
    assertEqual(1, fixture.lookupCalls, "malformed hierarchy lookup once " .. tostring(index))
end

local inspectionRole = makeRole({ [SEE] = true }, 1)
function inspectionRole:getPosition()
    self.positionCalls = self.positionCalls + 1
    error("inspection must not inspect actor hierarchy")
end
local inspectedTargetRole = makeRole({}, 100)
function inspectedTargetRole:getPosition()
    self.positionCalls = self.positionCalls + 1
    error("inspection must not inspect target hierarchy")
end
local inspectedTarget = makeTarget(8, "Target", inspectedTargetRole)
local inspectionFixture = makeBoundary(inspectedTarget)
local inspectionResult = inspectionFixture.boundary.authorizeAndResolve(
    makeActor(inspectionRole),
    "inspect",
    { onlineId = 8, username = "Target" }
)
assertSuccess(inspectionResult, inspectedTarget, 8, "Target", "inspection ignores hierarchy")
assertEqual(0, inspectionRole.positionCalls, "inspection actor position unused")
assertEqual(0, inspectedTarget.roleCalls, "inspection target role unused")
assertEqual(0, inspectedTargetRole.positionCalls, "inspection target position unused")

local selector = { onlineId = 8, username = "Target" }
local detachedTarget = makeTarget(8, "Target", makeRole({}, 1))
local detachedFixture = makeBoundary(detachedTarget)
local detachedResult = detachedFixture.boundary.authorizeAndResolve(
    makeActor(makeRole({ [SEE] = true }, 10)),
    "inspect",
    selector
)
selector.onlineId = 99
selector.username = "Changed"
assertEqual(8, detachedResult.targetRef.onlineId, "targetRef onlineId detached")
assertEqual("Target", detachedResult.targetRef.username, "targetRef username detached")
assertFalse(detachedResult.targetRef == selector, "targetRef is a new table")

local oldSee = {}
local oldModify = {}
local mutableCapabilities = {
    CanSeePlayersStats = oldSee,
    CanModifyPlayerStatsInThePlayerStatsUI = oldModify,
}
local capturedTarget = makeTarget(8, "Target", makeRole({}, 1))
local replacementLookupCalls = 0
local mutableDependencies = {
    Capability = mutableCapabilities,
    getPlayerByOnlineID = function()
        return capturedTarget
    end,
}
local capturedConstruction = Build42AdminBoundary.create(mutableDependencies)
assertTrue(capturedConstruction.ok, "captured dependency construction")
local capturedBoundary = capturedConstruction.boundary
mutableCapabilities.CanSeePlayersStats = {}
mutableCapabilities.CanModifyPlayerStatsInThePlayerStatsUI = {}
mutableDependencies.getPlayerByOnlineID = function()
    replacementLookupCalls = replacementLookupCalls + 1
    return nil
end
local capturedRole = makeRole({ [oldSee] = true }, 10)
local capturedResult = capturedBoundary.authorizeAndResolve(
    makeActor(capturedRole),
    "inspect",
    { onlineId = 8, username = "Target" }
)
assertSuccess(capturedResult, capturedTarget, 8, "Target", "dependencies captured")
assertEqual(oldSee, capturedRole.lastCapability, "captured capability identity")
assertEqual(0, replacementLookupCalls, "captured lookup identity")

return assertionCount
