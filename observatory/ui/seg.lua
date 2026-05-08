-- Segmented button group — a horizontal cluster of buttons sharing one
-- border, separated by hairline right-edges. Each item can be the "primary"
-- variant which uses the accent soft background and accent text.

local theme = require("observatory.ui.theme")
local button = require("observatory.ui.button")
local icon = require("observatory.ui.icon")
local text = require("observatory.ui.text")

local M = {}

local function ensure(state, n)
    state = state or {}
    state.items = state.items or {}
    for i = 1, n do
        state.items[i] = state.items[i] or {}
    end
    return state
end

local function item_width(it, font)
    local pad = (it.pad_x or theme.metrics.seg_pad_x) * 2
    local lw = it.label and text.width(it.label, font, it.letter_em or 0.14) or 0
    local prefix_w = it.icon and (font:getHeight() * 0.55) or 0
    local prefix_gap = it.icon and 6 or 0
    return pad + prefix_w + prefix_gap + lw
end

local PREFIX_BUILDERS = {
    play = function(px, py, ps, color) icon.play(px, py, ps, color) end,
    stop = function(px, py, ps, color) icon.stop(px, py, ps, color) end,
}

-- items[i]: { label, letter_em, primary (bool), icon ("play"|"stop"|nil),
--             on_click (fn), min_w }.
-- Returns total width consumed, clicked index (or nil), state.
function M.draw(state, items, x, y, opts)
    opts = opts or {}
    state = ensure(state, #items)
    local font = opts.font or theme.font("mono", 11)
    local h = opts.h or 28
    local border = opts.border or theme.colors.rule
    local sep = opts.sep or theme.colors.rule

    local widths = {}
    local total_w = 0
    for i, it in ipairs(items) do
        widths[i] = math.max(it.min_w or 0, item_width(it, font))
        total_w = total_w + widths[i]
    end

    love.graphics.setColor(border)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, total_w - 1, h - 1)

    local clicked
    local cursor = x
    for i, it in ipairs(items) do
        local iw = widths[i]
        local is_last = i == #items
        local prefix = it.icon and PREFIX_BUILDERS[it.icon] or nil

        local was_clicked = button.draw(state.items[i],
            cursor, y, iw, h, {
                label = it.label,
                font = font,
                letter_em = it.letter_em or 0.14,
                color = it.primary and theme.colors.accent or theme.colors.text_dim,
                hover_color = theme.colors.text,
                bg = it.primary and theme.colors.accent_soft or nil,
                hover_bg = it.primary
                    and theme.with_alpha(theme.colors.accent, 0.24)
                    or theme.colors.seg_hover,
                right_border = (not is_last) and sep or nil,
                prefix = prefix,
                prefix_w = prefix and (font:getHeight() * 0.55) or nil,
            })
        if was_clicked then
            clicked = i
            if it.on_click then it.on_click() end
        end
        cursor = cursor + iw
    end

    return total_w, clicked, state
end

return M
