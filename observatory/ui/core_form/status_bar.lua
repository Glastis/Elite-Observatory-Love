local ui = require("observatory.ui")
local theme = ui.theme

local status_bar = {}

local REALTIME_PULSE_PERIOD = 5.0
local PAD_X = 14
local GLYPH_RATIO = 0.7
local GLYPH_GAP = 6
local LETTER_EM = 0.1

local STATE_LABEL_BUILDERS = {
    function(deps) if deps.is_batch_read() then return "BATCH" end end,
    function(deps) if deps.is_monitoring() then return "REALTIME" end end,
    function(deps) if deps.current_state() == 0 then return "IDLE" end end,
    function() return "BUSY" end,
}

local function monitor_status_label(deps)
    for _, builder in ipairs(STATE_LABEL_BUILDERS) do
        local label = builder(deps)
        if label then return label end
    end
end

local function monitor_status_color(label)
    if label == "REALTIME" then
        return ui.pulse.color(theme.colors.success, REALTIME_PULSE_PERIOD)
    end
    return theme.colors.accent
end

local function format_count(n)
    n = tonumber(n) or 0
    return string.format("%04d", n)
end

local function short_path(p, max_chars)
    if not p or p == "" then return "(none)" end
    max_chars = max_chars or 28
    local tail = p:match("[^/\\]+$") or p
    local parent = p:match("([^/\\]+)[/\\][^/\\]+$")
    local label = parent and (".../" .. parent .. "/" .. tail) or tail
    if #label > max_chars then
        label = "..." .. label:sub(-max_chars)
    end
    return label
end

local function draw_monitor_status(w, y, bh, deps)
    local label = monitor_status_label(deps)
    local color = monitor_status_color(label)
    local font = theme.font("mono", 10)
    local glyph_size = math.floor(font:getHeight() * GLYPH_RATIO)
    local label_w = ui.text.width(label, font, LETTER_EM)
    local cell_w = label_w + PAD_X * 2
    local x = w - cell_w - glyph_size - GLYPH_GAP
    ui.icon.diamond(x, y + (bh - glyph_size) / 2, glyph_size, color)
    ui.status_cell.draw({
        { text = label, color = color },
    }, x + glyph_size + GLYPH_GAP, y, bh,
        { divider = false, accent = true })
end

local function draw_left_cells(y, bh, deps)
    local cursor = 0
    cursor = ui.status_cell.draw({
        { text = "LAST" },
        { text = deps.last_event() or "NONE",
          color = theme.colors.text_dim },
    }, cursor, y, bh)
    cursor = ui.status_cell.draw({
        { text = "EVENTS" },
        { text = format_count(deps.total_events()),
          color = theme.colors.text_dim },
    }, cursor, y, bh)
    ui.status_cell.draw({
        { text = "JRNL" },
        { text = short_path(deps.journal_folder()),
          color = theme.colors.text_dim, no_letter_em = true },
    }, cursor, y, bh)
end

function status_bar.draw(w, h, deps)
    local bh = theme.metrics.bar_bottom_h
    local y = h - bh
    ui.panel.draw(0, y, w, bh, {
        bg = theme.colors.panel,
        border = false,
    })
    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", 0, y, w, 1)

    draw_left_cells(y, bh, deps)
    draw_monitor_status(w, y, bh, deps)
end

return status_bar
