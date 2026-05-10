local body_value = require("observatory.body_value")

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
    VALUE_MILLION            = body_value.VALUE_MILLION,
    VALUE_THOUSAND           = body_value.VALUE_THOUSAND,
    VALUE_MILLION_FORMAT     = body_value.VALUE_MILLION_FORMAT,
    VALUE_THOUSAND_FORMAT    = body_value.VALUE_THOUSAND_FORMAT,
    UNKNOWN_TEXT             = body_value.UNKNOWN_TEXT,

    TERRAFORM_LABEL_YES      = "Yes",
    TERRAFORM_LABEL_NO       = "-",
    MAP_LABEL_YES            = "*",
    MAP_LABEL_NO             = "",

    DEFAULT_MIN_BODY_VALUE          = 400000,
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

    PLANET_K_BY_TYPE  = body_value.PLANET_K_BY_TYPE,
    DEFAULT_PLANET_K  = body_value.DEFAULT_PLANET_K,
    DEFAULT_PLANET_KT = body_value.DEFAULT_PLANET_KT,

    STAR_K_BY_TYPE = body_value.STAR_K_BY_TYPE,
    DEFAULT_STAR_K = body_value.DEFAULT_STAR_K,

    MASS_FACTOR_NUMERATOR   = body_value.MASS_FACTOR_NUMERATOR,
    MASS_FACTOR_DENOMINATOR = body_value.MASS_FACTOR_DENOMINATOR,
    MASS_EXPONENT           = body_value.MASS_EXPONENT,
    DEFAULT_MASS_EM         = body_value.DEFAULT_MASS_EM,

    MAPPING_MULTIPLIER         = body_value.MAPPING_MULTIPLIER,
    FIRST_MAPPER_MULTIPLIER    = body_value.FIRST_MAPPER_MULTIPLIER,
    EFFICIENCY_MULTIPLIER      = body_value.EFFICIENCY_MULTIPLIER,
    ODYSSEY_MAPPING_MULTIPLIER = body_value.ODYSSEY_MAPPING_MULTIPLIER,
    FIRST_DISCOVERY_MULTIPLIER = body_value.FIRST_DISCOVERY_MULTIPLIER,

    MIN_BODY_VALUE = body_value.MIN_BODY_VALUE,

    NOTIFY_TITLE_HIGH_VALUE = "High-value body",
    NOTIFY_TITLE_TERRAFORM  = "Terraformable",
    NOTIFY_TITLE_LANDABLE   = "Landable atmospheric",
}
