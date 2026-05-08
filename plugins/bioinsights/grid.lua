local constants = require("plugins.bioinsights.constants")
local state = require("plugins.bioinsights.state")
local species_values = require("plugins.bioinsights.species_values")
local hierarchy = require("observatory.grid_hierarchy")

local grid = {}

local function format_number(value)
    if not value or value <= 0 then return constants.UNKNOWN_TEXT end
    if value >= constants.VALUE_MILLION then
        return string.format(constants.VALUE_MILLION_FORMAT,
            value / constants.VALUE_MILLION)
    end
    return string.format(constants.VALUE_THOUSAND_FORMAT,
        value / constants.VALUE_THOUSAND)
end

local function format_distance(distance_ls)
    if not distance_ls or distance_ls <= 0 then
        return constants.UNKNOWN_TEXT
    end
    return string.format(constants.DISTANCE_FORMAT, distance_ls)
end

local function display_name(body)
    if body and body.name and body.name ~= "" and body.name ~= "?" then
        return body.name
    end
    return constants.UNNAMED_BODY_PLACEHOLDER
end

local function exact_value_for_entry(genus_entry)
    if genus_entry.confirmed_value and genus_entry.confirmed_value > 0 then
        return genus_entry.confirmed_value
    end
    if not genus_entry.species_label then return nil end
    local exact = species_values.for_species(genus_entry.species_label)
    if exact and exact > 0 then return exact end
    return nil
end

local function format_value_for_genus(genus_entry, genus_label)
    local exact = exact_value_for_entry(genus_entry)
    if exact then
        return string.format(constants.VALUE_FORMAT, format_number(exact))
    end
    local range = species_values.for_genus(genus_label)
    if not range then return constants.UNKNOWN_TEXT end
    if range.min == range.max then
        return string.format(constants.VALUE_FORMAT, format_number(range.min))
    end
    return string.format(constants.VALUE_RANGE_FORMAT,
        format_number(range.min), format_number(range.max))
end

local function row_for_genus(body, genus_label, body_label)
    local entry = body.genus_entries[genus_label]
    return {
        ["Body"]     = body_label,
        ["Type"]     = body.body_type ~= "" and body.body_type or constants.UNKNOWN_TEXT,
        ["Genus"]    = genus_label,
        ["Species"]  = entry.species_label or constants.UNKNOWN_TEXT,
        ["Variant"]  = entry.variant_label or constants.UNKNOWN_TEXT,
        ["Samples"]  = constants.SAMPLE_INDEX_TO_LABEL[entry.sample_index] or "?",
        ["Value"]    = format_value_for_genus(entry, genus_label),
        ["Distance"] = format_distance(body.distance_ls),
    }
end

local function row_for_pending_body(body, body_label)
    return {
        ["Body"]     = body_label,
        ["Type"]     = body.body_type ~= "" and body.body_type or constants.UNKNOWN_TEXT,
        ["Genus"]    = string.format("%s × %d",
            constants.PENDING_BIO_PLACEHOLDER, body.biological_count),
        ["Species"]  = constants.UNKNOWN_TEXT,
        ["Variant"]  = constants.UNKNOWN_TEXT,
        ["Samples"]  = constants.SAMPLE_INDEX_TO_LABEL[0],
        ["Value"]    = constants.UNKNOWN_TEXT,
        ["Distance"] = format_distance(body.distance_ls),
    }
end

local function placeholder_ancestor_row(body, body_label)
    return {
        ["Body"]     = body_label,
        ["Type"]     = (body and body.body_type ~= "" and body.body_type)
            or constants.UNKNOWN_TEXT,
        ["Genus"]    = constants.UNKNOWN_TEXT,
        ["Species"]  = constants.UNKNOWN_TEXT,
        ["Variant"]  = constants.UNKNOWN_TEXT,
        ["Samples"]  = constants.SAMPLE_INDEX_TO_LABEL[0],
        ["Value"]    = constants.UNKNOWN_TEXT,
        ["Distance"] = format_distance(body and body.distance_ls or 0),
    }
