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

local function column_count_for(available_w, min_card_w, max_columns)
    local n = math.floor(available_w / min_card_w)
    if n < 1 then return 1 end
    if n > max_columns then return max_columns end
    return n
end

local function card_width_for(available_w, columns, gap)
    local total_gap = (columns - 1) * gap
    return math.floor((available_w - total_gap) / columns)
end

local function build_grid_layout(cards, available_w, opts)
    local columns = column_count_for(available_w,
        opts.min_card_w or DEFAULT_MIN_CARD_W,
        opts.max_columns or DEFAULT_MAX_COLUMNS)
    local card_w = card_width_for(available_w, columns, opts.gap or DEFAULT_GAP)
    local rows = {}
    local current = { cards = {}, height = 0 }
    for _, card in ipairs(cards) do
        if opts.prepare_card then opts.prepare_card(card, card_w) end
        if #current.cards >= columns then
            table.insert(rows, current)
            current = { cards = {}, height = 0 }
        end
        local h = opts.card_height(card)
        table.insert(current.cards, card)
        if h > current.height then current.height = h end
    end
    if #current.cards > 0 then table.insert(rows, current) end
    return { rows = rows, columns = columns, card_w = card_w }
end

local function compute_content_height(layout, gap)
    local total = 0
    for i, row in ipairs(layout.rows) do
        if i > 1 then total = total + gap end
        total = total + row.height
    end
    return total
end

local function clamp_scroll(view_state, content_h, view_h)
    local max_scroll = math.max(0, content_h - view_h)
    view_state.max_scroll = max_scroll
    if view_state.scroll > max_scroll then view_state.scroll = max_scroll end
    if view_state.scroll < 0 then view_state.scroll = 0 end
    return max_scroll
end

local function handle_wheel(view_state, x, y, w, h, step)
    if not input.in_rect(x, y, w, h) then return end
    if input.wheel_dy == 0 then return end
    view_state.scroll = view_state.scroll - input.wheel_dy * step
end

local function draw_scrollbar(view_state, max_scroll, x, y, w, h, content_h, bar_w)
    if max_scroll <= 0 then return end
    local bar_h = math.max(SCROLLBAR_MIN_H, h * (h / content_h))
    local bar_y = y + (h - bar_h) * (view_state.scroll / max_scroll)
    love.graphics.setColor(theme.colors.rule_strong)
    love.graphics.rectangle("fill", x + w - bar_w - 1, bar_y, bar_w, bar_h)
end

local function draw_empty_state(x, y, w, h, message, font)
    text.draw(message, x, y + h / 2 - font:getHeight() / 2, {
        font = font, color = theme.colors.text_faint,
        align = "center", width = w, letter_em = 0.06,
    })
end

local function draw_grid(layout, view_state, x, y, w, h, opts)
    love.graphics.setScissor(x, y, w, h)
    local gap = opts.gap or DEFAULT_GAP
    local cy = y - view_state.scroll
    for _, row in ipairs(layout.rows) do
        if cy + row.height >= y and cy <= y + h then
            for i, card in ipairs(row.cards) do
                local card_x = x + (i - 1) * (layout.card_w + gap)
                opts.draw_card(card, card_x, cy, layout.card_w, row.height)
            end
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
        left_accent_w = opts.left_accent_w or 2,
    })
end

function card_view.draw(view_state, x, y, w, h, opts)
    view_state = view_state or {}
    view_state.scroll = view_state.scroll or 0

    local gap = opts.gap or DEFAULT_GAP
    local wheel_step = opts.wheel_step or DEFAULT_WHEEL_STEP
    local scrollbar_w = opts.scrollbar_w or DEFAULT_SCROLLBAR_W
    local scrollbar_reserve = opts.scrollbar_reserve or DEFAULT_SCROLLBAR_RESERVE
    local content_w = w - scrollbar_reserve

    handle_wheel(view_state, x, y, w, h, wheel_step)

    local cards = opts.build_cards()
    if #cards == 0 then
        draw_empty_state(x, y, w, h, opts.empty_message or "(empty)",
            opts.empty_font or theme.font("mono", 11))
        return view_state
    end

    local layout = build_grid_layout(cards, content_w, opts)
    local content_h = compute_content_height(layout, gap)
    local max_scroll = clamp_scroll(view_state, content_h, h)
    draw_grid(layout, view_state, x, y, content_w, h, opts)
    draw_scrollbar(view_state, max_scroll, x, y, w, h, content_h, scrollbar_w)
    if opts.draw_overlay then
        opts.draw_overlay(view_state, x, y, content_w, h)
    end
    return view_state
end

return card_view
