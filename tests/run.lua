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
    local FD  = constants.FIRST_DISCOVERY_MULTIPLIER
    local MAP = constants.MAPPING_MULTIPLIER
    local FM  = constants.FIRST_MAPPER_MULTIPLIER
    local EFF = constants.EFFICIENCY_MULTIPLIER
    local ODY = constants.ODYSSEY_MAPPING_MULTIPLIER

    local function mass_factor(m)
        return 1 + (constants.MASS_FACTOR_NUMERATOR
            * (m ^ constants.MASS_EXPONENT))
            / constants.MASS_FACTOR_DENOMINATOR
    end

    local function planet_base(class_entry, terraformable, mass)
        local k = class_entry.k + (terraformable and class_entry.kt or 0)
        return k * mass_factor(mass)
    end

    local elw_entry = constants.PLANET_K_BY_TYPE["Earthlike body"]
    local hmc_entry = constants.PLANET_K_BY_TYPE["High metal content body"]

    local body = {
        is_star = false, body_type = "Earthlike body",
        terraformable = false,
        was_discovered = true, was_mapped = false,
        mass_em = constants.DEFAULT_MASS_EM,
    }
    body_value.compute(body)
    local elw_default_base = planet_base(elw_entry, false, constants.DEFAULT_MASS_EM)
    eq(body.current_value, math.floor(elw_default_base),
        "ELW default-mass current value (already discovered)")
    eq(body.potential_max,
        math.floor(elw_default_base * MAP * EFF * ODY * FM),
        "ELW default-mass potential max (mapped, first mapper, efficient)")

    body = {
        is_star = false, body_type = "Earthlike body",
        terraformable = true,
        was_discovered = false, was_mapped = false,
        mass_em = constants.DEFAULT_MASS_EM,
    }
    body_value.compute(body)
    eq(body.current_value, math.floor(elw_default_base * FD),
        "ELW first-discovery current value")
    eq(body.potential_max,
        math.floor(elw_default_base * MAP * EFF * ODY * FM * FD),
        "ELW FD+FM potential max")

    body = {
        is_star = false, body_type = "High metal content body",
        terraformable = true,
        was_discovered = true, was_mapped = false,
        mass_em = 0.8,
    }
    body_value.compute(body)
    local hmc_b22_base = planet_base(hmc_entry, true, 0.8)
    eq(body.potential_max,
        math.floor(hmc_b22_base * MAP * EFF * ODY * FM),
        "HMC terraformable mass=0.8 potential max with Odyssey bonus")
    truthy(body.potential_max > 1000000 and body.potential_max < 1050000,
        "HMC TF mass=0.8 lands near 1.02M cr (b22-1 4 regression)")

    body = {
        is_star = true, body_type = "O",
        was_discovered = true,
    }
    body_value.compute(body)
    eq(body.current_value, constants.STAR_K_BY_TYPE.O,
        "Star O current value uses canonical k coefficient")
    eq(body.potential_max, body.current_value,
        "Star potential equals current")
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
    truthy(body.mapped_by_player, "SAA marks body as mapped by the player")
    truthy(not body.was_mapped,
        "SAA does not flip the journal-derived was_mapped flag")
    truthy(body.worth_mapping ~= nil, "SAA re-evaluates worth_mapping")

    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 1, BodyID = 3, BodyName = "Test A 3",
        PlanetClass = "High metal content body", DistanceFromArrivalLS = 800,
        WasDiscovered = false, WasMapped = false,
    }, settings)
    evaluator_handlers.dispatch({
        event = "SAAScanComplete", SystemAddress = 1, BodyID = 3,
        BodyName = "Test A 3", ProbesUsed = 4, EfficiencyTarget = 6,
    }, settings)
    local silent_mapped = evaluator_state.bodies_in_current_system()[3]
    truthy(silent_mapped.mapped_by_player,
        "SAAScanComplete marks signal-less body as mapped by the player")

    local prev_address = evaluator_state.current_system_address()
    evaluator_handlers.dispatch({event = "LoadGame"}, settings)
    eq(evaluator_state.current_system_address(), prev_address,
        "LoadGame keeps accumulated evaluator state across sessions")
end

