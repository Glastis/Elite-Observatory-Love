local state = {}

local data = {
    systems = {},
    current_system_address = nil,
}

local function blank_genus_entry()
    return {
        species_label   = nil,
        variant_label   = nil,
        sample_index    = 0,
        confirmed_value = nil,
    }
end

local function blank_body(body_name)
    return {
        name                = body_name or "?",
        body_type           = "",
        distance_ls         = 0,
        parent_body_id      = nil,
        biological_count    = 0,
        geological_count    = 0,
        genus_entries       = {},
        genus_order         = {},
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
    system.bodies[body_id] = system.bodies[body_id] or blank_body(body_name)
    if body_name then system.bodies[body_id].name = body_name end
    return system.bodies[body_id]
end

function state.ensure_genus(body, genus_label)
    if not body or not genus_label then return nil end
    if not body.genus_entries[genus_label] then
        body.genus_entries[genus_label] = blank_genus_entry()
        table.insert(body.genus_order, genus_label)
    end
    return body.genus_entries[genus_label]
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
