-- Main UI form. Composed entirely from generic ui/* components — anything
-- specific to "this is the observatory app" lives in this file (plugin
-- enumeration, log_monitor wiring, settings persistence). Everything else
-- is delegated to the components in observatory.ui.*.

local ui = require("observatory.ui")
local log_monitor = require("observatory.log_monitor")
local plugin_manager = require("observatory.plugin_manager")
local settings = require("observatory.settings")
local paths = require("observatory.paths")

local theme = ui.theme

local core_form = {}

-- ---------- Persistent UI state ----------

local state = {
    tabs        = nil,
    seg_header  = nil,
    seg_apply   = nil,
    seg_group   = {},      -- plugin id => seg widget state
    cb_rows     = {},      -- one slot per checkbox
    plugin_rows = {},      -- plugin id => { row, switch, status_color }
    grid_state  = {},      -- plugin id => grid scroll state
    fade        = { t = 0 },
    last_tab    = 1,
    journal_field = nil,   -- text_field state for journal folder
    journal_seeded = false,
    seg_combined = { left = {}, right = {}, split = {} },
}

local CB_SETTINGS = {
    { key = "NativeNotify", label = "Desktop notifications" },
    { key = "StartMonitor", label = "Begin monitoring on launch" },
    { key = "StartReadAll", label = "Backfill all journals on first run" },
    { key = "AltMonitor",   label = "Polling monitor mode" },
}

local FIXED_TABS = { "Core settings", "Combined" }
local COMBINED_SEPARATOR_W = 1
local COMBINED_SLOT_KEYS = { left = "CombinedViewLeft", right = "CombinedViewRight" }
local COMBINED_SPLIT_KEY = "CombinedViewSplit"
local COMBINED_DEFAULT_SPLIT = "vertical"
local COMBINED_PLACEHOLDER_NONE = "(none)"
local COMBINED_PANE_PLACEHOLDER = "Pick a plugin in Core settings."

-- ---------- Helpers ----------

local function plugin_slot(p)
    state.plugin_rows[p.id] = state.plugin_rows[p.id] or {
        row = {},
        switch = {},
        status_color = ui.animation.tween_color(theme.colors.accent),
    }
    return state.plugin_rows[p.id]
end

local function format_count(n)
    n = tonumber(n) or 0
    return string.format("%04d", n)
end

local function short_path(p, max_chars)
    if not p or p == "" then return "(none)" end
    max_chars = max_chars or 28
    local tail = p:match("[^/\\]+$") or p
    -- Try to keep the last directory and its parent for context.
    local parent = p:match("([^/\\]+)[/\\][^/\\]+$")
    local label = parent and (".../" .. parent .. "/" .. tail) or tail
    if #label > max_chars then
        label = "..." .. label:sub(-max_chars)
    end
    return label
end

-- ---------- Header ----------

local function draw_header(w)
    local hh = theme.metrics.bar_top_h
    ui.panel.draw(0, 0, w, hh, {
        bg = theme.colors.panel,
        bottom_border = theme.colors.rule,
    })

    local pad_x = 16
    local cursor = pad_x

    local mark = 14
    ui.icon.compass(cursor, (hh - mark) / 2, mark, theme.colors.accent)
    cursor = cursor + mark + 14

    local title_font = theme.font("mono", 11)
    ui.text.draw_v_center("OBSERVATORY", cursor, 0, hh, {
        font = title_font,
        color = theme.colors.accent,
        letter_em = 0.14,
    })
    cursor = cursor + ui.text.width("OBSERVATORY", title_font, 0.14) + 12

    local sub_font = theme.font("mono", 10)
    local version_label = string.format("0.4 / %s", paths.os())
    ui.text.draw_v_center(version_label, cursor, 0, hh, {
        font = sub_font,
        color = theme.colors.text_faint,
        letter_em = 0.1,
    })

    local monitoring = log_monitor.is_monitoring()
    local items = {
        {
            label = monitoring and "STOP MONITOR" or "START MONITOR",
            primary = true,
            icon = monitoring and "stop" or "play",
            on_click = function()
                if monitoring then log_monitor.stop()
                else log_monitor.start() end
            end,
        },
        { label = "READ ALL", on_click = function() log_monitor.read_all() end },
    }

    local seg_font = theme.font("mono", 11)
    local total_w = 0
    for _, it in ipairs(items) do
        local pad = theme.metrics.seg_pad_x * 2
        local lw = ui.text.width(it.label, seg_font, 0.14)
        local prefix_w = it.icon and (seg_font:getHeight() * 0.55) or 0
        local prefix_gap = it.icon and 6 or 0
        total_w = total_w + pad + prefix_w + prefix_gap + lw
    end
    local btn_h = 28
    local seg_y = (hh - btn_h) / 2
    local seg_x = w - total_w - pad_x
    state.seg_header = state.seg_header or {}
    ui.seg.draw(state.seg_header, items, seg_x, seg_y, {
        h = btn_h, font = seg_font,
    })
end

-- ---------- Tabs ----------

local function draw_tabs(w, y)
    local hh = theme.metrics.tabs_h
    ui.panel.draw(0, y, w, hh, {
        bg = theme.colors.panel,
        border = false,
    })
    state.tabs = state.tabs or {}

    local labels = {}
    for _, l in ipairs(FIXED_TABS) do table.insert(labels, l) end
    for _, p in ipairs(plugin_manager.list_enabled()) do
        table.insert(labels, p.short_name or p.name)
    end

    local sel = ui.tabs.draw(state.tabs, labels, 0, y, w, hh, {
        tab_w = 160, pad_x = 14,
        font = theme.font("main", 13),
    })
    return sel, hh
end

local function begin_pane_fade(tab_index)
    if state.last_tab ~= tab_index then
        state.fade.t = 0
        state.last_tab = tab_index
    end
    local k = ui.animation.fade_in(state.fade, ui.input.dt, 0.25)
    return k, (1 - k) * 4
end

-- ---------- Combined view configuration ----------

local SPLIT_OPTIONS = { "vertical", "horizontal" }
local NONE_VALUE = ""

local function none_picker_item(setting_key, current)
    return {
        key = NONE_VALUE,
        label = COMBINED_PLACEHOLDER_NONE:upper(),
        primary = current == NONE_VALUE,
        on_click = function()
            settings.set(setting_key, NONE_VALUE)
            settings.save()
        end,
    }
end

local function plugin_picker_item(plugin, setting_key, current)
    local plugin_id = plugin.id
    return {
        key = plugin_id,
        label = (plugin.short_name or plugin.name):upper(),
        primary = current == plugin_id,
        on_click = function()
            settings.set(setting_key, plugin_id)
            settings.save()
        end,
    }
end

local function combined_picker_items(setting_key, excluded_id)
    local current = settings.get(setting_key) or NONE_VALUE
    local items = { none_picker_item(setting_key, current) }
    for _, p in ipairs(plugin_manager.list_enabled()) do
        local item = plugin_picker_item(p, setting_key, current)
        if p.id == excluded_id and p.id ~= current then
            item.disabled = true
        end
        table.insert(items, item)
    end
    return items
end

local function combined_split_items()
    local current = settings.get(COMBINED_SPLIT_KEY) or COMBINED_DEFAULT_SPLIT
    local items = {}
    for _, opt in ipairs(SPLIT_OPTIONS) do
        local value = opt
        table.insert(items, {
            key = value,
            label = value:upper(),
            primary = current == value,
            on_click = function()
                settings.set(COMBINED_SPLIT_KEY, value)
                settings.save()
            end,
        })
    end
    return items
end

local function draw_combined_field(label, picker_state, items, inner_x, cy, inner_w, font, row_h)
    local _, content_y = ui.labeled_value.draw(label, inner_x, cy, inner_w)
    ui.picker.draw(picker_state, items, inner_x, content_y, {
        h = row_h, font = font, max_w = inner_w,
    })
    return content_y + row_h + 12
end

local function draw_combined_settings(inner_x, cy, inner_w)
    local current_split = settings.get(COMBINED_SPLIT_KEY) or COMBINED_DEFAULT_SPLIT
    local current_left = settings.get(COMBINED_SLOT_KEYS.left) or NONE_VALUE
    local current_right = settings.get(COMBINED_SLOT_KEYS.right) or NONE_VALUE

    cy = cy + ui.section_header.draw("COMBINED VIEW", inner_x, cy, inner_w, {
        num = "04",
        right = current_split:upper(),
    }) + 8

    local picker_font = theme.font("mono", 10)
    local row_h = 24

    cy = draw_combined_field("LEFT", state.seg_combined.left,
        combined_picker_items(COMBINED_SLOT_KEYS.left, current_right),
        inner_x, cy, inner_w, picker_font, row_h)
    cy = draw_combined_field("RIGHT", state.seg_combined.right,
        combined_picker_items(COMBINED_SLOT_KEYS.right, current_left),
        inner_x, cy, inner_w, picker_font, row_h)
    cy = draw_combined_field("SPLIT", state.seg_combined.split,
        combined_split_items(),
        inner_x, cy, inner_w, picker_font, row_h)

    return cy
end

-- ---------- Settings tab ----------

local function draw_left_column(x, y, w, h)
    local pad_x = theme.metrics.section_pad_x
    local pad_y = theme.metrics.section_pad_y
    local inner_x = x + pad_x
    local inner_w = w - pad_x * 2

    local cy = y + pad_y
    cy = cy + ui.section_header.draw("LOCATIONS", inner_x, cy, inner_w, {
        num = "01",
        right = "OS / " .. paths.os():upper(),
    }) + 10

    -- APP DATA — read-only display of the LÖVE save directory.
    local _, content_y = ui.labeled_value.draw("APP DATA",
        inner_x, cy, inner_w)
    local mono = theme.font("mono", 11)
    local app_dir = (love.filesystem and love.filesystem.getSaveDirectory()) or "?"
    ui.text.draw(ui.text.truncate_left(app_dir, mono, inner_w, 0),
        inner_x, content_y, { font = mono, color = theme.colors.text })
    cy = content_y + mono:getHeight() + 16

    -- JOURNAL FOLDER — editable.
    local _, jy = ui.labeled_value.draw("JOURNAL FOLDER",
        inner_x, cy, inner_w)
    state.journal_field = state.journal_field or { id = "journal_folder" }
    local current_folder = log_monitor.journal_folder() or ""
    if not state.journal_seeded then
        ui.text_field.set_value(state.journal_field, current_folder)
        state.journal_seeded = true
    end
    local field_w = inner_w
    local field_h
    do
        local font = theme.font("mono", 11)
        field_h = font:getHeight() + 7 * 2
    end
    local new_value, committed = ui.text_field.draw(state.journal_field,
        nil, inner_x, jy, field_w, {
            placeholder = "(unset)",
        })
    if committed then
        log_monitor.change_watched_directory(new_value)
        ui.text_field.set_value(state.journal_field,
            log_monitor.journal_folder() or "")
    end
    cy = jy + field_h + 8

    -- APPLY / DETECT segmented action.
    state.seg_apply = state.seg_apply or {}
    local seg_font = theme.font("mono", 10)
    local _, _ = ui.seg.draw(state.seg_apply, {
        {
            label = "APPLY", primary = true,
            on_click = function()
                log_monitor.change_watched_directory(
                    ui.text_field.value(state.journal_field))
                ui.text_field.set_value(state.journal_field,
                    log_monitor.journal_folder() or "")
            end,
        },
        {
            label = "DETECT",
            on_click = function()
                log_monitor.change_watched_directory("")
                ui.text_field.set_value(state.journal_field,
                    log_monitor.journal_folder() or "")
            end,
        },
    }, inner_x, cy, { h = 24, font = seg_font })

    -- READABLE pulse if the folder actually opens.
    local readable = current_folder ~= "" and paths.dir_exists(current_folder)
    if readable then
        local caption = "READABLE"
        local cap_font = theme.font("mono", 10)
        local pulse_w = 6 + 6 + ui.text.width(caption, cap_font, 0.08)
        ui.pulse.draw(caption,
            inner_x + inner_w - pulse_w,
            cy + (24 - cap_font:getHeight()) / 2,
            { font = cap_font })
    end

    cy = cy + 24 + 18

    -- Plugin load errors.
    local errs = plugin_manager.errors()
    if #errs > 0 then
        cy = cy + ui.section_header.draw("ERRORS", inner_x, cy, inner_w, {
            num = "!!",
            color_num = theme.colors.danger,
            rule_color = theme.with_alpha(theme.colors.danger, 0.5),
            right = string.format("%02d", #errs),
        }) + 6
        local err_font = theme.font("mono", 10)
        for _, e in ipairs(errs) do
            local label = string.format("%s: %s", e.plugin, e.message)
            local shown = ui.text.truncate_right(label, err_font, inner_w, 0)
            ui.text.draw(shown, inner_x, cy, {
                font = err_font, color = theme.colors.danger,
            })
            cy = cy + err_font:getHeight() + 4
        end
        cy = cy + 12
    end

    draw_combined_settings(inner_x, cy, inner_w)
end

local function draw_right_column(x, y, w, h)
    local pad_x = theme.metrics.section_pad_x
    local pad_y = theme.metrics.section_pad_y
    local inner_x = x + pad_x
    local inner_w = w - pad_x * 2

    local cy = y + pad_y

    -- 02 BEHAVIOUR.
    cy = cy + ui.section_header.draw("BEHAVIOUR", inner_x, cy, inner_w, {
        num = "02",
        right = string.format("%02d OPTIONS", #CB_SETTINGS),
    }) + 6

    for i, entry in ipairs(CB_SETTINGS) do
        state.cb_rows[i] = state.cb_rows[i] or {}
        local current = settings.get(entry.key)
        local new_val, toggled = ui.checkbox.draw(state.cb_rows[i], entry.label,
            current, inner_x, cy, inner_w)
        if toggled then
            settings.set(entry.key, new_val)
            settings.save()
        end
        cy = cy + 30
    end

    cy = cy + 12

    -- 03 PLUGINS.
    local plugin_list = plugin_manager.list()
    cy = cy + ui.section_header.draw("PLUGINS", inner_x, cy, inner_w, {
        num = "03",
        right = string.format("%02d / %02d", #plugin_list, #plugin_list),
    }) + 6

    if #plugin_list == 0 then
        ui.text.draw("No plugins discovered.", inner_x, cy, {
            font = theme.font("mono", 11),
            color = theme.colors.text_faint,
            letter_em = 0.04,
        })
        return
    end

    for _, p in ipairs(plugin_list) do
        local slot = plugin_slot(p)
        local enabled = plugin_manager.is_enabled(p.id)

        local clicked = ui.list_item.draw(slot.row,
            inner_x, cy, inner_w, {
                row_h = 44,
                leading_w = 26,
                leading = function(lx, ly, lw, lh)
                    local sy = ly + (lh - 14) / 2
                    ui.switch.draw(slot.switch, enabled, lx, sy,
                        { w = 26, h = 14 })
                end,
                title = p.name,
                title_color = enabled and theme.colors.text or theme.colors.text_dim,
                subtitle = {
                    { text = "v" .. (p.version or "0"), letter_em = 0.04 },
                    { text = " | ", letter_em = 0.04 },
                    {
                        text = enabled and "loaded" or "disabled",
                        color = ui.animation.color_value(slot.status_color),
                        letter_em = 0.04,
                    },
                },
            })

        if clicked then
            plugin_manager.set_enabled(p.id, not enabled)
            enabled = not enabled
        end

        ui.animation.go_color(slot.status_color,
            enabled and theme.colors.accent or theme.colors.text_faint,
            theme.motion.fast, theme.motion.smooth)
        ui.animation.update_color(slot.status_color, ui.input.dt)

        cy = cy + 44
    end
end

local function draw_settings_body(w, body_y, body_h)
    local left_w = math.floor(w * (1.05 / 2.05))
    local right_w = w - left_w

    draw_left_column(0, body_y, left_w, body_h)

    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", left_w, body_y, 1, body_h)

    draw_right_column(left_w, body_y, right_w, body_h)
end

-- ---------- Plugin tab ----------

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

local function reset_grid_scroll(plugin_id)
    local gs = state.grid_state[plugin_id]
    if not gs then return end
    gs.scroll = 0
end

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

local DEFAULT_SORT_MODE = "body"

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
    {
        label    = system_toggle_label,
        setter   = "set_system_hidden",
        flag     = "is_system_hidden",
    },
    {
        label    = scanned_toggle_label,
        setter   = "set_scanned_hidden",
        flag     = "is_scanned_hidden",
    },
    {
        label    = "GROUP BY BODY",
        setter   = "set_grouping",
        flag     = "group_by_body",
    },
    {
        label    = "CLOSE TO NEBULA",
        setter   = "set_near_nebula",
        flag     = "near_nebula",
    },
    {
        label    = "CLOSE TO GUARDIAN",
        setter   = "set_near_guardian",
        flag     = "near_guardian",
    },
}

local function resolve_toolbar_value(value, plugin)
    if type(value) == "function" then return value(plugin) end
    return value
end

local function build_toggle_item(plugin, definition)
    return {
        label = resolve_toolbar_value(definition.label, plugin),
        primary = plugin[definition.flag] == true,
        on_click = function()
            plugin[definition.setter](plugin, not plugin[definition.flag])
            reset_grid_scroll(plugin.id)
        end,
    }
end

local function build_cycle_item(plugin, definition)
    return {
        label = resolve_toolbar_value(definition.label, plugin),
        primary = resolve_toolbar_value(definition.primary, plugin) == true,
        on_click = function()
            plugin[definition.setter](plugin)
            reset_grid_scroll(plugin.id)
        end,
    }
end

local TOOLBAR_ITEM_BUILDERS = {
    toggle = build_toggle_item,
    cycle  = build_cycle_item,
}

local function build_toolbar_item(plugin, definition)
    if not plugin[definition.setter] then return nil end
    local builder = TOOLBAR_ITEM_BUILDERS[definition.kind or "toggle"]
    return builder(plugin, definition)
end

local function build_toolbar_items(plugin)
    local items = {}
    for _, definition in ipairs(TOOLBAR_BUTTON_BUILDERS) do
        local item = build_toolbar_item(plugin, definition)
        if item then table.insert(items, item) end
    end
    return items
end

local function draw_toolbar_buttons(plugin, x, y, h, font)
    local items = build_toolbar_items(plugin)
    if #items == 0 then return end
    state.seg_group[plugin.id] = state.seg_group[plugin.id] or {}
    ui.seg.draw(state.seg_group[plugin.id], items, x, y,
        { h = h, font = font })
end

local function draw_plugin_toolbar(plugin, x, y, w, h, font)
    draw_toolbar_buttons(plugin, x, y, h, font)
    draw_row_count(plugin, x + w, y, h, font)
end

local function draw_plugin_body(plugin, x, body_y, w, body_h)
    local pad_x = theme.metrics.section_pad_x
    local pad_y = theme.metrics.section_pad_y
    local inner_x = x + pad_x
    local inner_w = w - pad_x * 2

    local cy = body_y + pad_y
    cy = cy + ui.section_header.draw(string.upper(plugin.name),
        inner_x, cy, inner_w, {
            num = "::",
            right = "v" .. (plugin.version or "0.0"),
        }) + 10

    if not plugin.draw_view and not plugin.grid then
        ui.text.draw("This plugin has no grid.",
            x, body_y + body_h / 2 - 8, {
                font = theme.font("mono", 11),
                color = theme.colors.text_faint,
                letter_em = 0.08,
                align = "center",
                width = w,
            })
        return
    end

    local seg_font = theme.font("mono", 10)
    local toolbar_h = 24
    draw_plugin_toolbar(plugin, inner_x, cy, inner_w, toolbar_h, seg_font)
    cy = cy + toolbar_h + 12

    state.grid_state[plugin.id] = state.grid_state[plugin.id] or {}
    local available_h = body_y + body_h - cy - pad_y

    if plugin.draw_view then
        plugin:draw_view(state.grid_state[plugin.id],
            inner_x, cy, inner_w, available_h)
        return
    end

    state.grid_state[plugin.id] = ui.grid.draw(
        state.grid_state[plugin.id], plugin.grid,
        inner_x, cy, inner_w, available_h)
end

-- ---------- Combined view tab ----------

local SPLIT_LAYOUTS = {
    vertical = function(w, body_y, body_h)
        local half_w = math.floor(w / 2)
        return {
            { x = 0,      y = body_y, w = half_w,     h = body_h },
            { x = half_w, y = body_y, w = w - half_w, h = body_h },
            separator = {
                x = half_w, y = body_y, w = COMBINED_SEPARATOR_W, h = body_h,
            },
        }
    end,
    horizontal = function(w, body_y, body_h)
        local half_h = math.floor(body_h / 2)
        return {
            { x = 0, y = body_y,          w = w, h = half_h },
            { x = 0, y = body_y + half_h, w = w, h = body_h - half_h },
            separator = {
                x = 0, y = body_y + half_h, w = w, h = COMBINED_SEPARATOR_W,
            },
        }
    end,
}

local function plugin_for_combined_pane(plugin_id)
    if not plugin_id or plugin_id == "" then return nil end
    for _, p in ipairs(plugin_manager.list_enabled()) do
        if p.id == plugin_id then return p end
    end
    return nil
end

local function draw_combined_pane(plugin, pane)
    if plugin then
        draw_plugin_body(plugin, pane.x, pane.y, pane.w, pane.h)
        return
    end
    local font = theme.font("mono", 11)
    ui.text.draw(COMBINED_PANE_PLACEHOLDER,
        pane.x, pane.y + pane.h / 2 - font:getHeight() / 2, {
            font = font, color = theme.colors.text_faint,
            letter_em = 0.08, align = "center", width = pane.w,
        })
end

local function combined_layout_for(w, body_y, body_h)
    local split = settings.get(COMBINED_SPLIT_KEY) or COMBINED_DEFAULT_SPLIT
    local layout_fn = SPLIT_LAYOUTS[split] or SPLIT_LAYOUTS[COMBINED_DEFAULT_SPLIT]
    return layout_fn(w, body_y, body_h)
end

local function draw_combined_body(w, body_y, body_h)
    local panes = combined_layout_for(w, body_y, body_h)
    local left = plugin_for_combined_pane(settings.get(COMBINED_SLOT_KEYS.left))
    local right = plugin_for_combined_pane(settings.get(COMBINED_SLOT_KEYS.right))
    draw_combined_pane(left, panes[1])
    draw_combined_pane(right, panes[2])

    local sep = panes.separator
    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", sep.x, sep.y, sep.w, sep.h)
end

-- ---------- Body dispatcher ----------

local function fixed_tab_handlers(w, body_y, body_h)
    return {
        function() draw_settings_body(w, body_y, body_h) end,
        function() draw_combined_body(w, body_y, body_h) end,
    }
end

local function draw_body(w, body_y, body_h, tab_index)
    local _, y_offset = begin_pane_fade(tab_index)

    love.graphics.push()
    love.graphics.translate(0, y_offset)

    local handlers = fixed_tab_handlers(w, body_y, body_h)
    local handler = handlers[tab_index]
    if handler then
        handler()
    else
        local plugin = plugin_manager.list_enabled()[tab_index - #FIXED_TABS]
        if plugin then
            draw_plugin_body(plugin, 0, body_y, w, body_h)
        end
    end

    love.graphics.pop()
end

-- ---------- Bottom status bar ----------

local function monitor_status_label()
    if log_monitor.is_batch_read() then return "BATCH" end
    if log_monitor.is_monitoring() then return "REALTIME" end
    if log_monitor.current_state() == 0 then return "IDLE" end
    return "BUSY"
end

local REALTIME_PULSE_PERIOD = 5.0

local function monitor_status_color(label)
    if label == "REALTIME" then
        return ui.pulse.color(theme.colors.success, REALTIME_PULSE_PERIOD)
    end
    return theme.colors.accent
end

local function draw_monitor_status(w, y, bh)
    local label = monitor_status_label()
    local color = monitor_status_color(label)
    local font = theme.font("mono", 10)
    local glyph_size = math.floor(font:getHeight() * 0.7)
    local glyph_gap = 6
    local pad_x = 14
    local label_w = ui.text.width(label, font, 0.1)
    local cell_w = label_w + pad_x * 2
    local x = w - cell_w - glyph_size - glyph_gap
    ui.icon.diamond(x, y + (bh - glyph_size) / 2, glyph_size, color)
    ui.status_cell.draw({
        { text = label, color = color },
    }, x + glyph_size + glyph_gap, y, bh,
        { divider = false, accent = true })
end

local function draw_status_bar(w, h)
    local bh = theme.metrics.bar_bottom_h
    local y = h - bh
    ui.panel.draw(0, y, w, bh, {
        bg = theme.colors.panel,
        border = false,
    })
    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", 0, y, w, 1)

    local cursor = 0
    cursor = ui.status_cell.draw({
        { text = "LAST" },
        { text = log_monitor.last_event() or "NONE",
          color = theme.colors.text_dim },
    }, cursor, y, bh)
    cursor = ui.status_cell.draw({
        { text = "EVENTS" },
        { text = format_count(log_monitor.total_events()),
          color = theme.colors.text_dim },
    }, cursor, y, bh)
    cursor = ui.status_cell.draw({
        { text = "JRNL" },
        { text = short_path(log_monitor.journal_folder()),
          color = theme.colors.text_dim, no_letter_em = true },
    }, cursor, y, bh)

    draw_monitor_status(w, y, bh)
end

-- ---------- Batch progress overlay ----------

local function draw_batch_overlay(w, h)
    local progress = log_monitor.batch_progress()
    if not progress then return end
    local box_w, box_h = 360, 80
    local x = (w - box_w) / 2
    local y = (h - box_h) / 2

    ui.panel.draw(x, y, box_w, box_h, {
        bg = { 0, 0, 0, 0.85 },
        border = theme.colors.accent_rule,
    })

    local title_font = theme.font("mono", 11)
    ui.text.draw(string.format("Reading journals: %d / %d",
        progress.done, math.max(progress.total, 1)),
        x, y + 14, {
            font = title_font, color = theme.colors.text,
            align = "center", width = box_w, letter_em = 0.08,
        })
    local sub_font = theme.font("mono", 10)
    ui.text.draw(string.format("%d events processed",
        progress.processed_lines),
        x, y + 34, {
            font = sub_font, color = theme.colors.text_dim,
            align = "center", width = box_w, letter_em = 0.06,
        })

    local frac = progress.total > 0
        and math.min(progress.done / progress.total, 1) or 0
    local bar_w = box_w - 32
    love.graphics.setColor(theme.colors.rule_strong)
    love.graphics.rectangle("fill", x + 16, y + box_h - 22, bar_w, 6)
    love.graphics.setColor(theme.colors.accent)
    love.graphics.rectangle("fill", x + 16, y + box_h - 22, bar_w * frac, 6)
end

-- ---------- Public API ----------

function core_form.draw()
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    love.graphics.setColor(theme.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    draw_header(w)

    local tabs_y = theme.metrics.bar_top_h
    local tab_index, tabs_h = draw_tabs(w, tabs_y)

    local body_y = tabs_y + tabs_h
    local body_h = h - body_y - theme.metrics.bar_bottom_h
    draw_body(w, body_y, body_h, tab_index)

    draw_status_bar(w, h)
    draw_batch_overlay(w, h)
end

function core_form.wheel(dx, dy)
    -- Forward to the shared input module so any grid currently under the
    -- cursor consumes the scroll on next draw.
    ui.input.feed_wheel(dx, dy)
end

return core_form
