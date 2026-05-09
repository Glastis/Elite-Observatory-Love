local species_values = require("plugins.bioinsights.species_values")
local species_codex = require("plugins.bioinsights.codex")

local state = {}

local data = {
    systems = {},
    current_system_address = nil,
}

local user_context = {
    near_nebula   = false,
    near_guardian = false,
}

function state.set_user_context(ctx)
    ctx = ctx or {}
    user_context = {
        near_nebula   = ctx.near_nebula and true or false,
        near_guardian = ctx.near_guardian and true or false,
    }
end

function state.user_context()
    return user_context
end

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
        dss_confirmed    = false,
        species_states   = build_initial_species_states(genus_label),
        species_order    = species_values.species_in_genus(genus_label),
    }
end

local function blank_body(body_name)
    return {
        name                = body_name or "?",
        body_type           = "",
        atmosphere_type     = "",
        atmosphere          = "",
        volcanism           = "",
        parent_star_type    = "",
        distance_ls         = 0,
        gravity_ms2         = 0,
        temperature_k       = 0,
        pressure_pa         = 0,
        parent_body_id      = nil,
        biological_count    = 0,
        geological_count    = 0,
        materials           = {},
        genus_entries       = {},
        genus_order         = {},
        system_address      = nil,
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
    system.bodies[body_id].system_address = system_address
    return system.bodies[body_id]
end

local function system_for_body(body)
    if not body or not body.system_address then return nil end
    return data.systems[body.system_address]
end

local function build_eval_context(body)
    return {
        near_nebula   = user_context.near_nebula,
        near_guardian = user_context.near_guardian,
        system        = system_for_body(body),
    }
end

local function apply_codex_constraints(body, entry)
    if entry.species_label then return end
    local eval_context = build_eval_context(body)
    for species_label, status in pairs(entry.species_states) do
        if status ~= SPECIES_STATUS.CONFIRMED then
            local match = species_codex.species_matches_body(species_label, body, eval_context)
            if match == false then
                entry.species_states[species_label] = SPECIES_STATUS.EXCLUDED
            else
                entry.species_states[species_label] = SPECIES_STATUS.PENDING
            end
        end
    end
end

function state.ensure_genus(body, genus_label)
    if not body or not genus_label then return nil end
    if not body.genus_entries[genus_label] then
        body.genus_entries[genus_label] = blank_genus_entry(genus_label)
        table.insert(body.genus_order, genus_label)
        apply_codex_constraints(body, body.genus_entries[genus_label])
    end
    return body.genus_entries[genus_label]
end

function state.mark_genus_dss_confirmed(body, genus_label)
    local entry = state.ensure_genus(body, genus_label)
    if entry then entry.dss_confirmed = true end
    return entry
end

local function genus_is_authoritative(entry)
    if not entry then return false end
    return entry.dss_confirmed or entry.species_label ~= nil
end

local function remove_genus(body, genus_label)
    body.genus_entries[genus_label] = nil
    for index, label in ipairs(body.genus_order) do
        if label == genus_label then
            table.remove(body.genus_order, index)
            return
        end
    end
end

function state.prune_candidate_genuses(body)
    if not body then return end
    local stale = {}
    for genus_label, entry in pairs(body.genus_entries) do
        if not genus_is_authoritative(entry) then
            table.insert(stale, genus_label)
        end
    end
    for _, label in ipairs(stale) do remove_genus(body, label) end
end

function state.refresh_genus_constraints(body)
    if not body then return end
    for _, entry in pairs(body.genus_entries) do
        apply_codex_constraints(body, entry)
    end
end

local function genus_has_possible_species(body, genus_label)
    local eval_context = build_eval_context(body)
    for _, species_label in ipairs(species_values.species_in_genus(genus_label)) do
        if species_codex.species_matches_body(species_label, body, eval_context) ~= false then
            return true
        end
    end
    return false
end

local function body_has_dss_data(body)
    for _, entry in pairs(body.genus_entries) do
        if entry.dss_confirmed then return true end
    end
    return false
end

function state.populate_candidate_genuses(body)
    if not body then return end
    if body.biological_count <= 0 then return end
    if not body.body_type or body.body_type == "" then return end
    if body_has_dss_data(body) then return end
    for _, genus_label in ipairs(species_codex.all_genuses()) do
        if not body.genus_entries[genus_label]
            and genus_has_possible_species(body, genus_label) then
            state.ensure_genus(body, genus_label)
        end
    end
end

local function genus_can_be_pruned_after_refresh(body, genus_label, entry)
    if entry.species_label or entry.dss_confirmed then return false end
    return not genus_has_possible_species(body, genus_label)
end

local function drop_now_impossible_genuses(body)
    local stale = {}
    for genus_label, entry in pairs(body.genus_entries) do
        if genus_can_be_pruned_after_refresh(body, genus_label, entry) then
            table.insert(stale, genus_label)
        end
    end
    for _, label in ipairs(stale) do remove_genus(body, label) end
end

function state.refresh_all_constraints()
    for _, system in pairs(data.systems) do
        for _, body in pairs(system.bodies) do
            for _, entry in pairs(body.genus_entries) do
                apply_codex_constraints(body, entry)
            end
            drop_now_impossible_genuses(body)
            state.populate_candidate_genuses(body)
        end
    end
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
