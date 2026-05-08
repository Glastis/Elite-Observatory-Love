return {
    GRID_COLUMNS = {
        "Body", "Type", "Genus", "Species",
        "Variant", "Samples", "Value", "Distance",
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
    VALUE_FORMAT               = "%s cr",
    VALUE_RANGE_FORMAT         = "%s – %s cr",
    UNKNOWN_TEXT               = "—",

    NOTIFY_TITLE_HIGH_VALUE    = "High-value biological",
    NOTIFY_TITLE_PERSONAL_NEW  = "New personal codex entry",
    NOTIFY_TITLE_GALACTIC_NEW  = "Possible galactic first",

    PENDING_BIO_PLACEHOLDER    = "(unmapped)",
}
