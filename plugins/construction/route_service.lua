local constants       = require("plugins.construction.route_constants")
local state           = require("plugins.construction.state")
local amounts         = require("plugins.construction.amounts")
local route_state     = require("plugins.construction.route_state")
local route_api       = require("plugins.construction.route_api")
local route_cache     = require("plugins.construction.route_cache")
local route_planner   = require("plugins.construction.route_planner")
local route_consumption = require("plugins.construction.route_consumption")
local route_debug     = require("plugins.construction.route_debug")
local commodity_names = require("plugins.construction.commodity_names")

local route_service = {}

local core_ref
local ship_params = {}
local delivered_baseline = {}
local aggressive_fetches = {}

local function numeric_ship()
    local cargo = tonumber(ship_params.cargo_capacity)
    local loaded = tonumber(ship_params.jump_loaded)
    local unloaded = tonumber(ship_params.jump_unloaded)
    if not (cargo and loaded and unloaded) then return nil end
    if cargo < 1 or loaded <= 0 or unloaded <= 0 then return nil end
    return {
        cargo_capacity      = math.floor(cargo),
        jump_range_loaded   = loaded,
        jump_range_unloaded = unloaded,
    }
end

local function build_demand(site)
    local demand, displays = {}, {}
    for _, entry in ipairs(amounts.unfinished(site)) do
        if entry.to_buy > 0 then
            demand[entry.resource.key] = entry.to_buy
            displays[entry.resource.key] = entry.resource.display
        end
    end
    return demand, displays
end

local function provided_by_key(site)
    local map = {}
    local resources = (site and site.resources) or {}
    local index = 1
    while resources[index] do
        map[resources[index].key] = resources[index].provided or 0
        index = index + 1
    end
    return map
end

local function provided_delta(baseline, current)
    local delta = {}
    local key = next(current)
    while key do
        local gained = current[key] - (baseline[key] or 0)
        if gained > 0 then delta[key] = gained end
        key = next(current, key)
    end
    return delta
end

local function ready_empty_route(ship)
    return {
        status        = constants.STATUS_READY,
        stops         = {},
        total_stops   = 0,
        total_jumps   = 0,
        unsatisfiable = {},
        ship_snapshot = ship,
        computed_at   = os.time(),
    }
end

local function ship_matches(a, b)
    return a and b
        and a.cargo_capacity == b.cargo_capacity
        and a.jump_range_loaded == b.jump_range_loaded
        and a.jump_range_unloaded == b.jump_range_unloaded
end

local function is_route_current(market_id, ship)
    local route = route_state.get(market_id)
    return route ~= nil and route.status == constants.STATUS_READY
        and ship_matches(route.ship_snapshot, ship)
end

local function current_origin_coords()
    local current = state.current_system()
    return current and current.coords
end

local function plan_input_for(fetch)
    return {
        demand         = fetch.demand,
        displays       = fetch.displays,
        sources_by_key = fetch.sources_by_key,
        depot_coords   = fetch.depot_coords,
        origin_coords  = current_origin_coords(),
        ship           = fetch.ship,
    }
end

local function finalise_route(fetch, route, site)
    route.ship_snapshot = fetch.ship
    route.computed_at = os.time()
    route.depot_system = site.system_name
    route_state.set(fetch.market_id, route)
    delivered_baseline[fetch.market_id] = provided_by_key(site)
end

local function finalise_normal(fetch, site)
    route_state.clear_in_flight(fetch.market_id)
    finalise_route(fetch, route_planner.compute(plan_input_for(fetch)), site)
end

local function begin_aggressive(fetch)
    fetch.bruteforce_handle = route_planner.start_aggressive(
        plan_input_for(fetch))
    aggressive_fetches[fetch.market_id] = fetch
end

local function finish_fetch(fetch)
    if fetch.is_cancelled then return end
    local site = state.get_site(fetch.market_id)
    if not site then
        route_state.clear_in_flight(fetch.market_id)
        return route_state.remove(fetch.market_id)
    end
    route_debug.record_sources(fetch.market_id, fetch.system_name,
        fetch.depot_coords, fetch.sources_by_key, fetch.displays)
    if fetch.success_count <= 0 then
        route_state.clear_in_flight(fetch.market_id)
        return route_state.set_status(fetch.market_id, constants.STATUS_ERROR)
    end
    if fetch.is_aggressive then return begin_aggressive(fetch) end
    finalise_normal(fetch, site)
end

local function finalise_aggressive(fetch, route)
    aggressive_fetches[fetch.market_id] = nil
    route_state.clear_in_flight(fetch.market_id)
    local site = state.get_site(fetch.market_id)
    if not site then return route_state.remove(fetch.market_id) end
    finalise_route(fetch, route, site)
end

local function poll_aggressive_fetches()
    for market_id, fetch in pairs(aggressive_fetches) do
        if not fetch.is_cancelled then
            local is_done, route = route_planner.step_aggressive(
                fetch.bruteforce_handle)
            if is_done then finalise_aggressive(fetch, route) end
        end
    end
