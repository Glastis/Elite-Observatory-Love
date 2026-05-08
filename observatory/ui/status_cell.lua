-- A single cell inside a horizontal status bar. Cells share a fixed height,
-- have right-side dividers, and can carry an optional accent flag for the
-- "current state" cell.

local theme = require("observatory.ui.theme")
local text = require("observatory.ui.text")

local M = {}

-- segments: list of { text, color?, font?, letter_em?, no_letter_em? }
-- opts: pad_x (14), gap (8), divider, accent (bool), font, letter_em.
-- Returns next cursor x, cell_w.
function M.draw(segments, x, y, h, opts)
    opts = opts or {}
    local pad_x = opts.pad_x or 14
    local gap = opts.gap or 8
    local font = opts.font or theme.font("mono", 10)
    local default_color = opts.accent and theme.colors.accent
        or theme.colors.text_faint
    local default_em = opts.letter_em or 0.1

    local total_w = 0
    for i, seg in ipairs(segments) do
        local f = seg.font or font
        local em = seg.no_letter_em and 0 or (seg.letter_em or default_em)
        total_w = total_w + text.width(seg.text, f, em)
        if i < #segments then total_w = total_w + gap end
    end
    local cell_w = total_w + pad_x * 2

    local cursor = x + pad_x
    for _, seg in ipairs(segments) do
        local f = seg.font or font
        local em = seg.no_letter_em and 0 or (seg.letter_em or default_em)
        text.draw_v_center(seg.text, cursor, y, h, {
            font = f,
            color = seg.color or default_color,
            letter_em = em,
        })
        cursor = cursor + text.width(seg.text, f, em) + gap
    end

    if opts.divider ~= false then
        love.graphics.setColor(opts.divider or theme.colors.rule)
        love.graphics.rectangle("fill", x + cell_w - 1, y, 1, h)
    end

    return x + cell_w, cell_w
end

return M
