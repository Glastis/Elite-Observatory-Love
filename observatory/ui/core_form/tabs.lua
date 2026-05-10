local ui = require("observatory.ui")
local theme = ui.theme

local tabs_view = {}

local TAB_W = 160
local TAB_PAD_X = 14
local FADE_DURATION = 0.25
local FADE_OFFSET_FACTOR = 4

function tabs_view.draw(state, w, y, fixed_labels, plugins)
    local hh = theme.metrics.tabs_h
    ui.panel.draw(0, y, w, hh, {
        bg = theme.colors.panel,
        border = false,
    })
    state.tabs = state.tabs or {}

    local labels = {}
    for _, l in ipairs(fixed_labels) do table.insert(labels, l) end
    for _, p in ipairs(plugins) do
        table.insert(labels, p.short_name or p.name)
    end

    local sel = ui.tabs.draw(state.tabs, labels, 0, y, w, hh, {
        tab_w = TAB_W, pad_x = TAB_PAD_X,
        font = theme.font("main", 13),
    })
    return sel, hh
end

function tabs_view.begin_pane_fade(state, tab_index)
    if state.last_tab ~= tab_index then
        state.fade.t = 0
        state.last_tab = tab_index
    end
    local k = ui.animation.fade_in(state.fade, ui.input.dt, FADE_DURATION)
    return k, (1 - k) * FADE_OFFSET_FACTOR
end

return tabs_view
