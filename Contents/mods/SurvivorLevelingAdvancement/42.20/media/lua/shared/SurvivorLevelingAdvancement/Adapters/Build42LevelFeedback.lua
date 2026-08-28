local Build42LevelFeedback = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

function Build42LevelFeedback.create(dependencies)
    if type(dependencies) ~= "table" then
        return failure("invalid_dependencies", "dependencies")
    end
    local halo = rawget(dependencies, "HaloTextHelper")
    local getText = rawget(dependencies, "getText")
    local addTextWithArrow = type(halo) == "table" and rawget(halo, "addTextWithArrow") or nil
    local getGoodColor = type(halo) == "table" and rawget(halo, "getGoodColor") or nil
    if type(addTextWithArrow) ~= "function" or type(getGoodColor) ~= "function"
        or type(getText) ~= "function" then
        return failure("invalid_dependencies", "HaloTextHelper and getText")
    end

    local presenter = {}

    function presenter.show(player, completion)
        if player == nil or type(completion) ~= "table" then
            return failure("invalid_feedback", "player and completion")
        end
        local count = rawget(completion, "levelsGained")
        if type(count) ~= "number" or count < 1 or count ~= math.floor(count)
            or rawget(completion, "apGained") ~= count then
            return failure("invalid_feedback", "completion")
        end
        local soundCalled, playLevelSound = pcall(function()
            return player.playGainExperienceLevelSound
        end)
        if not soundCalled or type(playLevelSound) ~= "function" then
            return failure("feedback_failed", "IsoPlayer.playGainExperienceLevelSound")
        end
        local firstKey = count == 1 and "IGUI_SLA_LevelGain_Singular"
            or "IGUI_SLA_LevelGain_Plural"
        local firstCalled, firstLine = pcall(getText, firstKey, count)
        local secondCalled, secondLine = pcall(getText, "IGUI_SLA_LevelGain_AP", count)
        if not firstCalled or not secondCalled
            or type(firstLine) ~= "string" or #firstLine == 0
            or type(secondLine) ~= "string" or #secondLine == 0
            or firstLine:find(";", 1, true) ~= nil or secondLine:find(";", 1, true) ~= nil
            or firstLine:find("[%c]") ~= nil or secondLine:find("[%c]") ~= nil then
            return failure("feedback_failed", "getText")
        end
        local colorCalled, color = pcall(getGoodColor)
        if not colorCalled or color == nil then
            return failure("feedback_failed", "HaloTextHelper.getGoodColor")
        end
        local shown = pcall(
            addTextWithArrow,
            player,
            firstLine .. "[br/]" .. secondLine,
            "[br/]",
            true,
            color
        )
        if not shown then
            return failure("feedback_failed", "HaloTextHelper.addTextWithArrow")
        end
        local played = pcall(playLevelSound, player)
        if not played then
            return failure("feedback_failed", "IsoPlayer.playGainExperienceLevelSound")
        end
        return { ok = true }
    end

    return { ok = true, presenter = presenter }
end

return Build42LevelFeedback
