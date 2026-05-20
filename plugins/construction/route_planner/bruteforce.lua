local constants      = require("plugins.construction.route_constants")
local route_distance = require("plugins.construction.route_distance")
local trips_module   = require("plugins.construction.route_planner.trips")

local bruteforce = {}

local DEADLINE_CHECK_STRIDE = 1024

local fill_trip

local function resolve_clock()
    local love_ref

    love_ref = rawget(_G, "love")
    if love_ref and love_ref.timer and love_ref.timer.getTime then
        return love_ref.timer.getTime
    end
    return os.clock
end

local now_seconds = resolve_clock()

local function copy_map(map)
    local out

    out = {}
    for key, value in pairs(map) do
        out[key] = value
    end
    return out
end

local function jumps_for(from_coords, to_coords, jump_range)
    local distance

    distance = route_distance.between(from_coords, to_coords) or 0
    return route_distance.jumps_for_leg(distance, jump_range,
        constants.JUMPS_MIN_PER_LEG)
end

local function build_stock_table(index)
    local stock
    local offers

    stock = {}
    for key, station in pairs(index) do
        offers = {}
        for commodity_key, offer in pairs(station.offers) do
            offers[commodity_key] = offer.stock
        end
        stock[key] = offers
    end
    return stock
end

local function station_useful(station, remaining, station_stock)
    for commodity_key, qty in pairs(remaining) do
        if qty > 0 and (station_stock[commodity_key] or 0) > 0 then
            return true
        end
    end
    return false
end

local function any_useful_station(ctx)
    for _, station in ipairs(ctx.stations) do
        if station_useful(station, ctx.remaining, ctx.stock[station.key]) then
            return true
        end
    end
    return false
end

local function min_round_trip(stations, depot, ship)
    local best
    local out
    local back
    local round

    best = math.huge
    for _, station in ipairs(stations) do
        out = jumps_for(depot, station.coords, ship.jump_range_unloaded)
        back = jumps_for(station.coords, depot, ship.jump_range_loaded)
        round = out + back
        if round < best then
            best = round
        end
    end
    if best == math.huge then
        return 0
    end
    return best
end

local function station_cover_score(station, remaining, depot, ship)
    local cover
    local offer
    local round

    cover = 0
    for commodity_key, qty in pairs(remaining) do
        offer = station.offers[commodity_key]
        if offer and qty > 0 and offer.stock > 0 then
            cover = cover + 1
        end
    end
    round = jumps_for(depot, station.coords, ship.jump_range_unloaded)
        + jumps_for(station.coords, depot, ship.jump_range_loaded)
    return cover * constants.STATION_COVERAGE_WEIGHT - round
end

local function sorted_stations(index, remaining, depot, ship)
    local annotated
    local list

    annotated = {}
    for _, station in pairs(index) do
        table.insert(annotated, {
            station = station,
            score   = station_cover_score(station, remaining, depot, ship),
        })
    end
    table.sort(annotated, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.station.key < b.station.key
    end)
    list = {}
    for _, entry in ipairs(annotated) do
        table.insert(list, entry.station)
    end
    return list
end

local function demand_keys_by_price(station, remaining)
    local keys
    local offer

    keys = {}
    for commodity_key, qty in pairs(remaining) do
        offer = station.offers[commodity_key]
        if qty > 0 and offer and offer.stock > 0 then
            table.insert(keys, commodity_key)
        end
    end
    table.sort(keys, function(a, b)
        if station.offers[a].price ~= station.offers[b].price then
            return station.offers[a].price < station.offers[b].price
        end
        return a < b
    end)
    return keys
end

local function commit_pickups(ctx, station, station_stock, cargo_left)
    local pickups
    local taken
    local offer
    local wanted
    local stock_avail
    local take

    pickups = {}
    taken = 0
    for _, commodity_key in ipairs(demand_keys_by_price(station, ctx.remaining)) do
        if taken >= cargo_left then
            break
        end
        offer = station.offers[commodity_key]
        wanted = ctx.remaining[commodity_key] or 0
        stock_avail = station_stock[commodity_key] or 0
        take = math.min(wanted, stock_avail, cargo_left - taken)
        if take > 0 then
            table.insert(pickups, {
                commodity_key = commodity_key,
                display       = offer.display,
                quantity      = take,
                unit_price    = offer.price,
            })
            taken = taken + take
            ctx.remaining[commodity_key] = wanted - take
            station_stock[commodity_key] = stock_avail - take
        end
    end
    ctx.remaining_total = ctx.remaining_total - taken
    return pickups, taken
