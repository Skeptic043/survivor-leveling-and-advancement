local InheritanceRecordStore = {}

local ROOT_SCHEMA = 1
local RECORD_SCHEMA = 1
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_USERNAME_BYTES = 64

local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function safeInteger(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
        and value >= 0 and value <= MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function safeProfile(value)
    return safeInteger(value) and value <= 3
end

local function safeUsername(value)
    if type(value) ~= "string" or value == "" or #value > MAX_USERNAME_BYTES then return false end
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then return false end
    end
    return true
end

local function exact(value, keys, count)
    if not plain(value) then return false end
    local found = 0
    for key in pairs(value) do
        if not keys[key] then return false end
        found = found + 1
    end
    return found == count
end

local function copyRecord(record)
    if not exact(record, { schemaVersion = true, deadSurvivorLevel = true }, 2)
        or rawget(record, "schemaVersion") ~= RECORD_SCHEMA
        or not safeInteger(rawget(record, "deadSurvivorLevel")) then
        return nil
    end
    return { schemaVersion = RECORD_SCHEMA, deadSurvivorLevel = rawget(record, "deadSurvivorLevel") }
end

local function copyProfileMap(source)
    if not plain(source) then return nil end
    local copy = {}
    for profileIndex, record in pairs(source) do
        if not safeProfile(profileIndex) then return nil end
        local detached = copyRecord(record)
        if detached == nil then return nil end
        copy[profileIndex] = detached
    end
    return copy
end

local function copyRoot(root)
    if not exact(root, { schemaVersion = true, sp = true, mp = true }, 3)
        or rawget(root, "schemaVersion") ~= ROOT_SCHEMA
        or not plain(rawget(root, "sp")) or not plain(rawget(root, "mp")) then
        return nil
    end
    local sp = copyProfileMap(rawget(root, "sp"))
    if sp == nil then return nil end
    local mp = {}
    for username, profiles in pairs(rawget(root, "mp")) do
        if not safeUsername(username) then return nil end
        local copiedProfiles = copyProfileMap(profiles)
        if copiedProfiles == nil then return nil end
        mp[username] = copiedProfiles
    end
    return { schemaVersion = ROOT_SCHEMA, sp = sp, mp = mp }
end

local function newRoot()
    return { schemaVersion = ROOT_SCHEMA, sp = {}, mp = {} }
end

local function profileMapEmpty(profiles)
    for _ in pairs(profiles) do return false end
    return true
end

local function copyOwner(owner)
    if not plain(owner) then return nil end
    local kind = rawget(owner, "kind")
    if kind == "sp" then
        if not exact(owner, { kind = true, profileIndex = true }, 2)
            or not safeProfile(rawget(owner, "profileIndex")) then return nil end
        return { kind = "sp", profileIndex = rawget(owner, "profileIndex") }
    end
    if kind == "mp" then
        if not exact(owner, {
            kind = true, primaryLoginUsername = true, profileIndex = true,
        }, 3) or not safeUsername(rawget(owner, "primaryLoginUsername"))
            or not safeProfile(rawget(owner, "profileIndex")) then return nil end
        return {
            kind = "mp",
            primaryLoginUsername = rawget(owner, "primaryLoginUsername"),
            profileIndex = rawget(owner, "profileIndex"),
        }
    end
    return nil
end

local function locate(root, owner, createAccount)
    if owner.kind == "sp" then return root.sp, owner.profileIndex end
    local profiles = root.mp[owner.primaryLoginUsername]
    if profiles == nil and createAccount then
        profiles = {}
        root.mp[owner.primaryLoginUsername] = profiles
    end
    return profiles, owner.profileIndex
end

local function failure(code)
    return { ok = false, code = code }
end

function InheritanceRecordStore.create(dependencies)
    if not plain(dependencies)
        or type(rawget(dependencies, "readRoot")) ~= "function"
        or type(rawget(dependencies, "writeRoot")) ~= "function" then
        return failure("invalid_capabilities")
    end
    local readRoot, writeRoot = rawget(dependencies, "readRoot"), rawget(dependencies, "writeRoot")

    local function readValidated(allowAbsent)
        local called, root = pcall(readRoot)
        if not called then return nil, "read_failed" end
        if root == nil and allowAbsent then return newRoot(), nil, true end
        local copied = copyRoot(root)
        if copied == nil then return nil, "invalid_root" end
        return copied, nil, false
    end

    local function writeValidated(root)
        local called, accepted = pcall(writeRoot, root)
        return called and accepted == true
    end

    local store = {}

    function store.peek(ownerValue)
        local owner = copyOwner(ownerValue)
        if owner == nil then return failure("invalid_owner") end
        local root, code = readValidated(true)
        if root == nil then return failure(code) end
        local profiles, profileIndex = locate(root, owner, false)
        local record = profiles and profiles[profileIndex] or nil
        if record == nil then return { ok = true, found = false } end
        return { ok = true, found = true, record = copyRecord(record) }
    end

    function store.put(ownerValue, deadSurvivorLevel)
        local owner = copyOwner(ownerValue)
        if owner == nil then return failure("invalid_owner") end
        if not safeInteger(deadSurvivorLevel) then return failure("invalid_level") end
        local root, code = readValidated(true)
        if root == nil then return failure(code) end
        local profiles, profileIndex = locate(root, owner, true)
        profiles[profileIndex] = {
            schemaVersion = RECORD_SCHEMA,
            deadSurvivorLevel = deadSurvivorLevel,
        }
        if not writeValidated(root) then return failure("write_failed") end
        return { ok = true, stored = true }
    end

    function store.consume(ownerValue, expectedRecord)
        local owner = copyOwner(ownerValue)
        if owner == nil then return failure("invalid_owner") end
        local expected = copyRecord(expectedRecord)
        if expected == nil then return failure("invalid_record") end
        local root, code = readValidated(true)
        if root == nil then return failure(code) end
        local profiles, profileIndex = locate(root, owner, false)
        local current = profiles and profiles[profileIndex] or nil
        if current == nil or current.schemaVersion ~= expected.schemaVersion
            or current.deadSurvivorLevel ~= expected.deadSurvivorLevel then
            return { ok = true, consumed = false }
        end
        profiles[profileIndex] = nil
        if owner.kind == "mp" and profileMapEmpty(profiles) then
            root.mp[owner.primaryLoginUsername] = nil
        end
        if not writeValidated(root) then return failure("write_failed") end
        return { ok = true, consumed = true, record = copyRecord(current) }
    end

    return { ok = true, store = store }
end

return InheritanceRecordStore
