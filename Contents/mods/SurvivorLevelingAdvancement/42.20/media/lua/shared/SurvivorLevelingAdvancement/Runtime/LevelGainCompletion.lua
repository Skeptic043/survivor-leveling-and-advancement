local LevelGainCompletion = {}

local PROTOCOL_VERSION = 1
local KIND = "survivor_level_gain"
local MAX_SAFE_INTEGER = 9007199254740991
local FIELDS = {
    protocolVersion = true,
    kind = true,
    levelsGained = true,
    apGained = true,
}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function safePositiveInteger(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
        and value > 0 and value <= MAX_SAFE_INTEGER
        and value == math.floor(value)
end

local function exactPlain(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    for key in pairs(value) do
        if type(key) ~= "string" or not FIELDS[key] then return false end
    end
    for key in pairs(FIELDS) do
        if rawget(value, key) == nil then return false end
    end
    return true
end

function LevelGainCompletion.validate(value)
    if not exactPlain(value)
        or rawget(value, "protocolVersion") ~= PROTOCOL_VERSION
        or rawget(value, "kind") ~= KIND
        or not safePositiveInteger(rawget(value, "levelsGained"))
        or rawget(value, "apGained") ~= rawget(value, "levelsGained") then
        return failure("invalid_completion", "level gain completion")
    end
    return {
        ok = true,
        completion = {
            protocolVersion = PROTOCOL_VERSION,
            kind = KIND,
            levelsGained = rawget(value, "levelsGained"),
            apGained = rawget(value, "apGained"),
        },
    }
end

function LevelGainCompletion.create(levelsGained, apGained)
    return LevelGainCompletion.validate({
        protocolVersion = PROTOCOL_VERSION,
        kind = KIND,
        levelsGained = levelsGained,
        apGained = apGained,
    })
end

return LevelGainCompletion
