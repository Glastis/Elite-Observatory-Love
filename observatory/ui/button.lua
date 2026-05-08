-- Generic flat button. Renders an animated hover background plus an
-- optional centred label, and reports clicks to the caller. State (the
-- hover tween) is held by the caller so animation persists between frames.

local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local anim = require("observatory.ui.animation")
local text = require("observatory.ui.text")

local M = {}

local function ensure(state)
    state = state or {}
    if state.hover == nil then state.hover = anim.tween(0) end
    return state
end

-- opts (all optional):
--   label, font, letter_em, color, bg, hover_bg, hover_color,
--   border, right_border, prefix(fn), prefix_w, prefix_gap, active.
function M.draw(state, x, y, w, h, opts)
    state = ensure(state)
    opts = opts or {}

    local hovered = input.in_rect(x, y, w, h)
    local target = (hovered or opts.active) and 1 or 0
    anim.go(state.hover, target, theme.motion.fast, theme.motion.smooth)
    anim.update(state.hover, input.dt)
    local k = state.hover.value

    local function blend(a, b)
        if not b then return a end
        return {
            a[1] + (b[1] - a[1]) * k,
            a[2] + (b[2] - a[2]) * k,
            a[3] + (b[3] - a[3]) * k,
            (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * k,
        }
    end

    if opts.bg or opts.hover_bg then
        local base = opts.bg or { 0, 0, 0, 0 }
        local fill = blend(base, opts.hover_bg or theme.colors.seg_hover)
        love.graphics.setColor(fill)
        love.graphics.rectangle("fill", x, y, w, h)
    end

    if opts.border then
        love.graphics.setColor(opts.border)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
    end
    if opts.right_border then
        love.graphics.setColor(opts.right_border)
        love.graphics.rectangle("fill", x + w - 1, y, 1, h)
    end

    local label_color = blend(opts.color or theme.colors.text, opts.hover_color)

    local font = opts.font or theme.font("main", 13)
    love.graphics.setFont(font)
    local lw = opts.label and text.width(opts.label, font, opts.letter_em or 0) or 0
    local prefix_w = opts.prefix and (opts.prefix_w or font:getHeight() * 0.7) or 0
    local prefix_gap = opts.prefix and (opts.prefix_gap or 6) or 0
    local content_w = prefix_w + prefix_gap + lw
    local cx = x + (w - content_w) / 2

    if opts.prefix then
        opts.prefix(cx, y + h / 2 - prefix_w / 2, prefix_w, label_color)
    end
    if opts.label then
        text.draw_v_center(opts.label, cx + prefix_w + prefix_gap, y, h, {
            font = font,
            color = label_color,
            letter_em = opts.letter_em,
        })
    end

    return input.clicked_in(x, y, w, h), state
end

return M
