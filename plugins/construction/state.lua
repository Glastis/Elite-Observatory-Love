local state = {}

local sites = {}
local cargo = {}
local stations = {}
local hidden = {}
local on_change = function() end

function state.set_on_change(callback)
    on_change = callback or function() end
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
    sites[market_id] = site
    on_change()
end

function state.remove_site(market_id)
    if not market_id or not sites[market_id] then return end
    sites[market_id] = nil
    hidden[market_id] = nil
    on_change()
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
