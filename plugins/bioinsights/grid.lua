local constants = require("plugins.bioinsights.constants")
local state = require("plugins.bioinsights.state")
local species_values = require("plugins.bioinsights.species_values")
local variants = require("plugins.bioinsights.variants")
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

local function format_value_for_species(species_label)
    local exact = species_values.for_species(species_label)
    if exact and exact > 0 then
        return string.format(constants.VALUE_FORMAT, format_number(exact))
    end
    return constants.UNKNOWN_TEXT
end

local function genus_value_bounds(body, genus_label)
    local entry = body.genus_entries[genus_label]
    if not entry then
        local range = species_values.for_genus(genus_label)
        if range then return range.min, range.max end
        return 0, 0
    end
    local lo, hi
    for species_label, status in pairs(entry.species_states) do
        if status ~= "excluded" then
            local v = species_values.for_species(species_label) or 0
            if status == "confirmed" then return v, v end
            if not lo or v < lo then lo = v end
            if not hi or v > hi then hi = v end
        end
    end
    if not lo then return 0, 0 end
    return lo, hi
end

local function body_value_bounds(body)
    local total_lo, total_hi = 0, 0
    if not body.genus_order or #body.genus_order == 0 then
        return 0, 0
    end
    for _, genus_label in ipairs(body.genus_order) do
        local lo, hi = genus_value_bounds(body, genus_label)
        total_lo = total_lo + lo
        total_hi = total_hi + hi
    end
    return total_lo, total_hi
end

local function format_body_value(body)
    local lo, hi = body_value_bounds(body)
    if hi <= 0 then return constants.UNKNOWN_TEXT end
    if lo == hi then
        return string.format(constants.VALUE_FORMAT, format_number(lo))
    end
    return string.format(constants.VALUE_RANGE_FORMAT,
        format_number(lo), format_number(hi))
end

local function format_star(body)
    if body.parent_star_type and body.parent_star_type ~= "" then
        return body.parent_star_type
    end
    return constants.UNKNOWN_TEXT
end

local function format_bios(body)
    if body.biological_count and body.biological_count > 0 then
        return tostring(body.biological_count)
    end
    return constants.UNKNOWN_TEXT
end

local function decorate_with_body_data(row, body)
    row["Star"]        = format_star(body)
    row["Bios"]        = format_bios(body)
    row["Body Value"]  = format_body_value(body)
    return row
end

local function variant_for_pending(species_label, body)
    return variants.predict_for(species_label, body) or constants.UNKNOWN_TEXT
end

local function variant_for_row(body, entry, species_label, status)
    if status == "confirmed" then
        return entry.variant_label or constants.UNKNOWN_TEXT
    end
    return variant_for_pending(species_label, body)
end

local function display_status(entry, status)
    if status == "pending" and entry and entry.dss_confirmed then
        return constants.STATUS_LABEL.predicted
    end
    return constants.STATUS_LABEL[status] or status
end

local function species_row_for_status(body, genus_label, species_label, status, body_label)
    local entry = body.genus_entries[genus_label]
    local is_confirmed = (status == "confirmed")
    return {
        ["Body"]     = body_label,
        ["Type"]     = body.body_type ~= "" and body.body_type or constants.UNKNOWN_TEXT,
        ["Genus"]    = genus_label,
        ["Species"]  = species_label,
        ["Status"]   = display_status(entry, status),
        ["Variant"]  = variant_for_row(body, entry, species_label, status),
        ["Samples"]  = is_confirmed and (constants.SAMPLE_INDEX_TO_LABEL[entry.sample_index] or "?") or constants.SAMPLE_INDEX_TO_LABEL[0],
        ["Value"]    = format_value_for_species(species_label),
        ["Distance"] = format_distance(body.distance_ls),
    }
end

local function row_for_genus(body, genus_label, body_label)
    local entry = body.genus_entries[genus_label]
    local variant_label = entry.variant_label
    if not variant_label and entry.species_label then
        variant_label = variants.predict_for(entry.species_label, body)
    end
    return {
        ["Body"]     = body_label,
        ["Type"]     = body.body_type ~= "" and body.body_type or constants.UNKNOWN_TEXT,
        ["Genus"]    = genus_label,
        ["Species"]  = entry.species_label or constants.UNKNOWN_TEXT,
        ["Status"]   = entry.species_label and constants.STATUS_LABEL.confirmed or constants.STATUS_LABEL.pending,
        ["Variant"]  = variant_label or constants.UNKNOWN_TEXT,
        ["Samples"]  = constants.SAMPLE_INDEX_TO_LABEL[entry.sample_index] or "?",
        ["Value"]    = format_value_for_genus(entry, genus_label),
        ["Distance"] = format_distance(body.distance_ls),
    }
end

