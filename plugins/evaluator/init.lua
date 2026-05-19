local constants = require("plugins.evaluator.constants")
local handlers = require("plugins.evaluator.handlers")
local card_view = require("plugins.evaluator.card_view")
local settings_helpers = require("observatory.plugin_helpers.settings")

local SORT_MODE_CYCLE = {
    body  = "price",
    price = "body",
}

local DEFAULT_SORT_MODE = "price"

local PERSISTENT_STATE_DEFAULTS = {
    is_system_hidden  = false,
    is_scanned_hidden = true,
    sort_mode         = DEFAULT_SORT_MODE,
}

local Plugin = {
    id = "evaluator",
    name = "Evaluator",
    short_name = "Evaluator",
    version = "0.2.0",
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

local function send_notification(args)
    if not core_ref then return end
    core_ref:send_notification(args)
end

function Plugin:load(core)
    core_ref = core
    settings_helpers.apply_defaults(self)
    core:bind_state(self, PERSISTENT_STATE_DEFAULTS)
    handlers.set_notifier(send_notification)
end

function Plugin:journal_event(entry)
    handlers.dispatch(entry, self.settings)
end

function Plugin:status_change(_)
end

function Plugin:set_system_hidden(is_enabled)
    self.is_system_hidden = is_enabled and true or false
    if core_ref then core_ref:save_state() end
end

function Plugin:set_scanned_hidden(is_enabled)
    self.is_scanned_hidden = is_enabled and true or false
    if core_ref then core_ref:save_state() end
end

function Plugin:cycle_sort_mode()
    local current = self.sort_mode or DEFAULT_SORT_MODE
    self.sort_mode = SORT_MODE_CYCLE[current] or DEFAULT_SORT_MODE
    if core_ref then core_ref:save_state() end
end

function Plugin:draw_view(view_state, x, y, w, h)
    return card_view.draw(view_state, x, y, w, h, self.settings,
        self.is_system_hidden, self.sort_mode or DEFAULT_SORT_MODE,
        self.is_scanned_hidden)
end

function Plugin:row_count_label()
    return string.format("%d BODIES",
        card_view.card_count(self.settings, self.is_scanned_hidden))
end

return Plugin
