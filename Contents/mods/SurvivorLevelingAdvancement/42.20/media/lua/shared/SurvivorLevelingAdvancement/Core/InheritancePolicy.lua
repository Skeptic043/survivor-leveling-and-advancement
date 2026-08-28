local InheritancePolicy = {}

local MAX_SAFE_INTEGER = 9007199254740991

local INPUT_KEYS = {
    initializationStatus = true,
    enabled = true,
    retainedRatio = true,
    pendingDeadLevel = true,
    tokenStatus = true,
}

local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function safeInteger(value)
    return finite(value) and value >= 0 and value <= MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function invalid()
    return { ok = false, code = "invalid_input" }
end

function InheritancePolicy.plan(input)
    if not plain(input) then return invalid() end
    local validKeys, count = true, 0
    for key in pairs(input) do
        if not INPUT_KEYS[key] then validKeys = false end
        count = count + 1
    end
    if not validKeys or count < 4 or count > 5 then return invalid() end

    local initializationStatus = rawget(input, "initializationStatus")
    local enabled = rawget(input, "enabled")
    local retainedRatio = rawget(input, "retainedRatio")
    local pendingDeadLevel = rawget(input, "pendingDeadLevel")
    local tokenStatus = rawget(input, "tokenStatus")
    if (initializationStatus ~= "existing"
            and initializationStatus ~= "fresh_unmarked"
            and initializationStatus ~= "genuine_new")
        or type(enabled) ~= "boolean"
        or not finite(retainedRatio) or retainedRatio < 0 or retainedRatio > 1
        or (tokenStatus ~= "valid" and tokenStatus ~= "absent")
        or (pendingDeadLevel ~= nil and not safeInteger(pendingDeadLevel)) then
        return invalid()
    end

    if initializationStatus == "existing" then
        return { ok = true, outcome = "existing", consumePending = false, survivorLevel = 0 }
    end
    if initializationStatus == "fresh_unmarked" or not enabled
        or tokenStatus ~= "valid" or pendingDeadLevel == nil then
        return { ok = true, outcome = "fresh", consumePending = false, survivorLevel = 0 }
    end
    local survivorLevel = math.floor(pendingDeadLevel * retainedRatio)
    if not safeInteger(survivorLevel) then return invalid() end
    return {
        ok = true,
        outcome = "inherit",
        consumePending = true,
        survivorLevel = survivorLevel,
    }
end

return InheritancePolicy
