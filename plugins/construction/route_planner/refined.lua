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

local function sorted_keys_by_price(map)
    local keys
    local key

    keys = {}
    key = next(map)
    while key do
        table.insert(keys, key)
        key = next(map, key)
    end
    table.sort(keys, function(a, b)
        return map[a].price < map[b].price
    end)
    return keys
end

local function ensure_pickup_entry(result, result_index, commodity_key, source)
    local entry

    entry = result_index[commodity_key]
    if entry then return entry end
    entry = {
        commodity_key = commodity_key,
        display       = source.display,
        quantity      = 0,
        unit_price    = source.price,
    }
    table.insert(result, entry)
    result_index[commodity_key] = entry
    return entry
end

local function add_to_pickup(result, result_index, commodity_key, source, amount)
    local entry

    if amount <= 0 then return end
    entry = ensure_pickup_entry(result, result_index, commodity_key, source)
    entry.quantity = entry.quantity + amount
end

local function consume_reservation(visit, cargo_left, result, result_index)
    local keys
    local taken
    local position
    local commodity_key
    local pickup
    local take

    keys = sorted_keys_by_price(visit.pickups)
    taken = 0
    position = 1
    while keys[position] do
        commodity_key = keys[position]
        pickup = visit.pickups[commodity_key]
        take = math.min(pickup.quantity, cargo_left - taken)
        if take > 0 then
            add_to_pickup(result, result_index, commodity_key, pickup, take)
            pickup.quantity = pickup.quantity - take
            taken = taken + take
        end
        position = position + 1
    end
    return taken
end

local function steal_reservation(visits, current_visit, commodity_key, max_amount)
    local stolen
    local position
    local other
    local pickup
    local take

    stolen = 0
    position = 1
    while visits[position] and stolen < max_amount do
        other = visits[position]
        if other ~= current_visit then
            pickup = other.pickups[commodity_key]
            if pickup and pickup.quantity > 0 then
                take = math.min(pickup.quantity, max_amount - stolen)
                pickup.quantity = pickup.quantity - take
                stolen = stolen + take
            end
        end
        position = position + 1
    end
    return stolen
end

local function top_up_offer(visits, visit, commodity_key, cargo_left,
        remaining, result, result_index)
    local offer
    local from_remaining
    local from_steal

    offer = visit.station.offers[commodity_key]
    if not offer or offer.stock <= 0 or cargo_left <= 0 then return 0 end
    from_remaining = math.min(remaining[commodity_key] or 0, offer.stock,
        cargo_left)
    if from_remaining > 0 then
        remaining[commodity_key] = remaining[commodity_key] - from_remaining
        offer.stock = offer.stock - from_remaining
        add_to_pickup(result, result_index, commodity_key, offer, from_remaining)
    end
    from_steal = steal_reservation(visits, visit, commodity_key,
        math.min(offer.stock, cargo_left - from_remaining))
    if from_steal > 0 then
        offer.stock = offer.stock - from_steal
        add_to_pickup(result, result_index, commodity_key, offer, from_steal)
    end
    return from_remaining + from_steal
end

local function top_up_from_station(visits, visit, cargo_left, remaining,
        result, result_index)
    local keys
    local taken
    local position
    local pulled

    keys = sorted_keys_by_price(visit.station.offers)
    taken = 0
    position = 1
    while keys[position] and taken < cargo_left do
        pulled = top_up_offer(visits, visit, keys[position], cargo_left - taken,
            remaining, result, result_index)
        taken = taken + pulled
        position = position + 1
    end
    return taken
end

local function take_from_visit(visits, visit, cargo_left, remaining)
    local result
    local result_index
    local taken
    local extra

    result = {}
    result_index = {}
    taken = consume_reservation(visit, cargo_left, result, result_index)
    extra = top_up_from_station(visits, visit, cargo_left - taken, remaining,
        result, result_index)
    return result, taken + extra
end

local function nearest_visit(visits, cursor)
    local best
    local best_distance
    local position
    local visit
    local distance

    position = 1
    while visits[position] do
        visit = visits[position]
        if pickup_quantity(visit) > 0 then
            distance = route_distance.between(visit.station.coords, cursor)
                or math.huge
            if not best_distance or distance < best_distance then
                best, best_distance = visit, distance
            end
        end
        position = position + 1
    end
    return best
end

local function build_trip(visits, cargo_capacity, depot_coords, remaining)
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
        pickups, taken = take_from_visit(visits, visit, cargo_left, remaining)
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

local function pack_trips(visits, cargo_capacity, depot_coords, remaining)
    local routes
    local trip

    routes = {}
    while nearest_visit(visits, depot_coords) do
        trip = build_trip(visits, cargo_capacity, depot_coords, remaining)
        if #trip.stops == 0 then break end
        table.insert(routes, trip)
    end
    return routes
end

function refined.find(market)
    local visits
    local routes

    visits = run_cover_phase(market.index, market.remaining,
        market.depot_coords, market.ship)
    routes = pack_trips(visits, market.ship.cargo_capacity,
        market.depot_coords, market.remaining)
    append_leftovers(market.remaining, market.unsatisfiable)
    return trips.order(routes, market.depot_coords)
end

return refined
