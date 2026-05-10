local state = require("plugins.bioinsights.state")
local constants = require("plugins.bioinsights.constants")
local species_values = require("plugins.bioinsights.species_values")

local handlers = {}

local notifier = function(_) end
local on_change = function() end

function handlers.set_notifier(fn) notifier = fn or notifier end
function handlers.set_on_change(fn) on_change = fn or on_change end

local SIGNAL_BUCKETS = {
    [constants.SIGNAL_KEY_BIOLOGICAL] = "biological_count",
    [constants.SIGNAL_KEY_GEOLOGICAL] = "geological_count",
}

local function update_signals(body, signals)
    for _, sig in ipairs(signals or {}) do
        local key = SIGNAL_BUCKETS[sig.Type]
        if key then body[key] = sig.Count or 0 end
    end
end

local function register_genuses(body, genuses)
    for _, genus in ipairs(genuses or {}) do
        local label = genus.Genus_Localised or genus.Genus
        if label then state.mark_genus_dss_confirmed(body, label) end
    end
end

local NULL_PARENT_KIND = "Null"

local function extract_parent_body_id(parents)
    if type(parents) ~= "table" then return nil end
    for _, parent in ipairs(parents) do
        for kind, body_id in pairs(parent) do
            if kind ~= NULL_PARENT_KIND then return body_id end
        end
    end
    return nil
end

local function ensure_parent_chain(system_address, parents)
    if type(parents) ~= "table" then return end
    for _, parent in ipairs(parents) do
        for kind, body_id in pairs(parent) do
            if kind ~= NULL_PARENT_KIND then
                state.ensure_body(system_address, body_id, nil)
            end
        end
    end
end

local function on_location_like(entry)
    state.set_current_system(entry.SystemAddress, entry.StarSystem)
end

local function inherit_parent_star_type(system_address, body, parents)
    if type(parents) ~= "table" then return end
    for _, parent in ipairs(parents) do
        for kind, body_id in pairs(parent) do
            if kind == "Star" then
                local star_body = state.ensure_body(system_address, body_id, nil)
                if star_body and star_body.parent_star_type ~= "" then
                    body.parent_star_type = star_body.parent_star_type
                    return
                end
            end
        end
    end
end

local function collect_materials(material_list)
    local result = {}
    for _, mat in ipairs(material_list or {}) do
        local raw = mat.Name or mat.name
        if raw and raw ~= "" then
            table.insert(result, string.lower(raw))
        end
    end
    return result
end

local function on_scan(entry)
    ensure_parent_chain(entry.SystemAddress, entry.Parents)
    local body = state.ensure_body(entry.SystemAddress, entry.BodyID, entry.BodyName)
    if not body then return end
    body.distance_ls      = entry.DistanceFromArrivalLS or body.distance_ls
    body.body_type        = entry.PlanetClass or entry.StarType or body.body_type
    body.atmosphere_type  = entry.AtmosphereType or body.atmosphere_type
    body.atmosphere       = entry.Atmosphere or body.atmosphere
    body.volcanism        = entry.Volcanism or body.volcanism
    body.gravity_ms2      = entry.SurfaceGravity or body.gravity_ms2
    body.temperature_k    = entry.SurfaceTemperature or body.temperature_k
    body.pressure_pa      = entry.SurfacePressure or body.pressure_pa
    if entry.Materials then body.materials = collect_materials(entry.Materials) end
    if entry.StarType then body.parent_star_type = entry.StarType end
    if not entry.StarType then
        inherit_parent_star_type(entry.SystemAddress, body, entry.Parents)
    end
    body.parent_body_id   = extract_parent_body_id(entry.Parents)
        or body.parent_body_id
    state.refresh_genus_constraints(body)
    state.populate_candidate_genuses(body)
end

local function on_fss_body_signals(entry)
    local body = state.ensure_body(entry.SystemAddress, entry.BodyID, entry.BodyName)
    if not body then return end
    update_signals(body, entry.Signals)
    state.populate_candidate_genuses(body)
end

local function notify_high_value_genus(body, genus_label, settings)
    if not settings.notify_on_high_value then return end
    local range = species_values.for_genus(genus_label)
    if not range then return end
    if range.max < settings.minimum_high_value then return end
    notifier({
        title = constants.NOTIFY_TITLE_HIGH_VALUE,
        detail = string.format("%s: %s (up to %d cr)",
            body.name, genus_label, range.max),
    })
end

local function on_saa_signals_found(entry, settings)
    local body = state.ensure_body(entry.SystemAddress, entry.BodyID, entry.BodyName)
    if not body then return end
    update_signals(body, entry.Signals)
    register_genuses(body, entry.Genuses)
    state.prune_candidate_genuses(body)
    for _, genus in ipairs(entry.Genuses or {}) do
        local label = genus.Genus_Localised or genus.Genus
        if label then notify_high_value_genus(body, label, settings) end
    end
end

local function refine_genus_with_species(body, species_label, variant_label, sample_index)
    local genus_label = species_label and species_label:match("^(%S+)") or nil
    if not genus_label then return end
    state.confirm_species(body, genus_label, species_label, variant_label, sample_index)
end

local function on_scan_organic(entry)
    local body = state.ensure_body(entry.SystemAddress, entry.Body)
    if not body then return end
    local sample_index = constants.SCAN_TYPE_TO_SAMPLE_INDEX[entry.ScanType] or 0
    local species_label = entry.Species_Localised or entry.Species
    local variant_label = entry.Variant_Localised or entry.Variant
    refine_genus_with_species(body, species_label, variant_label, sample_index)
    state.record_sample_at_current_position()
end

local function on_codex_entry(entry, settings)
    if not entry.IsNewEntry then return end
    if not settings.notify_on_new_codex then return end
    notifier({
        title = constants.NOTIFY_TITLE_PERSONAL_NEW,
        detail = entry.Name_Localised or entry.Name or "",
    })
end

local DISPATCH_TABLE = {
    Location          = on_location_like,
    FSDJump           = on_location_like,
    Scan              = on_scan,
    FSSBodySignals    = on_fss_body_signals,
    SAASignalsFound   = on_saa_signals_found,
    ScanOrganic       = on_scan_organic,
    CodexEntry        = on_codex_entry,
}

function handlers.dispatch(entry, settings)
    if not entry or not entry.event then return end
    local handler = DISPATCH_TABLE[entry.event]
    if not handler then return end
    handler(entry, settings)
    on_change()
end

function handlers.handle_status(status)
    state.set_current_status(status)
    on_change()
end

return handlers
