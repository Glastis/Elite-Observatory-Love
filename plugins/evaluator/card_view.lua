local theme        = require("observatory.ui.theme")
local text         = require("observatory.ui.text")
local badge        = require("observatory.ui.badge")
local card_view    = require("observatory.ui.card_view")
local format       = require("observatory.plugin_helpers.format")
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
local BADGE_GAP_X          = 5
local BADGE_GAP_Y          = 4
local BADGE_LETTER_EM      = 0.08
local FOOTER_H             = 18
local FOOTER_GAP           = 6
local SUB_PARTS_SEP        = "  -  "
local MIN_CARD_W           = 320
local MAX_COLUMNS          = 4
local UNNAMED_PLACEHOLDER  = "(unscanned)"
local TITLE_TRAILING_GAP   = 12
local ACCENT_W_NORMAL      = 2
local ACCENT_W_PREMIUM     = 3
local VALUE_TOP_NUDGE      = 2
local VALUE_LETTER_EM      = 0.1
local DISTANCE_LETTER_EM   = 0.05
local SUB_LETTER_EM        = 0.06
local FOOTER_LETTER_EM     = 0.04
local EMPTY_MESSAGE        = "(no bodies above the value threshold)"

local FONT_TITLE    = { family = "main_medium", size = 14 }
local FONT_VALUE    = { family = "mono",        size = 11 }
local FONT_DISTANCE = { family = "mono_medium", size = 11 }
local FONT_SUB      = { family = "mono",        size = 10 }
local FONT_BADGE    = { family = "mono_medium", size = 9  }
local FONT_FOOTER   = { family = "mono",        size = 10 }
local FONT_EMPTY    = { family = "mono",        size = 11 }

local HIGH_VALUE_BOLD_THRESHOLD = 2 * 1000000

local KIND_PREMIUM = "premium"
local KIND_BONUS   = "bonus"
local KIND_INFO    = "info"

local FOOTER_MAP_FOR         = "Map for +%s"
local FOOTER_MAPPED_BY_YOU   = "Mapped by you"
local FOOTER_MAPPED_BY_OTHER = "Mapped by another commander"
local FOOTER_STAR_VALUE      = "Star value: %s"

local BADGE_LABEL_FIRST_DISCOVERY = "FIRST DISCOVERY"
local BADGE_LABEL_FIRST_MAPPING   = "FIRST MAPPING"
local BADGE_LABEL_MAPPED_BY_YOU   = "MAPPED BY YOU"
local BADGE_LABEL_MAPPED_BY_OTHER = "MAPPED BY ANOTHER"
local BADGE_LABEL_TERRAFORM       = "TERRAFORM"
local BADGE_LABEL_WORTH_MAPPING   = "WORTH MAPPING"
local BADGE_LABEL_LANDABLE        = "LANDABLE"
local BADGE_LABEL_ATMO            = "ATMO"
local BADGE_LABEL_VOLCANIC        = "VOLCANIC"

local FORMAT_SCALES = {
    { threshold = constants.VALUE_MILLION,  divider = constants.VALUE_MILLION,  format = constants.VALUE_MILLION_FORMAT },
    { threshold = constants.VALUE_THOUSAND, divider = constants.VALUE_THOUSAND, format = constants.VALUE_THOUSAND_FORMAT },
}

