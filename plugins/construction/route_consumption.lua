local route_consumption = {}

local function find_pickup(stop, commodity_key)
    local pickups = stop.pickups or {}
    local index = 1
    while pickups[index] do
        if pickups[index].commodity_key == commodity_key then
            return pickups[index]
        end
        index = index + 1
    end
    return nil
end

local function consume_into_stop(stop, commodity_key, amount)
    local pickup = find_pickup(stop, commodity_key)
    if not pickup then return amount end
    stop.delivered = stop.delivered or {}
    local already = stop.delivered[commodity_key] or 0
    local room = math.max(0, pickup.quantity - already)
    local taken = math.min(room, amount)
    stop.delivered[commodity_key] = already + taken
    return amount - taken
end

local function consume_commodity(stops, commodity_key, amount)
    local index = 1
    while stops[index] and amount > 0 do
        amount = consume_into_stop(stops[index], commodity_key, amount)
        index = index + 1
    end
end

local function is_stop_delivered(stop)
    local pickups = stop.pickups or {}
    if not pickups[1] then return false end
    local delivered = stop.delivered or {}
    local index = 1
    while pickups[index] do
        local pickup = pickups[index]
        if (delivered[pickup.commodity_key] or 0) < pickup.quantity then
            return false
        end
        index = index + 1
    end
    return true
end

local function mark_completed(stops)
    local index = 1
    while stops[index] do
        local stop = stops[index]
        if not stop.is_completed and is_stop_delivered(stop) then
            stop.is_completed = true
        end
        index = index + 1
    end
end

function route_consumption.apply(route, delivered_delta)
    local stops = (route and route.stops) or {}
    local commodity_key = next(delivered_delta)
    while commodity_key do
        consume_commodity(stops, commodity_key, delivered_delta[commodity_key])
        commodity_key = next(delivered_delta, commodity_key)
    end
    mark_completed(stops)
end

return route_consumption