-- evaluator: hierarchical grid grouping -----------------------------------
do
    local evaluator_state = require("plugins.evaluator.state")
    local evaluator_handlers = require("plugins.evaluator.handlers")
    local evaluator_grid = require("plugins.evaluator.grid")
    local evaluator_constants = require("plugins.evaluator.constants")

    evaluator_state.reset()
    evaluator_handlers.set_notifier(function(_) end)
    evaluator_handlers.set_on_change(function() end)

    local settings = {
        minimum_body_value          = 100000,
        minimum_mapping_value       = 200000,
        max_distance_elw            = 100000,
        max_distance_ww             = 100000,
        max_distance_aw             = 100000,
        max_distance_atmospheric    = 50000,
        max_distance_other          = 25000,
        notify_on_high_value        = false,
        minimum_high_value_notify   = 500000,
    }

    evaluator_handlers.dispatch({
        event = "FSDJump", SystemAddress = 7, StarSystem = "Hier",
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 7, BodyID = 0,
        BodyName = "Hier", StarType = "G",
        DistanceFromArrivalLS = 0, WasDiscovered = true,
        Parents = {},
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 7, BodyID = 1,
        BodyName = "Hier 1", PlanetClass = "Rocky body",
        DistanceFromArrivalLS = 100,
        Parents = {{ Star = 0 }},
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 7, BodyID = 2,
        BodyName = "Hier 1 a", PlanetClass = "Earthlike body",
        DistanceFromArrivalLS = 110,
        TerraformState = "Terraformable",
        Parents = {{ Planet = 1 }, { Star = 0 }},
    }, settings)

    local target = {
        columns = evaluator_constants.GRID_COLUMNS,
        rows = {},
    }
    evaluator_grid.rebuild(target, settings, { group_by_body = true })

    eq(#target.rows, 3, "hierarchical rebuild surfaces ELW and its ancestors")
    eq(target.rows[1]["Body"], "Hier", "root star has no indent")
    truthy(target.rows[2]["Body"]:find("  > Hier 1", 1, true),
        "rocky parent carried as ancestor with branch glyph")
    truthy(target.rows[3]["Body"]:find("    > Hier 1 a", 1, true),
        "ELW grandchild indented one level deeper")

    target.rows = {}
    evaluator_grid.rebuild(target, settings)
    eq(#target.rows, 1, "flat rebuild filters out low-value bodies")
    eq(target.rows[1]["Body"], "Hier 1 a", "only ELW remains in flat view")
end

-- bioinsights: hierarchical grid grouping ---------------------------------
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_grid = require("plugins.bioinsights.grid")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    bi_handlers.set_notifier(function(_) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value   = false,
        notify_on_new_codex    = false,
        minimum_high_value     = 0,
        only_show_high_value   = false,
    }

    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 11, StarSystem = "Bio",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 11, BodyID = 0,
        BodyName = "Bio", StarType = "G",
        DistanceFromArrivalLS = 0,
        Parents = {},
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 11, BodyID = 1,
        BodyName = "Bio 1", PlanetClass = "High metal content body",
        DistanceFromArrivalLS = 50,
        Parents = {{ Star = 0 }},
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 11, BodyID = 2,
        BodyName = "Bio 1 a", PlanetClass = "Rocky body",
        DistanceFromArrivalLS = 60,
        AtmosphereType = "Ammonia",
        SurfaceGravity = 1.5,
        SurfaceTemperature = 165.0,
        SurfacePressure = 1000.0,
        Parents = {{ Planet = 1 }, { Star = 0 }},
    }, settings)
    bi_handlers.dispatch({
        event = "SAASignalsFound", SystemAddress = 11, BodyID = 2,
        BodyName = "Bio 1 a",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
        Genuses = {{ Genus_Localised = "Frutexa" }},
    }, settings)

    local target = { columns = bi_constants.GRID_COLUMNS, rows = {} }
    bi_grid.rebuild(target, settings, { group_by_body = true })

    truthy(#target.rows >= 4,
        "hierarchical surfaces ancestors + at least one Frutexa species")
    eq(target.rows[1]["Body"], "Bio", "star ancestor at depth 0")
    truthy(target.rows[2]["Body"]:find("  > Bio 1", 1, true),
        "intermediate planet carries branch glyph at depth 1")
    truthy(target.rows[3]["Body"]:find("    > Bio 1 a", 1, true),
        "bio body header indented one level deeper")
    eq(target.rows[3]["Genus"], bi_constants.UNKNOWN_TEXT,
        "body header row carries no genus")
    truthy(target.rows[4]["_depth"] == 3,
        "genus child sits one level below the body header")
    eq(target.rows[4]["Genus"], "Frutexa",
        "genus sub-row holds the bio data")
    eq(target.rows[4]["Status"], bi_constants.STATUS_LABEL.predicted,
        "first surfaced Frutexa species is predicted (DSS-mapped, excluded ones hidden)")

    target.rows = {}
    bi_grid.rebuild(target, settings)
    truthy(#target.rows >= 1,
        "flat rebuild emits at least one row for the matching bio body")
    eq(target.rows[1]["Body"], "Bio 1 a", "first row carries the bio body name")
end

