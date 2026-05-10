local helpers = {}

local function blank_system(name)
    return { name = name or "?", bodies = {} }
end

local function ensure_system_in_store(store, system_address, system_name)
    local existing = store.systems[system_address]
    if existing then
        if system_name then existing.name = system_name end
        return existing
    end
    local created = blank_system(system_name)
    store.systems[system_address] = created
    return created
end

local function attach_body_to_system(system, body_id, body_factory, body_name, system_address)
    local body = system.bodies[body_id]
    if not body then
        body = body_factory(body_name)
        body.body_id = body_id
        body.system_address = system_address
        system.bodies[body_id] = body
    end
    if body_name then body.name = body_name end
    return body
end

local function build_systems_sorted(store)
    local list = {}
    for address, system in pairs(store.systems) do
        table.insert(list, { address = address, system = system })
    end
    table.sort(list, function(a, b)
        return (a.system.name or "") < (b.system.name or "")
    end)
    return list
end

function helpers.create_system_store(body_factory)
    local store = {
        systems = {},
        current_system_address = nil,
    }

    function store.set_current_system(system_address, system_name)
        if not system_address then return end
        store.current_system_address = system_address
        ensure_system_in_store(store, system_address, system_name)
    end

    function store.current_system()
        if not store.current_system_address then return nil end
        return store.systems[store.current_system_address]
    end

    function store.ensure_body(system_address, body_id, body_name)
        if not system_address or not body_id then return nil end
        local system = ensure_system_in_store(store, system_address, nil)
        return attach_body_to_system(system, body_id, body_factory, body_name, system_address)
    end

    function store.bodies_in_current_system()
        local system = store.current_system()
        if not system then return {} end
        return system.bodies
    end

    function store.systems_sorted()
        return build_systems_sorted(store)
    end

    function store.reset()
        store.systems = {}
        store.current_system_address = nil
    end

    return store
end

return helpers
