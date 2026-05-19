local commodity_names = {}

local API_NAME_OVERRIDES = {}

function commodity_names.to_api_name(commodity_key)
    if type(commodity_key) ~= "string" then return nil end
    return API_NAME_OVERRIDES[commodity_key] or commodity_key
end

return commodity_names