-- evaluator: hierarchical rows carry sort metadata ------------------------
do
    local evaluator_state = require("plugins.evaluator.state")
    local evaluator_handlers = require("plugins.evaluator.handlers")
    local evaluator_grid = require("plugins.evaluator.grid")
    local evaluator_constants = require("plugins.evaluator.constants")

    evaluator_state.reset()
    evaluator_handlers.set_notifier(function(_) end)
    evaluator_handlers.set_on_change(function() end)

    local settings = {
        minimum_body_value          = 0,
        minimum_mapping_value       = 200000,
        max_distance_elw            = 100000,
        max_distance_ww             = 100000,
        max_distance_aw             = 100000,
        max_distance_atmospheric    = 50000,
        max_distance_other          = 25000,
        notify_on_high_value        = false,
        minimum_high_value_notify   = 500000,
    }

    evaluator_handlers.dispatch({
        event = "FSDJump", SystemAddress = 13, StarSystem = "Sort",
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 13, BodyID = 0,
        BodyName = "Sort", StarType = "G", DistanceFromArrivalLS = 0,
        Parents = {},
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 13, BodyID = 1,
        BodyName = "Sort A", PlanetClass = "Rocky body",
        DistanceFromArrivalLS = 200,
        Parents = {{ Star = 0 }},
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 13, BodyID = 2,
        BodyName = "Sort B", PlanetClass = "Rocky body",
        DistanceFromArrivalLS = 100,
        Parents = {{ Star = 0 }},
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 13, BodyID = 3,
        BodyName = "Sort A 1", PlanetClass = "Icy body",
        DistanceFromArrivalLS = 250,
        Parents = {{ Planet = 1 }, { Star = 0 }},
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 13, BodyID = 4,
        BodyName = "Sort A 2", PlanetClass = "Icy body",
        DistanceFromArrivalLS = 220,
        Parents = {{ Planet = 1 }, { Star = 0 }},
    }, settings)

    local target = {
        columns = evaluator_constants.GRID_COLUMNS,
        rows = {},
    }
    evaluator_grid.rebuild(target, settings, { group_by_body = true })

    truthy(target.rows[1]._depth == 0,
        "root row carries depth 0 metadata")
    truthy(target.rows[1]._raw and target.rows[1]._raw["Body"] == "Sort",
        "root row carries raw body name for sort")
    truthy(target.rows[1]._node_id == "body_0",
        "root row carries node_id keyed on body id")
    truthy(target.rows[2]._depth == 1,
        "first child row carries depth 1 metadata")
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

    local rows_before_load = #target.rows
    bi_handlers.dispatch({event = "LoadGame"}, settings)
    bi_grid.rebuild(target, settings)
    eq(#target.rows, rows_before_load,
        "LoadGame does not wipe accumulated bioinsights state")
end

-- bioinsights: bodies from prior systems remain visible after a fresh jump --
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_grid = require("plugins.bioinsights.grid")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    bi_handlers.set_notifier(function(_) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value   = false,
        notify_on_new_codex    = false,
        minimum_high_value     = 0,
        only_show_high_value   = false,
    }

    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 100, StarSystem = "Alpha",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 100, BodyID = 0,
        BodyName = "Alpha", StarType = "G", DistanceFromArrivalLS = 0,
        Parents = {},
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 100, BodyID = 1,
        BodyName = "Alpha 1", PlanetClass = "Rocky body",
        AtmosphereType = "Ammonia",
        SurfaceGravity = 1.5, SurfaceTemperature = 165.0,
        SurfacePressure = 1000.0,
        DistanceFromArrivalLS = 100,
        Parents = {{ Star = 0 }},
    }, settings)
    bi_handlers.dispatch({
        event = "SAASignalsFound", SystemAddress = 100, BodyID = 1,
        BodyName = "Alpha 1",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
        Genuses = {{ Genus_Localised = "Bacterium" }},
    }, settings)

    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 200, StarSystem = "Beta",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 200, BodyID = 0,
        BodyName = "Beta", StarType = "G", DistanceFromArrivalLS = 0,
        Parents = {},
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 200, BodyID = 1,
        BodyName = "Beta 1", PlanetClass = "Rocky body",
        AtmosphereType = "Ammonia",
        SurfaceGravity = 1.5, SurfaceTemperature = 165.0,
        SurfacePressure = 1000.0,
        DistanceFromArrivalLS = 100,
        Parents = {{ Star = 0 }},
    }, settings)
    bi_handlers.dispatch({
        event = "SAASignalsFound", SystemAddress = 200, BodyID = 1,
        BodyName = "Beta 1",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
        Genuses = {{ Genus_Localised = "Frutexa" }},
    }, settings)

    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 300, StarSystem = "Gamma",
    }, settings)

    local target = { columns = bi_constants.GRID_COLUMNS, rows = {} }
    bi_grid.rebuild(target, settings)
    truthy(#target.rows >= 2,
        "bioinsights surfaces matching species across multiple systems")
    local body_labels = {}
    for _, row in ipairs(target.rows) do
        if row["Body"] ~= "" then body_labels[row["Body"]] = true end
    end
    truthy(body_labels["Alpha 1"], "Alpha 1 surfaced as a body label")
    truthy(body_labels["Beta 1"], "Beta 1 surfaced as a body label")
