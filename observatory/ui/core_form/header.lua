local ui = require("observatory.ui")
local paths = require("observatory.paths")
local theme = ui.theme

local header = {}

local PAD_X = 16
local MARK_SIZE = 14
local TITLE_GAP = 14
local TITLE_TO_VERSION_GAP = 12
local LETTER_EM_TITLE = 0.14
local LETTER_EM_VERSION = 0.1
local BTN_HEIGHT = 28
local SEG_LETTER_EM = 0.14
local PREFIX_RATIO = 0.55
local PREFIX_GAP = 6
local VERSION_LABEL_FORMAT = "0.4 / %s"

local function draw_brand(hh)
    local cursor = PAD_X
    ui.icon.compass(cursor, (hh - MARK_SIZE) / 2, MARK_SIZE, theme.colors.accent)
    cursor = cursor + MARK_SIZE + TITLE_GAP

    local title_font = theme.font("mono", 11)
    ui.text.draw_v_center("OBSERVATORY", cursor, 0, hh, {
        font = title_font,
        color = theme.colors.accent,
        letter_em = LETTER_EM_TITLE,
    })
    cursor = cursor + ui.text.width("OBSERVATORY", title_font, LETTER_EM_TITLE)
        + TITLE_TO_VERSION_GAP

    local sub_font = theme.font("mono", 10)
    ui.text.draw_v_center(string.format(VERSION_LABEL_FORMAT, paths.os()), cursor, 0, hh, {
        font = sub_font,
        color = theme.colors.text_faint,
        letter_em = LETTER_EM_VERSION,
    })
end

local function action_items(actions)
    local monitoring = actions.is_monitoring()
    return {
        {
            label = monitoring and "STOP MONITOR" or "START MONITOR",
            primary = true,
            icon = monitoring and "stop" or "play",
            on_click = function()
                if monitoring then actions.stop_monitor()
                else actions.start_monitor() end
            end,
        },
        { label = "READ ALL", on_click = actions.read_all },
    }
end

local function items_total_width(items, font)
    local total = 0
    for _, it in ipairs(items) do
        local pad = theme.metrics.seg_pad_x * 2
        local lw = ui.text.width(it.label, font, SEG_LETTER_EM)
        local prefix_w = it.icon and (font:getHeight() * PREFIX_RATIO) or 0
        local prefix_gap = it.icon and PREFIX_GAP or 0
        total = total + pad + prefix_w + prefix_gap + lw
    end
    return total
end

local function draw_actions(state, w, hh, actions)
    local seg_font = theme.font("mono", 11)
    local items = action_items(actions)
    local total_w = items_total_width(items, seg_font)
    local seg_y = (hh - BTN_HEIGHT) / 2
    local seg_x = w - total_w - PAD_X
    state.seg_header = state.seg_header or {}
    ui.seg.draw(state.seg_header, items, seg_x, seg_y, {
        h = BTN_HEIGHT, font = seg_font,
    })
end

function header.draw(state, w, actions)
    local hh = theme.metrics.bar_top_h
    ui.panel.draw(0, 0, w, hh, {
        bg = theme.colors.panel,
        bottom_border = theme.colors.rule,
    })
    draw_brand(hh)
    draw_actions(state, w, hh, actions)
end

return header
