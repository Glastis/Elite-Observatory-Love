-- Generic data grid. Renders a header row + scrollable data rows, with
-- alternating row backgrounds, vertical clipping and a thin scroll
-- indicator. The grid takes a simple { columns = {...}, rows = {...} }
-- shape; rows are tables keyed by column name.
--
-- Scroll position is held by the caller in the state slot so the same grid
-- keeps its scroll across frames and across re-orderings.

local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local text = require("observatory.ui.text")

local M = {}

-- opts: header_color, row_color, alt_color, font.
-- state fields touched: scroll, max_scroll.
function M.draw(state, grid, x, y, w, h, opts)
    state = state or {}
    state.scroll = state.scroll or 0
    opts = opts or {}

    local font = opts.font or theme.font("mono", 11)
    local row_h = font:getHeight() + 8
    local cols = grid and grid.columns or {}
    local rows = grid and grid.rows or {}
    local n_cols = #cols

    -- Empty-state.
    if n_cols == 0 then
        text.draw("(no data)", x, y + h / 2 - font:getHeight() / 2, {
            font = font, color = theme.colors.text_faint,
            align = "center", width = w,
        })
        return state
    end

    -- Wheel scroll when pointer is inside the grid.
    if input.in_rect(x, y, w, h) and input.wheel_dy ~= 0 then
        state.scroll = state.scroll - input.wheel_dy * row_h * 2
    end

    local col_w = w / n_cols

    -- Header.
    love.graphics.setColor(opts.header_color or theme.colors.panel)
    love.graphics.rectangle("fill", x, y, w, row_h)
    for i, col in ipairs(cols) do
        text.draw_v_center(col, x + (i - 1) * col_w + 6, y, row_h, {
            font = font, color = theme.colors.text_faint,
            letter_em = 0.08,
        })
    end
    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", x, y + row_h - 1, w, 1)

    -- Body — clipped & scrolled.
    local total = #rows
    local content_h = total * row_h
    local view_y = y + row_h
    local view_h = h - row_h

    love.graphics.setScissor(x, view_y, w, view_h)
    local visible_top = view_y - state.scroll
    for i, r in ipairs(rows) do
        local ry = visible_top + (i - 1) * row_h
        if ry + row_h >= view_y and ry <= view_y + view_h then
            if i % 2 == 0 then
                love.graphics.setColor(opts.alt_color or theme.colors.row_alt)
                love.graphics.rectangle("fill", x, ry, w, row_h)
            end
            for ci, col in ipairs(cols) do
                local val = r[col]
                if val == nil then val = "" else val = tostring(val) end
                text.draw_v_center(val, x + (ci - 1) * col_w + 6, ry, row_h, {
                    font = font, color = opts.row_color or theme.colors.text,
                })
            end
        end
    end
    love.graphics.setScissor()

    local max_scroll = math.max(0, content_h - view_h)
    state.max_scroll = max_scroll
    if state.scroll > max_scroll then state.scroll = max_scroll end
    if state.scroll < 0 then state.scroll = 0 end

    if max_scroll > 0 then
        local bar_h = math.max(20, view_h * (view_h / content_h))
        local bar_y = view_y + (view_h - bar_h) * (state.scroll / max_scroll)
        love.graphics.setColor(theme.colors.rule_strong)
        love.graphics.rectangle("fill", x + w - 4, bar_y, 3, bar_h)
    end

    return state
end

return M
