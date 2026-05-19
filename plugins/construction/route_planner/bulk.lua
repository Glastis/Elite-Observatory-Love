local constants = require("plugins.construction.route_constants")
local scoring   = require("plugins.construction.route_planner.scoring")
local trips     = require("plugins.construction.route_planner.trips")

local bulk = {}

local function bulk_stop(station, commodity_key, quantity)
    local offer

    offer = station.offers[commodity_key]
    return {
        kind    = constants.BULK_STOP_KIND,
        station = station,
        total   = quantity,
        pickups = { {
            commodity_key = commodity_key,
            display       = offer.display,
            quantity      = quantity,
            unit_price    = offer.price,
        } },
    }
end

local function peel_full_loads(market, commodity_key, routes)
    local index
    local remaining
    local ship
    local depot_coords
    local cargo
    local station

    index = market.index
    remaining = market.remaining
    ship = market.ship
    depot_coords = market.depot_coords
    cargo = ship.cargo_capacity
    while remaining[commodity_key] >= cargo do
        station = scoring.best_value_station(
            scoring.full_load_stations(index, commodity_key, cargo),
            commodity_key, depot_coords, ship)
        if not station then return end
        table.insert(routes, { stops = { bulk_stop(station, commodity_key, cargo) } })
        station.offers[commodity_key].stock = station.offers[commodity_key].stock - cargo
        remaining[commodity_key] = remaining[commodity_key] - cargo
    end
end

function bulk.find(market)
    local routes
    local commodity_key

    routes = {}
    commodity_key = next(market.remaining)
    while commodity_key do
        peel_full_loads(market, commodity_key, routes)
        commodity_key = next(market.remaining, commodity_key)
    end
    return trips.order(routes, market.depot_coords)
end

return bulk
