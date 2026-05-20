local state = require("plugins.bioinsights.state")
local constants = require("plugins.bioinsights.constants")
local species_values = require("plugins.bioinsights.species_values")
local journal_helpers = require("observatory.plugin_helpers.journal")

local handlers = {}

local GENUS_LABEL_PATTERN = "^(%S+)"
local PARENT_KIND_STAR = "Star"
local HIGH_VALUE_DETAIL_FORMAT = "%s: %s (up to %d cr)"

local notifier = function(_) end
local on_change = function() end

function handlers.set_notifier(fn)
    notifier = fn or notifier
end

function handlers.set_on_change(fn)
    on_change = fn or on_change
end

local SIGNAL_BUCKETS = {
    [constants.SIGNAL_KEY_BIOLOGICAL] = "biological_count",
    [constants.SIGNAL_KEY_GEOLOGICAL] = "geological_count",
}

local function update_signals(body, signals)
    local key

    for _, sig in ipairs(signals or {}) do
        key = SIGNAL_BUCKETS[sig.Type]
        if key then
            body[key] = sig.Count or 0
        end
    end
end

local function register_genuses(body, genuses)
    local label

    for _, genus in ipairs(genuses or {}) do
        label = genus.Genus_Localised or genus.Genus
        if label then
            state.mark_genus_dss_confirmed(body, label)
        end
    end
end

local function ensure_parent_chain(system_address, parents)
    journal_helpers.ensure_parent_chain(state.ensure_body, system_address, parents)
end

local function on_location_like(entry)
    state.set_current_system(entry.SystemAddress, entry.StarSystem)
end

local function inherit_parent_star_type(system_address, body, parents)
    local star_type
    local star_body

    journal_helpers.for_each_parent(parents, function(kind, body_id)
        if star_type or kind ~= PARENT_KIND_STAR then
            return
        end
        star_body = state.ensure_body(system_address, body_id, nil)
        if star_body and star_body.parent_star_type ~= "" then
            star_type = star_body.parent_star_type
        end
    end)
    if star_type then
        body.parent_star_type = star_type
    end
end

local function collect_materials(material_list)
    local result
    local raw

    result = {}
    for _, mat in ipairs(material_list or {}) do
        raw = mat.Name or mat.name
        if raw and raw ~= "" then
            table.insert(result, string.lower(raw))
        end
    end
    return result
end

local function apply_scan_fields(body, entry)
    body.distance_ls      = entry.DistanceFromArrivalLS or body.distance_ls
    body.body_type        = entry.PlanetClass or entry.StarType or body.body_type
    body.atmosphere_type  = entry.AtmosphereType or body.atmosphere_type
    body.atmosphere       = entry.Atmosphere or body.atmosphere
    body.volcanism        = entry.Volcanism or body.volcanism
    body.gravity_ms2      = entry.SurfaceGravity or body.gravity_ms2
    body.temperature_k    = entry.SurfaceTemperature or body.temperature_k
    body.pressure_pa      = entry.SurfacePressure or body.pressure_pa
end

local function apply_scan_parents(body, entry)
    if entry.Materials then
        body.materials = collect_materials(entry.Materials)
    end
    if entry.StarType then
        body.parent_star_type = entry.StarType
    end
    if not entry.StarType then
        inherit_parent_star_type(entry.SystemAddress, body, entry.Parents)
    end
    body.parent_body_id =
        journal_helpers.extract_parent_body_id(entry.Parents)
        or body.parent_body_id
end

local function on_scan(entry)
    local body

    ensure_parent_chain(entry.SystemAddress, entry.Parents)
    body = state.ensure_body(entry.SystemAddress, entry.BodyID, entry.BodyName)
    if not body then
        return
    end
    apply_scan_fields(body, entry)
    apply_scan_parents(body, entry)
    state.refresh_genus_constraints(body)
    state.populate_candidate_genuses(body)
end

local function on_fss_body_signals(entry)
    local body

    body = state.ensure_body(entry.SystemAddress, entry.BodyID, entry.BodyName)
    if not body then
        return
    end
    update_signals(body, entry.Signals)
    state.populate_candidate_genuses(body)
end

local function notify_high_value_genus(body, genus_label, settings)
    local range

    if not settings.notify_on_high_value then
        return
    end
    range = species_values.for_genus(genus_label)
    if not range then
        return
    end
    if range.max < settings.minimum_high_value then
        return
    end
    notifier({
        title = constants.NOTIFY_TITLE_HIGH_VALUE,
        detail = string.format(HIGH_VALUE_DETAIL_FORMAT,
            body.name, genus_label, range.max),
    })
end

local function announce_high_value_genuses(body, genuses, settings)
    local label

    for _, genus in ipairs(genuses or {}) do
        label = genus.Genus_Localised or genus.Genus
        if label then
            notify_high_value_genus(body, label, settings)
        end
    end
end

local function on_saa_signals_found(entry, settings)
    local body

    body = state.ensure_body(entry.SystemAddress, entry.BodyID, entry.BodyName)
    if not body then
        return
    end
    update_signals(body, entry.Signals)
    register_genuses(body, entry.Genuses)
    state.prune_candidate_genuses(body)
    announce_high_value_genuses(body, entry.Genuses, settings)
end

local function refine_genus_with_species(body, species_label, variant_label, sample_index)
    local genus_label

    genus_label = species_label and species_label:match(GENUS_LABEL_PATTERN) or nil
    if not genus_label then
        return
    end
    state.confirm_species(body, genus_label, species_label, variant_label, sample_index)
end

local function genus_label_from_entry(entry, species_label)
    local label

    label = entry.Genus_Localised or entry.Genus
    if label and label ~= "" then
        return label
    end
    return species_label and species_label:match(GENUS_LABEL_PATTERN) or nil
end

local function on_scan_organic(entry)
    local body
    local sample_index
    local species_label
    local variant_label

    body = state.ensure_body(entry.SystemAddress, entry.Body)
    if not body then
        return
    end
    sample_index = constants.SCAN_TYPE_TO_SAMPLE_INDEX[entry.ScanType] or 0
    species_label = entry.Species_Localised or entry.Species
    variant_label = entry.Variant_Localised or entry.Variant
    refine_genus_with_species(body, species_label, variant_label, sample_index)
    state.record_sample_at_current_position(
        genus_label_from_entry(entry, species_label))
end

local function on_codex_entry(entry, settings)
    if not entry.IsNewEntry then
        return
    end
    if not settings.notify_on_new_codex then
        return
    end
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

handlers.dispatch = journal_helpers.create_dispatcher({
    handlers = DISPATCH_TABLE,
    on_change = function() on_change() end,
})

function handlers.handle_status(status)
    state.set_current_status(status)
    on_change()
end

return handlers
