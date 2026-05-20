-- Observatory Core API exposed to plugins.
-- This is the Lua equivalent of IObservatoryCore (Framework/Interfaces.cs).
-- Plugins receive an instance of this object via their `load(core)` method
-- and use it to send notifications, request status, play audio, write to
-- their grid, etc.

local settings = require("observatory.settings")
local notifications = require("observatory.notifications")
local audio_handler = require("observatory.audio_handler")
local http_service = require("observatory.http_service")
local log_monitor = require("observatory.log_monitor")
local paths = require("observatory.paths")
local plugin_helpers = require("observatory.plugin_helpers")
local error_channel = require("observatory.error_channel")
local debug_mode = require("observatory.debug_mode")

local Core = {}
Core.__index = Core

Core.helpers = plugin_helpers

function Core.new(plugin_id, plugin_storage_root)
    local self = setmetatable({}, Core)
    self.plugin_id = plugin_id
    self._storage_root = plugin_storage_root
    self.version = "1.0.0-lua"
    self._status = nil
    self.helpers = plugin_helpers
    self._state_owner = nil
    self._state_defaults = nil
    return self
end

-- Notifications -----------------------------------------------------------
function Core:send_notification(title_or_args, detail)
    if type(title_or_args) == "table" then
        title_or_args.sender = title_or_args.sender or self.plugin_id
        return notifications.send(title_or_args)
    end
    return notifications.send({
        title = title_or_args,
        detail = detail,
        sender = self.plugin_id,
    })
end

function Core:cancel_notification(guid)
    notifications.cancel(guid)
end

function Core:update_notification(args)
    notifications.update(args)
end

-- Status / monitor state --------------------------------------------------
function Core:get_status()
    return self._status
end

function Core:_set_status(status) self._status = status end

function Core:current_log_monitor_state()
    return log_monitor.current_state()
end

function Core:is_log_monitor_batch_reading()
    return log_monitor.is_batch_read()
end

function Core:refresh_ancillary_state()
    log_monitor.refresh_ancillary_state()
end

-- Debug -------------------------------------------------------------------
function Core:is_debug()
    return debug_mode.is_enabled()
end

-- Audio -------------------------------------------------------------------
function Core:play_audio_file(file_path, options)
    audio_handler.play(file_path, options)
end

function Core:http_get(url, callback)
    return http_service.request(url, callback)
end

function Core:http_cancel(request_id)
    http_service.cancel(request_id)
end

-- Grid (data) -------------------------------------------------------------
-- The plugin owns its grid table; we expose helpers that match the C# names.
function Core:add_grid_item(grid, item)
    if not grid or not grid.rows then return end
    table.insert(grid.rows, item)
end

function Core:add_grid_items(grid, items)
    if not grid or not grid.rows or not items then return end
    for _, item in ipairs(items) do
        table.insert(grid.rows, item)
    end
end

function Core:set_grid_items(grid, items)
    if not grid then return end
    grid.rows = {}
    for _, item in ipairs(items or {}) do
        table.insert(grid.rows, item)
    end
end

function Core:clear_grid(grid)
    if grid then grid.rows = {} end
end

-- Storage -----------------------------------------------------------------
function Core:plugin_storage_folder()
    return self._storage_root
end

-- Settings ----------------------------------------------------------------
function Core:save_settings(plugin_settings)
    settings.set_plugin_settings(self.plugin_id, plugin_settings)
end

-- State ------------------------------------------------------------------
function Core:bind_state(owner, defaults)
    self._state_owner = owner
    self._state_defaults = defaults or {}
    local saved = settings.get_plugin_state(self.plugin_id) or {}
    for key, default_value in pairs(self._state_defaults) do
        if saved[key] ~= nil then
            owner[key] = saved[key]
        elseif owner[key] == nil then
            owner[key] = default_value
        end
    end
end

function Core:save_state()
    if not self._state_owner or not self._state_defaults then return end
    local snapshot = {}
    for key in pairs(self._state_defaults) do
        snapshot[key] = self._state_owner[key]
    end
    settings.set_plugin_state(self.plugin_id, snapshot)
end

-- Paths -------------------------------------------------------------------
function Core:journal_folder() return log_monitor.journal_folder() end
function Core:home() return paths.home() end

-- Error reporting --------------------------------------------------------
function Core:report_error(message)
    error_channel.report(self.plugin_id, message)
end

function Core.get_errors()
    return error_channel.get_all()
end

function Core.clear_errors()
    error_channel.clear()
end

return Core
