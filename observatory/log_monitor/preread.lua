local journal_reader = require("observatory.journal_reader")
local file_reader = require("observatory.log_monitor.file_reader")

local preread = {}

local CARRIER_DOCKED_MARKER = '"Docked":true'
local CARRIER_FOOT_MARKER = '"OnFoot":true'

local function is_system_boundary(event, line)
    if event == "FSDJump" then return true end
    if event == "CarrierJump" then
        return line:find(CARRIER_DOCKED_MARKER, 1, true)
            or line:find(CARRIER_FOOT_MARKER, 1, true)
    end
    return false
end

local HEADER_EVENTS = {
    LoadGame         = true,
    Statistics       = true,
    CarrierLocation  = true,
    Loadout          = true,
}

local function blank_snapshot()
    return {
        last_system_lines = {},
        last_file_lines   = {},
        file_header_lines = {},
        saw_fsd_jump      = false,
    }
end

local LINE_HANDLERS = {
    file_boundary = function(snapshot, line)
        snapshot.last_file_lines = {}
        snapshot.file_header_lines = { line }
    end,
    system_boundary = function(snapshot, _)
        snapshot.last_system_lines = {}
        snapshot.saw_fsd_jump = true
    end,
    header_payload = function(snapshot, line)
        table.insert(snapshot.file_header_lines, line)
    end,
}

local function classify_line(event, line)
    if is_system_boundary(event, line) then return "system_boundary" end
    if event == "Fileheader" then return "file_boundary" end
    if HEADER_EVENTS[event] then return "header_payload" end
    return nil
end

local function ingest_line(snapshot, line)
    local event = journal_reader.get_event_type(line)
    local kind = classify_line(event, line)
    local handler = kind and LINE_HANDLERS[kind] or nil
    if handler then handler(snapshot, line) end
    table.insert(snapshot.last_system_lines, line)
    table.insert(snapshot.last_file_lines, line)
end

local function ingest_file(snapshot, file_lines)
    for _, line in ipairs(file_lines) do
        ingest_line(snapshot, line)
    end
end

local function merge_lines(snapshot)
    if not snapshot.saw_fsd_jump then return snapshot.last_file_lines end
    local merged = {}
    for _, l in ipairs(snapshot.file_header_lines) do table.insert(merged, l) end
    for _, l in ipairs(snapshot.last_system_lines) do table.insert(merged, l) end
    return merged
end

function preread.collect(state, files)
    local snapshot = blank_snapshot()
    local start_idx = math.max(#files - 1, 1)
    for i = start_idx, #files do
        local fpath = files[i]
        ingest_file(snapshot, file_reader.read_all_lines(fpath))
        file_reader.mark_consumed(state, fpath)
    end
    return merge_lines(snapshot)
end

return preread
