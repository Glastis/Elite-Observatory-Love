local constants  = require("plugins.construction.route_constants")
local bruteforce = require("plugins.construction.route_planner.bruteforce")

local bruteforce_pool = {}

local JOB_CHANNEL_PREFIX    = "construction.bruteforce.jobs."
local RESULT_CHANNEL_PREFIX = "construction.bruteforce.results."
local SHUTDOWN_SENTINEL     = "__construction_bruteforce_shutdown__"
local WORKER_SCRIPT_PATH    = "plugins/construction/route_planner/bruteforce_worker.lua"

local function has_threads()
    return love ~= nil and love.thread ~= nil
end

local function probe_processor_count()
    if love and love.system and love.system.getProcessorCount then
        return love.system.getProcessorCount() or 1
    end
    return 1
end

local function resolve_worker_count()
    local available = probe_processor_count()
    return math.max(1, math.min(constants.AGGRESSIVE_WORKER_COUNT, available))
end

local pool = {
    is_started      = false,
    workers         = {},
    job_channels    = {},
    result_channels = {},
    worker_count    = 0,
}

local batch_counter = 0

local function spawn_workers(count)
    for index = 1, count do
        local job_name    = JOB_CHANNEL_PREFIX .. index
        local result_name = RESULT_CHANNEL_PREFIX .. index
        local thread = love.thread.newThread(WORKER_SCRIPT_PATH)
        thread:start(job_name, result_name, SHUTDOWN_SENTINEL)
        pool.workers[index]         = thread
        pool.job_channels[index]    = love.thread.getChannel(job_name)
        pool.result_channels[index] = love.thread.getChannel(result_name)
    end
end

local function ensure_pool_started()
    if pool.is_started or not has_threads() then return pool.is_started end
    pool.worker_count = resolve_worker_count()
    spawn_workers(pool.worker_count)
    pool.is_started = true
    return true
end

local function clear_channels(count)
    for index = 1, count do
        pool.job_channels[index]:clear()
        pool.result_channels[index]:clear()
    end
end

local function copy_offers(offers)
    local out = {}
    for commodity_key, offer in pairs(offers) do
        out[commodity_key] = {
            price   = offer.price,
            stock   = offer.stock,
            display = offer.display,
        }
    end
    return out
end

local function copy_station(station)
    return {
        key                    = station.key,
        station_name           = station.station_name,
        system_name            = station.system_name,
        coords                 = { x = station.coords.x,
                                   y = station.coords.y,
                                   z = station.coords.z },
        distance_to_arrival_ls = station.distance_to_arrival_ls,
        is_orbital             = station.is_orbital,
        offers                 = copy_offers(station.offers),
    }
end

local function copy_map(map)
    local out = {}
    for k, v in pairs(map) do out[k] = v end
    return out
end

local function serialise_market(market)
    local index = {}
    for key, station in pairs(market.index) do
        index[key] = copy_station(station)
    end
    return {
        ship          = copy_map(market.ship),
        depot_coords  = { x = market.depot_coords.x,
                          y = market.depot_coords.y,
                          z = market.depot_coords.z },
        index         = index,
        remaining     = copy_map(market.remaining),
        unsatisfiable = {},
    }
end

local function partition_roots(market, worker_count)
    local roots = {}
    for key, station in pairs(market.index) do
        for commodity_key, qty in pairs(market.remaining) do
            local offer = station.offers[commodity_key]
            if qty > 0 and offer and offer.stock > 0 then
                table.insert(roots, key)
                break
            end
        end
    end
    table.sort(roots)
    local buckets = {}
    for index = 1, worker_count do buckets[index] = {} end
    for index, key in ipairs(roots) do
        local bucket = ((index - 1) % worker_count) + 1
        table.insert(buckets[bucket], key)
    end
    return buckets
end

local function dispatch_jobs(handle)
    local buckets = partition_roots(handle.market, pool.worker_count)
    for index = 1, pool.worker_count do
        pool.job_channels[index]:push({
            batch_id      = handle.batch_id,
            market        = handle.market,
            root_stations = buckets[index],
        })
        handle.pending_workers = handle.pending_workers + 1
    end
end

local function worker_error()
    for index = 1, pool.worker_count do
        local message = pool.workers[index]:getError()
        if message then return message end
    end
    return nil
end

local function harvest_threaded(handle)
    for index = 1, pool.worker_count do
        local result = pool.result_channels[index]:pop()
        while result do
            if result.batch_id == handle.batch_id then
                handle.pending_workers = handle.pending_workers - 1
                table.insert(handle.results, result)
            end
            result = pool.result_channels[index]:pop()
        end
    end
end

local function is_usable_result(result)
    if result.routes == nil then return false end
    return (result.total_stops or math.huge) < math.huge
end

local function is_better(stops_a, jumps_a, stops_b, jumps_b)
    if stops_a ~= stops_b then return stops_a < stops_b end
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
    if not result then return {}, {} end
    return result.routes or {}, result.unsatisfiable or {}
end

local function sync_step(handle)
    local routes = bruteforce.find(handle.market, { root_stations = nil })
    handle.is_done = true
    return true, routes or {}, handle.market.unsatisfiable or {}
end

local function fall_back_to_sync(handle, reason)
    handle.is_threaded = false
    handle.fallback_reason = reason
    return sync_step(handle)
end

function bruteforce_pool.start(market)
    batch_counter = batch_counter + 1
    local handle = {
        batch_id        = batch_counter,
        market          = serialise_market(market),
        results         = {},
        pending_workers = 0,
        is_threaded     = ensure_pool_started(),
        is_done         = false,
    }
    if handle.is_threaded then
        clear_channels(pool.worker_count)
        dispatch_jobs(handle)
    end
    return handle
end

function bruteforce_pool.step(handle)
    if handle.is_done then
        local routes, leftovers = routes_of(pick_best_result(handle.results))
        return true, routes, leftovers
    end
    if not handle.is_threaded then return sync_step(handle) end
    local crash = worker_error()
    if crash then return fall_back_to_sync(handle, crash) end
    harvest_threaded(handle)
    if handle.pending_workers <= 0 then
        handle.is_done = true
        local routes, leftovers = routes_of(pick_best_result(handle.results))
        return true, routes, leftovers
    end
    return false, nil
end

function bruteforce_pool.cancel(handle)
    handle.is_done = true
    if not handle.is_threaded then return end
    for index = 1, pool.worker_count do
        pool.job_channels[index]:clear()
        pool.result_channels[index]:clear()
    end
end

function bruteforce_pool.shutdown()
    if not pool.is_started then return end
    for index = 1, pool.worker_count do
        pool.job_channels[index]:push(SHUTDOWN_SENTINEL)
    end
    pool.is_started = false
    pool.workers = {}
    pool.job_channels = {}
    pool.result_channels = {}
    pool.worker_count = 0
end

return bruteforce_pool