end

local function decrement_and_maybe_finish(fetch)
    fetch.pending = fetch.pending - 1
    if fetch.pending <= 0 then finish_fetch(fetch) end
end

local function count_keys(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    return count
end

local function track_request(fetch, request_id)
    if request_id then table.insert(fetch.request_ids, request_id) end
end

local function issue_exports(fetch)
    for commodity_key in pairs(fetch.demand) do
        local api_name = commodity_names.to_api_name(commodity_key)
        local request_id = route_api.fetch_exports(core_ref, fetch.system_name,
            api_name, constants.EXPORTS_MIN_VOLUME,
            function(is_ok, sources)
                if fetch.is_cancelled then return end
                if is_ok then fetch.success_count = fetch.success_count + 1 end
                fetch.sources_by_key[commodity_key] = is_ok and sources or {}
                decrement_and_maybe_finish(fetch)
            end)
        track_request(fetch, request_id)
    end
end

local function start_fetch(market_id, system_name, ship, depot_coords,
        demand, displays, is_aggressive)
    local fetch = {
        market_id      = market_id,
        system_name    = system_name,
        ship           = ship,
        depot_coords   = depot_coords,
        demand         = demand,
        displays       = displays,
        pending        = count_keys(demand),
        success_count  = 0,
        sources_by_key = {},
        request_ids    = {},
        is_cancelled   = false,
        is_aggressive  = is_aggressive == true,
    }
    route_state.mark_in_flight(market_id, fetch)
    route_state.set_status(market_id, constants.STATUS_PENDING)
    issue_exports(fetch)
end

local function cancel_in_flight(market_id)
    local fetch = route_state.in_flight_handle(market_id)
    if not fetch then return end
    fetch.is_cancelled = true
    if fetch.bruteforce_handle then
        route_planner.cancel_aggressive(fetch.bruteforce_handle)
    end
    if core_ref then
        for _, request_id in ipairs(fetch.request_ids or {}) do
            core_ref:http_cancel(request_id)
        end
    end
    aggressive_fetches[market_id] = nil
    route_state.clear_in_flight(market_id)
end

function route_service.init(core)
    core_ref = core
    route_cache.init()
    route_debug.set_enabled(core:is_debug())
end

function route_service.update(dt)
    route_cache.update(dt)
    route_debug.update(dt)
    poll_aggressive_fetches()
end

function route_service.set_ship_params(params)
    ship_params = params or {}
end

function route_service.compute_for_site(market_id, is_forced, is_aggressive)
    if not core_ref then return end
    if core_ref.refresh_ancillary_state then
        core_ref:refresh_ancillary_state()
    end
    local site = state.get_site(market_id)
    if not site or not site.system_name then return end
    if route_state.in_flight_handle(market_id) then
        if not is_forced then return end
        cancel_in_flight(market_id)
    end
    local ship = numeric_ship()
    if not ship then
        return route_state.set_status(market_id, constants.STATUS_NO_SHIP_PARAMS)
    end
    local depot_coords = site.system_coords
        or state.coords_for_system(site.system_name)
    if not depot_coords then
        return route_state.set_status(market_id, constants.STATUS_NO_COORDS)
    end
    if not is_forced and is_route_current(market_id, ship) then return end
    local demand, displays = build_demand(site)
    if not next(demand) then
        route_state.set(market_id, ready_empty_route(ship))
        delivered_baseline[market_id] = provided_by_key(site)
        return
    end
    start_fetch(market_id, site.system_name, ship, depot_coords, demand,
        displays, is_aggressive)
end

function route_service.compute_all(is_forced)
    for _, entry in ipairs(state.sites_sorted()) do
        if not entry.is_hidden then
            route_service.compute_for_site(entry.market_id, is_forced)
        end
    end
end

function route_service.on_site_added(market_id)
    if core_ref and core_ref:is_log_monitor_batch_reading() then return end
    route_service.compute_for_site(market_id, false)
end

function route_service.on_site_removed(market_id)
    cancel_in_flight(market_id)
    route_state.remove(market_id)
    route_debug.forget(market_id)
    delivered_baseline[market_id] = nil
end

function route_service.on_site_updated(market_id)
    local route = route_state.get(market_id)
    if not route or route.status ~= constants.STATUS_READY then return end
    local baseline = delivered_baseline[market_id]
    if not baseline then return end
    local site = state.get_site(market_id)
    if not site then return end
    local current = provided_by_key(site)
    local delta = provided_delta(baseline, current)
    delivered_baseline[market_id] = current
    if next(delta) then
        route_consumption.apply(route, delta)
    end
    route_service.compute_for_site(market_id, true)
end

function route_service.on_monitor_state_changed()
    if core_ref and core_ref:is_log_monitor_batch_reading() then return end
    route_service.compute_all(false)
end

function route_service.observatory_ready()
    route_service.compute_all(false)
end

return route_service
