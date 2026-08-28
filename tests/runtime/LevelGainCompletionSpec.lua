local assertions = 0

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local function valid(value, levels)
    local result = LevelGainCompletion.validate(value)
    equal(result.ok, true, "completion accepted")
    equal(result.completion.protocolVersion, 1, "protocol detached")
    equal(result.completion.kind, "survivor_level_gain", "kind detached")
    equal(result.completion.levelsGained, levels, "level count detached")
    equal(result.completion.apGained, levels, "AP count detached")
    equal(result.completion == value, false, "completion detached from caller")
end

valid({ protocolVersion = 1, kind = "survivor_level_gain", levelsGained = 1, apGained = 1 }, 1)
valid({ protocolVersion = 1, kind = "survivor_level_gain", levelsGained = 7, apGained = 7 }, 7)

local created = LevelGainCompletion.create(3, 3)
equal(created.ok, true, "factory accepts equal positive gains")
equal(created.completion.levelsGained, 3, "factory levels")
equal(created.completion.apGained, 3, "factory AP")

local invalid = {
    {},
    { protocolVersion = 2, kind = "survivor_level_gain", levelsGained = 1, apGained = 1 },
    { protocolVersion = 1, kind = "other", levelsGained = 1, apGained = 1 },
    { protocolVersion = 1, kind = "survivor_level_gain", levelsGained = 0, apGained = 0 },
    { protocolVersion = 1, kind = "survivor_level_gain", levelsGained = -1, apGained = -1 },
    { protocolVersion = 1, kind = "survivor_level_gain", levelsGained = 1.5, apGained = 1.5 },
    { protocolVersion = 1, kind = "survivor_level_gain", levelsGained = 2, apGained = 1 },
    { protocolVersion = 1, kind = "survivor_level_gain", levelsGained = math.huge, apGained = math.huge },
    { protocolVersion = 1, kind = "survivor_level_gain", levelsGained = 1, apGained = 1, private = true },
}
equal(LevelGainCompletion.validate(nil).ok, false, "nil completion rejected")
for index = 1, #invalid do
    local result = LevelGainCompletion.validate(invalid[index])
    equal(result.ok, false, "invalid completion rejected " .. index)
    equal(result.code, "invalid_completion", "invalid completion code " .. index)
end
local hostile = setmetatable({ protocolVersion = 1, kind = "survivor_level_gain", levelsGained = 1, apGained = 1 }, {})
equal(LevelGainCompletion.validate(hostile).ok, false, "metatable completion rejected")
equal(LevelGainCompletion.create(0, 0).ok, false, "zero factory rejected")
equal(LevelGainCompletion.create(2, 1).ok, false, "unequal factory rejected")

return assertions
