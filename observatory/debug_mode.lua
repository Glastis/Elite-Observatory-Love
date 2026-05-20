local debug_mode = {}

local is_enabled = false

function debug_mode.set(value)
    is_enabled = value and true or false
end

function debug_mode.is_enabled()
    return is_enabled
end

return debug_mode
