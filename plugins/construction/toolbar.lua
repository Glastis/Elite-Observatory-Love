local ui    = require("observatory.ui")
local theme = require("observatory.ui.theme")

local toolbar = {}

local FIELD_W         = 104
local FIELD_GAP       = 8
local FIELD_PAD_X     = 8
local FIELD_PAD_Y     = 4
local FIELD_FONT      = { family = "mono", size = 11 }
local NUMERIC_PATTERN = "^%d*%.?%d*$"
local STRIP_PATTERN   = "[^%d%.]"

local SHIP_PARAM_FIELDS = {
    { key = "cargo_capacity", id = "construction_ship_cargo",
      placeholder = "Cargo t" },
    { key = "jump_loaded",    id = "construction_ship_jump_l",
      placeholder = "Jump laden" },
    { key = "jump_unloaded",  id = "construction_ship_jump_u",
      placeholder = "Jump empty" },
}

local function ensure_field_state(view_state, plugin, definition)
    view_state.ship_param_fields = view_state.ship_param_fields or {}
    local field = view_state.ship_param_fields[definition.key]
    if not field then
        field = { id = definition.id }
        ui.text_field.set_value(field, plugin.ship_params[definition.key] or "")
        view_state.ship_param_fields[definition.key] = field
    end
    return field
end

local function commit_field(plugin, field, definition, value)
    if value:match(NUMERIC_PATTERN) then
        plugin:set_ship_param(definition.key, value)
    else
        ui.text_field.set_value(field, plugin.ship_params[definition.key] or "")
    end
end

local function field_width_for(available_w)
    local count = #SHIP_PARAM_FIELDS
    local computed = math.floor((available_w - (count - 1) * FIELD_GAP) / count)
    return math.min(FIELD_W, math.max(0, computed))
end

local function draw_field(view_state, plugin, definition, x, y, w, h)
    local field = ensure_field_state(view_state, plugin, definition)
    local buffer = ui.text_field.draw(field, nil, x, y, w, {
        font        = theme.font(FIELD_FONT.family, FIELD_FONT.size),
        pad_x       = FIELD_PAD_X,
        pad_y       = FIELD_PAD_Y,
        h           = h,
        placeholder = definition.placeholder,
        on_commit   = function(value)
            commit_field(plugin, field, definition, value)
        end,
    })
    local cleaned = buffer:gsub(STRIP_PATTERN, "")
    if cleaned ~= buffer then ui.text_field.set_value(field, cleaned) end
end

function toolbar.draw(view_state, plugin, x, y, w, h)
    local field_w = field_width_for(w)
    if field_w <= 0 then return end
    for index, definition in ipairs(SHIP_PARAM_FIELDS) do
        local field_x = x + (index - 1) * (field_w + FIELD_GAP)
        draw_field(view_state, plugin, definition, field_x, y, field_w, h)
    end
end

return toolbar
