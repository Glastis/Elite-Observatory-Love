local theme           = require("observatory.ui.theme")
local text            = require("observatory.ui.text")
local input           = require("observatory.ui.input")
local panel           = require("observatory.ui.panel")
local card_view       = require("observatory.ui.card_view")
local format          = require("observatory.plugin_helpers.format")
local state           = require("plugins.construction.state")
local amounts         = require("plugins.construction.amounts")
local constants       = require("plugins.construction.constants")
local route_state     = require("plugins.construction.route_state")
local route_constants = require("plugins.construction.route_constants")

local CARD_GAP          = 12
local CARD_PAD_X        = 14
local CARD_PAD_Y        = 12
local CARD_HEADER_H     = 22
local PROGRESS_BAR_H    = 6
local PROGRESS_GAP      = 10
local CARD_TOTALS_H     = 16
local SECTION_GAP       = 10
local COL_HEADER_H      = 16
local RESOURCE_ROW_H    = 20
local RULE_H            = 1
local MIN_CARD_W        = 880
local MAX_COLUMNS       = 2
local NUM_RESERVE       = 64
local NUM_GAP           = 12
local NAME_TRAILING_GAP = 10
local HEADER_GAP        = 12
local PERCENT_TOP_NUDGE = 2

local BODY_COL_GAP       = 16
local VRULE_W            = 1
local ROUTE_COL_MIN_W    = 260
local ROUTE_COL_FRACTION = 0.6
local ROUTE_HEADER_H     = 16
local ROUTE_MESSAGE_H    = 24
local ROUTE_MAX_STOPS    = route_constants.PREVIEW_STOP_COUNT

local STOP_CARD_GAP   = 8
local STOP_CARD_PAD_X = 10
local STOP_CARD_PAD_Y = 8
local STOP_SYSTEM_H   = 20
local STOP_STATION_H  = 16
local STOP_RESOURCE_H = 16
local COPY_FEEDBACK_S = 1.6

local MENU_BTN_W       = 24
local MENU_BTN_GAP     = 6
local MENU_DOT_RADIUS  = 1.6
local MENU_DOT_SPACING = 5
local MENU_WIDTH       = 150
local MENU_ITEM_H      = 28
local MENU_PAD_Y       = 4
local MENU_ITEM_PAD_X  = 12
local MENU_ANCHOR_GAP  = 4

local PERCENT_LETTER_EM    = 0.05
local TOTALS_LETTER_EM     = 0.04
local COL_HEADER_LETTER_EM = 0.1

local PERCENT_ROUNDING = 0.5
local INT_FORMAT       = "%d"
local LY_NUMBER_FORMAT = "%.1f"

local EMPTY_MESSAGE      = "(no construction sites visited yet)"
local ALL_HIDDEN_MESSAGE = "(every site is hidden - enable Show Hidden)"
local ALL_DELIVERED_TEXT = "All commodities delivered"
local TOTALS_SEPARATOR   = "   -   "

local ROUTE_HEADER_LABEL   = "ROUTE"
local ROUTE_STOPS_FORMAT   = "%d STOPS"
local ROUTE_EMPTY_MESSAGE  = "No destinations"
local STOP_LY_FORMAT       = "%s ly"
local STOP_LS_FORMAT       = "%s ls"
local STOP_QTY_FORMAT      = "%s t"
local COPY_FEEDBACK_LABEL  = "Copied"

local FONT_TITLE      = { family = "main_medium", size = 14 }
local FONT_PERCENT    = { family = "mono_medium", size = 12 }
local FONT_TOTALS     = { family = "mono",        size = 10 }
local FONT_COL_HEADER = { family = "mono_medium", size = 9  }
local FONT_RESOURCE   = { family = "main",        size = 12 }
local FONT_NUMBER     = { family = "mono",        size = 11 }
local FONT_EMPTY      = { family = "mono",        size = 11 }
local FONT_MENU       = { family = "main",        size = 12 }
local FONT_ROUTE      = { family = "main",        size = 11 }
local FONT_STOP_SYSTEM   = { family = "main_medium", size = 12 }
local FONT_STOP_STATION  = { family = "main",        size = 11 }
local FONT_STOP_RESOURCE = { family = "main",        size = 11 }
local FONT_STOP_NUMBER   = { family = "mono",        size = 10 }
local FONT_STOP_META     = { family = "mono",        size = 10 }

