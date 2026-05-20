local constants      = require("plugins.construction.route_constants")
local route_distance = require("plugins.construction.route_distance")

local market = {}

local function station_key_of(source)
    return (source.system_name or "?")
        .. constants.STATION_KEY_SEPARATOR
        .. (source.station_name or "?")
end

local function partition_orbital(sources)
    local orbital
    local surface
    local index
    local source

    orbital = {}
    surface = {}
    index = 1
    while sources[index] do
        source = sources[index]
        if source.is_orbital == false then
            table.insert(surface, source)
        else
            table.insert(orbital, source)
        end
        index = index + 1
    end
    return orbital, surface
end

local function prefer_orbital(sources)
    local orbital
    local surface

    orbital, surface = partition_orbital(sources)
    if #orbital > 0 then return orbital end
    return surface
end

local function sources_in_range(sources, depot_coords, max_distance_ly)
    local kept
    local index
    local source
    local distance
    local limit

    limit = max_distance_ly or constants.MAX_SOURCE_DISTANCE_LY
    kept = {}
    index = 1
    while sources[index] do
        source = sources[index]
        distance = route_distance.between(source.coords, depot_coords)
        if distance and distance <= limit then
            table.insert(kept, source)
        end
        index = index + 1
    end
    return kept
end

local function filter_in_range(sources_by_key, depot_coords, max_distance_ly)
    local result
    local commodity_key

    result = {}
    commodity_key = next(sources_by_key)
    while commodity_key do
        result[commodity_key] = sources_in_range(sources_by_key[commodity_key],
            depot_coords, max_distance_ly)
        commodity_key = next(sources_by_key, commodity_key)
    end
    return result
end

local function select_sources(sources_by_key, demand)
    local filtered
    local unsatisfiable
    local commodity_key
    local chosen

    filtered = {}
    unsatisfiable = {}
    commodity_key = next(demand)
    while commodity_key do
        chosen = prefer_orbital(sources_by_key[commodity_key] or {})
        if #chosen > 0 then
            filtered[commodity_key] = chosen
        else
            table.insert(unsatisfiable, commodity_key)
        end
        commodity_key = next(demand, commodity_key)
    end
    return filtered, unsatisfiable
end

local function ensure_station(index, source)
    local key

    key = station_key_of(source)
    if not index[key] then
        index[key] = {
            key                    = key,
            station_name           = source.station_name,
            system_name            = source.system_name,
            coords                 = source.coords,
            distance_to_arrival_ls = source.distance_to_arrival_ls,
            is_orbital             = source.is_orbital ~= false,
            offers                 = {},
        }
    end
    return index[key]
end

local function record_offer(station, commodity_key, source, display)
    local existing

    existing = station.offers[commodity_key]
    if existing and existing.price <= (source.price or 0) then return end
    station.offers[commodity_key] = {
        price   = source.price or 0,
        stock   = source.stock or 0,
        display = display,
    }
end

local function index_commodity_sources(index, commodity_key, sources, display)
    local position
    local station

    position = 1
    while sources[position] do
        station = ensure_station(index, sources[position])
        record_offer(station, commodity_key, sources[position], display)
        position = position + 1
    end
end

local function build_station_index(filtered, displays)
    local index
    local commodity_key

    index = {}
    commodity_key = next(filtered)
    while commodity_key do
        index_commodity_sources(index, commodity_key,
            filtered[commodity_key], displays[commodity_key] or commodity_key)
        commodity_key = next(filtered, commodity_key)
    end
    return index
end

local function copy_demand(demand, filtered)
    local remaining
    local commodity_key

    remaining = {}
    commodity_key = next(demand)
    while commodity_key do
        if filtered[commodity_key] then
            remaining[commodity_key] = demand[commodity_key]
        end
        commodity_key = next(demand, commodity_key)
    end
    return remaining
end

function market.survey(plan_input)
    local in_range
    local sources
    local unsatisfiable

    in_range = filter_in_range(plan_input.sources_by_key,
        plan_input.depot_coords, plan_input.max_distance_ly)
    sources, unsatisfiable = select_sources(in_range, plan_input.demand)
    return {
        ship          = plan_input.ship,
        depot_coords  = plan_input.depot_coords,
        origin_coords = plan_input.origin_coords or plan_input.depot_coords,
        index         = build_station_index(sources, plan_input.displays or {}),
        remaining     = copy_demand(plan_input.demand, sources),
        unsatisfiable = unsatisfiable,
    }
end

return market
