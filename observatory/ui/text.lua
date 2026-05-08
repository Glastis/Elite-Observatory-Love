-- Text rendering helpers. Adds two things on top of love.graphics.print:
--   * letter-spacing emulation (Love2D has no native equivalent).
--   * easy width measurement that accounts for the same letter-spacing,
--     so callers can right-align without re-implementing the loop.

local theme = require("observatory.ui.theme")
local utf8 = require("utf8")

local M = {}

local function spacing_px(font, em)
    if not em or em == 0 then return 0 end
    return em * font:getHeight()
end

function M.width(s, font, em)
    if not s or s == "" then return 0 end
    local sp = spacing_px(font, em)
    local total = font:getWidth(s)
    if sp == 0 then return total end
    return total + sp * math.max(0, M.count(s) - 1)
end

function M.count(s)
    local n = utf8.len(s)
    if n then return n end
    return #s
end

-- opts:
--   color, font, letter_em, align ("left"|"center"|"right"), width.
function M.draw(s, x, y, opts)
    if not s or s == "" then return 0 end
    opts = opts or {}
    local font = opts.font or love.graphics.getFont()
    love.graphics.setFont(font)
    if opts.color then love.graphics.setColor(opts.color) end

    local em = opts.letter_em or 0
    local sp = spacing_px(font, em)

    local total_w = M.width(s, font, em)
    local draw_x = x
    if opts.align == "center" and opts.width then
        draw_x = x + (opts.width - total_w) / 2
    elseif opts.align == "right" and opts.width then
        draw_x = x + opts.width - total_w
    end

    if sp == 0 then
        love.graphics.print(s, draw_x, y)
        return total_w
    end

    local cursor = draw_x
    for _, cp in utf8.codes(s) do
        local ch = utf8.char(cp)
        love.graphics.print(ch, cursor, y)
        cursor = cursor + font:getWidth(ch) + sp
    end
    return total_w
end

function M.draw_v_center(s, x, y, h, opts)
    opts = opts or {}
    local font = opts.font or love.graphics.getFont()
    return M.draw(s, x, y + (h - font:getHeight()) / 2, opts)
end

-- Crop a path-like string from the left with an ellipsis until it fits.
function M.truncate_left(s, font, max_w, em)
    em = em or 0
    if M.width(s, font, em) <= max_w then return s end
    local ellipsis = "..."
    local trimmed = s
    while #trimmed > 0 and M.width(ellipsis .. trimmed, font, em) > max_w do
        trimmed = trimmed:sub(2)
    end
    return ellipsis .. trimmed
end

-- Crop from the right with an ellipsis. Used by single-line input fields so
-- the head of the value stays anchored.
function M.truncate_right(s, font, max_w, em)
    em = em or 0
    if M.width(s, font, em) <= max_w then return s end
    local ellipsis = "..."
    local trimmed = s
    while #trimmed > 0 and M.width(trimmed .. ellipsis, font, em) > max_w do
        trimmed = trimmed:sub(1, -2)
    end
    return trimmed .. ellipsis
end

function M.font(spec)
    spec = spec or {}
    return theme.font(spec.family or "main", spec.size or 13)
end

return M
