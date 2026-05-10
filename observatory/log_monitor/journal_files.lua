local paths = require("observatory.paths")

local journal_files = {}

local JOURNAL_NAME_PATTERN = "^Journal%..+%.%d+%.log$"
local FILENAME_TAIL_PATTERN = "[^/\\]+$"
local DATE_PART_PATTERN = "^Journal%.(.-)%.%d+%.log$"
local NEW_STYLE_DATE_PATTERN = "^%d%d%d%d%-%d%d%-%d%d"
local NEW_STYLE_PREFIX = "2_"
local LEGACY_STYLE_PREFIX = "1_20"

local function now_seconds()
    return (love and love.timer) and love.timer.getTime() or os.time()
end

local function sort_key_for(date_part)
    if date_part:match(NEW_STYLE_DATE_PATTERN) then
        return NEW_STYLE_PREFIX .. date_part
    end
    return LEGACY_STYLE_PREFIX .. date_part
end

local function decorate(files)
    local decorated = {}
    for _, f in ipairs(files) do
        local name = f:match(FILENAME_TAIL_PATTERN) or f
        local date_part = name:match(DATE_PART_PATTERN) or ""
        table.insert(decorated, { path = f, key = sort_key_for(date_part) })
    end
    table.sort(decorated, function(a, b) return a.key < b.key end)
    return decorated
end

local function decorated_to_paths(decorated)
    local out = {}
    for _, d in ipairs(decorated) do table.insert(out, d.path) end
    return out
end

function journal_files.create_cache()
    return { folder = nil, files = nil, expires_at = 0 }
end

function journal_files.invalidate(cache)
    cache.expires_at = 0
    cache.files = nil
end

function journal_files.list(cache, folder, ttl_seconds)
    if not folder then return {} end
    local now = now_seconds()
    if cache.folder == folder and cache.files and now < cache.expires_at then
        return cache.files
    end
    local raw = paths.list_files(folder, JOURNAL_NAME_PATTERN)
    local out = decorated_to_paths(decorate(raw))
    cache.folder = folder
    cache.files = out
    cache.expires_at = now + ttl_seconds
    return out
end

return journal_files
