local json = require("lib.json")

local route_cache = {}

local CACHE_FILE       = "construction_route_cache.json"
local CACHE_TTL_S      = 2 * 60 * 60
local FLUSH_DEBOUNCE_S = 2
local TIME_KEY         = "stored_at"
local DATA_KEY         = "payload"

local entries = {}
local is_dirty = false
local seconds_since_change = 0

local function has_filesystem()
    return love ~= nil and love.filesystem ~= nil
end

local function age_of(entry)
    if type(entry) ~= "table" or type(entry[TIME_KEY]) ~= "number" then
        return math.huge
    end
    return os.time() - entry[TIME_KEY]
end

local function is_fresh(entry)
    return age_of(entry) < CACHE_TTL_S
end

local function drop_expired()
    local has_removed = false
    for url, entry in pairs(entries) do
        if not is_fresh(entry) then
            entries[url] = nil
            has_removed = true
        end
    end
    return has_removed
end

local function read_file()
    if not has_filesystem() then return nil end
    if not love.filesystem.getInfo(CACHE_FILE) then return nil end
    local raw = love.filesystem.read(CACHE_FILE)
    if not raw then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == "table" then return decoded end
    return nil
end

function route_cache.init()
    entries = read_file() or {}
    is_dirty = drop_expired()
    seconds_since_change = 0
end

function route_cache.reset()
    entries = {}
    is_dirty = false
    seconds_since_change = 0
end

function route_cache.get(url)
    local entry = entries[url]
    if not entry then return nil end
    if not is_fresh(entry) then
        entries[url] = nil
        return nil
    end
    return entry[DATA_KEY]
end

function route_cache.put(url, payload, timestamp)
    if url == nil or payload == nil then return end
    entries[url] = {
        [TIME_KEY] = timestamp or os.time(),
        [DATA_KEY] = payload,
    }
    is_dirty = true
    seconds_since_change = 0
end

function route_cache.flush()
    if not is_dirty or not has_filesystem() then return end
    local ok, encoded = pcall(json.encode, entries)
    if not ok then return end
    love.filesystem.write(CACHE_FILE, encoded)
    is_dirty = false
end

function route_cache.update(dt)
    if not is_dirty then return end
    seconds_since_change = seconds_since_change + (dt or 0)
    if seconds_since_change >= FLUSH_DEBOUNCE_S then
        route_cache.flush()
    end
end

return route_cache