local COLUMN_HEADER_LABELS = { "NEED", "CARGO", "BUY" }

local HIDE_LABELS         = { [false] = "Hide site", [true] = "Show site" }
local REFRESH_ROUTE_LABEL = "Refresh route"

local MENU_ITEMS = {
    {
        label = function(market_id)
            return HIDE_LABELS[state.is_hidden(market_id)]
        end,
        on_click = function(market_id)
            state.set_hidden(market_id, not state.is_hidden(market_id))
        end,
    },
    {
        label = function() return REFRESH_ROUTE_LABEL end,
        on_click = function(market_id)
            state.request_route_refresh(market_id)
        end,
    },
}

local ROUTE_STATE_MESSAGES = {
    [route_constants.STATUS_IDLE]           = "Route not computed",
    [route_constants.STATUS_PENDING]        = "Computing route...",
    [route_constants.STATUS_ERROR]          = "Route unavailable",
    [route_constants.STATUS_NO_SHIP_PARAMS] = "Set ship parameters",
    [route_constants.STATUS_NO_COORDS]      = "Visit the depot system",
}

local ROUTE_STATE_COLOR_KEY = {
    [route_constants.STATUS_ERROR] = "danger",
}

local TOTALS_PARTS = {
    { label = "To buy %s",   key = "to_buy_total" },
    { label = "In cargo %s", key = "cargo_total" },
    { label = "Needed %s",   key = "needed_total" },
}

local CARD_VIEW = {}

local function font_for(spec)
    return theme.font(spec.family, spec.size)
end

local function format_count(value)
    return format.group_thousands(string.format(INT_FORMAT, value or 0))
end

local function format_percent(fraction)
    local percent = math.floor((fraction or 0) * constants.PERCENT_MULTIPLIER
        + PERCENT_ROUNDING)
    return string.format(constants.PERCENT_FORMAT, percent)
end

local function progress_color(card)
    if card.is_ready then return theme.colors.success end
    return theme.colors.accent
end

local function build_card(market_id, site, is_hidden)
    local needed_total, cargo_total, to_buy_total = amounts.site_totals(site)
    return {
        market_id    = market_id,
        title        = site.label or (constants.UNKNOWN_SITE_PREFIX .. market_id),
        progress     = site.progress or 0,
        resources    = amounts.unfinished(site),
        route        = route_state.preview(market_id, ROUTE_MAX_STOPS),
        needed_total = needed_total,
        cargo_total  = cargo_total,
        to_buy_total = to_buy_total,
        is_ready     = to_buy_total <= 0,
        is_hidden    = is_hidden == true,
    }
end

local function build_cards(show_hidden)
    local list = {}
    for _, entry in ipairs(state.sites_sorted()) do
        if show_hidden or not entry.is_hidden then
            table.insert(list,
                build_card(entry.market_id, entry.site, entry.is_hidden))
        end
    end
    return list
end

local function resource_body_h(card)
    if #card.resources == 0 then return RESOURCE_ROW_H end
    return COL_HEADER_H + #card.resources * RESOURCE_ROW_H
end

local function route_status_of(card)
    return (card.route and card.route.status) or route_constants.STATUS_IDLE
end

