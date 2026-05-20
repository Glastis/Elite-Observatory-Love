local constants  = require("plugins.construction.route_constants")
local bruteforce = require("plugins.construction.route_planner.bruteforce")

local bruteforce_pool = {}

local JOB_CHANNEL_PREFIX    = "construction.bruteforce.jobs."
local RESULT_CHANNEL_PREFIX = "construction.bruteforce.results."
local SHUTDOWN_SENTINEL     = "__construction_bruteforce_shutdown__"
local WORKER_SCRIPT_PATH    = "plugins/construction/route_planner/bruteforce_worker.lua"
local MIN_WORKER_COUNT      = 1
local DEFAULT_PROCESSOR_COUNT = 1

local function has_threads()
    return love ~= nil and love.thread ~= nil
end

local function resolve_clock()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime
    end
    return os.clock
end

local now_seconds = resolve_clock()

local function probe_processor_count()
    if love and love.system and love.system.getProcessorCount then
        return love.system.getProcessorCount() or DEFAULT_PROCESSOR_COUNT
    end
    return DEFAULT_PROCESSOR_COUNT
end

local function resolve_worker_count()
    local available

    available = probe_processor_count()
    return math.max(MIN_WORKER_COUNT,
        math.min(constants.AGGRESSIVE_WORKER_COUNT, available))
end

local pool = {
    is_started      = false,
    workers         = {},
    job_channels    = {},
    result_channels = {},
    worker_count    = 0,
}

local active_handles = {}
local batch_counter = 0

local function spawn_workers(count)
    local job_name
    local result_name
    local thread

    for index = 1, count do
        job_name    = JOB_CHANNEL_PREFIX .. index
        result_name = RESULT_CHANNEL_PREFIX .. index
        thread = love.thread.newThread(WORKER_SCRIPT_PATH)
        thread:start(job_name, result_name, SHUTDOWN_SENTINEL)
        pool.workers[index]         = thread
        pool.job_channels[index]    = love.thread.getChannel(job_name)
        pool.result_channels[index] = love.thread.getChannel(result_name)
    end
end

local function ensure_pool_started()
    if pool.is_started or not has_threads() then
        return pool.is_started
    end
    pool.worker_count = resolve_worker_count()
    spawn_workers(pool.worker_count)
    pool.is_started = true
    return true
end

local function copy_offers(offers)
    local out

    out = {}
    for commodity_key, offer in pairs(offers) do
        out[commodity_key] = {
            price   = offer.price,
            stock   = offer.stock,
            display = offer.display,
        }
    end
    return out
end

local function copy_coords(coords)
    return { x = coords.x, y = coords.y, z = coords.z }
end

local function copy_station(station)
    return {
        key                    = station.key,
        station_name           = station.station_name,
        system_name            = station.system_name,
        coords                 = copy_coords(station.coords),
        distance_to_arrival_ls = station.distance_to_arrival_ls,
        is_orbital             = station.is_orbital,
        offers                 = copy_offers(station.offers),
    }
end

local function copy_map(map)
    local out

    out = {}
    for k, v in pairs(map) do
        out[k] = v
    end
    return out
end

local function copy_station_index(index)
    local out

    out = {}
    for key, station in pairs(index) do
        out[key] = copy_station(station)
    end
    return out
end

local function serialise_market(market)
    return {
        ship          = copy_map(market.ship),
        depot_coords  = copy_coords(market.depot_coords),
        index         = copy_station_index(market.index),
        remaining     = copy_map(market.remaining),
        unsatisfiable = {},
    }
end

local function station_has_useful_offer(station, remaining)
    local offer

    for commodity_key, qty in pairs(remaining) do
        offer = station.offers[commodity_key]
        if qty > 0 and offer and offer.stock > 0 then
            return true
        end
    end
    return false
end

local function partition_roots(market, worker_count)
    local roots
    local buckets
    local bucket

    roots = {}
    for key, station in pairs(market.index) do
        if station_has_useful_offer(station, market.remaining) then
            table.insert(roots, key)
        end
    end
    table.sort(roots)
    buckets = {}
    for index = 1, worker_count do
        buckets[index] = {}
    end
    for index, key in ipairs(roots) do
        bucket = ((index - 1) % worker_count) + 1
        table.insert(buckets[bucket], key)
    end
    return buckets
