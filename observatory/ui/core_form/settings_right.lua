local ui = require("observatory.ui")
local theme = ui.theme

local settings_right = {}

local CB_ROW_HEIGHT = 30
local PLUGIN_ROW_HEIGHT = 44
local SWITCH_W = 26
local SWITCH_H = 14
local LEADING_W = 26
local SECTION_GAP_AFTER_CB = 12
local HEADER_GAP = 6
local LETTER_EM = 0.04

local function draw_behaviour(state, x, y, w, settings, cb_settings)
    local cy = y + ui.section_header.draw("BEHAVIOUR", x, y, w, {
        num = "02",
        right = string.format("%02d OPTIONS", #cb_settings),
    }) + HEADER_GAP

    for i, entry in ipairs(cb_settings) do
        state.cb_rows[i] = state.cb_rows[i] or {}
        local current = settings.get(entry.key)
        local new_val, toggled = ui.checkbox.draw(state.cb_rows[i], entry.label,
            current, x, cy, w)
        if toggled then
            settings.set(entry.key, new_val)
            settings.save()
        end
        cy = cy + CB_ROW_HEIGHT
    end
    return cy + SECTION_GAP_AFTER_CB
end

local function ensure_plugin_slot(state, plugin)
    state.plugin_rows[plugin.id] = state.plugin_rows[plugin.id] or {
        row = {},
        switch = {},
        status_color = ui.animation.tween_color(theme.colors.accent),
    }
    return state.plugin_rows[plugin.id]
end

local function plugin_subtitle(plugin, enabled, slot)
    return {
        { text = "v" .. (plugin.version or "0"), letter_em = LETTER_EM },
        { text = " | ", letter_em = LETTER_EM },
        {
            text = enabled and "loaded" or "disabled",
            color = ui.animation.color_value(slot.status_color),
            letter_em = LETTER_EM,
        },
    }
end

local function draw_plugin_row(slot, plugin, enabled, x, y, w)
    return ui.list_item.draw(slot.row, x, y, w, {
        row_h = PLUGIN_ROW_HEIGHT,
        leading_w = LEADING_W,
        leading = function(lx, ly, lw, lh)
            local sy = ly + (lh - SWITCH_H) / 2
            ui.switch.draw(slot.switch, enabled, lx, sy,
                { w = SWITCH_W, h = SWITCH_H })
        end,
        title = plugin.name,
        title_color = enabled and theme.colors.text or theme.colors.text_dim,
        subtitle = plugin_subtitle(plugin, enabled, slot),
    })
end

local function update_status_color(slot, enabled)
    ui.animation.go_color(slot.status_color,
        enabled and theme.colors.accent or theme.colors.text_faint,
        theme.motion.fast, theme.motion.smooth)
    ui.animation.update_color(slot.status_color, ui.input.dt)
end

local function draw_plugin_list(state, x, y, w, plugins, plugin_actions)
    local cy = y
    for _, p in ipairs(plugins) do
        local slot = ensure_plugin_slot(state, p)
        local enabled = plugin_actions.is_enabled(p.id)
        local clicked = draw_plugin_row(slot, p, enabled, x, cy, w)
        if clicked then
            plugin_actions.set_enabled(p.id, not enabled)
            enabled = not enabled
        end
        update_status_color(slot, enabled)
        cy = cy + PLUGIN_ROW_HEIGHT
    end
end

local function draw_no_plugins(x, y)
    ui.text.draw("No plugins discovered.", x, y, {
        font = theme.font("mono", 11),
        color = theme.colors.text_faint,
        letter_em = LETTER_EM,
    })
end

local function draw_plugins_section(state, x, y, w, plugins, plugin_actions)
    local cy = y + ui.section_header.draw("PLUGINS", x, y, w, {
        num = "03",
        right = string.format("%02d / %02d", #plugins, #plugins),
    }) + HEADER_GAP

    if #plugins == 0 then
        draw_no_plugins(x, cy)
        return
    end
    draw_plugin_list(state, x, cy, w, plugins, plugin_actions)
end

function settings_right.draw(state, x, y, w, deps)
    local pad_x = theme.metrics.section_pad_x
    local pad_y = theme.metrics.section_pad_y
    local inner_x = x + pad_x
    local inner_w = w - pad_x * 2

    local cy = y + pad_y
    cy = draw_behaviour(state, inner_x, cy, inner_w, deps.settings, deps.cb_settings)
    draw_plugins_section(state, inner_x, cy, inner_w, deps.list_plugins(), deps.plugin_actions)
end

return settings_right