end

-- evaluator: high-value bodies from prior systems survive an empty jump ----
do
    local evaluator_state = require("plugins.evaluator.state")
    local evaluator_handlers = require("plugins.evaluator.handlers")
    local evaluator_grid = require("plugins.evaluator.grid")
    local evaluator_constants = require("plugins.evaluator.constants")

    evaluator_state.reset()
    evaluator_handlers.set_notifier(function(_) end)
    evaluator_handlers.set_on_change(function() end)

    local settings = {
        minimum_body_value          = 0,
        minimum_mapping_value       = 200000,
        max_distance_elw            = 100000,
        max_distance_ww             = 100000,
        max_distance_aw             = 100000,
        max_distance_atmospheric    = 50000,
        max_distance_other          = 25000,
        notify_on_high_value        = false,
        minimum_high_value_notify   = 500000,
    }

    evaluator_handlers.dispatch({
        event = "FSDJump", SystemAddress = 100, StarSystem = "Alpha",
    }, settings)
    evaluator_handlers.dispatch({
        event = "Scan", SystemAddress = 100, BodyID = 1,
        BodyName = "Alpha 1", PlanetClass = "Earthlike body",
        DistanceFromArrivalLS = 500, TerraformState = "",
        SurfaceGravity = 9.8, WasDiscovered = true,
    }, settings)
    evaluator_handlers.dispatch({
        event = "FSDJump", SystemAddress = 200, StarSystem = "Empty",
    }, settings)

    local target = {
        columns = evaluator_constants.GRID_COLUMNS,
        rows = {},
    }
    evaluator_grid.rebuild(target, settings)
    eq(#target.rows, 1, "evaluator keeps Alpha's ELW after jumping to Empty")
    eq(target.rows[1]["Body"], "Alpha 1",
        "evaluator row identifies Alpha's ELW")
end

-- bioinsights: data accumulates across journal files split by LoadGame ----
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_grid = require("plugins.bioinsights.grid")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    bi_handlers.set_notifier(function(_) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value   = false,
        notify_on_new_codex    = false,
        minimum_high_value     = 0,
        only_show_high_value   = false,
    }

    bi_handlers.dispatch({event = "LoadGame"}, settings)
    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 500, StarSystem = "Session1",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 500, BodyID = 1,
        BodyName = "Session1 1", PlanetClass = "Icy body",
        AtmosphereType = "Argon",
        SurfaceGravity = 2.0,
        DistanceFromArrivalLS = 10,
    }, settings)
    bi_handlers.dispatch({
        event = "SAASignalsFound", SystemAddress = 500, BodyID = 1,
        BodyName = "Session1 1",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
        Genuses = {{ Genus_Localised = "Bacterium" }},
    }, settings)

    bi_handlers.dispatch({event = "LoadGame"}, settings)
    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 600, StarSystem = "Session2",
    }, settings)

    local target = { columns = bi_constants.GRID_COLUMNS, rows = {} }
    bi_grid.rebuild(target, settings)
    truthy(#target.rows >= 1,
        "Session1 bio candidates survive LoadGame on next journal")
end

-- bioinsights: ScanOrganic confirms the species and excludes siblings -----
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_grid = require("plugins.bioinsights.grid")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    bi_handlers.set_notifier(function(_) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value   = false,
        notify_on_new_codex    = false,
        minimum_high_value     = 0,
        only_show_high_value   = false,
    }

    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 700, StarSystem = "Confirm",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 700, BodyID = 1,
        BodyName = "Confirm 1", PlanetClass = "Icy body",
        DistanceFromArrivalLS = 100,
    }, settings)
    bi_handlers.dispatch({
        event = "SAASignalsFound", SystemAddress = 700, BodyID = 1,
        BodyName = "Confirm 1",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
        Genuses = {{ Genus_Localised = "Bacterium" }},
    }, settings)
    bi_handlers.dispatch({
        event = "ScanOrganic", SystemAddress = 700, Body = 1,
        ScanType = "Analyse",
        Genus_Localised = "Bacterium",
        Species_Localised = "Bacterium Acies",
        Variant_Localised = "Bacterium Acies - Cobalt",
    }, settings)

    local target = { columns = bi_constants.GRID_COLUMNS, rows = {} }
    bi_grid.rebuild(target, settings)
    local confirmed_rows, pending_rows = 0, 0
    local confirmed_species
    for _, row in ipairs(target.rows) do
        if row["Status"] == bi_constants.STATUS_LABEL.confirmed then
            confirmed_rows = confirmed_rows + 1
            confirmed_species = row["Species"]
        elseif row["Status"] == bi_constants.STATUS_LABEL.pending then
            pending_rows = pending_rows + 1
        end
    end
    eq(confirmed_rows, 1, "exactly one species is confirmed for the genus")
    eq(confirmed_species, "Bacterium Acies",
        "confirmed species matches ScanOrganic payload")
    eq(pending_rows, 0,
        "no sibling species remains pending after the genus is confirmed")
