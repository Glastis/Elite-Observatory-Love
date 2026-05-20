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
local ERROR_LINE_GAP = 4
local ERROR_BLOCK_GAP = 12
local PULSE_BORDER = 6
local PULSE_GAP = 6
local PULSE_LETTER_EM = 0.08
local DANGER_RULE_ALPHA = 0.5
local LOCATIONS_HEADER = "LOCATIONS"
local LOCATIONS_NUM = "01"
local OS_LABEL_PREFIX = "OS / "
local APP_DATA_LABEL = "APP DATA"
local JOURNAL_LABEL = "JOURNAL FOLDER"
local JOURNAL_FIELD_ID = "journal_folder"
local JOURNAL_PLACEHOLDER = "(unset)"
local APPLY_LABEL = "APPLY"
local DETECT_LABEL = "DETECT"
local READABLE_CAPTION = "READABLE"
local ERRORS_HEADER = "ERRORS"
local ERRORS_NUM = "!!"
local ERRORS_COUNT_FORMAT = "%02d"
local UNKNOWN_DIR = "?"
local ERROR_LABEL_FORMAT = "%s: %s"
local MONO_SIZE_SMALL = 10
local MONO_SIZE_NORMAL = 11

local function draw_locations_header(x, y, w, os_label)
    return ui.section_header.draw(LOCATIONS_HEADER, x, y, w, {
        num = LOCATIONS_NUM,
        right = OS_LABEL_PREFIX .. os_label:upper(),
    })
end

local function draw_app_data_row(x, y, w, app_dir)
    local content_y
    local mono

    _, content_y = ui.labeled_value.draw(APP_DATA_LABEL, x, y, w)
    mono = theme.font("mono", MONO_SIZE_NORMAL)
    ui.text.draw(ui.text.truncate_left(app_dir, mono, w, 0),
        x, content_y, { font = mono, color = theme.colors.text })
    return content_y + mono:getHeight() + APP_DATA_GAP
end

local function ensure_journal_seed(state, current_folder)
    state.journal_field = state.journal_field or { id = JOURNAL_FIELD_ID }
    if not state.journal_seeded then
        ui.text_field.set_value(state.journal_field, current_folder)
        state.journal_seeded = true
    end
end

local function field_height_for(font)
    return font:getHeight() + TEXT_FIELD_PAD_Y * 2
end

local function draw_journal_field(state, x, y, w, current_folder, on_commit)
    local jy
    local font
    local fh
    local new_value
    local committed

    _, jy = ui.labeled_value.draw(JOURNAL_LABEL, x, y, w)
    ensure_journal_seed(state, current_folder)
    font = theme.font("mono", MONO_SIZE_NORMAL)
    fh = field_height_for(font)
    new_value, committed = ui.text_field.draw(state.journal_field,
        nil, x, jy, w, { placeholder = JOURNAL_PLACEHOLDER })
    if committed then
        on_commit(new_value)
    end
    return jy + fh + FIELD_GAP
end

local function apply_action_items(state, actions)
    return {
        {
            label = APPLY_LABEL, primary = true,
            on_click = function()
                actions.apply(ui.text_field.value(state.journal_field))
            end,
        },
        {
            label = DETECT_LABEL,
            on_click = function() actions.detect() end,
        },
    }
end

local function draw_readable_pulse(x, y, w)
    local cap_font
    local pulse_w

    cap_font = theme.font("mono", MONO_SIZE_SMALL)
    pulse_w = PULSE_BORDER + PULSE_GAP
        + ui.text.width(READABLE_CAPTION, cap_font, PULSE_LETTER_EM)
    ui.pulse.draw(READABLE_CAPTION,
        x + w - pulse_w,
        y + (APPLY_HEIGHT - cap_font:getHeight()) / 2,
        { font = cap_font })
end

local function draw_apply_segment(state, x, y, w, actions)
    local seg_font

    state.seg_apply = state.seg_apply or {}
    seg_font = theme.font("mono", MONO_SIZE_SMALL)
    ui.seg.draw(state.seg_apply, apply_action_items(state, actions),
        x, y, { h = APPLY_HEIGHT, font = seg_font })
    if not actions.is_readable() then
        return
    end
    draw_readable_pulse(x, y, w)
end

local function commit_journal_folder(state, deps, value)
    deps.actions.apply(value)
    ui.text_field.set_value(state.journal_field,
        deps.actions.journal_folder() or "")
end

local function journal_block_actions(state, deps, current_folder)
    return {
        apply = function(value) commit_journal_folder(state, deps, value) end,
        detect = function() commit_journal_folder(state, deps, "") end,
        is_readable = function()
            return current_folder ~= "" and deps.actions.dir_exists(current_folder)
        end,
    }
end

local function draw_journal_block(state, x, y, w, deps)
    local current_folder
    local cy

    current_folder = deps.actions.journal_folder() or ""
    cy = draw_journal_field(state, x, y, w, current_folder, function(value)
        commit_journal_folder(state, deps, value)
    end)
    draw_apply_segment(state, x, cy, w,
        journal_block_actions(state, deps, current_folder))
    return cy + APPLY_HEIGHT + SEG_TOP_GAP
end

local function draw_error_header(x, y, w, count)
    return ui.section_header.draw(ERRORS_HEADER, x, y, w, {
        num = ERRORS_NUM,
        color_num = theme.colors.danger,
        rule_color = theme.with_alpha(theme.colors.danger, DANGER_RULE_ALPHA),
        right = string.format(ERRORS_COUNT_FORMAT, count),
    })
end

local function draw_error_lines(x, cy, w, errors)
    local err_font
    local label
    local shown

    err_font = theme.font("mono", MONO_SIZE_SMALL)
    for _, e in ipairs(errors) do
        label = string.format(ERROR_LABEL_FORMAT, e.plugin, e.message)
        shown = ui.text.truncate_right(label, err_font, w, 0)
        ui.text.draw(shown, x, cy, {
            font = err_font, color = theme.colors.danger,
        })
        cy = cy + err_font:getHeight() + ERROR_LINE_GAP
    end
    return cy
end

local function draw_error_list(x, y, w, errors)
    local cy

    if #errors == 0 then
        return y
    end
    cy = y + draw_error_header(x, y, w, #errors) + ERROR_GAP
    cy = draw_error_lines(x, cy, w, errors)
    return cy + ERROR_BLOCK_GAP
end

function settings_left.draw(state, x, y, w, deps)
    local pad_x
    local pad_y
    local inner_x
    local inner_w
    local cy
    local app_dir

    pad_x = theme.metrics.section_pad_x
    pad_y = theme.metrics.section_pad_y
    inner_x = x + pad_x
    inner_w = w - pad_x * 2
    cy = y + pad_y
    cy = cy + draw_locations_header(inner_x, cy, inner_w, deps.os_label) + SECTION_GAP
    app_dir = deps.app_dir() or UNKNOWN_DIR
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
