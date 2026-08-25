local assertions = 0

local function assertTrue(value, message)
    assertions = assertions + 1
    if value ~= true then
        error(message or "expected true")
    end
end

local function assertFalse(value, message)
    assertions = assertions + 1
    if value ~= false then
        error(message or "expected false")
    end
end

local function assertEqual(expected, actual, message)
    assertions = assertions + 1
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assertNil(value, message)
    assertions = assertions + 1
    if value ~= nil then
        error(message or "expected nil")
    end
end

local function fieldCount(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

do
    local registry = ExactXpClaims.create()
    assertEqual("function", type(registry.claim))
    assertEqual("function", type(registry.consume))
    assertEqual("function", type(registry.release))
    assertEqual("function", type(registry.status))
    local status = registry.status()
    assertEqual(0, status.pendingClaims)
    assertEqual(0, status.activeTokens)
    assertEqual("created", status.lastCode)
end

do
    local registry = ExactXpClaims.create()
    local token = {}
    local owner = {}
    local perk = {}
    local invalid = {
        { nil, owner, perk, 1, "invalid_token" },
        { token, nil, perk, 1, "invalid_owner" },
        { token, owner, nil, 1, "invalid_perk" },
        { token, owner, perk, nil, "invalid_amount" },
        { token, owner, perk, "1", "invalid_amount" },
        { token, owner, perk, 0 / 0, "invalid_amount" },
        { token, owner, perk, math.huge, "invalid_amount" },
        { token, owner, perk, -math.huge, "invalid_amount" },
    }
    for index = 1, #invalid do
        local entry = invalid[index]
        local claimed = registry.claim(entry[1], entry[2], entry[3], entry[4])
        assertFalse(claimed.ok, "invalid claim rejected " .. index)
        assertEqual(entry[5], claimed.code, "invalid claim code " .. index)
        assertFalse(claimed.claimed, "invalid claim not marked claimed " .. index)
    end
    assertEqual(0, registry.status().pendingClaims)

    local invalidConsumes = {
        { nil, perk, 1, "invalid_owner" },
        { owner, nil, 1, "invalid_perk" },
        { owner, perk, nil, "invalid_amount" },
        { owner, perk, 0 / 0, "invalid_amount" },
        { owner, perk, math.huge, "invalid_amount" },
    }
    for index = 1, #invalidConsumes do
        local entry = invalidConsumes[index]
        local consumed = registry.consume(entry[1], entry[2], entry[3])
        assertFalse(consumed.ok, "invalid consume rejected " .. index)
        assertEqual(entry[4], consumed.code, "invalid consume code " .. index)
        assertFalse(consumed.claimed, "invalid consume not claimed " .. index)
    end
    local released = registry.release(nil)
    assertFalse(released.ok)
    assertEqual("invalid_token", released.code)
end

do
    local registry = ExactXpClaims.create()
    local token = {}
    local owner = {}
    local perk = {}
    assertTrue(registry.claim(token, owner, perk, -2.5).ok)
    assertTrue(registry.claim(token, owner, perk, -2.5).ok)
    local status = registry.status()
    assertEqual(2, status.pendingClaims, "identical claims remain distinct")
    assertEqual(1, status.activeTokens)
    local consumed = registry.consume(owner, perk, -2.5)
    assertTrue(consumed.ok)
    assertTrue(consumed.claimed, "one exact event consumes all matching claims")
    assertEqual("consumed", consumed.code)
    assertEqual(0, registry.status().pendingClaims)
    consumed = registry.consume(owner, perk, -2.5)
    assertTrue(consumed.ok)
    assertFalse(consumed.claimed)
    assertEqual("not_claimed", consumed.code)
end

do
    local registry = ExactXpClaims.create()
    local outer = {}
    local inner = {}
    local owner = {}
    local otherOwner = {}
    local perk = {}
    local otherPerk = {}
    assertTrue(registry.claim(outer, owner, perk, 1).ok)
    assertTrue(registry.claim(outer, owner, perk, 2).ok)
    assertTrue(registry.claim(inner, owner, perk, 1).ok)
    assertTrue(registry.claim(inner, otherOwner, perk, 1).ok)
    assertTrue(registry.claim(inner, owner, otherPerk, 1).ok)
    assertEqual(5, registry.status().pendingClaims)
    assertEqual(2, registry.status().activeTokens)

    local mismatch = registry.consume(owner, perk, 3)
    assertFalse(mismatch.claimed, "amount mismatch is preserved")
    assertEqual(5, registry.status().pendingClaims)
    mismatch = registry.consume(otherOwner, otherPerk, 1)
    assertFalse(mismatch.claimed, "identity mismatch is preserved")
    assertEqual(5, registry.status().pendingClaims)

    local exact = registry.consume(owner, perk, 1)
    assertTrue(exact.claimed)
    assertEqual(3, registry.status().pendingClaims, "matching tuple removed across nested tokens")
    assertEqual(2, registry.status().activeTokens)
    assertTrue(registry.release(outer).ok)
    assertEqual(2, registry.status().pendingClaims, "outer release preserves inner claims")
    assertEqual(1, registry.status().activeTokens)
    assertTrue(registry.release(outer).ok, "release is idempotent")
    assertEqual(2, registry.status().pendingClaims)
    assertTrue(registry.release(inner).ok)
    assertEqual(0, registry.status().pendingClaims, "release retains no owned entries")
    assertEqual(0, registry.status().activeTokens)
end

do
    local registry = ExactXpClaims.create()
    local token = {}
    local owner = {}
    local perk = {}
    assertTrue(registry.claim(token, owner, perk, 0).ok, "zero is a finite signed amount")
    local status = registry.status()
    assertEqual(3, fieldCount(status), "status has bounded fields")
    assertNil(status.token)
    assertNil(status.owner)
    assertNil(status.perk)
    assertNil(status.amount)
    assertNil(status.entries)
    registry.release(token)
    assertEqual(0, registry.status().pendingClaims)
end

return assertions
