local json        = require("lib.json")
local constants   = require("plugins.construction.route_constants")
local route_cache = require("plugins.construction.route_cache")

local route_api = {}

local HTTP_OK_MIN = 200
local HTTP_OK_MAX = 299

local PAD_SIZE_BY_LABEL = {
    L = 3, M = 2, S = 1,
    large = 3, medium = 2, small = 1,
}

local UNSAFE_URL_PATTERN = "[^%w%-_%.~]"

local function url_encode(text)
    return (tostring(text):gsub(UNSAFE_URL_PATTERN, function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

local function first_value(raw, keys)
    for _, key in ipairs(keys) do
        if raw[key] ~= nil then return raw[key] end
    end
    return nil
end

local function coords_from(raw)
    local x = tonumber(first_value(raw, { "systemX" }))
    local y = tonumber(first_value(raw, { "systemY" }))
    local z = tonumber(first_value(raw, { "systemZ" }))
    if x and y and z then return { x = x, y = y, z = z } end
    return nil
end

local function to_pad_size(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return PAD_SIZE_BY_LABEL[value] end
    return nil
end

local function is_orbital_type(station_type)
    if station_type and constants.SURFACE_STATION_TYPES[station_type] then
        return false
    end
    return true
end

local function is_fleet_carrier(raw)
    local flag = first_value(raw, { "fleetCarrier", "isFleetCarrier" })
    return flag == 1 or flag == true
end

local function normalize_export_entry(raw)
    if type(raw) ~= "table" or is_fleet_carrier(raw) then return nil end
    local station_name = first_value(raw, { "stationName" })
    local system_name = first_value(raw, { "systemName" })
    if not station_name or not system_name then return nil end
    local pad_size = to_pad_size(first_value(raw, { "maxLandingPadSize" }))
    if pad_size and pad_size < constants.LARGE_PAD_SIZE then return nil end
    local station_type = first_value(raw, { "stationType" })
    return {
        station_name           = station_name,
        system_name            = system_name,
        station_type           = station_type,
        is_orbital             = is_orbital_type(station_type),
        coords                 = coords_from(raw),
        distance_to_arrival_ls = tonumber(first_value(raw,
            { "distanceToArrival", "stationDistanceFromStar" })),
        price                  = tonumber(first_value(raw,
            { "buyPrice", "price", "sellPrice" })) or 0,
        stock                  = tonumber(first_value(raw,
            { "stock", "stockQuantity" })) or 0,
    }
end

local function normalize_list(decoded, normalize_entry)
    local result = {}
    if type(decoded) ~= "table" then return result end
    for _, raw in ipairs(decoded) do
        local entry = normalize_entry(raw)
        if entry then table.insert(result, entry) end
    end
    return result
end

local function decode_body(body)
    local ok, decoded = pcall(json.decode, body or "")
    if not ok then return nil end
    return decoded
end

local function handle_response(result, url, callback)
    if not result.is_ok then
        return callback(false, nil, result.error or "request failed")
    end
    if result.status < HTTP_OK_MIN or result.status > HTTP_OK_MAX then
        return callback(false, nil, "http " .. tostring(result.status))
    end
    local decoded = decode_body(result.body)
    if decoded == nil then
        return callback(false, nil, "invalid json")
    end
    route_cache.put(url, decoded)
    callback(true, decoded, nil)
end

local function request_json(core, url, callback)
    local cached = route_cache.get(url)
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
    local url = constants.API_BASE_URL
        .. string.format(constants.EXPORTS_PATH_FORMAT,
            url_encode(system_name), url_encode(api_commodity_name))
        .. string.format(constants.EXPORTS_QUERY_FORMAT, min_volume,
            constants.MAX_SOURCE_DISTANCE_LY)
    return request_json(core, url, function(is_ok, decoded, error_message)
        if not is_ok then return callback(false, nil, error_message) end
        callback(true, normalize_list(decoded, normalize_export_entry), nil)
    end)
end

return route_api