local BADGE_STYLES = {
    [KIND_PREMIUM] = { text_color = "bg",       bg_color = "accent",                          bold = true  },
    [KIND_BONUS]   = { text_color = "success",  outline_color = "success",                    bold = false },
    [KIND_INFO]    = { text_color = "text_dim", outline_color = "rule_strong",                bold = false },
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

local function format_value_str(value)
    if not value or value <= 0 then
        return constants.UNKNOWN_TEXT
    end
    return format.compact_number(value, FORMAT_SCALES, constants.UNKNOWN_TEXT) .. " cr"
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

local function display_body_name(body, system_name, hide_system)
    local name

    name = format.display_name(body, nil)
    if not name then
        return UNNAMED_PLACEHOLDER
    end
    if not hide_system then
        return name
    end
    return format.strip_system_prefix(name, system_name)
end

local function body_type_label(body)
    if body.body_type and body.body_type ~= "" then
        return body.body_type
    end
    return constants.UNKNOWN_TEXT
end

local function append_part(list, value)
    if not value or value == "" or value == constants.UNKNOWN_TEXT then
        return
    end
    table.insert(list, value)
end

local function build_subheader_parts(body)
    local parts

    parts = {}
    append_part(parts, body_type_label(body))
    append_part(parts, format_gravity(body.gravity_ms2))
    if body.atmosphere and body.atmosphere ~= "" then
        append_part(parts, body.atmosphere)
    end
    return parts
end

local function is_currently_mapped(body)
    return body.was_mapped or body.mapped_by_player
end

local function build_premium_planet_badge(body)
    return { label = PREMIUM_PLANET_LABEL[body.body_type], kind = KIND_PREMIUM }
end

local function build_terraform_badge()
    return { label = BADGE_LABEL_TERRAFORM, kind = KIND_PREMIUM }
end

local function build_first_discovery_badge()
    return { label = BADGE_LABEL_FIRST_DISCOVERY, kind = KIND_BONUS }
end

local function build_first_mapping_badge()
    return { label = BADGE_LABEL_FIRST_MAPPING, kind = KIND_BONUS }
end

local function build_mapped_by_you_badge()
    return { label = BADGE_LABEL_MAPPED_BY_YOU, kind = KIND_BONUS }
end

local function build_mapped_by_other_badge()
    return { label = BADGE_LABEL_MAPPED_BY_OTHER, kind = KIND_INFO }
end

local function build_worth_mapping_badge()
    return { label = BADGE_LABEL_WORTH_MAPPING, kind = KIND_PREMIUM }
end

local function build_landable_badge()
    return { label = BADGE_LABEL_LANDABLE, kind = KIND_INFO }
end

local function build_atmo_badge()
    return { label = BADGE_LABEL_ATMO, kind = KIND_INFO }
end

local function build_volcanic_badge()
    return { label = BADGE_LABEL_VOLCANIC, kind = KIND_INFO }
end

local BADGE_BUILDERS = {
    {
        active = function(body) return PREMIUM_PLANET_LABEL[body.body_type] ~= nil end,
        build  = build_premium_planet_badge,
    },
    {
        active = function(body) return body.terraformable end,
        build  = build_terraform_badge,
    },
    {
        active = function(body) return not body.was_discovered end,
        build  = build_first_discovery_badge,
    },
    {
        active = function(body)
            return not body.is_star and not body.was_mapped and not body.mapped_by_player
        end,
        build  = build_first_mapping_badge,
    },
    {
        active = function(body) return body.mapped_by_player end,
        build  = build_mapped_by_you_badge,
    },
    {
        active = function(body)
            return body.was_mapped and not body.mapped_by_player and not body.is_star
        end,
        build  = build_mapped_by_other_badge,
    },
    {
        active = function(body) return body.worth_mapping and not is_currently_mapped(body) end,
        build  = build_worth_mapping_badge,
    },
    {
        active = function(body) return body.is_landable end,
        build  = build_landable_badge,
    },
    {
        active = function(body) return body.atmosphere and body.atmosphere ~= "" end,
        build  = build_atmo_badge,
    },
    {
        active = function(body) return body.volcanism and body.volcanism ~= "" end,
        build  = build_volcanic_badge,
    },
}

local function badge_item_for(badge_def)
    local font
    local width

    font = font_for(FONT_BADGE)
    width = badge.measure(badge_def.label, font, {
        pad_x = BADGE_PAD_X, h = BADGE_ROW_H, letter_em = BADGE_LETTER_EM,
    })
    return {
        label = badge_def.label,
        style = BADGE_STYLES[badge_def.kind] or BADGE_STYLES[KIND_INFO],
        width = width,
    }
end

local function build_badges(body)
    local list

    list = {}
    for _, builder in ipairs(BADGE_BUILDERS) do
        if builder.active(body) then
            table.insert(list, badge_item_for(builder.build(body)))
        end
    end
    return list
end

local function map_for_delta(body)
    return (body.potential_max or 0) - (body.current_value or 0)
end

local function has_map_for_footer(body)
    if body.is_star or is_currently_mapped(body) or not body.worth_mapping then
        return false
    end
    return map_for_delta(body) > 0
end

local function build_map_for_footer(body)
    return {
        label = string.format(FOOTER_MAP_FOR, format_value_str(map_for_delta(body))),
        color_key = "accent",
    }
end

local function build_mapped_by_you_footer()
    return { label = FOOTER_MAPPED_BY_YOU, color_key = "success" }
end

local function build_mapped_by_other_footer()
    return { label = FOOTER_MAPPED_BY_OTHER, color_key = "text_dim" }
end

local function build_star_value_footer(body)
    return {
        label = string.format(FOOTER_STAR_VALUE, format_value_str(body.current_value)),
        color_key = "text_dim",
    }
end

local FOOTER_BUILDERS = {
    {
        active = has_map_for_footer,
        build  = build_map_for_footer,
    },
    {
        active = function(body) return body.mapped_by_player and not body.is_star end,
        build  = build_mapped_by_you_footer,
    },
    {
        active = function(body)
            return body.was_mapped and not body.mapped_by_player and not body.is_star
        end,
        build  = build_mapped_by_other_footer,
    },
    {
        active = function(body) return body.is_star end,
        build  = build_star_value_footer,
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
    if body.is_star then
        return body.current_value or 0
    end
    return body.potential_max or 0
end

local function build_card(body, system_name, hide_system)
    return {
        body          = body,
        system_name   = system_name,
        title         = display_body_name(body, system_name, hide_system),
        sub_parts     = build_subheader_parts(body),
        value_text    = format_value_str(predicted_value(body)),
        distance_text = format_distance(body.distance_ls),
        is_high_value = predicted_value(body) >= HIGH_VALUE_BOLD_THRESHOLD,
        badges        = build_badges(body),
        footer        = build_footer(body),
        sort_value    = predicted_value(body),
    }
end

local function should_skip_body(body, settings, hide_scanned)
    if not body or not body.scanned then
        return true
    end
    if hide_scanned and is_currently_mapped(body) then
        return true
    end
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

local SORT_COMPARATORS = { body = compare_by_body, price = compare_by_price }
local DEFAULT_SORT_MODE = "price"

local function comparator_for(sort_mode)
    return SORT_COMPARATORS[sort_mode or DEFAULT_SORT_MODE]
        or SORT_COMPARATORS[DEFAULT_SORT_MODE]
end

local function build_cards(settings, hide_system, sort_mode, hide_scanned)
    local list
    local system

    list = {}
    system = plugin_state.current_system()
    if not system then
        return list
    end
    for _, body in pairs(system.bodies) do
        if not should_skip_body(body, settings, hide_scanned) then
            table.insert(list, build_card(body, system.name, hide_system))
        end
    end
    table.sort(list, comparator_for(sort_mode))
    return list
end

local function badges_inner_width(card_w)
    return card_w - CARD_PAD_X * 2
end

local function prepare_card(card, card_w)
    card.badge_rows = badge.layout_rows(card.badges, badges_inner_width(card_w), BADGE_GAP_X)
    card.layout_w   = card_w
end

local function card_height(card)
    local h
    local badges_h

    h = CARD_PAD_Y * 2 + CARD_HEADER_H + CARD_DISTANCE_H + CARD_SUB_H
    badges_h = badge.rows_height(card.badge_rows, BADGE_ROW_H, BADGE_GAP_Y)
    if badges_h > 0 then
        h = h + CARD_INTERNAL_GAP + badges_h
    end
    if card.footer then
        h = h + FOOTER_GAP + FOOTER_H
    end
    return h
end

local function panel_opts_for(card)
    local accent

    accent = card.is_high_value and theme.colors.accent or theme.colors.accent_rule
    return {
        left_accent = accent,
        left_accent_w = card.is_high_value and ACCENT_W_PREMIUM or ACCENT_W_NORMAL,
    }
end

local function draw_card_title(card, x, y, w)
    local title_font
    local value_font
    local value_w
    local title_w
    local fitted

    title_font = font_for(FONT_TITLE)
    value_font = font_for(FONT_VALUE)
    value_w = text.width(card.value_text, value_font, VALUE_LETTER_EM)
    title_w = math.max(0, w - value_w - TITLE_TRAILING_GAP)
    fitted = text.truncate_right(card.title, title_font, title_w, 0)
    text.draw(fitted, x, y, {
        font = title_font, color = theme.colors.text, bold = card.is_high_value,
    })
    text.draw(card.value_text, x + w - value_w, y + VALUE_TOP_NUDGE, {
        font = value_font, color = theme.colors.accent, letter_em = VALUE_LETTER_EM,
        bold = card.is_high_value,
    })
end

local function draw_card_distance(card, x, y, w)
    local dist_font
    local dist_w

    if not card.distance_text or card.distance_text == constants.UNKNOWN_TEXT then
        return
    end
    dist_font = font_for(FONT_DISTANCE)
    dist_w = text.width(card.distance_text, dist_font, DISTANCE_LETTER_EM)
    text.draw(card.distance_text, x + w - dist_w, y, {
        font = dist_font, color = theme.colors.text, letter_em = DISTANCE_LETTER_EM,
    })
end

local function draw_card_subheader(card, x, y, w)
    local sub_font
    local joined
    local fitted

    if #card.sub_parts == 0 then
        return
    end
    sub_font = font_for(FONT_SUB)
    joined = table.concat(card.sub_parts, SUB_PARTS_SEP)
    fitted = text.truncate_right(joined, sub_font, w, SUB_LETTER_EM)
    text.draw(fitted, x, y, {
        font = sub_font, color = theme.colors.text_dim, letter_em = SUB_LETTER_EM,
    })
end

local function draw_badge_rows(card, x, y)
    if #card.badge_rows == 0 then
        return y
    end
    return badge.draw_rows(card.badge_rows, x, y, font_for(FONT_BADGE), {
        h = BADGE_ROW_H, gap_x = BADGE_GAP_X, gap_y = BADGE_GAP_Y,
        pad_x = BADGE_PAD_X, letter_em = BADGE_LETTER_EM,
    })
end

local function draw_footer(card, x, y, w)
    local font
    local fitted

    if not card.footer then
        return
    end
    font = font_for(FONT_FOOTER)
    fitted = text.truncate_right(card.footer.label, font, w, FOOTER_LETTER_EM)
    text.draw(fitted, x, y, {
        font = font, color = theme.colors[card.footer.color_key], letter_em = FOOTER_LETTER_EM,
    })
end

local function draw_card(card, x, y, w, h)
    local inner_x
    local inner_w
    local cy

    h = h or card_height(card)
    card_view.draw_card_panel(x, y, w, h, panel_opts_for(card))
    inner_x = x + CARD_PAD_X
    inner_w = w - CARD_PAD_X * 2
    cy = y + CARD_PAD_Y
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

function CARD_VIEW.card_count(settings, hide_scanned)
    local count
    local system

    count = 0
    system = plugin_state.current_system()
    if not system then
        return count
    end
    for _, body in pairs(system.bodies) do
        if not should_skip_body(body, settings, hide_scanned) then
            count = count + 1
        end
    end
    return count
end

function CARD_VIEW.draw(view_state, x, y, w, h, settings, hide_system, sort_mode, hide_scanned)
    return card_view.draw(view_state, x, y, w, h, {
        gap = CARD_GAP,
        min_card_w = MIN_CARD_W,
        max_columns = MAX_COLUMNS,
        empty_message = EMPTY_MESSAGE,
        empty_font = font_for(FONT_EMPTY),
        build_cards = function()
            return build_cards(settings, hide_system, sort_mode, hide_scanned)
        end,
        prepare_card = prepare_card,
        card_height = card_height,
        draw_card = draw_card,
    })
end

return CARD_VIEW
