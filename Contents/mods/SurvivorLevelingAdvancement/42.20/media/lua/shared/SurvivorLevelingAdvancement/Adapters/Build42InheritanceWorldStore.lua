local Build42InheritanceWorldStore = {}

local NAMESPACE = "SLA_InheritancePending_v1"

local function failure(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function empty(value)
    if not plain(value) then return false end
    for _ in pairs(value) do return false end
    return true
end

function Build42InheritanceWorldStore.create(dependencies)
    if not plain(dependencies)
        or type(rawget(dependencies, "getOrCreate")) ~= "function"
        or type(rawget(dependencies, "add")) ~= "function" then
        return failure("invalid_capabilities", "Global ModData capabilities are required")
    end
    local getOrCreate = rawget(dependencies, "getOrCreate")
    local add = rawget(dependencies, "add")
    local capabilities = {}

    function capabilities.readRoot()
        local called, value = pcall(getOrCreate, NAMESPACE)
        if not called or value == nil then error("global_mod_data_read_failed") end
        if empty(value) then return nil end
        return value
    end

    function capabilities.writeRoot(root)
        local called, accepted = pcall(add, NAMESPACE, root)
        return called and accepted ~= false
    end

    return { ok = true, capabilities = capabilities }
end

return Build42InheritanceWorldStore