end

-- bioinsights: codex filters Bacterium by atmosphere -----------------------
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_grid = require("plugins.bioinsights.grid")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    bi_handlers.set_notifier(function(_) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value   = false,
        notify_on_new_codex    = false,
        minimum_high_value     = 0,
        only_show_high_value   = false,
    }

    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 800, StarSystem = "Codex",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 800, BodyID = 1,
        BodyName = "Codex 1", PlanetClass = "Icy body",
        AtmosphereType = "Argon", DistanceFromArrivalLS = 100,
    }, settings)
    bi_handlers.dispatch({
        event = "SAASignalsFound", SystemAddress = 800, BodyID = 1,
        BodyName = "Codex 1",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
        Genuses = {{ Genus_Localised = "Bacterium" }},
    }, settings)

    local target = { columns = bi_constants.GRID_COLUMNS, rows = {} }
    bi_grid.rebuild(target, settings)

    local visible_species = {}
    for _, row in ipairs(target.rows) do
        local s = row["Status"]
        if s == bi_constants.STATUS_LABEL.pending
            or s == bi_constants.STATUS_LABEL.predicted then
            visible_species[row["Species"]] = true
        end
    end
    truthy(visible_species["Bacterium Vesicula"],
        "Argon atmosphere keeps Bacterium Vesicula predicted")
    truthy(not visible_species["Bacterium Aurasus"],
        "Argon atmosphere excludes Bacterium Aurasus (CO2)")
    truthy(not visible_species["Bacterium Acies"],
        "Argon atmosphere excludes Bacterium Acies (Neon)")
    truthy(not visible_species["Bacterium Tela"],
        "Non-volcanic body excludes Bacterium Tela")
end

-- bioinsights: codex enforces Crystalline Shards distance/star/bodies rules --
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    bi_handlers.set_notifier(function(_) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value   = false,
        notify_on_new_codex    = false,
        minimum_high_value     = 0,
        only_show_high_value   = false,
    }

    local SYS = 1234
    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = SYS, StarSystem = "Shards Test",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = SYS, BodyID = 0,
        BodyName = "Shards Test A", StarType = "A",
        DistanceFromArrivalLS = 0, Parents = {},
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = SYS, BodyID = 5,
        BodyName = "Shards Test 5", PlanetClass = "Earthlike body",
        AtmosphereType = "", DistanceFromArrivalLS = 800,
        Parents = {{ Star = 0 }},
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = SYS, BodyID = 9,
        BodyName = "Shards Test 9", PlanetClass = "Icy body",
        AtmosphereType = "Argon", SurfaceGravity = 0.95,
        SurfaceTemperature = 50.0, DistanceFromArrivalLS = 1500,
        Parents = {{ Star = 0 }},
    }, settings)
    bi_handlers.dispatch({
        event = "FSSBodySignals", SystemAddress = SYS, BodyID = 9,
        BodyName = "Shards Test 9",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
    }, settings)

    bi_handlers.dispatch({
        event = "Scan", SystemAddress = SYS, BodyID = 12,
        BodyName = "Shards Test 12", PlanetClass = "Icy body",
        AtmosphereType = "Argon", SurfaceGravity = 0.95,
        SurfaceTemperature = 50.0, DistanceFromArrivalLS = 14000,
        Parents = {{ Star = 0 }},
    }, settings)
    bi_handlers.dispatch({
        event = "FSSBodySignals", SystemAddress = SYS, BodyID = 12,
        BodyName = "Shards Test 12",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
    }, settings)

    local close_body = bi_state.bodies_in_current_system()[9]
    local far_body   = bi_state.bodies_in_current_system()[12]

    truthy(close_body and not close_body.genus_entries["Crystalline"],
        "Crystalline genus is dropped on body inside 12000 Ls")

    local far_entry = far_body and far_body.genus_entries["Crystalline"]
    truthy(far_entry and far_entry.species_states["Crystalline Shards"]
        ~= bi_state.SPECIES_STATUS.EXCLUDED,
        "Crystalline Shards stays predicted on body beyond 12000 Ls in qualifying system")
