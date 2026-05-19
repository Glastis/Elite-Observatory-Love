local constants      = require("plugins.construction.route_constants")
local route_distance = require("plugins.construction.route_distance")

local scoring = {}

local function round_trip_jumps(station, depot_coords, ship)
    local distance
    local outbound
    local inbound

    distance = route_distance.between(station.coords, depot_coords)
    if not distance then return math.huge end
    outbound = route_distance.jumps_for_leg(distance,
        ship.jump_range_unloaded, constants.JUMPS_MIN_PER_LEG)
    inbound = route_distance.jumps_for_leg(distance,
        ship.jump_range_loaded, constants.JUMPS_MIN_PER_LEG)
    return outbound + inbound
end

local function min_offer_price(stations, commodity_key)
    local min_price
    local index
    local price

    index = 1
    while stations[index] do
        price = stations[index].offers[commodity_key].price
        if not min_price or price < min_price then min_price = price end
        index = index + 1
    end
    return min_price
end

local function price_premium_jumps(price, min_price)
    local premium_pct

    if not min_price or min_price <= 0 then return 0 end
    premium_pct = (price - min_price) / min_price * 100
    return premium_pct / constants.PRICE_PCT_PER_JUMP
end

function scoring.full_load_stations(index, commodity_key, cargo_capacity)
    local list
    local key
    local offer

    list = {}
    key = next(index)
    while key do
        offer = index[key].offers[commodity_key]
        if offer and offer.stock >= cargo_capacity then
            table.insert(list, index[key])
        end
        key = next(index, key)
    end
    return list
end

function scoring.best_value_station(stations, commodity_key, depot_coords, ship)
    local min_price
    local best
    local best_cost
    local index
    local station
    local cost

    min_price = min_offer_price(stations, commodity_key)
    index = 1
    while stations[index] do
        station = stations[index]
        cost = round_trip_jumps(station, depot_coords, ship)
            + price_premium_jumps(station.offers[commodity_key].price, min_price)
        if not best_cost or cost < best_cost then
            best, best_cost = station, cost
        end
        index = index + 1
    end
    return best
end

local function score_station(station, remaining, depot_coords, ship)
    local covered_count
    local commodity_key
    local offer

    covered_count = 0
    commodity_key = next(station.offers)
    while commodity_key do
        offer = station.offers[commodity_key]
        if (remaining[commodity_key] or 0) > 0 and offer.stock > 0 then
            covered_count = covered_count + 1
        end
        commodity_key = next(station.offers, commodity_key)
    end
    if covered_count == 0 then return nil end
    return covered_count * constants.STATION_COVERAGE_WEIGHT
        - round_trip_jumps(station, depot_coords, ship)
end

function scoring.best_cover_station(index, remaining, depot_coords, ship)
    local best
    local best_score
    local key
    local score

    key = next(index)
    while key do
        score = score_station(index[key], remaining, depot_coords, ship)
        if score and (not best_score or score > best_score) then
            best, best_score = index[key], score
        end
        key = next(index, key)
    end
    return best
end

return scoring
