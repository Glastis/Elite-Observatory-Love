local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local anim = require("observatory.ui.animation")
local text = require("observatory.ui.text")
local button = require("observatory.ui.button")

local M = {}

local LETTER_EM = 0.14
local EDGE_LABEL = "..."
local EDGE_LETTER_EM = 0.18
local INDICATOR_INSET_Y = 1
local NO_PRIMARY_KEY = "__none__"

local ITEM_VISUALS = {
    primary = {
        color = theme.colors.accent,
        hover_color = theme.colors.text,
        hover_bg = theme.with_alpha(theme.colors.accent, 0.24),
    },
    disabled = {
        color = theme.colors.text_faint,
    },
    normal = {
        color = theme.colors.text_dim,
        hover_color = theme.colors.text,
        hover_bg = theme.colors.seg_hover,
    },
}

local function item_visual_kind(item)
    if item.primary then return "primary" end
    if item.disabled then return "disabled" end
    return "normal"
end

local function default_pad_x()
    return theme.metrics.seg_pad_x
end

local function ensure_state(state)
    state = state or {}
    state.items = state.items or {}
    state.start_index = state.start_index or 1
    state.indicator_x = state.indicator_x or anim.tween(0)
    state.indicator_w = state.indicator_w or anim.tween(0)
    state.indicator_a = state.indicator_a or anim.tween(0)
    state.prev_btn = state.prev_btn or {}
    state.next_btn = state.next_btn or {}
    state.last_primary_key = state.last_primary_key or NO_PRIMARY_KEY
    return state
end

local function ensure_item_states(state, n)
    for i = 1, n do
        state.items[i] = state.items[i] or {}
    end
end

local function item_width(it, font)
    local pad = (it.pad_x or default_pad_x()) * 2
    local label_w = it.label
        and text.width(it.label, font, it.letter_em or LETTER_EM) or 0
    return pad + label_w
end

local function edge_width(font)
    return default_pad_x() * 2 + text.width(EDGE_LABEL, font, EDGE_LETTER_EM)
end

local function find_primary_index(items)
    for i, it in ipairs(items) do
        if it.primary then return i end
    end
    return nil
end

local function primary_key_of(items, idx)
    if not idx then return NO_PRIMARY_KEY end
    local it = items[idx]
    return it.key or it.label or NO_PRIMARY_KEY
end

local function fit_window(widths, start_idx, available)
    local end_idx = start_idx - 1
    local used = 0
    for i = start_idx, #widths do
        if used + widths[i] > available then break end
        used = used + widths[i]
        end_idx = i
    end
    return end_idx, used
end

local function compute_window(widths, start_idx, max_w, edge_w)
    local n = #widths
    if n == 0 then return start_idx, 0, false, false, 0 end
    if start_idx < 1 then start_idx = 1 end
    if start_idx > n then start_idx = n end

    local has_prev = start_idx > 1
    local reserve = has_prev and edge_w or 0
    local end_idx, used = fit_window(widths, start_idx, max_w - reserve)
    local has_next = end_idx < n
    if not has_next then
        return start_idx, end_idx, has_prev, false, used
    end
    end_idx, used = fit_window(widths, start_idx, max_w - reserve - edge_w)
    return start_idx, end_idx, has_prev, end_idx < n, used
end

local function clamp_start(state, n)
    if n == 0 then state.start_index = 1; return end
    if state.start_index < 1 then state.start_index = 1 end
    if state.start_index > n then state.start_index = n end
end

local function scroll_primary_into_view(state, widths, primary_idx, max_w, edge_w)
    if not primary_idx then return end
    local n = #widths
    if state.start_index > primary_idx then
        state.start_index = primary_idx
        return
    end
    while state.start_index <= n do
        local _, end_idx = compute_window(widths, state.start_index,
            max_w, edge_w)
        if primary_idx <= end_idx then return end
        state.start_index = state.start_index + 1
    end
    state.start_index = math.max(1, primary_idx)
end

local function maybe_scroll_to_primary(state, items, widths, max_w, edge_w)
    local primary_idx = find_primary_index(items)
    local current_key = primary_key_of(items, primary_idx)
    if current_key ~= state.last_primary_key then
        scroll_primary_into_view(state, widths, primary_idx, max_w, edge_w)
    end
    state.last_primary_key = current_key
    return primary_idx
end

local function draw_edge_button(state_btn, x, y, w, h, font, on_click)
    local was_clicked = button.draw(state_btn, x, y, w, h, {
        label = EDGE_LABEL,
        font = font,
        letter_em = EDGE_LETTER_EM,
        color = theme.colors.text_dim,
        hover_color = theme.colors.text,
        hover_bg = theme.colors.seg_hover,
    })
    if was_clicked and on_click then on_click() end
end

local function draw_separator(x, y, h)
    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", x, y, 1, h)
end

