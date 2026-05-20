local M = {}

local GLYPH_BASE_SIZE = 14
local CHECK_BASE_SIZE = 10
local CHECK_DEFAULT_LINE_W = 1.6
local CIRCLE_MIN_SEGMENTS = 24
local CIRCLE_SEG_FACTOR = 6
local HALF_PIXEL = 0.5
local STAR_INNER_RATIO = 0.45
local STAR_TOTAL_VERTICES = 10
local TRIANGLE_BASE_DIVISOR = 2
local CHECK_SEG_LENGTHS = { 3.111, 5.815 }
local CHECK_WAYPOINTS = {
    { 2,   5.2 },
    { 4.2, 7.4 },
    { 8,   3 },
}
local COMPASS_OPS = {
    { "circle", 7, 7, 5.5, "line" },
    { "circle", 7, 7, 1.5, "fill" },
    { "line", 7, 0, 7, 3 },
    { "line", 7, 11, 7, 14 },
    { "line", 0, 7, 3, 7 },
    { "line", 11, 7, 14, 7 },
}

local function apply_circle_op(op, x, y, s)
    local cx
    local cy
    local r
    local mode

    cx = op[2]
    cy = op[3]
    r = op[4]
    mode = op[5]
    love.graphics.circle(mode or "line", x + cx * s, y + cy * s, r * s)
end

local function apply_line_op(op, x, y, s)
    love.graphics.line(
        x + op[2] * s, y + op[3] * s,
        x + op[4] * s, y + op[5] * s)
end

local GLYPH_OP_HANDLERS = {
    circle = apply_circle_op,
    line   = apply_line_op,
}

local function draw_glyph(x, y, size, color, ops)
    local s
    local prev_lw
    local handler

    s = size / GLYPH_BASE_SIZE
    prev_lw = love.graphics.getLineWidth()
    love.graphics.setLineWidth(math.max(1, math.floor(s + HALF_PIXEL)))
    love.graphics.setColor(color)
    for _, op in ipairs(ops) do
        handler = GLYPH_OP_HANDLERS[op[1]]
        if handler then
            handler(op, x, y, s)
        end
    end
    love.graphics.setLineWidth(prev_lw)
end

function M.compass(x, y, size, color)
    draw_glyph(x, y, size, color, COMPASS_OPS)
end

local function check_total_length()
    return CHECK_SEG_LENGTHS[1] + CHECK_SEG_LENGTHS[2]
end

local function draw_full_check_segment(a, b, s, x, y)
    love.graphics.line(
        x + a[1] * s, y + a[2] * s,
        x + b[1] * s, y + b[2] * s)
end

local function draw_partial_check_segment(a, b, k, s, x, y)
    love.graphics.line(
        x + a[1] * s, y + a[2] * s,
        x + (a[1] + (b[1] - a[1]) * k) * s,
        y + (a[2] + (b[2] - a[2]) * k) * s)
end

local function draw_check_segments(s, x, y, target)
    local consumed
    local a
    local b
    local len
    local remaining
    local k

    consumed = 0
    for i = 1, #CHECK_SEG_LENGTHS do
        a = CHECK_WAYPOINTS[i]
        b = CHECK_WAYPOINTS[i + 1]
        len = CHECK_SEG_LENGTHS[i]
        remaining = target - consumed
        if remaining <= 0 then
            break
        end
        if remaining >= len then
            draw_full_check_segment(a, b, s, x, y)
        else
            k = remaining / len
            draw_partial_check_segment(a, b, k, s, x, y)
        end
        consumed = consumed + len
    end
end

function M.check(x, y, size, color, progress, line_w)
    local s
    local target
    local prev_lw

    progress = math.max(0, math.min(1, progress or 1))
    if progress <= 0 then
        return
    end
    s = size / CHECK_BASE_SIZE
    target = check_total_length() * progress
    prev_lw = love.graphics.getLineWidth()
    love.graphics.setLineWidth(line_w or CHECK_DEFAULT_LINE_W)
    love.graphics.setColor(color)
    draw_check_segments(s, x, y, target)
    love.graphics.setLineWidth(prev_lw)
end

local function circle_segments(radius)
    return math.max(CIRCLE_MIN_SEGMENTS,
        math.floor(radius * CIRCLE_SEG_FACTOR + HALF_PIXEL))
end

function M.dot(x, y, size, color)
    local r

    love.graphics.setColor(color)
    r = size / TRIANGLE_BASE_DIVISOR
    love.graphics.circle("fill", x + r, y + r, r, circle_segments(r))
end

function M.triangle_up(x, y, size, color)
    local cx

    love.graphics.setColor(color)
    cx = x + size / TRIANGLE_BASE_DIVISOR
    love.graphics.polygon("fill",
        cx, y,
        x + size, y + size,
        x, y + size)
end

function M.triangle_down(x, y, size, color)
    local cx

    love.graphics.setColor(color)
    cx = x + size / TRIANGLE_BASE_DIVISOR
    love.graphics.polygon("fill",
        x, y,
        x + size, y,
        cx, y + size)
end

local function star_points(cx, cy, outer)
    local inner
    local pts
    local angle
    local r

    inner = outer * STAR_INNER_RATIO
    pts = {}
    for i = 0, STAR_TOTAL_VERTICES - 1 do
        angle = -math.pi / 2 + i * math.pi / (STAR_TOTAL_VERTICES / 2)
        r = (i % 2 == 0) and outer or inner
        table.insert(pts, cx + math.cos(angle) * r)
        table.insert(pts, cy + math.sin(angle) * r)
    end
    return pts
end

function M.star(x, y, size, color)
    local cx
    local cy
    local outer

    love.graphics.setColor(color)
    cx = x + size / TRIANGLE_BASE_DIVISOR
    cy = y + size / TRIANGLE_BASE_DIVISOR
    outer = size / TRIANGLE_BASE_DIVISOR
    love.graphics.polygon("fill", star_points(cx, cy, outer))
end

function M.diamond(x, y, size, color)
    local cx
    local cy
    local r

    love.graphics.setColor(color)
    cx = x + size / TRIANGLE_BASE_DIVISOR
    cy = y + size / TRIANGLE_BASE_DIVISOR
    r = size / TRIANGLE_BASE_DIVISOR
    love.graphics.polygon("fill",
        cx, cy - r,
        cx + r, cy,
        cx, cy + r,
        cx - r, cy)
end

function M.play(x, y, size, color)
    love.graphics.setColor(color)
    love.graphics.polygon("fill",
        x, y,
        x + size, y + size / TRIANGLE_BASE_DIVISOR,
        x, y + size)
end

function M.stop(x, y, size, color)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y, size, size)
end

return M
