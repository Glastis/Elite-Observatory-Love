-- Log monitor: equivalent of Utils/LogMonitor.cs.
-- Polls the Elite Dangerous journal directory for new lines in `Journal.*.log`
-- files and for changes to `Status.json`. LÖVE doesn't ship a real
-- FileSystemWatcher, so we poll on a fixed interval inside love.update.

local paths = require("observatory.paths")
local journal_reader = require("observatory.journal_reader")
local settings = require("observatory.settings")

-- LuaJIT (which LÖVE 11 ships with) exposes the `bit` library. Falling back
-- to a small implementation keeps `lua main.lua --smoke` runnable on plain
-- Lua 5.1/5.2 too, where `bit` may be absent.
local bit_ok, bit = pcall(require, "bit")
if not bit_ok then
    bit = {
        bor  = function(a, b) return ((a or 0) + (b or 0)) - (((a or 0) % (b * 2 / b)) >= b and 0 or 0) end,
    }
    -- Minimal portable replacements; only the ops we use.
    bit.bor  = function(a, b)
        local r, p = 0, 1
        while a > 0 or b > 0 do
            local ab, bb = a % 2, b % 2
            if ab + bb > 0 then r = r + p end
            a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
        end
        return r
    end
    bit.band = function(a, b)
        local r, p = 0, 1
        while a > 0 and b > 0 do
            if (a % 2) == 1 and (b % 2) == 1 then r = r + p end
            a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
        end
        return r
    end
    bit.bnot = function(a) return (-1) - a end
end

local log_monitor = {}

-- LogMonitorState flags (matches Framework/EventArgs.cs LogMonitorState).
log_monitor.STATE = {
    Idle           = 0,
    Realtime       = 1,
    Batch          = 2,
    PreRead        = 4,
    BatchCancelled = 8,
}

-- Events with ancillary JSON files alongside the journal (Cargo.json, etc.).
local ANCILLARY_EVENTS = {
    Cargo = "Cargo.json",
    NavRoute = "NavRoute.json",
    Market = "Market.json",
    Outfitting = "Outfitting.json",
    Shipyard = "Shipyard.json",
    Backpack = "Backpack.json",
    FCMaterials = "FCMaterials.json",
    ModuleInfo = "ModulesInfo.json", -- FDev typo'd: Modules vs Module
    ShipLocker = "ShipLocker.json",
}

local POLL_INTERVAL = 0.25 -- seconds, like the original 250ms JournalPoke.
local POLL_INTERVAL_ALT = 1.0

-- Module state -------------------------------------------------------------
local state = {
    current_state = log_monitor.STATE.Idle,
    journal_folder = nil,
    file_offsets = {},   -- absolute path => byte offset already read
    file_sizes = {},     -- absolute path => last observed size
    status_size = nil,
    status_path = nil,
    last_event = "None",
    total_events = 0,
    listeners = {
        journal_entry = {},
        status_update = {},
        state_changed = {},
    },
    poll_timer = 0,
    first_start = true,
}

-- Subscribe ----------------------------------------------------------------
local function subscribe(channel, fn)
    table.insert(state.listeners[channel], fn)
end

function log_monitor.on_journal_entry(fn) subscribe("journal_entry", fn) end
function log_monitor.on_status_update(fn) subscribe("status_update", fn) end
function log_monitor.on_state_changed(fn) subscribe("state_changed", fn) end

-- Drop every previously-registered listener. Called before re-wiring during a
-- plugin hot-reload to avoid duplicating dispatches.
function log_monitor.clear_listeners()
    for channel in pairs(state.listeners) do
        state.listeners[channel] = {}
    end
end

local function dispatch(channel, ...)
    for _, fn in ipairs(state.listeners[channel]) do
        local ok, err = pcall(fn, ...)
        if not ok then
            print("[log_monitor] listener error:", err)
        end
    end
end

-- State management ---------------------------------------------------------
local function set_state(new_state)
    local old = state.current_state
    state.current_state = new_state
    dispatch("state_changed", { previous = old, current = new_state })
end

local function has_flag(s, flag)
    return bit.band(s, flag) ~= 0
end

local function set_flag(s, flag) return bit.bor(s, flag) end
local function clear_flag(s, flag) return bit.band(s, bit.bnot(flag)) end

