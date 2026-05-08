local constants = require("plugins.evaluator.constants")
local state = require("plugins.evaluator.state")

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

local function row_for_body(body)
    return {
        ["Body"]          = body.name,
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

local function should_skip(body, settings)
    if not body.scanned then return true end
    if not settings then return false end
    if body.potential_max < settings.minimum_body_value then
        return true
    end
    return false
end

local function sorted_bodies(bodies)
    local list = {}
    for _, body in pairs(bodies) do table.insert(list, body) end
    table.sort(list, function(a, b)
        return (a.distance_ls or 0) < (b.distance_ls or 0)
    end)
    return list
end

function grid.rebuild(target_grid, settings)
    target_grid.rows = {}
    for _, body in ipairs(sorted_bodies(state.bodies_in_current_system())) do
        if not should_skip(body, settings) then
            table.insert(target_grid.rows, row_for_body(body))
        end
    end
end

return grid
