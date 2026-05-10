local species_values = require("plugins.bioinsights.species_values")

local body_value = {}

local STATUS_EXCLUDED  = "excluded"
local STATUS_CONFIRMED = "confirmed"

function body_value.exact_value_for_entry(entry)
    if entry.confirmed_value and entry.confirmed_value > 0 then
        return entry.confirmed_value
    end
    if not entry.species_label then return nil end
    local exact = species_values.for_species(entry.species_label)
    if exact and exact > 0 then return exact end
    return nil
end

function body_value.genus_value_bounds(body, genus_label)
    local entry = body.genus_entries[genus_label]
    if not entry then
        local range = species_values.for_genus(genus_label)
        if range then return range.min, range.max end
        return 0, 0
    end
    local lo, hi
    for species_label, status in pairs(entry.species_states) do
        if status ~= STATUS_EXCLUDED then
            local v = species_values.for_species(species_label) or 0
            if status == STATUS_CONFIRMED then return v, v end
            if not lo or v < lo then lo = v end
            if not hi or v > hi then hi = v end
        end
    end
    if not lo then return 0, 0 end
    return lo, hi
end

function body_value.genus_potential_max(entry, genus_label)
    local exact = entry and body_value.exact_value_for_entry(entry)
    if exact then return exact end
    local range = species_values.for_genus(genus_label)
    if range then return range.max end
    return 0
end

function body_value.body_potential_max(body)
    local best = 0
    for _, genus_label in ipairs(body.genus_order) do
        local v = body_value.genus_potential_max(
            body.genus_entries[genus_label], genus_label)
        if v > best then best = v end
    end
    return best
end

local function is_confirmed_entry(entry)
    return entry and entry.species_label ~= nil
end

local function partition_genus_bounds(body)
    local confirmed_lo, confirmed_hi = 0, 0
    local confirmed_count = 0
    local candidate_los, candidate_his = {}, {}
    for _, genus_label in ipairs(body.genus_order) do
        local lo, hi = body_value.genus_value_bounds(body, genus_label)
        if is_confirmed_entry(body.genus_entries[genus_label]) then
            confirmed_lo = confirmed_lo + lo
            confirmed_hi = confirmed_hi + hi
            confirmed_count = confirmed_count + 1
        else
            table.insert(candidate_los, lo)
            table.insert(candidate_his, hi)
        end
    end
    return confirmed_lo, confirmed_hi, confirmed_count,
        candidate_los, candidate_his
end

local function descending(a, b) return a > b end

local function sum_top_n(values, n, comparator)
    if n <= 0 then return 0 end
    table.sort(values, comparator)
    local total = 0
    for i = 1, math.min(n, #values) do
        total = total + values[i]
    end
    return total
end

local function effective_target(body)
    local count = body.biological_count or 0
    if count > 0 then return count end
    return #body.genus_order
end

function body_value.body_value_bounds(body)
    local target_count = effective_target(body)
    if target_count <= 0 then return 0, 0 end
    local confirmed_lo, confirmed_hi, confirmed_count,
        candidate_los, candidate_his = partition_genus_bounds(body)
    local remaining = math.max(0, target_count - confirmed_count)
    return confirmed_lo + sum_top_n(candidate_los, remaining),
        confirmed_hi + sum_top_n(candidate_his, remaining, descending)
end

return body_value
