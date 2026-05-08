-- Mini toggle switch. Round-cap track with a sliding knob; track colour
-- fades between accent and a faint white when the value flips, knob position
-- uses the back_out easing for a slight overshoot.

local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local anim = require("observatory.ui.animation")

local M = {}

local function ensure(state, value)
    state = state or {}
    if state.knob == nil then
        state.knob = anim.tween(value and 1 or 0)
    end
    if state.track == nil then
        state.track = anim.tween_color(
            value and theme.colors.accent or theme.colors.track_off)
    end
    if state.knob_color == nil then
        state.knob_color = anim.tween_color(
            value and theme.colors.knob_on or theme.colors.knob_off)
    end
    return state
end

-- opts: w, h (defaults 26 × 14).
function M.draw(state, value, x, y, opts)
    opts = opts or {}
    state = ensure(state, value)
    local w = opts.w or 26
    local h = opts.h or 14

    anim.go(state.knob, value and 1 or 0,
        theme.motion.normal, theme.motion.overshoot)
    anim.go_color(state.track,
        value and theme.colors.accent or theme.colors.track_off,
        theme.motion.normal, theme.motion.smooth)
    anim.go_color(state.knob_color,
        value and theme.colors.knob_on or theme.colors.knob_off,
        theme.motion.normal, theme.motion.smooth)

    anim.update(state.knob, input.dt)
    anim.update_color(state.track, input.dt)
    anim.update_color(state.knob_color, input.dt)

    local r = h / 2
    love.graphics.setColor(anim.color_value(state.track))
    love.graphics.rectangle("fill", x, y, w, h, r, r)

    local pad = 1.5
    local knob_d = h - pad * 2
    local kx_off = (w - knob_d - pad * 2) * state.knob.value
    love.graphics.setColor(anim.color_value(state.knob_color))
    love.graphics.circle("fill",
        x + pad + knob_d / 2 + kx_off,
        y + pad + knob_d / 2,
        knob_d / 2)
end

return M
