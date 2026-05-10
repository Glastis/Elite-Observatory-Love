local ui = require("observatory.ui")
local plugin_pane = require("observatory.ui.core_form.plugin_pane")
local theme = ui.theme

local combined_pane = {}

local SEPARATOR_W = 1
local PLACEHOLDER_TEXT = "Pick a plugin in Core settings."

local SPLIT_LAYOUTS = {
    vertical = function(w, body_y, body_h)
        local half_w = math.floor(w / 2)
        return {
            { x = 0,      y = body_y, w = half_w,     h = body_h },
            { x = half_w, y = body_y, w = w - half_w, h = body_h },
            separator = {
                x = half_w, y = body_y, w = SEPARATOR_W, h = body_h,
            },
        }
    end,
    horizontal = function(w, body_y, body_h)
        local half_h = math.floor(body_h / 2)
        return {
            { x = 0, y = body_y,          w = w, h = half_h },
            { x = 0, y = body_y + half_h, w = w, h = body_h - half_h },
            separator = {
                x = 0, y = body_y + half_h, w = w, h = SEPARATOR_W,
            },
        }
    end,
}

local function plugin_for_pane(plugin_id, list_enabled)
    if not plugin_id or plugin_id == "" then return nil end
    for _, p in ipairs(list_enabled) do
        if p.id == plugin_id then return p end
    end
    return nil
end

local function draw_pane(state, plugin, pane)
    if plugin then
        plugin_pane.draw(state, plugin, pane.x, pane.y, pane.w, pane.h)
        return
    end
    local font = theme.font("mono", 11)
    ui.text.draw(PLACEHOLDER_TEXT,
        pane.x, pane.y + pane.h / 2 - font:getHeight() / 2, {
            font = font, color = theme.colors.text_faint,
            letter_em = 0.08, align = "center", width = pane.w,
        })
end

local function layout_for(w, body_y, body_h, split, default_split)
    local layout_fn = SPLIT_LAYOUTS[split] or SPLIT_LAYOUTS[default_split]
    return layout_fn(w, body_y, body_h)
end

function combined_pane.draw(state, w, body_y, body_h, deps)
    local split = deps.settings.get(deps.split_key) or deps.default_split
    local panes = layout_for(w, body_y, body_h, split, deps.default_split)
    local list_enabled = deps.list_enabled_plugins()
    local left = plugin_for_pane(deps.settings.get(deps.slot_keys.left), list_enabled)
    local right = plugin_for_pane(deps.settings.get(deps.slot_keys.right), list_enabled)
    draw_pane(state, left, panes[1])
    draw_pane(state, right, panes[2])

    local sep = panes.separator
    love.graphics.setColor(theme.colors.rule)
    love.graphics.rectangle("fill", sep.x, sep.y, sep.w, sep.h)
end

return combined_pane