end

-- bioinsights: body value tightens as species are confirmed/excluded -------
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_grid = require("plugins.bioinsights.grid")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    bi_handlers.set_notifier(function(_) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value   = false,
        notify_on_new_codex    = false,
        minimum_high_value     = 0,
        only_show_high_value   = false,
    }

    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = 900, StarSystem = "Range",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = 900, BodyID = 1,
        BodyName = "Range 1", PlanetClass = "Icy body",
        AtmosphereType = "Neon", DistanceFromArrivalLS = 100,
    }, settings)
    bi_handlers.dispatch({
        event = "SAASignalsFound", SystemAddress = 900, BodyID = 1,
        BodyName = "Range 1",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 1 }},
        Genuses = {{ Genus_Localised = "Bacterium" }},
    }, settings)

    local target = { columns = bi_constants.GRID_COLUMNS, rows = {} }
    bi_grid.rebuild(target, settings)
    local first_body_value = target.rows[1]["Body Value"]
    truthy(first_body_value:find("cr"),
        "body value column is populated before ScanOrganic")

    bi_handlers.dispatch({
        event = "ScanOrganic", SystemAddress = 900, Body = 1,
        ScanType = "Analyse",
        Species_Localised = "Bacterium Acies",
        Variant_Localised = "Bacterium Acies - Cobalt",
    }, settings)

    target.rows = {}
    bi_grid.rebuild(target, settings)
    eq(target.rows[1]["Body Value"], "1.0M cr",
        "body value collapses to single confirmed species value")
end

