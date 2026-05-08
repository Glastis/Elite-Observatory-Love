-- Journal line deserialisation.
-- Equivalent to Utils/JournalReader.cs in ObservatoryCore. Each line of an
-- Elite Dangerous journal is a JSON object containing at minimum "timestamp"
-- and "event" fields. We expose:
--   * get_event_type(line)       => string or "InvalidJson"
--   * deserialize(line)          => decoded table (with .Json = original line)
-- Type dispatch is left to the LogMonitor / plugins; we don't ship the full
-- C# type hierarchy, since plugins in this port consume plain tables.

local json = require("lib.json")

local journal_reader = {}

-- Light-weight extraction of the "event" field without a full JSON parse.
-- Falls back to json.decode if the regex extraction misses (which can happen
-- if the field appears inside a string value).
function journal_reader.get_event_type(line)
    if not line or line == "" then return "InvalidJson" end
    local quick = line:match('"event"%s*:%s*"([^"]+)"')
    if quick then return quick end
    local ok, obj = pcall(json.decode, line)
    if ok and type(obj) == "table" and type(obj.event) == "string" then
        return obj.event
    end
    return "InvalidJson"
end

-- Deserialises a journal line into a Lua table. The original raw line is
-- preserved as `Json` (matching the C# JournalBase.Json property), so plugins
-- can re-emit or hash it.
function journal_reader.deserialize(line)
    if not line or line == "" then
        return {
            event = "InvalidJson",
            timestamp = "",
            Json = line or "",
        }
    end

    -- Workaround for a 2017-era Elite Dangerous bug where some Scan events
    -- contained `"RotationPeriod":inf` which is not valid JSON.
    local cleaned = line
    if cleaned:find('"RotationPeriod":inf', 1, true) then
        cleaned = cleaned:gsub('"RotationPeriod":inf,?', "")
    end

    local ok, obj = pcall(json.decode, cleaned)
    if not ok or type(obj) ~= "table" then
        local timestamp = line:match('"timestamp"%s*:%s*"([^"]+)"') or ""
        local original_event = line:match('"event"%s*:%s*"([^"]+)"') or ""
        return {
            event = "InvalidJson",
            timestamp = timestamp,
            OriginalEvent = original_event,
            Json = line,
        }
    end

    obj.Json = line
    return obj
end

return journal_reader
