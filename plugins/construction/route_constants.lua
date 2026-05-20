return {
    API_BASE_URL           = "https://api.ardent-insight.com/v2",
    EXPORTS_PATH_FORMAT    = "/system/name/%s/commodity/name/%s/nearby/exports",
    EXPORTS_QUERY_FORMAT   = "?minVolume=%d&maxDistance=%d&fleetCarriers=false",
    EXPORTS_MIN_VOLUME     = 1000,
    MAX_SOURCE_DISTANCE_LY = 100,

    LARGE_PAD_SIZE = 3,

    SURFACE_STATION_TYPES = {
        CraterPort       = true,
        CraterOutpost    = true,
        SurfaceStation   = true,
        OnFootSettlement = true,
        PlanetaryPort    = true,
    },

    STATUS_IDLE           = "idle",
    STATUS_PENDING        = "pending",
    STATUS_READY          = "ready",
    STATUS_ERROR          = "error",
    STATUS_NO_SHIP_PARAMS = "missing_params",
    STATUS_NO_COORDS      = "no_coords",

    PREVIEW_STOP_COUNT      = 5,
    STATION_COVERAGE_WEIGHT = 100000,
    PRICE_PCT_PER_JUMP      = 5,
    JUMPS_MIN_PER_LEG       = 1,

    STATION_KEY_SEPARATOR = "||",
    BULK_STOP_KIND        = "bulk",
    MULTI_STOP_KIND       = "multi",

    AGGRESSIVE_WORKER_COUNT = 8,
}
