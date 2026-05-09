local constants = require("plugins.bioinsights.constants")
local handlers = require("plugins.bioinsights.handlers")
local grid_builder = require("plugins.bioinsights.grid")
local state = require("plugins.bioinsights.state")

local Plugin = {
    id = "bioinsights",
    name = "Observatory Bio Insights",
    short_name = "BioInsights",
    version = "0.1.0",
    grid = {
        columns = constants.GRID_COLUMNS,
        column_align = constants.COLUMN_ALIGN,
        rows = {},
    },
    default_settings = {
        notify_on_high_value   = true,
        notify_on_new_codex    = true,
        minimum_high_value     = constants.HIGH_VALUE_THRESHOLD,
        only_show_high_value   = false,
        show_headers           = true,
    },
}

local core_ref

local function ensure_settings(plugin)
    plugin.settings = plugin.settings or {}
    for key, value in pairs(plugin.default_settings) do
        if plugin.settings[key] == nil then plugin.settings[key] = value end
    end
end

local function refresh_grid()
    grid_builder.rebuild(Plugin.grid, Plugin.settings, {
        group_by_body = Plugin.group_by_body,
    })
end

local function sync_state_context()
    state.set_user_context({
        near_nebula   = Plugin.near_nebula,
        near_guardian = Plugin.near_guardian,
    })
end

local function apply_user_context_change()
    sync_state_context()
    state.refresh_all_constraints()
    refresh_grid()
end

local function send_notification(args)
    if not core_ref then return end
    core_ref:send_notification(args)
end

function Plugin:load(core)
    core_ref = core
    ensure_settings(self)
    handlers.set_notifier(send_notification)
    handlers.set_on_change(refresh_grid)
    sync_state_context()
    refresh_grid()
end

function Plugin:journal_event(entry)
    handlers.dispatch(entry, self.settings)
end

function Plugin:status_change(_)
end

function Plugin:set_grouping(is_enabled)
    self.group_by_body = is_enabled and true or false
    refresh_grid()
end

function Plugin:set_near_nebula(is_enabled)
    self.near_nebula = is_enabled and true or false
    apply_user_context_change()
end

function Plugin:set_near_guardian(is_enabled)
    self.near_guardian = is_enabled and true or false
    apply_user_context_change()
end

return Plugin
