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
            adapterVersion = 1,
            representation = "java-binary32",
        }
    end

    function arithmetic.previous(positionAfter, eventAmount)
        if not isFinite(positionAfter) or positionAfter < 0 then
            return failure("invalid-position-after", "positionAfter must be finite and nonnegative")
        end
        if not isFinite(eventAmount) or eventAmount <= 0 then
            return failure("invalid-event-amount", "eventAmount must be finite and positive")
        end

        local callOK, positionBefore = pcall(
            clampFloat,
            positionAfter - eventAmount,
            -FLOAT_MAX,
            FLOAT_MAX
        )
        if not callOK then
            return failure("capability-error", "PZMath.clampFloat failed")
        end
        if not isFinite(positionBefore) then
            return failure("invalid-result", "PZMath.clampFloat returned a non-finite value")
        end
        if positionBefore < 0 or positionBefore > positionAfter then
            return failure("invalid-result", "PZMath.clampFloat returned an invalid prior position")
        end
        if positionBefore >= positionAfter then
            return failure("no-representable-movement", "eventAmount did not move the stored float")
        end

        return {
            ok = true,
            positionBefore = positionBefore,
        }
    end

    return {
        ok = true,
        arithmetic = arithmetic,
    }
end

return Build42XpPositionArithmetic
