-- Generic list item — hover-aware row with three slots: leading (callback),
-- title, and an optional list of inline subtitle fragments.

local theme = require("observatory.ui.theme")
local text = require("observatory.ui.text")
local row = require("observatory.ui.row")

local M = {}

local function ensure(state)
    state = state or {}
    state.row = state.row or {}
    return state
end

-- opts: leading_w, leading (fn), title_font, title_color, subtitle_font,
-- subtitle_color, pad_x, row_h, bottom_rule, subtitle (fragments), title.
-- Returns clicked, state.
function M.draw(state, x, y, w, opts)
    state = ensure(state)
    opts = opts or {}
    local pad_x = opts.pad_x or 4
    local row_h = opts.row_h or 44
    local leading_w = opts.leading_w or 0
    local title_font = opts.title_font or theme.font("main", 13)
    local subtitle_font = opts.subtitle_font or theme.font("mono", 10)
    local title_color = opts.title_color or theme.colors.text
    local subtitle_color = opts.subtitle_color or theme.colors.text_faint

    local _, clicked = row.draw(state.row, x, y, w, row_h, {
        bottom_rule = opts.bottom_rule,
    })

    if opts.leading then
        opts.leading(x + pad_x, y, leading_w, row_h)
    end

    local content_x = x + pad_x + leading_w + (leading_w > 0 and 12 or 0)

    local has_subtitle = opts.subtitle and #opts.subtitle > 0
    local title_y, subtitle_y
    if has_subtitle then
        local total_h = title_font:getHeight() + 2 + subtitle_font:getHeight()
        title_y = y + (row_h - total_h) / 2
        subtitle_y = title_y + title_font:getHeight() + 2
    else
        title_y = y + (row_h - title_font:getHeight()) / 2
    end

    text.draw(opts.title or "", content_x, title_y, {
        font = title_font, color = title_color,
    })

    if has_subtitle then
        local cursor = content_x
        for _, frag in ipairs(opts.subtitle) do
            local tw = text.draw(frag.text, cursor, subtitle_y, {
                font = frag.font or subtitle_font,
                color = frag.color or subtitle_color,
                letter_em = frag.letter_em or 0.04,
            })
            cursor = cursor + tw
        end
    end

    return clicked, state
end

return M