function log_monitor.current_state() return state.current_state end
function log_monitor.is_monitoring()
    return has_flag(state.current_state, log_monitor.STATE.Realtime)
end

local function is_batch_read(s)
    s = s or state.current_state
    return has_flag(s, log_monitor.STATE.Batch)
        or has_flag(s, log_monitor.STATE.PreRead)
end
log_monitor.is_batch_read = is_batch_read

function log_monitor.last_event() return state.last_event end
function log_monitor.total_events() return state.total_events end

-- File helpers -------------------------------------------------------------

-- Cache for list_journal_files: spawning `dir`/`ls` on every 250 ms tick is
-- expensive (cold popen on Windows is ~50–100 ms). We refresh at most every
-- DIR_CACHE_TTL seconds, or immediately when forced via invalidate_dir_cache().
local DIR_CACHE_TTL = 5.0
local dir_cache = { folder = nil, files = nil, expires_at = 0 }

local function invalidate_dir_cache()
    dir_cache.expires_at = 0
    dir_cache.files = nil
end

-- Folder management --------------------------------------------------------
local function resolve_folder()
    local override = settings.get("JournalFolder")
    local folder, source = paths.find_journal_folder(override)
    if folder ~= override then
        settings.set("JournalFolder", folder)
        settings.save()
    end
    state.journal_folder = folder
    state.status_path = paths.join(folder, "Status.json")
    return folder, source
end

function log_monitor.journal_folder() return state.journal_folder end

function log_monitor.change_watched_directory(path)
    settings.set("JournalFolder", path or "")
    settings.save()
    state.file_offsets = {}
    state.file_sizes = {}
    state.status_size = nil
    invalidate_dir_cache()
    resolve_folder()
end

-- Returns sorted list of journal files, oldest first, based on filename.
-- Matches the original ordering logic which extracts a date part either
-- as `yyyy-MM-ddTHHmmss` or legacy `yyMMddHHmmss` from `Journal.<date>.<n>.log`.
local function list_journal_files()
    if not state.journal_folder then return {} end
    local now = (love and love.timer) and love.timer.getTime() or os.time()
    if dir_cache.folder == state.journal_folder
        and dir_cache.files
        and now < dir_cache.expires_at then
        return dir_cache.files
    end
    local files = paths.list_files(state.journal_folder, "^Journal%..+%.%d+%.log$")
    -- Decorate with a sortable timestamp string from the filename so we don't
    -- need to call stat for every file on every poll.
    local decorated = {}
    for _, f in ipairs(files) do
        local name = f:match("[^/\\]+$") or f
        local date_part = name:match("^Journal%.(.-)%.%d+%.log$") or ""
        local sort_key
        if date_part:match("^%d%d%d%d%-%d%d%-%d%d") then
            -- New style: 2024-05-08T142233 sorts naturally
            sort_key = "2_" .. date_part
        else
            -- Legacy yyMMddHHmmss => prefix with century guess (20YY)
            sort_key = "1_20" .. date_part
        end
        table.insert(decorated, { path = f, key = sort_key })
    end
    table.sort(decorated, function(a, b) return a.key < b.key end)
    local out = {}
    for _, d in ipairs(decorated) do table.insert(out, d.path) end
    dir_cache.folder = state.journal_folder
    dir_cache.files = out
    dir_cache.expires_at = now + DIR_CACHE_TTL
    return out
end

-- Reads only the new bytes in a file since the last poll, splits them into
-- complete lines and returns them. Partial trailing lines are kept for the
-- next poll.
local function read_new_lines(path)
    local size = paths.file_size(path)
    if size == nil then return {}, false end
    local prev_offset = state.file_offsets[path] or 0
    if size < prev_offset then
        -- File was rotated/truncated, re-read from start.
        prev_offset = 0
    end
    if size == prev_offset then
        state.file_sizes[path] = size
        return {}, false
    end
    local f = io.open(path, "rb")
    if not f then return {}, false end
    if prev_offset > 0 then f:seek("set", prev_offset) end
    local chunk = f:read("*a") or ""
    f:close()
    -- Split into lines, keeping any incomplete trailing line buffered by
    -- adjusting the file offset accordingly.
    local lines = {}
    local consumed_to = prev_offset
    for line, lend in chunk:gmatch("([^\n]*)\n()") do
        -- Strip optional carriage return for files written on Windows.
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        if line ~= "" then table.insert(lines, line) end
        consumed_to = prev_offset + (lend - 1)
    end
    state.file_offsets[path] = consumed_to
    state.file_sizes[path] = size
    return lines, true
