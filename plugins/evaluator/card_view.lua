local theme        = require("observatory.ui.theme")
local input        = require("observatory.ui.input")
local text         = require("observatory.ui.text")
local panel        = require("observatory.ui.panel")
local plugin_state = require("plugins.evaluator.state")
local constants    = require("plugins.evaluator.constants")

local CARD_GAP             = 12
local CARD_PAD_X           = 14
local CARD_PAD_Y           = 12
local CARD_HEADER_H        = 22
local CARD_DISTANCE_H      = 16
local CARD_SUB_H           = 18
local CARD_INTERNAL_GAP    = 10
local BADGE_ROW_H          = 20
local BADGE_PAD_X          = 7
local BADGE_PAD_Y          = 3
local BADGE_GAP_X          = 5
local BADGE_GAP_Y          = 4
local BADGE_RADIUS         = 0
local FOOTER_H             = 18
local FOOTER_GAP           = 6
local SCROLLBAR_RESERVE    = 6
local SCROLLBAR_W          = 3
local WHEEL_STEP_PX        = 40
local SUB_PARTS_SEP        = "  -  "
local MIN_CARD_W           = 320
local MAX_COLUMNS          = 4
local UNNAMED_PLACEHOLDER  = "(unscanned)"

local FONT_TITLE    = { family = "main_medium", size = 14 }
local FONT_VALUE    = { family = "mono",        size = 11 }
local FONT_DISTANCE = { family = "mono_medium", size = 11 }
local FONT_SUB      = { family = "mono",        size = 10 }
local FONT_BADGE    = { family = "mono_medium", size = 9  }
local FONT_FOOTER   = { family = "mono",        size = 10 }
local FONT_EMPTY    = { family = "mono",        size = 11 }

local TITLE_TRAILING_GAP = 12

local HIGH_VALUE_BOLD_THRESHOLD = 2 * 1000000

local KIND_PREMIUM   = "premium"
local KIND_BONUS     = "bonus"
local KIND_INFO      = "info"

local BADGE_STYLES = {
    [KIND_PREMIUM] = {
        text_color   = "bg",
        bg_color     = "accent",
        is_emphasis  = true,
    },
    [KIND_BONUS] = {
        text_color   = "success",
        bg_color     = nil,
        outline_color = "success",
        is_emphasis  = false,
    },
    [KIND_INFO] = {
        text_color   = "text_dim",
        bg_color     = nil,
        outline_color = "rule_strong",
        is_emphasis  = false,
    },
}

local PREMIUM_PLANET_LABEL = {
    ["Earthlike body"] = "ELW",
    ["Water world"]    = "WW",
    ["Ammonia world"]  = "AW",
}

local CARD_VIEW = {}

local function font_for(spec)
    return theme.font(spec.family, spec.size)
end

local function format_thousand_million(value)
    if value >= constants.VALUE_MILLION then
        return string.format(constants.VALUE_MILLION_FORMAT,
            value / constants.VALUE_MILLION)
    end
    return string.format(constants.VALUE_THOUSAND_FORMAT,
        value / constants.VALUE_THOUSAND)
end

local function format_value_str(value)
    if not value or value <= 0 then return constants.UNKNOWN_TEXT end
    return format_thousand_million(value) .. " cr"
end

local function format_distance(distance_ls)
    if not distance_ls or distance_ls <= 0 then
        return constants.UNKNOWN_TEXT
    end
    return string.format("%.0f Ls", distance_ls)
end

local function format_gravity(gravity_ms2)
    if not gravity_ms2 or gravity_ms2 <= 0 then
        return constants.UNKNOWN_TEXT
    end
    return string.format("%.2fg", gravity_ms2 / constants.GRAVITY_DIVIDER)
end

