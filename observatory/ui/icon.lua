-- Vector icon library — line-drawn glyphs that scale crisply at any size.
-- Each icon is a pure function; pass top-left position, box size, and colour.

local M = {}

local function draw_glyph(x, y, size, color, ops)
    local s = size / 14
    local prev_lw = love.graphics.getLineWidth()
    love.graphics.setLineWidth(math.max(1, math.floor(s + 0.5)))
    love.graphics.setColor(color)
    for _, op in ipairs(ops) do
        local kind = op[1]
        if kind == "circle" then
            local cx, cy, r, mode = op[2], op[3], op[4], op[5]
            love.graphics.circle(mode or "line", x + cx * s, y + cy * s, r * s)
        elseif kind == "line" then
            love.graphics.line(
                x + op[2] * s, y + op[3] * s,
                x + op[4] * s, y + op[5] * s)
        end
    end
    love.graphics.setLineWidth(prev_lw)
end

function M.compass(x, y, size, color)
    draw_glyph(x, y, size, color, {
        { "circle", 7, 7, 5.5, "line" },
        { "circle", 7, 7, 1.5, "fill" },
        { "line", 7, 0, 7, 3 },
        { "line", 7, 11, 7, 14 },
        { "line", 0, 7, 3, 7 },
        { "line", 11, 7, 14, 7 },
    })
end

-- Animated check mark. `progress` ∈ [0,1] — the tick draws itself in.
function M.check(x, y, size, color, progress, line_w)
    progress = math.max(0, math.min(1, progress or 1))
    if progress <= 0 then return end
    local s = size / 10
    local pts = {
        { 2,   5.2 },
        { 4.2, 7.4 },
        { 8,   3 },
    }
    local seg = { 3.111, 5.815 }
    local total = seg[1] + seg[2]
    local target = total * progress

    local prev_lw = love.graphics.getLineWidth()
    love.graphics.setLineWidth(line_w or 1.6)
    love.graphics.setColor(color)

    local consumed = 0
    for i = 1, #seg do
        local a = pts[i]
        local b = pts[i + 1]
        local len = seg[i]
        local remaining = target - consumed
        if remaining <= 0 then break end
        if remaining >= len then
            love.graphics.line(
                x + a[1] * s, y + a[2] * s,
                x + b[1] * s, y + b[2] * s)
        else
            local k = remaining / len
            love.graphics.line(
                x + a[1] * s, y + a[2] * s,
                x + (a[1] + (b[1] - a[1]) * k) * s,
                y + (a[2] + (b[2] - a[2]) * k) * s)
        end
        consumed = consumed + len
    end
    love.graphics.setLineWidth(prev_lw)
end

local CIRCLE_MIN_SEGMENTS = 24

local function circle_segments(radius)
    return math.max(CIRCLE_MIN_SEGMENTS, math.floor(radius * 6 + 0.5))
end

function M.dot(x, y, size, color)
    love.graphics.setColor(color)
    local r = size / 2
    love.graphics.circle("fill", x + r, y + r, r, circle_segments(r))
end

function M.triangle_up(x, y, size, color)
    love.graphics.setColor(color)
    local cx = x + size / 2
    love.graphics.polygon("fill",
        cx, y,
        x + size, y + size,
        x, y + size)
end

function M.triangle_down(x, y, size, color)
    love.graphics.setColor(color)
    local cx = x + size / 2
    love.graphics.polygon("fill",
        x, y,
        x + size, y,
        cx, y + size)
end

function M.star(x, y, size, color)
    love.graphics.setColor(color)
    local cx, cy = x + size / 2, y + size / 2
    local outer = size / 2
    local inner = outer * 0.45
    local pts = {}
    for i = 0, 9 do
        local angle = -math.pi / 2 + i * math.pi / 5
        local r = (i % 2 == 0) and outer or inner
        table.insert(pts, cx + math.cos(angle) * r)
        table.insert(pts, cy + math.sin(angle) * r)
    end
    love.graphics.polygon("fill", pts)
end

function M.diamond(x, y, size, color)
    love.graphics.setColor(color)
    local cx, cy = x + size / 2, y + size / 2
    local r = size / 2
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
        x + size, y + size / 2,
        x, y + size)
end

-- Stop / square — used to swap in for `play` when monitoring is active.
function M.stop(x, y, size, color)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y, size, size)
end

return M
