local channel = {}

local entries = {}
local listeners = {}

local function notify()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, entries)
        if not ok then print("[error_channel] listener error:", err) end
    end
end

function channel.report(plugin_id, message)
    table.insert(entries, {
        plugin = plugin_id or "?",
        message = tostring(message or ""),
        timestamp = os.time(),
    })
    notify()
end

function channel.get_all()
    return entries
end

function channel.clear()
    entries = {}
    notify()
end

function channel.on_change(fn)
    table.insert(listeners, fn)
end

return channel
