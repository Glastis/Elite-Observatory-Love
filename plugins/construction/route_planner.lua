local market   = require("plugins.construction.route_planner.market")
local bulk     = require("plugins.construction.route_planner.bulk")
local refined  = require("plugins.construction.route_planner.refined")
local assembly = require("plugins.construction.route_planner.assembly")
local trips    = require("plugins.construction.route_planner.trips")

local route_planner = {}

function route_planner.compute(plan_input)
    local surveyed
    local routes

    surveyed = market.survey(plan_input)
    routes = {}
    trips.add_all(routes, bulk.find(surveyed))
    trips.add_all(routes, refined.find(surveyed))
    return assembly.assemble(routes, surveyed)
end

return route_planner
