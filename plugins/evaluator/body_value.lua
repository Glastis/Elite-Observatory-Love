local constants = require("plugins.evaluator.constants")

local body_value = {}

local function clamped_mass(mass_em)
    local mass = mass_em or constants.DEFAULT_MASS_EM
    if mass <= 0 then return constants.DEFAULT_MASS_EM end
    return mass
end

local function mass_factor(mass_em)
    local mass = clamped_mass(mass_em)
    return 1 + (constants.MASS_FACTOR_NUMERATOR
        * (mass ^ constants.MASS_EXPONENT))
        / constants.MASS_FACTOR_DENOMINATOR
end

local function planet_k_total(body_type, terraformable)
    local entry = constants.PLANET_K_BY_TYPE[body_type]
    local k  = entry and entry.k  or constants.DEFAULT_PLANET_K
    local kt = entry and entry.kt or constants.DEFAULT_PLANET_KT
    if terraformable then return k + kt end
    return k
end

local function star_k(body_type)
    return constants.STAR_K_BY_TYPE[body_type] or constants.DEFAULT_STAR_K
end

local function clamp_floor(value)
    return math.floor(math.max(value, constants.MIN_BODY_VALUE))
end

local function planet_base(body)
    return planet_k_total(body.body_type, body.terraformable)
        * mass_factor(body.mass_em)
end

local function with_first_discovery(value, was_discovered)
    if was_discovered then return value end
    return value * constants.FIRST_DISCOVERY_MULTIPLIER
end

local function mapping_chain(was_mapped)
    local mult = constants.MAPPING_MULTIPLIER
        * constants.EFFICIENCY_MULTIPLIER
        * constants.ODYSSEY_MAPPING_MULTIPLIER
    if was_mapped then return mult end
    return mult * constants.FIRST_MAPPER_MULTIPLIER
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

function body_value.compute(body)
    if body.is_star then
        body.current_value = star_value(body)
        body.potential_max = body.current_value
        return
    end
    body.current_value = planet_scan_value(body)
    body.potential_max = planet_max_value(body)
end

return body_value
