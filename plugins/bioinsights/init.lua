local constants = require("plugins.bioinsights.constants")
local handlers = require("plugins.bioinsights.handlers")
local card_view = require("plugins.bioinsights.card_view")
local state = require("plugins.bioinsights.state")

local SORT_MODE_CYCLE = {
    body  = "price",
    price = "body",
}

local DEFAULT_SORT_MODE = "body"

local Plugin = {
    id = "bioinsights",
    name = "Observatory Bio Insights",
    short_name = "BioInsights",
    version = "0.1.0",
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

local function sync_state_context()
    state.set_user_context({
        near_nebula   = Plugin.near_nebula,
        near_guardian = Plugin.near_guardian,
    })
end

local function apply_user_context_change()
    sync_state_context()
    state.refresh_all_constraints()
end

local function send_notification(args)
    if not core_ref then return end
    core_ref:send_notification(args)
end

function Plugin:load(core)
    core_ref = core
    ensure_settings(self)
    if self.is_scanned_hidden == nil then self.is_scanned_hidden = true end
    handlers.set_notifier(send_notification)
    sync_state_context()
end

function Plugin:journal_event(entry)
    handlers.dispatch(entry, self.settings)
end

function Plugin:status_change(status)
    handlers.handle_status(status)
end

function Plugin:set_near_nebula(is_enabled)
    self.near_nebula = is_enabled and true or false
    apply_user_context_change()
end

function Plugin:set_near_guardian(is_enabled)
    self.near_guardian = is_enabled and true or false
    apply_user_context_change()
end

function Plugin:set_system_hidden(is_enabled)
    self.is_system_hidden = is_enabled and true or false
end

function Plugin:set_scanned_hidden(is_enabled)
    self.is_scanned_hidden = is_enabled and true or false
end

function Plugin:cycle_sort_mode()
    local current = self.sort_mode or DEFAULT_SORT_MODE
    self.sort_mode = SORT_MODE_CYCLE[current] or DEFAULT_SORT_MODE
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