local function row_for_pending_body(body, body_label)
    return {
        ["Body"]     = body_label,
        ["Type"]     = body.body_type ~= "" and body.body_type or constants.UNKNOWN_TEXT,
        ["Genus"]    = string.format("%s x %d",
            constants.PENDING_BIO_PLACEHOLDER, body.biological_count),
        ["Species"]  = constants.UNKNOWN_TEXT,
        ["Status"]   = constants.STATUS_LABEL.pending,
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
        ["Status"]   = constants.UNKNOWN_TEXT,
        ["Variant"]  = constants.UNKNOWN_TEXT,
        ["Samples"]  = constants.SAMPLE_INDEX_TO_LABEL[0],
        ["Value"]    = constants.UNKNOWN_TEXT,
        ["Distance"] = format_distance(body and body.distance_ls or 0),
    }
end

local function body_header_row(body, body_label)
    return {
        ["Body"]     = body_label,
        ["Type"]     = body.body_type ~= "" and body.body_type or constants.UNKNOWN_TEXT,
        ["Genus"]    = constants.UNKNOWN_TEXT,
        ["Species"]  = constants.UNKNOWN_TEXT,
        ["Status"]   = constants.UNKNOWN_TEXT,
        ["Variant"]  = constants.UNKNOWN_TEXT,
        ["Samples"]  = constants.SAMPLE_INDEX_TO_LABEL[0],
        ["Value"]    = constants.UNKNOWN_TEXT,
        ["Distance"] = format_distance(body.distance_ls),
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

local function should_hide_pending_species(status, species_label, body)
    if status ~= "pending" then return false end
    return variants.predict_for(species_label, body) == nil
end

local function rows_for_genus_species(body, genus_label, body_label)
    local entry = body.genus_entries[genus_label]
    if not entry or #entry.species_order == 0 then
        return { row_for_genus(body, genus_label, body_label) }
    end
    local rows = {}
    local emitted_first = false
    for _, species_label in ipairs(entry.species_order) do
        local status = entry.species_states[species_label] or "pending"
        if status ~= "excluded"
            and not should_hide_pending_species(status, species_label, body) then
            local label = (not emitted_first) and body_label or ""
            table.insert(rows, species_row_for_status(body, genus_label, species_label, status, label))
            emitted_first = true
        end
    end
    return rows
end

local function rows_for_body(body, body_label)
    if #body.genus_order == 0 then
        return { row_for_pending_body(body, body_label) }
    end
    local rows = {}
    local emitted_label = false
    for _, genus_label in ipairs(body.genus_order) do
        local label = (not emitted_label) and body_label or ""
        for _, row in ipairs(rows_for_genus_species(body, genus_label, label)) do
            table.insert(rows, row)
            label = ""
            emitted_label = true
        end
    end
    return rows
end

local function rebuild_flat(target_grid, bodies, settings)
    for _, body in ipairs(bodies_with_biology(bodies)) do
        if not should_skip_body(body, settings) then
            for _, row in ipairs(rows_for_body(body, body.name)) do
                table.insert(target_grid.rows, decorate_with_body_data(row, body))
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

local function emit_genus_children(target_grid, body, body_node_id, depth)
    local sub_indent = hierarchy.indent_prefix(depth)
    if #body.genus_order == 0 then
        table.insert(target_grid.rows,
            annotate_hierarchy(decorate_with_body_data(row_for_pending_body(body, sub_indent), body),
                depth, body_node_id .. "_pending", ""))
        return
    end
    for _, genus_label in ipairs(body.genus_order) do
        for _, row in ipairs(rows_for_genus_species(body, genus_label, sub_indent)) do
            table.insert(target_grid.rows,
                annotate_hierarchy(decorate_with_body_data(row, body), depth,
                    body_node_id .. "_g_" .. genus_label .. "_" .. (row["Species"] or "?"), ""))
        end
    end
end

local function emit_hierarchical_rows(target_grid, bodies, id, depth, settings)
    local body = bodies[id]
    local raw_name = display_name(body)
    local indented_name = hierarchy.indent_prefix(depth) .. raw_name
    local body_node_id = "body_" .. tostring(id)
    if not body or should_skip_body(body, settings) then
        local placeholder = placeholder_ancestor_row(body, indented_name)
        if body then placeholder = decorate_with_body_data(placeholder, body) end
        table.insert(target_grid.rows,
            annotate_hierarchy(placeholder, depth, body_node_id, raw_name))
        return
    end
    table.insert(target_grid.rows,
        annotate_hierarchy(decorate_with_body_data(body_header_row(body, indented_name), body),
            depth, body_node_id, raw_name))
    emit_genus_children(target_grid, body, body_node_id, depth + 1)
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

local function rebuild_for_view(target_grid, bodies, settings, view_options)
    if view_options and view_options.group_by_body then
        rebuild_hierarchical(target_grid, bodies, settings)
        return
    end
    rebuild_flat(target_grid, bodies, settings)
end

function grid.rebuild(target_grid, settings, view_options)
    target_grid.rows = {}
    for _, entry in ipairs(state.systems_sorted()) do
        rebuild_for_view(target_grid, entry.system.bodies, settings, view_options)
    end
end

return grid
