local theme           = require("observatory.ui.theme")
local input           = require("observatory.ui.input")
local text            = require("observatory.ui.text")
local panel           = require("observatory.ui.panel")
local plugin_state    = require("plugins.bioinsights.state")
local species_values  = require("plugins.bioinsights.species_values")
local variants        = require("plugins.bioinsights.variants")
local constants       = require("plugins.bioinsights.constants")

local CARD_GAP            = 12
local CARD_PAD_X          = 14
local CARD_PAD_Y          = 12
local CARD_HEADER_H       = 22
local CARD_SUB_H          = 18
local CARD_INTERNAL_GAP   = 10
local GENUS_HEADER_H      = 22
local SPECIES_ROW_H       = 22
local SECTION_GAP         = 6
local STATUS_BADGE_W      = 18
local STATUS_BADGE_SIZE   = 9
local STATUS_BADGE_INSET  = 1
local STATUS_BADGE_LINE_W = 1.6
local SCAN_DOTS_TOTAL     = 3
local SCAN_DOT_RADIUS     = 3
local SCAN_DOT_GAP        = 4
local SCAN_DOTS_WIDTH     = SCAN_DOTS_TOTAL * SCAN_DOT_RADIUS * 2
                            + (SCAN_DOTS_TOTAL - 1) * SCAN_DOT_GAP
local SCROLLBAR_RESERVE   = 6
local SCROLLBAR_W         = 3
local WHEEL_STEP_PX       = 40
local SPECIES_VARIANT_GAP = 8
local SUB_PARTS_SEP       = "  -  "
local MIN_CARD_W          = 300
local MAX_COLUMNS         = 4

local FONT_TITLE          = { family = "main_medium", size = 14 }
local FONT_BODY_VALUE     = { family = "mono",        size = 11 }
local FONT_SUB            = { family = "mono",        size = 10 }
local FONT_GENUS          = { family = "mono_medium", size = 11 }
local FONT_SPECIES        = { family = "mono",        size = 11 }
local FONT_META           = { family = "mono",        size = 10 }

local HIGH_VALUE_BOLD_THRESHOLD = 2 * 1000000

local STATUS_CONFIRMED = "confirmed"
local STATUS_PREDICTED = "predicted"
local STATUS_PENDING   = "pending"
local STATUS_EXCLUDED  = "excluded"

local function draw_check_icon(x, y, size)
    local s = size - STATUS_BADGE_INSET * 2
    local ox = x + STATUS_BADGE_INSET
    local oy = y + STATUS_BADGE_INSET
    love.graphics.line(
        ox,             oy + s * 0.55,
        ox + s * 0.38,  oy + s * 0.92,
        ox + s,         oy + s * 0.18
    )
end

local function draw_arrow_icon(x, y, size)
    local s = size - STATUS_BADGE_INSET * 2
    local ox = x + STATUS_BADGE_INSET
    local oy = y + STATUS_BADGE_INSET
    love.graphics.polygon("fill",
        ox + s * 0.20, oy + s * 0.10,
        ox + s * 0.95, oy + s * 0.50,
        ox + s * 0.20, oy + s * 0.90
    )
end

local function draw_dot_icon(x, y, size)
    local cx = x + size * 0.5
    local cy = y + size * 0.5
    love.graphics.circle("fill", cx, cy, math.max(1, size * 0.18))
end

local STATUS_BADGE = {
    [STATUS_CONFIRMED] = { draw = draw_check_icon, color_key = "success",  line_w = STATUS_BADGE_LINE_W },
    [STATUS_PREDICTED] = { draw = draw_arrow_icon, color_key = "accent",   line_w = 1 },
    [STATUS_PENDING]   = { draw = draw_dot_icon,   color_key = "text_dim", line_w = 1 },
}

local function scan_dot_color_key(dot_index, scans)
    if scans >= SCAN_DOTS_TOTAL then return "success" end
    if dot_index <= scans then return "accent" end
    return "text_faint"
end

