local constants = require("observatory.http_constants")

local http_service = {}

local worker_threads = {}
local request_channel
local response_channel
local pending = {}
local next_request_id = 0
local is_started = false

local function current_time()
    if love and love.timer then return love.timer.getTime() end
    return 0
end

local function deliver(callback, result)
    if type(callback) ~= "function" then return end
    pcall(callback, result)
end

local function spawn_workers()
    for index = 1, constants.WORKER_POOL_SIZE do
        local thread = love.thread.newThread(constants.WORKER_SCRIPT_PATH)
        thread:start(constants.REQUEST_CHANNEL_NAME,
            constants.RESPONSE_CHANNEL_NAME, constants.SHUTDOWN_SENTINEL)
        worker_threads[index] = thread
    end
end

function http_service.start()
    if is_started or not (love and love.thread) then return end
    request_channel = love.thread.getChannel(constants.REQUEST_CHANNEL_NAME)
    response_channel = love.thread.getChannel(constants.RESPONSE_CHANNEL_NAME)
    spawn_workers()
    is_started = true
end

function http_service.request(url, callback)
    next_request_id = next_request_id + 1
    local request_id = next_request_id
    if not is_started then
        deliver(callback, { is_ok = false, error = "http service unavailable" })
        return request_id
    end
    pending[request_id] = { callback = callback, started_at = current_time() }
    request_channel:push({ id = request_id, url = url })
    return request_id
end

function http_service.cancel(request_id)
    pending[request_id] = nil
end

local function drain_responses()
    while true do
        local response = response_channel:pop()
        if not response then return end
        local entry = pending[response.id]
        if entry then
            pending[response.id] = nil
            deliver(entry.callback, response)
        end
    end
end

local function check_timeouts()
    local deadline = current_time() - constants.REQUEST_TIMEOUT_S
    for request_id, entry in pairs(pending) do
        if entry.started_at <= deadline then
            pending[request_id] = nil
            deliver(entry.callback, { is_ok = false, error = "timeout" })
        end
    end
end

function http_service.update()
    if not is_started then return end
    drain_responses()
    check_timeouts()
end

function http_service.shutdown()
    if not is_started then return end
    for _ = 1, #worker_threads do
        request_channel:push(constants.SHUTDOWN_SENTINEL)
    end
end

function http_service.pending_count()
    local count = 0
    for _ in pairs(pending) do count = count + 1 end
    return count
end

return http_service
