local constants      = require("plugins.construction.route_constants")
local route_distance = require("plugins.construction.route_distance")
local scoring        = require("plugins.construction.route_planner.scoring")
local trips          = require("plugins.construction.route_planner.trips")

local refined = {}

local function take_station_pickups(station, remaining)
    local pickups
    local commodity_key
    local offer
    local wanted
    local take

    pickups = {}
    commodity_key = next(station.offers)
    while commodity_key do
        offer = station.offers[commodity_key]
        wanted = remaining[commodity_key] or 0
        take = math.min(wanted, offer.stock)
        if take > 0 then
            pickups[commodity_key] = {
                quantity = take,
                price    = offer.price,
                display  = offer.display,
            }
            remaining[commodity_key] = wanted - take
            offer.stock = offer.stock - take
        end
        commodity_key = next(station.offers, commodity_key)
    end
    return pickups
end

local function run_cover_phase(index, remaining, depot_coords, ship)
    local visits
    local station

    visits = {}
    while true do
        station = scoring.best_cover_station(index, remaining, depot_coords, ship)
        if not station then break end
        table.insert(visits, {
            station = station,
            pickups = take_station_pickups(station, remaining),
        })
    end
    return visits
end

local function append_leftovers(remaining, unsatisfiable)
    local commodity_key

    commodity_key = next(remaining)
    while commodity_key do
        if remaining[commodity_key] > 0 then
            table.insert(unsatisfiable, commodity_key)
        end
        commodity_key = next(remaining, commodity_key)
    end
end

local function pickup_quantity(visit)
    local total
    local commodity_key

    total = 0
    commodity_key = next(visit.pickups)
    while commodity_key do
        total = total + visit.pickups[commodity_key].quantity
        commodity_key = next(visit.pickups, commodity_key)
    end
    return total
end

local function sorted_pickup_keys(pickups)
    local keys
    local commodity_key

    keys = {}
    commodity_key = next(pickups)
    while commodity_key do
        table.insert(keys, commodity_key)
        commodity_key = next(pickups, commodity_key)
    end
    table.sort(keys, function(a, b)
        return pickups[a].price < pickups[b].price
    end)
    return keys
end

local function take_from_visit(visit, cargo_left)
    local keys
    local taken
    local result
    local index
    local commodity_key
    local pickup
    local take

    keys = sorted_pickup_keys(visit.pickups)
    taken = 0
    result = {}
    index = 1
    while keys[index] do
        commodity_key = keys[index]
        pickup = visit.pickups[commodity_key]
        take = math.min(pickup.quantity, cargo_left - taken)
        if take > 0 then
            table.insert(result, {
                commodity_key = commodity_key,
                display       = pickup.display,
                quantity      = take,
                unit_price    = pickup.price,
            })
            pickup.quantity = pickup.quantity - take
            taken = taken + take
        end
        index = index + 1
    end
    return result, taken
end

local function nearest_visit(visits, cursor)
    local best
    local best_distance
    local index
    local visit
    local distance

    index = 1
    while visits[index] do
        visit = visits[index]
        if pickup_quantity(visit) > 0 then
            distance = route_distance.between(visit.station.coords, cursor) or math.huge
            if not best_distance or distance < best_distance then
                best, best_distance = visit, distance
            end
        end
        index = index + 1
    end
    return best
end

local function build_trip(visits, cargo_capacity, depot_coords)
    local trip
    local cargo_left
    local cursor
    local visit
    local pickups
    local taken

    trip = { stops = {} }
    cargo_left = cargo_capacity
    cursor = depot_coords
    while cargo_left > 0 do
        visit = nearest_visit(visits, cursor)
        if not visit then break end
        pickups, taken = take_from_visit(visit, cargo_left)
        if taken <= 0 then break end
        table.insert(trip.stops, {
            kind    = constants.MULTI_STOP_KIND,
            station = visit.station,
            total   = taken,
            pickups = pickups,
        })
        cargo_left = cargo_left - taken
        cursor = visit.station.coords
    end
    return trip
end

local function pack_trips(visits, cargo_capacity, depot_coords)
    local routes
    local trip

    routes = {}
    while nearest_visit(visits, depot_coords) do
        trip = build_trip(visits, cargo_capacity, depot_coords)
        if #trip.stops == 0 then break end
        table.insert(routes, trip)
    end
    return routes
end

function refined.find(market)
    local visits
    local routes

    visits = run_cover_phase(market.index, market.remaining, market.depot_coords, market.ship)
    append_leftovers(market.remaining, market.unsatisfiable)
    routes = pack_trips(visits, market.ship.cargo_capacity, market.depot_coords)
    return trips.order(routes, market.depot_coords)
end

return refined
