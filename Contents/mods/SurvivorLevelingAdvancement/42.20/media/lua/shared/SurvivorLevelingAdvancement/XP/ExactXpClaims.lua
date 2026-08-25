local ExactXpClaims = {}

local function result(ok, code, claimed)
    return { ok = ok, code = code, claimed = claimed }
end

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function ExactXpClaims.create()
    local entries = {}
    local lastCode = "created"
    local instance = {}

    local function invalidIdentity(token, owner, perk, amount)
        if token == nil then
            return "invalid_token"
        elseif owner == nil then
            return "invalid_owner"
        elseif perk == nil then
            return "invalid_perk"
        elseif not isFinite(amount) then
            return "invalid_amount"
        end
        return nil
    end

    function instance.claim(token, owner, perk, amount)
        local invalid = invalidIdentity(token, owner, perk, amount)
        if invalid then
            lastCode = invalid
            return result(false, invalid, false)
        end

        entries[#entries + 1] = {
            token = token,
            owner = owner,
            perk = perk,
            amount = amount,
        }
        lastCode = "claimed"
        return result(true, "claimed", true)
    end

    function instance.consume(owner, perk, amount)
        local invalid = invalidIdentity(true, owner, perk, amount)
        if invalid then
            lastCode = invalid
            return result(false, invalid, false)
        end

        local claimed = false
        local kept = {}
        for index = 1, #entries do
            local entry = entries[index]
            if entry.owner == owner and entry.perk == perk and entry.amount == amount then
                claimed = true
            else
                kept[#kept + 1] = entry
            end
        end
        entries = kept
        lastCode = claimed and "consumed" or "not_claimed"
        return result(true, lastCode, claimed)
    end

    function instance.release(token)
        if token == nil then
            lastCode = "invalid_token"
            return result(false, "invalid_token", false)
        end

        local kept = {}
        for index = 1, #entries do
            local entry = entries[index]
            if entry.token ~= token then
                kept[#kept + 1] = entry
            end
        end
        entries = kept
        lastCode = "released"
        return result(true, "released", false)
    end

    function instance.status()
        local tokens = {}
        local tokenCount = 0
        for index = 1, #entries do
            local token = entries[index].token
            local seen = false
            for tokenIndex = 1, #tokens do
                if tokens[tokenIndex] == token then
                    seen = true
                    break
                end
            end
            if not seen then
                tokens[#tokens + 1] = token
                tokenCount = tokenCount + 1
            end
        end
        return {
            pendingClaims = #entries,
            activeTokens = tokenCount,
            lastCode = lastCode,
        }
    end

    return instance
end

return ExactXpClaims
