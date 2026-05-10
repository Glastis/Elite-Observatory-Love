local tree_view = require("plugins.example.tree_view")
local body_value = require("observatory.body_value")
local journal_helpers = require("observatory.plugin_helpers.journal")
local format_helpers = require("observatory.plugin_helpers.format")
local settings_helpers = require("observatory.plugin_helpers.settings")

local NOTIFY_TITLE_LANDABLE   = "Landable Body"
local NOTIFY_TITLE_FSD_JUMP   = "FSD Jump"
local NOTIFY_DEFAULT_SYSTEM   = "Unknown system"
local DISTANCE_FORMAT         = "%.1f"
local DISTANCE_SUFFIX         = " Ls"
local DEFAULT_KIND            = "other"

local PARENT_KIND_TO_KIND = {
    Star   = "planet",
    Planet = "moon",
    Ring   = "ring",
}

local EVENT_KIND_OVERRIDES = {
    ScanBaryCentre = "barycentre",
}

local Plugin = {
    id              = "example",
    name            = "Explorer",
    short_name      = "Explorer",
    version         = "0.2.0",
    default_settings = {
        notify_on_landable = true,
    },
    _bodies = {},
}

local core_ref

local function format_distance(distance_ls)
    if type(distance_ls) ~= "number" then return "" end
    local formatted = string.format(DISTANCE_FORMAT, distance_ls)
    return format_helpers.group_thousands_in_formatted(formatted) .. DISTANCE_SUFFIX
end

local function detect_kind(entry, parent_kind)
    if EVENT_KIND_OVERRIDES[entry.event] then
        return EVENT_KIND_OVERRIDES[entry.event]
    end
    if entry.StarType then return "star" end
    if entry.PlanetClass then
        return PARENT_KIND_TO_KIND[parent_kind] or "planet"
    end
    return DEFAULT_KIND
end

local function ensure_body_stub(plugin, body_id)
    if body_id == nil then return end
    if plugin._bodies[body_id] then return end
    plugin._bodies[body_id] = {
        body_id        = body_id,
        name           = nil,
        type           = "",
        body_type      = "",
        is_star        = false,
        terraformable  = false,
        mass_em        = 0,
        was_discovered = false,
        was_mapped     = false,
        current_value  = 0,
        potential_max  = 0,
        distance       = "",
        distance_num   = nil,
        kind           = "unknown",
        parent_body_id = nil,
        parent_kind    = nil,
        scanned        = false,
    }
end

local NULL_PARENT_KIND        = "Null"
local BARYCENTRE_KIND_LABEL   = "barycentre"

local function pick_immediate_parent(parents)
    if type(parents) ~= "table" then return nil, nil end
    for _, parent in ipairs(parents) do
        for kind, body_id in pairs(parent) do
            if body_id and body_id > 0 then
                return body_id, kind
            end
        end
    end
    return nil, nil
end

local function ensure_immediate_chain(plugin, parents)
    if type(parents) ~= "table" then return end
    for _, parent in ipairs(parents) do
        for kind, body_id in pairs(parent) do
            if body_id and body_id > 0 then
                ensure_body_stub(plugin, body_id)
                if kind == NULL_PARENT_KIND then
                    plugin._bodies[body_id].kind = BARYCENTRE_KIND_LABEL
                end
            end
        end
    end
end

local function is_terraformable(entry)
    return entry.TerraformState ~= nil and entry.TerraformState ~= ""
end

local function update_body_from_scan(body, entry, parent_id, parent_kind)
    body.name           = entry.BodyName or body.name or "?"
    body.type           = entry.PlanetClass or entry.StarType or entry.event or ""
    body.body_type      = entry.PlanetClass or entry.StarType or body.body_type
    body.is_star        = entry.StarType ~= nil
    body.terraformable  = is_terraformable(entry)
    body.mass_em        = entry.MassEM or body.mass_em
    body.was_discovered = entry.WasDiscovered == true
    body.was_mapped     = entry.WasMapped == true
    body.distance       = format_distance(entry.DistanceFromArrivalLS)
    body.distance_num   = (type(entry.DistanceFromArrivalLS) == "number")
        and entry.DistanceFromArrivalLS or body.distance_num
    body.kind           = detect_kind(entry, parent_kind)
    body.parent_body_id = parent_id or body.parent_body_id
    body.parent_kind    = parent_kind or body.parent_kind
    body.scanned        = true
    body_value.compute(body)
end

local function record_scan(plugin, entry)
    local body_id = entry.BodyID
    if body_id == nil then return end
    ensure_immediate_chain(plugin, entry.Parents)
    ensure_body_stub(plugin, body_id)
    local immediate_parent_id = pick_immediate_parent(entry.Parents)
    local _, kind_parent = journal_helpers.extract_parent(entry.Parents)
    update_body_from_scan(plugin._bodies[body_id], entry,
        immediate_parent_id, kind_parent)
end

local function reset_bodies(plugin)
    plugin._bodies = {}
end

local function notify_landable(plugin, entry)
    if not plugin.settings or not plugin.settings.notify_on_landable then return end
    if entry.Landable ~= true or not core_ref then return end
    core_ref:send_notification({
        title  = NOTIFY_TITLE_LANDABLE,
        detail = string.format("%s (%s)",
            entry.BodyName or "?",
            tostring(entry.PlanetClass or entry.StarType or entry.event)),
    })
end

local function on_scan(plugin, entry)
    record_scan(plugin, entry)
    notify_landable(plugin, entry)
end

local function on_fsd_jump(plugin, entry)
    reset_bodies(plugin)
    if not core_ref then return end
    core_ref:send_notification({
        title  = NOTIFY_TITLE_FSD_JUMP,
        detail = entry.StarSystem or NOTIFY_DEFAULT_SYSTEM,
    })
end

local EVENT_HANDLERS = {
    Scan           = on_scan,
    ScanBaryCentre = on_scan,
    FSDJump        = on_fsd_jump,
}

function Plugin:load(core)
    core_ref = core
    settings_helpers.apply_defaults(self)
end

function Plugin:journal_event(entry)
    if not entry or not entry.event then return end
    local handler = EVENT_HANDLERS[entry.event]
    if not handler then return end
    handler(self, entry)
end

function Plugin:status_change(_)
end

function Plugin:draw_view(view_state, x, y, w, h)
    return tree_view.draw(view_state, x, y, w, h, self._bodies)
end

function Plugin:row_count_label()
    return string.format("%d BODIES", tree_view.row_count(self._bodies))
end

return Plugin
