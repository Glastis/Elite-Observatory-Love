local codex = require("plugins.bioinsights.codex")

local species_values = {}

function species_values.for_species(species_label)
    return codex.value_for_species(species_label)
end

function species_values.for_genus(genus_label)
    return codex.value_range_for_genus(genus_label)
end

function species_values.species_in_genus(genus_label)
    return codex.species_in_genus(genus_label)
end

return species_values
