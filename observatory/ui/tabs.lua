-- Tab strip — fixed-width tabs along a horizontal rule, with the active
-- selection marked by a 2px accent indicator that slides between tabs on
-- click.

local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local anim = require("observatory.ui.animation")
local text = require("observatory.ui.text")

local M = {}

local function ensure(state, n)
    state = state or {}
    state.selected = state.selected or 1
    state.indicator_x = state.indicator_x or anim.tween(0)
    state.indicator_w = state.indicator_w or anim.tween(0)
    state.label_color = state.label_color or {}
    for i = 1, n do
        state.label_color[i] = state.label_color[i] or anim.tween_color(theme.colors.text_dim)
    end
    return state
end

-- opts:
--   tab_w (default 160), pad_x (default 14), font, selected (force-set).
function M.draw(state, labels, x, y, w, h, opts)
    opts = opts or {}
    state = ensure(state, #labels)
    local font = opts.font or theme.font("main", 13)
    local tab_w = opts.tab_w or 160
    local pad_x = opts.pad_x or 14

    if opts.selected and opts.selected ~= state.selected then
        state.selected = opts.selected
    end
    if state.selected > #labels then state.selected = #labels end
    if state.selected < 1 then state.selected = 1 end

    for i = 1, #labels do
        local tx = x + pad_x + (i - 1) * tab_w
        if input.clicked_in(tx, y, tab_w, h) then
            state.selected = i
        end
    end

    local sel_x = x + pad_x + (state.selected - 1) * tab_w
    anim.go(state.indicator_x, sel_x, theme.motion.slow, theme.motion.overshoot)
    anim.go(state.indicator_w, tab_w, theme.motion.slow, theme.motion.overshoot)
    anim.update(state.indicator_x, input.dt)
    anim.update(state.indicator_w, input.dt)

    for i = 1, #labels do
        local target = (i == state.selected)
            and theme.colors.text
            or theme.colors.text_dim
        anim.go_color(state.label_color[i], target, theme.motion.fast, theme.motion.smooth)
        anim.update_color(state.label_color[i], input.dt)
    end

    for i, label in ipairs(labels) do
        local lbl = type(label) == "table" and label[2] or label
        local tx = x + pad_x + (i - 1) * tab_w
        text.draw_v_center(lbl, tx, y, h, {
            font = font,
            color = anim.color_value(state.label_color[i]),
            align = "center",
            width = tab_w,
        })
    end

    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", x, y + h - 1, w, 1)

    love.graphics.setColor(theme.colors.accent)
    love.graphics.rectangle("fill",
        state.indicator_x.value, y + h - 2,
        state.indicator_w.value, 2)

    return state.selected, state
end

return M
