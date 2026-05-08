-- Section header — numbered heading with title, optional right-aligned hint
-- text, and a thin accent rule below.

local theme = require("observatory.ui.theme")
local text = require("observatory.ui.text")

local M = {}

-- opts: num, right, font_main, font_meta, color_num, color_title, color_right,
-- rule_color, pad_bottom.
-- Returns the height the header consumed.
function M.draw(title, x, y, w, opts)
    opts = opts or {}
    local font_main = opts.font_main or theme.font("mono", 11)
    local font_meta = opts.font_meta or theme.font("mono", 10)
    local pad_bottom = opts.pad_bottom or 6

    local cursor = x

    if opts.num then
        local nw = text.draw(opts.num, cursor, y, {
            font = font_meta,
            color = opts.color_num or theme.colors.accent,
            letter_em = 0.1,
        })
        cursor = cursor + nw + 8
    end

    text.draw(title, cursor, y, {
        font = font_main,
        color = opts.color_title or theme.colors.text,
        letter_em = 0.16,
    })

    if opts.right then
        local rw = text.width(opts.right, font_meta, 0.14)
        text.draw(opts.right, x + w - rw, y, {
            font = font_meta,
            color = opts.color_right or theme.colors.text_faint,
            letter_em = 0.14,
        })
    end

    local h = font_main:getHeight() + pad_bottom + 1
    love.graphics.setColor(opts.rule_color or theme.colors.accent_rule)
    love.graphics.rectangle("fill", x, y + h - 1, w, 1)
    return h
end

return M
