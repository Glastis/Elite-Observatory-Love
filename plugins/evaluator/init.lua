local constants = require("plugins.evaluator.constants")
local handlers = require("plugins.evaluator.handlers")
local grid_builder = require("plugins.evaluator.grid")

local Plugin = {
    id = "evaluator",
    name = "Observatory Evaluator",
    short_name = "Evaluator",
    version = "0.1.0",
    grid = {
        columns = constants.GRID_COLUMNS,
        column_align = constants.COLUMN_ALIGN,
        rows = {},
    },
    default_settings = {
        minimum_body_value          = constants.DEFAULT_MIN_BODY_VALUE,
        minimum_mapping_value       = constants.DEFAULT_MIN_VALUE_FOR_MAPPING,
        max_distance_elw            = constants.DEFAULT_MAX_DISTANCE_ELW,
        max_distance_ww             = constants.DEFAULT_MAX_DISTANCE_WW,
        max_distance_aw             = constants.DEFAULT_MAX_DISTANCE_AW,
        max_distance_atmospheric    = constants.DEFAULT_MAX_DISTANCE_ATMO,
        max_distance_other          = constants.DEFAULT_MAX_DISTANCE_OTHER,
        include_atmospheric_bio     = false,
        notify_on_high_value        = true,
        minimum_high_value_notify   = constants.DEFAULT_HIGH_VALUE_NOTIFY,
        show_headers                = true,
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
    grid_builder.rebuild(Plugin.grid, Plugin.settings)
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
    refresh_grid()
end

function Plugin:journal_event(entry)
    handlers.dispatch(entry, self.settings)
end

function Plugin:status_change(_)
end

return Plugin
