-- Animated checkbox row. The check tick draws itself in along its path,
-- and the row body fades to a soft hover background. Toggling is reported
-- back to the caller — the value itself lives wherever the caller stores it.

local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local anim = require("observatory.ui.animation")
local icon = require("observatory.ui.icon")
local text = require("observatory.ui.text")
local row = require("observatory.ui.row")

local M = {}

local function ensure(state, value)
    state = state or {}
    state.row = state.row or {}
    if state.tick == nil then
        state.tick = anim.tween(value and 1 or 0)
    end
    if state.label_color == nil then
        state.label_color = anim.tween_color(
            value and theme.colors.text or theme.colors.text_dim)
    end
    if state.box_border == nil then
        state.box_border = anim.tween_color(
            value and theme.colors.accent or theme.colors.text_faint)
    end
    if state.box_fill == nil then
        state.box_fill = anim.tween_color(
            value and theme.colors.accent_soft or { 0, 0, 0, 0 })
    end
    return state
end

-- opts: font, letter_em, row_h (default 30), box (default 16).
-- Returns new value, toggled (bool), state.
function M.draw(state, label, value, x, y, w, opts)
    opts = opts or {}
    state = ensure(state, value)
    local font = opts.font or theme.font("mono", 12)
    local row_h = opts.row_h or 30
    local box = opts.box or 16

    local _, clicked = row.draw(state.row, x, y, w, row_h, {
        bottom_rule = theme.colors.rule,
    })

    local toggled = false
    if clicked then
        value = not value
        toggled = true
    end

    anim.go(state.tick, value and 1 or 0,
        theme.motion.normal, theme.motion.smooth)
    anim.go_color(state.label_color,
        value and theme.colors.text or theme.colors.text_dim,
        theme.motion.fast, theme.motion.smooth)
    anim.go_color(state.box_border,
        value and theme.colors.accent or theme.colors.text_faint,
        theme.motion.fast, theme.motion.smooth)
    anim.go_color(state.box_fill,
        value and theme.colors.accent_soft or { 0, 0, 0, 0 },
        theme.motion.fast, theme.motion.smooth)

    anim.update(state.tick, input.dt)
    anim.update_color(state.label_color, input.dt)
    anim.update_color(state.box_border, input.dt)
    anim.update_color(state.box_fill, input.dt)

    local box_x = x + 4
    local box_y = y + (row_h - box) / 2
    love.graphics.setColor(anim.color_value(state.box_fill))
    love.graphics.rectangle("fill", box_x, box_y, box, box)
    love.graphics.setColor(anim.color_value(state.box_border))
    love.graphics.rectangle("line", box_x + 0.5, box_y + 0.5, box - 1, box - 1)

    -- Fade the tick alpha as progress → 0 so the tail end of the path
    -- stroke doesn't leave a visible stub at the start of the tick when
    -- unchecking (the path-trim animation always retracts from the end).
    local inset = 3
    local accent = theme.colors.accent
    local tick_alpha_k = math.min(1, state.tick.value * 5)
    icon.check(box_x + inset, box_y + inset, box - inset * 2,
        { accent[1], accent[2], accent[3], (accent[4] or 1) * tick_alpha_k },
        state.tick.value, 1.6)

    text.draw_v_center(label, box_x + box + 12, y, row_h, {
        font = font,
        color = anim.color_value(state.label_color),
        letter_em = opts.letter_em or 0.02,
    })

    return value, toggled, state
end

return M
