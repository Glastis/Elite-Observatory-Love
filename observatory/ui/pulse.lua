-- Pulsing label — a leading dot + caption whose alpha breathes between
-- 0.5 and 1.0 over a configurable period.

local theme = require("observatory.ui.theme")
local text = require("observatory.ui.text")
local icon = require("observatory.ui.icon")

local M = {}

function M.alpha(period)
    period = period or theme.motion.pulse_period
    local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
    local k = math.abs(((t / period) % 1) * 2 - 1)
    return 0.5 + 0.5 * k
end

function M.color(base, period)
    local a = M.alpha(period)
    return { base[1], base[2], base[3], (base[4] or 1) * a }
end

-- opts: color, font, letter_em, period, dot_size, gap.
function M.draw(caption, x, y, opts)
    opts = opts or {}
    local font = opts.font or theme.font("mono", 10)
    local color = opts.color or theme.colors.success
    local period = opts.period or theme.motion.pulse_period
    local em = opts.letter_em or 0.08

    local pulsed = M.color(color, period)

    local dot_size = opts.dot_size or 6
    local gap = opts.gap or 6
    local center_y = y + font:getHeight() / 2
    icon.dot(x, center_y - dot_size / 2, dot_size, pulsed)

    local cap_x = x + dot_size + gap
    text.draw(caption, cap_x, y, {
        font = font,
        color = pulsed,
        letter_em = em,
    })

    return dot_size + gap + text.width(caption, font, em)
end

return M
