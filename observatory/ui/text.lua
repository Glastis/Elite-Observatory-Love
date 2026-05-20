local theme = require("observatory.ui.theme")
local utf8 = require("utf8")

local M = {}

local ELLIPSIS = "..."
local BOLD_OFFSET = 1
local DEFAULT_FONT_FAMILY = "main"
local DEFAULT_FONT_SIZE = 13

local function spacing_px(font, em)
    if not em or em == 0 then
        return 0
    end
    return em * font:getHeight()
end

function M.width(s, font, em)
    local sp
    local total

    if not s or s == "" then
        return 0
    end
    sp = spacing_px(font, em)
    total = font:getWidth(s)
    if sp == 0 then
        return total
    end
    return total + sp * math.max(0, M.count(s) - 1)
end

function M.count(s)
    local n

    n = utf8.len(s)
    if n then
        return n
    end
    return #s
end

local function print_run_plain(s, x, y)
    love.graphics.print(s, x, y)
end

local function print_run_spaced(s, x, y, font, sp)
    local cursor
    local ch

    cursor = x
    for _, cp in utf8.codes(s) do
        ch = utf8.char(cp)
        love.graphics.print(ch, cursor, y)
        cursor = cursor + font:getWidth(ch) + sp
    end
end

local function print_run(s, x, y, font, sp)
    if sp == 0 then
        print_run_plain(s, x, y)
        return
    end
    print_run_spaced(s, x, y, font, sp)
end

local ALIGN_OFFSET = {
    center = function(width, total_w) return (width - total_w) / 2 end,
    right  = function(width, total_w) return width - total_w end,
}

local function aligned_x(x, opts, total_w)
    local resolver

    if not opts.align or not opts.width then
        return x
    end
    resolver = ALIGN_OFFSET[opts.align]
    if not resolver then
        return x
    end
    return x + resolver(opts.width, total_w)
end

function M.draw(s, x, y, opts)
    local font
    local em
    local sp
    local total_w
    local draw_x

    if not s or s == "" then
        return 0
    end
    opts = opts or {}
    font = opts.font or love.graphics.getFont()
    love.graphics.setFont(font)
    if opts.color then
        love.graphics.setColor(opts.color)
    end
    em = opts.letter_em or 0
    sp = spacing_px(font, em)
    total_w = M.width(s, font, em)
    draw_x = aligned_x(x, opts, total_w)
    print_run(s, draw_x, y, font, sp)
    if opts.bold then
        print_run(s, draw_x + BOLD_OFFSET, y, font, sp)
    end
    return total_w
end

function M.draw_v_center(s, x, y, h, opts)
    local font

    opts = opts or {}
    font = opts.font or love.graphics.getFont()
    return M.draw(s, x, y + (h - font:getHeight()) / 2, opts)
end

function M.truncate_left(s, font, max_w, em)
    local count
    local byte_pos
    local trimmed

    em = em or 0
    if M.width(s, font, em) <= max_w then
        return s
    end
    count = utf8.len(s) or 0
    for skip = 1, count do
        byte_pos = utf8.offset(s, skip + 1)
        trimmed = byte_pos and s:sub(byte_pos) or ""
        if M.width(ELLIPSIS .. trimmed, font, em) <= max_w then
            return ELLIPSIS .. trimmed
        end
    end
    return ELLIPSIS
end

function M.truncate_right(s, font, max_w, em)
    local count
    local byte_end
    local trimmed

    em = em or 0
    if M.width(s, font, em) <= max_w then
        return s
    end
    count = utf8.len(s) or 0
    for keep = count - 1, 0, -1 do
        byte_end = utf8.offset(s, keep + 1)
        trimmed = byte_end and s:sub(1, byte_end - 1) or ""
        if M.width(trimmed .. ELLIPSIS, font, em) <= max_w then
            return trimmed .. ELLIPSIS
        end
    end
    return ELLIPSIS
end

function M.font(spec)
    spec = spec or {}
    return theme.font(spec.family or DEFAULT_FONT_FAMILY,
        spec.size or DEFAULT_FONT_SIZE)
end

return M
