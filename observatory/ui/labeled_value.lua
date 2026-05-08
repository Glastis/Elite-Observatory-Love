-- Labelled value — a small mono caps label rendered above an arbitrary
-- content area. The component itself doesn't render the value: it draws the
-- label and returns the inner-content rectangle so the caller can place
-- whatever it wants there.

local theme = require("observatory.ui.theme")
local text = require("observatory.ui.text")

local M = {}

-- opts: font, color, letter_em, gap.
-- Returns x, content_y, w, consumed.
function M.draw(label, x, y, w, opts)
    opts = opts or {}
    local font = opts.font or theme.font("mono", 10)
    local gap = opts.gap or 5

    text.draw(label, x, y, {
        font = font,
        color = opts.color or theme.colors.text_faint,
        letter_em = opts.letter_em or 0.1,
    })

    local consumed = font:getHeight() + gap
    return x, y + consumed, w, consumed
end

return M
