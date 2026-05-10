local theme = require("observatory.ui.theme")
local input = require("observatory.ui.input")
local panel = require("observatory.ui.panel")
local text = require("observatory.ui.text")

local M = {}

local DEFAULT_PAD_X = 10
local DEFAULT_PAD_Y = 7
local CARET_BLINK_HZ = 2
local UTF8_CONTINUATION_LOW = 0x80
local UTF8_CONTINUATION_HIGH = 0xC0
local DEFAULT_ACCENT_W = 2

local function ensure(state, initial)
    state = state or {}
    state.id = state.id or tostring(state)
    if state.buffer == nil then state.buffer = initial or "" end
    return state
end

function M.set_value(state, value)
    state.buffer = value or ""
end

function M.value(state)
    return state and state.buffer or ""
end

local function trim_last_codepoint(s)
    if #s == 0 then return s end
    local last = #s
    while last > 1 do
        local b = s:byte(last)
        if b < UTF8_CONTINUATION_LOW or b >= UTF8_CONTINUATION_HIGH then break end
        last = last - 1
    end
    return s:sub(1, last - 1)
end

local function handle_backspace(state)
    state.buffer = trim_last_codepoint(state.buffer)
end

local function handle_commit(state, opts, signal)
    signal.committed = true
    input.clear_focus()
    if opts.on_commit then opts.on_commit(state.buffer) end
end

local function handle_escape()
    input.clear_focus()
end

local KEY_HANDLERS = {
    backspace = handle_backspace,
    ["return"] = handle_commit,
    kpenter = handle_commit,
    escape = handle_escape,
}

local function process_focus_input(state, opts)
    local signal = { committed = false }
    for _, ch in ipairs(input.pending_text) do
        state.buffer = state.buffer .. ch
    end
    for _, key in ipairs(input.pending_keys) do
        local handler = KEY_HANDLERS[key]
        if handler then handler(state, opts, signal) end
    end
    return signal.committed
end

local function update_focus(state, x, y, w, h)
    if not input.pressed then return end
    if input.in_rect(x, y, w, h) then
        input.set_focus(state.id)
    elseif input.focus == state.id then
        input.clear_focus()
    end
end

local function draw_chrome(state, focused, opts, x, y, w, h)
    local accent_w = (opts.accent ~= false) and DEFAULT_ACCENT_W or 0
    panel.draw(x, y, w, h, {
        bg = opts.bg or theme.colors.panel_deep,
        border = focused and theme.colors.accent_rule or theme.colors.rule,
        left_accent = (opts.accent ~= false) and (opts.accent or theme.colors.accent),
        left_accent_w = accent_w,
    })
    return accent_w
end

local function display_for(state, focused, opts)
    local display = state.buffer
    local color = opts.color or theme.colors.text
    if (display == nil or display == "") and not focused and opts.placeholder then
        return opts.placeholder, theme.colors.text_faint
    end
    return display or "", color
end

local function fit_display(display, focused, font, inner_w)
    if focused then return text.truncate_left(display, font, inner_w, 0) end
    return text.truncate_right(display, font, inner_w, 0)
end

local function draw_caret(font, shown, inner_x, y, h, pad_y)
    if math.floor((love.timer.getTime() or 0) * CARET_BLINK_HZ) % 2 ~= 0 then return end
    local cx = inner_x + font:getWidth(shown)
    love.graphics.setColor(theme.colors.text)
    love.graphics.line(cx, y + pad_y, cx, y + h - pad_y)
end

function M.draw(state, value, x, y, w, opts)
    opts = opts or {}
    state = ensure(state, value)

    local font = opts.font or theme.font("mono", 11)
    local pad_x = opts.pad_x or DEFAULT_PAD_X
    local pad_y = opts.pad_y or DEFAULT_PAD_Y
    local h = opts.h or (font:getHeight() + pad_y * 2)

    update_focus(state, x, y, w, h)

    local committed = false
    local focused = input.focus == state.id
    if focused then committed = process_focus_input(state, opts) end

    focused = input.focus == state.id
    local accent_w = draw_chrome(state, focused, opts, x, y, w, h)
    local inner_x = x + accent_w + pad_x
    local inner_w = w - accent_w - pad_x * 2

    local display, color = display_for(state, focused, opts)
    local shown = fit_display(display, focused, font, inner_w)

    text.draw(shown, inner_x, y + pad_y, { font = font, color = color })
    if focused then draw_caret(font, shown, inner_x, y, h, pad_y) end

    return state.buffer, committed, state
end

return M
