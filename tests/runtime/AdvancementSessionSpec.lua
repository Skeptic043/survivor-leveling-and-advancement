local count = 0
local function yes(value, message)
    count = count + 1
    if not value then error(message or "expected true") end
end
local function no(value, message)
    count = count + 1
    if value then error(message or "expected false") end
end
local function eq(actual, expected, message)
    count = count + 1
    if actual ~= expected then error((message or "not equal") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)) end
end
local function keys(value, allowed, message)
    for key in pairs(value) do yes(allowed[key] == true, (message or "unexpected key") .. ": " .. tostring(key)) end
    for key in pairs(allowed) do yes(rawget(value, key) ~= nil, (message or "missing key") .. ": " .. tostring(key)) end
end
local function request(perkId, requestId, revision)
    return { perkId = perkId or "Strength", requestId = requestId or "request-1", expectedRevision = revision or 0 }
end
local function failure(code, detail)
    return { ok = false, code = code or "rejected", detail = detail or "ordinary rejection" }
end
local function success(submitted, overrides)
    local result = {
        ok = true,
        requestId = submitted and submitted.requestId or "request-1",
        perkId = submitted and submitted.perkId or "Strength",
        revision = 1,
        spent = 1,
        availableAp = 0,
        apCost = 1,
        mastered = false,
        addedTarget = true,
        clearedTargetIds = {},
        xpWriteInvoked = true,
        levelWriteInvoked = false,
        recovered = false,
    }
    if overrides then for key, value in pairs(overrides) do result[key] = value end end
    return result
