local job_channel_name, result_channel_name, shutdown_sentinel = ...

local file_parser = require("observatory.log_monitor.file_parser")

local job_channel = love.thread.getChannel(job_channel_name)
local result_channel = love.thread.getChannel(result_channel_name)

while true do
    local job = job_channel:demand()
    if job == shutdown_sentinel then break end
    local result = file_parser.parse(job.index, job.path)
    result.batch_id = job.batch_id
    result_channel:push(result)
end
