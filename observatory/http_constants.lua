return {
    REQUEST_CHANNEL_NAME  = "observatory.http.requests",
    RESPONSE_CHANNEL_NAME = "observatory.http.responses",
    SHUTDOWN_SENTINEL     = "__observatory_http_shutdown__",
    WORKER_SCRIPT_PATH    = "observatory/http_worker.lua",
    WORKER_POOL_SIZE      = 4,
    REQUEST_TIMEOUT_S     = 30,
    HTTP_STATUS_OK_MIN    = 200,
    HTTP_STATUS_OK_MAX    = 299,
}