end

local function read_all_lines(path)
    local f = io.open(path, "rb")
    if not f then return {} end
    local content = f:read("*a") or ""
    f:close()
    local lines = {}
    for line in content:gmatch("[^\n]+") do
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        table.insert(lines, line)
    end
    return lines
end

-- Process a single journal line: deserialise + dispatch + ancillary file pull
local function process_line(line, file_label)
    local ok, entry = pcall(journal_reader.deserialize, line)
    if not ok then
        print(string.format("[log_monitor] failed to parse line in %s: %s",
            tostring(file_label), tostring(entry)))
        return
    end
    state.last_event = entry.event or "Unknown"
    state.total_events = state.total_events + 1
    dispatch("journal_entry", entry)

    -- Ancillary files only valid in realtime, not batch/preread.
    if not is_batch_read() then
        local fname = ANCILLARY_EVENTS[entry.event]
        if fname and state.journal_folder then
            local apath = paths.join(state.journal_folder, fname)
            local af = io.open(apath, "rb")
            if af then
                local content = af:read("*a") or ""
                af:close()
                -- journal_reader.deserialize never throws (it returns an
                -- {event="InvalidJson"} table on parse failure), so the prior
                -- pcall was misleading: a failed parse still synthesised a
                -- "<event>File" dispatch with garbage. Drop it explicitly.
                local parsed = journal_reader.deserialize(content)
                if parsed.event ~= "InvalidJson" then
                    parsed.event = entry.event .. "File"
                    dispatch("journal_entry", parsed)
                end
            end
        end
    end
end

local function process_lines(lines, file_label)
    for _, line in ipairs(lines) do
        process_line(line, file_label)
    end
end

