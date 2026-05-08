-- Row — a hover-tracked, full-width clickable container. Wraps its content
-- in an animated background fade. Pure container: it doesn't render the
-- inside, it just paints the background and reports hover/click for the
-- caller to decorate however it wants.

local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local anim = require("observatory.ui.animation")

local M = {}

local function ensure(state)
    if state.hover_alpha == nil then
        state.hover_alpha = anim.tween(0)
    end
    return state
end

-- opts: bg, bottom_rule, cursor.
-- Returns hovered, clicked, state.
function M.draw(state, x, y, w, h, opts)
    state = ensure(state or {})
    opts = opts or {}

    local hovered = input.in_rect(x, y, w, h)
    local target = hovered and 1 or 0
    anim.go(state.hover_alpha, target, theme.motion.fast, theme.motion.smooth)
    anim.update(state.hover_alpha, input.dt)

    if state.hover_alpha.value > 0.001 then
        local bg = opts.bg or theme.colors.row_hover
        love.graphics.setColor(bg[1], bg[2], bg[3],
            (bg[4] or 1) * state.hover_alpha.value)
        love.graphics.rectangle("fill", x, y, w, h)
    end

    if opts.bottom_rule ~= false then
        local rule = opts.bottom_rule or theme.colors.rule
        love.graphics.setColor(rule)
        love.graphics.rectangle("fill", x, y + h - 1, w, 1)
    end

    local clicked = input.clicked_in(x, y, w, h)
    return hovered, clicked, state
end

return M
