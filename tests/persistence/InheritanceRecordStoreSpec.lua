local StoreModule = InheritanceRecordStore
local assertions = 0

local function yes(value, message) assertions = assertions + 1; if not value then error(message, 2) end end
local function no(value, message) assertions = assertions + 1; if value then error(message, 2) end end
local function eq(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local function sp(index) return { kind = "sp", profileIndex = index } end
local function mp(username, index)
    return { kind = "mp", primaryLoginUsername = username, profileIndex = index }
end

local root, writes, reads = nil, 0, 0
local creation = StoreModule.create({
    readRoot = function() reads = reads + 1; return root end,
    writeRoot = function(value) writes = writes + 1; root = value; return true end,
})
yes(creation.ok, "valid store capabilities create")
local store = creation.store
eq(StoreModule.create(nil).code, "invalid_capabilities", "nil capabilities rejected")
eq(StoreModule.create({ readRoot = function() end }).code, "invalid_capabilities", "missing writer rejected")
eq(StoreModule.create(setmetatable({ readRoot = function() end, writeRoot = function() end }, {})).code,
    "invalid_capabilities", "metatable capabilities rejected")

local empty = store.peek(sp(0))
yes(empty.ok, "absent root reads as empty")
no(empty.found, "absent root has no record")
eq(writes, 0, "peek never creates root")

yes(store.put(sp(0), 10).ok, "SP zero profile stores")
yes(store.put(sp(1), 20).ok, "SP one profile stores separately")
yes(store.put(mp("login", 0), 30).ok, "MP primary stores")
yes(store.put(mp("login", 1), 40).ok, "MP secondary stores separately")
yes(store.put(mp("login:1", 0), 50).ok, "nested username with delimiter character stores")
eq(root.sp[0].deadSurvivorLevel, 10, "SP zero retained")
eq(root.sp[1].deadSurvivorLevel, 20, "SP one retained")
eq(root.mp.login[0].deadSurvivorLevel, 30, "MP primary retained")
eq(root.mp.login[1].deadSurvivorLevel, 40, "MP secondary retained")
eq(root.mp["login:1"][0].deadSurvivorLevel, 50, "delimiter username cannot collide")
eq(root["login:1:0"], nil, "store never creates delimiter keys")

yes(store.put(sp(0), 77).ok, "later valid death overwrites")
eq(store.peek(sp(0)).record.deadSurvivorLevel, 77, "newest overwrite wins")
local detached = store.peek(mp("login", 1))
detached.record.deadSurvivorLevel = 999
eq(store.peek(mp("login", 1)).record.deadSurvivorLevel, 40, "peek record is detached")

local beforeStale = writes
local stale = store.consume(sp(0), { schemaVersion = 1, deadSurvivorLevel = 10 })
yes(stale.ok, "stale exact consume is handled")
no(stale.consumed, "stale record is not consumed")
eq(writes, beforeStale, "stale consume performs no write")
local consumed = store.consume(sp(0), { schemaVersion = 1, deadSurvivorLevel = 77 })
yes(consumed.ok and consumed.consumed, "exact record consumes")
eq(consumed.record.deadSurvivorLevel, 77, "consumed record returned detached")
eq(root.sp[0], nil, "consume removes exact SP record")
eq(root.sp[1].deadSurvivorLevel, 20, "consume preserves other SP profile")
eq(root.mp.login[1].deadSurvivorLevel, 40, "consume preserves MP records")
consumed.record.deadSurvivorLevel = 1
eq(root.sp[1].deadSurvivorLevel, 20, "consumed return cannot mutate root")

local consumedPrimary = store.consume(mp("login", 0), { schemaVersion = 1, deadSurvivorLevel = 30 })
yes(consumedPrimary.ok and consumedPrimary.consumed, "MP primary record consumes")
eq(root.mp.login[0], nil, "MP consume removes exact profile record")
eq(root.mp.login[1].deadSurvivorLevel, 40, "MP consume preserves sibling profile")
eq(root.mp["login:1"][0].deadSurvivorLevel, 50, "MP consume preserves sibling account")
local consumedSecondary = store.consume(mp("login", 1), { schemaVersion = 1, deadSurvivorLevel = 40 })
yes(consumedSecondary.ok and consumedSecondary.consumed, "last MP profile record consumes")
eq(root.mp.login, nil, "last MP consume prunes raw username bucket")
eq(root.mp["login:1"][0].deadSurvivorLevel, 50, "MP bucket prune preserves sibling account")

local invalidOwners = {
    sp(-1), sp(4), sp(1.5),
    mp("", 0), mp("bad\nlogin", 0), mp(string.rep("x", 65), 0), mp("login", 4),
    { kind = "mp", primaryLoginUsername = "login", profileIndex = 0, extra = true },
    setmetatable(sp(0), {}),
}
for index = 1, #invalidOwners do
    local before = writes
    eq(store.put(invalidOwners[index], 1).code, "invalid_owner", "unsafe owner rejected")
    eq(writes, before, "unsafe owner never writes")
end
for _, level in ipairs({ -1, 1.5, math.huge, "1" }) do
    eq(store.put(sp(0), level).code, "invalid_level", "unsafe level rejected")
end

local validRoot = root
local malformedRoots = {
    { schemaVersion = 2, sp = {}, mp = {} },
    { schemaVersion = 1, sp = {}, mp = {}, extra = true },
    { schemaVersion = 1, sp = { [0] = { schemaVersion = 2, deadSurvivorLevel = 1 } }, mp = {} },
    { schemaVersion = 1, sp = { [4] = { schemaVersion = 1, deadSurvivorLevel = 1 } }, mp = {} },
    { schemaVersion = 1, sp = {}, mp = { ["bad\n"] = {} } },
    setmetatable({ schemaVersion = 1, sp = {}, mp = {} }, {}),
}
for index = 1, #malformedRoots do
    root = malformedRoots[index]
    local before = writes
    eq(store.peek(sp(0)).code, "invalid_root", "malformed or newer root fails closed")
    eq(store.put(sp(0), 1).code, "invalid_root", "malformed root is not rewritten")
    eq(writes, before, "malformed root performs no write")
    eq(root, malformedRoots[index], "malformed root identity remains unchanged")
end
root = validRoot

local writeFail = StoreModule.create({
    readRoot = function() return nil end,
    writeRoot = function() return false end,
}).store
eq(writeFail.put(sp(0), 1).code, "write_failed", "rejected write fails closed")
local readFail = StoreModule.create({
    readRoot = function() error("read") end,
    writeRoot = function() return true end,
}).store
eq(readFail.peek(sp(0)).code, "read_failed", "throwing read fails closed")

return assertions