end

local function genus_potential_max(genus_entry, genus_label)
    local exact = exact_value_for_entry(genus_entry)
    if exact then return exact end
    local range = species_values.for_genus(genus_label)
    if range then return range.max end
    return 0
end

local function body_potential_max(body)
    local best = 0
    for _, genus_label in ipairs(body.genus_order) do
        local value = genus_potential_max(body.genus_entries[genus_label], genus_label)
        if value > best then best = value end
    end
    return best
end

local function should_skip_body(body, settings)
    if not body then return true end
    if body.biological_count <= 0 and #body.genus_order == 0 then
        return true
    end
    if not settings or not settings.only_show_high_value then return false end
    if #body.genus_order == 0 then return false end
    return body_potential_max(body) < (settings.minimum_high_value or 0)
end

local function bodies_with_biology(bodies)
    local list = {}
    for _, body in pairs(bodies) do
        if body.biological_count > 0 or #body.genus_order > 0 then
            table.insert(list, body)
        end
    end
    table.sort(list, function(a, b)
        return (a.distance_ls or 0) < (b.distance_ls or 0)
    end)
    return list
end

local function rows_for_body(body, body_label)
    if #body.genus_order == 0 then
        return { row_for_pending_body(body, body_label) }
    end
    local rows = {}
    for i, genus_label in ipairs(body.genus_order) do
        local label = (i == 1) and body_label or ""
        table.insert(rows, row_for_genus(body, genus_label, label))
    end
    return rows
end

local function rebuild_flat(target_grid, bodies, settings)
    for _, body in ipairs(bodies_with_biology(bodies)) do
        if not should_skip_body(body, settings) then
            for _, row in ipairs(rows_for_body(body, body.name)) do
                table.insert(target_grid.rows, row)
            end
        end
    end
end

local function visible_seed_ids(bodies, settings)
    local seeds = {}
    for id, body in pairs(bodies) do
        if not should_skip_body(body, settings) then
            table.insert(seeds, id)
        end
    end
    return seeds
end

local function annotate_hierarchy(row, depth, node_id, raw_body_name)
    row._depth = depth
    row._node_id = node_id
    row._raw = { Body = raw_body_name }
    return row
end

local function emit_hierarchical_rows(target_grid, bodies, id, depth, settings)
    local body = bodies[id]
    local raw_name = display_name(body)
    local indented_name = hierarchy.indent_prefix(depth) .. raw_name
    local node_id = "body_" .. tostring(id)
    if not body or should_skip_body(body, settings) then
        table.insert(target_grid.rows,
            annotate_hierarchy(placeholder_ancestor_row(body, indented_name),
                depth, node_id, raw_name))
        return
    end
    for _, row in ipairs(rows_for_body(body, indented_name)) do
        table.insert(target_grid.rows,
            annotate_hierarchy(row, depth, node_id, raw_name))
    end
end

local function rebuild_hierarchical(target_grid, bodies, settings)
    hierarchy.walk({
        seed_ids = visible_seed_ids(bodies, settings),
        parent_for = function(id)
            local body = bodies[id]
            return body and body.parent_body_id
        end,
        sort_ids = function(ids)
            table.sort(ids, function(a, b)
                local da = bodies[a] and bodies[a].distance_ls or 0
                local db = bodies[b] and bodies[b].distance_ls or 0
                return da < db
            end)
        end,
        visit = function(id, depth)
            emit_hierarchical_rows(target_grid, bodies, id, depth, settings)
        end,
    })
end

function grid.rebuild(target_grid, settings, view_options)
    target_grid.rows = {}
    local bodies = state.bodies_in_current_system()
    if view_options and view_options.group_by_body then
        rebuild_hierarchical(target_grid, bodies, settings)
        return
    end
    rebuild_flat(target_grid, bodies, settings)
end

return grid