local function pickup_count(stop)
    return math.max(1, #(stop.pickups or {}))
end

local function stop_card_height(stop)
    return STOP_CARD_PAD_Y * 2 + STOP_SYSTEM_H + STOP_STATION_H
        + pickup_count(stop) * STOP_RESOURCE_H
end

local function route_stops_height(stops)
    local total = 0
    for _, stop in ipairs(stops) do
        total = total + STOP_CARD_GAP + stop_card_height(stop)
    end
    return total
end

local function route_body_h(card)
    if route_status_of(card) ~= route_constants.STATUS_READY then
        return ROUTE_HEADER_H + ROUTE_MESSAGE_H
    end
    if #card.route.stops == 0 then
        return ROUTE_HEADER_H + ROUTE_MESSAGE_H
    end
    return ROUTE_HEADER_H + route_stops_height(card.route.stops)
end

local function body_height(card)
    return math.max(resource_body_h(card), route_body_h(card))
end

local function card_height(card)
    local base = CARD_PAD_Y * 2 + CARD_HEADER_H + PROGRESS_BAR_H
        + PROGRESS_GAP + CARD_TOTALS_H + SECTION_GAP
    return base + body_height(card)
end

local function body_columns(inner_x, inner_w)
    local route_w = math.max(ROUTE_COL_MIN_W,
        math.floor(inner_w * ROUTE_COL_FRACTION))
    local resource_w = inner_w - route_w - VRULE_W - BODY_COL_GAP * 2
    local rule_x = inner_x + resource_w + BODY_COL_GAP
    local route_x = rule_x + VRULE_W + BODY_COL_GAP
    return {
        resource = { x = inner_x, w = resource_w },
        rule_x   = rule_x,
        route    = { x = route_x, w = route_w },
    }
end

local function panel_opts_for(card)
    if card.is_hidden then
        return { left_accent = theme.colors.rule_strong, left_accent_w = 2 }
    end
    if card.is_ready then
        return { left_accent = theme.colors.success, left_accent_w = 3 }
    end
    return { left_accent = theme.colors.accent_rule, left_accent_w = 2 }
end

local function title_color(card)
    if card.is_hidden then return theme.colors.text_dim end
    return theme.colors.text
end

local function draw_header(card, x, y, w)
    local title_font = font_for(FONT_TITLE)
    local percent_font = font_for(FONT_PERCENT)
    local percent_text = format_percent(card.progress)
    local percent_w = text.width(percent_text, percent_font, PERCENT_LETTER_EM)
    local title_w = math.max(0, w - percent_w - HEADER_GAP)
    text.draw(text.truncate_right(card.title, title_font, title_w, 0), x, y, {
        font = title_font, color = title_color(card),
    })
    text.draw(percent_text, x + w - percent_w, y + PERCENT_TOP_NUDGE, {
        font = percent_font, color = progress_color(card),
        letter_em = PERCENT_LETTER_EM,
    })
end

local function toggle_menu(view_state, market_id)
    if view_state.menu_market == market_id then
        view_state.menu_market = nil
        return
    end
    view_state.menu_market = market_id
end

local function draw_menu_glyph(cx, cy, color)
    love.graphics.setColor(color)
    for offset = -1, 1 do
        love.graphics.circle("fill",
            cx + offset * MENU_DOT_SPACING, cy, MENU_DOT_RADIUS)
    end
end

local function menu_button_color(is_active)
    if is_active then return theme.colors.text end
    return theme.colors.text_faint
end

local function draw_menu_button(card, bx, by, view_state)
    local is_open = view_state.menu_market == card.market_id
    local is_active = is_open or input.in_rect(bx, by, MENU_BTN_W, CARD_HEADER_H)
    if is_active then
        love.graphics.setColor(theme.colors.seg_hover)
        love.graphics.rectangle("fill", bx, by, MENU_BTN_W, CARD_HEADER_H)
    end
    draw_menu_glyph(bx + MENU_BTN_W / 2, by + CARD_HEADER_H / 2,
        menu_button_color(is_active))
    if input.clicked_in(bx, by, MENU_BTN_W, CARD_HEADER_H) then
        toggle_menu(view_state, card.market_id)
    end
    if view_state.menu_market == card.market_id then
        view_state.menu_anchor =
            { x = bx, y = by, w = MENU_BTN_W, h = CARD_HEADER_H }
    end
end

local function draw_progress_bar(card, x, y, w)
    love.graphics.setColor(theme.colors.rule_strong)
    love.graphics.rectangle("fill", x, y, w, PROGRESS_BAR_H)
    local fraction = math.max(0, math.min(1, card.progress))
    love.graphics.setColor(progress_color(card))
    love.graphics.rectangle("fill", x, y, w * fraction, PROGRESS_BAR_H)
end

local function totals_text(card)
    local parts = {}
    for _, part in ipairs(TOTALS_PARTS) do
        table.insert(parts,
            string.format(part.label, format_count(card[part.key])))
    end
    return table.concat(parts, TOTALS_SEPARATOR)
end

local function draw_totals(card, x, y, w)
    local font = font_for(FONT_TOTALS)
    text.draw(text.truncate_right(totals_text(card), font, w, TOTALS_LETTER_EM),
        x, y, {
            font = font, color = theme.colors.text_dim,
            letter_em = TOTALS_LETTER_EM,
        })
end

local function resource_columns(x, w)
    local buy_x   = x + w - NUM_RESERVE
    local cargo_x = buy_x   - NUM_GAP - NUM_RESERVE
    local need_x  = cargo_x - NUM_GAP - NUM_RESERVE
    return { need_x, cargo_x, buy_x }
end

local function draw_rule(x, y, w)
    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", x, y, w, RULE_H)
end

local function draw_v_rule(x, y, h)
    panel.rule(x, y, x + VRULE_W, y + h, theme.colors.rule)
end

local function draw_column_header(x, y, w, columns)
    local font = font_for(FONT_COL_HEADER)
    for i, label in ipairs(COLUMN_HEADER_LABELS) do
        text.draw_v_center(label, columns[i], y, COL_HEADER_H, {
            font = font, color = theme.colors.text_faint, align = "right",
            width = NUM_RESERVE, letter_em = COL_HEADER_LETTER_EM,
        })
    end
    draw_rule(x, y + COL_HEADER_H - RULE_H, w)
end

local function value_color(value, positive_key, zero_key)
    if (value or 0) > 0 then return theme.colors[positive_key] end
    return theme.colors[zero_key]
end

local function resource_cells(entry)
    return {
        { value = entry.needed,   color = theme.colors.text_dim },
        { value = entry.in_cargo,
          color = value_color(entry.in_cargo, "success", "text_faint") },
        { value = entry.to_buy,
          color = value_color(entry.to_buy, "accent", "success") },
    }
end

local function draw_resource_row(entry, x, y, columns)
    local name_font = font_for(FONT_RESOURCE)
    local name_w = math.max(0, columns[1] - x - NAME_TRAILING_GAP)
    text.draw_v_center(
        text.truncate_right(entry.resource.display, name_font, name_w, 0),
        x, y, RESOURCE_ROW_H, { font = name_font, color = theme.colors.text })
    local number_font = font_for(FONT_NUMBER)
    for i, cell in ipairs(resource_cells(entry)) do
        text.draw_v_center(format_count(cell.value), columns[i], y,
            RESOURCE_ROW_H, {
                font = number_font, color = cell.color,
                align = "right", width = NUM_RESERVE,
            })
    end
end

local function draw_all_delivered(x, y, w)
    text.draw_v_center(ALL_DELIVERED_TEXT, x, y, RESOURCE_ROW_H, {
        font = font_for(FONT_RESOURCE), color = theme.colors.success,
        align = "center", width = w,
    })
end

local function resource_row_color(row_index, is_hovered)
    if is_hovered then return theme.colors.seg_hover end
    if row_index % 2 == 0 then return theme.colors.row_alt end
    return nil
end

local function fill_resource_row(x, y, w, color)
    if not color then return end
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y, w, RESOURCE_ROW_H)
end

