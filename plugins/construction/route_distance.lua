local route_distance = {}

local DEFAULT_MIN_JUMPS = 1

function route_distance.between(coords_a, coords_b)
    if not coords_a or not coords_b then return nil end
    local dx = (coords_a.x or 0) - (coords_b.x or 0)
    local dy = (coords_a.y or 0) - (coords_b.y or 0)
    local dz = (coords_a.z or 0) - (coords_b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function route_distance.jumps_for_leg(distance_ly, jump_range, min_jumps)
    min_jumps = min_jumps or DEFAULT_MIN_JUMPS
    if not distance_ly or distance_ly <= 0 then return 0 end
    if not jump_range or jump_range <= 0 then return min_jumps end
    return math.max(min_jumps, math.ceil(distance_ly / jump_range))
end

return route_distance
