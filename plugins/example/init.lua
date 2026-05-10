local tree_view = require("plugins.example.tree_view")
local body_value = require("observatory.body_value")

local NULL_PARENT_KIND        = "Null"
local NOTIFY_TITLE_LANDABLE   = "Landable Body"
local NOTIFY_TITLE_FSD_JUMP   = "FSD Jump"
local NOTIFY_DEFAULT_SYSTEM   = "Unknown system"
local DISTANCE_FORMAT         = "%.1f"
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

local function ensure_settings(plugin)
    plugin.settings = plugin.settings or {}
    for key, value in pairs(plugin.default_settings) do
        if plugin.settings[key] == nil then plugin.settings[key] = value end
    end
end

local function format_distance(distance_ls)
    if type(distance_ls) ~= "number" then return "" end
    return string.format(DISTANCE_FORMAT, distance_ls) .. " Ls"
end

local function extract_parent_info(parents)
    if type(parents) ~= "table" then return nil, nil end
    for _, parent in ipairs(parents) do
        for kind, body_id in pairs(parent) do
            if kind ~= NULL_PARENT_KIND then return body_id, kind end
        end
    end
    return nil, nil
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

local function ensure_parent_chain(plugin, parents)
    if type(parents) ~= "table" then return end
    for _, parent in ipairs(parents) do
        for kind, body_id in pairs(parent) do
            if kind ~= NULL_PARENT_KIND then ensure_body_stub(plugin, body_id) end
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
    ensure_parent_chain(plugin, entry.Parents)
    ensure_body_stub(plugin, body_id)
    local parent_id, parent_kind = extract_parent_info(entry.Parents)
    update_body_from_scan(plugin._bodies[body_id], entry, parent_id, parent_kind)
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
    ensure_settings(self)
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
