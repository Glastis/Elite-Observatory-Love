-- Plugin manager.
-- The original C# port loads .NET assemblies (.dll / .eop). In this Lua port,
-- plugins are simple Lua modules at `plugins/<id>/init.lua` that return a
-- table conforming to the IObservatoryPlugin / IObservatoryWorker /
-- IObservatoryNotifier contracts.
--
-- A plugin module looks like:
--   local Plugin = { id="my-plugin", name="My Plugin", short_name="MP",
--                    version="1.0", grid = { columns = {...}, rows = {} } }
--   function Plugin:load(core) end
--   function Plugin:journal_event(entry) end
--   function Plugin:status_change(status) end
--   function Plugin:on_notification(args) end       -- notifier
--   return Plugin

local Core = require("observatory.core")
local settings = require("observatory.settings")
local http_service = require("observatory.http_service")
local log_monitor = require("observatory.log_monitor")
local paths = require("observatory.paths")
local error_channel = require("observatory.error_channel")

local plugin_manager = {}

local plugins = {}
local cores_by_id = {}
local disabled = {}

local function plugin_storage_folder(plugin_id)
    -- Use love.filesystem.getSaveDirectory() so storage is per-user, then
    -- create a `plugins/<id>` subfolder. We let LÖVE create the directory.
    local sub = "plugins/" .. plugin_id
    if love and love.filesystem then
        love.filesystem.createDirectory(sub)
        local saveDir = love.filesystem.getSaveDirectory()
        return paths.join(saveDir, sub)
    end
    return paths.join(paths.home(), ".observatory", sub)
end

-- Discover plugin folders inside the game's `plugins/` directory.
-- Skips folders without an init.lua.
local function discover_plugin_ids()
    local ids = {}
    if not (love and love.filesystem) then return ids end
    local items = love.filesystem.getDirectoryItems("plugins")
    for _, name in ipairs(items) do
        local info = love.filesystem.getInfo("plugins/" .. name)
        if info and info.type == "directory" then
            local init = love.filesystem.getInfo("plugins/" .. name .. "/init.lua")
            if init then table.insert(ids, name) end
        end
    end
    table.sort(ids)
    return ids
end

local function method_call(obj, method_name, ...)
    if type(obj) ~= "table" then return true end
    local fn = obj[method_name]
    if type(fn) ~= "function" then return true end
    local ok, err = pcall(fn, obj, ...)
    if not ok then
        error_channel.report(obj.id or obj.name or "?",
            string.format("%s: %s", method_name, tostring(err)))
    end
    return ok, err
end

-- Drop cached modules under `plugins.<id>` so subsequent `require` calls reload
-- the source from disk. Without this, F5 would always hand back the cached
-- table from `package.loaded`.
local function purge_plugin_cache()
    for key in pairs(package.loaded) do
        if key == "plugins" or key:sub(1, 8) == "plugins." then
            package.loaded[key] = nil
        end
    end
end

function plugin_manager.load_all()
    plugins = {}
    cores_by_id = {}
    error_channel.clear()
    disabled = {}

    -- Wipe any listeners we registered on a previous load so we don't dispatch
    -- each event N times after N reloads.
    log_monitor.clear_listeners()
    purge_plugin_cache()

    for _, id in ipairs(discover_plugin_ids()) do
        local mod_path = "plugins." .. id
        local ok, plugin = pcall(require, mod_path)
        if not ok then
            error_channel.report(id, tostring(plugin))
        elseif type(plugin) ~= "table" then
            error_channel.report(id, "plugin did not return a table")
        else
            plugin.id = plugin.id or id
            plugin.name = plugin.name or id
            plugin.short_name = plugin.short_name or plugin.name
            plugin.version = plugin.version or "0.0.0"
            -- Restore saved settings before load().
            local saved = settings.get_plugin_settings(plugin.id)
            if saved ~= nil then plugin.settings = saved
            elseif plugin.default_settings ~= nil then
                plugin.settings = plugin.default_settings
            end
            local core = Core.new(plugin.id, plugin_storage_folder(plugin.id))
            cores_by_id[plugin.id] = core
            method_call(plugin, "load", core)
            table.insert(plugins, plugin)
        end
    end

    -- Wire log monitor events into plugins.
    log_monitor.on_journal_entry(function(entry)
        for _, p in ipairs(plugins) do
            if not disabled[p.id] then
                method_call(p, "journal_event", entry)
            end
        end
    end)
    log_monitor.on_status_update(function(status)
        for _, p in ipairs(plugins) do
            if not disabled[p.id] then
                local core = cores_by_id[p.id]
                if core then core:_set_status(status) end
                method_call(p, "status_change", status)
            end
        end
    end)
    log_monitor.on_state_changed(function(change)
        for _, p in ipairs(plugins) do
            if not disabled[p.id] then
                method_call(p, "log_monitor_state_changed", change)
            end
        end
    end)
end

function plugin_manager.observatory_ready()
    for _, p in ipairs(plugins) do
        if not disabled[p.id] then
            method_call(p, "observatory_ready")
        end
    end
end

function plugin_manager.update(dt)
    http_service.update(dt)
    for _, p in ipairs(plugins) do
        if not disabled[p.id] then
            method_call(p, "update", dt)
        end
    end
end

function plugin_manager.dispatch_notification(args)
    for _, p in ipairs(plugins) do
        if not disabled[p.id] and type(p.on_notification) == "function" then
            method_call(p, "on_notification", args)
        end
    end
end

function plugin_manager.list() return plugins end

function plugin_manager.list_enabled()
    local result = {}
    for _, p in ipairs(plugins) do
        if not disabled[p.id] then
            table.insert(result, p)
        end
    end
    return result
end

function plugin_manager.errors() return error_channel.get_all() end

function plugin_manager.set_enabled(plugin_id, enabled)
    if enabled then
        disabled[plugin_id] = nil
    else
        disabled[plugin_id] = true
    end
end

function plugin_manager.is_enabled(plugin_id)
    return not disabled[plugin_id]
end

function plugin_manager.find(plugin_id)
    for _, p in ipairs(plugins) do
        if p.id == plugin_id then return p end
    end
    return nil
end

return plugin_manager
