local assertions = 0

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local calls = {}
local goodColor = {}
local translations = {
    IGUI_SLA_LevelGain_Singular = "Survivor Level +%1",
    IGUI_SLA_LevelGain_Plural = "Survivor Levels +%1",
    IGUI_SLA_LevelGain_AP = "AP +%1",
}
local function getText(key, value)
    local text = translations[key]
    if text == nil then return key end
    return string.gsub(text, "%%1", tostring(value))
end
local halo = {
    getGoodColor = function() calls[#calls + 1] = { "color" }; return goodColor end,
    addTextWithArrow = function(player, first, second, upward, color)
        calls[#calls + 1] = { "halo", player, first, second, upward, color }
    end,
}
local created = Build42LevelFeedback.create({ HaloTextHelper = halo, getText = getText })
equal(created.ok, true, "presenter creates")
local player = {
    playGainExperienceLevelSound = function(self)
        calls[#calls + 1] = { "sound", self }
        return 1
    end,
}
local shown = created.presenter.show(player, { levelsGained = 1, apGained = 1 })
equal(shown.ok, true, "singular shows")
equal(#calls, 3, "one color, one halo, and one vanilla sound call")
equal(calls[2][2], player, "exact player passed")
equal(calls[2][3], "Survivor Level +1[br/]AP +1", "singular two-line text")
equal(calls[2][4], "[br/]", "vanilla merge separator")
equal(calls[2][5], true, "upward arrow")
equal(calls[2][6], goodColor, "good color")
equal(calls[3][1], "sound", "vanilla player sound seam called")
equal(calls[3][2], player, "sound uses exact player emitter")

calls = {}
shown = created.presenter.show(player, { levelsGained = 4, apGained = 4 })
equal(shown.ok, true, "plural shows")
equal(#calls, 3, "multi-level is one halo and one sound request")
equal(calls[2][3], "Survivor Levels +4[br/]AP +4", "plural two-line text")
equal(calls[2][4], "[br/]", "plural vanilla merge separator")

equal(Build42LevelFeedback.create(nil).ok, false, "nil dependencies rejected")
equal(Build42LevelFeedback.create({ HaloTextHelper = halo }).ok, false, "missing localization rejected")
equal(Build42LevelFeedback.create({ HaloTextHelper = {}, getText = getText }).ok, false, "missing halo API rejected")
equal(created.presenter.show(nil, { levelsGained = 1, apGained = 1 }).ok, false, "nil player rejected")
equal(created.presenter.show(player, { levelsGained = 0, apGained = 0 }).ok, false, "zero completion rejected")
equal(created.presenter.show(player, { levelsGained = 2, apGained = 1 }).ok, false, "unequal completion rejected")
equal(created.presenter.show({}, { levelsGained = 1, apGained = 1 }).ok, false, "missing player sound seam rejected")

local brokenText = Build42LevelFeedback.create({
    HaloTextHelper = halo,
    getText = function() error("translation") end,
}).presenter
equal(brokenText.show(player, { levelsGained = 1, apGained = 1 }).ok, false, "translation failure contained")
local brokenHalo = Build42LevelFeedback.create({
    HaloTextHelper = { getGoodColor = function() return goodColor end, addTextWithArrow = function() error("halo") end },
    getText = getText,
}).presenter
equal(brokenHalo.show(player, { levelsGained = 1, apGained = 1 }).ok, false, "halo failure contained")
local brokenSoundPlayer = {
    playGainExperienceLevelSound = function() error("sound") end,
}
equal(created.presenter.show(brokenSoundPlayer, { levelsGained = 1, apGained = 1 }).ok, false, "sound failure contained")

return assertions
