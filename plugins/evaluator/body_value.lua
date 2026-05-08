local constants = require("plugins.evaluator.constants")

local body_value = {}

local function star_base_value(star_type)
    if not star_type then return 0 end
    return constants.STAR_BASE_VALUES[star_type] or 1500
end

local function planet_base_value(planet_class, terraformable)
    if not planet_class then return 0 end
    local base = constants.BODY_BASE_VALUES[planet_class] or 0
    if terraformable then
        base = base + (constants.BODY_TERRAFORM_BONUS[planet_class] or 0)
    end
    return base
end

local function with_discovery_bonus(base, was_discovered)
    if was_discovered then return base end
    return math.floor(base * constants.FIRST_DISCOVERY_MULTIPLIER)
end

local function with_mapping_bonus(base, was_mapped, was_discovered)
    local mapped = math.floor(base * constants.MAPPING_MULTIPLIER)
    if not was_discovered and not was_mapped then
        return math.floor(mapped * constants.FIRST_DISCOVERY_MULTIPLIER)
    end
    return mapped
end

function body_value.compute(body)
    if body.is_star then
        local base = star_base_value(body.body_type)
        body.current_value = with_discovery_bonus(base, body.was_discovered)
        body.potential_max = body.current_value
        return
    end
    local base = planet_base_value(body.body_type, body.terraformable)
    body.current_value = with_discovery_bonus(base, body.was_discovered)
    body.potential_max = with_mapping_bonus(base, body.was_mapped, body.was_discovered)
end

return body_value