local function draw_resource_section(card, x, y, w)
    if #card.resources == 0 then
        draw_all_delivered(x, y, w)
        return
    end
    local columns = resource_columns(x, w)
    draw_column_header(x, y, w, columns)
    local cy = y + COL_HEADER_H
    for row_index, entry in ipairs(card.resources) do
        local is_hovered = input.in_rect(x, cy, w, RESOURCE_ROW_H)
        fill_resource_row(x, cy, w, resource_row_color(row_index, is_hovered))
        draw_resource_row(entry, x, cy, columns)
        cy = cy + RESOURCE_ROW_H
    end
end

local function fmt_ly(value)
    return string.format(LY_NUMBER_FORMAT, value or 0)
end

local function fmt_ls(value)
    return format.group_thousands(string.format(INT_FORMAT,
        math.floor(value or 0)))
end

local function fmt_qty(value)
    return format.group_thousands(string.format(INT_FORMAT,
        math.floor(value or 0)))
end

local function copy_system_to_clipboard(view_state, stop)
    if not stop or not stop.system then return end
    if love.system and love.system.setClipboardText then
        love.system.setClipboardText(stop.system)
    end
    view_state.route_copy = {
        stop    = stop,
        expires = love.timer.getTime() + COPY_FEEDBACK_S,
    }
