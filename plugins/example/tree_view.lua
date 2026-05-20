local theme       = require("observatory.ui.theme")
local input       = require("observatory.ui.input")
local text        = require("observatory.ui.text")
local icon        = require("observatory.ui.icon")
local body_value  = require("observatory.plugin_helpers.body_value")
local body_colors = require("plugins.example.body_colors")

local M = {}

local ROW_H               = 26
local INDENT_OFFSET       = 14
local INDENT_PX           = 22
local CONNECTOR_W         = 1
local CONNECTOR_GAP       = 4
local ICON_TEXT_GAP       = 10
local TYPE_RESERVE        = 220
local TYPE_GAP            = 14
local STATUS_RESERVE      = 80
local STATUS_GAP          = 12
local DISTANCE_RESERVE    = 110
local DISTANCE_GAP        = 12
local VALUE_RESERVE       = 90
local SCROLLBAR_RESERVE   = 6

local VALUE_BANDS = {
    { min = 400000, color_key = "success"  },
    { min = 100000, color_key = "accent"   },
    { min = 0,      color_key = "text_dim" },
}

local STATUS_LABEL_FIRST     = "FIRST"
local STATUS_LABEL_FIRST_MAP = "1ST MAP"
local STATUS_LABEL_MAPPED    = "MAPPED"
local STATUS_LABEL_DISC      = "DISC"

local STATUS_COLOR_KEY_NEW  = "accent"
local STATUS_COLOR_KEY_HALF = "success"
local STATUS_COLOR_KEY_DONE = "text_dim"
local SCROLLBAR_W         = 3
local WHEEL_STEP_PX       = 40
local UNNAMED_PLACEHOLDER = "(unscanned)"
local EMPTY_TEXT          = "(no scans yet — fly somewhere)"

local KIND_UNKNOWN    = "unknown"
local KIND_BARYCENTRE = "barycentre"
local BARYCENTRE_LABEL = "Barycentre"

local SCROLLBAR_MIN_H = 20
local SCROLLBAR_RIGHT_INSET = 1
local NAME_RIGHT_PADDING = 8

local function is_barycentre(body)
    return body and body.kind == KIND_BARYCENTRE
end

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
    if not is_scanned then
        return theme.colors.text_faint
    end
    return theme.colors[KIND_COLOR_KEYS[kind] or "text"] or theme.colors.text
end

local function body_icon_color(body)
    local typed

    if not body or not body.scanned then
        return theme.colors.text_faint
    end
    typed = body_colors.lookup(body.body_type)
    if typed then
        return typed
    end
    return kind_color(body.kind or KIND_UNKNOWN, true)
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
    local frontier
    local id
    local body
    local pid

    frontier = {}
    for node_id in pairs(nodes) do
        table.insert(frontier, node_id)
    end
    while #frontier > 0 do
        id = table.remove(frontier)
        body = bodies[id]
        pid = body and body.parent_body_id
        if pid and bodies[pid] and not nodes[pid] then
            nodes[pid] = bodies[pid]
            table.insert(frontier, pid)
        end
    end
end

local function partition_tree(nodes)
    local children
    local roots
    local pid

    children = {}
    roots    = {}
    for id, body in pairs(nodes) do
        pid = body.parent_body_id
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
    local na
    local nb
    local da
    local db

    na = nodes[a]
    nb = nodes[b]
    da = na._effective_distance or math.huge
    db = nb._effective_distance or math.huge
    if da ~= db then
        return da < db
    end
    return (na.name or "") < (nb.name or "")
end

local function sort_ids(ids, nodes)
    table.sort(ids, function(a, b) return sort_compare(a, b, nodes) end)
end

local function compute_effective_distance(id, nodes, children, memo)
    local body
    local kids
    local min_d
    local d

    if memo[id] ~= nil then
        return memo[id]
    end
    memo[id] = math.huge
    body = nodes[id]
    if body and body.distance_num then
        memo[id] = body.distance_num
        return memo[id]
    end
    kids = children[id]
    if not kids then
        return memo[id]
    end
    min_d = math.huge
    for _, kid_id in ipairs(kids) do
        d = compute_effective_distance(kid_id, nodes, children, memo)
        if d < min_d then
            min_d = d
        end
    end
    memo[id] = min_d
    return min_d
