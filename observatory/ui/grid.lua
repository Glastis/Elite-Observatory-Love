local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local text = require("observatory.ui.text")
local icon = require("observatory.ui.icon")

local M = {}

local CELL_PADDING_X = 6
local HEADER_LETTER_EM = 0.08
local SORT_GLYPH_GAP = 4
local SORT_GLYPH_SCALE = 0.55
local ROW_VERTICAL_PADDING = 8
local WHEEL_ROWS_PER_TICK = 2
local ROW_STRIPE_PERIOD = 2
local ROW_STRIPE_OFFSET = 0
local SCROLLBAR_W = 3
local SCROLLBAR_RIGHT_INSET = 1
local SCROLLBAR_MIN_H = 20
local HEADER_RULE_H = 1
local DEFAULT_FONT_FAMILY = "mono"
local DEFAULT_FONT_SIZE = 11
local EMPTY_TABLE_TEXT = "(no data)"
local ALIGN_LEFT = "left"
local ALIGN_RIGHT = "right"

local SORT_GLYPHS = {
    ascending  = icon.triangle_up,
    descending = icon.triangle_down,
}
local UNIT_MULTIPLIERS = { K = 1e3, M = 1e6 }
local SORT_KEY_PATTERN = "^%-?(%d+%.?%d*)%s*([KM]?)"

local function fit_text(s, font, em, max_w)
    if not s or s == "" then
        return ""
    end
    if max_w <= 0 then
        return ""
    end
    if text.width(s, font, em) <= max_w then
        return s
    end
    return text.truncate_right(s, font, max_w, em)
end

local function sort_key(value)
    local str
    local num
    local suffix
    local n

    str = tostring(value or "")
    num, suffix = str:match(SORT_KEY_PATTERN)
    if not num or num == "" then
        return nil
    end
    n = tonumber(num)
    if not n then
        return nil
    end
    return n * (UNIT_MULTIPLIERS[suffix] or 1)
end

local function compare_values(a, b, is_ascending)
    local a_n
    local b_n
    local a_s
    local b_s

    a_n = sort_key(a)
    b_n = sort_key(b)
    if a_n and b_n then
        if is_ascending then
            return a_n < b_n
        end
        return a_n > b_n
    end
    if a_n then
        return is_ascending
    end
    if b_n then
        return not is_ascending
    end
    a_s = tostring(a or "")
    b_s = tostring(b or "")
    if is_ascending then
        return a_s < b_s
    end
    return a_s > b_s
end

local function sort_value_for(row, col)
    if row._raw and row._raw[col] ~= nil then
        return row._raw[col]
    end
    return row[col]
end

local function sorted_rows(rows, col, is_ascending)
    local copy

    copy = {}
    for i, r in ipairs(rows) do
        copy[i] = r
    end
    table.sort(copy, function(a, b)
        return compare_values(sort_value_for(a, col),
            sort_value_for(b, col), is_ascending)
    end)
    return copy
end

