local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local text  = require("observatory.ui.text")
local icon  = require("observatory.ui.icon")

local M = {}

local ROW_H               = 26
local INDENT_OFFSET       = 14
local INDENT_PX           = 22
local CONNECTOR_W         = 1
local CONNECTOR_GAP       = 4
local ICON_TEXT_GAP       = 10
local TYPE_RESERVE        = 220
local TYPE_GAP            = 14
local TIME_RESERVE        = 84
local TIME_GAP            = 12
local DISTANCE_RESERVE    = 110
local SCROLLBAR_RESERVE   = 6
local SCROLLBAR_W         = 3
local WHEEL_STEP_PX       = 40
local UNNAMED_PLACEHOLDER = "(unscanned)"
local EMPTY_TEXT          = "(no scans yet — fly somewhere)"

local KIND_UNKNOWN = "unknown"

local KIND_ICON_GLYPHS = {
    star       = icon.star,
    planet     = icon.dot,
    moon       = icon.dot,
    ring       = icon.diamond,
    belt       = icon.diamond,
    barycentre = icon.diamond,
    other      = icon.dot,
    unknown    = icon.dot,
}

local KIND_ICON_SIZES = {
    star       = 12,
    planet     = 9,
    moon       = 6,
    ring       = 7,
    belt       = 8,
    barycentre = 7,
    other      = 7,
    unknown    = 5,
}

local KIND_COLOR_KEYS = {
    star       = "accent",
    planet     = "text",
    moon       = "text_dim",
    ring       = "text_dim",
    belt       = "text_dim",
    barycentre = "text_dim",
    other      = "text_dim",
    unknown    = "text_faint",
}

local FONT_BODY = { family = "mono",        size = 11 }
local FONT_NAME = { family = "main_medium", size = 12 }

local function font_for(spec)
    return theme.font(spec.family, spec.size)
end

local function kind_color(kind, is_scanned)
    if not is_scanned then return theme.colors.text_faint end
    return theme.colors[KIND_COLOR_KEYS[kind] or "text"] or theme.colors.text
end

local function kind_glyph(kind)
    return KIND_ICON_GLYPHS[kind] or KIND_ICON_GLYPHS[KIND_UNKNOWN]
end

local function kind_size(kind)
    return KIND_ICON_SIZES[kind] or KIND_ICON_SIZES[KIND_UNKNOWN]
end

local function rail_x(x, depth)
    return x + INDENT_OFFSET + depth * INDENT_PX
end

local function expand_ancestors(nodes, bodies)
    local frontier = {}
    for id in pairs(nodes) do table.insert(frontier, id) end
    while #frontier > 0 do
        local id = table.remove(frontier)
        local body = bodies[id]
        local pid = body and body.parent_body_id
        if pid and bodies[pid] and not nodes[pid] then
            nodes[pid] = bodies[pid]
            table.insert(frontier, pid)
        end
    end
end

local function partition_tree(nodes)
    local children = {}
    local roots    = {}
    for id, body in pairs(nodes) do
        local pid = body.parent_body_id
        if pid and nodes[pid] then
            children[pid] = children[pid] or {}
            table.insert(children[pid], id)
        else
            table.insert(roots, id)
        end
    end
    return roots, children
end

local function sort_compare(a, b, nodes)
    local na, nb = nodes[a], nodes[b]
    local da = na.distance_num or math.huge
    local db = nb.distance_num or math.huge
    if da ~= db then return da < db end
    return (na.name or "") < (nb.name or "")
end

local function sort_ids(ids, nodes)
    table.sort(ids, function(a, b) return sort_compare(a, b, nodes) end)
end

local function build_tree(bodies)
    local nodes = {}
    for id, body in pairs(bodies) do
        if body.scanned then nodes[id] = body end
    end
    expand_ancestors(nodes, bodies)
    local roots, children = partition_tree(nodes)
    sort_ids(roots, nodes)
    for _, list in pairs(children) do sort_ids(list, nodes) end
    return nodes, children, roots
end

local function copy_continues(src, depth)
    local copy = {}
    for i = 1, depth do copy[i] = src[i] end
    return copy
