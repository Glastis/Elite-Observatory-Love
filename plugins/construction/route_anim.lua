local animation = require("observatory.ui.animation")
local input     = require("observatory.ui.input")

local route_anim = {}

local GREEN_RAMP_S = 0.16
local GREEN_HOLD_S = 0.40
local FADE_OUT_S   = 0.34
local FADE_IN_S    = 0.30
local SLIDE_S      = 0.28
local EASING       = "ease_out_cubic"

local PHASE_GREEN  = "green"
local PHASE_FADE   = "fade"
local PHASE_PRUNED = "pruned"

local function ensure_card_anim(view_state, market_id)
    view_state.route_anim = view_state.route_anim or {}
    local card_anim = view_state.route_anim[market_id]
    if card_anim then return card_anim end
    card_anim = { stops = {} }
    view_state.route_anim[market_id] = card_anim
    return card_anim
end

local function build_layout(stops, top_y, ctx)
    local layout = {}
    local cy = top_y
    local index = 1
    while stops[index] do
        local stop = stops[index]
        cy = cy + ctx.gap
        layout[index] = { stop = stop, target_y = cy }
        cy = cy + ctx.stop_height(stop)
        index = index + 1
    end
    return layout
end

local function count_existing(card_anim, layout)
    local existing = 0
    local index = 1
    while layout[index] do
        if card_anim.stops[layout[index].stop.id] then
            existing = existing + 1
        end
        index = index + 1
    end
    return existing
end

local function new_entry(target_y, is_intro)
    local entry = {
        y        = animation.tween(target_y),
        alpha    = animation.tween(1),
        green    = animation.tween(0),
        target_y = target_y,
        phase_t  = 0,
    }
    if is_intro then
        animation.set(entry.alpha, 0)
        animation.go(entry.alpha, 1, FADE_IN_S, EASING)
    end
    return entry
end

local function present_ids(layout)
    local ids = {}
    local index = 1
    while layout[index] do
        ids[layout[index].stop.id] = true
        index = index + 1
    end
    return ids
end

local function drop_missing(card_anim, ids)
    local stale = {}
    local id = next(card_anim.stops)
    while id do
        if not ids[id] then table.insert(stale, id) end
        id = next(card_anim.stops, id)
    end
    local index = 1
    while stale[index] do
        card_anim.stops[stale[index]] = nil
        index = index + 1
    end
end

local function reconcile(card_anim, layout)
    local is_intro = count_existing(card_anim, layout) > 0
    local index = 1
    while layout[index] do
        local item = layout[index]
        if not card_anim.stops[item.stop.id] then
            card_anim.stops[item.stop.id] = new_entry(item.target_y, is_intro)
        end
        index = index + 1
    end
    drop_missing(card_anim, present_ids(layout))
end

local function start_green(entry)
    entry.phase = PHASE_GREEN
    entry.phase_t = 0
    animation.go(entry.green, 1, GREEN_RAMP_S, EASING)
end

local function enter_fade(entry)
    animation.go(entry.alpha, 0, FADE_OUT_S, EASING)
end

local PHASE_NEXT = {
    [PHASE_GREEN] = { duration = GREEN_HOLD_S, follows = PHASE_FADE },
    [PHASE_FADE]  = { duration = FADE_OUT_S, follows = PHASE_PRUNED,
        on_enter = enter_fade },
}

local function advance_phase(entry, dt)
    local step = PHASE_NEXT[entry.phase]
    if not step then return false end
    entry.phase_t = entry.phase_t + dt
    if entry.phase_t < step.duration then return false end
    entry.phase = step.follows
    entry.phase_t = 0
    if PHASE_NEXT[entry.phase] and PHASE_NEXT[entry.phase].on_enter then
        PHASE_NEXT[entry.phase].on_enter(entry)
    end
    return entry.phase == PHASE_PRUNED
end

local function slide_to(entry, target_y)
    if entry.target_y == target_y then return end
    entry.target_y = target_y
    animation.go(entry.y, target_y, SLIDE_S, EASING)
end

local function update_entry(entry, target_y, dt)
    slide_to(entry, target_y)
    animation.update(entry.y, dt)
    animation.update(entry.alpha, dt)
    animation.update(entry.green, dt)
end

local function draw_entry(entry, stop, x, w, ctx)
    if entry.phase == PHASE_PRUNED then return end
    ctx.draw_stop(stop, x, entry.y.value, w,
        entry.alpha.value, entry.green.value)
end

local function prune(card_anim, ctx, doomed)
    local index = 1
    while doomed[index] do
        local id = doomed[index]
        card_anim.stops[id] = nil
        ctx.prune(id)
        index = index + 1
    end
end

function route_anim.run(view_state, market_id, stops, x, top_y, w, ctx)
    local card_anim = ensure_card_anim(view_state, market_id)
    local layout = build_layout(stops, top_y, ctx)
    reconcile(card_anim, layout)
    local dt = input.dt or 0
    local doomed = {}
    local index = 1
    while layout[index] do
        local item = layout[index]
        local entry = card_anim.stops[item.stop.id]
        if item.stop.is_completed and not entry.phase then
            start_green(entry)
        end
        if advance_phase(entry, dt) then
            table.insert(doomed, item.stop.id)
        end
        update_entry(entry, item.target_y, dt)
        draw_entry(entry, item.stop, x, w, ctx)
        index = index + 1
    end
    prune(card_anim, ctx, doomed)
end

return route_anim
