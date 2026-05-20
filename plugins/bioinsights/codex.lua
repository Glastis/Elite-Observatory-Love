local CATALOG_FILES = {
    "aleoida", "anemone", "bacterium", "brain_tree", "cactoida",
    "clypeus", "concha", "electricae", "fonticulua", "frutexa",
    "fumerola", "fungoida", "osseus", "recepta", "shard",
    "stratum", "tubers", "tubus", "tussock",
}

local CATALOG_REQUIRE_PREFIX = "plugins.bioinsights.codex."
local GENUS_LABEL_PATTERN = "^(%S+)"

local GRAVITY_DIVISOR  = 9.797759
local PRESSURE_DIVISOR = 101231.656250

local ATMOSPHERE_FALLBACK = "None"
local VOLCANISM_ANY_RULE = "Any"
local VOLCANISM_NONE_RULE = "None"
local VOLCANISM_NEGATE_PREFIX = "!"
local VOLCANISM_EXACT_PREFIX = "="
local USER_FLAG_NEAR_NEBULA = "near_nebula"
local USER_FLAG_NEAR_GUARDIAN = "near_guardian"

local codex = {}

local species_by_name = {}
local species_order_by_genus = {}
local genus_value_range = {}

local function record_genus_value(genus_label, entry_value)
    local range

    range = genus_value_range[genus_label]
        or { min = entry_value, max = entry_value }
    if entry_value < range.min then
        range.min = entry_value
    end
    if entry_value > range.max then
        range.max = entry_value
    end
    genus_value_range[genus_label] = range
end

local function register_species(entry, species_name)
    local genus_label

    species_by_name[species_name] = entry
    genus_label = species_name:match(GENUS_LABEL_PATTERN)
    if not genus_label then
        return
    end
    species_order_by_genus[genus_label] =
        species_order_by_genus[genus_label] or {}
    table.insert(species_order_by_genus[genus_label], species_name)
    record_genus_value(genus_label, entry.value)
end

local function build_species_entry(genus_key, species_key, species_data)
    return {
        name        = species_data.name,
        value       = species_data.value or 0,
        rulesets    = species_data.rulesets or {},
        genus_key   = genus_key,
        species_key = species_key,
    }
end

local function process_catalog(catalog)
    local entry

    for genus_key, species_map in pairs(catalog) do
        for species_key, species_data in pairs(species_map) do
            entry = build_species_entry(genus_key, species_key, species_data)
            register_species(entry, species_data.name)
        end
    end
end

local function load_catalog(file)
    local ok
    local catalog

    ok, catalog = pcall(require, CATALOG_REQUIRE_PREFIX .. file)
    if ok and type(catalog) == "table" then
        return catalog
    end
    return nil
end

local function aggregate()
    local catalog

    species_by_name = {}
    species_order_by_genus = {}
    genus_value_range = {}
    for _, file in ipairs(CATALOG_FILES) do
        catalog = load_catalog(file)
        if catalog then
            process_catalog(catalog)
        end
    end
    for _, list in pairs(species_order_by_genus) do
        table.sort(list)
    end
end

aggregate()

function codex.species_in_genus(genus_label)
    return species_order_by_genus[genus_label] or {}
end

function codex.all_genuses()
    local list

    list = {}
    for genus_label in pairs(species_order_by_genus) do
        table.insert(list, genus_label)
    end
    table.sort(list)
    return list
end

function codex.value_for_species(species_label)
    local entry

    entry = species_by_name[species_label]
    return entry and entry.value or nil
end

function codex.value_range_for_genus(genus_label)
    return genus_value_range[genus_label]
end

function codex.has_constraints(species_label)
    local entry

    entry = species_by_name[species_label]
    return entry ~= nil and entry.rulesets and #entry.rulesets > 0
end

local function value_in_list(value, list)
    if not list then
        return false
    end
    for _, candidate in ipairs(list) do
        if candidate == value then
            return true
        end
    end
    return false
end

local function lower_substring_match(body_value, candidates)
    local low

    if not body_value or body_value == "" then
        return false
    end
    low = string.lower(body_value)
    for _, candidate in ipairs(candidates) do
        if low:find(string.lower(candidate), 1, true) then
            return true
        end
    end
    return false
end

local function gravity_in_g(body)
    if not body.gravity_ms2 or body.gravity_ms2 <= 0 then
        return nil
    end
    return body.gravity_ms2 / GRAVITY_DIVISOR
end

local function pressure_in_atm(body)
    if not body.pressure_pa or body.pressure_pa <= 0 then
        return nil
    end
    return body.pressure_pa / PRESSURE_DIVISOR
end

local function temperature_k(body)
    if not body.temperature_k or body.temperature_k <= 0 then
        return nil
    end
    return body.temperature_k
end

local function check_atmosphere(allowed, body)
    local body_atm

    if not body.body_type or body.body_type == "" then
        return nil
    end
    body_atm = body.atmosphere_type or ""
    if body_atm == "" then
        body_atm = ATMOSPHERE_FALLBACK
    end
    if value_in_list(body_atm, allowed) then
        return true
    end
    return false
end

local function check_body_type(allowed, body)
    if not body.body_type or body.body_type == "" then
        return nil
    end
    if value_in_list(body.body_type, allowed) then
        return true
    end
    return false
end

local function check_parent_star(allowed, body)
    local star

    star = body.parent_star_type
    if not star or star == "" then
        return nil
    end
    if value_in_list(star, allowed) then
        return true
    end
    if value_in_list(star:sub(1, 1), allowed) then
        return true
    end
    return false
