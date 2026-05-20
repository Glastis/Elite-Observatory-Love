local ui = require("observatory.ui")
local theme = ui.theme

local plugin_pane = {}

local TOOLBAR_H = 24
local TOOLBAR_GAP = 12
local TOOLBAR_EXTRA_GAP = 12
local SECTION_GAP = 10
local PLACEHOLDER_VOFFSET = 8
local ROW_COUNT_LETTER_EM = 0.1
local ROW_COUNT_FORMAT = "%d ROWS"
local PLACEHOLDER_TEXT = "This plugin has no grid."
local PLACEHOLDER_LETTER_EM = 0.08
local DEFAULT_TOOLBAR_KIND = "toggle"
local DEFAULT_VERSION = "0.0"
local HEADER_NUM = "::"
local VERSION_PREFIX = "v"
local MONO_SMALL_SIZE = 10
local MONO_NORMAL_SIZE = 11

local function resolve_value(value, plugin)
    if type(value) == "function" then
        return value(plugin)
    end
    return value
end

local function reset_grid_scroll(state, plugin_id)
    local gs

    gs = state.grid_state[plugin_id]
    if not gs then
        return
    end
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
    local builder

    if not plugin[definition.setter] then
        return nil
    end
    builder = TOOLBAR_ITEM_BUILDERS[definition.kind or DEFAULT_TOOLBAR_KIND]
    return builder(state, plugin, definition)
end

local function build_toolbar_items(state, plugin)
    local items
    local item

    items = {}
    for _, definition in ipairs(plugin.toolbar or {}) do
        item = build_toolbar_item(state, plugin, definition)
        if item then
            table.insert(items, item)
        end
    end
    return items
end

local function row_count_text(plugin)
    if plugin.row_count_label then
        return plugin:row_count_label()
    end
    if plugin.grid then
        return string.format(ROW_COUNT_FORMAT, #(plugin.grid.rows or {}))
    end
    return ""
end

local function draw_row_count(plugin, x_right, y, h, font)
    local row_count
    local rc_w

    row_count = row_count_text(plugin)
    if row_count == "" then
        return
    end
    rc_w = ui.text.width(row_count, font, ROW_COUNT_LETTER_EM)
    ui.text.draw_v_center(row_count, x_right - rc_w, y, h, {
        font = font, color = theme.colors.text_faint,
        letter_em = ROW_COUNT_LETTER_EM,
    })
end

local function draw_toolbar_extra(state, plugin, x, y, w, h)
    if not plugin.draw_toolbar_extra or w <= 0 then
        return
    end
    state.grid_state[plugin.id] = state.grid_state[plugin.id] or {}
    plugin:draw_toolbar_extra(state.grid_state[plugin.id], x, y, w, h)
end

local function draw_segment_buttons(state, plugin, items, x, y, h, font)
    if #items == 0 then
        return 0
    end
    state.seg_group[plugin.id] = state.seg_group[plugin.id] or {}
    return ui.seg.draw(state.seg_group[plugin.id], items, x, y,
        { h = h, font = font })
end

local function draw_toolbar(state, plugin, x, y, w, h, font)
    local items
    local seg_w
    local extra_x

    items = build_toolbar_items(state, plugin)
    seg_w = draw_segment_buttons(state, plugin, items, x, y, h, font)
    extra_x = x + seg_w
    if seg_w > 0 then
        extra_x = extra_x + TOOLBAR_EXTRA_GAP
    end
    draw_row_count(plugin, x + w, y, h, font)
    draw_toolbar_extra(state, plugin, extra_x, y, x + w - extra_x, h)
end

local function draw_grid_placeholder(plugin, x, body_y, w, body_h)
    if plugin.draw_view or plugin.grid then
        return false
    end
    ui.text.draw(PLACEHOLDER_TEXT,
        x, body_y + body_h / 2 - PLACEHOLDER_VOFFSET, {
            font = theme.font("mono", MONO_NORMAL_SIZE),
            color = theme.colors.text_faint,
            letter_em = PLACEHOLDER_LETTER_EM,
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
    local pad_x
    local pad_y
    local inner_x
    local inner_w
    local cy
    local seg_font
    local available_h

    pad_x = theme.metrics.section_pad_x
    pad_y = theme.metrics.section_pad_y
    inner_x = x + pad_x
    inner_w = w - pad_x * 2
    cy = body_y + pad_y
    cy = cy + ui.section_header.draw(string.upper(plugin.name),
        inner_x, cy, inner_w, {
            num = HEADER_NUM,
            right = VERSION_PREFIX .. (plugin.version or DEFAULT_VERSION),
        }) + SECTION_GAP
    if draw_grid_placeholder(plugin, x, body_y, w, body_h) then
        return
    end
    seg_font = theme.font("mono", MONO_SMALL_SIZE)
    draw_toolbar(state, plugin, inner_x, cy, inner_w, TOOLBAR_H, seg_font)
    cy = cy + TOOLBAR_H + TOOLBAR_GAP
    available_h = body_y + body_h - cy - pad_y
    draw_grid_or_view(state, plugin, inner_x, cy, inner_w, available_h)
end

return plugin_pane