end

local function is_copy_active(view_state, stop)
    local feedback = view_state.route_copy
    return feedback ~= nil and feedback.stop == stop
        and love.timer.getTime() < feedback.expires
end

local function stop_system_label(view_state, stop)
    if is_copy_active(view_state, stop) then
        return COPY_FEEDBACK_LABEL, theme.colors.success
    end
    return string.format(STOP_LY_FORMAT, fmt_ly(stop.distance_ly)),
        theme.colors.accent
end

local function draw_label_right(label, color, spec, x, y, w, h)
    return text.draw_v_center(label, x, y, h, {
        font = font_for(spec), color = color, align = "right", width = w,
    })
end

local function draw_truncated_name(name, spec, color, x, y, h, w)
    text.draw_v_center(
        text.truncate_right(name, font_for(spec), math.max(0, w), 0),
        x, y, h, { font = font_for(spec), color = color })
end

local function draw_stop_system(stop, view_state, x, y, w)
    local is_hovered = input.in_rect(x, y, w, STOP_SYSTEM_H)
    if is_hovered then
        love.graphics.setColor(theme.colors.seg_hover)
        love.graphics.rectangle("fill", x, y, w, STOP_SYSTEM_H)
    end
    local label, label_color = stop_system_label(view_state, stop)
    local label_w = draw_label_right(label, label_color, FONT_STOP_META,
        x, y, w, STOP_SYSTEM_H)
    local name_color = is_hovered and theme.colors.accent or theme.colors.text
    draw_truncated_name(stop.system or "?", FONT_STOP_SYSTEM, name_color,
        x, y, STOP_SYSTEM_H, w - label_w - NUM_GAP)
    if input.clicked_in(x, y, w, STOP_SYSTEM_H) and not view_state.menu_market then
        copy_system_to_clipboard(view_state, stop)
    end
end

local function draw_stop_station(stop, x, y, w)
    local meta = string.format(STOP_LS_FORMAT, fmt_ls(stop.distance_to_arrival_ls))
    local meta_w = draw_label_right(meta, theme.colors.text_faint,
        FONT_STOP_META, x, y, w, STOP_STATION_H)
    draw_truncated_name(stop.station or "?", FONT_STOP_STATION,
        theme.colors.text_dim, x, y, STOP_STATION_H, w - meta_w - NUM_GAP)
end

local function draw_stop_pickup(pickup, x, y, w)
    local qty = string.format(STOP_QTY_FORMAT, fmt_qty(pickup.quantity))
    local qty_w = draw_label_right(qty, theme.colors.accent, FONT_STOP_NUMBER,
        x, y, w, STOP_RESOURCE_H)
    draw_truncated_name(pickup.display or pickup.commodity_key or "?",
        FONT_STOP_RESOURCE, theme.colors.text,
        x, y, STOP_RESOURCE_H, w - qty_w - NUM_GAP)
end

local function draw_stop_pickups(stop, x, y, w)
    local cy = y
    for _, pickup in ipairs(stop.pickups or {}) do
        draw_stop_pickup(pickup, x, cy, w)
        cy = cy + STOP_RESOURCE_H
    end
