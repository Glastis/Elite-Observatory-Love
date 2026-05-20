local file_reader = require("observatory.log_monitor.file_reader")
local file_parser = require("observatory.log_monitor.file_parser")

local parse_pool = {}

local JOB_CHANNEL_PREFIX    = "observatory.journal.parse.jobs."
local RESULT_CHANNEL_PREFIX = "observatory.journal.parse.results."
local SHUTDOWN_SENTINEL     = "__observatory_journal_parse_shutdown__"
local WORKER_SCRIPT_PATH    = "observatory/log_monitor/parse_pool_worker.lua"
local WORKER_CAP            = 8
local WORKER_FLOOR          = 2
local IN_FLIGHT_MARGIN      = 2
local FALLBACK_LOG_PREFIX   = "[parse_pool] worker failed, falling back to sync: "

local function resolve_worker_count()
    local probe
    local available

    probe = love and love.system and love.system.getProcessorCount
    if type(probe) ~= "function" then
        return WORKER_FLOOR
    end
    available = probe() or WORKER_FLOOR
    return math.max(WORKER_FLOOR, math.min(available, WORKER_CAP))
end

local WORKER_COUNT = resolve_worker_count()
local MAX_FILES_IN_FLIGHT = WORKER_COUNT + IN_FLIGHT_MARGIN

local pool = {
    workers         = {},
    job_channels    = {},
    result_channels = {},
    is_started      = false,
}

local batch_counter = 0

local function worker_for(file_index)
    return (file_index - 1) % WORKER_COUNT + 1
end

local function spawn_workers()
    local index
    local job_name
    local result_name
    local thread

    index = 1
    while index <= WORKER_COUNT do
        job_name = JOB_CHANNEL_PREFIX .. index
        result_name = RESULT_CHANNEL_PREFIX .. index
        thread = love.thread.newThread(WORKER_SCRIPT_PATH)
        thread:start(job_name, result_name, SHUTDOWN_SENTINEL)
        pool.workers[index] = thread
        pool.job_channels[index] = love.thread.getChannel(job_name)
        pool.result_channels[index] = love.thread.getChannel(result_name)
        index = index + 1
    end
end

local function start_pool()
    if pool.is_started or not (love and love.thread) then
        return pool.is_started
    end
    spawn_workers()
    pool.is_started = true
    return true
end

local function clear_channels()
    local index

    index = 1
    while index <= WORKER_COUNT do
        pool.job_channels[index]:clear()
        pool.result_channels[index]:clear()
        index = index + 1
    end
end

local function new_job(files, is_threaded)
    batch_counter = batch_counter + 1
    return {
        batch_id        = batch_counter,
        files           = files,
        total_files     = #files,
        next_to_assign  = 1,
        next_to_emit    = 1,
        current         = nil,
        done            = 0,
        processed_lines = 0,
        is_threaded     = is_threaded,
    }
end

local function in_flight(job)
    return (job.next_to_assign - 1) - job.done
end

local function assign_jobs(job)
    local index

    while in_flight(job) < MAX_FILES_IN_FLIGHT
            and job.next_to_assign <= job.total_files do
        index = job.next_to_assign
        pool.job_channels[worker_for(index)]:push({
            batch_id = job.batch_id,
            index    = index,
            path     = job.files[index],
        })
        job.next_to_assign = index + 1
    end
end

local function worker_error()
    local index
    local message

    index = 1
    while index <= #pool.workers do
        message = pool.workers[index]:getError()
        if message then
            return message
        end
        index = index + 1
    end
    return nil
end

local function service_threads(job)
    local message

    message = worker_error()
    if message then
        print(FALLBACK_LOG_PREFIX .. message)
        job.is_threaded = false
        return
    end
    assign_jobs(job)
end

local function pop_fresh_result(channel, batch_id)
    local result

    while true do
        result = channel:pop()
        if not result then
            return nil
        end
        if result.batch_id == batch_id then
            return result
        end
    end
end

local function take_current_threaded(job)
    local channel
    local result

    channel = pool.result_channels[worker_for(job.next_to_emit)]
    result = pop_fresh_result(channel, job.batch_id)
    if not result then
        return false
    end
    result.cursor = 1
    job.current = result
    return true
end

local function take_current(job)
    if job.next_to_emit > job.total_files then
        return false
    end
    if job.is_threaded then
        return take_current_threaded(job)
    end
    job.current = file_parser.parse(job.next_to_emit,
        job.files[job.next_to_emit])
    job.current.cursor = 1
    return true
end

local function ensure_current(job)
    if job.current then
        return true
    end
    return take_current(job)
end

local function emit_current(job, remaining, process_entry)
    local entries
    local count

    entries = job.current.entries
    count = #entries
    while remaining > 0 and job.current.cursor <= count do
        process_entry(entries[job.current.cursor])
        job.current.cursor = job.current.cursor + 1
        job.processed_lines = job.processed_lines + 1
        remaining = remaining - 1
    end
    return remaining
end

local function finalize_current(job, state)
    local current

    current = job.current
    if current.cursor <= #current.entries then
        return
    end
    file_reader.mark_consumed(state, current.path, current.size)
    job.next_to_emit = job.next_to_emit + 1
    job.done = job.done + 1
    job.current = nil
end

local function is_finished(job)
    return job.next_to_emit > job.total_files and not job.current
end

function parse_pool.start(files)
    local is_threaded
    local job

    is_threaded = start_pool()
    job = new_job(files, is_threaded)
    if is_threaded then
        clear_channels()
        assign_jobs(job)
    end
    return job
end

function parse_pool.step(job, budget, state, process_entry)
    local remaining

    if not job then
        return false, false
    end
    if job.is_threaded then
        service_threads(job)
    end
    remaining = budget
    while remaining > 0 and ensure_current(job) do
        remaining = emit_current(job, remaining, process_entry)
        finalize_current(job, state)
    end
    return not is_finished(job), remaining < budget
end

function parse_pool.snapshot(job)
    if not job then
        return nil
    end
    return {
        done            = job.done,
        total           = job.total_files,
        processed_lines = job.processed_lines,
    }
end

function parse_pool.shutdown()
    local index

    if not pool.is_started then
        return
    end
    index = 1
    while index <= #pool.workers do
        pool.job_channels[index]:push(SHUTDOWN_SENTINEL)
        index = index + 1
    end
    pool.is_started = false
    pool.workers = {}
    pool.job_channels = {}
    pool.result_channels = {}
end

return parse_pool