local function draw_scan_dots(scans, x, y)
    local cy = y + SCAN_DOT_RADIUS
    for i = 1, SCAN_DOTS_TOTAL do
        local cx = x + SCAN_DOT_RADIUS
            + (i - 1) * (SCAN_DOT_RADIUS * 2 + SCAN_DOT_GAP)
        love.graphics.setColor(theme.colors[scan_dot_color_key(i, scans)])
        love.graphics.circle("fill", cx, cy, SCAN_DOT_RADIUS)
    end
end

local STATUS_RANK = {
    [STATUS_CONFIRMED] = 1,
    [STATUS_PREDICTED] = 2,
    [STATUS_PENDING]   = 3,
}

local STATUS_FALLBACK_RANK = 9

local SPECIES_LABEL_COLOR = {
    [STATUS_CONFIRMED] = "text",
    [STATUS_PREDICTED] = "text",
    [STATUS_PENDING]   = "text_dim",
}

local GENUS_RIGHT_LABEL = {
    confirmed = function(entry) return { kind = "scans", scans = entry.sample_index or 0 } end,
    predicted = function(_)     return { kind = "scans", scans = 0 } end,
    pending   = function(_)     return nil end,
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

local function format_number(value)
    if not value or value <= 0 then return constants.UNKNOWN_TEXT end
    return format_thousand_million(value)
end

local function format_value_str(value)
    if not value or value <= 0 then return constants.UNKNOWN_TEXT end
    return string.format(constants.VALUE_FORMAT, format_thousand_million(value))
end

local function format_distance(distance_ls)
    if not distance_ls or distance_ls <= 0 then
        return constants.UNKNOWN_TEXT
    end
    return string.format(constants.DISTANCE_FORMAT, distance_ls)
end

local function genus_value_bounds(body, genus_label)
    local entry = body.genus_entries[genus_label]
    if not entry then
        local range = species_values.for_genus(genus_label)
        if range then return range.min, range.max end
        return 0, 0
    end
    local lo, hi
    for species_label, status in pairs(entry.species_states) do
        if status ~= STATUS_EXCLUDED then
            local v = species_values.for_species(species_label) or 0
            if status == STATUS_CONFIRMED then return v, v end
            if not lo or v < lo then lo = v end
            if not hi or v > hi then hi = v end
        end
    end
    if not lo then return 0, 0 end
    return lo, hi
end

local function body_value_bounds(body)
    local total_lo, total_hi = 0, 0
    for _, genus_label in ipairs(body.genus_order) do
        local lo, hi = genus_value_bounds(body, genus_label)
        total_lo = total_lo + lo
        total_hi = total_hi + hi
    end
    return total_lo, total_hi
end

local function format_body_value(body)
    local lo, hi = body_value_bounds(body)
    if hi <= 0 then return constants.UNKNOWN_TEXT end
    if lo == hi then return format_value_str(lo) end
    return string.format(constants.VALUE_RANGE_FORMAT,
        format_number(lo), format_number(hi))
end

local function exact_value_for_entry(entry)
    if entry.confirmed_value and entry.confirmed_value > 0 then
        return entry.confirmed_value
    end
    if not entry.species_label then return nil end
    return species_values.for_species(entry.species_label)
end

local function genus_potential_max(entry, genus_label)
    local exact = exact_value_for_entry(entry)
    if exact then return exact end
    local range = species_values.for_genus(genus_label)
    if range then return range.max end
    return 0
end

local function body_potential_max(body)
    local best = 0
    for _, genus_label in ipairs(body.genus_order) do
        local v = genus_potential_max(body.genus_entries[genus_label], genus_label)
        if v > best then best = v end
    end
    return best
end

local function should_skip_body(body, settings)
    if not body then return true end
    if body.biological_count <= 0 and #body.genus_order == 0 then
        return true
    end
    if not settings or not settings.only_show_high_value then return false end
    if #body.genus_order == 0 then return false end
    return body_potential_max(body) < (settings.minimum_high_value or 0)
end

local function status_for_species(entry, species_label)
    local status = entry.species_states[species_label] or STATUS_PENDING
    if status == STATUS_PENDING and entry.dss_confirmed then
        return STATUS_PREDICTED
    end
    return status
end

local function genus_status(entry)
    if entry.species_label then return STATUS_CONFIRMED end
    if entry.dss_confirmed then return STATUS_PREDICTED end
    return STATUS_PENDING
end

local function species_short_name(label)
    local stripped = label:gsub("^%S+%s*", "")
    if stripped == "" then return label end
    return stripped
end

local function variant_for_species(species_label, status, entry, body)
    if status == STATUS_CONFIRMED and entry.variant_label then
        return entry.variant_label
    end
    return variants.predict_for(species_label, body)
end

local function build_species_entries(entry, body)
    local list = {}
    for _, species_label in ipairs(entry.species_order) do
        local status = status_for_species(entry, species_label)
        if status ~= STATUS_EXCLUDED then
            local raw_value = species_values.for_species(species_label) or 0
            table.insert(list, {
                label         = species_label,
                short         = species_short_name(species_label),
                status        = status,
                variant       = variant_for_species(species_label, status, entry, body),
                value         = format_value_str(raw_value),
                is_high_value = raw_value >= HIGH_VALUE_BOLD_THRESHOLD,
            })
        end
    end
    table.sort(list, function(a, b)
        local ra = STATUS_RANK[a.status] or STATUS_FALLBACK_RANK
        local rb = STATUS_RANK[b.status] or STATUS_FALLBACK_RANK
        if ra ~= rb then return ra < rb end
        return a.label < b.label
    end)
    return list
end

local function any_species_high_value(species_list)
    for _, sp in ipairs(species_list) do
        if sp.is_high_value then return true end
    end
    return false
end

local function build_genus_block(body, genus_label)
    local entry = body.genus_entries[genus_label]
    local status = genus_status(entry)
    local right_resolver = GENUS_RIGHT_LABEL[status]
    local species = build_species_entries(entry, body)
    return {
        label         = genus_label,
        entry         = entry,
        status        = status,
        species       = species,
        right         = right_resolver and right_resolver(entry) or nil,
        is_high_value = any_species_high_value(species),
    }
end

local function display_body_name(body)
    if body.name and body.name ~= "" and body.name ~= "?" then
        return body.name
    end
    return constants.UNNAMED_BODY_PLACEHOLDER
end

local function star_label(body)
    if body.parent_star_type and body.parent_star_type ~= "" then
        return body.parent_star_type
    end
    return constants.UNKNOWN_TEXT
end

local function body_type_label(body)
    if body.body_type and body.body_type ~= "" then
        return body.body_type
    end
    return constants.UNKNOWN_TEXT
end

local function bios_label(body)
    local count = body.biological_count or 0
    local plural = count == 1 and "" or "s"
    return string.format("%d bio%s", count, plural)
end

local function build_card(body, system_name)
    local card = {
        body           = body,
        system_name    = system_name,
        title          = display_body_name(body),
        body_type      = body_type_label(body),
        star           = star_label(body),
        distance       = format_distance(body.distance_ls),
        body_value     = format_body_value(body),
        bios           = bios_label(body),
        genuses        = {},
        unmapped_count = 0,
    }
    if #body.genus_order == 0 then
        card.unmapped_count = body.biological_count or 0
        return card
    end
    for _, genus_label in ipairs(body.genus_order) do
        table.insert(card.genuses, build_genus_block(body, genus_label))
    end
    return card
end

local function build_cards(settings)
    local list = {}
    for _, item in ipairs(plugin_state.systems_sorted()) do
        for _, body in pairs(item.system.bodies) do
            if not should_skip_body(body, settings) then
                table.insert(list, build_card(body, item.system.name))
            end
        end
    end
    table.sort(list, function(a, b)
        if (a.system_name or "") ~= (b.system_name or "") then
            return (a.system_name or "") < (b.system_name or "")
        end
        return (a.body.distance_ls or 0) < (b.body.distance_ls or 0)
    end)
    return list
end

local function genus_block_height(block)
    local rows = math.max(1, #block.species)
    return GENUS_HEADER_H + rows * SPECIES_ROW_H
end

local function genuses_height(card)
    local total = 0
    for i, block in ipairs(card.genuses) do
        if i > 1 then total = total + SECTION_GAP end
        total = total + genus_block_height(block)
    end
    return total
end

local function card_height(card)
    local h = CARD_PAD_Y * 2 + CARD_HEADER_H + CARD_SUB_H
    if card.unmapped_count > 0 and #card.genuses == 0 then
        return h + CARD_INTERNAL_GAP + GENUS_HEADER_H
    end
    if #card.genuses == 0 then return h end
    return h + CARD_INTERNAL_GAP + genuses_height(card)
end

local function draw_card_title(card, x, y, w)
    local title_font = font_for(FONT_TITLE)
    local value_font = font_for(FONT_BODY_VALUE)
    local rw = text.width(card.body_value, value_font, 0.1)
    local title_w = math.max(0, w - rw - 12)
    local fitted = text.truncate_right(card.title, title_font, title_w, 0)
    text.draw(fitted, x, y, {
        font = title_font, color = theme.colors.text,
    })
    text.draw(card.body_value, x + w - rw, y + 2, {
        font = value_font, color = theme.colors.accent, letter_em = 0.1,
    })
end

local function build_subheader_parts(card)
    local parts = { card.body_type, card.star, card.distance, card.bios }
    if card.system_name and card.system_name ~= "" and card.system_name ~= "?" then
        table.insert(parts, 1, card.system_name)
    end
    return parts
end

local function draw_card_subheader(card, x, y, w)
    local sub_font = font_for(FONT_SUB)
    local joined = table.concat(build_subheader_parts(card), SUB_PARTS_SEP)
    local fitted = text.truncate_right(joined, sub_font, w, 0.06)
    text.draw(fitted, x, y, {
        font = sub_font, color = theme.colors.text_dim, letter_em = 0.06,
    })
end

local function draw_right_scans(payload, x, y, w)
    local meta_font = font_for(FONT_META)
    local dot_y = y + math.floor((meta_font:getHeight() - SCAN_DOT_RADIUS * 2) / 2) + 1
    draw_scan_dots(payload.scans, x + w - SCAN_DOTS_WIDTH, dot_y)
end

local GENUS_RIGHT_RENDERERS = {
    scans = draw_right_scans,
}

local function draw_genus_header(block, x, y, w)
    local genus_font = font_for(FONT_GENUS)
    text.draw(block.label, x, y, {
        font = genus_font, color = theme.colors.text, letter_em = 0.08,
        bold = block.is_high_value,
    })
    if not block.right then return end
    local renderer = GENUS_RIGHT_RENDERERS[block.right.kind]
    if not renderer then return end
    renderer(block.right, x, y, w)
end

local function species_label_color(status)
    local key = SPECIES_LABEL_COLOR[status] or "text_dim"
    return theme.colors[key]
end

local function draw_species_badge(sp, x, y)
    local species_font = font_for(FONT_SPECIES)
    local badge = STATUS_BADGE[sp.status] or STATUS_BADGE[STATUS_PENDING]
    local icon_y = y + math.floor((species_font:getHeight() - STATUS_BADGE_SIZE) / 2)
    local prev_w = love.graphics.getLineWidth()
    love.graphics.setLineWidth(badge.line_w)
    love.graphics.setColor(theme.colors[badge.color_key])
    badge.draw(x, icon_y, STATUS_BADGE_SIZE)
    love.graphics.setLineWidth(prev_w)
end

local function draw_species_variant(sp, x, y, max_w)
    if not sp.variant or sp.variant == "" then return end
    if max_w <= 0 then return end
    local meta_font = font_for(FONT_META)
    local fitted = text.truncate_right("(" .. sp.variant .. ")",
        meta_font, max_w, 0.04)
    text.draw(fitted, x, y + 1, {
        font = meta_font, color = theme.colors.text_faint, letter_em = 0.04,
        bold = sp.is_high_value,
    })
end

local function draw_species_value(sp, x, y, w)
    local meta_font = font_for(FONT_META)
    local rw = text.width(sp.value, meta_font, 0.06)
    local color_key = sp.is_high_value and "text" or "text_dim"
    text.draw(sp.value, x + w - rw, y + 1, {
        font = meta_font, color = theme.colors[color_key], letter_em = 0.06,
        bold = sp.is_high_value,
    })
    return rw
end

local function draw_species_row(sp, x, y, w)
    local species_font = font_for(FONT_SPECIES)
    draw_species_badge(sp, x, y)
    local label_x = x + STATUS_BADGE_W
    text.draw(sp.short, label_x, y, {
        font = species_font, color = species_label_color(sp.status),
        bold = sp.is_high_value,
    })
    local label_w = text.width(sp.short, species_font, 0)
    local value_w = draw_species_value(sp, x, y, w)
    local variant_x = label_x + label_w + SPECIES_VARIANT_GAP
    local variant_max_w = (x + w - value_w - SPECIES_VARIANT_GAP) - variant_x
    draw_species_variant(sp, variant_x, y, variant_max_w)
end

local function draw_genus_block(block, x, y, w)
    draw_genus_header(block, x, y, w)
    local cy = y + GENUS_HEADER_H
    for _, sp in ipairs(block.species) do
        draw_species_row(sp, x, cy, w)
        cy = cy + SPECIES_ROW_H
    end
    return cy
end

local function draw_unmapped_section(card, x, y)
    local font = font_for(FONT_SPECIES)
    local label = string.format("%s x %d",
        constants.PENDING_BIO_PLACEHOLDER, card.unmapped_count)
    text.draw(label, x, y, {
        font = font, color = theme.colors.text_faint, letter_em = 0.04,
    })
end

local function draw_card_body(card, x, y, w)
    if card.unmapped_count > 0 and #card.genuses == 0 then
        draw_unmapped_section(card, x, y)
        return
    end
    local cy = y
    for i, block in ipairs(card.genuses) do
        if i > 1 then cy = cy + SECTION_GAP end
        cy = draw_genus_block(block, x, cy, w)
    end
end

local function draw_card_panel(x, y, w, h)
    panel.draw(x, y, w, h, {
        bg = theme.colors.panel,
        border = theme.colors.rule,
        left_accent = theme.colors.accent_rule,
        left_accent_w = 2,
    })
end

local function draw_card(card, x, y, w, h)
    h = h or card_height(card)
    draw_card_panel(x, y, w, h)
    local inner_x = x + CARD_PAD_X
    local inner_w = w - CARD_PAD_X * 2
    local cy = y + CARD_PAD_Y
    draw_card_title(card, inner_x, cy, inner_w)
    cy = cy + CARD_HEADER_H
    draw_card_subheader(card, inner_x, cy, inner_w)
    cy = cy + CARD_SUB_H
    if card.unmapped_count == 0 and #card.genuses == 0 then return h end
    cy = cy + CARD_INTERNAL_GAP
    draw_card_body(card, inner_x, cy, inner_w)
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
    local card_w = card_width_for(available_w, columns)
    local rows = {}
    local current = { cards = {}, height = 0 }
    for _, card in ipairs(cards) do
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
    local font = font_for(FONT_SPECIES)
    text.draw("(no biology data)", x, y + h / 2 - font:getHeight() / 2, {
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

function CARD_VIEW.card_count(settings)
    local count = 0
    for _, item in ipairs(plugin_state.systems_sorted()) do
        for _, body in pairs(item.system.bodies) do
            if not should_skip_body(body, settings) then
                count = count + 1
            end
        end
    end
    return count
end

function CARD_VIEW.draw(view_state, x, y, w, h, settings)
    view_state = view_state or {}
    view_state.scroll = view_state.scroll or 0
    handle_wheel(view_state, x, y, w, h)
    local cards = build_cards(settings)
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
