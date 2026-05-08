-- Headless test runner for the LÖVE port. Run with plain Lua:
--   lua tests/run.lua
-- (works under Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT). It stubs the bits of
-- love.* that pure-Lua modules touch on import so the runner needs no LÖVE
-- runtime; tests that genuinely require love.graphics/audio are excluded.

package.path = "?.lua;?/init.lua;" .. package.path

-- love stub: just enough surface for settings.lua not to blow up when loaded.
_G.love = {
    filesystem = {
        getInfo = function() return nil end,
        read = function() return nil end,
        write = function() end,
        getSaveDirectory = function() return "/tmp/observatory-test-save" end,
        createDirectory = function() end,
        getDirectoryItems = function() return {} end,
    },
    system = { getOS = function() return "Linux" end },
    timer = { getTime = function() return 0 end },
}

local total, failures = 0, 0
local function eq(a, b, msg)
    total = total + 1
    if a ~= b then
        failures = failures + 1
        print(string.format("FAIL: %s\n  expected: %s\n  got:      %s",
            msg or "(no message)", tostring(b), tostring(a)))
    end
end
local function truthy(v, msg)
    total = total + 1
    if not v then
        failures = failures + 1
        print(string.format("FAIL: %s (got %s)", msg or "(no message)", tostring(v)))
    end
end

-- paths.join ---------------------------------------------------------------
do
    local paths = require("observatory.paths")
    -- We can't predict the host SEP, so test the known properties.
    local joined = paths.join("a", "b", "c")
    truthy(joined:find("a"), "join keeps first component")
    truthy(joined:find("b"), "join keeps middle component")
    truthy(joined:find("c"), "join keeps last component")
    eq(paths.join(""), "", "join of single empty is empty")
    eq(paths.join("a", ""), "a", "trailing empty is dropped")
    eq(paths.join("", "b"), "b", "leading empty is dropped")
    -- A trailing slash on the prefix should not produce a double separator.
    local with_slash = paths.join("a/", "b")
    eq(with_slash, "a/b", "trailing / not duplicated")
    local with_back = paths.join("a\\", "b")
    eq(with_back, "a\\b", "trailing \\ not duplicated")
end

-- journal_reader ----------------------------------------------------------
do
    local jr = require("observatory.journal_reader")
    eq(jr.get_event_type(""), "InvalidJson", "empty line => InvalidJson")
    eq(jr.get_event_type('{"timestamp":"t","event":"FSDJump"}'), "FSDJump",
        "extracts FSDJump event")
    -- Bad JSON: regex fast-path still matches the event field even when the
    -- rest of the document is malformed.
    eq(jr.get_event_type('{"event":"Scan",broken'), "Scan",
        "regex fast-path on partial line")

    local entry = jr.deserialize('{"timestamp":"2024-01-01T00:00:00Z","event":"FSDJump","StarSystem":"Sol"}')
    eq(entry.event, "FSDJump", "deserialize event")
    eq(entry.StarSystem, "Sol", "deserialize field")
    truthy(entry.Json, "deserialize preserves raw line")

    local bad = jr.deserialize('{"event":"Scan","RotationPeriod":inf,"BodyName":"X"}')
    eq(bad.event, "Scan", "RotationPeriod:inf workaround keeps event")
    eq(bad.BodyName, "X", "RotationPeriod:inf workaround preserves BodyName")

    local invalid = jr.deserialize('{"timestamp":"t","event":"Foo",broken')
    eq(invalid.event, "InvalidJson", "broken line => InvalidJson")
    eq(invalid.timestamp, "t", "broken line keeps timestamp")
    eq(invalid.OriginalEvent, "Foo", "broken line keeps OriginalEvent")
end

-- export_handler ----------------------------------------------------------
do
    local export_handler = require("observatory.export_handler")
    local plugin = { id = "p", name = "P", short_name = "P" }
    local grid = {
        columns = { "A", "B" },
        rows = {
            { A = "x",      B = "y" },
            { A = "tab\tx", B = "line\nbreak" },
        },
    }
    local out = "/tmp/observatory-test-export.csv"
    os.remove(out)
    local ok, err = export_handler.export_csv(plugin, grid, out)
    truthy(ok, "export_csv ok: " .. tostring(err))
    local f = assert(io.open(out, "rb"))
    local content = f:read("*a")
    f:close()
    eq(content, "A\tB\nx\ty\ntab x\tline break\n",
        "tabs/newlines escaped in fields")
    os.remove(out)
end

-- log_monitor bit flags ---------------------------------------------------
do
    local log_monitor = require("observatory.log_monitor")
    -- Sanity: STATE constants stay the same single-bit values.
    eq(log_monitor.STATE.Idle, 0, "Idle")
    eq(log_monitor.STATE.Realtime, 1, "Realtime")
    eq(log_monitor.STATE.Batch, 2, "Batch")
    eq(log_monitor.STATE.PreRead, 4, "PreRead")
end

-- evaluator: body_value ---------------------------------------------------
do
    local body_value = require("plugins.evaluator.body_value")
    local constants = require("plugins.evaluator.constants")
    local FD = constants.FIRST_DISCOVERY_MULTIPLIER
    local MAP = constants.MAPPING_MULTIPLIER

    local body = {
        is_star = false, body_type = "Earthlike body",
        terraformable = false,
        was_discovered = true, was_mapped = false,
    }
    body_value.compute(body)
    eq(body.current_value, 268000, "ELW current value (already discovered)")
    eq(body.potential_max, math.floor(268000 * MAP),
        "ELW potential max (already discovered, not mapped)")

    body = {
        is_star = false, body_type = "Earthlike body",
        terraformable = true,
        was_discovered = false, was_mapped = false,
    }
    body_value.compute(body)
    eq(body.current_value, math.floor((268000 + 132000) * FD),
        "ELW terraformable first-discovery current value")
    eq(body.potential_max,
        math.floor(math.floor((268000 + 132000) * MAP) * FD),
        "ELW terraformable FD+FM potential max")

    body = {
        is_star = true, body_type = "O",
        was_discovered = true,
    }
    body_value.compute(body)
    eq(body.current_value, 3500, "Star O current value")
    eq(body.potential_max, 3500, "Star potential equals current")