-- Pre-read: read recent lines so plugins know the player's current location,
-- last loadout, etc. before realtime kicks in. Mirrors PrereadJournals().
local function preread()
    if settings.get("StartReadAll") then return end
    set_state(set_flag(state.current_state, log_monitor.STATE.PreRead))
    local files = list_journal_files()
    if #files == 0 then
        set_state(clear_flag(state.current_state, log_monitor.STATE.PreRead))
        return
    end
    -- Take at most the last two files.
    local start_idx = math.max(#files - 1, 1)
    local last_system_lines = {}
    local last_file_lines = {}
    local file_header_lines = {}
    local saw_fsd_jump = false

    for i = start_idx, #files do
        local fpath = files[i]
        local lines = read_all_lines(fpath)
        for _, line in ipairs(lines) do
            local ev = journal_reader.get_event_type(line)
            if ev == "FSDJump"
                or (ev == "CarrierJump"
                    and (line:find('"Docked":true', 1, true)
                      or line:find('"OnFoot":true', 1, true))) then
                last_system_lines = {}
                saw_fsd_jump = true
            elseif ev == "Fileheader" then
                last_file_lines = {}
                file_header_lines = { line }
            elseif ev == "LoadGame" or ev == "Statistics"
                or ev == "CarrierLocation" or ev == "Loadout" then
                table.insert(file_header_lines, line)
            end
            table.insert(last_system_lines, line)
            table.insert(last_file_lines, line)
        end
        -- Track these as already-consumed for future polling.
        local size = paths.file_size(fpath) or 0
        state.file_offsets[fpath] = size
        state.file_sizes[fpath] = size
    end

    local lines_to_read = last_file_lines
    if saw_fsd_jump then
        -- Prepend header lines for context.
        local merged = {}
        for _, l in ipairs(file_header_lines) do table.insert(merged, l) end
        for _, l in ipairs(last_system_lines) do table.insert(merged, l) end
        lines_to_read = merged
    end

    process_lines(lines_to_read, "Pre-read")
    set_state(clear_flag(state.current_state, log_monitor.STATE.PreRead))
end

-- Public control -----------------------------------------------------------
function log_monitor.init()
    resolve_folder()
end

function log_monitor.start()
    if state.first_start then
        state.first_start = false
        preread()
    end
    set_state(log_monitor.STATE.Realtime)
    state.poll_timer = 0
end

function log_monitor.stop()
    set_state(log_monitor.STATE.Idle)
end

-- Read All (batch). Two execution modes:
--   * Async (default): registers a job consumed in chunks by update(dt) so the
--     UI keeps drawing at 60 FPS even on hundreds of journals. Progress is
--     surfaced via log_monitor.batch_progress().
--   * Blocking: pass {blocking = true} to drain everything synchronously. The
--     smoke-test harness uses this so the run is deterministic.
local LINES_PER_TICK = 4000

state.batch_job = nil

local function start_batch_job(files)
    state.batch_job = {
        files = files,
        file_index = 1,
        lines = nil,
        line_index = 1,
        total_files = #files,
        processed_lines = 0,
    }
end

local function batch_step(budget)
    local job = state.batch_job
    if not job then return false end
    local remaining = budget
    while remaining > 0 do
        if not job.lines then
            local fpath = job.files[job.file_index]
            if not fpath then
                state.batch_job = nil
                return false
            end
            job.lines = read_all_lines(fpath)
            job.line_index = 1
        end
        local fpath = job.files[job.file_index]
        local count = #job.lines
        while remaining > 0 and job.line_index <= count do
            process_line(job.lines[job.line_index], fpath)
            job.line_index = job.line_index + 1
            job.processed_lines = job.processed_lines + 1
            remaining = remaining - 1
        end
        if job.line_index > count then
            local size = paths.file_size(fpath) or 0
            state.file_offsets[fpath] = size
            state.file_sizes[fpath] = size
            job.file_index = job.file_index + 1
            job.lines = nil
        end
    end
    return state.batch_job ~= nil
end

function log_monitor.read_all(opts)
    opts = opts or {}
    state.first_start = false
    set_state(set_flag(state.current_state, log_monitor.STATE.Batch))
    local files = list_journal_files()
    start_batch_job(files)
    if opts.blocking then
        while batch_step(LINES_PER_TICK) do end
        set_state(clear_flag(state.current_state, log_monitor.STATE.Batch))
    end
end

-- Returns nil when no batch is in flight, otherwise a snapshot used by the UI
-- to render a progress overlay. `done` is incremented per fully-consumed file.
function log_monitor.batch_progress()
    local job = state.batch_job
    if not job then return nil end
    return {
        done = job.file_index - 1,
        total = job.total_files,
        processed_lines = job.processed_lines,
    }
end

-- Polled watcher tick: call from love.update with dt.
function log_monitor.update(dt)
    -- Drain a chunk of the async Read All before doing anything else, so big
    -- batches don't block on Realtime polling.
    if state.batch_job then
        local still_running = batch_step(LINES_PER_TICK)
        if not still_running then
            set_state(clear_flag(state.current_state, log_monitor.STATE.Batch))
        end
    end
    if not log_monitor.is_monitoring() then return end
    state.poll_timer = state.poll_timer + dt
    local interval = settings.get("AltMonitor") and POLL_INTERVAL_ALT or POLL_INTERVAL
    if state.poll_timer < interval then return end
    state.poll_timer = 0

    -- Most recent journal file: poll for new lines.
    local files = list_journal_files()
    if #files > 0 then
        local latest = files[#files]
        local prev_known_size = state.file_sizes[latest] or 0
        local current_size = paths.file_size(latest)
        -- If the file we tracked shrunk (rotation) or a brand-new journal
        -- appeared, invalidate the cached listing so we pick it up next tick
        -- without waiting for DIR_CACHE_TTL.
        if current_size and current_size < prev_known_size then
            invalidate_dir_cache()
        end
        local lines = read_new_lines(latest)
        process_lines(lines, latest)
    end

    -- Status.json: re-read on size change.
    if state.status_path then
        local size = paths.file_size(state.status_path)
        if size and size ~= state.status_size then
            state.status_size = size
            local lines = read_all_lines(state.status_path)
            if #lines > 0 then
                local ok, status = pcall(journal_reader.deserialize, lines[1])
                if ok then
                    dispatch("status_update", status)
                end
            end
        end
    end
end

return log_monitor
