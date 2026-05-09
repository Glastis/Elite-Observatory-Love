local wiki = require("plugins.bioinsights.codex.wiki_variants")

local variants = {}

local STAR_TYPE_ALIASES = {
    ["Ae"] = "Ae/Be",
    ["Be"] = "Ae/Be",
    ["AeBe"] = "Ae/Be",
    ["Herbig_AeBe"] = "Ae/Be",
    ["TTS"] = "TTS",
    ["TTauri"] = "TTS",
    ["T_Tauri"] = "TTS",
    ["WR"] = "W",
    ["W"] = "W",
}

local function normalize_star(star_type)
    if not star_type or star_type == "" then return nil end
    local mapped = STAR_TYPE_ALIASES[star_type]
    if mapped then return mapped end
    return star_type
end

local function star_lookup(mapping, star_type)
    local normalized = normalize_star(star_type)
    if not normalized then return nil end
    if mapping[normalized] then return mapping[normalized] end
    local first_letter = normalized:sub(1, 1)
    return mapping[first_letter]
end

local function unique_sorted_colors(mapping)
    local seen = {}
    local list = {}
    for _, color in pairs(mapping) do
        if not seen[color] then
            seen[color] = true
            table.insert(list, color)
        end
    end
    table.sort(list)
    return list
end

local function body_has_material(body, material_name)
    if not body or not body.materials then return false end
    local needle = string.lower(material_name)
    for _, present in ipairs(body.materials) do
        if present == needle then return true end
    end
    return false
end

local function sorted_materials(mapping)
    local keys = {}
    for material in pairs(mapping) do table.insert(keys, material) end
    table.sort(keys)
    return keys
end

local function material_candidates(mapping, body)
    if not body or not body.materials or #body.materials == 0 then
        return table.concat(unique_sorted_colors(mapping), " | ")
    end
    local matched = {}
    local seen = {}
    for _, material in ipairs(sorted_materials(mapping)) do
        local color = mapping[material]
        if body_has_material(body, material) and not seen[color] then
            seen[color] = true
            table.insert(matched, color)
        end
    end
    if #matched == 0 then return nil end
    return table.concat(matched, " or ")
end

local PREDICTORS = {
    star = function(entry, body)
        return star_lookup(entry.variant_mapping, body and body.parent_star_type)
    end,
    grade_4_material = function(entry, body)
        return material_candidates(entry.variant_mapping, body)
    end,
    grade_3_material = function(entry, body)
        return material_candidates(entry.variant_mapping, body)
    end,
    rare_material = function(entry, body)
        return material_candidates(entry.variant_mapping, body)
    end,
}

local function lookup(species_label)
    if not species_label then return nil end
    return wiki[species_label]
end

function variants.predict_for(species_label, body)
    local entry = lookup(species_label)
    if not entry or not entry.variant_method then return nil end
    local predictor = PREDICTORS[entry.variant_method]
    if not predictor then return nil end
    local result = predictor(entry, body)
    if result == nil or result == "" then return nil end
    return result
end

function variants.entry_for(species_label)
    return lookup(species_label)
end

return variants
