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

print(string.format("\n%d tests, %d failures", total, failures))
os.exit(failures == 0 and 0 or 1)