end

local function dispatch_jobs(handle)
    local buckets

    buckets = partition_roots(handle.market, pool.worker_count)
    for index = 1, pool.worker_count do
        pool.job_channels[index]:push({
            batch_id      = handle.batch_id,
            market        = handle.market,
            root_stations = buckets[index],
            time_budget   = constants.AGGRESSIVE_TIME_BUDGET_S,
        })
        handle.pending_workers = handle.pending_workers + 1
    end
end

local function worker_error()
    local message

    for index = 1, pool.worker_count do
        message = pool.workers[index]:getError()
        if message then
            return message
        end
    end
    return nil
end

local function deliver_result(result)
    local owner

    owner = active_handles[result.batch_id]
    if not owner then
        return
    end
    owner.pending_workers = owner.pending_workers - 1
    table.insert(owner.results, result)
end

local function drain_results()
    local result

    for index = 1, pool.worker_count do
        result = pool.result_channels[index]:pop()
        while result do
            deliver_result(result)
            result = pool.result_channels[index]:pop()
        end
    end
end

local function is_usable_result(result)
    if result.routes == nil then
        return false
    end
    return (result.total_stops or math.huge) < math.huge
end

local function is_better(stops_a, jumps_a, stops_b, jumps_b)
    if stops_a ~= stops_b then
        return stops_a < stops_b
    end
    return jumps_a < jumps_b
end

local function pick_best_result(results)
    local best

    for _, result in ipairs(results) do
        if is_usable_result(result) and (not best or is_better(
                result.total_stops, result.total_jumps,
                best.total_stops, best.total_jumps)) then
            best = result
        end
    end
    return best
end

local function routes_of(result)
    if not result then
        return {}, {}
    end
    return result.routes or {}, result.unsatisfiable or {}
end

local function sync_step(handle)
    local routes

    routes = bruteforce.find(handle.market, {
        root_stations = nil,
        deadline      = now_seconds() + constants.AGGRESSIVE_TIME_BUDGET_S,
    })
    handle.is_done = true
    return true, routes or {}, handle.market.unsatisfiable or {}
end

local function fall_back_to_sync(handle, reason)
    handle.is_threaded = false
    handle.fallback_reason = reason
    active_handles[handle.batch_id] = nil
    return sync_step(handle)
end

local function finish_handle(handle)
    local routes
    local leftovers

    active_handles[handle.batch_id] = nil
    handle.is_done = true
    routes, leftovers = routes_of(pick_best_result(handle.results))
    return true, routes, leftovers
end

function bruteforce_pool.start(market)
    local handle

    batch_counter = batch_counter + 1
    handle = {
        batch_id        = batch_counter,
        market          = serialise_market(market),
        results         = {},
        pending_workers = 0,
        is_threaded     = ensure_pool_started(),
        is_done         = false,
    }
    if handle.is_threaded then
        active_handles[handle.batch_id] = handle
        dispatch_jobs(handle)
    end
    return handle
end

function bruteforce_pool.step(handle)
    local routes
    local leftovers
    local crash

    if handle.is_done then
        routes, leftovers = routes_of(pick_best_result(handle.results))
        return true, routes, leftovers
    end
    if not handle.is_threaded then
        return sync_step(handle)
    end
    crash = worker_error()
    if crash then
        return fall_back_to_sync(handle, crash)
    end
    drain_results()
    if handle.pending_workers <= 0 then
        return finish_handle(handle)
    end
    return false, nil
end

function bruteforce_pool.cancel(handle)
    handle.is_done = true
    active_handles[handle.batch_id] = nil
end

function bruteforce_pool.shutdown()
    if not pool.is_started then
        return
    end
    for index = 1, pool.worker_count do
        pool.job_channels[index]:push(SHUTDOWN_SENTINEL)
    end
    pool.is_started = false
    pool.workers = {}
    pool.job_channels = {}
    pool.result_channels = {}
    pool.worker_count = 0
    active_handles = {}
end

return bruteforce_pool
