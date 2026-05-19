local route_state = {}

local routes = {}
local in_flight = {}

function route_state.reset()
    routes = {}
    in_flight = {}
end

function route_state.get(market_id)
    return routes[market_id]
end

function route_state.set(market_id, route)
    routes[market_id] = route
end

function route_state.set_status(market_id, status)
    local route = routes[market_id] or { stops = {} }
    route.status = status
    route.stops = route.stops or {}
    routes[market_id] = route
end

function route_state.remove(market_id)
    routes[market_id] = nil
    in_flight[market_id] = nil
end

function route_state.preview(market_id, count)
    local route = routes[market_id]
    if not route then return nil end
    local stops = {}
    local available = route.stops or {}
    for index = 1, math.min(count, #available) do
        stops[index] = available[index]
    end
    return {
        status        = route.status,
        total_stops   = route.total_stops or #available,
        total_jumps   = route.total_jumps,
        unsatisfiable = route.unsatisfiable or {},
        stops         = stops,
    }
end

function route_state.mark_in_flight(market_id, handle)
    in_flight[market_id] = handle
end

function route_state.in_flight_handle(market_id)
    return in_flight[market_id]
end

function route_state.clear_in_flight(market_id)
    in_flight[market_id] = nil
end

return route_state