end

local function walk(out, nodes, children, id, depth, is_last, ancestor_continues)
    table.insert(out, {
        body               = nodes[id],
        depth              = depth,
        is_last            = is_last,
        ancestor_continues = ancestor_continues,
    })
    local kids = children[id]
    if not kids then return end
    local next_continues = copy_continues(ancestor_continues, depth)
    next_continues[depth + 1] = not is_last
    for i, child in ipairs(kids) do
        walk(out, nodes, children, child, depth + 1, i == #kids, next_continues)
    end
end

local function flatten(nodes, children, roots)
    local out = {}
    for _, root in ipairs(roots) do
        walk(out, nodes, children, root, 0, true, {})
    end
    return out
end

local function raw_name(body)
    if body and body.name and body.name ~= "" and body.name ~= "?" then
        return body.name
    end
    return nil
end

local function strip_prefix(name, prefix)
    if not prefix or prefix == "" then return name end
    if name:sub(1, #prefix) ~= prefix then return name end
    local rest = name:sub(#prefix + 1):match("^%s*(.-)%s*$")
    if not rest or rest == "" then return name end
    return rest
end

local function attach_display_names(rows, nodes)
    for _, row in ipairs(rows) do
        local name = raw_name(row.body)
        if not name then
            row.display = UNNAMED_PLACEHOLDER
        elseif row.depth == 0 then
            row.display = name
        else
            local parent = nodes[row.body.parent_body_id]
            row.display = strip_prefix(name, raw_name(parent))
        end
    end
end

local function name_color(body)
    if not body or not body.scanned then return theme.colors.text_faint end
    return kind_color(body.kind or KIND_UNKNOWN, true)
end

local function draw_ancestor_rails(row, x, y, h)
    local up_to = row.depth - 1
    for c = 0, up_to - 1 do
        if row.ancestor_continues[c + 1] then
            local rx = rail_x(x, c)
            love.graphics.line(rx, y, rx, y + h)
        end
    end
end

local function draw_parent_connector(row, x, y, h)
    if row.depth == 0 then return end
    local mid_y     = math.floor(y + h / 2)
    local parent_rx = rail_x(x, row.depth - 1)
    local self_rx   = rail_x(x, row.depth)
    local v_end     = row.is_last and mid_y or (y + h)
    love.graphics.line(parent_rx, y, parent_rx, v_end)
    love.graphics.line(parent_rx, mid_y, self_rx - CONNECTOR_GAP, mid_y)
end

local function draw_connectors(row, x, y, h)
    if row.depth == 0 then return end
    love.graphics.setColor(theme.colors.rule_strong)
    local prev_lw = love.graphics.getLineWidth()
    love.graphics.setLineWidth(CONNECTOR_W)
    draw_ancestor_rails(row, x, y, h)
    draw_parent_connector(row, x, y, h)
    love.graphics.setLineWidth(prev_lw)
end

local function draw_kind_icon(row, x, y, h)
    local body = row.body
    local kind = (body and body.kind) or KIND_UNKNOWN
    local size = kind_size(kind)
    local glyph = kind_glyph(kind)
    local cx = rail_x(x, row.depth)
    local color = kind_color(kind, body and body.scanned)
    glyph(cx - size / 2, y + (h - size) / 2, size, color)
    return cx + size / 2
end

local function build_text_columns(right_edge)
    local distance_x = right_edge - DISTANCE_RESERVE
    local time_x     = distance_x - TIME_GAP - TIME_RESERVE
    local type_x     = time_x     - TYPE_GAP - TYPE_RESERVE
    return type_x, time_x, distance_x
end

local function draw_name(row, x, y, max_w, h)
    local font = font_for(FONT_NAME)
    local label = row.display or UNNAMED_PLACEHOLDER
    local fitted = text.truncate_right(label, font, max_w, 0)
    text.draw_v_center(fitted, x, y, h, {
        font = font, color = name_color(row.body),
    })
end

local function draw_meta_cell(value, x, y, h, w, color, align)
    if not value or value == "" then return end
    local font = font_for(FONT_BODY)
    local fitted = text.truncate_right(value, font, w, 0)
    text.draw_v_center(fitted, x, y, h, {
        font = font, color = color, align = align, width = w,
    })
end

local function draw_row_meta(row, type_x, time_x, distance_x, y, h)
    local body = row.body
    local type_color = (body and body.scanned)
        and theme.colors.text_dim or theme.colors.text_faint
    draw_meta_cell(body and body.type, type_x, y, h, TYPE_RESERVE,
        type_color, "left")
    draw_meta_cell(body and body.time, time_x, y, h, TIME_RESERVE,
        theme.colors.text_faint, "left")
    draw_meta_cell(body and body.distance, distance_x, y, h, DISTANCE_RESERVE,
        theme.colors.text, "right")
end

local function draw_row(row, x, y, w, h)
    draw_connectors(row, x, y, h)
    local icon_right = draw_kind_icon(row, x, y, h)
    local type_x, time_x, distance_x = build_text_columns(x + w)
    local name_x = icon_right + ICON_TEXT_GAP
    local name_w = math.max(0, type_x - name_x - 8)
    draw_name(row, name_x, y, name_w, h)
    draw_row_meta(row, type_x, time_x, distance_x, y, h)
end

local function clamp_scroll(view_state, content_h, view_h)
    local max_scroll = math.max(0, content_h - view_h)
    view_state.max_scroll = max_scroll
    if view_state.scroll > max_scroll then view_state.scroll = max_scroll end
    if view_state.scroll < 0 then view_state.scroll = 0 end
    return max_scroll
end

local function handle_wheel(view_state, x, y, w, h)
    if not input.in_rect(x, y, w, h) then return end
    if input.wheel_dy == 0 then return end
    view_state.scroll = view_state.scroll - input.wheel_dy * WHEEL_STEP_PX
end

local function draw_scrollbar(view_state, max_scroll, x, y, w, h, content_h)
    if max_scroll <= 0 then return end
    local bar_h = math.max(20, h * (h / content_h))
    local bar_y = y + (h - bar_h) * (view_state.scroll / max_scroll)
    love.graphics.setColor(theme.colors.rule_strong)
    love.graphics.rectangle("fill",
        x + w - SCROLLBAR_W - 1, bar_y, SCROLLBAR_W, bar_h)
end

local function draw_empty(x, y, w, h)
    local font = font_for(FONT_BODY)
    text.draw(EMPTY_TEXT, x, y + h / 2 - font:getHeight() / 2, {
        font = font, color = theme.colors.text_faint,
        align = "center", width = w, letter_em = 0.06,
    })
end

local function draw_visible_rows(rows, x, y, w, h, view_state)
    love.graphics.setScissor(x, y, w, h)
    local cy = y - view_state.scroll
    for i, row in ipairs(rows) do
        local row_top = cy + (i - 1) * ROW_H
        local row_bottom = row_top + ROW_H
        if row_bottom >= y and row_top <= y + h then
            draw_row(row, x, row_top, w, ROW_H)
        end
    end
    love.graphics.setScissor()
end

function M.row_count(bodies)
    if type(bodies) ~= "table" then return 0 end
    local n = 0
    for _, body in pairs(bodies) do
        if body.scanned then n = n + 1 end
    end
    return n
end

function M.draw(view_state, x, y, w, h, bodies)
    view_state = view_state or {}
    view_state.scroll = view_state.scroll or 0
    handle_wheel(view_state, x, y, w, h)
    local nodes, children, roots = build_tree(bodies or {})
    local rows = flatten(nodes, children, roots)
    if #rows == 0 then
        draw_empty(x, y, w, h)
        return view_state
    end
    attach_display_names(rows, nodes)
    local inner_w = w - SCROLLBAR_RESERVE
    local content_h = #rows * ROW_H
    local max_scroll = clamp_scroll(view_state, content_h, h)
    draw_visible_rows(rows, x, y, inner_w, h, view_state)
    draw_scrollbar(view_state, max_scroll, x, y, w, h, content_h)
    return view_state
end

return M