end

local function revert_pickups(ctx, pickups, station_stock)
    local total
    local commodity_key

    total = 0
    for _, pickup in ipairs(pickups) do
        commodity_key = pickup.commodity_key
        ctx.remaining[commodity_key] = (ctx.remaining[commodity_key] or 0)
            + pickup.quantity
        station_stock[commodity_key] = (station_stock[commodity_key] or 0)
            + pickup.quantity
        total = total + pickup.quantity
    end
    ctx.remaining_total = ctx.remaining_total + total
end

local function clone_stops(current_trip)
    local stops

    stops = {}
    for _, stop in ipairs(current_trip) do
        table.insert(stops, {
            kind    = stop.kind,
            station = stop.station,
            total   = stop.total,
            pickups = stop.pickups,
        })
    end
    return stops
end

local function clone_routes(routes)
    local out

    out = {}
    for _, trip in ipairs(routes) do
        table.insert(out, { stops = clone_stops(trip.stops) })
    end
    return out
end

local function is_better(stops_a, jumps_a, stops_b, jumps_b)
    if stops_a ~= stops_b then
        return stops_a < stops_b
    end
    return jumps_a < jumps_b
end

local function record_best(ctx, total_stops, total_jumps)
    if not is_better(total_stops, total_jumps,
            ctx.best.total_stops, ctx.best.total_jumps) then
        return
    end
    ctx.best.total_stops = total_stops
    ctx.best.total_jumps = total_jumps
    ctx.best.routes = clone_routes(ctx.accumulated_routes)
    ctx.best.remaining = copy_map(ctx.remaining)
end

local function remaining_min_stops(ctx)
    if ctx.remaining_total <= 0 then
        return 0
    end
    return math.ceil(ctx.remaining_total / ctx.cargo_cap)
end

local function lower_bound_jumps(ctx, trip_jumps, in_trip, cursor)
    local bound
    local trips_needed

    bound = ctx.accumulated_jumps + trip_jumps
    if in_trip then
        bound = bound + jumps_for(cursor, ctx.depot, ctx.ship.jump_range_loaded)
    end
    if ctx.remaining_total > 0 then
        trips_needed = math.ceil(ctx.remaining_total / ctx.cargo_cap)
        bound = bound + trips_needed * ctx.min_round_trip
    end
    return bound
end

local function should_prune(ctx, trip_jumps, in_trip, cursor)
    local lb_stops

    lb_stops = ctx.total_stops + remaining_min_stops(ctx)
    if lb_stops > ctx.best.total_stops then
        return true
    end
    if lb_stops < ctx.best.total_stops then
        return false
    end
    return lower_bound_jumps(ctx, trip_jumps, in_trip, cursor)
        >= ctx.best.total_jumps
end

local function finalise_with_open_trip(ctx, cursor, trip_jumps)
    local closed
    local appended

    closed = trip_jumps
    appended = false
    if #ctx.current_trip > 0 then
        closed = closed + jumps_for(cursor, ctx.depot, ctx.ship.jump_range_loaded)
        table.insert(ctx.accumulated_routes,
            { stops = clone_stops(ctx.current_trip) })
        appended = true
    end
    record_best(ctx, ctx.total_stops, ctx.accumulated_jumps + closed)
    if appended then
        table.remove(ctx.accumulated_routes)
    end
end

local function close_trip_and_recurse(ctx, cursor, trip_jumps)
    local return_jumps
    local saved_jumps
    local saved_trip

    return_jumps = jumps_for(cursor, ctx.depot, ctx.ship.jump_range_loaded)
    table.insert(ctx.accumulated_routes,
        { stops = clone_stops(ctx.current_trip) })
    saved_jumps = ctx.accumulated_jumps
    saved_trip  = ctx.current_trip
    ctx.accumulated_jumps = ctx.accumulated_jumps + trip_jumps + return_jumps
    ctx.current_trip = {}
    fill_trip(ctx, ctx.depot, ctx.cargo_cap, 0)
    ctx.current_trip = saved_trip
    ctx.accumulated_jumps = saved_jumps
    table.remove(ctx.accumulated_routes)
end

local function should_filter_station(ctx, station)
    if not ctx.root_filter then
        return false
    end
    if #ctx.accumulated_routes > 0 or #ctx.current_trip > 0 then
        return false
    end
    return ctx.root_filter[station.key] ~= true
end

