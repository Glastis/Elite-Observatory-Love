-- Single-line editable text field. Visually echoes the code_box style — a
-- deeper-than-panel surface with an accent left edge — so a writable path
-- field sits naturally next to read-only `code_box` displays elsewhere on
-- the same screen.
--
-- Focus is owned by the shared `input` module, which routes love.textinput
-- and love.keypressed events to whichever field is currently active.

local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local panel = require("observatory.ui.panel")
local text = require("observatory.ui.text")

local M = {}

local function ensure(state, initial)
    state = state or {}
    state.id = state.id or tostring(state)
    if state.buffer == nil then
        state.buffer = initial or ""
    end
    return state
end

-- Force-overwrite the buffer (e.g. after auto-detect rewrites the value).
function M.set_value(state, value)
    state.buffer = value or ""
end

function M.value(state)
    return state and state.buffer or ""
end

-- opts:
--   font, color, accent (left bar), pad_x, pad_y, h (override),
--   placeholder, on_commit (fn called with new value when user presses enter).
-- Returns: current value, committed (bool), state.
function M.draw(state, value, x, y, w, opts)
    opts = opts or {}
    state = ensure(state, value)

    -- The caller may seed an initial value via the `value` argument on the
    -- first frame. After that, the widget owns the buffer; subsequent
    -- non-nil callers can sync via M.set_value() explicitly.
    if state.buffer == nil and value ~= nil then state.buffer = value end

    local font = opts.font or theme.font("mono", 11)
    local pad_x = opts.pad_x or 10
    local pad_y = opts.pad_y or 7
    local h = opts.h or (font:getHeight() + pad_y * 2)

    -- Click-to-focus / click-out-to-blur.
    if input.pressed then
        if input.in_rect(x, y, w, h) then
            input.set_focus(state.id)
        elseif input.focus == state.id then
            input.clear_focus()
        end
    end

    local committed = false
    if input.focus == state.id then
        for _, ch in ipairs(input.pending_text) do
            state.buffer = state.buffer .. ch
        end
        for _, key in ipairs(input.pending_keys) do
            if key == "backspace" then
                local s = state.buffer
                if #s > 0 then
                    -- Trim one UTF-8 codepoint, not just one byte.
                    local last = #s
                    while last > 1 do
                        local b = s:byte(last)
                        if b < 0x80 or b >= 0xC0 then break end
                        last = last - 1
                    end
                    state.buffer = s:sub(1, last - 1)
                end
            elseif key == "return" or key == "kpenter" then
                committed = true
                input.clear_focus()
                if opts.on_commit then opts.on_commit(state.buffer) end
            elseif key == "escape" then
                input.clear_focus()
            end
        end
    end

    local focused = input.focus == state.id
    local accent_w = (opts.accent ~= false) and 2 or 0
    panel.draw(x, y, w, h, {
        bg = opts.bg or theme.colors.panel_deep,
        border = focused and theme.colors.accent_rule or theme.colors.rule,
        left_accent = (opts.accent ~= false) and (opts.accent or theme.colors.accent),
        left_accent_w = accent_w,
    })

    local inner_x = x + accent_w + pad_x
    local inner_w = w - accent_w - pad_x * 2

    local display = state.buffer
    local color = opts.color or theme.colors.text
    if (display == nil or display == "") and not focused and opts.placeholder then
        display = opts.placeholder
        color = theme.colors.text_faint
    end

    -- Right-truncate so the head stays visible. When focused we show the
    -- tail instead so the caret stays in view while typing.
    local shown
    if focused then
        shown = text.truncate_left(display or "", font, inner_w, 0)
    else
        shown = text.truncate_right(display or "", font, inner_w, 0)
    end

    text.draw(shown, inner_x, y + pad_y, {
        font = font,
        color = color,
    })

    if focused and (math.floor((love.timer.getTime() or 0) * 2) % 2 == 0) then
        local cx = inner_x + font:getWidth(shown)
        love.graphics.setColor(theme.colors.text)
        love.graphics.line(cx, y + pad_y, cx, y + h - pad_y)
    end

    return state.buffer, committed, state
end

return M
