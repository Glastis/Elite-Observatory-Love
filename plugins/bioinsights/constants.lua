return {
    GRID_COLUMNS = {
        "Body", "Type", "Star", "Bios", "Body Value",
        "Genus", "Species", "Status",
        "Variant", "Samples", "Value", "Distance",
    },

    COLUMN_ALIGN = {
        ["Distance"]   = "right",
        ["Value"]      = "right",
        ["Body Value"] = "right",
        ["Bios"]       = "right",
    },

    STATUS_LABEL = {
        pending   = "pending",
        predicted = "predicted",
        confirmed = "confirmed",
        excluded  = "excluded",
    },

    SIGNAL_KEY_BIOLOGICAL = "$SAA_SignalType_Biological;",
    SIGNAL_KEY_GEOLOGICAL = "$SAA_SignalType_Geological;",

    SCAN_TYPE_TO_SAMPLE_INDEX = {
        Log     = 1,
        Sample  = 2,
        Analyse = 3,
    },

    SAMPLE_INDEX_FINAL_SCAN = 3,

    SAMPLE_INDEX_TO_LABEL = {
        [0] = "0/3",
        [1] = "1/3",
        [2] = "2/3",
        [3] = "3/3",
    },

    HIGH_VALUE_THRESHOLD       = 5000000,
    DISTANCE_FORMAT            = "%.0f Ls",
    SAMPLE_DISTANCE_LABEL      = "Last sample",
    SAMPLE_DISTANCE_METER_FMT  = "%.0f m",
    SAMPLE_DISTANCE_KM_FMT     = "%.2f km",
    SAMPLE_DISTANCE_KM_THRESHOLD = 1000,
    SAMPLE_DISTANCE_PAIR_FMT   = "%s / %s",
    VALUE_FORMAT               = "%s cr",
    VALUE_RANGE_FORMAT         = "%s - %s cr",
    VALUE_MILLION              = 1000000,
    VALUE_THOUSAND             = 1000,
    VALUE_MILLION_FORMAT       = "%.1fM",
    VALUE_THOUSAND_FORMAT      = "%.1fK",
    UNKNOWN_TEXT               = "-",
    UNNAMED_BODY_PLACEHOLDER   = "(unscanned)",

    NOTIFY_TITLE_HIGH_VALUE    = "High-value biological",
    NOTIFY_TITLE_PERSONAL_NEW  = "New personal codex entry",
    NOTIFY_TITLE_GALACTIC_NEW  = "Possible galactic first",

    PENDING_BIO_PLACEHOLDER    = "(unmapped)",
}
