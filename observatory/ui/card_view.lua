local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local text = require("observatory.ui.text")
local panel = require("observatory.ui.panel")

local card_view = {}

local DEFAULT_GAP = 12
local DEFAULT_MIN_CARD_W = 320
local DEFAULT_MAX_COLUMNS = 4
local DEFAULT_WHEEL_STEP = 40
local DEFAULT_SCROLLBAR_W = 3
local DEFAULT_SCROLLBAR_RESERVE = 6
local SCROLLBAR_MIN_H = 20
local SCROLLBAR_RIGHT_INSET = 1
local DEFAULT_LEFT_ACCENT_W = 2
local DEFAULT_EMPTY_MESSAGE = "(empty)"
local DEFAULT_EMPTY_FONT_FAMILY = "mono"
local DEFAULT_EMPTY_FONT_SIZE = 11
local EMPTY_LETTER_EM = 0.06

local function column_count_for(available_w, min_card_w, max_columns)
    local n

    n = math.floor(available_w / min_card_w)
    if n < 1 then
        return 1
    end
    if n > max_columns then
        return max_columns
    end
    return n
end

local function card_width_for(available_w, columns, gap)
    local total_gap

    total_gap = (columns - 1) * gap
    return math.floor((available_w - total_gap) / columns)
end

local function add_card_to_layout(card, current_row, columns, rows, h)
    if #current_row.cards >= columns then
        table.insert(rows, current_row)
        current_row = { cards = {}, height = 0 }
    end
    table.insert(current_row.cards, card)
    if h > current_row.height then
        current_row.height = h
    end
    return current_row
end

local function build_grid_layout(cards, available_w, opts)
    local columns
    local card_w
    local rows
    local current_row
    local h

    columns = column_count_for(available_w,
        opts.min_card_w or DEFAULT_MIN_CARD_W,
        opts.max_columns or DEFAULT_MAX_COLUMNS)
    card_w = card_width_for(available_w, columns, opts.gap or DEFAULT_GAP)
    rows = {}
    current_row = { cards = {}, height = 0 }
    for _, card in ipairs(cards) do
        if opts.prepare_card then
            opts.prepare_card(card, card_w)
        end
        h = opts.card_height(card)
        current_row = add_card_to_layout(card, current_row, columns, rows, h)
    end
    if #current_row.cards > 0 then
        table.insert(rows, current_row)
    end
    return { rows = rows, columns = columns, card_w = card_w }
end

local function compute_content_height(layout, gap)
    local total

    total = 0
    for i, row in ipairs(layout.rows) do
        if i > 1 then
            total = total + gap
        end
        total = total + row.height
    end
    return total
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

local function handle_wheel(view_state, x, y, w, h, step)
    if not input.in_rect(x, y, w, h) then
        return
    end
    if input.wheel_dy == 0 then
        return
    end
    view_state.scroll = view_state.scroll - input.wheel_dy * step
end

local function draw_scrollbar(view_state, max_scroll, x, y, w, h, content_h, bar_w)
    local bar_h
    local bar_y

    if max_scroll <= 0 then
        return
    end
    bar_h = math.max(SCROLLBAR_MIN_H, h * (h / content_h))
    bar_y = y + (h - bar_h) * (view_state.scroll / max_scroll)
    love.graphics.setColor(theme.colors.rule_strong)
    love.graphics.rectangle("fill",
        x + w - bar_w - SCROLLBAR_RIGHT_INSET, bar_y, bar_w, bar_h)
end

local function draw_empty_state(x, y, w, h, message, font)
    text.draw(message, x, y + h / 2 - font:getHeight() / 2, {
        font = font, color = theme.colors.text_faint,
        align = "center", width = w, letter_em = EMPTY_LETTER_EM,
    })
end

local function draw_row(row, layout, x, cy, gap, opts)
    local card_x

    for i, card in ipairs(row.cards) do
        card_x = x + (i - 1) * (layout.card_w + gap)
        opts.draw_card(card, card_x, cy, layout.card_w, row.height)
    end
end

local function draw_grid(layout, view_state, x, y, w, h, opts)
    local gap
    local cy

    love.graphics.setScissor(x, y, w, h)
    gap = opts.gap or DEFAULT_GAP
    cy = y - view_state.scroll
    for _, row in ipairs(layout.rows) do
        if cy + row.height >= y and cy <= y + h then
            draw_row(row, layout, x, cy, gap, opts)
        end
        cy = cy + row.height + gap
    end
    love.graphics.setScissor()
end

function card_view.draw_card_panel(x, y, w, h, opts)
    opts = opts or {}
    panel.draw(x, y, w, h, {
        bg = opts.bg or theme.colors.panel,
        border = opts.border or theme.colors.rule,
        left_accent = opts.left_accent or theme.colors.accent_rule,
        left_accent_w = opts.left_accent_w or DEFAULT_LEFT_ACCENT_W,
    })
end

local function should_handle_wheel(view_state, opts)
    if not opts.wheel_locked then
        return true
    end
    return not opts.wheel_locked(view_state)
end

local function show_empty_card_view(view_state, x, y, w, h, opts)
    draw_empty_state(x, y, w, h,
        opts.empty_message or DEFAULT_EMPTY_MESSAGE,
        opts.empty_font or theme.font(DEFAULT_EMPTY_FONT_FAMILY, DEFAULT_EMPTY_FONT_SIZE))
    return view_state
end

function card_view.draw(view_state, x, y, w, h, opts)
    local gap
    local wheel_step
    local scrollbar_w
    local scrollbar_reserve
    local content_w
    local cards
    local layout
    local content_h
    local max_scroll

    view_state = view_state or {}
    view_state.scroll = view_state.scroll or 0
    gap = opts.gap or DEFAULT_GAP
    wheel_step = opts.wheel_step or DEFAULT_WHEEL_STEP
    scrollbar_w = opts.scrollbar_w or DEFAULT_SCROLLBAR_W
    scrollbar_reserve = opts.scrollbar_reserve or DEFAULT_SCROLLBAR_RESERVE
    content_w = w - scrollbar_reserve
    if should_handle_wheel(view_state, opts) then
        handle_wheel(view_state, x, y, w, h, wheel_step)
    end
    cards = opts.build_cards()
    if #cards == 0 then
        return show_empty_card_view(view_state, x, y, w, h, opts)
    end
    layout = build_grid_layout(cards, content_w, opts)
    content_h = compute_content_height(layout, gap)
    max_scroll = clamp_scroll(view_state, content_h, h)
    draw_grid(layout, view_state, x, y, content_w, h, opts)
    draw_scrollbar(view_state, max_scroll, x, y, w, h, content_h, scrollbar_w)
    if opts.draw_overlay then
        opts.draw_overlay(view_state, x, y, content_w, h)
    end
    return view_state
end

return card_view