end

local function check_min(value, threshold)
    if value == nil then
        return nil
    end
    if value < threshold then
        return false
    end
    return true
end

local function check_max(value, threshold)
    if value == nil then
        return nil
    end
    if value > threshold then
        return false
    end
    return true
end

local function check_volcanism_any(body_volc)
    if body_volc == "" then
        return false
    end
    return true
end

local function check_volcanism_none(body_volc)
    if body_volc == "" then
        return true
    end
    return false
end

local function check_volcanism_negate(rule_value, body_volc)
    local target

    if body_volc == "" then
        return false
    end
    target = rule_value:sub(2)
    if string.lower(body_volc):find(string.lower(target), 1, true) then
        return false
    end
    return true
end

local function volcanism_candidate_matches(candidate, body_volc)
    if type(candidate) ~= "string" then
        return false
    end
    if candidate:sub(1, 1) == VOLCANISM_EXACT_PREFIX then
        return body_volc == candidate:sub(2)
    end
    return string.lower(body_volc):find(string.lower(candidate), 1, true) ~= nil
end

local function check_volcanism_candidates(rule_value, body_volc)
    for _, candidate in ipairs(rule_value) do
        if volcanism_candidate_matches(candidate, body_volc) then
            return true
        end
    end
    return false
end

local function is_volcanism_negate_rule(rule_value)
    return type(rule_value) == "string"
        and rule_value:sub(1, 1) == VOLCANISM_NEGATE_PREFIX
end

local function check_volcanism(rule_value, body)
    local body_volc

    body_volc = body.volcanism or ""
    if rule_value == VOLCANISM_ANY_RULE then
        return check_volcanism_any(body_volc)
    end
    if rule_value == VOLCANISM_NONE_RULE then
        return check_volcanism_none(body_volc)
    end
    if is_volcanism_negate_rule(rule_value) then
        return check_volcanism_negate(rule_value, body_volc)
    end
    if type(rule_value) == "table" then
        return check_volcanism_candidates(rule_value, body_volc)
    end
    return nil
end

local function check_user_flag(context, key)
    if context and context[key] then
        return true
    end
    return false
end

local function check_min_distance(rule, body)
    if not body.distance_ls or body.distance_ls <= 0 then
        return nil
    end
    if body.distance_ls < rule then
        return false
    end
    return true
end

local function context_system(context)
    return context and context.system or nil
end

local function any_body_type_matches(system, candidates)
    local sibling_type

    if not system or not system.bodies then
        return nil
    end
    for _, sibling in pairs(system.bodies) do
        sibling_type = sibling.body_type
        if sibling_type and sibling_type ~= ""
            and value_in_list(sibling_type, candidates) then
            return true
        end
    end
    return nil
end

local function check_system_body_match(rule, context)
    return any_body_type_matches(context_system(context), rule)
end

local function check_indeterminate()
    return nil
end

local CONSTRAINT_CHECKERS = {
    atmosphere      = function(rule, body, _) return check_atmosphere(rule, body) end,
    body_type       = function(rule, body, _) return check_body_type(rule, body) end,
    parent_star     = function(rule, body, _) return check_parent_star(rule, body) end,
    min_gravity     = function(rule, body, _) return check_min(gravity_in_g(body), rule) end,
    max_gravity     = function(rule, body, _) return check_max(gravity_in_g(body), rule) end,
    min_temperature = function(rule, body, _) return check_min(temperature_k(body), rule) end,
    max_temperature = function(rule, body, _) return check_max(temperature_k(body), rule) end,
    min_pressure    = function(rule, body, _) return check_min(pressure_in_atm(body), rule) end,
    max_pressure    = function(rule, body, _) return check_max(pressure_in_atm(body), rule) end,
    volcanism       = function(rule, body, _) return check_volcanism(rule, body) end,
    nebula          = function(_, _, context) return check_user_flag(context, USER_FLAG_NEAR_NEBULA) end,
    guardian        = function(_, _, context) return check_user_flag(context, USER_FLAG_NEAR_GUARDIAN) end,
    distance        = function(rule, body, _) return check_min_distance(rule, body) end,
    star            = function(rule, _, context) return check_system_body_match(rule, context) end,
    bodies          = function(rule, _, context) return check_system_body_match(rule, context) end,
    regions         = check_indeterminate,
    region          = check_indeterminate,
}

local function ruleset_matches(ruleset, body, context)
    local indeterminate
    local checker
    local result

    indeterminate = false
    for key, rule in pairs(ruleset) do
        checker = CONSTRAINT_CHECKERS[key]
        if checker then
            result = checker(rule, body, context)
            if result == false then
                return false
            end
            if result == nil then
                indeterminate = true
            end
        end
    end
    if indeterminate then
        return nil
    end
    return true
end

function codex.species_matches_body(species_label, body, context)
    local entry
    local saw_indeterminate
    local result

    entry = species_by_name[species_label]
    if not entry or not body then
        return nil
    end
    if not entry.rulesets or #entry.rulesets == 0 then
        return nil
    end
    saw_indeterminate = false
    for _, ruleset in ipairs(entry.rulesets) do
        result = ruleset_matches(ruleset, body, context)
        if result == true then
            return true
        end
        if result == nil then
            saw_indeterminate = true
        end
    end
    if saw_indeterminate then
        return nil
    end
    return false
end

return codex
