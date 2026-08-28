local World = Build42InheritanceWorldStore
local Records = InheritanceRecordStore
local assertions = 0
local function eq(a, b, m) assertions = assertions + 1; if a ~= b then error(m .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function yes(v, m) eq(v, true, m) end

local namespaces, getCalls, addCalls, transmitCalls = {}, 0, 0, 0
local lastGetName, lastAddName
local function adapter()
    return World.create({
        getOrCreate = function(name)
            getCalls, lastGetName = getCalls + 1, name
            if namespaces[name] == nil then namespaces[name] = {} end
            return namespaces[name]
        end,
        add = function(name, value)
            addCalls, lastAddName = addCalls + 1, name
            namespaces[name] = value
        end,
        transmit = function() transmitCalls = transmitCalls + 1 end,
    })
end

local created = adapter()
yes(created.ok, "world capabilities create")
local store = Records.create(created.capabilities).store
local owner = { kind = "sp", profileIndex = 0 }
local empty = store.peek(owner)
yes(empty.ok, "new empty namespace is absent")
eq(empty.found, false, "empty namespace has no pending record")
eq(lastGetName, "SLA_InheritancePending_v1", "exact private namespace read")
eq(addCalls, 0, "read does not replace namespace")
yes(store.put(owner, 7).ok, "validated D1 write persists")
eq(lastAddName, "SLA_InheritancePending_v1", "exact private namespace replaced")
eq(namespaces[lastAddName].sp[0].deadSurvivorLevel, 7, "exact D1 root stored")
eq(transmitCalls, 0, "private root is never transmitted")

local recreated = Records.create(adapter().capabilities).store
eq(recreated.peek(owner).record.deadSurvivorLevel, 7, "persistence survives adapter recreation")
local malformed = { schemaVersion = 2, sp = {}, mp = {} }
namespaces[lastAddName] = malformed
local beforeAdds = addCalls
eq(recreated.peek(owner).code, "invalid_root", "newer root fails closed")
eq(recreated.put(owner, 8).code, "invalid_root", "newer root is not rewritten")
eq(addCalls, beforeAdds, "malformed root performs no add")
eq(namespaces[lastAddName], malformed, "malformed root identity preserved")

local rejected = World.create({
    getOrCreate = function() return {} end,
    add = function() return false end,
}).capabilities
eq(Records.create(rejected).store.put(owner, 1).code, "write_failed", "replace rejection contained")
local throwing = World.create({
    getOrCreate = function() error("read") end,
    add = function() end,
}).capabilities
eq(Records.create(throwing).store.peek(owner).code, "read_failed", "read throw contained")
eq(World.create(nil).code, "invalid_capabilities", "nil capabilities rejected")
eq(World.create({}).code, "invalid_capabilities", "missing capabilities rejected")

return assertions