end

-- evaluator: handlers dispatch + notification dedup -----------------------
do
    local evaluator_state = require("plugins.evaluator.state")
    local evaluator_handlers = require("plugins.evaluator.handlers")

    evaluator_state.reset()
    local notified = {}
    evaluator_handlers.set_notifier(function(args) table.insert(notified, args) end)
    evaluator_handlers.set_on_change(function() end)

    local settings = {
        minimum_body_value          = 0,
        minimum_mapping_value       = 200000,
        max_distance_elw            = 100000,
        max_distance_ww             = 100000,
        max_distance_aw             = 100000,
        max_distance_atmospheric    = 50000,
        max_distance_other          = 25000,
        notify_on_high_value        = true,
        minimum_high_value_notify   = 500000,
    }

    evaluator_handlers.dispatch({
        event = "FSDJump", SystemAddress = 1, StarSystem = "Test",
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 1, BodyID = 2, BodyName = "Test A 2",
        PlanetClass = "Earthlike body", DistanceFromArrivalLS = 500,
        TerraformState = "Terraformable", SurfaceGravity = 9.8,
        WasDiscovered = false, WasMapped = false,
    }, settings)
    eq(#notified, 1, "ELW FD scan notifies once")

    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 1, BodyID = 2, BodyName = "Test A 2",
        PlanetClass = "Earthlike body", DistanceFromArrivalLS = 500,
        WasDiscovered = false, WasMapped = false,
    }, settings)
    eq(#notified, 1, "second Scan on same body does not re-notify")

    evaluator_handlers.dispatch({
        event = "SAASignalsFound", SystemAddress = 1, BodyID = 2,
        BodyName = "Test A 2", Signals = {},
    }, settings)
    eq(#notified, 1, "SAASignalsFound does not re-notify when already notified")

    local body = evaluator_state.bodies_in_current_system()[2]
    truthy(body.was_mapped, "SAA marks body as mapped")
    truthy(body.worth_mapping ~= nil, "SAA re-evaluates worth_mapping")

    evaluator_handlers.dispatch({event = "LoadGame"}, settings)
    eq(evaluator_state.current_system_address(), nil,
        "LoadGame resets evaluator state")
end

-- evaluator: distance threshold via lookup table --------------------------
do
    local constants = require("plugins.evaluator.constants")
    eq(constants.MAX_DISTANCE_SETTING_BY_BODY_TYPE["Earthlike body"],
        "max_distance_elw", "ELW maps to max_distance_elw")
    eq(constants.MAX_DISTANCE_SETTING_BY_BODY_TYPE["Water world"],
        "max_distance_ww", "WW maps to max_distance_ww")
    eq(constants.MAX_DISTANCE_SETTING_BY_BODY_TYPE["Ammonia world"],
        "max_distance_aw", "AW maps to max_distance_aw")
    eq(constants.MAX_DISTANCE_SETTING_BY_BODY_TYPE["Rocky body"], nil,
        "Rocky body falls through to atmospheric/other branch")
end

-- bioinsights: handlers + grid filter -------------------------------------
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_grid = require("plugins.bioinsights.grid")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    local notified = {}
    bi_handlers.set_notifier(function(args) table.insert(notified, args) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value   = true,
        notify_on_new_codex    = true,
        minimum_high_value     = 1000000,
        only_show_high_value   = false,
    }

    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 1, StarSystem = "Test",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 1, BodyID = 2, BodyName = "Test B 2",
        PlanetClass = "High metal content body", DistanceFromArrivalLS = 100,
    }, settings)
    bi_handlers.dispatch({
        event = "SAASignalsFound", SystemAddress = 1, BodyID = 2,
        BodyName = "Test B 2",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
        Genuses = {{ Genus_Localised = "Bacterium" }},
    }, settings)
    truthy(#notified >= 1, "bioinsights notifies on high-value genus")

    bi_handlers.dispatch({
        event = "ScanOrganic", SystemAddress = 1, Body = 2,
        ScanType = "Analyse",
        Species_Localised = "Bacterium Aurasus",
    }, settings)

    local target = { columns = bi_constants.GRID_COLUMNS, rows = {} }
    bi_grid.rebuild(target, settings)
    truthy(#target.rows >= 1, "grid populated after bio scans")
    truthy(target.rows[1]["Value"]:find("cr"), "value cell contains cr suffix")
    truthy(not target.rows[1]["Value"]:find(bi_constants.UNKNOWN_TEXT .. " cr"),
        "no '— cr' artifact in value cell")

    settings.only_show_high_value = true
    settings.minimum_high_value = 50000000
    bi_grid.rebuild(target, settings)
    eq(#target.rows, 0, "only_show_high_value with high threshold filters all")

    settings.minimum_high_value = 1
    bi_grid.rebuild(target, settings)
    truthy(#target.rows >= 1, "only_show_high_value with low threshold keeps rows")

    bi_handlers.dispatch({event = "LoadGame"}, settings)
    bi_grid.rebuild(target, settings)
    eq(#target.rows, 0, "LoadGame resets bioinsights state")
end

print(string.format("\n%d tests, %d failures", total, failures))
os.exit(failures == 0 and 0 or 1)
