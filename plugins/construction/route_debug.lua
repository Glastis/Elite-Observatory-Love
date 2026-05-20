local json            = require("lib.json")
local route_constants = require("plugins.construction.route_constants")
local state           = require("plugins.construction.state")
local route_state     = require("plugins.construction.route_state")
local amounts         = require("plugins.construction.amounts")
local route_distance  = require("plugins.construction.route_distance")

local route_debug = {}

local STATIONS_FILE      = "construction_debug_stations.json"
local ROUTES_FILE        = "construction_debug_routes.json"
local CONSTRUCTIONS_FILE = "construction_debug_constructions.json"
local DUMP_INTERVAL_S    = 5
local UNKNOWN_GLYPH      = "?"
local PATH_SEPARATOR     = "/"
local ANNOUNCE_PREFIX    = "construction debug logs -> "
local CWD_PATH           = "."

local is_enabled = false
local fetched_by_market = {}
local seconds_since_dump = DUMP_INTERVAL_S
local has_announced_path = false

local function output_dir()
    if love and love.filesystem and love.filesystem.getSource then
        return love.filesystem.getSource()
    end
    return CWD_PATH
end

local function write_json(file_name, payload)
    local ok
    local encoded
    local handle

    ok, encoded = pcall(json.encode, payload)
    if not ok then
        return
    end
    handle = io.open(output_dir() .. PATH_SEPARATOR .. file_name, "w")
    if not handle then
        return
    end
    handle:write(encoded)
    handle:close()
end

local function values_of(map)
    local list
    local key

    list = {}
    key = next(map)
    while key do
        table.insert(list, map[key])
        key = next(map, key)
    end
    return list
end

local function build_list(records, builder)
    local list
    local index
    local entry

    list = {}
    index = 1
    while records[index] do
        entry = builder(records[index])
        if entry then
            table.insert(list, entry)
        end
        index = index + 1
    end
    return list
end

local function resource_row(resource)
    local needed
    local in_cargo
    local to_buy

    needed, in_cargo, to_buy = amounts.for_resource(resource)
    return {
        key      = resource.key,
        display  = resource.display,
        required = resource.required or 0,
        provided = resource.provided or 0,
        needed   = needed,
        in_cargo = in_cargo,
        to_buy   = to_buy,
    }
end

local function resource_rows(site)
    local rows
    local resources
    local index

    rows = {}
    resources = (site and site.resources) or {}
    index = 1
    while resources[index] do
        table.insert(rows, resource_row(resources[index]))
        index = index + 1
    end
    return rows
end

local function construction_entry(record)
    local site
    local needed
    local in_cargo
    local to_buy

    site = record.site
    needed, in_cargo, to_buy = amounts.site_totals(site)
    return {
        market_id = record.market_id,
        label     = site.label,
        system    = site.system_name,
        is_hidden = record.is_hidden,
        progress  = site.progress,
        totals    = { needed = needed, in_cargo = in_cargo, to_buy = to_buy },
        resources = resource_rows(site),
    }
end

local function stop_row(stop)
    return {
        system                 = stop.system,
        station                = stop.station,
        distance_ly            = stop.distance_ly,
        distance_to_arrival_ls = stop.distance_to_arrival_ls,
        jumps                  = stop.jumps,
        pickups                = stop.pickups,
    }
end

local function stop_rows(route)
    local rows
    local stops
    local index

    rows = {}
    stops = route.stops or {}
    index = 1
    while stops[index] do
        table.insert(rows, stop_row(stops[index]))
        index = index + 1
    end
    return rows
end

local function route_entry(record)
    local route

    route = route_state.get(record.market_id)
    if not route then
        return nil
    end
    return {
        market_id     = record.market_id,
        label         = record.site.label,
        system        = record.site.system_name,
        depot_system  = route.depot_system,
        status        = route.status,
        total_stops   = route.total_stops or 0,
        total_jumps   = route.total_jumps or 0,
        computed_at   = route.computed_at,
        ship          = route.ship_snapshot,
        unsatisfiable = route.unsatisfiable or {},
        stops         = stop_rows(route),
    }
end

local function station_record(grouped, source, depot_coords)
    local key
    local entry

    key = (source.system_name or UNKNOWN_GLYPH)
        .. route_constants.STATION_KEY_SEPARATOR
        .. (source.station_name or UNKNOWN_GLYPH)
    entry = grouped[key]
    if entry then
        return entry
    end
    entry = {
        station                = source.station_name,
        system                 = source.system_name,
        station_type           = source.station_type,
        is_orbital             = source.is_orbital,
        distance_to_arrival_ls = source.distance_to_arrival_ls,
        distance_ly            = route_distance.between(source.coords,
            depot_coords),
        coords                 = source.coords,
        goods                  = {},
    }
    grouped[key] = entry
    return entry
end

local function good_row(commodity_key, source, displays)
    return {
        commodity = commodity_key,
        display   = displays[commodity_key] or commodity_key,
        stock     = source.stock or 0,
        price     = source.price or 0,
    }
end

local function collect_commodity(grouped, commodity_key, sources, fetched)
    local index
    local source
    local entry

    index = 1
    while sources[index] do
        source = sources[index]
        entry = station_record(grouped, source, fetched.depot_coords)
        table.insert(entry.goods,
            good_row(commodity_key, source, fetched.displays))
        index = index + 1
    end
end

local function stations_of(fetched)
    local grouped
    local commodity_key

    grouped = {}
    commodity_key = next(fetched.sources_by_key)
    while commodity_key do
        collect_commodity(grouped, commodity_key,
            fetched.sources_by_key[commodity_key], fetched)
        commodity_key = next(fetched.sources_by_key, commodity_key)
    end
    return values_of(grouped)
end

local function station_site_entry(record)
    local fetched

    fetched = fetched_by_market[record.market_id]
    if not fetched then
        return nil
    end
    return {
        market_id = record.market_id,
        label     = record.site.label,
        system    = fetched.system_name,
        stations  = stations_of(fetched),
    }
end

local function announce_path()
    if has_announced_path then
        return
    end
    has_announced_path = true
    print(ANNOUNCE_PREFIX .. output_dir())
end

local function dump()
    local records
    local generated_at

    records = state.sites_sorted()
    generated_at = os.date()
    write_json(STATIONS_FILE, {
        generated_at = generated_at,
        sites        = build_list(records, station_site_entry),
    })
    write_json(ROUTES_FILE, {
        generated_at = generated_at,
        routes       = build_list(records, route_entry),
    })
    write_json(CONSTRUCTIONS_FILE, {
        generated_at  = generated_at,
        constructions = build_list(records, construction_entry),
    })
end

function route_debug.set_enabled(value)
    is_enabled = value and true or false
end

function route_debug.record_sources(market_id, system_name, depot_coords,
        sources_by_key, displays)
    if not is_enabled or not market_id then
        return
    end
    fetched_by_market[market_id] = {
        system_name    = system_name,
        depot_coords   = depot_coords,
        sources_by_key = sources_by_key or {},
        displays       = displays or {},
    }
end

function route_debug.forget(market_id)
    if market_id then
        fetched_by_market[market_id] = nil
    end
end

function route_debug.update(dt)
    if not is_enabled then
        return
    end
    seconds_since_dump = seconds_since_dump + (dt or 0)
    if seconds_since_dump < DUMP_INTERVAL_S then
        return
    end
    seconds_since_dump = 0
    announce_path()
    dump()
end

function route_debug.reset()
    fetched_by_market = {}
    seconds_since_dump = DUMP_INTERVAL_S
    has_announced_path = false
end

return route_debug
