local state = {}

local sites = {}
local cargo = {}
local stations = {}
local hidden = {}
local system_coords = {}
local current_system_record = nil
local on_change = function() end
local on_site_added = function() end
local on_site_removed = function() end
local on_site_updated = function() end
local on_refresh_route = function() end
local on_aggressive_refresh_route = function() end

function state.set_on_change(callback)
    on_change = callback or function() end
end

function state.set_on_site_added(callback)
    on_site_added = callback or function() end
end

function state.set_on_site_removed(callback)
    on_site_removed = callback or function() end
end

function state.set_on_site_updated(callback)
    on_site_updated = callback or function() end
end

function state.set_on_refresh_route(callback)
    on_refresh_route = callback or function() end
end

function state.request_route_refresh(market_id)
    if market_id then on_refresh_route(market_id) end
end

function state.set_on_aggressive_refresh_route(callback)
    on_aggressive_refresh_route = callback or function() end
end

function state.request_aggressive_route_refresh(market_id)
    if market_id then on_aggressive_refresh_route(market_id) end
end

function state.attach(sites_table, hidden_table)
    sites = sites_table or {}
    hidden = hidden_table or {}
end

function state.reset()
    sites = {}
    cargo = {}
    stations = {}
    hidden = {}
    system_coords = {}
    current_system_record = nil
end

function state.record_system_position(system_name, star_pos)
    if not system_name or type(star_pos) ~= "table" then return end
    local x, y, z = star_pos[1], star_pos[2], star_pos[3]
    if not (x and y and z) then return end
    system_coords[system_name] = { x = x, y = y, z = z }
    current_system_record = {
        name   = system_name,
        coords = system_coords[system_name],
    }
end

function state.coords_for_system(system_name)
    return system_coords[system_name]
end

function state.current_system()
    return current_system_record
end

function state.record_station(market_id, station_name, system_name)
    if not market_id then return end
    stations[market_id] = { station = station_name, system = system_name }
end

function state.station_for(market_id)
    return stations[market_id]
end

function state.get_site(market_id)
    return sites[market_id]
end

function state.upsert_site(market_id, site)
    if not market_id then return end
    local is_new_site = sites[market_id] == nil
    sites[market_id] = site
    on_change()
    if is_new_site then
        on_site_added(market_id)
        return
    end
    on_site_updated(market_id)
end

function state.remove_site(market_id)
    if not market_id or not sites[market_id] then return end
    sites[market_id] = nil
    hidden[market_id] = nil
    on_change()
    on_site_removed(market_id)
end

function state.set_hidden(market_id, is_hidden)
    if not market_id then return end
    hidden[market_id] = is_hidden and true or nil
    on_change()
end

function state.is_hidden(market_id)
    return hidden[market_id] == true
end

function state.set_cargo(cargo_by_key)
    cargo = cargo_by_key or {}
end

function state.cargo_count(commodity_key)
    return cargo[commodity_key] or 0
end

function state.site_count()
    local count = 0
    for _ in pairs(sites) do count = count + 1 end
    return count
end

function state.visible_count()
    local count = 0
    for market_id in pairs(sites) do
        if not hidden[market_id] then count = count + 1 end
    end
    return count
end

local function compare_sites(a, b)
    if a.is_hidden ~= b.is_hidden then
        return not a.is_hidden
    end
    return (a.site.label or "") < (b.site.label or "")
end

function state.sites_sorted()
    local list = {}
    for market_id, site in pairs(sites) do
        table.insert(list, {
            market_id = market_id,
            site      = site,
            is_hidden = hidden[market_id] == true,
        })
    end
    table.sort(list, compare_sites)
    return list
end

return state
