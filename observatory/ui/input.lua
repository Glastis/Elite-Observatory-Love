-- Per-frame input context. Components read from this module to know mouse
-- position, hover, click edges, the current frame's dt, and any text/key
-- events the host has forwarded into the focused field.

local M = {
    mouse_x = 0,
    mouse_y = 0,
    down = false,
    prev_down = false,
    pressed = false,
    released = false,
    dt = 0,
    wheel_dy = 0,

    -- Text-input plumbing. Stays at module scope so keystrokes routed via
    -- love.textinput / love.keypressed reach the active field even though
    -- widgets are immediate-mode and recreated every frame.
    focus = nil,
    pending_text = {},
    pending_keys = {},
}

function M.begin(dt)
    M.dt = dt or 0
    if love.mouse and love.mouse.getPosition then
        M.mouse_x, M.mouse_y = love.mouse.getPosition()
        M.down = love.mouse.isDown(1)
    end
    M.pressed = M.down and not M.prev_down
    M.released = (not M.down) and M.prev_down
end

function M.finish()
    M.prev_down = M.down
    M.wheel_dy = 0
    M.pending_text = {}
    M.pending_keys = {}
end

function M.in_rect(x, y, w, h)
    return M.mouse_x >= x and M.mouse_x <= x + w
       and M.mouse_y >= y and M.mouse_y <= y + h
end

function M.clicked_in(x, y, w, h)
    return M.released and M.in_rect(x, y, w, h)
end

function M.feed_wheel(_, dy)
    M.wheel_dy = M.wheel_dy + (dy or 0)
end

-- Called from love.textinput; only kept when a field has focus, otherwise
-- the host's global shortcuts keep their default behaviour.
function M.feed_text(t)
    if M.focus then table.insert(M.pending_text, t) end
end

function M.feed_key(key)
    if M.focus then table.insert(M.pending_keys, key) end
end

function M.has_focus()
    return M.focus ~= nil
end

function M.set_focus(id) M.focus = id end
function M.clear_focus() M.focus = nil end

return M
