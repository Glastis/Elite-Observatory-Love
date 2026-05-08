local hierarchy = require("observatory.grid_hierarchy")

local NULL_PARENT_KIND = "Null"
local UNNAMED_BODY_PLACEHOLDER = "(unscanned)"
local DISTANCE_FORMAT = "%.1f"
local NOTIFY_TITLE_LANDABLE = "Landable Body"
local NOTIFY_TITLE_FSD_JUMP = "FSD Jump"
local NOTIFY_DEFAULT_SYSTEM = "Unknown system"

local Plugin = {
    id = "example",
    name = "Example Explorer",
    short_name = "Explorer",
    version = "0.1.0",
    grid = {
        columns = { "Time", "Body", "Type", "Distance (Ls)" },
        column_align = { ["Distance (Ls)"] = "right" },
        rows = {},
    },
    default_settings = {
        notify_on_landable = true,
    },
    group_by_body = false,
    _bodies = {},
}

local core_ref

local function format_distance(distance_ls)
    if type(distance_ls) ~= "number" then return "" end
    return string.format(DISTANCE_FORMAT, distance_ls)
end

local function extract_parent_body_id(parents)
    if type(parents) ~= "table" then return nil end
    for _, parent in ipairs(parents) do
        for kind, body_id in pairs(parent) do
            if kind ~= NULL_PARENT_KIND then return body_id end
        end
    end
    return nil
end

local function ensure_body_stub(plugin, body_id)
    if body_id == nil then return end
    if plugin._bodies[body_id] then return end
    plugin._bodies[body_id] = {
        body_id        = body_id,
        name           = nil,
        type           = "",
        distance       = "",
        time           = "",
        parent_body_id = nil,
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

local function record_scan(plugin, entry)
    local body_id = entry.BodyID
    if body_id == nil then return end
    ensure_parent_chain(plugin, entry.Parents)
    ensure_body_stub(plugin, body_id)
    local body = plugin._bodies[body_id]
    body.name           = entry.BodyName or body.name or "?"
    body.type           = entry.PlanetClass or entry.StarType or entry.event
    body.distance       = format_distance(entry.DistanceFromArrivalLS)
    body.time           = entry.timestamp or body.time
    body.parent_body_id = extract_parent_body_id(entry.Parents)
        or body.parent_body_id
    body.scanned        = true
end

local function display_name(body)
    if body and body.name and body.name ~= "" then return body.name end
    return UNNAMED_BODY_PLACEHOLDER
end

local function row_for_body(body, indented_name)
    return {
        ["Time"]          = (body and body.time) or "",
        ["Body"]          = indented_name or display_name(body),
        ["Type"]          = (body and body.type) or "",
        ["Distance (Ls)"] = (body and body.distance) or "",
    }
end

local function flat_rows(bodies)
    local rows = {}
    for _, body in pairs(bodies) do
        if body.scanned then table.insert(rows, row_for_body(body)) end
    end
    table.sort(rows, function(a, b) return a.Time < b.Time end)
    return rows
end

local function visible_seed_ids(bodies)
    local seeds = {}
    for id, body in pairs(bodies) do
        if body.scanned then table.insert(seeds, id) end
    end
    return seeds
end

local function hierarchical_rows(bodies)
    local rows = {}
    hierarchy.walk({
        seed_ids = visible_seed_ids(bodies),
        parent_for = function(id)
            local body = bodies[id]
            return body and body.parent_body_id
        end,
        sort_ids = function(ids)
            table.sort(ids, function(a, b)
                local ta = (bodies[a] and bodies[a].time) or ""
                local tb = (bodies[b] and bodies[b].time) or ""
                if ta == tb then return a < b end
                return ta < tb
            end)
        end,
        visit = function(id, depth)
            local body = bodies[id]
            local raw_name = display_name(body)
            local row = row_for_body(body, hierarchy.indent_prefix(depth) .. raw_name)
            row._depth = depth
            row._node_id = "body_" .. tostring(id)
            row._raw = { Body = raw_name }
            table.insert(rows, row)
        end,
    })
    return rows
end

local function rebuild_grid(plugin)
    if plugin.group_by_body then
        plugin.grid.rows = hierarchical_rows(plugin._bodies)
    else
        plugin.grid.rows = flat_rows(plugin._bodies)
    end
end

local function reset_bodies(plugin)
    plugin._bodies = {}
    rebuild_grid(plugin)
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
    rebuild_grid(plugin)
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
    Scan    = on_scan,
    FSDJump = on_fsd_jump,
}

function Plugin:load(core)
    core_ref = core
end

function Plugin:journal_event(entry)
    if not entry or not entry.event then return end
    local handler = EVENT_HANDLERS[entry.event]
    if not handler then return end
    handler(self, entry)
end

function Plugin:status_change(_)
end

function Plugin:set_grouping(is_enabled)
    self.group_by_body = is_enabled and true or false
    rebuild_grid(self)
end

return Plugin
