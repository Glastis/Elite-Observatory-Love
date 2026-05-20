local job_channel_name, result_channel_name, shutdown_sentinel = ...

local bruteforce = require("plugins.construction.route_planner.bruteforce")

local job_channel    = love.thread.getChannel(job_channel_name)
local result_channel = love.thread.getChannel(result_channel_name)

while true do
    local job = job_channel:demand()
    if job == shutdown_sentinel then break end
    local routes, total_jumps, total_stops = bruteforce.find(job.market, {
        root_stations = job.root_stations,
    })
    result_channel:push({
        batch_id      = job.batch_id,
        routes        = routes,
        total_jumps   = total_jumps,
        total_stops   = total_stops,
        unsatisfiable = job.market.unsatisfiable,
    })
end
