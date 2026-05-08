local species_values = require("plugins.bioinsights.species_values")

local state = {}

local data = {
    systems = {},
    current_system_address = nil,
}

local SPECIES_STATUS = {
    PENDING   = "pending",
    CONFIRMED = "confirmed",
    EXCLUDED  = "excluded",
}

state.SPECIES_STATUS = SPECIES_STATUS

local function build_initial_species_states(genus_label)
    local result = {}
    for _, species_label in ipairs(species_values.species_in_genus(genus_label)) do
        result[species_label] = SPECIES_STATUS.PENDING
    end
    return result
end

local function blank_genus_entry(genus_label)
    return {
        species_label    = nil,
        variant_label    = nil,
        sample_index     = 0,
        confirmed_value  = nil,
        species_states   = build_initial_species_states(genus_label),
        species_order    = species_values.species_in_genus(genus_label),
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
        body.genus_entries[genus_label] = blank_genus_entry(genus_label)
        table.insert(body.genus_order, genus_label)
    end
    return body.genus_entries[genus_label]
end

function state.confirm_species(body, genus_label, species_label, variant_label, sample_index)
    if not body or not genus_label or not species_label then return end
    local entry = state.ensure_genus(body, genus_label)
    entry.species_label   = species_label
    entry.variant_label   = variant_label or entry.variant_label
    entry.sample_index    = math.max(entry.sample_index, sample_index or 0)
    entry.confirmed_value = species_values.for_species(species_label)
        or entry.confirmed_value
    if not entry.species_states[species_label] then
        entry.species_states[species_label] = SPECIES_STATUS.PENDING
        table.insert(entry.species_order, species_label)
    end
    for sibling in pairs(entry.species_states) do
        if sibling == species_label then
            entry.species_states[sibling] = SPECIES_STATUS.CONFIRMED
        else
            entry.species_states[sibling] = SPECIES_STATUS.EXCLUDED
        end
    end
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
