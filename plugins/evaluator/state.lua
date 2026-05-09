local state = {}

local data = {
    systems = {},
    current_system_address = nil,
}

local function blank_body()
    return {
        name                  = "?",
        body_id               = nil,
        parent_body_id        = nil,
        body_type             = "",
        is_star               = false,
        is_landable           = false,
        terraformable         = false,
        distance_ls           = 0,
        gravity_ms2           = 0,
        mass_em               = 0,
        radius_m              = 0,
        volcanism             = "",
        atmosphere            = "",
        was_discovered        = false,
        was_mapped            = false,
        was_footfalled        = false,
        current_value         = 0,
        potential_max         = 0,
        worth_mapping         = false,
        scanned               = false,
        notified_high_value   = false,
    }
end

local function blank_system(name)
    return { name = name or "?", bodies = {} }
end

function state.set_current_system(system_address, system_name)
    if not system_address then return end
    data.current_system_address = system_address
    data.systems[system_address] = data.systems[system_address] or blank_system(system_name)
    if system_name then data.systems[system_address].name = system_name end
end

function state.current_system_address()
    return data.current_system_address
end

function state.current_system()
    if not data.current_system_address then return nil end
    return data.systems[data.current_system_address]
end

function state.ensure_body(system_address, body_id, body_name)
    if not system_address or not body_id then return nil end
    local system = data.systems[system_address]
    if not system then
        data.systems[system_address] = blank_system(nil)
        system = data.systems[system_address]
    end
    if not system.bodies[body_id] then
        system.bodies[body_id] = blank_body()
        system.bodies[body_id].body_id = body_id
    end
    if body_name then system.bodies[body_id].name = body_name end
    return system.bodies[body_id]
end

function state.bodies_in_current_system()
    local system = state.current_system()
    if not system then return {} end
    return system.bodies
end

function state.systems_sorted()
    local list = {}
    for address, system in pairs(data.systems) do
        table.insert(list, { address = address, system = system })
    end
    table.sort(list, function(a, b)
        return (a.system.name or "") < (b.system.name or "")
    end)
    return list
end

function state.reset()
    data.systems = {}
    data.current_system_address = nil
end

return state
