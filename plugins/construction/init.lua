local constants        = require("plugins.construction.constants")
local handlers         = require("plugins.construction.handlers")
local card_view        = require("plugins.construction.card_view")
local toolbar          = require("plugins.construction.toolbar")
local plugin_state     = require("plugins.construction.state")
local route_service    = require("plugins.construction.route_service")
local settings_helpers = require("observatory.plugin_helpers.settings")

local PERSISTENT_STATE_DEFAULTS = {
    sites          = {},
    hidden         = {},
    is_show_hidden = false,
    ship_params    = { cargo_capacity = "", jump_loaded = "", jump_unloaded = "" },
}

local Plugin = {
    id         = "construction",
    name       = "Construction Tracker",
    short_name = "Construction",
    version    = "0.2.0",
    default_settings = {},
}

local core_ref

function Plugin:load(core)
    core_ref = core
    settings_helpers.apply_defaults(self)
    core:bind_state(self, PERSISTENT_STATE_DEFAULTS)
    plugin_state.attach(self.sites, self.hidden)
    plugin_state.set_on_change(function() core:save_state() end)
    plugin_state.set_on_site_added(route_service.on_site_added)
    plugin_state.set_on_site_removed(route_service.on_site_removed)
    plugin_state.set_on_refresh_route(function(market_id)
        route_service.compute_for_site(market_id, true)
    end)
    route_service.init(core)
    route_service.set_ship_params(self.ship_params)
end

function Plugin:journal_event(entry)
    handlers.dispatch(entry, self.settings)
end

function Plugin:status_change(_)
end

function Plugin:log_monitor_state_changed(_)
    route_service.on_monitor_state_changed()
end

function Plugin:observatory_ready()
    route_service.observatory_ready()
end

function Plugin:update(dt)
    route_service.update(dt)
end

function Plugin:set_show_hidden(is_enabled)
    self.is_show_hidden = is_enabled and true or false
    if core_ref then core_ref:save_state() end
end

function Plugin:set_ship_param(param_key, value)
    self.ship_params[param_key] = value
    route_service.set_ship_params(self.ship_params)
    if core_ref then core_ref:save_state() end
    route_service.compute_all(true)
end

function Plugin:draw_toolbar_extra(view_state, x, y, w, h)
    toolbar.draw(view_state, self, x, y, w, h)
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
