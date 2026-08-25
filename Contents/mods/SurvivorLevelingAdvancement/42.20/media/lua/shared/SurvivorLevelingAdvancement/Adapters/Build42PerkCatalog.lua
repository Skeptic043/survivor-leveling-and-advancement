local Catalog = {}

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function success(fields)
    fields.ok = true
    return fields
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isInteger(value)
    return isFiniteNumber(value) and value == math.floor(value)
end

local function isSafeId(value)
    return type(value) == "string" and value:match("^[%w%._:%-]+$") ~= nil
end

local function method(target, name, label)
    if target == nil then
        return nil, failure("missing-capability", label .. " is required")
    end
    local ok, value = pcall(function()
        return target[name]
    end)
    if not ok then
        return nil, failure("capability-error", label .. "." .. name .. " lookup failed")
    end
    if type(value) ~= "function" then
        return nil, failure("missing-capability", label .. "." .. name .. " is required")
    end
    return value, nil
end

local function call(target, fn, label, ...)
    local arguments = { ... }
    local ok, value = pcall(function()
        return fn(target, unpack(arguments))
    end)
    if not ok then
        return nil, failure("capability-error", label .. " failed")
    end
    return value, nil
end

local function validDescription(description)
    if type(description) ~= "table" or description.ok ~= true
        or not isSafeId(description.adapterId)
        or not isInteger(description.adapterVersion) or description.adapterVersion < 0
        or not isSafeId(description.curveFingerprint)
        or not isInteger(description.effectiveMaximum) or description.effectiveMaximum < 1
        or type(description.cumulativeThresholds) ~= "table"
        or type(description.perLevelRequirements) ~= "table" then
        return false
    end

    local previous = description.cumulativeThresholds[0]
    if not isFiniteNumber(previous) or previous ~= 0 then
        return false
    end
    for level = 1, description.effectiveMaximum do
        local threshold = description.cumulativeThresholds[level]
        local requirement = description.perLevelRequirements[level]
        if not isFiniteNumber(threshold) or threshold <= previous
            or not isFiniteNumber(requirement) or requirement <= 0
            or requirement ~= threshold - previous then
            return false
        end
        previous = threshold
    end
    return true
end

local function compatibleRecord(description)
    return {
        adapterId = description.adapterId,
        adapterVersion = description.adapterVersion,
        curveFingerprint = description.curveFingerprint,
        effectiveMaximum = description.effectiveMaximum,
    }
end

