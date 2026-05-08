-- Tiny tween system. Each component owns its tweens inside its persistent
-- state slot and calls `update` from its draw function. There is no global
-- tween registry — values stay scoped to the component that drives them.

local M = {}

M.easings = {
    linear = function(t) return t end,
    ease_out_cubic = function(t)
        t = t - 1
        return t * t * t + 1
    end,
    ease_in_out_cubic = function(t)
        if t < 0.5 then
            return 4 * t * t * t
        else
            t = 2 * t - 2
            return 0.5 * t * t * t + 1
        end
    end,
    -- Approximation of cubic-bezier(.4,1.2,.4,1) — slight overshoot ease-out.
    back_out = function(t)
        local c1 = 1.40158
        local c3 = c1 + 1
        local k = t - 1
        return 1 + c3 * k * k * k + c1 * k * k
    end,
}

local function pick_ease(name_or_fn)
    if type(name_or_fn) == "function" then return name_or_fn end
    return M.easings[name_or_fn] or M.easings.ease_out_cubic
end

function M.tween(initial)
    return {
        kind = "scalar",
        value = initial,
        from = initial,
        target = initial,
        t = 0,
        duration = 0,
        easing = M.easings.ease_out_cubic,
    }
end

function M.go(tw, target, duration, easing)
    if tw.target == target and tw.duration == 0 then return end
    tw.from = tw.value
    tw.target = target
    tw.duration = duration or 0.22
    tw.t = 0
    tw.easing = pick_ease(easing)
end

function M.set(tw, value)
    tw.value = value
    tw.from = value
    tw.target = value
    tw.t = 0
    tw.duration = 0
end

function M.update(tw, dt)
    if tw.duration <= 0 then
        tw.value = tw.target
        return
    end
    tw.t = tw.t + dt
    if tw.t >= tw.duration then
        tw.value = tw.target
        tw.duration = 0
        tw.t = 0
    else
        local k = tw.easing(tw.t / tw.duration)
        tw.value = tw.from + (tw.target - tw.from) * k
    end
end

function M.tween_color(initial)
    initial = initial or { 1, 1, 1, 1 }
    return {
        kind = "color",
        r = M.tween(initial[1]),
        g = M.tween(initial[2]),
        b = M.tween(initial[3]),
        a = M.tween(initial[4] or 1),
    }
end

function M.go_color(tc, target, duration, easing)
    M.go(tc.r, target[1], duration, easing)
    M.go(tc.g, target[2], duration, easing)
    M.go(tc.b, target[3], duration, easing)
    M.go(tc.a, target[4] or 1, duration, easing)
end

function M.set_color(tc, target)
    M.set(tc.r, target[1])
    M.set(tc.g, target[2])
    M.set(tc.b, target[3])
    M.set(tc.a, target[4] or 1)
end

function M.update_color(tc, dt)
    M.update(tc.r, dt)
    M.update(tc.g, dt)
    M.update(tc.b, dt)
    M.update(tc.a, dt)
end

function M.color_value(tc)
    return { tc.r.value, tc.g.value, tc.b.value, tc.a.value }
end

function M.sine(time, period)
    period = period or 1
    local k = (time % period) / period
    return 0.5 - 0.5 * math.cos(k * 2 * math.pi)
end

function M.fade_in(state, dt, duration)
    state.t = (state.t or 0) + dt
    duration = duration or 0.25
    if state.t >= duration then return 1 end
    local k = state.t / duration
    return M.easings.ease_out_cubic(k)
end

return M
