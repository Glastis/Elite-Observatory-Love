local theme = require("observatory.ui.theme")
local text = require("observatory.ui.text")

local badge = {}

local DEFAULT_PAD_X = 7
local DEFAULT_HEIGHT = 20
local DEFAULT_RADIUS = 0
local DEFAULT_LETTER_EM = 0.08
local OUTLINE_INSET = 0.5

local function resolve_color(value)
    if type(value) == "string" then return theme.colors[value] end
    return value
end

local function fill_rect(style, x, y, w, h)
    local bg_color = resolve_color(style.bg_color)
    if not bg_color then return end
    love.graphics.setColor(bg_color)
    love.graphics.rectangle("fill", x, y, w, h, style.radius or DEFAULT_RADIUS,
        style.radius or DEFAULT_RADIUS)
end

local function outline_rect(style, x, y, w, h)
    local outline_color = resolve_color(style.outline_color)
    if not outline_color then return end
    love.graphics.setColor(outline_color)
    love.graphics.rectangle("line",
        x + OUTLINE_INSET, y + OUTLINE_INSET,
        w - 1, h - 1,
        style.radius or DEFAULT_RADIUS, style.radius or DEFAULT_RADIUS)
end

function badge.measure(label, font, opts)
    opts = opts or {}
    local pad_x = opts.pad_x or DEFAULT_PAD_X
    local letter_em = opts.letter_em or DEFAULT_LETTER_EM
    local text_w = text.width(label, font, letter_em)
    return text_w + pad_x * 2, opts.h or DEFAULT_HEIGHT, text_w
end

function badge.draw(label, x, y, font, style, opts)
    opts = opts or {}
    local pad_x = opts.pad_x or DEFAULT_PAD_X
    local h = opts.h or DEFAULT_HEIGHT
    local letter_em = opts.letter_em or DEFAULT_LETTER_EM
    local w = opts.w or (text.width(label, font, letter_em) + pad_x * 2)

    fill_rect(style, x, y, w, h)
    outline_rect(style, x, y, w, h)

    local label_y = y + math.floor((h - font:getHeight()) / 2)
    text.draw(label, x + pad_x, label_y, {
        font = font,
        color = resolve_color(style.text_color) or theme.colors.text,
        letter_em = letter_em,
        bold = style.bold,
    })
    return w, h
end

function badge.layout_rows(items, max_w, gap_x)
    if #items == 0 then return {} end
    local rows = { {} }
    local cur_w = 0
    for _, item in ipairs(items) do
        local needed = item.width + (#rows[#rows] > 0 and gap_x or 0)
        if cur_w + needed > max_w and #rows[#rows] > 0 then
            table.insert(rows, {})
            cur_w = 0
            needed = item.width
        end
        table.insert(rows[#rows], item)
        cur_w = cur_w + needed
    end
    return rows
end

function badge.rows_height(rows, row_h, gap_y)
    if #rows == 0 then return 0 end
    return #rows * row_h + (#rows - 1) * gap_y
end

function badge.draw_rows(rows, x, y, font, opts)
    opts = opts or {}
    local row_h = opts.h or DEFAULT_HEIGHT
    local gap_x = opts.gap_x or 5
    local gap_y = opts.gap_y or 4
    local cy = y
    for i, row in ipairs(rows) do
        if i > 1 then cy = cy + gap_y end
        local cx = x
        for j, item in ipairs(row) do
            if j > 1 then cx = cx + gap_x end
            badge.draw(item.label, cx, cy, font, item.style or {}, {
                pad_x = opts.pad_x, h = row_h, letter_em = opts.letter_em,
                w = item.width,
            })
            cx = cx + item.width
        end
        cy = cy + row_h
    end
    return cy
end

return badge
