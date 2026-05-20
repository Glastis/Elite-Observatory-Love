local json        = require("lib.json")
local constants   = require("plugins.construction.route_constants")
local route_cache = require("plugins.construction.route_cache")

local route_api = {}

local HTTP_OK_MIN = 200
local HTTP_OK_MAX = 299
local HTTP_ERROR_PREFIX = "http "
local DEFAULT_ERROR = "request failed"
local INVALID_JSON_ERROR = "invalid json"

local PAD_SIZE_BY_LABEL = {
    L = 3, M = 2, S = 1,
    large = 3, medium = 2, small = 1,
}

local UNSAFE_URL_PATTERN = "[^%w%-_%.~]"
local URL_BYTE_FORMAT = "%%%02X"

local STATION_NAME_KEYS = { "stationName" }
local SYSTEM_NAME_KEYS  = { "systemName" }
local SYSTEM_X_KEYS     = { "systemX" }
local SYSTEM_Y_KEYS     = { "systemY" }
local SYSTEM_Z_KEYS     = { "systemZ" }
local PAD_SIZE_KEYS     = { "maxLandingPadSize" }
local STATION_TYPE_KEYS = { "stationType" }
local FLEET_CARRIER_KEYS = { "fleetCarrier", "isFleetCarrier" }
local DISTANCE_KEYS     = { "distanceToArrival", "stationDistanceFromStar" }
local PRICE_KEYS        = { "buyPrice", "price", "sellPrice" }
local STOCK_KEYS        = { "stock", "stockQuantity" }

local function url_encode(text)
    return (tostring(text):gsub(UNSAFE_URL_PATTERN, function(character)
        return string.format(URL_BYTE_FORMAT, string.byte(character))
    end))
end

local function first_value(raw, keys)
    for _, key in ipairs(keys) do
        if raw[key] ~= nil then
            return raw[key]
        end
    end
    return nil
end

local function coords_from(raw)
    local x
    local y
    local z

    x = tonumber(first_value(raw, SYSTEM_X_KEYS))
    y = tonumber(first_value(raw, SYSTEM_Y_KEYS))
    z = tonumber(first_value(raw, SYSTEM_Z_KEYS))
    if x and y and z then
        return { x = x, y = y, z = z }
    end
    return nil
end

local PAD_SIZE_RESOLVERS = {
    number = function(value) return value end,
    string = function(value) return PAD_SIZE_BY_LABEL[value] end,
}

local function to_pad_size(value)
    local resolver

    resolver = PAD_SIZE_RESOLVERS[type(value)]
    if not resolver then
        return nil
    end
    return resolver(value)
end

local function is_orbital_type(station_type)
    if station_type and constants.SURFACE_STATION_TYPES[station_type] then
        return false
    end
    return true
end

local function is_fleet_carrier(raw)
    local flag

    flag = first_value(raw, FLEET_CARRIER_KEYS)
    return flag == 1 or flag == true
end

local function normalize_export_entry(raw)
    local station_name
    local system_name
    local pad_size
    local station_type

    if type(raw) ~= "table" or is_fleet_carrier(raw) then
        return nil
    end
    station_name = first_value(raw, STATION_NAME_KEYS)
    system_name = first_value(raw, SYSTEM_NAME_KEYS)
    if not station_name or not system_name then
        return nil
    end
    pad_size = to_pad_size(first_value(raw, PAD_SIZE_KEYS))
    if pad_size and pad_size < constants.LARGE_PAD_SIZE then
        return nil
    end
    station_type = first_value(raw, STATION_TYPE_KEYS)
    return {
        station_name           = station_name,
        system_name            = system_name,
        station_type           = station_type,
        is_orbital             = is_orbital_type(station_type),
        coords                 = coords_from(raw),
        distance_to_arrival_ls = tonumber(first_value(raw, DISTANCE_KEYS)),
        price                  = tonumber(first_value(raw, PRICE_KEYS)) or 0,
        stock                  = tonumber(first_value(raw, STOCK_KEYS)) or 0,
    }
end

local function normalize_list(decoded, normalize_entry)
    local result
    local entry

    result = {}
    if type(decoded) ~= "table" then
        return result
    end
    for _, raw in ipairs(decoded) do
        entry = normalize_entry(raw)
        if entry then
            table.insert(result, entry)
        end
    end
    return result
end

local function decode_body(body)
    local ok
    local decoded

    ok, decoded = pcall(json.decode, body or "")
    if not ok then
        return nil
    end
    return decoded
end

local function handle_response(result, url, callback)
    local decoded

    if not result.is_ok then
        return callback(false, nil, result.error or DEFAULT_ERROR)
    end
    if result.status < HTTP_OK_MIN or result.status > HTTP_OK_MAX then
        return callback(false, nil, HTTP_ERROR_PREFIX .. tostring(result.status))
    end
    decoded = decode_body(result.body)
    if decoded == nil then
        return callback(false, nil, INVALID_JSON_ERROR)
    end
    route_cache.put(url, decoded)
    callback(true, decoded, nil)
end

local function request_json(core, url, callback)
    local cached

    cached = route_cache.get(url)
    if cached ~= nil then
        callback(true, cached, nil)
        return nil
    end
    return core:http_get(url, function(result)
        handle_response(result, url, callback)
    end)
end

function route_api.fetch_exports(core, system_name, api_commodity_name,
        min_volume, callback)
    local url

    url = constants.API_BASE_URL
        .. string.format(constants.EXPORTS_PATH_FORMAT,
            url_encode(system_name), url_encode(api_commodity_name))
        .. string.format(constants.EXPORTS_QUERY_FORMAT, min_volume,
            constants.MAX_SOURCE_DISTANCE_LY)
    return request_json(core, url, function(is_ok, decoded, error_message)
        if not is_ok then
            return callback(false, nil, error_message)
        end
        callback(true, normalize_list(decoded, normalize_export_entry), nil)
    end)
end

return route_api