-- bioinsights: reproduce tmp.png reference grid -----------------------------
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_grid = require("plugins.bioinsights.grid")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    bi_handlers.set_notifier(function(_) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value   = false,
        notify_on_new_codex    = false,
        minimum_high_value     = 0,
        only_show_high_value   = false,
    }

    local function fsd(addr, name)
        bi_handlers.dispatch({
            event = "FSDJump", SystemAddress = addr, StarSystem = name,
        }, settings)
    end

    local function scan_star(addr, body_id, body_name, star_type)
        bi_handlers.dispatch({
            event = "Scan", SystemAddress = addr, BodyID = body_id,
            BodyName = body_name, StarType = star_type,
            DistanceFromArrivalLS = 0,
            Parents = {},
        }, settings)
    end

    local function build_materials(names)
        if not names then return nil end
        local result = {}
        for _, name in ipairs(names) do
            table.insert(result, { Name = name, Percent = 1.0 })
        end
        return result
    end

    local function scan_body(opts)
        bi_handlers.dispatch({
            event = "Scan", SystemAddress = opts.system, BodyID = opts.id,
            BodyName = opts.name, PlanetClass = opts.planet_class,
            AtmosphereType = opts.atmosphere or "",
            SurfaceGravity = opts.gravity_ms2 or 0,
            SurfaceTemperature = opts.temperature_k or 0,
            SurfacePressure = opts.pressure_pa or 0,
            Volcanism = opts.volcanism or "",
            DistanceFromArrivalLS = opts.distance_ls or 0,
            Materials = build_materials(opts.materials),
            Parents = opts.parents or {{ Star = 0 }},
        }, settings)
    end

    local function saa(opts)
        local genuses = {}
        for _, label in ipairs(opts.genuses) do
            table.insert(genuses, { Genus_Localised = label })
        end
        bi_handlers.dispatch({
            event = "SAASignalsFound", SystemAddress = opts.system,
            BodyID = opts.id, BodyName = opts.name,
            Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL,
                Count = #genuses }},
            Genuses = genuses,
        }, settings)
    end

    local function scan_organic(opts)
        bi_handlers.dispatch({
            event = "ScanOrganic", SystemAddress = opts.system, Body = opts.id,
            ScanType = "Analyse",
            Species_Localised = opts.species,
            Variant_Localised = opts.variant,
        }, settings)
    end

    local SYS_VG_Q_b23_0 = 1001
    local SYS_VG_Q_b23_1 = 1011
    local SYS_QA_S_b22_1 = 1002

    fsd(SYS_VG_Q_b23_0, "Prua Dryoae VG-Q b23-0")
    scan_star(SYS_VG_Q_b23_0, 0, "Prua Dryoae VG-Q b23-0", "M")
    scan_body({
        system = SYS_VG_Q_b23_0, id = 3, name = "Prua Dryoae VG-Q b23-0 B 3",
        planet_class = "Icy body", atmosphere = "Neon",
        gravity_ms2 = 4.0, temperature_k = 30.0, pressure_pa = 500.0,
        distance_ls = 500.0,
    })
    saa({ system = SYS_VG_Q_b23_0, id = 3,
        name = "Prua Dryoae VG-Q b23-0 B 3", genuses = { "Bacterium" } })
    scan_organic({ system = SYS_VG_Q_b23_0, id = 3,
        species = "Bacterium Acies",
        variant = "Bacterium Acies - Cobalt" })

    fsd(SYS_VG_Q_b23_1, "Prua Dryoae VG-Q b23-1")
    scan_star(SYS_VG_Q_b23_1, 0, "Prua Dryoae VG-Q b23-1", "M")
    scan_body({
        system = SYS_VG_Q_b23_1, id = 6, name = "Prua Dryoae VG-Q b23-1 B 6",
        planet_class = "Icy body", atmosphere = "Neon",
        gravity_ms2 = 4.0, temperature_k = 30.0, pressure_pa = 500.0,
        distance_ls = 500.0,
    })
    saa({ system = SYS_VG_Q_b23_1, id = 6,
        name = "Prua Dryoae VG-Q b23-1 B 6", genuses = { "Bacterium" } })
    scan_organic({ system = SYS_VG_Q_b23_1, id = 6,
        species = "Bacterium Acies",
        variant = "Bacterium Acies - Lime" })

    fsd(SYS_QA_S_b22_1, "Prua Dryoae QA-S b22-1")
    scan_star(SYS_QA_S_b22_1, 0, "Prua Dryoae QA-S b22-1", "M")

    scan_body({
        system = SYS_QA_S_b22_1, id = 7, name = "Prua Dryoae QA-S b22-1 7 b",
        planet_class = "Rocky body", atmosphere = "CarbonDioxide",
        gravity_ms2 = 1.5, temperature_k = 170.0, pressure_pa = 5000.0,
        distance_ls = 500.0,
    })
    saa({ system = SYS_QA_S_b22_1, id = 7,
        name = "Prua Dryoae QA-S b22-1 7 b",
        genuses = { "Bacterium", "Frutexa", "Stratum" } })
    scan_organic({ system = SYS_QA_S_b22_1, id = 7,
        species = "Frutexa Acus",
        variant = "Frutexa Acus - Grey" })
    scan_organic({ system = SYS_QA_S_b22_1, id = 7,
        species = "Stratum Paleas",
        variant = "Stratum Paleas - Green" })

    scan_body({
        system = SYS_QA_S_b22_1, id = 8, name = "Prua Dryoae QA-S b22-1 8 g",
        planet_class = "Icy body", atmosphere = "ArgonRich",
        gravity_ms2 = 2.5, temperature_k = 90.0, pressure_pa = 2500.0,
        distance_ls = 500.0,
    })
    saa({ system = SYS_QA_S_b22_1, id = 8,
        name = "Prua Dryoae QA-S b22-1 8 g", genuses = { "Fonticulua" } })
    scan_organic({ system = SYS_QA_S_b22_1, id = 8,
        species = "Fonticulua Upupam",
        variant = "Fonticulua Upupam - Amethyst" })

    scan_body({
        system = SYS_QA_S_b22_1, id = 9, name = "Prua Dryoae QA-S b22-1 9 d",
        planet_class = "Icy body", atmosphere = "Argon",
        gravity_ms2 = 2.0, temperature_k = 65.0, pressure_pa = 600.0,
        volcanism = "minor nitrogen magma volcanism",
        materials = { "mercury", "tungsten", "technetium" },
        distance_ls = 500.0,
    })
    saa({ system = SYS_QA_S_b22_1, id = 9,
        name = "Prua Dryoae QA-S b22-1 9 d",
        genuses = { "Bacterium", "Fonticulua", "Fumerola" } })

    local target = { columns = bi_constants.GRID_COLUMNS, rows = {} }
    bi_grid.rebuild(target, settings)
    local visible = {}
    local current_body = ""
    for _, row in ipairs(target.rows) do
        if row["Body"] and row["Body"] ~= "" then
            current_body = row["Body"]
        end
        local species = row["Species"] or "?"
        visible[current_body] = visible[current_body] or {}
        visible[current_body][species] = {
            status  = row["Status"] or "?",
            variant = row["Variant"] or "",
        }
    end

    local EXPECTED_PER_BODY = {
        ["Prua Dryoae VG-Q b23-0 B 3"] = {
            { species = "Bacterium Acies",       status = "confirmed", variant = "Bacterium Acies - Cobalt" },
        },
        ["Prua Dryoae VG-Q b23-1 B 6"] = {
            { species = "Bacterium Acies",       status = "confirmed", variant = "Bacterium Acies - Lime" },
        },
        ["Prua Dryoae QA-S b22-1 7 b"] = {
            { species = "Bacterium Aurasus",     status = "predicted", variant = "Teal" },
            { species = "Frutexa Acus",          status = "confirmed", variant = "Frutexa Acus - Grey" },
            { species = "Stratum Paleas",        status = "confirmed", variant = "Stratum Paleas - Green" },
        },
        ["Prua Dryoae QA-S b22-1 8 g"] = {
            { species = "Fonticulua Upupam",     status = "confirmed", variant = "Fonticulua Upupam - Amethyst" },
        },
        ["Prua Dryoae QA-S b22-1 9 d"] = {
            { species = "Bacterium Omentum",     status = "predicted", variant = "White or Blue" },
            { species = "Bacterium Tela",        status = "predicted", variant = "Orange or Green" },
            { species = "Bacterium Vesicula",    status = "predicted", variant = "Gold" },
            { species = "Fonticulua Campestris", status = "predicted", variant = "Amethyst" },
            { species = "Fumerola Nitris",       status = "predicted", variant = "Peach or Aquamarine" },
        },
    }

    for body_name, expected_species in pairs(EXPECTED_PER_BODY) do
        local body_rows = visible[body_name] or {}
        for _, expected in ipairs(expected_species) do
            local actual = body_rows[expected.species]
            eq(actual and actual.status or nil, expected.status,
                string.format("tmp.png %s | %s should be %s",
                    body_name, expected.species, expected.status))
            if expected.variant then
                eq(actual and actual.variant or nil, expected.variant,
                    string.format("tmp.png %s | %s variant should be %s",
                        body_name, expected.species, expected.variant))
            end
        end
        local expected_set = {}
        for _, e in ipairs(expected_species) do expected_set[e.species] = true end
        for species, _ in pairs(body_rows) do
            truthy(expected_set[species],
                string.format("tmp.png %s | %s appears in grid but is not in screenshot",
                    body_name, species))
        end
    end
