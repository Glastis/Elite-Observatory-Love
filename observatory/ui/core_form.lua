local ui = require("observatory.ui")
local log_monitor = require("observatory.log_monitor")
local plugin_manager = require("observatory.plugin_manager")
local settings = require("observatory.settings")
local paths = require("observatory.paths")

local header = require("observatory.ui.core_form.header")
local tabs_view = require("observatory.ui.core_form.tabs")
local settings_left = require("observatory.ui.core_form.settings_left")
local settings_right = require("observatory.ui.core_form.settings_right")
local plugin_pane = require("observatory.ui.core_form.plugin_pane")
local combined_pane = require("observatory.ui.core_form.combined_pane")
local status_bar = require("observatory.ui.core_form.status_bar")
local batch_overlay = require("observatory.ui.core_form.batch_overlay")

local theme = ui.theme

local core_form = {}

local state = {
    tabs           = nil,
    seg_header     = nil,
    seg_apply      = nil,
    seg_group      = {},
    cb_rows        = {},
    plugin_rows    = {},
    grid_state     = {},
    fade           = { t = 0 },
    last_tab       = 1,
    journal_field  = nil,
    journal_seeded = false,
    seg_combined   = { left = {}, right = {}, split = {} },
}

local CB_SETTINGS = {
    { key = "NativeNotify", label = "Desktop notifications" },
    { key = "StartMonitor", label = "Begin monitoring on launch" },
    { key = "StartReadAll", label = "Backfill all journals on first run" },
    { key = "AltMonitor",   label = "Polling monitor mode" },
}

local FIXED_TABS = { "Core settings", "Combined" }
local COMBINED_SLOT_KEYS = { left = "CombinedViewLeft", right = "CombinedViewRight" }
local COMBINED_SPLIT_KEY = "CombinedViewSplit"
local COMBINED_DEFAULT_SPLIT = "vertical"

local header_actions = {
    is_monitoring = function() return log_monitor.is_monitoring() end,
    start_monitor = function() log_monitor.start() end,
    stop_monitor  = function() log_monitor.stop() end,
    read_all      = function() log_monitor.read_all() end,
}

local left_actions = {
    journal_folder = function() return log_monitor.journal_folder() end,
    apply          = function(value) log_monitor.change_watched_directory(value) end,
    dir_exists     = function(p) return paths.dir_exists(p) end,
}

local plugin_actions = {
    is_enabled  = function(id) return plugin_manager.is_enabled(id) end,
    set_enabled = function(id, enabled) plugin_manager.set_enabled(id, enabled) end,
}

local function app_dir()
    return love.filesystem and love.filesystem.getSaveDirectory()
end

local function settings_left_deps()
    return {
        actions = left_actions,
        os_label = paths.os(),
        app_dir = app_dir,
        errors = function() return plugin_manager.errors() end,
        settings = settings,
        list_enabled_plugins = function() return plugin_manager.list_enabled() end,
        combined_slot_keys = COMBINED_SLOT_KEYS,
        combined_split_key = COMBINED_SPLIT_KEY,
        combined_default_split = COMBINED_DEFAULT_SPLIT,
    }
end

local function settings_right_deps()
    return {
        settings = settings,
        cb_settings = CB_SETTINGS,
        list_plugins = function() return plugin_manager.list() end,
        plugin_actions = plugin_actions,
    }
end

local function combined_pane_deps()
    return {
        settings = settings,
        slot_keys = COMBINED_SLOT_KEYS,
        split_key = COMBINED_SPLIT_KEY,
        default_split = COMBINED_DEFAULT_SPLIT,
        list_enabled_plugins = function() return plugin_manager.list_enabled() end,
    }
end

local function status_bar_deps()
    return {
        is_batch_read   = function() return log_monitor.is_batch_read() end,
        is_monitoring   = function() return log_monitor.is_monitoring() end,
        current_state   = function() return log_monitor.current_state() end,
        last_event      = function() return log_monitor.last_event() end,
        total_events    = function() return log_monitor.total_events() end,
        journal_folder  = function() return log_monitor.journal_folder() end,
    }
end

local function draw_settings_body(w, body_y, body_h)
    local left_w = math.floor(w * (1.05 / 2.05))
    local right_w = w - left_w

    settings_left.draw(state, 0, body_y, left_w, settings_left_deps())

    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", left_w, body_y, 1, body_h)

    settings_right.draw(state, left_w, body_y, right_w, settings_right_deps())
end

local function fixed_tab_handlers(w, body_y, body_h)
    return {
        function() draw_settings_body(w, body_y, body_h) end,
        function()
            combined_pane.draw(state, w, body_y, body_h, combined_pane_deps())
        end,
    }
end

local function draw_body(w, body_y, body_h, tab_index)
    local _, y_offset = tabs_view.begin_pane_fade(state, tab_index)

    love.graphics.push()
    love.graphics.translate(0, y_offset)

    local handlers = fixed_tab_handlers(w, body_y, body_h)
    local handler = handlers[tab_index]
    if handler then
        handler()
    else
        local plugin = plugin_manager.list_enabled()[tab_index - #FIXED_TABS]
        if plugin then
            plugin_pane.draw(state, plugin, 0, body_y, w, body_h)
        end
    end

    love.graphics.pop()
end

function core_form.draw()
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    love.graphics.setColor(theme.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    header.draw(state, w, header_actions)

    local tabs_y = theme.metrics.bar_top_h
    local tab_index, tabs_h = tabs_view.draw(state, w, tabs_y,
        FIXED_TABS, plugin_manager.list_enabled())

    local body_y = tabs_y + tabs_h
    local body_h = h - body_y - theme.metrics.bar_bottom_h
    draw_body(w, body_y, body_h, tab_index)

    status_bar.draw(w, h, status_bar_deps())
    batch_overlay.draw(w, h, log_monitor.batch_progress())
end

function core_form.wheel(dx, dy)
    ui.input.feed_wheel(dx, dy)
end

return core_form
