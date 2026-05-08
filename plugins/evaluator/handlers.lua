local state = require("plugins.evaluator.state")
local body_value = require("plugins.evaluator.body_value")
local constants = require("plugins.evaluator.constants")

local handlers = {}

local notifier = function(_) end
local on_change = function() end

function handlers.set_notifier(fn) notifier = fn or notifier end
function handlers.set_on_change(fn) on_change = fn or on_change end

local function is_terraformable(entry)
    return entry.TerraformState ~= nil and entry.TerraformState ~= ""
end

local function gravity_in_g(surface_gravity_ms2)
    if not surface_gravity_ms2 then return 0 end
    return surface_gravity_ms2 / constants.GRAVITY_DIVIDER
end

local function distance_threshold(body, settings)
    local setting_key = constants.MAX_DISTANCE_SETTING_BY_BODY_TYPE[body.body_type]
    if setting_key then return settings[setting_key] end
    if body.atmosphere ~= "" then return settings.max_distance_atmospheric end
    return settings.max_distance_other
end

local function evaluate_mapping(body, settings)
    if body.potential_max < settings.minimum_mapping_value then
        body.worth_mapping = false
        return
    end
    if body.distance_ls > distance_threshold(body, settings) then
        body.worth_mapping = false
        return
    end
    body.worth_mapping = true
end

local function maybe_notify(body, settings)
    if body.notified_high_value then return end
    if not settings.notify_on_high_value then return end
    if body.potential_max < settings.minimum_high_value_notify then return end
    notifier({
        title = constants.NOTIFY_TITLE_HIGH_VALUE,
        detail = string.format("%s (%s) — %d cr",
            body.name, body.body_type, body.potential_max),
    })
    body.notified_high_value = true
end

local function on_location_like(entry)
    state.set_current_system(entry.SystemAddress, entry.StarSystem)
end

local function on_scan(entry, settings)
    local body = state.ensure_body(entry.SystemAddress, entry.BodyID, entry.BodyName)
    if not body then return end
    body.distance_ls    = entry.DistanceFromArrivalLS or body.distance_ls
    body.is_star        = entry.StarType ~= nil
    body.body_type      = entry.PlanetClass or entry.StarType or body.body_type
    body.is_landable    = entry.Landable == true
    body.terraformable  = is_terraformable(entry)
    body.gravity_ms2    = entry.SurfaceGravity or 0
    body.volcanism      = entry.Volcanism or ""
    body.atmosphere     = entry.Atmosphere or ""
    body.was_discovered = entry.WasDiscovered == true
    body.was_mapped     = entry.WasMapped == true
    body.scanned        = true
    body_value.compute(body)
    evaluate_mapping(body, settings)
    maybe_notify(body, settings)
end

local function on_saa_signals_found(entry, settings)
    local body = state.ensure_body(entry.SystemAddress, entry.BodyID, entry.BodyName)
    if not body then return end
    body.was_mapped = true
    body_value.compute(body)
    if not body.scanned then return end
    evaluate_mapping(body, settings)
    maybe_notify(body, settings)
end

local function on_load_game(entry)
    state.reset()
end

local DISPATCH_TABLE = {
    Location          = on_location_like,
    FSDJump           = on_location_like,
    LoadGame          = on_load_game,
    Scan              = on_scan,
    SAASignalsFound   = on_saa_signals_found,
}

function handlers.dispatch(entry, settings)
    if not entry or not entry.event then return end
    local handler = DISPATCH_TABLE[entry.event]
    if not handler then return end
    handler(entry, settings)
    on_change()
end

return handlers
