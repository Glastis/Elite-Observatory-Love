local DISTANCES_BY_GENUS = {
    Aleoida           = 150,
    Bacterium         = 500,
    Cactoida          = 300,
    Clypeus           = 150,
    Concha            = 150,
    Electricae        = 1000,
    Fonticulua        = 500,
    Frutexa           = 150,
    Fumerola          = 100,
    Fungoida          = 300,
    Osseus            = 800,
    Recepta           = 150,
    Stratum           = 500,
    Tubus             = 800,
    Tussock           = 200,
    Crystalline       = 100,
    ["Brain Tree"]    = 100,
    ["Sinuous Tubers"] = 100,
    Anemone           = 100,
    ["Bark Mound"]    = 100,
    ["Amphora Plant"] = 100,
    Aureum            = 100,
    Gypseeum          = 100,
    Lindigoticum      = 100,
    Lividum           = 100,
    Ostrinum          = 100,
    Puniceum          = 100,
    Roseum            = 100,
    Viride            = 100,
    Albidum           = 100,
    Blatteum          = 100,
    Caeruleum         = 100,
    Croceum           = 100,
    Luteolum          = 100,
    Prasinum          = 100,
    Rubeum            = 100,
    Violaceum         = 100,
}

local sample_distances = {}

function sample_distances.for_genus(genus_label)
    if not genus_label then return nil end
    return DISTANCES_BY_GENUS[genus_label]
end

function sample_distances.for_species(species_label)
    if not species_label then return nil end
    local first_word = species_label:match("^(%S+)")
    return sample_distances.for_genus(first_word)
end

return sample_distances
