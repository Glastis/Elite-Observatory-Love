local ui = require("observatory.ui")
local theme = ui.theme

local batch_overlay = {}

local BOX_W = 360
local BOX_H = 80
local TITLE_OFFSET_Y = 14
local SUBTITLE_OFFSET_Y = 34
local BAR_OFFSET_FROM_BOTTOM = 22
local BAR_PAD_X = 16
local BAR_HEIGHT = 6

local function draw_panel(x, y)
    ui.panel.draw(x, y, BOX_W, BOX_H, {
        bg = { 0, 0, 0, 0.85 },
        border = theme.colors.accent_rule,
    })
end

local function draw_text_lines(x, y, progress)
    ui.text.draw(string.format("Reading journals: %d / %d",
        progress.done, math.max(progress.total, 1)),
        x, y + TITLE_OFFSET_Y, {
            font = theme.font("mono", 11),
            color = theme.colors.text,
            align = "center", width = BOX_W, letter_em = 0.08,
        })
    ui.text.draw(string.format("%d events processed",
        progress.processed_lines),
        x, y + SUBTITLE_OFFSET_Y, {
            font = theme.font("mono", 10),
            color = theme.colors.text_dim,
            align = "center", width = BOX_W, letter_em = 0.06,
        })
end

local function draw_progress_bar(x, y, progress)
    local frac = progress.total > 0
        and math.min(progress.done / progress.total, 1) or 0
    local bar_w = BOX_W - BAR_PAD_X * 2
    local bar_y = y + BOX_H - BAR_OFFSET_FROM_BOTTOM
    love.graphics.setColor(theme.colors.rule_strong)
    love.graphics.rectangle("fill", x + BAR_PAD_X, bar_y, bar_w, BAR_HEIGHT)
    love.graphics.setColor(theme.colors.accent)
    love.graphics.rectangle("fill", x + BAR_PAD_X, bar_y, bar_w * frac, BAR_HEIGHT)
end

function batch_overlay.draw(w, h, progress)
    if not progress then return end
    local x = (w - BOX_W) / 2
    local y = (h - BOX_H) / 2
    draw_panel(x, y)
    draw_text_lines(x, y, progress)
    draw_progress_bar(x, y, progress)
end

return batch_overlay
