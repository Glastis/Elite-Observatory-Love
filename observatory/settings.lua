-- Settings persistence.
-- The original C# port uses User Settings (Windows registry-ish) or a JSON
-- file in PORTABLE/PROTON builds. We always use a JSON file in the LÖVE save
-- directory (love.filesystem.getSaveDirectory()), which is cross-platform.

local json = require("lib.json")

local settings = {}

-- Default values mirror Properties/Core.settings from ObservatoryCore.
local DEFAULTS = {
    JournalFolder       = "",
    NativeNotify        = true,
    NativeNotifyColour  = 0xFFFFA500, -- ARGB orange (#FFA500)
    NativeNotifyCorner  = 0,          -- 0 top-left .. 3 bottom-right
    NativeNotifyTimeout = 8000,       -- ms
    NativeNotifyScale   = 100,
    StartMonitor        = false,
    StartReadAll        = true,
    AltMonitor          = false,
    Theme               = "Dark",
    AudioVolume         = 0.75,
    VoiceNotify         = false,
    VoiceVolume         = 75,
    ExportFolder        = "",
    PluginsEnabled      = "",
    MainWindowSize      = { width = 1024, height = 640 },
    PluginSettings      = {},
    CombinedViewLeft    = "",
    CombinedViewRight   = "",
    CombinedViewSplit   = "vertical",
    LogPollIntervalRealtimeS = 0.25,
    LogPollIntervalAltS      = 1.0,
    LogDirCacheTtlS          = 5.0,
    LogBatchLinesPerTick     = 4000,
}

local SAVE_FILE = "observatory.config"

settings.values = {}

-- Deep-copy a table to avoid mutating defaults.
local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deep_copy(v) end
    return out
end

local function reset_to_defaults()
    settings.values = {}
    for k, v in pairs(DEFAULTS) do
        settings.values[k] = deep_copy(v)
    end
end

function settings.load()
    reset_to_defaults()
    if love and love.filesystem and love.filesystem.getInfo(SAVE_FILE) then
        local raw = love.filesystem.read(SAVE_FILE)
        if raw then
            local ok, decoded = pcall(json.decode, raw)
            if ok and type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    settings.values[k] = v
                end
            end
        end
    end
    return settings.values
end

function settings.save()
    if not (love and love.filesystem) then return end
    local ok, encoded = pcall(json.encode, settings.values)
    if not ok then return end
    love.filesystem.write(SAVE_FILE, encoded)
end

local listeners_by_key = {}

function settings.on_change(key, fn)
    listeners_by_key[key] = listeners_by_key[key] or {}
    table.insert(listeners_by_key[key], fn)
end

function settings.off_change(key, fn)
    local list = listeners_by_key[key]
    if not list then return end
    for i, listener in ipairs(list) do
        if listener == fn then
            table.remove(list, i)
            return
        end
    end
end

local function notify_change(key, new_value, old_value)
    local list = listeners_by_key[key]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, new_value, old_value, key)
        if not ok then print("[settings] listener error:", err) end
    end
end

function settings.get(key)
    return settings.values[key]
end

function settings.set(key, value)
    local old = settings.values[key]
    settings.values[key] = value
    if old == value then return end
    notify_change(key, value, old)
end

function settings.defaults()
    return DEFAULTS
end

-- Per-plugin settings live as nested tables under PluginSettings[plugin_id].
function settings.get_plugin_settings(plugin_id)
    settings.values.PluginSettings = settings.values.PluginSettings or {}
    return settings.values.PluginSettings[plugin_id]
end

function settings.set_plugin_settings(plugin_id, value)
    settings.values.PluginSettings = settings.values.PluginSettings or {}
    settings.values.PluginSettings[plugin_id] = value
    settings.save()
end

return settings
