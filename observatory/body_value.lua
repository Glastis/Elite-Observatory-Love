local M = {}

M.PLANET_K_BY_TYPE = {
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
}

M.DEFAULT_PLANET_K  = 300
M.DEFAULT_PLANET_KT = 93328

M.STAR_K_BY_TYPE = {
    O = 1200, B = 1200, A = 1200, F = 1200, G = 1200,
    K = 1200, M = 1200, L = 1200, T = 1200, Y = 1200,
    TTS = 1200, AeBe = 1200,
    DA = 14057, DB = 14057, DC = 14057, DO = 14057,
    DQ = 14057, DX = 14057, DZ = 14057,
    N = 22628, H = 22628,
}

M.DEFAULT_STAR_K = 1200

M.MASS_FACTOR_NUMERATOR   = 3
M.MASS_FACTOR_DENOMINATOR = 5.3
M.MASS_EXPONENT           = 0.199977
M.DEFAULT_MASS_EM         = 1

M.MAPPING_MULTIPLIER         = 3.333333333
M.FIRST_MAPPER_MULTIPLIER    = 1.10967676
M.EFFICIENCY_MULTIPLIER      = 1.25
M.ODYSSEY_MAPPING_MULTIPLIER = 1.3
M.FIRST_DISCOVERY_MULTIPLIER = 2.6

M.MIN_BODY_VALUE = 500

M.VALUE_MILLION         = 1000000
M.VALUE_THOUSAND        = 1000
M.VALUE_MILLION_FORMAT  = "%.1fM"
M.VALUE_THOUSAND_FORMAT = "%.1fK"
M.UNKNOWN_TEXT          = "-"

local function clamped_mass(mass_em)
    local mass = mass_em or M.DEFAULT_MASS_EM
    if mass <= 0 then return M.DEFAULT_MASS_EM end
    return mass
end

local function mass_factor(mass_em)
    local mass = clamped_mass(mass_em)
    return 1 + (M.MASS_FACTOR_NUMERATOR
        * (mass ^ M.MASS_EXPONENT))
        / M.MASS_FACTOR_DENOMINATOR
end

local function planet_k_total(body_type, terraformable)
    local entry = M.PLANET_K_BY_TYPE[body_type]
    local k  = entry and entry.k  or M.DEFAULT_PLANET_K
    local kt = entry and entry.kt or M.DEFAULT_PLANET_KT
    if terraformable then return k + kt end
    return k
end

local function star_k(body_type)
    return M.STAR_K_BY_TYPE[body_type] or M.DEFAULT_STAR_K
end

local function clamp_floor(value)
    return math.floor(math.max(value, M.MIN_BODY_VALUE))
end

local function planet_base(body)
    return planet_k_total(body.body_type, body.terraformable)
        * mass_factor(body.mass_em)
end

local function with_first_discovery(value, was_discovered)
    if was_discovered then return value end
    return value * M.FIRST_DISCOVERY_MULTIPLIER
end

local function mapping_chain(was_mapped)
    local mult = M.MAPPING_MULTIPLIER
        * M.EFFICIENCY_MULTIPLIER
        * M.ODYSSEY_MAPPING_MULTIPLIER
    if was_mapped then return mult end
    return mult * M.FIRST_MAPPER_MULTIPLIER
end

local function planet_scan_value(body)
    return clamp_floor(with_first_discovery(planet_base(body), body.was_discovered))
end

local function planet_max_value(body)
    local mapped = planet_base(body) * mapping_chain(body.was_mapped)
    return clamp_floor(with_first_discovery(mapped, body.was_discovered))
end

local function star_value(body)
    return clamp_floor(with_first_discovery(star_k(body.body_type), body.was_discovered))
end

function M.compute(body)
    if body.is_star then
        body.current_value = star_value(body)
        body.potential_max = body.current_value
        return
    end
    body.current_value = planet_scan_value(body)
    body.potential_max = planet_max_value(body)
end

local function format_thousand_million(value)
    if value >= M.VALUE_MILLION then
        return string.format(M.VALUE_MILLION_FORMAT, value / M.VALUE_MILLION)
    end
    return string.format(M.VALUE_THOUSAND_FORMAT, value / M.VALUE_THOUSAND)
end

function M.format(value)
    if not value or value <= 0 then return M.UNKNOWN_TEXT end
    return format_thousand_million(value) .. " cr"
end

return M
