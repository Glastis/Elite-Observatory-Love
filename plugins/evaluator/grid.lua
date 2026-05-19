local constants = require("plugins.evaluator.constants")
local state = require("plugins.evaluator.state")
local hierarchy = require("observatory.plugin_helpers.grid_hierarchy")

local grid = {}

local function format_distance(distance_ls)
    if not distance_ls or distance_ls <= 0 then
        return constants.UNKNOWN_TEXT
    end
    return string.format(constants.DISTANCE_FORMAT, distance_ls)
end

local function format_gravity(gravity_ms2)
    if not gravity_ms2 or gravity_ms2 <= 0 then
        return constants.UNKNOWN_TEXT
    end
    return string.format(constants.GRAVITY_FORMAT,
        gravity_ms2 / constants.GRAVITY_DIVIDER)
end

local function format_value(value)
    if not value or value <= 0 then return constants.UNKNOWN_TEXT end
    if value >= constants.VALUE_MILLION then
        return string.format(constants.VALUE_MILLION_FORMAT,
            value / constants.VALUE_MILLION)
    end
    return string.format(constants.VALUE_THOUSAND_FORMAT,
        value / constants.VALUE_THOUSAND)
end

local function format_terraform(is_terraformable)
    if is_terraformable then return constants.TERRAFORM_LABEL_YES end
    return constants.TERRAFORM_LABEL_NO
end

local function format_map_flag(should_map)
    if should_map then return constants.MAP_LABEL_YES end
    return constants.MAP_LABEL_NO
end

local function format_volcanism(volcanism)
    if not volcanism or volcanism == "" then return constants.UNKNOWN_TEXT end
    return volcanism
end

local function display_name(body)
    if body and body.name and body.name ~= "" and body.name ~= "?" then
        return body.name
    end
    return constants.UNNAMED_BODY_PLACEHOLDER
end

local function row_for_body(body, indented_name)
    return {
        ["Body"]          = indented_name or display_name(body),
        ["Type"]          = body.body_type ~= "" and body.body_type or constants.UNKNOWN_TEXT,
        ["Distance (Ls)"] = format_distance(body.distance_ls),
        ["Gravity (g)"]   = format_gravity(body.gravity_ms2),
        ["Terraform"]     = format_terraform(body.terraformable),
        ["Value"]         = format_value(body.current_value),
        ["Max Value"]     = format_value(body.potential_max),
        ["Map"]           = format_map_flag(body.worth_mapping),
        ["Volcanism"]     = format_volcanism(body.volcanism),
    }
end

local function placeholder_row_for_id(body_id, indented_name)
    return {
        ["Body"]          = indented_name,
        ["Type"]          = constants.UNKNOWN_TEXT,
        ["Distance (Ls)"] = constants.UNKNOWN_TEXT,
        ["Gravity (g)"]   = constants.UNKNOWN_TEXT,
        ["Terraform"]     = constants.TERRAFORM_LABEL_NO,
        ["Value"]         = constants.UNKNOWN_TEXT,
        ["Max Value"]     = constants.UNKNOWN_TEXT,
        ["Map"]           = constants.MAP_LABEL_NO,
        ["Volcanism"]     = constants.UNKNOWN_TEXT,
    }
end

local function should_skip(body, settings)
    if not body or not body.scanned then return true end
    if not settings then return false end
    if body.potential_max < settings.minimum_body_value then
        return true
    end
    return false
end

local function sort_by_distance(list)
    table.sort(list, function(a, b)
        return (a.distance_ls or 0) < (b.distance_ls or 0)
    end)
end

local function sorted_bodies(bodies)
    local list = {}
    for _, body in pairs(bodies) do table.insert(list, body) end
    sort_by_distance(list)
    return list
end

local function rebuild_flat(target_grid, bodies, settings)
    for _, body in ipairs(sorted_bodies(bodies)) do
        if not should_skip(body, settings) then
            table.insert(target_grid.rows, row_for_body(body))
        end
    end
end

local function visible_seed_ids(bodies, settings)
    local seeds = {}
    for id, body in pairs(bodies) do
        if not should_skip(body, settings) then
            table.insert(seeds, id)
        end
    end
    return seeds
end

local function emit_hierarchical_row(target_grid, bodies, id, depth)
    local body = bodies[id]
    local name = body and display_name(body) or constants.UNNAMED_BODY_PLACEHOLDER
    local indented = hierarchy.indent_prefix(depth) .. name
    local row
    if body and body.scanned then
        row = row_for_body(body, indented)
    else
        row = placeholder_row_for_id(id, indented)
    end
    row._depth = depth
    row._node_id = "body_" .. tostring(id)
    row._raw = { Body = name }
    table.insert(target_grid.rows, row)
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
            emit_hierarchical_row(target_grid, bodies, id, depth)
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
