local listeners = {}

local CHANNELS = { "journal_entry", "status_update", "state_changed" }

function listeners.create()
    local store = {}
    for _, channel in ipairs(CHANNELS) do
        store[channel] = {}
    end
    return store
end

function listeners.subscribe(store, channel, fn)
    table.insert(store[channel], fn)
end

function listeners.clear(store)
    for channel in pairs(store) do
        store[channel] = {}
    end
end

function listeners.dispatch(store, channel, ...)
    for _, fn in ipairs(store[channel]) do
        local ok, err = pcall(fn, ...)
        if not ok then
            print("[log_monitor] listener error:", err)
        end
    end
end

return listeners
