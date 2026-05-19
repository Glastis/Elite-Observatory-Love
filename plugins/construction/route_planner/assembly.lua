local constants      = require("plugins.construction.route_constants")
local route_distance = require("plugins.construction.route_distance")

local assembly = {}

local function flatten_stop(stop, previous_coords, jump_range)
    local distance_ly

    distance_ly = route_distance.between(previous_coords, stop.station.coords) or 0
    return {
        kind                   = stop.kind,
        system                 = stop.station.system_name,
        station                = stop.station.station_name,
        coords                 = stop.station.coords,
        distance_to_arrival_ls = stop.station.distance_to_arrival_ls,
        distance_ly            = distance_ly,
        jumps                  = route_distance.jumps_for_leg(distance_ly,
            jump_range, constants.JUMPS_MIN_PER_LEG),
        pickups                = stop.pickups,
    }
end

local function flatten_trip(trip, trip_origin, depot_coords, ship, stops)
    local previous
    local total_jumps
    local position
    local stop
    local range
    local flat
    local return_ly

    previous = trip_origin
    total_jumps = 0
    position = 1
    while trip.stops[position] do
        stop = trip.stops[position]
        range = (position == 1) and ship.jump_range_unloaded or ship.jump_range_loaded
        flat = flatten_stop(stop, previous, range)
        total_jumps = total_jumps + flat.jumps
        table.insert(stops, flat)
        previous = stop.station.coords
        position = position + 1
    end
    return_ly = route_distance.between(previous, depot_coords) or 0
    return total_jumps + route_distance.jumps_for_leg(return_ly,
        ship.jump_range_loaded, constants.JUMPS_MIN_PER_LEG)
end

local function flatten_trips(routes, depot_coords, origin_coords, ship)
    local stops
    local total_jumps
    local index
    local trip_origin

    stops = {}
    total_jumps = 0
    index = 1
    while routes[index] do
        trip_origin = (index == 1) and origin_coords or depot_coords
        total_jumps = total_jumps + flatten_trip(routes[index], trip_origin,
            depot_coords, ship, stops)
        index = index + 1
    end
    return stops, total_jumps
end

function assembly.assemble(routes, market)
    local stops
    local total_jumps

    stops, total_jumps = flatten_trips(routes, market.depot_coords,
        market.origin_coords, market.ship)
    return {
        status        = constants.STATUS_READY,
        stops         = stops,
        total_stops   = #stops,
        total_jumps   = total_jumps,
        unsatisfiable = market.unsatisfiable,
    }
end

return assembly
