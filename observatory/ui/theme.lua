-- Design tokens — colour palette, font factory, and the timing/easing
-- constants the components share so animations stay consistent.
--
-- The palette mirrors the v7-cross.jsx prototype: oklch-based warm amber accent
-- on a near-black surface with sparing greys for rules and secondary text.

local M = {}

local function rgb(r, g, b, a)
    return { r / 255, g / 255, b / 255, a or 1 }
end

M.colors = {
    bg          = rgb(0x08, 0x09, 0x0a),
    panel       = rgb(0x0c, 0x0d, 0x0f),
    panel_deep  = rgb(0x04, 0x05, 0x06),
    rule        = { 1, 1, 1, 0.07 },
    rule_strong = { 1, 1, 1, 0.13 },
    text        = rgb(0xe6, 0xe7, 0xea),
    text_dim    = rgb(0x88, 0x8a, 0x90),
    text_faint  = rgb(0x54, 0x56, 0x5c),

    -- oklch(0.80 0.13 60) → warm amber.
    accent      = { 0.982, 0.661, 0.380, 1 },
    accent_soft = { 0.982, 0.661, 0.380, 0.18 },
    accent_rule = { 0.982, 0.661, 0.380, 0.35 },

    -- oklch(0.78 0.13 150) → readable green for the "● READABLE" indicator.
    success     = { 0.452, 0.816, 0.533, 1 },

    danger      = { 0.965, 0.376, 0.376, 1 },

    row_hover   = { 1, 1, 1, 0.025 },
    row_alt     = { 1, 1, 1, 0.018 },
    seg_hover   = { 1, 1, 1, 0.04 },
    knob_on     = rgb(0x1a, 0x12, 0x06),
    knob_off    = rgb(0xcc, 0xcd, 0xd0),
    track_off   = { 1, 1, 1, 0.08 },
}

M.motion = {
    fast      = 0.18,
    normal    = 0.22,
    slow      = 0.25,
    overshoot = "back_out",
    smooth    = "ease_out_cubic",
    pulse_period = 2.4,
}

M.metrics = {
    rule_w        = 1,
    section_pad_x = 18,
    section_pad_y = 20,
    row_h         = 28,
    bar_top_h     = 44,
    tabs_h        = 36,
    bar_bottom_h  = 30,
    seg_pad_x     = 12,
    seg_pad_y     = 7,
    btn_radius    = 0,
}

local font_paths = {
    main = "assets/fonts/Geist-Regular.ttf",
    main_medium = "assets/fonts/Geist-Medium.ttf",
    mono = "assets/fonts/JetBrainsMono-Regular.ttf",
    mono_medium = "assets/fonts/JetBrainsMono-Medium.ttf",
}

local font_cache = {}

local function load_font(family, size)
    local path = font_paths[family]
    if path and love.filesystem.getInfo(path) then
        return love.graphics.newFont(path, size)
    end
    return love.graphics.newFont(size)
end

function M.font(family, size)
    family = family or "main"
    size = size or 13
    local key = family .. "@" .. size
    if not font_cache[key] then
        font_cache[key] = load_font(family, size)
    end
    return font_cache[key]
end

function M.with_alpha(color, alpha)
    return { color[1], color[2], color[3], alpha }
end

return M
