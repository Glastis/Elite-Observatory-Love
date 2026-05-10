local ui = require("observatory.ui")
local theme = ui.theme

local combined_picker = {}

local NONE_VALUE = ""
local COMBINED_PLACEHOLDER_NONE = "(none)"
local SPLIT_OPTIONS = { "vertical", "horizontal" }
local PICKER_ROW_H = 24
local SECTION_GAP = 8
local FIELD_GAP = 12

combined_picker.NONE_VALUE = NONE_VALUE
combined_picker.SPLIT_OPTIONS = SPLIT_OPTIONS

local function none_picker_item(setting_key, current, settings)
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

local function plugin_picker_item(plugin, setting_key, current, settings)
    return {
        key = plugin.id,
        label = (plugin.short_name or plugin.name):upper(),
        primary = current == plugin.id,
        on_click = function()
            settings.set(setting_key, plugin.id)
            settings.save()
        end,
    }
end

function combined_picker.plugin_items(setting_key, excluded_id, plugins, settings)
    local current = settings.get(setting_key) or NONE_VALUE
    local items = { none_picker_item(setting_key, current, settings) }
    for _, p in ipairs(plugins) do
        local item = plugin_picker_item(p, setting_key, current, settings)
        if p.id == excluded_id and p.id ~= current then
            item.disabled = true
        end
        table.insert(items, item)
    end
    return items
end

function combined_picker.split_items(split_key, default_split, settings)
    local current = settings.get(split_key) or default_split
    local items = {}
    for _, opt in ipairs(SPLIT_OPTIONS) do
        local value = opt
        table.insert(items, {
            key = value,
            label = value:upper(),
            primary = current == value,
            on_click = function()
                settings.set(split_key, value)
                settings.save()
            end,
        })
    end
    return items
end

local function draw_field(label, picker_state, items, x, y, w, font)
    local _, content_y = ui.labeled_value.draw(label, x, y, w)
    ui.picker.draw(picker_state, items, x, content_y, {
        h = PICKER_ROW_H, font = font, max_w = w,
    })
    return content_y + PICKER_ROW_H + FIELD_GAP
end

function combined_picker.draw_section(opts, x, y, w)
    local seg_state = opts.seg_state
    local settings = opts.settings
    local plugins = opts.plugins
    local slot_keys = opts.slot_keys
    local split_key = opts.split_key
    local default_split = opts.default_split

    local current_split = settings.get(split_key) or default_split
    local current_left = settings.get(slot_keys.left) or NONE_VALUE
    local current_right = settings.get(slot_keys.right) or NONE_VALUE

    local cy = y + ui.section_header.draw("COMBINED VIEW", x, y, w, {
        num = "04",
        right = current_split:upper(),
    }) + SECTION_GAP

    local picker_font = theme.font("mono", 10)

    cy = draw_field("LEFT", seg_state.left,
        combined_picker.plugin_items(slot_keys.left, current_right, plugins, settings),
        x, cy, w, picker_font)
    cy = draw_field("RIGHT", seg_state.right,
        combined_picker.plugin_items(slot_keys.right, current_left, plugins, settings),
        x, cy, w, picker_font)
    cy = draw_field("SPLIT", seg_state.split,
        combined_picker.split_items(split_key, default_split, settings),
        x, cy, w, picker_font)

    return cy
end

return combined_picker