end
local function fixture()
    local f = {
        calls = {},
        ready = true,
        settingsResult = { ok = true, settings = { maximum = 3 } },
        spendResult = success(),
        snapshotResult = { ok = true, snapshot = { protocolVersion = 1, perks = { Strength = { level = 2 } } } },
    }
    local ap = {}
    function ap.spend(player, submitted, settings)
        f.calls[#f.calls + 1] = "spend"
        f.spendPlayer, f.spendRequest, f.spendSettings = player, submitted, settings
        if type(f.spendResult) == "function" then return f.spendResult(player, submitted, settings) end
        return f.spendResult
    end
    local settings = {}
    function settings.resolve(player, perkId)
        f.calls[#f.calls + 1] = "settings"
        f.settingsPlayer, f.settingsPerkId = player, perkId
        if type(f.settingsResult) == "function" then return f.settingsResult(player, perkId) end
        return f.settingsResult
    end
    local owner = {}
    function owner.isReady(player)
        f.calls[#f.calls + 1] = "ready"
        f.readyPlayer = player
        if type(f.ready) == "function" then return f.ready(player) end
        return f.ready
    end
    function owner.snapshot(player)
        f.calls[#f.calls + 1] = "snapshot"
        f.snapshotPlayer = player
        if type(f.snapshotResult) == "function" then return f.snapshotResult(player) end
        return f.snapshotResult
    end
    local created = AdvancementSession.create({ apTransaction = ap, allotmentSettings = settings, ownerSession = owner })
    eq(created.ok, true, "fixture created")
    return f, created.session, ap, settings, owner
end
local function assertFailure(result, code, committed)
    eq(result.ok, false, "failure ok")
    eq(result.code, code, "failure code")
    yes(type(result.detail) == "string" and #result.detail > 0 and #result.detail <= 160, "failure detail bounded")
    if committed == nil then
        eq(result.committed, nil, "construction has no committed marker")
        keys(result, { ok = true, code = true, detail = true }, "failure shape")
    else
        eq(result.committed, committed, "failure committed")
        keys(result, { ok = true, code = true, detail = true, committed = true }, "failure shape")
    end
end

do
    local f, session = fixture()
    local player, submitted = {}, request()
    local result = session.request(player, submitted)
    eq(result.ok, true, "success")
    eq(result.applied, true, "success applied")
    eq(result.requestId, submitted.requestId, "request id")
    eq(result.perkId, submitted.perkId, "perk id")
    eq(result.apCost, 1, "ap cost")
    eq(result.mastered, false, "mastered")
    keys(result, { ok = true, applied = true, requestId = true, perkId = true, apCost = true, mastered = true, snapshot = true }, "success shape")
    eq(table.concat(f.calls, ","), "ready,settings,spend,snapshot", "success order")
    eq(f.readyPlayer, player, "ready player identity")
    eq(f.settingsPlayer, player, "settings player identity")
    eq(f.settingsPerkId, submitted.perkId, "settings perk identity")
    eq(f.spendPlayer, player, "spend player identity")
    eq(f.spendRequest, submitted, "request identity")
    eq(f.spendSettings, f.settingsResult.settings, "settings identity")
    eq(f.snapshotPlayer, player, "snapshot player identity")
    eq(result.snapshot, f.snapshotResult.snapshot, "snapshot identity preserved")
    eq(result.snapshot.perks, f.snapshotResult.snapshot.perks, "nested snapshot identity preserved")
    f.snapshotResult.snapshot.perks.Strength.level = 99
    eq(result.snapshot.perks.Strength.level, 99, "owner projection is passed through")
end

do
    local f, session = fixture()
    f.ready = false
    local result = session.request({}, request())
    assertFailure(result, "not_ready", false)
    eq(table.concat(f.calls, ","), "ready", "unready ordering")
end

do
    local f, session = fixture()
    f.ready = function() error("boom") end
    assertFailure(session.request({}, request()), "readiness_failed", false)
    eq(table.concat(f.calls, ","), "ready", "readiness throw ordering")
    f, session = fixture()
    f.ready = "yes"
    assertFailure(session.request({}, request()), "readiness_failed", false)
    eq(table.concat(f.calls, ","), "ready", "readiness malformed ordering")
end

do
    local f, session = fixture()
    f.settingsResult = function() error("boom") end
    assertFailure(session.request({}, request()), "settings_failed", false)
    eq(table.concat(f.calls, ","), "ready,settings", "settings throw ordering")
    f, session = fixture()
    f.settingsResult = { ok = true, settings = {}, extra = true }
    assertFailure(session.request({}, request()), "settings_failed", false)
    f, session = fixture()
    f.settingsResult = { ok = false, code = "bad_settings", detail = "not usable" }
    assertFailure(session.request({}, request()), "settings_failed", false)
    eq(session.request({}, request()).detail, "bad_settings:not usable", "settings nested detail")
    f, session = fixture()
    f.settingsResult = { ok = true, settings = setmetatable({}, {}) }
    assertFailure(session.request({}, request()), "settings_failed", false)
end

do
    local f, session = fixture()
    f.spendResult = function() error("boom") end
    assertFailure(session.request({}, request()), "ap_failed", false)
    eq(table.concat(f.calls, ","), "ready,settings,spend", "spend throw ordering")
    f, session = fixture()
    f.spendResult = success(nil, { extra = true })
    assertFailure(session.request({}, request()), "ap_failed", false)
    f, session = fixture()
    f.spendResult = setmetatable(success(), {})
    assertFailure(session.request({}, request()), "ap_failed", false)
    f, session = fixture()
    f.spendResult = { ok = false, code = "bad code", detail = "ordinary rejection" }
    assertFailure(session.request({}, request()), "ap_failed", false)
end

do
    local f, session = fixture()
    local submitted = request("Fitness", "full-shape", 0)
    f.spendResult = success(submitted, { revision = 2, spent = 3, availableAp = 4, apCost = 2, mastered = true, addedTarget = false, clearedTargetIds = { "old-target" }, xpWriteInvoked = false, levelWriteInvoked = true, recovered = true })
    local result = session.request({}, submitted)
    eq(result.ok, true, "full AP result accepted")
    eq(result.apCost, 2, "full AP result cost extracted")
    eq(result.mastered, true, "full AP result mastery extracted")
    f, session = fixture()
    f.spendResult = success(request(), { addedTarget = false, xpWriteInvoked = false })
    result = session.request({}, request())
    eq(result.ok, true, "ordinary reboost accepted")
    eq(result.apCost, 1, "ordinary reboost cost")
    eq(result.mastered, false, "ordinary reboost is not mastery")
    f, session = fixture()
    f.spendResult = success(request(), { requestId = "different" })
    assertFailure(session.request({}, request()), "ap_failed", false)
    f, session = fixture()
    f.spendResult = success(request(), { clearedTargetIds = { [2] = "gap" } })
    assertFailure(session.request({}, request()), "ap_failed", false)
    f, session = fixture()
    f.spendResult = success(request(), { apCost = 2, mastered = false })
    assertFailure(session.request({}, request()), "ap_failed", false)
    f, session = fixture()
    f.spendResult = success(request(), { apCost = 1, mastered = true, addedTarget = false })
    assertFailure(session.request({}, request()), "ap_failed", false)
end

do
    local f, session = fixture()
    f.spendResult = failure("no_ap", "need one point")
    local result = session.request({}, request())
    eq(result.ok, true, "ordinary rejection handled")
    eq(result.applied, false, "ordinary rejection not applied")
    eq(result.code, "no_ap", "ordinary rejection code")
    eq(result.detail, "need one point", "ordinary rejection detail")
    keys(result, { ok = true, applied = true, requestId = true, perkId = true, code = true, detail = true }, "ordinary rejection shape")
    eq(table.concat(f.calls, ","), "ready,settings,spend", "ordinary rejection does not project")
end

do
    local ordinaryCodes = {
        "store_load_failed", "recovery_quarantined", "invalid_request", "resolver_failed", "adapter_description_failed",
        "adapter_inspection_failed", "adapter_identity_mismatch", "perk_quarantined", "observation_failed",
        "stale_revision", "invalid_state", "no_ap", "misaligned_progression", "at_maximum", "red_recovery",
        "target_rejected", "allotment_invalid", "allotment_rejected", "scope_begin_failed", "reservation_save_failed",
        "scope_finish_failed", "engine_mutation_failed", "post_inspection_failed", "commit_save_failed",
    }
    for _, code in ipairs(ordinaryCodes) do
        local f, session = fixture()
        f.spendResult = failure(code, "ordinary rejection")
        local result = session.request({}, request())
        eq(result.ok, true, "ordinary AP rejection handled: " .. code)
        eq(result.applied, false, "ordinary AP rejection not applied: " .. code)
        eq(result.code, code, "ordinary AP rejection code: " .. code)
        eq(result.detail, "ordinary rejection", "ordinary AP rejection detail: " .. code)
        if code == "stale_revision" then
            yes(type(result.snapshot) == "table", "only stale projects: " .. code)
            eq(table.concat(f.calls, ","), "ready,settings,spend,snapshot", "stale AP rejection order")
        else
            eq(result.snapshot, nil, "ordinary AP rejection omits snapshot: " .. code)
            eq(table.concat(f.calls, ","), "ready,settings,spend", "ordinary AP rejection order: " .. code)
        end
        keys(result, code == "stale_revision"
            and { ok = true, applied = true, requestId = true, perkId = true, code = true, detail = true, snapshot = true }
            or { ok = true, applied = true, requestId = true, perkId = true, code = true, detail = true }, "ordinary AP rejection shape: " .. code)
    end
end

do
    local f, session = fixture()
    f.spendResult = failure("stale_revision", "revision changed")
    local result = session.request({}, request())
    eq(result.ok, true, "stale handled")
    eq(result.applied, false, "stale not applied")
    eq(result.snapshot.protocolVersion, 1, "stale snapshot included")
    eq(table.concat(f.calls, ","), "ready,settings,spend,snapshot", "stale projects")
    f, session = fixture()
    f.spendResult = failure("stale_revision", "revision changed")
    f.snapshotResult = failure("not_ready", "projection unavailable")
    result = session.request({}, request())
    eq(result.ok, true, "stale remains handled")
    eq(result.code, "stale_revision", "stale code retained")
    eq(result.snapshot, nil, "stale failed snapshot omitted")
    f, session = fixture()
    f.spendResult = failure("stale_revision", "revision changed")
    f.snapshotResult = function() error("boom") end
    result = session.request({}, request())
    eq(result.ok, true, "stale throw remains handled")
    eq(result.snapshot, nil, "stale thrown snapshot omitted")
end

do
    local f, session = fixture()
    f.snapshotResult = function() error("boom") end
    assertFailure(session.request({}, request()), "post_commit_snapshot_failed", true)
    eq(table.concat(f.calls, ","), "ready,settings,spend,snapshot", "post commit throw order")
    f, session = fixture()
    f.snapshotResult = { ok = false, code = "not_ready", detail = "projection unavailable" }
    local result = session.request({}, request())
    assertFailure(result, "post_commit_snapshot_failed", true)
    eq(result.detail, "not_ready:projection unavailable", "post commit nested detail")
    f, session = fixture()
    f.snapshotResult = { ok = true, snapshot = {}, extra = true }
    assertFailure(session.request({}, request()), "post_commit_snapshot_failed", true)
    f, session = fixture()
    f.snapshotResult = { ok = true, snapshot = setmetatable({}, {}) }
    assertFailure(session.request({}, request()), "post_commit_snapshot_failed", true)
end

do
    local f, session = fixture()
    assertFailure(session.request({}, nil), "invalid_request", false)
    local invalid = {
        { perkId = "", requestId = "request", expectedRevision = 0 },
        { perkId = "perk!", requestId = "request", expectedRevision = 0 },
        { perkId = string.rep("a", 129), requestId = "request", expectedRevision = 0 },
        { perkId = "perk", requestId = string.rep("b", 65), expectedRevision = 0 },
        { perkId = "perk", requestId = "r\195\169", expectedRevision = 0 },
        { perkId = "perk", requestId = "request", expectedRevision = -1 },
        { perkId = "perk", requestId = "request", expectedRevision = 1.5 },
        { perkId = "perk", requestId = "request", expectedRevision = 9007199254740992 },
        { perkId = "perk", requestId = "request", expectedRevision = 0, extra = true },
        setmetatable({ perkId = "perk", requestId = "request", expectedRevision = 0 }, {}),
    }
    for _, submitted in ipairs(invalid) do assertFailure(session.request({}, submitted), "invalid_request", false) end
    eq(#f.calls, 0, "invalid requests do not call dependencies")
    local boundary = request(string.rep("a", 128), string.rep("b", 64), 9007199254740991)
    f.spendResult = function(_, submitted) return success(submitted) end
    local result = session.request({}, boundary)
    eq(result.ok, true, "ASCII and safe integer boundary accepted")
end

do
    local f, session, ap, settings, owner = fixture()
    local originalSpend, originalResolve, originalReady, originalSnapshot = ap.spend, settings.resolve, owner.isReady, owner.snapshot
    ap.spend = function() error("mutated") end
    settings.resolve = function() error("mutated") end
    owner.isReady = function() error("mutated") end
    owner.snapshot = function() error("mutated") end
    local result = session.request({}, request())
    eq(result.ok, true, "captured callables used")
    yes(originalSpend ~= ap.spend and originalResolve ~= settings.resolve and originalReady ~= owner.isReady and originalSnapshot ~= owner.snapshot, "dependencies mutated")
end

do
    local malformed = {
        {},
        { apTransaction = {}, allotmentSettings = {}, ownerSession = {} },
        { apTransaction = { spend = function() end }, allotmentSettings = { resolve = function() end }, ownerSession = { isReady = function() end } },
        { apTransaction = { spend = function() end }, allotmentSettings = { resolve = function() end }, ownerSession = { isReady = function() end, snapshot = function() end }, extra = true },
        setmetatable({ apTransaction = {}, allotmentSettings = {}, ownerSession = {} }, {}),
    }
    assertFailure(AdvancementSession.create(nil), "construction_invalid")
    for _, dependencies in ipairs(malformed) do
        local result = AdvancementSession.create(dependencies)
        assertFailure(result, "construction_invalid")
    end
    local throwing = setmetatable({}, { __index = function() error("index") end })
    assertFailure(AdvancementSession.create(throwing), "construction_invalid")
end

return count
