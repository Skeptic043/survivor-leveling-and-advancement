local Codec = {}

Codec.SCHEMA_VERSION = 1
Codec.WRITER_VERSION = 1

local ROOT_FIELDS = { schemaVersion = true, writerVersion = true, revision = true, survivor = true, perks = true, orphanedPerks = true }
local SURVIVOR_FIELDS = { level = true, xpIntoLevel = true, earned = true, spent = true }
local PERK_FIELDS = {
    adapterId = true, adapterVersion = true, capabilityEpoch = true, curveFingerprint = true,
    effectiveMaximum = true, naturalPosition = true, highWaterPosition = true,
    fractionalCarry = true, activeTargets = true, postMaxFullRateUsed = true, postMaxEpoch = true,
}
local TARGET_FIELDS = { targetId = true, targetLevel = true, targetPosition = true }

local function failure(code, detail, raw)
    return { ok = false, code = code, detail = detail, raw = raw }
end

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isNonNegativeInteger(value)
    return isFiniteNumber(value) and value >= 0 and value == math.floor(value)
end

local function isPositiveInteger(value)
    return isFiniteNumber(value) and value > 0 and value == math.floor(value)
end

local function isSafeId(value)
    return type(value) == "string" and value:match("^[%w%._:%-]+$") ~= nil
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function hasOnlyFields(value, allowed)
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then
            return false, key
        end
    end
    return true
end

