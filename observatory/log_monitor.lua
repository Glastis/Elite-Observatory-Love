local paths = require("observatory.paths")
local journal_reader = require("observatory.journal_reader")
local settings = require("observatory.settings")
local state_flags = require("observatory.log_monitor.state_flags")
local listeners = require("observatory.log_monitor.listeners")
local journal_files = require("observatory.log_monitor.journal_files")
local file_reader = require("observatory.log_monitor.file_reader")
local preread = require("observatory.log_monitor.preread")
local parse_pool = require("observatory.log_monitor.parse_pool")

local log_monitor = {}

log_monitor.STATE = state_flags.STATE

local ANCILLARY_EVENTS = {
    Cargo       = "Cargo.json",
    NavRoute    = "NavRoute.json",
    Market      = "Market.json",
    Outfitting  = "Outfitting.json",
    Shipyard    = "Shipyard.json",
    Backpack    = "Backpack.json",
    FCMaterials = "FCMaterials.json",
    ModuleInfo  = "ModulesInfo.json",
    ShipLocker  = "ShipLocker.json",
}

local INVALID_JSON_EVENT = "InvalidJson"
local UNKNOWN_EVENT = "Unknown"
local STATUS_FILE = "Status.json"
local BATCH_SPIN_SLEEP_S = 0.0005

local SETTING_POLL_REALTIME = "LogPollIntervalRealtimeS"
local SETTING_POLL_ALT = "LogPollIntervalAltS"
local SETTING_DIR_TTL = "LogDirCacheTtlS"
local SETTING_BATCH_BUDGET = "LogBatchLinesPerTick"
local SETTING_ALT_MODE = "AltMonitor"
local SETTING_JOURNAL_FOLDER = "JournalFolder"
local SETTING_START_READ_ALL = "StartReadAll"

local state = {
    current_state  = state_flags.STATE.Idle,
    journal_folder = nil,
    file_offsets   = {},
    file_sizes     = {},
    status_size    = nil,
    status_path    = nil,
    last_event     = "None",
    total_events   = 0,
    listeners      = listeners.create(),
    poll_timer     = 0,
    first_start    = true,
    dir_cache      = journal_files.create_cache(),
    batch_pool     = nil,
}

local function settings_or(default, key)
    local value = settings.get(key)
    if value == nil then return default end
    return value
end

function log_monitor.on_journal_entry(fn) listeners.subscribe(state.listeners, "journal_entry", fn) end
function log_monitor.on_status_update(fn) listeners.subscribe(state.listeners, "status_update", fn) end
function log_monitor.on_state_changed(fn) listeners.subscribe(state.listeners, "state_changed", fn) end

function log_monitor.clear_listeners()
    listeners.clear(state.listeners)
end

local function dispatch(channel, ...)
    listeners.dispatch(state.listeners, channel, ...)
end

local function set_state(new_state)
    local old = state.current_state
    state.current_state = new_state
    dispatch("state_changed", { previous = old, current = new_state })
end

function log_monitor.current_state() return state.current_state end
function log_monitor.is_monitoring() return state_flags.is_realtime(state.current_state) end
function log_monitor.is_batch_read() return state_flags.is_batch_read(state.current_state) end
function log_monitor.last_event() return state.last_event end
function log_monitor.total_events() return state.total_events end

local function dir_ttl()
    return settings_or(5.0, SETTING_DIR_TTL)
end

local function batch_budget()
    return settings_or(4000, SETTING_BATCH_BUDGET)
end

local function poll_interval()
    if settings.get(SETTING_ALT_MODE) then
        return settings_or(1.0, SETTING_POLL_ALT)
    end
    return settings_or(0.25, SETTING_POLL_REALTIME)
end

local function list_journal_files()
    return journal_files.list(state.dir_cache, state.journal_folder, dir_ttl())
end

local function resolve_folder()
    local override = settings.get(SETTING_JOURNAL_FOLDER)
    local folder, source = paths.find_journal_folder(override)
    if folder ~= override then
        settings.set(SETTING_JOURNAL_FOLDER, folder)
        settings.save()
    end
    state.journal_folder = folder
    state.status_path = paths.join(folder, STATUS_FILE)
    return folder, source
end

function log_monitor.journal_folder() return state.journal_folder end

local function reset_file_tracking()
    state.file_offsets = {}
    state.file_sizes = {}
    state.status_size = nil
    journal_files.invalidate(state.dir_cache)
