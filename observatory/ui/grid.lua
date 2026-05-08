local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local text = require("observatory.ui.text")

local M = {}

local CELL_PADDING_X = 6
local HEADER_LETTER_EM = 0.08

local function fit_text(s, font, em, max_w)
    if not s or s == "" then return "" end
    if max_w <= 0 then return "" end
    if text.width(s, font, em) <= max_w then return s end
    return text.truncate_right(s, font, max_w, em)
end

local function draw_empty_state(font, x, y, w, h)
    text.draw("(no data)", x, y + h / 2 - font:getHeight() / 2, {
        font = font, color = theme.colors.text_faint,
        align = "center", width = w,
    })
end

local function handle_wheel_scroll(state, x, y, w, h, row_h)
    if input.in_rect(x, y, w, h) and input.wheel_dy ~= 0 then
        state.scroll = state.scroll - input.wheel_dy * row_h * 2
    end
end

local function draw_header(cols, ctx, header_color)
    love.graphics.setColor(header_color or theme.colors.panel)
    love.graphics.rectangle("fill", ctx.x, ctx.y, ctx.w, ctx.row_h)
    for i, col in ipairs(cols) do
        local label = fit_text(col, ctx.font, HEADER_LETTER_EM, ctx.cell_text_w)
        text.draw_v_center(label, ctx.x + (i - 1) * ctx.col_w + CELL_PADDING_X,
            ctx.y, ctx.row_h, {
                font = ctx.font, color = theme.colors.text_faint,
                letter_em = HEADER_LETTER_EM,
            })
    end
    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", ctx.x, ctx.y + ctx.row_h - 1, ctx.w, 1)
end

local function draw_row(r, cols, ctx, ry, row_color)
    for ci, col in ipairs(cols) do
        local val = r[col]
        if val == nil then val = "" else val = tostring(val) end
        val = fit_text(val, ctx.font, 0, ctx.cell_text_w)
        text.draw_v_center(val, ctx.x + (ci - 1) * ctx.col_w + CELL_PADDING_X,
            ry, ctx.row_h, {
                font = ctx.font, color = row_color or theme.colors.text,
            })
    end
end

local function draw_body(rows, cols, state, ctx, opts)
    love.graphics.setScissor(ctx.x, ctx.view_y, ctx.w, ctx.view_h)
    local visible_top = ctx.view_y - state.scroll
    for i, r in ipairs(rows) do
        local ry = visible_top + (i - 1) * ctx.row_h
        if ry + ctx.row_h >= ctx.view_y and ry <= ctx.view_y + ctx.view_h then
            if i % 2 == 0 then
                love.graphics.setColor(opts.alt_color or theme.colors.row_alt)
                love.graphics.rectangle("fill", ctx.x, ry, ctx.w, ctx.row_h)
            end
            draw_row(r, cols, ctx, ry, opts.row_color)
        end
    end
    love.graphics.setScissor()
end

local function clamp_scroll(state, content_h, view_h)
    local max_scroll = math.max(0, content_h - view_h)
    state.max_scroll = max_scroll
    if state.scroll > max_scroll then state.scroll = max_scroll end
    if state.scroll < 0 then state.scroll = 0 end
    return max_scroll
end

local function draw_scrollbar(state, max_scroll, view_y, view_h, content_h, x, w)
    if max_scroll <= 0 then return end
    local bar_h = math.max(20, view_h * (view_h / content_h))
    local bar_y = view_y + (view_h - bar_h) * (state.scroll / max_scroll)
    love.graphics.setColor(theme.colors.rule_strong)
    love.graphics.rectangle("fill", x + w - 4, bar_y, 3, bar_h)
end

function M.draw(state, grid, x, y, w, h, opts)
    state = state or {}
    state.scroll = state.scroll or 0
    opts = opts or {}

    local font = opts.font or theme.font("mono", 11)
    local row_h = font:getHeight() + 8
    local cols = grid and grid.columns or {}
    local rows = grid and grid.rows or {}
    local n_cols = #cols

    if n_cols == 0 then
        draw_empty_state(font, x, y, w, h)
        return state
    end

    handle_wheel_scroll(state, x, y, w, h, row_h)

    local col_w = w / n_cols
    local ctx = {
        font         = font,
        x            = x,
        y            = y,
        w            = w,
        row_h        = row_h,
        col_w        = col_w,
        cell_text_w  = math.max(0, col_w - CELL_PADDING_X * 2),
        view_y       = y + row_h,
        view_h       = h - row_h,
    }

    draw_header(cols, ctx, opts.header_color)

    local content_h = #rows * row_h

    draw_body(rows, cols, state, ctx, opts)

    local max_scroll = clamp_scroll(state, content_h, ctx.view_h)
    draw_scrollbar(state, max_scroll, ctx.view_y, ctx.view_h, content_h, x, w)

    return state
end

return M