local function cloneValue(value, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "string" then
        return value
    end
    if valueType == "number" then
        if not isFiniteNumber(value) then return nil, "non_finite" end
        return value
    end
    if valueType ~= "table" then return nil, "unsupported_type" end
    seen = seen or {}
    if seen[value] then return nil, "cycle" end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        local copiedKey, keyError = cloneValue(key, seen)
        if keyError then seen[value] = nil; return nil, keyError end
        local copiedChild, childError = cloneValue(child, seen)
        if childError then seen[value] = nil; return nil, childError end
        result[copiedKey] = copiedChild
    end
    seen[value] = nil
    return result
end

local function cloneChecked(raw)
    local copy, err = cloneValue(raw)
    if err then return nil, failure("invalid_raw", err) end
    return copy
end

local function validateTarget(target)
    if type(target) ~= "table" then return nil, failure("invalid_target", "not_table") end
    local fields, key = hasOnlyFields(target, TARGET_FIELDS)
    if not fields then return nil, failure("invalid_target", "unknown_field:" .. tostring(key)) end
    if not isSafeId(target.targetId) then return nil, failure("invalid_target", "targetId") end
    if not isPositiveInteger(target.targetLevel) then return nil, failure("invalid_target", "targetLevel") end
    if not (isFiniteNumber(target.targetPosition) and target.targetPosition >= 0) then return nil, failure("invalid_target", "targetPosition") end
    return { targetId = target.targetId, targetLevel = target.targetLevel, targetPosition = target.targetPosition }
end

local function validatePerk(perk)
    if type(perk) ~= "table" then return nil, failure("invalid_perk", "not_table") end
    local fields, key = hasOnlyFields(perk, PERK_FIELDS)
    if not fields then return nil, failure("invalid_perk", "unknown_field:" .. tostring(key)) end
    if not isSafeId(perk.adapterId) then return nil, failure("invalid_perk", "adapterId") end
    if not isNonNegativeInteger(perk.adapterVersion) then return nil, failure("invalid_perk", "adapterVersion") end
    if not isNonNegativeInteger(perk.capabilityEpoch) then return nil, failure("invalid_perk", "capabilityEpoch") end
    if not isSafeId(perk.curveFingerprint) then return nil, failure("invalid_perk", "curveFingerprint") end
    if not isPositiveInteger(perk.effectiveMaximum) then return nil, failure("invalid_perk", "effectiveMaximum") end
    if not (isFiniteNumber(perk.naturalPosition) and perk.naturalPosition >= 0) then return nil, failure("invalid_perk", "naturalPosition") end
    if not (isFiniteNumber(perk.highWaterPosition) and perk.highWaterPosition >= perk.naturalPosition) then return nil, failure("invalid_perk", "highWaterPosition") end
    if not (isFiniteNumber(perk.fractionalCarry) and perk.fractionalCarry >= 0 and perk.fractionalCarry < 1) then return nil, failure("invalid_perk", "fractionalCarry") end
    if not (isFiniteNumber(perk.postMaxFullRateUsed) and perk.postMaxFullRateUsed >= 0) then return nil, failure("invalid_perk", "postMaxFullRateUsed") end
    if not isNonNegativeInteger(perk.postMaxEpoch) then return nil, failure("invalid_perk", "postMaxEpoch") end
    if type(perk.activeTargets) ~= "table" then return nil, failure("invalid_perk", "activeTargets") end
    local targets, lastPosition = {}, -1
    for index = 1, #perk.activeTargets do
        local target, targetError = validateTarget(perk.activeTargets[index])
        if not target then return nil, targetError end
        if target.targetPosition <= lastPosition then return nil, failure("invalid_perk", "target_order") end
        lastPosition = target.targetPosition
        targets[index] = target
    end
    for key in pairs(perk.activeTargets) do
        if type(key) ~= "number" or key < 1 or key > #perk.activeTargets or key ~= math.floor(key) then
            return nil, failure("invalid_perk", "activeTargets_shape")
        end
    end
    return {
        adapterId = perk.adapterId, adapterVersion = perk.adapterVersion, capabilityEpoch = perk.capabilityEpoch,
        curveFingerprint = perk.curveFingerprint, effectiveMaximum = perk.effectiveMaximum,
        naturalPosition = perk.naturalPosition, highWaterPosition = perk.highWaterPosition,
        fractionalCarry = perk.fractionalCarry, activeTargets = targets,
        postMaxFullRateUsed = perk.postMaxFullRateUsed, postMaxEpoch = perk.postMaxEpoch,
    }
end

local function validateMap(map, label)
    if type(map) ~= "table" then return nil, failure("invalid_" .. label, "not_table") end
    local result = {}
    for id, record in pairs(map) do
        if not isSafeId(id) then return nil, failure("invalid_" .. label, "id") end
        local checked, err = validatePerk(record)
        if not checked then return nil, err end
        result[id] = checked
    end
    return result
end

local function validateV1(raw)
    if type(raw) ~= "table" then return nil, failure("invalid_state", "not_table") end
    local fields, key = hasOnlyFields(raw, ROOT_FIELDS)
    if not fields then return nil, failure("invalid_state", "unknown_field:" .. tostring(key)) end
    if raw.schemaVersion ~= Codec.SCHEMA_VERSION or raw.writerVersion ~= Codec.WRITER_VERSION then return nil, failure("invalid_state", "version") end
    if not isNonNegativeInteger(raw.revision) then return nil, failure("invalid_state", "revision") end
    if type(raw.survivor) ~= "table" then return nil, failure("invalid_survivor", "not_table") end
    local survivorFields, survivorKey = hasOnlyFields(raw.survivor, SURVIVOR_FIELDS)
    if not survivorFields then return nil, failure("invalid_survivor", "unknown_field:" .. tostring(survivorKey)) end
    local survivor = raw.survivor
    if not isNonNegativeInteger(survivor.level) or not (isFiniteNumber(survivor.xpIntoLevel) and survivor.xpIntoLevel >= 0) then return nil, failure("invalid_survivor", "level_or_xp") end
    if not isNonNegativeInteger(survivor.earned) or not isNonNegativeInteger(survivor.spent) or survivor.spent > survivor.earned then return nil, failure("invalid_survivor", "ap") end
    local perks, perkError = validateMap(raw.perks, "perks")
    if not perks then return nil, perkError end
    local orphaned, orphanError = validateMap(raw.orphanedPerks, "orphaned_perks")
    if not orphaned then return nil, orphanError end
    for id in pairs(perks) do
        if orphaned[id] then return nil, failure("invalid_state", "duplicate_perk:" .. id) end
    end
    return {
        schemaVersion = Codec.SCHEMA_VERSION, writerVersion = Codec.WRITER_VERSION, revision = raw.revision,
        survivor = { level = survivor.level, xpIntoLevel = survivor.xpIntoLevel, earned = survivor.earned, spent = survivor.spent },
        perks = perks, orphanedPerks = orphaned,
    }
end

local function freshState()
    return { schemaVersion = Codec.SCHEMA_VERSION, writerVersion = Codec.WRITER_VERSION, revision = 0,
        survivor = { level = 0, xpIntoLevel = 0, earned = 0, spent = 0 }, perks = {}, orphanedPerks = {} }
end

local function sameIdentity(record, spec)
    return record.adapterId == spec.adapterId and record.adapterVersion == spec.adapterVersion
        and record.capabilityEpoch == spec.capabilityEpoch and record.curveFingerprint == spec.curveFingerprint
        and record.effectiveMaximum == spec.effectiveMaximum
end

local function applyCompatibility(state, options)
    local loaded = options and options.loadedPerks
    if loaded == nil then return state end
    if type(loaded) ~= "table" then return nil, failure("invalid_options", "loadedPerks") end
    local migrated = {}
    local activeIds = sortedKeys(state.perks)
    for index = 1, #activeIds do
        local id = activeIds[index]
        local record = state.perks[id]
        local spec = loaded[id]
        if type(spec) ~= "table" then
            state.orphanedPerks[id] = record
            state.perks[id] = nil
        elseif sameIdentity(record, spec) then
            migrated[id] = record
        else
            local migration = options and options.perkMigrator
            if type(migration) ~= "function" then
                state.orphanedPerks[id] = record
                state.perks[id] = nil
            else
                local ok, changed = pcall(migration, id, cloneValue(record), cloneValue(spec))
                if not ok or changed == nil then return nil, failure("perk_migration_failed", id) end
                local checked, err = validatePerk(changed)
                if not checked then return nil, err end
                if not sameIdentity(checked, spec) then return nil, failure("perk_migration_failed", id) end
                migrated[id] = checked
            end
        end
    end
    local orphanedIds = sortedKeys(state.orphanedPerks)
    for index = 1, #orphanedIds do
        local id = orphanedIds[index]
        local record = state.orphanedPerks[id]
        local spec = loaded[id]
        if type(spec) == "table" and sameIdentity(record, spec) then
            local migration = options and options.perkMigrator
            if type(migration) == "function" then
                local ok, restored = pcall(migration, id, cloneValue(record), cloneValue(spec))
                if not ok or restored == nil then return nil, failure("perk_migration_failed", id) end
                local checked = validatePerk(restored)
                if not checked or not sameIdentity(checked, spec) then return nil, failure("perk_migration_failed", id) end
                state.orphanedPerks[id] = nil
                migrated[id] = checked
            end
        end
    end
    local migratedIds = sortedKeys(migrated)
    for index = 1, #migratedIds do
        local id = migratedIds[index]
        state.perks[id] = migrated[id]
    end
    return state
end

local function canonical(state)
    local function number(value)
        if value == 0 then return "0" end
        return string.format("%.17g", value)
    end
    local function target(value) return "{" .. value.targetId .. ":" .. value.targetLevel .. ":" .. number(value.targetPosition) .. "}" end
    local function perk(value)
        local parts = { value.adapterId, value.adapterVersion, value.capabilityEpoch, value.curveFingerprint, value.effectiveMaximum,
            number(value.naturalPosition), number(value.highWaterPosition), number(value.fractionalCarry), number(value.postMaxFullRateUsed), value.postMaxEpoch }
        for index = 1, #value.activeTargets do parts[#parts + 1] = target(value.activeTargets[index]) end
        return table.concat(parts, "|")
    end
    local function map(value)
        local parts, keys = {}, sortedKeys(value)
        for index = 1, #keys do parts[index] = keys[index] .. "=" .. perk(value[keys[index]]) end
        return table.concat(parts, ";")
    end
    return table.concat({ state.schemaVersion, state.writerVersion, state.revision, state.survivor.level, number(state.survivor.xpIntoLevel), state.survivor.earned, state.survivor.spent, map(state.perks), map(state.orphanedPerks) }, "#")
end

function Codec.decode(raw, options)
    if raw == nil then return { ok = true, state = freshState() } end
    if type(raw) ~= "table" then return failure("invalid_state", "not_table", raw) end
    local cloned, cloneError = cloneChecked(raw)
    if not cloned then return cloneError end
    local schema = cloned.schemaVersion
    local writer = cloned.writerVersion
    if type(schema) ~= "number" or type(writer) ~= "number" then return failure("unversioned_state", "missing_version", raw) end
    if schema > Codec.SCHEMA_VERSION then return failure("newer_schema", schema, raw) end
    if writer > Codec.WRITER_VERSION then return failure("newer_writer", writer, raw) end
    while schema < Codec.SCHEMA_VERSION do
        local migrations = options and options.schemaMigrations
        local migration = migrations and migrations[schema]
        if type(migration) ~= "function" then return failure("missing_schema_migration", schema, raw) end
        local ok, nextRaw = pcall(migration, cloned)
        if not ok or type(nextRaw) ~= "table" then return failure("schema_migration_failed", schema, raw) end
        cloned, cloneError = cloneChecked(nextRaw)
        if not cloned then return cloneError end
        if cloned.schemaVersion ~= schema + 1 then return failure("schema_migration_not_consecutive", schema, raw) end
        schema = cloned.schemaVersion
    end
    local state, err = validateV1(cloned)
    if not state then return err end
    local compatible, compatibilityError = applyCompatibility(state, options)
    if not compatible then return compatibilityError end
    return { ok = true, state = compatible }
end

function Codec.encode(state)
    local checked, err = validateV1(state)
    if not checked then return err end
    return { ok = true, state = checked, canonical = canonical(checked) }
end

function Codec.fresh()
    return freshState()
end

return Codec
