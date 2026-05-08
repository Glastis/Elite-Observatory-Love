-- Panel — flat rectangular surface with optional border, optional accent
-- left edge, and a `bottom_border` shorthand for cards that only ever draw a
-- single rule below themselves.

local theme = require("observatory.ui.theme")

local M = {}

-- opts:
--   bg, border, bottom_border, left_accent, left_accent_w, radius.
function M.draw(x, y, w, h, opts)
    opts = opts or {}
    local r = opts.radius or 0

    if opts.bg ~= false then
        love.graphics.setColor(opts.bg or theme.colors.panel)
        love.graphics.rectangle("fill", x, y, w, h, r, r)
    end

    if opts.left_accent then
        local lw = opts.left_accent_w or 2
        love.graphics.setColor(opts.left_accent)
        love.graphics.rectangle("fill", x, y, lw, h)
    end

    if opts.border then
        love.graphics.setColor(opts.border)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, r, r)
    end

    if opts.bottom_border then
        love.graphics.setColor(opts.bottom_border)
        love.graphics.rectangle("fill", x, y + h - 1, w, 1)
    end
end

function M.rule(x1, y1, x2, y2, color)
    love.graphics.setColor(color or theme.colors.rule)
    love.graphics.rectangle("fill",
        math.min(x1, x2), math.min(y1, y2),
        math.max(1, math.abs(x2 - x1)),
        math.max(1, math.abs(y2 - y1)))
end

return M
