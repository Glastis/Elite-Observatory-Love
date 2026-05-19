local ui = require("observatory.ui")
local theme = ui.theme

local plugin_pane = {}

local TOOLBAR_H = 24
local TOOLBAR_GAP = 12
local TOOLBAR_EXTRA_GAP = 12
local SECTION_GAP = 10
local PLACEHOLDER_VOFFSET = 8
local DEFAULT_SORT_MODE = "body"

local SYSTEM_TOGGLE_LABEL = {
    [true]  = "SHOW SYSTEM",
    [false] = "HIDE SYSTEM",
}

local SCANNED_TOGGLE_LABEL = {
    [true]  = "SHOW SCANNED",
    [false] = "HIDE SCANNED",
}

local SORT_MODE_LABEL = {
    body  = "SORT BY BODY",
    price = "SORT BY PRICE",
}

local function system_toggle_label(plugin)
    return SYSTEM_TOGGLE_LABEL[plugin.is_system_hidden == true]
end

local function scanned_toggle_label(plugin)
    return SCANNED_TOGGLE_LABEL[plugin.is_scanned_hidden == true]
end

local function sort_mode_label(plugin)
    return SORT_MODE_LABEL[plugin.sort_mode or DEFAULT_SORT_MODE]
        or SORT_MODE_LABEL[DEFAULT_SORT_MODE]
end

local function sort_mode_is_primary(plugin)
    return (plugin.sort_mode or DEFAULT_SORT_MODE) ~= DEFAULT_SORT_MODE
end

local TOOLBAR_BUTTON_BUILDERS = {
    {
        kind    = "cycle",
        label   = sort_mode_label,
        setter  = "cycle_sort_mode",
        primary = sort_mode_is_primary,
    },
    { label = system_toggle_label,  setter = "set_system_hidden",  flag = "is_system_hidden" },
    { label = scanned_toggle_label, setter = "set_scanned_hidden", flag = "is_scanned_hidden" },
    { label = "GROUP BY BODY",      setter = "set_grouping",       flag = "group_by_body" },
    { label = "CLOSE TO NEBULA",    setter = "set_near_nebula",    flag = "near_nebula" },
    { label = "CLOSE TO GUARDIAN",  setter = "set_near_guardian",  flag = "near_guardian" },
    { label = "SHOW HIDDEN",        setter = "set_show_hidden",    flag = "is_show_hidden" },
}

local function resolve_value(value, plugin)
    if type(value) == "function" then return value(plugin) end
    return value
end

local function reset_grid_scroll(state, plugin_id)
    local gs = state.grid_state[plugin_id]
    if not gs then return end
    gs.scroll = 0
end

local function build_toggle_item(state, plugin, definition)
    return {
        label = resolve_value(definition.label, plugin),
        primary = plugin[definition.flag] == true,
        on_click = function()
            plugin[definition.setter](plugin, not plugin[definition.flag])
            reset_grid_scroll(state, plugin.id)
        end,
    }
end

local function build_cycle_item(state, plugin, definition)
    return {
        label = resolve_value(definition.label, plugin),
        primary = resolve_value(definition.primary, plugin) == true,
        on_click = function()
            plugin[definition.setter](plugin)
            reset_grid_scroll(state, plugin.id)
        end,
    }
end

local TOOLBAR_ITEM_BUILDERS = {
    toggle = build_toggle_item,
    cycle  = build_cycle_item,
}

local function build_toolbar_item(state, plugin, definition)
    if not plugin[definition.setter] then return nil end
    local builder = TOOLBAR_ITEM_BUILDERS[definition.kind or "toggle"]
    return builder(state, plugin, definition)
end

local function build_toolbar_items(state, plugin)
    local items = {}
    for _, definition in ipairs(TOOLBAR_BUTTON_BUILDERS) do
        local item = build_toolbar_item(state, plugin, definition)
        if item then table.insert(items, item) end
    end
    return items
end

local function row_count_text(plugin)
    if plugin.row_count_label then return plugin:row_count_label() end
    if plugin.grid then
        return string.format("%d ROWS", #(plugin.grid.rows or {}))
    end
    return ""
end

local function draw_row_count(plugin, x_right, y, h, font)
    local row_count = row_count_text(plugin)
    if row_count == "" then return end
    local rc_w = ui.text.width(row_count, font, 0.1)
    ui.text.draw_v_center(row_count, x_right - rc_w, y, h, {
        font = font, color = theme.colors.text_faint, letter_em = 0.1,
    })
end

local function draw_toolbar_extra(state, plugin, x, y, w, h)
    if not plugin.draw_toolbar_extra or w <= 0 then return end
    state.grid_state[plugin.id] = state.grid_state[plugin.id] or {}
    plugin:draw_toolbar_extra(state.grid_state[plugin.id], x, y, w, h)
end

local function draw_toolbar(state, plugin, x, y, w, h, font)
    local items = build_toolbar_items(state, plugin)
    local seg_w = 0
    if #items > 0 then
        state.seg_group[plugin.id] = state.seg_group[plugin.id] or {}
        seg_w = ui.seg.draw(state.seg_group[plugin.id], items, x, y,
            { h = h, font = font })
    end
    local extra_x = x + seg_w
    if seg_w > 0 then extra_x = extra_x + TOOLBAR_EXTRA_GAP end
    draw_row_count(plugin, x + w, y, h, font)
    draw_toolbar_extra(state, plugin, extra_x, y, x + w - extra_x, h)
end

local function draw_grid_placeholder(plugin, x, body_y, w, body_h)
    if plugin.draw_view or plugin.grid then return false end
    ui.text.draw("This plugin has no grid.",
        x, body_y + body_h / 2 - PLACEHOLDER_VOFFSET, {
            font = theme.font("mono", 11),
            color = theme.colors.text_faint,
            letter_em = 0.08,
            align = "center",
            width = w,
        })
    return true
end

local function draw_grid_or_view(state, plugin, x, y, w, h)
    state.grid_state[plugin.id] = state.grid_state[plugin.id] or {}
    if plugin.draw_view then
        plugin:draw_view(state.grid_state[plugin.id], x, y, w, h)
        return
    end
    state.grid_state[plugin.id] = ui.grid.draw(
        state.grid_state[plugin.id], plugin.grid, x, y, w, h)
end

function plugin_pane.draw(state, plugin, x, body_y, w, body_h)
    local pad_x = theme.metrics.section_pad_x
    local pad_y = theme.metrics.section_pad_y
    local inner_x = x + pad_x
    local inner_w = w - pad_x * 2

    local cy = body_y + pad_y
    cy = cy + ui.section_header.draw(string.upper(plugin.name),
        inner_x, cy, inner_w, {
            num = "::",
            right = "v" .. (plugin.version or "0.0"),
        }) + SECTION_GAP

    if draw_grid_placeholder(plugin, x, body_y, w, body_h) then return end

    local seg_font = theme.font("mono", 10)
    draw_toolbar(state, plugin, inner_x, cy, inner_w, TOOLBAR_H, seg_font)
    cy = cy + TOOLBAR_H + TOOLBAR_GAP

    local available_h = body_y + body_h - cy - pad_y
    draw_grid_or_view(state, plugin, inner_x, cy, inner_w, available_h)
end

return plugin_pane