end

local function draw_stop_card(stop, view_state, x, y, w)
    panel.draw(x, y, w, stop_card_height(stop), {
        bg = theme.colors.panel_deep, border = theme.colors.rule,
        left_accent = theme.colors.accent_rule, left_accent_w = 2,
    })
    local inner_x = x + STOP_CARD_PAD_X
    local inner_w = w - STOP_CARD_PAD_X * 2
    local cy = y + STOP_CARD_PAD_Y
    draw_stop_system(stop, view_state, inner_x, cy, inner_w)
    cy = cy + STOP_SYSTEM_H
    draw_stop_station(stop, inner_x, cy, inner_w)
    cy = cy + STOP_STATION_H
    draw_stop_pickups(stop, inner_x, cy, inner_w)
end

local function draw_route_summary(route, x, y, w)
    if not route or route.status ~= route_constants.STATUS_READY then return end
    if (route.total_stops or 0) <= 0 then return end
    local font = font_for(FONT_COL_HEADER)
    local summary = string.format(ROUTE_STOPS_FORMAT, route.total_stops)
    local summary_w = text.width(summary, font, COL_HEADER_LETTER_EM)
    text.draw_v_center(summary, x + w - summary_w, y, ROUTE_HEADER_H, {
        font = font, color = theme.colors.text_faint,
        letter_em = COL_HEADER_LETTER_EM,
    })
end

local function draw_route_header(card, x, y, w)
    text.draw_v_center(ROUTE_HEADER_LABEL, x, y, ROUTE_HEADER_H, {
        font = font_for(FONT_COL_HEADER), color = theme.colors.text_faint,
        letter_em = COL_HEADER_LETTER_EM,
    })
    draw_route_summary(card.route, x, y, w)
    draw_rule(x, y + ROUTE_HEADER_H - RULE_H, w)
end

local function draw_route_message(message, color_key, x, y, w)
    text.draw_v_center(message, x, y, ROUTE_MESSAGE_H, {
        font = font_for(FONT_ROUTE),
        color = theme.colors[color_key or "text_faint"],
        align = "center", width = w,
    })
end

local function draw_route_stops(card, view_state, x, y, w)
    local cy = y
    for _, stop in ipairs(card.route.stops) do
        cy = cy + STOP_CARD_GAP
        draw_stop_card(stop, view_state, x, cy, w)
        cy = cy + stop_card_height(stop)
    end
end

local function draw_route_body(card, view_state, x, y, w)
    local status = route_status_of(card)
    if status ~= route_constants.STATUS_READY then
        draw_route_message(ROUTE_STATE_MESSAGES[status]
            or ROUTE_STATE_MESSAGES[route_constants.STATUS_PENDING],
            ROUTE_STATE_COLOR_KEY[status], x, y, w)
        return
    end
    if #card.route.stops == 0 then
        draw_route_message(ROUTE_EMPTY_MESSAGE, nil, x, y, w)
        return
    end
    draw_route_stops(card, view_state, x, y, w)
end

local function draw_route_section(card, view_state, x, y, w)
    draw_route_header(card, x, y, w)
    draw_route_body(card, view_state, x, y + ROUTE_HEADER_H, w)
end

local function draw_card(card, x, y, w, h, view_state)
    h = h or card_height(card)
    card_view.draw_card_panel(x, y, w, h, panel_opts_for(card))
    local inner_x = x + CARD_PAD_X
    local inner_w = w - CARD_PAD_X * 2
    local cy = y + CARD_PAD_Y
    draw_header(card, inner_x, cy, inner_w - MENU_BTN_W - MENU_BTN_GAP)
    draw_menu_button(card, inner_x + inner_w - MENU_BTN_W, cy, view_state)
    cy = cy + CARD_HEADER_H
    draw_progress_bar(card, inner_x, cy, inner_w)
    cy = cy + PROGRESS_BAR_H + PROGRESS_GAP
    draw_totals(card, inner_x, cy, inner_w)
    cy = cy + CARD_TOTALS_H + SECTION_GAP
    local columns = body_columns(inner_x, inner_w)
    draw_resource_section(card, columns.resource.x, cy, columns.resource.w)
    draw_v_rule(columns.rule_x, cy, y + h - CARD_PAD_Y - cy)
    draw_route_section(card, view_state, columns.route.x, cy, columns.route.w)
    return h
