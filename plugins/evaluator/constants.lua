return {
    GRID_COLUMNS = {
        "Body", "Type", "Distance (Ls)", "Gravity (g)",
        "Terraform", "Value", "Max Value", "Map", "Volcanism",
    },

    COLUMN_ALIGN = {
        ["Distance (Ls)"] = "right",
    },

    GRAVITY_DIVIDER          = 9.80665,
    DISTANCE_FORMAT          = "%.0f",
    GRAVITY_FORMAT           = "%.2f",
    VALUE_MILLION            = 1000000,
    VALUE_THOUSAND           = 1000,
    VALUE_MILLION_FORMAT     = "%.1fM",
    VALUE_THOUSAND_FORMAT    = "%.1fK",
    UNKNOWN_TEXT             = "—",

    TERRAFORM_LABEL_YES      = "Yes",
    TERRAFORM_LABEL_NO       = "—",
    MAP_LABEL_YES            = "★",
    MAP_LABEL_NO             = "",

    DEFAULT_MIN_BODY_VALUE          = 50000,
    DEFAULT_MIN_VALUE_FOR_MAPPING   = 200000,
    DEFAULT_MAX_DISTANCE_ELW        = 100000,
    DEFAULT_MAX_DISTANCE_WW         = 100000,
    DEFAULT_MAX_DISTANCE_AW         = 100000,
    DEFAULT_MAX_DISTANCE_ATMO       = 50000,
    DEFAULT_MAX_DISTANCE_OTHER      = 25000,
    DEFAULT_HIGH_VALUE_NOTIFY       = 1000000,

    MAX_DISTANCE_SETTING_BY_BODY_TYPE = {
        ["Earthlike body"] = "max_distance_elw",
        ["Water world"]    = "max_distance_ww",
        ["Ammonia world"]  = "max_distance_aw",
    },

    BODY_BASE_VALUES = {
        ["Earthlike body"]            = 268000,
        ["Water world"]               = 155000,
        ["Ammonia world"]             = 232000,
        ["High metal content body"]   = 12500,
        ["Metal rich body"]           = 21800,
        ["Rocky body"]                = 500,
        ["Icy body"]                  = 500,
        ["Rocky ice body"]            = 500,
        ["Sudarsky class I gas giant"]   = 1500,
        ["Sudarsky class II gas giant"]  = 24000,
        ["Sudarsky class III gas giant"] = 1500,
        ["Sudarsky class IV gas giant"]  = 1500,
        ["Sudarsky class V gas giant"]   = 1500,
    },

    BODY_TERRAFORM_BONUS = {
        ["Earthlike body"]            = 132000,
        ["Water world"]               = 65000,
        ["High metal content body"]   = 50000,
        ["Rocky body"]                = 50000,
    },

    STAR_BASE_VALUES = {
        O = 3500, B = 2500, A = 2000, F = 1500, G = 1500,
        K = 1500, M = 1500, L = 1500, T = 1500, Y = 1500,
        DA = 14057, DB = 14057, DC = 14057, DO = 14057,
        DQ = 14057, DX = 14057, DZ = 14057,
        N = 22628, H = 22628,
    },

    FIRST_DISCOVERY_MULTIPLIER = 2.6,
    MAPPING_MULTIPLIER         = 3.3333333333,

    NOTIFY_TITLE_HIGH_VALUE = "High-value body",
    NOTIFY_TITLE_TERRAFORM  = "Terraformable",
    NOTIFY_TITLE_LANDABLE   = "Landable atmospheric",
}