local function attempt_visit(ctx, station, cursor, cargo_left, trip_jumps)
    local station_stock
    local jump_range
    local leg_jumps
    local pickups
    local taken

    station_stock = ctx.stock[station.key]
    jump_range = (#ctx.current_trip == 0)
        and ctx.ship.jump_range_unloaded
        or ctx.ship.jump_range_loaded
    leg_jumps = jumps_for(cursor, station.coords, jump_range)
    pickups, taken = commit_pickups(ctx, station, station_stock, cargo_left)
    if taken <= 0 then
        return
    end
    table.insert(ctx.current_trip, {
        kind    = constants.MULTI_STOP_KIND,
        station = station,
        total   = taken,
        pickups = pickups,
    })
    ctx.total_stops = ctx.total_stops + 1
    fill_trip(ctx, station.coords, cargo_left - taken, trip_jumps + leg_jumps)
    ctx.total_stops = ctx.total_stops - 1
    table.remove(ctx.current_trip)
    revert_pickups(ctx, pickups, station_stock)
end

local function try_visits(ctx, cursor, cargo_left, trip_jumps)
    local station_stock

    for _, station in ipairs(ctx.stations) do
        if not should_filter_station(ctx, station) then
            station_stock = ctx.stock[station.key]
            if station_useful(station, ctx.remaining, station_stock) then
                attempt_visit(ctx, station, cursor, cargo_left, trip_jumps)
            end
        end
    end
end

local function deadline_expired(ctx)
    if ctx.is_expired then
        return true
    end
    ctx.deadline_counter = ctx.deadline_counter + 1
    if ctx.deadline_counter < DEADLINE_CHECK_STRIDE then
        return false
    end
    ctx.deadline_counter = 0
    if now_seconds() <= ctx.deadline then
        return false
    end
    ctx.is_expired = true
    return true
end

fill_trip = function(ctx, cursor, cargo_left, trip_jumps)
    local in_trip

    if deadline_expired(ctx) then
        return
    end
    in_trip = #ctx.current_trip > 0
    if should_prune(ctx, trip_jumps, in_trip, cursor) then
        return
    end
    if ctx.remaining_total <= 0 or not any_useful_station(ctx) then
        return finalise_with_open_trip(ctx, cursor, trip_jumps)
    end
    if in_trip then
        close_trip_and_recurse(ctx, cursor, trip_jumps)
    end
    if cargo_left > 0 then
        try_visits(ctx, cursor, cargo_left, trip_jumps)
    end
end

local function compute_remaining_total(remaining)
    local total

    total = 0
    for _, qty in pairs(remaining) do
        total = total + qty
    end
    return total
end

local function build_root_filter(root_stations)
    local filter

    if not root_stations then
        return nil
    end
    filter = {}
    for _, key in ipairs(root_stations) do
        filter[key] = true
    end
    return filter
end

local function build_context(market, opts)
    local stations

    stations = sorted_stations(market.index, market.remaining,
        market.depot_coords, market.ship)
    return {
        ship               = market.ship,
        depot              = market.depot_coords,
        cargo_cap          = market.ship.cargo_capacity,
        stations           = stations,
        stock              = build_stock_table(market.index),
        remaining          = copy_map(market.remaining),
        remaining_total    = compute_remaining_total(market.remaining),
        min_round_trip     = min_round_trip(stations, market.depot_coords,
            market.ship),
        accumulated_routes = {},
        accumulated_jumps  = 0,
        current_trip       = {},
        total_stops        = 0,
        best               = { total_stops = math.huge,
            total_jumps = math.huge, routes = nil,
            remaining = copy_map(market.remaining) },
        root_filter        = build_root_filter(opts.root_stations),
        deadline           = opts.deadline or math.huge,
        deadline_counter   = 0,
        is_expired         = false,
    }
end

local function append_leftovers(remaining, unsatisfiable)
    for commodity_key, qty in pairs(remaining) do
        if qty > 0 then
            table.insert(unsatisfiable, commodity_key)
        end
    end
end

function bruteforce.find(market, opts)
    local ctx

    opts = opts or {}
    if not next(market.remaining) then
        return {}, 0, 0
    end
    ctx = build_context(market, opts)
    fill_trip(ctx, ctx.depot, ctx.cargo_cap, 0)
    append_leftovers(ctx.best.remaining or ctx.remaining, market.unsatisfiable)
    if ctx.best.total_stops == math.huge then
        return nil, math.huge, math.huge
    end
    return trips_module.order(ctx.best.routes, market.depot_coords),
        ctx.best.total_jumps, ctx.best.total_stops
end

return bruteforce
