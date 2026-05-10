local ui = require("observatory.ui")
local combined_picker = require("observatory.ui.core_form.combined_picker")
local theme = ui.theme

local settings_left = {}

local TEXT_FIELD_PAD_Y = 7
local APPLY_HEIGHT = 24
local APP_DATA_GAP = 16
local FIELD_GAP = 8
local SEG_TOP_GAP = 18
local SECTION_GAP = 10
local ERROR_GAP = 6
local ERROR_BLOCK_GAP = 12
local PULSE_BORDER = 6
local PULSE_GAP = 6
local PULSE_LETTER_EM = 0.08

local function draw_locations_header(x, y, w, os_label)
    return ui.section_header.draw("LOCATIONS", x, y, w, {
        num = "01",
        right = "OS / " .. os_label:upper(),
    })
end

local function draw_app_data_row(x, y, w, app_dir)
    local _, content_y = ui.labeled_value.draw("APP DATA", x, y, w)
    local mono = theme.font("mono", 11)
    ui.text.draw(ui.text.truncate_left(app_dir, mono, w, 0),
        x, content_y, { font = mono, color = theme.colors.text })
    return content_y + mono:getHeight() + APP_DATA_GAP
end

local function ensure_journal_seed(state, current_folder, refresh_value)
    state.journal_field = state.journal_field or { id = "journal_folder" }
    if not state.journal_seeded then
        ui.text_field.set_value(state.journal_field, current_folder)
        state.journal_seeded = true
    end
    return refresh_value
end

local function field_height_for(font)
    return font:getHeight() + TEXT_FIELD_PAD_Y * 2
end

local function draw_journal_field(state, x, y, w, current_folder, on_commit)
    local _, jy = ui.labeled_value.draw("JOURNAL FOLDER", x, y, w)
    ensure_journal_seed(state, current_folder)
    local font = theme.font("mono", 11)
    local fh = field_height_for(font)
    local new_value, committed = ui.text_field.draw(state.journal_field,
        nil, x, jy, w, { placeholder = "(unset)" })
    if committed then on_commit(new_value) end
    return jy + fh + FIELD_GAP
end

local function apply_action_items(state, actions)
    return {
        {
            label = "APPLY", primary = true,
            on_click = function()
                actions.apply(ui.text_field.value(state.journal_field))
            end,
        },
        {
            label = "DETECT",
            on_click = function() actions.detect() end,
        },
    }
end

local function draw_apply_segment(state, x, y, w, actions)
    state.seg_apply = state.seg_apply or {}
    local seg_font = theme.font("mono", 10)
    ui.seg.draw(state.seg_apply, apply_action_items(state, actions),
        x, y, { h = APPLY_HEIGHT, font = seg_font })

    if not actions.is_readable() then return end
    local caption = "READABLE"
    local cap_font = theme.font("mono", 10)
    local pulse_w = PULSE_BORDER + PULSE_GAP + ui.text.width(caption, cap_font, PULSE_LETTER_EM)
    ui.pulse.draw(caption,
        x + w - pulse_w,
        y + (APPLY_HEIGHT - cap_font:getHeight()) / 2,
        { font = cap_font })
end

local function draw_journal_block(state, x, y, w, deps)
    local current_folder = deps.actions.journal_folder() or ""
    local cy = draw_journal_field(state, x, y, w, current_folder, function(value)
        deps.actions.apply(value)
        ui.text_field.set_value(state.journal_field,
            deps.actions.journal_folder() or "")
    end)
    draw_apply_segment(state, x, cy, w, {
        apply = function(value)
            deps.actions.apply(value)
            ui.text_field.set_value(state.journal_field,
                deps.actions.journal_folder() or "")
        end,
        detect = function()
            deps.actions.apply("")
            ui.text_field.set_value(state.journal_field,
                deps.actions.journal_folder() or "")
        end,
        is_readable = function()
            return current_folder ~= "" and deps.actions.dir_exists(current_folder)
        end,
    })
    return cy + APPLY_HEIGHT + SEG_TOP_GAP
end

local function draw_error_list(x, y, w, errors)
    if #errors == 0 then return y end
    local cy = y + ui.section_header.draw("ERRORS", x, y, w, {
        num = "!!",
        color_num = theme.colors.danger,
        rule_color = theme.with_alpha(theme.colors.danger, 0.5),
        right = string.format("%02d", #errors),
    }) + ERROR_GAP
    local err_font = theme.font("mono", 10)
    for _, e in ipairs(errors) do
        local label = string.format("%s: %s", e.plugin, e.message)
        local shown = ui.text.truncate_right(label, err_font, w, 0)
        ui.text.draw(shown, x, cy, {
            font = err_font, color = theme.colors.danger,
        })
        cy = cy + err_font:getHeight() + 4
    end
    return cy + ERROR_BLOCK_GAP
end

function settings_left.draw(state, x, y, w, deps)
    local pad_x = theme.metrics.section_pad_x
    local pad_y = theme.metrics.section_pad_y
    local inner_x = x + pad_x
    local inner_w = w - pad_x * 2

    local cy = y + pad_y
    cy = cy + draw_locations_header(inner_x, cy, inner_w, deps.os_label) + SECTION_GAP

    local app_dir = deps.app_dir() or "?"
    cy = draw_app_data_row(inner_x, cy, inner_w, app_dir)
    cy = draw_journal_block(state, inner_x, cy, inner_w, deps)
    cy = draw_error_list(inner_x, cy, inner_w, deps.errors())

    combined_picker.draw_section({
        seg_state = state.seg_combined,
        settings = deps.settings,
        plugins = deps.list_enabled_plugins(),
        slot_keys = deps.combined_slot_keys,
        split_key = deps.combined_split_key,
        default_split = deps.combined_default_split,
    }, inner_x, cy, inner_w)
end

return settings_left
