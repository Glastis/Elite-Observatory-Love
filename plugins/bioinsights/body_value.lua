local species_values = require("plugins.bioinsights.species_values")

local body_value = {}

local STATUS_EXCLUDED  = "excluded"
local STATUS_CONFIRMED = "confirmed"

function body_value.exact_value_for_entry(entry)
    local exact

    if entry.confirmed_value and entry.confirmed_value > 0 then
        return entry.confirmed_value
    end
    if not entry.species_label then
        return nil
    end
    exact = species_values.for_species(entry.species_label)
    if exact and exact > 0 then
        return exact
    end
    return nil
end

local function unbounded_genus_range(genus_label)
    local range

    range = species_values.for_genus(genus_label)
    if range then
        return range.min, range.max
    end
    return 0, 0
end

local function species_state_bounds(entry)
    local lo
    local hi
    local v

    for species_label, status in pairs(entry.species_states) do
        if status ~= STATUS_EXCLUDED then
            v = species_values.for_species(species_label) or 0
            if status == STATUS_CONFIRMED then
                return v, v
            end
            if not lo or v < lo then
                lo = v
            end
            if not hi or v > hi then
                hi = v
            end
        end
    end
    if not lo then
        return 0, 0
    end
    return lo, hi
end

function body_value.genus_value_bounds(body, genus_label)
    local entry

    entry = body.genus_entries[genus_label]
    if not entry then
        return unbounded_genus_range(genus_label)
    end
    return species_state_bounds(entry)
end

function body_value.genus_potential_max(entry, genus_label)
    local exact
    local range

    exact = entry and body_value.exact_value_for_entry(entry)
    if exact then
        return exact
    end
    range = species_values.for_genus(genus_label)
    if range then
        return range.max
    end
    return 0
end

function body_value.body_potential_max(body)
    local best
    local v

    best = 0
    for _, genus_label in ipairs(body.genus_order) do
        v = body_value.genus_potential_max(
            body.genus_entries[genus_label], genus_label)
        if v > best then
            best = v
        end
    end
    return best
end

local function is_confirmed_entry(entry)
    return entry and entry.species_label ~= nil
end

local function partition_genus_bounds(body)
    local confirmed_lo
    local confirmed_hi
    local confirmed_count
    local candidate_los
    local candidate_his
    local lo
    local hi

    confirmed_lo = 0
    confirmed_hi = 0
    confirmed_count = 0
    candidate_los = {}
    candidate_his = {}
    for _, genus_label in ipairs(body.genus_order) do
        lo, hi = body_value.genus_value_bounds(body, genus_label)
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

local function descending(a, b)
    return a > b
end

local function sum_top_n(values, n, comparator)
    local total

    if n <= 0 then
        return 0
    end
    table.sort(values, comparator)
    total = 0
    for i = 1, math.min(n, #values) do
        total = total + values[i]
    end
    return total
end

local function effective_target(body)
    local count

    count = body.biological_count or 0
    if count > 0 then
        return count
    end
    return #body.genus_order
end

function body_value.body_value_bounds(body)
    local target_count
    local confirmed_lo
    local confirmed_hi
    local confirmed_count
    local candidate_los
    local candidate_his
    local remaining

    target_count = effective_target(body)
    if target_count <= 0 then
        return 0, 0
    end
    confirmed_lo, confirmed_hi, confirmed_count,
        candidate_los, candidate_his = partition_genus_bounds(body)
    remaining = math.max(0, target_count - confirmed_count)
    return confirmed_lo + sum_top_n(candidate_los, remaining),
        confirmed_hi + sum_top_n(candidate_his, remaining, descending)
end

return body_value
