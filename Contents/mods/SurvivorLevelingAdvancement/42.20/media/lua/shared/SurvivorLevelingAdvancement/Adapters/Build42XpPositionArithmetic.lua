local Build42XpPositionArithmetic = {}

local FLOAT_MAX = 3.4028234663852886e38

local function failure(code, detail)
    return {
        ok = false,
        code = code,
        detail = detail,
    }
end

local function isFinite(value)
    return type(value) == "number"
            and value == value
            and value ~= math.huge
            and value ~= -math.huge
end

function Build42XpPositionArithmetic.create(dependencies)
    if type(dependencies) ~= "table"
            or type(dependencies.environment) ~= "table"
            or type(dependencies.environment.globals) ~= "table" then
        return failure("invalid-dependencies", "environment globals are required")
    end

    local lookupOK, clampFloat = pcall(function()
        return dependencies.environment.globals.PZMath.clampFloat
    end)
    if not lookupOK or type(clampFloat) ~= "function" then
        return failure("missing-capability", "PZMath.clampFloat is required")
    end

    local arithmetic = {}

    function arithmetic.describe()
        return {
            ok = true,
            adapterId = "sla.pz42-xp-position",
            adapterVersion = 2,
            representation = "java-binary32",
        }
    end

    function arithmetic.add(positionBefore, eventAmount)
        if not isFinite(positionBefore) or positionBefore < 0 then
            return failure("invalid-position-before", "positionBefore must be finite and nonnegative")
        end
        if not isFinite(eventAmount) then
            return failure("invalid-event-amount", "eventAmount must be finite")
        end

        local callOK, positionAfter = pcall(
            clampFloat,
            positionBefore + eventAmount,
            -FLOAT_MAX,
            FLOAT_MAX
        )
        if not callOK then
            return failure("capability-error", "PZMath.clampFloat failed")
        end
        if not isFinite(positionAfter) then
            return failure("invalid-result", "PZMath.clampFloat returned a non-finite value")
        end
        if positionAfter < 0 or positionAfter > FLOAT_MAX then
            return failure("invalid-result", "PZMath.clampFloat returned an invalid position")
        end

        return {
            ok = true,
            positionAfter = positionAfter,
            moved = positionAfter ~= positionBefore,
        }
    end

    return {
        ok = true,
        arithmetic = arithmetic,
    }
end

return Build42XpPositionArithmetic
