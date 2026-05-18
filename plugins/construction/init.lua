local constants        = require("plugins.construction.constants")
local handlers         = require("plugins.construction.handlers")
local card_view        = require("plugins.construction.card_view")
local plugin_state     = require("plugins.construction.state")
local settings_helpers = require("observatory.plugin_helpers.settings")

local PERSISTENT_STATE_DEFAULTS = {
    sites          = {},
    hidden         = {},
    is_show_hidden = false,
}

local Plugin = {
    id         = "construction",
    name       = "Construction Tracker",
    short_name = "Construction",
    version    = "0.1.0",
    default_settings = {},
}

local core_ref

function Plugin:load(core)
    core_ref = core
    settings_helpers.apply_defaults(self)
    core:bind_state(self, PERSISTENT_STATE_DEFAULTS)
    plugin_state.attach(self.sites, self.hidden)
    plugin_state.set_on_change(function() core:save_state() end)
end

function Plugin:journal_event(entry)
    handlers.dispatch(entry, self.settings)
end

function Plugin:status_change(_)
end

function Plugin:set_show_hidden(is_enabled)
    self.is_show_hidden = is_enabled and true or false
    if core_ref then core_ref:save_state() end
end

function Plugin:draw_view(view_state, x, y, w, h)
    return card_view.draw(view_state, x, y, w, h, self.is_show_hidden)
end

function Plugin:row_count_label()
    local count = plugin_state.visible_count()
    if self.is_show_hidden then count = plugin_state.site_count() end
    return string.format(constants.ROW_COUNT_FORMAT, count)
end

return Plugin