local function build_hierarchy_nodes(rows)
    local nodes
    local stack
    local current_node_id
    local depth
    local node_id
    local parent_idx

    nodes = {}
    stack = {}
    for i, row in ipairs(rows) do
        depth = row._depth or 0
        node_id = row._node_id or ("__row_" .. tostring(i))
        if node_id ~= current_node_id then
            while #stack > 0 and stack[#stack].depth >= depth do
                table.remove(stack)
            end
            parent_idx = #stack > 0 and stack[#stack].node_idx or nil
            table.insert(nodes, {
                depth        = depth,
                parent_idx   = parent_idx,
                row_indices  = { i },
            })
            table.insert(stack, { node_idx = #nodes, depth = depth })
            current_node_id = node_id
        else
            table.insert(nodes[#nodes].row_indices, i)
        end
    end
    return nodes
end

local function children_map_from_nodes(nodes)
    local children
    local roots

    children = {}
    roots = {}
    for i, node in ipairs(nodes) do
        if node.parent_idx then
            children[node.parent_idx] = children[node.parent_idx] or {}
            table.insert(children[node.parent_idx], i)
        else
            table.insert(roots, i)
        end
    end
    return roots, children
end

local function compute_effective_node_key(idx, own, children, computed, effective)
    local best
    local kid_key

    if computed[idx] then
        return effective[idx]
    end
    computed[idx] = true
    best = own[idx]
    for _, kid in ipairs(children[idx] or {}) do
        kid_key = compute_effective_node_key(kid, own, children, computed, effective)
        if kid_key and (best == nil or kid_key > best) then
            best = kid_key
        end
    end
    effective[idx] = best
    return best
end

local function effective_node_keys(nodes, children, rows, col)
    local own
    local computed
    local effective
    local first_row

    own = {}
    for i, node in ipairs(nodes) do
        first_row = rows[node.row_indices[1]]
        own[i] = sort_key(sort_value_for(first_row, col))
    end
    computed = {}
    effective = {}
    for i = 1, #nodes do
        compute_effective_node_key(i, own, children, computed, effective)
    end
    return effective
end

local function node_fallback_string(idx, nodes, rows, col)
    local first_row

    first_row = rows[nodes[idx].row_indices[1]]
    return tostring(sort_value_for(first_row, col) or "")
end

local function compare_nodes(a, b, ctx)
    local ka
    local kb
    local sa
    local sb

    ka = ctx.effective[a]
    kb = ctx.effective[b]
    if ka and kb then
        if ctx.is_ascending then
            return ka < kb
        end
        return ka > kb
    end
    if ka then
        return ctx.is_ascending
    end
    if kb then
        return not ctx.is_ascending
    end
    sa = node_fallback_string(a, ctx.nodes, ctx.rows, ctx.col)
    sb = node_fallback_string(b, ctx.nodes, ctx.rows, ctx.col)
    if ctx.is_ascending then
        return sa < sb
    end
    return sa > sb
end

local function emit_node(output, nodes, children, rows, node_idx)
    local kids

    for _, ri in ipairs(nodes[node_idx].row_indices) do
        table.insert(output, rows[ri])
    end
    kids = children[node_idx]
    if not kids then
        return
    end
    for _, j in ipairs(kids) do
        emit_node(output, nodes, children, rows, j)
    end
end

local function sorted_hierarchical_rows(rows, col, is_ascending)
    local nodes
    local roots
    local children
    local effective
    local ctx
    local output

    nodes = build_hierarchy_nodes(rows)
    roots, children = children_map_from_nodes(nodes)
    effective = effective_node_keys(nodes, children, rows, col)
    ctx = {
        effective    = effective,
        nodes        = nodes,
        rows         = rows,
        col          = col,
        is_ascending = is_ascending,
    }
    table.sort(roots, function(a, b) return compare_nodes(a, b, ctx) end)
    for _, kids in pairs(children) do
        table.sort(kids, function(a, b) return compare_nodes(a, b, ctx) end)
    end
    output = {}
    for _, root in ipairs(roots) do
        emit_node(output, nodes, children, rows, root)
    end
    return output
end

local function is_hierarchical(rows)
    for _, row in ipairs(rows) do
        if row._depth ~= nil then
            return true
        end
    end
    return false
end

local function sort_direction_key(state)
    if state.sort_ascending then
        return "ascending"
    end
    return "descending"
end

local function header_sort_glyph(col, state)
    if state.sort_col ~= col then
        return nil
    end
    return SORT_GLYPHS[sort_direction_key(state)]
end

local function toggle_sort(state, col)
    if state.sort_col == col then
        state.sort_ascending = not state.sort_ascending
    else
        state.sort_col = col
        state.sort_ascending = true
    end
    state.scroll = 0
end

local function draw_empty_state(font, x, y, w, h)
    text.draw(EMPTY_TABLE_TEXT, x, y + h / 2 - font:getHeight() / 2, {
        font = font, color = theme.colors.text_faint,
        align = "center", width = w,
    })
end

local function handle_wheel_scroll(state, x, y, w, h, row_h)
    if input.in_rect(x, y, w, h) and input.wheel_dy ~= 0 then
        state.scroll = state.scroll - input.wheel_dy * row_h * WHEEL_ROWS_PER_TICK
    end
end

local function handle_header_click(state, col, hx, hy, hw, hh)
    if not input.clicked_in(hx, hy, hw, hh) then
        return
    end
    toggle_sort(state, col)
end

local function draw_sort_glyph(glyph, ctx, hx, col_align, label_w)
    local glyph_size
    local gy
    local gx

    glyph_size = math.floor(ctx.font:getHeight() * SORT_GLYPH_SCALE)
    gy = ctx.y + (ctx.row_h - glyph_size) / 2
    if col_align == ALIGN_RIGHT then
        gx = hx + CELL_PADDING_X + ctx.cell_text_w - label_w - SORT_GLYPH_GAP - glyph_size
    else
        gx = hx + CELL_PADDING_X + label_w + SORT_GLYPH_GAP
    end
    glyph(gx, gy, glyph_size, theme.colors.text_faint)
end

local function draw_header_cell(col, ctx, state, hx)
    local glyph
    local glyph_size
    local reserved
    local label
    local col_align
    local label_w

    handle_header_click(state, col, hx, ctx.y, ctx.col_w, ctx.row_h)
    glyph = header_sort_glyph(col, state)
    glyph_size = math.floor(ctx.font:getHeight() * SORT_GLYPH_SCALE)
    reserved = glyph and (glyph_size + SORT_GLYPH_GAP) or 0
    label = fit_text(col, ctx.font, HEADER_LETTER_EM,
        math.max(0, ctx.cell_text_w - reserved))
    col_align = ctx.align_by_col[col] or ALIGN_LEFT
    text.draw_v_center(label, hx + CELL_PADDING_X, ctx.y, ctx.row_h, {
        font = ctx.font, color = theme.colors.text_faint,
        letter_em = HEADER_LETTER_EM,
        align = col_align,
        width = ctx.cell_text_w,
    })
    if not glyph then
        return
    end
    label_w = text.width(label, ctx.font, HEADER_LETTER_EM)
    draw_sort_glyph(glyph, ctx, hx, col_align, label_w)
end

local function draw_header(cols, ctx, state, header_color)
    local hx

    love.graphics.setColor(header_color or theme.colors.panel)
    love.graphics.rectangle("fill", ctx.x, ctx.y, ctx.w, ctx.row_h)
    for i, col in ipairs(cols) do
        hx = ctx.x + (i - 1) * ctx.col_w
        draw_header_cell(col, ctx, state, hx)
    end
    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", ctx.x, ctx.y + ctx.row_h - HEADER_RULE_H,
        ctx.w, HEADER_RULE_H)
end

local function as_display_string(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function draw_row(r, cols, ctx, ry, row_color)
    local val

    for ci, col in ipairs(cols) do
        val = as_display_string(r[col])
        val = fit_text(val, ctx.font, 0, ctx.cell_text_w)
        text.draw_v_center(val, ctx.x + (ci - 1) * ctx.col_w + CELL_PADDING_X,
            ry, ctx.row_h, {
                font = ctx.font, color = row_color or theme.colors.text,
                align = ctx.align_by_col[col] or ALIGN_LEFT,
                width = ctx.cell_text_w,
            })
    end
end

local function draw_body(rows, cols, state, ctx, opts)
    local visible_top
    local ry

    love.graphics.setScissor(ctx.x, ctx.view_y, ctx.w, ctx.view_h)
    visible_top = ctx.view_y - state.scroll
    for i, r in ipairs(rows) do
        ry = visible_top + (i - 1) * ctx.row_h
        if ry + ctx.row_h >= ctx.view_y and ry <= ctx.view_y + ctx.view_h then
            if i % ROW_STRIPE_PERIOD == ROW_STRIPE_OFFSET then
                love.graphics.setColor(opts.alt_color or theme.colors.row_alt)
                love.graphics.rectangle("fill", ctx.x, ry, ctx.w, ctx.row_h)
            end
            draw_row(r, cols, ctx, ry, opts.row_color)
        end
    end
    love.graphics.setScissor()
end

local function clamp_scroll(state, content_h, view_h)
    local max_scroll

    max_scroll = math.max(0, content_h - view_h)
    state.max_scroll = max_scroll
    if state.scroll > max_scroll then
        state.scroll = max_scroll
    end
    if state.scroll < 0 then
        state.scroll = 0
    end
    return max_scroll
end

local function draw_scrollbar(state, max_scroll, view_y, view_h, content_h, x, w)
    local bar_h
    local bar_y

    if max_scroll <= 0 then
        return
    end
    bar_h = math.max(SCROLLBAR_MIN_H, view_h * (view_h / content_h))
    bar_y = view_y + (view_h - bar_h) * (state.scroll / max_scroll)
    love.graphics.setColor(theme.colors.rule_strong)
    love.graphics.rectangle("fill",
        x + w - SCROLLBAR_W - SCROLLBAR_RIGHT_INSET, bar_y, SCROLLBAR_W, bar_h)
end

local function init_grid_state(state)
    state = state or {}
    state.scroll = state.scroll or 0
    if state.sort_ascending == nil then
        state.sort_ascending = true
    end
    return state
end

local function build_grid_context(opts, grid, x, y, w, h)
    local font
    local row_h
    local cols
    local rows
    local n_cols
    local col_w
    local ctx

    font = opts.font or theme.font(DEFAULT_FONT_FAMILY, DEFAULT_FONT_SIZE)
    row_h = font:getHeight() + ROW_VERTICAL_PADDING
    cols = grid and grid.columns or {}
    rows = grid and grid.rows or {}
    n_cols = #cols
    col_w = n_cols > 0 and (w / n_cols) or 0
    ctx = {
        font         = font,
        x            = x,
        y            = y,
        w            = w,
        row_h        = row_h,
        col_w        = col_w,
        cell_text_w  = math.max(0, col_w - CELL_PADDING_X * 2),
        view_y       = y + row_h,
        view_h       = h - row_h,
        align_by_col = (grid and grid.column_align) or {},
    }
    return font, cols, rows, ctx
end

local function compute_display_rows(rows, state)
    if not state.sort_col then
        return rows
    end
    if is_hierarchical(rows) then
        return sorted_hierarchical_rows(rows, state.sort_col, state.sort_ascending)
    end
    return sorted_rows(rows, state.sort_col, state.sort_ascending)
end

function M.draw(state, grid, x, y, w, h, opts)
    local font
    local cols
    local rows
    local ctx
    local display_rows
    local content_h
    local max_scroll

    state = init_grid_state(state)
    opts = opts or {}
    font, cols, rows, ctx = build_grid_context(opts, grid, x, y, w, h)
    if #cols == 0 then
        draw_empty_state(font, x, y, w, h)
        return state
    end
    handle_wheel_scroll(state, x, y, w, h, ctx.row_h)
    draw_header(cols, ctx, state, opts.header_color)
    display_rows = compute_display_rows(rows, state)
    content_h = #display_rows * ctx.row_h
    draw_body(display_rows, cols, state, ctx, opts)
    max_scroll = clamp_scroll(state, content_h, ctx.view_h)
    draw_scrollbar(state, max_scroll, ctx.view_y, ctx.view_h, content_h, x, w)
    return state
end

return M
