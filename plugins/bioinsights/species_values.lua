local SPECIES_BASE_VALUE = {
    ["Bacterium Aurasus"]      = 1000000,
    ["Bacterium Cerbrus"]      = 1689800,
    ["Bacterium Nebulus"]      = 5289900,
    ["Bacterium Acies"]        = 1000000,
    ["Bacterium Vesicula"]     = 1000000,
    ["Bacterium Bullaris"]     = 1000000,
    ["Bacterium Informem"]     = 8418000,
    ["Bacterium Tela"]         = 1949800,
    ["Bacterium Volu"]         = 7774700,
    ["Bacterium Omentum"]      = 4638900,
    ["Bacterium Scopulum"]     = 4934500,
    ["Bacterium Verrata"]      = 3897000,
    ["Bacterium Alcyoneum"]    = 1658500,

    ["Aleoida Arcus"]          = 7252500,
    ["Aleoida Coronamus"]      = 6284600,
    ["Aleoida Spica"]          = 3385200,
    ["Aleoida Laminiae"]       = 3385200,
    ["Aleoida Gravis"]         = 12934900,

    ["Cactoida Cortexum"]      = 3667600,
    ["Cactoida Vermis"]        = 16202800,
    ["Cactoida Lapis"]         = 2483600,
    ["Cactoida Pullulanta"]    = 3667600,
    ["Cactoida Peperatis"]     = 2483600,

    ["Clypeus Lacrimam"]       = 8418000,
    ["Clypeus Margaritus"]     = 11873200,
    ["Clypeus Speculumi"]      = 16202800,

    ["Concha Renibus"]         = 4572400,
    ["Concha Aureolas"]        = 7774700,
    ["Concha Labiata"]         = 2352400,
    ["Concha Biconcavis"]      = 19010800,

    ["Electricae Pluma"]       = 6284600,
    ["Electricae Radialem"]    = 6284600,

    ["Fonticulua Segmentatus"] = 19010800,
    ["Fonticulua Campestris"]  = 1000000,
    ["Fonticulua Upupam"]      = 5727600,
    ["Fonticulua Lapida"]      = 3425600,
    ["Fonticulua Fluctus"]     = 20000000,
    ["Fonticulua Digitos"]     = 1804100,

    ["Frutexa Flabellum"]      = 1808900,
    ["Frutexa Acus"]           = 7774700,
    ["Frutexa Metallicum"]     = 1632500,
    ["Frutexa Flammasis"]      = 10326000,
    ["Frutexa Fera"]           = 1632500,
    ["Frutexa Sponsae"]        = 5988000,
    ["Frutexa Collum"]         = 1639800,

    ["Fumerola Carbosis"]      = 6284600,
    ["Fumerola Extremus"]      = 16202800,
    ["Fumerola Nitris"]        = 7500900,
    ["Fumerola Aquatis"]       = 6284600,

    ["Fungoida Setisis"]       = 1670100,
    ["Fungoida Stabitis"]      = 2680300,
    ["Fungoida Bullarum"]      = 3703200,
    ["Fungoida Gelata"]        = 3330300,

    ["Osseus Fractus"]         = 4027800,
    ["Osseus Discus"]          = 12934900,
    ["Osseus Spiralis"]        = 2404700,
    ["Osseus Pumice"]          = 3156300,
    ["Osseus Cornibus"]        = 1483000,
    ["Osseus Pellebantus"]     = 9739000,

    ["Recepta Umbrux"]         = 12934900,
    ["Recepta Deltahedronix"]  = 16202800,
    ["Recepta Conditivus"]     = 14313700,

    ["Stratum Excutitus"]      = 2448900,
    ["Stratum Paleas"]         = 1362000,
    ["Stratum Laminamus"]      = 2788300,
    ["Stratum Araneamus"]      = 2448900,
    ["Stratum Limaxus"]        = 1362000,
    ["Stratum Cucumisis"]      = 16202800,
    ["Stratum Tectonicas"]     = 19010800,
    ["Stratum Frigus"]         = 2637500,

    ["Tubus Conifer"]          = 2415500,
    ["Tubus Sororibus"]        = 5727600,
    ["Tubus Cavas"]            = 11873200,
    ["Tubus Rosaris"]          = 2637500,
    ["Tubus Compagibus"]       = 7774700,

    ["Tussock Pennata"]        = 5853800,
    ["Tussock Stigmasis"]      = 19010800,
    ["Tussock Capillum"]       = 7025800,
    ["Tussock Triticum"]       = 7774700,
    ["Tussock Catena"]         = 1766600,
    ["Tussock Cultro"]         = 1766600,
    ["Tussock Caputus"]        = 3472400,
    ["Tussock Ignis"]          = 1849000,
    ["Tussock Virgam"]         = 14313700,
    ["Tussock Ventusa"]        = 3277700,
    ["Tussock Albata"]         = 3252500,
    ["Tussock Propagito"]      = 1000000,
    ["Tussock Pennatis"]       = 1000000,
    ["Tussock Serrati"]        = 4447100,
    ["Tussock Divisa"]         = 1766600,
}

local species_values = {}

local function genus_from_species(species_label)
    return species_label:match("^(%S+)")
end

local genus_index = {}
for species_label, value in pairs(SPECIES_BASE_VALUE) do
    local genus = genus_from_species(species_label)
    if genus then
        genus_index[genus] = genus_index[genus] or { min = value, max = value, species = {} }
        local entry = genus_index[genus]
        if value < entry.min then entry.min = value end
        if value > entry.max then entry.max = value end
        table.insert(entry.species, species_label)
    end
end

function species_values.for_species(species_label)
    if not species_label then return nil end
    return SPECIES_BASE_VALUE[species_label]
end

function species_values.for_genus(genus_label)
    if not genus_label then return nil end
    return genus_index[genus_label]
end

function species_values.species_in_genus(genus_label)
    local entry = genus_index[genus_label]
    if not entry then return {} end
    return entry.species
end

return species_values