end

local function menu_height()
    return MENU_PAD_Y * 2 + #MENU_ITEMS * MENU_ITEM_H
end

local function menu_geometry(anchor, pane_y, pane_h)
    local x = anchor.x + anchor.w - MENU_WIDTH
    local h = menu_height()
    local below_y = anchor.y + anchor.h + MENU_ANCHOR_GAP
    if below_y + h <= pane_y + pane_h then
        return x, below_y, h
    end
    return x, anchor.y - MENU_ANCHOR_GAP - h, h
end

local function dismiss_if_outside(view_state, anchor, menu_x, menu_y, menu_h)
    if not input.released then return false end
    if input.in_rect(anchor.x, anchor.y, anchor.w, anchor.h) then return false end
    if input.in_rect(menu_x, menu_y, MENU_WIDTH, menu_h) then return false end
    view_state.menu_market = nil
    return true
end

local function draw_menu_item(view_state, market_id, definition, x, item_y)
    local is_hovered = input.in_rect(x, item_y, MENU_WIDTH, MENU_ITEM_H)
    if is_hovered then
        love.graphics.setColor(theme.colors.seg_hover)
        love.graphics.rectangle("fill", x, item_y, MENU_WIDTH, MENU_ITEM_H)
    end
    text.draw_v_center(definition.label(market_id),
        x + MENU_ITEM_PAD_X, item_y, MENU_ITEM_H, {
            font = font_for(FONT_MENU),
            color = is_hovered and theme.colors.text or theme.colors.text_dim,
        })
    if input.clicked_in(x, item_y, MENU_WIDTH, MENU_ITEM_H) then
        definition.on_click(market_id)
        view_state.menu_market = nil
    end
end

local function draw_menu_items(view_state, market_id, x, y)
    for index, definition in ipairs(MENU_ITEMS) do
        local item_y = y + MENU_PAD_Y + (index - 1) * MENU_ITEM_H
        draw_menu_item(view_state, market_id, definition, x, item_y)
    end
end

local function draw_menu_overlay(view_state, _, pane_y, _, pane_h)
    local market_id = view_state.menu_market
    if not market_id then return end
    if not state.get_site(market_id) then
        view_state.menu_market = nil
        return
    end
    local anchor = view_state.menu_anchor
    if not anchor then return end
    local menu_x, menu_y, menu_h = menu_geometry(anchor, pane_y, pane_h)
    if dismiss_if_outside(view_state, anchor, menu_x, menu_y, menu_h) then
        return
    end
    panel.draw(menu_x, menu_y, MENU_WIDTH, menu_h, {
        bg = theme.colors.panel, border = theme.colors.rule_strong,
    })
    draw_menu_items(view_state, market_id, menu_x, menu_y)
end

local function empty_message_for()
    if state.site_count() > 0 and state.visible_count() == 0 then
        return ALL_HIDDEN_MESSAGE
    end
    return EMPTY_MESSAGE
end

function CARD_VIEW.draw(view_state, x, y, w, h, show_hidden)
    view_state.menu_anchor = nil
    return card_view.draw(view_state, x, y, w, h, {
        gap           = CARD_GAP,
        min_card_w    = MIN_CARD_W,
        max_columns   = MAX_COLUMNS,
        empty_message = empty_message_for(),
        empty_font    = font_for(FONT_EMPTY),
        build_cards   = function() return build_cards(show_hidden) end,
        card_height   = card_height,
        draw_card     = function(card, cx, cy, cw, ch)
            return draw_card(card, cx, cy, cw, ch, view_state)
        end,
        draw_overlay  = draw_menu_overlay,
    })
end

return CARD_VIEW