local function strip_system_prefix(body_name, system_name)
    if not system_name or system_name == "" then return body_name end
    if body_name:sub(1, #system_name) ~= system_name then return body_name end
    local last_word = system_name:match("(%S+)%s*$")
    if not last_word then return body_name end
    local keep_from = #system_name - #last_word + 1
    local rest = body_name:sub(keep_from)
    if rest == "" then return body_name end
    return rest
end

local function raw_body_name(body)
    if body.name and body.name ~= "" and body.name ~= "?" then
        return body.name
    end
    return nil
end

local function display_body_name(body, system_name, hide_system)
    local name = raw_body_name(body)
    if not name then return UNNAMED_PLACEHOLDER end
    if not hide_system then return name end
    return strip_system_prefix(name, system_name)
end

local function body_type_label(body)
    if body.body_type and body.body_type ~= "" then
        return body.body_type
    end
    return constants.UNKNOWN_TEXT
end

local function append_part(list, value)
    if not value or value == "" or value == constants.UNKNOWN_TEXT then return end
    table.insert(list, value)
end

local function build_subheader_parts(body)
    local parts = {}
    append_part(parts, body_type_label(body))
    append_part(parts, format_gravity(body.gravity_ms2))
    if body.atmosphere and body.atmosphere ~= "" then
        append_part(parts, body.atmosphere)
    end
    return parts
end

local BADGE_BUILDERS = {
    {
        active = function(body) return PREMIUM_PLANET_LABEL[body.body_type] ~= nil end,
        build  = function(body)
            return { label = PREMIUM_PLANET_LABEL[body.body_type], kind = KIND_PREMIUM }
        end,
    },
    {
        active = function(body) return body.terraformable end,
        build  = function() return { label = "TERRAFORM", kind = KIND_PREMIUM } end,
    },
    {
        active = function(body) return not body.was_discovered end,
        build  = function() return { label = "FIRST DISCOVERY", kind = KIND_BONUS } end,
    },
    {
        active = function(body) return not body.was_mapped and not body.is_star end,
        build  = function() return { label = "FIRST MAPPING", kind = KIND_BONUS } end,
    },
    {
        active = function(body) return body.worth_mapping end,
        build  = function() return { label = "WORTH MAPPING", kind = KIND_PREMIUM } end,
    },
    {
        active = function(body) return body.is_landable end,
        build  = function() return { label = "LANDABLE", kind = KIND_INFO } end,
    },
    {
        active = function(body)
            return body.atmosphere and body.atmosphere ~= ""
        end,
        build  = function() return { label = "ATMO", kind = KIND_INFO } end,
    },
    {
        active = function(body)
            return body.volcanism and body.volcanism ~= ""
        end,
        build  = function() return { label = "VOLCANIC", kind = KIND_INFO } end,
    },
}

local function build_badges(body)
    local list = {}
    for _, builder in ipairs(BADGE_BUILDERS) do
        if builder.active(body) then
            local badge = builder.build(body)
            badge.text_w = text.width(badge.label, font_for(FONT_BADGE), 0.08)
            badge.width  = badge.text_w + BADGE_PAD_X * 2
            table.insert(list, badge)
        end
    end
    return list
end

local function layout_badge_rows(badges, max_w)
    if #badges == 0 then return {} end
    local rows = { {} }
    local cur_w = 0
    for _, badge in ipairs(badges) do
        local needed = badge.width + (#rows[#rows] > 0 and BADGE_GAP_X or 0)
        if cur_w + needed > max_w and #rows[#rows] > 0 then
            table.insert(rows, {})
            cur_w = 0
            needed = badge.width
        end
        table.insert(rows[#rows], badge)
        cur_w = cur_w + needed
    end
    return rows
end

local function badges_block_height(rows)
    if #rows == 0 then return 0 end
    return #rows * BADGE_ROW_H + (#rows - 1) * BADGE_GAP_Y
end

local FOOTER_BUILDERS = {
    {
        active = function(body)
            if body.is_star then return false end
            if body.was_mapped then return false end
            if not body.worth_mapping then return false end
            local delta = (body.potential_max or 0) - (body.current_value or 0)
            return delta > 0
        end,
        build = function(body)
            local delta = (body.potential_max or 0) - (body.current_value or 0)
            return {
                label     = string.format("Map for +%s", format_value_str(delta)),
                color_key = "accent",
            }
        end,
    },
    {
        active = function(body) return body.was_mapped and not body.is_star end,
        build  = function() return { label = "Already mapped", color_key = "text_dim" } end,
    },
    {
        active = function(body) return body.is_star end,
        build  = function(body)
            return {
                label     = string.format("Star value: %s",
                    format_value_str(body.current_value)),
                color_key = "text_dim",
            }
        end,
    },
}

local function build_footer(body)
    for _, builder in ipairs(FOOTER_BUILDERS) do
        if builder.active(body) then
            return builder.build(body)
        end
    end
    return nil
end

local function predicted_value(body)
    if body.is_star then return body.current_value or 0 end
    return body.potential_max or 0
end

local function build_card(body, system_name, hide_system)
    local title = display_body_name(body, system_name, hide_system)
    local card  = {
        body          = body,
        system_name   = system_name,
        title         = title,
        sub_parts     = build_subheader_parts(body),
        value_text    = format_value_str(predicted_value(body)),
        distance_text = format_distance(body.distance_ls),
        is_high_value = predicted_value(body) >= HIGH_VALUE_BOLD_THRESHOLD,
        badges        = build_badges(body),
        footer        = build_footer(body),
        sort_value    = predicted_value(body),
    }
    return card
end

local function should_skip_body(body, settings, hide_scanned)
    if not body or not body.scanned then return true end
    if hide_scanned and body.was_mapped then return true end
    if settings and settings.minimum_body_value
        and (body.potential_max or 0) < settings.minimum_body_value then
        return true
    end
    return false
end

local function compare_by_body(a, b)
    if (a.system_name or "") ~= (b.system_name or "") then
        return (a.system_name or "") < (b.system_name or "")
    end
    return (a.body.distance_ls or 0) < (b.body.distance_ls or 0)
end

local function compare_by_price(a, b)
    if (a.sort_value or 0) ~= (b.sort_value or 0) then
        return (a.sort_value or 0) > (b.sort_value or 0)
    end
    return compare_by_body(a, b)
end

local SORT_COMPARATORS = {
    body  = compare_by_body,
    price = compare_by_price,
}

local DEFAULT_SORT_MODE = "price"

local function comparator_for(sort_mode)
    return SORT_COMPARATORS[sort_mode or DEFAULT_SORT_MODE]
        or SORT_COMPARATORS[DEFAULT_SORT_MODE]
end

local function build_cards(settings, hide_system, sort_mode, hide_scanned)
    local list = {}
    for _, item in ipairs(plugin_state.systems_sorted()) do
        for _, body in pairs(item.system.bodies) do
            if not should_skip_body(body, settings, hide_scanned) then
                table.insert(list, build_card(body, item.system.name, hide_system))
            end
        end
    end
    table.sort(list, comparator_for(sort_mode))
    return list
end

local function badges_inner_width(card_w)
    return card_w - CARD_PAD_X * 2
end

local function compute_card_layout(card, card_w)
    card.badge_rows = layout_badge_rows(card.badges, badges_inner_width(card_w))
    card.layout_w   = card_w
end

local function card_height(card)
    local h = CARD_PAD_Y * 2 + CARD_HEADER_H + CARD_DISTANCE_H + CARD_SUB_H
    local badges_h = badges_block_height(card.badge_rows)
    if badges_h > 0 then
        h = h + CARD_INTERNAL_GAP + badges_h
    end
    if card.footer then
        h = h + FOOTER_GAP + FOOTER_H
    end
    return h
end

local function draw_card_panel(x, y, w, h, is_high_value)
    local accent_color = is_high_value and theme.colors.accent
        or theme.colors.accent_rule
    panel.draw(x, y, w, h, {
        bg            = theme.colors.panel,
        border        = theme.colors.rule,
        left_accent   = accent_color,
        left_accent_w = is_high_value and 3 or 2,
    })
end

local function draw_card_title(card, x, y, w)
    local title_font = font_for(FONT_TITLE)
    local value_font = font_for(FONT_VALUE)
    local value_w = text.width(card.value_text, value_font, 0.1)
    local title_w = math.max(0, w - value_w - TITLE_TRAILING_GAP)
    local fitted = text.truncate_right(card.title, title_font, title_w, 0)
    text.draw(fitted, x, y, {
        font = title_font, color = theme.colors.text,
        bold = card.is_high_value,
    })
    text.draw(card.value_text, x + w - value_w, y + 2, {
        font = value_font, color = theme.colors.accent, letter_em = 0.1,
        bold = card.is_high_value,
    })
end

local function draw_card_distance(card, x, y, w)
    if not card.distance_text or card.distance_text == constants.UNKNOWN_TEXT then
        return
    end
    local dist_font = font_for(FONT_DISTANCE)
    local dist_w = text.width(card.distance_text, dist_font, 0.05)
    text.draw(card.distance_text, x + w - dist_w, y, {
        font = dist_font, color = theme.colors.text, letter_em = 0.05,
    })
end

local function draw_card_subheader(card, x, y, w)
    if #card.sub_parts == 0 then return end
    local sub_font = font_for(FONT_SUB)
    local joined = table.concat(card.sub_parts, SUB_PARTS_SEP)
    local fitted = text.truncate_right(joined, sub_font, w, 0.06)
    text.draw(fitted, x, y, {
        font = sub_font, color = theme.colors.text_dim, letter_em = 0.06,
    })
end

local function draw_badge_background(badge, x, y)
    local style = BADGE_STYLES[badge.kind] or BADGE_STYLES[KIND_INFO]
    if style.bg_color then
        love.graphics.setColor(theme.colors[style.bg_color])
        love.graphics.rectangle("fill", x, y, badge.width, BADGE_ROW_H,
            BADGE_RADIUS, BADGE_RADIUS)
    end
    if style.outline_color then
        love.graphics.setColor(theme.colors[style.outline_color])
        love.graphics.rectangle("line",
            x + 0.5, y + 0.5, badge.width - 1, BADGE_ROW_H - 1,
            BADGE_RADIUS, BADGE_RADIUS)
    end
end

local function draw_badge(badge, x, y)
    draw_badge_background(badge, x, y)
    local font  = font_for(FONT_BADGE)
    local style = BADGE_STYLES[badge.kind] or BADGE_STYLES[KIND_INFO]
    local label_y = y + math.floor((BADGE_ROW_H - font:getHeight()) / 2)
    text.draw(badge.label, x + BADGE_PAD_X, label_y, {
        font = font, color = theme.colors[style.text_color],
        letter_em = 0.08, bold = style.is_emphasis,
    })
end

local function draw_badge_rows(card, x, y)
    if #card.badge_rows == 0 then return y end
    local cy = y
    for i, row in ipairs(card.badge_rows) do
        if i > 1 then cy = cy + BADGE_GAP_Y end
        local cx = x
        for j, badge in ipairs(row) do
            if j > 1 then cx = cx + BADGE_GAP_X end
            draw_badge(badge, cx, cy)
            cx = cx + badge.width
        end
        cy = cy + BADGE_ROW_H
    end
    return cy
end

local function draw_footer(card, x, y, w)
    if not card.footer then return end
    local font = font_for(FONT_FOOTER)
    local fitted = text.truncate_right(card.footer.label, font, w, 0.04)
    text.draw(fitted, x, y, {
        font = font, color = theme.colors[card.footer.color_key],
        letter_em = 0.04,
    })
end

local function draw_card(card, x, y, w, h)
    h = h or card_height(card)
    draw_card_panel(x, y, w, h, card.is_high_value)
    local inner_x = x + CARD_PAD_X
    local inner_w = w - CARD_PAD_X * 2
    local cy = y + CARD_PAD_Y
    draw_card_title(card, inner_x, cy, inner_w)
    cy = cy + CARD_HEADER_H
    draw_card_distance(card, inner_x, cy, inner_w)
    cy = cy + CARD_DISTANCE_H
    draw_card_subheader(card, inner_x, cy, inner_w)
    cy = cy + CARD_SUB_H
    if #card.badge_rows > 0 then
        cy = cy + CARD_INTERNAL_GAP
        cy = draw_badge_rows(card, inner_x, cy)
    end
    if card.footer then
        cy = cy + FOOTER_GAP
        draw_footer(card, inner_x, cy, inner_w)
    end
    return h
end

local function column_count_for(available_w)
    local n = math.floor(available_w / MIN_CARD_W)
    if n < 1 then return 1 end
    if n > MAX_COLUMNS then return MAX_COLUMNS end
    return n
end

local function card_width_for(available_w, columns)
    local total_gap = (columns - 1) * CARD_GAP
    return math.floor((available_w - total_gap) / columns)
end

local function build_grid_layout(cards, available_w)
    local columns = column_count_for(available_w)
    local card_w  = card_width_for(available_w, columns)
    local rows    = {}
    local current = { cards = {}, height = 0 }
    for _, card in ipairs(cards) do
        compute_card_layout(card, card_w)
        if #current.cards >= columns then
            table.insert(rows, current)
            current = { cards = {}, height = 0 }
        end
        local h = card_height(card)
        table.insert(current.cards, card)
        if h > current.height then current.height = h end
    end
    if #current.cards > 0 then table.insert(rows, current) end
    return { rows = rows, columns = columns, card_w = card_w }
end

local function compute_content_height(layout)
    local total = 0
    for i, row in ipairs(layout.rows) do
        if i > 1 then total = total + CARD_GAP end
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

local function draw_empty_state(x, y, w, h)
    local font = font_for(FONT_EMPTY)
    text.draw("(no bodies above the value threshold)",
        x, y + h / 2 - font:getHeight() / 2, {
            font = font, color = theme.colors.text_faint,
            align = "center", width = w, letter_em = 0.06,
        })
end

local function draw_grid(layout, view_state, x, y, w, h)
    love.graphics.setScissor(x, y, w, h)
    local cy = y - view_state.scroll
    for _, row in ipairs(layout.rows) do
        if cy + row.height >= y and cy <= y + h then
            for i, card in ipairs(row.cards) do
                local card_x = x + (i - 1) * (layout.card_w + CARD_GAP)
                draw_card(card, card_x, cy, layout.card_w, row.height)
            end
        end
        cy = cy + row.height + CARD_GAP
    end
    love.graphics.setScissor()
end

function CARD_VIEW.card_count(settings, hide_scanned)
    local count = 0
    for _, item in ipairs(plugin_state.systems_sorted()) do
        for _, body in pairs(item.system.bodies) do
            if not should_skip_body(body, settings, hide_scanned) then
                count = count + 1
            end
        end
    end
    return count
end

function CARD_VIEW.draw(view_state, x, y, w, h, settings, hide_system, sort_mode, hide_scanned)
    view_state = view_state or {}
    view_state.scroll = view_state.scroll or 0
    handle_wheel(view_state, x, y, w, h)
    local cards = build_cards(settings, hide_system, sort_mode, hide_scanned)
    if #cards == 0 then
        draw_empty_state(x, y, w, h)
        return view_state
    end
    local layout = build_grid_layout(cards, w - SCROLLBAR_RESERVE)
    local content_h = compute_content_height(layout)
    local max_scroll = clamp_scroll(view_state, content_h, h)
    draw_grid(layout, view_state, x, y, w - SCROLLBAR_RESERVE, h)
    draw_scrollbar(view_state, max_scroll, x, y, w, h, content_h)
    return view_state
end

return CARD_VIEW