local function draw_item_button(state_btn, item, x, y, w, h, font, draw_right_sep)
    local visual = ITEM_VISUALS[item_visual_kind(item)]
    local was_clicked = button.draw(state_btn, x, y, w, h, {
        label = item.label,
        font = font,
        letter_em = item.letter_em or LETTER_EM,
        color = visual.color,
        hover_color = visual.hover_color,
        hover_bg = visual.hover_bg,
        right_border = draw_right_sep and theme.colors.rule or nil,
    })
    if was_clicked and not item.disabled and item.on_click then
        item.on_click()
    end
    return was_clicked
end

local function visible_primary_x(start_x, widths, start_idx, primary_idx)
    local px = start_x
    for i = start_idx, primary_idx - 1 do
        px = px + widths[i]
    end
    return px
end

local function update_indicator(state, target_x, target_w, visible)
    anim.go(state.indicator_x, target_x,
        theme.motion.slow, theme.motion.overshoot)
    anim.go(state.indicator_w, target_w,
        theme.motion.slow, theme.motion.overshoot)
    anim.go(state.indicator_a, visible and 1 or 0,
        theme.motion.fast, theme.motion.smooth)
    anim.update(state.indicator_x, input.dt)
    anim.update(state.indicator_w, input.dt)
    anim.update(state.indicator_a, input.dt)
end

local function draw_indicator(state, y, h)
    if state.indicator_a.value <= 0 then return end
    local base = theme.colors.accent_soft
    local fill = {
        base[1], base[2], base[3],
        (base[4] or 1) * state.indicator_a.value,
    }
    love.graphics.setColor(fill)
    love.graphics.rectangle("fill",
        state.indicator_x.value, y + INDICATOR_INSET_Y,
        state.indicator_w.value, h - INDICATOR_INSET_Y * 2)
end

local function draw_visible_items(state, items, widths, ctx)
    local cursor = ctx.items_x
    local clicked
    for i = ctx.start_idx, ctx.end_idx do
        local iw = widths[i]
        local need_sep = (i ~= ctx.end_idx) or ctx.has_next
        if draw_item_button(state.items[i], items[i],
                cursor, ctx.y, iw, ctx.h, ctx.font, need_sep) then
            clicked = i
        end
        cursor = cursor + iw
    end
    return clicked, cursor
end

local function compute_layout(widths, max_w, edge_w, start_idx)
    local s, e, has_prev, has_next, items_w =
        compute_window(widths, start_idx, max_w, edge_w)
    local total_w = items_w
        + (has_prev and edge_w or 0)
        + (has_next and edge_w or 0)
    return {
        start_idx = s, end_idx = e,
        has_prev = has_prev, has_next = has_next,
        items_w = items_w, total_w = total_w,
    }
end

local function step_start(state, delta, n)
    state.start_index = math.max(1, math.min(n, state.start_index + delta))
end

local function paint_indicator(state, items, widths, ctx)
    local primary_idx = ctx.primary_idx
    local visible = primary_idx
        and primary_idx >= ctx.start_idx
        and primary_idx <= ctx.end_idx
    if visible then
        local px = visible_primary_x(ctx.items_x, widths,
            ctx.start_idx, primary_idx)
        update_indicator(state, px, widths[primary_idx], true)
    else
        update_indicator(state,
            state.indicator_x.target,
            state.indicator_w.target,
            false)
    end
    draw_indicator(state, ctx.y, ctx.h)
end

function M.draw(state, items, x, y, opts)
    opts = opts or {}
    state = ensure_state(state)
    ensure_item_states(state, #items)

    local font = opts.font or theme.font("mono", 11)
    local h = opts.h or 28
    local max_w = opts.max_w or math.huge
    local border = opts.border or theme.colors.rule

    local widths = {}
    for i, it in ipairs(items) do widths[i] = item_width(it, font) end
    clamp_start(state, #items)

    local edge_w = edge_width(font)
    local primary_idx = maybe_scroll_to_primary(state, items, widths,
        max_w, edge_w)
    local layout = compute_layout(widths, max_w, edge_w, state.start_index)

    love.graphics.setColor(border)
    love.graphics.rectangle("line",
        x + 0.5, y + 0.5, layout.total_w - 1, h - 1)

    local cursor = x
    if layout.has_prev then
        draw_edge_button(state.prev_btn, cursor, y, edge_w, h, font, function()
            step_start(state, -1, #items)
        end)
        draw_separator(cursor + edge_w - 1, y, h)
        cursor = cursor + edge_w
    end

    local items_x = cursor
    local ctx = {
        font = font, y = y, h = h,
        items_x = items_x,
        start_idx = layout.start_idx,
        end_idx = layout.end_idx,
        has_next = layout.has_next,
        primary_idx = primary_idx,
    }

    paint_indicator(state, items, widths, ctx)
    local clicked, after_items_x = draw_visible_items(state, items, widths, ctx)
    cursor = after_items_x

    if layout.has_next then
        draw_separator(cursor, y, h)
        draw_edge_button(state.next_btn, cursor, y, edge_w, h, font, function()
            step_start(state, 1, #items)
        end)
    end

    return layout.total_w, clicked, state, h
end

return M
