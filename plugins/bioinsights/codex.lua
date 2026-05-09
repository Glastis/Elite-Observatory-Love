local CATALOG_FILES = {
    "aleoida", "anemone", "bacterium", "brain_tree", "cactoida",
    "clypeus", "concha", "electricae", "fonticulua", "frutexa",
    "fumerola", "fungoida", "osseus", "recepta", "shard",
    "stratum", "tubers", "tubus", "tussock",
}

local GRAVITY_DIVISOR  = 9.797759
local PRESSURE_DIVISOR = 101231.656250

local codex = {}

local species_by_name = {}
local species_order_by_genus = {}
local genus_value_range = {}

local function aggregate()
    species_by_name = {}
    species_order_by_genus = {}
    genus_value_range = {}
    for _, file in ipairs(CATALOG_FILES) do
        local ok, catalog = pcall(require, "plugins.bioinsights.codex." .. file)
        if ok and type(catalog) == "table" then
            for genus_key, species_map in pairs(catalog) do
                for species_key, species_data in pairs(species_map) do
                    local entry = {
                        name        = species_data.name,
                        value       = species_data.value or 0,
                        rulesets    = species_data.rulesets or {},
                        genus_key   = genus_key,
                        species_key = species_key,
                    }
                    species_by_name[species_data.name] = entry
                    local genus_label = species_data.name:match("^(%S+)")
                    if genus_label then
                        species_order_by_genus[genus_label]
                            = species_order_by_genus[genus_label] or {}
                        table.insert(species_order_by_genus[genus_label], species_data.name)
                        local range = genus_value_range[genus_label]
                            or { min = entry.value, max = entry.value }
                        if entry.value < range.min then range.min = entry.value end
                        if entry.value > range.max then range.max = entry.value end
                        genus_value_range[genus_label] = range
                    end
                end
            end
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
    local list = {}
    for genus_label in pairs(species_order_by_genus) do
        table.insert(list, genus_label)
    end
    table.sort(list)
    return list
end

function codex.value_for_species(species_label)
    local entry = species_by_name[species_label]
    return entry and entry.value or nil
end

function codex.value_range_for_genus(genus_label)
    return genus_value_range[genus_label]
end

function codex.has_constraints(species_label)
    local entry = species_by_name[species_label]
    return entry ~= nil and entry.rulesets and #entry.rulesets > 0
end

local function value_in_list(value, list)
    if not list then return false end
    for _, candidate in ipairs(list) do
        if candidate == value then return true end
    end
    return false
end

local function lower_substring_match(body_value, candidates)
    if not body_value or body_value == "" then return false end
    local low = string.lower(body_value)
    for _, candidate in ipairs(candidates) do
        if low:find(string.lower(candidate), 1, true) then return true end
    end
    return false
end

local function gravity_in_g(body)
    if not body.gravity_ms2 or body.gravity_ms2 <= 0 then return nil end
    return body.gravity_ms2 / GRAVITY_DIVISOR
end

local function pressure_in_atm(body)
    if not body.pressure_pa or body.pressure_pa <= 0 then return nil end
    return body.pressure_pa / PRESSURE_DIVISOR
end

local function temperature_k(body)
    if not body.temperature_k or body.temperature_k <= 0 then return nil end
    return body.temperature_k
end

local function check_atmosphere(allowed, body)
    if not body.body_type or body.body_type == "" then return nil end
    local body_atm = body.atmosphere_type or ""
    if body_atm == "" then body_atm = "None" end
    if value_in_list(body_atm, allowed) then return true end
    return false
end

local function check_body_type(allowed, body)
    if not body.body_type or body.body_type == "" then return nil end
    if value_in_list(body.body_type, allowed) then return true end
    return false
end

local function check_parent_star(allowed, body)
    local star = body.parent_star_type
    if not star or star == "" then return nil end
    if value_in_list(star, allowed) then return true end
    if value_in_list(star:sub(1, 1), allowed) then return true end
    return false
end

local function check_min(value, threshold)
    if value == nil then return nil end
    if value < threshold then return false end
    return true
end

local function check_max(value, threshold)
    if value == nil then return nil end
    if value > threshold then return false end
    return true
end

local function check_volcanism(rule_value, body)
    local body_volc = body.volcanism or ""
    if rule_value == "Any" then
        if body_volc == "" then return false end
        return true
    end
    if rule_value == "None" then
        if body_volc == "" then return true end
        return false
    end
    if type(rule_value) == "string" and rule_value:sub(1, 1) == "!" then
        local target = rule_value:sub(2)
        if body_volc == "" then return false end
        if string.lower(body_volc):find(string.lower(target), 1, true) then return false end
        return true
    end
    if type(rule_value) == "table" then
        for _, candidate in ipairs(rule_value) do
            if type(candidate) == "string" and candidate:sub(1, 1) == "=" then
                if body_volc == candidate:sub(2) then return true end
            elseif type(candidate) == "string"
                and string.lower(body_volc):find(string.lower(candidate), 1, true) then
                return true
            end
        end
        return false
    end
    return nil
end

local function check_user_flag(context, key)
    if context and context[key] then return true end
    return false
end

local function check_min_distance(rule, body)
    if not body.distance_ls or body.distance_ls <= 0 then return nil end
    if body.distance_ls < rule then return false end
    return true
end

local function context_system(context)
    return context and context.system or nil
end

local function any_body_type_matches(system, candidates)
    if not system or not system.bodies then return nil end
    for _, sibling in pairs(system.bodies) do
        local sibling_type = sibling.body_type
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
    nebula          = function(_, _, context) return check_user_flag(context, "near_nebula") end,
    guardian        = function(_, _, context) return check_user_flag(context, "near_guardian") end,
    distance        = function(rule, body, _) return check_min_distance(rule, body) end,
    star            = function(rule, _, context) return check_system_body_match(rule, context) end,
    bodies          = function(rule, _, context) return check_system_body_match(rule, context) end,
    regions         = check_indeterminate,
    region          = check_indeterminate,
}

local function ruleset_matches(ruleset, body, context)
    local indeterminate = false
    for key, rule in pairs(ruleset) do
        local checker = CONSTRAINT_CHECKERS[key]
        if checker then
            local result = checker(rule, body, context)
            if result == false then return false end
            if result == nil then indeterminate = true end
        end
    end
    if indeterminate then return nil end
    return true
end

function codex.species_matches_body(species_label, body, context)
    local entry = species_by_name[species_label]
    if not entry or not body then return nil end
    if not entry.rulesets or #entry.rulesets == 0 then return nil end
    local saw_indeterminate = false
    for _, ruleset in ipairs(entry.rulesets) do
        local result = ruleset_matches(ruleset, body, context)
        if result == true then return true end
        if result == nil then saw_indeterminate = true end
    end
    if saw_indeterminate then return nil end
    return false
end

return codex