end

settings.on_change(SETTING_JOURNAL_FOLDER, function()
    reset_file_tracking()
    resolve_folder()
end)

function log_monitor.change_watched_directory(path)
    settings.set(SETTING_JOURNAL_FOLDER, path or "")
    settings.save()
end

local function dispatch_ancillary_for(entry)
    if log_monitor.is_batch_read() then return end
    local fname = ANCILLARY_EVENTS[entry.event]
    if not fname or not state.journal_folder then return end
    local apath = paths.join(state.journal_folder, fname)
    local af = io.open(apath, "rb")
    if not af then return end
    local content = af:read("*a") or ""
    af:close()
    local parsed = journal_reader.deserialize(content)
    if parsed.event == INVALID_JSON_EVENT then return end
    parsed.event = entry.event .. "File"
    dispatch("journal_entry", parsed)
end

local function process_entry(entry)
    state.last_event = entry.event or UNKNOWN_EVENT
    state.total_events = state.total_events + 1
    dispatch("journal_entry", entry)
    dispatch_ancillary_for(entry)
end

local function process_line(line, file_label)
    local is_ok, entry = pcall(journal_reader.deserialize, line)
    if not is_ok then
        print(string.format("[log_monitor] failed to parse line in %s: %s",
            tostring(file_label), tostring(entry)))
        return
    end
    process_entry(entry)
end

local function process_lines(lines, file_label)
    for _, line in ipairs(lines) do process_line(line, file_label) end
end

local function run_preread()
    if settings.get(SETTING_START_READ_ALL) then return end
    set_state(state_flags.set_flag(state.current_state, state_flags.STATE.PreRead))
    local files = list_journal_files()
    if #files > 0 then
        process_lines(preread.collect(state, files), "Pre-read")
    end
    set_state(state_flags.clear_flag(state.current_state, state_flags.STATE.PreRead))
end

function log_monitor.init()
    resolve_folder()
end

function log_monitor.start()
    if state.first_start then
        state.first_start = false
        run_preread()
    end
    set_state(state_flags.STATE.Realtime)
    state.poll_timer = 0
end

function log_monitor.stop()
    set_state(state_flags.STATE.Idle)
end

local function finish_batch()
    state.batch_pool = nil
    set_state(state_flags.clear_flag(state.current_state, state_flags.STATE.Batch))
end

local function drain_batch_blocking()
    while true do
        local is_running, made_progress = parse_pool.step(
            state.batch_pool, batch_budget(), state, process_entry)
        if not is_running then break end
        if not made_progress and love and love.timer then
            love.timer.sleep(BATCH_SPIN_SLEEP_S)
        end
    end
    finish_batch()
end

function log_monitor.read_all(opts)
    opts = opts or {}
    state.first_start = false
    set_state(state_flags.set_flag(state.current_state, state_flags.STATE.Batch))
    state.batch_pool = parse_pool.start(list_journal_files())
    if opts.blocking then drain_batch_blocking() end
end

function log_monitor.batch_progress()
    return parse_pool.snapshot(state.batch_pool)
end

function log_monitor.shutdown()
    parse_pool.shutdown()
end

local function step_batch_if_active()
    if not state.batch_pool then return end
    local is_running = parse_pool.step(state.batch_pool, batch_budget(),
        state, process_entry)
    if not is_running then finish_batch() end
end

local function poll_latest_journal()
    local files = list_journal_files()
    if #files == 0 then return end
    local latest = files[#files]
    local prev_known_size = state.file_sizes[latest] or 0
    local current_size = paths.file_size(latest)
    if current_size and current_size < prev_known_size then
        journal_files.invalidate(state.dir_cache)
    end
    process_lines(file_reader.read_new_lines(state, latest), latest)
end

local function poll_status_file()
    if not state.status_path then return end
    local size = paths.file_size(state.status_path)
    if not size or size == state.status_size then return end
    state.status_size = size
    local lines = file_reader.read_all_lines(state.status_path)
    if #lines == 0 then return end
    local ok, status = pcall(journal_reader.deserialize, lines[1])
    if ok then dispatch("status_update", status) end
end

function log_monitor.update(dt)
    step_batch_if_active()
    if not log_monitor.is_monitoring() then return end
    state.poll_timer = state.poll_timer + dt
    if state.poll_timer < poll_interval() then return end
    state.poll_timer = 0
    poll_latest_journal()
    poll_status_file()
end

return log_monitor