end

local function annotate_effective_distance(nodes, children)
    local memo

    memo = {}
    for id in pairs(nodes) do
        compute_effective_distance(id, nodes, children, memo)
    end
    for id, body in pairs(nodes) do
        body._effective_distance = memo[id]
    end
end

local function build_tree(bodies)
    local nodes
    local roots
    local children

    nodes = {}
    for id, body in pairs(bodies) do
        if body.scanned then
            nodes[id] = body
        end
    end
    expand_ancestors(nodes, bodies)
    roots, children = partition_tree(nodes)
    annotate_effective_distance(nodes, children)
    sort_ids(roots, nodes)
    for _, list in pairs(children) do
        sort_ids(list, nodes)
    end
    return nodes, children, roots
end

local function copy_continues(src, depth)
    local copy

    copy = {}
    for i = 1, depth do
        copy[i] = src[i]
    end
    return copy
end

local function walk(out, nodes, children, id, depth, is_last, ancestor_continues)
    local kids
    local next_continues

    table.insert(out, {
        body               = nodes[id],
        depth              = depth,
        is_last            = is_last,
        ancestor_continues = ancestor_continues,
    })
    kids = children[id]
    if not kids then
        return
    end
    next_continues = copy_continues(ancestor_continues, depth)
    next_continues[depth + 1] = not is_last
    for i, child in ipairs(kids) do
        walk(out, nodes, children, child, depth + 1, i == #kids, next_continues)
    end
end

local function flatten(nodes, children, roots)
    local out

    out = {}
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
    local rest

    if not prefix or prefix == "" then
        return name
    end
    if name:sub(1, #prefix) ~= prefix then
        return name
    end
    rest = name:sub(#prefix + 1):match("^%s*(.-)%s*$")
    if not rest or rest == "" then
        return name
    end
    return rest
end

local function display_name_for_row(row, nodes)
    local name
    local parent

    if is_barycentre(row.body) then
        return BARYCENTRE_LABEL
    end
    name = raw_name(row.body)
    if not name then
        return UNNAMED_PLACEHOLDER
    end
    if row.depth == 0 then
        return name
    end
    parent = nodes[row.body.parent_body_id]
    return strip_prefix(name, raw_name(parent))
end

local function attach_display_names(rows, nodes)
    for _, row in ipairs(rows) do
        row.display = display_name_for_row(row, nodes)
    end
end

local function name_color(body)
    if is_barycentre(body) then
        return theme.colors.text_dim
    end
    if not body or not body.scanned then
        return theme.colors.text_faint
    end
    return kind_color(body.kind or KIND_UNKNOWN, true)
end

local function draw_ancestor_rails(row, x, y, h)
    local up_to
    local rx

    up_to = row.depth - 1
    for c = 0, up_to - 1 do
        if row.ancestor_continues[c + 1] then
            rx = rail_x(x, c)
            love.graphics.line(rx, y, rx, y + h)
        end
    end
end

local function draw_parent_connector(row, x, y, h)
    local mid_y
    local parent_rx
    local self_rx
    local v_end

    if row.depth == 0 then
        return
    end
    mid_y     = math.floor(y + h / 2)
    parent_rx = rail_x(x, row.depth - 1)
    self_rx   = rail_x(x, row.depth)
    v_end     = row.is_last and mid_y or (y + h)
    love.graphics.line(parent_rx, y, parent_rx, v_end)
    love.graphics.line(parent_rx, mid_y, self_rx - CONNECTOR_GAP, mid_y)
end

local function draw_connectors(row, x, y, h)
    local prev_lw

    if row.depth == 0 then
        return
    end
    love.graphics.setColor(theme.colors.rule_strong)
    prev_lw = love.graphics.getLineWidth()
    love.graphics.setLineWidth(CONNECTOR_W)
    draw_ancestor_rails(row, x, y, h)
    draw_parent_connector(row, x, y, h)
    love.graphics.setLineWidth(prev_lw)
end

local function draw_kind_icon(row, x, y, h)
    local body
    local kind
    local size
    local glyph
    local cx
    local color

    body = row.body
    kind = (body and body.kind) or KIND_UNKNOWN
    size = kind_size(kind)
    glyph = kind_glyph(kind)
    cx = rail_x(x, row.depth)
    color = body_icon_color(body)
    glyph(cx - size / 2, y + (h - size) / 2, size, color)
    return cx + size / 2
end

local function build_text_columns(right_edge)
    local value_x
    local distance_x
    local status_x
    local type_x

    value_x    = right_edge - VALUE_RESERVE
    distance_x = value_x    - DISTANCE_GAP - DISTANCE_RESERVE
    status_x   = distance_x - STATUS_GAP   - STATUS_RESERVE
    type_x     = status_x   - TYPE_GAP     - TYPE_RESERVE
    return type_x, status_x, distance_x, value_x
end

local function draw_name(row, x, y, max_w, h)
    local font
    local label
    local fitted

    font = font_for(FONT_NAME)
    label = row.display or UNNAMED_PLACEHOLDER
    fitted = text.truncate_right(label, font, max_w, 0)
    text.draw_v_center(fitted, x, y, h, {
        font = font, color = name_color(row.body),
    })
end

local function draw_meta_cell(value, x, y, h, w, color, align)
    local font
    local fitted

    if not value or value == "" then
        return
    end
    font = font_for(FONT_BODY)
    fitted = text.truncate_right(value, font, w, 0)
    text.draw_v_center(fitted, x, y, h, {
        font = font, color = color, align = align, width = w,
    })
end

local STATUS_RULES = {
    {
        active = function(body) return not body.was_discovered end,
        label = STATUS_LABEL_FIRST, color_key = STATUS_COLOR_KEY_NEW,
    },
    {
        active = function(body) return body.is_star end,
        label = STATUS_LABEL_DISC, color_key = STATUS_COLOR_KEY_DONE,
    },
    {
        active = function(body) return not body.was_mapped end,
        label = STATUS_LABEL_FIRST_MAP, color_key = STATUS_COLOR_KEY_HALF,
    },
    {
        active = function(_) return true end,
        label = STATUS_LABEL_MAPPED, color_key = STATUS_COLOR_KEY_DONE,
    },
}

local function pick_status(body)
    if not body or not body.scanned then
        return nil
    end
    for _, rule in ipairs(STATUS_RULES) do
        if rule.active(body) then
            return rule
        end
    end
    return nil
end

local function status_text_for(body)
    local rule

    rule = pick_status(body)
    if not rule then
        return ""
    end
    return rule.label
end

local function status_color_for(body)
    local rule

    rule = pick_status(body)
    if not rule then
        return theme.colors.text_faint
    end
    return theme.colors[rule.color_key] or theme.colors.text
end

local function value_text_for(body)
    local value

    if not body or not body.scanned then
        return ""
    end
    value = body.is_star and body.current_value or body.potential_max
    return body_value.format(value)
end

local function value_color_for(body)
    local value

    if not body or not body.scanned then
        return theme.colors.text_faint
    end
    value = (body.is_star and body.current_value or body.potential_max) or 0
    for _, band in ipairs(VALUE_BANDS) do
        if value >= band.min then
            return theme.colors[band.color_key]
        end
    end
    return theme.colors.text
end

local function draw_row_meta(row, type_x, status_x, distance_x, value_x, y, h)
    local body
    local type_color

    body = row.body
    type_color = (body and body.scanned)
        and theme.colors.text_dim or theme.colors.text_faint
    draw_meta_cell(body and body.type, type_x, y, h, TYPE_RESERVE,
        type_color, "left")
    draw_meta_cell(status_text_for(body), status_x, y, h, STATUS_RESERVE,
        status_color_for(body), "left")
    draw_meta_cell(body and body.distance, distance_x, y, h, DISTANCE_RESERVE,
        theme.colors.text, "right")
    draw_meta_cell(value_text_for(body), value_x, y, h, VALUE_RESERVE,
        value_color_for(body), "right")
end

local function draw_barycentre_row(row, x, y, w, h, name_x)
    local name_w

    name_w = math.max(0, (x + w) - name_x - NAME_RIGHT_PADDING)
    draw_name(row, name_x, y, name_w, h)
end

local function draw_full_row(row, x, y, w, h, name_x)
    local type_x
    local status_x
    local distance_x
    local value_x
    local name_w

    type_x, status_x, distance_x, value_x = build_text_columns(x + w)
    name_w = math.max(0, type_x - name_x - NAME_RIGHT_PADDING)
    draw_name(row, name_x, y, name_w, h)
    draw_row_meta(row, type_x, status_x, distance_x, value_x, y, h)
end

local function draw_row(row, x, y, w, h)
    local icon_right
    local name_x

    draw_connectors(row, x, y, h)
    icon_right = draw_kind_icon(row, x, y, h)
    name_x = icon_right + ICON_TEXT_GAP
    if is_barycentre(row.body) then
        draw_barycentre_row(row, x, y, w, h, name_x)
    else
        draw_full_row(row, x, y, w, h, name_x)
    end
end

local function clamp_scroll(view_state, content_h, view_h)
    local max_scroll

    max_scroll = math.max(0, content_h - view_h)
    view_state.max_scroll = max_scroll
    if view_state.scroll > max_scroll then
        view_state.scroll = max_scroll
    end
    if view_state.scroll < 0 then
        view_state.scroll = 0
    end
    return max_scroll
end

local function handle_wheel(view_state, x, y, w, h)
    if not input.in_rect(x, y, w, h) then
        return
    end
    if input.wheel_dy == 0 then
        return
    end
    view_state.scroll = view_state.scroll - input.wheel_dy * WHEEL_STEP_PX
end

local function draw_scrollbar(view_state, max_scroll, x, y, w, h, content_h)
    local bar_h
    local bar_y

    if max_scroll <= 0 then
        return
    end
    bar_h = math.max(SCROLLBAR_MIN_H, h * (h / content_h))
    bar_y = y + (h - bar_h) * (view_state.scroll / max_scroll)
    love.graphics.setColor(theme.colors.rule_strong)
    love.graphics.rectangle("fill",
        x + w - SCROLLBAR_W - SCROLLBAR_RIGHT_INSET, bar_y, SCROLLBAR_W, bar_h)
end

local function draw_empty(x, y, w, h)
    local font

    font = font_for(FONT_BODY)
    text.draw(EMPTY_TEXT, x, y + h / 2 - font:getHeight() / 2, {
        font = font, color = theme.colors.text_faint,
        align = "center", width = w, letter_em = 0.06,
    })
end

local function draw_visible_rows(rows, x, y, w, h, view_state)
    local cy
    local row_top
    local row_bottom

    love.graphics.setScissor(x, y, w, h)
    cy = y - view_state.scroll
    for i, row in ipairs(rows) do
        row_top = cy + (i - 1) * ROW_H
        row_bottom = row_top + ROW_H
        if row_bottom >= y and row_top <= y + h then
            draw_row(row, x, row_top, w, ROW_H)
        end
    end
    love.graphics.setScissor()
end

function M.row_count(bodies)
    local n

    if type(bodies) ~= "table" then
        return 0
    end
    n = 0
    for _, body in pairs(bodies) do
        if body.scanned then
            n = n + 1
        end
    end
    return n
end

function M.draw(view_state, x, y, w, h, bodies)
    local nodes
    local children
    local roots
    local rows
    local inner_w
    local content_h
    local max_scroll

    view_state = view_state or {}
    view_state.scroll = view_state.scroll or 0
    handle_wheel(view_state, x, y, w, h)
    nodes, children, roots = build_tree(bodies or {})
    rows = flatten(nodes, children, roots)
    if #rows == 0 then
        draw_empty(x, y, w, h)
        return view_state
    end
    attach_display_names(rows, nodes)
    inner_w = w - SCROLLBAR_RESERVE
    content_h = #rows * ROW_H
    max_scroll = clamp_scroll(view_state, content_h, h)
    draw_visible_rows(rows, x, y, inner_w, h, view_state)
    draw_scrollbar(view_state, max_scroll, x, y, w, h, content_h)
    return view_state
end

return M
