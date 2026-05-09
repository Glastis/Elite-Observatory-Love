return {
    GRID_COLUMNS = {
        "Body", "Type", "Distance (Ls)", "Gravity (g)",
        "Terraform", "Value", "Max Value", "Map", "Volcanism",
    },

    COLUMN_ALIGN = {
        ["Distance (Ls)"] = "right",
    },

    UNNAMED_BODY_PLACEHOLDER  = "(unscanned)",

    GRAVITY_DIVIDER          = 9.80665,
    DISTANCE_FORMAT          = "%.0f",
    GRAVITY_FORMAT           = "%.2f",
    VALUE_MILLION            = 1000000,
    VALUE_THOUSAND           = 1000,
    VALUE_MILLION_FORMAT     = "%.1fM",
    VALUE_THOUSAND_FORMAT    = "%.1fK",
    UNKNOWN_TEXT             = "-",

    TERRAFORM_LABEL_YES      = "Yes",
    TERRAFORM_LABEL_NO       = "-",
    MAP_LABEL_YES            = "*",
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

    PLANET_K_BY_TYPE = {
        ["Metal rich body"]              = { k = 21790, kt = 65631 },
        ["High metal content body"]      = { k = 9654,  kt = 100677 },
        ["Earthlike body"]               = { k = 64831 + 116295, kt = 0 },
        ["Water world"]                  = { k = 64831, kt = 116295 },
        ["Ammonia world"]                = { k = 96932, kt = 0 },
        ["Sudarsky class I gas giant"]   = { k = 1656,  kt = 0 },
        ["Sudarsky class II gas giant"]  = { k = 9654,  kt = 100677 },
        ["Sudarsky class III gas giant"] = { k = 1656,  kt = 0 },
        ["Sudarsky class IV gas giant"]  = { k = 1656,  kt = 0 },
        ["Sudarsky class V gas giant"]   = { k = 1656,  kt = 0 },
    },

    DEFAULT_PLANET_K  = 300,
    DEFAULT_PLANET_KT = 93328,

    STAR_K_BY_TYPE = {
        O = 1200, B = 1200, A = 1200, F = 1200, G = 1200,
        K = 1200, M = 1200, L = 1200, T = 1200, Y = 1200,
        TTS = 1200, AeBe = 1200,
        DA = 14057, DB = 14057, DC = 14057, DO = 14057,
        DQ = 14057, DX = 14057, DZ = 14057,
        N = 22628, H = 22628,
    },

    DEFAULT_STAR_K = 1200,

    MASS_FACTOR_NUMERATOR   = 3,
    MASS_FACTOR_DENOMINATOR = 5.3,
    MASS_EXPONENT           = 0.199977,
    DEFAULT_MASS_EM         = 1,

    MAPPING_MULTIPLIER         = 3.333333333,
    FIRST_MAPPER_MULTIPLIER    = 1.10967676,
    EFFICIENCY_MULTIPLIER      = 1.25,
    ODYSSEY_MAPPING_MULTIPLIER = 1.3,
    FIRST_DISCOVERY_MULTIPLIER = 2.6,

    MIN_BODY_VALUE = 500,

    NOTIFY_TITLE_HIGH_VALUE = "High-value body",
    NOTIFY_TITLE_TERRAFORM  = "Terraformable",
    NOTIFY_TITLE_LANDABLE   = "Landable atmospheric",
}
