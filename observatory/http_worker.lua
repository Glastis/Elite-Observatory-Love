local request_channel_name, response_channel_name, shutdown_sentinel = ...

local request_channel = love.thread.getChannel(request_channel_name)
local response_channel = love.thread.getChannel(response_channel_name)

local CURL_TIMEOUT_S = 25
local CURL_COMMAND_FORMAT = "curl -s -m %d -w \"\\n%%{http_code}\" %s"
local CURL_OUTPUT_PATTERN = "^(.*)\n(%d+)%s*$"

local has_https, https = pcall(require, "https")

local function failure(request_id, message)
    return { id = request_id, is_ok = false, error = message }
end

local function success(request_id, status, body)
    return { id = request_id, is_ok = true, status = status, body = body or "" }
end

local function fetch_with_https(request)
    local ok, status, body = pcall(https.request, request.url)
    if not ok then return failure(request.id, tostring(status)) end
    if type(status) ~= "number" then return failure(request.id, "no response") end
    return success(request.id, status, body)
end

local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

local function fetch_with_curl(request)
    local command = string.format(CURL_COMMAND_FORMAT, CURL_TIMEOUT_S,
        shell_quote(request.url))
    local pipe = io.popen(command, "r")
    if not pipe then return failure(request.id, "curl unavailable") end
    local output = pipe:read("*a") or ""
    pipe:close()
    local body, status = output:match(CURL_OUTPUT_PATTERN)
    if not status then return failure(request.id, "curl request failed") end
    return success(request.id, tonumber(status), body)
end

local perform_request = has_https and fetch_with_https or fetch_with_curl

while true do
    local request = request_channel:demand()
    if request == shutdown_sentinel then break end
    response_channel:push(perform_request(request))
end