end

-- bioinsights: FSS-only body (no SAA) still enumerates candidate species ----
do
    local bi_state = require("plugins.bioinsights.state")
    local bi_handlers = require("plugins.bioinsights.handlers")
    local bi_grid = require("plugins.bioinsights.grid")
    local bi_constants = require("plugins.bioinsights.constants")

    bi_state.reset()
    bi_handlers.set_notifier(function(_) end)
    bi_handlers.set_on_change(function() end)

    local settings = {
        notify_on_high_value = false, notify_on_new_codex = false,
        minimum_high_value = 0, only_show_high_value = false,
    }

    local SYS = 9001
    bi_handlers.dispatch({
        event = "FSDJump", SystemAddress = SYS, StarSystem = "Test System",
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = SYS, BodyID = 1,
        BodyName = "Test Body 1", StarType = "M",
        DistanceFromArrivalLS = 0, Parents = {},
    }, settings)
    bi_handlers.dispatch({
        event = "Scan", SystemAddress = SYS, BodyID = 9,
        BodyName = "Test Body 1 9 d", PlanetClass = "Icy body",
        AtmosphereType = "Argon",
        SurfaceGravity = 0.96, SurfaceTemperature = 57.0, SurfacePressure = 463.0,
        Volcanism = "minor nitrogen magma volcanism",
        DistanceFromArrivalLS = 1611.0,
        Materials = { { Name = "mercury", Percent = 0.5 },
                      { Name = "tungsten", Percent = 0.7 },
                      { Name = "technetium", Percent = 0.4 } },
        Parents = {{ Star = 1 }},
    }, settings)
    bi_handlers.dispatch({
        event = "FSSBodySignals", SystemAddress = SYS, BodyID = 9,
        BodyName = "Test Body 1 9 d",
        Signals = {{ Type = bi_constants.SIGNAL_KEY_BIOLOGICAL, Count = 3 }},
    }, settings)

    local target = { columns = bi_constants.GRID_COLUMNS, rows = {} }
    bi_grid.rebuild(target, settings)

    local species_seen = {}
    for _, row in ipairs(target.rows) do
        species_seen[row["Species"]] = row["Variant"]
    end

    truthy(species_seen["Bacterium Vesicula"],
        "FSS-only body should enumerate Bacterium Vesicula")
    truthy(species_seen["Fonticulua Campestris"],
        "FSS-only body should enumerate Fonticulua Campestris")
    truthy(species_seen["Fumerola Nitris"],
        "FSS-only body should enumerate Fumerola Nitris")
    eq(species_seen["Bacterium Vesicula"], "Gold",
        "FSS-only body still gets material-based variant prediction")
end

print(string.format("\n%d tests, %d failures", total, failures))
os.exit(failures == 0 and 0 or 1)

