local ATMOSPHERES = {
    NEON           = { "Neon", "NeonRich" },
    AMMONIA        = { "Ammonia", "AmmoniaRich" },
    ARGON          = { "Argon", "ArgonRich" },
    CARBON_DIOXIDE = { "CarbonDioxide", "CarbonDioxideRich" },
    SULPHUR_DIOXIDE = { "SulphurDioxide" },
    NITROGEN       = { "Nitrogen" },
    HELIUM         = { "Helium" },
    METHANE        = { "Methane", "MethaneRich" },
    OXYGEN         = { "Oxygen" },
    WATER          = { "Water", "WaterRich" },
}

local VOLCANISMS = {
    NITROGEN  = { "nitrogen" },
    CARBON    = { "carbon" },
    SILICATE  = { "silicate" },
    IRON      = { "iron" },
    HELIUM    = { "helium" },
    WATER     = { "water" },
    METHANE   = { "methane" },
    AMMONIA   = { "ammonia" },
}

local SPECIES_CODEX = {
    ["Bacterium Acies"]     = { atmospheres = ATMOSPHERES.NEON },
    ["Bacterium Alcyoneum"] = { atmospheres = ATMOSPHERES.AMMONIA },
    ["Bacterium Aurasus"]   = { atmospheres = ATMOSPHERES.CARBON_DIOXIDE },
    ["Bacterium Bullaris"]  = { atmospheres = ATMOSPHERES.METHANE },
    ["Bacterium Cerbrus"]   = { atmospheres = ATMOSPHERES.SULPHUR_DIOXIDE },
    ["Bacterium Informem"]  = { atmospheres = ATMOSPHERES.NITROGEN },
    ["Bacterium Nebulus"]   = { atmospheres = ATMOSPHERES.HELIUM },
    ["Bacterium Vesicula"]  = { atmospheres = ATMOSPHERES.ARGON },
    ["Bacterium Volu"]      = { atmospheres = ATMOSPHERES.OXYGEN },
    ["Bacterium Omentum"]   = { volcanisms  = VOLCANISMS.NITROGEN },
    ["Bacterium Scopulum"]  = { volcanisms  = VOLCANISMS.CARBON },
    ["Bacterium Tela"]      = { volcanisms  = { "helium", "iron", "silicate" } },
    ["Bacterium Verrata"]   = { volcanisms  = VOLCANISMS.WATER },

    ["Fonticulua Campestris"] = { atmospheres = ATMOSPHERES.ARGON },
    ["Fonticulua Digitos"]    = { atmospheres = ATMOSPHERES.METHANE },
    ["Fonticulua Fluctus"]    = { atmospheres = ATMOSPHERES.OXYGEN },
    ["Fonticulua Lapida"]     = { atmospheres = ATMOSPHERES.NITROGEN },
    ["Fonticulua Segmentatus"] = { atmospheres = ATMOSPHERES.NEON },
    ["Fonticulua Upupam"]     = { atmospheres = ATMOSPHERES.ARGON },

    ["Concha Aureolas"]       = { atmospheres = ATMOSPHERES.NITROGEN },
    ["Concha Labiata"]        = { atmospheres = ATMOSPHERES.CARBON_DIOXIDE },
}

local codex = {}

local function value_in_list(value, list)
    for _, candidate in ipairs(list) do
        if candidate == value then return true end
    end
    return false
end

local function lower_value_in_list(value, list)
    if not value or value == "" then return false end
    local low = string.lower(value)
    for _, candidate in ipairs(list) do
        if low:find(candidate, 1, true) then return true end
    end
    return false
end

function codex.species_matches_body(species_label, body)
    local entry = SPECIES_CODEX[species_label]
    if not entry or not body then return nil end
    local body_was_scanned = body.body_type and body.body_type ~= ""
    if entry.atmospheres then
        if not body_was_scanned then return nil end
        if value_in_list(body.atmosphere_type or "", entry.atmospheres) then
            return true
        end
        return false
    end
    if entry.volcanisms then
        if not body_was_scanned then return nil end
        local volcanism = body.volcanism or ""
        if volcanism == "" then return false end
        if lower_value_in_list(volcanism, entry.volcanisms) then return true end
        return false
    end
    return nil
end

function codex.has_constraints(species_label)
    return SPECIES_CODEX[species_label] ~= nil
end

return codex