function Catalog.create(dependencies)
    if type(dependencies) ~= "table" then
        return failure("invalid-dependencies", "dependencies must be a table")
    end
    if dependencies.nonePerk == nil then
        return failure("missing-dependency", "nonePerk is required")
    end

    local size, sizeFailure = method(dependencies.perkRegistry, "size", "perkRegistry")
    if size == nil then
        return sizeFailure
    end
    local get, getFailure = method(dependencies.perkRegistry, "get", "perkRegistry")
    if get == nil then
        return getFailure
    end
    local build, buildFailure = method(dependencies.progressionAdapter, "build", "progressionAdapter")
    if build == nil then
        return buildFailure
    end
    local describe, describeFailure = method(dependencies.progressionAdapter, "describe", "progressionAdapter")
    if describe == nil then
        return describeFailure
    end
    local inspect, inspectFailure = method(dependencies.progressionAdapter, "inspect", "progressionAdapter")
    if inspect == nil then
        return inspectFailure
    end

    local snapshot = nil
    local loadOptions = { loadedPerks = {} }

    local function refresh()
        local registrySize, sizeCallFailure = call(dependencies.perkRegistry, size, "perkRegistry.size")
        if registrySize == nil then
            return sizeCallFailure
        end
        if not isInteger(registrySize) or registrySize < 0 then
            return failure("invalid-registry-size", "perkRegistry.size must return a nonnegative integer")
        end

        local temporary = {
            perks = {},
            byId = {},
            byObject = {},
            loadedPerks = {},
            acceptedCount = 0,
            skippedCount = 0,
        }
        for index = 0, registrySize - 1 do
            local perk, getCallFailure = call(dependencies.perkRegistry, get, "perkRegistry.get", index)
            if perk == nil then
                return getCallFailure or failure("invalid-registry-entry", "perkRegistry.get returned nil")
            end

            local getParent = method(perk, "getParent", "perk")
            local getId = method(perk, "getId", "perk")
            if getParent == nil or getId == nil then
                temporary.skippedCount = temporary.skippedCount + 1
            else
                local parent = call(perk, getParent, "perk.getParent")
                local perkId = call(perk, getId, "perk.getId")
                if parent == nil or not isSafeId(perkId) or parent == dependencies.nonePerk then
                    temporary.skippedCount = temporary.skippedCount + 1
                elseif temporary.byId[perkId] ~= nil or temporary.byObject[perk] ~= nil then
                    return failure("ambiguous-perk", "duplicate published perk ID or object identity")
                else
                    local built = call(dependencies.progressionAdapter, build, "progressionAdapter.build", perk)
                    if type(built) ~= "table" or built.ok ~= true or built.handle == nil then
                        temporary.skippedCount = temporary.skippedCount + 1
                    else
                        local description = call(dependencies.progressionAdapter, describe, "progressionAdapter.describe", built.handle)
                        if not validDescription(description) then
                            temporary.skippedCount = temporary.skippedCount + 1
                        else
                            local entry = { perk = perk, adapter = dependencies.progressionAdapter, handle = built.handle }
                            temporary.perks[#temporary.perks + 1] = entry
                            temporary.byId[perkId] = entry
                            temporary.byObject[perk] = perkId
                            temporary.loadedPerks[perkId] = compatibleRecord(description)
                            temporary.acceptedCount = temporary.acceptedCount + 1
                        end
                    end
                end
            end
        end

        snapshot = temporary
        loadOptions.loadedPerks = temporary.loadedPerks
        return success({ acceptedCount = temporary.acceptedCount, skippedCount = temporary.skippedCount })
    end

    local resolver = { loadOptions = loadOptions }
    function resolver.resolve(perkId)
        if snapshot == nil then
            return failure("not-initialized", "catalog has not been refreshed")
        end
        local entry = snapshot.byId[perkId]
        if entry == nil then
            return failure("unknown-perk", "perk ID is not published")
        end
        return success({ adapter = entry.adapter, handle = entry.handle })
    end

    local perkIdentity = {}
    function perkIdentity.resolve(perk)
        if snapshot == nil then
            return failure("not-initialized", "catalog has not been refreshed")
        end
        local perkId = snapshot.byObject[perk]
        if perkId == nil then
            return failure("unknown-perk", "perk object is not published")
        end
        return success({ perkId = perkId })
    end

    local positionReader = {}
    function positionReader.read(player, perkId)
        local resolved = resolver.resolve(perkId)
        if not resolved.ok then
            return resolved
        end
        local inspected, inspectionFailure = call(resolved.adapter, inspect, "progressionAdapter.inspect", resolved.handle, player)
        if inspected == nil then
            return inspectionFailure
        end
        if type(inspected) ~= "table" or inspected.ok ~= true
            or not isFiniteNumber(inspected.actualPosition) or inspected.actualPosition < 0 then
            return failure("invalid-position", "adapter inspection must return a finite nonnegative actualPosition")
        end
        return success({ position = inspected.actualPosition })
    end

    local catalog = { resolver = resolver, perkIdentity = perkIdentity, positionReader = positionReader }
    function catalog.refresh()
        return refresh()
    end
    function catalog.allPerks()
        if snapshot == nil then
            return failure("not-initialized", "catalog has not been refreshed")
        end
        local perks = {}
        for index = 1, #snapshot.perks do
            perks[index] = snapshot.perks[index].perk
        end
        return success({ perks = perks })
    end
    function catalog.perkFor(perkId)
        if snapshot == nil then
            return failure("not-initialized", "catalog has not been refreshed")
        end
        local entry = snapshot.byId[perkId]
        if entry == nil then
            return failure("unknown-perk", "perk ID is not published")
        end
        return success({ perk = entry.perk })
    end
    function catalog.status()
        if snapshot == nil then
            return success({ initialized = false, acceptedCount = 0, skippedCount = 0 })
        end
        return success({
            initialized = true,
            acceptedCount = snapshot.acceptedCount,
            skippedCount = snapshot.skippedCount,
        })
    end

    return success({ catalog = catalog })
end

return Catalog
