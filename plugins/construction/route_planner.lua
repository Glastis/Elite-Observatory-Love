local market          = require("plugins.construction.route_planner.market")
local bulk             = require("plugins.construction.route_planner.bulk")
local refined          = require("plugins.construction.route_planner.refined")
local assembly         = require("plugins.construction.route_planner.assembly")
local trips            = require("plugins.construction.route_planner.trips")
local bruteforce_pool  = require("plugins.construction.route_planner.bruteforce_pool")

local route_planner = {}

function route_planner.compute(plan_input)
    local surveyed = market.survey(plan_input)
    local routes = {}
    trips.add_all(routes, bulk.find(surveyed))
    trips.add_all(routes, refined.find(surveyed))
    return assembly.assemble(routes, surveyed)
end

function route_planner.start_aggressive(plan_input)
    local surveyed = market.survey(plan_input)
    local bulk_routes = bulk.find(surveyed)
    return {
        surveyed    = surveyed,
        bulk_routes = bulk_routes,
        pool_handle = bruteforce_pool.start(surveyed),
    }
end

local function merge_unsatisfiable(target, more)
    if not more then return end
    for _, key in ipairs(more) do table.insert(target, key) end
end

local function has_pending_demand(remaining)
    if not remaining then return false end
    local key = next(remaining)
    while key do
        if (remaining[key] or 0) > 0 then return true end
        key = next(remaining, key)
    end
    return false
end

local function select_aggressive_routes(handle, agg_routes)
    if agg_routes and #agg_routes > 0 then return agg_routes end
    if has_pending_demand(handle.surveyed.remaining) then
        return refined.find(handle.surveyed)
    end
    return {}
end

function route_planner.step_aggressive(handle)
    local is_done, agg_routes, leftovers = bruteforce_pool.step(
        handle.pool_handle)
    if not is_done then return false, nil end
    local routes = {}
    trips.add_all(routes, handle.bulk_routes)
    trips.add_all(routes, select_aggressive_routes(handle, agg_routes))
    merge_unsatisfiable(handle.surveyed.unsatisfiable, leftovers)
    return true, assembly.assemble(routes, handle.surveyed)
end

function route_planner.cancel_aggressive(handle)
    if handle and handle.pool_handle then
        bruteforce_pool.cancel(handle.pool_handle)
    end
end

return route_planner
