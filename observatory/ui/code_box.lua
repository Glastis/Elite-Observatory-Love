-- Code/path box — a deeper-than-panel rectangle with an accent left edge,
-- holding a single line of monospace text that overflows to the right with
-- ellipsis. Used for path/command displays.

local theme = require("observatory.ui.theme")
local text = require("observatory.ui.text")
local panel = require("observatory.ui.panel")

local M = {}

-- opts: bg, border, accent, accent_w, font, color, pad_x, pad_y, align.
-- Returns the height consumed.
function M.draw(value, x, y, w, opts)
    opts = opts or {}
    local font = opts.font or theme.font("mono", 11)
    local pad_x = opts.pad_x or 10
    local pad_y = opts.pad_y or 7
    local h = font:getHeight() + pad_y * 2

    panel.draw(x, y, w, h, {
        bg = opts.bg or theme.colors.panel_deep,
        border = opts.border or theme.colors.rule,
        left_accent = opts.accent or theme.colors.accent,
        left_accent_w = opts.accent_w or 2,
    })

    local accent_w = opts.accent_w or 2
    local inner_x = x + accent_w + pad_x
    local inner_w = w - accent_w - pad_x * 2
    local shown = text.truncate_left(value, font, inner_w, 0)

    text.draw(shown, inner_x, y + pad_y, {
        font = font,
        color = opts.color or theme.colors.text,
    })

    return h
end

return M
